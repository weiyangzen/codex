# runner_pipe.rs 研究文档

## 场景与职责

`runner_pipe.rs` 是 Windows 沙箱系统中**提升权限路径（elevated path）**的命名管道辅助模块。它负责在父进程（Codex CLI）和命令运行器（command_runner_win.rs）之间建立安全的 IPC 通道。

### 核心场景

1. **管道名称生成**：生成唯一的命名管道路径，避免冲突
2. **安全管道创建**：创建具有严格 DACL（ discretionary access control list）的命名管道，仅允许特定沙箱用户连接
3. **连接管理**：处理运行器到管道的连接，支持已连接状态的容错
4. **运行器可执行文件定位**：解析命令运行器二进制文件的路径

### 与 ipc_framed.rs 的关系

- `ipc_framed.rs`：定义帧协议（**什么**数据被传输）
- `runner_pipe.rs`：管理传输通道（**如何**建立连接）

### 使用位置

该模块被 `elevated_impl.rs` 使用（父进程侧），而 `command_runner_win.rs` 使用 `CreateFileW` 直接连接管道（子进程侧）。

## 功能点目的

### 1. 唯一管道名称生成
- **目的**：防止多个并发沙箱会话之间的管道名称冲突
- **机制**：使用 `SmallRng` 生成 128 位随机数，格式为 `\\.\pipe\codex-runner-{随机数}-{in|out}`
- **双管道设计**：一对管道（in/out）实现全双工通信

### 2. 安全管道创建
- **目的**：确保只有授权的沙箱用户可以连接到管道，防止权限提升攻击
- **机制**：
  - 解析沙箱用户名为 SID
  - 构建 SDDL（Security Descriptor Definition Language）字符串
  - 使用 `ConvertStringSecurityDescriptorToSecurityDescriptorW` 创建安全描述符
  - 创建管道时应用该安全描述符

### 3. 连接等待
- **目的**：父进程创建管道后等待运行器连接
- **容错**：处理 `ERROR_PIPE_CONNECTED`（管道已连接）状态，避免竞争条件导致的错误

### 4. 辅助可执行文件解析
- **目的**：定位 `codex-command-runner.exe` 二进制文件
- **策略**：优先使用 `helper_materialization` 模块复制的版本，回退到传统查找方式

## 具体技术实现

### 关键常量

```rust
/// PIPE_ACCESS_INBOUND (win32 constant), not exposed in windows-sys 0.52.
pub const PIPE_ACCESS_INBOUND: u32 = 0x0000_0001;
/// PIPE_ACCESS_OUTBOUND (win32 constant), not exposed in windows-sys 0.52.
pub const PIPE_ACCESS_OUTBOUND: u32 = 0x0000_0002;
```

### 关键函数

#### `find_runner_exe(codex_home: &Path, log_dir: Option<&Path>) -> PathBuf`
```rust
pub fn find_runner_exe(codex_home: &Path, log_dir: Option<&Path>) -> PathBuf {
    resolve_helper_for_launch(HelperExecutable::CommandRunner, codex_home, log_dir)
}
```
- 委托给 `helper_materialization::resolve_helper_for_launch`
- 优先从 `%CODEX_HOME%/.sandbox-bin/` 查找已复制的辅助程序
- 回退到与当前可执行文件同目录的查找

#### `pipe_pair() -> (String, String)`
```rust
pub fn pipe_pair() -> (String, String) {
    let mut rng = SmallRng::from_entropy();
    let base = format!(r"\\.\pipe\codex-runner-{:x}", rng.gen::<u128>());
    (format!("{base}-in"), format!("{base}-out"))
}
```
- 生成 128 位随机数（16 字节），十六进制编码
- 返回一对管道名称：`-in`（父进程写，运行器读）和 `-out`（运行器写，父进程读）

#### `create_named_pipe(name: &str, access: u32, sandbox_username: &str) -> io::Result<HANDLE>`

**完整流程：**

```
1. 解析沙箱用户名为 SID 字节（resolve_sid）
2. 将 SID 字节转换为字符串表示（string_from_sid_bytes）
3. 构建 SDDL 字符串："D:(A;;GA;;;{sandbox_sid})"
   - D: DACL 开始
   - A: 允许访问
   - GA: 通用所有权限（GENERIC_ALL）
   - {sandbox_sid}: 沙箱用户的 SID
4. 转换 SDDL 为安全描述符（ConvertStringSecurityDescriptorToSecurityDescriptorW）
5. 填充 SECURITY_ATTRIBUTES 结构
6. 创建命名管道（CreateNamedPipeW）：
   - 访问模式：传入的 access（INBOUND 或 OUTBOUND）
   - 管道模式：字节类型 + 字节读取模式 + 阻塞等待
   - 最大实例数：1
   - 缓冲区大小：64KB（输入和输出）
   - 默认超时：0
   - 安全属性：上述 SECURITY_ATTRIBUTES
7. 返回管道句柄
```

**SDDL 详解：**
```
D:(A;;GA;;;S-1-5-21-...)
│ │  │   │
│ │  │   └── 受托人 SID（沙箱用户）
│ │  └────── 访问权限（GA = GENERIC_ALL）
│ └───────── 访问模式（A = 允许）
└─────────── DACL 条目
```

#### `connect_pipe(h: HANDLE) -> io::Result<()>`
```rust
pub fn connect_pipe(h: HANDLE) -> io::Result<()> {
    let ok = unsafe { ConnectNamedPipe(h, ptr::null_mut()) };
    if ok == 0 {
        let err = unsafe { GetLastError() };
        const ERROR_PIPE_CONNECTED: u32 = 535;
        if err != ERROR_PIPE_CONNECTED {
            return Err(io::Error::from_raw_os_error(err as i32));
        }
    }
    Ok(())
}
```
- 调用 `ConnectNamedPipe` 等待客户端连接
- 处理 `ERROR_PIPE_CONNECTED`（535）：表示运行器在 `ConnectNamedPipe` 调用前已连接，这是正常竞争条件

### 数据结构

```rust
// 隐式数据结构
struct PipePair {
    in_pipe: String,   // \\.\pipe\codex-runner-{random}-in
    out_pipe: String,  // \\.\pipe\codex-runner-{random}-out
}

struct SecurePipeConfig {
    name: String,
    access: u32,       // PIPE_ACCESS_INBOUND 或 PIPE_ACCESS_OUTBOUND
    sddl: String,      // 安全描述符定义语言字符串
    security_descriptor: PSECURITY_DESCRIPTOR,
    security_attributes: SECURITY_ATTRIBUTES,
}
```

## 关键代码路径与文件引用

### 当前文件结构

| 函数/常量 | 行号 | 职责 |
|-----------|------|------|
| `PIPE_ACCESS_INBOUND` | 33 | 入站访问常量 |
| `PIPE_ACCESS_OUTBOUND` | 35 | 出站访问常量 |
| `find_runner_exe` | 39-41 | 定位运行器可执行文件 |
| `pipe_pair` | 44-48 | 生成唯一管道名称对 |
| `create_named_pipe` | 51-95 | 创建带安全描述的命名管道 |
| `connect_pipe` | 98-111 | 等待客户端连接 |

### 调用关系

```
elevated_impl.rs::run_windows_sandbox_capture()
    ├── pipe_pair()                    # 生成管道名称
    ├── create_named_pipe(pipe_in, PIPE_ACCESS_OUTBOUND, sandbox_sid)   # 创建输入管道
    ├── create_named_pipe(pipe_out, PIPE_ACCESS_INBOUND, sandbox_sid)   # 创建输出管道
    ├── find_runner_exe(codex_home, logs_base_dir)                      # 定位运行器
    ├── CreateProcessWithLogonW()      # 启动运行器（传入管道名）
    ├── connect_pipe(h_pipe_in)        # 等待连接
    └── connect_pipe(h_pipe_out)       # 等待连接

command_runner_win.rs (子进程侧)
    └── open_pipe(name, access)        # 使用 CreateFileW 连接管道
```

### 依赖模块

```
runner_pipe.rs
├── crate::helper_materialization      # 辅助可执行文件定位
├── crate::winutil                     # SID 解析和字符串转换
├── rand                               # 随机数生成
└── windows_sys::Win32::*              # Windows API
    ├── Security::Authorization        # SDDL 转换
    ├── System::Pipes                  # 命名管道 API
    └── Foundation                     # 错误处理
```

## 依赖与外部交互

### 输入依赖

| 来源 | 类型 | 说明 |
|------|------|------|
| 参数 | `codex_home` | Codex 主目录，用于定位运行器 |
| 参数 | `sandbox_username` | 沙箱用户名，用于构建 DACL |
| 随机数生成器 | `SmallRng` | 生成唯一管道名称 |
| 环境 | 当前可执行文件路径 | 传统查找方式的回退 |

### 输出交互

| 目标 | 类型 | 说明 |
|------|------|------|
| 命名管道 | 内核对象 | 创建的管道句柄 |
| 返回值 | `PathBuf` | 运行器可执行文件路径 |
| 日志 | 文本 | 通过 `helper_materialization` 记录 |

### 外部系统交互

| 系统 | 交互方式 | 目的 |
|------|----------|------|
| Windows 安全子系统 | SID 解析 | 将用户名转换为 SID |
| Windows 安全子系统 | SDDL 转换 | 创建安全描述符 |
| Windows 命名管道 | CreateNamedPipeW | 创建管道 |
| Windows 命名管道 | ConnectNamedPipe | 等待连接 |
| Windows 文件系统 | 路径解析 | 定位辅助可执行文件 |

## 风险、边界与改进建议

### 已知风险

1. **随机数冲突**
   - 使用 128 位随机数，冲突概率极低（约 2^-128），但理论上可能
   - 冲突会导致管道创建失败或安全漏洞（如果另一个会话使用相同名称）

2. **SDDL 注入风险**
   - 当前通过 `format!("D:(A;;GA;;;{sandbox_sid})")` 构建 SDDL
   - 如果 `sandbox_sid` 包含恶意内容，可能导致安全描述符解析失败或被利用
   - **缓解**：SID 来自系统 API，格式固定，风险较低

3. **管道句柄泄漏**
   - 如果 `connect_pipe` 失败，调用方需要负责关闭管道句柄
   - `elevated_impl.rs` 中有相应的清理逻辑

4. **竞争条件**
   - 运行器可能在 `CreateNamedPipe` 和 `ConnectNamedPipe` 之间尝试连接
   - 当前通过处理 `ERROR_PIPE_CONNECTED` 缓解

5. **权限依赖**
   - 创建命名管道需要 `SeCreateGlobalPrivilege`（在 `\Global\` 命名空间）
   - 当前使用 `\\.\pipe\`（本地命名空间），权限要求较低

### 边界条件

| 边界 | 处理 |
|------|------|
| SID 解析失败 | 返回 `PermissionDenied` IO 错误 |
| SDDL 转换失败 | 返回原始 OS 错误码 |
| 管道创建失败 | 返回原始 OS 错误码 |
| 连接超时 | 当前无超时，无限等待 |
| 管道已连接 | 视为成功（`ERROR_PIPE_CONNECTED`） |

### 改进建议

1. **连接超时**
   ```rust
   // 建议：添加超时机制
   pub fn connect_pipe_with_timeout(h: HANDLE, timeout_ms: u32) -> io::Result<()> {
       // 使用异步 I/O 或线程实现超时
   }
   ```

2. **增强安全描述符**
   ```rust
   // 建议：添加完整性级别（Integrity Level）限制
   let sddl = format!(
       "D:(A;;GA;;;{sandbox_sid})S:(ML;;NW;;;LW)",
       // ML: 强制标签
       // NW: 不写入
       // LW: 低完整性级别
   );
   ```

3. **随机数增强**
   ```rust
   // 建议：添加进程 ID 和时间戳进一步降低冲突概率
   let base = format!(
       r"\\.\pipe\codex-runner-{:x}-{}-{}",
       rng.gen::<u128>(),
       std::process::id(),
       std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_nanos()
   );
   ```

4. **异步支持**
   ```rust
   // 建议：支持异步管道操作
   #[cfg(feature = "async")]
   pub async fn connect_pipe_async(h: HANDLE) -> io::Result<()> {
       // 使用 overlapped I/O 或 tokio::windows::named_pipe
   }
   ```

5. **命名空间隔离**
   ```rust
   // 建议：使用会话私有命名空间
   let base = format!(r"\\.\pipe\Local\codex-runner-{:x}", rng.gen::<u128>());
   ```

6. **测试覆盖**
   - 当前文件没有单元测试，建议添加：
     - 管道创建和连接测试
     - SDDL 构建验证测试
     - 并发管道创建测试
     - 权限拒绝场景测试

7. **错误信息增强**
   ```rust
   // 建议：添加更多上下文信息
   pub fn create_named_pipe(name: &str, access: u32, sandbox_username: &str) -> io::Result<HANDLE> {
       let sandbox_sid = resolve_sid(sandbox_username)
           .map_err(|err| io::Error::new(
               io::ErrorKind::PermissionDenied,
               format!("Failed to resolve SID for user '{}': {}", sandbox_username, err)
           ))?;
       // ...
   }
   ```

8. **资源清理封装**
   ```rust
   // 建议：使用 RAII 模式管理管道句柄
   pub struct NamedPipe {
       handle: HANDLE,
   }
   
   impl Drop for NamedPipe {
       fn drop(&mut self) {
           unsafe { CloseHandle(self.handle); }
       }
   }
   ```

9. **管道配置参数化**
   ```rust
   // 建议：允许调用方配置缓冲区大小和超时
   pub struct PipeConfig {
       pub input_buffer_size: u32,
       pub output_buffer_size: u32,
       pub default_timeout: u32,
   }
   ```

10. **安全审计日志**
    ```rust
    // 建议：记录安全相关事件
    log_security_event(SecurityEvent::PipeCreated {
        name: name.to_string(),
        sid: sandbox_sid.clone(),
        timestamp: std::time::SystemTime::now(),
    });
    ```
