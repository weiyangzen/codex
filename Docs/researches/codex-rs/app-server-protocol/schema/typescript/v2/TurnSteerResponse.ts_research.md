# TurnSteerResponse.ts Research Document

## 场景与职责

`TurnSteerResponse` 是 App-Server Protocol v2 中的服务器响应类型，用于确认 `turn/steer` 请求的处理结果。该类型在以下场景中发挥关键作用：

1. **操作确认**: 向客户端确认 steer 操作已成功接收并处理
2. **状态同步**: 返回当前回合的 ID，帮助客户端确认服务器端状态
3. **乐观更新验证**: 客户端可以对比返回的 `turnId` 与预期值，验证状态一致性
4. **错误边界**: 作为成功响应的载体，与错误响应（JSON-RPC error）形成完整的结果处理

## 功能点目的

该响应类型的核心目的是：

- **成功确认**: 明确告知客户端 steer 操作已成功
- **ID 回显**: 返回确认的回合 ID，支持客户端状态验证
- **协议完整性**: 完成 `turn/steer` 请求-响应循环
- **调试支持**: 提供可用于日志记录和调试的标识信息

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnSteerResponse = { 
  turnId: string, 
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnSteerResponse {
    pub turn_id: String,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `turnId` | `string` | 被 steer 的回合的唯一标识符 |

### 序列化特性

- **命名规范**: 使用 `camelCase` 进行序列化（`turn_id` → `"turnId"`）
- **派生特性**: 实现了 `Serialize`, `Deserialize`, `Debug`, `Clone`, `PartialEq`, `JsonSchema`, `TS`
- **非默认派生**: 未实现 `Default`，因为 `turnId` 是必需字段且应由服务器生成

### 响应流程

```
客户端发送: ClientRequest::TurnSteer { params: TurnSteerParams }
                    │
                    ▼
服务器处理: 验证 expectedTurnId, 添加 input
                    │
                    ▼
服务器响应: ClientResponse::TurnSteer(TurnSteerResponse { turnId })
                    │
                    ▼
客户端接收: 验证 turnId 与 expectedTurnId 匹配
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3952-3957) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnSteerResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnSteerResponse.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 `turn/steer` 方法的响应类型 |
| `codex-rs/app-server-protocol/schema/json/ClientRequest.json` | 在客户端请求 schema 中引用响应类型 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 构造并返回 steer 响应 |
| `codex-rs/tui_app_server/src/app_server_session.rs` | 处理 steer 响应 |
| `codex-rs/app-server/tests/suite/v2/turn_steer.rs` | 测试中验证响应内容 |

### 请求-响应映射

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    TurnSteer => "turn/steer" {
        params: TurnSteerParams,
        response: TurnSteerResponse,
    },
    // ...
}
```

## 依赖与外部交互

### 内部依赖

- **`TurnSteerParams`**: 对应的请求参数类型
- **`Turn`**: 响应中的 `turnId` 来源于 Turn 结构

### 协议依赖

- 属于 **Client Response** 类别（服务器 → 客户端）
- 对应 RPC 方法: `turn/steer`
- 错误处理: 如果 steer 失败，返回 JSON-RPC error 而非此响应

### 错误响应对比

| 场景 | 响应类型 | 说明 |
|-----|---------|------|
| 成功 | `TurnSteerResponse` | 包含确认的 `turnId` |
| expectedTurnId 不匹配 | JSON-RPC Error | code: -32000, message: "turn mismatch" |
| 回合不存在 | JSON-RPC Error | code: -32602, message: "invalid params" |
| 服务器内部错误 | JSON-RPC Error | code: -32603, message: "internal error" |

## 风险、边界与改进建议

### 潜在风险

1. **响应延迟**: 如果 steer 操作涉及复杂处理，响应延迟可能影响用户体验
2. **ID 不匹配**: 客户端需要正确处理返回的 `turnId` 与预期不匹配的情况（理论上不应发生）
3. **响应丢失**: 在网络不稳定场景下，成功响应可能丢失，导致客户端重试

### 边界情况

1. **快速连续 steer**: 多个 steer 请求的快速响应顺序需要保证
2. **回合在 steer 期间完成**: 如果回合在 steer 处理期间完成，响应中仍返回原 turnId
3. ** steer 后立即可见性**: steer 添加的输入何时在 UI 中可见需要明确定义

### 改进建议

1. **添加时间戳**: 考虑添加处理时间戳，便于性能分析：
   ```typescript
   export type TurnSteerResponse = {
     turnId: string,
     processedAt: number, // Unix timestamp
   };
   ```

2. **输入确认**: 返回实际接收并处理的输入摘要：
   ```typescript
   export type TurnSteerResponse = {
     turnId: string,
     acceptedInputs: number,
     inputSummary: string, // 截断的输入预览
   };
   ```

3. **状态快照**: 返回 steer 后的回合状态快照：
   ```typescript
   export type TurnSteerResponse = {
     turnId: string,
     turnStatus: TurnStatus, // steer 后的状态
   };
   ```

4. **队列位置**: 如果 steer 需要排队处理，返回队列信息：
   ```typescript
   export type TurnSteerResponse = {
     turnId: string,
     queuePosition?: number,
     estimatedWaitMs?: number,
   };
   ```

5. **版本标记**: 添加协议版本或特性标记，支持未来扩展：
   ```typescript
   export type TurnSteerResponse = {
     turnId: string,
     version: "v2.0",
   };
   ```

### 测试覆盖

- 基础响应测试: `codex-rs/app-server/tests/suite/v2/turn_steer.rs`
- 响应字段验证: 确保 `turnId` 格式正确且与请求匹配
- 建议添加：
  - 响应时间性能测试
  - 高并发场景下的响应一致性测试
  - 网络分区恢复后的响应重传测试
