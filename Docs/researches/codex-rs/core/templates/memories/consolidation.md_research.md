# consolidation.md 深度研究文档

## 文件基本信息

| 属性 | 值 |
|------|-----|
| 文件路径 | `codex-rs/core/templates/memories/consolidation.md` |
| 文件大小 | 835 行 |
| 文件类型 | Askama 模板 (Markdown) |
| 所属模块 | `codex-core` memories 子系统 |

---

## 一、场景与职责

### 1.1 核心定位

`consolidation.md` 是 **Memory Writing Agent Phase 2 (Consolidation)** 的系统提示模板，负责指导 AI Agent 将 Phase 1 提取的原始记忆（raw memories）整合为结构化的、可检索的长期记忆存储。

### 1.2 运行时机

- 在 Phase 1 完成 rollout 提取后触发
- 由 `phase2.rs` 中的 `run()` 函数调度执行
- 作为子代理（sub-agent）在隔离的沙箱环境中运行

### 1.3 目标产出

该模板指导 Agent 生成以下记忆文件：

| 产出文件 | 用途 |
|---------|------|
| `MEMORY.md` | 可检索的记忆手册，按任务分组组织 |
| `memory_summary.md` | 用户画像和快速索引 |
| `skills/<skill-name>/SKILL.md` | 可复用的技能包（可选） |
| `rollout_summaries/*.md` | 每个 rollout 的摘要文件（由 Phase 1 生成） |

---

## 二、功能点目的

### 2.1 渐进式披露架构

模板设计的核心理念是 **Progressive Disclosure**（渐进式披露）：

```
raw_memories.md (临时输入)
    ↓
MEMORY.md (可检索的中间层)
    ↓
memory_summary.md (快速导航层)
```

### 2.2 两种操作模式

| 模式 | 触发条件 | 行为 |
|------|---------|------|
| **INIT** | 首次运行，缺少 `memory_summary.md` 和 `skills/` | 从零构建所有记忆文件 |
| **INCREMENTAL UPDATE** | 已有记忆文件，新增/删除 thread | 基于 diff 增量更新，支持遗忘机制 |

### 2.3 高信号记忆筛选

模板明确定义了哪些信息值得保存：

**值得保存的信号：**
- 稳定的用户操作偏好（重复请求、纠正、中断模式）
- 高杠杆程序知识（捷径、失败防护、精确路径/命令）
- 可靠的任务地图和决策触发器
- 关于用户环境和工作流程的持久证据

**非目标（不保存）：**
- 通用建议（"be careful", "check docs"）
- 密钥/凭证
- 大型原始输出逐字复制
- 探索性讨论或一次性印象

---

## 三、具体技术实现

### 3.1 模板变量

```rust
#[derive(Template)]
#[template(path = "memories/consolidation.md", escape = "none")]
struct ConsolidationPromptTemplate<'a> {
    memory_root: &'a str,           // 记忆根目录路径
    phase2_input_selection: &'a str, // Phase 1 输入选择 diff
}
```

### 3.2 Phase 2 输入选择渲染

`phase2_input_selection` 由 `prompts.rs` 中的 `render_phase2_input_selection()` 生成：

```rust
fn render_phase2_input_selection(selection: &Phase2InputSelection) -> String {
    // 包含以下信息：
    // - selected inputs this run: N
    // - newly added since last Phase 2: N
    // - retained from last Phase 2: N
    // - removed from last Phase 2: N
    // - 当前选中的 Phase 1 输入列表（带 [added]/[retained] 标记）
    // - 从上次选择中移除的输入列表
}
```

### 3.3 MEMORY.md 格式规范

**必须的结构：**

```markdown
# Task Group: <cwd/project/workflow/detail-task family>

scope: <what this block covers, when to use it>
applies_to: cwd=<primary working directory>; reuse_rule=<when safe to reuse>

## Task 1: <task description, outcome>

### rollout_summary_files
- <rollout_summaries/file1.md> (cwd=<path>, rollout_path=<path>, updated_at=<timestamp>, thread_id=<thread_id>)

### keywords
- <keyword1>, <keyword2>, <keyword3>, ...

## Task 2: ...

## User preferences
- when <situation>, the user asked / corrected: "<quote>" -> <operating-style guidance> [Task 1]

## Reusable knowledge
- <validated repo/system facts, reusable procedures> [Task 1]

## Failures and how to do differently
- <symptom -> cause -> fix> [Task 1]
```

### 3.4 memory_summary.md 格式规范

**必须包含的章节：**

```markdown
## User Profile
<concise user snapshot, <= 500 words>

## User preferences
<actionable bullet list of user preferences>

## General Tips
<durable, actionable guidance>

## What's in Memory
### <cwd/project scope>
#### <most recent memory day: YYYY-MM-DD>
- <topic>: <keyword1>, <keyword2>, ...
  - desc: <clear description>
  - learnings: <recent takeaways>

### Older Memory Topics
...
```

### 3.5 Skills 格式规范

**SKILL.md 结构：**

```markdown
---
name: <skill-name>
description: 1-2 lines with concrete triggers
argument-hint: "[branch]" (optional)
disable-model-invocation: true (for side-effect workflows)
user-invocable: false (for background-only skills)
allowed-tools: [Read, Grep, Glob, Bash] (optional)
---

## When to use
- triggers + non-goals

## Inputs / context to gather
- what to check first

## Procedure
1. step-by-step
2. include commands/paths

## Efficiency plan
- how to reduce tool calls/tokens

## Pitfalls and fixes
- symptom -> likely cause -> fix

## Verification checklist
- concrete success checks
```

---

## 四、关键代码路径与文件引用

### 4.1 调用链

```
start_memories_startup_task() [memories/mod.rs:25]
    ↓
phase1::run() [memories/phase1.rs:86]
    ↓ (after phase1 completes)
phase2::run() [memories/phase2.rs:43]
    ↓
agent::get_prompt() [memories/phase2.rs:312]
    ↓
prompts::build_consolidation_prompt() [memories/prompts.rs:38]
    ↓
ConsolidationPromptTemplate.render() [memories/prompts.rs:16]
    ↓ (renders)
consolidation.md (this file)
```

### 4.2 关键文件引用

| 文件 | 角色 |
|------|------|
| `codex-rs/core/src/memories/mod.rs` | 模块入口，定义 Phase 2 常量 |
| `codex-rs/core/src/memories/phase2.rs` | Phase 2 执行逻辑，调用模板渲染 |
| `codex-rs/core/src/memories/prompts.rs` | 模板定义和渲染函数 |
| `codex-rs/core/src/memories/storage.rs` | 文件系统同步逻辑 |
| `codex-rs/state/src/model/memories.rs` | 数据结构定义 (`Stage1Output`, `Phase2InputSelection`) |
| `codex-rs/state/src/runtime/memories.rs` | 数据库操作和 Phase 2 作业管理 |

### 4.3 配置常量

```rust
// phase_two 常量 [memories/mod.rs:64-77]
const MODEL: &str = "gpt-5.3-codex";
const REASONING_EFFORT: ReasoningEffort = ReasoningEffort::Medium;
const JOB_LEASE_SECONDS: i64 = 3_600;
const JOB_RETRY_DELAY_SECONDS: i64 = 3_600;
const JOB_HEARTBEAT_SECONDS: u64 = 90;
```

---

## 五、依赖与外部交互

### 5.1 输入依赖

| 输入 | 来源 | 用途 |
|------|------|------|
| `raw_memories.md` | Phase 1 输出 | 原始记忆输入 |
| `MEMORY.md` | 现有文件（增量模式） | 读取现有记忆进行更新 |
| `rollout_summaries/*.md` | Phase 1 输出 | 详细 rollout 信息 |
| `memory_summary.md` | 现有文件（增量模式） | 读取现有摘要 |
| `skills/*` | 现有技能目录 | 读取现有技能 |

### 5.2 输出产物

| 输出 | 位置 | 消费者 |
|------|------|--------|
| `MEMORY.md` | `{{ memory_root }}/` | Memory Tool (read_path.md) |
| `memory_summary.md` | `{{ memory_root }}/` | Memory Tool (read_path.md) |
| `skills/<name>/SKILL.md` | `{{ memory_root }}/skills/` | 用户/Agent |
| `raw_memories.md` | `{{ memory_root }}/` | Phase 2 Agent 输入 |

### 5.3 沙箱配置

Phase 2 Agent 在严格限制的沙箱中运行 [phase2.rs:277-298]：

```rust
// Approval policy: Never
agent_config.permissions.approval_policy = Constrained::allow_only(AskForApproval::Never);

// Disabled features
agent_config.features.disable(Feature::SpawnCsv);
agent_config.features.disable(Feature::Collab);
agent_config.features.disable(Feature::MemoryTool);

// Sandbox: WorkspaceWrite with only codex_home writable
SandboxPolicy::WorkspaceWrite {
    writable_roots: vec![codex_home],
    read_only_access: Default::default(),
    network_access: false,
    exclude_tmpdir_env_var: false,
    exclude_slash_tmp: false,
}
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **模板膨胀** | 835 行的大型模板可能导致 token 消耗过高 | 使用 `gpt-5.3-codex` 模型，控制输入大小 |
| **增量更新复杂性** | 增量模式的 diff 逻辑复杂，容易出错 | 通过 `Phase2InputSelection` 精确跟踪 added/retained/removed |
| **并发安全** | Phase 2 是全局单点，需要作业锁 | 使用 `try_claim_global_phase2_job` 和心跳机制 |
| **数据丢失** | 错误的遗忘逻辑可能删除有价值的记忆 | `removed` 列表在文件系统中保留直到 consolidation 完成 |

### 6.2 边界条件

1. **空输入处理**：当 `raw_memories` 为空时，Phase 2 直接标记成功并退出 [phase2.rs:115-127]
2. **最大记忆限制**：`max_raw_memories_for_consolidation` 默认 256，超出部分被截断
3. **最大未使用天数**：`max_unused_days` 默认 30 天，超期记忆被清理
4. **心跳超时**：90 秒心跳间隔，丢失心跳会导致作业失败

### 6.3 改进建议

1. **模板分片**：将 835 行的 `consolidation.md` 按功能拆分为多个小模板：
   - `consolidation_init.md` - INIT 模式专用
   - `consolidation_incremental.md` - 增量更新专用
   - `consolidation_formats.md` - 格式规范参考

2. **验证增强**：在模板中添加更多输出格式验证指令，确保 MEMORY.md 和 memory_summary.md 符合严格模式

3. **技能模板化**：将常见的技能模式提取为可复用模板，减少重复编写

4. **监控增强**：
   - 添加模板渲染时间指标
   - 跟踪 Phase 2 Agent 的 tool 调用模式
   - 监控输出文件大小和结构合规性

5. **测试覆盖**：
   - 添加针对模板渲染输出的单元测试
   - 验证 MEMORY.md 和 memory_summary.md 的结构合规性
   - 测试增量更新时的边缘情况（如 mixed block 处理）

---

## 七、相关文档索引

| 文档 | 描述 |
|------|------|
| `codex-rs/core/src/memories/README.md` | Memories Pipeline 概述 |
| `codex-rs/core/templates/memories/stage_one_system.md` | Phase 1 系统提示 |
| `codex-rs/core/templates/memories/stage_one_input.md` | Phase 1 输入模板 |
| `codex-rs/core/templates/memories/read_path.md` | Memory Tool 开发者指令 |
| `codex-rs/core/tests/suite/memories.rs` | 集成测试 |

---

## 八、模板内容结构速览

```
consolidation.md (835 lines)
├── Header: Memory Writing Agent: Phase 2 (Consolidation)
├── CONTEXT: MEMORY FOLDER STRUCTURE
├── GLOBAL SAFETY, HYGIENE, AND NO-FILLER RULES
├── WHAT COUNTS AS HIGH-SIGNAL MEMORY
├── EXAMPLES: USEFUL MEMORIES BY TASK TYPE
├── PHASE 2: CONSOLIDATION — YOUR TASK
│   ├── Mode selection (INIT vs INCREMENTAL)
│   ├── Incremental diff snapshot
│   └── Forgetting mechanism
├── 1. MEMORY.md FORMAT (STRICT)
│   ├── Block structure
│   ├── Schema rules
│   └── What to write
├── 2. memory_summary.md FORMAT (STRICT)
│   ├── User Profile
│   ├── User preferences
│   ├── General Tips
│   └── What's in Memory
├── 3. skills/ FORMAT (optional)
│   ├── SKILL.md frontmatter
│   └── Supporting files
└── WORKFLOW
    ├── INIT phase behavior
    ├── INCREMENTAL UPDATE behavior
    ├── Evidence deep-dive rule
    └── Final pass checklist
```
