# exit_interrupted.xml 研究文档

## 场景与职责

`exit_interrupted.xml` 是 Codex 代码审查（Review）功能的关键模板文件，用于在审查任务被用户中断时生成标准化的用户消息。该模板定义了当用户启动审查任务但任务被中断（如用户取消、网络问题或其他异常）时，系统向主对话历史中记录的用户消息格式。

### 使用场景
1. **用户主动中断**：用户在审查进行中按 Ctrl+C 或发送取消信号
2. **任务异常终止**：审查子进程因错误或其他原因非正常结束
3. **超时或资源限制**：审查任务因系统限制被强制终止

## 功能点目的

该模板的核心目的是：
1. **状态记录**：在对话历史中明确标记审查任务的中断状态
2. **上下文保持**：让后续对话能够感知到之前发生过一次被中断的审查
3. **用户引导**：提示用户如果需要完成审查，需要重新发起 `/review` 命令

### 模板内容解析

```xml
<user_action>
  <context>User initiated a review task, but was interrupted. If user asks about this, tell them to re-initiate a review with `/review` and wait for it to complete.</context>
  <action>review</action>
  <results>
  None.
  </results>
</user_action>
```

- `<context>`：描述发生了什么（审查被中断）以及如何处理（重新发起 `/review`）
- `<action>`：标识这是一个 review 类型的操作
- `<results>`：固定为 "None"，表示没有产生有效的审查结果

## 具体技术实现

### 模板加载与常量定义

模板通过 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/core/src/client_common.rs 第21-23行
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str = 
    include_str!("../templates/review/exit_interrupted.xml");
```

### 调用流程

1. **审查任务执行** (`codex-rs/core/src/tasks/review.rs`):
   - `ReviewTask::run()` 方法执行审查流程
   - 如果 `cancellation_token.is_cancelled()` 为 true，调用 `exit_review_mode()`

2. **退出审查模式** (`codex-rs/core/src/tasks/review.rs` 第206-273行):
   ```rust
   pub(crate) async fn exit_review_mode(
       session: Arc<Session>,
       review_output: Option<ReviewOutputEvent>,
       ctx: Arc<TurnContext>,
   ) {
       const REVIEW_USER_MESSAGE_ID: &str = "review_rollout_user";
       const REVIEW_ASSISTANT_MESSAGE_ID: &str = "review_rollout_assistant";
       let (user_message, assistant_message) = if let Some(out) = review_output.clone() {
           // 成功完成的情况，使用 exit_success.xml 模板
           ...
       } else {
           // 被中断的情况，使用 exit_interrupted.xml 模板
           let rendered = crate::client_common::REVIEW_EXIT_INTERRUPTED_TMPL.to_string();
           let assistant_message =
               "Review was interrupted. Please re-run /review and wait for it to complete."
                   .to_string();
           (rendered, assistant_message)
       };
       
       // 记录用户消息到对话历史
       session.record_conversation_items(...).await;
       
       // 发送 ExitedReviewMode 事件
       session.send_event(...).await;
       
       // 记录助手消息
       session.record_response_item_and_emit_turn_item(...).await;
   }
   ```

### 数据结构

审查输出事件结构（`codex-rs/protocol/src/protocol.rs` 第2564-2580行）：

```rust
pub struct ReviewOutputEvent {
    pub findings: Vec<ReviewFinding>,
    pub overall_correctness: String,
    pub overall_explanation: String,
    pub overall_confidence_score: f32,
}
```

当 `review_output` 为 `None` 时，表示审查被中断，使用 `exit_interrupted.xml` 模板。

## 关键代码路径与文件引用

### 核心文件
1. **模板定义**：`codex-rs/core/templates/review/exit_interrupted.xml`
2. **模板加载**：`codex-rs/core/src/client_common.rs` 第21-23行
3. **使用位置**：`codex-rs/core/src/tasks/review.rs` 第228行

### 相关文件
- `codex-rs/core/src/tasks/review.rs`：审查任务实现，`exit_review_mode()` 函数
- `codex-rs/core/src/client_common.rs`：模板常量定义
- `codex-rs/protocol/src/protocol.rs`：`ReviewOutputEvent` 和 `ExitedReviewModeEvent` 定义
- `codex-rs/core/tests/suite/review.rs`：审查功能测试套件

### 调用链
```
ReviewTask::run()
  └── exit_review_mode()
        └── REVIEW_EXIT_INTERRUPTED_TMPL (当 review_output 为 None 时)
              └── 记录到对话历史 + 发送 ExitedReviewMode 事件
```

## 依赖与外部交互

### 依赖模块
1. **协议层**：`codex_protocol::protocol::ExitedReviewModeEvent`
2. **会话管理**：`Session::record_conversation_items()` 和 `Session::send_event()`
3. **任务系统**：`SessionTask` trait 和 `CancellationToken`

### 事件流
1. 审查任务被中断时，`exit_review_mode()` 被调用
2. 生成 `ExitedReviewModeEvent` 事件（`review_output` 为 `None`）
3. 事件通过 `session.send_event()` 发送给客户端
4. 用户消息通过 `session.record_conversation_items()` 持久化到 rollout

### 客户端处理
- TUI 客户端通过 `EventMsg::ExitedReviewMode` 事件感知审查结束
- `tui_app_server/src/chatwidget.rs` 处理该事件并更新 UI 状态

## 风险、边界与改进建议

### 潜在风险

1. **模板内容硬编码**：模板内容变更需要重新编译，无法运行时配置
2. **XML 格式依赖**：如果协议从 XML 切换到其他格式（如 JSON），需要同步更新
3. **国际化缺失**：模板内容为英文硬编码，不支持多语言

### 边界情况

1. **并发审查**：当前实现假设同一时间只有一个审查任务，如果有并发需要确保消息 ID 唯一
2. **重复中断**：如果审查任务连续多次被中断，每次都会在历史中记录一条中断消息
3. **恢复机制**：当前实现不支持从中断点恢复审查，用户需要重新开始

### 改进建议

1. **模板外部化**：
   - 考虑将模板移至配置文件或资源文件，支持运行时更新
   - 允许用户自定义中断消息内容

2. **增强上下文**：
   - 在中断消息中包含更多上下文信息，如审查开始时间、已处理的文件数等
   - 记录中断原因（用户取消 vs 系统错误）

3. **国际化支持**：
   - 使用本地化框架（如 `fluent` 或 `i18n`）支持多语言模板

4. **测试覆盖**：
   - 当前测试主要关注成功路径，建议增加更多中断场景的测试用例
   - 验证中断后重新发起审查的正确性

5. **与 exit_success.xml 的对比**：
   - 两个模板结构相似，但 `exit_success.xml` 包含 `{results}` 占位符用于动态内容
   - 考虑统一模板风格，或提取公共部分减少维护成本
