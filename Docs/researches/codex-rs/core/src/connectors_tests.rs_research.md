# connectors_tests.rs 研究文档

## 场景与职责

`connectors_tests.rs` 是 `connectors.rs` 的配套测试文件，使用 Rust 内置测试框架和 `pretty_assertions` 提供全面的单元测试覆盖。测试范围涵盖连接器合并、缓存管理、工具策略评估、配置约束应用等核心功能。

### 测试目标
1. 验证连接器合并逻辑的正确性（元数据合并、去重、排序）
2. 验证 MCP 工具到可访问连接器的转换
3. 验证应用启用状态和工具策略评估
4. 验证 requirements.toml 约束的应用
5. 验证缓存刷新和读取机制

---

## 功能点目的

### 1. 连接器合并测试
测试 `merge_connectors` 函数的各种场景：
- 插件占位符名称被可访问连接器名称替换
- 插件显示名称的合并与去重
- 描述、logo、分发渠道等元数据合并

### 2. MCP 工具转换测试
测试 `accessible_connectors_from_mcp_tools`：
- 从工具元数据正确提取 connector_id、connector_name
- 插件显示名称的聚合
- 非 codex_apps 服务器的工具被忽略

### 3. 缓存管理测试
测试 `refresh_accessible_connectors_cache_from_mcp_tools`：
- 缓存正确写入和读取
- 黑名单过滤在缓存前应用

### 4. 工具策略评估测试
测试 `app_tool_policy_from_apps_config`：
- 全局默认值应用
- 应用级覆盖生效
- 工具级覆盖生效
- destructive/open_world hint 的影响

### 5. Requirements 约束测试
测试云端和本地 requirements 对应用启用状态的强制约束：
- requirements 禁用可覆盖用户启用
- requirements 启用不可覆盖用户禁用

---

## 具体技术实现

### 测试辅助函数

```rust
// 创建基础 AppInfo
fn app(id: &str) -> AppInfo { ... }

// 创建带名称的 AppInfo
fn named_app(id: &str, name: &str) -> AppInfo { ... }

// 创建插件名称列表
fn plugin_names(names: &[&str]) -> Vec<String> { ... }

// 创建测试工具定义
fn test_tool_definition(tool_name: &str) -> Tool { ... }

// 创建 codex_apps 工具
fn codex_app_tool(
    tool_name: &str,
    connector_id: &str,
    connector_name: Option<&str>,
    plugin_display_names: &[&str],
) -> ToolInfo { ... }

// 缓存清理包装器
fn with_accessible_connectors_cache_cleared<R>(f: impl FnOnce() -> R) -> R { ... }

// 创建 Google Calendar 可访问连接器
fn google_calendar_accessible_connector(plugin_display_names: &[&str]) -> AppInfo { ... }

// 创建工具注解
fn annotations(destructive_hint: Option<bool>, open_world_hint: Option<bool>) -> ToolAnnotations { ... }
```

### 关键测试用例

#### 1. 连接器合并测试
```rust
#[test]
fn merge_connectors_replaces_plugin_placeholder_name_with_accessible_name() {
    let plugin = plugin_app_to_app_info(AppConnectorId("calendar".to_string()));
    let accessible = google_calendar_accessible_connector(&[]);
    let merged = merge_connectors(vec![plugin], vec![accessible]);
    // 验证：插件的占位符名称被替换为 "Google Calendar"
    assert_eq!(merged[0].name, "Google Calendar");
}
```

#### 2. 插件显示名称合并测试
```rust
#[test]
fn merge_connectors_unions_and_dedupes_plugin_display_names() {
    let mut plugin = plugin_app_to_app_info(AppConnectorId("calendar".to_string()));
    plugin.plugin_display_names = plugin_names(&["sample", "alpha", "sample"]);
    let accessible = google_calendar_accessible_connector(&["beta", "alpha"]);
    let merged = merge_connectors(vec![plugin], vec![accessible]);
    // 验证：去重并排序后为 ["alpha", "beta", "sample"]
    assert_eq!(merged[0].plugin_display_names, plugin_names(&["alpha", "beta", "sample"]));
}
```

#### 3. MCP 工具转换测试
```rust
#[test]
fn accessible_connectors_from_mcp_tools_carries_plugin_display_names() {
    let tools = HashMap::from([
        ("mcp__codex_apps__calendar_list_events".to_string(), 
         codex_app_tool("calendar_list_events", "calendar", None, &["sample", "sample"])),
        ("mcp__codex_apps__calendar_create_event".to_string(),
         codex_app_tool("calendar_create_event", "calendar", Some("Google Calendar"), &["beta", "sample"])),
    ]);
    let connectors = accessible_connectors_from_mcp_tools(&tools);
    // 验证：显示名称为去重后的 ["beta", "sample"]
    assert_eq!(connectors[0].plugin_display_names, plugin_names(&["beta", "sample"]));
}
```

#### 4. 缓存刷新测试（异步）
```rust
#[tokio::test]
async fn refresh_accessible_connectors_cache_from_mcp_tools_writes_latest_installed_apps() {
    let codex_home = tempdir().expect("tempdir should succeed");
    let mut config = ConfigBuilder::default()
        .codex_home(codex_home.path().to_path_buf())
        .build().await.expect("config should load");
    let _ = config.features.set_enabled(Feature::Apps, true);
    
    let tools = HashMap::from([
        ("mcp__codex_apps__calendar_list_events".to_string(),
         codex_app_tool("calendar_list_events", "calendar", Some("Google Calendar"), &["calendar-plugin"])),
    ]);
    
    let cached = with_accessible_connectors_cache_cleared(|| {
        refresh_accessible_connectors_cache_from_mcp_tools(&config, None, &tools);
        read_cached_accessible_connectors(&cache_key).expect("cache should be populated")
    });
    
    // 验证：缓存中包含 Google Calendar，且 openai_hidden 被黑名单过滤
    assert_eq!(cached[0].name, "Google Calendar");
}
```

#### 5. 工具策略评估测试
```rust
#[test]
fn app_tool_policy_uses_global_defaults_for_destructive_hints() {
    let apps_config = AppsConfigToml {
        default: Some(AppsDefaultConfig {
            enabled: true,
            destructive_enabled: false,  // 禁用破坏性工具
            open_world_enabled: true,
        }),
        apps: HashMap::new(),
    };
    
    let policy = app_tool_policy_from_apps_config(
        Some(&apps_config),
        Some("calendar"),
        "events/create",
        None,
        Some(&annotations(Some(true), None)),  // destructive_hint = true
    );
    
    // 验证：由于 destructive_hint=true 且 destructive_enabled=false，工具被禁用
    assert_eq!(policy.enabled, false);
}
```

#### 6. Requirements 约束测试
```rust
#[tokio::test]
async fn cloud_requirements_disable_connector_overrides_user_apps_config() {
    let codex_home = tempdir().expect("tempdir should succeed");
    std::fs::write(codex_home.path().join(CONFIG_TOML_FILE), r#"
[apps.connector_123123]
enabled = true
"#).expect("write config");
    
    let requirements = ConfigRequirementsToml {
        apps: Some(AppsRequirementsToml {
            apps: BTreeMap::from([(
                "connector_123123".to_string(),
                AppRequirementToml { enabled: Some(false) },  // 强制禁用
            )]),
        }),
        ..Default::default()
    };
    
    let config = ConfigBuilder::default()
        .cloud_requirements(CloudRequirementsLoader::new(async move { Ok(Some(requirements)) }))
        .build().await.expect("config should build");
    
    let policy = app_tool_policy(&config, Some("connector_123123"), "events.list", None, None);
    // 验证：requirements 禁用覆盖了用户配置
    assert_eq!(policy.enabled, false);
}
```

#### 7. 工具建议连接器过滤测试
```rust
#[test]
fn filter_tool_suggest_discoverable_connectors_keeps_only_plugin_backed_uninstalled_apps() {
    let filtered = filter_tool_suggest_discoverable_connectors(
        vec![
            named_app("connector_2128aebfecb84f64a069897515042a44", "Google Calendar"),
            named_app("connector_68df038e0ba48191908c8434991bbac2", "Gmail"),
        ],
        &[AppInfo { is_accessible: true, ..named_app("connector_2128aebfecb84f64a069897515042a44", "Google Calendar") }],
        &HashSet::from(["connector_2128aebfecb84f64a069897515042a44".to_string(), 
                       "connector_68df038e0ba48191908c8434991bbac2".to_string()]),
    );
    
    // 验证：已安装的 Google Calendar 被过滤，只保留 Gmail
    assert_eq!(filtered, vec![named_app("connector_68df038e0ba48191908c8434991bbac2", "Gmail")]);
}
```

---

## 关键代码路径与文件引用

### 被测试文件
| 文件 | 被测功能 |
|------|----------|
| `connectors.rs` | `merge_connectors`, `accessible_connectors_from_mcp_tools`, `app_tool_policy` 等 |

### 测试依赖
| 文件/模块 | 用途 |
|-----------|------|
| `config::ConfigBuilder` | 构建测试配置 |
| `config_loader::ConfigLayerStack` | 构建 requirements 层 |
| `tempfile::tempdir` | 临时目录用于测试配置 |
| `pretty_assertions::assert_eq` | 更好的测试失败输出 |

### 测试覆盖统计
- **单元测试**：约 30+ 个测试用例
- **异步测试**：使用 `#[tokio::test]` 测试缓存刷新等异步功能
- **集成测试**：验证配置层叠（user config + requirements）的正确性

---

## 依赖与外部交互

### 测试框架
- **标准测试框架**：`#[test]`, `#[tokio::test]`
- **断言库**：`pretty_assertions` 提供结构化的差异输出

### 模拟依赖
- **临时文件系统**：`tempfile` crate 创建隔离的测试环境
- **配置构建器**：使用 `ConfigBuilder` 构建各种测试场景的配置

### 无外部网络依赖
- 所有测试使用模拟数据，不调用真实的 ChatGPT API
- MCP 工具通过 `HashMap` 模拟，不使用真实的 MCP 连接

---

## 风险、边界与改进建议

### 测试覆盖分析

#### 已充分覆盖
- ✅ 连接器合并逻辑（元数据、显示名称、排序）
- ✅ MCP 工具到连接器的转换
- ✅ 工具策略评估（hint、覆盖层级）
- ✅ Requirements 约束应用（云端和本地）
- ✅ 缓存读写机制
- ✅ 黑名单过滤

#### 覆盖不足/潜在风险
- ⚠️ 真实的 MCP 服务器交互（需要集成测试）
- ⚠️ 缓存过期后的并发刷新场景
- ⚠️ 目录 API 失败时的降级逻辑
- ⚠️ 大规模连接器列表的性能测试

### 改进建议

1. **添加性能基准测试**
   ```rust
   // 建议添加：大规模连接器列表的合并性能测试
   #[bench]
   fn bench_merge_large_connector_list(b: &mut Bencher) { ... }
   ```

2. **添加模糊测试**
   - 对 `app_tool_policy` 使用模糊测试验证各种配置组合不会 panic

3. **改进测试隔离**
   - 当前使用全局缓存，虽然 `with_accessible_connectors_cache_cleared` 提供了隔离，但仍有风险
   - 建议：使用依赖注入替代全局状态

4. **添加并发测试**
   ```rust
   // 建议添加：并发缓存刷新测试
   #[tokio::test]
   async fn concurrent_cache_refresh_is_safe() { ... }
   ```

5. **文档测试**
   - 为公共 API 添加 `#[doc = include_str!("...")]` 或示例代码测试
