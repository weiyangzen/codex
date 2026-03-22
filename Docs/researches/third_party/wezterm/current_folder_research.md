# third_party/wezterm 目录研究报告

## 1. 场景与职责

### 1.1 目录定位

`third_party/wezterm` 是 Codex 项目的第三方依赖目录，用于存放从 WezTerm 项目（https://github.com/wezterm/wezterm）引入的代码的许可证文件。WezTerm 是一个用 Rust 编写的 GPU 加速跨平台终端模拟器，Codex 项目借用了其 Windows ConPTY（Pseudo Console）实现。

### 1.2 核心职责

该目录的核心职责是：

1. **许可证合规**：存放 WezTerm 项目的 MIT 许可证全文，确保代码使用的法律合规性
2. **代码溯源**：明确标识代码来源，便于后续维护和审计
3. **变更记录**：记录 Codex 项目对原始代码的修改（如 Bug #13945 修复）

### 1.3 在项目中的角色

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex Project                             │
├─────────────────────────────────────────────────────────────────┤
│  third_party/wezterm/                                           │
│  └── LICENSE          ← MIT 许可证（本目录唯一文件）              │
│                                                                 │
│  codex-rs/utils/pty/src/win/                                    │
│  ├── mod.rs           ← WinChild 实现（源自 WezTerm）             │
│  ├── conpty.rs        ← ConPtySystem 实现（源自 WezTerm）         │
│  ├── psuedocon.rs     ← PsuedoCon 封装（源自 WezTerm）            │
│  └── procthreadattr.rs← 进程属性管理（源自 WezTerm）              │
│                                                                 │
│  codex-rs/core/src/terminal.rs                                  │
│  └── WezTerm 终端检测支持                                       │
│                                                                 │
│  codex-rs/tui/src/notifications/mod.rs                          │
│  └── WezTerm OSC 9 通知支持                                     │
└─────────────────────────────────────────────────────────────────┘
```

## 2. 功能点目的

### 2.1 许可证管理

`third_party/wezterm/LICENSE` 文件包含完整的 MIT 许可证文本：

```
MIT License

Copyright (c) 2018-Present Wez Furlong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
```

**目的**：
- 满足 MIT 许可证的归属要求（Attribution）
- 为项目提供法律合规保障
- 明确代码原作者版权信息

### 2.2 代码来源标识

实际功能代码位于 `codex-rs/utils/pty/src/win/` 目录，这些文件头部均包含：

```rust
// This file is copied from https://github.com/wezterm/wezterm (MIT license).
// Copyright (c) 2018-Present Wez Furlong
// ... MIT 许可证声明 ...

// Local modifications:
// - Fix Codex bug #13945 in the Windows PTY kill path...
```

**目的**：
- 明确代码来源和许可证类型
- 记录本地修改历史
- 便于后续同步上游更新

## 3. 具体技术实现

### 3.1 WezTerm 代码在 Codex 中的使用

虽然 `third_party/wezterm` 目录仅包含许可证文件，但理解其关联的功能代码对完整理解该目录的作用至关重要。

#### 3.1.1 Windows PTY 实现架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Windows PTY 架构                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐    │
│  │   PtySystem  │────▶│  ConPtySystem │────▶│   PsuedoCon      │    │
│  │   (trait)    │     │  (impl)       │     │   (HPCON handle) │    │
│  └──────────────┘     └──────────────┘     └──────────────────┘    │
│         │                      │                      │             │
│         ▼                      ▼                      ▼             │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐    │
│  │  MasterPty   │     │ConPtyMasterPty│────▶│  ProcThreadAttr  │    │
│  │  (trait)     │     │  (impl)       │     │  (PTY attribute) │    │
│  └──────────────┘     └──────────────┘     └──────────────────┘    │
│         │                      │                                    │
│         ▼                      ▼                                    │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐    │
│  │   SlavePty   │     │ ConPtySlavePty│────▶│   WinChild       │    │
│  │   (trait)    │     │   (impl)      │     │ (Child process)  │    │
│  └──────────────┘     └──────────────┘     └──────────────────┘    │
│                                                                     │
│  底层 Windows API:                                                  │
│  - CreatePseudoConsole (kernel32.dll)                               │
│  - ResizePseudoConsole                                              │
│  - ClosePseudoConsole                                               │
│  - UpdateProcThreadAttribute (PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE)  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

#### 3.1.2 关键数据结构

**`PsuedoCon` 结构体**（`psuedocon.rs`）：
```rust
pub struct PsuedoCon {
    con: HPCON,  // Windows Pseudo Console 句柄
}

// 关键方法
impl PsuedoCon {
    pub fn new(size: COORD, input: FileDescriptor, output: FileDescriptor) -> Result<Self>
    pub fn resize(&self, size: COORD) -> Result<()>
    pub fn spawn_command(&self, cmd: CommandBuilder) -> anyhow::Result<WinChild>
}
```

**`WinChild` 结构体**（`mod.rs`）：
```rust
pub struct WinChild {
    proc: Mutex<OwnedHandle>,  // 进程句柄
}

// 实现 Child trait
impl Child for WinChild {
    fn try_wait(&mut self) -> IoResult<Option<ExitStatus>>
    fn wait(&mut self) -> IoResult<ExitStatus>
    fn process_id(&self) -> Option<u32>
}
```

**`ConPtySystem` 结构体**（`conpty.rs`）：
```rust
#[derive(Default)]
pub struct ConPtySystem {}

impl PtySystem for ConPtySystem {
    fn openpty(&self, size: PtySize) -> anyhow::Result<PtyPair>
}
```

#### 3.1.3 关键流程

**PTY 创建流程**：

```
1. spawn_pty_process() 调用
   ↓
2. platform_native_pty_system() 返回 ConPtySystem
   ↓
3. pty_system.openpty(size) 调用
   ↓
4. create_conpty_handles() 创建管道
   │   - Pipe::new() 创建 stdin/stdout 管道
   │   - PsuedoCon::new() 调用 Windows CreatePseudoConsole API
   ↓
5. 返回 PtyPair { master: ConPtyMasterPty, slave: ConPtySlavePty }
```

**进程创建流程**：

```
1. pair.slave.spawn_command(cmd) 调用
   ↓
2. PsuedoCon::spawn_command() 执行
   │   - 初始化 STARTUPINFOEXW 结构
   │   - 创建 ProcThreadAttributeList
   │   - 设置 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE 属性
   ↓
3. CreateProcessW 创建进程
   │   - EXTENDED_STARTUPINFO_PRESENT 标志
   │   - CREATE_UNICODE_ENVIRONMENT 标志
   ↓
4. 返回 WinChild 包装进程句柄
```

**进程终止流程**（Bug #13945 修复点）：

```rust
// codex-rs/utils/pty/src/win/mod.rs
fn do_kill(&mut self) -> IoResult<()> {
    let proc = self.proc.lock().unwrap().try_clone().unwrap();
    let res = unsafe { TerminateProcess(proc.as_raw_handle() as _, 1) };
    // Codex bug #13945: Win32 returns nonzero on success, so only `0` is an error.
    if res == 0 {
        Err(IoError::last_os_error())
    } else {
        Ok(())
    }
}
```

**重要修复说明**：
- Windows API `TerminateProcess` 返回非零值表示成功
- 原始 WezTerm 代码错误地将非零值视为失败
- 该 Bug 导致进程无法正确终止
- 修复于 2026-03-08 之前，上游 WezTerm 仍存在此问题

### 3.2 终端检测支持

Codex 项目还在终端检测模块中支持识别 WezTerm：

**`codex-rs/core/src/terminal.rs`**：

```rust
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TerminalName {
    // ... 其他终端
    /// WezTerm terminal emulator.
    WezTerm,
    // ...
}

// 检测逻辑
fn detect_terminal_info_from_env(env: &dyn Environment) -> TerminalInfo {
    // ...
    if env.has("WEZTERM_VERSION") {
        let version = env.var_non_empty("WEZTERM_VERSION");
        return TerminalInfo::from_name(TerminalName::WezTerm, version, multiplexer);
    }
    // ...
}

// TERM_PROGRAM 检测
fn terminal_name_from_term_program(value: &str) -> Option<TerminalName> {
    // ...
    match normalized.as_str() {
        // ...
        "wezterm" => Some(TerminalName::WezTerm),
        // ...
    }
}
```

### 3.3 桌面通知支持

**`codex-rs/tui/src/notifications/mod.rs`**：

```rust
fn supports_osc9() -> bool {
    // ...
    // WezTerm 支持 OSC 9 通知协议
    if matches!(
        env::var("TERM_PROGRAM").ok().as_deref(),
        Some("WezTerm" | "ghostty")
    ) {
        return true;
    }
    // TERM-based hints cover kitty/wezterm setups without TERM_PROGRAM.
    matches!(
        env::var("TERM").ok().as_deref(),
        Some("xterm-kitty" | "wezterm" | "wezterm-mux")
    )
}
```

## 4. 关键代码路径与文件引用

### 4.1 目录结构

```
third_party/wezterm/
└── LICENSE                 # MIT 许可证文件（21 行）
```

### 4.2 关联代码文件

| 文件路径 | 来源 | 说明 |
|---------|------|------|
| `third_party/wezterm/LICENSE` | WezTerm (MIT) | 许可证文件 |
| `codex-rs/utils/pty/src/win/mod.rs` | WezTerm (MIT) + 修改 | WinChild 实现，含 Bug #13945 修复 |
| `codex-rs/utils/pty/src/win/conpty.rs` | WezTerm (MIT) | ConPtySystem 实现 |
| `codex-rs/utils/pty/src/win/psuedocon.rs` | WezTerm (MIT) | PsuedoCon 封装 |
| `codex-rs/utils/pty/src/win/procthreadattr.rs` | WezTerm (MIT) | 进程线程属性列表 |
| `codex-rs/core/src/terminal.rs` | Codex 原创 | 终端检测，支持 WezTerm |
| `codex-rs/core/src/terminal_tests.rs` | Codex 原创 | 含 WezTerm 检测测试 |
| `codex-rs/tui/src/notifications/mod.rs` | Codex 原创 | OSC 9 通知支持 WezTerm |
| `codex-rs/tui/src/chatwidget.rs` | Codex 原创 | 键盘绑定处理 WezTerm |

### 4.3 代码引用链

```
third_party/wezterm/LICENSE
    │
    ▼（许可证合规）
codex-rs/utils/pty/src/win/*.rs
    │
    ▼（功能调用）
codex-rs/utils/pty/src/pty.rs
    │   - spawn_process()
    │   - platform_native_pty_system()
    │
    ▼
codex-rs/utils/pty/src/lib.rs
    │   - pub use pty::spawn_process
    │   - pub use win::conpty::RawConPty
    │
    ▼
其他使用 PTY 的模块
```

## 5. 依赖与外部交互

### 5.1 外部依赖

**Windows API 依赖**（通过 `winapi` crate）：

| API | 用途 | 所在文件 |
|-----|------|---------|
| `CreatePseudoConsole` | 创建伪终端 | `psuedocon.rs` |
| `ResizePseudoConsole` | 调整终端大小 | `psuedocon.rs` |
| `ClosePseudoConsole` | 关闭伪终端 | `psuedocon.rs` |
| `CreateProcessW` | 创建进程 | `psuedocon.rs` |
| `TerminateProcess` | 终止进程 | `mod.rs` |
| `GetExitCodeProcess` | 获取退出码 | `mod.rs` |
| `WaitForSingleObject` | 等待进程 | `mod.rs` |
| `UpdateProcThreadAttribute` | 设置 PTY 属性 | `procthreadattr.rs` |
| `InitializeProcThreadAttributeList` | 初始化属性列表 | `procthreadattr.rs` |

**Rust crate 依赖**：

| Crate | 用途 |
|-------|------|
| `winapi` | Windows API 绑定 |
| `filedescriptor` | 文件描述符抽象 |
| `portable-pty` | PTY trait 定义 |
| `shared_library` | 动态库加载（用于 ConPTY 函数） |
| `lazy_static` | 静态初始化 |
| `anyhow` | 错误处理 |

### 5.2 系统要求

**最低 Windows 版本**：Windows 10 October 2018 Update (Build 17763)

```rust
// psuedocon.rs
const MIN_CONPTY_BUILD: u32 = 17_763;

pub fn conpty_supported() -> bool {
    windows_build_number().is_some_and(|build| build >= MIN_CONPTY_BUILD)
}
```

**动态库加载**：
- 首选 `conpty.dll`（如果存在）
- 回退 `kernel32.dll`
- 始终需要 `ntdll.dll` 用于版本检测

### 5.3 与上游 WezTerm 的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    WezTerm (upstream)                        │
│  https://github.com/wezterm/wezterm                         │
│                                                              │
│  pty/src/windows/                                            │
│  ├── mod.rs                                                  │
│  ├── conpty.rs                                               │
│  ├── psuedocon.rs                                            │
│  └── procthreadattr.rs                                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ 复制 (MIT License)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Codex Project                             │
│                                                              │
│  codex-rs/utils/pty/src/win/                                 │
│  ├── mod.rs          ← Bug #13945 修复                      │
│  ├── conpty.rs       ← 无修改                               │
│  ├── psuedocon.rs    ← 无修改                               │
│  └── procthreadattr.rs ← 无修改                             │
│                                                              │
│  third_party/wezterm/LICENSE  ← 许可证文件                  │
└─────────────────────────────────────────────────────────────┘
```

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 上游同步风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 代码分歧 | Codex 对 `mod.rs` 有本地修复，与上游不同步 | 文档记录修改，定期评估上游更新 |
| Bug 传播 | 上游 WezTerm 的 Bug 可能存在于其他文件 | 定期审查上游 issue 和 PR |
| 许可证变更 | 上游许可证变更风险（MIT 较低） | 监控上游许可证变化 |

#### 6.1.2 技术风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| Windows 版本依赖 | 需要 Windows 10 Build 17763+ | 运行时检测，优雅降级 |
| API 稳定性 | ConPTY API 相对较新，可能有变化 | 跟随 Windows SDK 更新 |
| 进程终止 Bug | 原始代码的进程终止逻辑错误 | 已修复（Bug #13945） |

### 6.2 边界条件

#### 6.2.1 平台边界

```rust
// lib.rs
#[cfg(windows)]
mod win;

// 仅在 Windows 平台编译 WezTerm 代码
#[cfg(windows)]
pub use win::conpty::RawConPty;
```

#### 6.2.2 功能边界

- **不支持 Windows 7/8**：ConPTY 需要 Windows 10 17763+
- **不支持 Wine/兼容层**：需要原生 Windows ConPTY API
- **进程终止行为**：修复后的行为与 Unix 信号不同

### 6.3 改进建议

#### 6.3.1 短期改进

1. **上游反馈**
   - 将 Bug #13945 修复反馈给 WezTerm 项目
   - 提交 PR 到上游，减少代码分歧

2. **文档完善**
   - 在 `third_party/wezterm/` 添加 README.md 说明代码使用情况
   - 记录具体版本/Commit 的代码快照

3. **测试增强**
   - 添加 Windows PTY 集成测试
   - 测试进程终止边界情况

#### 6.3.2 中期改进

1. **依赖管理**
   - 考虑使用 `cargo vendor` 或 git submodule 管理第三方代码
   - 自动化上游同步流程

2. **功能扩展**
   - 评估 Windows Terminal 的 ConPTY 实现作为备选
   - 支持更多 Windows 终端特性（如 24-bit 颜色、鼠标事件）

#### 6.3.3 长期考虑

1. **架构演进**
   - 关注 `portable-pty` crate 的发展，可能无需直接维护 ConPTY 代码
   - 评估 Windows 官方 PTY API 的稳定性

2. **许可证合规自动化**
   - 使用工具（如 `cargo-deny`）自动检查第三方许可证
   - 生成 SBOM（软件物料清单）

### 6.4 监控要点

| 监控项 | 频率 | 责任人 |
|--------|------|--------|
| WezTerm 上游更新 | 每月 | 维护团队 |
| Windows API 变更 | 每季度 | 维护团队 |
| 安全公告（CVE） | 实时 | 安全团队 |
| 许可证变更 | 每季度 | 法务/合规 |

---

## 附录

### A. 相关链接

- WezTerm 项目：https://github.com/wezterm/wezterm
- Windows ConPTY 文档：https://learn.microsoft.com/en-us/windows/console/pseudoconsoles
- MIT 许可证：https://opensource.org/licenses/MIT

### B. 变更历史

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-03-08 前 | 引入 WezTerm ConPTY 代码 | Codex 团队 |
| 2026-03-08 前 | 修复 Bug #13945（进程终止） | Codex 团队 |
| 2026-03-22 | 编写本研究报告 | Kimi Code CLI |

### C. 术语表

| 术语 | 说明 |
|------|------|
| ConPTY | Windows Pseudo Console，Windows 10 引入的伪终端 API |
| PTY | Pseudo Terminal，伪终端，用于模拟终端设备 |
| HPCON | Pseudo Console 句柄类型 |
| OSC 9 | Operating System Command 9，终端通知协议 |
| MIT License | 宽松的开源软件许可证 |
