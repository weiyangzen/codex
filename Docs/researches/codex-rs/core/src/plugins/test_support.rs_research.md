# test_support.rs 研究文档

## 场景与职责

`test_support.rs` 是 Codex 插件系统的 **测试辅助模块**，仅在测试编译时可用（`#[cfg(test)]`）。它提供了一组通用的测试辅助函数，用于创建测试用的插件目录结构、配置文件和模拟数据，减少测试代码的重复。

### 核心职责

1. **测试数据构造**：快速创建插件目录结构和文件
2. **配置模拟**：创建测试用的 config.toml 和插件配置
3. **精选插件模拟**：模拟 OpenAI 精选插件仓库结构
4. **SHA 管理**：模拟精选插件的版本 SHA 文件

---

## 功能点目的

### 1. 文件写入辅助

```rust
pub(crate) fn write_file(path: &Path, contents: &str)
```

**目的**：自动创建父目录并写入文件内容，简化测试中的文件操作。

### 2. 精选插件创建

```rust
pub(crate) fn write_curated_plugin(root: &Path, plugin_name: &str)
```

**目的**：创建一个完整的精选插件目录结构，包括：
- `.codex-plugin/plugin.json` - 插件清单
- `skills/SKILL.md` - 技能文件
- `.mcp.json` - MCP 服务器配置
- `.app.json` - App 连接器配置

### 3. 精选市场创建

```rust
pub(crate) fn write_openai_curated_marketplace(root: &Path, plugin_names: &[&str])
```

**目的**：创建 OpenAI 精选市场的 marketplace.json 文件，并自动创建对应的插件目录。

### 4. SHA 文件管理

```rust
pub(crate) fn write_curated_plugin_sha(codex_home: &Path)
pub(crate) fn write_curated_plugin_sha_with(codex_home: &Path, sha: &str)
```

**目的**：创建精选插件仓库的 SHA 标记文件，用于版本控制。

### 5. 功能配置

```rust
pub(crate) fn write_plugins_feature_config(codex_home: &Path)
```

**目的**：创建启用插件功能的 config.toml 文件。

### 6. 配置加载

```rust
pub(crate) async fn load_plugins_config(codex_home: &Path) -> crate::config::Config
```

**目的**：从测试目录加载配置，供集成测试使用。

---

## 具体技术实现

### 文件写入辅助

```rust
pub(crate) fn write_file(path: &Path, contents: &str) {
    fs::create_dir_all(path.parent().expect("file should have a parent")).unwrap();
    fs::write(path, contents).unwrap();
}
```

**特点**：
- 自动创建父目录
- 使用 `unwrap()` 简化错误处理（测试失败即 panic）

### 精选插件创建

```rust
pub(crate) fn write_curated_plugin(root: &Path, plugin_name: &str) {
    let plugin_root = root.join("plugins").join(plugin_name);
    
    // 1. 创建插件清单
    write_file(
        &plugin_root.join(".codex-plugin/plugin.json"),
        &format!(
            r#"{{
  "name": "{plugin_name}",
  "description": "Plugin that includes skills, MCP servers, and app connectors"
}}"#
        ),
    );
    
    // 2. 创建技能文件
    write_file(
        &plugin_root.join("skills/SKILL.md"),
        "---\nname: sample\ndescription: sample\n---\n",
    );
    
    // 3. 创建 MCP 配置
    write_file(
        &plugin_root.join(".mcp.json"),
        r#"{
  "mcpServers": {
    "sample-docs": {
      "type": "http",
      "url": "https://sample.example/mcp"
    }
  }
}"#,
    );
    
    // 4. 创建 App 配置
    write_file(
        &plugin_root.join(".app.json"),
        r#"{
  "apps": {
    "calendar": {
      "id": "connector_calendar"
    }
  }
}"#,
    );
}
```

**创建的目录结构**：
```
{root}/
└── plugins/
    └── {plugin_name}/
        ├── .codex-plugin/
        │   └── plugin.json
        ├── skills/
        │   └── SKILL.md
        ├── .mcp.json
        └── .app.json
```

### 精选市场创建

```rust
pub(crate) fn write_openai_curated_marketplace(root: &Path, plugin_names: &[&str]) {
    // 1. 生成插件条目 JSON
    let plugins = plugin_names
        .iter()
        .map(|plugin_name| {
            format!(
                r#"{{
      "name": "{plugin_name}",
      "source": {{
        "source": "local",
        "path": "./plugins/{plugin_name}"
      }}
    }}"#
            )
        })
        .collect::<Vec<_>>()
        .join(",\n");
    
    // 2. 创建 marketplace.json
    write_file(
        &root.join(".agents/plugins/marketplace.json"),
        &format!(
            r#"{{
  "name": "{OPENAI_CURATED_MARKETPLACE_NAME}",
  "plugins": [
{plugins}
  ]
}}"#
        ),
    );
    
    // 3. 为每个插件创建目录
    for plugin_name in plugin_names {
        write_curated_plugin(root, plugin_name);
    }
}
```

**创建的目录结构**：
```
{root}/
├── .agents/
│   └── plugins/
│       └── marketplace.json
└── plugins/
    ├── {plugin1}/
    │   └── ...
    └── {plugin2}/
        └── ...
```

### SHA 文件管理

```rust
pub(crate) const TEST_CURATED_PLUGIN_SHA: &str = "0123456789abcdef0123456789abcdef01234567";

pub(crate) fn write_curated_plugin_sha(codex_home: &Path) {
    write_curated_plugin_sha_with(codex_home, TEST_CURATED_PLUGIN_SHA);
}

pub(crate) fn write_curated_plugin_sha_with(codex_home: &Path, sha: &str) {
    write_file(&codex_home.join(".tmp/plugins.sha"), &format!("{sha}\n"));
}
```

### 功能配置

```rust
pub(crate) fn write_plugins_feature_config(codex_home: &Path) {
    write_file(
        &codex_home.join(CONFIG_TOML_FILE),
        r#"[features]
plugins = true
"#,
    );
}
```

### 配置加载

```rust
pub(crate) async fn load_plugins_config(codex_home: &Path) -> crate::config::Config {
    ConfigBuilder::default()
        .codex_home(codex_home.to_path_buf())
        .fallback_cwd(Some(codex_home.to_path_buf()))
        .build()
        .await
        .expect("config should load")
}
```

---

## 关键代码路径与文件引用

### 使用方

| 模块 | 使用函数 | 用途 |
|------|----------|------|
| `manager_tests.rs` | `write_curated_plugin`, `write_openai_curated_marketplace`, `write_curated_plugin_sha`, `write_plugins_feature_config`, `load_plugins_config` | 测试插件管理器 |
| `marketplace_tests.rs` | （内联实现） | 市场测试使用自己的辅助函数 |
| `store_tests.rs` | （内联实现） | 存储测试使用自己的辅助函数 |

### 依赖关系

```
test_support.rs
    ├── 依赖:
    │   ├── crate::config::CONFIG_TOML_FILE
    │   ├── crate::config::ConfigBuilder
    │   ├── super::OPENAI_CURATED_MARKETPLACE_NAME
    │   └── std::fs
    │
    └── 被依赖:
        └── manager_tests.rs (通过 super::test_support)
```

---

## 依赖与外部交互

### 条件编译

```rust
#[cfg(test)]
pub(crate) mod test_support;
```

该模块仅在测试时编译，不会包含在发布版本中。

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `std::fs` | 文件系统操作 |
| `std::path::Path` | 路径处理 |
| `crate::config` | 配置构建 |

### 常量定义

```rust
// 测试用的固定 SHA
pub(crate) const TEST_CURATED_PLUGIN_SHA: &str = "0123456789abcdef0123456789abcdef01234567";

// 来自 config 模块
const CONFIG_TOML_FILE: &str = "config.toml";

// 来自 manager 模块
const OPENAI_CURATED_MARKETPLACE_NAME: &str = "openai-curated";
```

---

## 风险、边界与改进建议

### 当前限制

1. **硬编码内容**：
   - 插件模板内容固定，无法自定义
   - 技能文件内容简单，可能不满足复杂测试需求

2. **单一市场支持**：
   - 仅支持 `openai-curated` 市场
   - 不支持自定义市场名称

3. **同步 API**：
   - 所有函数都是同步的
   - 大量文件操作时可能阻塞

### 改进建议

1. **添加自定义内容支持**：
   ```rust
   pub(crate) fn write_curated_plugin_with_content(
       root: &Path,
       plugin_name: &str,
       manifest: Option<&str>,
       skills: Option<&str>,
       mcp_config: Option<&str>,
   ) {
       // 允许自定义各文件内容
   }
   ```

2. **支持自定义市场**：
   ```rust
   pub(crate) fn write_marketplace(
       root: &Path,
       marketplace_name: &str,
       plugin_names: &[&str],
   ) {
       // 不仅限于 openai-curated
   }
   ```

3. **添加异步版本**：
   ```rust
   pub(crate) async fn write_curated_plugin_async(root: &Path, plugin_name: &str) {
       // 异步文件操作
   }
   ```

4. **添加验证函数**：
   ```rust
   pub(crate) fn assert_plugin_installed(codex_home: &Path, plugin_id: &PluginId) {
       // 验证插件正确安装
   }
   
   pub(crate) fn assert_plugin_configured(codex_home: &Path, plugin_id: &PluginId) {
       // 验证配置正确写入
   }
   ```

5. **使用 Builder 模式**：
   ```rust
   pub(crate) struct TestPluginBuilder {
       name: String,
       skills: Vec<String>,
       mcp_servers: HashMap<String, McpServerConfig>,
       // ...
   }
   
   impl TestPluginBuilder {
       pub fn with_skill(mut self, name: &str) -> Self { ... }
       pub fn with_mcp_server(mut self, name: &str, config: McpServerConfig) -> Self { ... }
       pub fn build(self, root: &Path) { ... }
   }
   ```

### 维护风险

1. **与生产代码不同步**：
   - 测试用的 JSON 结构与生产代码期望的结构可能不一致
   - 建议：使用生产代码的序列化函数生成 JSON

2. **重复定义**：
   - `TEST_CURATED_PLUGIN_SHA` 与生产代码中的 SHA 检查可能不一致
   - 建议：从统一常量导入

3. **缺乏文档**：
   - 函数没有文档注释
   - 建议：添加使用示例

### 使用示例

```rust
#[cfg(test)]
mod tests {
    use super::test_support::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_plugin_loading() {
        let tmp = tempdir().unwrap();
        let codex_home = tmp.path();
        
        // 1. 创建精选市场
        write_openai_curated_marketplace(codex_home, &["github", "slack"]);
        
        // 2. 创建 SHA 文件
        write_curated_plugin_sha(codex_home);
        
        // 3. 启用插件功能
        write_plugins_feature_config(codex_home);
        
        // 4. 加载配置
        let config = load_plugins_config(codex_home).await;
        
        // 5. 执行测试...
    }
}
```
