# codex-rs/core/templates/review 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位
`codex-rs/core/templates/review/` 目录包含 Codex 代码审查功能的核心模板文件，用于支持 `/review` 命令的完整生命周期管理。该目录位于 `codex-rs/core/templates/` 下，与 `agents/` 目录并列，专门处理代码审查场景下的消息格式化和状态管理。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **审查结果格式化** | 定义审查成功/中断状态的 XML 消息模板 |
| **历史消息记录** | 提供审查会话历史消息的 Markdown 格式 |
| **状态转换标记** | 通过结构化 XML 标记审查会话的生命周期状态 |
| **用户交互上下文** | 为用户和助手消息提供一致的格式框架 |

### 1.3 使用场景

```
用户触发 /review 命令
    ↓
系统进入审查模式 (EnteredReviewMode)
    ↓
子 Agent 执行代码审查
    ↓
审查完成 → 使用 exit_success.xml 格式化结果
    ↓
或审查中断 → 使用 exit_interrupted.xml 标记状态
    ↓
系统退出审查模式 (ExitedReviewMode)
```

---

## 功能点目的

### 2.1 模板文件功能详解

#### 2.1.1 `exit_success.xml` - 审查成功退出模板

**用途**: 当审查任务成功完成时，用于格式化审查结果并记录到对话历史中。

**内容结构**:
```xml
<user_action>
  <context>User initiated a review task. Here's the full review output from reviewer model. User may select one or more comments to resolve.</context>
  <action>review</action>
  <results>
  {results}
  </results>
</user_action>
```

**关键特性**:
- 包含 `{results}` 占位符，用于注入格式化的审查发现
- 明确标记 `action` 类型为 `review`
- 提供上下文说明，告知用户可以选中评论进行解决

#### 2.1.2 `exit_interrupted.xml` - 审查中断退出模板

**用途**: 当审查任务被用户中断或异常终止时使用。

**内容结构**:
```xml
<user_action>
  <context>User initiated a review task, but was interrupted. If user asks about this, tell them to re-initiate a review with `/review` and wait for it to complete.</context>
  <action>review</action>
  <results>
  None.
  </results>
</user_action>
```

**关键特性**:
- 明确标记中断状态
- 提供用户指导：建议重新发起 `/review` 命令
- 结果为 `None`，表示无有效输出

#### 2.1.3 `history_message_completed.md` 与 `history_message_interrupted.md`

这两个 Markdown 文件与对应的 XML 模板内容几乎一致，但用于不同的记录场景：

| 文件 | 用途差异 |
|-----|---------|
| `history_message_completed.md` | 使用 `{findings}` 占位符（而非 `{results}`），用于历史记录中的发现列表 |
| `history_message_interrupted.md` | 与 XML 版本一致，用于标记中断状态 |

**注意**: 根据代码分析，实际使用的是 XML 版本模板（`exit_success.xml` 和 `exit_interrupted.xml`），Markdown 版本可能是遗留文件或用于其他展示场景。

### 2.2 模板在系统中的角色

```
┌─────────────────────────────────────────────────────────────┐
│                     Review Task Flow                        │
├─────────────────────────────────────────────────────────────┤
│  1. User submits Op::Review                                  │
│           ↓                                                  │
│  2. handlers::review() → spawn_review_thread()              │
│           ↓                                                  │
│  3. ReviewTask::run() → start_review_conversation()         │
│           ↓                                                  │
│  4. process_review_events() → parse_review_output_event()   │
│           ↓                                                  │
│  5. exit_review_mode()                                      │
│           ↓                                                  │
│  6. ┌─────────────────────────────────────────┐             │
│     │ 使用 REVIEW_EXIT_SUCCESS_TMPL 或        │             │
│     │     REVIEW_EXIT_INTERRUPTED_TMPL        │             │
│     │ 格式化审查结果并记录到历史              │             │
│     └─────────────────────────────────────────┘             │
│           ↓                                                  │
│  7. Emit ExitedReviewMode event                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 具体技术实现

### 3.1 模板加载机制

模板通过 Rust 的 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/core/src/client_common.rs
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");

// Centralized templates for review-related user messages
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str =
    include_str!("../templates/review/exit_interrupted.xml");
```

**技术特点**:
- 编译时嵌入，无运行时文件读取开销
- 保证模板始终可用，不受部署环境影响
- 修改模板需要重新编译

### 3.2 模板使用流程

#### 3.2.1 成功场景 (`exit_review_mode` 函数)

```rust
// codex-rs/core/src/tasks/review.rs
pub(crate) async fn exit_review_mode(
    session: Arc<Session>,
    review_output: Option<ReviewOutputEvent>,
    ctx: Arc<TurnContext>,
) {
    const REVIEW_USER_MESSAGE_ID: &str = "review_rollout_user";
    const REVIEW_ASSISTANT_MESSAGE_ID: &str = "review_rollout_assistant";
    let (user_message, assistant_message) = if let Some(out) = review_output.clone() {
        let mut findings_str = String::new();
        let text = out.overall_explanation.trim();
        if !text.is_empty() {
            findings_str.push_str(text);
        }
        if !out.findings.is_empty() {
            let block = format_review_findings_block(&out.findings, /*selection*/ None);
            findings_str.push_str(&format!("\n{block}"));
        }
        // 使用 REVIEW_EXIT_SUCCESS_TMPL 模板
        let rendered =
            crate::client_common::REVIEW_EXIT_SUCCESS_TMPL.replace("{results}", &findings_str);
        let assistant_message = render_review_output_text(&out);
        (rendered, assistant_message)
    } else {
        // 使用 REVIEW_EXIT_INTERRUPTED_TMPL 模板
        let rendered = crate::client_common::REVIEW_EXIT_INTERRUPTED_TMPL.to_string();
        let assistant_message =
            "Review was interrupted. Please re-run /review and wait for it to complete."
                .to_string();
        (rendered, assistant_message)
    };

    // 记录用户消息到对话历史
    session
        .record_conversation_items(
            &ctx,
            &[ResponseItem::Message {
                id: Some(REVIEW_USER_MESSAGE_ID.to_string()),
                role: "user".to_string(),
                content: vec![ContentItem::InputText { text: user_message }],
                end_turn: None,
                phase: None,
            }],
        )
        .await;

    // 发送 ExitedReviewMode 事件
    session
        .send_event(
            ctx.as_ref(),
            EventMsg::ExitedReviewMode(ExitedReviewModeEvent { review_output }),
        )
        .await;
    
    // 记录助手消息
    session
        .record_response_item_and_emit_turn_item(
            ctx.as_ref(),
            ResponseItem::Message {
                id: Some(REVIEW_ASSISTANT_MESSAGE_ID.to_string()),
                role: "assistant".to_string(),
                content: vec![ContentItem::OutputText {
                    text: assistant_message,
                }],
                end_turn: None,
                phase: None,
            },
        )
        .await;

    // 确保 rollout 持久化
    session.ensure_rollout_materialized().await;
}
```

#### 3.2.2 数据流结构

```
ReviewOutputEvent
    ├── findings: Vec<ReviewFinding>
    │       ├── title: String
    │       ├── body: String
    │       ├── confidence_score: f32
    │       ├── priority: i32
    │       └── code_location: ReviewCodeLocation
    │               ├── absolute_file_path: PathBuf
    │               └── line_range: ReviewLineRange
    ├── overall_correctness: String
    ├── overall_explanation: String
    └── overall_confidence_score: f32
```

### 3.3 审查输出格式化

#### 3.3.1 `format_review_findings_block` 函数

```rust
// codex-rs/core/src/review_format.rs
pub fn format_review_findings_block(
    findings: &[ReviewFinding],
    selection: Option<&[bool]>,
) -> String {
    let mut lines: Vec<String> = Vec::new();
    lines.push(String::new());

    // Header
    if findings.len() > 1 {
        lines.push("Full review comments:".to_string());
    } else {
        lines.push("Review comment:".to_string());
    }

    for (idx, item) in findings.iter().enumerate() {
        lines.push(String::new());

        let title = &item.title;
        let location = format_location(item);

        if let Some(flags) = selection {
            // 带选择框的格式（用于 UI 交互）
            let checked = flags.get(idx).copied().unwrap_or(true);
            let marker = if checked { "[x]" } else { "[ ]" };
            lines.push(format!("- {marker} {title} — {location}"));
        } else {
            // 简单列表格式
            lines.push(format!("- {title} — {location}"));
        }

        for body_line in item.body.lines() {
            lines.push(format!("  {body_line}"));
        }
    }

    lines.join("\n")
}
```

### 3.4 审查提示词系统

#### 3.4.1 `review_prompt.md` 主提示词

位于 `codex-rs/core/review_prompt.md`，定义了审查模型的行为准则：

**核心指导原则**:
1. 准确性、性能、安全性、可维护性影响评估
2. 问题必须是离散且可操作的
3. 修复需求不应超出代码库现有严谨程度
4. 只标记本次提交引入的问题（非预存问题）
5. 作者可能会修复的问题才标记

**输出格式要求**:
```json
{
  "findings": [
    {
      "title": "<≤ 80 chars, imperative>",
      "body": "<valid Markdown explaining *why* this is a problem>",
      "confidence_score": <float 0.0-1.0>,
      "priority": <int 0-3>,
      "code_location": {
        "absolute_file_path": "<file path>",
        "line_range": {"start": <int>, "end": <int>}
      }
    }
  ],
  "overall_correctness": "patch is correct" | "patch is incorrect",
  "overall_explanation": "<1-3 sentence explanation>",
  "overall_confidence_score": <float 0.0-1.0>
}
```

**优先级定义**:
- `[P0]` - 阻塞性问题，立即修复
- `[P1]` - 紧急，下一周期处理
- `[P2]` - 正常， eventually 修复
- `[P3]` - 低优先级，锦上添花

### 3.5 Guardian 审查系统（关联系统）

虽然 Guardian 系统使用独立的策略文件（`guardian/policy.md`），但它与 Review 系统共享类似的模板机制：

```rust
// codex-rs/core/src/guardian/prompt.rs
pub(crate) fn guardian_policy_prompt() -> String {
    let prompt = include_str!("policy.md").trim_end();
    format!("{prompt}\n\n{}\n", guardian_output_contract_prompt())
}
```

Guardian 输出 schema:
```json
{
  "risk_level": "low" | "medium" | "high",
  "risk_score": 0-100,
  "rationale": string,
  "evidence": [{"message": string, "why": string}]
}
```

---

## 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/
├── templates/review/
│   ├── exit_success.xml              # 审查成功退出模板
│   ├── exit_interrupted.xml          # 审查中断退出模板
│   ├── history_message_completed.md  # 历史消息完成模板（Markdown）
│   └── history_message_interrupted.md # 历史消息中断模板（Markdown）
├── src/
│   ├── client_common.rs              # 模板加载和 REVIEW_PROMPT
│   ├── review_format.rs              # 审查结果格式化
│   ├── review_prompts.rs             # 审查提示词解析
│   ├── tasks/review.rs               # ReviewTask 实现
│   ├── guardian/
│   │   ├── mod.rs                    # Guardian 模块入口
│   │   ├── prompt.rs                 # Guardian 提示词构建
│   │   ├── review.rs                 # Guardian 审查逻辑
│   │   ├── review_session.rs         # Guardian 会话管理
│   │   └── policy.md                 # Guardian 策略文档
│   └── codex.rs                      # 主 Codex 逻辑，包含 review handler
└── review_prompt.md                  # 主审查提示词文档
```

### 4.2 调用链详细路径

#### 4.2.1 Review 命令处理流程

```
1. Op::Review 提交
   └── codex-rs/core/src/codex.rs:4367
       └── handlers::review()
           └── codex-rs/core/src/codex.rs:5147-5179

2. 审查线程创建
   └── spawn_review_thread()
       └── codex-rs/core/src/codex.rs:5182-5329
           ├── 构建 review_turn_context
           ├── 创建 ReviewTask
           └── 发送 EnteredReviewMode 事件

3. ReviewTask 执行
   └── codex-rs/core/src/tasks/review.rs:42-85
       ├── start_review_conversation()
       │   └── 创建子 Codex 会话
       ├── process_review_events()
       │   └── 解析 ReviewOutputEvent
       └── exit_review_mode()
           └── 使用模板格式化结果

4. 模板使用
   └── codex-rs/core/src/tasks/review.rs:224
       └── REVIEW_EXIT_SUCCESS_TMPL.replace("{results}", &findings_str)
```

#### 4.2.2 关键数据结构

```rust
// Protocol 定义（codex-rs/protocol/src/protocol.rs）

pub struct ReviewOutputEvent {
    pub findings: Vec<ReviewFinding>,
    pub overall_correctness: String,
    pub overall_explanation: String,
    pub overall_confidence_score: f32,
}

pub struct ReviewFinding {
    pub title: String,
    pub body: String,
    pub confidence_score: f32,
    pub priority: i32,
    pub code_location: ReviewCodeLocation,
}

pub struct ReviewCodeLocation {
    pub absolute_file_path: PathBuf,
    pub line_range: ReviewLineRange,
}

pub struct ReviewLineRange {
    pub start: u32,
    pub end: u32,
}
```

### 4.3 测试覆盖

```
codex-rs/core/tests/suite/review.rs
├── review_op_emits_lifecycle_and_review_output()
├── review_op_with_plain_text_emits_review_fallback()
├── review_filters_agent_message_related_events()
├── review_does_not_emit_agent_message_on_structured_output()
├── review_uses_custom_review_model_from_config()
├── review_uses_session_model_when_review_model_unset()
├── review_input_isolated_from_parent_history()
├── review_history_surfaces_in_parent_session()
└── review_uses_overridden_cwd_for_base_branch_merge_base()
```

---

## 依赖与外部交互

### 5.1 内部依赖

| 模块 | 依赖关系 | 说明 |
|-----|---------|------|
| `client_common` | 模板定义 | 通过 `include_str!` 加载模板 |
| `tasks/review` | 模板使用 | 调用模板格式化审查结果 |
| `review_format` | 格式化辅助 | 提供 `format_review_findings_block` |
| `review_prompts` | 提示词生成 | 解析 ReviewRequest 生成提示词 |
| `codex` | 主逻辑 | 处理 Op::Review 并创建审查线程 |
| `guardian` | 安全审查 | 并行存在的审查子系统 |

### 5.2 协议依赖

```rust
// codex-rs/protocol/src/protocol.rs

// 事件类型
EventMsg::EnteredReviewMode(ReviewRequest)
EventMsg::ExitedReviewMode(ExitedReviewModeEvent)

// 审查请求
pub struct ReviewRequest {
    pub target: ReviewTarget,
    pub user_facing_hint: Option<String>,
}

// 审查目标类型
pub enum ReviewTarget {
    UncommittedChanges,
    BaseBranch { branch: String },
    Commit { sha: String, title: Option<String> },
    Custom { instructions: String },
}
```

### 5.3 外部接口

#### 5.3.1 与 TUI/App-Server 的交互

```
┌─────────────┐     EventMsg::EnteredReviewMode      ┌─────────────┐
│             │ ───────────────────────────────────→ │             │
│   Codex     │                                      │  TUI/App    │
│   Core      │     EventMsg::ExitedReviewMode       │   Server    │
│             │ ───────────────────────────────────→ │             │
└─────────────┘                                      └─────────────┘
```

#### 5.3.2 与模型服务的交互

```
ReviewTask
    ↓
run_codex_thread_one_shot()
    ↓
创建子 Codex 会话（使用 review_model 或默认模型）
    ↓
提交 UserTurn 到模型 API
    ↓
解析模型返回的 JSON 输出为 ReviewOutputEvent
```

### 5.4 配置依赖

```rust
// Config 中与 review 相关的字段
pub struct Config {
    pub review_model: Option<String>,  // 专用审查模型
    // ... 其他字段
}
```

---

## 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 模板内容风险

| 风险 | 描述 | 影响 |
|-----|------|------|
| 硬编码占位符 | 模板使用 `{results}` 和 `{findings}` 占位符，如果替换逻辑出错会导致格式错误 | 中等 |
| XML 格式依赖 | 模板格式与解析逻辑紧密耦合 | 低 |
| 多语言支持 | 模板内容为英文，无国际化支持 | 低 |

#### 6.1.2 代码路径风险

```rust
// 潜在问题：模板替换失败时的回退逻辑
let rendered =
    crate::client_common::REVIEW_EXIT_SUCCESS_TMPL.replace("{results}", &findings_str);
```

- **风险**: 如果 `findings_str` 包含 XML 特殊字符（`<`, `>`, `&`），可能导致格式问题
- **缓解**: 当前代码未进行 XML 转义，依赖上层保证内容安全

#### 6.1.3 遗留文件风险

`history_message_completed.md` 和 `history_message_interrupted.md` 似乎未被直接使用，但：
- 可能用于未来功能
- 可能与某些外部工具集成
- 需要维护一致性

### 6.2 边界情况

#### 6.2.1 审查输出解析边界

```rust
// codex-rs/core/src/tasks/review.rs:187-202
fn parse_review_output_event(text: &str) -> ReviewOutputEvent {
    if let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(text) {
        return ev;
    }
    // 尝试从文本中提取 JSON 子串
    if let (Some(start), Some(end)) = (text.find('{'), text.rfind('}'))
        && start < end
        && let Some(slice) = text.get(start..=end)
        && let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(slice)
    {
        return ev;
    }
    // 回退：将纯文本作为 overall_explanation
    ReviewOutputEvent {
        overall_explanation: text.to_string(),
        ..Default::default()
    }
}
```

**边界情况**:
1. 模型返回非 JSON 格式 → 回退到纯文本模式
2. JSON 解析失败 → 尝试提取子串
3. 完全无法解析 → 使用默认结构

#### 6.2.2 空结果处理

```rust
if !out.findings.is_empty() {
    let block = format_review_findings_block(&out.findings, /*selection*/ None);
    findings_str.push_str(&format!("\n{block}"));
}
```

- 空 findings 列表时仅显示 overall_explanation
- 如果 overall_explanation 也为空，则结果可能为空

### 6.3 改进建议

#### 6.3.1 短期改进

1. **XML 转义处理**
   ```rust
   // 建议添加 XML 转义
   fn escape_xml(s: &str) -> String {
       s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
   }
   ```

2. **模板验证测试**
   - 添加测试确保模板占位符正确替换
   - 验证 XML 格式有效性

3. **清理遗留文件**
   - 确认 `history_message_*.md` 是否被使用
   - 如未使用，考虑删除或标记为废弃

#### 6.3.2 中期改进

1. **模板国际化支持**
   ```
   templates/review/
   ├── en/
   │   ├── exit_success.xml
   │   └── exit_interrupted.xml
   ├── zh/
   │   ├── exit_success.xml
   │   └── exit_interrupted.xml
   └── ...
   ```

2. **模板可配置化**
   - 允许用户自定义审查输出格式
   - 通过配置指定模板路径

3. **增强错误处理**
   - 模板替换失败时提供详细错误信息
   - 添加模板版本控制

#### 6.3.3 长期改进

1. **统一模板系统**
   - 与 Guardian 系统共享模板基础设施
   - 建立模板注册表机制

2. **动态模板加载**
   - 运行时热更新模板
   - 支持 A/B 测试不同模板效果

3. **结构化日志**
   - 记录模板使用统计
   - 分析不同模板对用户行为的影响

### 6.4 监控与可观测性建议

```rust
// 建议添加的指标
pub struct ReviewMetrics {
    pub review_task_count: Counter,
    pub review_success_count: Counter,
    pub review_interrupt_count: Counter,
    pub review_parse_failure_count: Counter,
    pub review_duration_seconds: Histogram,
    pub findings_per_review: Histogram,
}
```

### 6.5 文档维护建议

1. **模板变更日志**: 记录每次模板修改的原因和影响
2. **版本兼容性**: 模板与代码版本匹配说明
3. **使用示例**: 提供模板使用的具体示例

---

## 附录

### A. 文件完整列表

```
codex-rs/core/templates/review/
├── exit_interrupted.xml              (8 lines)
├── exit_success.xml                  (8 lines)
├── history_message_completed.md      (8 lines)
└── history_message_interrupted.md    (8 lines)
```

### B. 相关常量定义

```rust
// codex-rs/core/src/client_common.rs
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str = include_str!("../templates/review/exit_interrupted.xml");

// codex-rs/core/src/tasks/review.rs
const REVIEW_USER_MESSAGE_ID: &str = "review_rollout_user";
const REVIEW_ASSISTANT_MESSAGE_ID: &str = "review_rollout_assistant";
```

### C. 模板内容参考

**exit_success.xml**:
```xml
<user_action>
  <context>User initiated a review task. Here's the full review output from reviewer model. User may select one or more comments to resolve.</context>
  <action>review</action>
  <results>
  {results}
  </results>
  </user_action>
```

**exit_interrupted.xml**:
```xml
<user_action>
  <context>User initiated a review task, but was interrupted. If user asks about this, tell them to re-initiate a review with `/review` and wait for it to complete.</context>
  <action>review</action>
  <results>
  None.
  </results>
</user_action>
```

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/core/templates/review/*
*关联模块: client_common, tasks/review, review_format, codex, guardian*
