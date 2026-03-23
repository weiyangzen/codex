# gpt-5.2-codex_pragmatic.md 深度研究文档

## 文件基本信息

- **文件路径**: `codex-rs/core/templates/personalities/gpt-5.2-codex_pragmatic.md`
- **文件大小**: 1851 bytes
- **文件类型**: Markdown 模板文件
- **所属模块**: codex-core / Model Personalities

---

## 场景与职责

### 核心定位

该文件是 Codex CLI 的**人格化（Personality）系统**的核心模板文件之一，定义了名为 "Pragmatic"（务实型）的 AI 助手人格。这是 GPT-5.2 Codex 模型的**默认人格**，与 "Friendly"（友好型）人格形成互补。

### 业务场景

1. **高效工程执行**: 适合需要快速推进的技术任务
2. **技术决策支持**: 提供清晰、可辩护的技术论证
3. **资深开发者协作**: 与经验丰富的开发者进行高效技术对话
4. **代码审查与重构**: 直接、聚焦问题的反馈风格

### 使用场景示例

- 紧急 bug 修复需要快速定位问题
- 技术方案评审需要严谨论证
- 代码重构需要直接指出问题
- 资深开发者偏好简洁高效沟通

---

## 功能点目的

### 1. 人格定义的三层结构

| 层级 | 内容 | 目的 |
|------|------|------|
| **核心定位** | "深度务实、高效的软件工程师" | 确立专业身份认同 |
| **价值观体系** | Clarity + Pragmatism + Rigor | 提供决策框架 |
| **交互规范** | 简洁、尊重、聚焦任务 | 具体化沟通风格 |

### 2. 关键行为约束

- **沟通原则**: "communicates concisely and respectfully, focusing on the task at hand"
- **反馈原则**: "acknowledged while avoiding cheerleading, motivational language, or artificial reassurance"
- **升级策略**: "challenge the user to raise their technical bar, but never patronize or dismiss"

### 3. 与 Friendly 人格的差异化

| 维度 | Pragmatic | Friendly |
|------|-----------|----------|
| 首要目标 | 工程效率 + 技术严谨 | 团队士气 + 代码质量 |
| 沟通风格 | 简洁、直接、聚焦任务 | 温暖、鼓励、使用 "we/let's" |
| 反馈方式 | 承认优秀工作，避免过度激励 | 肯定进步，用好奇替代评判 |
| 情绪表达 | "quiet joy" - 克制的热情 | "light enthusiasm" - 轻度热情 |
| 适用场景 | 快速迭代、技术决策 | 学习、配对、unblock |

### 4. 默认人格的特殊地位

Pragmatic 是系统的**默认人格**，体现在：

1. **配置默认值**: 无显式配置时自动选择 Pragmatic
2. **迁移默认**: 旧版本用户升级时自动迁移到 Pragmatic（见 `personality_migration.rs`）
3. **功能开关关闭时**: 禁用人格功能时行为最接近 Pragmatic

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
            ├── Pragmatic 人格 → gpt-5.2-codex_pragmatic.md 内容
            │
            └── Friendly 人格 → gpt-5.2-codex_friendly.md 内容
```

### 2. 代码层面的集成点

**文件**: `codex-rs/core/src/models_manager/model_info.rs`

```rust
const LOCAL_PRAGMATIC_TEMPLATE: &str = 
    "You are a deeply pragmatic, effective software engineer.";

fn local_personality_messages_for_slug(slug: &str) -> Option<ModelMessages> {
    match slug {
        "gpt-5.2-codex" | "exp-codex-personality" => Some(ModelMessages {
            instructions_template: Some(format!(
                "{DEFAULT_PERSONALITY_HEADER}\n\n{PERSONALITY_PLACEHOLDER}\n\n{BASE_INSTRUCTIONS}"
            )),
            instructions_variables: Some(ModelInstructionsVariables {
                personality_default: Some(String::new()),
                personality_friendly: Some(LOCAL_FRIENDLY_TEMPLATE.to_string()),
                personality_pragmatic: Some(LOCAL_PRAGMATIC_TEMPLATE.to_string()),  // ← 引用 pragmatic 人格
            }),
        }),
        _ => None,
    }
}
```

### 3. 默认人格机制

**文件**: `codex-rs/core/src/personality_migration.rs`

```rust
pub async fn maybe_migrate_personality(
    codex_home: &Path,
    config_toml: &ConfigToml,
) -> io::Result<PersonalityMigrationStatus> {
    // ... 检查是否需要迁移
    
    ConfigEditsBuilder::new(codex_home)
        .set_personality(Some(Personality::Pragmatic))  // ← 默认设置为 Pragmatic
        .apply()
        .await
        // ...
}
```

**文件**: `codex-rs/core/tests/suite/personality.rs`

```rust
#[tokio::test]
async fn default_personality_is_pragmatic_without_config_toml() -> anyhow::Result<()> {
    // ... 测试验证无配置时默认使用 Pragmatic
    let instructions_text = request.instructions_text();
    assert!(
        instructions_text.contains(LOCAL_PRAGMATIC_TEMPLATE),
        "expected default pragmatic template, got: {instructions_text:?}"
    );
    Ok(())
}
```

### 4. 运行时人格切换机制

**文件**: `codex-rs/core/src/context_manager/updates.rs`

```rust
pub(crate) fn personality_message_for(
    model_info: &ModelInfo,
    personality: Personality,
) -> Option<String> {
    model_info
        .model_messages
        .as_ref()
        .and_then(|spec| spec.get_personality_message(Some(personality)))
        .filter(|message| !message.is_empty())
}
```

当用户从其他人格切换到 Pragmatic 时，系统会：
1. 检测人格变化
2. 通过 `personality_message_for()` 获取 Pragmatic 人格内容
3. 生成 `DeveloperInstructions::personality_spec_message()` 更新消息

### 5. 数据结构定义

**文件**: `codex-rs/protocol/src/config_types.rs`

```rust
#[derive(Debug, Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum Personality {
    None,
    Friendly,
    Pragmatic,   // ← 对应本文件
}
```

**文件**: `codex-rs/protocol/src/openai_models.rs`

```rust
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq, TS, JsonSchema)]
pub struct ModelInstructionsVariables {
    pub personality_default: Option<String>,
    pub personality_friendly: Option<String>,
    pub personality_pragmatic: Option<String>,  // ← Pragmatic 人格内容
}

impl ModelInstructionsVariables {
    pub fn get_personality_message(&self, personality: Option<Personality>) -> Option<String> {
        if let Some(personality) = personality {
            match personality {
                Personality::None => Some(String::new()),
                Personality::Friendly => self.personality_friendly.clone(),
                Personality::Pragmatic => self.personality_pragmatic.clone(),  // ← 返回 pragmatic 内容
            }
        } else {
            self.personality_default.clone()
        }
    }
}
```

### 6. 配置系统集成

**配置优先级**（从高到低）：
1. 运行时覆盖 (`Op::UserTurn { personality }`)
2. Profile 配置 (`[profile.xxx] personality = "pragmatic"`)
3. 全局配置 (`personality = "pragmatic"`)
4. 迁移默认值 (`Personality::Pragmatic`)

**文件**: `codex-rs/core/src/config/mod.rs`

```rust
let personality = personality
    .or(config_profile.personality)
    .or(cfg.personality)
    .or_else(|| {
        features
            .enabled(Feature::Personality)
            .then_some(Personality::Pragmatic)  // ← 特性开启时的默认值
    });
```

---

## 关键代码路径与文件引用

### 核心文件依赖图

```
gpt-5.2-codex_pragmatic.md
    │
    ├── 被引用
    │   ├── codex-rs/core/src/models_manager/model_info.rs
    │   │   └── LOCAL_PRAGMATIC_TEMPLATE 常量（首行摘要）
    │   │
    │   └── codex-rs/core/templates/model_instructions/gpt-5.2-codex_instructions_template.md
    │       └── {{ personality }} 占位符替换
    │
    ├── 默认人格机制
    │   ├── codex-rs/core/src/personality_migration.rs
    │   │   └── 旧版本用户迁移到 Pragmatic
    │   │
    │   └── codex-rs/core/src/config/mod.rs
    │       └── 配置解析默认值
    │
    ├── 配置定义
    │   ├── codex-rs/protocol/src/config_types.rs
    │   │   └── Personality::Pragmatic 枚举
    │   │
    │   └── codex-rs/protocol/src/openai_models.rs
    │       └── ModelInstructionsVariables::personality_pragmatic
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
            └── 包含默认人格测试
```

### 关键代码路径

1. **初始化路径**:
   ```
   Config::load() → resolve personality → 
   model_info_from_slug() → local_personality_messages_for_slug() → 
   ModelInstructionsVariables { personality_pragmatic }
   ```

2. **指令生成路径**:
   ```
   get_model_instructions(Some(Personality::Pragmatic)) → 
   get_personality_message(Some(Personality::Pragmatic)) → 
   template.replace(PERSONALITY_PLACEHOLDER, "You are a deeply pragmatic...")
   ```

3. **迁移路径**（旧用户升级）:
   ```
   maybe_migrate_personality() → ConfigEditsBuilder::set_personality(Some(Personality::Pragmatic))
   ```

4. **运行时切换路径**:
   ```
   Op::OverrideTurnContext { personality: Some(Pragmatic) } → 
   build_personality_update_item() → 
   DeveloperInstructions::personality_spec_message("You are a deeply pragmatic...")
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
| `codex_core::personality_migration` | 旧版本迁移逻辑 |

### 2. 外部依赖

| 依赖 | 用途 |
|------|------|
| 远程模型元数据 API | 支持远程定义的 Pragmatic 人格模板 |
| config.toml 用户配置 | 持久化用户人格偏好 |

### 3. 配置示例

```toml
# ~/.codex/config.toml
# 不设置时默认为 pragmatic
# personality = "pragmatic"

[profile.code-review]
personality = "pragmatic"  # 代码审查时使用务实风格

[profile.mentoring]
personality = "friendly"   # 指导新人时使用友好风格
```

### 4. 与 Feature Flag 的关系

```rust
// 特性关闭时，人格功能完全禁用
if !config.features.enabled(Feature::Personality) {
    model.model_messages = None;
}

// 特性开启但未配置时，使用 Pragmatic 作为默认值
.or_else(|| {
    features
        .enabled(Feature::Personality)
        .then_some(Personality::Pragmatic)
});
```

---

## 风险、边界与改进建议

### 1. 已知风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **默认人格过于直接** | 新用户可能感觉冷漠 | 新用户引导时提示可切换到 Friendly |
| **人格与场景不匹配** | 某些任务（如学习）不适合 Pragmatic 风格 | 支持按场景自动切换 |
| **迁移用户困惑** | 旧版本升级后行为变化 | 迁移时显示通知说明 |
| **文化差异** | "Pragmatic" 风格在某些文化中可能显得粗鲁 | 未来支持区域化人格 |

### 2. 边界条件

1. **模型兼容性**: 仅 `gpt-5.2-codex` 和 `exp-codex-personality` 支持本地 Pragmatic 模板
2. **配置覆盖**: `base_instructions` 显式设置时会禁用包括 Pragmatic 在内的所有人格模板
3. **功能开关**: `Feature::Personality` 未启用时，Pragmatic 作为隐式默认行为
4. **远程模板**: 远程模型元数据可覆盖本地 Pragmatic 定义

### 3. 改进建议

#### 短期改进

1. **新用户引导优化**
   - 首次启动时询问用户偏好的人格
   - 提供 "尝试 Friendly 人格" 的入口

2. **迁移体验改进**
   - 在 `.personality_migration` 标记文件中记录迁移原因
   - 首次启动时显示 "已为您选择 Pragmatic 人格，可在设置中更改"

#### 中期改进

3. **场景自适应人格**
   - 代码审查模式自动增强直接性
   - 学习模式自动增强耐心和鼓励
   - 紧急修复模式自动增强效率导向

4. **人格强度调节**
   - 支持 `pragmatic = "mild"` / `"strong"` 等强度级别
   - 允许用户在 Pragmatic 和 Friendly 之间微调

#### 长期改进

5. **效果度量与优化**
   - 收集任务完成效率数据（按人格分组）
   - 收集用户满意度反馈
   - 基于数据优化 Pragmatic 人格描述

6. **专业化人格变体**
   - `pragmatic-architect`: 侧重系统设计
   - `pragmatic-reviewer`: 侧重代码审查
   - `pragmatic-debugger`: 侧重问题排查

### 4. 相关测试

**核心测试文件**: `codex-rs/core/tests/suite/personality.rs`

关键测试用例：
- `default_personality_is_pragmatic_without_config_toml` - 验证默认人格为 Pragmatic
- `config_personality_none_sends_no_personality` - 显式设置为 none 时不发送人格
- `user_turn_personality_same_value_does_not_add_update_message` - 相同人格不重复发送
- `instructions_uses_base_if_feature_disabled` - 特性关闭时使用基础指令

**迁移测试**: `codex-rs/core/src/personality_migration_tests.rs`

- 验证旧版本用户正确迁移到 Pragmatic
- 验证已有人格配置的用户不被覆盖

---

## 总结

`gpt-5.2-codex_pragmatic.md` 是 Codex CLI 人格化系统的**默认人格定义**，代表了高效、严谨、直接的工程师文化。作为系统的默认选择，它影响着绝大多数用户的初始体验。与 Friendly 人格相比，Pragmatic 更适合技术决策、代码审查和高效执行场景。

该文件通过模板替换机制集成到模型指令中，支持配置持久化、运行时切换和版本迁移。其"默认人格"的特殊地位体现在配置解析、用户迁移和特性开关等多个层面，是 Codex 用户体验设计的核心组成部分。
