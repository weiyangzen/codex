# ModelListResponse.json 研究文档

## 场景与职责

`ModelListResponse.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述模型列表查询响应的结构。

该响应结构用于 `model/list` 方法的返回，包含可用的 AI 模型列表、分页信息以及模型详细元数据，支持客户端实现模型选择、能力展示和升级提示等功能。

## 功能点目的

1. **模型发现**: 向客户端展示所有可用的 AI 模型
2. **能力展示**: 提供每个模型的详细能力信息（推理强度、输入模态等）
3. **升级引导**: 通过 `upgrade_info` 字段支持模型版本升级提示
4. **分页支持**: 支持游标分页，处理大量模型数据
5. **默认模型标识**: 通过 `isDefault` 字段指示推荐使用的默认模型

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "InputModality": {
      "description": "Canonical user-input modality tags advertised by a model.",
      "oneOf": [
        { "description": "Plain text turns and tool payloads.", "enum": ["text"], "type": "string" },
        { "description": "Image attachments included in user turns.", "enum": ["image"], "type": "string" }
      ]
    },
    "Model": {
      "properties": {
        "availabilityNux": { /* 模型可用性新用户引导 */ },
        "defaultReasoningEffort": { "$ref": "#/definitions/ReasoningEffort" },
        "description": { "type": "string" },
        "displayName": { "type": "string" },
        "hidden": { "type": "boolean" },
        "id": { "type": "string" },
        "inputModalities": { "items": { "$ref": "#/definitions/InputModality" }, "type": "array" },
        "isDefault": { "type": "boolean" },
        "model": { "type": "string" },
        "supportedReasoningEfforts": { "items": { "$ref": "#/definitions/ReasoningEffortOption" }, "type": "array" },
        "supportsPersonality": { "default": false, "type": "boolean" },
        "upgrade": { "type": ["string", "null"] },
        "upgradeInfo": { /* 升级信息 */ }
      },
      "required": ["defaultReasoningEffort", "description", "displayName", "hidden", "id", "isDefault", "model", "supportedReasoningEfforts"],
      "type": "object"
    },
    "ModelAvailabilityNux": {
      "properties": { "message": { "type": "string" } },
      "required": ["message"],
      "type": "object"
    },
    "ModelUpgradeInfo": {
      "properties": {
        "migrationMarkdown": { "type": ["string", "null"] },
        "model": { "type": "string" },
        "modelLink": { "type": ["string", "null"] },
        "upgradeCopy": { "type": ["string", "null"] }
      },
      "required": ["model"],
      "type": "object"
    },
    "ReasoningEffort": {
      "description": "See https://platform.openai.com/docs/guides/reasoning",
      "enum": ["none", "minimal", "low", "medium", "high", "xhigh"],
      "type": "string"
    },
    "ReasoningEffortOption": {
      "properties": {
        "description": { "type": "string" },
        "reasoningEffort": { "$ref": "#/definitions/ReasoningEffort" }
      },
      "required": ["description", "reasoningEffort"],
      "type": "object"
    }
  },
  "properties": {
    "data": {
      "items": { "$ref": "#/definitions/Model" },
      "type": "array"
    },
    "nextCursor": {
      "description": "Opaque cursor to pass to the next call to continue after the last item.",
      "type": ["string", "null"]
    }
  },
  "required": ["data"],
  "title": "ModelListResponse",
  "type": "object"
}
```

### 核心字段说明

#### Model 对象

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 模型唯一标识符 |
| `model` | string | 底层模型名称（如 "gpt-4"） |
| `displayName` | string | 用户友好的显示名称 |
| `description` | string | 模型描述 |
| `isDefault` | boolean | 是否为默认推荐模型 |
| `hidden` | boolean | 是否在默认选择器中隐藏 |
| `inputModalities` | array | 支持的输入模态（text/image） |
| `defaultReasoningEffort` | string | 默认推理强度 |
| `supportedReasoningEfforts` | array | 支持的推理强度选项 |
| `supportsPersonality` | boolean | 是否支持个性设置 |
| `upgrade` | string \| null | 推荐升级到的模型 ID |
| `upgradeInfo` | object | 升级信息详情 |
| `availabilityNux` | object | 新用户引导消息 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:1787
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelListResponse {
    pub data: Vec<Model>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    pub next_cursor: Option<String>,
}

// Model 结构体 (行 1747-1767)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
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
    pub default_reasoning_effort: ReasoningEffort,
    #[serde(default = "default_input_modalities")]
    pub input_modalities: Vec<InputModality>,
    #[serde(default)]
    pub supports_personality: bool,
    pub is_default: bool,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1787-1795)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/ModelListResponse.json`
- **相关定义**: 
  - `Model` (行 1747-1767)
  - `ModelUpgradeInfo` (行 1769-1777)
  - `ModelAvailabilityNux` (行 1735-1745)
  - `ReasoningEffortOption` (行 1779-1785)

### 调用方
- **方法注册**: `common.rs` 行 389-392
- **请求参数**: `ModelListParams`

### 数据来源
- **模型注册表**: 服务器端的模型配置和元数据
- **OpenAI API**: 底层模型能力信息

## 依赖与外部交互

### 上游依赖
1. **模型配置系统**: 维护可用模型列表和元数据
2. **OpenAI 模型 API**: 获取模型能力和特性信息
3. **特性标志系统**: 控制模型的可见性和可用性

### 下游使用方
1. **模型选择器 UI**: 展示模型列表和能力
2. **配置系统**: 验证和设置默认模型
3. **升级提示**: 根据 `upgrade_info` 展示升级建议

### 相关枚举
```rust
// ReasoningEffort (来自 codex_protocol)
pub enum ReasoningEffort {
    None,
    Minimal,
    Low,
    Medium,
    High,
    Xhigh,
}

// InputModality (来自 codex_protocol::openai_models)
pub enum InputModality {
    Text,
    Image,
}
```

## 风险、边界与改进建议

### 潜在风险
1. **模型 ID 变更**: 底层模型名称变更可能导致配置失效
2. **能力差异**: 不同提供商的相同名称模型可能有不同能力
3. **缓存过期**: 客户端缓存的模型信息可能过时

### 边界情况
1. **空列表**: 当没有可用模型时返回空 `data` 数组
2. **全部隐藏**: 所有模型都标记为 `hidden` 时的处理
3. **无默认模型**: 多个或零个模型标记为 `isDefault`

### 改进建议

#### 1. 添加提供商信息
```json
{
  "id": "gpt-4",
  "provider": "openai",
  "providerDisplayName": "OpenAI"
}
```

#### 2. 添加模型状态
```json
{
  "id": "gpt-4",
  "status": "available",
  "statusMessage": null
}
```

#### 3. 添加定价信息
```json
{
  "id": "gpt-4",
  "pricing": {
    "inputTokens": 0.03,
    "outputTokens": 0.06,
    "currency": "USD"
  }
}
```

#### 4. 添加模型限制
```json
{
  "id": "gpt-4",
  "limits": {
    "maxTokens": 8192,
    "maxInputTokens": 6144,
    "contextWindow": 8192
  }
}
```

#### 5. 响应元数据
```json
{
  "data": [...],
  "nextCursor": "...",
  "totalCount": 15,
  "hasMore": false,
  "lastUpdated": 1712345678
}
```

### 最佳实践
1. **本地缓存**: 客户端应缓存模型列表，减少重复请求
2. **默认选择**: 优先使用 `isDefault` 为 true 的模型
3. **升级提示**: 当 `upgradeInfo` 存在时，向用户展示升级建议
4. **隐藏模型**: 仅在高级设置或调试模式下显示 `hidden` 模型

### 相关 API
- `ModelListParams` - 模型列表查询参数
- `ThreadStartParams.model` - 创建线程时指定模型
- `ModelReroutedNotification` - 模型自动切换通知
