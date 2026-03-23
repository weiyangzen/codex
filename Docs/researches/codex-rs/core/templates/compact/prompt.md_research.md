# Research: codex-rs/core/templates/compact/prompt.md

## 场景与职责

该文件是 Codex CLI 核心库中的**上下文压缩（Context Compaction）模板文件**，用于在对话历史过长时生成一个"交接摘要"（handoff summary）。当 LLM 会话的 token 使用量接近或超过模型上下文窗口限制时，系统会触发 compaction 机制，使用该 prompt 模板请求模型生成一个简洁的摘要，以便替换冗长的历史记录。

该模板属于**本地压缩（local/inline compaction）** 流程的一部分，与远程压缩（remote compaction）相对。本地压缩通过构造特殊的用户消息发送给模型，要求其总结之前的对话内容。

## 功能点目的

1. **上下文窗口管理**：当对话历史接近模型上下文限制时，通过生成摘要来减少 token 使用量
2. **任务交接**：为后续接续工作的 LLM 提供清晰的上下文概要
3. **状态保存**：在压缩后保留关键的用户消息和决策信息

模板内容指导模型生成包含以下信息的摘要：
- 当前进展和关键决策
- 重要的上下文、约束条件或用户偏好
- 待完成的任务（明确的下一步）
- 继续工作所需的关键数据、示例或参考

## 具体技术实现

### 关键流程

1. **模板加载**：在 `codex-rs/core/src/compact.rs` 中通过 `include_str!` 宏编译时嵌入：
   ```rust
   pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
   ```

2. **本地压缩任务执行**（`run_compact_task_inner` 函数）：
   - 构造包含 `SUMMARIZATION_PROMPT` 的用户输入
   - 通过模型客户端流式发送请求
   - 接收模型生成的摘要内容
   - 将摘要与前缀 `SUMMARY_PREFIX` 组合

3. **历史记录重建**（`build_compacted_history` 函数）：
   - 保留原始用户消息（非摘要消息）
   - 添加新的摘要消息作为用户消息
   - 可选地注入初始上下文

### 数据结构

```rust
// 压缩任务配置
pub(crate) enum InitialContextInjection {
    BeforeLastUserMessage,  // 用于 mid-turn 压缩
    DoNotInject,            // 用于 pre-turn/manual 压缩
}

// 压缩结果项
pub struct CompactedItem {
    pub message: String,
    pub replacement_history: Option<Vec<ResponseItem>>,
}
```

### 关键常量

- `SUMMARIZATION_PROMPT`: 本模板内容
- `SUMMARY_PREFIX`: 来自 `summary_prefix.md`，用于标识摘要消息的前缀
- `COMPACT_USER_MESSAGE_MAX_TOKENS`: 20,000，用户消息的最大 token 限制

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/compact.rs` | 本地压缩核心逻辑，包含模板引用和压缩流程 |
| `codex-rs/core/src/compact_remote.rs` | 远程压缩实现（OpenAI  provider 使用） |
| `codex-rs/core/src/tasks/compact.rs` | 压缩任务定义和调度 |
| `codex-rs/codex-api/src/endpoint/compact.rs` | 远程压缩 API 客户端 |

### 调用路径

```
Codex::submit(Op::Compact) 
  -> CompactTask::run()
    -> should_use_remote_compact_task() ? 
       run_remote_compact_task() : run_compact_task()
         -> run_compact_task_inner()
           -> 使用 SUMMARIZATION_PROMPT 构造请求
           -> drain_to_completed() 获取模型响应
           -> build_compacted_history() 重建历史
```

### 测试文件

- `codex-rs/core/tests/suite/compact.rs`: 本地压缩测试套件
- `codex-rs/core/tests/suite/compact_remote.rs`: 远程压缩测试
- `codex-rs/core/tests/suite/compact_resume_fork.rs`: 压缩后恢复和分叉测试

## 依赖与外部交互

### 内部依赖

1. **模型客户端** (`crate::client::ModelClientSession`): 用于发送压缩请求
2. **上下文管理器** (`ContextManager`): 管理历史记录的增删改
3. **会话状态** (`Session`): 存储和更新压缩后的历史
4. **协议类型** (`codex_protocol`): `ResponseItem`, `TurnItem`, `ContextCompactionItem`

### 外部交互

1. **模型 API**: 本地压缩通过标准 chat completions/responses API 发送请求
2. **远程压缩端点** (`/v1/responses/compact`): OpenAI provider 专用的压缩端点

### 配置项

在 `Config` 中相关配置：
- `compact_prompt`: 可选的自定义压缩 prompt
- `model_auto_compact_token_limit`: 自动压缩触发阈值

## 风险、边界与改进建议

### 风险

1. **信息丢失**: 压缩过程会丢失历史细节，可能导致模型丢失重要上下文
2. **摘要质量依赖**: 摘要质量完全依赖模型能力，可能遗漏关键信息
3. **递归压缩**: 多次压缩后累积的信息损失（代码中已有警告提示）

### 边界条件

1. **Context Window 超限**: 即使压缩过程中也可能触发 `ContextWindowExceeded` 错误，代码会回退到删除最旧的历史项
2. **Token 限制**: `COMPACT_USER_MESSAGE_MAX_TOKENS` 限制保留的用户消息大小
3. **模型切换**: 切换到更小上下文窗口的模型时会触发预采样压缩（pre-sampling compaction）

### 改进建议

1. **模板国际化**: 当前模板为英文，可考虑根据用户语言偏好本地化
2. **可配置摘要长度**: 当前没有控制摘要长度的参数
3. **摘要质量评估**: 可考虑添加机制评估摘要是否保留了足够的上下文信息
4. **分层压缩**: 对于超长对话，可考虑多级压缩策略

### 相关日志和监控

代码中通过 `tracing` 记录的关键事件：
- 压缩失败：`error!("remote compaction failed", ...)`
- 历史项修剪：`error!("Context window exceeded while compacting; removing oldest history item", ...)`
- 遥测计数：`session_telemetry.counter("codex.task.compact", ...)` 区分 local/remote 类型
