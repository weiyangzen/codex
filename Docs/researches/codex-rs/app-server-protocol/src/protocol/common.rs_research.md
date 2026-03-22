# common.rs 研究文档

## 场景与职责

`common.rs` 是 Codex App Server Protocol 的核心协议定义文件，负责定义客户端与服务器之间 JSON-RPC 通信的所有消息类型。它是整个协议层的基础，定义了：

1. **客户端请求 (ClientRequest)**：客户端向服务器发送的所有请求方法
2. **服务器请求 (ServerRequest)**：服务器向客户端发送的请求（如需要用户确认的操作）
3. **服务器通知 (ServerNotification)**：服务器向客户端推送的事件通知
4. **客户端通知 (ClientNotification)**：客户端向服务器发送的轻量级通知
5. **实验性 API 标记**：通过宏系统标记和管理实验性功能

该文件是 `codex-app-server-protocol` crate 的核心，被 `lib.rs` 通过 `pub use protocol::common::*` 公开导出。

## 功能点目的

### 1. 协议版本管理
- 同时支持 **v1 (遗留 API)** 和 **v2 (新 API)** 两种协议版本
- v1 API 主要用于向后兼容（如 `GetConversationSummary`, `GetAuthStatus` 等）
- v2 API 是活跃开发的重点，包含 Thread/Turn/Item 等新概念

### 2. 请求/响应类型定义
通过声明式宏 `client_request_definitions!` 和 `server_request_definitions!` 自动生成：
- 枚举变体与 wire 格式的映射（如 `ThreadStart => "thread/start"`）
- 参数类型和响应类型的关联
- 实验性功能标记支持

### 3. 实验性 API 控制
- 使用 `#[experimental("reason")]` 属性标记实验性方法/字段
- 通过 `inspect_params` 支持字段级别的实验性控制
- 生成实验性方法/类型的元数据常量（`EXPERIMENTAL_CLIENT_METHODS` 等）

### 4. 序列化/反序列化支持
- 使用 `serde` 进行 JSON 序列化
- 使用 `ts-rs` 生成 TypeScript 类型定义
- 使用 `schemars` 生成 JSON Schema
- 统一的 camelCase wire 格式

## 具体技术实现

### 核心宏系统

#### `client_request_definitions!`
```rust
client_request_definitions! {
    Initialize { params: v1::InitializeParams, response: v1::InitializeResponse },
    ThreadStart => "thread/start" { 
        params: v2::ThreadStartParams, 
        inspect_params: true,  // 字段级实验性检查
        response: v2::ThreadStartResponse 
    },
    // ... 更多方法
}
```

生成内容包括：
- `ClientRequest` 枚举（带 `#[serde(tag = "method")]` 的 tagged union）
- `id()` 和 `method()` 方法
- `ExperimentalApi` trait 实现
- `export_client_responses()` 等导出函数
- 实验性方法/类型常量数组

#### `server_request_definitions!`
类似地生成 `ServerRequest` 和 `ServerRequestPayload`，用于服务器向客户端发起的请求（如需要用户批准的命令执行）。

#### `server_notification_definitions!`
生成 `ServerNotification` 枚举，用于服务器向客户端推送的事件（如 `ThreadStarted`, `ItemCompleted` 等）。

### 关键数据结构

#### 认证模式 (`AuthMode`)
```rust
pub enum AuthMode {
    ApiKey,           // OpenAI API key
    Chatgpt,          // ChatGPT OAuth
    ChatgptAuthTokens, // 外部管理的 ChatGPT token（内部使用）
}
```

#### 模糊文件搜索
```rust
pub struct FuzzyFileSearchParams {
    pub query: String,
    pub roots: Vec<String>,
    pub cancellation_token: Option<String>,
}

pub struct FuzzyFileSearchResult {
    pub root: String,
    pub path: String,
    pub match_type: FuzzyFileSearchMatchType,
    pub file_name: String,
    pub score: u32,
    pub indices: Option<Vec<u32>>,
}
```

#### 会话搜索（实验性）
支持增量式文件搜索会话，包括 `sessionStart`, `sessionUpdate`, `sessionStop` 三个方法。

## 关键代码路径与文件引用

### 文件关系图
```
common.rs
├── 导入依赖
│   ├── crate::protocol::v1 (遗留 API 类型)
│   ├── crate::protocol::v2 (新 API 类型)
│   ├── crate::experimental_api (实验性 API trait)
│   └── crate::export (TypeScript/JSON Schema 导出)
├── 宏定义 (experimental_*!, client_request_definitions!, ...)
├── 类型定义 (GitSha, AuthMode, FuzzyFileSearch*)
└── 测试模块

lib.rs
└── pub use protocol::common::*;
```

### 重要方法列表（ClientRequest）

| 方法 | Wire 格式 | 实验性 | 说明 |
|------|-----------|--------|------|
| Initialize | `initialize` | 否 | 协议初始化 |
| ThreadStart | `thread/start` | 部分字段 | 创建新线程 |
| ThreadResume | `thread/resume` | 部分字段 | 恢复已有线程 |
| TurnStart | `turn/start` | 部分字段 | 开始新回合 |
| CommandExec | `command/exec` | 否 | 执行独立命令 |
| FsReadFile | `fs/readFile` | 否 | 文件系统操作 |
| ModelList | `model/list` | 否 | 列出可用模型 |
| LoginAccount | `account/login/start` | 部分字段 | 账户登录 |

### 重要通知列表（ServerNotification）

| 通知 | Wire 格式 | 实验性 | 说明 |
|------|-----------|--------|------|
| ThreadStarted | `thread/started` | 否 | 线程创建成功 |
| TurnStarted | `turn/started` | 否 | 回合开始 |
| ItemStarted | `item/started` | 否 | 项目开始处理 |
| ItemCompleted | `item/completed` | 否 | 项目完成 |
| AgentMessageDelta | `item/agentMessage/delta` | 否 | 流式消息增量 |
| ThreadRealtimeStarted | `thread/realtime/started` | 是 | 实时会话开始 |

## 依赖与外部交互

### 内部依赖
- `crate::protocol::v1`: 遗留 API 类型定义
- `crate::protocol::v2`: 新 API 类型定义（约 6000+ 行）
- `crate::experimental_api`: `ExperimentalApi` trait 和字段注册
- `crate::export`: TypeScript 和 JSON Schema 导出工具
- `crate::jsonrpc_lite`: JSON-RPC 基础类型（RequestId 等）

### 外部 crate
- `serde` / `serde_json`: 序列化
- `ts-rs`: TypeScript 类型生成
- `schemars`: JSON Schema 生成
- `strum_macros`: 枚举工具（Display）
- `codex_experimental_api_macros`: 实验性 API 过程宏

### 下游使用者
- `codex-cli`: CLI 客户端实现
- `codex-tui`: TUI 客户端实现
- `codex-app-server`: 服务器端实现

## 风险、边界与改进建议

### 当前风险

1. **实验性 API 管理复杂性**
   - 字段级实验性控制需要 `inspect_params: true` 标记
   - 容易遗漏或错误标记实验性字段
   - 建议：使用编译时检查确保所有实验性字段都被正确处理

2. **v1/v2 API 共存维护成本**
   - 遗留 API 与新 API 同时维护
   - 类型转换和兼容性处理分散在多处
   - 建议：制定明确的 v1 废弃时间表

3. **宏生成的代码难以调试**
   - 大量使用声明宏生成代码
   - 编译错误信息可能难以定位
   - 建议：考虑使用过程宏提供更好的错误信息

### 边界情况

1. **请求 ID 处理**
   - `RequestId` 支持 `String` 和 `i64` 两种类型（untagged）
   - 需要确保服务器和客户端对 ID 类型的处理一致

2. **空参数请求**
   - 部分请求使用 `Option<()>` 作为参数类型
   - 序列化时需要注意 `skip_serializing_if` 的处理

3. **实验性功能过滤**
   - 非实验性客户端需要过滤掉实验性方法和字段
   - 过滤逻辑在 `export.rs` 中实现，与 `common.rs` 中的标记需要保持一致

### 改进建议

1. **API 文档生成**
   - 当前依赖 TypeScript 和 JSON Schema 作为文档
   - 建议：增加 Markdown 格式的 API 文档自动生成

2. **协议版本协商**
   - 当前 `Initialize` 参数有限
   - 建议：增加客户端/服务器协议版本协商机制

3. **测试覆盖**
   - 当前测试主要集中在序列化/反序列化
   - 建议：增加协议状态机测试和边界情况测试

4. **类型安全**
   - 部分类型使用 `JsonValue`（如 `DynamicToolCallParams.arguments`）
   - 建议：在可能的情况下使用更具体的类型

### 性能考虑
- 大量使用 `serde` 的 tagged union 可能影响序列化性能
- 大型枚举（如 `ClientRequest` 有约 50+ 变体）可能影响 match 性能
- 建议：对性能关键路径进行基准测试
