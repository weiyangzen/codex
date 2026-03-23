# process.rs 深度研究文档

## 场景与职责

`process.rs` 是 Windows Sandbox 模块中的**进程管理器**，负责在 Windows 平台上以特定用户身份创建和管理进程。它提供了两种主要的进程创建模式：标准 IO 继承模式和管道模式。

### 核心职责
1. **用户令牌进程创建**：使用 `CreateProcessAsUserW` 以受限用户身份创建进程
2. **环境变量块构建**：将 Rust 的 `HashMap` 转换为 Windows 环境块格式
3. **标准 IO 处理**：支持继承父进程 IO 或使用匿名管道
4. **桌面隔离支持**：支持在私有桌面或默认桌面创建进程

## 功能点目的

### 1. `CreatedProcess` 结构
```rust
pub struct CreatedProcess {
    pub process_info: PROCESS_INFORMATION,
    pub startup_info: STARTUPINFOW,
    _desktop: LaunchDesktop,
}
```
- 封装进程创建结果
- 包含进程/线程句柄、启动信息、桌面引用
- 桌面引用确保生命周期管理（RAII）

### 2. `make_env_block` - 环境变量块构建
```rust
pub fn make_env_block(env: &HashMap<String, String>) -> Vec<u16>
```
- **格式**：Windows 要求的环境块格式
- **排序**：按键名不区分大小写排序，然后按原始大小写排序
- **编码**：UTF-16 LE，以双 null 终止

**格式示例**：
```
"KEY1=value1\0KEY2=value2\0\0"
```

### 3. `create_process_as_user` - 核心进程创建
```rust
pub unsafe fn create_process_as_user(
    h_token: HANDLE,
    argv: &[String],
    cwd: &Path,
    env_map: &HashMap<String, String>,
    logs_base_dir: Option<&Path>,
    stdio: Option<(HANDLE, HANDLE, HANDLE)>,
    use_private_desktop: bool,
) -> Result<CreatedProcess>
```

**关键步骤**：
1. 构建命令行（参数转义）
2. 构建环境变量块
3. 准备启动信息（STARTUPINFOW）
4. 配置桌面（默认或私有）
5. 设置 IO 句柄继承
6. 调用 `CreateProcessAsUserW`
7. 错误处理和日志记录

### 4. 管道模式支持

#### `StdinMode` / `StderrMode` 枚举
```rust
pub enum StdinMode { Closed, Open }
pub enum StderrMode { MergeStdout, Separate }
```

#### `PipeSpawnHandles` 结构
```rust
pub struct PipeSpawnHandles {
    pub process: PROCESS_INFORMATION,
    pub stdin_write: Option<HANDLE>,
    pub stdout_read: HANDLE,
    pub stderr_read: Option<HANDLE>,
}
```

#### `spawn_process_with_pipes`
- 创建匿名管道对
- 配置管道句柄继承
- 调用 `create_process_as_user`
- 关闭父进程不需要的管道端
- 返回管道句柄供后续读写

### 5. `read_handle_loop` - 异步读取
```rust
pub fn read_handle_loop<F>(handle: HANDLE, mut on_chunk: F) -> std::thread::JoinHandle<()>
```
- 在独立线程中读取管道句柄
- 使用 8KB 缓冲区
- 对每个读取的数据块调用回调函数
- 自动关闭句柄（EOF 或错误时）

## 具体技术实现

### 命令行构建
```rust
let cmdline_str = argv
    .iter()
    .map(|a| quote_windows_arg(a))
    .collect::<Vec<_>>()
    .join(" ");
```
- 使用 `winutil::quote_windows_arg` 进行 Windows 风格的参数转义
- 处理空格、引号、反斜杠等特殊字符

### 桌面配置
```rust
let desktop = LaunchDesktop::prepare(use_private_desktop, logs_base_dir)?;
si.lpDesktop = desktop.startup_info_desktop();
```
- 私有桌面：创建隔离的桌面环境
- 默认桌面：`Winsta0\Default`
- 某些进程（如 PowerShell）需要显式桌面设置

### IO 句柄继承
```rust
let inherit_handles = match stdio {
    Some((stdin_h, stdout_h, stderr_h)) => {
        si.dwFlags |= STARTF_USESTDHANDLES;
        si.hStdInput = stdin_h;
        si.hStdOutput = stdout_h;
        si.hStdError = stderr_h;
        // 设置句柄继承标志
        for h in [stdin_h, stdout_h, stderr_h] {
            SetHandleInformation(h, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
        }
        true
    }
    None => { /* 使用标准句柄 */ }
};
```

### 错误诊断
```rust
let msg = format!(
    "CreateProcessAsUserW failed: {} ({}) | cwd={} | cmd={} | env_u16_len={} | si_flags={} | creation_flags={}",
    err, format_last_error(err), cwd.display(), cmdline_str,
    env_block_len, si.dwFlags, creation_flags,
);
logging::debug_log(&msg, logs_base_dir);
```
- 详细的错误上下文信息
- 便于调试进程启动失败

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源 | 用途 |
|------|------|------|
| `quote_windows_arg` | `winutil.rs` | 参数转义 |
| `to_wide` | `winutil.rs` | 字符串转宽字符 |
| `format_last_error` | `winutil.rs` | 错误格式化 |
| `LaunchDesktop::prepare` | `desktop.rs` | 桌面准备 |
| `debug_log` | `logging.rs` | 调试日志 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `lib.rs` (windows_impl) | `create_process_as_user` | 沙箱进程创建 |
| `lib.rs` | `spawn_process_with_pipes` | 管道模式进程 |
| `lib.rs` | `read_handle_loop` | 输出读取 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use process::create_process_as_user;
#[cfg(target_os = "windows")]
pub use process::read_handle_loop;
#[cfg(target_os = "windows")]
pub use process::spawn_process_with_pipes;
#[cfg(target_os = "windows")]
pub use process::PipeSpawnHandles;
#[cfg(target_os = "windows")]
pub use process::StderrMode;
#[cfg(target_os = "windows")]
pub use process::StdinMode;
```

## 依赖与外部交互

### Windows API
- `CreateProcessAsUserW`：以指定用户令牌创建进程
- `CreatePipe`：创建匿名管道
- `SetHandleInformation`：设置句柄继承标志
- `GetStdHandle` / `SetStdHandle`：标准句柄管理
- `ReadFile`：管道读取
- `CloseHandle`：句柄清理

### 外部 Crate
- `windows-sys`：Windows API 绑定
- `anyhow`：错误处理

### 环境依赖
- 有效的用户令牌（`HANDLE`）
- 存在的工作目录
- 环境变量映射

## 风险、边界与改进建议

### 已知风险

1. **句柄泄漏**
   - 问题：错误路径上可能未正确关闭句柄
   - 缓解：使用 RAII 模式，确保清理
   - 风险点：`spawn_process_with_pipes` 的多个错误返回点

2. **管道死锁**
   - 问题：管道缓冲区满时可能死锁
   - 缓解：使用独立线程读取输出
   - 注意：需要及时消费输出

3. **令牌权限**
   - 问题：受限令牌可能无法创建某些进程
   - 缓解：确保令牌具有 `TOKEN_ASSIGN_PRIMARY` 权限

### 边界条件

1. **空参数列表**：至少应包含可执行文件路径
2. **空环境变量**：生成仅包含终止符的环境块
3. **不存在的 cwd**：`CreateProcessAsUserW` 可能失败
4. **无效令牌**：进程创建失败
5. **私有桌面失败**：回退到默认桌面或返回错误

### 改进建议

1. **异步 I/O**
   - 当前：同步读取，使用线程模拟异步
   - 建议：使用 Windows Overlapped I/O 或 IOCP

2. **超时控制**
   - 当前：读取无超时
   - 建议：添加读取超时选项

3. **资源限制**
   - 当前：无资源限制
   - 建议：支持 JOB_OBJECT 限制 CPU/内存

4. **更好的错误分类**
   - 当前：统一返回 `anyhow::Error`
   - 建议：定义具体的错误类型（权限不足、路径不存在等）

5. **命令行长度限制**
   - Windows 命令行长度限制约 32767 字符
   - 当前：无显式检查
   - 建议：添加长度验证

### 安全考虑

1. **命令注入**
   - 使用 `quote_windows_arg` 正确转义参数
   - 避免 shell 解释

2. **句柄继承**
   - 仅标记必要的句柄为可继承
   - 防止敏感句柄泄漏给子进程

3. **令牌安全**
   - 确保令牌具有最小必要权限
   - 及时关闭不再使用的令牌句柄

### 性能特征

1. **线程创建**
   - `read_handle_loop` 创建独立线程
   - 频繁调用可能产生线程开销

2. **内存分配**
   - 环境块和命令行涉及多次分配
   - 长环境变量列表可能影响性能

3. **系统调用**
   - `CreateProcessAsUserW` 是重量级操作
   - 涉及安全子系统检查
