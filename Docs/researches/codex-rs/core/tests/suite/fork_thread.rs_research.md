# fork_thread.rs 深度研究文档

## 场景与职责

`fork_thread.rs` 是 Codex 核心测试套件中专门验证**线程分叉（Thread Fork）**功能的集成测试文件。该测试确保：

1. **历史截断正确性**：分叉后的线程只包含指定位置之前的历史
2. **多次分叉链**：支持基于已分叉线程再次分叉
3. **Rollout 文件一致性**：分叉后的 rollout 文件格式与预期一致

线程分叉是 Codex 的重要功能，允许用户从对话的任意历史点创建新的探索分支，类似于 Git 的分支机制。

## 功能点目的

### 1. 单次分叉验证
- **目的**：验证基于第 n 个用户消息分叉的正确性
- **行为**：保留第 n 个用户消息之前的所有历史

### 2. 多次分叉链
- **目的**：验证分叉链的累积效果
- **场景**：A → fork(1) → B → fork(0) → C

### 3. Rollout 文件验证
- **目的**：确保分叉后的 rollout 文件可正确解析
- **验证点**：条目类型、顺序、内容完整性

## 具体技术实现

### 线程分叉 API

```rust
// codex-rs/core/src/thread_manager.rs
pub async fn fork_thread(
    &self,
    nth_user_message: usize,      // 截断位置（第 n 个用户消息之前）
    config: Config,
    path: PathBuf,                // 源 rollout 文件路径
    persist_extended_history: bool,
    parent_trace: Option<W3cTraceContext>,
) -> CodexResult<NewThread> {
    // 1. 读取源 rollout 历史
    let history = RolloutRecorder::get_rollout_history(&path).await?;
    
    // 2. 截断历史
    let history = truncate_before_nth_user_message(history, nth_user_message);
    
    // 3. 使用截断后的历史创建新线程
    Box::pin(self.state.spawn_thread(
        config,
        history,
        Arc::clone(&self.state.auth_manager),
        self.agent_control(),
        Vec::new(),
        persist_extended_history,
        None,
        parent_trace,
        None,
    )).await
}
```

### 历史截断算法

```rust
fn truncate_before_nth_user_message(history: InitialHistory, n: usize) -> InitialHistory {
    let items: Vec<RolloutItem> = history.get_rollout_items();
    let rolled = truncation::truncate_rollout_before_nth_user_message_from_start(&items, n);
    
    if rolled.is_empty() {
        InitialHistory::New
    } else {
        InitialHistory::Forked(rolled)
    }
}
```

### Rollout 条目解析

```rust
// 测试中使用的辅助函数
let read_items = |p: &std::path::Path| -> Vec<RolloutItem> {
    let text = std::fs::read_to_string(p).expect("read rollout file");
    let mut items: Vec<RolloutItem> = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let v: serde_json::Value = serde_json::from_str(line).expect("jsonl line");
        let rl: RolloutLine = serde_json::from_value(v).expect("rollout line");
        match rl.item {
            RolloutItem::SessionMeta(_) => {}  // 跳过会话元数据
            other => items.push(other),
        }
    }
    items
};
```

### 用户消息位置识别

```rust
let find_user_input_positions = |items: &[RolloutItem]| -> Vec<usize> {
    let mut pos = Vec::new();
    for (i, it) in items.iter().enumerate() {
        if let RolloutItem::ResponseItem(response_item) = it
            && let Some(TurnItem::UserMessage(_)) = parse_turn_item(response_item)
        {
            pos.push(i);
        }
    }
    pos
};
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/fork_thread.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/thread_manager.rs` - 线程管理器
  - `fork_thread` - 分叉入口
  - `truncate_before_nth_user_message` - 历史截断

- `codex-rs/core/src/rollout/truncation.rs` - 历史截断实现
  - `truncate_rollout_before_nth_user_message_from_start` - 核心算法

- `codex-rs/core/src/rollout/recorder.rs` - Rollout 记录器
  - `get_rollout_history` - 读取 rollout 历史

### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `InitialHistory` - 初始历史类型
    - `New` - 全新对话
    - `Forked(Vec<RolloutItem>)` - 分叉历史
    - `Resumed(...)` - 恢复的历史
  - `RolloutItem` - Rollout 条目
  - `RolloutLine` - Rollout 文件行格式

- `codex-rs/core/src/codex.rs`
  - `NewThread` - 新线程结果

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_core::ThreadManager` | 线程生命周期管理 |
| `codex_core::NewThread` | 新线程创建结果 |
| `codex_protocol::protocol` | 协议类型 |
| `core_test_support` | 测试基础设施 |

### 测试流程
```rust
// 1. 创建基础对话
let test = builder.build(&server).await.expect("create conversation");
let codex = test.codex.clone();
let thread_manager = test.thread_manager.clone();

// 2. 发送三条用户消息
for text in ["first", "second", "third"] {
    codex.submit(Op::UserInput { ... }).await.unwrap();
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
}

// 3. 获取 rollout 路径
let base_path = codex.rollout_path().expect("rollout path");

// 4. 第一次分叉（保留到第二条消息前）
let NewThread { thread: codex_fork1, .. } = thread_manager
    .fork_thread(1, config_for_fork.clone(), base_path.clone(), false, None)
    .await
    .expect("fork 1");

// 5. 第二次分叉（基于 fork1，保留到第一条消息前）
let NewThread { thread: codex_fork2, .. } = thread_manager
    .fork_thread(0, config_for_fork.clone(), fork1_path.clone(), false, None)
    .await
    .expect("fork 2");
```

### Mock Server 配置
```rust
let server = MockServer::start().await;
let sse = sse(vec![ev_response_created("resp"), ev_completed("resp")]);
let first = ResponseTemplate::new(200)
    .insert_header("content-type", "text/event-stream")
    .set_body_raw(sse.clone(), "text/event-stream");

Mock::given(method("POST"))
    .and(path("/v1/responses"))
    .respond_with(first)
    .expect(3)  // 期望 3 次调用（3 条用户消息）
    .mount(&server)
    .await;
```

## 风险、边界与改进建议

### 已知风险

1. **索引越界**
   - 风险：`nth_user_message` 超过实际用户消息数
   - 现状：使用 `get(n).copied().unwrap_or(0)` 安全处理

2. **历史不一致**
   - 风险：源 rollout 文件在分叉过程中被修改
   - 缓解：RolloutRecorder 使用追加写入，减少冲突

3. **SessionMeta 处理**
   - 注意：测试中显式跳过 `SessionMeta` 条目
   - 风险：不同版本间 SessionMeta 格式变化

### 边界情况

1. **空历史分叉** (`n = 0` 且历史为空)
   - 结果：`InitialHistory::New`

2. **完整保留** (`n >= 用户消息数`)
   - 结果：保留全部历史

3. **负索引/溢出**
   - 处理：`usize` 类型，负值会编译错误
   - 大值：`saturating_sub` 安全处理

### 改进建议

1. **分叉元数据**
   - 在分叉后的 rollout 中记录源线程 ID 和分叉点
   - 支持可视化分叉历史图

2. **并发安全**
   - 添加源 rollout 文件锁定机制
   - 防止读写冲突

3. **部分分叉**
   - 支持基于消息 ID 而非索引的分叉
   - 支持基于时间戳的分叉

4. **分叉合并**
   - 探索分叉合并（merge）功能
   - 类似于 Git 的合并机制

5. **测试增强**
   - 添加并发分叉测试
   - 添加大历史文件性能测试
   - 添加分叉后修改独立性的验证

6. **用户体验**
   - 提供分叉预览功能
   - 显示分叉前后历史对比
