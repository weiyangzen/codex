# TurnSteerParams.ts Research Document

## 场景与职责

`TurnSteerParams` 是 App-Server Protocol v2 中的客户端请求参数类型，用于在已有回合进行中时向服务器发送额外的用户输入（"steer" 操作）。该类型在以下场景中发挥关键作用：

1. **实时对话干预**: 当 AI 正在生成回复或执行工具时，用户可以发送额外指令进行干预或补充
2. **多轮对话修正**: 用户在看到 AI 部分输出后，希望修正或调整对话方向
3. **流式响应控制**: 在流式输出过程中，用户可以发送停止、修改方向等指令
4. **复杂任务分解**: 对于复杂任务，用户可以在一个回合内分多次提供输入信息

## 功能点目的

该参数类型的核心目的是：

- **回合内输入**: 允许在回合进行中（`inProgress` 状态）向服务器发送额外输入
- **并发控制**: 通过 `expectedTurnId` 确保操作的原子性和一致性，防止竞态条件
- **输入丰富化**: 支持多种输入类型（文本、图片、技能引用等），与初始回合启动时相同
- **用户体验优化**: 支持更自然的对话流程，无需等待当前回合完成即可开始下一轮意图表达

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnSteerParams = { 
  threadId: string, 
  input: Array<UserInput>, 
  /**
   * Required active turn id precondition. The request fails when it does not
   * match the currently active turn.
   */
  expectedTurnId: string, 
};
```

### Rust 源类型定义

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

### 关键字段说明

| 字段 | 类型 | 必需 | 说明 |
|-----|------|------|------|
| `threadId` | `string` | 是 | 目标对话线程的唯一标识符 |
| `input` | `UserInput[]` | 是 | 用户输入内容数组，支持文本、图片、技能引用等多种类型 |
| `expectedTurnId` | `string` | 是 | 预期的当前活跃回合 ID，用于乐观并发控制 |

### 乐观并发控制（OCC）

`expectedTurnId` 是实现乐观并发控制的关键机制：

```
客户端读取当前 turnId = "turn-123"
                    │
                    ▼
客户端发送 TurnSteerParams { expectedTurnId: "turn-123", ... }
                    │
                    ▼
服务器验证: 当前活跃 turnId == "turn-123"?
    ├── 是 → 处理 steer 操作
    └── 否 → 返回错误（回合已变更）
```

这种设计确保：
- 客户端基于过时信息发出的请求会被拒绝
- 防止在回合已结束或变更后仍向其发送输入
- 支持客户端实现重试逻辑

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3941-3950) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnSteerParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnSteerParams.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 `turn/steer` 方法的参数类型 |
| `codex-rs/app-server-protocol/schema/typescript/ClientRequest.ts` | 包含在客户端请求联合类型中 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 steer 请求的核心逻辑 |
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI 应用服务器会话处理 |
| `codex-rs/app-server/tests/suite/v2/turn_steer.rs` | steer 功能集成测试 |

### 请求处理流程

```
ClientRequest::TurnSteer { params: TurnSteerParams }
                    │
                    ▼
    codex_message_processor.rs
                    │
                    ▼
    验证 expected_turn_id 匹配
                    │
                    ▼
    将 input 添加到当前回合
                    │
                    ▼
    返回 TurnSteerResponse { turn_id }
```

## 依赖与外部交互

### 内部依赖

- **`UserInput`**: 输入内容类型，支持多种输入变体
  - `Text`: 文本输入
  - `Image`: 图片 URL
  - `LocalImage`: 本地图片路径
  - `Skill`: 技能引用
  - `Mention`: 提及/引用

- **`TurnSteerResponse`**: 对应的响应类型，返回确认的 `turnId`

### 协议依赖

- 属于 **Client Request** 类别（客户端 → 服务器）
- 对应 RPC 方法: `turn/steer`
- 请求-响应模式：同步请求，返回 `TurnSteerResponse`

### 核心层交互

```rust
// 伪代码示意
codex.steer_turn(
    thread_id: &str,
    expected_turn_id: &str,
    input: Vec<UserInput>,
) -> Result<TurnSteerResponse, SteerError>
```

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**: 尽管有 `expectedTurnId` 保护，但在高并发场景下仍可能出现意外行为
2. **输入顺序**: 多个 steer 操作的输入顺序处理需要确保一致性
3. **资源泄漏**: 如果客户端频繁 steer 但不等待完成，可能导致资源累积

### 边界情况

1. **回合已结束**: 如果回合在 steer 请求发送期间完成，`expectedTurnId` 验证将失败
2. **空输入**: `input` 数组为空时的行为需要明确
3. **超大输入**: 大量或超大输入可能导致性能问题
4. **网络分区**: 客户端发送 steer 后失去连接，无法确认是否成功

### 改进建议

1. **批量 steer**: 考虑支持一次请求中的多个 steer 操作，减少往返次数

2. **优先级机制**: 为 steer 输入添加优先级，支持紧急干预：
   ```typescript
   export type TurnSteerParams = {
     threadId: string,
     input: UserInput[],
     expectedTurnId: string,
     priority?: 'normal' | 'urgent' | 'interrupt',
   };
   ```

3. **部分确认**: 对于大型输入，考虑支持分块传输和确认机制

4. **超时配置**: 添加可选的等待超时参数：
   ```typescript
   waitTimeout?: number; // 等待回合进入可 steer 状态的最大时间
   ```

5. **状态预检**: 添加 `turn/steerable` 查询方法，允许客户端预先检查是否可以 steer

6. **输入去重**: 实现输入内容的哈希检查，防止重复提交

### 测试覆盖

- 基础功能测试: `codex-rs/app-server/tests/suite/v2/turn_steer.rs`
- 竞态条件测试: 建议添加并发 steer 测试
- 错误处理测试: expectedTurnId 不匹配场景
- 建议添加：
  - 网络延迟下的 steer 行为测试
  - 大量 steer 操作的性能测试
  - 边界值测试（空输入、超大输入）
