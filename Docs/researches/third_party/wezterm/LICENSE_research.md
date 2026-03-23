# third_party/wezterm/LICENSE 研究文档

## 场景与职责

`third_party/wezterm/LICENSE` 是 Codex 项目中用于声明第三方代码许可协议的关键文件。该文件包含 WezTerm 项目的 MIT 许可证全文，用于合法合规地引用和修改 WezTerm 项目中的 Windows ConPTY（Pseudo Console）实现代码。

### 在项目中的定位

```
third_party/
├── meriyah/           # JavaScript 解析器许可证
└── wezterm/
    └── LICENSE        # WezTerm MIT 许可证（本文件）
```

该许可证文件与以下代码文件形成完整的合规引用关系：
- `codex-rs/utils/pty/src/win/mod.rs` - Windows PTY 主模块
- `codex-rs/utils/pty/src/win/conpty.rs` - ConPTY 系统实现
- `codex-rs/utils/pty/src/win/procthreadattr.rs` - 进程线程属性管理
- `codex-rs/utils/pty/src/win/psuedocon.rs` - 伪控制台底层封装

### 核心职责

1. **法律合规**: 满足 MIT 许可证要求，在项目中保留原始版权声明和许可文本
2. **代码溯源**: 明确标识代码来源为 https://github.com/wezterm/wezterm
3. **权利声明**: 声明代码使用、修改、分发的权利和限制条件
4. **责任免除**: 明确软件按"原样"提供，不承担任何责任

---

## 功能点目的

### MIT 许可证的核心条款

该许可证文件包含以下关键条款：

| 条款 | 内容 | 对 Codex 项目的影响 |
|------|------|---------------------|
| **授权范围** | 免费授予任何人软件副本 | Codex 可自由使用 WezTerm 代码 |
| **权利清单** | 使用、复制、修改、合并、发布、分发、再许可、销售 | 支持 Codex 对代码的修改和再分发 |
| **条件** | 必须在所有副本或实质性部分中包含版权声明和许可声明 | 每个引用文件头部必须保留版权声明 |
| **免责声明** | 按"原样"提供，无任何形式的担保 | 用户自行承担使用风险 |
| **责任限制** | 不对任何索赔、损害或其他责任负责 | 保护原作者和版权持有者 |

### 代码使用场景

Codex 项目使用 WezTerm 代码的具体场景：

1. **Windows PTY 支持**: 在 Windows 平台上提供伪终端功能，使 Codex 能够运行交互式命令（如 shell、REPL）
2. **ConPTY API 封装**: 封装 Windows 10 版本 1809 引入的 ConPTY API（`CreatePseudoConsole`、`ResizePseudoConsole`、`ClosePseudoConsole`）
3. **进程管理**: 通过 `ProcThreadAttributeList` 设置伪控制台属性，创建附加到 PTY 的进程

---

## 具体技术实现

### 许可证文本结构

```
MIT License

Copyright (c) 2018-Present Wez Furlong

Permission is hereby granted...  [权限授予条款]

The above copyright notice...    [条件条款]

THE SOFTWARE IS PROVIDED "AS IS"... [免责声明]
```

### 代码引用实现

每个引用 WezTerm 代码的文件头部都包含以下标准版权声明：

```rust
// This file is copied from https://github.com/wezterm/wezterm (MIT license).
// Copyright (c) 2018-Present Wez Furlong
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
```

### 依赖的 WezTerm 技术实现

#### 1. ConPTY 系统 (`conpty.rs`)

```rust
// 关键数据结构
pub struct ConPtySystem {}

pub struct RawConPty {
    con: PsuedoCon,
    input_write: FileDescriptor,
    output_read: FileDescriptor,
}

pub struct ConPtyMasterPty {
    inner: Arc<Mutex<Inner>>,
}

pub struct ConPtySlavePty {
    inner: Arc<Mutex<Inner>>,
}

struct Inner {
    con: PsuedoCon,
    readable: FileDescriptor,
    writable: Option<FileDescriptor>,
    size: PtySize,
}
```

#### 2. 伪控制台封装 (`psuedocon.rs`)

```rust
pub type HPCON = HANDLE;

pub struct PsuedoCon {
    con: HPCON,
}

// 关键 Windows API 动态加载
shared_library!(ConPtyFuncs,
    pub fn CreatePseudoConsole(
        size: COORD,
        hInput: HANDLE,
        hOutput: HANDLE,
        flags: DWORD,
        hpc: *mut HPCON
    ) -> HRESULT,
    pub fn ResizePseudoConsole(hpc: HPCON, size: COORD) -> HRESULT,
    pub fn ClosePseudoConsole(hpc: HPCON),
);

// Windows 版本检测
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 版本 1809
```

#### 3. 进程线程属性 (`procthreadattr.rs`)

```rust
const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x00020016;

pub struct ProcThreadAttributeList {
    data: Vec<u8>,
}

impl ProcThreadAttributeList {
    pub fn with_capacity(num_attributes: DWORD) -> Result<Self, Error>
    pub fn set_pty(&mut self, con: HPCON) -> Result<(), Error>
}
```

#### 4. 子进程管理 (`mod.rs`)

```rust
pub struct WinChild {
    proc: Mutex<OwnedHandle>,
}

pub struct WinChildKiller {
    proc: OwnedHandle,
}

// 关键修改（Codex bug #13945）:
// 修复了 TerminateProcess 返回值判断错误
// Win32 返回非零值表示成功，0 表示失败
```

---

## 关键代码路径与文件引用

### 直接引用 WezTerm 代码的文件

| 文件路径 | 代码行数 | 主要职责 |
|----------|----------|----------|
| `codex-rs/utils/pty/src/win/mod.rs` | 178 | WinChild/WinChildKiller 实现，进程生命周期管理 |
| `codex-rs/utils/pty/src/win/conpty.rs` | 190 | ConPtySystem 实现，PTY 系统接口 |
| `codex-rs/utils/pty/src/win/procthreadattr.rs` | 91 | ProcThreadAttributeList，进程属性管理 |
| `codex-rs/utils/pty/src/win/psuedocon.rs` | 369 | PsuedoCon，伪控制台底层封装 |

### 调用链分析

```
┌─────────────────────────────────────────────────────────────────┐
│                        Codex 应用层                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   TUI / CLI     │  │  App Server     │  │  Core Agent     │  │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
└───────────┼────────────────────┼────────────────────┼───────────┘
            │                    │                    │
            ▼                    ▼                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                    codex-utils-pty crate                         │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  pty.rs (平台抽象层)                                         │ │
│  │  ├── spawn_process() ───────────────────┐                   │ │
│  │  ├── conpty_supported()                 │                   │ │
│  │  └── platform_native_pty_system()       ▼                   │ │
│  │                              ┌─────────────────────┐        │ │
│  │                              │ win/ConPtySystem    │        │ │
│  │                              │ (WezTerm 代码)      │        │ │
│  └──────────────────────────────┴─────────────────────┘────────┘ │
└─────────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Windows ConPTY API                           │
│  CreatePseudoConsole / ResizePseudoConsole / ClosePseudoConsole │
└─────────────────────────────────────────────────────────────────┘
```

### 构建系统引用

在 Bazel 构建系统中，`wezterm_license` 被声明为依赖：

```python
# codex-rs/utils/pty/BUILD.bazel (概念性)
codex_rust_crate(
    name = "pty",
    crate_name = "codex_utils_pty",
    # Windows 平台依赖 wezterm_license
    deps = select({
        "@platforms//os:windows": ["//third_party:wezterm_license"],
        "//conditions:default": [],
    }),
)
```

---

## 依赖与外部交互

### 外部依赖

#### 1. WezTerm 项目
- **仓库**: https://github.com/wezterm/wezterm
- **作者**: Wez Furlong
- **许可证**: MIT
- **代码用途**: Windows ConPTY 实现

#### 2. Windows API (通过 winapi crate)

```rust
// psuedocon.rs 使用的 Windows API
winapi::um::wincon::{COORD}
winapi::um::handleapi::{CloseHandle, INVALID_HANDLE_VALUE}
winapi::um::processthreadsapi::{CreateProcessW, ...}
winapi::um::winbase::{CREATE_UNICODE_ENVIRONMENT, EXTENDED_STARTUPINFO_PRESENT, ...}

// mod.rs 使用的 Windows API
winapi::um::processthreadsapi::{GetExitCodeProcess, TerminateProcess, ...}
winapi::um::synchapi::{WaitForSingleObject}
```

#### 3. Rust 依赖 crate

| Crate | 用途 |
|-------|------|
| `filedescriptor` | 文件描述符抽象 (`FileDescriptor`, `OwnedHandle`, `Pipe`) |
| `portable-pty` | 跨平台 PTY trait 定义 (`PtySystem`, `MasterPty`, `SlavePty`, `Child`) |
| `shared_library` | 动态加载 DLL (`shared_library!` 宏) |
| `winapi` | Windows API 绑定 |
| `lazy_static` | 静态初始化 (`CONPTY` 函数表) |

### 内部调用方

| 调用方 | 用途 |
|--------|------|
| `codex-rs/utils/pty/src/pty.rs` | 平台抽象，统一 PTY 接口 |
| `codex-rs/windows-sandbox-rs/src/conpty/mod.rs` | Windows 沙箱 ConPTY 支持 |
| `codex-rs/core/src/terminal.rs` | 终端检测（识别 WezTerm 终端） |

### 终端检测关联

Codex 在终端检测逻辑中识别 WezTerm 终端：

```rust
// codex-rs/core/src/terminal.rs
fn parse_terminal_name(value: &str) -> Option<TerminalName> {
    match normalized.as_str() {
        // ...
        "wezterm" => Some(TerminalName::WezTerm),
        // ...
    }
}

// 通过环境变量检测
// - WEZTERM_VERSION
// - TERM_PROGRAM=WezTerm
// - TERM=wezterm | wezterm-mux
```

---

## 风险、边界与改进建议

### 风险分析

#### 1. 许可证合规风险

| 风险等级 | 描述 | 缓解措施 |
|----------|------|----------|
| 低 | MIT 许可证要求保留版权声明 | 每个文件头部已包含完整版权声明 |
| 低 | 修改代码需注明变更 | `mod.rs` 中已记录 Codex bug #13945 修复 |

#### 2. 技术风险

| 风险等级 | 描述 | 影响 |
|----------|------|------|
| 中 | Windows 版本依赖（需 Build 17763+） | 旧版 Windows 无法使用 ConPTY 功能 |
| 中 | 动态加载 kernel32.dll/conpty.dll | DLL 不存在时会导致运行时错误 |
| 低 | 与上游 WezTerm 代码分叉 | 需要手动同步上游修复 |

#### 3. 已知 Bug 修复

**Codex bug #13945** (已修复):
```rust
// 修复前（错误）:
if res != 0 { Err(...) } else { Ok(()) }

// 修复后（正确）:
if res == 0 { Err(...) } else { Ok(()) }
// Win32 TerminateProcess 返回非零表示成功
```

### 边界条件

1. **Windows 版本边界**: 
   - 最低要求: Windows 10 Build 17763 (版本 1809)
   - 检测函数: `conpty_supported()`

2. **功能边界**:
   - 仅 Windows 平台使用 WezTerm 代码
   - Unix 平台使用 `portable-pty` 的原生实现

3. **API 边界**:
   - 通过 `RawConPty` 封装提供有限接口
   - 内部使用 `ManuallyDrop` 避免重复释放句柄

### 改进建议

#### 1. 文档改进

```markdown
建议添加 third_party/wezterm/README.md：
- 说明代码来源和版本
- 列出本地修改记录
- 提供同步上游代码的流程
```

#### 2. 代码同步机制

```rust
// 建议在文件头部添加版本标识
// WezTerm source: commit abc123
git hash of the original wezterm source
```

#### 3. 测试覆盖

| 测试类型 | 建议 |
|----------|------|
| 单元测试 | 添加 Windows 版本检测测试 |
| 集成测试 | 验证 ConPTY 创建和进程生命周期 |
| 兼容性测试 | 在不同 Windows 版本上验证 |

#### 4. 依赖管理

```toml
# 建议：明确 shared_library 和 filedescriptor 的最低版本
[target.'cfg(windows)'.dependencies]
filedescriptor = "0.8.3"  # 当前版本
shared_library = "0.1.9"  # 当前版本
```

#### 5. 上游贡献

考虑将 Codex bug #13945 的修复回馈给 WezTerm 上游：
- 该 bug 在 WezTerm 源代码中仍然存在（截至 2026-03-08）
- 修复简单且明确，适合作为 PR 提交

---

## 附录

### 完整文件引用清单

```
third_party/wezterm/LICENSE
├── 被引用者:
│   ├── codex-rs/utils/pty/src/win/mod.rs (178 lines)
│   ├── codex-rs/utils/pty/src/win/conpty.rs (190 lines)
│   ├── codex-rs/utils/pty/src/win/procthreadattr.rs (91 lines)
│   └── codex-rs/utils/pty/src/win/psuedocon.rs (369 lines)
│
├── 调用方:
│   ├── codex-rs/utils/pty/src/pty.rs
│   ├── codex-rs/utils/pty/src/lib.rs
│   ├── codex-rs/windows-sandbox-rs/src/conpty/mod.rs
│   └── codex-rs/core/src/terminal.rs (检测)
│
└── 构建系统:
    └── codex-rs/utils/pty/BUILD.bazel (通过 wezterm_license 依赖)
```

### 许可证全文

```
MIT License

Copyright (c) 2018-Present Wez Furlong

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

*文档生成时间: 2026-03-24*
*研究范围: third_party/wezterm/LICENSE 及其关联代码*
