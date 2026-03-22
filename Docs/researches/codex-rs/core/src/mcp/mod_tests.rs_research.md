# mod_tests.rs 研究文档

## 场景与职责

`mod_tests.rs` 是 `codex-rs/core/src/mcp/mod.rs` 模块的单元测试文件，负责验证 MCP 核心模块的各项功能，包括工具名称解析、工具分组、插件来源追踪、Codex Apps URL 构建以及 MCP 服务器配置合并等关键逻辑。

### 核心职责
1. **工具名称解析测试**：验证 `split_qualified_tool_name` 函数的正确性
2. **工具分组测试**：验证 `group_tools_by_server` 函数的分组逻辑
3. **插件来源追踪测试**：验证 `ToolPluginProvenance` 的构建和查询
4. **Codex Apps 集成测试**：验证 URL 构建和服务器配置生成
5. **配置合并测试**：验证用户配置与插件配置的合并策略

---

## 功能点目的

### 1. 工具名称解析测试

**目的**：确保工具名称限定符（qualified name）能正确解析为服务器名和工具名。

**测试覆盖**：
- 标准格式：`mcp__alpha__do_thing` → `("alpha", "do_thing")`
- 嵌套工具名：`mcp__alpha__nested__op` → `("alpha", "nested__op")`
- 无效格式拒绝：错误前缀、空工具名等

### 2. 工具分组测试

**目的**：验证工具能按服务器正确分组，便于按服务器维度管理和展示。

**测试覆盖**：
- 多服务器工具分组
- 嵌套工具名保留
- 空输入处理

### 3. 插件来源追踪测试

**目的**：验证工具来源追踪系统能正确记录工具来自哪个插件/连接器。

**测试覆盖**：
- 按 connector_id 分组
- 按 mcp_server_name 分组
- 多插件来源去重和排序

### 4. Codex Apps URL 构建测试

**目的**：确保 Codex Apps MCP 服务器的 URL 能根据不同的基础 URL 正确构建。

**测试覆盖**：
- 生产环境 URL（chatgpt.com）
- 本地开发 URL
- 已有 backend-api 路径的 URL

### 5. 配置合并测试

**目的**：验证用户配置的 MCP 服务器优先级高于插件配置。

**测试覆盖**：
- 用户配置覆盖插件配置
- 插件新增服务器保留
- 配置持久化验证

---

## 具体技术实现

### 测试辅助函数

```rust
// 创建临时文件和目录
fn write_file(path: &Path, contents: &str) {
    fs::create_dir_all(path.parent().expect("file should have a parent")).unwrap();
    fs::write(path, contents).unwrap();
}

// 构建插件测试配置
fn plugin_config_toml() -> String {
    let mut root = toml::map::Map::new();
    
    let mut features = toml::map::Map::new();
    features.insert("plugins".to_string(), Value::Boolean(true));
    root.insert("features".to_string(), Value::Table(features));
    
    let mut plugin = toml::map::Map::new();
    plugin.insert("enabled".to_string(), Value::Boolean(true));
    
    let mut plugins = toml::map::Map::new();
    plugins.insert("sample@test".to_string(), Value::Table(plugin));
    root.insert("plugins".to_string(), Value::Table(plugins));
    
    toml::to_string(&Value::Table(root)).expect("plugin test config should serialize")
}

// 创建测试工具对象
fn make_tool(name: &str) -> Tool {
    Tool {
        name: name.to_string(),
        title: None,
        description: None,
        input_schema: serde_json::json!({"type": "object", "properties": {}}),
        output_schema: None,
        annotations: None,
        icons: None,
        meta: None,
    }
}
```

### 测试用例详解

#### 1. 工具名称解析测试

```rust
#[test]
fn split_qualified_tool_name_returns_server_and_tool() {
    assert_eq!(
        split_qualified_tool_name("mcp__alpha__do_thing"),
        Some(("alpha".to_string(), "do_thing".to_string()))
    );
}

#[test]
fn split_qualified_tool_name_rejects_invalid_names() {
    assert_eq!(split_qualified_tool_name("other__alpha__do_thing"), None);
    assert_eq!(split_qualified_tool_name("mcp__alpha__"), None);
}
```

**测试逻辑**：
- 验证正确的前缀 `mcp` 被识别
- 验证服务器名和工具名的正确提取
- 验证错误前缀被拒绝
- 验证空工具名被拒绝

#### 2. 工具分组测试

```rust
#[test]
fn group_tools_by_server_strips_prefix_and_groups() {
    let mut tools = HashMap::new();
    tools.insert("mcp__alpha__do_thing".to_string(), make_tool("do_thing"));
    tools.insert("mcp__alpha__nested__op".to_string(), make_tool("nested__op"));
    tools.insert("mcp__beta__do_other".to_string(), make_tool("do_other"));

    let mut expected_alpha = HashMap::new();
    expected_alpha.insert("do_thing".to_string(), make_tool("do_thing"));
    expected_alpha.insert("nested__op".to_string(), make_tool("nested__op"));

    let mut expected_beta = HashMap::new();
    expected_beta.insert("do_other".to_string(), make_tool("do_other"));

    let mut expected = HashMap::new();
    expected.insert("alpha".to_string(), expected_alpha);
    expected.insert("beta".to_string(), expected_beta);

    assert_eq!(group_tools_by_server(&tools), expected);
}
```

**测试逻辑**：
- 创建包含多个服务器工具的工具列表
- 验证按服务器正确分组
- 验证嵌套工具名（含 `__`）被正确处理

#### 3. 插件来源追踪测试

```rust
#[test]
fn tool_plugin_provenance_collects_app_and_mcp_sources() {
    let provenance = ToolPluginProvenance::from_capability_summaries(&[
        PluginCapabilitySummary {
            display_name: "alpha-plugin".to_string(),
            app_connector_ids: vec![AppConnectorId("connector_example".to_string())],
            mcp_server_names: vec!["alpha".to_string()],
            ..PluginCapabilitySummary::default()
        },
        PluginCapabilitySummary {
            display_name: "beta-plugin".to_string(),
            app_connector_ids: vec![
                AppConnectorId("connector_example".to_string()),
                AppConnectorId("connector_gmail".to_string()),
            ],
            mcp_server_names: vec!["beta".to_string()],
            ..PluginCapabilitySummary::default()
        },
    ]);

    assert_eq!(
        provenance,
        ToolPluginProvenance {
            plugin_display_names_by_connector_id: HashMap::from([
                ("connector_example".to_string(), vec!["alpha-plugin".to_string(), "beta-plugin".to_string()]),
                ("connector_gmail".to_string(), vec!["beta-plugin".to_string()]),
            ]),
            plugin_display_names_by_mcp_server_name: HashMap::from([
                ("alpha".to_string(), vec!["alpha-plugin".to_string()]),
                ("beta".to_string(), vec!["beta-plugin".to_string()]),
            ]),
        }
    );
}
```

**测试逻辑**：
- 创建包含 connector_id 和 mcp_server_name 的插件摘要
- 验证按 connector_id 正确分组（支持多对多关系）
- 验证按 mcp_server_name 正确分组
- 验证多个插件来源的排序和去重

#### 4. Codex Apps URL 构建测试

```rust
#[test]
fn codex_apps_mcp_url_for_base_url_keeps_existing_paths() {
    assert_eq!(
        codex_apps_mcp_url_for_base_url("https://chatgpt.com/backend-api"),
        "https://chatgpt.com/backend-api/wham/apps"
    );
    assert_eq!(
        codex_apps_mcp_url_for_base_url("https://chat.openai.com"),
        "https://chat.openai.com/backend-api/wham/apps"
    );
    assert_eq!(
        codex_apps_mcp_url_for_base_url("http://localhost:8080/api/codex"),
        "http://localhost:8080/api/codex/apps"
    );
    assert_eq!(
        codex_apps_mcp_url_for_base_url("http://localhost:8080"),
        "http://localhost:8080/api/codex/apps"
    );
}
```

**测试逻辑**：
- 验证已有 backend-api 路径的 URL 正确追加 `/wham/apps`
- 验证 chat.openai.com 自动添加 backend-api 路径
- 验证已有 /api/codex 路径的 URL 正确追加 `/apps`
- 验证普通 URL 添加完整路径 `/api/codex/apps`

#### 5. 配置合并测试

```rust
#[tokio::test]
async fn effective_mcp_servers_include_plugins_without_overriding_user_config() {
    // 创建临时目录结构
    let codex_home = tempfile::tempdir().expect("tempdir");
    let plugin_root = codex_home.path().join("plugins/cache").join("test/sample/local");
    
    // 写入插件配置
    write_file(&plugin_root.join(".codex-plugin/plugin.json"), r#"{"name":"sample"}"#);
    write_file(&plugin_root.join(".mcp.json"), r#"{
        "mcpServers": {
            "sample": { "type": "http", "url": "https://plugin.example/mcp" },
            "docs": { "type": "http", "url": "https://docs.example/mcp" }
        }
    }"#);
    
    // 用户配置覆盖 sample 服务器
    let mut configured_servers = config.mcp_servers.get().clone();
    configured_servers.insert(
        "sample".to_string(),
        McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url: "https://user.example/mcp".to_string(),
                // ...
            },
            // ...
        },
    );
    
    // 验证：用户配置优先
    let sample = effective.get("sample").expect("user server should exist");
    match &sample.transport {
        McpServerTransportConfig::StreamableHttp { url, .. } => {
            assert_eq!(url, "https://user.example/mcp");
        }
        other => panic!("expected streamable http transport, got {other:?}"),
    }
    
    // 验证：插件新增服务器保留
    let docs = effective.get("docs").expect("plugin server should exist");
    match &docs.transport {
        McpServerTransportConfig::StreamableHttp { url, .. } => {
            assert_eq!(url, "https://docs.example/mcp");
        }
        other => panic!("expected streamable http transport, got {other:?}"),
    }
}
```

**测试逻辑**：
- 创建包含插件配置和用户配置的临时环境
- 验证同名服务器（sample）用户配置优先
- 验证插件独有的服务器（docs）被保留

---

## 关键代码路径与文件引用

### 测试模块结构

```
mod.rs
└── #[cfg(test)]
    └── mod tests
        └── #[path = "mod_tests.rs"]
            ├── 测试辅助函数
            │   ├── write_file
            │   ├── plugin_config_toml
            │   └── make_tool
            └── 测试用例
                ├── split_qualified_tool_name_returns_server_and_tool
                ├── split_qualified_tool_name_rejects_invalid_names
                ├── group_tools_by_server_strips_prefix_and_groups
                ├── tool_plugin_provenance_collects_app_and_mcp_sources
                ├── codex_apps_mcp_url_for_base_url_keeps_existing_paths
                ├── codex_apps_mcp_url_uses_legacy_codex_apps_path
                ├── codex_apps_server_config_uses_legacy_codex_apps_path
                └── effective_mcp_servers_include_plugins_without_overriding_user_config
```

### 被测试代码路径

| 测试函数 | 被测试代码 | 所在文件 |
|---------|-----------|---------|
| `split_qualified_tool_name_*` | `split_qualified_tool_name` | `mod.rs:306-318` |
| `group_tools_by_server_*` | `group_tools_by_server` | `mod.rs:320-333` |
| `tool_plugin_provenance_*` | `ToolPluginProvenance::from_capability_summaries` | `mod.rs:57-91` |
| `codex_apps_mcp_url_*` | `codex_apps_mcp_url_for_base_url` | `mod.rs:139-148` |
| `codex_apps_server_config_*` | `codex_apps_mcp_server_config`, `with_codex_apps_mcp` | `mod.rs:154-197` |
| `effective_mcp_servers_*` | `effective_mcp_servers`, `configured_mcp_servers` | `mod.rs:226-250` |

### 依赖类型

```rust
// 来自被测试模块
use super::*;

// 配置相关
use crate::config::CONFIG_TOML_FILE;
use crate::config::ConfigBuilder;

// 特性开关
use crate::features::Feature;

// 插件相关
use crate::plugins::AppConnectorId;
use crate::plugins::PluginCapabilitySummary;

// 测试工具
use pretty_assertions::assert_eq;
use std::fs;
use std::path::Path;
use toml::Value;
```

---

## 依赖与外部交互

### 测试环境依赖

1. **临时文件系统**
   - 使用 `tempfile::tempdir()` 创建隔离的测试环境
   - 模拟 `~/.codex` 目录结构

2. **插件系统**
   - 依赖 `PluginsManager` 加载插件配置
   - 需要 `.codex-plugin/plugin.json` 和 `.mcp.json` 文件

3. **配置系统**
   - 使用 `ConfigBuilder` 构建测试配置
   - 依赖 `CONFIG_TOML_FILE` 常量

### 异步测试

```rust
#[tokio::test]
async fn effective_mcp_servers_include_plugins_without_overriding_user_config() {
    // 异步配置加载
    let mut config = ConfigBuilder::default()
        .codex_home(codex_home.path().to_path_buf())
        .build()
        .await
        .expect("config should load");
    // ...
}
```

---

## 风险、边界与改进建议

### 当前测试覆盖评估

| 功能模块 | 覆盖度 | 说明 |
|---------|-------|------|
| 工具名称解析 | ✅ 完整 | 正常/异常路径均覆盖 |
| 工具分组 | ✅ 完整 | 多服务器、嵌套名覆盖 |
| 插件来源追踪 | ✅ 完整 | 多对多关系覆盖 |
| Codex Apps URL | ✅ 完整 | 多种 URL 模式覆盖 |
| 配置合并 | ✅ 完整 | 优先级策略覆盖 |

### 缺失测试场景

1. **错误处理路径**
   - 无效 TOML 配置的处理
   - 插件加载失败的回退行为
   - 网络超时场景（Codex Apps URL 构建）

2. **并发场景**
   - 多线程环境下的配置访问
   - 插件动态更新场景

3. **边界值测试**
   ```rust
   // 建议补充
   #[test]
   fn split_qualified_tool_name_handles_empty() {
       assert_eq!(split_qualified_tool_name(""), None);
       assert_eq!(split_qualified_tool_name("mcp"), None);
       assert_eq!(split_qualified_tool_name("mcp__"), None);
   }
   
   #[test]
   fn group_tools_by_server_handles_empty() {
       let empty: HashMap<String, Tool> = HashMap::new();
       assert_eq!(group_tools_by_server(&empty), HashMap::new());
   }
   ```

4. **Codex Apps 认证场景**
   - Bearer Token 环境变量设置/未设置
   - AuthManager Token 获取成功/失败

### 改进建议

1. **使用 insta 快照测试**
   ```rust
   // 建议：对复杂结构使用快照测试
   #[test]
   fn tool_plugin_provenance_snapshot() {
       let provenance = // ...
       insta::assert_debug_snapshot!(provenance);
   }
   ```

2. **参数化测试**
   ```rust
   // 建议：使用 test_case 宏减少重复
   #[test_case("https://chatgpt.com", "https://chatgpt.com/backend-api/wham/apps")]
   #[test_case("http://localhost:8080", "http://localhost:8080/api/codex/apps")]
   fn codex_apps_url_builds_correctly(input: &str, expected: &str) {
       assert_eq!(codex_apps_mcp_url_for_base_url(input), expected);
   }
   ```

3. **测试数据工厂**
   ```rust
   // 建议：提取可复用的测试数据构建器
   struct TestPluginBuilder { /* ... */ }
   impl TestPluginBuilder {
       fn with_mcp_server(self, name: &str, url: &str) -> Self { /* ... */ }
       fn build(self) -> PluginCapabilitySummary { /* ... */ }
   }
   ```

4. **集成测试迁移**
   - `effective_mcp_servers_include_plugins_without_overriding_user_config` 涉及多个组件
   - 建议迁移到 `tests/` 目录作为集成测试

### 潜在风险

1. **测试间依赖**
   - 当前测试使用独立临时目录，无共享状态
   - ✅ 风险较低

2. **环境敏感性**
   - 依赖文件系统操作
   - 依赖 TOML 序列化/反序列化
   - 建议：增加更多错误路径覆盖

3. **维护成本**
   - 手动构建期望结果（如 `expected_alpha`）在结构变更时需要同步更新
   - 建议：对稳定结构使用快照测试
