# third_party 目录研究文档

## 概述

`third_party` 目录是 OpenAI Codex 项目中用于存放第三方依赖代码和资源的专用目录。该目录遵循开源软件许可合规的最佳实践，集中管理所有外部引入的代码，确保许可证声明清晰、可追溯。

---

## 一、场景与职责

### 1.1 目录定位

`third_party` 位于项目根目录 `/home/sansha/Github/codex/third_party/`，是 Codex 项目的第三方依赖代码托管中心。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **许可证合规** | 存储第三方代码的许可证文件，确保法律合规性 |
| **代码溯源** | 维护第三方代码的来源信息，便于审计和更新 |
| **依赖隔离** | 将外部代码与项目自有代码物理隔离 |
| **安全审查** | 为安全审计提供明确的第三方代码边界 |

### 1.3 使用场景

1. **JavaScript REPL 功能**：使用 Meriyah 解析器对 JS 代码进行 AST 分析
2. **Windows PTY 支持**：使用 WezTerm 的 ConPTY 实现，为 Windows 平台提供伪终端功能
3. **合规声明**：通过 NOTICE 文件向用户披露项目依赖的第三方组件

---

## 二、功能点目的

### 2.1 Meriyah - JavaScript 解析器

**项目信息**：
- **来源**：https://github.com/meriyah/meriyah
- **版本**：v7.0.0
- **许可证**：ISC License
- **版权**：Copyright (c) 2019 and later, KFlash and others

**功能目的**：

Meriyah 是一个高性能的 JavaScript/TypeScript 解析器，在 Codex 项目中用于 `js_repl` 工具的代码分析：

1. **AST 解析**：将用户输入的 JavaScript 代码解析为抽象语法树
2. **绑定收集**：识别代码中的变量声明（`const`/`let`/`var`/`function`/`class`）
3. **代码注入**：在关键位置注入标记函数，实现 REPL 状态持久化
4. **语法验证**：确保用户代码符合 ECMAScript 模块规范

**关键使用场景**（位于 `codex-rs/core/src/tools/js_repl/kernel.js`）：

```javascript
// 解析用户代码为 AST
const ast = meriyah.parseModule(code, {
  next: true,
  module: true,
  ranges: true,
  loc: false,
  disableWebCompat: true,
});

// 收集变量绑定
const currentBindings = collectBindings(ast);

// 二次解析用于代码注入
const instrumentedAst = meriyah.parseModule(writeInstrumentedCode, {
  next: true,
  module: true,
  ranges: true,
  loc: false,
  disableWebCompat: true,
});
```

### 2.2 WezTerm - Windows PTY 实现

**项目信息**：
- **来源**：https://github.com/wezterm/wezterm
- **许可证**：MIT License
- **版权**：Copyright (c) 2018-Present Wez Furlong

**功能目的**：

WezTerm 的 ConPTY 代码被移植到 Codex 项目，为 Windows 平台提供伪终端（Pseudo Terminal）支持：

1. **ConPTY 封装**：封装 Windows 10 1809+ 引入的 ConPTY API
2. **进程管理**：提供 `WinChild` 结构体管理子进程生命周期
3. **终端仿真**：支持终端大小调整、输入输出重定向
4. **跨平台兼容**：通过 `portable-pty` trait 与 Unix PTY 统一接口

**关键使用场景**（位于 `codex-rs/utils/pty/src/win/`）：

```rust
// 创建 ConPTY 系统
pub struct ConPtySystem {}

// 伪终端主端/从端实现
pub struct ConPtyMasterPty { ... }
pub struct ConPtySlavePty { ... }

// 进程句柄管理
pub struct WinChild {
    proc: Mutex<OwnedHandle>,
}
```

---

## 三、具体技术实现

### 3.1 Meriyah 集成技术细节

#### 3.1.1 文件分布

| 文件路径 | 说明 |
|----------|------|
| `third_party/meriyah/LICENSE` | ISC 许可证全文 |
| `codex-rs/core/src/tools/js_repl/meriyah.umd.min.js` | Meriyah v7.0.0 UMD 构建产物 |
| `codex-rs/core/src/tools/js_repl/kernel.js` | 内核代码，调用 Meriyah API |
| `codex-rs/core/src/tools/js_repl/mod.rs` | Rust 封装，加载 Meriyah 资源 |

#### 3.1.2 资源嵌入

在 Rust 代码中通过 `include_str!` 宏将 Meriyah 嵌入二进制：

```rust
// codex-rs/core/src/tools/js_repl/mod.rs
const MERIYAH_UMD: &str = include_str!("meriyah.umd.min.js");
```

#### 3.1.3 内核启动时写入文件系统

```rust
async fn write_kernel_script(&self) -> Result<PathBuf, std::io::Error> {
    let dir = self.tmp_dir.path();
    let kernel_path = dir.join("js_repl_kernel.js");
    let meriyah_path = dir.join("meriyah.umd.min.js");
    tokio::fs::write(&kernel_path, KERNEL_SOURCE).await?;
    tokio::fs::write(&meriyah_path, MERIYAH_UMD).await?;  // 写入 Meriyah
    Ok(kernel_path)
}
```

#### 3.1.4 Meriyah 解析配置

```javascript
const meriyah = await meriyahPromise;
const ast = meriyah.parseModule(code, {
  next: true,        // 支持 ES2020+ 特性
  module: true,      // 严格模块模式
  ranges: true,      // 包含节点范围信息（用于代码注入）
  loc: false,        // 不生成位置信息（减少内存占用）
  disableWebCompat: true,  // 禁用 Web 兼容性模式
});
```

### 3.2 WezTerm ConPTY 集成技术细节

#### 3.2.1 文件分布

| 文件路径 | 说明 |
|----------|------|
| `third_party/wezterm/LICENSE` | MIT 许可证全文 |
| `codex-rs/utils/pty/src/win/mod.rs` | WinChild 进程管理实现 |
| `codex-rs/utils/pty/src/win/conpty.rs` | ConPtySystem PTY 系统实现 |
| `codex-rs/utils/pty/src/win/procthreadattr.rs` | 进程线程属性列表封装 |
| `codex-rs/utils/pty/src/win/psuedocon.rs` | 伪控制台核心实现 |

#### 3.2.2 核心数据结构

**WinChild - 子进程句柄**：

```rust
#[derive(Debug)]
pub struct WinChild {
    proc: Mutex<OwnedHandle>,
}

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

**PsuedoCon - 伪控制台**：

```rust
pub struct PsuedoCon {
    con: HPCON,  // Windows HANDLE
}

impl PsuedoCon {
    pub fn new(size: COORD, input: FileDescriptor, output: FileDescriptor) -> Result<Self>;
    pub fn resize(&self, size: COORD) -> Result<()>;
    pub fn spawn_command(&self, cmd: CommandBuilder) -> anyhow::Result<WinChild>;
}
```

#### 3.2.3 Windows API 绑定

```rust
// 动态加载 kernel32.dll 中的 ConPTY 函数
shared_library!(ConPtyFuncs,
    pub fn CreatePseudoConsole(size: COORD, hInput: HANDLE, hOutput: HANDLE, flags: DWORD, hpc: *mut HPCON) -> HRESULT,
    pub fn ResizePseudoConsole(hpc: HPCON, size: COORD) -> HRESULT,
    pub fn ClosePseudoConsole(hpc: HPCON),
);

// 最低支持的 Windows 构建版本（Windows 10 1809）
const MIN_CONPTY_BUILD: u32 = 17_763;
```

#### 3.2.4 本地修改（Bug 修复）

Codex 项目对 WezTerm 代码进行了关键修复（Bug #13945）：

```rust
// 原始 WezTerm 代码错误地将非零返回值视为失败
// 修复：Win32 API 返回非零表示成功
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

### 3.3 许可证合规流程

#### 3.3.1 NOTICE 文件声明

项目根目录 `NOTICE` 文件包含第三方组件声明：

```
OpenAI Codex
Copyright 2025 OpenAI

This project includes code derived from [Ratatui](https://github.com/ratatui/ratatui), licensed under the MIT license.
Copyright (c) 2016-2022 Florian Dehau
Copyright (c) 2023-2025 The Ratatui Developers

This project includes Meriyah parser assets from [meriyah](https://github.com/meriyah/meriyah), licensed under the ISC license.
Copyright (c) 2019 and later, KFlash and others.
```

#### 3.3.2 源代码头部声明

每个 vendored 文件都包含完整的许可证头部：

```rust
// This file is copied from https://github.com/wezterm/wezterm (MIT license).
// Copyright (c) 2018-Present Wez Furlong
// Permission is hereby granted...
```

---

## 四、关键代码路径与文件引用

### 4.1 Meriyah 相关路径

```
third_party/
└── meriyah/
    └── LICENSE                          # ISC 许可证

codex-rs/core/src/tools/js_repl/
├── meriyah.umd.min.js                   # Meriyah v7.0.0 UMD 构建产物
│   └── 头部包含版本和许可证注释
├── kernel.js                            # Node.js 内核，调用 Meriyah API
│   ├── L19: const meriyahPromise = import("./meriyah.umd.min.js")
│   ├── L960-967: meriyah.parseModule() 首次解析
│   └── L991-997: meriyah.parseModule() 二次解析（代码注入后）
└── mod.rs                               # Rust 封装
    ├── L52: const MERIYAH_UMD: &str = include_str!("meriyah.umd.min.js")
    └── L1163: 启动内核时写入 meriyah.umd.min.js
```

### 4.2 WezTerm 相关路径

```
third_party/
└── wezterm/
    └── LICENSE                          # MIT 许可证

codex-rs/utils/pty/src/
├── lib.rs                               # 模块导出
│   └── L29-33: pub use win::conpty::RawConPty
└── win/
    ├── mod.rs                           # WinChild 实现
    │   ├── L3-27: 许可证声明和本地修改说明
    │   ├── L54-57: WinChild 结构体
    │   └── L75-84: do_kill() Bug 修复
    ├── conpty.rs                        # ConPtySystem 实现
    │   ├── L39-40: ConPtySystem 结构体
    │   └── L95-116: PtySystem trait 实现
    ├── procthreadattr.rs                # 进程线程属性
    │   └── L32-84: ProcThreadAttributeList 实现
    └── psuedocon.rs                     # 伪控制台核心
        ├── L69-79: ConPtyFuncs 动态加载
        ├── L119-130: PsuedoCon 结构体
        └── L137-153: CreatePseudoConsole 封装
```

### 4.3 文档引用

| 文档 | 路径 | 相关内容 |
|------|------|----------|
| js_repl.md | `docs/js_repl.md` | Meriyah 使用说明、更新流程 |
| NOTICE | `NOTICE` | 第三方组件许可证声明 |

---

## 五、依赖与外部交互

### 5.1 Meriyah 依赖关系

```
js_repl 功能
├── 运行时依赖
│   └── Node.js (>= 版本见 node-version.txt)
├── 解析依赖
│   └── meriyah.umd.min.js (v7.0.0)
└── 调用链
    mod.rs:execute() 
    → start_kernel()
    → write_kernel_script() [写入 meriyah.umd.min.js]
    → Node.js 子进程启动
    → kernel.js [通过 import() 加载 Meriyah]
    → buildModuleSource() [调用 meriyah.parseModule()]
```

### 5.2 WezTerm/ConPTY 依赖关系

```
Windows PTY 功能
├── 系统依赖
│   ├── Windows 10 版本 1809 或更高 (Build >= 17763)
│   ├── kernel32.dll (ConPTY API)
│   └── ntdll.dll (RtlGetVersion)
├── Rust 依赖
│   ├── winapi crate (Windows API 绑定)
│   ├── filedescriptor crate (句柄管理)
│   ├── portable-pty crate (PTY trait 定义)
│   └── shared_library crate (动态库加载)
└── 调用链
    pty.rs [Unix/Windows 统一接口]
    → win::conpty::ConPtySystem [Windows 特定实现]
    → PsuedoCon::new() [创建伪控制台]
    → CreatePseudoConsole() [Windows API]
```

### 5.3 平台支持矩阵

| 组件 | Linux | macOS | Windows |
|------|-------|-------|---------|
| Meriyah | ✅ | ✅ | ✅ |
| WezTerm ConPTY | N/A | N/A | ✅ (Build >= 17763) |

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Meriyah 相关风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **版本锁定** | 中 | 当前锁定 v7.0.0，需手动更新以获取安全修复 |
| **供应链攻击** | 中 | UMD 构建产物需验证完整性（无 checksum 机制） |
| **解析兼容性** | 低 | 新 JS 语法可能需要更新 Meriyah 版本 |

#### 6.1.2 WezTerm 相关风险

| 风险 | 严重程度 | 说明 |
|------|----------|------|
| **上游 Bug** | 中 | Bug #13945 表明上游可能存在其他未发现问题 |
| **Windows 版本依赖** | 低 | 不支持 Windows 10 1809 之前的版本 |
| **代码漂移** | 中 | 本地修改与上游分叉，增加维护成本 |

### 6.2 边界条件

#### 6.2.1 Meriyah 使用边界

- **仅支持模块模式**：`parseModule()` 强制使用，不支持脚本模式
- **范围信息依赖**：`ranges: true` 是代码注入功能的前提
- **内存占用**：大型文件解析时 AST 可能占用大量内存

#### 6.2.2 ConPTY 使用边界

- **Windows 版本检查**：`conpty_supported()` 在旧版本返回 false
- **句柄泄漏风险**：`PsuedoCon::drop()` 必须调用 `ClosePseudoConsole`
- **进程终止语义**：`TerminateProcess` 是强制终止，无优雅关闭

### 6.3 改进建议

#### 6.3.1 短期改进

1. **添加完整性校验**
   ```rust
   // 为 meriyah.umd.min.js 添加 SHA256 校验
   const MERIYAH_UMD_SHA256: &str = "...";
   ```

2. **自动化更新流程**
   - 创建脚本自动从 npm 拉取最新 Meriyah 版本
   - 集成到 CI/CD 进行版本更新检测

3. **上游 Bug 反馈**
   - 将 Bug #13945 修复反馈给 WezTerm 项目
   - 跟踪上游合并进度，减少本地维护负担

#### 6.3.2 中期改进

1. **依赖版本管理**
   - 引入 `third_party/manifest.json` 记录所有第三方组件版本
   - 包含来源 URL、许可证、校验和、更新日期

2. **安全扫描集成**
   - 对 `third_party` 目录进行定期 SCA（软件成分分析）扫描
   - 监控 CVE 数据库中的相关组件漏洞

3. **文档自动化**
   - 从源代码自动生成第三方组件清单
   - 集成到构建流程，确保 NOTICE 文件同步

#### 6.3.3 长期改进

1. **替代方案评估**
   - 评估 `swc` 作为 Meriyah 的替代（Rust 原生，性能更高）
   - 评估 Windows Terminal 的 ConPTY 实现作为 WezTerm 替代

2. **沙箱化第三方代码**
   - 对 Meriyah 解析在独立进程/线程中进行
   - 限制解析器资源使用（CPU 时间、内存）

---

## 七、附录

### 7.1 许可证全文

#### ISC License (Meriyah)

```
ISC License

Copyright (c) 2019 and later, KFlash and others.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```

#### MIT License (WezTerm)

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

### 7.2 更新 Meriyah 流程

根据 `docs/js_repl.md`：

```bash
# 从干净临时目录执行
tmp="$(mktemp -d)"
cd "$tmp"
npm pack meriyah@7.0.0
tar -xzf meriyah-7.0.0.tgz
cp package/dist/meriyah.umd.min.js /path/to/repo/codex-rs/core/src/tools/js_repl/meriyah.umd.min.js
cp package/LICENSE.md /path/to/repo/third_party/meriyah/LICENSE

# 额外步骤：
# 1. 更新 meriyah.umd.min.js 头部版本注释
# 2. 更新 NOTICE 文件（如版权信息变更）
# 3. 运行 js_repl 相关测试
```

---

*文档生成时间：2026-03-22*
*研究范围：third_party 目录及其所有依赖方*
