# web_search.rs 研究文档

## 场景与职责

`web_search.rs` 是 Codex Core 集成测试套件中专门测试**网络搜索工具配置**的测试文件。该文件验证了 `web_search` 工具的各种配置模式，包括缓存模式、实时模式、配置优先级、以及从 `config.toml` 加载的复杂配置。

### 核心职责

1. **验证搜索模式配置**：测试 `WebSearchMode::Cached` 和 `WebSearchMode::Live` 两种模式
2. **验证配置优先级**：确保 `web_search_mode` 优先于传统的特性标志
3. **测试动态模式切换**：验证根据沙箱策略在回合间切换搜索模式
4. **验证配置转发**：确保 `config.toml` 中的配置正确转发到 API 请求

---

## 功能点目的

### 1. 缓存模式设置 (`web_search_mode_cached_sets_external_web_access_false`)

**目的**：验证当 `web_search_mode` 设置为 `Cached` 时，`external_web_access` 被设置为 `false`。

**测试逻辑**：
- 配置 `WebSearchMode::Cached`
- 提交用户回合
- 验证请求中的 `web_search` 工具 `external_web_access` 为 `false`

**关键断言**：
```rust
assert_eq!(
    tool.get("external_web_access").and_then(Value::as_bool),
    Some(false),
    "web_search cached mode should force external_web_access=false"
);
```

### 2. 配置优先级 (`web_search_mode_takes_precedence_over_legacy_flags`)

**目的**：验证 `web_search_mode` 优先于传统的 `WebSearchRequest` 特性标志。

**测试逻辑**：
- 启用 `WebSearchRequest` 特性（传统上启用实时搜索）
- 同时设置 `WebSearchMode::Cached`
- 验证 `external_web_access` 为 `false`（缓存模式胜出）

### 3. 默认缓存模式 (`web_search_mode_defaults_to_cached_when_features_disabled`)

**目的**：验证当特性被禁用时，默认使用缓存模式。

**测试逻辑**：
- 显式禁用 `WebSearchCached` 和 `WebSearchRequest` 特性
- 设置 `WebSearchMode::Cached`
- 验证 `external_web_access` 为 `false`

### 4. 回合间模式切换 (`web_search_mode_updates_between_turns_with_sandbox_policy`)

**目的**：验证根据沙箱策略在回合间动态切换搜索模式。

**测试逻辑**：
- 第一回合：使用 `ReadOnly` 沙箱策略，验证 `external_web_access=false`
- 第二回合：使用 `DangerFullAccess` 沙箱策略，验证 `external_web_access=true`

**沙箱策略影响**：
| 沙箱策略 | 默认搜索模式 | external_web_access |
|---------|------------|-------------------|
| `ReadOnly` | Cached | false |
| `DangerFullAccess` | Live | true |

### 5. 配置转发 (`web_search_tool_config_from_config_toml_is_forwarded_to_request`)

**目的**：验证 `config.toml` 中的复杂配置正确转发到 API 请求。

**测试配置**：
```toml
web_search = "live"

[tools.web_search]
context_size = "high"
allowed_domains = ["example.com"]
location = { country = "US", city = "New York", timezone = "America/New_York" }
```

**预期输出**：
```json
{
    "type": "web_search",
    "external_web_access": true,
    "search_context_size": "high",
    "filters": {
        "allowed_domains": ["example.com"]
    },
    "user_location": {
        "type": "approximate",
        "country": "US",
        "city": "New York",
        "timezone": "America/New_York"
    }
}
```

---

## 具体技术实现

### 关键数据结构

#### `WebSearchMode` 枚举
```rust
pub enum WebSearchMode {
    Cached,  // 使用缓存搜索结果，external_web_access = false
    Live,    // 实时网络搜索，external_web_access = true
}
```

#### `WebSearchConfig` 结构体
```rust
pub struct WebSearchConfig {
    pub context_size: Option<WebSearchContextSize>,  // "low", "medium", "high"
    pub allowed_domains: Option<Vec<String>>,
    pub location: Option<WebSearchLocation>,
}
```

#### `WebSearchLocation` 结构体
```rust
pub struct WebSearchLocation {
    pub country: String,
    pub city: Option<String>,
    pub timezone: Option<String>,
}
```

### 工具配置生成流程

#### 1. 模式解析

```rust
// 从配置中解析 web_search_mode
let web_search_mode = config.web_search_mode.get();

// 根据沙箱策略确定默认模式
let mode = match (web_search_mode, sandbox_policy) {
    (Some(mode), _) => mode,
    (None, SandboxPolicy::ReadOnly) => WebSearchMode::Cached,
    (None, SandboxPolicy::DangerFullAccess) => WebSearchMode::Live,
    // ...
};
```

#### 2. 工具 JSON 生成

```rust
fn create_web_search_tool(
    mode: WebSearchMode,
    config: &WebSearchConfig,
) -> serde_json::Value {
    let mut tool = json!({
        "type": "web_search",
        "external_web_access": matches!(mode, WebSearchMode::Live),
    });
    
    if let Some(context_size) = &config.context_size {
        tool["search_context_size"] = json!(context_size.to_string());
    }
    
    if let Some(domains) = &config.allowed_domains {
        tool["filters"] = json!({ "allowed_domains": domains });
    }
    
    if let Some(location) = &config.location {
        tool["user_location"] = json!({
            "type": "approximate",
            "country": location.country,
            "city": location.city,
            "timezone": location.timezone,
        });
    }
    
    tool
}
```

### 配置加载流程

#### 1. TOML 解析

```rust
// config.toml
web_search = "live"  // 或 "cached"

[tools.web_search]
context_size = "high"
allowed_domains = ["example.com"]
```

#### 2. 配置合并

```rust
// 1. 从 TOML 加载原始配置
// 2. 应用环境变量覆盖
// 3. 应用特性标志调整
// 4. 生成最终工具配置
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/tools/spec.rs` | 工具配置生成，包括 `web_search` 工具 |
| `codex-rs/core/src/config/mod.rs` | 配置加载和 `web_search_mode` 处理 |
| `codex-rs/core/src/config/types.rs` | `WebSearchMode` 和 `WebSearchConfig` 定义 |

### 协议定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs` | `WebSearchMode`、`WebSearchConfig`、`WebSearchLocation` |

### 关键代码引用

#### 工具配置生成
```rust
// codex-rs/core/src/tools/spec.rs
fn create_tools_json_for_responses_api(
    tools: &ToolsConfig,
) -> Result<Option<Vec<serde_json::Value>>> {
    let mut tools_json = Vec::new();
    
    if tools.web_search_tool_type != WebSearchToolType::None {
        let web_search_tool = create_web_search_tool(
            tools.web_search_mode,
            tools.web_search_config.as_ref(),
        );
        tools_json.push(web_search_tool);
    }
    
    // ... 其他工具
    
    Ok(Some(tools_json))
}
```

#### 模式优先级处理
```rust
// codex-rs/core/src/tools/spec.rs
fn resolve_web_search_mode(
    config_mode: Option<WebSearchMode>,
    features: &Features,
    sandbox_policy: &SandboxPolicy,
) -> WebSearchMode {
    // 1. 配置模式优先
    if let Some(mode) = config_mode {
        return mode;
    }
    
    // 2. 传统特性标志（向后兼容）
    if features.is_enabled(Feature::WebSearchRequest) {
        return WebSearchMode::Live;
    }
    
    // 3. 根据沙箱策略默认
    match sandbox_policy {
        SandboxPolicy::ReadOnly => WebSearchMode::Cached,
        SandboxPolicy::DangerFullAccess => WebSearchMode::Live,
        _ => WebSearchMode::Cached,  // 默认缓存
    }
}
```

### 测试辅助函数

#### 查找 web_search 工具
```rust
fn find_web_search_tool(body: &Value) -> &Value {
    body["tools"]
        .as_array()
        .expect("request body should include tools array")
        .iter()
        .find(|tool| tool.get("type").and_then(Value::as_str) == Some("web_search"))
        .expect("tools should include a web_search tool")
}
```

---

## 依赖与外部交互

### 外部依赖

1. **serde_json**：JSON 处理和验证
2. **wiremock**：API 请求模拟
3. **tempfile**：临时配置目录

### 内部依赖

1. **codex_protocol**：配置类型定义
2. **codex_core**：工具配置生成
3. **core_test_support**：测试支持

### 配置系统交互

```rust
// 配置加载链
config.toml → ConfigBuilder → Config → ToolsConfig → API Request
```

### 特性标志交互

| 特性 | 与 web_search_mode 的关系 |
|-----|------------------------|
| `WebSearchCached` | 向后兼容，被 `web_search_mode` 覆盖 |
| `WebSearchRequest` | 向后兼容，被 `web_search_mode` 覆盖 |

---

## 风险、边界与改进建议

### 已知风险

1. **配置冲突**：`web_search_mode` 与传统特性标志可能产生混淆
2. **沙箱策略耦合**：搜索模式与沙箱策略的隐式关联可能不直观
3. **地理位置隐私**：`user_location` 配置涉及隐私考虑

### 边界情况

1. **无效配置值**：TOML 中无效的 `web_search` 值处理
2. **空域名列表**：`allowed_domains = []` 的行为
3. **部分位置信息**：仅提供国家而不提供城市/时区
4. **并发配置修改**：配置在回合间被修改的行为

### 改进建议

1. **配置验证**：
   - 添加 TOML 配置模式验证
   - 对无效 `allowed_domains` 提供警告
   - 验证 `user_location` 的时区格式

2. **文档完善**：
   - 明确说明 `web_search_mode` 与特性标志的优先级
   - 文档化沙箱策略对搜索模式的影响
   - 提供配置示例

3. **测试扩展**：
   - 添加无效配置的错误处理测试
   - 测试配置热重载
   - 测试网络超时和重试

4. **隐私保护**：
   - 考虑默认禁用 `user_location`
   - 添加配置选项控制位置精度
   - 日志中脱敏位置信息

### 向后兼容性

当前实现支持向后兼容：
```rust
// 传统方式（仍支持）
config.features.enable(Feature::WebSearchRequest)?;

// 新方式（推荐）
config.web_search_mode.set(WebSearchMode::Live)?;
```

**建议**：在文档中明确标记传统方式为弃用。

### 配置示例

推荐的 `config.toml` 配置：
```toml
# 基础模式设置
web_search = "cached"  # 或 "live"

# 高级配置（可选）
[tools.web_search]
context_size = "high"  # "low", "medium", "high"
allowed_domains = ["docs.rs", "crates.io"]

[tools.web_search.location]
country = "US"
city = "San Francisco"
timezone = "America/Los_Angeles"
```
