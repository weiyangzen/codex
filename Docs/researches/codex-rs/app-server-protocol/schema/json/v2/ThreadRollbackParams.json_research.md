# ThreadRollbackParams.json 研究文档

## 场景与职责

`ThreadRollbackParams` 是 Codex App Server Protocol v2 中 `thread/rollback` 方法的请求参数结构，用于将线程的历史记录回滚到指定数量的回合之前。这是实现对话"撤销"功能的核心 API。

该功能允许用户：
- 撤销最近的一次或多次对话回合
- 回退到之前的对话状态继续交互
- 在错误或不满意的代理响应后重新开始

**重要限制**: 该操作仅修改线程的历史记录，不会回滚代理已执行的本地文件更改。客户端需要自行负责文件系统状态的恢复。

## 功能点目的

### 核心功能
- **历史回滚**: 从线程末尾删除指定数量的回合（turns）
- **状态重置**: 将线程恢复到之前的状态，允许重新进行对话
- **持久化同步**: 回滚操作会同步更新磁盘上的 rollout 文件

### 使用场景
1. 用户对最近几次对话结果不满意，希望回到之前的状态
2. 代理执行了错误的操作，用户希望撤销并重新尝试
3. 测试和调试场景下重置对话状态

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRollbackParams {
    /// 目标线程 ID
    pub thread_id: String,
    
    /// 从线程末尾删除的回合数，必须 >= 1
    /// 
    /// 注意：这仅修改线程历史，不回滚本地文件更改
    pub num_turns: u32,
}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "numTurns": {
      "description": "The number of turns to drop from the end of the thread...",
      "format": "uint32",
      "minimum": 0.0,
      "type": "integer"
    },
    "threadId": {
      "type": "string"
    }
  },
  "required": ["numTurns", "threadId"],
  "title": "ThreadRollbackParams",
  "type": "object"
}
```

### 关键流程

1. **请求处理入口**: `CodexMessageProcessor::thread_rollback()` (codex_message_processor.rs:2853)
2. **参数验证**: 检查 `num_turns >= 1`，否则返回无效请求错误
3. **线程加载**: 通过 `load_thread()` 获取线程实例
4. **并发控制**: 检查是否已有回滚操作在进行中，防止重复提交
5. **核心操作提交**: 发送 `Op::ThreadRollback { num_turns }` 到线程执行器
6. **事件处理**: 等待 `ThreadRollback` 事件，构造 `ThreadRollbackResponse`

### 并发控制机制

```rust
// 检查是否已有回滚在进行中
let rollback_already_in_progress = {
    let thread_state = self.thread_state_manager.thread_state(thread_id).await;
    let mut thread_state = thread_state.lock().await;
    if thread_state.pending_rollbacks.is_some() {
        true
    } else {
        thread_state.pending_rollbacks = Some(request.clone());
        false
    }
};
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadRollbackParams 结构体定义 (line ~2300)
- `codex-rs/app-server-protocol/src/protocol/common.rs`: ClientRequest 枚举 ThreadRollback 变体

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_rollback()` 方法 (line 2853-2916)
- `codex-rs/app-server/src/bespoke_event_handling.rs`:
  - 处理 `ThreadRollback` 事件，构造响应 (line ~800)

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_rollback.rs`:
  - `thread_rollback_drops_last_turns_and_persists_to_rollout`: 验证回滚和持久化

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRollbackParams.ts`

## 依赖与外部交互

### 内部依赖
- **codex_core**: `Op::ThreadRollback` 操作码，线程执行器处理回滚逻辑
- **codex_protocol**: `ThreadId` 类型解析
- **codex_state**: 持久化 rollout 文件更新

### 外部交互
- **文件系统**: 截断 rollout 文件，删除指定数量的回合记录
- **SQLite**: 更新 state_db 中的线程元数据（如需要）

### 响应结构
回滚成功后返回 `ThreadRollbackResponse`：
```rust
pub struct ThreadRollbackResponse {
    /// 回滚后的线程状态，包含 turns 数组
    pub thread: Thread,
}
```

## 风险、边界与改进建议

### 已知风险

1. **文件更改不回滚**: 明确文档化的限制，但用户可能误解此行为
2. **并发回滚冲突**: 同一时刻只能有一个回滚操作在进行
3. **数据丢失**: 回滚操作不可逆，删除的历史记录无法恢复

### 边界情况

1. **num_turns = 0**: 服务端会拒绝，要求至少回滚 1 个回合
2. **回滚所有回合**: 允许回滚到空历史状态
3. **运行中 turn**: 如果有正在进行的 turn，回滚行为需要明确定义
4. **持久化失败**: rollout 文件更新失败时，内存状态与磁盘可能不一致

### 改进建议

1. **软回滚选项**: 考虑添加标记历史为"已撤销"而非物理删除的选项
2. **回滚预览**: 在正式执行前返回将被删除的回合预览
3. **文件更改追踪**: 考虑与版本控制系统集成，自动回滚关联的文件更改
4. **批量回滚优化**: 大量回合回滚时的性能优化

### 安全考虑
- 回滚操作需要适当的权限检查，确保用户只能回滚自己的线程
- 考虑添加回滚操作的审计日志
