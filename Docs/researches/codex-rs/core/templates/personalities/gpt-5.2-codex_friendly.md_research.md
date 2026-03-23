# gpt-5.2-codex_friendly.md 深度研究文档

## 文件基本信息

- **文件路径**: `codex-rs/core/templates/personalities/gpt-5.2-codex_friendly.md`
- **文件大小**: 2068 bytes
- **文件类型**: Markdown 模板文件
- **所属模块**: codex-core / Model Personalities

---

## 场景与职责

### 核心定位

该文件是 Codex CLI 的**人格化（Personality）系统**的核心模板文件之一，定义了名为 "Friendly"（友好型）的 AI 助手人格。这是 GPT-5.2 Codex 模型的两种内置人格之一，与 "Pragmatic"（务实型）人格形成互补。

### 业务场景

1. **用户体验定制**: 允许用户根据偏好选择 AI 助手的沟通风格
2. **团队协作优化**: 特别适合配对编程、新人入职、技术 unblock 等需要高情感支持的场景
3. **情绪价值提供**: 在复杂技术任务中降低用户焦虑，提升持续动力

### 使用场景示例

- 新开发者学习代码库时需要耐心指导
- 团队 morale 较低时需要鼓励性反馈
- 复杂调试过程中需要情感支持
- 代码审查时需要建设性而非批判性的反馈

---

## 功能点目的

### 1. 人格定义的三层结构

| 层级 | 内容 | 目的 |
|------|------|------|
| **核心定位** | "优化团队士气，成为支持性队友" | 确立最高优先级价值观 |
| **价值观体系** | Empathy + Collaboration + Ownership | 提供行为准则框架 |
| **交互规范** | 温暖、鼓励、对话式的语调 | 具体化沟通风格 |

### 2. 关键行为约束

- **禁止行为**: "NEVER curt or dismissive"（绝不简短或轻蔑）
- **强制行为**: "patient and enjoyable collaborator"（耐心且愉快的协作者）
- **升级策略**: "escalate gently and deliberately"（温和而审慎地升级）

### 3. 与 Pragmatic 人格的差异化

| 维度 | Friendly | Pragmatic |
|------|----------|-----------|
| 首要目标 | 团队士气 + 代码质量 | 工程效率 + 技术严谨 |
| 沟通风格 | 温暖、鼓励、使用 "we/let's" | 简洁、直接、聚焦任务 |
| 反馈方式 | 肯定进步，用好奇替代评判 | 承认优秀工作，避免过度激励 |
| 适用场景 | 学习、配对、unblock | 快速迭代、技术决策 |

---

## 具体技术实现

### 1. 模板集成架构

```
模型指令模板 (gpt-5.2-codex_instructions_template.md)
    │
    ├── 基础指令 (BASE_INSTRUCTIONS) - prompt.md
    │
    └── {{ personality }} 占位符
            │
            ├── Friendly 人格 → gpt-5.2-codex_friendly.md 内容
            │
            └── Pragmatic 人格 → gpt-5.2-codex_pragmatic.md 内容
```

### 2. 代码层面的集成点

**文件**: `codex-rs/core/src/models_manager/model_info.rs`

```rust
const LOCAL_FRIENDLY_TEMPLATE: &str =
    "You optimize for team morale and being a supportive teammate as much as code quality.";

fn local_personality_messages_for_slug(slug: &str) -> Option<ModelMessages> {
    match slug {
        "gpt-5.2-codex" | "exp-codex-personality" => Some(ModelMessages {
            instructions_template: Some(format!(
                "{DEFAULT_PERSONALITY_HEADER}\n\n{PERSONALITY_PLACEHOLDER}\n\n{BASE_INSTRUCTIONS}"
            )),
            instructions_variables: Some(ModelInstructionsVariables {
                personality_default: Some(String::new()),
                personality_friendly: Some(LOCAL_FRIENDLY_TEMPLATE.to_string()),  // ← 引用 friendly 人格
                personality_pragmatic: Some(LOCAL_PRAGMATIC_TEMPLATE.to_string()),
            }),
        }),
        _ => None,
    }
}
```

### 3. 运行时人格切换机制

**文件**: `codex-rs/core/src/context_manager/updates.rs`

```rust
fn build_personality_update_item(
    previous: Option<&TurnContextItem>,
    next: &TurnContext,
    personality_feature_enabled: bool,
) -> Option<DeveloperInstructions> {
    if !personality_feature_enabled {
        return None;
    }
    // ... 检测人格变化
    if let Some(personality) = next.personality
        && next.personality != previous.personality
    {
        let personality_message = personality_message_for(model_info, personality);
        personality_message.map(DeveloperInstructions::personality_spec_message)
    }
}
```

### 4. 数据结构定义

**文件**: `codex-rs/protocol/src/config_types.rs`

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum Personality {
    None,
    Friendly,      // ← 对应本文件
    Pragmatic,
}
```

**文件**: `codex-rs/protocol/src/openai_models.rs`

```rust
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelInstructionsVariables {
    pub personality_default: Option<String>,
    pub personality_friendly: Option<String>,   // ← Friendly 人格内容
    pub personality_pragmatic: Option<String>,
}
```

### 5. 配置系统集成

**文件**: `codex-rs/core/src/config/mod.rs`

```rust
pub struct Config {
    // ...
    /// Optionally specify the personality of the model
    pub personality: Option<Personality>,
    // ...
}
```

配置优先级（从高到低）：
1. 运行时覆盖 (`ConfigOverrides`)
2. Profile 配置 (`config_profile.personality`)
3. 全局配置 (`cfg.personality`)
4. 默认值（无配置时为 Pragmatic）

---

## 关键代码路径与文件引用

### 核心文件依赖图

```
gpt-5.2-codex_friendly.md
    │
    ├── 被引用
    │   ├── codex-rs/core/src/models_manager/model_info.rs
    │   │   └── LOCAL_FRIENDLY_TEMPLATE 常量（首行摘要）
    │   │
    │   └── codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md
    │       └── {{ personality }} 占位符替换
    │
    ├── 配置定义
    │   ├── codex-rs/protocol/src/config_types.rs
    │   │   └── Personality::Friendly 枚举
    │   │
    │   └── codex-rs/protocol/src/openai_models.rs
    │       └── ModelInstructionsVariables::personality_friendly
    │
    ├── 运行时处理
    │   ├── codex-rs/core/src/codex.rs
    │   │   ├── TurnContext::personality 字段
    │   │   └── personality 变更处理逻辑
    │   │
    │   └── codex-rs/core/src/context_manager/updates.rs
    │       └── build_personality_update_item()
    │
    └── 测试覆盖
        └── codex-rs/core/tests/suite/personality.rs
            └── 完整的人格功能测试套件
```

### 关键代码路径

1. **初始化路径**:
   ```
   Config::load() → model_info_from_slug() → local_personality_messages_for_slug()
   ```

2. **指令生成路径**:
   ```
   get_model_instructions() → template.replace(PERSONALITY_PLACEHOLDER, personality_message)
   ```

3. **运行时切换路径**:
   ```
   Op::OverrideTurnContext { personality } → build_personality_update_item() → DeveloperInstructions::personality_spec_message()
   ```

---

## 依赖与外部交互

### 1. 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `codex_protocol::config_types::Personality` | 人格枚举定义 |
| `codex_protocol::openai_models::ModelInstructionsVariables` | 人格内容存储结构 |
| `codex_core::features::Feature::Personality` | 功能开关控制 |
| `codex_core::config::Config` | 用户配置存储 |

### 2. 外部依赖

| 依赖 | 用途 |
|------|------|
| 远程模型元数据 API | 支持远程定义的人格模板 |
| config.toml 用户配置 | 持久化用户人格偏好 |

### 3. 配置示例

```toml
# ~/.codex/config.toml
personality = "friendly"  # 或 "pragmatic" / "none"

[profile.work]
personality = "pragmatic"

[profile.mentoring]
personality = "friendly"
```

### 4. 与 Feature Flag 的关系

人格功能受 `Feature::Personality` 控制：

```rust
// codex-rs/core/src/models_manager/model_info.rs
if !config.features.enabled(Feature::Personality) {
    model.model_messages = None;  // 禁用人格模板
}
```

---

## 风险、边界与改进建议

### 1. 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **人格提示注入** | 恶意用户可能通过输入操控人格行为 | 人格内容作为系统指令，用户输入在后续处理 |
| **人格与功能冲突** | 某些工具（如代码审查）可能需要更直接的风格 | 支持按场景覆盖人格 |
| **多语言支持缺失** | 当前仅英文模板 | 需要 i18n 框架支持 |
| **人格漂移** | 长会话中模型可能逐渐偏离定义的人格 | 定期通过 `build_personality_update_item` 强化 |

### 2. 边界条件

1. **模型兼容性**: 仅 `gpt-5.2-codex` 和 `exp-codex-personality` 支持本地人格模板
2. **配置覆盖**: `base_instructions` 显式设置时会禁用人格模板
3. **功能开关**: `Feature::Personality` 未启用时，人格设置被忽略
4. **远程模板**: 远程模型元数据可覆盖本地人格定义

### 3. 改进建议

#### 短期改进

1. **增强测试覆盖**
   - 添加人格一致性测试（长会话中人格稳定性）
   - 添加人格切换边界测试（快速连续切换）

2. **配置验证**
   - 在 `config.toml` 解析时验证人格值的有效性
   - 提供人格预览功能（"这是 Friendly 人格的示例回复"）

#### 中期改进

3. **动态人格调整**
   - 支持基于任务类型的自动人格切换（如代码审查时自动切换到 Pragmatic）
   - 支持用户自定义人格（在 Friendly/Pragmatic 基础上微调）

4. **多语言支持**
   - 添加 `gpt-5.2-codex_friendly_zh.md` 等本地化模板
   - 根据用户系统语言自动选择人格语言

#### 长期改进

5. **人格效果度量**
   - 收集匿名反馈评估人格效果
   - A/B 测试不同人格描述的效果

6. **更细粒度的人格控制**
   - 支持维度化人格（温暖度 × 直接度 × 技术深度）
   - 支持场景特定人格（代码审查人格、调试人格、学习人格）

### 4. 相关测试

**核心测试文件**: `codex-rs/core/tests/suite/personality.rs`

关键测试用例：
- `personality_does_not_mutate_base_instructions_without_template` - 无模板时不影响基础指令
- `config_personality_some_sets_instructions_template` - 配置人格正确设置模板
- `default_personality_is_pragmatic_without_config_toml` - 默认人格为 Pragmatic
- `user_turn_personality_some_adds_update_message` - 人格切换时发送更新消息
- `remote_model_friendly_personality_instructions_with_feature` - 远程模型人格支持

---

## 总结

`gpt-5.2-codex_friendly.md` 是 Codex CLI 人格化系统的核心组成部分，定义了温暖、支持性的 AI 助手人格。它通过模板替换机制集成到模型指令中，支持配置持久化和运行时切换。该文件与 `gpt-5.2-codex_pragmatic.md` 共同构成了 Codex 的双人格体系，让用户可以根据场景选择最适合的交互风格。
