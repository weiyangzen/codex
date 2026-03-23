# launcher.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`launcher.rs` 是 Codex Linux 沙箱的**执行启动器**，负责选择并执行 bubblewrap 二进制文件。它是连接沙箱参数生成（`bwrap.rs`）和实际沙箱执行的桥梁。

### 1.2 核心职责
- **bwrap 源选择**：优先使用系统 bwrap，回退到内嵌 bwrap
- **文件描述符继承**：确保保留的文件描述符跨越 exec 边界
- **进程替换执行**：使用 `execv` 系列调用替换当前进程

### 1.3 执行流程位置

```
┌─────────────────────────────────────────────────────────────┐
│                    沙箱启动流程                              │
├─────────────────────────────────────────────────────────────┤
│  1. linux_run_main.rs                                       │
│     └── 解析参数，确定策略                                   │
├─────────────────────────────────────────────────────────────┤
│  2. bwrap.rs                                                │
│     └── 生成 bwrap 命令行参数                                │
├─────────────────────────────────────────────────────────────┤
│  3. launcher.rs  ★ 当前模块                                  │
│     ├── 选择 bwrap 源（系统/内嵌）                           │
│     ├── 设置文件描述符继承                                   │
│     └── exec 到 bwrap                                        │
├─────────────────────────────────────────────────────────────┤
│  4. bubblewrap                                              │
│     └── 设置命名空间，执行用户命令                           │
└─────────────────────────────────────────────────────────────┘
```

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 使用场景 |
|--------|------|----------|
| `exec_bwrap` | 主入口：执行 bubblewrap | 所有沙箱启动 |
| `preferred_bwrap_launcher` | 选择最优 bwrap 源 | 启动时自动检测 |
| `exec_system_bwrap` | 执行系统 bwrap | 系统已安装 bwrap |
| `exec_vendored_bwrap` | 执行内嵌 bwrap | 系统无 bwrap 或不可用时 |
| `make_files_inheritable` | 清除 FD_CLOEXEC 标志 | 需要保留的文件描述符 |

### 2.2 bwrap 源选择策略

```
检查 /usr/bin/bwrap 是否存在 ──否──► 使用内嵌 bwrap
         │
         是
         ▼
检查路径是否可解析为绝对路径 ──否──► panic（配置错误）
         │
         是
         ▼
    使用系统 bwrap
```

### 2.3 文件描述符继承机制

**问题背景**：
- `preserved_files` 包含需要保持打开的文件描述符（如用于 `--ro-bind-data` 的 `/dev/null`）
- 默认情况下，文件描述符设置 `FD_CLOEXEC` 标志，在 exec 时自动关闭
- 系统 bwrap 跨越 exec 边界，需要显式清除 CLOEXEC

**解决方案**：
```rust
fn make_files_inheritable(files: &[File]) {
    for file in files {
        clear_cloexec(file.as_raw_fd());
    }
}
```

## 3. 具体技术实现

### 3.1 核心数据结构

#### BubblewrapLauncher - bwrap 源枚举
```rust
#[derive(Debug, Clone, PartialEq, Eq)]
enum BubblewrapLauncher {
    System(AbsolutePathBuf),  // 系统 bwrap 路径
    Vendored,                 // 内嵌 bwrap
}
```

### 3.2 主入口函数

```rust
pub(crate) fn exec_bwrap(argv: Vec<String>, preserved_files: Vec<File>) -> !
```

**参数**：
- `argv`: 完整的 bwrap 命令行参数（包括 `argv[0]`）
- `preserved_files`: 需要保持打开的文件描述符列表

**返回值**：`!`（发散类型），因为成功时不会返回

**执行流程**：
1. 选择 bwrap 启动器
2. 根据选择分发到具体实现

### 3.3 bwrap 源选择

```rust
const SYSTEM_BWRAP_PATH: &str = "/usr/bin/bwrap";

fn preferred_bwrap_launcher() -> BubblewrapLauncher {
    if !Path::new(SYSTEM_BWRAP_PATH).is_file() {
        return BubblewrapLauncher::Vendored;
    }

    let system_bwrap_path = match AbsolutePathBuf::from_absolute_path(SYSTEM_BWRAP_PATH) {
        Ok(path) => path,
        Err(err) => panic!("failed to normalize system bubblewrap path {SYSTEM_BWRAP_PATH}: {err}"),
    };
    BubblewrapLauncher::System(system_bwrap_path)
}
```

**选择逻辑**：
1. 检查 `/usr/bin/bwrap` 是否为常规文件
2. 解析为绝对路径（规范化符号链接）
3. 如果任何步骤失败，回退到内嵌 bwrap

### 3.4 系统 bwrap 执行

```rust
fn exec_system_bwrap(
    program: &AbsolutePathBuf,
    argv: Vec<String>,
    preserved_files: Vec<File>,
) -> !
```

**执行步骤**：
1. **设置文件描述符继承**：
   ```rust
   make_files_inheritable(&preserved_files);
   ```

2. **准备 exec 参数**：
   ```rust
   let program = CString::new(program.as_path().as_os_str().as_bytes())
       .unwrap_or_else(|err| panic!("invalid system bubblewrap path: {err}"));
   let cstrings = argv_to_cstrings(&argv);
   let mut argv_ptrs: Vec<*const c_char> = cstrings.iter().map(|arg| arg.as_ptr()).collect();
   argv_ptrs.push(std::ptr::null());
   ```

3. **执行系统调用**：
   ```rust
   unsafe {
       libc::execv(program.as_ptr(), argv_ptrs.as_ptr());
   }
   ```

4. **错误处理**：
   ```rust
   let err = std::io::Error::last_os_error();
   panic!("failed to exec system bubblewrap {program_path}: {err}");
   ```

### 3.5 参数转换

```rust
fn argv_to_cstrings(argv: &[String]) -> Vec<CString>
```

将 Rust `String` 向量转换为 C 字符串向量：
- 使用 `CString::new` 转换
- 处理内部 null 字节的错误情况（panic）

### 3.6 文件描述符继承实现

```rust
fn clear_cloexec(fd: libc::c_int) {
    // 获取当前 flags
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
    if flags < 0 {
        let err = std::io::Error::last_os_error();
        panic!("failed to read fd flags for preserved bubblewrap file descriptor {fd}: {err}");
    }
    
    // 清除 FD_CLOEXEC
    let cleared_flags = flags & !libc::FD_CLOEXEC;
    if cleared_flags == flags {
        return;  // 已经是可继承的
    }
    
    // 设置新 flags
    let result = unsafe { libc::fcntl(fd, libc::F_SETFD, cleared_flags) };
    if result < 0 {
        let err = std::io::Error::last_os_error();
        panic!("failed to clear CLOEXEC for preserved bubblewrap file descriptor {fd}: {err}");
    }
}
```

### 3.7 内嵌 bwrap 执行

内嵌 bwrap 由 `vendored_bwrap.rs` 提供：

```rust
// launcher.rs
use crate::vendored_bwrap::exec_vendored_bwrap;

// 在 exec_bwrap 中
BubblewrapLauncher::Vendored => exec_vendored_bwrap(argv, preserved_files),
```

内嵌 bwrap 的特点：
- 在构建时从 C 源码编译
- 通过 FFI 调用 `bwrap_main` 函数
- 不跨越 exec 边界，因此不需要 `make_files_inheritable`

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
linux_run_main::run_main
  └── run_bwrap_with_proc_fallback
      └── exec_bwrap (launcher.rs:19)
          ├── preferred_bwrap_launcher (launcher.rs:26)
          ├── exec_system_bwrap (launcher.rs:38) [如果系统 bwrap 可用]
          │   ├── make_files_inheritable (launcher.rs:73)
          │   │   └── clear_cloexec (launcher.rs:79)
          │   ├── argv_to_cstrings (launcher.rs:62)
          │   └── libc::execv
          └── exec_vendored_bwrap (vendored_bwrap.rs:46) [如果系统 bwrap 不可用]
```

### 4.2 调用方

| 调用方 | 文件 | 位置 | 用途 |
|--------|------|------|------|
| `run_bwrap_with_proc_fallback` | `linux_run_main.rs` | 行 436 | 启动沙箱 |
| `run_bwrap_in_child_capture_stderr` | `linux_run_main.rs` | 行 570 | 预检 proc 挂载 |

### 4.3 测试覆盖

单元测试位于模块底部（行 99-134）：

| 测试函数 | 测试目的 |
|----------|----------|
| `preserved_files_are_made_inheritable_for_system_exec` | 验证 FD_CLOEXEC 清除 |

**测试实现细节**：
```rust
#[test]
fn preserved_files_are_made_inheritable_for_system_exec() {
    let file = NamedTempFile::new().expect("temp file");
    set_cloexec(file.as_file().as_raw_fd());  // 先设置 CLOEXEC
    
    make_files_inheritable(std::slice::from_ref(file.as_file()));
    
    assert_eq!(fd_flags(file.as_file().as_raw_fd()) & libc::FD_CLOEXEC, 0);
}
```

## 5. 依赖与外部交互

### 5.1 标准库依赖

| 模块 | 用途 |
|------|------|
| `std::ffi::CString` | C 字符串转换 |
| `std::fs::File` | 文件描述符操作 |
| `std::os::fd::AsRawFd` | 获取原始文件描述符 |
| `std::os::raw::c_char` | C 字符类型 |
| `std::os::unix::ffi::OsStrExt` | Unix 特定字符串转换 |

### 5.2 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `libc` | `execv`, `fcntl`, `FD_CLOEXEC` 等系统调用 |

### 5.3 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::vendored_bwrap::exec_vendored_bwrap` | 内嵌 bwrap 执行 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |

### 5.4 系统依赖

| 路径 | 用途 | 可选性 |
|------|------|--------|
| `/usr/bin/bwrap` | 系统 bubblewrap | 可选（有回退） |

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 硬编码路径风险
- **风险**：`/usr/bin/bwrap` 是硬编码路径
- **影响**：某些发行版（如 NixOS）可能将 bwrap 安装在其他位置
- **缓解**：内嵌 bwrap 作为回退
- **建议**：考虑添加环境变量覆盖路径

#### 6.1.2 exec 失败后的 panic
- **风险**：`exec_system_bwrap` 在 exec 失败后 panic
- **影响**：无法优雅地向上层返回错误
- **缓解**：这是设计选择，exec 失败通常是致命错误

#### 6.1.3 文件描述符泄漏风险
- **风险**：`clear_cloexec` 失败时 panic，但之前的 fd 可能已被修改
- **概率**：低（fcntl 很少失败）
- **缓解**：panic 会终止进程，不会继续执行

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 系统 bwrap 不存在 | 回退到内嵌 bwrap |
| 系统 bwrap 路径包含 null 字节 | panic（无效路径） |
| argv 包含 null 字节 | panic（无效参数） |
| fcntl 失败 | panic（系统错误） |
| 无 preserved_files | 正常工作（空操作） |

### 6.3 改进建议

#### 6.3.1 可配置的系统 bwrap 路径
- **建议**：添加 `CODEX_SYSTEM_BWRAP_PATH` 环境变量
- **实现**：
```rust
const SYSTEM_BWRAP_PATH: &str = option_env!("CODEX_SYSTEM_BWRAP_PATH")
    .unwrap_or("/usr/bin/bwrap");
```
- **价值**：支持非标准安装路径（如 NixOS、自定义前缀）

#### 6.3.2 多路径搜索
- **建议**：搜索多个常见 bwrap 路径
- **实现**：
```rust
const SYSTEM_BWRAP_PATHS: &[&str] = &[
    "/usr/bin/bwrap",
    "/usr/local/bin/bwrap",
    "/opt/bin/bwrap",
];
```

#### 6.3.3 错误处理改进
- **建议**：将 panic 转换为 `Result`，由调用方决定如何处理
- **挑战**：函数签名需要更改，影响调用链
- **权衡**：exec 失败通常是致命的，panic 可能是合理选择

#### 6.3.4 日志记录
- **建议**：在选择 bwrap 源时添加 info 级别日志
- **价值**：便于调试沙箱启动问题
- **实现**：
```rust
fn preferred_bwrap_launcher() -> BubblewrapLauncher {
    if !Path::new(SYSTEM_BWRAP_PATH).is_file() {
        tracing::info!("System bwrap not found at {}, using vendored", SYSTEM_BWRAP_PATH);
        return BubblewrapLauncher::Vendored;
    }
    // ...
}
```

#### 6.3.5 测试覆盖扩展
- **建议**：添加内嵌 bwrap 路径的测试
- **挑战**：需要构建时启用内嵌 bwrap
- **建议**：添加 argv 转换的边界测试（空参数、特殊字符）

### 6.4 维护注意事项

1. **内嵌 bwrap 同步**：确保 `vendored_bwrap.rs` 与模块接口保持一致
2. **路径规范化**：`AbsolutePathBuf` 的使用确保路径安全
3. **FFI 安全**：所有 FFI 调用都有 `unsafe` 块和相应的安全注释
