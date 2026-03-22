# model_list.rs 深入研究文档

## 场景与职责

`model_list.rs` 是 Codex App Server v2 协议测试套件中的模型列表 API 测试模块。该模块测试了 `model/list` JSON-RPC 方法的完整功能，包括模型列表获取、分页、隐藏模型过滤以及无效游标处理。

该测试文件确保客户端能够正确获取可用的 AI 模型列表，支持分页浏览和包含隐藏模型的选项，同时验证错误处理机制。

## 功能点目的

### 1. 完整模型列表获取 (`list_models_returns_all_models_with_large_limit`)
验证当请求较大的 `limit` 值时，API 返回所有可见模型，且 `next_cursor` 为 `None` 表示没有更多数据。

### 2. 隐藏模型包含 (`list_models_includes_hidden_models`)
验证当 `include_hidden` 参数为 `true` 时，响应包含标记为 `hidden: true` 的模型。这些模型通常不在默认选择器中显示。

### 3. 分页功能 (`list_models_pagination_works`)
验证游标分页机制：
- 使用 `limit: 1` 逐页获取模型
- 每页返回一个模型和下一页游标
- 最终所有页面数据与预期完整列表匹配

### 4. 无效游标处理 (`list_models_rejects_invalid_cursor`)
验证当提供无效游标时，API 返回标准的 JSON-RPC 错误：
- 错误码: `-32600` (Invalid Request)
- 错误消息: "invalid cursor: {cursor}"

## 具体技术实现

### 关键流程

#### 模型列表获取流程
```
Client -> Server: model/list
         Params: { limit: 100, cursor: null, include_hidden: null }
Server -> Client: ModelListResponse
         Result: {
           data: [Model { id, model, display_name, hidden, ... }, ...],
           next_cursor: null
         }
```

#### 分页流程
```
Page 1:
  Client -> Server: model/list { limit: 1, cursor: null }
  Server -> Client: { data: [model1], next_cursor: "cursor_1" }

Page 2:
  Client -> Server: model/list { limit: 1, cursor: "cursor_1" }
  Server -> Client: { data: [model2], next_cursor: "cursor_2" }

...直到 next_cursor 为 null
```

### 数据结构

#### ModelListParams
```rust
pub struct ModelListParams {
    /// Opaque pagination cursor returned by a previous call.
    pub cursor: Option<String>,
    /// Optional page size; defaults to a reasonable server-side value.
    pub limit: Option<u32>,
    /// When true, include models that are hidden from the default picker list.
    pub include_hidden: Option<bool>,
}
```

#### Model
```rust
pub struct Model {
    pub id: String,                      // 模型 ID，如 "o4-mini"
    pub model: String,                   // 模型名称
    pub upgrade: Option<String>,         // 升级目标模型 ID
    pub upgrade_info: Option<ModelUpgradeInfo>,
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub display_name: String,            // 显示名称
    pub description: String,             // 描述
    pub hidden: bool,                    // 是否隐藏
    pub supported_reasoning_efforts: Vec<ReasoningEffortOption>,
    pub default_reasoning_effort: ReasoningEffort,
    pub input_modalities: Vec<InputModality>,
    pub supports_personality: bool,
    pub is_default: bool,                // 是否为默认模型
}
```

#### ModelListResponse
```rust
pub struct ModelListResponse {
    pub data: Vec<Model>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

#### ModelUpgradeInfo
```rust
pub struct ModelUpgradeInfo {
    pub model: String,
    pub upgrade_copy: Option<String>,
    pub model_link: Option<String>,
    pub migration_markdown: Option<String>,
}
```

#### ReasoningEffortOption
```rust
pub struct ReasoningEffortOption {
    pub reasoning_effort: ReasoningEffort,  // low, medium, high
    pub description: String,
}
```

### 测试辅助函数

#### model_from_preset
将内部 `ModelPreset` 转换为 API `Model`：
```rust
fn model_from_preset(preset: &ModelPreset) -> Model {
    Model {
        id: preset.id.clone(),
        model: preset.model.clone(),
        upgrade: preset.upgrade.as_ref().map(|upgrade| upgrade.id.clone()),
        upgrade_info: preset.upgrade.as_ref().map(|upgrade| ModelUpgradeInfo { ... }),
        availability_nux: preset.availability_nux.clone().map(Into::into),
        display_name: preset.display_name.clone(),
        description: preset.description.clone(),
        hidden: !preset.show_in_picker,
        supported_reasoning_efforts: preset.supported_reasoning_efforts.iter().map(...).collect(),
        default_reasoning_effort: preset.default_reasoning_effort,
        input_modalities: preset.input_modalities.clone(),
        supports_personality: false,  // 已知限制
        is_default: preset.is_default,
    }
}
```

#### expected_visible_models
生成预期的可见模型列表：
```rust
fn expected_visible_models() -> Vec<Model> {
    // 1. 获取所有模型预设
    // 2. 根据认证模式过滤
    // 3. 标记默认模型
    // 4. 过滤出 show_in_picker = true 的模型
    // 5. 转换为 Model 类型
}
```

### 常量定义
```rust
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
const INVALID_REQUEST_ERROR_CODE: i64 = -32600;
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/model_list.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/mod.rs`: v2 测试模块入口

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `ModelListParams` (line 1717)
  - `Model` (line 1747)
  - `ModelListResponse` (line 1787)
  - `ModelUpgradeInfo` (line 1769)
  - `ReasoningEffortOption` (line 1779)
  - `ModelAvailabilityNux` (line 1735)

- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ClientRequest::ModelList` (line 389)

### 测试支持
- `codex-rs/app-server/tests/common/mcp_process.rs`:
  - `McpProcess::send_list_models_request()`: 发送模型列表请求

- `codex-rs/app-server/tests/common/models_cache.rs`:
  - `write_models_cache()`: 写入模型缓存文件

### 核心模型定义
- `codex-protocol/src/openai_models.rs`:
  - `ModelPreset`: 内部模型预设定义
  - `ModelPreset::filter_by_auth()`: 根据认证过滤
  - `ModelPreset::mark_default_by_picker_visibility()`: 标记默认模型

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 异步操作超时控制 |
| `pretty_assertions::assert_eq` | 测试断言美化 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `app_test_support::McpProcess` | MCP 客户端进程管理 |
| `app_test_support::to_response` | 响应解析 |
| `app_test_support::write_models_cache` | 准备模型缓存 |
| `codex_app_server_protocol::*` | 协议类型定义 |
| `codex_protocol::openai_models::ModelPreset` | 模型预设定义 |
| `codex_core::test_support::all_model_presets` | 测试 fixtures |

### 测试数据流
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  write_models_  │────▶│   Model Cache    │────▶│  ModelsManager  │
│    cache()      │     │   (models.json)  │     │  (in app-server)│
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                               ┌──────────────────────────┘
                               ▼
┌─────────────────┐     ┌──────────────────┐
│   Test Client   │◀────│  model/list API  │
│  (Assertions)   │     │  (JSON-RPC)      │
└─────────────────┘     └──────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **测试数据依赖**
   - 测试依赖 `all_model_presets()` 返回的模型列表
   - 如果模型配置改变，测试需要更新

2. **已知限制未修复**
   ```rust
   // 代码注释中的 TODO:
   // `write_models_cache()` round-trips through a simplified ModelInfo fixture 
   // that does not preserve personality placeholders in base instructions, 
   // so app-server list results from cache report `supports_personality = false`.
   // todo(sayan): fix, maybe make roundtrip use ModelInfo only
   ```
   `supports_personality` 字段当前始终返回 `false`，这是一个已知但未修复的问题。

3. **认证模式敏感**
   - `expected_visible_models()` 使用 `filter_by_auth(..., false)`
   - 不同认证模式下可见模型可能不同

### 边界情况

1. **空列表处理**
   - 未测试模型列表为空的情况
   - 未测试所有模型都被隐藏的情况

2. **大分页值**
   - 测试使用 `limit: 100` 获取完整列表
   - 未测试 `limit: 0` 或极大值的行为

3. **并发请求**
   - 未测试并发模型列表请求的处理

4. **缓存失效**
   - 未测试模型缓存更新后的列表变化

### 改进建议

1. **修复已知限制**
   修复 `supports_personality` 字段的正确性：
   ```rust
   // 在 model_from_preset 中
   supports_personality: preset.supports_personality, // 而非硬编码 false
   ```

2. **增加边界测试**
   ```rust
   // 建议添加
   async fn list_models_with_zero_limit() // limit: 0 的行为
   async fn list_models_with_very_large_limit() // limit: u32::MAX
   async fn list_models_empty_cache() // 空缓存处理
   ```

3. **并发测试**
   ```rust
   // 建议添加
   async fn concurrent_model_list_requests()
   ```

4. **缓存更新测试**
   ```rust
   // 建议添加
   async fn list_models_after_cache_update()
   ```

5. **认证模式覆盖**
   测试不同认证模式下的模型可见性：
   ```rust
   // 建议添加
   async fn list_models_with_chatgpt_auth()
   async fn list_models_with_api_key_auth()
   ```

6. **性能基准**
   - 模型列表 API 响应时间基准测试
   - 大列表分页性能测试
