# marketplace_tests.rs 研究文档

## 场景与职责

`marketplace_tests.rs` 是 Codex 插件系统中 **Marketplace（插件市场）模块的单元测试文件**，负责对 `marketplace.rs` 中的核心功能进行全面测试。该文件确保插件市场的发现、解析、加载等关键流程的正确性和健壮性。

### 核心测试场景

1. **插件解析测试**：验证从 marketplace.json 文件中正确解析插件信息
2. **市场列表测试**：验证从多个根目录（home 目录、repo 目录）发现和加载市场
3. **路径解析测试**：验证相对路径解析为绝对路径的正确性
4. **错误处理测试**：验证各种错误情况（缺失插件、无效路径等）的处理
5. **重复项处理测试**：验证同名插件、同名市场的去重逻辑

---

## 功能点目的

### 1. `resolve_marketplace_plugin` 测试

**目的**：验证从指定 marketplace.json 文件中解析特定插件的功能。

**关键测试点**：
- 正确找到本地插件并解析其路径
- 缺失插件时返回正确的错误信息
- 拒绝非相对路径（如 `../` 开头的路径）
- 同名插件时优先使用第一个匹配项

### 2. `list_marketplaces` 测试

**目的**：验证从多个来源（home 目录、repo 目录）发现和加载市场的功能。

**关键测试点**：
- 同时从 home 和 repo 目录加载市场
- 相同名称的市场保持独立条目（不合并）
- 同一仓库内的多个根目录去重
- 读取市场的显示名称（displayName）
- 跳过加载失败的市场（容错处理）
- 解析插件界面资源路径为绝对路径

### 3. 向后兼容性测试

**目的**：确保对旧版本 marketplace.json 格式的兼容。

**测试点**：
- 忽略顶层遗留的 `installPolicy` 和 `authPolicy` 字段
- 正确处理新的嵌套 `policy` 对象格式

### 4. 安全边界测试

**目的**：验证路径安全限制。

**测试点**：
- 忽略不以 `./` 开头的资源路径（防止目录遍历）
- 拒绝 `../` 开头的插件源路径

---

## 具体技术实现

### 测试数据结构

```rust
// 测试用的 marketplace.json 结构示例
{
  "name": "codex-curated",
  "interface": {
    "displayName": "ChatGPT Official"
  },
  "plugins": [
    {
      "name": "local-plugin",
      "source": {
        "source": "local",
        "path": "./plugin-1"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL",
        "products": ["CODEX", "CHATGPT", "ATLAS"]
      },
      "category": "Design"
    }
  ]
}
```

### 关键测试辅助函数

```rust
// 使用 tempfile 创建临时目录结构
let tmp = tempdir().unwrap();
let repo_root = tmp.path().join("repo");
fs::create_dir_all(repo_root.join(".git")).unwrap();
fs::create_dir_all(repo_root.join(".agents/plugins")).unwrap();
```

### 测试断言风格

- 使用 `pretty_assertions::assert_eq` 提供清晰的差异对比
- 完整比较复杂的结构体（如 `Marketplace`、`MarketplacePlugin`）
- 验证错误消息的精确内容

---

## 关键代码路径与文件引用

### 被测试的主要函数

| 函数名 | 所在文件 | 功能描述 |
|--------|----------|----------|
| `resolve_marketplace_plugin` | `marketplace.rs:146` | 从 marketplace 文件解析特定插件 |
| `list_marketplaces_with_home` | `marketplace.rs:238` | 从多个根目录加载市场列表 |
| `load_marketplace` | `marketplace.rs:194` | 加载单个市场文件 |
| `discover_marketplace_paths_from_roots` | `marketplace.rs:260` | 发现市场文件路径 |

### 测试覆盖的核心类型

| 类型名 | 描述 |
|--------|------|
| `ResolvedMarketplacePlugin` | 解析后的插件信息（含 plugin_id、source_path、auth_policy） |
| `Marketplace` | 市场信息（名称、路径、界面、插件列表） |
| `MarketplacePlugin` | 市场中的插件条目 |
| `MarketplacePluginSource::Local` | 本地插件源（含绝对路径） |
| `MarketplacePluginPolicy` | 插件策略（安装、认证、产品） |
| `PluginManifestInterface` | 插件界面信息（显示名称、图标、截图等） |

### 相关文件依赖

```
marketplace_tests.rs
    ├── marketplace.rs (被测试的主要实现)
    ├── manifest.rs (PluginManifestInterface 定义)
    ├── store.rs (PluginId 定义)
    └── codex_protocol::protocol::Product (产品枚举)
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::tempdir` | 创建临时测试目录 |
| `pretty_assertions::assert_eq` | 美化断言失败输出 |
| `std::fs` | 文件系统操作（创建目录、写入文件） |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径类型 |

### 测试数据文件结构

测试创建的典型目录结构：
```
/tmp/xxx/
├── home/
│   └── .agents/plugins/marketplace.json
└── repo/
    ├── .git/
    └── .agents/plugins/marketplace.json
```

### 环境依赖

- 测试不依赖真实网络或外部服务
- 所有测试使用临时文件系统，完全隔离
- 测试不依赖特定的环境变量

---

## 风险、边界与改进建议

### 当前风险点

1. **路径分隔符硬编码**：测试中使用 `/` 作为路径分隔符，可能在 Windows 上失败
   - 建议：使用 `std::path::MAIN_SEPARATOR` 或 `Path::join`

2. **JSON 字符串硬编码**：测试数据以字符串形式嵌入，维护困难
   - 建议：考虑使用 serde_json 构建或从文件加载

3. **测试间隐式依赖**：某些测试依赖于特定的目录结构，但没有明确的 setup/teardown

### 边界情况覆盖

| 边界情况 | 覆盖状态 | 说明 |
|----------|----------|------|
| 空插件列表 | ✅ | `render_plugins_section_returns_none_for_empty_plugins` |
| 缺失插件 | ✅ | `resolve_marketplace_plugin_reports_missing_plugin` |
| 无效路径（../） | ✅ | `resolve_marketplace_plugin_rejects_non_relative_local_paths` |
| 同名插件 | ✅ | `resolve_marketplace_plugin_uses_first_duplicate_entry` |
| 同名市场 | ✅ | `list_marketplaces_keeps_distinct_entries_for_same_name` |
| 市场文件损坏 | ✅ | `list_marketplaces_skips_marketplaces_that_fail_to_load` |
| 资源路径非相对路径 | ✅ | `list_marketplaces_ignores_plugin_interface_assets_without_dot_slash` |

### 改进建议

1. **增加并发测试**：验证多线程环境下市场加载的安全性
2. **增加性能测试**：大规模 marketplace.json 的加载性能
3. **增加模糊测试**：随机生成 marketplace.json 验证鲁棒性
4. **改进错误消息测试**：使用 `insta` 快照测试验证错误消息格式
5. **提取测试辅助函数**：将通用的 marketplace.json 创建逻辑提取为辅助宏

### 与生产代码的同步风险

- 当 `marketplace.rs` 中的数据结构变更时，测试中的硬编码 JSON 需要同步更新
- 建议在 `marketplace.rs` 中添加序列化辅助函数，供测试和生产代码共用
