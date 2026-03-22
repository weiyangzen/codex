# Codex Core Templates Personalities 研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`codex-rs/core/templates/personalities/` 目录是 Codex CLI 项目中负责**模型人格（Personality）提示词模板**的核心配置目录。它定义了 AI 助手在与用户交互时可采用的两种主要沟通风格：

- **Friendly（友好型）**：温暖、支持性、鼓励性的沟通风格，优化团队协作和士气
- **Pragmatic（务实型）**：简洁、直接、高效的沟通风格，专注于任务完成和技术严谨性

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| TUI 交互 | 用户在终端界面中与 Codex 进行对话时，根据选择的 personality 呈现不同的沟通风格 |
| API 调用 | 通过 app-server 协议进行程序化调用时，可指定 personality 参数 |
| 模型切换 | 在会话中动态切换 personality，系统会发送 personality 更新消息给模型 |
| 新用户引导 | 对于已有会话历史的用户，系统会自动迁移并设置默认 personality 为 Pragmatic |

### 1.3 目录内容

```
codex-rs/core/templates/personalities/
├── gpt-5.2-codex_friendly.md      # 友好型人格提示词
└── gpt-5.2-codex_pragmatic.md     # 务实型人格提示词
```

---

## 功能点目的

### 2.1 核心功能

1. **人格提示词定义**：为 GPT-5.2-Codex 模型提供结构化的人格提示词模板
2. **动态注入**：通过模板占位符 `{{ personality }}` 在运行时注入到模型指令中
3. **用户偏好持久化**：支持用户选择并持久化 personality 偏好到配置文件
4. **向后兼容**：通过迁移机制为现有用户自动设置默认 personality

### 2.2 Personality 类型定义

```rust
// codex-rs/protocol/src/config_types.rs
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS, PartialOrd, Ord, EnumIter)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum Personality {
    None,       // 无特定人格，使用模型默认行为
    Friendly,   // 友好型：温暖、支持性、鼓励性
    Pragmatic,  // 务实型：简洁、直接、高效
}
```

### 2.3 功能特性开关

Personality 功能通过 `Feature::Personality` 特性开关控制：

```rust
// codex-rs/core/src/features.rs
pub enum Feature {
    // ...
    /// Enable personality selection in the TUI.
    Personality,
    // ...
}
```

---

## 具体技术实现

### 3.1 模板文件结构

#### 3.1.1 Friendly Personality (`gpt-5.2-codex_friendly.md`)

```markdown
# Personality

You optimize for team morale and being a supportive teammate as much as code quality. 
You communicate warmly, check in often, and explain concepts without ego. 
You excel at pairing, onboarding, and unblocking others. 
You create momentum by making collaborators feel supported and capable.

## Values
- Empathy: Interprets empathy as meeting people where they are...
- Collaboration: Sees collaboration as an active skill...
- Ownership: Takes responsibility not just for code, but for whether teammates are unblocked...

## Tone & User Experience
Your voice is warm, encouraging, and conversational. 
You use teamwork-oriented language such as "we" and "let's"...

## Escalation
You escalate gently and deliberately when decisions have non-obvious consequences...
```

#### 3.1.2 Pragmatic Personality (`gpt-5.2-codex_pragmatic.md`)

```markdown
# Personality

You are a deeply pragmatic, effective software engineer. 
You take engineering quality seriously, and collaboration is a kind of quiet joy...
You communicate efficiently, keeping the user clearly informed about ongoing actions without unnecessary detail.

## Values
- Clarity: You communicate reasoning explicitly and concretely...
- Pragmatism: You keep the end goal and momentum in mind...
- Rigor: You expect technical arguments to be coherent and defensible...

## Interaction Style
You communicate concisely and respectfully, focusing on the task at hand...

## Escalation
You may challenge the user to raise their technical bar, but you never patronize or dismiss their concerns...
```

### 3.2 模板注入机制

#### 3.2.1 指令模板结构

```rust
// codex-rs/core/src/models_manager/model_info.rs
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
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

#### 3.2.2 模型指令生成流程

```rust
// codex-rs/protocol/src/openai_models.rs
pub fn get_model_instructions(&self, personality: Option<Personality>) -> String {
    if let Some(model_messages) = &self.model_messages
        && let Some(template) = &model_messages.instructions_template
    {
        // 如果有模板，使用模板并替换 personality 占位符
        let personality_message = model_messages
            .get_personality_message(personality)
            .unwrap_or_default();
        template.replace(PERSONALITY_PLACEHOLDER, personality_message.as_str())
    } else if let Some(personality) = personality {
        // 回退到 base_instructions
        self.base_instructions.clone()
    } else {
        self.base_instructions.clone()
    }
}
```

### 3.3 Personality 消息获取逻辑

```rust
// codex-rs/protocol/src/openai_models.rs
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

### 3.4 运行时 Personality 更新

当用户在会话中切换 personality 时，系统会发送更新消息：

```rust
// codex-rs/core/src/codex.rs
if self.features.enabled(Feature::Personality)
    && let Some(personality) = turn_context.personality
{
    let model_info = turn_context.model_info.clone();
    let has_baked_personality = model_info.supports_personality()
        && base_instructions == model_info.get_model_instructions(Some(personality));
    if !has_baked_personality
        && let Some(personality_message) =
            crate::context_manager::updates::personality_message_for(&model_info, personality)
    {
        developer_sections.push(
            DeveloperInstructions::personality_spec_message(personality_message)
                .into_text(),
        );
    }
}
```

### 3.5 Personality 迁移机制

对于已有会话历史但没有明确设置 personality 的用户，系统会自动迁移：

```rust
// codex-rs/core/src/personality_migration.rs
pub async fn maybe_migrate_personality(
    codex_home: &Path,
    config_toml: &ConfigToml,
) -> io::Result<PersonalityMigrationStatus> {
    // 检查迁移标记文件
    let marker_path = codex_home.join(PERSONALITY_MIGRATION_FILENAME);
    if tokio::fs::try_exists(&marker_path).await? {
        return Ok(PersonalityMigrationStatus::SkippedMarker);
    }

    // 如果用户已明确设置 personality，跳过迁移
    if config_toml.personality.is_some() || config_profile.personality.is_some() {
        return Ok(PersonalityMigrationStatus::SkippedExplicitPersonality);
    }

    // 如果没有会话历史，跳过迁移
    if !has_recorded_sessions(codex_home, model_provider_id.as_str()).await? {
        return Ok(PersonalityMigrationStatus::SkippedNoSessions);
    }

    // 应用迁移：设置默认 personality 为 Pragmatic
    ConfigEditsBuilder::new(codex_home)
        .set_personality(Some(Personality::Pragmatic))
        .apply()
        .await?;

    Ok(PersonalityMigrationStatus::Applied)
}
```

---

## 关键代码路径与文件引用

### 4.1 核心数据类型定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs` | `Personality` 枚举定义（None/Friendly/Pragmatic） |
| `codex-rs/protocol/src/openai_models.rs` | `ModelMessages`, `ModelInstructionsVariables` 结构体，指令生成逻辑 |
| `codex-rs/core/src/features.rs` | `Feature::Personality` 特性开关定义 |

### 4.2 模板文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md` | 友好型人格提示词模板 |
| `codex-rs/core/templates/personalities/gpt-5.2-codex_pragmatic.md` | 务实型人格提示词模板 |
| `codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md` | 模型指令主模板，包含 `{{ personality }}` 占位符 |

### 4.3 模型信息管理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/models_manager/model_info.rs` | 本地 personality 模板绑定，`local_personality_messages_for_slug()` 函数 |
| `codex-rs/core/models.json` | 远程模型配置，包含 `personality_friendly` 和 `personality_pragmatic` 字段 |

### 4.4 运行时处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/codex.rs` | 会话管理，personality 更新检测与消息发送 |
| `codex-rs/core/src/context_manager/updates.rs` | `build_personality_update_item()`, `personality_message_for()` 函数 |
| `codex-rs/core/src/personality_migration.rs` | 现有用户的 personality 迁移逻辑 |

### 4.5 配置管理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/config/mod.rs` | `ConfigToml` 结构体，personality 字段定义 |
| `codex-rs/core/src/config/edit.rs` | `ConfigEdit::SetModelPersonality`，配置编辑操作 |
| `codex-rs/core/src/config/profile.rs` | `Profile` 结构体，profile 级 personality 配置 |

### 4.6 TUI 界面

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/app.rs` | `on_update_personality()`, `personality_label()` 函数 |
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget personality 状态管理 |
| `codex-rs/tui_app_server/src/app.rs` | App-server 模式的 personality 处理 |

### 4.7 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `ThreadStartParams`, `TurnStartParams` 中的 personality 字段 |
| `codex-rs/protocol/src/protocol.rs` | `Op::UserTurn`, `Op::OverrideTurnContext` 中的 personality 字段 |

### 4.8 测试

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/personality.rs` | Personality 功能的核心测试套件 |
| `codex-rs/core/tests/suite/personality_migration.rs` | 迁移逻辑测试 |
| `codex-rs/core/src/personality_migration_tests.rs` | 迁移单元测试 |

---

## 依赖与外部交互

### 5.1 内部依赖关系

```
personalities/ 模板文件
    ↑
    │ 被读取并嵌入到
    ↓
model_info.rs (local_personality_messages_for_slug)
    ↑
    │ 被引用生成
    ↓
ModelInfo::get_model_instructions()
    ↑
    │ 被调用于
    ↓
codex.rs (会话初始化/更新)
    ↑
    │ 通过事件通知
    ↓
TUI/App (用户界面)
```

### 5.2 配置层级

Personality 配置遵循以下优先级（从高到低）：

1. **运行时覆盖**：`Op::OverrideTurnContext` 中的 personality 参数
2. **用户配置**：`config.toml` 中的 `personality` 字段
3. **Profile 配置**：当前激活的 profile 中的 personality 设置
4. **默认值**：如果启用 Personality 特性，默认为 `Pragmatic`

### 5.3 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|---------|------|
| OpenAI API | 通过 `instructions` 字段 | Personality 提示词作为 system/developer 消息发送 |
| 远程模型配置 | `models.json` API | 远程模型可提供自定义 personality 模板 |
| 用户配置 | `config.toml` 文件 | 持久化用户的 personality 偏好 |
| TUI 界面 | 状态栏/设置面板 | 显示当前 personality，支持切换 |

### 5.4 远程模型支持

远程模型可通过 `models.json` 提供自定义 personality 配置：

```json
{
  "model_messages": {
    "instructions_template": "Base instructions\n{{ personality }}\n",
    "instructions_variables": {
      "personality_default": "Default personality text",
      "personality_friendly": "Friendly personality text",
      "personality_pragmatic": "Pragmatic personality text"
    }
  }
}
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 模型支持限制
- **风险**：并非所有模型都支持 personality 特性。如果模型不支持，`model_messages` 会被设置为 `None`，回退到 `base_instructions`
- **缓解**：通过 `ModelInfo::supports_personality()` 方法检测支持情况

#### 6.1.2 配置覆盖冲突
- **风险**：用户设置 `base_instructions` 会完全禁用 personality 模板机制
- **代码位置**：`model_info.rs:50-55`
- **缓解**：文档说明，引导用户使用 personality 而非直接覆盖 base_instructions

#### 6.1.3 迁移状态不一致
- **风险**：迁移标记文件 `.personality_migration` 存在但配置未实际应用
- **缓解**：迁移逻辑幂等，可安全重试

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| Personality::None | 返回空字符串，不添加任何 personality 提示词 |
| 特性开关关闭 | `model_messages` 被清空，使用 `base_instructions` |
| 模型切换 | 如果新模型支持 personality，会发送 model switch 消息 |
| 远程模型无 personality | 使用本地默认模板或 base_instructions |
| 会话恢复 | 从持久化状态恢复 personality 设置 |

### 6.3 改进建议

#### 6.3.1 模板管理优化
- **建议**：将 personality 模板从硬编码字符串迁移到独立的模板文件，支持热更新
- **收益**：无需重新编译即可调整 personality 提示词

#### 6.3.2 扩展 Personality 类型
- **建议**：考虑支持用户自定义 personality 或更多预设类型
- **实现**：在 `Personality` 枚举中添加 `Custom(String)` 变体

#### 6.3.3 增强测试覆盖
- **建议**：添加更多边界测试，如：
  - 特性开关动态切换
  - 远程模型 personality 模板不完整的情况
  - 多语言 personality 支持

#### 6.3.4 配置验证
- **建议**：在配置加载时验证 personality 值的有效性
- **实现**：在 `ConfigToml` 反序列化时添加验证逻辑

#### 6.3.5 UI/UX 改进
- **建议**：在 TUI 中提供更直观的 personality 切换界面，显示当前 personality 的简要描述
- **实现**：在状态栏或设置面板添加 personality 指示器和快速切换按钮

### 6.4 技术债务

1. **硬编码模型 slug**：`local_personality_messages_for_slug()` 中硬编码了 `"gpt-5.2-codex"` 和 `"exp-codex-personality"`，新增模型需要修改代码
2. **模板与代码耦合**：personality 模板内容分散在模板文件和代码中的 `LOCAL_FRIENDLY_TEMPLATE`/`LOCAL_PRAGMATIC_TEMPLATE` 常量
3. **迁移逻辑复杂**：personality 迁移涉及多个条件判断，逻辑较为复杂，建议简化或文档化

---

## 附录：关键常量与配置

### A.1 常量定义

```rust
// model_info.rs
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
const LOCAL_FRIENDLY_TEMPLATE: &str = "You optimize for team morale...";
const LOCAL_PRAGMATIC_TEMPLATE: &str = "You are a deeply pragmatic...";
const PERSONALITY_PLACEHOLDER: &str = "{{ personality }}";

// personality_migration.rs
const PERSONALITY_MIGRATION_FILENAME: &str = ".personality_migration";
```

### A.2 配置示例

```toml
# config.toml
[profile.default]
model = "gpt-5.2-codex"
personality = "pragmatic"  # 或 "friendly", "none"
```

### A.3 API 使用示例

```rust
// 启动线程时指定 personality
let params = ThreadStartParams {
    model: Some("gpt-5.2-codex".to_string()),
    personality: Some(Personality::Friendly),
    // ...
};

// 在会话中切换 personality
codex.submit(Op::OverrideTurnContext {
    personality: Some(Personality::Pragmatic),
    // ...
}).await?;
```

---

*文档生成时间：2026-03-22*
*研究范围：codex-rs/core/templates/personalities/ 及其相关依赖*
