# models_cache.rs 研究文档

## 场景与职责

该文件提供了用于测试的模型缓存文件（`models_cache.json`）生成功能。在 Codex 中，`ModelsManager` 负责从网络获取可用模型列表，但在测试中：
1. 不应进行真实的网络请求
2. 需要控制可用的模型列表以测试特定场景
3. 需要确保模型数据格式正确

该模块通过生成预填充的模型缓存文件，让 `ModelsManager` 认为缓存是"新鲜"的，从而避免网络请求。

## 功能点目的

1. **避免网络请求**：通过预填充缓存阻止 `ModelsManager` 发起网络请求
2. **控制测试模型**：提供特定的模型列表用于测试
3. **使用真实模型数据**：基于 `codex_core::test_support::all_model_presets()` 生成，确保数据格式与实际一致
4. **支持自定义模型**：允许测试注入特定的模型配置

## 具体技术实现

### 核心数据结构

```rust
/// 从 ModelPreset 转换为 ModelInfo（用于缓存存储）
fn preset_to_info(preset: &ModelPreset, priority: i32) -> ModelInfo {
    ModelInfo {
        slug: preset.id.clone(),
        display_name: preset.display_name.clone(),
        description: Some(preset.description.clone()),
        default_reasoning_level: Some(preset.default_reasoning_effort),
        supported_reasoning_levels: preset.supported_reasoning_efforts.clone(),
        shell_type: ConfigShellToolType::ShellCommand,
        visibility: if preset.show_in_picker {
            ModelVisibility::List
        } else {
            ModelVisibility::Hide
        },
        supported_in_api: preset.supported_in_api,
        priority,  // 用于排序，值越小越靠前
        upgrade: preset.upgrade.as_ref().map(|u| u.into()),
        base_instructions: "base instructions".to_string(),
        model_messages: None,
        supports_reasoning_summaries: false,
        default_reasoning_summary: ReasoningSummary::Auto,
        support_verbosity: false,
        default_verbosity: None,
        availability_nux: None,
        apply_patch_tool_type: None,
        web_search_tool_type: Default::default(),
        truncation_policy: TruncationPolicyConfig::bytes(/*limit*/ 10_000),
        supports_parallel_tool_calls: false,
        supports_image_detail_original: false,
        context_window: Some(272_000),
        auto_compact_token_limit: None,
        effective_context_window_percent: 95,
        experimental_supported_tools: Vec::new(),
        input_modalities: default_input_modalities(),
        used_fallback_model_metadata: false,
        supports_search_tool: false,
    }
}
```

### 缓存写入函数

```rust
/// 使用 bundled-catalog-derived presets 写入模型缓存
pub fn write_models_cache(codex_home: &Path) -> std::io::Result<()> {
    // 获取稳定的 bundled catalog presets
    let presets: Vec<&ModelPreset> = all_model_presets()
        .iter()
        .filter(|preset| preset.show_in_picker)  // 只包含在 picker 中显示的模型
        .collect();
    
    // 转换为 ModelInfo，分配优先级（索引越小优先级越低）
    let models: Vec<ModelInfo> = presets
        .iter()
        .enumerate()
        .map(|(idx, preset)| {
            let priority = idx as i32;
            preset_to_info(preset, priority)
        })
        .collect();
    
    write_models_cache_with_models(codex_home, models)
}

/// 使用指定的模型列表写入缓存
pub fn write_models_cache_with_models(
    codex_home: &Path,
    models: Vec<ModelInfo>,
) -> std::io::Result<()> {
    let cache_path = codex_home.join("models_cache.json");
    
    let fetched_at: DateTime<Utc> = Utc::now();
    let client_version = codex_core::models_manager::client_version_to_whole();
    
    let cache = json!({
        "fetched_at": fetched_at,        // RFC3339 格式
        "etag": null,                    // 无 ETag（缓存验证用）
        "client_version": client_version, // 客户端版本
        "models": models
    });
    
    std::fs::write(cache_path, serde_json::to_string_pretty(&cache)?)
}
```

### 缓存文件结构

生成的 `models_cache.json` 结构：
```json
{
  "fetched_at": "2024-01-15T10:30:00+00:00",
  "etag": null,
  "client_version": 100,
  "models": [
    {
      "slug": "gpt-4o",
      "display_name": "GPT-4o",
      "description": "...",
      "priority": 0,
      "context_window": 272000,
      ...
    }
  ]
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/models_cache.rs`

### 导出位置
- `lib.rs`: 
```rust
pub use models_cache::write_models_cache;
pub use models_cache::write_models_cache_with_models;
```

### 依赖的 Codex 内部类型
- `codex_core::test_support::all_model_presets` - 获取所有模型预设
- `codex_core::models_manager::client_version_to_whole` - 客户端版本转换
- `codex_protocol::openai_models::{ModelInfo, ModelPreset, ...}` - 模型类型定义

### 使用示例

```rust
// 1. 使用默认模型列表
write_models_cache(codex_home.path())?;

// 2. 使用自定义模型列表
let custom_models = vec![
    ModelInfo {
        slug: "test-model".to_string(),
        display_name: "Test Model".to_string(),
        // ... 其他字段
    }
];
write_models_cache_with_models(codex_home.path(), custom_models)?;
```

## 依赖与外部交互

### 外部 crate 依赖
- `chrono::{DateTime, Utc}` - UTC 时间处理
- `serde_json` - JSON 序列化
- `std::path::Path` - 路径操作

### Codex 内部依赖
```
models_cache.rs
├── codex_core::test_support
│   └── all_model_presets() -> Vec<ModelPreset>
├── codex_core::models_manager
│   └── client_version_to_whole() -> i64
└── codex_protocol::openai_models
    ├── ModelInfo
    ├── ModelPreset
    ├── ConfigShellToolType
    ├── ModelVisibility
    ├── ReasoningSummary
    ├── TruncationPolicyConfig
    └── ...
```

### 与 ModelsManager 的交互

```
测试代码
    │
    ├──► write_models_cache(codex_home)
    │       │
    │       └──► 写入 codex_home/models_cache.json
    │
    └──► 启动 codex-app-server
            │
            └──► ModelsManager 读取缓存
                    │
                    ├──► 检查 fetched_at 是否在 TTL 内
                    │       └── 是 → 使用缓存
                    │       └── 否 → 发起网络请求（测试中应避免）
                    │
                    └──► 返回模型列表
```

## 风险、边界与改进建议

### 风险
1. **TTL 过期**：如果 `ModelsManager` 的缓存 TTL 设置较短，缓存可能在测试期间被视为过期，导致意外的网络请求
2. **版本不匹配**：`client_version` 硬编码通过 `client_version_to_whole()` 获取，如果测试环境与预期版本不一致可能导致问题
3. **模型数据不完整**：`preset_to_info` 中有许多硬编码的默认值（如 `base_instructions: "base instructions"`），可能与实际模型行为不一致
4. **ETag 处理**：`etag` 字段始终为 `null`，如果 `ModelsManager` 实现了条件请求验证，可能无法正确处理

### 边界
- 仅支持写入缓存，不支持读取或验证缓存内容
- 仅支持 `ModelInfo` 格式，不支持其他模型元数据格式
- 生成的缓存始终被视为"新鲜"，不支持模拟过期场景
- 不支持模拟网络请求失败后的降级缓存

### 改进建议

1. **TTL 控制**：
```rust
pub fn write_models_cache_with_ttl(
    codex_home: &Path,
    ttl: Duration,  // 自定义缓存有效期
) -> std::io::Result<()> {
    let fetched_at = Utc::now() - ttl;  // 设置过去的获取时间
    // ...
}
```

2. **缓存验证**：
```rust
pub fn verify_models_cache(codex_home: &Path) -> Result<Vec<ModelInfo>> {
    let cache_path = codex_home.join("models_cache.json");
    let content = std::fs::read_to_string(&cache_path)?;
    let cache: ModelsCache = serde_json::from_str(&content)?;
    Ok(cache.models)
}
```

3. **特定模型筛选**：
```rust
pub fn write_models_cache_with_filter<F>(
    codex_home: &Path,
    filter: F,
) -> std::io::Result<()>
where
    F: Fn(&ModelPreset) -> bool,
{ ... }

// 使用示例
write_models_cache_with_filter(codex_home, |p| p.id.starts_with("gpt-4"))?;
```

4. **模拟过期缓存**：
```rust
pub fn write_expired_models_cache(codex_home: &Path) -> std::io::Result<()> {
    let fetched_at = Utc::now() - Duration::from_days(7);  // 一周前
    // ...
}
```

5. **模型数据模板**：
```rust
pub struct ModelInfoTemplate {
    pub slug: String,
    pub display_name: String,
    pub context_window: Option<i64>,
    // ... 其他关键字段
}

impl ModelInfoTemplate {
    pub fn build(self) -> ModelInfo {
        ModelInfo {
            slug: self.slug,
            display_name: self.display_name,
            context_window: self.context_window,
            // 其他字段使用合理默认值
            ..Default::default()
        }
    }
}
```

6. **文档增强**：
```rust
/// 写入模型缓存文件，阻止 ModelsManager 发起网络请求。
/// 
/// # 注意
/// - 缓存的 `fetched_at` 设置为当前时间
/// - 如果需要模拟过期缓存，请使用 `write_expired_models_cache`
/// - 模型数据基于 bundled catalog，可能与远程数据略有差异
pub fn write_models_cache(codex_home: &Path) -> std::io::Result<()> { ... }
```
