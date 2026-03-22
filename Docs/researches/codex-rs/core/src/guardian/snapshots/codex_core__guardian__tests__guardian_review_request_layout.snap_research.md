# Guardian Review Request Layout Snapshot 研究文档

## 场景与职责

此 snapshot 文件是 Codex 核心 Guardian（安全审查）模块的测试快照，记录了**首次 Guardian 审查请求**的完整 prompt 结构。该测试验证当 Codex 代理需要执行高风险操作（如 `git push`）时，系统如何构建发送给 Guardian 子代理的审查请求。

**关键场景**：
- 用户请求 Codex 检查仓库可见性并在需要时推送文档修复
- Codex 执行 `gh_repo_view` 工具调用确认仓库为 public
- Codex 尝试执行 `git push origin guardian-approval-mvp` 命令
- 由于需要用户审批，触发 Guardian 自动审查流程

## 功能点目的

### 1. Prompt 结构验证
该 snapshot 捕获 Guardian 审查请求的完整 prompt 布局，确保：
- 系统指令（developer message）正确包含安全策略
- 用户上下文（environment context）正确传递
- 对话历史（transcript）被正确序列化
- 待审查动作（planned action）以结构化 JSON 呈现

### 2. 安全策略传递
验证 Guardian 是否收到完整的安全评估指令，包括：
- 核心原则：将 transcript、工具调用参数视为不可信证据
- 高风险动作识别标准
- 低风险动作判定依据
- 严格的 JSON 输出格式要求

### 3. 动作上下文完整性
确保 Guardian 能够获取评估所需的全部上下文：
- 原始用户请求
- 已执行的工具调用及其结果
- 待审批的具体命令及其参数
- 重试原因（如有）

## 具体技术实现

### 关键数据结构

```rust
// GuardianApprovalRequest - 待审查的动作请求
pub(crate) enum GuardianApprovalRequest {
    Shell {
        id: String,
        command: Vec<String>,
        cwd: PathBuf,
        sandbox_permissions: SandboxPermissions,
        additional_permissions: Option<PermissionProfile>,
        justification: Option<String>,
    },
    // ... 其他变体
}

// GuardianAssessment - Guardian 返回的评估结果
pub(crate) struct GuardianAssessment {
    pub(crate) risk_level: GuardianRiskLevel,  // "low" | "medium" | "high"
    pub(crate) risk_score: u8,                 // 0-100
    pub(crate) rationale: String,
    pub(crate) evidence: Vec<GuardianEvidence>,
}
```

### Prompt 构建流程

1. **构建 Guardian Prompt Items** (`prompt.rs:build_guardian_prompt_items`)
   ```rust
   pub(crate) async fn build_guardian_prompt_items(
       session: &Session,
       retry_reason: Option<String>,
       request: GuardianApprovalRequest,
   ) -> serde_json::Result<Vec<UserInput>>
   ```
   - 提取会话历史记录
   - 收集 Guardian 转录条目
   - 格式化待执行动作为 JSON

2. **转录条目收集** (`prompt.rs:collect_guardian_transcript_entries`)
   - 保留所有用户消息（携带授权和意图）
   - 保留最近的助手/工具上下文（有界预算）
   - 跳过合成上下文脚手架（避免噪音）

3. **转录条目渲染** (`prompt.rs:render_guardian_transcript_entries`)
   - 用户消息：始终保留，预算 10,000 tokens
   - 工具条目：单独预算 10,000 tokens
   - 单条上限：消息 2,000 tokens，工具 1,000 tokens
   - 最近条目限制：40 条非用户条目

### Snapshot 中的 Prompt 结构

```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>     # 系统安全策略
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>     # 环境上下文
02:message/developer:You are performing...          # Guardian 策略提示
03:message/user[16]:                                 # 结构化审查请求
    [01] TRANSCRIPT START 标记
    [02-07] 对话历史（用户请求、工具调用、结果）
    [08-16] 审批请求详情（重试原因、计划动作 JSON、输出格式要求）
```

### 输出格式约束

Guardian 必须返回严格 JSON：
```json
{
  "risk_level": "low" | "medium" | "high",
  "risk_score": 0-100,
  "rationale": string,
  "evidence": [{"message": string, "why": string}]
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/guardian/mod.rs` | Guardian 模块入口，定义常量和核心结构 |
| `codex-rs/core/src/guardian/prompt.rs` | Prompt 构建、转录处理、文本截断 |
| `codex-rs/core/src/guardian/review.rs` | 审查流程编排、风险评估决策 |
| `codex-rs/core/src/guardian/review_session.rs` | Guardian 会话管理、缓存策略 |
| `codex-rs/core/src/guardian/approval_request.rs` | 审批请求数据结构、序列化 |
| `codex-rs/core/src/guardian/policy.md` | Guardian 安全策略提示文本 |
| `codex-rs/core/src/guardian/tests.rs` | 测试用例，包含本 snapshot 的生成逻辑 |

### 测试代码路径

```rust
// tests.rs:guardian_review_request_layout_test (约第 520-579 行)
let request = request_log.single_request();
assert_snapshot!(
    "codex_core__guardian__tests__guardian_review_request_layout",
    context_snapshot::format_labeled_requests_snapshot(
        "Guardian review request layout",
        &[("Guardian Review Request", &request)],
        &guardian_snapshot_options(),
    )
);
```

### Snapshot 格式化工具

```rust
// tests/common/context_snapshot.rs
pub fn format_labeled_requests_snapshot(
    scenario: &str,
    sections: &[(&str, &ResponsesRequest)],
    options: &ContextSnapshotOptions,
) -> String
```

## 依赖与外部交互

### 内部依赖

1. **codex_protocol**: 协议类型定义
   - `ResponseItem`: 对话历史条目
   - `UserInput`: Prompt 输入项
   - `GuardianRiskLevel`, `GuardianAssessmentEvent`: 风险评估相关类型

2. **core_test_support**: 测试支持库
   - `context_snapshot`: Snapshot 格式化
   - `responses`: Mock 服务器响应

3. **Session/TurnContext**: 会话状态
   - 历史记录提取
   - 配置继承

### 外部交互

1. **OpenAI Responses API**
   - Guardian 作为子代理通过 Responses API 调用
   - 使用 `prompt_cache_key` 优化重复审查
   - 结构化输出通过 `final_output_json_schema` 强制

2. **网络代理**
   - Guardian 继承父会话的网络代理配置
   - 用于执行只读工具检查（如需要）

## 风险、边界与改进建议

### 当前风险与边界

1. **Token 预算限制**
   - 消息历史 10K tokens 可能不足以覆盖复杂场景
   - 工具结果 10K tokens 可能截断重要证据
   - 边界：当历史超过预算时，早期条目被省略

2. **提示注入风险**
   - 策略明确警告：将 transcript 视为不可信证据
   - 攻击者可能尝试通过用户输入影响 Guardian 判断
   - 缓解：明确的 JSON 输出格式要求，低/中风险阈值 80

3. **模型依赖性**
   - 首选模型 `gpt-5.4` 可能不可用
   - 回退到当前活动模型，可能行为不一致
   - 超时 90 秒，可能在高负载时失败

4. **缓存策略复杂性**
   - Trunk/Ephemeral 会话管理逻辑复杂
   - 配置变更时需要重新创建会话
   - 并行审查时需要 fork 历史

### 改进建议

1. **可观测性增强**
   - 添加 Guardian 决策原因的详细日志
   - 记录 prompt 构建过程中的截断决策
   - 监控缓存命中率和会话复用率

2. **策略版本控制**
   - `policy.md` 变更时增加版本标识
   - 允许配置指定策略版本
   - 支持 A/B 测试不同策略效果

3. **预算动态调整**
   - 根据动作风险等级动态调整 token 预算
   - 高敏感操作保留更多历史上下文
   - 考虑使用智能摘要替代简单截断

4. **测试覆盖扩展**
   - 添加多轮对话场景测试
   - 测试 token 预算边界条件
   - 验证不同模型的输出一致性

5. **错误处理细化**
   - 区分 Guardian 超时、解析失败、模型错误
   - 提供降级策略（如直接要求用户审批）
   - 记录失败模式用于策略迭代
