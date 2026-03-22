# codex_app_server_protocol.schemas.json 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`codex_app_server_protocol.schemas.json` 是 Codex App Server Protocol 的 **JSON Schema 定义文件**，位于 `codex-rs/app-server-protocol/schema/json/` 目录下。该文件是 codex-rs 项目中 app-server 协议层的核心 schema 定义，用于：

1. **客户端-服务器通信契约**：定义了客户端（如 VS Code 扩展、CLI）与 Codex App Server 之间的所有 JSON-RPC 消息格式
2. **类型验证**：为 TypeScript 客户端和 Rust 服务端提供运行时类型验证依据
3. **API 文档**：作为机器可读的 API 规范，支持代码生成和文档自动生成

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **LSP-like 通信** | 基于 JSON-RPC 2.0 的客户端-服务器双向通信 |
| **Thread 生命周期管理** | 创建、恢复、归档、fork 对话线程 |
| **Turn 执行** | 用户输入处理、AI 响应流式传输 |
| **审批流程** | 命令执行审批、文件变更审批、权限请求 |
| **实时会话** | Realtime API 的音频输入输出 |
| **配置管理** | 读取/写入用户配置、配置层管理 |
| **MCP 集成** | Model Context Protocol 服务器管理 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                     客户端 (VS Code/CLI)                      │
├─────────────────────────────────────────────────────────────┤
│              TypeScript 类型 (从 Schema 生成)                  │
├─────────────────────────────────────────────────────────────┤
│    JSON-RPC 消息 (符合 codex_app_server_protocol.schemas.json) │
├─────────────────────────────────────────────────────────────┤
│              Rust 类型 (codex-app-server-protocol crate)       │
├─────────────────────────────────────────────────────────────┤
│                    Codex App Server                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能模块

#### 2.1.1 JSON-RPC 基础信封 (Lines 2280-2396)

定义了 JSON-RPC 2.0 的基础消息结构：

- **`JSONRPCMessage`**: 统一消息类型（Request/Notification/Response/Error）
- **`JSONRPCRequest`**: 客户端发起的请求，包含 `id`, `method`, `params`, 可选的 `trace` (W3C Trace Context)
- **`JSONRPCNotification`**: 单向通知，无响应期望
- **`JSONRPCResponse`**: 成功响应
- **`JSONRPCError`**: 错误响应

#### 2.1.2 客户端请求 (ClientRequest, Lines 257-1606)

定义了客户端可调用的所有方法，按功能分组：

**初始化与账户管理：**
- `initialize` - 协议初始化
- `account/login/start`, `account/login/cancel`, `account/logout` - 认证流程
- `account/rateLimits/read` - 查询速率限制
- `account/read` - 获取账户信息

**Thread 生命周期：**
- `thread/start` - 创建新线程
- `thread/resume` - 恢复已有线程
- `thread/fork` - 分叉线程
- `thread/archive`, `thread/unarchive` - 归档/解归档
- `thread/unsubscribe` - 取消订阅
- `thread/name/set`, `thread/metadata/update` - 元数据管理
- `thread/compact/start` - 上下文压缩
- `thread/shellCommand` - 执行 shell 命令
- `thread/rollback` - 回滚线程历史
- `thread/list`, `thread/loaded/list`, `thread/read` - 查询操作

**Turn 执行：**
- `turn/start` - 开始新的用户回合
- `turn/steer` - 引导/修改进行中的回合
- `turn/interrupt` - 中断回合
- `review/start` - 启动审查流程

**文件系统操作：**
- `fs/readFile`, `fs/writeFile` - 文件读写
- `fs/createDirectory` - 创建目录
- `fs/getMetadata`, `fs/readDirectory` - 元数据查询
- `fs/remove`, `fs/copy` - 删除/复制

**配置管理：**
- `config/read`, `config/value/write`, `config/batchWrite` - 配置读写
- `configRequirements/read` - 读取配置要求
- `externalAgentConfig/detect`, `externalAgentConfig/import` - 外部配置迁移

**MCP 与工具：**
- `mcpServer/oauth/login`, `config/mcpServer/reload` - MCP 服务器管理
- `mcpServerStatus/list` - 查询 MCP 服务器状态
- `skills/list`, `skills/config/write` - Skills 管理
- `plugin/list`, `plugin/read`, `plugin/install`, `plugin/uninstall` - 插件管理
- `app/list` - 应用列表

**命令执行：**
- `command/exec`, `command/exec/write`, `command/exec/terminate`, `command/exec/resize` - 命令执行生命周期

**模型与功能：**
- `model/list` - 可用模型列表
- `experimentalFeature/list` - 实验性功能列表
- `feedback/upload` - 反馈上传

**文件搜索：**
- `fuzzyFileSearch` - 模糊文件搜索

#### 2.1.3 服务器请求 (ServerRequest, Lines 732-790)

服务器向客户端发起的请求（需要客户端响应）：

- `item/commandExecution/requestApproval` - 请求命令执行审批
- `item/fileChange/requestApproval` - 请求文件变更审批
- `item/tool/requestUserInput` - 请求工具用户输入
- `mcpServer/elicitation/request` - MCP 服务器信息收集请求
- `item/permissions/requestApproval` - 请求额外权限
- `item/tool/call` - 动态工具调用
- `account/chatgptAuthTokens/refresh` - 刷新 ChatGPT 认证令牌

#### 2.1.4 服务器通知 (ServerNotification, Lines 874-940)

服务器向客户端发送的单向通知：

**Thread 相关：**
- `thread/started`, `thread/status/changed`, `thread/archived`, `thread/unarchived`, `thread/closed`
- `thread/name/updated`, `thread/tokenUsage/updated`

**Turn 相关：**
- `turn/started`, `turn/completed`
- `turn/diff/updated`, `turn/plan/updated`

**Item 相关：**
- `item/started`, `item/completed`
- `item/agentMessage/delta` - 流式 AI 消息
- `item/plan/delta` - 计划步骤更新（实验性）
- `item/commandExecution/outputDelta`, `item/commandExecution/terminalInteraction`
- `item/fileChange/outputDelta`
- `item/mcpToolCall/progress`
- `item/autoApprovalReview/started`, `item/autoApprovalReview/completed`

**其他：**
- `error` - 通用错误通知
- `hook/started`, `hook/completed`
- `serverRequest/resolved`
- `mcpServer/oauthLogin/completed`
- `account/updated`, `account/rateLimits/updated`
- `app/list/updated`
- `configWarning` - 配置警告

### 2.2 关键数据结构

#### 2.2.1 审批决策类型

**`ReviewDecision`** (Lines 3329-3408): 用户审批决策的联合类型
- `approved` - 简单批准
- `approved_execpolicy_amendment` - 批准并添加执行策略
- `approved_for_session` - 会话级批准
- `network_policy_amendment` - 网络策略修改
- `denied` - 拒绝但继续
- `abort` - 拒绝并中断

#### 2.2.2 沙箱策略

**`SandboxPolicy`** (Lines 1275-1381): 定义代码执行的安全边界
- `DangerFullAccess` - 完全访问（危险）
- `ReadOnly` - 只读访问
- `ExternalSandbox` - 外部沙箱
- `WorkspaceWrite` - 工作区写入

#### 2.2.3 配置层来源

**`ConfigLayerSource`** (Lines 444-496): 配置优先级层
- `Mdm` - MDM 管理配置（最低优先级）
- `System` - 系统级配置
- `User` - 用户配置 (~/.codex/config.toml)
- `Project` - 项目配置 (.codex/config.toml)
- `SessionFlags` - 会话标志（最高优先级）

---

## 3. 具体技术实现

### 3.1 Schema 生成流程

```rust
// 源文件: codex-rs/app-server-protocol/src/export.rs

// 1. 从 Rust 类型生成 JSON Schema
pub fn generate_json_with_experimental(out_dir: &Path, experimental_api: bool) -> Result<()> {
    // 生成信封类型
    let envelope_emitters: Vec<JsonSchemaEmitter> = vec![
        |d| write_json_schema_with_return::<crate::RequestId>(d, "RequestId"),
        |d| write_json_schema_with_return::<crate::JSONRPCMessage>(d, "JSONRPCMessage"),
        // ... 更多信封类型
    ];
    
    // 2. 生成客户端/服务器请求/响应
    schemas.extend(export_client_param_schemas(out_dir)?);
    schemas.extend(export_client_response_schemas(out_dir)?);
    schemas.extend(export_server_param_schemas(out_dir)?);
    schemas.extend(export_server_response_schemas(out_dir)?);
    
    // 3. 构建 schema bundle
    let mut bundle = build_schema_bundle(schemas)?;
    
    // 4. 过滤实验性功能（如需要）
    if !experimental_api {
        filter_experimental_schema(&mut bundle)?;
    }
    
    // 5. 写入最终文件
    write_pretty_json(
        out_dir.join("codex_app_server_protocol.schemas.json"),
        &bundle,
    )?;
}
```

### 3.2 宏驱动的协议定义

**`client_request_definitions!`** 宏 (codex-rs/app-server-protocol/src/protocol/common.rs, Lines 85-203):

```rust
client_request_definitions! {
    Initialize {
        params: v1::InitializeParams,
        response: v1::InitializeResponse,
    },
    ThreadStart => "thread/start" {
        params: v2::ThreadStartParams,
        inspect_params: true,  // 字段级实验性检查
        response: v2::ThreadStartResponse,
    },
    // ... 更多方法
}
```

该宏自动生成：
- `ClientRequest` enum，带 `method` tag 和 serde 属性
- `id()` 和 `method()` 辅助方法
- `ExperimentalApi` trait 实现
- TypeScript 导出函数

### 3.3 实验性功能标记

**`#[experimental(...)]` 属性** (codex-rs/app-server-protocol/src/experimental_api.rs):

```rust
#[derive(ExperimentalApi)]
pub struct ThreadStartParams {
    pub model: Option<String>,
    
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
    
    #[experimental("thread/start.dynamicTools")]
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
    
    #[experimental("thread/start.mockExperimentalField")]
    pub mock_experimental_field: Option<String>,
}
```

运行时检查：
```rust
impl ExperimentalApi for ClientRequest {
    fn experimental_reason(&self) -> Option<&'static str> {
        match self {
            Self::ThreadStart { params, .. } => {
                // 检查 params 中是否有实验性字段
                params.experimental_reason()
            }
            // ...
        }
    }
}
```

### 3.4 v2 命名空间组织

Schema 使用 `v2/` 命名空间组织类型 (Lines 13000+): 

```json
{
  "definitions": {
    "v2": {
      "Thread": { ... },
      "Turn": { ... },
      "AskForApproval": { ... },
      // ... 所有 v2 API 类型
    }
  }
}
```

这种组织方式支持未来 v3 API 的并行开发。

### 3.5 类型映射与转换

**Rust ↔ JSON Schema 映射规则：**

| Rust 类型 | JSON Schema | 说明 |
|-----------|-------------|------|
| `Option<T>` | `anyOf[T, null]` | 可空类型 |
| `Vec<T>` | `array` + `items` | 数组 |
| `HashMap<String, V>` | `object` + `additionalProperties` | 字典 |
| `enum` | `oneOf` 或 `enum` | 联合类型或字符串枚举 |
| `#[serde(tag = "type")]` | `oneOf` + `properties.type` | 标签联合 |
| `#[ts(type = "number")]` | `integer`/`number` | 数值类型覆盖 |

---

## 4. 关键代码路径与文件引用

### 4.1 协议定义层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/lib.rs` | 公共导出，聚合 v1/v2/common 模块 |
| `codex-rs/app-server-protocol/src/protocol/mod.rs` | 模块声明 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 核心宏定义、`ClientRequest`/`ServerRequest`/`ServerNotification` 生成 |
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | 遗留 API 类型（Initialize, ApplyPatchApproval 等） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 新 API 类型（Thread, Turn, Config 等），~3000 行 |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSON-RPC 基础信封类型 |
| `codex-rs/app-server-protocol/src/experimental_api.rs` | 实验性功能标记 trait 和宏 |

### 4.2 Schema 生成层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/src/export.rs` | JSON Schema 和 TypeScript 生成逻辑，~1100 行 |
| `codex-rs/app-server-protocol/src/schema_fixtures.rs` | Schema fixture 读写和测试支持 |
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | 命令行工具：`just write-app-server-schema` |
| `codex-rs/app-server-protocol/src/bin/export.rs` | 独立导出工具 |

### 4.3 服务端实现层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server/src/lib.rs` | App Server 主入口，连接处理 |
| `codex-rs/app-server/src/message_processor.rs` | JSON-RPC 消息分发和处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | Codex 核心消息处理 |
| `codex-rs/app-server/src/config_api.rs` | 配置 RPC 实现 |
| `codex-rs/app-server/src/fs_api.rs` | 文件系统 RPC 实现 |
| `codex-rs/app-server/src/command_exec.rs` | 命令执行 RPC 实现 |

### 4.4 测试层

| 文件 | 职责 |
|------|------|
| `codex-rs/app-server-protocol/tests/schema_fixtures.rs` | Schema fixture 一致性测试 |
| `codex-rs/app-server/tests/suite/v2/*.rs` | 各 API 的集成测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-app-server-protocol
├── codex-protocol (核心协议类型)
├── codex-experimental-api-macros (实验性宏)
├── codex-utils-absolute-path (绝对路径类型)
├── schemars (JSON Schema 生成)
├── ts-rs (TypeScript 生成)
├── serde (序列化)
└── strum (字符串枚举)
```

### 5.2 外部交互

**上游（数据消费者）：**
- **VS Code 扩展**: 通过 WebSocket 连接，使用生成的 TypeScript 类型
- **Codex CLI**: 通过 stdio 连接
- **Codex Cloud**: 内部服务，使用实验性 API

**下游（数据生产者）：**
- **Codex Core**: 核心 AI 逻辑，提供 `codex-protocol` 类型
- **MCP 服务器**: 通过 MCP 协议提供工具和资源

### 5.3 构建工具链

```bash
# 重新生成 schema
just write-app-server-schema

# 带实验性功能的 schema
just write-app-server-schema --experimental

# 测试 schema 一致性
cargo test -p codex-app-server-protocol
```

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 Schema 版本管理

**风险：** v1 和 v2 API 共存，v1 类型（如 `ApplyPatchApprovalParams`）仍在根 definitions 中，可能导致命名冲突。

**代码位置：** Lines 108-146 (v1 ApplyPatchApprovalParams)

```json
"ApplyPatchApprovalParams": {  // 根级别，无 v1/ 前缀
  "$schema": "http://json-schema.org/draft-07/schema#",
  ...
}
```

#### 6.1.2 实验性功能过滤复杂性

**风险：** 实验性字段过滤逻辑复杂，涉及多处（TypeScript 生成、JSON Schema 生成、运行时检查），容易遗漏。

**代码位置：** `export.rs` Lines 246-292, 400-407

#### 6.1.3 大文件问题

**风险：** Schema 文件 14,000+ 行，加载和解析开销大。当前无按需加载机制。

### 6.2 边界情况

#### 6.2.1 类型兼容性

- **Double Option 模式**: `Option<Option<T>>` 用于区分 "未设置" 和 "显式设置为 null"
  ```rust
  #[serde(
      default,
      deserialize_with = "super::serde_helpers::deserialize_double_option",
      serialize_with = "super::serde_helpers::serialize_double_option",
      skip_serializing_if = "Option::is_none"
  )]
  pub service_tier: Option<Option<ServiceTier>>,
  ```

#### 6.2.2 请求 ID 类型

`RequestId` 支持 `String` 或 `Integer` (i64)，但某些语言客户端可能发送浮点数导致解析失败。

#### 6.2.3 路径处理

使用 `AbsolutePathBuf` 类型确保路径绝对性，但在 Windows/Linux 路径格式混用时可能出现问题。

### 6.3 改进建议

#### 6.3.1 短期改进

1. **文档内联**
   - 为复杂字段添加更多 `description`，如 `ThreadResumeParams.history` 的实验性警告
   
2. **Schema 分割**
   - 按功能模块拆分 schema 文件（thread.json, turn.json, config.json）
   - 使用 `$ref` 跨文件引用

3. **废弃标记**
   - 为 v1 API 添加明确的 `deprecated` 标记
   ```json
   "ApplyPatchApprovalParams": {
     "deprecated": true,
     "x-deprecated-reason": "Use item/commandExecution/requestApproval instead"
   }
   ```

#### 6.3.2 中期改进

1. **OpenAPI 迁移**
   - 考虑迁移到 OpenAPI 3.0，获得更好的生态工具支持
   - 保留 JSON Schema 作为组件定义

2. **版本协商**
   - 在 `initialize` 中添加协议版本协商
   ```json
   {
     "protocolVersion": "2024-03-15",
     "supportedVersions": ["2024-03-15", "2024-01-01"]
   }
   ```

3. **增量 Schema 生成**
   - 仅生成变更的类型，减少 CI 时间和文件大小

#### 6.3.3 长期改进

1. **类型安全增强**
   - 使用 `newtype` 模式包装 ID 类型（ThreadId, TurnId, ItemId）
   - 防止 ID 类型混用（如将 TurnId 当作 ThreadId 传递）

2. **性能优化**
   - 引入二进制序列化选项（MessagePack）用于高频消息
   - 保持 JSON 用于调试和兼容性

3. **治理自动化**
   - 自动化 API 变更检测和兼容性报告
   - 集成 breaking change 检测工具

---

## 7. 附录

### 7.1 关键行号索引

| 概念 | 行号范围 |
|------|----------|
| JSON-RPC 基础类型 | 2280-2396 |
| ClientRequest 定义 | 257-1606 |
| ServerRequest 定义 | 732-790 |
| ServerNotification 定义 | 874-940 |
| ReviewDecision | 3329-3408 |
| SandboxPolicy | 1275-1381 (v2.rs) |
| ConfigLayerSource | 444-496 (v2.rs) |
| Thread 类型 | 13000+ (v2 namespace) |
| Turn 类型 | 13677-14000 (v2 namespace) |

### 7.2 相关命令

```bash
# 阅读 schema 文件
head -n 100 codex_app_server_protocol.schemas.json

# 统计类型数量
grep -c '"title"' codex_app_server_protocol.schemas.json

# 查找特定方法定义
grep -n '"thread/start"' codex_app_server_protocol.schemas.json

# 生成并对比
cargo test -p codex-app-server-protocol --test schema_fixtures
```

### 7.3 参考资料

- [JSON Schema Draft 07](https://json-schema.org/draft-07/schema)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Codex App Server README](../../../../../../codex-rs/app-server/README.md)
