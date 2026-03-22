# thread_rollback.rs 研究文档

## 场景与职责

`thread_rollback.rs` 是 Codex App Server v2 API 的集成测试文件，专门测试**线程回滚（Thread Rollback）**功能。该功能允许用户删除线程中最近的一个或多个 Turn（对话轮次），实现类似"撤销"的效果。这是对话系统中重要的纠错机制，让用户可以回退到之前的状态。

### 核心测试场景

1. **基础回滚流程** - 验证可以删除最后一个 Turn 并持久化到 rollout 文件
2. **回滚后恢复** - 测试回滚后的线程可以通过 thread/resume 正确恢复
3. **序列化格式验证** - 验证 `name` 字段在 unset 时正确序列化为 `null`

## 功能点目的

### Thread Rollback 的核心价值

- **错误恢复**: 用户可以撤销最近的操作，回到之前的状态
- **对话管理**: 删除不需要或错误的对话轮次
- **分支探索**: 支持基于历史状态的不同尝试（与 fork 配合使用）

### 关键测试功能点

| 测试函数 | 目的 |
|---------|------|
| `thread_rollback_drops_last_turns_and_persists_to_rollout` | 验证回滚删除 Turn 并持久化 |

### 回滚操作的影响

```
Before Rollback:
  Turn 1: User: "First" -> Agent: "Response 1"
  Turn 2: User: "Second" -> Agent: "Response 2"
  
After Rollback (num_turns=1):
  Turn 1: User: "First" -> Agent: "Response 1"
  (Turn 2 removed)
```

## 具体技术实现

### 关键数据结构

#### ThreadRollbackParams (v2 协议)
```rust
pub struct ThreadRollbackParams {
    pub thread_id: String,
    pub num_turns: u32,  // 要删除的最近 Turn 数量
}
```

#### ThreadRollbackResponse
```rust
pub struct ThreadRollbackResponse {
    pub thread: Thread,  // 回滚后的线程状态
}
```

### 关键流程

#### 回滚流程

```
Client -> thread/rollback (thread_id, num_turns=1)
    |
    v
Server 读取 rollout 文件
    |
    v
ThreadHistoryBuilder 解析历史
    |
    v
截断最后 N 个 Turn
    |
    v
重写 rollout 文件（截断后的历史）
    |
    v
发送 ThreadRolledBackEvent
    |
    v
返回 ThreadRollbackResponse
```

### 核心代码路径

#### 历史构建
- **文件**: `codex-rs/app-server-protocol/src/protocol/thread_history.rs`
- **函数**: `handle_thread_rollback()`
- **实现**:
```rust
fn handle_thread_rollback(&mut self, payload: &ThreadRolledBackEvent) {
    self.finish_current_turn();
    
    let n = usize::try_from(payload.num_turns).unwrap_or(usize::MAX);
    if n >= self.turns.len() {
        self.turns.clear();
    } else {
        self.turns.truncate(self.turns.len().saturating_sub(n));
    }
    
    // 重新计算 item 索引
    let item_count: usize = self.turns.iter().map(|t| t.items.len()).sum();
    self.next_item_index = i64::try_from(item_count.saturating_add(1)).unwrap_or(i64::MAX);
}
```

#### Rollout 文件截断
- **文件**: `codex-rs/core/src/rollout/` (推测)
- **操作**: 物理删除 rollout 文件中对应 Turn 的 JSONL 行

## 关键代码路径与文件引用

### 主要测试文件
- `codex-rs/app-server/tests/suite/v2/thread_rollback.rs` - 本文件，包含 1 个主要测试用例

### 被测实现文件
- `codex-rs/app-server/src/codex_message_processor.rs` - 处理 thread/rollback 请求
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs` - 历史回滚处理

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - ThreadRollbackParams/Response 定义

### 测试基础设施
- `codex-rs/app-server/tests/common/mcp_process.rs` - MCP 进程管理
- `codex-rs/app-server/tests/common/rollout.rs` - Rollout 文件辅助

## 依赖与外部交互

### 测试流程详解

```rust
#[tokio::test]
async fn thread_rollback_drops_last_turns_and_persists_to_rollout() -> Result<()> {
    // 1. 创建 Mock 服务器，提供 3 个响应
    let responses = vec![
        create_final_assistant_message_sse_response("Done")?,
        create_final_assistant_message_sse_response("Done")?,
        create_final_assistant_message_sse_response("Done")?,
    ];
    let server = create_mock_responses_server_sequence_unchecked(responses).await;

    // 2. 初始化 MCP 进程
    let mut mcp = McpProcess::new(codex_home.path()).await?;
    
    // 3. 创建线程并执行 2 个 Turn
    //    - Turn 1: "First" -> "Done"
    //    - Turn 2: "Second" -> "Done"
    
    // 4. 执行回滚，删除 1 个 Turn
    let rollback_id = mcp
        .send_thread_rollback_request(ThreadRollbackParams {
            thread_id: thread.id.clone(),
            num_turns: 1,
        })
        .await?;
    
    // 5. 验证回滚响应
    assert_eq!(rolled_back_thread.turns.len(), 1);
    assert_eq!(rolled_back_thread.status, ThreadStatus::Idle);
    
    // 6. 通过 thread/resume 验证持久化
    let resume_resp = mcp.send_thread_resume_request(...).await?;
    assert_eq!(thread.turns.len(), 1);  // 确认回滚已持久化
}
```

### 依赖关系

```
thread_rollback.rs
    |
    +-> app_test_support
    |       +-> McpProcess
    |       +-> create_mock_responses_server_sequence_unchecked
    |       +-> create_final_assistant_message_sse_response
    |
    +-> codex_app_server_protocol
    |       +-> ThreadRollbackParams
    |       +-> ThreadRollbackResponse
    |       +-> ThreadResumeParams (用于验证)
    |
    +-> codex_protocol
            +-> ThreadStatus
```

## 风险、边界与改进建议

### 当前测试覆盖的局限

1. **单一测试用例**
   - 当前只有一个测试函数覆盖回滚功能
   - 边界情况覆盖不足

2. **未覆盖的场景**
   - 回滚所有 Turn（num_turns >= total_turns）
   - 回滚 0 个 Turn（边界值）
   - 并发回滚请求
   - 回滚运行中的 Turn
   - 回滚后新 Turn 的创建

3. **错误处理**
   - 不存在的 thread_id
   - 无效的 num_turns（如大于实际 Turn 数）
   - 文件系统错误（磁盘满、权限等）

### 改进建议

1. **增加边界测试**
   ```rust
   #[tokio::test]
   async fn thread_rollback_all_turns() -> Result<()> {
       // 测试 num_turns >= total_turns 的情况
   }
   
   #[tokio::test]
   async fn thread_rollback_zero_turns() -> Result<()> {
       // 测试 num_turns = 0 的情况
   }
   ```

2. **增加错误场景测试**
   ```rust
   #[tokio::test]
   async fn thread_rollback_rejects_nonexistent_thread() -> Result<()> {
       // 测试不存在的 thread_id
   }
   ```

3. **增加并发测试**
   ```rust
   #[tokio::test]
   async fn thread_rollback_concurrent_requests() -> Result<()> {
       // 测试并发回滚请求的处理
   }
   ```

4. **验证 Rollout 文件内容**
   - 当前测试通过 resume 间接验证
   - 建议直接读取 rollout 文件验证 JSONL 内容

### 实现层面的潜在风险

1. **数据一致性**
   - 回滚操作需要同时更新内存状态和持久化文件
   - 崩溃恢复时可能出现不一致

2. **事件顺序**
   - ThreadRolledBackEvent 需要正确排序
   - 与其他事件（如 TurnComplete）的并发处理

3. **索引重置**
   - `next_item_index` 的重置逻辑需要确保新 Turn 的 ID 不冲突
   - 代码中：`self.next_item_index = item_count.saturating_add(1)`

### 与 Fork 功能的对比

| 特性 | Rollback | Fork |
|-----|----------|------|
| 目的 | 删除历史 | 创建分支 |
| 持久化 | 修改原文件 | 创建新文件 |
| 可逆性 | 不可逆（数据丢失） | 可逆（原线程保留） |
| 使用场景 | 纠错 | 探索 |

建议：在文档中明确区分 Rollback 和 Fork 的使用场景，避免用户误用。
