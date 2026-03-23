# compact_resume_fork.rs 深度研究文档

## 场景与职责

`compact_resume_fork.rs` 是 Codex 核心集成测试套件中的关键测试文件，专注于验证三个核心功能的交互正确性：

1. **Conversation Compaction（对话压缩）**：当对话历史过长时，将历史记录压缩为摘要，减少 token 消耗
2. **Thread Resume（线程恢复）**：从持久化的 rollout 文件恢复对话状态
3. **Thread Fork（线程分叉）**：基于历史对话的某个时间点创建新的对话分支

这些功能是 Codex 作为长期运行 AI 助手的基础能力，确保用户可以在多轮对话后依然保持上下文，同时支持分支探索不同解决方案。

## 功能点目的

### 1. 对话压缩 (Compact)
- **目的**：解决长对话导致的上下文窗口超限问题
- **机制**：将历史对话发送给模型生成摘要，用摘要替换详细历史
- **触发方式**：
  - 手动触发：用户主动调用 `Op::Compact`
  - 自动触发：当 token 数超过 `model_auto_compact_token_limit` 阈值

### 2. 线程恢复 (Resume)
- **目的**：允许用户从之前的对话状态继续
- **机制**：读取持久化的 rollout JSONL 文件，重建对话历史
- **应用场景**：程序重启后恢复、跨设备同步对话状态

### 3. 线程分叉 (Fork)
- **目的**：基于历史状态创建新的对话分支，支持探索不同方案
- **机制**：截取 rollout 历史中第 n 个用户消息之前的所有内容，创建新线程
- **应用场景**：尝试不同解决路径、回退到之前决策点

## 具体技术实现

### 核心数据结构

```rust
// 来自 compact.rs
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");

// 压缩历史构建
pub(crate) fn build_compacted_history(
    initial_context: Vec<ResponseItem>,
    user_messages: &[String],
    summary_text: &str,
) -> Vec<ResponseItem>
```

### 关键流程

#### 压缩流程 (compact.rs)
1. **准备阶段**：
   - 克隆当前历史记录
   - 注入压缩提示词（summarization prompt）
   
2. **模型调用**：
   - 使用 `drain_to_completed` 流式处理响应
   - 捕获最后一条助手消息作为摘要

3. **历史重建**：
   - 收集所有非摘要类型的用户消息
   - 构建新的压缩历史：`[initial_context] + [user_messages] + [summary]`
   - 保留 GhostSnapshot 条目用于内部状态追踪

4. **状态更新**：
   - 调用 `replace_compacted_history` 替换会话历史
   - 发送 `ContextCompacted` 事件和警告消息

#### 恢复流程 (thread_manager.rs)
```rust
pub async fn resume_thread_from_rollout(
    &self,
    config: Config,
    rollout_path: PathBuf,
    auth_manager: Arc<AuthManager>,
    parent_trace: Option<W3cTraceContext>,
) -> CodexResult<NewThread> {
    let initial_history = RolloutRecorder::get_rollout_history(&rollout_path).await?;
    // 使用 rollout 历史创建新线程
}
```

#### 分叉流程 (thread_manager.rs)
```rust
pub async fn fork_thread(
    &self,
    nth_user_message: usize,
    config: Config,
    path: PathBuf,
    persist_extended_history: bool,
    parent_trace: Option<W3cTraceContext>,
) -> CodexResult<NewThread> {
    let history = RolloutRecorder::get_rollout_history(&path).await?;
    let history = truncate_before_nth_user_message(history, nth_user_message);
    // 使用截断后的历史创建新线程
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

算法逻辑：
1. 遍历 rollout 条目，识别用户消息位置
2. 截取第 n 个用户消息之前的所有条目
3. 返回 `InitialHistory::Forked` 包装截断后的历史

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/compact_resume_fork.rs` - 本测试文件
- `codex-rs/core/tests/suite/compact.rs` - 基础压缩测试和共享常量

### 核心实现
- `codex-rs/core/src/compact.rs` - 压缩逻辑实现
  - `run_compact_task` - 手动压缩入口
  - `run_inline_auto_compact_task` - 自动压缩入口
  - `build_compacted_history` - 构建压缩历史
  - `insert_initial_context_before_last_real_user_or_summary` - 初始上下文注入

- `codex-rs/core/src/thread_manager.rs` - 线程管理
  - `resume_thread_from_rollout` - 恢复线程
  - `fork_thread` - 分叉线程
  - `truncate_before_nth_user_message` - 历史截断

- `codex-rs/core/src/rollout/` - Rollout 持久化
  - `RolloutRecorder` - 记录对话历史到 JSONL
  - `get_rollout_history` - 读取历史用于恢复/分叉

### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `InitialHistory` - 初始历史类型（New/Forked/Resumed）
  - `RolloutItem` - Rollout 条目类型
  - `CompactedItem` - 压缩记录

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `core_test_support` | 测试基础设施（mock server、事件等待） |
| `codex_core::compact` | 压缩实现 |
| `codex_core::ThreadManager` | 线程生命周期管理 |
| `codex_protocol` | 协议类型定义 |

### 外部工具
- **wiremock**: 模拟 OpenAI API 响应
- **tempfile**: 创建临时目录用于测试隔离

### 测试基础设施
```rust
// 来自 core_test_support
async fn start_test_conversation(...) -> (Arc<TempDir>, Config, Arc<ThreadManager>, Arc<CodexThread>);
async fn user_turn(conversation: &Arc<CodexThread>, text: &str);
async fn compact_conversation(conversation: &Arc<CodexThread>);
async fn resume_conversation(...) -> Arc<CodexThread>;
async fn fork_thread(...) -> Arc<CodexThread>;
```

## 风险、边界与改进建议

### 已知风险

1. **Ghost Snapshot 污染**
   - 问题：压缩后的历史中可能包含 ghost snapshot 条目，影响模型可见历史
   - 缓解：测试中使用 `filter_out_ghost_snapshot_entries` 过滤
   - 代码：`is_ghost_snapshot_message` 检测逻辑

2. **历史前缀一致性**
   - 风险：恢复/分叉后的历史前缀可能与压缩后不一致
   - 测试验证：`assert_eq!(compact_arr.as_slice(), &resume_arr[..compact_arr.len()])`

3. **换行符规范化**
   - 跨平台问题：Windows (CRLF) vs Unix (LF)
   - 处理：`normalize_line_endings_str` 统一转换为 LF

### 边界情况

1. **空历史分叉** (`n=0`)
   - 保留第一个用户消息之前的所有内容（通常是系统提示）
   - 测试：`fork_thread(0, ...)` 验证行为

2. **多次压缩**
   - 场景：压缩 → 恢复 → 再压缩
   - 验证：第二次压缩应基于第一次的摘要继续

3. **Rollback 过压缩点**
   - 场景：回退到压缩之前的某个回合
   - 行为：从 rollout 文件重放 append-only 历史
   - 测试：`snapshot_rollback_past_compaction_replays_append_only_history`

### 改进建议

1. **测试覆盖**
   - 添加并发压缩测试（多线程同时触发压缩）
   - 添加大文件历史恢复性能测试
   - 添加网络中断后恢复测试

2. **代码重构**
   - 将 `normalize_compact_prompts` 逻辑提取到生产代码复用
   - 统一 ghost snapshot 处理逻辑

3. **监控增强**
   - 添加压缩比率指标（原始 token 数 / 压缩后 token 数）
   - 记录压缩触发原因（手动/自动/阈值）

4. **文档完善**
   - 补充压缩策略决策流程图
   - 明确 InitialContextInjection 两种模式的适用场景
