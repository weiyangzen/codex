# personality.rs 研究文档

## 场景与职责

`personality.rs` 是 Codex Core 的集成测试套件，专门测试 **Personality（人格/沟通风格）** 功能。该功能允许用户选择 AI 助手的沟通风格（友好型 Friendly 或务实型 Pragmatic），并动态调整系统指令（instructions）以匹配所选风格。

Personality 功能是 Codex 的一个重要用户体验特性，它通过修改发送给模型的系统指令来改变 AI 的回应风格：
- **Friendly（友好型）**: "You optimize for team morale and being a supportive teammate as much as code quality."
- **Pragmatic（务实型）**: "You are a deeply pragmatic, effective software engineer."

## 功能点目的

### 1. 人格模板注入验证
测试确认当用户选择特定人格时，系统指令中是否正确注入对应的人格模板文本。

### 2. 人格切换机制
验证在对话过程中切换人格时，系统是否通过 `<personality_spec>` 标签向模型发送更新通知。

### 3. 本地与远程模型支持
测试同时覆盖：
- 本地硬编码的人格模板（针对 gpt-5.2-codex 等模型）
- 远程模型通过 API 返回的 `model_messages` 中定义的动态人格模板

### 4. 功能开关控制
验证 `Feature::Personality` 功能标志是否正确控制人格功能的启用/禁用。

### 5. 配置优先级
测试确认 `base_instructions` 覆盖可以禁用人格模板注入。

## 具体技术实现

### 关键数据结构

```rust
// 人格类型定义（来自 codex_protocol::config_types）
pub enum Personality {
    None,
    Friendly,
    Pragmatic,
}

// 模型信息中的人格相关字段
pub struct ModelMessages {
    pub instructions_template: Option<String>,  // 包含 {{ personality }} 占位符
    pub instructions_variables: Option<ModelInstructionsVariables>,
}

pub struct ModelInstructionsVariables {
    pub personality_default: Option<String>,
    pub personality_friendly: Option<String>,
    pub personality_pragmatic: Option<String>,
}
```

### 核心测试流程

1. **模板注入测试** (`config_personality_some_sets_instructions_template`):
   - 配置 `personality = Some(Personality::Friendly)`
   - 发送用户消息
   - 验证请求中的 `instructions_text()` 包含 Friendly 模板
   - 验证开发者消息中**不包含** `<personality_spec>`

2. **人格切换测试** (`user_turn_personality_some_adds_update_message`):
   - 第一轮对话使用默认人格
   - 发送 `Op::OverrideTurnContext { personality: Some(Personality::Friendly) }`
   - 第二轮对话
   - 验证第二轮请求的开发者消息中包含 `<personality_spec>` 更新通知

3. **重复人格跳过测试** (`user_turn_personality_same_value_does_not_add_update_message`):
   - 验证相同人格切换不会重复发送更新消息

4. **远程模型测试** (`remote_model_friendly_personality_instructions_with_feature`):
   - 使用 MockServer 返回自定义 `ModelInfo`
   - 验证远程定义的人格模板被正确使用

### 关键代码路径

```
codex-rs/core/tests/suite/personality.rs
├── 测试初始化
│   ├── test_codex() - 创建测试环境
│   ├── mount_sse_once() / mount_sse_sequence() - 模拟 API 响应
│   └── with_config() - 启用 Feature::Personality
│
├── 人格注入验证
│   ├── request.instructions_text() - 获取系统指令
│   └── request.message_input_texts("developer") - 获取开发者消息
│
└── 人格切换验证
    ├── Op::OverrideTurnContext { personality } - 切换人格
    └── 验证 <personality_spec> 标签存在/不存在
```

### 依赖与外部交互

| 依赖模块 | 用途 |
|---------|------|
| `codex_core::features::Feature` | 功能标志控制 |
| `codex_core::config::types::Personality` | 人格类型定义 |
| `codex_protocol::openai_models::ModelInfo` | 模型元数据 |
| `codex_protocol::protocol::Op` | 操作类型（UserTurn, OverrideTurnContext） |
| `core_test_support::responses::*` | Mock API 响应 |
| `wiremock::MockServer` | HTTP 模拟服务器 |

### 生产代码关联

```
codex-rs/core/src/models_manager/model_info.rs
├── local_personality_messages_for_slug() - 本地人格模板
├── with_config_overrides() - 应用配置覆盖
└── model_info_from_slug() - 创建模型信息

codex-rs/core/src/features.rs
└── Feature::Personality - 功能标志定义
```

## 风险、边界与改进建议

### 已知边界

1. **模型特定性**: 人格模板目前仅针对特定模型（gpt-5.2-codex, exp-codex-personality）有本地定义，其他模型依赖远程配置。

2. **功能标志依赖**: 所有人格功能都依赖 `Feature::Personality` 标志，禁用时完全跳过人格处理。

3. **base_instructions 覆盖**: 当用户设置 `base_instructions` 时，人格模板被完全禁用，这可能造成用户困惑。

### 测试覆盖缺口

1. **并发人格切换**: 未测试多线程环境下的人格切换行为。

2. **人格与协作模式交互**: 未测试人格设置与 `CollaborationMode` 的交互。

3. **错误处理**: 未测试远程模型返回无效人格配置时的错误处理。

### 改进建议

1. **统一人格配置**: 考虑将本地和远程人格模板统一，减少维护负担。

2. **人格预览功能**: 添加 API 让用户预览不同人格的系统指令差异。

3. **细粒度人格控制**: 允许在单次对话中临时切换人格而不影响全局设置。

4. **人格分析指标**: 添加遥测数据收集，分析用户对人格功能的偏好。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/personality.rs` (901 行)
- 功能定义: `codex-rs/core/src/features.rs` (第 173-174 行, 第 802-807 行)
- 模型信息: `codex-rs/core/src/models_manager/model_info.rs`
- 人格迁移: `codex-rs/core/src/personality_migration.rs`
- 协议定义: `codex-rs/protocol/src/config_types.rs`
