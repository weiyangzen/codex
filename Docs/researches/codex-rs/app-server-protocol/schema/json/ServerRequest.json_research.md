# ServerRequest.json 深入研究

## 场景与职责

`ServerRequest.json` 是 Codex App Server Protocol 的核心 JSON Schema 文件，定义了**服务器向客户端发起请求**的所有可能消息类型。该文件作为协议规范的权威来源，用于：

1. **协议契约定义**：明确服务器可以发送给客户端的请求格式
2. **代码生成基础**：通过 `schemars` 和 `ts-rs` 生成 TypeScript 类型和 JSON Schema
3. **运行时验证**：客户端使用该 schema 验证收到的服务器请求
4. **文档生成**：为客户端开发者提供 API 参考

该文件位于 `codex-rs/app-server-protocol/schema/json/ServerRequest.json`，是自动生成的产物，其源头是 Rust 源码中的 `server_request_definitions!` 宏定义。

## 功能点目的

### 1. 请求类型枚举（OneOf 结构）

ServerRequest 采用 JSON Schema 的 `oneOf` 结构定义了 9 种服务器请求类型：

| 请求类型 | 方法名 | 用途 | 状态 |
|---------|--------|------|------|
| CommandExecutionRequestApproval | `item/commandExecution/requestApproval` | 请求用户批准命令执行 | NEW API |
| FileChangeRequestApproval | `item/fileChange/requestApproval` | 请求用户批准文件变更 | NEW API |
| ToolRequestUserInput | `item/tool/requestUserInput` | 请求用户为工具调用提供输入 | EXPERIMENTAL |
| McpServerElicitationRequest | `mcpServer/elicitation/request` | MCP 服务器请求用户输入 | 稳定 |
| PermissionsRequestApproval | `item/permissions/requestApproval` | 请求额外权限批准 | 稳定 |
| DynamicToolCall | `item/tool/call` | 在客户端执行动态工具调用 | 稳定 |
| ChatgptAuthTokensRefresh | `account/chatgptAuthTokens/refresh` | 请求刷新 ChatGPT 认证令牌 | 稳定 |
| ApplyPatchApproval (DEPRECATED) | `applyPatchApproval` | 旧版补丁批准请求 | 已弃用 |
| ExecCommandApproval (DEPRECATED) | `execCommandApproval` | 旧版命令执行批准 | 已弃用 |

### 2. 通用字段结构

每个请求类型都包含以下通用字段：

```json
{
  "id": "请求标识符（string 或 integer）",
  "method": "请求方法名（string）",
  "params": "方法特定的参数对象"
}
```

### 3. 命令执行批准决策类型

定义了丰富的决策选项，支持多种用户交互模式：

- `accept`：单次批准
- `acceptForSession`：会话级批准
- `acceptWithExecpolicyAmendment`：带执行策略修正的批准
- `applyNetworkPolicyAmendment`：应用网络策略修正
- `decline`：拒绝但继续会话
- `cancel`：拒绝并中断当前 turn

### 4. 文件变更类型定义

支持三种文件变更操作：

- `add`：添加新文件（含完整内容）
- `delete`：删除文件（含删除前内容）
- `update`：更新文件（含 unified diff）

## 具体技术实现

### 1. Schema 生成流程

```rust
// 源头：codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    CommandExecutionRequestApproval => "item/commandExecution/requestApproval" {
        params: v2::CommandExecutionRequestApprovalParams,
        response: v2::CommandExecutionRequestApprovalResponse,
    },
    // ... 其他请求类型
}
```

生成流程：
1. Rust 宏 `server_request_definitions!` 展开为 `ServerRequest` enum
2. `schemars::JsonSchema` derive 宏生成 JSON Schema
3. `export.rs` 中的 `export_server_param_schemas()` 写入单独 JSON 文件
4. `build_schema_bundle()` 合并为最终的 `ServerRequest.json`

### 2. 关键数据结构映射

#### RequestId 类型（多态标识符）
```json
"RequestId": {
  "anyOf": [
    { "type": "string" },
    { "type": "integer", "format": "int64" }
  ]
}
```

支持字符串或整数 ID，符合 JSON-RPC 2.0 规范。

#### CommandAction 类型（命令解析结果）
```json
"CommandAction": {
  "oneOf": [
    { "title": "ReadCommandAction", ... },
    { "title": "ListFilesCommandAction", ... },
    { "title": "SearchCommandAction", ... },
    { "title": "UnknownCommandAction", ... }
  ]
}
```

用于向用户友好展示命令意图。

### 3. 实验性功能标记

Schema 中通过 `description` 字段标记实验性功能：
- `"EXPERIMENTAL. Params sent with a request_user_input event."`
- 实验性字段在生成稳定版 schema 时会被过滤掉（见 `export.rs` 中的 `filter_experimental_schema`）

### 4. 嵌套定义组织

所有相关类型都在 `definitions` 节中内联定义，包括：
- `AbsolutePathBuf`：绝对路径类型
- `AdditionalPermissionProfile`：额外权限配置
- `McpElicitationSchema` 及其子类型：MCP 引导表单 schema
- `ParsedCommand`：解析后的命令结构
- `ToolRequestUserInput*` 系列类型

## 关键代码路径与文件引用

### 源头定义
| 文件 | 职责 |
|------|------|
| `src/protocol/common.rs` | `server_request_definitions!` 宏定义，ServerRequest enum |
| `src/protocol/v2.rs` | 所有 v2 API 的 params/response 类型定义 |
| `src/protocol/v1.rs` | 废弃 API 的类型定义（ApplyPatchApprovalParams 等） |

### 生成代码
| 文件 | 职责 |
|------|------|
| `src/export.rs` | Schema 生成逻辑，`generate_json()` 函数 |
| `src/bin/write_schema_fixtures.rs` | 二进制工具，写入 schema fixtures |
| `src/schema_fixtures.rs` | Fixture 读取/写入辅助函数 |

### 输出文件
| 文件 | 职责 |
|------|------|
| `schema/json/ServerRequest.json` | 本文件，服务器请求 schema |
| `schema/typescript/ServerRequest.ts` | 生成的 TypeScript 类型 |
| `schema/json/codex_app_server_protocol.schemas.json` | 完整 schema bundle |

### 测试文件
| 文件 | 职责 |
|------|------|
| `tests/schema_fixtures.rs` | Schema fixture 一致性测试 |
| `src/protocol/common.rs` (mod tests) | 序列化/反序列化测试 |

## 依赖与外部交互

### 内部依赖
1. **codex-protocol crate**：核心类型定义（`CoreReviewDecision`, `CoreParsedCommand` 等）
2. **codex-experimental-api-macros**：`#[experimental(...)]` 属性宏
3. **codex-utils-absolute-path**：`AbsolutePathBuf` 类型

### 外部协议依赖
1. **JSON-RPC 2.0**：基础消息格式（id, method, params 结构）
2. **MCP (Model Context Protocol)**：`McpElicitationSchema` 兼容 MCP 表单规范

### 消费者
1. **codex-cli**：命令行客户端处理服务器请求
2. **VS Code Extension**：IDE 插件处理批准请求
3. **codex-tui**：终端 UI 客户端

## 风险、边界与改进建议

### 当前风险

1. **实验性功能稳定性**
   - `ToolRequestUserInput` 标记为 EXPERIMENTAL，API 可能变更
   - 实验性字段过滤逻辑复杂，可能导致意外行为

2. **废弃 API 维护负担**
   - `applyPatchApproval` 和 `execCommandApproval` 仍保留在 schema 中
   - 需要维护两套并行的批准流程代码

3. **类型膨胀**
   - 单个 schema 文件包含 50+ 个定义，大小超过 43KB
   - 加载和验证性能可能受影响

### 边界情况

1. **RequestId 多态处理**
   - 客户端必须同时处理 string 和 integer 类型的 id
   - 序列化时保持类型一致性

2. **路径验证**
   - `AbsolutePathBuf` 要求绝对路径，相对路径会导致反序列化失败
   - 需要明确的错误处理

3. **可选字段默认值**
   - 大量字段使用 `Option<T>` 配合 `#[serde(default)]`
   - 客户端不能假设任何可选字段一定存在

### 改进建议

1. **Schema 拆分**
   ```
   建议将 ServerRequest.json 按功能拆分为：
   - ServerRequest.Core.json（核心请求）
   - ServerRequest.Approval.json（批准相关）
   - ServerRequest.Experimental.json（实验性功能）
   ```

2. **版本化策略**
   - 当前通过 `NEW APIs` / `DEPRECATED APIs` 注释标记
   - 建议引入正式的版本号字段（`apiVersion`）

3. **增强文档**
   - 为每个请求类型添加使用示例
   - 在 schema 中嵌入 `examples` 字段

4. **实验性功能隔离**
   - 考虑将实验性功能完全分离到独立的 schema 文件
   - 通过 feature flag 控制是否包含在稳定 bundle 中

5. **废弃 API 清理计划**
   - 制定明确的废弃 API 移除时间表
   - 在 schema 中添加 `deprecated: true` 标记（JSON Schema draft 2019-09 支持）
