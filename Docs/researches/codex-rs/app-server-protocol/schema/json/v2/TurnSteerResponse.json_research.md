# TurnSteerResponse.json 研究文档

## 场景与职责

`TurnSteerResponse` 是 Codex App-Server Protocol v2 中 `turn/steer` RPC 方法的响应结构。它在客户端发送 steer 请求后返回，确认 steer 操作已成功应用并返回当前 Turn ID。

**核心职责：**
- 确认 steer 操作成功
- 返回当前活跃 Turn 的 ID
- 与 `TurnSteerParams` 中的 `expected_turn_id` 形成验证闭环

## 功能点目的

### 1. 操作确认
`turn_id` 字段确认：
- Steer 操作已成功处理
- 返回的 Turn ID 与请求中的 `expected_turn_id` 一致
- 客户端可以继续跟踪该 Turn 的状态

### 2. 状态同步
响应提供简单的成功确认：
- 无复杂数据结构，仅返回 Turn ID
- 客户端通过通知（如 `item/started`）获取实际效果
- 与 `turn/start` 的完整 `Turn` 响应形成对比

### 3. 轻量级设计
响应结构极简：
- 仅包含 `turn_id` 一个字段
- 快速响应，不等待 AI 处理结果
- 实际处理效果通过异步通知传达

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnSteerResponse {
    pub turn_id: String,
}
```

### 与 TurnStartResponse 的对比

| 特性 | TurnStartResponse | TurnSteerResponse |
|------|-------------------|-------------------|
| 结构 | 包含完整 `Turn` 对象 | 仅 `turn_id` 字符串 |
| 数据量 | 大（可能包含 items） | 极小 |
| 同步性 | 同步创建 Turn | 同步确认 steer |
| 状态信息 | 完整 Turn 状态 | 仅 ID 确认 |
| 后续通知 | `turn/started`, `turn/completed` | `item/started` 等 |

### 关键流程

1. **接收请求**：服务器接收 `turn/steer` RPC 请求
2. **验证**：检查 `expected_turn_id` 是否匹配当前活跃 Turn
3. **应用 steer**：将新输入添加到 Turn
4. **返回响应**：返回 `TurnSteerResponse` 确认成功
5. **异步通知**：发送 `item/started` 等通知

### 成功响应示例

```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "result": {
    "turnId": "turn-456"
  }
}
```

### 错误响应示例

```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "error": {
    "code": -32600,
    "message": "Invalid request: turn id mismatch"
  }
}
```

## 关键代码路径与文件引用

### 定义位置
- `TurnSteerResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3955`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:356-359`
  ```rust
  TurnSteer => "turn/steer" {
      params: v2::TurnSteerParams,
      response: v2::TurnSteerResponse,
  },
  ```

### 测试覆盖
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/turn_steer.rs:243-264`
  ```rust
  let steer_req = mcp
      .send_turn_steer_request(TurnSteerParams {
          thread_id: thread.id.clone(),
          input: vec![V2UserInput::Text {
              text: "steer".to_string(),
              text_elements: Vec::new(),
          }],
          expected_turn_id: turn.id.clone(),
      })
      .await?;
  let steer_resp: JSONRPCResponse = timeout(
      DEFAULT_READ_TIMEOUT,
      mcp.read_stream_until_response_message(RequestId::Integer(steer_req)),
  ).await??;
  let steer: TurnSteerResponse = to_response::<TurnSteerResponse>(steer_resp)?;
  assert_eq!(steer.turn_id, turn.id);
  ```

### 相关类型
- `TurnSteerParams`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3944`

## 依赖与外部交互

### 上游依赖
- 无特殊依赖，仅使用标准 `String` 类型

### 下游消费
- 客户端确认 steer 成功
- 客户端验证返回的 `turn_id` 与预期一致

### 协议集成
- 作为 JSON-RPC 2.0 响应的 `result` 字段
- 请求方法: `turn/steer`
- 请求参数: `TurnSteerParams`

## 风险、边界与改进建议

### 已知风险

1. **信息不足**
   - 响应仅包含 Turn ID，无其他状态信息
   - 客户端需要单独查询或等待通知获取更新后的状态

2. **时序不确定性**
   - 响应返回后，steer 的实际处理可能尚未开始
   - 客户端不能假设响应返回即表示 AI 已看到 steer 输入

### 边界情况

1. **Turn 状态变化**
   - 响应返回后，Turn 可能立即完成或失败
   - 客户端需要处理这种竞态条件

2. **重复 steer**
   - 同一 Turn 可以被多次 steer
   - 每次 steer 都会返回相同的 Turn ID

### 改进建议

1. **响应增强**
   - 考虑添加 `steer_id` 用于追踪具体 steer 操作
   - 考虑添加 `timestamp` 记录 steer 处理时间

2. **状态信息**
   - 考虑添加简化的 Turn 状态摘要（如 `status` 字段）
   - 帮助客户端避免额外的状态查询

3. **确认机制**
   - 考虑添加 steer 确认通知（如 `turn/steered`）
   - 明确告知客户端 steer 已被 AI 处理

4. **批量支持**
   - 考虑支持批量 steer 响应
   - 返回多个 steer 操作的结果

5. **错误细化**
   - 为不同的失败场景提供更具体的错误代码
   - 如 Turn 已完成、Turn 不存在、输入无效等
