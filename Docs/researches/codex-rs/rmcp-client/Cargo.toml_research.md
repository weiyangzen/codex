# Cargo.toml 研究文档

## 场景与职责

`codex-rmcp-client` 是 Codex 项目中基于官方 `rmcp` SDK 的 Model Context Protocol (MCP) 客户端实现。该 crate 提供了与 MCP 服务器通信的能力，支持两种传输方式：
1. **STDIO 传输** - 通过子进程标准输入输出与本地 MCP 服务器通信
2. **Streamable HTTP 传输** - 通过 HTTP/SSE 与远程 MCP 服务器通信，支持 OAuth 2.0 认证

## 功能点目的

### 核心功能
1. **MCP 客户端封装**：基于 `rmcp` crate 提供高层次的 MCP 客户端 API
2. **认证管理**：支持 Bearer Token 和 OAuth 2.0 两种认证方式
3. **凭证存储**：通过系统密钥环安全存储 OAuth 凭证，支持降级到文件存储
4. **会话恢复**：Streamable HTTP 会话过期后自动重新初始化
5. **进程管理**：Unix 系统上通过进程组确保子进程清理

### 依赖分类

#### MCP/协议相关
- `rmcp` - 官方 MCP Rust SDK，提供协议实现和传输层
- `codex-protocol` - 内部协议定义

#### HTTP/网络相关
- `reqwest` - HTTP 客户端，用于 Streamable HTTP 传输
- `axum` - HTTP 服务器框架（测试用）
- `sse-stream` - Server-Sent Events 解析
- `tiny_http` - 轻量级 HTTP 服务器（OAuth 回调）

#### 认证相关
- `oauth2` - OAuth 2.0 客户端实现
- `keyring` - 系统密钥环访问（跨平台）

#### 异步运行时
- `tokio` - 异步运行时，启用多线程、进程、IO、同步等功能
- `futures` - 异步编程工具

#### 序列化/数据
- `serde` / `serde_json` - JSON 序列化
- `schemars` - JSON Schema 生成
- `sha2` - SHA-256 哈希（用于存储键计算）

#### 工具库
- `anyhow` - 错误处理
- `thiserror` - 自定义错误类型
- `tracing` - 日志/追踪
- `webbrowser` - 打开浏览器（OAuth 流程）
- `which` - 可执行文件查找
- `urlencoding` - URL 编码

## 具体技术实现

### 包配置
```toml
[package]
name = "codex-rmcp-client"
version.workspace = true      # 从工作区继承版本
edition.workspace = true      # 从工作区继承 edition (2024)
license.workspace = true      # 从工作区继承许可证 (Apache-2.0)
```

### 关键依赖详解

#### rmcp 特性配置
```toml
rmcp = { workspace = true, default-features = false, features = [
    "auth",                           # OAuth 认证支持
    "base64",                         # Base64 编码
    "client",                         # 客户端角色
    "macros",                         # 派生宏
    "schemars",                       # JSON Schema 支持
    "server",                         # 服务器角色（测试用）
    "transport-child-process",        # 子进程传输
    "transport-streamable-http-client-reqwest",  # HTTP 客户端传输
    "transport-streamable-http-server",          # HTTP 服务器传输（测试用）
] }
```

#### reqwest 配置
```toml
reqwest = { version = "0.12", default-features = false, features = [
    "json",           # JSON 支持
    "stream",         # 流式响应
    "rustls-tls",     # TLS 支持（使用 rustls，非 native-tls）
] }
```

#### tokio 配置
```toml
tokio = { workspace = true, features = [
    "io-util",        # 异步 IO 工具
    "macros",         # 宏支持
    "process",        # 进程管理
    "rt-multi-thread", # 多线程运行时
    "sync",           # 同步原语
    "io-std",         # 标准 IO
    "time",           # 定时器
] }
```

### 平台特定依赖

#### Linux
```toml
[target.'cfg(target_os = "linux")'.dependencies]
keyring = { workspace = true, features = ["linux-native-async-persistent"] }
```
使用 `linux-native-async-persistent` 特性，结合 keyutils 和 async-secret-service 实现持久化存储。

#### macOS
```toml
[target.'cfg(target_os = "macos")'.dependencies]
keyring = { workspace = true, features = ["apple-native"] }
```
使用 macOS Keychain。

#### Windows
```toml
[target.'cfg(target_os = "windows")'.dependencies]
keyring = { workspace = true, features = ["windows-native"] }
```
使用 Windows Credential Manager。

#### FreeBSD/OpenBSD
```toml
[target.'cfg(any(target_os = "freebsd", target_os = "openbsd"))'.dependencies]
keyring = { workspace = true, features = ["sync-secret-service"] }
```
使用 DBus-based Secret Service。

## 关键代码路径与文件引用

### 源码结构
```
src/
├── lib.rs                      # 模块导出
├── rmcp_client.rs              # 核心 RmcpClient 实现
├── oauth.rs                    # OAuth 凭证存储管理
├── perform_oauth_login.rs      # OAuth 登录流程
├── auth_status.rs              # 认证状态检测
├── program_resolver.rs         # 跨平台程序解析
├── logging_client_handler.rs   # MCP 客户端日志处理
├── utils.rs                    # 工具函数
└── bin/
    ├── rmcp_test_server.rs     # 测试服务器
    ├── test_stdio_server.rs    # STDIO 测试服务器
    └── test_streamable_http_server.rs  # HTTP 测试服务器
```

### 测试文件
```
tests/
├── process_group_cleanup.rs    # 进程组清理测试
├── resources.rs                # 资源操作测试
└── streamable_http_recovery.rs # HTTP 会话恢复测试
```

## 依赖与外部交互

### 内部依赖（Workspace）
| Crate | 用途 |
|-------|------|
| `codex-client` | HTTP 客户端构建（自定义 CA 支持） |
| `codex-keyring-store` | 密钥环存储抽象 |
| `codex-protocol` | MCP 协议类型定义 |
| `codex-utils-pty` | 进程组管理（Unix） |
| `codex-utils-home-dir` | CODEX_HOME 目录查找 |

### 外部依赖（关键）
| Crate | 版本 | 用途 |
|-------|------|------|
| `rmcp` | 0.15.0 | MCP SDK |
| `oauth2` | 5 | OAuth 2.0 |
| `reqwest` | 0.12 | HTTP 客户端 |
| `keyring` | 3.6 | 系统密钥环 |
| `axum` | 0.8 | HTTP 服务器 |
| `tokio` | 1 | 异步运行时 |

### 下游使用者
- `codex-cli` - CLI 入口
- `codex-core` - 核心逻辑
- `codex-tui` - TUI 界面
- `codex-app-server` - 应用服务器

## 风险、边界与改进建议

### 风险

1. **OAuth 凭证安全**
   - 密钥环不可用时降级到文件存储（`.credentials.json`）
   - 文件存储权限设置为 `0o600`，但仍存在被同用户进程读取的风险

2. **会话恢复竞争条件**
   - `session_recovery_lock` 防止并发恢复，但复杂场景下仍可能出现问题

3. **进程组清理（Unix）**
   - 依赖 `kill -0` 检测进程存在性，存在竞态条件
   - 优雅关闭（SIGTERM）后强制杀死（SIGKILL）的 2 秒延迟可能不足

4. **HTTP 传输错误处理**
   - 404 触发会话恢复，但其他 4xx/5xx 错误直接抛出
   - 网络中断恢复策略较简单

### 边界

1. **平台限制**
   - 进程组管理仅在 Unix 系统可用
   - Windows 使用 `which` crate 解析程序路径

2. **OAuth 支持**
   - 仅支持授权码流程（Authorization Code Flow）
   - 需要本地回调服务器（端口可配置）

3. **传输限制**
   - Streamable HTTP 需要服务器支持 SSE
   - 不支持 WebSocket 传输

### 改进建议

1. **凭证存储**
   - 考虑使用系统密钥链的加密 API 而非直接存储 JSON
   - 添加凭证过期自动清理机制

2. **可观测性**
   - 添加 MCP 操作指标（调用次数、延迟、错误率）
   - 增加结构化日志字段（session_id, server_name）

3. **错误处理**
   - 区分可恢复错误和永久性错误
   - 添加指数退避重试机制

4. **测试覆盖**
   - 添加 OAuth 集成测试（使用 mock 授权服务器）
   - 测试网络中断和恢复场景

5. **配置优化**
   - 考虑将超时配置外部化（当前硬编码或参数传递）
   - 支持 HTTP/2 连接池配置
