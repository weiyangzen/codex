# ThreadRollbackParams 类型研究报告

## 场景与职责

`ThreadRollbackParams` 是 Codex App-Server Protocol v2 中的参数类型，用于在客户端发起对话线程回滚操作时，指定回滚的具体参数。

**主要使用场景：**
- 用户想要撤销最近的若干轮对话（turns）
- 对话进入不良状态，需要回退到之前的检查点
- 用户改变主意，想要删除最近的几轮交互
- 调试和测试场景下重置对话状态

**职责范围：**
- 标识目标线程（`threadId`）
- 指定回滚的回合数（`numTurns`）
- 明确回滚操作的边界和限制

## 功能点目的

该类型的核心目的是为 `thread/rollback` RPC 调用提供精确的参数控制，使客户端能够：

1. **精确控制回滚范围**：通过 `numTurns` 指定从线程末尾删除多少轮对话
2. **历史记录管理**：支持对话历史的修剪和整理
3. **错误恢复**：在对话偏离预期方向时提供恢复机制

**重要限制说明**（来自代码注释）：
- `numTurns` 必须 >= 1
- 回滚**仅修改线程历史记录**，不会恢复代理已执行的本地文件变更
- 客户端负责处理文件变更的回滚（如通过 git 操作）

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadRollbackParams = {
  threadId: string,
  /**
   * The number of turns to drop from the end of the thread. Must be >= 1.
   *
   * This only modifies the thread's history and does not revert local file changes
   * that have been made by the agent. Clients are responsible for reverting these changes.
   */
  numTurns: number,
};
```

### Rust 源类型定义

```rust
// Line 2905-2915
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRollbackParams {
    pub thread_id: String,
    /// The number of turns to drop from the end of the thread. Must be >= 1.
    ///
    /// This only modifies the thread's history and does not revert local file changes
    /// that have been made by the agent. Clients are responsible for reverting these changes.
    pub num_turns: u32,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 目标线程的唯一标识符 |
| `numTurns` | `number` | 要从线程末尾删除的对话轮数，必须 >= 1 |

### 类型约束

- `num_turns` 在 Rust 中使用 `u32` 类型，确保值为非负整数
- 最小值为 1，即至少回滚一轮对话
- 如果 `num_turns` 超过实际回合数，服务端应返回错误

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRollbackParams.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2908-2915

### 相关类型
| 类型 | 说明 | 路径 |
|------|------|------|
| ThreadRollbackResponse | 回滚操作的响应类型 | `v2/ThreadRollbackResponse.ts` |
| Thread | 线程对象，包含被修改的历史记录 | `v2/Thread.ts` |
| Turn | 对话回合，回滚操作删除的基本单位 | `v2/Turn.ts` |

### 使用场景
- 与 `ThreadRollbackResponse` 配对使用，构成完整的 rollback 请求-响应周期
- 通常由客户端在用户触发"撤销"或"回滚"操作时调用

## 依赖与外部交互

### 内部依赖

1. **Thread 类型**: 回滚操作的目标对象
2. **Turn 类型**: 回滚操作的基本单位，每个 Turn 代表一轮对话交互

### 外部交互

1. **与 ThreadRollbackResponse 的交互**:
   - `ThreadRollbackParams` 发起回滚请求
   - `ThreadRollbackResponse` 返回回滚后的线程状态

2. **与客户端文件系统的交互**:
   - 服务端仅负责删除历史记录中的 turns
   - 客户端需要独立处理文件系统变更的回滚（如通过 git checkout、手动撤销等）

3. **与版本控制的交互**:
   - 建议客户端在回滚前创建 git 提交或快照
   - 便于在需要时恢复文件变更

### 安全考虑

- 回滚操作不可逆，删除的 turns 无法自动恢复
- 建议在执行前向用户确认
- 对于重要操作，建议先备份线程状态（通过 fork）

## 风险、边界与改进建议

### 潜在风险

1. **数据丢失风险**:
   - 回滚操作永久删除 turns，无法撤销
   - 如果用户误操作，可能丢失重要对话历史

2. **文件状态不一致**:
   - 历史记录回滚了，但文件变更保留
   - 可能导致对话上下文与实际文件状态不匹配
   - 例如：回滚了"创建文件"的对话，但文件仍然存在

3. **验证不足**:
   - 当前仅验证 `numTurns >= 1`
   - 缺乏对线程存在性、用户权限等的运行时验证说明

### 边界情况

1. **numTurns 等于总回合数**: 回滚后线程可能变为空状态
2. **numTurns 超过总回合数**: 服务端应返回错误还是回滚全部？
3. **并发修改**: 如果回滚过程中线程被其他客户端修改
4. **正在进行的回合**: 如果当前有正在进行的 agent 操作

### 改进建议

1. **增强验证**:
   ```rust
   // 建议添加验证逻辑
   pub fn validate(&self, thread: &Thread) -> Result<(), ValidationError> {
       if self.num_turns == 0 {
           return Err(ValidationError::InvalidNumTurns);
       }
       if self.num_turns > thread.turns.len() as u32 {
           return Err(ValidationError::ExceedsTurnCount);
       }
       Ok(())
   }
   ```

2. **添加预览模式**:
   - 增加 `dryRun` 选项，允许客户端预览回滚效果而不实际执行
   - 返回将被删除的 turns 列表供用户确认

3. **文件变更追踪**:
   - 考虑在 turns 中记录关联的文件变更
   - 提供文件变更回滚的建议或自动化支持

4. **软删除机制**:
   - 考虑实现软删除，保留被回滚的 turns 一段时间
   - 允许用户在一定时间内撤销回滚操作

5. **批量回滚优化**:
   - 对于大量回滚，考虑支持事务性操作
   - 确保回滚操作的原子性

6. **用户确认增强**:
   - 在 API 层面添加 `requireConfirmation` 标志
   - 对于影响较大的回滚，要求额外确认

7. **回滚原因记录**:
   - 添加可选的 `reason` 字段，记录回滚原因
   - 有助于后续分析和审计
