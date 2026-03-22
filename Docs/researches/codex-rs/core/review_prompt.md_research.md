# review_prompt.md 研究文档

## 场景与职责

`codex-rs/core/review_prompt.md` 是 Codex CLI 代码审查功能的专用系统提示词文件，定义了 AI 代码审查助手的行为准则、评审标准和输出格式规范。当用户执行 `/review` 命令时，该 prompt 作为基础指令发送给审查模型，指导其如何分析代码变更并提供评审意见。

该 prompt 专门用于代码审查子代理（review sub-agent），与主对话模型隔离运行，确保审查的客观性和专注性。

## 功能点目的

### 1. 审查者角色定义
- **角色定位**：作为另一位工程师提出的代码变更的审查者
- **目标**：提供建设性、可操作的反馈意见
- **语气**：实事求是、非指责性、不过度积极

### 2. 缺陷判定标准

#### 2.1 通用判定准则（8 条）
1. **影响程度**：对代码准确性、性能、安全性或可维护性有实质性影响
2. **可行动性**：缺陷是离散且可操作的（非笼统问题或多问题组合）
3. **一致性要求**：修复缺陷不需要超出代码库现有水平的严谨性
4. **引入范围**：缺陷是在当前 commit 中引入的（不报告已存在的缺陷）
5. **作者意愿**：原始 PR 作者如果知晓该问题，可能会修复
6. **假设依赖**：缺陷不依赖于未声明的代码库或作者意图假设
7. **可证明性**：必须能识别出被影响的其他代码部分，而非仅推测
8. **意图明确**：缺陷明显不是原始作者有意为之的变更

#### 2.2 评论构造准则（8 条）
1. **清晰性**：明确说明为什么是缺陷
2. **严重性**：准确传达问题严重程度，不夸大
3. **简洁性**：最多 1 段，不在自然语言流中引入换行
4. **代码限制**：代码片段不超过 3 行，使用 markdown 代码标记
5. **场景说明**：明确说明缺陷出现的场景、环境或输入条件
6. **语气**：实事求是，像有帮助的 AI 助手建议，不像人类审查者
7. **可读性**：原始作者无需仔细阅读即可理解要点
8. **避免冗余**：避免过度赞美和无帮助的评论（如 "Great job..."）

### 3. 发现数量原则
- **输出所有发现**：输出原始作者如果知晓就会修复的所有发现
- **无发现时**：如果没有值得修复的发现，优先不输出任何发现
- **不提前停止**：不要在第一个符合条件的发现处停止，列出所有符合条件的发现

### 4. 详细指南

#### 4.1 风格与格式
- **忽略琐碎风格**：除非影响意义或违反文档化标准
- **单条评论原则**：每个独立问题一条评论（必要时可多行范围）
- **Suggestion 块**：仅在提供具体替换代码时使用 ```suggestion 块
- **缩进保留**：在 suggestion 块中精确保留被替换行的前导空格

#### 4.2 代码位置
- **行范围**：尽可能短（避免超过 5-10 行），选择最能 pinpoint 问题的子范围
- **与 diff 重叠**：代码位置应与 diff 有重叠
- **不生成 PR 修复**：不要生成 PR 修复代码

### 5. 优先级标记
- **[P0]**：放下一切立即修复。阻塞发布、运营或主要使用。仅用于不依赖输入假设的普遍问题
- **[P1]**：紧急。应在下个周期处理
- **[P2]**：正常。最终修复
- **[P3]**：低。锦上添花

### 6. 整体正确性判定
- **"patch is correct"**：现有代码和测试不会破坏，补丁无缺陷和其他阻塞问题
- **忽略非阻塞问题**：风格、格式、拼写、文档和其他小问题

### 7. 输出格式规范

#### JSON Schema
```json
{
  "findings": [
    {
      "title": "<≤ 80 chars, imperative>",
      "body": "<valid Markdown explaining *why* this is a problem; cite files/lines/functions>",
      "confidence_score": <float 0.0-1.0>,
      "priority": <int 0-3, optional>,
      "code_location": {
        "absolute_file_path": "<file path>",
        "line_range": {"start": <int>, "end": <int>}
      }
    }
  ],
  "overall_correctness": "patch is correct" | "patch is incorrect",
  "overall_explanation": "<1-3 sentence explanation justifying the overall_correctness verdict>",
  "overall_confidence_score": <float 0.0-1.0>
}
```

#### 格式要求
- 不要将 JSON 包装在 markdown 代码块或额外文本中
- `code_location` 字段必需，必须包含 `absolute_file_path` 和 `line_range`
- 行范围应尽可能短（避免超过 5-10 行）
- 代码位置应与 diff 有重叠

## 具体技术实现

### 编译时嵌入
```rust
// codex-rs/core/src/client_common.rs:17-18
/// Review thread system prompt. Edit `core/src/review_prompt.md` to customize.
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");
```

### 公共导出
```rust
// codex-rs/core/src/lib.rs:167
pub use client_common::REVIEW_PROMPT;
```

### 审查任务使用
```rust
// codex-rs/core/src/tasks/review.rs:106-107
// Set explicit review rubric for the sub-agent
sub_agent_config.base_instructions = Some(crate::REVIEW_PROMPT.to_string());
```

### 审查流程架构

#### 1. 审查请求发起
```rust
// codex-rs/core/src/review_prompts.rs:22-37
pub fn resolve_review_request(
    request: ReviewRequest,
    cwd: &Path,
) -> anyhow::Result<ResolvedReviewRequest> {
    let target = request.target;
    let prompt = review_prompt(&target, cwd)?;
    let user_facing_hint = request
        .user_facing_hint
        .unwrap_or_else(|| user_facing_hint(&target));

    Ok(ResolvedReviewRequest {
        target,
        prompt,
        user_facing_hint,
    })
}
```

#### 2. 审查目标类型
- `UncommittedChanges`：当前变更（staged、unstaged、untracked）
- `BaseBranch { branch }`：与基分支的对比
- `Commit { sha, title }`：特定 commit 的变更
- `Custom { instructions }`：自定义审查指令

#### 3. 子代理配置
```rust
// codex-rs/core/src/tasks/review.rs:93-114
async fn start_review_conversation(...) {
    let mut sub_agent_config = config.as_ref().clone();
    
    // 禁用审查专用功能限制
    sub_agent_config.web_search_mode.set(WebSearchMode::Disabled)?;
    sub_agent_config.features.disable(Feature::SpawnCsv);
    sub_agent_config.features.disable(Feature::Collab);

    // 设置审查专用 rubric
    sub_agent_config.base_instructions = Some(crate::REVIEW_PROMPT.to_string());
    sub_agent_config.permissions.approval_policy = Constrained::allow_only(AskForApproval::Never);

    // 使用审查专用模型（如果配置）
    let model = config.review_model
        .unwrap_or_else(|| ctx.model_info.slug.clone());
    sub_agent_config.model = Some(model);
    
    // 启动一次性子代理
    run_codex_thread_one_shot(...)
}
```

#### 4. 审查输出解析
```rust
// codex-rs/core/src/tasks/review.rs:187-202
fn parse_review_output_event(text: &str) -> ReviewOutputEvent {
    // 尝试完整 JSON 解析
    if let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(text) {
        return ev;
    }
    // 尝试提取 JSON 子串解析
    if let (Some(start), Some(end)) = (text.find('{'), text.rfind('}'))
        && start < end
        && let Some(slice) = text.get(start..=end)
        && let Ok(ev) = serde_json::from_str::<ReviewOutputEvent>(slice)
    {
        return ev;
    }
    // 回退：纯文本作为 overall_explanation
    ReviewOutputEvent {
        overall_explanation: text.to_string(),
        ..Default::default()
    }
}
```

#### 5. 审查结果格式化
```rust
// codex-rs/core/src/review_format.rs:23-58
pub fn format_review_findings_block(
    findings: &[ReviewFinding],
    selection: Option<&[bool]>,
) -> String {
    // 格式化发现列表为可读的文本块
    // 支持选择标记（checkbox）
}
```

#### 6. 审查模式生命周期
```
User submits /review
    -> EnteredReviewMode event
    -> ReviewTask::run()
        -> start_review_conversation()
            -> run_codex_thread_one_shot() with REVIEW_PROMPT
        -> process_review_events()
            -> parse_review_output_event()
        -> exit_review_mode()
            -> ExitedReviewMode event with ReviewOutputEvent
    -> TurnComplete event
```

## 关键代码路径与文件引用

### 主要引用点
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/core/src/client_common.rs` | 17-18 | 定义 `REVIEW_PROMPT` 常量 |
| `codex-rs/core/src/lib.rs` | 96, 167 | 模块导出和公共导出 |
| `codex-rs/core/src/tasks/review.rs` | 107 | 审查任务设置基础指令 |

### 审查相关文件
| 文件 | 描述 |
|------|------|
| `codex-rs/core/src/review_prompts.rs` | 审查请求解析和 prompt 生成 |
| `codex-rs/core/src/review_format.rs` | 审查结果格式化 |
| `codex-rs/core/src/tasks/review.rs` | 审查任务实现 |
| `codex-rs/core/templates/review/exit_success.xml` | 审查成功模板 |
| `codex-rs/core/templates/review/exit_interrupted.xml` | 审查中断模板 |

### 测试覆盖
| 文件 | 描述 |
|------|------|
| `codex-rs/core/tests/suite/review.rs` | 审查功能集成测试（936 行） |
| `codex-rs/core/src/client_common_tests.rs` | 客户端通用测试 |

### 测试用例概览
1. `review_op_emits_lifecycle_and_review_output`：验证审查生命周期和结构化输出
2. `review_op_with_plain_text_emits_review_fallback`：纯文本输出的回退处理
3. `review_filters_agent_message_related_events`：事件过滤验证
4. `review_does_not_emit_agent_message_on_structured_output`：结构化输出时不发送代理消息
5. `review_uses_custom_review_model_from_config`：自定义审查模型
6. `review_uses_session_model_when_review_model_unset`：默认使用会话模型
7. `review_input_isolated_from_parent_history`：审查输入与父历史隔离
8. `review_history_surfaces_in_parent_session`：审查历史在父会话中可见
9. `review_uses_overridden_cwd_for_base_branch_merge_base`：使用覆盖的 cwd 进行基分支比较

## 依赖与外部交互

### 内部依赖
- `codex_protocol::protocol::ReviewRequest`：审查请求协议类型
- `codex_protocol::protocol::ReviewOutputEvent`：审查输出事件
- `codex_protocol::protocol::ReviewFinding`：单个审查发现
- `codex_core::review_prompts`：审查 prompt 生成
- `codex_core::review_format`：审查结果格式化

### 子代理系统交互
```
REVIEW_PROMPT
    -> ReviewTask::start_review_conversation()
    -> run_codex_thread_one_shot()
    -> Sub-agent with isolated context
    -> Model API (OpenAI Responses API)
    -> ReviewOutputEvent (JSON)
    -> parse_review_output_event()
    -> exit_review_mode()
    -> Parent session history
```

### 配置交互
- `Config::review_model`：可选的审查专用模型
- `Config::base_instructions`：可覆盖默认审查指令

### UI 层交互
- `codex-rs/tui/src/chatwidget.rs`：TUI 审查结果显示
- `codex-rs/tui_app_server/src/chatwidget.rs`：TUI App Server 审查处理
- `codex-rs/app-server/src/bespoke_event_handling.rs`：App Server 事件处理

## 风险、边界与改进建议

### 风险点
1. **模型输出不一致**：不同模型对 JSON Schema 的遵循程度不同
2. **审查质量波动**：模型可能产生过多/过少审查意见，或误判严重性
3. **上下文隔离复杂性**：审查子代理与父会话的上下文隔离增加了状态管理复杂性
4. **Token 消耗**：代码审查需要额外模型调用，增加 Token 消耗

### 边界条件
1. **最大发现数量**：未明确限制，大量发现可能导致输出过长
2. **文件大小限制**：大文件的审查可能受上下文窗口限制
3. **JSON 解析容错**：解析失败时回退到纯文本，可能丢失结构化信息
4. **行范围精度**：模型生成的行范围可能不够精确

### 改进建议
1. **审查质量评估**：
   - 添加审查意见的有用性反馈机制
   - 基于用户反馈微调审查模型或 prompt

2. **增量审查**：
   - 支持仅审查自上次审查以来的新变更
   - 缓存已审查的 commit SHA

3. **审查规则自定义**：
   - 支持项目特定的审查规则（通过 AGENTS.md 或配置文件）
   - 支持审查规则模板（安全优先、性能优先等）

4. **多模型审查**：
   - 支持多个审查模型投票或互补
   - 安全敏感代码使用更强的模型审查

5. **审查结果持久化**：
   - 将审查结果保存到数据库，支持历史查询
   - 与 GitHub/GitLab PR 评论集成

6. **交互式审查**：
   - 支持用户对审查意见进行标记（接受/拒绝/稍后处理）
   - 支持基于审查意见自动生成修复建议

### 监控指标建议
- 审查任务完成率
- 结构化输出解析成功率
- 平均审查发现数量
- 用户对审查意见的接受率
- 审查任务平均耗时
