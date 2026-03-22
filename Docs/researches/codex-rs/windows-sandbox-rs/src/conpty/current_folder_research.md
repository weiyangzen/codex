# ConPTY 模块研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与使用场景

`conpty` 模块位于 `codex-rs/windows-sandbox-rs/src/conpty/` 目录下，是 Codex Windows 沙箱实现中的**伪终端（Pseudo Terminal, PTY）核心组件**。其主要使用场景包括：

| 场景 | 描述 |
|------|------|
 **Elevated 路径** | 当 Windows 沙箱级别设置为 `Elevated` 且 `tty=true` 时，通过 `spawn_conpty_process_as_user` 创建带 PTY 的沙箱进程 |
 **Legacy 路径** | 在受限令牌（restricted-token）路径中，直接创建 PTY 支持的沙箱进程 |
 **统一执行（Unified Exec）** | 支持 `exec_command` 工具的 TTY 模式，为交互式命令提供终端体验 |

### 1.2 核心职责

```rust
// 模块文档注释（mod.rs 第 1-7 行）
//! ConPTY helpers for spawning sandboxed processes with a PTY on Windows.
//!
//! This module encapsulates ConPTY creation and process spawn with the required
//! `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` plumbing. It is shared by both the legacy
//! restricted‑token path and the elevated runner path when unified_exec runs with
//! `tty=true`. The helpers are not tied to the IPC layer and can be reused by other
//! Windows sandbox flows that need a PTY.
```

该模块的核心职责包括：

1. **ConPTY 实例管理**：创建和管理 Windows ConPTY 句柄及其底层管道
2. **进程启动**：使用 `CreateProcessAsUserW` 启动带有 PTY 附加的沙箱进程
3. **线程属性列表**：管理 `PROC_THREAD_ATTRIBUTE_LIST` 以附加 ConPTY 到子进程
4. **桌面隔离支持**：与 `LaunchDesktop` 集成，支持私有桌面（private desktop）模式

---

## 功能点目的

### 2.1 功能概览

| 功能点 | 目的 | 关键 API/结构 |
|--------|------|---------------|
 **ConptyInstance** | RAII 封装 ConPTY 句柄和管道句柄，确保资源正确释放 | `ConptyInstance` struct |
 **create_conpty** | 创建 ConPTY 实例（默认 80x24 终端大小） | `RawConPty::new` |
 **spawn_conpty_process_as_user** | 以指定用户令牌启动带 PTY 的进程 | `CreateProcessAsUserW` |
 **ProcThreadAttributeList** | 管理线程属性列表，附加 ConPTY 到进程 | `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` |

### 2.2 与相关模块的对比

```
┌─────────────────────────────────────────────────────────────────┐
│                    Windows 沙箱进程启动方式                       │
├─────────────────────────────────────────────────────────────────┤
│  方式              │  使用场景              │  是否使用 ConPTY   │
├────────────────────┼───────────────────────┼────────────────────┤
│  Pipe Spawn        │ 非交互式命令 (tty=false) │        否          │
│  ConPTY Spawn      │ 交互式命令 (tty=true)   │        是          │
│  Legacy Direct     │ 旧版受限令牌路径        │   可选（通过本模块） │
│  Elevated Runner   │ 提升权限路径            │   可选（通过本模块） │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 终端大小与配置

当前实现使用**硬编码的默认终端大小**：

```rust
// mod.rs 第 111 行
let conpty = create_conpty(80, 24)?;  // 80列 x 24行
```

这个默认值在 `spawn_conpty_process_as_user` 函数中固定，**不支持动态调整**。相比之下，`codex-utils-pty` 中的通用 PTY 实现支持通过 `TerminalSize` 参数动态指定。

---

## 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 ConptyInstance

```rust
// mod.rs 第 35-65 行
pub struct ConptyInstance {
    pub hpc: HANDLE,           // ConPTY 伪控制台句柄 (HPCON)
    pub input_write: HANDLE,   // 输入管道写入端（向子进程发送输入）
    pub output_read: HANDLE,   // 输出管道读取端（从子进程读取输出）
    _desktop: LaunchDesktop,   // 桌面隔离上下文（RAII 保护）
}

impl Drop for ConptyInstance {
    fn drop(&mut self) {
        unsafe {
            // 按正确顺序释放资源
            if self.input_write != 0 && self.input_write != INVALID_HANDLE_VALUE {
                CloseHandle(self.input_write);
            }
            if self.output_read != 0 && self.output_read != INVALID_HANDLE_VALUE {
                CloseHandle(self.output_read);
            }
            if self.hpc != 0 && self.hpc != INVALID_HANDLE_VALUE {
                ClosePseudoConsole(self.hpc);  // 关闭 ConPTY
            }
        }
    }
}
```

**设计要点**：
- 使用 `ManuallyDrop` 在 `into_raw()` 中转移所有权而不触发 `Drop`
- `_desktop` 字段确保桌面句柄在 ConPTY 之后释放

#### 3.1.2 ProcThreadAttributeList

```rust
// proc_thread_attr.rs 第 16-79 行
pub struct ProcThreadAttributeList {
    buffer: Vec<u8>,  // 底层存储缓冲区
}

// 关键常量：ConPTY 属性标识符
const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;
```

**初始化流程**：

```rust
pub fn new(attr_count: u32) -> io::Result<Self> {
    // 1. 第一次调用：获取所需缓冲区大小
    let mut size: usize = 0;
    unsafe {
        InitializeProcThreadAttributeList(std::ptr::null_mut(), attr_count, 0, &mut size);
    }
    
    // 2. 分配缓冲区
    let mut buffer = vec![0u8; size];
    
    // 3. 第二次调用：实际初始化
    let list = buffer.as_mut_ptr() as LPPROC_THREAD_ATTRIBUTE_LIST;
    let ok = unsafe { InitializeProcThreadAttributeList(list, attr_count, 0, &mut size) };
    
    Ok(Self { buffer })
}
```

### 3.2 关键流程

#### 3.2.1 ConPTY 创建流程

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  create_conpty  │────▶│  RawConPty::new  │────▶│  PsuedoCon::new │
│   (80, 24)      │     │  (utils/pty)     │     │  (kernel32.dll) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                              ┌───────────────────────────┘
                              ▼
                    ┌─────────────────────┐
                    │ CreatePseudoConsole │
                    │  (Windows API)      │
                    └─────────────────────┘
```

**代码实现**（mod.rs 第 71-81 行）：

```rust
pub fn create_conpty(cols: i16, rows: i16) -> Result<ConptyInstance> {
    // 委托给 codex-utils-pty 创建原始 ConPTY
    let raw = RawConPty::new(cols, rows)?;
    let (hpc, input_write, output_read) = raw.into_raw_handles();

    Ok(ConptyInstance {
        hpc: hpc as HANDLE,
        input_write: input_write as HANDLE,
        output_read: output_read as HANDLE,
        _desktop: LaunchDesktop::prepare(false, None)?,  // 准备桌面上下文
    })
}
```

#### 3.2.2 进程启动流程

```rust
// mod.rs 第 87-146 行
pub fn spawn_conpty_process_as_user(
    h_token: HANDLE,                    // 用户令牌（受限令牌或沙箱用户）
    argv: &[String],                    // 命令行参数
    cwd: &Path,                         // 工作目录
    env_map: &HashMap<String, String>,  // 环境变量
    use_private_desktop: bool,          // 是否使用私有桌面
    logs_base_dir: Option<&Path>,       // 日志目录
) -> Result<(PROCESS_INFORMATION, ConptyInstance)> {
    // 1. 构建命令行字符串（带引号处理）
    let cmdline_str = argv.iter()
        .map(|arg| quote_windows_arg(arg))
        .collect::<Vec<_>>()
        .join(" ");
    
    // 2. 创建环境块（Unicode 格式）
    let env_block = make_env_block(env_map);
    
    // 3. 初始化 STARTUPINFOEXW（扩展启动信息）
    let mut si: STARTUPINFOEXW = unsafe { std::mem::zeroed() };
    si.StartupInfo.cb = std::mem::size_of::<STARTUPINFOEXW>() as u32;
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    // 注意：使用 ConPTY 时，标准句柄被设为 INVALID_HANDLE_VALUE
    si.StartupInfo.hStdInput = INVALID_HANDLE_VALUE;
    si.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
    si.StartupInfo.hStdError = INVALID_HANDLE_VALUE;
    
    // 4. 准备桌面上下文
    let desktop = LaunchDesktop::prepare(use_private_desktop, logs_base_dir)?;
    si.StartupInfo.lpDesktop = desktop.startup_info_desktop();
    
    // 5. 创建 ConPTY 实例
    let conpty = create_conpty(80, 24)?;
    
    // 6. 创建并配置线程属性列表
    let mut attrs = ProcThreadAttributeList::new(1)?;
    attrs.set_pseudoconsole(conpty.hpc)?;  // 附加 ConPTY
    si.lpAttributeList = attrs.as_mut_ptr();
    
    // 7. 使用 CreateProcessAsUserW 创建进程
    let ok = unsafe {
        CreateProcessAsUserW(
            h_token,
            std::ptr::null(),      // 不指定模块名（从命令行解析）
            cmdline.as_mut_ptr(),  // 命令行（可变，因 Windows API 要求）
            std::ptr::null_mut(),  // 默认进程安全属性
            std::ptr::null_mut(),  // 默认线程安全属性
            0,                     // 不继承句柄
            EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            env_block.as_ptr() as *mut c_void,
            to_wide(cwd).as_ptr(),
            &si.StartupInfo,
            &mut pi,
        )
    };
}
```

#### 3.2.3 ProcThreadAttributeList 的 ConPTY 附加

```rust
// proc_thread_attr.rs 第 49-70 行
pub fn set_pseudoconsole(&mut self, hpc: isize) -> io::Result<()> {
    let list = self.as_mut_ptr();
    let mut hpc_value = hpc;
    let ok = unsafe {
        UpdateProcThreadAttribute(
            list,
            0,                                          // 保留标志
            PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,        // 属性标识符 (0x00020016)
            (&mut hpc_value as *mut isize).cast(),      // 属性值（ConPTY 句柄）
            std::mem::size_of::<isize>(),               // 值大小
            std::ptr::null_mut(),                       // 不返回旧值
            std::ptr::null_mut(),                       // 不返回旧值大小
        )
    };
    if ok == 0 {
        return Err(io::Error::from_raw_os_error(unsafe { GetLastError() as i32 }));
    }
    Ok(())
}
```

### 3.3 Windows API 调用链

| 调用层级 | 函数/结构 | 来源 |
|----------|-----------|------|
 高层 | `spawn_conpty_process_as_user` | `mod.rs` |
   ↓ | `create_conpty` | `mod.rs` |
   ↓ | `RawConPty::new` | `utils/pty/src/win/conpty.rs` |
   ↓ | `PsuedoCon::new` | `utils/pty/src/win/psuedocon.rs` |
   ↓ | `CreatePseudoConsole` | `kernel32.dll` (Windows 10 1809+) |
 并行 | `CreateProcessAsUserW` | `windows-sys` |
   ↓ | `STARTUPINFOEXW` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE` | Windows API |

---

## 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 行数 | 核心内容 |
|------|------|----------|
| `mod.rs` | 146 | `ConptyInstance`、`create_conpty`、`spawn_conpty_process_as_user` |
| `proc_thread_attr.rs` | 79 | `ProcThreadAttributeList`、ConPTY 属性附加 |

### 4.2 调用方（Callers）

```rust
// 1. elevated/command_runner_win.rs（提升权限路径）
// 第 254-278 行
let (pi, conpty) = codex_windows_sandbox::spawn_conpty_process_as_user(
    h_token,
    &req.command,
    &effective_cwd,
    &req.env,
    req.use_private_desktop,
    Some(log_dir.as_path()),
)?;
let (hpc, input_write, output_read) = conpty.into_raw();
```

```rust
// 2. lib.rs（模块导出）
// 第 67-68 行
#[cfg(target_os = "windows")]
pub use conpty::spawn_conpty_process_as_user;
```

### 4.3 被调用方（Callees）

| 被调用模块/函数 | 文件路径 | 用途 |
|-----------------|----------|------|
 `RawConPty::new` | `utils/pty/src/win/conpty.rs:67` | 底层 ConPTY 创建 |
 `LaunchDesktop::prepare` | `desktop.rs:63` | 桌面上下文准备 |
 `quote_windows_arg` | `winutil.rs:29` | Windows 命令行参数引号处理 |
 `to_wide` | `winutil.rs:19` | UTF-8 到 UTF-16 转换 |
 `make_env_block` | `process.rs:36` | 环境变量块构建 |
 `CreateProcessAsUserW` | `windows-sys` | Windows 进程创建 API |

### 4.4 依赖的 Windows API

```rust
// mod.rs 使用的 Windows API
use windows_sys::Win32::Foundation::CloseHandle;
use windows_sys::Win32::Foundation::GetLastError;
use windows_sys::Win32::Foundation::HANDLE;
use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
use windows_sys::Win32::System::Console::ClosePseudoConsole;
use windows_sys::Win32::System::Threading::CreateProcessAsUserW;
use windows_sys::Win32::System::Threading::CREATE_UNICODE_ENVIRONMENT;
use windows_sys::Win32::System::Threading::EXTENDED_STARTUPINFO_PRESENT;
use windows_sys::Win32::System::Threading::PROCESS_INFORMATION;
use windows_sys::Win32::System::Threading::STARTF_USESTDHANDLES;
use windows_sys::Win32::System::Threading::STARTUPINFOEXW;

// proc_thread_attr.rs 使用的 Windows API
use windows_sys::Win32::System::Threading::DeleteProcThreadAttributeList;
use windows_sys::Win32::System::Threading::InitializeProcThreadAttributeList;
use windows_sys::Win32::System::Threading::UpdateProcThreadAttribute;
use windows_sys::Win32::System::Threading::LPPROC_THREAD_ATTRIBUTE_LIST;
```

---

## 依赖与外部交互

### 5.1 Crate 依赖

```toml
# Cargo.toml（windows-sandbox-rs）
[dependencies]
codex-utils-pty = { workspace = true }  # RawConPty 来源
anyhow = "1.0"
windows-sys = { version = "0.52", features = [...] }
```

```toml
# utils/pty/Cargo.toml
[target.'cfg(windows)'.dependencies]
filedescriptor = "0.8.3"
winapi = { version = "0.3.9", features = [...] }
portable-pty = { workspace = true }
```

### 5.2 与 codex-utils-pty 的交互

```
┌─────────────────────────────┐         ┌─────────────────────────────┐
│   windows-sandbox-rs        │         │      codex-utils-pty        │
│                             │         │                             │
│  ┌─────────────────────┐    │  uses   │  ┌─────────────────────┐    │
│  │ conpty::mod.rs      │────┼────────▶│  │ win::conpty.rs      │    │
│  │ - ConptyInstance    │    │         │  │ - RawConPty         │    │
│  │ - create_conpty     │    │         │  │ - ConPtySystem      │    │
│  └─────────────────────┘    │         │  └─────────────────────┘    │
│                             │         │             │               │
│  ┌─────────────────────┐    │         │             ▼               │
│  │ elevated/           │    │         │  ┌─────────────────────┐    │
│  │ command_runner_win  │    │         │  │ win::psuedocon.rs   │    │
│  └─────────────────────┘    │         │  │ - PsuedoCon         │    │
│                             │         │  │ - CreatePseudoConsole│   │
└─────────────────────────────┘         │  └─────────────────────┘    │
                                        └─────────────────────────────┘
```

### 5.3 与 Desktop 模块的交互

```rust
// desktop.rs 关键接口
pub struct LaunchDesktop {
    _private_desktop: Option<PrivateDesktop>,
    startup_name: Vec<u16>,  // 如 "Winsta0\Default" 或 "Winsta0\CodexSandboxDesktop-{随机}"
}

impl LaunchDesktop {
    pub fn prepare(use_private_desktop: bool, logs_base_dir: Option<&Path>) -> Result<Self>;
    pub fn startup_info_desktop(&self) -> *mut u16;  // 返回桌面名称指针
}
```

**交互目的**：某些进程（如 PowerShell）在使用受限令牌启动时，如果 `lpDesktop` 未设置，可能会失败并返回 `STATUS_DLL_INIT_FAILED`。`LaunchDesktop` 确保正确设置桌面上下文。

### 5.4 与 Token 模块的交互

沙箱使用**受限令牌（restricted token）**启动进程，ConPTY 模块接收的 `h_token` 来自：

```rust
// token.rs 中的令牌创建函数
pub unsafe fn create_readonly_token_with_cap_from(
    base_token: HANDLE,
    psid_capability: *mut c_void,
) -> Result<(HANDLE, *mut c_void)>;

pub unsafe fn create_workspace_write_token_with_caps_from(
    base_token: HANDLE,
    psid_capabilities: &[*mut c_void],
) -> Result<HANDLE>;
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 硬编码终端大小

```rust
// mod.rs 第 111 行 - 问题代码
let conpty = create_conpty(80, 24)?;
```

**风险**：无法适应不同终端尺寸需求，可能导致：
- 长行被截断或换行异常
- 终端应用程序（如 `vim`、`htop`）布局错乱
- 与客户端实际终端尺寸不一致

**建议**：接受 `TerminalSize` 参数，从调用链传递：

```rust
pub fn spawn_conpty_process_as_user(
    h_token: HANDLE,
    argv: &[String],
    cwd: &Path,
    env_map: &HashMap<String, String>,
    use_private_desktop: bool,
    logs_base_dir: Option<&Path>,
    terminal_size: TerminalSize,  // 新增参数
) -> Result<(PROCESS_INFORMATION, ConptyInstance)> {
    let conpty = create_conpty(terminal_size.cols as i16, terminal_size.rows as i16)?;
    // ...
}
```

#### 6.1.2 错误处理与诊断

当前错误信息虽然包含上下文，但缺少 ConPTY 特定的诊断：

```rust
// mod.rs 第 132-141 行
return Err(anyhow::anyhow!(
    "CreateProcessAsUserW failed: {} ({}) | cwd={} | cmd={} | env_u16_len={}",
    err,
    format_last_error(err),
    cwd.display(),
    cmdline_str,
    env_block.len()
));
```

**建议**：添加 ConPTY 句柄状态、桌面名称等诊断信息。

#### 6.1.3 资源泄漏边界情况

虽然 `ConptyInstance` 实现了 `Drop`，但在某些路径中：

```rust
// command_runner_win.rs 第 521-523 行
if let Some(hpc) = hpc_handle {
    ClosePseudoConsole(hpc);  // 手动关闭，绕过 ConptyInstance::Drop
}
```

这可能导致重复关闭或关闭顺序问题。

### 6.2 平台兼容性边界

| 边界条件 | 说明 |
|----------|------|
 **Windows 版本** | ConPTY 需要 Windows 10 版本 1809（构建号 17763）或更高 |
 **构建号检查** | `utils/pty/src/win/psuedocon.rs:67` 定义 `MIN_CONPTY_BUILD: u32 = 17_763` |
 **Fallback** | 在不支持 ConPTY 的系统上，应回退到 `ShellCommand`（见 `spec.rs:358-362`） |

### 6.3 改进建议

#### 6.3.1 优先级：高

1. **支持动态终端大小**
   - 修改 `spawn_conpty_process_as_user` 签名，接受 `TerminalSize` 参数
   - 更新调用方（`command_runner_win.rs`）传递 `req.terminal_size`

2. **添加 ConPTY 调整大小支持**
   - `utils/pty` 已实现 `PsuedoCon::resize`，但 `ConptyInstance` 未暴露此功能
   - 建议添加 `resize` 方法支持终端动态调整

#### 6.3.2 优先级：中

3. **改进错误诊断**
   ```rust
   // 建议添加的信息
   - ConPTY 创建是否成功
   - 桌面名称（Default 或 Private）
   - 令牌类型（ReadOnly 或 WorkspaceWrite）
   - 线程属性列表状态
   ```

4. **代码复用优化**
   - `proc_thread_attr.rs` 与 `utils/pty/src/win/procthreadattr.rs` 功能重复
   - 考虑统一或明确职责分离

#### 6.3.3 优先级：低

5. **文档与测试**
   - 添加集成测试，验证 ConPTY 进程实际启动和 I/O 流转
   - 文档说明 ConPTY 与 Pipe Spawn 的行为差异

### 6.4 相关 Issue 模式

根据代码注释和结构，潜在问题模式包括：

| 模式 | 说明 | 相关代码 |
|------|------|----------|
 `STATUS_DLL_INIT_FAILED` | PowerShell 等进程在受限令牌+无桌面时失败 | `mod.rs` 注释提及 |
 管道死锁 | 未正确关闭管道句柄导致子进程阻塞 | `Drop` 实现关键 |
 桌面权限 | 私有桌面需要正确设置 DACL | `desktop.rs:128-186` |

---

## 附录：代码引用速查

### A.1 关键行号索引

| 功能 | 文件 | 行号 |
|------|------|------|
 `ConptyInstance` 定义 | `mod.rs` | 35-65 |
 `create_conpty` 函数 | `mod.rs` | 71-81 |
 `spawn_conpty_process_as_user` 函数 | `mod.rs` | 87-146 |
 `ProcThreadAttributeList` 定义 | `proc_thread_attr.rs` | 16-79 |
 `set_pseudoconsole` 方法 | `proc_thread_attr.rs` | 49-70 |
 `RawConPty` 定义 | `utils/pty/src/win/conpty.rs` | 60-93 |
 `PsuedoCon::new` | `utils/pty/src/win/psuedocon.rs` | 137-153 |
 调用方（Elevated） | `elevated/command_runner_win.rs` | 254-278 |

### A.2 Windows API 文档链接

- [`CreatePseudoConsole`](https://learn.microsoft.com/en-us/windows/console/createpseudoconsole)
- [`PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)
- [`CreateProcessAsUserW`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw)
- [`STARTUPINFOEXW`](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-startupinfoexw)
