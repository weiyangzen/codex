# config.rs 研究文档

## 场景与职责

该文件提供了用于测试的 Codex 配置文件（`config.toml`）生成功能。在集成测试中，每个测试需要独立的配置环境，包括：
1. 独立的 `CODEX_HOME` 目录
2. 指向 mock 模型服务器的 API 端点
3. 特定的功能开关（feature flags）
4. 模型提供商配置

该模块通过程序化生成 `config.toml` 文件，确保测试的隔离性和可重复性。

## 功能点目的

1. **隔离测试环境**：每个测试使用独立的配置目录
2. **Mock 服务器集成**：自动配置指向 mock 模型服务器的端点
3. **功能开关控制**：支持启用/禁用特定功能进行测试
4. **多提供商支持**：支持配置 OpenAI 或自定义 mock 提供商

## 具体技术实现

### 核心函数签名

```rust
pub fn write_mock_responses_config_toml(
    codex_home: &Path,           // 配置目录路径
    server_uri: &str,            // Mock 模型服务器 URI
    feature_flags: &BTreeMap<Feature, bool>,  // 功能开关映射
    auto_compact_limit: i64,     // 自动压缩 token 限制
    requires_openai_auth: Option<bool>,  // 是否需要 OpenAI 认证
    model_provider_id: &str,     // 模型提供商 ID
    compact_prompt: &str,        // 压缩提示词
) -> std::io::Result<()>
```

### 配置生成流程

```rust
// Phase 1: build the features block for config.toml.
let mut features = BTreeMap::new();
for (feature, enabled) in feature_flags {
    features.insert(*feature, *enabled);
}
let feature_entries = features
    .into_iter()
    .map(|(feature, enabled)| {
        let key = FEATURES
            .iter()
            .find(|spec| spec.id == feature)
            .map(|spec| spec.key)
            .unwrap_or_else(|| panic!("missing feature key for {feature:?}"));
        format!("{key} = {enabled}")
    })
    .collect::<Vec<_>>()
    .join("\n");
```

### 生成的配置结构

```toml
model = "mock-model"
approval_policy = "never"
sandbox_mode = "read-only"
compact_prompt = "{compact_prompt}"
model_auto_compact_token_limit = {auto_compact_limit}

model_provider = "{model_provider_id}"
openai_base_url = "{server_uri}/v1"  # 仅当 provider 为 openai 时

[features]
{feature_entries}

[model_providers.{model_provider_id}]
name = "{provider_name}"
base_url = "{server_uri}/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
supports_websockets = false
{requires_line}  # requires_openai_auth = true（可选）
```

### 提供商配置逻辑

```rust
let requires_line = match requires_openai_auth {
    Some(true) => "requires_openai_auth = true\n".to_string(),
    Some(false) | None => String::new(),
};
let provider_name = if matches!(requires_openai_auth, Some(true)) {
    "OpenAI"
} else {
    "Mock provider for test"
};
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/config.rs`

### 导出位置
- `lib.rs`: `pub use config::write_mock_responses_config_toml;`

### 依赖的 Codex 内部类型
- `codex_core::features::{FEATURES, Feature}` - 功能开关定义

### 使用示例

```rust
use codex_core::features::Feature;
use std::collections::BTreeMap;

let mut features = BTreeMap::new();
features.insert(Feature::Personality, true);
features.insert(Feature::WebSearch, false);

write_mock_responses_config_toml(
    codex_home.path(),
    &server.uri(),
    &features,
    10000,                    // auto_compact_limit
    Some(false),              // requires_openai_auth
    "mock-provider",          // model_provider_id
    "You are a helpful assistant.",  // compact_prompt
)?;
```

## 依赖与外部交互

### 外部 crate 依赖
- 仅使用标准库 `std::collections::BTreeMap` 和 `std::path::Path`

### Codex 内部依赖
```
config.rs
└── codex_core::features
    ├── FEATURES: &'static [FeatureSpec]  # 功能规格列表
    └── Feature: enum                     # 功能标识符
```

### 功能开关映射

`FEATURES` 数组将 `Feature` enum 映射到配置键名：

```rust
// 假设 FEATURES 包含：
// FeatureSpec { id: Feature::Personality, key: "personality" }
// FeatureSpec { id: Feature::WebSearch, key: "web_search" }

// 生成的配置：
[features]
personality = true
web_search = false
```

## 风险、边界与改进建议

### 风险
1. **硬编码配置值**：`model = "mock-model"`、`approval_policy = "never"` 等值是硬编码的，不够灵活
2. **FEATURES 遍历 panic**：如果传入的 feature 在 FEATURES 中找不到，会直接 panic
3. **字符串格式化风险**：`compact_prompt` 直接插入到配置字符串中，如果包含特殊字符可能破坏 TOML 格式

### 边界
- 仅支持生成特定结构的配置，不支持所有 config.toml 选项
- 不支持生成多个模型提供商配置
- 不支持生成复杂的嵌套配置（如代理设置、日志配置等）
- `openai_base_url` 仅在 `model_provider_id == "openai"` 时生成

### 改进建议

1. **使用 TOML 库生成**：
```rust
use toml::Value;

let config = toml::toml! {
    model = model_name,
    approval_policy = approval_policy,
    // ...
};
std::fs::write(path, toml::to_string(&config)?)?;
```

2. **配置模板支持**：
```rust
pub struct ConfigTemplate {
    pub model: Option<String>,
    pub approval_policy: Option<String>,
    pub sandbox_mode: Option<String>,
    // ...
}

pub fn write_config_with_template(
    codex_home: &Path,
    template: ConfigTemplate,
) -> Result<()> { ... }
```

3. **验证生成的配置**：
```rust
pub fn write_mock_responses_config_toml(...) -> Result<()> {
    // 生成配置...
    // 验证生成的 TOML 是否可解析
    let _: ConfigToml = toml::from_str(&config_content)?;
    Ok(())
}
```

4. **支持更多配置选项**：
```rust
pub fn write_mock_responses_config_toml(
    // ... 现有参数
    additional_settings: Option<HashMap<String, toml::Value>>,
) -> Result<()>
```

5. **转义处理**：
```rust
fn escape_toml_string(s: &str) -> String {
    // 处理包含引号、换行符等特殊字符的字符串
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}
```
