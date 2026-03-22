# ConfigService Tests 研究文档

## 场景与职责

`service_tests.rs` 是 `service.rs` 的配套单元测试文件，提供对 `ConfigService` 的全面测试覆盖。测试涵盖配置读写、版本控制、合并策略、托管策略验证等核心功能。

## 功能点目的

### 1. TOML 编辑测试
验证 `toml_value_to_item` 正确处理嵌套表结构，保留格式属性（如 `is_implicit`）。

### 2. 配置写入测试
- **基本写入**：验证配置值正确写入文件
- **嵌套路径**：验证 `features.personality` 等嵌套路径编辑
- **格式保留**：验证注释和顺序被保留

### 3. 配置读取测试
- **层叠读取**：验证多层配置正确合并
- **来源追踪**：验证 `origins` 正确显示配置来源
- **层信息**：验证 `layers` 包含所有配置层

### 4. 版本控制测试
- **乐观锁**：验证版本冲突检测
- **默认路径**：验证省略 `file_path` 时使用默认路径

### 5. 覆盖检测测试
- **托管覆盖**：验证用户配置被托管配置覆盖时正确报告
- **会话标志覆盖**：验证 CLI 覆盖的优先级

### 6. 验证测试
- **无效值拒绝**：验证无效配置值被拒绝
- **保留 provider 保护**：验证不能覆盖内置 provider
- **功能要求冲突**：验证违反功能要求的写入被拒绝

### 7. 合并策略测试
- **Upsert**：验证表合并行为
- **Replace**：验证完全替换行为

## 具体技术实现

### 测试结构示例

```rust
#[tokio::test]
async fn write_value_preserves_comments_and_order() -> Result<()> {
    // 1. 创建临时目录和初始配置
    let tmp = tempdir().expect("tempdir");
    let original = r#"# Codex user configuration
model = "gpt-5"
approval_policy = "on-request"

[notice]
# Preserve this comment
hide_full_access_warning = true

[features]
unified_exec = true
"#;
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), original)?;
    
    // 2. 执行写入
    let service = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    service
        .write_value(ConfigValueWriteParams {
            file_path: Some(tmp.path().join(CONFIG_TOML_FILE).display().to_string()),
            key_path: "features.personality".to_string(),
            value: serde_json::json!(true),
            merge_strategy: MergeStrategy::Replace,
            expected_version: None,
        })
        .await
        .expect("write succeeds");
    
    // 3. 验证结果
    let updated = std::fs::read_to_string(tmp.path().join(CONFIG_TOML_FILE))?;
    let expected = r#"# Codex user configuration
model = "gpt-5"
approval_policy = "on-request"

[notice]
# Preserve this comment
hide_full_access_warning = true

[features]
unified_exec = true
personality = true
"#;
    assert_eq!(updated, expected);
    Ok(())
}
```

### 关键测试用例分析

| 测试函数 | 验证功能 | 关键断言 |
|---------|---------|---------|
| `toml_value_to_item_handles_nested_config_tables` | 嵌套表处理 | 验证 `is_implicit` 属性 |
| `write_value_preserves_comments_and_order` | 格式保留 | 验证注释和顺序 |
| `write_value_supports_nested_app_paths` | 嵌套应用路径 | 验证 `apps.app1.default_tools_approval_mode` |
| `read_includes_origins_and_layers` | 层叠读取 | 验证 `origins` 和 `layers` |
| `write_value_reports_override` | 覆盖检测 | 验证 `WriteStatus::Ok` |
| `version_conflict_rejected` | 乐观锁 | 验证 `ConfigVersionConflict` |
| `write_value_defaults_to_user_config_path` | 默认路径 | 验证省略 `file_path` |
| `invalid_user_value_rejected_even_if_overridden_by_managed` | 验证严格性 | 验证无效值被拒绝 |
| `reserved_builtin_provider_override_rejected` | Provider 保护 | 验证保留 provider 错误 |
| `write_value_rejects_feature_requirement_conflict` | 功能要求 | 验证冲突检测 |
| `read_reports_managed_overrides_user_and_session_flags` | 优先级 | 验证层优先级 |
| `upsert_merges_tables_replace_overwrites` | 合并策略 | 对比 Upsert 和 Replace |

### 层优先级验证测试

```rust
#[tokio::test]
async fn read_reports_managed_overrides_user_and_session_flags() {
    let tmp = tempdir().expect("tempdir");
    
    // 用户配置
    let user_path = tmp.path().join(CONFIG_TOML_FILE);
    std::fs::write(&user_path, "model = \"user\"").unwrap();
    
    // 托管配置
    let managed_path = tmp.path().join("managed_config.toml");
    std::fs::write(&managed_path, "model = \"system\"").unwrap();
    
    // CLI 覆盖
    let cli_overrides = vec![(
        "model".to_string(),
        TomlValue::String("session".to_string()),
    )];
    
    let service = ConfigService::new(
        tmp.path().to_path_buf(),
        cli_overrides,
        LoaderOverrides {
            managed_config_path: Some(managed_path.clone()),
            // ...
        },
        CloudRequirementsLoader::default(),
    );
    
    let response = service.read(...).await.expect("response");
    
    // 验证：托管配置优先级最高
    assert_eq!(response.config.model.as_deref(), Some("system"));
    
    // 验证层顺序（高优先级在前）
    let layers = response.layers.expect("layers");
    assert_eq!(layers[0].name, ConfigLayerSource::LegacyManagedConfigTomlFromFile { ... });
    assert_eq!(layers[1].name, ConfigLayerSource::SessionFlags);
    assert_eq!(layers[2].name, ConfigLayerSource::User { ... });
}
```

### 合并策略对比测试

```rust
#[tokio::test]
async fn upsert_merges_tables_replace_overwrites() -> Result<()> {
    let tmp = tempdir().expect("tempdir");
    let path = tmp.path().join(CONFIG_TOML_FILE);
    
    // 基础配置
    let base = r#"[mcp_servers.linear]
bearer_token_env_var = "TOKEN"
name = "linear"
url = "https://linear.example"

[mcp_servers.linear.env_http_headers]
existing = "keep"

[mcp_servers.linear.http_headers]
alpha = "a"
"#;
    std::fs::write(&path, base)?;
    
    // 覆盖值
    let overlay = serde_json::json!({
        "bearer_token_env_var": "NEW_TOKEN",
        "http_headers": { "alpha": "updated", "beta": "b" },
        "name": "linear",
        "url": "https://linear.example"
    });
    
    // 测试 Upsert：合并表
    service.write_value(ConfigValueWriteParams {
        key_path: "mcp_servers.linear".to_string(),
        value: overlay.clone(),
        merge_strategy: MergeStrategy::Upsert,
        // ...
    }).await?;
    
    let upserted: TomlValue = toml::from_str(&std::fs::read_to_string(&path)?)?;
    // 验证：env_http_headers 保留，http_headers 合并
    assert!(upserted["mcp_servers"]["linear"]["env_http_headers"]["existing"].is_string());
    assert!(upserted["mcp_servers"]["linear"]["http_headers"]["beta"].is_string());
    
    // 测试 Replace：完全替换
    service.write_value(ConfigValueWriteParams {
        key_path: "mcp_servers.linear".to_string(),
        value: overlay,
        merge_strategy: MergeStrategy::Replace,
        // ...
    }).await?;
    
    let replaced: TomlValue = toml::from_str(&std::fs::read_to_string(&path)?)?;
    // 验证：env_http_headers 被移除
    assert!(!replaced["mcp_servers"]["linear"].as_table().unwrap().contains_key("env_http_headers"));
}
```

## 关键代码路径与文件引用

### 本文件测试函数

| 函数 | 行号 | 描述 |
|------|------|------|
| `toml_value_to_item_handles_nested_config_tables` | 13-59 | 嵌套表处理测试 |
| `write_value_preserves_comments_and_order` | 61-104 | 格式保留测试 |
| `write_value_supports_nested_app_paths` | 106-165 | 嵌套应用路径测试 |
| `read_includes_origins_and_layers` | 167-238 | 层叠读取测试 |
| `write_value_reports_override` | 240-299 | 覆盖检测测试 |
| `version_conflict_rejected` | 301-323 | 版本冲突测试 |
| `write_value_defaults_to_user_config_path` | 325-347 | 默认路径测试 |
| `invalid_user_value_rejected_even_if_overridden_by_managed` | 349-387 | 验证严格性测试 |
| `reserved_builtin_provider_override_rejected` | 389-415 | Provider 保护测试 |
| `write_value_rejects_feature_requirement_conflict` | 417-466 | 功能要求冲突测试 |
| `write_value_rejects_profile_feature_requirement_conflict` | 468-517 | Profile 功能要求测试 |
| `read_reports_managed_overrides_user_and_session_flags` | 519-582 | 层优先级测试 |
| `write_value_reports_managed_override` | 584-623 | 托管覆盖报告测试 |
| `upsert_merges_tables_replace_overwrites` | 625-710 | 合并策略对比测试 |

### 被测代码

- `codex-rs/core/src/config/service.rs` 第 111-738 行

### 测试辅助

| 类型/函数 | 来源 | 用途 |
|----------|------|------|
| `tempfile::tempdir` | `tempfile` crate | 创建临时测试目录 |
| `pretty_assertions::assert_eq` | `pretty_assertions` | 更好的 diff 输出 |
| `TomlValue` | `toml` crate | TOML 解析验证 |

## 依赖与外部交互

### 测试数据流

```
测试函数
    ↓
tempdir() 创建临时目录
    ↓
写入测试配置（TOML）
    ↓
ConfigService::new() / ConfigService::new_with_defaults()
    ↓
调用被测方法（read/write/batch_write）
    ↓
验证结果
    ├── 文件内容验证
    ├── 返回值验证
    └── 错误类型验证
```

### 模拟配置层

```rust
// 用户配置
std::fs::write(tmp.path().join(CONFIG_TOML_FILE), "model = \"user\"").unwrap();

// 托管配置
let managed_path = tmp.path().join("managed_config.toml");
std::fs::write(&managed_path, "approval_policy = \"never\"").unwrap();

// CLI 覆盖
let cli_overrides = vec![("model".to_string(), TomlValue::String("session".to_string()))];

// 创建服务
let service = ConfigService::new(
    tmp.path().to_path_buf(),
    cli_overrides,
    LoaderOverrides {
        managed_config_path: Some(managed_path.clone()),
        // ...
    },
    CloudRequirementsLoader::default(),
);
```

## 风险、边界与改进建议

### 当前覆盖

| 功能 | 覆盖程度 | 备注 |
|------|---------|------|
| 基本读写 | ✅ 完整 | 多个测试覆盖 |
| 嵌套路径 | ✅ 完整 | `write_value_supports_nested_app_paths` |
| 格式保留 | ✅ 完整 | `write_value_preserves_comments_and_order` |
| 层叠读取 | ✅ 完整 | `read_includes_origins_and_layers` |
| 版本控制 | ✅ 完整 | `version_conflict_rejected` |
| 覆盖检测 | ✅ 完整 | 多个测试覆盖 |
| 合并策略 | ✅ 完整 | `upsert_merges_tables_replace_overwrites` |
| 验证逻辑 | ✅ 完整 | 多个验证测试 |
| 批量写入 | ❌ 缺失 | 无专门测试 |
| 错误恢复 | ❌ 缺失 | 无失败恢复测试 |
| 并发写入 | ❌ 缺失 | 无并发测试 |
| 大配置性能 | ❌ 缺失 | 无性能测试 |

### 建议补充的测试

#### 1. 批量写入测试

```rust
#[tokio::test]
async fn batch_write_applies_multiple_edits_atomically() -> Result<()> {
    let tmp = tempdir().expect("tempdir");
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), "")?;
    
    let service = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    service
        .batch_write(ConfigBatchWriteParams {
            file_path: Some(tmp.path().join(CONFIG_TOML_FILE).display().to_string()),
            edits: vec![
                ConfigEditParams {
                    key_path: "model".to_string(),
                    value: serde_json::json!("gpt-5"),
                    merge_strategy: MergeStrategy::Replace,
                },
                ConfigEditParams {
                    key_path: "approval_policy".to_string(),
                    value: serde_json::json!("never"),
                    merge_strategy: MergeStrategy::Replace,
                },
            ],
            expected_version: None,
        })
        .await?;
    
    let config = service.read(ConfigReadParams { ... }).await?;
    assert_eq!(config.config.model.as_deref(), Some("gpt-5"));
    assert_eq!(config.config.approval_policy, Some(AskForApproval::Never));
    
    Ok(())
}
```

#### 2. 并发写入测试

```rust
#[tokio::test]
async fn concurrent_writes_handle_version_conflicts() -> Result<()> {
    let tmp = tempdir().expect("tempdir");
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), "model = \"initial\"")?;
    
    let service1 = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    let service2 = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    
    // 两个服务同时读取
    let read1 = service1.read(ConfigReadParams { ... }).await?;
    let read2 = service2.read(ConfigReadParams { ... }).await?;
    
    // service1 先写入
    service1.write_value(ConfigValueWriteParams {
        expected_version: Some(read1.layers.unwrap()[0].version.clone()),
        // ...
    }).await?;
    
    // service2 使用过期版本写入，应失败
    let result = service2.write_value(ConfigValueWriteParams {
        expected_version: Some(read2.layers.unwrap()[0].version.clone()),
        // ...
    }).await;
    
    assert!(result.is_err());
    assert_eq!(
        result.unwrap_err().write_error_code(),
        Some(ConfigWriteErrorCode::ConfigVersionConflict)
    );
    
    Ok(())
}
```

#### 3. 错误恢复测试

```rust
#[tokio::test]
async fn partial_failure_rolls_back_changes() -> Result<()> {
    // 测试批量写入中部分失败时的回滚行为
}
```

#### 4. 大配置性能测试

```rust
#[tokio::test]
async fn large_config_read_write_performance() -> Result<()> {
    let tmp = tempdir().expect("tempdir");
    
    // 生成大配置
    let large_config = generate_large_config(1000); // 1000 个字段
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), large_config)?;
    
    let service = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    
    let start = Instant::now();
    let _ = service.read(ConfigReadParams { ... }).await?;
    let read_duration = start.elapsed();
    
    assert!(read_duration < Duration::from_secs(1), "read too slow");
    
    Ok(())
}
```

#### 5. 数组操作测试

```rust
#[tokio::test]
async fn write_value_supports_array_index_paths() -> Result<()> {
    let tmp = tempdir().expect("tempdir");
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), 
        "items = [\"a\", \"b\", \"c\"]")?;
    
    let service = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    service
        .write_value(ConfigValueWriteParams {
            key_path: "items.1".to_string(),
            value: serde_json::json!("updated"),
            merge_strategy: MergeStrategy::Replace,
            expected_version: None,
        })
        .await?;
    
    let config: TomlValue = toml::from_str(
        &std::fs::read_to_string(tmp.path().join(CONFIG_TOML_FILE))?
    )?;
    assert_eq!(config["items"][1].as_str(), Some("updated"));
    
    Ok(())
}
```

### 测试组织改进

```rust
// 按功能模块组织
mod read_tests {
    use super::*;
    // ...
}

mod write_tests {
    use super::*;
    // ...
}

mod batch_write_tests {
    use super::*;
    // ...
}

mod validation_tests {
    use super::*;
    // ...
}

mod layering_tests {
    use super::*;
    // ...
}
```

### 测试工具函数

```rust
// 共享的测试辅助函数
async fn create_test_service(config_content: &str) -> (TempDir, ConfigService) {
    let tmp = tempdir().expect("tempdir");
    std::fs::write(tmp.path().join(CONFIG_TOML_FILE), config_content).unwrap();
    let service = ConfigService::new_with_defaults(tmp.path().to_path_buf());
    (tmp, service)
}

fn assert_config_eq(path: &Path, expected: &str) {
    let actual = std::fs::read_to_string(path).unwrap();
    assert_eq!(actual.trim(), expected.trim());
}
```
