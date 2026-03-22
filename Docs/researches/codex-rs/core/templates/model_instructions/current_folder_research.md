# 研究文档：codex-rs/core/templates/model_instructions

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/core/templates/model_instructions` 是 Codex CLI 项目中负责**模型指令模板**的核心目录。该目录包含用于 GPT-5.2 Codex 模型的指令模板文件，定义了 AI 助手的行为规范、输出格式和交互风格。

### 1.2 核心职责

该目录及其相关系统承担以下关键职责：

| 职责领域 | 说明 |
|---------|------|
| **基础指令模板** | 提供模型的基础行为指令，包括编码规范、响应格式、工具使用规则 |
| **人格化配置** | 支持不同人格风格（友好型/务实型）的指令注入 |
| **动态指令生成** | 通过模板引擎（Handlebars 风格）动态组装最终指令 |
| **模型切换支持** | 在会话中切换模型时，动态更新指令上下文 |

### 1.3 使用场景

1. **会话初始化**：当用户启动 Codex CLI 时，系统根据配置加载对应模型的指令模板
2. **模型切换**：用户在会话中切换模型（如从 gpt-5.2 切换到 gpt-5.4）时，动态更新指令
3. **人格切换**：用户切换人格风格（friendly/pragmatic/none）时，注入对应的人格指令
4. **自定义指令**：通过 `model_instructions_file` 配置加载用户自定义指令文件

---

## 功能点目的

### 2.1 指令模板系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    模型指令生成流程                               │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐  │
│  │ 基础指令模板  │───▶│ 人格指令注入  │───▶│ 最终模型指令      │  │
│  │ (templates)  │    │ (personality)│    │ (base_instructions)│ │
│  └──────────────┘    └──────────────┘    └──────────────────┘  │
│         │                   │                                    │
│         ▼                   ▼                                    │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │ model.json   │    │ personality  │                           │
│  │ 远程配置     │    │ _default/friendly/                       │
│  │              │    │ _pragmatic.md                            │
│  └──────────────┘    └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 核心功能点

#### 2.2.1 基础指令模板 (`gpt-5.2-codex_instructions_template.md`)

**文件路径**: `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md`

**核心内容结构**:
- **身份定义**：明确 Codex 是基于 GPT-5 的编码助手
- **用户交互规范**：终端交互规则、Markdown 格式化、文件引用规范
- **编辑约束**：ASCII 默认、代码注释规范、Git 工作流规则
- **计划工具使用**：何时使用/不使用计划工具的判断标准
- **前端任务规范**：避免"AI slop"的设计原则
- **特殊用户请求处理**：简单请求、代码审查、前端设计等场景

**关键指令片段**:
```markdown
You are Codex, a coding agent based on GPT-5. You and the user share the same workspace and collaborate to achieve the user's goals.

{{ personality }}

# Working with the user
...
```

#### 2.2.2 人格指令系统

**文件位置**:
- `codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md`
- `codex-rs/core/templates/personalities/gpt-5.2-codex_pragmatic.md`

**人格类型对比**:

| 特性 | Friendly | Pragmatic |
|-----|----------|-----------|
| **核心定位** | 团队士气优化者 | 务实软件工程师 |
| **沟通风格** | 温暖、鼓励性、对话式 | 简洁、高效、直接 |
| **价值观** | Empathy, Collaboration, Ownership | Clarity, Pragmatism, Rigor |
| **适用场景** | 配对编程、新人培训、困难任务 | 快速迭代、技术决策、代码审查 |

#### 2.2.3 动态指令组装

**占位符机制**:
- `{{ personality }}`：人格指令占位符，在运行时被替换为对应人格的 Markdown 内容

**组装流程**:
1. 加载基础模板（包含 `{{ personality }}` 占位符）
2. 根据配置选择人格（friendly/pragmatic/none/default）
3. 替换占位符为对应人格指令
4. 生成最终 `base_instructions` 发送给模型

---

## 具体技术实现

### 3.1 数据结构定义

#### 3.1.1 ModelMessages（协议层）

**文件**: `codex-rs/protocol/src/openai_models.rs`

```rust
/// 模型指令和开发者消息的强类型模板
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelMessages {
    pub instructions_template: Option<String>,  // 包含 {{ personality }} 占位符的模板
    pub instructions_variables: Option<ModelInstructionsVariables>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelInstructionsVariables {
    pub personality_default: Option<String>,
    pub personality_friendly: Option<String>,
    pub personality_pragmatic: Option<String>,
}
```

#### 3.1.2 ModelInfo（模型元数据）

```rust
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelInfo {
    pub slug: String,                          // 模型标识，如 "gpt-5.2-codex"
    pub base_instructions: String,             // 后备基础指令
    pub model_messages: Option<ModelMessages>, // 指令模板和变量
    pub supports_personality: bool,            // 是否支持人格化
    // ... 其他字段
}
```

### 3.2 核心算法流程

#### 3.2.1 指令生成算法

**文件**: `codex-rs/protocol/src/openai_models.rs` (lines 316-336)

```rust
impl ModelInfo {
    pub fn get_model_instructions(&self, personality: Option<Personality>) -> String {
        if let Some(model_messages) = &self.model_messages
            && let Some(template) = &model_messages.instructions_template
        {
            // 使用模板替换占位符
            let personality_message = model_messages
                .get_personality_message(personality)
                .unwrap_or_default();
            template.replace(PERSONALITY_PLACEHOLDER, personality_message.as_str())
        } else if let Some(personality) = personality {
            // 警告：模型不支持人格化但请求了人格
            warn!(...);
            self.base_instructions.clone()
        } else {
            // 无模板，使用基础指令
            self.base_instructions.clone()
        }
    }
}
```

#### 3.2.2 人格消息选择算法

```rust
impl ModelInstructionsVariables {
    pub fn get_personality_message(&self, personality: Option<Personality>) -> Option<String> {
        if let Some(personality) = personality {
            match personality {
                Personality::None => Some(String::new()),
                Personality::Friendly => self.personality_friendly.clone(),
                Personality::Pragmatic => self.personality_pragmatic.clone(),
            }
        } else {
            self.personality_default.clone()
        }
    }
}
```

### 3.3 配置加载流程

#### 3.3.1 配置优先级（从高到低）

```
1. CLI 覆盖参数 (--instructions)
2. 配置文件中的 base_instructions
3. 配置文件中的 model_instructions_file 指向的文件
4. 模型元数据中的 model_messages（远程或本地）
5. 模型元数据中的 base_instructions（后备）
```

**代码实现**: `codex-rs/core/src/codex.rs` (lines 520-529)

```rust
// 基础指令解析优先级：
// 1. config.base_instructions 覆盖
// 2. conversation history => session_meta.base_instructions
// 3. 当前模型的 base_instructions
let base_instructions = config
    .base_instructions
    .clone()
    .or_else(|| conversation_history.get_base_instructions().map(|s| s.text))
    .unwrap_or_else(|| model_info.get_model_instructions(config.personality));
```

#### 3.3.2 配置文件处理

**文件**: `codex-rs/core/src/config/mod.rs` (lines 2515-2521)

```rust
// 从配置文件加载 model_instructions_file
let model_instructions_path = config_profile
    .model_instructions_file
    .as_ref()
    .or(cfg.model_instructions_file.as_ref());
let file_base_instructions =
    Self::try_read_non_empty_file(model_instructions_path, "model instructions file")?;
let base_instructions = base_instructions.or(file_base_instructions);
```

### 3.4 模型切换时的指令更新

#### 3.4.1 更新检测逻辑

**文件**: `codex-rs/core/src/context_manager/updates.rs` (lines 141-158)

```rust
pub(crate) fn build_model_instructions_update_item(
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions> {
    let previous_turn_settings = previous_turn_settings?;
    // 检测模型是否变化
    if previous_turn_settings.model == next.model_info.slug {
        return None;
    }

    let model_instructions = next.model_info.get_model_instructions(next.personality);
    if model_instructions.is_empty() {
        return None;
    }

    Some(DeveloperInstructions::model_switch_message(model_instructions))
}
```

#### 3.4.2 开发者消息构造

```rust
impl DeveloperInstructions {
    pub fn model_switch_message(model_instructions: String) -> Self {
        DeveloperInstructions::new(format!(
            "<model_switch>\nThe user was previously using a different model. \
             Please continue the conversation according to the following instructions:\n\n\
             {model_instructions}\n</model_switch>"
        ))
    }
}
```

---

## 关键代码路径与文件引用

### 4.1 核心文件清单

| 类别 | 文件路径 | 职责 |
|-----|---------|------|
| **模板文件** | `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md` | GPT-5.2 基础指令模板 |
| **人格文件** | `codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md` | 友好型人格指令 |
| **人格文件** | `codex-rs/core/templates/personalities/gpt-5.2-codex_pragmatic.md` | 务实型人格指令 |
| **协议定义** | `codex-rs/protocol/src/openai_models.rs` | ModelMessages/ModelInfo 定义 |
| **协议定义** | `codex-rs/protocol/src/models.rs` | DeveloperInstructions 定义 |
| **模型管理** | `codex-rs/core/src/models_manager/model_info.rs` | 本地模型元数据构造 |
| **模型管理** | `codex-rs/core/src/models_manager/manager.rs` | 模型信息获取和缓存 |
| **会话核心** | `codex-rs/core/src/codex.rs` | 基础指令解析和会话初始化 |
| **上下文更新** | `codex-rs/core/src/context_manager/updates.rs` | 模型切换时的指令更新 |
| **配置加载** | `codex-rs/core/src/config/mod.rs` | model_instructions_file 处理 |
| **配置定义** | `codex-rs/core/src/config/profile.rs` | ConfigProfile 定义 |
| **模型数据** | `codex-rs/core/models.json` | 内置模型元数据（含指令模板） |

### 4.2 关键代码路径

#### 4.2.1 会话启动时的指令加载

```
Codex::spawn()
  └─▶ spawn_internal()
      └─▶ models_manager.get_model_info(model, &config)
          └─▶ construct_model_info_from_candidates()
              └─▶ model_info::with_config_overrides()  [应用配置覆盖]
      └─▶ // 基础指令优先级解析 (lines 524-529)
          let base_instructions = config.base_instructions
              .or_else(|| conversation_history.get_base_instructions())
              .unwrap_or_else(|| model_info.get_model_instructions(config.personality));
```

#### 4.2.2 模型切换时的指令更新

```
Session::handle_user_turn()
  └─▶ build_settings_update_items()
      └─▶ build_model_instructions_update_item(previous, next)
          └─▶ next.model_info.get_model_instructions(next.personality)
              └─▶ template.replace(PERSONALITY_PLACEHOLDER, personality_message)
      └─▶ DeveloperInstructions::model_switch_message(instructions)
```

#### 4.2.3 人格切换时的指令更新

```
build_personality_update_item()
  └─▶ personality_message_for(model_info, personality)
      └─▶ model_info.model_messages.get_personality_message(Some(personality))
          └─▶ ModelInstructionsVariables.get_personality_message()
  └─▶ DeveloperInstructions::personality_spec_message(spec)
```

### 4.3 配置 Schema

**文件**: `codex-rs/core/config.schema.json`

```json
{
  "model_instructions_file": {
    "description": "Optional path to a file containing model instructions.",
    "type": "string"
  }
}
```

**ConfigProfile 定义** (`codex-rs/core/src/config/profile.rs`):

```rust
pub struct ConfigProfile {
    // ... 其他字段
    /// Optional path to a file containing model instructions.
    pub model_instructions_file: Option<AbsolutePathBuf>,
    /// Deprecated: ignored. Use `model_instructions_file`.
    #[schemars(skip)]
    pub experimental_instructions_file: Option<AbsolutePathBuf>,
}
```

---

## 依赖与外部交互

### 5.1 内部依赖关系

```
codex-rs/core/templates/model_instructions/
  │
  ├─▶ codex-rs/protocol/src/openai_models.rs  [ModelMessages, ModelInfo]
  ├─▶ codex-rs/protocol/src/models.rs          [DeveloperInstructions]
  ├─▶ codex-rs/core/src/models_manager/        [模型元数据管理]
  ├─▶ codex-rs/core/src/codex.rs               [会话初始化和指令解析]
  ├─▶ codex-rs/core/src/context_manager/       [上下文更新]
  └─▶ codex-rs/core/src/config/                [配置加载]
```

### 5.2 外部交互

#### 5.2.1 远程模型元数据

**端点**: `/models` (通过 `codex-api` 调用)

**响应结构**:
```json
{
  "models": [
    {
      "slug": "gpt-5.2-codex",
      "base_instructions": "...",
      "model_messages": {
        "instructions_template": "...{{ personality }}...",
        "instructions_variables": {
          "personality_default": "",
          "personality_friendly": "...",
          "personality_pragmatic": "..."
        }
      }
    }
  ]
}
```

**缓存机制**:
- 缓存文件: `~/.codex/models_cache.json`
- TTL: 300 秒 (`DEFAULT_MODEL_CACHE_TTL`)

#### 5.2.2 用户自定义指令文件

**配置方式**:

```toml
# ~/.codex/config.toml
model_instructions_file = "/path/to/custom_instructions.md"

# 或在 profile 中
[profiles.work]
model_instructions_file = "/path/to/work_instructions.md"
```

**加载优先级**:
1. Profile 级别的 `model_instructions_file`
2. 全局 `model_instructions_file`
3. 内置或远程模型元数据

### 5.3 相关 Feature Flags

| Feature | 说明 |
|--------|------|
| `Personality` | 启用人格化指令系统 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 指令注入风险

**风险描述**: 用户通过 `model_instructions_file` 加载的自定义指令可能包含恶意内容，影响模型行为。

**缓解措施**:
- 指令文件仅影响当前用户会话
- 沙箱策略（SandboxPolicy）限制模型执行权限
- 审批策略（ApprovalPolicy）控制敏感操作

#### 6.1.2 人格化与基础指令冲突

**风险描述**: 当 `base_instructions` 被显式配置时，人格化模板会被禁用，可能导致用户困惑。

**代码体现** (`codex-rs/core/src/models_manager/model_info.rs` lines 50-55):
```rust
if let Some(base_instructions) = &config.base_instructions {
    model.base_instructions = base_instructions.clone();
    model.model_messages = None;  // 禁用模板系统
} else if !config.features.enabled(Feature::Personality) {
    model.model_messages = None;
}
```

#### 6.1.3 模型切换时的上下文丢失

**风险描述**: 切换模型时，新模型的指令可能与历史上下文不兼容。

**缓解措施**:
- 使用 `<model_switch>` 标签包裹切换指令
- 保留历史上下文，仅追加新指令

### 6.2 边界情况

#### 6.2.1 人格变量不完整

当 `ModelInstructionsVariables` 部分字段为 `None` 时：

```rust
// personality_friendly 为 None 时，Friendly 人格将返回空字符串
ModelInstructionsVariables {
    personality_default: Some("default".to_string()),
    personality_friendly: None,  // 缺失
    personality_pragmatic: Some("pragmatic".to_string()),
}
```

**处理逻辑**: 返回 `None`，最终使用空字符串替换占位符。

#### 6.2.2 未知模型回退

当使用未知模型 slug 时 (`codex-rs/core/src/models_manager/model_info.rs` lines 61-94):

```rust
pub(crate) fn model_info_from_slug(slug: &str) -> ModelInfo {
    warn!("Unknown model {slug} is used. This will use fallback model metadata.");
    ModelInfo {
        base_instructions: BASE_INSTRUCTIONS.to_string(),  // 使用内置后备指令
        model_messages: local_personality_messages_for_slug(slug),  // 尝试本地人格
        used_fallback_model_metadata: true,
        // ...
    }
}
```

#### 6.2.3 空指令处理

当 `model_instructions` 为空字符串时 (`updates.rs` lines 151-153):

```rust
let model_instructions = next.model_info.get_model_instructions(next.personality);
if model_instructions.is_empty() {
    return None;  // 不生成更新消息
}
```

### 6.3 改进建议

#### 6.3.1 模板系统增强

**现状**: 仅支持 `{{ personality }}` 单一占位符。

**建议**: 扩展模板变量系统，支持更多动态内容：
- `{{ cwd }}`：当前工作目录
- `{{ date }}`：当前日期
- `{{ tools }}`：可用工具列表
- `{{ sandbox_policy }}`：沙箱策略说明

#### 6.3.2 指令版本管理

**现状**: 指令模板随代码发布，更新需要升级 CLI。

**建议**: 
- 引入指令版本号
- 支持远程指令模板热更新
- 提供指令变更日志

#### 6.3.3 多模型指令对齐

**现状**: 不同模型的指令模板可能存在差异，切换时体验不一致。

**建议**:
- 建立统一的指令模板规范
- 提供模型间指令差异报告
- 支持用户定义的跨模型通用指令

#### 6.3.4 指令效果验证

**现状**: 自定义指令的效果难以预先验证。

**建议**:
- 添加指令预览功能（`--dry-run`）
- 提供指令 token 占用统计
- 指令语法校验（检查占位符是否正确）

#### 6.3.5 配置迁移提示

**现状**: `experimental_instructions_file` 已废弃，但用户可能仍在使用。

**建议**: 增强废弃提示，提供自动迁移工具：

```rust
// codex-rs/core/src/codex.rs lines 1549-1560
if crate::config::uses_deprecated_instructions_file(&config.config_layer_stack) {
    post_session_configured_events.push(Event {
        msg: EventMsg::DeprecationNotice(DeprecationNoticeEvent {
            summary: "`experimental_instructions_file` is deprecated...",
            details: Some("Move the setting to `model_instructions_file`..."),
        }),
    });
}
```

---

## 附录：关键常量定义

```rust
// codex-rs/protocol/src/openai_models.rs
const PERSONALITY_PLACEHOLDER: &str = "{{ personality }}";

// codex-rs/core/src/models_manager/model_info.rs
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
const LOCAL_FRIENDLY_TEMPLATE: &str = "You optimize for team morale...";
const LOCAL_PRAGMATIC_TEMPLATE: &str = "You are a deeply pragmatic...";
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/main*
