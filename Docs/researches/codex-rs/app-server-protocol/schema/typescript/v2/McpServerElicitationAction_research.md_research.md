# McpServerElicitationAction 研究文档

## 场景与职责

`McpServerElicitationAction` 是 MCP (Model Context Protocol) 服务器引导请求的用户响应动作枚举。它定义了客户端在处理 MCP 服务器的 `elicitation/create` 请求后，可以采取的三种可能的响应动作。

该类型是 app-server v2 API 中 ServerRequest 的 `McpServerElicitationRequest` 方法的响应类型 `McpServerElicitationRequestResponse` 的核心字段。

## 功能点目的

### 核心功能
1. **标准化用户决策**：统一 MCP 引导请求的用户响应语义
2. **支持三种操作**：接受(Accept)、拒绝(Decline)、取消(Cancel)
3. **协议桥接**：在 Codex 内部协议与 RMCP (Rust MCP) 协议之间进行转换

### 动作语义
| 动作 | 含义 | 使用场景 |
|------|------|----------|
| `Accept` | 接受引导请求 | 用户填写表单并提交，或同意打开 URL |
| `Decline` | 拒绝引导请求 | 用户明确拒绝，但希望继续当前对话 |
| `Cancel` | 取消引导请求 | 用户希望中断当前操作/对话 |

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 5127-5164)
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum McpServerElicitationAction {
    Accept,
    Decline,
    Cancel,
}

impl McpServerElicitationAction {
    pub fn to_core(self) -> codex_protocol::approvals::ElicitationAction {
        match self {
            Self::Accept => codex_protocol::approvals::ElicitationAction::Accept,
            Self::Decline => codex_protocol::approvals::ElicitationAction::Decline,
            Self::Cancel => codex_protocol::approvals::ElicitationAction::Cancel,
        }
    }
}

// 转换到 rmcp 类型
impl From<McpServerElicitationAction> for rmcp::model::ElicitationAction {
    fn from(value: McpServerElicitationAction) -> Self {
        match value {
            McpServerElicitationAction::Accept => Self::Accept,
            McpServerElicitationAction::Decline => Self::Decline,
            McpServerElicitationAction::Cancel => Self::Cancel,
        }
    }
}

// 从 rmcp 类型转换
impl From<rmcp::model::ElicitationAction> for McpServerElicitationAction {
    fn from(value: rmcp::model::ElicitationAction) -> Self {
        match value {
            rmcp::model::ElicitationAction::Accept => Self::Accept,
            rmcp::model::ElicitationAction::Decline => Self::Decline,
            rmcp::model::ElicitationAction::Cancel => Self::Cancel,
        }
    }
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/McpServerElicitationAction.ts
export type McpServerElicitationAction = "accept" | "decline" | "cancel";
```

### 在响应类型中的使用

```rust
// McpServerElicitationRequestResponse (lines 5559-5572)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerElicitationRequestResponse {
    pub action: McpServerElicitationAction,
    /// 接受引导时的结构化用户输入
    pub content: Option<JsonValue>,
    /// 客户端元数据
    pub meta: Option<JsonValue>,
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 5127-5135：枚举定义
  - 行 5137-5144：`to_core()` 方法
  - 行 5147-5164：`rmcp` 双向转换实现

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `McpServerElicitationRequestResponse` | v2.rs | 5559-5572 | 包含此枚举的响应类型 |
| `McpServerElicitationRequestParams` | v2.rs | 5167-5185 | 对应的请求参数类型 |
| `McpServerElicitationRequest` | v2.rs | 5504-5528 | 引导请求体枚举 |

### 核心协议集成
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 754-758)
server_request_definitions! {
    McpServerElicitationRequest => "mcpServer/elicitation/request" {
        params: v2::McpServerElicitationRequestParams,
        response: v2::McpServerElicitationRequestResponse,  // 使用此枚举
    },
}
```

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationAction.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/McpServerElicitationRequestResponse.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：序列化支持

### 外部协议依赖
1. **rmcp crate**：Rust MCP 实现
   - `rmcp::model::ElicitationAction`：底层 MCP 协议动作类型
   - `rmcp::model::CreateElicitationResult`：MCP 引导结果类型

2. **codex_protocol**：核心协议
   - `codex_protocol::approvals::ElicitationAction`：内部核心动作类型

### 转换流程
```
Client Response
    ↓
McpServerElicitationRequestResponse (v2 API)
    ↓
McpServerElicitationAction::to_core()
    ↓
codex_protocol::approvals::ElicitationAction (内部)
    ↓
rmcp::model::ElicitationAction (MCP 协议)
    ↓
MCP Server
```

## 风险、边界与改进建议

### 潜在风险
1. **语义混淆**：`Decline` 和 `Cancel` 的区别可能不够直观
   - `Decline`：拒绝此请求，但继续对话
   - `Cancel`：完全中断当前操作
   - 建议：在 UI 层面提供清晰的标签说明

2. **缺少部分接受**：无法表达"接受但修改内容"的场景

### 边界情况
1. **空 content 处理**：当 `action` 为 `Accept` 时，`content` 应该非空，但没有编译时保证
2. **元数据丢失**：`meta` 字段为可选，某些 MCP 服务器可能依赖此字段

### 改进建议
1. **添加验证方法**：
   ```rust
   impl McpServerElicitationRequestResponse {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if matches!(self.action, McpServerElicitationAction::Accept) 
               && self.content.is_none() {
               return Err(ValidationError::MissingContent);
           }
           Ok(())
       }
   }
   ```

2. **文档增强**：添加每个变体的详细使用场景说明

3. **考虑扩展**：未来可能需要添加 `AcceptWithModification` 变体

### 测试覆盖
相关测试位于 `v2.rs` 测试模块（约行 7138+）：
```rust
#[test]
fn test_elicitation_response_conversion() {
    let response = McpServerElicitationRequestResponse {
        action: McpServerElicitationAction::Accept,
        content: Some(json!({"key": "value"})),
        meta: None,
    };
    let rmcp_result: rmcp::model::CreateElicitationResult = response.into();
    // 验证转换正确性
}
```

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ServerRequest 的响应类型，变更会影响所有客户端实现
- 建议保持向后兼容，如需扩展应添加新字段而非修改枚举
