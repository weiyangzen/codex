# discoverable_tests.rs 研究文档

## 场景与职责

`discoverable_tests.rs` 是 `discoverable.rs` 的单元测试模块，负责验证工具建议功能中可发现插件列表生成的正确性。测试通过构造模拟的插件市场环境，验证筛选、过滤、排序等核心逻辑。

### 测试范围
1. **基本功能**：验证未安装的精选插件被正确返回
2. **功能开关**：验证 Plugins 功能禁用时返回空列表
3. **描述规范化**：验证插件描述的空白字符被正确处理
4. **已安装过滤**：验证已安装插件被正确排除
5. **配置扩展**：验证用户配置的额外插件被包含

---

## 功能点目的

### 1. 基本功能测试
- **测试函数**：`list_tool_suggest_discoverable_plugins_returns_uninstalled_curated_plugins`
- **目的**：验证正常场景下返回未安装的精选插件
- **验证点**：
  - 返回正确的插件 ID 格式（`slack@openai-curated`）
  - 包含技能、MCP 服务器、应用连接器信息

### 2. 功能开关测试
- **测试函数**：`list_tool_suggest_discoverable_plugins_returns_empty_when_plugins_feature_disabled`
- **目的**：验证 `features.plugins = false` 时返回空列表
- **验证点**：无 plugins 配置时返回空 Vec

### 3. 描述规范化测试
- **测试函数**：`list_tool_suggest_discoverable_plugins_normalizes_description`
- **目的**：验证描述中的多余空白被规范化
- **输入**：`"  Plugin\n   with   extra   spacing  "`
- **期望输出**：`"Plugin with extra spacing"`

### 4. 已安装过滤测试
- **测试函数**：`list_tool_suggest_discoverable_plugins_omits_installed_curated_plugins`
- **目的**：验证已安装的插件不被推荐
- **流程**：
  1. 创建市场和插件
  2. 安装 slack 插件
  3. 重新加载配置
  4. 验证返回空列表

### 5. 配置扩展测试
- **测试函数**：`list_tool_suggest_discoverable_plugins_includes_configured_plugin_ids`
- **目的**：验证用户配置的 `tool_suggest.discoverables` 被包含
- **配置示例**：
  ```toml
  [tool_suggest]
  discoverables = [{ type = "plugin", id = "sample@openai-curated" }]
  ```

---

## 具体技术实现

### 测试辅助工具

测试依赖 `test_support` 模块提供的辅助函数：

```rust
use crate::plugins::test_support::{
    load_plugins_config,           // 异步加载配置
    write_curated_plugin_sha,      // 写入 SHA 文件
    write_file,                    // 通用文件写入
    write_openai_curated_marketplace,  // 创建市场
    write_plugins_feature_config,  // 启用 plugins 功能
};
```

### 测试数据构造

```rust
// 创建临时 codex_home
let codex_home = tempdir().expect("tempdir should succeed");

// 创建精选插件市场（包含 sample 和 slack 插件）
let curated_root = crate::plugins::curated_plugins_repo_path(codex_home.path());
write_openai_curated_marketplace(&curated_root, &["sample", "slack"]);

// 启用 plugins 功能
write_plugins_feature_config(codex_home.path());

// 加载配置
let config = load_plugins_config(codex_home.path()).await;
```

### 插件安装流程（已安装过滤测试）

```rust
// 安装插件
PluginsManager::new(codex_home.path().to_path_buf())
    .install_plugin(PluginInstallRequest {
        plugin_name: "slack".to_string(),
        marketplace_path: AbsolutePathBuf::try_from(
            curated_root.join(".agents/plugins/marketplace.json"),
        ).expect("marketplace path"),
    })
    .await
    .expect("plugin should install");

// 重新加载配置（安装会修改配置）
let refreshed_config = load_plugins_config(codex_home.path()).await;

// 验证已安装插件不在推荐列表
let discoverable_plugins = list_tool_suggest_discoverable_plugins(&refreshed_config).unwrap();
assert_eq!(discoverable_plugins, Vec::<DiscoverablePluginInfo>::new());
```

### 类型转换

```rust
// PluginCapabilitySummary → DiscoverablePluginInfo
let discoverable_plugins = list_tool_suggest_discoverable_plugins(&config)
    .unwrap()
    .into_iter()
    .map(DiscoverablePluginInfo::from)
    .collect::<Vec<_>>();
```

---

## 关键代码路径与文件引用

### 被测函数

| 被测函数 | 所在文件 | 测试函数 |
|---------|---------|---------|
| `list_tool_suggest_discoverable_plugins()` | `discoverable.rs` | 所有测试函数 |
| `PluginsManager::install_plugin()` | `manager.rs` | `omits_installed_curated_plugins` |
| `load_plugins_config()` | `test_support.rs` | 所有测试函数 |

### 测试辅助函数（test_support.rs）

| 函数 | 用途 |
|------|------|
| `write_openai_curated_marketplace(root, plugin_names)` | 创建市场 JSON 和插件文件 |
| `write_curated_plugin(root, plugin_name)` | 创建单个插件结构 |
| `write_plugins_feature_config(codex_home)` | 写入启用 plugins 的配置 |
| `write_curated_plugin_sha(codex_home)` | 写入 SHA 文件 |
| `load_plugins_config(codex_home).await` | 异步加载完整配置 |

### 测试数据结构

```rust
// 期望的插件信息结构
DiscoverablePluginInfo {
    id: "slack@openai-curated".to_string(),
    name: "slack".to_string(),
    description: Some("Plugin that includes skills, MCP servers, and app connectors".to_string()),
    has_skills: true,
    mcp_server_names: vec!["sample-docs".to_string()],
    app_connector_ids: vec!["connector_calendar".to_string()],
}
```

---

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::tempdir` | 创建隔离的临时目录 |
| `pretty_assertions::assert_eq` | 美观的断言失败输出 |
| `tokio::test` | 异步测试运行时 |

### 文件系统布局

测试创建的临时目录结构：

```
{temp_dir}/
├── .tmp/plugins/           # 精选插件仓库路径
│   └── .agents/plugins/
│       └── marketplace.json    # 市场定义
│   └── plugins/
│       ├── sample/
│       │   └── .codex-plugin/
│       │       └── plugin.json
│       │   ├── skills/SKILL.md
│       │   ├── .mcp.json
│       │   └── .app.json
│       └── slack/
│           └── ...
├── plugins/                # 用户插件安装目录
│   └── cache/
│       └── openai-curated/
│           └── slack/
│               └── {version}/
└── config.toml            # 配置文件
```

### 配置示例

```toml
# write_plugins_feature_config 生成的配置
[features]
plugins = true
```

```toml
# includes_configured_plugin_ids 测试使用的配置
[features]
plugins = true

[tool_suggest]
discoverables = [{ type = "plugin", id = "sample@openai-curated" }]
```

---

## 风险、边界与改进建议

### 当前测试覆盖

| 场景 | 覆盖状态 |
|------|---------|
| 正常返回未安装插件 | ✅ |
| 功能禁用返回空 | ✅ |
| 描述规范化 | ✅ |
| 已安装过滤 | ✅ |
| 配置扩展 | ✅ |
| 白名单过滤 | ⚠️ 间接覆盖 |
| 排序验证 | ❌ |
| 多个市场 | ❌ |
| 插件加载失败 | ❌ |

### 边界条件

| 边界 | 当前测试 |
|------|---------|
| 空市场 | ❌ 未测试 |
| 所有插件已安装 | ❌ 未测试 |
| 白名单外插件 | ❌ 未直接测试 |
| 配置重复插件 | ❌ 未测试 |

### 改进建议

1. **白名单直接测试**
   ```rust
   #[tokio::test]
   async fn list_respects_allowlist() {
       // 创建白名单外插件
       write_openai_curated_marketplace(&curated_root, &["unknown-plugin"]);
       // 验证返回空列表
   }
   ```

2. **排序验证**
   ```rust
   #[tokio::test]
   async fn list_is_sorted_by_display_name() {
       // 创建多个插件，验证返回顺序
   }
   ```

3. **错误处理测试**
   ```rust
   #[tokio::test]
   async fn handles_corrupted_plugin_manifest() {
       // 创建损坏的 plugin.json
       // 验证跳过该插件，不 panic
   }
   ```

4. **性能测试**
   ```rust
   #[tokio::test]
   async fn handles_large_marketplace() {
       // 创建大量插件，验证性能可接受
   }
   ```

### 代码质量建议

1. **常量提取**：测试中的 `"sample"`、`"slack"` 可提取为常量
2. **辅助宏**：构造 `DiscoverablePluginInfo` 的代码可简化
3. **参数化测试**：使用 `rstest` 或类似库减少重复代码

### 测试稳定性

- 测试使用临时目录，相互隔离
- 异步测试使用 `tokio::test`，每个测试独立运行时
- 文件操作使用 `?` 或 `expect`，失败时提供清晰错误信息
