# gpt-5.2-codex_prompt.md 研究文档

## 场景与职责

`gpt-5.2-codex_prompt.md` 是 Codex CLI 项目中为 **GPT-5.2-Codex** 模型定义的系统提示词（System Prompt）文件。该文件定义了 AI Agent 在终端环境中与用户交互时的行为准则、工具使用规范和输出格式要求。

**核心定位**：
- 作为 GPT-5.2-Codex 模型的基础指令模板
- 定义 Agent 的人格特质、沟通风格和编码规范
- 规范工具调用（如 apply_patch、shell 命令）的使用方式
- 确保与 Codex CLI 终端渲染系统的兼容性

---

## 功能点目的

### 1. 身份定义与能力声明
- 明确 Agent 身份："You are Codex, based on GPT-5. You are running as a coding agent in the Codex CLI on a user's computer."
- 区分 Codex（开源 Agentic 编码接口）与旧版 OpenAI Codex 语言模型

### 2. 工具使用规范
- **apply_patch**：定义了文件编辑的标准 patch 格式，支持 Add/Update/Delete 三种操作
- **Shell 命令**：优先使用 `rg` (ripgrep) 进行文本搜索，因其性能优于 grep
- **update_plan**：规划工具的使用规范，用于跟踪多步骤任务进度

### 3. 编辑约束与代码风格
- 默认使用 ASCII 编码，仅在必要时引入 Unicode
- 代码注释要求简洁，避免无意义的注释（如 "Assigns the value to the variable"）
- 支持在 dirty git worktree 中工作，禁止擅自回滚用户未请求的更改

### 4. 输出格式规范
- 纯文本输出，由 CLI 进行样式渲染
- 文件引用格式：`src/app.ts:42` 或 `b/server/index.js#L10`
- 禁止使用 URI 格式（file://、vscode://、https://）
- 禁止使用 ANSI 转义码

### 5. 前端任务特殊要求
- 避免 "AI slop"（平庸、安全的布局）
- 字体：使用有表现力的字体，避免默认栈（Inter、Roboto、Arial）
- 颜色：定义清晰的视觉方向，避免紫色/白色默认配色
- 动效：使用有意义的动画而非通用微动效
- 背景：使用渐变、形状或微妙图案构建氛围

---

## 具体技术实现

### 关键数据结构

```rust
// ModelInfo 结构体中的提示词相关字段
pub struct ModelInfo {
    pub slug: String,
    pub base_instructions: String,      // 对应 gpt-5.2-codex_prompt.md 内容
    pub model_messages: Option<ModelMessages>,  // 模板化消息
    pub supports_parallel_tool_calls: bool,
    pub context_window: Option<u32>,
    // ... 其他字段
}

pub struct ModelMessages {
    pub instructions_template: Option<String>,  // 带 {{ personality }} 占位符的模板
    pub instructions_variables: Option<ModelInstructionsVariables>,
}
```

### 提示词加载流程

1. **编译时嵌入**：通过 `include_str!` 宏将 prompt 文件嵌入二进制
   ```rust
   // codex-rs/core/src/models_manager/model_info.rs:17
   pub const BASE_INSTRUCTIONS: &str = include_str!("../../prompt.md");
   ```

2. **模型配置合并**：`with_config_overrides` 函数合并用户配置覆盖
   ```rust
   pub(crate) fn with_config_overrides(mut model: ModelInfo, config: &Config) -> ModelInfo
   ```

3. **个性化模板处理**：对于 gpt-5.2-codex，使用 `local_personality_messages_for_slug` 函数
   ```rust
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

### 模板变量替换

- `{{ personality }}`：根据用户选择的 personality 模式（default/friendly/pragmatic）替换
- 模板文件位置：`codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md`

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/gpt-5.2-codex_prompt.md` | 本文件，定义 GPT-5.2-Codex 的基础系统提示词 |
| `codex-rs/core/src/models_manager/model_info.rs` | 模型信息定义，包含提示词加载逻辑 |
| `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md` | 带 personality 占位符的指令模板 |
| `codex-rs/core/models.json` | 模型配置 JSON，包含 base_instructions 和 model_messages |

### 关键代码引用

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

### 模型配置（models.json 节选）

```json
{
  "slug": "gpt-5.2-codex",
  "base_instructions": "You are Codex, based on GPT-5...",
  "model_messages": {
    "instructions_template": "You are Codex, a coding agent based on GPT-5...\n\n{{ personality }}...",
    "instructions_variables": {
      "personality_default": "",
      "personality_friendly": "# Personality\n\nYou optimize for team morale...",
      "personality_pragmatic": "# Personality\n\nYou are a deeply pragmatic..."
    }
  }
}
```

---

## 依赖与外部交互

### 内部依赖

1. **codex_protocol**: 定义 `ModelInfo`、`ModelMessages`、`ModelInstructionsVariables` 等类型
2. **Config 系统**: `codex-rs/core/src/config/` 提供用户配置覆盖能力
3. **Features 系统**: `codex-rs/core/src/features.rs` 控制 Personality 等功能的启用

### 外部交互

1. **OpenAI API**: 提示词通过 API 的 `system` 角色消息发送给模型
2. **Codex CLI 渲染器**: 纯文本输出由 CLI 的样式系统进行渲染
3. **用户终端**: 最终输出显示在用户的终端环境中

### 配置覆盖点

用户可通过以下方式覆盖默认提示词：
- `config.base_instructions`: 完全替换基础指令
- `config.features.Personality`: 启用/禁用 personality 功能
- `config.model_supports_reasoning_summaries`: 启用推理摘要

---

## 风险、边界与改进建议

### 潜在风险

1. **版本漂移风险**：
   - `gpt-5.2-codex_prompt.md` 与 `models.json` 中的 `base_instructions` 可能不一致
   - 模板文件 `gpt-5.2-codex_instructions_template.md` 需要与 prompt.md 保持同步

2. **提示词注入风险**：
   - 用户输入可能通过文件内容间接影响提示词（如 AGENTS.md 被包含进上下文）
   - `hierarchical_agents_message.md` 在 `ChildAgentsMd` 功能启用时追加到提示词

3. **个性化模板兼容性**：
   - `{{ personality }}` 占位符替换失败会导致提示词格式错误
   - 三种 personality 变体需要维护一致的指令结构

### 边界条件

1. **上下文窗口限制**：
   - GPT-5.2-Codex 上下文窗口：272,000 tokens
   - 提示词长度影响可用对话历史长度

2. **功能开关边界**：
   - 当 `Feature::Personality` 禁用时，`model_messages` 被设为 `None`
   - 当 `Feature::ChildAgentsMd` 启用时，追加分层 Agent 消息

3. **模型降级处理**：
   - 未知模型使用 `model_info_from_slug` 生成 fallback 配置
   - Fallback 使用 `BASE_INSTRUCTIONS`（即 `prompt.md` 内容，非本文件）

### 改进建议

1. **一致性保障**：
   - 建立 CI 检查确保 `gpt-5.2-codex_prompt.md`、`models.json`、`gpt-5.2-codex_instructions_template.md` 三者内容一致
   - 考虑使用代码生成工具从单一源生成多个目标文件

2. **版本管理**：
   - 为提示词文件添加版本注释，便于追踪变更历史
   - 考虑将提示词内容哈希存入模型元数据，便于调试

3. **测试覆盖**：
   - 添加提示词内容快照测试，防止意外变更
   - 测试 personality 变量替换的各种边界情况

4. **文档化**：
   - 在 `gpt-5.2-codex_prompt.md` 文件头添加注释，说明其用途和同步要求
   - 明确说明与 `gpt_5_2_prompt.md`（下划线命名版本）的区别

### 相关文件对比

| 文件 | 命名风格 | 用途 |
|------|---------|------|
| `gpt-5.2-codex_prompt.md` | 连字符命名 | 较短的 Codex 专用提示词 |
| `gpt_5_2_prompt.md` | 下划线命名 | 更详细的 GPT-5.2 通用提示词 |
| `gpt-5.2-codex_instructions_template.md` | 连字符命名 | 带 personality 占位符的模板 |

注意：项目中存在两种命名风格（连字符 vs 下划线），需要根据模型 slug 格式（`gpt-5.2-codex` 使用连字符）选择正确的文件。
