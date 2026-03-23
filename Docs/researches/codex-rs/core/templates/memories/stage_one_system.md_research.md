# stage_one_system.md 深度研究文档

## 文件基本信息

| 属性 | 值 |
|------|-----|
| 文件路径 | `codex-rs/core/templates/memories/stage_one_system.md` |
| 文件大小 | 569 行 |
| 文件类型 | 静态 Markdown（非 Askama 模板） |
| 所属模块 | `codex-core` memories 子系统 |

---

## 一、场景与职责

### 1.1 核心定位

`stage_one_system.md` 是 **Memory Writing Agent Phase 1** 的**系统提示模板**，提供完整的指令集指导模型如何从单个 rollout 中提取结构化记忆。它是 Phase 1 流程中**最复杂的提示模板**（569 行）。

### 1.2 运行时机

- 在 Phase 1 作业执行时作为 `BaseInstructions.text` 注入
- 每个 rollout 提取作业使用相同的系统提示
- 由 `phase1.rs` 中的 `job::sample()` 函数构建 `Prompt` 对象

### 1.3 设计目标

1. **结构化提取**：指导模型输出严格的 JSON 格式（`raw_memory`, `rollout_summary`, `rollout_slug`）
2. **质量筛选**：定义高信号记忆的标准，避免保存低价值信息
3. **用户偏好识别**：从用户消息中提取可复用的偏好和约束
4. **失败学习**：记录失败模式和改进建议

---

## 二、功能点目的

### 2.1 全局安全与卫生规则

模板强调以下严格规则：

| 规则 | 说明 |
|------|------|
| Raw rollouts are immutable | 永远不要编辑原始 rollout |
| Evidence-based only | 不要发明事实或声称未发生的验证 |
| Redact secrets | 用 `[REDACTED_SECRET]` 替换密钥/密码 |
| Avoid copying large tool outputs | 优先使用紧凑摘要 + 精确错误片段 |
| No-op is allowed | 如果没有值得保存的内容，返回空字段 |

### 2.2 最小信号门控 (Minimum Signal Gate)

在生成输出前，模型必须问自己：

> "Will a future agent plausibly act better because of what I write here?"

**返回空字段的情况：**
- 一次性的"随机"用户查询
- 没有收获的一般状态更新
- 临时事实（实时指标、短暂输出）
- 显而易见/常识性知识
- 没有新工件、没有可复用步骤、没有真正的复盘

### 2.3 高信号记忆定义

**高价值记忆类别：**

1. **稳定的用户操作偏好**
   - 用户反复要求、纠正或中断执行的内容
   - 用户希望默认拥有的内容

2. **高杠杆程序知识**
   - 来之不易的捷径、失败防护、精确路径/命令
   - 节省大量未来探索时间的仓库事实

3. **可靠的任务地图和决策触发器**
   - 真相所在的位置
   - 如何判断路径错误
   - 什么信号应该导致转向

4. **关于用户环境和工作流程的持久证据**
   - 稳定的工具习惯
   - 仓库约定
   - 展示/验证期望

### 2.4 任务结果分类

模板要求对每个任务进行分类：

| 结果 | 定义 |
|------|------|
| `success` | 任务完成 / 达成正确最终结果 |
| `partial` | 有意义的进展，但不完整 / 未验证 / 仅变通方案 |
| `uncertain` | 没有明确的成功/失败信号 |
| `fail` | 任务未完成、错误结果、卡住循环、工具误用或用户不满意 |

**分类信号优先级：**
1. 明确的用户反馈和验证 > 所有启发式
2. 正面反馈（"works", "this is good", "thanks"）→ 通常 success
3. 负面反馈（"this is wrong", "still broken"）→ fail 或 partial
4. 用户继续下一个任务且无未解决阻塞 → 通常 success
5. 最终任务更保守处理，无明确信号时倾向于 uncertain

---

## 三、具体技术实现

### 3.1 加载方式

与 Askama 模板不同，`stage_one_system.md` 使用 `include_str!` 直接嵌入二进制：

```rust
// memories/mod.rs:39
pub(super) const PROMPT: &str = include_str!("../../templates/memories/stage_one_system.md");
```

### 3.2 Prompt 构建

```rust
// phase1.rs:322-344
let prompt = Prompt {
    input: vec![ResponseItem::Message {
        id: None,
        role: "user".to_string(),
        content: vec![ContentItem::InputText {
            text: build_stage_one_input_message(...)?,
        }],
        end_turn: None,
        phase: None,
    }],
    tools: Vec::new(),
    parallel_tool_calls: false,
    base_instructions: BaseInstructions {
        text: phase_one::PROMPT.to_string(), // <-- stage_one_system.md
    },
    personality: None,
    output_schema: Some(output_schema()), // <-- JSON Schema 约束
};
```

### 3.3 输出 JSON Schema

```rust
// phase1.rs:150-161
pub fn output_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "rollout_summary": { "type": "string" },
            "rollout_slug": { "type": ["string", "null"] },
            "raw_memory": { "type": "string" }
        },
        "required": ["rollout_summary", "rollout_slug", "raw_memory"],
        "additionalProperties": false
    })
}
```

### 3.4 StageOneOutput 结构

```rust
// phase1.rs:67-79
#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct StageOneOutput {
    #[serde(rename = "raw_memory")]
    pub(crate) raw_memory: String,
    #[serde(rename = "rollout_summary")]
    pub(crate) rollout_summary: String,
    #[serde(default, rename = "rollout_slug")]
    pub(crate) rollout_slug: Option<String>,
}
```

---

## 四、关键代码路径与文件引用

### 4.1 调用链

```
编译时:
stage_one_system.md
    ↓ (include_str!)
嵌入到二进制中的 PROMPT 常量 [memories/mod.rs:39]

运行时:
phase1::run() [phase1.rs:86]
    ↓
job::run() [phase1.rs:260]
    ↓
job::sample() [phase1.rs:313]
    ↓
构建 Prompt 对象 [phase1.rs:322]
    ↓
phase_one::PROMPT (stage_one_system.md 内容)
    ↓
发送到模型 (gpt-5.1-codex-mini)
```

### 4.2 关键文件引用

| 文件 | 角色 |
|------|------|
| `codex-rs/core/src/memories/mod.rs` | 定义 `phase_one::PROMPT` 常量 |
| `codex-rs/core/src/memories/phase1.rs` | Phase 1 执行逻辑，构建 Prompt |
| `codex-rs/core/src/memories/prompts.rs` | `build_stage_one_input_message()` |

### 4.3 配置常量

```rust
// phase_one 常量 [memories/mod.rs:33-62]
const MODEL: &str = "gpt-5.1-codex-mini";
const REASONING_EFFORT: ReasoningEffort = ReasoningEffort::Low;
const CONCURRENCY_LIMIT: usize = 8;
const DEFAULT_STAGE_ONE_ROLLOUT_TOKEN_LIMIT: usize = 150_000;
const CONTEXT_WINDOW_PERCENT: i64 = 70;
const JOB_LEASE_SECONDS: i64 = 3_600;
const JOB_RETRY_DELAY_SECONDS: i64 = 3_600;
```

---

## 五、依赖与外部交互

### 5.1 输入依赖

| 输入 | 来源 | 用途 |
|------|------|------|
| 系统提示文本 | 编译时嵌入 | 指导模型行为 |
| rollout 内容 | `stage_one_input.md` 渲染 | 提取记忆的原始材料 |
| 输出 Schema | `output_schema()` | 约束模型输出格式 |

### 5.2 输出消费

| 输出字段 | 用途 | 存储位置 |
|---------|------|---------|
| `raw_memory` | 详细记忆，用于 Phase 2 整合 | `stage1_outputs` 表 |
| `rollout_summary` | 紧凑摘要，用于快速浏览 | `stage1_outputs` 表 + `rollout_summaries/*.md` |
| `rollout_slug` | 文件名标识 | `stage1_outputs` 表 + 文件名生成 |

### 5.3 后处理流程

```
模型输出 (JSON)
    ↓
serde_json::from_str::<StageOneOutput>() [phase1.rs:384]
    ↓
redact_secrets() [phase1.rs:385-387]
    ↓
存储到 state DB (stage1_outputs 表)
    ↓
触发 Phase 2 整合作业
```

---

## 六、模板内容结构详解

### 6.1 文档结构

```
stage_one_system.md (569 lines)
├── Header: Memory Writing Agent: Phase 1 (Single Rollout)
├── GLOBAL SAFETY, HYGIENE, AND NO-FILLER RULES
├── NO-OP / MINIMUM SIGNAL GATE
├── WHAT COUNTS AS HIGH-SIGNAL MEMORY
│   ├── 高价值记忆类别
│   └── 非目标
├── EXAMPLES: USEFUL MEMORIES BY TASK TYPE
│   ├── Coding / debugging agents
│   ├── Browsing/searching agents
│   └── Math/logic solving agents
├── TASK OUTCOME TRIAGE
│   ├── 结果标签定义
│   ├── 真实世界信号示例
│   ├── 信号优先级
│   └── 额外启发式
├── DELIVERABLES
│   └── JSON 输出格式要求
├── rollout_summary FORMAT
│   ├── 任务优先结构
│   └── 模板示例
├── raw_memory FORMAT (STRICT)
│   ├── YAML frontmatter
│   ├── Task 分组结构
│   └── 证据和归因规则
└── WORKFLOW
    └── 执行步骤
```

### 6.2 raw_memory 格式规范

**YAML Frontmatter：**

```yaml
---
description: concise description of task(s), outcome, and takeaway
task: <primary_task_signature>
task_group: <cwd_or_workflow_bucket>
task_outcome: <success|partial|fail|uncertain>
cwd: <primary working directory>
keywords: k1, k2, k3, ...
---
```

**Task 分组体：**

```markdown
### Task 1: <short task name>

task: <task signature>
task_group: <project/workflow topic>
task_outcome: <success|partial|fail|uncertain>

Preference signals:
- when <situation>, the user said / asked / corrected: "<quote>" -> <future default>

Reusable knowledge:
- <validated repo fact, procedural shortcut>

Failures and how to do differently:
- <what failed, what pivot worked>

References:
- <verbatim strings: commands, paths, error strings>
```

### 6.3 rollout_summary 格式规范

**任务优先结构：**

```markdown
# <one-sentence summary>

Rollout context: <context, constraints, environment>

## Task <idx>: <task name>

Outcome: <success|partial|fail|uncertain>

Preference signals:
- <evidence -> implication>

Key steps:
- <step> (optional evidence refs: [1], [2])

Failures and how to do differently:
- <symptom -> cause -> fix>

Reusable knowledge:
- <validated facts>

References:
- [1] command + output snippet
- [2] patch/code snippet
- [3] verification evidence

## Task <idx> (if multiple): ...
```

---

## 七、风险、边界与改进建议

### 7.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **模板过大** | 569 行可能导致 token 消耗过高 | 使用 `gpt-5.1-codex-mini`（低成本）；70% 上下文窗口用于 rollout |
| **输出格式错误** | 模型可能输出不符合 Schema 的 JSON | 使用 `output_schema` 约束；`deny_unknown_fields`；错误处理 |
| **过度提取** | 模型可能保存低价值信息 | 明确的最小信号门控；No-op 允许 |
| **秘密泄露** | 模型可能在输出中包含敏感信息 | `redact_secrets()` 后处理 |
| **指令遵循失败** | 模型可能遵循 rollout 中的指令 | `stage_one_input.md` 中的安全提示 |

### 7.2 边界条件

1. **空 rollout**：过滤后可能产生空内容，模型应返回空字段
2. **超大 rollout**：超过 token 限制的 rollout 会被截断
3. **并发执行**：最多 8 个并行作业
4. **作业租约**：每个作业有 1 小时租约，超时需重新认领
5. **重试限制**：默认 3 次重试，耗尽后标记为失败

### 7.3 改进建议

1. **模板优化**：
   - 将 569 行模板按功能拆分为多个小模板
   - 使用条件编译根据模型能力选择不同模板

2. **输出验证**：
   - 添加 JSON Schema 验证步骤
   - 对 `raw_memory` 进行 Markdown 结构验证

3. **质量评分**：
   - 添加模型置信度评分
   - 低置信度输出进入人工审核队列

4. **增量提取**：
   - 对于恢复的 rollout，只提取新内容
   - 避免重复处理相同内容

5. **多语言支持**：
   - 根据用户偏好提供本地化模板
   - 保持输出格式一致

6. **A/B 测试框架**：
   - 支持同时运行多个提示版本
   - 比较提取质量和覆盖率

---

## 八、与相关模板的关系

```
┌─────────────────────────────────────────────────────────────┐
│                     Phase 1 Extraction                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────────────────┐    ┌─────────────────────┐    │
│   │ stage_one_system.md     │    │ stage_one_input.md  │    │
│   │ (569 lines)             │    │ (11 lines)          │    │
│   │                         │    │                     │    │
│   │ • 详细指令              │◄──►│ • 变量注入          │    │
│   │ • 格式规范              │    │ • 安全提示          │    │
│   │ • 示例                  │    │ • 输入包装          │    │
│   │ • 工作流程              │    │                     │    │
│   └─────────────────────────┘    └─────────────────────┘    │
│              │                            │                  │
│              └────────────┬───────────────┘                  │
│                           ↓                                  │
│                  ┌─────────────────┐                        │
│                  │ 模型 (gpt-5.1   │                        │
│                  │  -codex-mini)   │                        │
│                  └─────────────────┘                        │
│                           │                                  │
│                           ↓                                  │
│                  ┌─────────────────┐                        │
│                  │ JSON Output     │                        │
│                  │ • raw_memory    │                        │
│                  │ • rollout_summary│                       │
│                  │ • rollout_slug  │                        │
│                  └─────────────────┘                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 九、相关文档索引

| 文档 | 描述 |
|------|------|
| `codex-rs/core/templates/memories/stage_one_input.md` | Phase 1 用户输入模板 |
| `codex-rs/core/templates/memories/consolidation.md` | Phase 2 整合提示 |
| `codex-rs/core/templates/memories/read_path.md` | Memory Tool 读取指导 |
| `codex-rs/core/src/memories/README.md` | Memories Pipeline 概述 |
| `codex-rs/core/src/memories/phase1.rs` | Phase 1 实现 |

---

## 十、测试相关

### 10.1 相关测试文件

| 测试文件 | 覆盖内容 |
|---------|---------|
| `codex-rs/core/src/memories/phase1_tests.rs` | Phase 1 单元测试 |
| `codex-rs/core/src/memories/prompts_tests.rs` | 输入构建测试 |
| `codex-rs/core/tests/suite/memories.rs` | 端到端记忆流程测试 |

### 10.2 测试要点

1. **输出解析**：验证模型输出正确解析为 `StageOneOutput`
2. **秘密脱敏**：验证 `redact_secrets()` 正确处理敏感信息
3. **截断逻辑**：验证不同上下文窗口下的截断行为
4. **作业状态机**：验证 claim → process → success/fail 流程
5. **并发安全**：验证多个 Phase 1 作业的正确协调
