# ServerRequest.ts 研究文档

## 1. 场景与职责

ServerRequest 是 Codex app-server 协议中服务器向客户端发起请求的核心类型。与通知不同，请求需要客户端返回响应。主要应用场景包括：

- **执行审批**: 请求用户批准 shell 命令执行（`item/commandExecution/requestApproval`）
- **文件变更审批**: 请求用户批准代码补丁应用（`item/fileChange/requestApproval`）
- **用户输入请求**: 请求用户提供特定输入（`item/tool/requestUserInput`）
- **MCP 服务器询问**: 请求用户响应 MCP 服务器的询问（`mcpServer/elicitation/request`）
- **权限请求**: 请求用户授予额外权限（`item/permissions/requestApproval`）
- **动态工具调用**: 请求客户端执行动态工具调用（`item/tool/call`）
- **ChatGPT Token 刷新**: 请求刷新 ChatGPT 认证令牌

## 2. 功能点目的

ServerRequest 实现了 JSON-RPC 风格的请求-响应模式：

1. **审批流程**: 在敏感操作前获取用户明确授权
2. **交互式工具**: 支持需要用户输入的工具调用
3. **外部系统集成**: 与 MCP 服务器、OAuth 等外部系统交互
4. **安全控制**: 通过审批机制控制 AI 的执行权限

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
export type ServerRequest = 
  | { "method": "item/commandExecution/requestApproval", id: RequestId, params: CommandExecutionRequestApprovalParams }
  | { "method": "item/fileChange/requestApproval", id: RequestId, params: FileChangeRequestApprovalParams }
  | { "method": "item/tool/requestUserInput", id: RequestId, params: ToolRequestUserInputParams }
  | { "method": "mcpServer/elicitation/request", id: RequestId, params: McpServerElicitationRequestParams }
  | { "method": "item/permissions/requestApproval", id: RequestId, params: PermissionsRequestApprovalParams }
  | { "method": "item/tool/call", id: RequestId, params: DynamicToolCallParams }
  | { "method": "account/chatgptAuthTokens/refresh", id: RequestId, params: ChatgptAuthTokensRefreshParams }
  | { "method": "applyPatchApproval", id: RequestId, params: ApplyPatchApprovalParams }
  | { "method": "execCommandApproval", id: RequestId, params: ExecCommandApprovalParams };
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (lines 543-638, 732-790):

```rust
macro_rules! server_request_definitions {
    (
        $(
            $(#[$variant_meta:meta])*
            $variant:ident $(=> $wire:literal)? {
                params: $params:ty,
                response: $response:ty,
            }
        ),* $(,)?
    ) => {
        #[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
        #[allow(clippy::large_enum_variant)]
        #[serde(tag = "method", rename_all = "camelCase")]
        pub enum ServerRequest {
            $(
                $(#[$variant_meta])*
                $(#[serde(rename = $wire)] #[ts(rename = $wire)])?
                $variant {
                    #[serde(rename = "id")]
                    request_id: RequestId,
                    params: $params,
                },
            )*
        }
        // ... 实现
    };
}

// 实际请求定义
server_request_definitions! {
    CommandExecutionRequestApproval => "item/commandExecution/requestApproval" {
        params: v2::CommandExecutionRequestApprovalParams,
        response: v2::CommandExecutionRequestApprovalResponse,
    },
    FileChangeRequestApproval => "item/fileChange/requestApproval" {
        params: v2::FileChangeRequestApprovalParams,
        response: v2::FileChangeRequestApprovalResponse,
    },
    // ... 更多定义
}
```

### 关键特性

1. **请求-响应对**: 每个请求都有对应的 params 和 response 类型
2. **RequestId**: 使用 `RequestId` 类型（string 或 number）关联请求和响应
3. **JSON-RPC 兼容**: 使用 `method`、`id`、`params` 字段结构
4. **Payload 枚举**: `ServerRequestPayload` 用于构造请求

### 辅助类型

```rust
#[derive(Debug, Clone, PartialEq, JsonSchema)]
pub enum ServerRequestPayload {
    CommandExecutionRequestApproval(v2::CommandExecutionRequestApprovalParams),
    // ...
}

impl ServerRequestPayload {
    pub fn request_with_id(self, request_id: RequestId) -> ServerRequest {
        // 构造完整请求
    }
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 宏定义 (lines 543-638) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` | 请求变体定义 (lines 732-790) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` | 各请求 params 和 response 类型定义 |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ServerRequest.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **JSON-RPC**: 协议风格遵循 JSON-RPC 2.0

### 外部交互

- **客户端响应**: 客户端必须返回对应的 response 类型
- **审批系统**: 与 Guardian 审批子系统集成
- **MCP 服务器**: MCP 询问请求与 MCP 服务器交互
- **OAuth 系统**: ChatGPT Token 刷新与认证系统交互

## 6. 风险、边界与改进建议

### 风险

1. **请求超时**: 客户端可能不响应，需要超时处理
2. **并发请求**: 多个并发请求需要正确匹配响应
3. **版本兼容性**: 新旧客户端对请求的处理可能不同

### 边界情况

1. **重复请求 ID**: 需要检测和处理重复的请求 ID
2. **客户端断开**: 请求发送后客户端断开连接
3. **响应延迟**: 用户长时间不响应审批请求
4. **嵌套请求**: 处理请求过程中产生新的请求

### 改进建议

1. **请求超时**: 添加请求级超时配置
2. **请求队列**: 实现请求队列管理并发请求
3. **取消机制**: 支持客户端取消待处理的请求
4. **请求优先级**: 重要请求优先处理
5. **批量审批**: 支持批量处理多个审批请求
6. **审批预览**: 在审批请求中提供更多上下文信息
7. **异步处理**: 支持异步请求-响应模式
