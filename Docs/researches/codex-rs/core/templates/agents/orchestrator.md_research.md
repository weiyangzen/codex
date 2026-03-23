# orchestrator.md 研究文档

## 场景与职责

### 核心定位

`codex-rs/core/templates/agents/orchestrator.md` 是 Codex CLI 项目中定义**主 Agent（Orchestrator Agent）**系统提示词（System Prompt）的核心模板文件。该文件定义了 GPT-5 基础模型的身份、性格、沟通风格、工具使用规范和子 Agent 编排规则。

**关键职责**：
1. **身份定义**：确立 Codex 作为协作型、高能力的结对编程 AI 助手
2. **沟通规范**：定义 CLI 优化的输出格式（简洁、无嵌套列表、无装饰性 emoji）
3. **工具指导**：规定工具选择偏好（如优先使用 `rg` 而非 `grep`）
4. **子 Agent 编排**：定义何时以及如何生成并行子 Agent 以提高效率
5. **安全准则**：Git 安全规则（禁止未经批准执行破坏性命令）

### 使用场景

| 场景 | 描述 |
|------|------|
| **主 Agent 初始化** | 作为基础指令加载到每个 Codex 会话的系统提示词中 |
| **子 Agent 委托** | 指导主 Agent 何时/如何生成子 Agent（explorer、worker 角色）|
| **工具选择** | 引导 Agent 优先使用 `rg`、`apply_patch` 等工具 |
| **用户协作** | 定义协作姿态（平等共建者、保留用户意图）|
| **代码审查** | 设置代码审查心态（优先识别 bug、风险、回归）|

---

## 功能点目的

### 内容结构

```
orchestrator.md (106 行)
├── Personality (个性定义)          # 协作型结对编程 AI
├── Tone and Style (语气和风格)      # CLI 优化、简洁、可扫描
├── Responsiveness (响应性)         # 用户更新频率和长度协议
├── Code Style (代码风格)           # 清晰、可读、可维护优先
├── Reviews (审查)                  # 代码审查心态
├── Environment (环境)              # Git、AGENTS.md 约定
├── Tool Use (工具使用)             # 工具选择指南
└── Sub-agents (子 Agent)           # 并行委托规则
```

### 关键功能组件

#### 1. 个性与语气定义

```markdown
You are Codex, a coding agent based on GPT-5.
You are a collaborative, highly capable pair-programmer AI.
```

**目的**：建立情感基调和工作关系，使 Agent 表现出"安静的热情"和工程质量意识。

#### 2. CLI 优化输出格式

| 规则 | 说明 |
|------|------|
| 无嵌套列表 | 保持列表扁平（单层级）|
| 编号列表格式 | 仅使用 `1. 2. 3.` 样式（点号，非括号）|
| 标题规范 | 短标题（1-3 词），`**标题**` 格式，标题后无空行 |
| 代码块 | 始终包含 info string |
| 文件引用 | 使用可点击格式（`src/app.ts:42`、`b/server/index.js#L10`）|

**目的**：确保输出针对 CLI/终端渲染优化，保持低噪音、高信号。

#### 3. 用户更新协议

**频率与长度**：
- 有意义的洞察时发送短更新（1-2 句话）
- 长时间操作前发布简要"埋头"通知
- 仅初始计划、计划更新和最终总结可较长

**内容**：
- 友好、自信、高级工程师能量
- 仅在里程碑/章节或真正胜利时使用 emoji

**目的**：在工具密集型操作期间保持用户知情而不压倒他们。

#### 4. 代码风格指南

- 优先级：用户指令 > 系统/AGENTS.md 指令 > 本地文件约定 > 以下指令
- 优化目标：清晰、可读、可维护
- 偏好显式、冗长、人类可读的代码而非聪明或简洁的代码
- 注释：解释复杂代码块，避免无意义注释（如"将值赋给变量"）

#### 5. 审查心态

当用户要求审查时，默认采用**代码审查心态**：
- 优先识别 bug、风险、行为回归和缺失测试
- 按严重性排序发现，包含文件或行引用
- 明确说明是否无发现

#### 6. 子 Agent 编排规则

**核心规则**：
> Sub-agents are there to make you go fast and time is a big constraint so leverage them smartly as much as you can.

**一般准则**：
- 优先使用多个子 Agent 并行化工作
- 子 Agent 运行时，**等待它们完成后再产出**（除非用户明确提问）
- 让子 Agent 完成实际工作，主 Agent 仅协调
- 多步骤计划时，尽可能并行处理

**流程**：
1. 理解任务
2. 生成最优必要的子 Agent
3. 通过 wait_agent / send_input 协调它们
4. 迭代此过程
5. 达到 Agent 限制前询问用户是否关闭子 Agent

#### 7. 工具使用规范

- 除非另有指示，优先使用 `rg` 或 `rg --files` 进行搜索（比 `grep` 快）
- 单文件编辑优先使用 `apply_patch`，其他选项在无法工作时使用
- 复杂逻辑使用 `if`、`case`、`for`、`while` 控制流

#### 8. Git 安全规则

- 可能工作目录不干净，**绝不回滚**非自己做出的更改
- **绝不**使用 `git reset --hard` 或 `git checkout --` 等破坏性命令，除非用户明确请求或批准
- 不修改未触及文件中的无关更改
- 不修改 `.specstory` 等历史文件
- 不 `amend` 提交除非明确请求

---

## 具体技术实现

### 模板加载机制

与其他模板（如 `hierarchical_agents_message.md`）不同，`orchestrator.md`**不直接通过 `include_str!` 嵌入**。它通过配置/提示词系统加载，具体路径：

```
用户工作区 AGENTS.md (可选)
    ↓
项目级 AGENTS.md 发现 (project_doc.rs)
    ↓
Config::base_instructions / user_instructions
    ↓
BaseInstructions 模型
    ↓
API 请求中的 system 消息
```

### 相关模板系统

#### 协作模式预设

**文件**：`codex-rs/core/src/models_manager/collaboration_mode_presets.rs`

```rust
const COLLABORATION_MODE_PLAN: &str = include_str!("../../templates/collaboration_mode/plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!("../../templates/collaboration_mode/default.md");
const COLLABORATION_MODE_EXECUTE: &str = include_str!("../../templates/collaboration_mode/execute.md");
const COLLABORATION_MODE_PAIR_PROGRAMMING: &str = include_str!("../../templates/collaboration_mode/pair_programming.md");
```

这些模板定义模式特定行为（Plan 模式、Default 模式、Execute 模式、Pair Programming 模式），**叠加**在 orchestrator.md 基础之上。

#### 分层 Agent 消息

**文件**：`codex-rs/core/src/project_doc.rs`

```rust
pub(crate) const HIERARCHICAL_AGENTS_MESSAGE: &str =
    include_str!("../hierarchical_agents_message.md");
```

当 `Feature::ChildAgentsMd` 启用时，追加到用户指令中，解释 AGENTS.md 文件的作用域和优先级规则。

#### 内存系统模板

**文件**：`codex-rs/core/src/memories/mod.rs`

```rust
pub(super) const PROMPT: &str = include_str!("../../templates/memories/stage_one_system.md");
```

用于内存写入 Agent 的 Phase 1 提取。

#### 压缩模板

**文件**：`codex-rs/core/src/compact.rs`

```rust
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
```

用于上下文窗口压缩。

### 子 Agent 角色系统

**文件**：`codex-rs/core/src/agent/role.rs`

内置角色包括：
- **`default`**：默认 Agent，无特殊配置
- **`explorer`**：快速、权威的代码库探索 Agent
- **`worker`**：执行和生产工作 Agent

```rust
pub const DEFAULT_ROLE_NAME: &str = "default";

// 内置角色定义
AgentRoleConfig {
    description: Some("Default agent.".to_string()),
    config_file: None,
    nickname_candidates: None,
}
```

### 多 Agent 工具处理器

**文件**：`codex-rs/core/src/tools/handlers/multi_agents.rs`

实现协作工具接口：
- `spawn_agent`：生成新子 Agent
- `send_input`：发送消息到现有 Agent
- `wait_agent`：等待 Agent 完成
- `close_agent`：关闭 Agent
- `resume_agent`：从 rollout 恢复 Agent

### Agent 控制平面

**文件**：`codex-rs/core/src/agent/control.rs`

`AgentControl` 结构体提供：
- 通过 `spawn_agent()` 生成线程
- 通过 `send_input()` 发送输入
- 通过 `subscribe_status()` 监控状态
- 父子通知的完成监视器

```rust
#[derive(Clone, Default)]
pub(crate) struct AgentControl {
    manager: Weak<ThreadManagerState>,
    state: Arc<Guards>,
}
```

### ToolOrchestrator（工具编排器）

**文件**：`codex-rs/core/src/tools/orchestrator.rs`

注意：此处的 "Orchestrator" 是**运行时组件**，负责：
- 工具调用审批（approval）
- 沙盒选择（sandbox selection）
- 重试语义（retry semantics）

与 `orchestrator.md` 模板文件**不同**：
- `orchestrator.md`：定义主 Agent 行为的**提示词模板**
- `orchestrator.rs`：执行工具调用的**运行时编排逻辑**

```rust
pub(crate) struct ToolOrchestrator {
    sandbox: SandboxManager,
}

pub(crate) struct OrchestratorRunResult<Out> {
    pub output: Out,
    pub deferred_network_approval: Option<DeferredNetworkApproval>,
}
```

---

## 关键代码路径与文件引用

### 直接模板文件

| 文件 | 用途 | 加载方式 |
|------|------|----------|
| `orchestrator.md` | 主 Agent 系统提示词 | 配置/提示词系统 |
| `collaboration_mode/plan.md` | Plan 模式指令 | `include_str!` |
| `collaboration_mode/default.md` | Default 模式指令 | `include_str!` |
| `collaboration_mode/execute.md` | Execute 模式指令 | `include_str!` |
| `collaboration_mode/pair_programming.md` | Pair Programming 模式 | `include_str!` |
| `hierarchical_agents_message.md` | AGENTS.md 规则说明 | `include_str!` |
| `compact/prompt.md` | 压缩系统提示词 | `include_str!` |
| `memories/stage_one_system.md` | 内存提取提示词 | `include_str!` |

### 核心实现文件

| 文件 | 描述 |
|------|------|
| `codex-rs/core/src/agent/mod.rs` | Agent 模块导出 |
| `codex-rs/core/src/agent/control.rs` | AgentControl 生成/管理 |
| `codex-rs/core/src/agent/role.rs` | 角色解析和内置配置 |
| `codex-rs/core/src/agent/guards.rs` | 生成深度限制、守卫 |
| `codex-rs/core/src/tools/handlers/multi_agents.rs` | 协作工具处理器 |
| `codex-rs/core/src/tools/handlers/multi_agents/spawn.rs` | 生成 Agent 实现 |
| `codex-rs/core/src/tools/orchestrator.rs` | ToolOrchestrator（审批/沙盒）|
| `codex-rs/core/src/project_doc.rs` | 项目文档发现和组装 |
| `codex-rs/core/src/models_manager/collaboration_mode_presets.rs` | 协作模式预设 |

### 角色配置流程

```
用户请求
    ↓
spawn_agent 工具调用
    ↓
multi_agents/spawn.rs::Handler::handle()
    ↓
build_agent_spawn_config()  ← 从 turn 上下文创建基础配置
    ↓
apply_role_to_config()      ← 应用角色层 (role.rs)
    ↓
resolve_role_config()       ← 解析内置或用户定义角色
    ↓
built_in::configs()         ← 返回内置角色映射
    ↓
AgentControl::spawn_agent() ← 使用配置创建新线程
```

### BaseInstructions 组装流程

```
orchestrator.md (系统级基础指令)
    ↓
+ AGENTS.md (项目级指令，通过 project_doc.rs 发现)
    ↓
+ hierarchical_agents_message.md (如果启用 ChildAgentsMd)
    ↓
+ 协作模式覆盖 (plan.md / default.md / execute.md / pair_programming.md)
    ↓
= BaseInstructions 模型
    ↓
API 请求中的 system 消息
```

---

## 依赖与外部交互

### 内部依赖

```
templates/agents/orchestrator.md
    ├── 被引用：配置/提示词系统
    ├── 相关：collaboration_mode/*.md (模式特定覆盖)
    ├── 相关：hierarchical_agents_message.md (AGENTS.md 规则)
    ├── 相关：memories/*.md (内存 Agent 提示词)
    └── 消费：codex::Session (通过配置间接)
```

### 外部交互

| 交互 | 描述 |
|------|------|
| **模型提供商** | 系统提示词通过 API 发送给 GPT-5/Codex 模型 |
| **子 Agent** | Orchestrator 定义生成子进程的规则 |
| **用户** | 定义沟通模式和协作风格 |
| **文件系统** | 引用 AGENTS.md 发现规则 |
| **Git** | 定义 Git 安全规则（无破坏性命令）|

### 配置集成

orchestrator 模板与以下组件协同工作：

1. **`ConfigToml`**：基础配置结构
2. **`AgentRoleConfig`**：角色特定覆盖
3. **`BaseInstructions`**：运行时指令注入
4. **`CollaborationModeMask`**：模式特定指令覆盖

---

## 风险、边界与改进建议

### 潜在风险

#### 风险 1：模板漂移

**问题**：`orchestrator.md` 文件不像其他 `include_str!` 模板那样在编译时验证。存在语法错误或格式问题未检测到的风险。

**缓解**：添加构建时检查或测试验证模板可加载。

#### 风险 2：子 Agent 章节歧义

**问题**：模板提到 `spawn_agent` 可用性取决于工具是否存在，但模板本身未动态检查。

**缓解**：模板应澄清子 Agent 章节以功能可用性为条件。

#### 风险 3：模板中的注释代码

**问题**：第 81 行包含注释掉的指令：
```markdown
<!-- - Parallelize tool calls whenever possible... -->
```

这是应删除的死内容。

#### 风险 4：与 ToolOrchestrator 混淆

**问题**：文件名 `orchestrator.md` 与 `orchestrator.rs` 运行时组件容易混淆。

**缓解**：在文档中明确区分：
- `orchestrator.md`：**提示词模板**，定义 Agent 行为
- `orchestrator.rs`：**运行时组件**，处理工具审批和沙盒

### 边界条件

| 边界 | 描述 |
|------|------|
| **静态内容** | 模板是静态的；无法适应运行时条件 |
| **无 i18n** | 模板仅英文；无本地化支持 |
| **模型特定** | 为 GPT-5/Codex 编写；可能不适用于其他模型 |
| **工具列表静态** | 工具引用（rg、apply_patch）假定特定工具可用 |
| **AGENTS.md 优先级** | 系统/开发者/用户直接提示词指令优先于任何 AGENTS.md 内容 |

### 改进建议

#### 建议 1：添加模板验证测试

```rust
// 在测试或构建脚本中
#[test]
fn validate_orchestrator_template() {
    let content = include_str!("../templates/agents/orchestrator.md");
    assert!(!content.contains("<!--"), "模板中无 HTML 注释");
    assert!(content.len() > 1000, "模板有实质内容");
}
```

#### 建议 2：记录模板加载路径

应记录 `orchestrator.md` 的确切加载机制。目前不清楚这是：
- 运行时从文件系统加载
- 通过不可见的宏嵌入
- 通过配置层加载

#### 建议 3：删除死内容

删除第 81 行的注释 HTML 注释以保持模板清洁。

#### 建议 4：版本化模板

添加版本头以跟踪模板迭代：
```markdown
---
version: 1.0.0
last_updated: 2026-03-23
model_target: gpt-5-codex
---
```

#### 建议 5：考虑拆分

模板为 106 行且不断增长。考虑拆分为：
- `orchestrator_core.md` - 基本身份和行为
- `orchestrator_tools.md` - 工具使用指南
- `orchestrator_subagents.md` - 子 Agent 委托规则

这将提高可维护性并允许基于功能标志的选择性加载。

#### 建议 6：统一模板加载模式

当前模板加载模式不一致：
- 大多数模板使用 `include_str!`
- `orchestrator.md` 可能通过配置系统加载

建议统一为 `include_str!` 模式以提高可预测性：

```rust
// 在配置或基础指令模块中
pub const ORCHESTRATOR_PROMPT: &str = include_str!("../templates/agents/orchestrator.md");
```

### 测试缺口

| 缺口 | 影响 | 建议 |
|------|------|------|
| 无编译时包含 | 可能出现运行时错误 | 使用 `include_str!` 或在测试中验证 |
| 无模板版本控制 | 难以跟踪更改 | 添加元数据头 |
| 无 A/B 框架 | 无法测试模板变体 | 添加模板变体支持 |
| 无死内容检测 | 注释代码残留 | 添加 CI 检查 |

---

## 附录：模板交叉引用

### 所有模板在 codex-rs/core/templates

```
templates/
├── agents/
│   └── orchestrator.md              # [本文件] 主 Agent 系统提示词
├── collaboration_mode/
│   ├── default.md                   # Default 模式指令
│   ├── execute.md                   # Execute 模式指令
│   ├── pair_programming.md          # Pair Programming 模式
│   └── plan.md                      # Plan 模式指令
├── compact/
│   ├── prompt.md                    # 压缩系统提示词
│   └── summary_prefix.md            # 压缩摘要前缀
├── memories/
│   ├── consolidation.md             # Phase 2 合并指令
│   ├── read_path.md                 # 内存读取路径模板
│   ├── stage_one_input.md           # Phase 1 输入模板
│   └── stage_one_system.md          # Phase 1 系统提示词
├── model_instructions/
│   └── gpt-5.2-codex_instructions_template.md
├── personalities/
│   ├── gpt-5.2-codex_friendly.md
│   └── gpt-5.2-codex_pragmatic.md
├── review/
│   ├── exit_interrupted.xml         # 审查中断模板
│   ├── exit_success.xml             # 审查成功模板
│   ├── history_message_completed.md
│   └── history_message_interrupted.md
├── search_tool/
│   ├── tool_description.md          # 工具搜索描述
│   └── tool_suggest_description.md  # 工具建议描述
└── tools/
    └── presentation_artifact.md
```

### 模板加载模式

| 模式 | 示例文件 | 用例 |
|------|----------|------|
| `include_str!` | 大多数 `.md` 文件 | 编译时嵌入 |
| 运行时文件读取 | `orchestrator.md` (可能) | 动态配置 |
| JSON 模板 | `consequential_tool_message_templates.json` | 结构化数据 |

---

## 结论

`codex-rs/core/templates/agents/orchestrator.md` 文件是一个**关键的系统组件**，定义了 Codex Agent 的基础行为。虽然它看起来简单（单个 Markdown 文件），但它编排了以下复杂交互：

- 用户与主 Agent 之间
- 主 Agent 与子 Agent 之间
- Agent 与其工具生态系统之间
- 不同协作模式之间

理解此模板对于任何修改 Agent 行为、添加新协作模式或调试 Agent 沟通模式的人员至关重要。

**关键要点**：
1. 此模板是 Codex Agent 的"宪法"——它不仅定义 Agent 能做什么，还定义它应如何解决问题、与用户沟通、委托工作给专业子 Agent
2. 与 `orchestrator.rs` 运行时组件区分：`orchestrator.md` 是**提示词模板**，`orchestrator.rs` 是**工具审批和沙盒运行时**
3. 模板通过配置/提示词系统加载，而非 `include_str!`，这与其他模板不同
4. 建议统一模板加载模式，添加版本控制和验证测试
