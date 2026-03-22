# TurnSteerParams.json 研究文档

## 场景与职责

`TurnSteerParams` 是 Codex App-Server Protocol v2 中用于在活跃 Turn 进行中"引导"或"修正"对话方向的请求参数结构。它是 `turn/steer` RPC 方法的核心输入，允许用户在 AI 处理过程中提供额外输入或纠正。

**核心职责：**
- 标识目标线程 (`thread_id`)
- 标识目标 Turn (`expected_turn_id`) - 用于并发控制
- 承载额外的用户输入 (`input`) - 支持相同的 UserInput 类型
- 实现"人机协作"模式，允许实时干预 AI 处理

## 功能点目的

### 1. 实时干预机制
与 `turn/start` 不同，`turn/steer` 用于：
- Turn 已经开始但尚未完成时
- 用户想要提供额外上下文或纠正方向
- AI 正在执行长时间运行的命令时提供指导

### 2. 并发安全
`expected_turn_id` 字段提供乐观并发控制：
- 确保操作针对的是预期的活跃 Turn
- 如果 Turn ID 不匹配（例如 Turn 已完成或切换），请求失败
- 防止操作过期或错误的 Turn

### 3. 输入扩展
`input` 字段支持与 `TurnStartParams` 相同的 `UserInput` 类型：
- **Text**: 文本纠正或额外指令
- **Image**: 额外参考图片
- **LocalImage**: 本地图片补充
- **Skill**: 引入额外 Skill
- **Mention**: 提及额外实体

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnSteerParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    /// Required active turn id precondition. The request fails when it does not
    /// match the currently active turn.
    pub expected_turn_id: String,
}
```

### 与 TurnStartParams 的对比

| 字段 | TurnStartParams | TurnSteerParams |
|------|-----------------|-----------------|
| thread_id | 必填 | 必填 |
| input | 必填 | 必填 |
| expected_turn_id | 无 | 必填 |
| cwd | 可选覆盖 | 不支持 |
| approval_policy | 可选覆盖 | 不支持 |
| sandbox_policy | 可选覆盖 | 不支持 |
| model | 可选覆盖 | 不支持 |
| ...其他覆盖 | 支持 | 不支持 |

### 关键流程

1. **前置验证**：
   - 验证 `thread_id` 存在
   - 验证 `expected_turn_id` 与当前活跃 Turn 匹配
   - 验证输入大小不超过限制

2. **输入处理**：
   - 将新输入添加到当前 Turn
   - 触发 `item/started` 通知（UserMessage 类型）

3. **AI 响应**：
   - 如果 AI 正在等待输入，继续处理
   - 如果 AI 正在执行命令，可能中断或调整

### 错误处理

```rust
// expected_turn_id 不匹配时的错误
assert_eq!(steer_err.error.code, -32600); // Invalid request
```

## 关键代码路径与文件引用

### 定义位置
- `TurnSteerParams`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3944`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:356-359`
  ```rust
  TurnSteer => "turn/steer" {
      params: v2::TurnSteerParams,
      response: v2::TurnSteerResponse,
  },
  ```

### 测试覆盖
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/turn_steer.rs`
  - `turn_steer_requires_active_turn`: 验证 Turn ID 不匹配时的错误
  - `turn_steer_rejects_oversized_text_input`: 验证输入大小限制
  - `turn_steer_returns_active_turn_id`: 验证成功场景

### 响应类型
- `TurnSteerResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3955`
  ```rust
  pub struct TurnSteerResponse {
      pub turn_id: String,
  }
  ```

## 依赖与外部交互

### 上游依赖
- `UserInput`: 与 TurnStartParams 共享相同的输入类型
- `MAX_USER_INPUT_TEXT_CHARS`: 输入大小限制常量

### 下游消费
- App-Server 的 `turn/steer` 请求处理器
- TUI 客户端的实时输入功能

### 协议集成
- 作为 JSON-RPC 2.0 请求的 `params` 字段
- 方法名: `turn/steer`
- 响应类型: `TurnSteerResponse`

## 风险、边界与改进建议

### 已知风险

1. **Turn ID 不匹配**
   - 如果客户端持有的 Turn ID 过期，请求会失败
   - 错误代码 `-32600` 不够具体，难以区分具体原因

2. **输入时序**
   - 如果 AI 已经完成处理，steer 可能无法生效
   - 客户端需要正确处理 `turn/completed` 通知

3. **并发冲突**
   - 多个客户端同时 steer 同一 Turn 可能导致混乱
   - 没有客户端级别的并发控制

### 边界情况

1. **空输入**
   - `input` 必须非空，但 Schema 层面未强制
   - 空输入可能导致无操作或错误

2. **超长输入**
   - 受 `MAX_USER_INPUT_TEXT_CHARS` 限制
   - 超限返回与 `turn/start` 相同的错误格式

3. **非活跃 Turn**
   - 如果 Turn 已完成、中断或失败，steer 会失败
   - 客户端需要通过 `turn/started` 和 `turn/completed` 跟踪状态

### 改进建议

1. **错误信息增强**
   - 为 Turn ID 不匹配提供更具体的错误代码
   - 在错误信息中包含当前活跃 Turn ID（如果存在）

2. **功能扩展**
   - 考虑支持 steer 时附带特定的 "steer 类型"（如纠正、补充、取消）
   - 支持针对特定 item 的 steer（如纠正特定命令）

3. **性能优化**
   - 考虑批量 steer 支持，减少网络往返
   - 添加 steer 速率限制防止滥用

4. **类型安全**
   - 为 `expected_turn_id` 使用强类型 `TurnId`
   - 考虑添加 `SteerId` 用于追踪 steer 操作

5. **客户端指导**
   - 在文档中明确 steer 的最佳实践
   - 提供何时使用 steer vs 等待 vs interrupt 的指导
