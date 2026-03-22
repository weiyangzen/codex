# Windows PTY 子系统深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`codex-rs/utils/pty/src/win/` 是 Codex 项目中 Windows 平台专用的 **PTY (Pseudo Terminal / 伪终端)** 实现模块。该模块负责在 Windows 系统上提供与 Unix PTY 类似的功能，使 Codex 能够：

- 启动交互式进程（如 Python REPL、Shell）
- 提供终端尺寸管理（行列数调整）
- 处理进程的生命周期管理（创建、等待、终止）
- 支持跨平台的统一抽象接口

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **ConPTY 封装** | 封装 Windows 10 1809+ 引入的 ConPTY API，提供伪终端功能 |
| **进程管理** | 创建、监控、终止 Windows 子进程 |
| **I/O 管道** | 管理 stdin/stdout 的管道通信 |
| **终端尺寸控制** | 支持动态调整终端行列数 |
| **跨平台适配** | 为上层提供与 Unix PTY 一致的抽象接口 |

### 1.3 调用方与被调用方

```
调用方 (上游):
├── codex-rs/tui/              # TUI 界面，需要 PTY 运行交互式命令
├── codex-rs/exec-server/      # 执行服务器，运行用户命令
├── codex-rs/windows-sandbox-rs/  # Windows 沙箱，使用 RawConPty
│   └── src/conpty/mod.rs      # 使用 RawConPty::new() 和 into_raw_handles()
│
被调用方 (下游/依赖):
├── winapi crate               # Windows API 绑定
├── portable-pty crate         # 跨平台 PTY 抽象 trait
├── filedescriptor crate       # 文件描述符管理
└── shared_library crate       # 动态库加载 (用于 ConPTY API)
```

---

## 功能点目的

### 2.1 功能列表

| 功能模块 | 源文件 | 目的 |
|---------|--------|------|
| **ConPTY 系统初始化** | `conpty.rs` | 创建和管理 ConPTY 实例，提供 Master/Slave PTY 对 |
| **伪控制台核心** | `psuedocon.rs` | 直接封装 Windows ConPTY API (CreatePseudoConsole 等) |
| **进程线程属性** | `procthreadattr.rs` | 配置进程启动属性，关联 PTY 到子进程 |
| **子进程管理** | `mod.rs` | 实现 Child trait，提供进程等待、终止功能 |
| **原始 ConPTY 句柄** | `conpty.rs` `RawConPty` | 为沙箱场景提供底层句柄访问 |

### 2.2 关键设计决策

#### 2.2.1 为什么选择 ConPTY 而非传统方案

Windows 历史上缺乏原生 PTY 支持，开发者通常使用：
- **WinPTY**: 第三方库，通过隐藏控制台窗口实现
- **直接控制台 API**: 限制多，不支持真正的 TTY 语义

Windows 10 1809 (Build 17763) 引入 **ConPTY** 后：
- 提供真正的伪终端语义
- 支持 ANSI 转义序列
- 与 Windows Terminal 共享底层实现
- 更好的性能和兼容性

#### 2.2.2 动态库加载策略

```rust
// psuedocon.rs 第 87-97 行
fn load_conpty() -> ConPtyFuncs {
    let kernel = ConPtyFuncs::open(Path::new("kernel32.dll")).expect(...);
    
    // 优先尝试加载 sideloaded 的 conpty.dll
    if let Ok(sideloaded) = ConPtyFuncs::open(Path::new("conpty.dll")) {
        sideloaded
    } else {
        kernel
    }
}
```

**设计考量**:
- 优先使用系统 `kernel32.dll` 中的 ConPTY 函数
- 支持 `conpty.dll` sideload，便于测试新版本的 ConPTY
- 运行时检测而非编译时链接，优雅处理旧版 Windows

---

## 具体技术实现

### 3.1 核心数据结构与类型

#### 3.1.1 HPCON - 伪控制台句柄

```rust
// psuedocon.rs 第 59 行
pub type HPCON = HANDLE;  // 底层是 Windows HANDLE 类型
```

`HPCON` 是 Windows ConPTY 的核心句柄类型，代表一个伪控制台实例。

#### 3.1.2 PsuedoCon - 伪控制台封装

```rust
// psuedocon.rs 第 119-130 行
pub struct PsuedoCon {
    con: HPCON,
}

unsafe impl Send for PsuedoCon {}
unsafe impl Sync for PsuedoCon {}

impl Drop for PsuedoCon {
    fn drop(&mut self) {
        unsafe { (CONPTY.ClosePseudoConsole)(self.con) };
    }
}
```

**关键特性**:
- 手动实现 `Send` + `Sync`，允许跨线程传递
- 自定义 `Drop` 确保资源释放

#### 3.1.3 ConPtyMasterPty / ConPtySlavePty

```rust
// conpty.rs 第 148-155 行
#[derive(Clone)]
pub struct ConPtyMasterPty {
    inner: Arc<Mutex<Inner>>,
}

pub struct ConPtySlavePty {
    inner: Arc<Mutex<Inner>>,
}

struct Inner {
    con: PsuedoCon,
    readable: FileDescriptor,    // stdout 读取端
    writable: Option<FileDescriptor>,  // stdin 写入端 (take后变为None)
    size: PtySize,
}
```

**设计模式**: 
- 使用 `Arc<Mutex<Inner>>` 共享状态
- Master 和 Slave 共享同一 `Inner`
- `writable` 为 `Option`，遵循 `take_writer()` 只能调用一次的语义

#### 3.1.4 WinChild / WinChildKiller - 子进程管理

```rust
// mod.rs 第 54-119 行
#[derive(Debug)]
pub struct WinChild {
    proc: Mutex<OwnedHandle>,  // 进程句柄
}

#[derive(Debug)]
pub struct WinChildKiller {
    proc: OwnedHandle,  // 用于终止进程的独立句柄
}
```

### 3.2 关键流程详解

#### 3.2.1 ConPTY 创建流程

```
spawn_pty_process() 
    └── platform_native_pty_system() 
            └── ConPtySystem::default()
    └── pty_system.openpty(size)
            └── create_conpty_handles()
                    ├── Pipe::new() -> (stdin_read, stdin_write)
                    ├── Pipe::new() -> (stdout_read, stdout_write)
                    └── PsuedoCon::new(COORD, stdin_read, stdout_write)
                            └── CreatePseudoConsole()
```

**代码路径**: `conpty.rs:42-58`, `psuedocon.rs:137-153`

#### 3.2.2 进程启动流程

```
ConPtySlavePty::spawn_command(cmd)
    └── PsuedoCon::spawn_command()
            ├── 构建 STARTUPINFOEXW
            ├── ProcThreadAttributeList::with_capacity(1)
            ├── attrs.set_pty(self.con)  // 关联 PTY
            └── CreateProcessW(
                    EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                    &mut si.StartupInfo,
                    &mut pi
                )
```

**关键 Windows API**: 
- `EXTENDED_STARTUPINFO_PRESENT`: 使用扩展启动信息
- `ProcThreadAttributeList` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`: 将 PTY 关联到子进程

**代码路径**: `psuedocon.rs:167-219`, `procthreadattr.rs`

#### 3.2.3 命令行构建与参数转义

Windows 命令行参数需要特殊转义处理：

```rust
// psuedocon.rs 第 312-355 行
fn append_quoted(arg: &OsStr, cmdline: &mut Vec<u16>) {
    // 1. 检查是否需要引号
    // 2. 处理反斜杠转义（Windows 特殊规则）
    // 3. 处理引号前的反斜杠加倍
}
```

**Windows 参数转义规则**:
- 包含空格、制表符、换行、引号的参数需要引号包裹
- 引号前的反斜杠需要加倍转义
- 参数末尾的反斜杠需要加倍

#### 3.2.4 进程终止流程

```
WinChild::do_kill()
    └── TerminateProcess(proc_handle, 1)

WinChildKiller::kill()
    └── TerminateProcess(proc_handle, 1)
```

**重要修复** (Codex Bug #13945):
```rust
// mod.rs 第 75-84 行
fn do_kill(&mut self) -> IoResult<()> {
    let res = unsafe { TerminateProcess(proc.as_raw_handle() as _, 1) };
    // Win32 返回非零表示成功！
    if res == 0 {
        Err(IoError::last_os_error())
    } else {
        Ok(())
    }
}
```

原 WezTerm 代码错误地将非零返回值视为失败，Codex 已修复此问题。

#### 3.2.5 终端尺寸调整流程

```
MasterPty::resize(size)
    └── Inner::resize()
            └── PsuedoCon::resize()
                    └── ResizePseudoConsole()
```

**代码路径**: `conpty.rs:127-146`, `psuedocon.rs:155-165`

### 3.3 协议与接口

#### 3.3.1 portable-pty Trait 实现

```rust
// conpty.rs 第 95-117 行
impl PtySystem for ConPtySystem {
    fn openpty(&self, size: PtySize) -> anyhow::Result<PtyPair>;
}

impl MasterPty for ConPtyMasterPty {
    fn resize(&self, size: PtySize) -> anyhow::Result<()>;
    fn get_size(&self) -> Result<PtySize>;
    fn try_clone_reader(&self) -> anyhow::Result<Box<dyn Read + Send>>;
    fn take_writer(&self) -> anyhow::Result<Box<dyn Write + Send>>;
}

impl SlavePty for ConPtySlavePty {
    fn spawn_command(&self, cmd: CommandBuilder) -> anyhow::Result<Box<dyn Child + Send + Sync>>;
}
```

#### 3.3.2 Child Trait 实现

```rust
// mod.rs 第 121-156 行
impl Child for WinChild {
    fn try_wait(&mut self) -> IoResult<Option<ExitStatus>>;
    fn wait(&mut self) -> IoResult<ExitStatus>;
    fn process_id(&self) -> Option<u32>;
    fn as_raw_handle(&self) -> Option<RawHandle>;
}

impl ChildKiller for WinChild {
    fn kill(&mut self) -> IoResult<()>;
    fn clone_killer(&self) -> Box<dyn ChildKiller + Send + Sync>;
}
```

### 3.4 特殊功能：RawConPty

为 Windows 沙箱提供底层句柄访问：

```rust
// conpty.rs 第 60-93 行
pub struct RawConPty {
    con: PsuedoCon,
    input_write: FileDescriptor,
    output_read: FileDescriptor,
}

impl RawConPty {
    pub fn new(cols: i16, rows: i16) -> anyhow::Result<Self>;
    pub fn pseudoconsole_handle(&self) -> RawHandle;
    pub fn into_raw_handles(self) -> (RawHandle, RawHandle, RawHandle);
}
```

**使用场景**: `windows-sandbox-rs/src/conpty/mod.rs` 使用此功能创建沙箱化 PTY 进程。

---

## 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/utils/pty/src/win/
├── mod.rs              # 子进程管理 (WinChild, WinChildKiller)
├── conpty.rs           # ConPTY 系统实现 (ConPtySystem, RawConPty)
├── psuedocon.rs        # 底层 ConPTY API 封装 (PsuedoCon)
└── procthreadattr.rs   # 进程线程属性列表 (ProcThreadAttributeList)
```

### 4.2 关键代码路径映射

| 功能 | 入口 | 核心实现 |
|------|------|----------|
| 创建 PTY | `pty.rs:spawn_process()` | `conpty.rs:ConPtySystem::openpty()` |
| 启动进程 | `SlavePty::spawn_command()` | `psuedocon.rs:PsuedoCon::spawn_command()` |
| 终止进程 | `ProcessHandle::terminate()` | `mod.rs:WinChild::do_kill()` |
| 调整尺寸 | `ProcessHandle::resize()` | `conpty.rs:Inner::resize()` |
| 等待退出 | `exit_rx.await` | `mod.rs:WinChild::wait()` |
| 检查状态 | `ProcessHandle::has_exited()` | `mod.rs:WinChild::is_complete()` |
| 构建命令行 | `psuedocon.rs:build_cmdline()` | `psuedocon.rs:append_quoted()` |
| 搜索可执行文件 | `psuedocon.rs:search_path()` | `psuedocon.rs:288-310` |
| 环境变量块 | `psuedocon.rs:build_environment_block()` | `psuedocon.rs:245-255` |

### 4.3 重要代码段索引

#### 4.3.1 版本检测

```rust
// psuedocon.rs 第 66-68 行
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 1809

pub fn conpty_supported() -> bool {
    windows_build_number().is_some_and(|build| build >= MIN_CONPTY_BUILD)
}
```

#### 4.3.2 进程属性列表初始化

```rust
// procthreadattr.rs 第 36-60 行
impl ProcThreadAttributeList {
    pub fn with_capacity(num_attributes: DWORD) -> Result<Self> {
        // 1. 查询所需内存大小
        // 2. 分配 Vec<u8>
        // 3. 初始化属性列表
    }
    
    pub fn set_pty(&mut self, con: HPCON) -> Result<()> {
        // 设置 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
    }
}
```

#### 4.3.3 Future 实现（异步等待）

```rust
// mod.rs 第 158-178 行
impl std::future::Future for WinChild {
    type Output = anyhow::Result<ExitStatus>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context) -> Poll<anyhow::Result<ExitStatus>> {
        match self.is_complete() {
            Ok(Some(status)) => Poll::Ready(Ok(status)),
            Err(err) => Poll::Ready(Err(err).context(...)),
            Ok(None) => {
                // 启动等待线程，完成后唤醒 waker
                let waker = cx.waker().clone();
                std::thread::spawn(move || {
                    unsafe { WaitForSingleObject(proc.as_raw_handle() as _, INFINITE) };
                    waker.wake();
                });
                Poll::Pending
            }
        }
    }
}
```

---

## 依赖与外部交互

### 5.1 Cargo 依赖

```toml
# Cargo.toml (Windows 专用依赖)
[target.'cfg(windows)'.dependencies]
filedescriptor = "0.8.3"        # 文件描述符抽象
lazy_static = { workspace = true }
log = { workspace = true }
shared_library = "0.1.9"        # 动态库加载
winapi = { version = "0.3.9", features = [
    "handleapi",
    "minwinbase",
    "processthreadsapi",
    "synchapi",
    "winbase",
    "wincon",
    "winerror",
    "winnt",
] }
```

### 5.2 Windows API 调用汇总

| API | 用途 | 所在文件 |
|-----|------|----------|
| `CreatePseudoConsole` | 创建伪控制台 | `psuedocon.rs` |
| `ResizePseudoConsole` | 调整终端尺寸 | `psuedocon.rs` |
| `ClosePseudoConsole` | 关闭伪控制台 | `psuedocon.rs` |
| `CreateProcessW` | 创建子进程 | `psuedocon.rs` |
| `TerminateProcess` | 终止进程 | `mod.rs` |
| `WaitForSingleObject` | 等待进程退出 | `mod.rs` |
| `GetExitCodeProcess` | 获取退出码 | `mod.rs` |
| `GetProcessId` | 获取进程 ID | `mod.rs` |
| `InitializeProcThreadAttributeList` | 初始化属性列表 | `procthreadattr.rs` |
| `UpdateProcThreadAttribute` | 设置 PTY 属性 | `procthreadattr.rs` |
| `DeleteProcThreadAttributeList` | 清理属性列表 | `procthreadattr.rs` |
| `RtlGetVersion` | 获取 Windows 版本 | `psuedocon.rs` |

### 5.3 上游调用方

| 调用方 | 使用方式 | 说明 |
|--------|----------|------|
| `codex-utils-pty::pty` | `platform_native_pty_system()` | 统一 PTY 接口 |
| `codex-utils-pty::lib` | `RawConPty` re-export | 公开 RawConPty |
| `windows-sandbox-rs::conpty` | `RawConPty::new()` | 沙箱 PTY 创建 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 版本兼容性风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 旧版 Windows 不支持 | Windows 10 1809 以下无 ConPTY | `conpty_supported()` 运行时检测 |
| API 行为变化 | ConPTY 在 Windows 11 有改进 | 使用 `PSEUDOCONSOLE_RESIZE_QUIRK` 标志 |

#### 6.1.2 资源管理风险

| 风险 | 位置 | 状态 |
|------|------|------|
| 句柄泄漏 | `RawConPty::into_raw_handles()` 使用 `ManuallyDrop` | 设计如此，调用方负责关闭 |
| 进程僵尸 | `WinChild` 未正确等待 | `Drop` 时调用 `terminate()` |

#### 6.1.3 并发风险

```rust
// mod.rs 第 62 行
let proc = self.proc.lock().unwrap().try_clone().unwrap();
```

- 使用 `Mutex` 保护进程句柄
- `try_clone()` 复制句柄而非共享所有权
- 潜在 panic: `lock().unwrap()` 在 poison 时 panic

### 6.2 边界情况

#### 6.2.1 命令行长度限制

Windows 命令行有 32,767 字符限制（理论值），实际可能更低。当前实现未显式检查。

#### 6.2.2 环境变量块大小

环境变量块无明确文档限制，但过大可能导致 `CreateProcessW` 失败。

#### 6.2.3 路径搜索行为

```rust
// psuedocon.rs 第 288-310 行
fn search_path(cmd: &CommandBuilder, exe: &OsStr) -> OsString {
    // 如果 PATH 中包含不存在的目录，会静默跳过
    // 如果找不到可执行文件，返回原始 exe 名称（可能导致 CreateProcessW 失败）
}
```

### 6.3 改进建议

#### 6.3.1 代码质量改进

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 替换 `lazy_static` | 低 | 使用 `std::sync::OnceLock` (Rust 1.70+) |
| 错误处理细化 | 中 | `conpty_supported()` 返回具体错误原因 |
| 文档完善 | 中 | 为 `RawConPty` 添加安全使用说明 |

#### 6.3.2 功能增强

| 建议 | 优先级 | 说明 |
|------|--------|------|
| ConPTY 标志配置 | 低 | 允许调用方配置 `PSEUDOCONSOLE_PASSTHROUGH_MODE` |
| 进程组支持 | 中 | Windows 下实现类似 Unix 的进程组终止 |
| 更好的错误信息 | 中 | 在 `CreateProcessW` 失败时提供更多上下文 |

#### 6.3.3 测试覆盖

当前测试在 `src/tests.rs` 中，主要覆盖：
- Python REPL 基本功能
- 管道进程 stdin/stdout
- 进程终止

**建议增加**:
- Windows 专用的 ConPTY 尺寸调整测试
- 长命令行参数测试
- 特殊字符参数转义测试
- 大输出压力测试

### 6.4 上游同步建议

代码源自 WezTerm (MIT License)，当前有意的分歧：

| 位置 | 分歧 | 状态 |
|------|------|------|
| `mod.rs:78-83` | `TerminateProcess` 返回值处理 | Codex 已修复 Bug #13945 |
| `mod.rs:106-113` | `WinChildKiller::kill` 同样修复 | Codex 已修复 |

**建议**: 跟踪 WezTerm 上游更新，评估是否合并其他修复。

---

## 附录：关键常量与配置

```rust
// psuedocon.rs
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 1809
pub const PSEUDOCONSOLE_RESIZE_QUIRK: DWORD = 0x2;
pub const PSEUDOCONSOLE_PASSTHROUGH_MODE: DWORD = 0x8;

// procthreadattr.rs
const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;

// lib.rs
pub const DEFAULT_OUTPUT_BYTES_CAP: usize = 1024 * 1024;  // 1MB
```

---

## 附录：调试与日志

```rust
// psuedocon.rs 第 201-210 行
if res == 0 {
    let err = IoError::last_os_error();
    let msg = format!(
        "CreateProcessW `{:?}` in cwd `{:?}` failed: {}",
        cmd_os,
        cwd.as_ref().map(|c| OsString::from_wide(c)),
        err
    );
    log::error!("{msg}");  // 使用 log crate 记录错误
    bail!("{msg}");
}
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/utils/pty/src/win/*
