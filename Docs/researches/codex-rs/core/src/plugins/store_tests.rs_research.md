# store_tests.rs 研究文档

## 场景与职责

`store_tests.rs` 是 `store.rs` 模块的单元测试文件，负责验证插件本地存储管理功能的正确性。该文件确保插件安装、版本管理、路径安全等核心功能的可靠性。

---

## 功能点目的

### 测试覆盖范围

1. **插件安装流程**：验证从源目录复制到缓存目录的完整流程
2. **版本管理**：验证多版本支持和活动版本检测
3. **路径安全**：验证对路径遍历攻击的防护
4. **名称验证**：验证插件名称与市场名称的合法性检查
5. **清单匹配**：验证源目录中的 manifest 名称与预期一致

---

## 具体技术实现

### 测试辅助函数

```rust
/// 创建测试插件目录结构
fn write_plugin(root: &Path, dir_name: &str, manifest_name: &str) {
    let plugin_root = root.join(dir_name);
    fs::create_dir_all(plugin_root.join(".codex-plugin")).unwrap();
    fs::create_dir_all(plugin_root.join("skills")).unwrap();
    fs::write(
        plugin_root.join(".codex-plugin/plugin.json"),
        format!(r#"{{"name":"{manifest_name}"}}"#),
    )
    .unwrap();
    fs::write(plugin_root.join("skills/SKILL.md"), "skill").unwrap();
    fs::write(plugin_root.join(".mcp.json"), r#"{"mcpServers":{}}"#).unwrap();
}
```

### 测试用例详解

#### 1. 基本安装测试

```rust
#[test]
fn install_copies_plugin_into_default_marketplace() {
    let tmp = tempdir().unwrap();
    write_plugin(tmp.path(), "sample-plugin", "sample-plugin");
    let plugin_id = PluginId::new("sample-plugin".to_string(), "debug".to_string()).unwrap();

    let result = PluginStore::new(tmp.path().to_path_buf())
        .install(
            AbsolutePathBuf::try_from(tmp.path().join("sample-plugin")).unwrap(),
            plugin_id.clone(),
        )
        .unwrap();

    let installed_path = tmp.path().join("plugins/cache/debug/sample-plugin/local");
    assert_eq!(
        result,
        PluginInstallResult {
            plugin_id,
            plugin_version: "local".to_string(),
            installed_path: AbsolutePathBuf::try_from(installed_path.clone()).unwrap(),
        }
    );
    // 验证文件复制
    assert!(installed_path.join(".codex-plugin/plugin.json").is_file());
    assert!(installed_path.join("skills/SKILL.md").is_file());
}
```

**验证点**：
- 插件正确安装到 `plugins/cache/{marketplace}/{plugin}/{version}/`
- 默认版本为 "local"
- 所有文件正确复制

#### 2. 清单名称作为目标名

```rust
#[test]
fn install_uses_manifest_name_for_destination_and_key() {
    let tmp = tempdir().unwrap();
    write_plugin(tmp.path(), "source-dir", "manifest-name");  // 目录名与 manifest 名不同
    let plugin_id = PluginId::new("manifest-name".to_string(), "market".to_string()).unwrap();

    let result = PluginStore::new(tmp.path().to_path_buf())
        .install(
            AbsolutePathBuf::try_from(tmp.path().join("source-dir")).unwrap(),
            plugin_id.clone(),
        )
        .unwrap();

    // 使用 manifest 中的名称，而非源目录名
    assert_eq!(
        result.installed_path.as_path(),
        tmp.path().join("plugins/cache/market/manifest-name/local")
    );
}
```

**验证点**：
- 目标路径使用 manifest 中的名称
- 源目录名仅作为输入路径

#### 3. 路径计算测试

```rust
#[test]
fn plugin_root_derives_path_from_key_and_version() {
    let tmp = tempdir().unwrap();
    let store = PluginStore::new(tmp.path().to_path_buf());
    let plugin_id = PluginId::new("sample".to_string(), "debug".to_string()).unwrap();

    assert_eq!(
        store.plugin_root(&plugin_id, "local").as_path(),
        tmp.path().join("plugins/cache/debug/sample/local")
    );
}
```

**验证点**：
- `plugin_root` 方法正确计算路径

#### 4. 指定版本安装

```rust
#[test]
fn install_with_version_uses_requested_cache_version() {
    let tmp = tempdir().unwrap();
    write_plugin(tmp.path(), "sample-plugin", "sample-plugin");
    let plugin_id = PluginId::new("sample-plugin".to_string(), "openai-curated".to_string()).unwrap();
    let plugin_version = "0123456789abcdef".to_string();

    let result = PluginStore::new(tmp.path().to_path_buf())
        .install_with_version(
            AbsolutePathBuf::try_from(tmp.path().join("sample-plugin")).unwrap(),
            plugin_id.clone(),
            plugin_version.clone(),
        )
        .unwrap();

    let installed_path = tmp.path().join(format!(
        "plugins/cache/openai-curated/sample-plugin/{plugin_version}"
    ));
    assert_eq!(result.plugin_version, plugin_version);
    assert_eq!(result.installed_path.as_path(), installed_path);
}
```

**验证点**：
- `install_with_version` 使用指定版本
- 适用于精选插件的 SHA 版本

#### 5. 活动版本检测

```rust
#[test]
fn active_plugin_version_reads_version_directory_name() {
    let tmp = tempdir().unwrap();
    write_plugin(
        &tmp.path().join("plugins/cache/debug"),
        "sample-plugin/local",
        "sample-plugin",
    );
    let store = PluginStore::new(tmp.path().to_path_buf());
    let plugin_id = PluginId::new("sample-plugin".to_string(), "debug".to_string()).unwrap();

    assert_eq!(
        store.active_plugin_version(&plugin_id),
        Some("local".to_string())
    );
    assert_eq!(
        store.active_plugin_root(&plugin_id).unwrap().as_path(),
        tmp.path().join("plugins/cache/debug/sample-plugin/local")
    );
}
```

**验证点**：
- 从目录名读取版本
- 单版本时正确识别

#### 6. 路径分隔符防护

```rust
#[test]
fn plugin_root_rejects_path_separators_in_key_segments() {
    let err = PluginId::parse("../../etc@debug").unwrap_err();
    assert_eq!(
        err.to_string(),
        "invalid plugin name: only ASCII letters, digits, `_`, and `-` are allowed in `../../etc@debug`"
    );

    let err = PluginId::parse("sample@../../etc").unwrap_err();
    assert_eq!(
        err.to_string(),
        "invalid marketplace name: only ASCII letters, digits, `_`, and `-` are allowed in `sample@../../etc`"
    );
}
```

**验证点**：
- 插件名中禁止 `../`
- 市场名中禁止 `../`

#### 7. 清单名称验证

```rust
#[test]
fn install_rejects_manifest_names_with_path_separators() {
    let tmp = tempdir().unwrap();
    write_plugin(tmp.path(), "source-dir", "../../etc");  // 恶意 manifest 名

    let err = PluginStore::new(tmp.path().to_path_buf())
        .install(...)
        .unwrap_err();

    assert_eq!(
        err.to_string(),
        "invalid plugin name: only ASCII letters, digits, `_`, and `-` are allowed"
    );
}
```

**验证点**：
- manifest 中的名称也经过验证

#### 8. 名称匹配验证

```rust
#[test]
fn install_rejects_manifest_names_that_do_not_match_marketplace_plugin_name() {
    let tmp = tempdir().unwrap();
    write_plugin(tmp.path(), "source-dir", "manifest-name");

    let err = PluginStore::new(tmp.path().to_path_buf())
        .install(
            AbsolutePathBuf::try_from(tmp.path().join("source-dir")).unwrap(),
            PluginId::new("different-name".to_string(), "debug".to_string()).unwrap(),
        )
        .unwrap_err();

    assert_eq!(
        err.to_string(),
        "plugin manifest name `manifest-name` does not match marketplace plugin name `different-name`"
    );
}
```

**验证点**：
- manifest 名称必须与 PluginId 中的名称一致
- 防止安装错误的插件

---

## 关键代码路径与文件引用

### 被测试的函数

| 函数 | 所在文件 | 测试覆盖 |
|------|----------|----------|
| `PluginStore::new` | `store.rs:72` | ✅ |
| `PluginStore::install` | `store.rs:129` | ✅ |
| `PluginStore::install_with_version` | `store.rs:137` | ✅ |
| `PluginStore::plugin_root` | `store.rs:93` | ✅ |
| `PluginStore::active_plugin_version` | `store.rs:102` | ✅ |
| `PluginStore::active_plugin_root` | `store.rs:120` | ✅ |
| `PluginId::new` | `store.rs:25` | ✅ |
| `PluginId::parse` | `store.rs:35` | ✅ |

### 测试依赖

```rust
use super::*;  // store.rs 的所有导出
use pretty_assertions::assert_eq;
use tempfile::tempdir;
```

---

## 依赖与外部交互

### 测试框架

| 依赖 | 用途 |
|------|------|
| `tempfile::tempdir` | 创建隔离的临时测试目录 |
| `pretty_assertions::assert_eq` | 清晰的差异输出 |

### 文件系统操作

测试大量使用 `std::fs`：
- `fs::create_dir_all` - 创建目录结构
- `fs::write` - 写入测试文件
- `Path::is_file()` - 验证文件存在

---

## 风险、边界与改进建议

### 当前覆盖缺口

| 功能 | 覆盖状态 | 优先级 |
|------|----------|--------|
| `PluginStore::uninstall` | ❌ | **高** |
| 原子安装失败回滚 | ❌ | **高** |
| 并发安装 | ❌ | 中 |
| 大文件安装 | ❌ | 低 |
| 磁盘满错误 | ❌ | 中 |
| 权限错误 | ❌ | 中 |

### 未测试的边界

1. **卸载功能**：
   ```rust
   // 建议添加
   #[test]
   fn uninstall_removes_plugin_directory() {
       let tmp = tempdir().unwrap();
       write_plugin(tmp.path(), "plugins/cache/debug/sample-plugin/local", "sample");
       let store = PluginStore::new(tmp.path().to_path_buf());
       let plugin_id = PluginId::new("sample".to_string(), "debug".to_string()).unwrap();
       
       store.uninstall(&plugin_id).unwrap();
       
       assert!(!tmp.path().join("plugins/cache/debug/sample-plugin").exists());
   }
   ```

2. **原子操作失败**：
   ```rust
   #[test]
   fn atomic_install_rolls_back_on_failure() {
       // 模拟重命名失败，验证回滚
   }
   ```

3. **多版本处理**：
   ```rust
   #[test]
   fn active_plugin_version_returns_none_for_multiple_versions() {
       let tmp = tempdir().unwrap();
       write_plugin(tmp.path(), "plugins/cache/debug/sample-plugin/v1", "sample");
       write_plugin(tmp.path(), "plugins/cache/debug/sample-plugin/v2", "sample");
       let store = PluginStore::new(tmp.path().to_path_buf());
       let plugin_id = PluginId::new("sample".to_string(), "debug".to_string()).unwrap();
       
       // 多版本时返回 None
       assert_eq!(store.active_plugin_version(&plugin_id), None);
   }
   ```

### 改进建议

1. **使用快照测试验证错误消息**：
   ```rust
   use insta::assert_snapshot;
   
   #[test]
   fn error_messages_snapshot() {
       let err = PluginId::parse("invalid@").unwrap_err();
       assert_snapshot!(err.to_string());
   }
   ```

2. **参数化测试**：
   ```rust
   use test_case::test_case;
   
   #[test_case("valid-name", true ; "valid name")]
   #[test_case("name-with-dash", true ; "with dash")]
   #[test_case("name_with_underscore", true ; "with underscore")]
   #[test_case("../etc", false ; "path traversal")]
   #[test_case("name.with.dot", false ; "with dot")]
   fn plugin_name_validation(name: &str, expected_valid: bool) {
       let result = PluginId::new(name.to_string(), "market".to_string());
       assert_eq!(result.is_ok(), expected_valid);
   }
   ```

3. **属性测试（Property-based testing）**：
   ```rust
   use proptest::prelude::*;
   
   proptest! {
       #[test]
       fn install_preserves_file_content(content: String) {
           // 验证任意内容正确复制
       }
   }
   ```

4. **并发测试**：
   ```rust
   #[tokio::test]
   async fn concurrent_install_is_safe() {
       // 验证多线程安装不会损坏状态
   }
   ```

### 维护风险

1. **硬编码路径分隔符**：
   - 测试中使用 `/` 作为分隔符
   - 可能在 Windows 上失败
   - 建议：使用 `Path::join`

2. **测试数据与实现耦合**：
   - `write_plugin` 函数与 manifest 结构耦合
   - manifest 结构变更时需要同步更新

3. **缺少集成测试**：
   - 当前都是单元测试
   - 建议添加与 manager.rs 的集成测试
