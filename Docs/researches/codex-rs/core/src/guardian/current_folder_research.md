# Guardian 模块研究文档

## 概述

Guardian（守护者）是 Codex 核心中的自动审批子系统，用于在 `on-request` 审批模式下自动评估和决策是否批准敏感操作，而无需用户手动介入。它通过创建一个独立的 AI 子代理来评估风险，实现"fail closed"（故障安全）的安全策略。

---

## 场景与职责

### 核心场景

Guardian 在以下场景中被激活：

1. **Shell 命令执行审批** - 当 Agent 需要执行 shell 命令时
2. **Exec 命令执行审批** - 当需要执行外部程序时
3. **Apply Patch 审批** - 当需要应用代码补丁修改文件时
4. **网络访问审批** - 当需要访问外部网络资源时
5. **MCP 工具调用审批** - 当需要调用 MCP（Model Context Protocol）工具时
6. **Unix Execve 审批** - Unix 系统下的程序执行

### 主要职责

| 职责 | 说明 |
|------|------|
| 风险评估 | 评估操作的风险等级（low/medium/high）和风险分数（0-100）|
| 自动决策 | 根据风险阈值（默认80）自动批准或拒绝操作|
| 上下文感知 | 分析会话历史、用户意图和工具调用来做出决策|
| 安全隔离 | 在只读沙箱中运行评估子代理，防止副作用|
| 故障安全 | 任何超时、执行失败或解析失败都视为高风险拒绝|

---

## 功能点目的

### 1. 自动审批替代人工审批

传统模式下，敏感操作需要用户手动确认。Guardian 允许配置为自动审批模式：

```rust
// 启用 Guardian 的条件
pub(crate) fn routes_approval_to_guardian(turn: &TurnContext) -> bool {
    turn.approval_policy.value() == AskForApproval::OnRequest
        && turn.config.approvals_reviewer == ApprovalsReviewer::GuardianSubagent
}
```

### 2. 风险分级评估

Guardian 输出结构化风险评估：
- **risk_level**: low / medium / high
- **risk_score**: 0-100 的数值评分
- **rationale**: 评估理由说明
- **evidence**: 支持证据列表

### 3. 会话复用与缓存

为了性能优化，Guardian 实现了会话复用机制：
- **Trunk Session**: 主会话，空闲时复用以保持 prompt cache
- **Ephemeral Fork**: 当 trunk 忙时，从上次提交的历史创建临时会话

### 4. 提示词压缩与截断

处理长历史记录时的智能压缩：
- 保留所有用户消息（授权和意图）
- 限制非用户条目数量（默认40条）
- 单独的工具证据预算（防止工具输出挤占对话空间）

---

## 具体技术实现

### 模块结构

```
codex-rs/core/src/guardian/
├── mod.rs              # 模块入口，常量定义，公共导出
├── approval_request.rs # 审批请求数据结构定义
├── prompt.rs           # 提示词构建与处理
├── review.rs           # 核心审查逻辑
├── review_session.rs   # 审查会话管理
├── tests.rs            # 单元测试和集成测试
└── policy.md           # Guardian 策略提示词（markdown）
```

### 关键数据结构

#### GuardianApprovalRequest（审批请求类型）

```rust
pub(crate) enum GuardianApprovalRequest {
    Shell { id, command, cwd, sandbox_permissions, additional_permissions, justification },
    ExecCommand { id, command, cwd, sandbox_permissions, additional_permissions, justification, tty },
    #[cfg(unix)]
    Execve { id, tool_name, program, argv, cwd, additional_permissions },
    ApplyPatch { id, cwd, files, change_count, patch },
    NetworkAccess { id, turn_id, target, host, protocol, port },
    McpToolCall { id, server, tool_name, arguments, connector_id, ... },
}
```

#### GuardianAssessment（评估结果）

```rust
pub(crate) struct GuardianAssessment {
    pub(crate) risk_level: GuardianRiskLevel,  // low/medium/high
    pub(crate) risk_score: u8,                 // 0-100
    pub(crate) rationale: String,              // 评估理由
    pub(crate) evidence: Vec<GuardianEvidence>, // 证据列表
}
```

#### GuardianTranscriptEntry（历史记录条目）

```rust
pub(crate) struct GuardianTranscriptEntry {
    pub(crate) kind: GuardianTranscriptEntryKind,  // User/Assistant/Tool
    pub(crate) text: String,
}

pub(crate) enum GuardianTranscriptEntryKind {
    User,
    Assistant,
    Tool(String),  // 工具名称
}
```

### 核心流程

#### 1. 审批路由流程

```
工具调用请求
    │
    ▼
┌─────────────────────┐
│ routes_approval_to_guardian │
│ 检查 approval_policy 和 approvals_reviewer │
└─────────────────────┘
    │
    ├─ 条件满足 ──▶ Guardian 自动审批
    │
    └─ 条件不满足 ─▶ 用户手动审批
```

#### 2. Guardian 审查流程

```
review_approval_request()
    │
    ▼
run_guardian_review()
    │
    ├─▶ 发送 GuardianAssessmentEvent(InProgress)
    │
    ├─▶ build_guardian_prompt_items() 构建提示词
    │       ├─ 收集历史记录 (collect_guardian_transcript_entries)
    │       ├─ 渲染压缩后的记录 (render_guardian_transcript_entries)
    │       └─ 构建 UserInput 列表
    │
    ├─▶ run_guardian_review_session() 运行审查会话
    │       ├─ 选择模型（优先 gpt-5.4）
    │       ├─ 构建 Guardian 配置（只读沙箱，approval_policy=never）
    │       ├─ 获取或创建审查会话（trunk/ephemeral）
    │       ├─ 提交 Op::UserTurn 到子代理
    │       └─ 等待 TurnComplete 事件
    │
    ├─▶ parse_guardian_assessment() 解析评估结果
    │
    ├─▶ 风险阈值判断 (risk_score < 80)
    │       ├─ 通过 ──▶ ReviewDecision::Approved
    │       └─ 拒绝 ──▶ ReviewDecision::Denied + GUARDIAN_REJECTION_MESSAGE
    │
    └─▶ 发送 GuardianAssessmentEvent(Approved/Denied/Aborted)
```

#### 3. 会话管理流程

```
GuardianReviewSessionManager::run_review()
    │
    ├─▶ 计算 reuse_key（基于配置）
    │
    ├─▶ 检查现有 trunk 会话
    │       ├─ reuse_key 匹配且空闲 ──▶ 复用 trunk
    │       ├─ reuse_key 匹配但忙 ────▶ 创建 ephemeral fork
    │       └─ reuse_key 不匹配 ──────▶ 关闭旧 trunk，创建新 trunk
    │
    ├─▶ 执行审查
    │
    └─▶ 根据结果决定是否保留会话
```

### 关键常量

```rust
const GUARDIAN_PREFERRED_MODEL: &str = "gpt-5.4";           // 首选模型
const GUARDIAN_REVIEW_TIMEOUT: Duration = Duration::from_secs(90);  // 超时时间
const GUARDIAN_REVIEWER_NAME: &str = "guardian";             // 子代理名称
const GUARDIAN_MAX_MESSAGE_TRANSCRIPT_TOKENS: usize = 10_000; // 消息历史token上限
const GUARDIAN_MAX_TOOL_TRANSCRIPT_TOKENS: usize = 10_000;   // 工具历史token上限
const GUARDIAN_MAX_MESSAGE_ENTRY_TOKENS: usize = 2_000;      // 单条消息token上限
const GUARDIAN_MAX_TOOL_ENTRY_TOKENS: usize = 1_000;         // 单条工具token上限
const GUARDIAN_MAX_ACTION_STRING_TOKENS: usize = 1_000;      // 动作字符串token上限
const GUARDIAN_APPROVAL_RISK_THRESHOLD: u8 = 80;             // 风险阈值
const GUARDIAN_RECENT_ENTRY_LIMIT: usize = 40;               // 非用户条目数量限制
```

### 提示词构建

#### 历史记录处理策略

1. **收集阶段** (`collect_guardian_transcript_entries`):
   - 遍历 `ResponseItem` 历史
   - 跳过上下文用户消息（环境信息等）
   - 保留：用户消息、助手消息、工具调用和结果
   - 使用 `call_id` 关联工具调用和结果

2. **渲染阶段** (`render_guardian_transcript_entries`):
   - 始终保留所有用户消息
   - 从最新到最旧遍历非用户条目
   - 检查消息和工具的独立预算
   - 生成 `[index] role: content` 格式

3. **截断处理** (`guardian_truncate_text`):
   - 超过 token 限制时保留前缀和后缀
   - 中间插入 `<truncated omitted_approx_tokens="N" />`
   - 确保字符边界安全（UTF-8）

#### 提示词结构

```
The following is the Codex agent history whose request action you are assessing...

>>> TRANSCRIPT START
[1] user: ...
[2] assistant: ...
[3] tool xxx call: ...
...
>>> TRANSCRIPT END

The Codex agent has requested the following action:

>>> APPROVAL REQUEST START
Retry reason: ...
Assess the exact planned action below...
Planned action JSON: {...}
>>> APPROVAL REQUEST END

You may use read-only tool checks...
Your final message must be strict JSON with this exact schema:
{ "risk_level": "low" | "medium" | "high", ... }
```

### 输出解析

```rust
pub(crate) fn parse_guardian_assessment(text: Option<&str>) -> anyhow::Result<GuardianAssessment> {
    // 1. 尝试直接解析 JSON
    if let Ok(assessment) = serde_json::from_str::<GuardianAssessment>(text) {
        return Ok(assessment);
    }
    // 2. 尝试从文本中提取 JSON 子串（处理模型包裹在额外文本中的情况）
    if let (Some(start), Some(end)) = (text.find('{'), text.rfind('}'))
        && start < end
        && let Some(slice) = text.get(start..=end)
    {
        return Ok(serde_json::from_str::<GuardianAssessment>(slice)?);
    }
    // 3. 解析失败
    anyhow::bail!("guardian assessment was not valid JSON")
}
```

### Guardian 会话配置

```rust
pub(crate) fn build_guardian_review_session_config(
    parent_config: &Config,
    live_network_config: Option<NetworkProxyConfig>,
    active_model: &str,
    reasoning_effort: Option<ReasoningEffort>,
) -> anyhow::Result<Config> {
    let mut guardian_config = parent_config.clone();
    
    // 使用指定模型
    guardian_config.model = Some(active_model.to_string());
    guardian_config.model_reasoning_effort = reasoning_effort;
    
    // 设置开发者指令（策略提示词）
    guardian_config.developer_instructions = Some(
        parent_config.guardian_developer_instructions.clone()
            .unwrap_or_else(guardian_policy_prompt)
    );
    
    // 锁定为永不审批（防止递归）
    guardian_config.permissions.approval_policy = Constrained::allow_only(AskForApproval::Never);
    
    // 锁定为只读沙箱
    guardian_config.permissions.sandbox_policy = 
        Constrained::allow_only(SandboxPolicy::new_read_only_policy());
    
    // 继承网络代理配置（用于只读检查）
    if let Some(live_network_config) = live_network_config {
        guardian_config.permissions.network = Some(NetworkProxySpec::from_config_and_constraints(...));
    }
    
    // 禁用特定功能（防止副作用）
    for feature in [SpawnCsv, Collab, WebSearchRequest, WebSearchCached] {
        guardian_config.features.disable(feature)?;
    }
    
    Ok(guardian_config)
}
```

---

## 关键代码路径与文件引用

### 入口点

| 函数 | 文件 | 说明 |
|------|------|------|
| `routes_approval_to_guardian` | `review.rs:58` | 判断是否路由到 Guardian |
| `review_approval_request` | `review.rs:213` | 公共入口（无取消token）|
| `review_approval_request_with_cancel` | `review.rs:229` | 公共入口（支持取消）|

### 核心实现

| 函数/结构 | 文件 | 说明 |
|-----------|------|------|
| `run_guardian_review` | `review.rs:75` | 核心审查逻辑 |
| `run_guardian_review_session` | `review.rs:260` | 运行审查会话 |
| `GuardianReviewSessionManager` | `review_session.rs:65` | 会话管理器 |
| `GuardianReviewSessionManager::run_review` | `review_session.rs:236` | 运行审查（含复用逻辑）|
| `build_guardian_prompt_items` | `prompt.rs:64` | 构建提示词 |
| `collect_guardian_transcript_entries` | `prompt.rs:208` | 收集历史记录 |
| `render_guardian_transcript_entries` | `prompt.rs:120` | 渲染压缩历史 |
| `parse_guardian_assessment` | `prompt.rs:360` | 解析评估结果 |

### 数据结构定义

| 结构/枚举 | 文件 | 说明 |
|-----------|------|------|
| `GuardianApprovalRequest` | `approval_request.rs:13` | 审批请求枚举 |
| `GuardianAssessment` | `mod.rs:55` | 评估结果结构 |
| `GuardianEvidence` | `mod.rs:47` | 证据项结构 |
| `GuardianTranscriptEntry` | `prompt.rs:26` | 历史条目结构 |
| `GuardianReviewSessionParams` | `review_session.rs:51` | 会话参数 |
| `GuardianReviewSessionReuseKey` | `review_session.rs:89` | 复用键 |

### 策略提示词

| 文件 | 说明 |
|------|------|
| `policy.md` | Guardian 策略提示词（markdown，可被覆盖）|
| `guardian_policy_prompt()` | `prompt.rs:437` | 加载策略提示词的函数 |
| `guardian_output_schema()` | `prompt.rs:381` | JSON Schema 定义 |

### 测试

| 测试 | 文件 | 说明 |
|------|------|------|
| `guardian_review_request_layout_matches_model_visible_request_snapshot` | `tests.rs:485` | 请求布局快照测试 |
| `guardian_reuses_prompt_cache_key_and_appends_prior_reviews` | `tests.rs:581` | 会话复用测试 |
| `guardian_parallel_reviews_fork_from_last_committed_trunk_history` | `tests.rs:710` | 并行审查 fork 测试 |
| `cancelled_guardian_review_emits_terminal_abort_without_warning` | `tests.rs:374` | 取消处理测试 |

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::codex` | Session, TurnContext, Codex 主结构 |
| `crate::codex_delegate` | `run_codex_thread_interactive` 创建子代理 |
| `crate::config` | Config, Permissions, SandboxPolicy 等配置 |
| `crate::sandboxing` | SandboxPermissions, SandboxPolicy |
| `crate::truncate` | Token 计数和截断工具 |
| `crate::compact` | content_items_to_text |
| `crate::event_mapping` | is_contextual_user_message_content |
| `crate::rollout::recorder` | RolloutRecorder 历史加载 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | 协议类型：ResponseItem, UserInput, EventMsg, GuardianRiskLevel 等 |
| `codex_network_proxy` | NetworkProxyConfig 网络代理配置 |
| `codex_utils_absolute_path` | AbsolutePathBuf |
| `serde_json` | JSON 序列化/反序列化 |
| `tokio_util::sync::CancellationToken` | 取消信号 |
| `tokio::sync::Mutex` | 异步锁 |

### 调用方

| 调用模块 | 文件 | 调用点 |
|----------|------|--------|
| 工具编排器 | `tools/orchestrator.rs` | 执行审批路由 |
| Shell 运行时 | `tools/runtimes/shell.rs` | Shell 命令审批 |
| Unix 提权 | `tools/runtimes/shell/unix_escalation.rs` | Execve 审批 |
| Apply Patch | `tools/runtimes/apply_patch.rs` | 补丁应用审批 |
| 统一执行 | `tools/runtimes/unified_exec.rs` | Exec 命令审批 |
| 网络审批 | `tools/network_approval.rs` | 网络访问审批 |
| MCP 工具调用 | `mcp_tool_call.rs` | MCP 工具审批 |
| Codex 委托 | `codex_delegate.rs` | 审批委托处理 |

---

## 风险、边界与改进建议

### 当前风险

1. **模型依赖风险**
   - Guardian 依赖 AI 模型（gpt-5.4 或 fallback）的风险评估能力
   - 模型可能被提示词注入攻击欺骗
   - 策略提示词 `policy.md` 中明确警告要忽略试图重新定义政策的内容

2. **超时处理**
   - 90秒超时后视为高风险拒绝
   - 网络延迟或模型响应慢可能导致误拒绝

3. **Token 预算限制**
   - 长历史记录会被截断，可能丢失关键上下文
   - 工具输出过大时可能无法完整评估

4. **递归风险**
   - Guardian 子代理本身被配置为 `approval_policy = Never`，防止递归调用
   - 但配置错误可能导致无限递归

### 边界情况

1. **并行审查**
   - 当多个审批同时到达时，会创建 ephemeral fork
   - Fork 从上次 committed trunk 历史创建，可能不包含正在进行的审查

2. **配置变更**
   - 配置变更会导致 reuse_key 变化，触发 trunk 重建
   - 网络代理配置可以动态更新（使用 live_network_config）

3. **取消处理**
   - 支持外部取消信号（CancellationToken）
   - 取消后发送 Aborted 事件，不产生警告

4. **解析容错**
   - 评估结果解析支持从文本中提取 JSON 子串
   - 但非 JSON 输出仍会导致审查失败

### 改进建议

1. **可观测性增强**
   - 添加更多 tracing span 和指标
   - 记录 Guardian 决策的详细理由到日志

2. **策略动态更新**
   - 当前策略通过 `policy.md` 或配置覆盖
   - 可考虑支持运行时策略热更新

3. **模型选择优化**
   - 当前优先使用 gpt-5.4，fallback 到父会话模型
   - 可考虑根据任务类型选择不同模型

4. **缓存策略优化**
   - 当前 trunk 会话在配置变化时重建
   - 可考虑更细粒度的缓存策略

5. **评估质量反馈**
   - 当前无反馈机制改进 Guardian 评估
   - 可考虑收集用户反馈来优化策略

6. **测试覆盖**
   - 增加更多边界情况测试（如超长历史、特殊字符等）
   - 增加性能测试（大历史记录的渲染性能）

---

## 相关文件速查

```
codex-rs/core/src/guardian/
├── mod.rs                    # 模块入口
├── approval_request.rs       # 请求类型定义
├── prompt.rs                 # 提示词构建
├── review.rs                 # 核心审查逻辑
├── review_session.rs         # 会话管理
├── tests.rs                  # 测试
└── policy.md                 # 策略提示词

codex-rs/core/src/
├── codex.rs                  # Session.guardian_review_session 定义
├── codex_delegate.rs         # 审批委托处理
├── tools/orchestrator.rs     # 工具审批路由
├── tools/runtimes/shell.rs   # Shell 审批
├── tools/runtimes/apply_patch.rs  # Patch 审批
├── tools/runtimes/unified_exec.rs # Exec 审批
├── tools/network_approval.rs # 网络审批
└── mcp_tool_call.rs          # MCP 审批
```

---

*研究完成时间: 2026-03-21*
*研究范围: codex-rs/core/src/guardian 目录及其依赖*
