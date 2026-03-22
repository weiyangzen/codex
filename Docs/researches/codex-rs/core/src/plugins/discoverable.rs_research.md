# discoverable.rs 研究文档

## 场景与职责

`discoverable.rs` 负责**工具建议（Tool Suggest）功能中的可发现插件管理**。该模块根据用户配置和 OpenAI 精选插件市场，筛选出适合向用户推荐的未安装插件，用于在用户输入时提供智能插件推荐。

### 核心职责
1. **插件发现**：从 OpenAI 精选市场中筛选可推荐插件
2. **白名单控制**：维护允许推荐的插件白名单
3. **配置感知**：读取用户配置的 `tool_suggest.discoverables` 设置
4. **能力聚合**：收集插件的技能、MCP 服务器和应用连接器信息

---

## 功能点目的

### 1. 可发现插件列表生成
- **函数**：`list_tool_suggest_discoverable_plugins()`
- **目的**：返回适合向用户推荐的插件列表
- **筛选逻辑**：
  - 排除已安装的插件
  - 仅包含白名单中的插件或用户明确配置的插件
  - 按显示名称排序

### 2. 白名单机制
- **常量**：`TOOL_SUGGEST_DISCOVERABLE_PLUGIN_ALLOWLIST`
- **目的**：控制哪些插件可以被推荐
- **当前白名单**：
  - `github@openai-curated`
  - `notion@openai-curated`
  - `slack@openai-curated`
  - `gmail@openai-curated`
  - `google-calendar@openai-curated`
  - `google-docs@openai-curated`
  - `google-drive@openai-curated`
  - `google-sheets@openai-curated`
  - `google-slides@openai-curated`

### 3. 配置集成
- 读取 `Config.tool_suggest.discoverables` 配置
- 支持 `ToolSuggestDiscoverableType::Plugin` 类型的发现项
- 用户可通过配置添加额外的可发现插件

---

## 具体技术实现

### 核心数据结构

```rust
// 从配置中筛选 Plugin 类型的发现项
let configured_plugin_ids = config
    .tool_suggest
    .discoverables
    .iter()
    .filter(|discoverable| discoverable.kind == ToolSuggestDiscoverableType::Plugin)
    .map(|discoverable| discoverable.id.as_str())
    .collect::<HashSet<_>>();
```

### 筛选算法

```rust
for plugin in curated_marketplace.plugins {
    // 跳过已安装的插件
    if plugin.installed {
        continue;
    }
    
    // 跳过不在白名单且未配置的插件
    if !TOOL_SUGGEST_DISCOVERABLE_PLUGIN_ALLOWLIST.contains(&plugin.id.as_str())
        && !configured_plugin_ids.contains(plugin.id.as_str())
    {
        continue;
    }
    
    // 加载插件详情并加入结果
    match plugins_manager.read_plugin_for_config(...) {
        Ok(plugin) => discoverable_plugins.push(plugin.plugin.into()),
        Err(err) => warn!(...),
    }
}

// 按显示名称排序
discoverable_plugins.sort_by(|left, right| {
    left.display_name
        .cmp(&right.display_name)
        .then_with(|| left.config_name.cmp(&right.config_name))
});
```

### 白名单常量定义

```rust
const TOOL_SUGGEST_DISCOVERABLE_PLUGIN_ALLOWLIST: &[&str] = &[
    "github@openai-curated",
    "notion@openai-curated",
    "slack@openai-curated",
    "gmail@openai-curated",
    "google-calendar@openai-curated",
    "google-docs@openai-curated",
    "google-drive@openai-curated",
    "google-sheets@openai-curated",
    "google-slides@openai-curated",
];
```

---

## 关键代码路径与文件引用

### 函数调用图

```
discoverable.rs
└── list_tool_suggest_discoverable_plugins(config)
    ├── Config.features.enabled(Feature::Plugins)  [功能开关检查]
    ├── PluginsManager::new(config.codex_home.clone())
    ├── config.tool_suggest.discoverables  [读取配置]
    ├── plugins_manager.list_marketplaces_for_config(config, &[])
    │   └── 查找 openai-curated 市场
    ├── plugins_manager.read_plugin_for_config(config, &PluginReadRequest)
    │   ├── load_marketplace()
    │   ├── load_plugin_manifest()
    │   ├── load_skills_from_roots()
    │   └── load_plugin_apps()
    └── 排序并返回 PluginCapabilitySummary 列表
```

### 依赖模块

| 模块 | 用途 |
|------|------|
| `manager::PluginsManager` | 插件管理器，用于读取插件详情 |
| `manager::PluginCapabilitySummary` | 插件能力摘要 |
| `config::Config` | 配置读取 |
| `config::types::ToolSuggestDiscoverableType` | 发现类型枚举 |
| `features::Feature` | 功能开关检查 |

### 类型转换

```rust
// PluginDetail → PluginCapabilitySummary
impl From<PluginDetail> for PluginCapabilitySummary {
    fn from(value: PluginDetail) -> Self {
        Self {
            config_name: value.id,
            display_name: value.name,
            description: prompt_safe_plugin_description(value.description.as_deref()),
            has_skills: !value.skills.is_empty(),
            mcp_server_names: value.mcp_server_names,
            app_connector_ids: value.apps,
        }
    }
}
```

---

## 依赖与外部交互

### 配置依赖

```toml
# 示例配置
[features]
plugins = true

[tool_suggest]
discoverables = [
    { type = "plugin", id = "custom-plugin@openai-curated" }
]
```

### 外部调用

| 被调用方 | 方法 | 用途 |
|---------|------|------|
| `PluginsManager` | `list_marketplaces_for_config()` | 获取市场列表 |
| `PluginsManager` | `read_plugin_for_config()` | 读取插件详情 |
| `tracing` | `warn!()` | 警告日志 |

### 错误处理

- 插件加载失败时记录警告日志，但不中断流程
- 返回 `anyhow::Result`，错误向上传播

---

## 风险、边界与改进建议

### 已知风险

1. **白名单维护成本**
   - 白名单硬编码在源码中，新增插件需要发版
   - **建议**：考虑从远程配置或 marketplace 读取白名单

2. **性能问题**
   - 每个插件都调用 `read_plugin_for_config()`，涉及多次文件 IO
   - 市场插件多时可能成为瓶颈
   - **建议**：增加缓存或批量读取接口

3. **排序稳定性**
   - 当前按 `display_name` 然后 `config_name` 排序
   - 如显示名称相同，排序可能不稳定
   - **建议**：增加稳定排序键（如插件 ID）

### 边界条件

| 场景 | 当前行为 |
|------|---------|
| Plugins 功能禁用 | 返回空列表 |
| openai-curated 市场不存在 | 返回空列表 |
| 所有插件已安装 | 返回空列表 |
| 插件加载失败 | 记录警告，跳过该插件 |
| 白名单为空 | 仅返回用户配置的插件 |

### 改进建议

1. **配置化白名单**
   ```rust
   // 建议：从配置读取白名单
   let allowlist = config
       .tool_suggest
       .discoverable_plugin_allowlist
       .unwrap_or_else(|| DEFAULT_ALLOWLIST.to_vec());
   ```

2. **异步加载**
   ```rust
   // 建议：并行加载插件详情
   let futures = curated_plugins.iter().map(|p| async {
       plugins_manager.read_plugin_for_config(config, p).await
   });
   let results = futures::future::join_all(futures).await;
   ```

3. **限流保护**
   ```rust
   // 建议：限制返回数量
   discoverable_plugins.into_iter().take(MAX_DISCOVERABLE_PLUGINS)
   ```

4. **埋点监控**
   - 记录推荐展示、点击等事件
   - 分析白名单插件的实际使用率

### 测试建议

测试文件：`discoverable_tests.rs`

| 已有测试 | 描述 |
|---------|------|
| `list_tool_suggest_discoverable_plugins_returns_uninstalled_curated_plugins` | 基本功能测试 |
| `list_tool_suggest_discoverable_plugins_returns_empty_when_plugins_feature_disabled` | 功能开关测试 |
| `list_tool_suggest_discoverable_plugins_normalizes_description` | 描述规范化测试 |
| `list_tool_suggest_discoverable_plugins_omits_installed_curated_plugins` | 已安装过滤测试 |
| `list_tool_suggest_discoverable_plugins_includes_configured_plugin_ids` | 配置扩展测试 |

**待补充测试**：
- 白名单边界测试（空白名单、全匹配）
- 性能测试（大量插件场景）
- 并发测试
