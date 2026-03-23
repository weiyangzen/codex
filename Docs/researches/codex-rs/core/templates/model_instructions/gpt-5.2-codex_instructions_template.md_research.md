# gpt-5.2-codex_instructions_template.md 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`gpt-5.2-codex_instructions_template.md` 是 Codex CLI 项目中用于 **GPT-5.2-Codex 模型** 的专用指令模板文件，位于 `codex-rs/core/templates/model_instructions/` 目录下。该文件是模型指令系统的核心组成部分，负责定义 Codex 代理在与用户交互时的行为准则、输出格式和约束条件。

### 1.2 核心职责

该模板承担以下关键职责：

1. **身份定义**：明确 Codex 作为基于 GPT-5 的编码代理的身份定位
2. **交互规范**：定义与用户通过终端交互时的格式、语调和结构要求
3. **工具使用指南**：规定 `apply_patch` 等核心工具的正确使用方式
4. **个性注入**：通过 `{{ personality }}` 占位符支持动态个性切换（Friendly/Pragmatic）
5. **约束声明**：明确编辑约束、计划工具使用规则、前端任务指导等

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| 会话初始化 | 新会话启动时，作为系统指令注入到模型上下文 |
| 模型切换 | 用户切换模型时，通过 `build_model_instructions_update_item` 更新指令 |
| 个性切换 | 用户切换 Friendly/Pragmatic 个性时，重新渲染模板 |
| 子代理派生 | 子代理（SubAgent）继承父代理的基础指令配置 |

---

## 2. 功能点目的

### 2.1 模板结构解析

该模板采用 **Handlebars-style** 占位符机制，核心结构如下：

```markdown
You are Codex, a coding agent based on GPT-5...

{{ personality }}

# Working with the user
...交互规范...

# General
...通用指南...

## Editing constraints
...编辑约束...

## Plan tool
...计划工具使用规则...

## Special user requests
...特殊请求处理...

## Frontend tasks
...前端任务指导...
```

### 2.2 关键功能模块

#### 2.2.1 个性系统（Personality System）

- **占位符**：`{{ personality }}`
- **替换来源**：`codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md` 或 `gpt-5.2-codex_pragmatic.md`
- **控制逻辑**：由 `ModelInfo::get_model_instructions()` 方法执行替换

**Friendly 个性特征**：
- 优化团队士气和协作体验
- 温暖、鼓励性、对话式语调
- 使用 "we" 和 "let's" 等团队导向语言
- 耐心、不急躁，即使面对错误也保持支持性

**Pragmatic 个性特征**（默认）：
- 深度务实、高效的软件工程师风格
- 清晰、务实、严谨的价值观
- 简洁、尊重、专注于任务的交互风格
- 避免过度热情或人工安慰

#### 2.2.2 最终答案格式化规则

定义了严格的输出格式规范：

| 规则 | 说明 |
|------|------|
| GitHub-flavored Markdown | 支持标准 Markdown 格式 |
| 扁平列表 | 禁止使用嵌套子弹点，保持单层列表 |
| 标题规范 | 简短 Title Case（1-3 词），包裹在 `**...**` 中 |
| 文件引用 | 支持绝对路径、工作区相对路径、a/b diff 前缀 |
| 禁止 Emoji | 输出中不得使用表情符号 |

#### 2.2.3 编辑约束（Editing Constraints）

- 默认使用 ASCII 编码，仅在必要时引入 Unicode
- 代码注释应简洁，解释复杂逻辑而非显而易见的内容
- 使用 `apply_patch` 进行单文件编辑
- 正确处理脏工作区（dirty git worktree）
- 禁止使用破坏性命令如 `git reset --hard`

#### 2.2.4 计划工具（Plan Tool）

- 仅对非简单任务（约最困难的 25%）使用计划工具
- 禁止单步计划
- 完成子任务后更新计划状态

#### 2.2.5 前端任务指导

明确避免 "AI slop"（AI 生成的平庸设计）：
- 排版：使用有表现力的字体，避免默认栈（Inter、Roboto、Arial）
- 色彩：定义清晰的视觉方向，避免紫色偏见或暗色模式偏见
- 动效：使用有意义的动画而非通用微动效
- 背景：使用渐变、形状或微妙图案营造氛围

---

## 3. 具体技术实现

### 3.1 指令模板渲染流程

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 会话初始化/模型切换                                          │
│     Codex::spawn_internal()                                      │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 获取模型信息                                                 │
│     models_manager.get_model_info(model, &config)                │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 解析 base_instructions 优先级                               │
│     config.base_instructions                                     │
│     -> conversation_history.get_base_instructions()             │
│     -> model_info.get_model_instructions(config.personality)    │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. 模板渲染（关键步骤）                                         │
│     ModelInfo::get_model_instructions(personality)              │
│     -> 检查 model_messages.instructions_template                │
│     -> 替换 {{ personality }} 占位符                            │
│     -> 返回最终指令文本                                          │
└──────────────────────────────────┬──────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. 存储到会话配置                                               │
│     session_configuration.base_instructions = base_instructions │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 ModelInfo（协议层）

```rust
// codex-rs/protocol/src/openai_models.rs
pub struct ModelInfo {
    pub slug: String,
    pub base_instructions: String,           // 基础指令（后备）
    pub model_messages: Option<ModelMessages>, // 模板化指令
    // ... 其他字段
}

impl ModelInfo {
    pub fn get_model_instructions(&self, personality: Option<Personality>) -> String {
        if let Some(model_messages) = &self.model_messages
            && let Some(template) = &model_messages.instructions_template
        {
            // 使用模板 + 个性替换
            let personality_message = model_messages
                .get_personality_message(personality)
                .unwrap_or_default();
            template.replace(PERSONALITY_PLACEHOLDER, personality_message.as_str())
        } else {
            // 后备：使用基础指令
            self.base_instructions.clone()
        }
    }
}
```

#### 3.2.2 ModelMessages（模板定义）

```rust
pub struct ModelMessages {
    pub instructions_template: Option<String>,      // 含 {{ personality }} 的模板
    pub instructions_variables: Option<ModelInstructionsVariables>, // 个性变量
}

pub struct ModelInstructionsVariables {
    pub personality_default: Option<String>,   // 默认个性（空字符串）
    pub personality_friendly: Option<String>,  // Friendly 个性片段
    pub personality_pragmatic: Option<String>, // Pragmatic 个性片段
}
```

#### 3.2.3 本地模型配置（core 层）

```rust
// codex-rs/core/src/models_manager/model_info.rs
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
const LOCAL_FRIENDLY_TEMPLATE: &str = "You optimize for team morale...";
const LOCAL_PRAGMATIC_TEMPLATE: &str = "You are a deeply pragmatic...";
const PERSONALITY_PLACEHOLDER: &str = "{{ personality }}";

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

### 3.3 指令注入流程

#### 3.3.1 API 请求构建

```rust
// codex-rs/core/src/client.rs::build_responses_request()
let instructions = &prompt.base_instructions.text;  // 来自模板渲染结果
let request = ResponsesApiRequest {
    model: model_info.slug.clone(),
    instructions: instructions.clone(),  // 注入到 API 请求
    input,
    tools,
    // ...
};
```

#### 3.3.2 Prompt 结构

```rust
// codex-rs/core/src/client_common.rs
pub struct Prompt {
    pub input: Vec<ResponseItem>,
    pub tools: Vec<ToolSpec>,
    pub base_instructions: BaseInstructions,  // 渲染后的指令
    pub personality: Option<Personality>,
    pub output_schema: Option<Value>,
}
```

### 3.4 模型切换时的指令更新

```rust
// codex-rs/core/src/context_manager/updates.rs
pub(crate) fn build_model_instructions_update_item(
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions> {
    let previous_turn_settings = previous_turn_settings?;
    if previous_turn_settings.model == next.model_info.slug {
        return None;  // 模型未变更，无需更新
    }

    let model_instructions = next.model_info.get_model_instructions(next.personality);
    if model_instructions.is_empty() {
        return None;
    }

    Some(DeveloperInstructions::model_switch_message(model_instructions))
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 模板文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md` | **本文件**：GPT-5.2-Codex 模型指令模板 |
| `codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md` | Friendly 个性片段 |
| `codex-rs/core/templates/personalities/gpt-5.2-codex_pragmatic.md` | Pragmatic 个性片段 |
| `codex-rs/core/prompt.md` | 基础指令（BASE_INSTRUCTIONS） |
| `codex-rs/protocol/src/prompts/base_instructions/default.md` | 协议层默认基础指令 |

### 4.2 核心代码文件

| 文件路径 | 关键功能 |
|----------|----------|
| `codex-rs/core/src/models_manager/model_info.rs:17-110` | `BASE_INSTRUCTIONS` 定义、`local_personality_messages_for_slug()` 函数 |
| `codex-rs/protocol/src/openai_models.rs:242-336` | `ModelInfo` 结构体、`get_model_instructions()` 方法 |
| `codex-rs/protocol/src/openai_models.rs:338-394` | `ModelMessages`、`ModelInstructionsVariables` 定义 |
| `codex-rs/core/src/codex.rs:520-529` | base_instructions 优先级解析逻辑 |
| `codex-rs/core/src/codex.rs:568-595` | `SessionConfiguration` 构建，包含 base_instructions |
| `codex-rs/core/src/client_common.rs:26-46` | `Prompt` 结构体定义 |
| `codex-rs/core/src/client.rs:682-748` | `build_responses_request()`，将指令注入 API 请求 |
| `codex-rs/core/src/context_manager/updates.rs:141-158` | `build_model_instructions_update_item()`，模型切换时更新指令 |

### 4.3 测试文件

| 文件路径 | 测试覆盖 |
|----------|----------|
| `codex-rs/core/tests/suite/personality.rs` | 个性系统完整测试（901 行） |
| `codex-rs/protocol/src/openai_models.rs:514-776` | `ModelInfo` 单元测试 |
| `codex-rs/core/src/models_manager/model_info_tests.rs` | 模型信息本地覆盖测试 |
| `codex-rs/core/tests/suite/collaboration_instructions.rs` | 协作模式指令测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
gpt-5.2-codex_instructions_template.md
    ├── 被读取并嵌入到：codex-rs/core/src/models_manager/model_info.rs
    │   └── 通过 BASE_INSTRUCTIONS 常量（prompt.md）
    │
    ├── 个性片段依赖：
    │   ├── gpt-5.2-codex_friendly.md
    │   └── gpt-5.2-codex_pragmatic.md
    │
    └── 模板渲染由：
        ├── ModelInfo::get_model_instructions() 执行
        └── 通过 PERSONALITY_PLACEHOLDER 替换
```

### 5.2 协议层依赖

```rust
// codex-rs/protocol/src/models.rs
pub struct BaseInstructions {
    pub text: String,  // 存储渲染后的指令
}

pub struct DeveloperInstructions {
    text: String,  // 用于模型切换时的开发者消息
}
```

### 5.3 API 交互

渲染后的指令通过 OpenAI Responses API 发送：

```rust
// API 请求结构
ResponsesApiRequest {
    model: "gpt-5.2-codex",
    instructions: "渲染后的完整指令文本",  // <-- 本模板的最终输出
    input: [...],  // 对话历史
    tools: [...],
    // ...
}
```

### 5.4 配置系统交互

| 配置项 | 作用 |
|--------|------|
| `Config::base_instructions` | 用户自定义指令覆盖 |
| `Config::model_instructions_file` | 从文件加载指令 |
| `Config::personality` | 选择 Friendly/Pragmatic/None |
| `Feature::Personality` | 个性功能开关 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 模板注入风险

- **风险**：`{{ personality }}` 占位符替换失败时，可能导致占位符原样输出到模型
- **缓解**：`get_model_instructions()` 方法中使用 `unwrap_or_default()` 确保空字符串替换

#### 6.1.2 指令覆盖优先级混淆

- **风险**：base_instructions 的三层优先级（config -> history -> model）可能导致用户困惑
- **代码位置**：`codex-rs/core/src/codex.rs:520-529`
- **建议**：添加调试日志明确显示最终指令来源

#### 6.1.3 远程模型与本地模板不一致

- **风险**：远程模型返回的 `model_messages` 与本地硬编码模板可能冲突
- **缓解**：`with_config_overrides()` 函数处理配置覆盖逻辑

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| `personality: None` | 使用 `personality_default`（空字符串），保留占位符位置但无内容 |
| `Feature::Personality` 禁用 | 忽略个性设置，直接使用 `base_instructions` |
| `model_messages: None` | 回退到 `base_instructions`，无个性支持 |
| `instructions_variables` 不完整 | 缺失的个性返回 `None`，替换为空字符串 |
| 模型切换 | 通过 `build_model_instructions_update_item` 生成开发者消息通知模型 |

### 6.3 改进建议

#### 6.3.1 模板版本管理

当前模板与代码强耦合，建议：
- 添加模板版本号字段，支持远程模板热更新
- 实现模板兼容性检查机制

```rust
pub struct ModelMessages {
    pub instructions_template: Option<String>,
    pub instructions_variables: Option<ModelInstructionsVariables>,
    pub template_version: Option<String>, // 新增
}
```

#### 6.3.2 指令调试工具

开发者和高级用户需要查看最终渲染的指令：
- 添加 CLI 命令如 `codex debug instructions` 输出完整指令
- 在日志中记录指令来源（config override / history / model default）

#### 6.3.3 多语言支持

当前模板仅支持英文，建议：
- 将模板提取到可本地化资源文件
- 支持 `instructions_locale` 配置项

#### 6.3.4 模板验证

在构建时验证模板完整性：
- 检查 `{{ personality }}` 占位符是否存在（如预期使用）
- 验证模板语法（防止意外 Markdown 解析问题）

#### 6.3.5 个性化扩展

当前仅支持两种预设个性，建议：
- 支持用户自定义个性片段
- 允许通过配置文件注入额外个性变量

```toml
[personalities.custom]
name = "Custom Personality"
template = "You are a specialized agent for..."
```

### 6.4 测试覆盖建议

当前测试主要集中在 `personality.rs`，建议补充：
- 模板渲染性能测试（大模板场景）
- 边界条件测试（空模板、缺失变量等）
- 多模型指令隔离测试

---

## 附录：相关配置示例

### 启用个性功能并选择 Friendly

```toml
# ~/.codex/config.toml
[features]
personality = true

[profile.default]
personality = "friendly"
```

### 自定义指令文件

```toml
# ~/.codex/config.toml
model_instructions_file = "~/.codex/custom_instructions.md"
```

### 完全覆盖指令（不推荐）

```toml
# ~/.codex/config.toml
base_instructions = "You are a custom agent..."
```

---

*文档生成时间：2026-03-23*
*基于代码版本：codex-rs 最新主干*
