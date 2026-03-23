# wait.rs 研究文档

## 场景与职责

`wait.rs` 实现了 `wait_agent` 工具的处理器，用于等待一个或多个子代理达到最终状态（final status）。这是多代理协作系统中的重要同步工具，允许父代理阻塞等待子代理完成执行，然后获取其结果。

在多代理协作场景中，父代理可能需要等待子代理完成特定任务后才能继续执行。`wait_agent` 支持等待多个代理，并在任意一个代理完成时返回（或超时），这使得父代理可以实现并行任务的协调和同步。

## 功能点目的

1. **等待子代理完成**：阻塞等待一个或多个子代理达到最终状态
2. **超时控制**：支持自定义超时时间，防止无限期等待
3. **批量等待**：支持同时等待多个代理，任意一个完成即返回
4. **状态收集**：返回所有被等待代理的最终状态
5. **超时检测**：区分正常完成和超时返回
6. **事件通知**：通过 `CollabWaitingBeginEvent` 和 `CollabWaitingEndEvent` 通知等待过程

## 具体技术实现

### 关键数据结构

```rust
// 等待代理的参数
#[derive(Debug, Deserialize)]
struct WaitArgs {
    ids: Vec<String>,           // 要等待的代理 ID 列表
    timeout_ms: Option<i64>,    // 超时时间（毫秒）
}

// 等待操作的结果
#[derive(Debug, Deserialize, Serialize, PartialEq, Eq)]
pub(crate) struct WaitAgentResult {
    pub(crate) status: HashMap<ThreadId, AgentStatus>,  // 代理状态映射
    pub(crate) timed_out: bool,                          // 是否超时
}

// 代理引用信息（用于事件通知）
struct CollabAgentRef {
    thread_id: ThreadId,
    agent_nickname: Option<String>,
    agent_role: Option<String>,
}
```

### 超时常量

```rust
pub(crate) const MIN_WAIT_TIMEOUT_MS: i64 = 10_000;      // 最小 10 秒
pub(crate) const DEFAULT_WAIT_TIMEOUT_MS: i64 = 30_000; // 默认 30 秒
pub(crate) const MAX_WAIT_TIMEOUT_MS: i64 = 3600 * 1000; // 最大 1 小时
```

### 关键流程

1. **参数解析与验证**：
   - 解析 `WaitArgs`
   - 验证 `ids` 非空
   - 将所有 ID 转换为 `ThreadId`
   - 获取每个代理的昵称和角色信息

2. **超时处理**：
   - 使用提供的 `timeout_ms` 或默认值
   - 验证超时时间大于 0
   - 将超时限制在 `[MIN_WAIT_TIMEOUT_MS, MAX_WAIT_TIMEOUT_MS]` 范围内

3. **发送开始事件**：
   - 发送 `CollabWaitingBeginEvent`，包含所有被等待代理的信息

4. **订阅状态**：
   - 对每个代理调用 `subscribe_status` 订阅状态更新
   - 如果代理不存在（`ThreadNotFound`），记录为初始最终状态
   - 如果订阅失败，发送结束事件并返回错误
   - 检查初始状态，如果已经是最终状态，记录到 `initial_final_statuses`

5. **等待逻辑**：
   - 如果已有代理处于最终状态，直接使用这些结果
   - 否则，创建 `FuturesUnordered` 并行等待所有代理
   - 使用 `timeout_at` 实现超时控制
   - 当任意代理完成时，尝试收集其他已完成的代理状态

6. **构建结果**：
   - 构建状态映射
   - 生成 `CollabAgentStatusEntry` 列表用于事件通知
   - 判断是否超时（`statuses.is_empty()`）

7. **发送结束事件**：
   - 发送 `CollabWaitingEndEvent`，包含最终状态信息

8. **返回结果**：
   - 返回 `WaitAgentResult`，包含状态映射和超时标志

### 等待实现详解

```rust
async fn wait_for_final_status(
    session: Arc<Session>,
    thread_id: ThreadId,
    mut status_rx: Receiver<AgentStatus>,
) -> Option<(ThreadId, AgentStatus)> {
    let mut status = status_rx.borrow().clone();
    // 检查初始状态
    if is_final(&status) {
        return Some((thread_id, status));
    }
    
    // 等待状态变化
    loop {
        if status_rx.changed().await.is_err() {
            // 接收器关闭，查询最新状态
            let latest = session.services.agent_control.get_status(thread_id).await;
            return is_final(&latest).then_some((thread_id, latest));
        }
        status = status_rx.borrow().clone();
        if is_final(&status) {
            return Some((thread_id, status));
        }
    }
}
```

### 最终状态判断

```rust
pub(crate) fn is_final(status: &AgentStatus) -> bool {
    !matches!(
        status,
        AgentStatus::PendingInit | AgentStatus::Running | AgentStatus::Interrupted
    )
}
```

最终状态包括：`Completed`、`Errored`、`Shutdown`、`NotFound`。

### 批量等待策略

使用 `FuturesUnordered` 实现高效的批量等待：

```rust
let mut futures = FuturesUnordered::new();
for (id, rx) in status_rxs.into_iter() {
    let session = session.clone();
    futures.push(wait_for_final_status(session, id, rx));
}

let deadline = Instant::now() + Duration::from_millis(timeout_ms as u64);
loop {
    match timeout_at(deadline, futures.next()).await {
        Ok(Some(Some(result))) => {
            results.push(result);
            break;  // 一个完成即退出
        }
        Ok(Some(None)) => continue,
        Ok(None) | Err(_) => break,  // 全部完成或超时
    }
}

// 收集其他已完成的代理
if !results.is_empty() {
    loop {
        match futures.next().now_or_never() {
            Some(Some(Some(result))) => results.push(result),
            Some(Some(None)) => continue,
            Some(None) | None => break,
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents/wait.rs` - 本文件

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents.rs` - 父模块，提供 `build_wait_agent_statuses`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/registry.rs` - 工具注册表
- `/home/sansha/Github/codex/codex-rs/core/src/agent/control.rs` - `AgentControl`，提供 `subscribe_status` 和 `get_status`
- `/home/sansha/Github/codex/codex-rs/core/src/agent/status.rs` - 提供 `is_final` 函数
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` - 协议事件定义

### 调用链
```
ToolRegistry::dispatch_any()
  -> WaitAgentHandler::handle()
    -> agent_id()  // 验证并转换 ID
    -> AgentControl::get_agent_nickname_and_role()  // 获取代理信息
    -> AgentControl::subscribe_status()  // 订阅状态
    -> wait_for_final_status()  // 等待最终状态
      -> is_final()  // 判断是否为最终状态
    -> build_wait_agent_statuses()  // 构建状态列表
```

## 依赖与外部交互

### 服务依赖
- `session.services.agent_control`：用于订阅和查询代理状态

### 异步原语
- `tokio::sync::watch::Receiver`：状态订阅通道
- `futures::stream::FuturesUnordered`：并行等待多个 future
- `tokio::time::timeout_at`：超时控制

### 事件类型
- `CollabWaitingBeginEvent`：等待开始，包含被等待代理列表
- `CollabWaitingEndEvent`：等待结束，包含最终状态

### 状态类型
- `AgentStatus::PendingInit`：等待初始化（非最终）
- `AgentStatus::Running`：运行中（非最终）
- `AgentStatus::Interrupted`：已中断（非最终）
- `AgentStatus::Completed`：已完成（最终）
- `AgentStatus::Errored`：出错（最终）
- `AgentStatus::Shutdown`：已关闭（最终）
- `AgentStatus::NotFound`：不存在（最终）

## 风险、边界与改进建议

### 边界情况

1. **空 ID 列表**：`ids` 为空时会返回错误
2. **无效 ID**：ID 格式无效会返回错误
3. **代理不存在**：不存在的代理会被视为 `NotFound` 状态（最终状态）
4. **超时范围**：超时时间会被限制在 `[10s, 1h]` 范围内
5. **全部完成**：如果所有代理都已完成，立即返回而不等待

### 风险点

1. **竞争条件**：订阅状态和检查初始状态之间可能存在竞争
2. **内存泄漏**：如果代理长时间不完成，`FuturesUnordered` 会保持所有 future
3. **状态同步延迟**：状态更新通过 watch 通道，可能存在短暂延迟
4. **超时精度**：`timeout_at` 的精度受 tokio 调度影响
5. **批量限制**：大量代理同时等待可能影响性能

### 改进建议

1. **等待全部完成**：添加选项等待所有代理完成，而不仅仅是任意一个
2. **进度通知**：在等待过程中定期发送进度事件
3. **取消机制**：支持取消等待操作
4. **智能超时**：根据代理历史执行时间动态调整超时
5. **批量查询优化**：优化大量代理的状态查询性能
6. **等待条件**：支持自定义等待条件（如等待特定状态）
7. **重试机制**：在状态订阅失败时支持重试
8. **并发限制**：限制同时等待的代理数量，避免资源耗尽

### 测试覆盖

测试文件：`/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents_tests.rs`

相关测试：
- `wait_agent_rejects_non_positive_timeout`：验证非正超时拒绝
- `wait_agent_rejects_invalid_id`：验证无效 ID 拒绝
- `wait_agent_rejects_empty_ids`：验证空 ID 列表拒绝
- `wait_agent_returns_not_found_for_missing_agents`：验证缺失代理返回 NotFound
- `wait_agent_times_out_when_status_is_not_final`：验证超时行为
- `wait_agent_clamps_short_timeouts_to_minimum`：验证超时限制
- `wait_agent_returns_final_status_without_timeout`：验证正常完成

### 特殊考虑

1. **超时语义**：当前实现中，`timed_out: true` 表示在超时时间内没有任何代理达到最终状态。如果有代理在超时前完成，即使其他代理未完成，`timed_out` 也为 `false`。

2. **状态收集**：当任意代理完成时，实现会尝试使用 `now_or_never` 收集其他已完成的代理状态，这确保了返回的结果尽可能完整。

3. **错误处理**：如果在订阅过程中发生非 `ThreadNotFound` 错误，整个操作会立即失败，已收集的状态不会返回。
