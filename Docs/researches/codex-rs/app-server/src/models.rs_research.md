# models.rs 研究文档

## 场景与职责

`models.rs` 是 Codex App Server 的**模型管理辅助模块**，负责将核心层 (`codex_core`) 的模型预设 (`ModelPreset`) 转换为应用服务器协议层 (`codex_app_server_protocol`) 的模型定义 (`Model`)。

该模块是一个**纯转换层**，没有业务逻辑，仅提供数据格式转换功能，用于：
1. 获取支持的模型列表
2. 模型预设到 API 响应的转换
3. 推理努力程度选项的转换

## 功能点目的

### 1. 支持模型列表获取 (supported_models)

**目的**：为客户端提供可用的 AI 模型列表。

**功能细节**：
- 调用 `ThreadManager::list_models()` 获取模型预设列表
- 支持 `RefreshStrategy::OnlineIfUncached` 策略（如果未缓存则在线获取）
- 支持 `include_hidden` 参数控制是否包含隐藏模型
- 过滤 `show_in_picker` 为 false 的隐藏模型（当 `include_hidden=false` 时）

### 2. 模型预设转换 (model_from_preset)

**目的**：将内部 `ModelPreset` 转换为 API 可用的 `Model` 结构。

**转换字段映射**：

| ModelPreset 字段 | Model 字段 | 说明 |
|-----------------|------------|------|
| `id` | `id` | 模型唯一标识 |
| `model` | `model` | 实际模型名称 |
| `upgrade` | `upgrade` | 升级目标模型 ID |
| `upgrade.*` | `upgrade_info` | 详细的升级信息 |
| `availability_nux` | `availability_nux` | 新用户体验可用性 |
| `display_name` | `display_name` | 显示名称 |
| `description` | `description` | 模型描述 |
| `show_in_picker` | `hidden` | 是否隐藏（取反） |
| `supported_reasoning_efforts` | `supported_reasoning_efforts` | 支持的推理努力程度 |
| `default_reasoning_effort` | `default_reasoning_effort` | 默认推理努力程度 |
| `input_modalities` | `input_modalities` | 输入模态 |
| `supports_personality` | `supports_personality` | 是否支持个性化 |
| `is_default` | `is_default` | 是否为默认模型 |

### 3. 推理努力程度转换 (reasoning_efforts_from_preset)

**目的**：转换推理努力程度预设列表。

**转换逻辑**：
```rust
ReasoningEffortPreset → ReasoningEffortOption
  effort → reasoning_effort
  description → description
```

## 具体技术实现

### 关键函数

#### supported_models

```rust
pub async fn supported_models(
    thread_manager: Arc<ThreadManager>,
    include_hidden: bool,
) -> Vec<Model> {
    thread_manager
        .list_models(RefreshStrategy::OnlineIfUncached)  // 获取模型列表
        .await
        .into_iter()
        .filter(|preset| include_hidden || preset.show_in_picker)  // 过滤隐藏模型
        .map(model_from_preset)  // 转换每个预设
        .collect()
}
```

#### model_from_preset

```rust
fn model_from_preset(preset: ModelPreset) -> Model {
    Model {
        id: preset.id.to_string(),
        model: preset.model.to_string(),
        upgrade: preset.upgrade.as_ref().map(|upgrade| upgrade.id.clone()),
        upgrade_info: preset.upgrade.as_ref().map(|upgrade| ModelUpgradeInfo {
            model: upgrade.id.clone(),
            upgrade_copy: upgrade.upgrade_copy.clone(),
            model_link: upgrade.model_link.clone(),
            migration_markdown: upgrade.migration_markdown.clone(),
        }),
        availability_nux: preset.availability_nux.map(Into::into),
        display_name: preset.display_name.to_string(),
        description: preset.description.to_string(),
        hidden: !preset.show_in_picker,  // 注意：取反
        supported_reasoning_efforts: reasoning_efforts_from_preset(
            preset.supported_reasoning_efforts,
        ),
        default_reasoning_effort: preset.default_reasoning_effort,
        input_modalities: preset.input_modalities,
        supports_personality: preset.supports_personality,
        is_default: preset.is_default,
    }
}
```

### 数据结构

#### Model (来自 codex_app_server_protocol)

```rust
pub struct Model {
    pub id: String,
    pub model: String,
    pub upgrade: Option<String>,
    pub upgrade_info: Option<ModelUpgradeInfo>,
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub display_name: String,
    pub description: String,
    pub hidden: bool,
    pub supported_reasoning_efforts: Vec<ReasoningEffortOption>,
    pub default_reasoning_effort: Option<ReasoningEffort>,
    pub input_modalities: Vec<InputModality>,
    pub supports_personality: bool,
    pub is_default: bool,
}
```

#### ModelUpgradeInfo

```rust
pub struct ModelUpgradeInfo {
    pub model: String,
    pub upgrade_copy: String,
    pub model_link: String,
    pub migration_markdown: String,
}
```

#### ReasoningEffortOption

```rust
pub struct ReasoningEffortOption {
    pub reasoning_effort: ReasoningEffort,
    pub description: String,
}
```

## 关键代码路径与文件引用

### 核心依赖

| 模块/类型 | 来源 | 用途 |
|----------|------|------|
| `Model` | `codex_app_server_protocol` | API 响应模型定义 |
| `ModelUpgradeInfo` | `codex_app_server_protocol` | 升级信息结构 |
| `ReasoningEffortOption` | `codex_app_server_protocol` | 推理努力程度选项 |
| `ModelPreset` | `codex_protocol::openai_models` | 核心层模型预设 |
| `ReasoningEffortPreset` | `codex_protocol::openai_models` | 核心层推理努力程度预设 |
| `RefreshStrategy` | `codex_core::models_manager` | 模型列表刷新策略 |
| `ThreadManager` | `codex_core` | 线程管理器，提供模型列表 |

### 调用方

该模块主要在 `codex_message_processor.rs` 中被调用：

```rust
// codex_message_processor.rs
use crate::models::supported_models;

// 在 model/list 请求处理中
async fn handle_model_list(&self, ...) {
    let models = supported_models(
        self.thread_manager.clone(),
        params.include_hidden.unwrap_or(false),
    ).await;
    // ...
}
```

## 依赖与外部交互

### 与 codex_core 的交互

- 依赖 `ThreadManager::list_models()` 获取模型列表
- 使用 `RefreshStrategy::OnlineIfUncached` 策略

### 与 codex_protocol 的交互

- 使用 `ModelPreset` 和 `ReasoningEffortPreset` 类型
- 这些类型定义了从 OpenAI API 获取的原始模型信息

### 与 codex_app_server_protocol 的交互

- 输出 `Model`、`ModelUpgradeInfo`、`ReasoningEffortOption` 类型
- 这些类型用于 API 响应序列化

## 风险、边界与改进建议

### 风险点

1. **模型列表缓存策略**
   - 当前使用 `OnlineIfUncached`，首次调用可能较慢
   - 如果网络不可用，可能返回空列表或错误

2. **字段映射错误**
   - `hidden` 字段是 `show_in_picker` 的取反，容易混淆
   - 如果核心层更改字段语义，可能导致显示错误

3. **升级信息缺失处理**
   - 当 `upgrade` 为 None 时，`upgrade_info` 也为 None
   - 客户端需要正确处理缺失情况

### 边界情况

1. **空模型列表**：当核心层返回空列表时，直接返回空 Vec
2. **所有模型隐藏**：当 `include_hidden=false` 且所有模型都隐藏时，返回空列表
3. **推理努力程度为空**：当模型不支持推理努力程度时，返回空 Vec

### 改进建议

1. **添加缓存层**
   - 在 App Server 层添加模型列表缓存
   - 减少频繁调用核心层的开销

2. **错误处理增强**
   - 当前 `list_models` 可能失败，但函数签名未体现
   - 建议返回 `Result<Vec<Model>, Error>`

3. **字段验证**
   - 添加对必需字段的验证（如 `id`、`model`、`display_name`）
   - 避免返回不完整的数据

4. **日志记录**
   - 添加模型列表获取的日志
   - 便于排查模型显示问题

5. **单元测试**
   - 当前无单元测试
   - 建议添加转换逻辑的单元测试
