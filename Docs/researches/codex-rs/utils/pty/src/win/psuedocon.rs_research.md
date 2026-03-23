# psuedocon.rs 研究文档

## 文件信息
- **路径**: `codex-rs/utils/pty/src/win/psuedocon.rs`
- **大小**: 11,691 bytes
- **来源**: 基于 WezTerm (MIT License) 的 vendored 代码

---

## 一、场景与职责

### 1.1 核心定位
`psuedocon.rs` 是 Windows ConPTY (Console Pseudo Terminal) 的 **底层核心实现**，直接封装 Windows 10+ 引入的 ConPTY API。它是整个 Windows PTY 栈的最底层，负责与操作系统内核直接交互。

### 1.2 主要职责
1. **ConPTY API 动态加载**: 运行时加载 `kernel32.dll` 或 `conpty.dll` 中的 ConPTY 函数
2. **伪控制台生命周期**: 创建、调整大小、关闭伪控制台
3. **进程创建**: 将新进程附加到伪控制台
4. **平台兼容性检测**: 检查 Windows 版本是否支持 ConPTY
5. **命令行构建**: 处理 Windows 特有的命令行参数引用规则

### 1.3 在架构中的位置
```
┌─────────────────────────────────────────────────────────────┐
│                    Windows PTY 架构                          │
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │  pty.rs     │───▶│ conpty.rs   │───▶│  psuedocon.rs   │  │
│  │ (跨平台)    │    │ (PtySystem) │    │ (底层 WinAPI)   │  │
│  └─────────────┘    └─────────────┘    └─────────────────┘  │
│                                               │             │
│                                               ▼             │
│                                        ┌─────────────┐      │
│                                        │ kernel32.dll│      │
│                                        │ conpty.dll  │      │
│                                        └─────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 PsuedoCon - 伪控制台封装
```rust
pub struct PsuedoCon {
    con: HPCON,  // 伪控制台句柄
}
```

**核心功能**:
- **创建**: `PsuedoCon::new()` - 调用 `CreatePseudoConsole`
- **调整大小**: `resize()` - 调用 `ResizePseudoConsole`
- **启动进程**: `spawn_command()` - 创建附加到 ConPTY 的进程
- **原始句柄**: `raw_handle()` - 暴露 HPCON 供外部使用

### 2.2 ConPTY 函数动态加载
```rust
shared_library!(ConPtyFuncs,
    pub fn CreatePseudoConsole(size: COORD, hInput: HANDLE, hOutput: HANDLE, 
                               flags: DWORD, hpc: *mut HPCON) -> HRESULT,
    pub fn ResizePseudoConsole(hpc: HPCON, size: COORD) -> HRESULT,
    pub fn ClosePseudoConsole(hpc: HPCON),
);
```

**设计目的**:
- Windows 10 1809+ 才支持 ConPTY，需要运行时检测
- 支持 `conpty.dll` 旁加载（开发/测试场景）
- 优雅降级：不支持时返回错误而非崩溃

### 2.3 平台兼容性检测
```rust
pub fn conpty_supported() -> bool {
    windows_build_number().is_some_and(|build| build >= MIN_CONPTY_BUILD)
}
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 版本 1809
```

### 2.4 命令行处理
```rust
fn build_cmdline(cmd: &CommandBuilder) -> anyhow::Result<(Vec<u16>, Vec<u16>)>
fn search_path(cmd: &CommandBuilder, exe: &OsStr) -> OsString
fn append_quoted(arg: &OsStr, cmdline: &mut Vec<u16>)
```

**Windows 命令行特殊性**:
- 需要处理 `ComSpec` 环境变量（默认 shell）
- 参数引用规则复杂（空格、制表符、引号、反斜杠）
- 支持 `PATHEXT` 扩展名搜索

---

## 三、具体技术实现

### 3.1 关键流程

#### 3.1.1 创建伪控制台
```rust
pub fn new(size: COORD, input: FileDescriptor, output: FileDescriptor) 
    -> Result<Self, Error> 
{
    let mut con: HPCON = INVALID_HANDLE_VALUE;
    let result = unsafe {
        (CONPTY.CreatePseudoConsole)(
            size,
            input.as_raw_handle() as _,
            output.as_raw_handle() as _,
            PSEUDOCONSOLE_RESIZE_QUIRK,  // 0x2
            &mut con,
        )
    };
    ensure!(result == S_OK, "failed to create psuedo console: HRESULT {result}");
    Ok(Self { con })
}
```

流程图:
```
输入: size (COORD), input pipe, output pipe
           │
           ▼
    CreatePseudoConsole
           │
           ▼
    result == S_OK?
        │
    Yes ──▶ 返回 PsuedoCon { con }
        │
    No ───▶ 返回错误 (HRESULT)
```

**关键标志**:
```rust
pub const PSEUDOCONSOLE_RESIZE_QUIRK: DWORD = 0x2;
```
- 启用调整大小的特殊行为
- 解决某些控制台应用程序的大小调整问题

#### 3.1.2 启动带 ConPTY 的进程
```rust
pub fn spawn_command(&self, cmd: CommandBuilder) -> anyhow::Result<WinChild> {
    // 1. 准备 STARTUPINFOEXW
    let mut si: STARTUPINFOEXW = unsafe { mem::zeroed() };
    si.StartupInfo.cb = mem::size_of::<STARTUPINFOEXW>() as u32;
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = INVALID_HANDLE_VALUE;
    si.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
    si.StartupInfo.hStdError = INVALID_HANDLE_VALUE;

    // 2. 创建并设置属性列表
    let mut attrs = ProcThreadAttributeList::with_capacity(1)?;
    attrs.set_pty(self.con)?;
    si.lpAttributeList = attrs.as_mut_ptr();

    // 3. 构建命令行和环境
    let (mut exe, mut cmdline) = build_cmdline(&cmd)?;
    let cwd = resolve_current_directory(&cmd);
    let mut env_block = build_environment_block(&cmd);

    // 4. 创建进程
    let res = unsafe {
        CreateProcessW(
            exe.as_mut_ptr(),
            cmdline.as_mut_ptr(),
            ptr::null_mut(),
            ptr::null_mut(),
            0,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            env_block.as_mut_ptr() as *mut _,
            cwd.as_ref().map_or(ptr::null(), Vec::as_ptr),
            &mut si.StartupInfo,
            &mut pi,
        )
    };
    // ... 错误处理和 WinChild 创建
}
```

#### 3.1.3 命令行参数引用 (append_quoted)
这是 Windows 命令行解析的复杂部分，遵循 Microsoft C Runtime 规则：

```rust
fn append_quoted(arg: &OsStr, cmdline: &mut Vec<u16>) {
    // 如果参数不含特殊字符，直接追加
    if !arg.is_empty() && !arg.encode_wide().any(|c| {
        c == ' ' as u16 || c == '\t' as u16 || c == '\n' as u16 
            || c == '\x0b' as u16 || c == '"' as u16
    }) {
        cmdline.extend(arg.encode_wide());
        return;
    }
    
    cmdline.push('"' as u16);
    
    // 复杂的反斜杠和引号处理
    let arg: Vec<_> = arg.encode_wide().collect();
    let mut i = 0;
    while i < arg.len() {
        let mut num_backslashes = 0;
        while i < arg.len() && arg[i] == '\\' as u16 {
            i += 1;
            num_backslashes += 1;
        }
        
        if i == arg.len() {
            // 参数末尾的反斜杠需要双倍
            for _ in 0..num_backslashes * 2 {
                cmdline.push('\\' as u16);
            }
            break;
        } else if arg[i] == b'"' as u16 {
            // 反斜杠+引号：反斜杠双倍+转义引号
            for _ in 0..num_backslashes * 2 + 1 {
                cmdline.push('\\' as u16);
            }
            cmdline.push(arg[i]);
        } else {
            // 普通字符前的反斜杠原样保留
            for _ in 0..num_backslashes {
                cmdline.push('\\' as u16);
            }
            cmdline.push(arg[i]);
        }
        i += 1;
    }
    cmdline.push('"' as u16);
}
```

**引用规则**:
| 场景 | 处理方式 |
|------|----------|
| 无特殊字符 | 原样输出 |
| 包含空格/制表符/换行/引号 | 整体用双引号包裹 |
| 末尾反斜杠 | 双倍（`\\` → `\\\\`） |
| 反斜杠+引号 | 反斜杠双倍+转义引号（`\\"` → `\\\\\"`） |

### 3.2 数据结构

#### 3.2.1 HPCON 类型
```rust
pub type HPCON = HANDLE;  // 伪控制台句柄类型别名
```

#### 3.2.2 ConPtyFuncs - 动态加载的函数表
```rust
shared_library!(ConPtyFuncs,
    pub fn CreatePseudoConsole(...) -> HRESULT,
    pub fn ResizePseudoConsole(...) -> HRESULT,
    pub fn ClosePseudoConsole(...),
);
```

#### 3.2.3 版本信息
```rust
shared_library!(Ntdll,
    pub fn RtlGetVersion(version_info: *mut OSVERSIONINFOW) -> NTSTATUS,
);
```
- 使用 `RtlGetVersion` 而非 `GetVersionEx`（后者被弃用且可能返回兼容版本）

### 3.3 关键代码路径

| 操作 | 调用链 |
|------|--------|
| 创建 ConPTY | `PsuedoCon::new()` → `CreatePseudoConsole()` |
| 调整大小 | `PsuedoCon::resize()` → `ResizePseudoConsole()` |
| 关闭 | `Drop::drop()` → `ClosePseudoConsole()` |
| 启动进程 | `spawn_command()` → `CreateProcessW()` |
| 检查支持 | `conpty_supported()` → `RtlGetVersion()` |

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖
```rust
use super::WinChild;                                    // 子进程句柄
use crate::win::procthreadattr::ProcThreadAttributeList; // 进程属性
use filedescriptor::{FileDescriptor, OwnedHandle};      // 文件描述符
use lazy_static::lazy_static;                           // 全局初始化
use shared_library::shared_library;                     // DLL 加载宏
use portable_pty::cmdbuilder::CommandBuilder;           // 命令构建器
```

### 4.2 调用关系图
```
psuedocon.rs
    │
    ├─── uses ───▶ procthreadattr.rs (ProcThreadAttributeList)
    │
    ├─── uses ───▶ win/mod.rs (WinChild)
    │
    ├─── used by ───▶ conpty.rs
    │       │
    │       └─── PsuedoCon::new() / resize() / spawn_command()
    │
    └─── exports ───▶ conpty_supported() → lib.rs → 外部
```

### 4.3 Windows API 调用汇总

| API 函数 | 来源 | 用途 |
|----------|------|------|
| `CreatePseudoConsole` | kernel32.dll/conpty.dll | 创建伪控制台 |
| `ResizePseudoConsole` | kernel32.dll/conpty.dll | 调整大小 |
| `ClosePseudoConsole` | kernel32.dll/conpty.dll | 关闭 |
| `RtlGetVersion` | ntdll.dll | 获取 Windows 版本 |
| `CreateProcessW` | kernel32.dll | 创建进程 |
| `InitializeProcThreadAttributeList` | kernel32.dll | 初始化属性列表 |
| `UpdateProcThreadAttribute` | kernel32.dll | 设置 ConPTY 属性 |

---

## 五、依赖与外部交互

### 5.1 外部 Crates
| Crate | 用途 |
|-------|------|
| `portable-pty` | `CommandBuilder` - 跨平台命令构建 |
| `filedescriptor` | `FileDescriptor`, `OwnedHandle` |
| `lazy_static` | 全局 `CONPTY` 函数表延迟初始化 |
| `shared_library` | `shared_library!` 宏用于动态加载 DLL |
| `winapi` | Windows API 绑定 |
| `anyhow` | 错误处理 |
| `log` | 日志记录（`log::error!`） |

### 5.2 动态加载策略
```rust
fn load_conpty() -> ConPtyFuncs {
    // 优先尝试加载 conpty.dll（旁加载）
    if let Ok(sideloaded) = ConPtyFuncs::open(Path::new("conpty.dll")) {
        sideloaded
    } else {
        // 回退到系统 kernel32.dll
        ConPtyFuncs::open(Path::new("kernel32.dll")).expect(
            "this system does not support conpty..."
        )
    }
}

lazy_static! {
    static ref CONPTY: ConPtyFuncs = load_conpty();
}
```

### 5.3 平台要求
- **最低版本**: Windows 10 版本 1809 (Build 17763)
- **架构**: x64, x86, ARM64
- **DLL**: kernel32.dll (系统自带) 或 conpty.dll (旁加载)

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 动态加载失败
```rust
ConPtyFuncs::open(Path::new("kernel32.dll")).expect(
    "this system does not support conpty..."
)
```
- **风险**: 旧版 Windows 上会 panic
- **缓解**: `conpty_supported()` 应在调用前检查
- **改进**: 考虑返回 `Result` 而非 panic

#### 6.1.2 命令行注入风险
```rust
fn build_cmdline(cmd: &CommandBuilder) -> anyhow::Result<(Vec<u16>, Vec<u16>)>
```
- **风险**: 如果参数包含 `"` 或特殊序列，可能破坏命令行结构
- **缓解**: `append_quoted()` 实现了正确的转义逻辑
- **注意**: 依赖 Microsoft C Runtime 的解析规则

#### 6.1.3 路径搜索安全问题
```rust
fn search_path(cmd: &CommandBuilder, exe: &OsStr) -> OsString
```
- **风险**: 当前目录优先于 PATH 中的目录（Windows 传统行为）
- **缓解**: 使用 `CommandBuilder` 的完整路径或显式搜索

### 6.2 边界条件

#### 6.2.1 工作目录解析
```rust
fn resolve_current_directory(cmd: &CommandBuilder) -> Option<Vec<u16>> {
    let home = cmd.get_env("USERPROFILE")...;
    let cwd = cmd.get_env("cwd")...;
    let dir = cwd.or(home)?;
    // 处理相对路径...
}
```
- 优先使用 `CommandBuilder` 中设置的工作目录
- 回退到 `USERPROFILE` 环境变量
- 支持相对路径解析为绝对路径

#### 6.2.2 环境变量块构建
```rust
fn build_environment_block(cmd: &CommandBuilder) -> Vec<u16>
```
- 格式: `KEY=value\0KEY2=value2\0\0`
- Unicode 编码 (UTF-16)
- 需要 `CREATE_UNICODE_ENVIRONMENT` 标志

### 6.3 改进建议

#### 6.3.1 错误处理增强
```rust
// 当前: expect 可能导致 panic
// 建议: 返回 Result

pub fn ensure_conpty_available() -> Result<(), ConPtyError> {
    if !conpty_supported() {
        return Err(ConPtyError::UnsupportedWindowsVersion);
    }
    ConPtyFuncs::open(Path::new("kernel32.dll"))
        .map_err(|_| ConPtyError::DllLoadFailed)?;
    Ok(())
}
```

#### 6.3.2 日志和诊断
```rust
// 当前: 仅在 CreateProcessW 失败时记录
// 建议: 增加更多诊断日志

log::debug!("Creating ConPTY: {}x{}", size.X, size.Y);
log::debug!("Command line: {:?}", cmd_os);
log::debug!("Working directory: {:?}", cwd);
```

#### 6.3.3 测试覆盖
建议增加：
- 命令行引用边界测试（各种特殊字符组合）
- 路径搜索测试（含扩展名、不含扩展名）
- 环境变量块构建测试
- 不同 Windows 版本的兼容性测试

#### 6.3.4 文档完善
- 添加 ConPTY API 的详细说明
- 记录 Windows 版本要求
- 提供 `PSEUDOCONSOLE_RESIZE_QUIRK` 的行为说明

### 6.4 与上游 WezTerm 的关系
- 代码源自 WezTerm，但可能有本地修改
- 建议定期同步上游修复
- 考虑向上游贡献改进

---

## 七、相关文件索引

| 文件 | 关系 | 说明 |
|------|------|------|
| `win/mod.rs` | 父模块 | 导出 `conpty_supported`，使用 `WinChild` |
| `win/conpty.rs` | 调用方 | 使用 `PsuedoCon` 实现 `PtySystem` |
| `win/procthreadattr.rs` | 依赖 | `ProcThreadAttributeList` 用于进程创建 |
| `lib.rs` | 调用方 | 导出 `conpty_supported` |
| `Cargo.toml` | 配置 | 依赖 `shared_library`, `lazy_static`, `winapi` |

---

## 八、技术参考

### 8.1 Windows ConPTY API
- [CreatePseudoConsole](https://docs.microsoft.com/en-us/windows/console/createpseudoconsole)
- [ResizePseudoConsole](https://docs.microsoft.com/en-us/windows/console/resizepseudoconsole)
- [ClosePseudoConsole](https://docs.microsoft.com/en-us/windows/console/closepseudoconsole)

### 8.2 Windows 版本历史
- Build 17763: Windows 10 版本 1809 (October 2018 Update)
- ConPTY 首次在此版本中引入

### 8.3 命令行解析规则
- [Parsing C++ Command-Line Arguments](https://docs.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments)
- [Everyone quotes command line arguments the wrong way](https://docs.microsoft.com/en-us/archive/blogs/twistylittlepassagesallalike/everyone-quotes-command-line-arguments-the-wrong-way)
