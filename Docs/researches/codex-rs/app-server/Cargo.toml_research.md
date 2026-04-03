# codex-rs/app-server/Cargo.toml 研究文档

## 场景与职责

`Cargo.toml` 是 Rust 包管理器 Cargo 的配置文件，定义了 `codex-app-server` crate 的元数据、构建目标、依赖关系和特性标志。该 crate 是 Codex 项目的核心应用服务器，为 VS Code 扩展等客户端提供 JSON-RPC API 服务。

### 定位
- **包名**: `codex-app-server`
- **版本**: 继承自工作区 (`version.workspace = true`)
- **Rust Edition**: 2021 (继承自工作区)
- **许可证**: 继承自工作区

## 功能点目的

### 1. 构建目标定义

#### 主二进制可执行文件
```toml
[[bin]]
name = "codex-app-server"
path = "src/main.rs"
```
- **用途**: `codex app-server` 子命令的入口点
- **功能**: 启动 JSON-RPC 服务器，支持 stdio 和 WebSocket 传输

#### 测试辅助二进制
```toml
[[bin]]
name = "codex-app-server-test-notify-capture"
path = "src/bin/notify_capture.rs"
```
- **用途**: 集成测试中捕获服务器通知的工具

#### 库目标
```toml
[lib]
name = "codex_app_server"
path = "src/lib.rs"
```
- **用途**: 供 `codex-cli` 等 crate 内嵌使用
- **关键模块**: `in_process` - 进程内运行时宿主

### 2. 依赖管理策略

该 crate 采用工作区依赖管理 (`workspace = true`)，集中控制版本：

| 依赖类别 | 数量 | 说明 |
|----------|------|------|
| 工作区依赖 | 40+ | 内部 crate 和外部库 |
| 特性启用 | 15+ | 条件编译和功能开关 |
| 开发依赖 | 10+ | 仅测试时使用 |

## 具体技术实现

### 核心依赖分析

#### Web 服务器与异步运行时
```toml
axum = { workspace = true, default-features = false, features = [
    "http1",
    "json",
    "tokio",
    "ws",
] }
tokio = { workspace = true, features = [
    "io-std",
    "macros",
    "process",
    "rt-multi-thread",
    "signal",
] }
```

- **axum**: 精简配置，仅启用 HTTP/1、JSON 和 WebSocket 支持
- **tokio**: 多线程运行时，支持进程管理和信号处理

#### Codex 内部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | 核心线程管理、配置、认证 |
| `codex-app-server-protocol` | JSON-RPC 协议类型定义 |
| `codex-protocol` | 底层协议消息 |
| `codex-login` | OAuth/API Key 认证流程 |
| `codex-state` | 状态持久化 (SQLite) |
| `codex-feedback` | 遥测和日志收集 |
| `codex-rmcp-client` | MCP (Model Context Protocol) 客户端 |

#### 关键外部依赖

```toml
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
chrono = { workspace = true }
uuid = { workspace = true, features = ["serde", "v7"] }
tracing = { workspace = true, features = ["log"] }
tracing-subscriber = { workspace = true, features = ["env-filter", "fmt", "json"] }
```

### 开发依赖特性

```toml
[dev-dependencies]
rmcp = { workspace = true, default-features = false, features = [
    "elicitation",
    "server",
    "transport-streamable-http-server",
] }
```

- **rmcp**: MCP 协议实现，测试中使用服务器模式和 elicitation 功能

## 关键代码路径与文件引用

### 源文件结构

```
codex-rs/app-server/src/
├── main.rs                      # 二进制入口
├── lib.rs                       # 库公共接口
├── bin/
│   ├── notify_capture.rs        # 测试通知捕获
│   └── test_notify_capture.rs   # 测试辅助
├── message_processor.rs         # JSON-RPC 请求处理核心
├── codex_message_processor.rs   # Codex 业务逻辑处理
├── transport.rs                 # 传输层 (stdio/WebSocket)
├── in_process.rs                # 进程内运行时
├── thread_state.rs              # 线程状态管理
├── config_api.rs                # 配置 API 实现
├── fs_api.rs                    # 文件系统 API
├── command_exec.rs              # 命令执行管理
├── models.rs                    # 数据模型
└── ...
```

### 协议相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-app-server-protocol/src/protocol/v2.rs` | 协议定义 | API v2 请求/响应类型 |
| `codex-app-server-protocol/src/protocol/common.rs` | 协议定义 | 通用协议组件 |
| `codex-app-server-protocol/src/experimental_api.rs` | 特性门控 | 实验性 API 注解宏 |

## 依赖与外部交互

### 运行时架构

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-app-server                         │
├─────────────────────────────────────────────────────────────┤
│  Transport Layer (transport.rs)                             │
│  ├── stdio:// (默认)                                        │
│  └── ws://IP:PORT (WebSocket)                               │
├─────────────────────────────────────────────────────────────┤
│  Message Processor (message_processor.rs)                   │
│  ├── JSON-RPC 解析                                          │
│  ├── 请求路由                                               │
│  └── 会话状态管理                                           │
├─────────────────────────────────────────────────────────────┤
│  Codex Message Processor (codex_message_processor.rs)       │
│  ├── Thread 生命周期管理                                    │
│  ├── Turn 执行                                              │
│  └── 事件流处理                                             │
├─────────────────────────────────────────────────────────────┤
│  Core Dependencies                                          │
│  ├── codex-core (ThreadManager, AuthManager)                │
│  ├── codex-state (持久化)                                   │
│  └── codex-protocol (底层消息)                              │
└─────────────────────────────────────────────────────────────┘
```

### 关键外部接口

| 接口 | 依赖 Crate | 用途 |
|------|-----------|------|
| JSON-RPC | `codex-app-server-protocol` | 客户端通信协议 |
| OpenAI API | `codex-backend-client` | LLM 调用 |
| MCP | `codex-rmcp-client` | 外部工具集成 |
| OAuth | `codex-login` | ChatGPT 认证 |
| SQLite | `codex-state` | 会话持久化 |

## 风险、边界与改进建议

### 当前风险

1. **依赖数量庞大 (40+ 直接依赖)**
   - **风险**: 编译时间长、依赖冲突概率高
   - **缓解**: 工作区统一管理、锁定版本

2. **特性标志复杂**
   - **风险**: 不同特性组合可能产生未测试的编译配置
   - **建议**: CI 中测试关键特性组合

3. **开发依赖包含 MCP 服务器**
   - **风险**: 测试环境需要额外设置
   - **注意**: 测试使用 `no-sandbox` 标签

### 边界条件

| 边界 | 说明 |
|------|------|
| 最小 Rust 版本 | 由工作区定义 |
| 支持平台 | macOS, Linux, Windows |
| 传输协议 | stdio (默认), WebSocket (实验性) |
| 并发模型 | 多线程 Tokio 运行时 |

### 改进建议

1. **依赖分组优化**
   ```toml
   [features]
   default = ["websocket", "mcp"]
   websocket = ["axum/ws"]
   mcp = ["codex-rmcp-client"]
   telemetry = ["codex-otel"]
   ```

2. **版本约束细化**
   ```toml
   [dependencies]
   # 对关键依赖添加最小版本约束
   tokio = { workspace = true, features = ["full"], version = ">=1.35" }
   ```

3. **文档依赖**
   ```toml
   [package.metadata.docs.rs]
   features = ["full"]
   rustdoc-args = ["--cfg", "docsrs"]
   ```

### 相关文档

- [README.md](README.md) - API 详细文档
- [AGENTS.md](../../../../AGENTS.md) - 项目开发规范
- `codex-app-server-protocol/README.md` - 协议规范
