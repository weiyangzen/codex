# gpt_5_1_prompt.md 研究文档

## 场景与职责

`gpt_5_1_prompt.md` 是 Codex CLI 项目中为 **GPT-5.1** 模型定义的详细系统提示词文件。这是 GPT-5.1 系列模型（包括 `gpt-5.1`、`gpt-5.1-codex`、`gpt-5.1-codex-max`、`gpt-5.1-codex-mini` 等变体）的核心行为定义文档。

**核心定位**：
- 定义 GPT-5.1 系列模型在 Codex CLI 中的完整行为准则
- 规范 Agent 的人格特质、沟通风格、任务执行流程
- 详细说明工具使用（apply_patch、update_plan、shell 命令等）
- 建立代码审查、测试验证、工作汇报的标准流程

**历史背景**：
- GPT-5.1 是 Codex CLI 早期采用的主力模型系列
- 该提示词文件代表了 OpenAI 对 Agentic 编码助手的早期设计思想
- 后续 GPT-5.2、GPT-5.3、GPT-5.4 的提示词在此基础上演进

---

## 功能点目的

### 1. 身份与能力声明（Identity & Capabilities）

明确 Agent 的核心能力：
- 接收用户提示和上下文（如工作区文件）
- 通过流式思考和响应与用户通信
- 创建和更新计划（plan）
- 发出函数调用执行终端命令和应用补丁

关键区分：
> "Within this context, Codex refers to the open-source agentic coding interface (not the old Codex language model built by OpenAI)."

### 2. AGENTS.md 规范

定义项目级配置文件的发现和使用规则：
- AGENTS.md 可出现在仓库任何位置
- 作用域：包含该文件的目录及其所有子目录
- 深层 AGENTS.md 优先于高层文件
- 直接指令（系统/开发者/用户）优先于 AGENTS.md

### 3. 自主性与持久性（Autonomy and Persistence）

核心原则：
- 在当前回合内持久处理任务直至完成
- 不停止在分析或部分修复阶段
- 实施变更、验证、清晰解释结果
- 除非用户明确要求，否则不猜测或编造答案

### 4. 响应性规范（Responsiveness）

**频率与长度**：
- 有意义的洞察时发送简短更新（1-2 句话）
- 长时间专注工作时提前告知用户
- 仅初始计划、计划更新和最终回顾可较长

**内容要求**：
- 第一次工具调用前给出快速计划（目标、约束、下一步）
- 探索过程中指出有意义的新发现
- 计划变更时明确说明

### 5. 规划工具（Planning）

**使用时机**：
- 非平凡任务需要多步骤长时间完成
- 存在逻辑阶段或依赖关系
- 工作存在需要明确高层目标的模糊性
- 需要中间检查点进行反馈和验证
- 用户要求使用计划工具（TODOs）

**计划质量标准**：
- 高质量计划：具体、可验证的步骤（如 "Add CLI entry with file args"）
- 低质量计划：模糊、笼统的步骤（如 "Create CLI tool"）

### 6. 任务执行准则（Task Execution）

**核心要求**：
- 在现有代码库中精确执行用户要求，避免过度扩展
- 修复根本原因而非表面修补
- 避免不必要的复杂性
- 不修复无关的 bug 或失败的测试
- 必要时更新文档
- 使用 `git log` 和 `git blame` 获取历史上下文

**禁止行为**：
- 添加版权或许可证头（除非明确要求）
- 在调用 `apply_patch` 后重新读取文件
- 执行 `git commit` 或创建分支（除非明确要求）
- 使用单字母变量名（除非明确要求）
- 输出内联引用（如 `【F:README.md†L5-L14】`）

### 7. 工作验证（Validating Work）

**测试哲学**：
- 从尽可能具体的测试开始，逐步扩展到更广泛的测试
- 如果代码变更无测试且相邻模式显示有逻辑位置，可添加测试
- 但不要为无测试的代码库添加测试

**验证命令执行时机**：
- **never/on-failure 模式**：主动运行测试、lint 等
- **untrusted/on-request 模式**：等待用户确认后再运行
- 测试相关任务：无论批准模式如何，都可主动运行测试

### 8. 野心与精确的平衡（Ambition vs. Precision）

- **全新任务**：可发挥创造力，展示雄心
- **现有代码库**：精确执行用户要求，尊重周围代码
- 根据用户需求判断细节和复杂度级别

### 9. 最终答案结构与风格

**结构要求**：
- 纯文本，CLI 处理样式
- 标题：1-3 个词，Title Case，`**Title**` 格式
- 项目符号：使用 `-`，4-6 个一组，按重要性排序
- 等宽字体：反引号包裹命令/路径/代码
- 代码块：围栏代码块，包含 info 字符串

**文件引用规则**：
- 使用内联代码使文件路径可点击
- 接受：绝对路径、工作区相对路径、a/ 或 b/ diff 前缀
- 行/列格式：`:line[:column]` 或 `#Lline[Ccolumn]`
- 不接受：URI 格式（file://、vscode://、https://）
- 不提供行范围

**详细程度规则**：
- 微小变更（≤10 行）：2-5 句话或 ≤3 个要点，无标题
- 中等变更：≤6 个要点或 6-10 句话，最多 1-2 个短代码片段
- 大型/多文件变更：每文件 1-2 个要点总结，避免内联代码

### 10. 工具使用指南

**Shell 命令**：
- 优先使用 `rg` 或 `rg --files` 进行文本/文件搜索
- 不要用 Python 脚本输出大文件内容

**apply_patch**：
- 使用剥离式、面向文件的 diff 格式
- 三种操作：Add File、Delete File、Update File
- Update 使用 `@@` 标记定位变更点

**update_plan**：
- 创建计划：简短步骤列表（5-7 个词），带状态
- 更新计划：标记完成项和进行中项
- 始终恰好有一个 `in_progress` 项直到完成

---

## 具体技术实现

### 提示词加载与使用

```rust
// models.json 中的 GPT-5.1 配置
{
  "slug": "gpt-5.1",
  "base_instructions": "You are GPT-5.1 running in the Codex CLI...",
  "model_messages": {
    "instructions_template": "...",
    "instructions_variables": {
      "personality_default": "",
      "personality_friendly": "...",
      "personality_pragmatic": "..."
    }
  }
}
```

### 模型变体配置

| 模型 slug | 配置特点 |
|----------|---------|
| `gpt-5.1` | 基础版本，标准配置 |
| `gpt-5.1-codex` | Codex 优化版本，启用代码专用功能 |
| `gpt-5.1-codex-max` | 最大能力版本，支持更多工具 |
| `gpt-5.1-codex-mini` | 轻量版本，资源受限环境使用 |

### 迁移提示配置

```rust
// codex-rs/core/src/models_manager/model_presets.rs
pub const HIDE_GPT5_1_MIGRATION_PROMPT_CONFIG: &str = "hide_gpt5_1_migration_prompt";
pub const HIDE_GPT_5_1_CODEX_MAX_MIGRATION_PROMPT_CONFIG: &str = 
    "hide_gpt-5.1-codex-max_migration_prompt";
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/gpt_5_1_prompt.md` | 本文件，GPT-5.1 详细系统提示词 |
| `codex-rs/core/models.json` | 模型配置，包含 base_instructions 和 model_messages |
| `codex-rs/core/src/models_manager/model_presets.rs` | 迁移提示配置常量 |
| `codex-rs/core/src/config/types.rs` | 配置类型定义，包含迁移提示隐藏标志 |

### 配置类型定义

```rust
// codex-rs/core/src/config/types.rs:784-786
/// Tracks whether the user has seen the gpt-5.1-codex-max migration prompt
#[serde(rename = "hide_gpt-5.1-codex-max_migration_prompt")]
pub hide_gpt_5_1_codex_max_migration_prompt: Option<bool>,
```

### 测试引用

```rust
// codex-rs/core/src/config/edit_tests.rs:473-496
#[test]
fn blocking_set_hide_gpt_5_1_codex_max_migration_prompt_preserves_table() {
    // 测试迁移提示配置持久化
}

// codex-rs/core/src/tools/spec_tests.rs:1279-1304
#[test]
fn test_gpt_5_1_codex_max_defaults() {
    // 测试 gpt-5.1-codex-max 默认配置
}

#[test]
fn test_gpt_5_1_defaults() {
    // 测试 gpt-5.1 默认配置
}
```

---

## 依赖与外部交互

### 内部依赖

1. **Model Manager** (`codex-rs/core/src/models_manager/`)
   - `manager.rs`: 模型生命周期管理
   - `model_info.rs`: 模型元数据，包含提示词
   - `cache.rs`: 模型配置缓存

2. **Config 系统** (`codex-rs/core/src/config/`)
   - `types.rs`: 配置类型定义
   - `edit.rs`: 配置编辑操作
   - 支持通过 `set_model` 切换 GPT-5.1 系列模型

3. **Features 系统** (`codex-rs/core/src/features.rs`)
   - 控制模型特性的启用/禁用
   - 影响提示词中的功能可用性

### 外部交互

1. **OpenAI API**
   - 提示词作为 `system` 消息发送
   - 支持流式响应（streaming）
   - 工具调用通过 API 的 function calling 机制

2. **Codex CLI 前端**
   - TUI（Terminal User Interface）渲染 Agent 输出
   - 处理用户输入和 Agent 响应的交互循环

### 配置覆盖点

```rust
// 用户可通过 Config 覆盖的选项
pub struct Config {
    pub model: Option<String>,  // 选择 "gpt-5.1" 等
    pub model_reasoning_effort: Option<ReasoningEffort>,
    pub base_instructions: Option<String>,  // 完全覆盖提示词
    pub features: Features,  // 启用/禁用特性
}
```

---

## 风险、边界与改进建议

### 潜在风险

1. **提示词长度风险**：
   - `gpt_5_1_prompt.md` 长达 331 行，约 24KB
   - 占用大量上下文窗口（272K tokens 中约 6-8K tokens）
   - 减少可用对话历史长度

2. **版本兼容性风险**：
   - GPT-5.1 系列有多个变体，提示词需要保持一致
   - `gpt_5_1_prompt.md` 与 `models.json` 中的配置可能漂移
   - 迁移提示配置需要向后兼容

3. **功能演进风险**：
   - GPT-5.2、5.3、5.4 的提示词基于此文件演进
   - 修改此文件可能影响后续模型的行为一致性
   - 新功能（如 `apply_patch` 改进）需要同步到所有版本

4. **测试依赖风险**：
   - 大量测试硬编码 `gpt-5.1` 作为测试模型
   - 变更提示词可能导致测试行为变化

### 边界条件

1. **模型降级边界**：
   ```rust
   // 未知模型使用 fallback
   pub(crate) fn model_info_from_slug(slug: &str) -> ModelInfo {
       // 使用 BASE_INSTRUCTIONS（prompt.md），非本文件
   }
   ```

2. **配置覆盖边界**：
   - 用户设置 `base_instructions` 时，`model_messages` 被设为 `None`
   - Personality 功能禁用时，个性化模板不生效

3. **迁移提示边界**：
   - 首次切换到 `gpt-5.1-codex-max` 时显示迁移提示
   - 用户可通过配置隐藏迁移提示

### 改进建议

1. **模块化提示词**：
   - 将 331 行的提示词拆分为多个模块文件
   - 使用 `include_str!` 组合，提高可维护性
   - 示例结构：
     ```
     prompts/
     ├── core/           # 核心行为
     ├── tools/          # 工具使用
     ├── formatting/     # 输出格式
     └── personality/    # 人格特质
     ```

2. **版本化提示词**：
   - 为提示词添加版本号（如 `gpt_5_1_prompt_v2.md`）
   - 支持模型配置引用特定版本
   - 便于 A/B 测试和回滚

3. **自动化同步**：
   - CI 检查确保 `gpt_5_1_prompt.md` 与 `models.json` 一致
   - 代码生成工具从 Markdown 生成 JSON 配置

4. **测试改进**：
   - 添加提示词内容快照测试
   - 测试 personality 变量替换
   - 验证关键指令（如 "NEVER use destructive commands"）存在于提示词中

5. **文档化**：
   - 在文件头添加注释说明文件用途和同步要求
   - 明确说明与 `gpt-5.1-codex_prompt.md`（连字符命名）的区别
   - 添加变更日志记录提示词演进

### 文件命名一致性

项目中存在命名不一致问题：

| 文件 | 命名风格 | 建议 |
|------|---------|------|
| `gpt_5_1_prompt.md` | 下划线 | 保持，对应 `gpt-5.1` 模型 |
| `gpt-5.1-codex_prompt.md` | 连字符 | 保持，对应 `gpt-5.1-codex` 模型 |
| `gpt_5_2_prompt.md` | 下划线 | 保持，对应 GPT-5.2 系列 |
| `gpt-5.2-codex_prompt.md` | 连字符 | 保持，对应 `gpt-5.2-codex` 模型 |

建议：建立命名规范文档，明确何时使用下划线（模型系列）vs 连字符（具体模型变体）。
