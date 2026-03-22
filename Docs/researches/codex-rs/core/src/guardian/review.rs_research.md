# review.rs 研究文档

## 场景与职责

`review.rs` 是 Guardian 子代理系统的核心审查逻辑模块，负责：
1. 判断是否需要将批准请求路由到 Guardian（`routes_approval_to_guardian`）
2. 执行完整的 Guardian 审查流程（`run_guardian_review`）
3. 处理审查结果并转换为 `ReviewDecision`
4. 发送 Guardian 评估事件到客户端
5. 管理审查超时和取消

**核心定位：**
该模块是 Guardian 系统的"协调器"，连接了提示词构建、会话管理、事件系统和决策逻辑。

## 功能点目的

### 1. 路由判断（routes_approval_to_guardian）

判断当前 turn 是否应该使用 Guardian 进行自动审查：

```rust
pub(crate) fn routes_approval_to_guardian(turn: &TurnContext) -> bool {
    turn.approval_policy.value() == AskForApproval::OnRequest
        && turn.config.approvals_reviewer == ApprovalsReviewer::GuardianSubagent
}
```

**条件：**
- 批准策略为 `OnRequest`（需要时询问）
- 审查者为 `GuardianSubagent`（而非 `User`）

### 2. Guardian 审查者源检测（is_guardian_reviewer_source）

检测会话源是否为 Guardian 子代理：

```rust
pub(crate) fn is_guardian_reviewer_source(
    session_source: &SessionSource,
) -> bool {
    matches!(
        session_source,
        SessionSource::SubAgent(SubAgentSource::Other(name))
            if name == GUARDIAN_REVIEWER_NAME
    )
}
```

用于防止递归审查（Guardian 不应该审查自己的操作）。

### 3. 核心审查流程（run_guardian_review）

完整的审查流程实现：

**阶段 1：初始化**
- 提取请求 ID 和 turn ID
- 生成动作摘要（脱敏）
- 发送 `GuardianAssessmentStatus::InProgress` 事件

**阶段 2：取消检查**
- 检查外部取消令牌
- 如果已取消，发送 `Aborted` 事件并返回

**阶段 3：提示词构建**
- 调用 `build_guardian_prompt_items` 构建提示词
- 如果失败，转为错误评估

**阶段 4：审查会话执行**
- 调用 `run_guardian_review_session` 执行实际审查
- 处理完成、超时、中止三种结果

**阶段 5：结果处理**
- 成功：解析评估结果
- 错误/超时：生成高风险的默认评估

**阶段 6：决策**
- 风险分数 < 80：批准
- 风险分数 ≥ 80：拒绝
- 发送 `Warning` 事件和最终 `GuardianAssessment` 事件

**失败关闭原则（Fail Closed）：**
- 超时 → 视为高风险（拒绝）
- 执行失败 → 视为高风险（拒绝）
- 解析失败 → 视为高风险（拒绝）

### 4. 审查会话执行（run_guardian_review_session）

配置并执行 Guardian 审查会话：

**模型选择逻辑：**
1. 首选 `gpt-5.4`（如果可用）
2. 如果不可用，使用父 turn 的模型
3. 优先使用 `Low` reasoning effort（如果支持）

**配置构建：**
- 调用 `build_guardian_review_session_config` 创建 Guardian 专用配置
- 继承父会话的网络代理配置
- 设置只读沙箱策略

**会话执行：**
- 通过 `GuardianReviewSessionManager` 执行审查
- 处理完成、超时、中止结果
- 解析最终消息为 `GuardianAssessment`

### 5. 公共 API

**review_approval_request**：
标准审查入口，无外部取消支持。

**review_approval_request_with_cancel**：
支持外部取消令牌的审查入口，用于需要提前终止的场景。

## 具体技术实现

### GuardianReviewOutcome 枚举

```rust
pub(super) enum GuardianReviewOutcome {
    Completed(anyhow::Result<GuardianAssessment>),  // 成功完成（可能解析失败）
    TimedOut,                                        // 超时
    Aborted,                                         // 被取消
}
```

### 风险等级转换

```rust
fn guardian_risk_level_str(level: GuardianRiskLevel) -> &'static str {
    match level {
        GuardianRiskLevel::Low => "low",
        GuardianRiskLevel::Medium => "medium",
        GuardianRiskLevel::High => "high",
    }
}
```

### 拒绝消息常量

```rust
pub(crate) const GUARDIAN_REJECTION_MESSAGE: &str = concat!(
    "This action was rejected due to unacceptable risk. ",
    "The agent must not attempt to achieve the same outcome via workaround, ",
    "indirect execution, or policy circumvention. ",
    "Proceed only with a materially safer alternative, ",
    "or if the user explicitly approves the action after being informed of the risk. ",
    "Otherwise, stop and request user input.",
);
```

这条消息在 Guardian 拒绝操作后发送给用户/Agent，明确禁止绕过尝试。

### 核心流程代码

```rust
async fn run_guardian_review(
    session: Arc<Session>,
    turn: Arc<TurnContext>,
    request: GuardianApprovalRequest,
    retry_reason: Option<String>,
    external_cancel: Option<CancellationToken>,
) -> ReviewDecision {
    // 1. 发送 InProgress 事件
    session.send_event(..., GuardianAssessmentEvent {
        status: GuardianAssessmentStatus::InProgress,
        ...
    }).await;

    // 2. 检查取消
    if external_cancel.is_cancelled() { ... }

    // 3. 构建提示词并执行审查
    let outcome = match build_guardian_prompt_items(...) {
        Ok(prompt_items) => run_guardian_review_session(...).await,
        Err(err) => GuardianReviewOutcome::Completed(Err(err.into())),
    };

    // 4. 处理结果（失败关闭）
    let assessment = match outcome {
        Completed(Ok(a)) => a,
        Completed(Err(e)) => GuardianAssessment { risk_level: High, risk_score: 100, ... },
        TimedOut => GuardianAssessment { risk_level: High, risk_score: 100, ... },
        Aborted => { ... return ReviewDecision::Abort; }
    };

    // 5. 决策并发送事件
    let approved = assessment.risk_score < GUARDIAN_APPROVAL_RISK_THRESHOLD;
    session.send_event(..., WarningEvent { ... }).await;
    session.send_event(..., GuardianAssessmentEvent { status: if approved { Approved } else { Denied }, ... }).await;

    if approved { ReviewDecision::Approved } else { ReviewDecision::Denied }
}
```

## 关键代码路径与文件引用

### 调用关系图

```
外部调用者 (shell.rs, apply_patch.rs, network_approval.rs, mcp_tool_call.rs)
    ↓
review_approval_request() / review_approval_request_with_cancel()
    ↓
run_guardian_review()
    ├── build_guardian_prompt_items() [prompt.rs]
    ├── run_guardian_review_session()
    │   ├── build_guardian_review_session_config() [review_session.rs]
    │   ├── session.guardian_review_session.run_review() [review_session.rs]
    │   └── parse_guardian_assessment() [prompt.rs]
    └── session.send_event() [事件系统]
```

### 外部调用方

| 文件 | 函数 | 场景 |
|------|------|------|
| `tools/runtimes/shell.rs` | `review_approval_request` | Shell 命令审查 |
| `tools/runtimes/apply_patch.rs` | `review_approval_request` | ApplyPatch 审查 |
| `tools/network_approval.rs` | `review_approval_request` | 网络访问审查 |
| `mcp_tool_call.rs` | `review_approval_request` | MCP 工具审查 |

### 事件类型

发送的事件类型：
- `GuardianAssessmentEvent`：评估状态变更（InProgress/Approved/Denied/Aborted）
- `WarningEvent`：审查结果警告（批准/拒绝原因）

### 测试覆盖

`tests.rs` 中的相关测试：

| 测试 | 验证内容 |
|------|----------|
| `cancelled_guardian_review_emits_terminal_abort_without_warning` | 取消处理 |
| `routes_approval_to_guardian_requires_auto_only_review_policy` | 路由判断 |
| `guardian_review_request_layout_matches_model_visible_request_snapshot` | 完整流程 |
| `guardian_reuses_prompt_cache_key_and_appends_prior_reviews` | 会话复用 |
| `guardian_parallel_reviews_fork_from_last_committed_trunk_history` | 并行审查 |

## 依赖与外部交互

### 外部依赖

| Crate/模块 | 用途 |
|------------|------|
| `codex_protocol::protocol::*` | 事件类型、决策类型 |
| `tokio_util::sync::CancellationToken` | 取消支持 |
| `std::sync::Arc` | 共享状态 |

### 内部依赖

| 模块 | 依赖内容 |
|------|----------|
| `approval_request` | `GuardianApprovalRequest`, `guardian_request_id`, `guardian_assessment_action_value` |
| `prompt` | `build_guardian_prompt_items`, `guardian_output_schema`, `parse_guardian_assessment` |
| `review_session` | `GuardianReviewSessionParams`, `GuardianReviewSessionOutcome`, `build_guardian_review_session_config` |
| `codex` | `Session`, `TurnContext` |

### 配置关联

- `ApprovalsReviewer::GuardianSubagent`：启用 Guardian 审查
- `AskForApproval::OnRequest`：触发 Guardian 审查的策略
- `GUARDIAN_APPROVAL_RISK_THRESHOLD` (80)：风险阈值

## 风险、边界与改进建议

### 已知风险

1. **单点故障**：
   - Guardian 审查失败（超时/错误）会导致操作被拒绝
   - 虽然符合"失败关闭"原则，但可能影响可用性

2. **模型依赖**：
   - 硬编码依赖 `gpt-5.4` 模型
   - 如果模型不可用，降级逻辑可能不够完善

3. **递归风险**：
   - 虽然 `is_guardian_reviewer_source` 防止了直接递归
   - 但间接递归（Guardian → Tool → Guardian）仍可能发生

4. **事件顺序**：
   - 事件发送是异步的，可能乱序到达客户端
   - 客户端需要按 ID 和状态处理

### 边界情况

1. **快速取消**：
   - 如果在 `InProgress` 事件发送前取消，仍可能发送事件
   - 需要确保状态一致性

2. **模型不可用**：
   - 如果首选和备用模型都不可用，审查会失败
   - 降级到用户确认的逻辑需要验证

3. **网络中断**：
   - 审查会话执行期间网络中断会导致超时
   - 超时后需要清理资源

4. **并发审查**：
   - 多个操作同时请求 Guardian 审查
   - `GuardianReviewSessionManager` 处理并发逻辑

### 改进建议

1. **可配置阈值**：
   - 将风险阈值 80 改为可配置
   - 支持不同操作类型使用不同阈值

2. **审查缓存**：
   - 缓存相同请求的审查结果
   - 减少重复审查的延迟和成本

3. **审查解释**：
   - 在拒绝时提供更详细的解释
   - 包括具体的策略条款引用

4. **人工回退**：
   - 当 Guardian 不确定时（如风险分数 70-80），转人工确认
   - 而非直接拒绝

5. **A/B 测试支持**：
   - 支持同时运行多个 Guardian 配置
   - 比较不同策略的效果

6. **模型选择优化**：
   - 根据操作类型选择最适合的模型
   - 例如，代码审查用代码模型，网络审查用通用模型

7. **可观测性增强**：
   - 添加详细的审查指标（延迟、成功率、分布）
   - 记录完整的审查上下文用于审计

8. **批量审查**：
   - 支持批量提交多个相关操作进行联合审查
   - 评估组合风险而非单个风险
