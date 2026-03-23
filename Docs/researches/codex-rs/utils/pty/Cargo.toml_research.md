# Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 包管理器 Cargo 的配置文件，定义了 `codex-utils-pty` crate 的元数据、依赖关系和构建配置。该 crate 是 Codex 项目的底层工具库，提供跨平台的伪终端（PTY）和管道进程管理功能。

## 功能点目的

### 1. 包元数据
```toml
[package]
edition = "2021"
license.workspace = true
name = "codex-utils-pty"
version.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `edition` | `"2021"` | Rust 语言版本，使用 2021 edition（注意：工作区使用 2024，但此 crate 单独指定 2021） |
| `license.workspace` | `true` | 继承工作区 `license = "Apache-2.0"` |
| `name` | `"codex-utils-pty"` | Crate 名称，符合 `codex-*` 命名规范 |
| `version.workspace` | `true` | 继承工作区 `version = "0.0.0"` |

### 2. 代码检查配置
```toml
[lints]
workspace = true
```
继承工作区级别的 Clippy lint 规则（定义在根 `Cargo.toml` 的 `[workspace.lints.clippy]`）。

### 3. 核心依赖
```toml
[dependencies]
anyhow = { workspace = true }
portable-pty = { workspace = true }
tokio = { workspace = true, features = ["io-util", "macros", "process", "rt-multi-thread", "sync", "time"] }
```

| 依赖 | 版本来源 | 用途 |
|------|----------|------|
| `anyhow` | workspace | 结构化错误处理 |
| `portable-pty` | workspace | 跨平台 PTY 抽象（版本 0.9.0） |
| `tokio` | workspace | 异步运行时，启用关键特性： |
| | | - `io-util`：异步 I/O 工具 |
| | | - `macros`：`#[tokio::main]` 等宏 |
| | | - `process`：异步进程管理 |
| | | - `rt-multi-thread`：多线程运行时 |
| | | - `sync`：异步同步原语 |
| | | - `time`：异步定时器 |

### 4. 开发依赖
```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
```
用于测试中的美观断言输出。

### 5. 平台特定依赖（Windows）
```toml
[target.'cfg(windows)'.dependencies]
filedescriptor = "0.8.3"
lazy_static = { workspace = true }
log = { workspace = true }
shared_library = "0.1.9"
winapi = { version = "0.3.9", features = [...] }
```

| 依赖 | 用途 |
|------|------|
| `filedescriptor` | 文件描述符抽象，用于 ConPTY 句柄管理 |
| `lazy_static` | 延迟初始化静态变量（如 `CONPTY` 函数表） |
| `log` | 日志记录（Windows 错误日志） |
| `shared_library` | 动态库加载（`kernel32.dll`/`conpty.dll`） |
| `winapi` | Windows API 绑定，启用特性： |
| | - `handleapi`：句柄操作 |
| | - `minwinbase`：基础类型 |
| | - `processthreadsapi`：进程/线程 API |
| | - `synchapi`：同步 API |
| | - `winbase`：Windows 基础 API |
| | - `wincon`：控制台 API |
| | - `winerror`：错误码 |
| | - `winnt`：NT 内核类型 |

### 6. 平台特定依赖（Unix）
```toml
[target.'cfg(unix)'.dependencies]
libc = { workspace = true }
```
Unix 系统调用绑定（`openpty`、`ioctl`、`setsid` 等）。

## 具体技术实现

### 依赖版本解析
工作区 `Cargo.toml` 定义：
```toml
[workspace.dependencies]
anyhow = "1"
portable-pty = "0.9.0"
tokio = "1"
libc = "0.2.182"
lazy_static = "1"
log = "0.4"
```

### 特性组合策略
`tokio` 的特性选择基于 crate 需求：
- **I/O 密集型**：`io-util`、`process`
- **并发模型**：`rt-multi-thread`、`sync`
- **测试支持**：`macros`、`time`

### Windows 依赖的特殊性
Windows 实现大量依赖 vendored 代码（来自 WezTerm），需要额外的系统级库：
```rust
// win/psuedocon.rs 中使用 shared_library 加载 kernel32.dll
shared_library!(ConPtyFuncs,
    pub fn CreatePseudoConsole(...),
    pub fn ResizePseudoConsole(...),
    pub fn ClosePseudoConsole(...),
);
```

## 关键代码路径与文件引用

### 依赖使用位置
| 依赖 | 使用文件 | 用途 |
|------|----------|------|
| `portable-pty` | `src/pty.rs` | `native_pty_system()`、`CommandBuilder` |
| `tokio` | 所有模块 | 异步运行时、`mpsc`、`oneshot`、`spawn_blocking` |
| `anyhow` | 所有模块 | `Result`、`bail!`、`ensure!` |
| `libc` | `src/pty.rs`、`src/process_group.rs` | `openpty`、`ioctl`、`setsid`、`killpg` |
| `winapi` | `src/win/*.rs` | Windows ConPTY API |

### 版本兼容性
- `portable-pty 0.9.0`：支持 Unix PTY 和 Windows ConPTY
- `tokio 1.x`：与整个工作区保持一致
- `winapi 0.3.9`：成熟的 Windows API 绑定

## 依赖与外部交互

### 上游依赖关系
```
codex-utils-pty
├── anyhow (错误处理)
├── portable-pty (PTY 抽象)
│   └── (内部依赖: libc/winapi)
├── tokio (异步运行时)
│   └── (内部依赖: mio/socket2)
├── libc (Unix)
└── winapi + 辅助库 (Windows)
```

### 下游调用方
通过 `cargo tree -p codex-utils-pty --edges normal` 可查看：
- `codex-core` → `codex-utils-pty`
- `codex-app-server` → `codex-utils-pty`
- `codex-rmcp-client` → `codex-utils-pty`
- `codex-tui` → `codex-utils-pty`

## 风险、边界与改进建议

### 风险
1. **版本漂移**：`portable-pty 0.9.0` 较旧，可能存在未修复的 bug
2. **Windows 动态加载**：`shared_library` 加载 `kernel32.dll` 失败时无优雅降级
3. **Tokio 特性膨胀**：启用较多特性，编译时间可能增加

### 边界
- **最低 Windows 版本**：ConPTY 需要 Windows 10 1809 (build 17763+)
- **Unix 假设**：依赖 `openpty()` 可用（现代 Linux/macOS 均支持）
- **Tokio 绑定**：强制使用 Tokio 运行时，不兼容 async-std 等其他运行时

### 改进建议

#### 1. 升级 portable-pty
```toml
# 检查是否有新版本
portable-pty = "0.10"  # 如有
```

#### 2. 考虑移除 winapi（长期）
`winapi`  crate 已进入维护模式，建议迁移到官方 `windows` crate：
```toml
[target.'cfg(windows)'.dependencies]
windows = { version = "0.52", features = ["Win32_System_Threading", ...] }
```

#### 3. 特性精简
如果某些特性未使用，可考虑移除：
```toml
# 如果不需要多线程运行时
tokio = { workspace = true, features = ["io-util", "process", "rt", "sync"] }
```

#### 4. 添加可选特性
为不同使用场景提供特性门控：
```toml
[features]
default = ["pty", "pipe"]
pty = ["portable-pty"]
pipe = []
```

#### 5. 文档依赖
添加文档构建依赖：
```toml
[package.metadata.docs.rs]
features = ["full"]
targets = ["x86_64-unknown-linux-gnu", "x86_64-pc-windows-msvc"]
```
