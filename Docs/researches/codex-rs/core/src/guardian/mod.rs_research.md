# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Guardian 子代理系统的模块入口和公共接口定义文件。它负责：
1. 声明 Guardian 子模块（approval_request, prompt, review, review_session）
2. 定义 Guardian 审查的核心常量和配置
3. 定义 Guardian 评估结果的数据结构（GuardianEvidence, GuardianAssessment）
4. 提供公共 API 的重新导出（re-export）
5. 管理测试模块的导入

**Guardian 系统整体定位：**
Guardian 是一个专门的子代理（sub-agent），用于自动评估 Codex 主代理发起的需要用户批准的操作（如 shell 命令、文件修改、网络访问等）。当配置为 `approvals_reviewer = GuardianSubagent` 且 `approval_policy = OnRequest` 时，Guardian 会代替用户进行自动风险评估。

## 功能点目的

### 1. 模块声明与组织

```rust
mod approval_request;  // 批准请求数据类型定义
mod prompt;            // 提示词构建和解析
mod review;            // 核心审查逻辑
mod review_session;    // 审查会话管理
```

采用扁平模块结构，各模块职责清晰分离。

### 2. 核心常量定义

| 常量 | 值 | 用途 |
|------|-----|------|
| `GUARDIAN_PREFERRED_MODEL` | `"gpt-5.4"` | Guardian 首选模型 |
| `GUARDIAN_REVIEW_TIMEOUT` | `90s` | 审查超时时间 |
| `GUARDIAN_REVIEWER_NAME` | `"guardian"` | 审查者标识 |
| `GUARDIAN_MAX_MESSAGE_TRANSCRIPT_TOKENS` | `10_000` | 消息转录最大 tokens |
| `GUARDIAN_MAX_TOOL_TRANSCRIPT_TOKENS` | `10_000` | 工具转录最大 tokens |
| `GUARDIAN_MAX_MESSAGE_ENTRY_TOKENS` | `2_000` | 单条消息最大 tokens |
| `GUARDIAN_MAX_TOOL_ENTRY_TOKENS` | `1_000` | 单条工具记录最大 tokens |
| `GUARDIAN_MAX_ACTION_STRING_TOKENS` | `1_000` | 动作字符串最大 tokens |
| `GUARDIAN_APPROVAL_RISK_THRESHOLD` | `80` | 风险分数阈值（≥80 拒绝）|
| `GUARDIAN_RECENT_ENTRY_LIMIT` | `40` | 保留的最近条目数 |
| `TRUNCATION_TAG` | `"truncated"` | 截断标记 |

### 3. 核心数据结构

**GuardianEvidence**：
```rust
pub(crate) struct GuardianEvidence {
    pub(crate) message: String,  // 证据描述
    pub(crate) why: String,      // 证据理由
}
```

**GuardianAssessment**：
```rust
pub(crate) struct GuardianAssessment {
    pub(crate) risk_level: GuardianRiskLevel,  // low/medium/high
    pub(crate) risk_score: u8,                 // 0-100
    pub(crate) rationale: String,              // 评估理由
    pub(crate) evidence: Vec<GuardianEvidence>, // 证据列表
}
```

这是 Guardian 子代理返回的严格 JSON 结构，通过 `guardian_output_schema()` 强制约束。

### 4. 公共 API 重新导出

```rust
pub(crate) use approval_request::GuardianApprovalRequest;
pub(crate) use approval_request::GuardianMcpAnnotations;
pub(crate) use approval_request::guardian_approval_request_to_json;
pub(crate) use review::GUARDIAN_REJECTION_MESSAGE;
pub(crate) use review::is_guardian_reviewer_source;
pub(crate) use review::review_approval_request;
pub(crate) use review::review_approval_request_with_cancel;
pub(crate) use review::routes_approval_to_guardian;
pub(crate) use review_session::GuardianReviewSessionManager;
```

### 5. 测试模块导入

使用 `#[cfg(test)]` 条件编译，仅在测试时导入内部实现细节，支持白盒测试：

```rust
#[cfg(test)]
use approval_request::format_guardian_action_pretty;
#[cfg(test)]
use prompt::GuardianTranscriptEntry;
// ... 更多测试导入
```

## 具体技术实现

### 模块初始化流程

```
codex::Session 创建
└── guardian_review_session: GuardianReviewSessionManager::default()
    └── state: Arc<Mutex<GuardianReviewSessionState>>
        ├── trunk: None  // 延迟初始化
        └── ephemeral_reviews: Vec::new()
```

### 常量设计原理

1. **Token 预算分层**：
   - 总预算：`MESSAGE (10k) + TOOL (10k) = 20k`
   - 单条限制：消息 2k，工具 1k
   - 动作字符串：1k
   - 这种分层确保工具输出不会挤占用户消息的空间

2. **风险阈值 80**：
   - 0-79：低风险/中风险，自动批准
   - 80-100：高风险，拒绝
   - 这个阈值是经验值，平衡了安全性和可用性

3. **90秒超时**：
   - 足够 Guardian 完成一次完整的推理
   - 不会让用户等待过久
   - 超时自动视为高风险（拒绝）

## 关键代码路径与文件引用

### 模块依赖图

```
mod.rs
├── approval_request.rs  (数据定义)
├── prompt.rs            (提示词构建)
│   └── 依赖: approval_request
├── review.rs            (审查逻辑)
│   ├── 依赖: approval_request, prompt, review_session
│   └── 被依赖: mod.rs (re-export)
├── review_session.rs    (会话管理)
│   └── 被依赖: review.rs
└── tests.rs             (测试)
    └── 依赖: 所有上述模块
```

### 外部调用入口

| 调用方 | 调用函数 | 场景 |
|--------|----------|------|
| `tools/runtimes/shell.rs` | `review_approval_request` | Shell 命令审查 |
| `tools/runtimes/apply_patch.rs` | `review_approval_request` | 补丁应用审查 |
| `tools/network_approval.rs` | `review_approval_request` | 网络访问审查 |
| `mcp_tool_call.rs` | `review_approval_request` | MCP 工具审查 |
| `codex.rs` | `GuardianReviewSessionManager` | Session 创建 |

### 配置关联

在 `config/mod.rs` 中：
```rust
pub(crate) fn approvals_reviewer(&self) -> ApprovalsReviewer {
    // 返回 User 或 GuardianSubagent
}
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `serde` | GuardianEvidence/GuardianAssessment 序列化 |
| `std::time::Duration` | 超时定义 |

### 内部模块依赖

| 模块 | 依赖内容 |
|------|----------|
| `approval_request` | GuardianApprovalRequest, GuardianMcpAnnotations |
| `prompt` | 测试时导入内部函数 |
| `review` | 核心 API 函数 |
| `review_session` | GuardianReviewSessionManager |

### 协议类型依赖

在 `codex_protocol` 中定义：
- `GuardianRiskLevel`：low/medium/high 枚举
- `GuardianAssessmentEvent`：评估事件
- `GuardianAssessmentStatus`：InProgress/Approved/Denied/Aborted

## 风险、边界与改进建议

### 已知风险

1. **常量硬编码**：
   - 所有 token 限制和阈值都是编译时常量，无法运行时调整
   - 不同模型可能需要不同的预算分配

2. **模型偏好硬编码**：
   - `GUARDIAN_PREFERRED_MODEL = "gpt-5.4"` 是硬编码字符串
   - 如果模型名称变更或下线，需要重新编译

3. **测试导入膨胀**：
   - 测试模块导入了大量内部实现细节
   - 可能导致测试与实现过度耦合

### 边界情况

1. **Token 预算竞争**：
   - 当用户消息和工具输出同时接近上限时，可能都得不到完整保留
   - 当前策略优先保留用户消息

2. **风险分数边界**：
   - 正好 80 分的操作会被拒绝
   - 这种硬边界可能导致"差 1 分"的困惑

### 改进建议

1. **配置化常量**：
   ```rust
   // 建议改为从 Config 读取
   pub(crate) fn max_message_tokens(config: &Config) -> usize {
       config.guardian_max_message_tokens.unwrap_or(10_000)
   }
   ```

2. **模型选择策略**：
   - 支持按能力选择模型（如优先选择支持 reasoning 的模型）
   - 添加模型可用性检查，自动降级

3. **风险分数模糊化**：
   - 考虑添加缓冲区间（如 75-85 为"需要复核"）
   - 或改为三级决策：批准/拒绝/人工复核

4. **模块组织优化**：
   - 考虑将常量提取到单独的 `constants.rs`
   - 将数据结构提取到 `types.rs`

5. **文档增强**：
   - 添加更多关于预算分配策略的注释
   - 解释为什么采用特定的阈值

6. **可观测性**：
   - 添加常量值的启动日志输出
   - 记录实际的 token 使用情况用于调优
