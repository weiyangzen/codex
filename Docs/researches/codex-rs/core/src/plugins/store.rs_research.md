# store.rs 研究文档

## 场景与职责

`store.rs` 是 Codex 插件系统中负责 **插件本地存储管理** 的核心模块。它实现了插件的物理存储、版本管理、原子安装/卸载等关键功能，确保插件文件在本地文件系统中的安全存储和访问。

### 核心场景

1. **插件安装**：将插件从源目录复制到本地缓存目录
2. **版本管理**：支持多版本插件并存，自动识别活动版本
3. **原子操作**：安装和卸载操作的原子性保证（失败回滚）
4. **路径安全**：防止路径遍历攻击，确保插件 ID 和版本号的合法性

---

## 功能点目的

### 1. `PluginId` - 插件标识符

**目的**：唯一标识一个插件，格式为 `{plugin_name}@{marketplace_name}`。

**安全特性**：
- 验证名称只包含 ASCII 字母、数字、`_` 和 `-`
- 防止路径分隔符注入

### 2. `PluginStore` - 存储管理器

**目的**：管理插件在本地文件系统的存储。

**核心功能**：
- 计算插件存储路径
- 检测活动版本
- 执行安装和卸载

### 3. 原子安装机制

**目的**：确保插件安装的原子性，避免部分安装导致的不一致状态。

**实现策略**：
1. 创建临时目录（staging）
2. 复制文件到临时目录
3. 备份现有版本（如果存在）
4. 原子重命名激活新版本
5. 失败时回滚到备份

---

## 具体技术实现

### 数据结构

```rust
/// 插件唯一标识符
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginId {
    pub plugin_name: String,      // 插件名称
    pub marketplace_name: String, // 市场名称
}

impl PluginId {
    /// 创建新的 PluginId，验证名称合法性
    pub fn new(plugin_name: String, marketplace_name: String) -> Result<Self, PluginIdError>;
    
    /// 从字符串解析，格式: "plugin@marketplace"
    pub fn parse(plugin_key: &str) -> Result<Self, PluginIdError>;
    
    /// 转换为字符串键
    pub fn as_key(&self) -> String;  // 返回 "plugin@marketplace"
}

/// 插件安装结果
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PluginInstallResult {
    pub plugin_id: PluginId,
    pub plugin_version: String,
    pub installed_path: AbsolutePathBuf,
}

/// 插件存储管理器
#[derive(Debug, Clone)]
pub struct PluginStore {
    root: AbsolutePathBuf,  // 缓存根目录: ~/.codex/plugins/cache
}
```

### 路径结构

```
~/.codex/
└── plugins/
    └── cache/
        └── {marketplace_name}/
            └── {plugin_name}/
                └── {version}/
                    ├── .codex-plugin/
                    │   └── plugin.json
                    ├── skills/
                    │   └── SKILL.md
                    └── ...
```

示例：
```
~/.codex/plugins/cache/openai-curated/github/local/
~/.codex/plugins/cache/openai-curated/github/0123456789abcdef/
```

### 核心方法实现

#### `PluginStore::install`

```rust
pub fn install(
    &self,
    source_path: AbsolutePathBuf,
    plugin_id: PluginId,
) -> Result<PluginInstallResult, PluginStoreError> {
    self.install_with_version(source_path, plugin_id, DEFAULT_PLUGIN_VERSION.to_string())
}

pub fn install_with_version(
    &self,
    source_path: AbsolutePathBuf,
    plugin_id: PluginId,
    plugin_version: String,
) -> Result<PluginInstallResult, PluginStoreError> {
    // 1. 验证源路径是目录
    if !source_path.as_path().is_dir() {
        return Err(PluginStoreError::Invalid(...));
    }

    // 2. 验证插件名称与 manifest 一致
    let plugin_name = plugin_name_for_source(source_path.as_path())?;
    if plugin_name != plugin_id.plugin_name {
        return Err(PluginStoreError::Invalid(...));
    }

    // 3. 验证版本号格式
    validate_plugin_segment(&plugin_version, "plugin version")
        .map_err(PluginStoreError::Invalid)?;

    // 4. 计算目标路径
    let installed_path = self.plugin_root(&plugin_id, &plugin_version);

    // 5. 执行原子替换
    replace_plugin_root_atomically(
        source_path.as_path(),
        self.plugin_base_root(&plugin_id).as_path(),
        &plugin_version,
    )?;

    Ok(PluginInstallResult { plugin_id, plugin_version, installed_path })
}
```

#### 原子替换实现

```rust
fn replace_plugin_root_atomically(
    source: &Path,
    target_root: &Path,
    plugin_version: &str,
) -> Result<(), PluginStoreError> {
    let parent = target_root.parent().ok_or(...)?;

    // 1. 创建父目录
    fs::create_dir_all(parent)?;

    // 2. 创建临时 staging 目录
    let staged_dir = tempfile::Builder::new()
        .prefix("plugin-install-")
        .tempdir_in(parent)?;
    let staged_root = staged_dir.path().join(plugin_dir_name);
    let staged_version_root = staged_root.join(plugin_version);

    // 3. 复制文件到 staging
    copy_dir_recursive(source, &staged_version_root)?;

    // 4. 如果目标存在，创建备份
    if target_root.exists() {
        let backup_dir = tempfile::Builder::new()
            .prefix("plugin-backup-")
            .tempdir_in(parent)?;
        let backup_root = backup_dir.path().join(plugin_dir_name);
        fs::rename(target_root, &backup_root)?;

        // 5. 尝试激活新版本
        if let Err(err) = fs::rename(&staged_root, target_root) {
            // 6. 失败时回滚
            let rollback_result = fs::rename(&backup_root, target_root);
            return match rollback_result {
                Ok(()) => Err(...),
                Err(rollback_err) => {
                    // 回滚失败，保留备份供手动恢复
                    let backup_path = backup_dir.keep().join(plugin_dir_name);
                    Err(PluginStoreError::Invalid(format!(
                        "failed to activate...; failed to restore... (left at {})",
                        backup_path.display()
                    )))
                }
            };
        }
    } else {
        // 7. 目标不存在，直接重命名
        fs::rename(&staged_root, target_root)?;
    }

    Ok(())
}
```

#### 活动版本检测

```rust
pub fn active_plugin_version(&self, plugin_id: &PluginId) -> Option<String> {
    // 1. 读取版本目录
    let mut discovered_versions = fs::read_dir(self.plugin_base_root(plugin_id).as_path())
        .ok()?
        .filter_map(Result::ok)
        .filter_map(|entry| {
            entry.file_type().ok().filter(std::fs::FileType::is_dir)?;
            entry.file_name().into_string().ok()
        })
        .filter(|version| validate_plugin_segment(version, "plugin version").is_ok())
        .collect::<Vec<_>>();

    // 2. 排序
    discovered_versions.sort_unstable();

    // 3. 只有唯一版本时才返回
    if discovered_versions.len() == 1 {
        discovered_versions.pop()
    } else {
        None
    }
}
```

### 安全验证

```rust
fn validate_plugin_segment(segment: &str, kind: &str) -> Result<(), String> {
    if segment.is_empty() {
        return Err(format!("invalid {kind}: must not be empty"));
    }
    // 只允许 ASCII 字母、数字、下划线和连字符
    if !segment.chars().all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_') {
        return Err(format!(
            "invalid {kind}: only ASCII letters, digits, `_`, and `-` are allowed"
        ));
    }
    Ok(())
}
```

---

## 关键代码路径与文件引用

### 调用关系图

```
store.rs
    ├── manager.rs 调用:
    │   ├── PluginStore::new
    │   ├── PluginStore::install / install_with_version
    │   ├── PluginStore::uninstall
    │   ├── PluginStore::active_plugin_version
    │   ├── PluginStore::active_plugin_root
    │   ├── PluginStore::is_installed
    │   ├── PluginId::new / parse / as_key
    │   └── PluginInstallResult
    │
    ├── marketplace.rs 调用:
    │   └── PluginId::new
    │
    └── manifest.rs 调用:
        └── plugin_name_for_source (内部使用 load_plugin_manifest)
```

### 错误类型

```rust
#[derive(Debug, thiserror::Error)]
pub enum PluginStoreError {
    #[error("{context}: {source}")]
    Io {
        context: &'static str,
        source: io::Error,
    },
    #[error("{0}")]
    Invalid(String),
}

#[derive(Debug, thiserror::Error)]
pub enum PluginIdError {
    #[error("{0}")]
    Invalid(String),
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile` | 创建临时目录用于原子操作 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径类型保证 |
| `std::fs` | 文件系统操作 |

### 配置常量

```rust
pub(crate) const DEFAULT_PLUGIN_VERSION: &str = "local";
pub(crate) const PLUGINS_CACHE_DIR: &str = "plugins/cache";
```

### 与 manifest 的交互

```rust
// 验证插件名称时加载 manifest
fn plugin_name_for_source(source_path: &Path) -> Result<String, PluginStoreError> {
    let manifest_path = source_path.join(PLUGIN_MANIFEST_PATH);
    let manifest = load_plugin_manifest(source_path).ok_or(...)?;
    Ok(manifest.name)
}
```

---

## 风险、边界与改进建议

### 安全风险

1. **路径遍历防护**：
   - 现状：`validate_plugin_segment` 阻止 `/` 和 `..`
   - 风险：较低，但需确保所有路径入口都经过验证

2. **临时目录安全**：
   - 现状：使用 `tempfile` 创建安全临时目录
   - 风险：较低

3. **并发安全**：
   - 现状：无显式锁，依赖文件系统原子操作
   - 风险：并发安装同一插件可能产生竞态条件
   - 建议：添加文件锁或进程间锁

### 可靠性边界

| 场景 | 当前行为 | 风险 |
|------|----------|------|
| 多版本并存 | 返回 `None`（无活动版本） | 可能导致插件无法加载 |
| 磁盘满 | 复制失败，staging 残留 | 需清理机制 |
| 权限不足 | 返回 IO 错误 | 错误消息不够友好 |
| 备份恢复失败 | 保留备份路径在错误中 | 需要手动干预 |

### 改进建议

1. **添加并发控制**：
   ```rust
   use fs2::FileExt;
   
   impl PluginStore {
       pub fn install_with_lock(&self, ...) -> Result<...> {
           let lock_file = fs::File::create(self.root().join(".install.lock"))?;
           lock_file.lock_exclusive()?;
           // ... 执行安装
           lock_file.unlock()?;
       }
   }
   ```

2. **改进多版本处理**：
   ```rust
   pub fn active_plugin_version(&self, plugin_id: &PluginId) -> Option<String> {
       // 当前：多版本返回 None
       // 建议：返回最新版本或配置指定的版本
       discovered_versions.into_iter().max()
   }
   ```

3. **添加清理机制**：
   ```rust
   pub fn cleanup_stale_installations(&self) -> Result<usize, PluginStoreError> {
       // 清理残留的 staging 和 backup 目录
   }
   ```

4. **添加校验和验证**：
   ```rust
   pub fn install_with_verification(
       &self,
       source_path: AbsolutePathBuf,
       plugin_id: PluginId,
       expected_checksum: &str,
   ) -> Result<PluginInstallResult, PluginStoreError> {
       // 安装后验证文件完整性
   }
   ```

5. **改进错误消息**：
   ```rust
   impl PluginStoreError {
       pub fn user_friendly_message(&self) -> String {
           match self {
               Self::Io { context, source } if source.kind() == PermissionDenied => {
                   "无法写入插件目录，请检查权限".to_string()
               }
               _ => self.to_string(),
           }
       }
   }
   ```

### 测试覆盖

测试文件 `store_tests.rs` 覆盖：
- 基本安装流程
- 版本管理
- 路径安全验证
- 名称匹配验证

**建议添加**：
- 并发安装测试
- 磁盘满错误处理
- 大文件安装性能
- 回滚机制验证
