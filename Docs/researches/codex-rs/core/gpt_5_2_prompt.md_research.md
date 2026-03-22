# gpt_5_2_prompt.md 研究文档

## 场景与职责

`gpt_5_2_prompt.md` 是 Codex CLI 项目中为 **GPT-5.2** 模型定义的详细系统提示词文件。这是 GPT-5.2 系列模型的核心行为定义文档，在 GPT-5.1 的基础上进行了简化和优化。

**核心定位**：
- 定义 GPT-5.2 系列模型在 Codex CLI 中的行为准则
- 相比 GPT-5.1 提示词更加精简（298 行 vs 331 行）
- 移除了部分重复或冗余的指令，保留核心要求
- 优化了工具使用（特别是 `update_plan`）的描述

**演进关系**：
- GPT-5.2 → GPT-5.3 → GPT-5.4：逐步演进
- 提示词风格从详细规范向简洁实用转变
- 前端任务要求首次在 GPT-5.2 提示词中明确添加

---

## 功能点目的

### 1. 身份与能力声明

与 GPT-5.1 一致，明确 Agent 的核心能力：
- 接收用户提示和上下文
- 流式思考和响应
- 创建和更新计划
- 发出函数调用

关键区分说明：
> "Within this context, Codex refers to the open-source agentic coding interface (not the old Codex language model built by OpenAI)."

### 2. AGENTS.md 规范（简化版）

保留了 AGENTS.md 的核心规则：
- 发现机制：仓库任何位置
- 作用域：目录树继承
- 优先级：深层覆盖高层，直接指令覆盖文件

**变化**：相比 GPT-5.1，移除了部分示例说明，更加简洁。

### 3. 自主性与持久性

核心原则保持一致：
- 持久处理直至任务完成
- 不停止在分析阶段
- 实施、验证、解释

### 4. 响应性规范（精简）

**主要变化**：
- GPT-5.1 有详细的 "User Updates Spec" 小节
- GPT-5.2 合并为更简洁的 "Responsiveness" 部分
- 移除了具体的示例列表（如 "I've explored the repo..."）

### 5. 规划工具（优化描述）

**使用时机**：与 GPT-5.1 基本一致

**关键改进**：
- 更清晰的计划质量标准说明
- 强调 "Plans are not for padding out simple work"
- 明确禁止 "do anything that you aren't capable of doing"

**高质量计划示例**：
```
1. Add CLI entry with file args
2. Parse Markdown via CommonMark library
3. Apply semantic HTML template
4. Handle code blocks, images, links
5. Add error handling for invalid files
```

**低质量计划示例**：
```
1. Create CLI tool
2. Add Markdown parser
3. Convert to HTML
```

### 6. 任务执行准则

**核心要求**：与 GPT-5.1 基本一致

**新增/强调内容**：
- 明确添加 "If you're building a web app from scratch, give it a beautiful and modern UI, imbued with best UX practices."
- 这是前端任务要求的早期形态

**禁止行为**：与 GPT-5.1 一致，包括：
- 不添加版权/许可证头
- 不重新读取已 patch 的文件
- 不自动执行 git commit
- 不使用单字母变量名
- 不输出内联引用

### 7. 工作验证

**测试哲学**：与 GPT-5.1 一致

**验证命令执行时机**：明确三种批准模式的行为差异

### 8. 野心与精确的平衡

内容基本与 GPT-5.1 一致，强调：
- 新任务：可发挥创造力
- 现有代码库：精确执行

### 9. 最终答案结构与风格

**结构要求**：与 GPT-5.1 基本一致

**关键差异**：
- GPT-5.2 将 "Final answer structure and style guidelines" 提升为独立顶级章节
- 更强调 "Plain text; CLI handles styling"
- 详细说明详细程度规则（verbosity rules）

**详细程度规则**：
- 微小变更（≤10 行）：2-5 句话或 ≤3 个要点
- 中等变更：≤6 个要点或 6-10 句话
- 大型/多文件变更：每文件 1-2 个要点

### 10. 工具使用指南

**Shell 命令**：与 GPT-5.1 一致，优先使用 `rg`

**apply_patch**：格式描述与 GPT-5.1 一致

**update_plan**：描述更加简洁

**新增**：
- 明确提及 "Parallelize tool calls whenever possible"
- 强调使用 `multi_tool_use.parallel`

---

## 具体技术实现

### 提示词加载

```rust
// models.json 中的 GPT-5.2-Codex 配置
{
  "slug": "gpt-5.2-codex",
  "base_instructions": "You are Codex, based on GPT-5...",
  "model_messages": {
    "instructions_template": "You are Codex, a coding agent based on GPT-5...\n\n{{ personality }}...",
    "instructions_variables": {
      "personality_default": "",
      "personality_friendly": "...",
      "personality_pragmatic": "..."
    }
  }
}
```

### 模型变体

GPT-5.2 系列主要包括：
- `gpt-5.2-codex`: 主要变体，Codex 优化版本
- `exp-codex-personality`: 实验性 personality 功能版本

### 个性化模板处理

```rust
// codex-rs/core/src/models_manager/model_info.rs:96-110
fn local_personality_messages_for_slug(slug: &str) -> Option<ModelMessages> {
    match slug {
        "gpt-5.2-codex" | "exp-codex-personality" => Some(ModelMessages {
            instructions_template: Some(format!(
                "{DEFAULT_PERSONALITY_HEADER}\n\n{PERSONALITY_PLACEHOLDER}\n\n{BASE_INSTRUCTIONS}"
            )),
            instructions_variables: Some(ModelInstructionsVariables {
                personality_default: Some(String::new()),
                personality_friendly: Some(LOCAL_FRIENDLY_TEMPLATE.to_string()),
                personality_pragmatic: Some(LOCAL_PRAGMATIC_TEMPLATE.to_string()),
            }),
        }),
        _ => None,
    }
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/gpt_5_2_prompt.md` | 本文件，GPT-5.2 详细系统提示词（298 行） |
| `codex-rs/core/gpt-5.2-codex_prompt.md` | GPT-5.2-Codex 简短版本（80 行） |
| `codex-rs/core/models.json` | 模型配置，包含 GPT-5.2-Codex 配置 |
| `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md` | 带 personality 占位符的模板 |

### 测试引用

```rust
// codex-rs/core/src/memories/prompts_tests.rs
#[test]
fn test_memory_prompts() {
    let mut model_info = model_info_from_slug("gpt-5.2-codex");
    // 测试记忆功能提示词
}
```

### 模型配置（models.json 节选）

```json
{
  "slug": "gpt-5.2-codex",
  "display_name": "gpt-5.2-codex",
  "description": "Frontier agentic coding model.",
  "context_window": 272000,
  "base_instructions": "You are Codex, based on GPT-5...",
  "model_messages": {
    "instructions_template": "You are Codex, a coding agent based on GPT-5...\n\n{{ personality }}...",
    "instructions_variables": {
      "personality_default": "",
      "personality_friendly": "# Personality\n\nYou optimize for team morale...",
      "personality_pragmatic": "# Personality\n\nYou are a deeply pragmatic..."
    }
  },
  "upgrade": {
    "model": "gpt-5.4",
    "migration_markdown": "Introducing GPT-5.4..."
  }
}
```

---

## 依赖与外部交互

### 内部依赖

1. **Model Manager** (`codex-rs/core/src/models_manager/`)
   - 管理 GPT-5.2-Codex 模型的生命周期
   - 处理模型配置和提示词加载

2. **Config 系统** (`codex-rs/core/src/config/`)
   - 支持用户配置覆盖默认提示词
   - 模型切换功能

3. **Features 系统** (`codex-rs/core/src/features.rs`)
   - `Feature::Personality`: 控制个性化模板
   - `Feature::ChildAgentsMd`: 控制分层 Agent 消息

### 外部交互

1. **OpenAI API**
   - GPT-5.2 模型通过 API 调用
   - 支持流式响应和工具调用

2. **Codex CLI 渲染器**
   - 纯文本输出由 CLI 样式系统渲染

---

## 风险、边界与改进建议

### 潜在风险

1. **与 GPT-5.1 提示词的差异风险**：
   - GPT-5.2 提示词是 GPT-5.1 的简化版，但两者并存
   - 用户可能困惑于两个版本的差异
   - 维护两个相似文件增加同步成本

2. **文件命名混淆**：
   - `gpt_5_2_prompt.md`（下划线）vs `gpt-5.2-codex_prompt.md`（连字符）
   - 两个文件内容差异显著（298 行 vs 80 行）
   - 需要明确各自的使用场景

3. **演进方向风险**：
   - GPT-5.2 提示词是向更简洁风格演进的中间阶段
   - GPT-5.3、5.4 的提示词又采用了不同的结构
   - 历史文件可能缺乏维护

### 边界条件

1. **模型升级路径**：
   - GPT-5.2-Codex 配置为升级到 GPT-5.4
   - 升级时显示迁移提示（migration_markdown）

2. **Fallback 处理**：
   - 未知模型使用 `BASE_INSTRUCTIONS`（`prompt.md` 内容）
   - 非 `gpt-5.2-codex` 或 `exp-codex-personality` 不使用个性化模板

3. **Personality 功能边界**：
   - 仅当 `Feature::Personality` 启用且模型匹配时才使用 `model_messages`
   - 用户设置 `base_instructions` 时禁用 `model_messages`

### 改进建议

1. **文件合并或清理**：
   - 评估是否仍需要维护 `gpt_5_2_prompt.md`
   - 如果 `gpt-5.2-codex_prompt.md` 已足够，考虑移除长版本
   - 或在文件头添加注释说明各自用途

2. **命名规范化**：
   - 建立清晰的命名约定：
     - 下划线版本（`gpt_5_2_prompt.md`）：通用/详细版本
     - 连字符版本（`gpt-5.2-codex_prompt.md`）：特定模型/精简版本
   - 在 README 或 AGENTS.md 中记录约定

3. **内容同步**：
   - 如果保留两个版本，建立同步机制
   - 关键变更（如工具使用规范）需要同时更新两个文件

4. **版本标记**：
   - 在提示词文件头添加版本注释：
     ```markdown
     <!-- Version: 2024-03 -->
     <!-- Model: GPT-5.2 series -->
     <!-- Purpose: Detailed system prompt for GPT-5.2 models -->
     ```

5. **文档化差异**：
   - 创建对比文档说明 GPT-5.1 vs GPT-5.2 提示词的主要差异
   - 帮助开发者理解演进方向

### 与 GPT-5.1 提示词的关键差异总结

| 方面 | GPT-5.1 | GPT-5.2 | 影响 |
|------|---------|---------|------|
| 行数 | 331 行 | 298 行 | 精简 10% |
| 响应性描述 | 详细，含示例 | 精简，无示例 | 减少冗余 |
| 规划工具 | 详细说明 | 更简洁 | 聚焦核心 |
| 前端任务 | 无明确要求 | 首次添加 | 新增能力 |
| 工具并行 | 提及 | 强调 | 更重要 |
| 详细程度规则 | 有 | 更详细 | 更明确 |

### 结论

`gpt_5_2_prompt.md` 代表了 Codex CLI 提示词设计向更简洁、更实用方向的演进。相比 GPT-5.1，它移除了部分冗余说明，增加了前端任务支持，并强化了工具并行调用的重要性。然而，与 `gpt-5.2-codex_prompt.md` 的并存以及文件命名不一致带来了维护复杂性，建议进行清理和规范化。
