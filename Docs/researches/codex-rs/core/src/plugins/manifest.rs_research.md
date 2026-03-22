# manifest.rs 深度研究文档

## 场景与职责

`manifest.rs` 是 Codex 插件系统的核心模块，负责插件清单（manifest）的解析和验证。插件清单定义在 `.codex-plugin/plugin.json` 文件中，描述了插件的元数据、能力组件路径以及界面展示信息。

### 核心职责

1. **Manifest 解析**：将 JSON 格式的 `plugin.json` 解析为结构化的 Rust 类型
2. **路径解析与验证**：处理插件组件路径（skills、mcpServers、apps），确保安全的路径解析
3. **界面配置处理**：解析插件的 UI 展示配置（图标、截图、描述等）
4. **默认值处理**：处理可选字段的默认值和缺失值

## 功能点目的

### 1. 核心数据结构

#### `PluginManifest` - 解析后的插件清单

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PluginManifest {
    pub(crate) name: String,                    // 插件名称
    pub(crate) description: Option<String>,     // 插件描述
    pub(crate) paths: PluginManifestPaths,      // 组件路径配置
    pub(crate) interface: Option<PluginManifestInterface>, // UI 配置
}
```

#### `PluginManifestPaths` - 组件路径

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginManifestPaths {
    pub skills: Option<AbsolutePathBuf>,        // 技能目录路径
    pub mcp_servers: Option<AbsolutePathBuf>,   // MCP 配置文件路径
    pub apps: Option<AbsolutePathBuf>,          // App 配置文件路径
}
```

#### `PluginManifestInterface` - 界面配置

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PluginManifestInterface {
    pub display_name: Option<String>,           // 显示名称
    pub short_description: Option<String>,      // 短描述
    pub long_description: Option<String>,      // 长描述
    pub developer_name: Option<String>,        // 开发者名称
    pub category: Option<String>,              // 分类
    pub capabilities: Vec<String>,             // 能力标签
    pub website_url: Option<String>,           // 网站 URL
    pub privacy_policy_url: Option<String>,    // 隐私政策
    pub terms_of_service_url: Option<String>, // 服务条款
    pub default_prompt: Option<Vec<String>>,   // 默认提示词
    pub brand_color: Option<String>,           // 品牌色
    pub composer_icon: Option<AbsolutePathBuf>, // 编辑器图标
    pub logo: Option<AbsolutePathBuf>,         // Logo
    pub screenshots: Vec<AbsolutePathBuf>,     // 截图
}
```

### 2. 路径安全机制

路径解析实现了严格的安全检查，防止目录遍历攻击：

```rust
fn resolve_manifest_path(
    plugin_root: &Path,
    field: &'static str,
    path: Option<&str>,
) -> Option<AbsolutePathBuf> {
    let path = path?;
    if path.is_empty() {
        return None;
    }
    // 必须以 ./ 开头，确保是相对路径
    let Some(relative_path) = path.strip_prefix("./") else {
        tracing::warn!("ignoring {field}: path must start with `./`");
        return None;
    };
    // 禁止 .. 组件
    for component in Path::new(relative_path).components() {
        match component {
            Component::Normal(component) => normalized.push(component),
            Component::ParentDir => {
                tracing::warn!("ignoring {field}: path must not contain '..'");
                return None;
            }
            _ => {
                tracing::warn!("ignoring {field}: path must stay within the plugin root");
                return None;
            }
        }
    }
    // ...
}
```

### 3. Default Prompt 处理

支持字符串或字符串数组格式，并进行验证：

```rust
const MAX_DEFAULT_PROMPT_COUNT: usize = 3;      // 最多 3 个提示词
const MAX_DEFAULT_PROMPT_LEN: usize = 128;      // 每个最多 128 字符

// 支持的格式：
// "defaultPrompt": "Single prompt"
// "defaultPrompt": ["Prompt 1", "Prompt 2"]
```

处理流程：
1. 规范化空白字符（合并多个空格、去除首尾空格）
2. 验证非空
3. 验证长度限制
4. 过滤无效条目（非字符串类型）

### 4. 界面资源路径解析

界面资源（图标、Logo、截图）同样遵循 `./` 前缀要求：

```rust
fn resolve_interface_asset_path(
    plugin_root: &Path,
    field: &'static str,
    path: Option<&str>,
) -> Option<AbsolutePathBuf> {
    resolve_manifest_path(plugin_root, field, path)
}
```

## 具体技术实现

### 主入口函数

```rust
pub(crate) fn load_plugin_manifest(plugin_root: &Path) -> Option<PluginManifest> {
    let manifest_path = plugin_root.join(PLUGIN_MANIFEST_PATH);  // .codex-plugin/plugin.json
    if !manifest_path.is_file() {
        return None;
    }
    let contents = fs::read_to_string(&manifest_path).ok()?;
    match serde_json::from_str::<RawPluginManifest>(&contents) {
        Ok(manifest) => {
            // 解析并转换为 PluginManifest
            // 处理 name 回退（使用目录名）
            // 解析 interface 配置
            // 解析 paths 配置
        }
        Err(err) => {
            tracing::warn!("failed to parse plugin manifest: {err}");
            None
        }
    }
}
```

### 名称回退逻辑

如果 manifest 中的 `name` 字段为空，使用插件目录名作为回退：

```rust
let name = plugin_root
    .file_name()
    .and_then(|entry| entry.to_str())
    .filter(|_| raw_name.trim().is_empty())
    .unwrap_or(&raw_name)
    .to_string();
```

### Raw 类型定义

使用 serde 的 `Raw` 类型进行初步解析，然后转换为内部类型：

```rust
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawPluginManifest {
    #[serde(default)]
    name: String,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    skills: Option<String>,
    #[serde(default)]
    mcp_servers: Option<String>,
    #[serde(default)]
    apps: Option<String>,
    #[serde(default)]
    interface: Option<RawPluginManifestInterface>,
}
```

### Default Prompt 的复杂解析

使用 `untagged` 枚举处理多种输入格式：

```rust
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum RawPluginManifestDefaultPrompt {
    String(String),
    List(Vec<RawPluginManifestDefaultPromptEntry>),
    Invalid(JsonValue),  // 捕获无效格式用于错误报告
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum RawPluginManifestDefaultPromptEntry {
    String(String),
    Invalid(JsonValue),
}
```

## 关键代码路径与文件引用

### 主要函数调用链

```
load_plugin_manifest(plugin_root)
├── fs::read_to_string(plugin_root.join(".codex-plugin/plugin.json"))
├── serde_json::from_str::<RawPluginManifest>()
├── 解析 name（支持目录名回退）
├── 解析 interface（如果存在）
│   ├── resolve_default_prompts()  // 处理默认提示词
│   └── resolve_interface_asset_path()  // 处理界面资源路径
└── 解析 paths
    ├── resolve_manifest_path("skills", ...)
    ├── resolve_manifest_path("mcpServers", ...)
    └── resolve_manifest_path("apps", ...)
```

### 文件引用

| 路径 | 说明 |
|------|------|
| `codex-rs/core/src/plugins/manager.rs` | 调用 `load_plugin_manifest` 加载插件 |
| `codex-rs/core/src/plugins/marketplace.rs` | 调用 `load_plugin_manifest` 读取插件界面信息 |
| `codex-rs/core/src/plugins/mod.rs` | 模块导出：`pub use manifest::PluginManifestInterface` |

## 依赖与外部交互

### 依赖 crate

```rust
use codex_utils_absolute_path::AbsolutePathBuf;  // 绝对路径类型
use serde::Deserialize;                           // 反序列化
use serde_json::Value as JsonValue;              // JSON 值类型
use std::fs;                                      // 文件系统
use std::path::Component;                         // 路径组件
use std::path::Path;                              // 路径类型
```

### 常量定义

```rust
pub(crate) const PLUGIN_MANIFEST_PATH: &str = ".codex-plugin/plugin.json";
const MAX_DEFAULT_PROMPT_COUNT: usize = 3;
const MAX_DEFAULT_PROMPT_LEN: usize = 128;
```

### 错误处理

- 使用 `tracing::warn!` 记录警告信息
- 解析失败返回 `None` 而非 `Err`，允许优雅降级
- 无效字段被忽略而非导致整体失败

## 风险、边界与改进建议

### 安全风险与防护

| 风险 | 防护措施 |
|------|---------|
| 目录遍历 (`../etc/passwd`) | 强制 `./` 前缀，禁止 `..` 组件 |
| 绝对路径注入 | 强制 `./` 前缀，拒绝绝对路径 |
| 空路径 | 检查并拒绝空路径和仅 `./` 的路径 |
| 符号链接攻击 | 依赖文件系统权限，未显式处理 |

### 边界条件

1. **空 manifest**：所有字段使用 `#[serde(default)]`，空 JSON `{}` 是有效的
2. **空 name**：回退到目录名
3. **超长 defaultPrompt**：截断并警告
4. **无效 defaultPrompt 类型**：记录警告，返回 `None`
5. **非字符串数组元素**：跳过并警告

### 改进建议

1. **路径验证增强**
   - 考虑添加符号链接检测，防止 symlink 攻击
   - 添加路径长度限制检查

2. **错误报告改进**
   - 当前解析失败返回 `None`，考虑返回具体错误类型
   - 添加更多上下文信息到警告日志

3. **性能优化**
   - 考虑添加 manifest 缓存，避免重复读取
   - 使用 `memmap` 读取大文件（如果有）

4. **Schema 验证**
   - 考虑使用 JSON Schema 进行预验证
   - 提供更详细的验证错误信息

5. **测试覆盖**
   - 添加更多边界测试（如特殊字符、Unicode 路径）
   - 添加并发读取测试

### 相关测试

- `codex-rs/core/src/plugins/manifest.rs` 内嵌测试模块（`#[cfg(test)]`）
- `manager_tests.rs` 中的集成测试（如 `load_plugins_uses_manifest_configured_component_paths`）
- `marketplace_tests.rs` 中的界面资源路径测试
