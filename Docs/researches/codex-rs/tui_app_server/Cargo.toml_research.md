# Cargo.toml 研究文档

## 场景与职责

此 Cargo.toml 文件定义了 `codex-tui-app-server` crate 的元数据、构建配置和依赖关系。该 crate 是 Codex CLI 的核心 TUI（终端用户界面）实现，基于 Ratatui 框架提供富交互式聊天体验。

## 功能点目的

1. **定义 Crate 元数据**：名称、版本、许可证等基础信息
2. **配置构建目标**：主二进制、辅助二进制、库的定义
3. **管理功能开关**：语音输入、调试日志、vt100 测试等可选功能
4. **声明依赖关系**：30+ 个生产依赖和 10+ 个开发依赖
5. **平台特定配置**：Linux/Windows/Unix/Android 的条件依赖

## 具体技术实现

### 包元数据

```toml
[package]
name = "codex-tui-app-server"
version.workspace = true      # 继承工作区版本
edition.workspace = true      # 继承工作区 Rust 版本
license.workspace = true      # 继承工作区许可证
autobins = false              # 禁用自动二进制发现
```

### 构建目标配置

#### 主二进制文件
```toml
[[bin]]
name = "codex-tui-app-server"
path = "src/main.rs"
```

#### 辅助二进制文件（md-events 调试工具）
```toml
[[bin]]
name = "md-events-app-server"
path = "src/bin/md-events.rs"
```

#### 库目标
```toml
[lib]
name = "codex_tui_app_server"
path = "src/lib.rs"
```

### 功能开关 (Features)

| 功能 | 默认 | 描述 |
|-----|------|------|
| `voice-input` | ✅ | 启用语音输入（依赖 cpal + hound） |
| `debug-logs` | ❌ | 启用 TUI 内部调试日志 |
| `vt100-tests` | ❌ | 启用基于 vt100 的终端模拟测试 |

```toml
[features]
default = ["voice-input"]
voice-input = ["dep:cpal", "dep:hound"]
```

### 核心依赖分析

#### UI 框架
```toml
ratatui = { workspace = true, features = [
    "scrolling-regions",
    "unstable-backend-writer",
    "unstable-rendered-line-info",
    "unstable-widget-ref",
] }
crossterm = { workspace = true, features = ["bracketed-paste", "event-stream"] }
```

使用 Ratatui 的实验性功能：
- `scrolling-regions`: 优化滚动性能
- `unstable-backend-writer`: 后端直接写入能力
- `unstable-rendered-line-info`: 渲染行信息查询

#### 内部 Workspace 依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 核心配置、协议、状态管理 |
| `codex-app-server-client` | App Server 客户端连接 |
| `codex-app-server-protocol` | App Server 通信协议 |
| `codex-protocol` | 共享协议类型 |
| `codex-client` | API 客户端 |
| `codex-feedback` | 遥测和反馈收集 |
| `codex-state` | 状态持久化 |

#### 语法高亮
```toml
syntect = "5"
two-face = { version = "0.5", default-features = false, features = ["syntect-default-onig"] }
```

使用 Syntect 5 进行代码语法高亮，`two-face` 提供额外语法定义。

### 平台特定依赖

#### 非 Linux 平台（语音输入）
```toml
[target.'cfg(not(target_os = "linux"))'.dependencies]
cpal = { version = "0.15", optional = true }      # 音频捕获
hound = { version = "3.5", optional = true }      # WAV 文件处理
```

#### Unix 平台
```toml
[target.'cfg(unix)'.dependencies]
libc = { workspace = true }
```

#### Windows 平台
```toml
[target.'cfg(windows)'.dependencies]
which = { workspace = true }
windows-sys = { version = "0.52", features = ["Win32_Foundation", "Win32_System_Console"] }
winsplit = "0.1"
```

#### Android 排除
```toml
[target.'cfg(not(target_os = "android"))'.dependencies]
arboard = { workspace = true }  # 剪贴板支持（Android/Termux 不可用）
```

### 开发依赖

```toml
[dev-dependencies]
insta = { workspace = true }              # 快照测试
vt100 = { workspace = true }              # 终端模拟
serial_test = { workspace = true }        # 串行化测试
codex-utils-pty = { workspace = true }    # PTY 测试工具
```

## 关键代码路径与文件引用

### 依赖关系图

```
codex-tui-app-server
├── Core UI
│   ├── ratatui (TUI 框架)
│   ├── crossterm (终端控制)
│   └── syntect (语法高亮)
├── Internal Crates
│   ├── codex-core (配置/协议)
│   ├── codex-app-server-client
│   ├── codex-app-server-protocol
│   └── codex-protocol
├── Async Runtime
│   └── tokio (多线程运行时)
├── Serialization
│   ├── serde
│   └── serde_json
└── Platform-specific
    ├── cpal/hound (非 Linux 语音)
    └── windows-sys (Windows API)
```

### 关键源文件

| 文件 | 描述 |
|------|------|
| `src/main.rs` | 二进制入口点 |
| `src/lib.rs` | 库入口，App 启动逻辑 |
| `src/app.rs` | 主应用状态机 |
| `src/chatwidget.rs` | 聊天界面组件 |
| `src/tui.rs` | 终端初始化和事件处理 |
| `src/bin/md-events.rs` | Markdown 事件调试工具 |

## 依赖与外部交互

### Workspace 依赖管理

所有内部 crate 使用 `workspace = true` 继承工作区统一版本：
- 确保版本一致性
- 简化版本升级
- 减少冲突

### 外部 Crate 选择理由

| Crate | 选择理由 |
|-------|---------|
| `ratatui` | Rust 生态最成熟的 TUI 框架 |
| `crossterm` | 跨平台终端控制 |
| `tokio` | 异步运行时标准 |
| `color-eyre` | 增强错误报告 |
| `serde` | 序列化标准 |
| `pulldown-cmark` | Markdown 解析 |

## 风险、边界与改进建议

### 潜在风险

1. **实验性功能依赖**：Ratatui 的 `unstable-*` 功能可能在升级时破坏 API
2. **平台差异**：语音输入在 Linux 上完全禁用，功能不一致
3. **依赖膨胀**：30+ 生产依赖增加编译时间和二进制大小

### 边界条件

1. **Android 剪贴板**：`arboard` 在 Android 上被排除，粘贴功能受限
2. **语音输入平台限制**：Linux 用户无法使用语音功能
3. **Windows API 版本**：`windows-sys 0.52` 需要特定 Windows 版本

### 改进建议

1. **功能拆分**：
   ```toml
   # 建议：将语音功能拆分为独立 crate
   [features]
   voice-input = ["codex-voice/client"]
   ```

2. **稳定化 Ratatui 功能**：
   - 跟踪 Ratatui 稳定版本发布
   - 逐步迁移 `unstable-*` 功能到稳定 API

3. **Linux 语音支持**：
   - 评估 PipeWire/PulseAudio 替代方案
   - 或提供基于 WebRTC 的跨平台方案

4. **依赖优化**：
   - 审计未使用的依赖（如 `rand` 可能可通过 `getrandom` 替代）
   - 考虑使用 `features` 进一步拆分可选功能

5. **版本锁定策略**：
   ```toml
   # 建议：为关键依赖添加版本上限
   ratatui = { workspace = true, features = [...], version = ">=0.29, <0.31" }
   ```
