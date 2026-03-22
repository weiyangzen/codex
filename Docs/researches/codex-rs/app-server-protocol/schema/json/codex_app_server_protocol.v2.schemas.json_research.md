# Codex App Server Protocol v2 JSON Schema 研究文档

## 1. 场景与职责

### 1.1 文件定位

**文件路径**: `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json`

该文件是 Codex 应用服务器协议 v2 版本的 JSON Schema 规范文件，是客户端（如 VS Code 扩展、CLI、TUI）与 Codex 应用服务器之间通信的契约定义。

### 1.2 核心职责

1. **协议契约定义**: 定义了客户端与服务器之间所有 JSON-RPC 消息的结构，包括请求、响应、通知等
2. **类型系统规范**: 提供了完整的类型定义，用于代码生成、类型检查和文档生成
3. **多语言绑定基础**: 作为生成 TypeScript 类型、Rust 结构体等的源头
4. **API 版本控制**: v2 版本是当前活跃开发的主要 API 版本，v1 已标记为废弃

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| 客户端开发 | VS Code 扩展、TUI 等客户端使用该 schema 生成类型安全的 API 调用代码 |
| 服务器实现 | app-server 基于该 schema 实现请求处理和响应构造 |
| 文档生成 | 自动生成 API 文档和开发者指南 |
| 测试验证 | 用于验证消息格式是否符合协议规范 |

## 2. 功能点目的

### 2.1 Schema 结构概览

该 JSON Schema 文件遵循 JSON Schema Draft-07 规范，包含以下主要部分：

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    // 约 300+ 个类型定义
  }
}
```

### 2.2 核心功能模块

#### 2.2.1 Thread 生命周期管理

定义了对话线程的完整生命周期：

- `ThreadStartParams` / `ThreadStartResponse`: 启动新线程
- `ThreadResumeParams`: 恢复已存在的线程
- `ThreadForkParams`: 从现有线程分叉创建新线程
- `ThreadArchiveParams` / `ThreadUnarchiveParams`: 归档/解归档线程
- `ThreadListParams` / `ThreadListResponse`: 列出线程
- `ThreadReadParams` / `ThreadReadResponse`: 读取线程详情

#### 2.2.2 Turn 管理

Turn 是线程中的单次交互回合：

- `TurnStartParams`: 启动新的用户回合
- `TurnSteerParams`: 引导/干预当前回合
- `TurnInterruptParams`: 中断正在进行的回合
- `TurnCompletedNotification`: 回合完成通知

#### 2.2.3 Item 系统

Item 是回合中的具体项目（消息、工具调用等）：

- `ItemStartedNotification`: 项目开始
- `ItemCompletedNotification`: 项目完成
- `AgentMessageDeltaNotification`: 代理消息增量更新
- `CommandExecutionOutputDeltaNotification`: 命令执行输出
- `FileChangeOutputDeltaNotification`: 文件变更输出

#### 2.2.4 配置管理

- `ConfigReadParams` / `ConfigReadResponse`: 读取配置
- `ConfigValueWriteParams`: 写入配置值
- `ConfigBatchWriteParams`: 批量写入配置
- `ConfigLayerSource`: 配置层级来源（MDM、System、User、Project 等）

#### 2.2.5 文件系统操作

- `FsReadFileParams` / `FsReadFileResponse`: 读取文件
- `FsWriteFileParams`: 写入文件
- `FsCreateDirectoryParams`: 创建目录
- `FsReadDirectoryParams` / `FsReadDirectoryResponse`: 读取目录
- `FsRemoveParams`: 删除文件/目录
- `FsCopyParams`: 复制文件

#### 2.2.6 命令执行

- `CommandExecParams` / `CommandExecResponse`: 执行命令
- `CommandExecWriteParams`: 向运行中的命令写入 stdin
- `CommandExecTerminateParams`: 终止命令
- `CommandExecResizeParams`: 调整 PTY 大小
- `CommandExecOutputDeltaNotification`: 命令输出流

#### 2.2.7 账户与认证

- `LoginAccountParams` / `LoginAccountResponse`: 登录账户
- `GetAccountParams` / `GetAccountResponse`: 获取账户信息
- `GetAccountRateLimitsResponse`: 获取速率限制
- `AccountUpdatedNotification`: 账户更新通知

#### 2.2.8 MCP (Model Context Protocol)

- `ListMcpServerStatusParams` / `ListMcpServerStatusResponse`: MCP 服务器状态
- `McpServerOauthLoginParams`: MCP OAuth 登录
- `McpToolCallProgressNotification`: MCP 工具调用进度

#### 2.2.9 插件系统

- `PluginListParams` / `PluginListResponse`: 列出插件
- `PluginReadParams` / `PluginReadResponse`: 读取插件详情
- `PluginInstallParams` / `PluginInstallResponse`: 安装插件
- `PluginUninstallParams`: 卸载插件

#### 2.2.10 实验性功能

标记为 `EXPERIMENTAL` 的功能：

- Realtime API (`ThreadRealtimeStartParams` 等)
- Collaboration Mode (`CollaborationModeMask`)
- Guardian Approval Review (`ItemGuardianApprovalReviewStartedNotification`)
- Fuzzy File Search Session API

## 3. 具体技术实现

### 3.1 代码生成流程

```
Rust 类型定义 (protocol/v2.rs, protocol/common.rs)
    ↓
#[derive(JsonSchema, TS)] 宏生成
    ↓
schemars 生成 JSON Schema
    ↓
export.rs 中的 generate_json() 函数
    ↓
合并为 codex_app_server_protocol.v2.schemas.json
```

### 3.2 关键数据结构

#### 3.2.1 ClientRequest

所有客户端请求的联合类型，使用 `oneOf` 定义：

```json
{
  "oneOf": [
    {
      "title": "InitializeRequest",
      "properties": {
        "id": { "$ref": "#/definitions/RequestId" },
        "method": { "enum": ["initialize"] },
        "params": { "$ref": "#/definitions/InitializeParams" }
      }
    },
    // ... 更多请求类型
  ]
}
```

#### 3.2.2 ServerNotification

服务器向客户端发送的通知：

```json
{
  "oneOf": [
    {
      "title": "ErrorNotification",
      "properties": {
        "method": { "enum": ["error"] },
        "params": { "$ref": "#/definitions/ErrorNotification" }
      }
    },
    // ... 更多通知类型
  ]
}
```

#### 3.2.3 ResponseItem

响应项目的联合类型，包含：
- `MessageResponseItem`: 文本消息
- `ReasoningResponseItem`: 推理内容
- `FunctionCallResponseItem`: 函数调用
- `LocalShellCallResponseItem`: 本地 shell 调用
- `WebSearchCallResponseItem`: 网络搜索
- `ImageGenerationCallResponseItem`: 图像生成
- `GhostSnapshotResponseItem`: Git 快照
- `CompactionResponseItem`: 上下文压缩

### 3.3 命名规范

| 元素 | 命名风格 | 示例 |
|------|----------|------|
| 请求参数 | PascalCase + Params | `ThreadStartParams` |
| 响应 | PascalCase + Response | `ThreadStartResponse` |
| 通知 | PascalCase + Notification | `ThreadStartedNotification` |
| 枚举 | camelCase | `sandboxMode: "read-only"` |
| 字段 | camelCase | `threadId`, `turnId` |

### 3.4 实验性 API 标记

使用 `#[experimental("reason")]` 属性标记实验性功能：

```rust
#[experimental("thread/realtime/start")]
ThreadRealtimeStart => "thread/realtime/start" {
    params: v2::ThreadRealtimeStartParams,
    response: v2::ThreadRealtimeStartResponse,
}
```

在生成的 schema 中，实验性字段和方法会被条件性过滤（通过 `experimental_api` 标志控制）。

## 4. 关键代码路径与文件引用

### 4.1 协议定义层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 类型定义（约 2000+ 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 通用类型和宏定义（ClientRequest/ServerRequest/ServerNotification） |
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | v1 遗留 API（已废弃） |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSON-RPC 基础类型 |
| `codex-rs/app-server-protocol/src/experimental_api.rs` | 实验性 API 标记 trait |

### 4.2 代码生成层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/export.rs` | TypeScript 和 JSON Schema 生成逻辑 |
| `codex-rs/app-server-protocol/src/schema_fixtures.rs` | Schema fixture 管理和测试 |
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | CLI 工具用于重新生成 schema |

### 4.3 服务器实现层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server/src/lib.rs` | 主入口和消息循环 |
| `codex-rs/app-server/src/message_processor.rs` | JSON-RPC 消息处理 |
| `codex-rs/app-server/src/config_api.rs` | 配置相关 API 实现 |
| `codex-rs/app-server/src/fs_api.rs` | 文件系统 API 实现 |
| `codex-rs/app-server/src/command_exec.rs` | 命令执行 API 实现 |

### 4.4 测试层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/tests/schema_fixtures.rs` | 验证生成的 schema 与 fixture 一致 |
| `codex-rs/app-server/tests/suite/v2/` | v2 API 集成测试套件 |

### 4.5 生成产物

| 路径 | 说明 |
|------|------|
| `schema/json/codex_app_server_protocol.v2.schemas.json` | v2 扁平化 schema（本文件） |
| `schema/json/codex_app_server_protocol.schemas.json` | 完整 schema（含 v1） |
| `schema/typescript/v2/*.ts` | 生成的 TypeScript 类型 |
| `schema/typescript/*.ts` | 顶层 TypeScript 类型 |

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex_app_server_protocol
├── codex_protocol (核心协议类型)
├── codex_experimental_api_macros (实验性 API 宏)
├── schemars (JSON Schema 生成)
├── ts-rs (TypeScript 类型生成)
├── serde (序列化)
└── strum (字符串枚举)
```

### 5.2 外部消费者

| 消费者 | 使用方式 |
|--------|----------|
| codex-app-server | 实现协议处理器 |
| codex-tui | 通过 WebSocket/stdio 连接使用 |
| VS Code 扩展 | 生成 TypeScript 客户端 |
| 第三方客户端 | 基于 schema 生成代码 |

### 5.3 协议传输层

支持两种传输方式：

1. **Stdio**: 标准输入输出（单客户端模式）
   - 默认模式，适用于 CLI 和本地集成
   
2. **WebSocket**: `ws://IP:PORT`
   - 支持多客户端连接
   - 适用于远程开发和 IDE 集成

### 5.4 配置来源层级

`ConfigLayerSource` 定义了配置优先级（从低到高）：

1. `Mdm` - MDM 管理配置（macOS）
2. `System` - 系统级配置
3. `User` - 用户配置 (`$CODEX_HOME/config.toml`)
4. `Project` - 项目配置 (`.codex/` 目录)
5. `SessionFlags` - 会话级 CLI 覆盖 (`-c` 参数)
6. `LegacyManagedConfigTomlFromFile` - 遗留托管配置
7. `LegacyManagedConfigTomlFromMdm` - 遗留 MDM 配置

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 Schema 漂移风险

- **风险**: 手动修改生成的 schema 文件会导致与代码不同步
- **缓解**: 使用 `just write-app-server-schema` 命令重新生成，CI 中运行 `schema_fixtures_match_generated` 测试验证

#### 6.1.2 实验性 API 稳定性

- **风险**: 标记为 `EXPERIMENTAL` 的 API 可能随时变更
- **缓解**: 客户端需显式声明 `experimentalApi: true` 能力才能使用

#### 6.1.3 大文件处理

- **风险**: schema 文件约 9000+ 行，手动阅读困难
- **缓解**: 使用工具生成文档和类型定义，避免直接编辑

### 6.2 边界情况

#### 6.2.1 版本兼容性

- v1 API 已标记为废弃，但仍保留用于向后兼容
- v2 是主要开发版本，新功能优先在 v2 添加

#### 6.2.2 平台差异

- Windows Sandbox 相关 API 仅在 Windows 平台有效
- macOS Seatbelt 扩展仅在 macOS 有效
- MDM 配置仅在 macOS 支持

#### 6.2.3 实验性功能门控

- 实验性字段在 schema 中可能被过滤（非实验模式）
- 服务器会拒绝未声明 experimentalApi 能力的客户端调用实验性方法

### 6.3 改进建议

#### 6.3.1 文档生成

- 建议添加自动化文档生成流程，从 schema 生成 Markdown/HTML 文档
- 为每个 API 方法添加使用示例

#### 6.3.2 版本管理

- 考虑引入更细粒度的 API 版本控制（如 `v2.1`）
- 添加弃用时间表和迁移指南

#### 6.3.3 测试覆盖

- 增加 schema 验证测试，确保所有生成的类型都能正确序列化/反序列化
- 添加模糊测试验证边界情况处理

#### 6.3.4 工具链

- 提供官方客户端代码生成工具（OpenAPI Generator 插件等）
- 添加 schema 变更检测和破坏性变更警告

#### 6.3.5 性能优化

- 考虑将大型 schema 拆分为按功能模块组织的多个文件
- 添加 schema 压缩/缓存机制减少传输开销

### 6.4 维护建议

1. **定期同步**: 修改 `protocol/v2.rs` 后必须运行 `just write-app-server-schema`
2. **变更审查**: API 变更需经过协议兼容性审查
3. **文档更新**: 同步更新 `app-server/README.md` 中的 API 文档
4. **测试验证**: 确保 `cargo test -p codex-app-server-protocol` 通过

---

*文档生成时间: 2026-03-22*
*基于 schema 版本: codex_app_server_protocol.v2.schemas.json (JSON Schema Draft-07)*
