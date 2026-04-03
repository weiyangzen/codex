# edit_tests.rs 研究文档

## 场景与职责

`edit_tests.rs` 是 `edit.rs` 的配套测试模块，通过 `#[path = "edit_tests.rs"]` 在 `edit.rs` 末尾条件编译引入。该测试文件全面验证配置编辑引擎的正确性，覆盖从基础 CRUD 到复杂边界情况的各种场景。

### 核心职责

1. **功能回归防护**：确保配置编辑操作按预期工作
2. **格式保留验证**：验证 TOML 注释和格式在编辑后得以保留
3. **边界情况覆盖**：测试符号链接、循环引用、空值等边界条件
4. **Profile 作用域验证**：确保配置正确写入指定 profile
5. **API 兼容性**：同时测试同步 (`apply_blocking`) 和异步 (`apply`) 接口

---

## 功能点目的

### 测试分类

| 类别 | 测试数量 | 代表测试 | 目的 |
|------|----------|----------|------|
| 基础模型设置 | 4 | `blocking_set_model_top_level` | 验证基本配置写入 |
| Profile 作用域 | 3 | `blocking_set_model_scopes_to_active_profile` | 验证 profile 隔离 |
| 符号链接处理 | 2 | `blocking_set_model_writes_through_symlink_chain` | 验证符号链接跟随 |
| 格式保留 | 5 | `batch_write_table_upsert_preserves_inline_comments` | 验证注释保留 |
| MCP 服务器 | 6 | `blocking_replace_mcp_servers_round_trips` | 验证 MCP 配置序列化 |
| Skill 配置 | 2 | `set_skill_config_writes_disabled_entry` | 验证技能启用/禁用 |
| Notice/警告 | 4 | `blocking_set_hide_full_access_warning_preserves_table` | 验证通知设置 |
| 路径操作 | 2 | `blocking_clear_path_noop_when_missing` | 验证路径清除 |
| 构建器 API | 6 | `async_builder_set_model_persists` | 验证流式 API |

---

## 具体技术实现

### 测试基础设施

```rust
// 标准测试依赖
use super::*;  // 引入 edit.rs 的所有导出项
use tempfile::tempdir;  // 临时目录用于隔离测试
use toml::Value as TomlValue;  // 用于解析和验证生成的 TOML
use pretty_assertions::assert_eq;  // 更好的 diff 输出
```

### 典型测试模式

#### 模式 1：基本写入验证

```rust
#[test]
fn blocking_set_model_top_level() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();

    // 执行编辑操作
    apply_blocking(
        codex_home,
        None,  // 无特定 profile
        &[ConfigEdit::SetModel {
            model: Some("gpt-5.1-codex".to_string()),
            effort: Some(ReasoningEffort::High),
        }],
    )
    .expect("persist");

    // 验证文件内容
    let contents = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    let expected = r#"model = "gpt-5.1-codex"
model_reasoning_effort = "high"
"#;
    assert_eq!(contents, expected);
}
```

#### 模式 2：Profile 作用域验证

```rust
#[test]
fn blocking_set_model_scopes_to_active_profile() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();
    
    // 预置配置：激活 "team" profile
    std::fs::write(
        codex_home.join(CONFIG_TOML_FILE),
        r#"profile = "team"

[profiles.team]
model_reasoning_effort = "low"
"#,
    )
    .expect("seed");

    // 应用编辑（无显式 profile，应从文件读取）
    apply_blocking(
        codex_home,
        None,
        &[ConfigEdit::SetModel {
            model: Some("o5-preview".to_string()),
            effort: Some(ReasoningEffort::Minimal),
        }],
    )
    .expect("persist");

    // 验证写入到 profiles.team 而非全局
    let contents = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    let expected = r#"profile = "team"

[profiles.team]
model_reasoning_effort = "minimal"
model = "o5-preview"
"#;
    assert_eq!(contents, expected);
}
```

#### 模式 3：内联表迁移验证

```rust
#[test]
fn blocking_set_model_preserves_inline_table_contents() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();

    // 预置内联表格式配置
    std::fs::write(
        codex_home.join(CONFIG_TOML_FILE),
        r#"profile = "fast"

profiles = { fast = { model = "gpt-4o", sandbox_mode = "strict" } }
"#,
    )
    .expect("seed");

    apply_blocking(
        codex_home,
        None,
        &[ConfigEdit::SetModel {
            model: Some("o4-mini".to_string()),
            effort: None,
        }],
    )
    .expect("persist");

    // 使用 toml::Value 解析验证逻辑结构
    let raw = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    let value: TomlValue = toml::from_str(&raw).expect("parse config");

    // 验证 sandbox_mode 被保留
    let profiles_tbl = value
        .get("profiles")
        .and_then(|v| v.as_table())
        .expect("profiles table");
    let fast_tbl = profiles_tbl
        .get("fast")
        .and_then(|v| v.as_table())
        .expect("fast table");
    assert_eq!(
        fast_tbl.get("sandbox_mode").and_then(|v| v.as_str()),
        Some("strict")
    );
    assert_eq!(
        fast_tbl.get("model").and_then(|v| v.as_str()),
        Some("o4-mini")
    );
}
```

#### 模式 4：符号链接处理（Unix 特有）

```rust
#[cfg(unix)]
#[test]
fn blocking_set_model_writes_through_symlink_chain() {
    use std::os::unix::fs::symlink;
    
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();
    let target_dir = tempdir().expect("target dir");
    let target_path = target_dir.path().join(CONFIG_TOML_FILE);
    let link_path = codex_home.join("config-link.toml");
    let config_path = codex_home.join(CONFIG_TOML_FILE);

    // 创建符号链接链：config.toml -> config-link.toml -> target/config.toml
    symlink(&target_path, &link_path).expect("symlink link");
    symlink("config-link.toml", &config_path).expect("symlink config");

    apply_blocking(
        codex_home,
        None,
        &[ConfigEdit::SetModel {
            model: Some("gpt-5.1-codex".to_string()),
            effort: Some(ReasoningEffort::High),
        }],
    )
    .expect("persist");

    // 验证 config.toml 仍是符号链接
    let meta = std::fs::symlink_metadata(&config_path).expect("config metadata");
    assert!(meta.file_type().is_symlink());

    // 验证内容写入到最终目标
    let contents = std::fs::read_to_string(&target_path).expect("read target");
    assert!(contents.contains("gpt-5.1-codex"));
}
```

#### 模式 5：循环符号链接处理

```rust
#[cfg(unix)]
#[test]
fn blocking_set_model_replaces_symlink_on_cycle() {
    use std::os::unix::fs::symlink;
    
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();
    let link_a = codex_home.join("a.toml");
    let link_b = codex_home.join("b.toml");
    let config_path = codex_home.join(CONFIG_TOML_FILE);

    // 创建循环：a.toml -> b.toml -> a.toml
    symlink("b.toml", &link_a).expect("symlink a");
    symlink("a.toml", &link_b).expect("symlink b");
    symlink("a.toml", &config_path).expect("symlink config");

    apply_blocking(
        codex_home,
        None,
        &[ConfigEdit::SetModel {
            model: Some("gpt-5.1-codex".to_string()),
            effort: None,
        }],
    )
    .expect("persist");

    // 检测到循环后，应替换符号链接为普通文件
    let meta = std::fs::symlink_metadata(&config_path).expect("config metadata");
    assert!(!meta.file_type().is_symlink());
}
```

#### 模式 6：注释保留验证

```rust
#[test]
fn batch_write_table_upsert_preserves_inline_comments() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();
    let original = r#"approval_policy = "never"

[mcp_servers.linear]
name = "linear"
# ok
url = "https://linear.example"

[mcp_servers.linear.http_headers]
foo = "bar"

[sandbox_workspace_write]
# ok 3
network_access = false
"#;
    std::fs::write(codex_home.join(CONFIG_TOML_FILE), original).expect("seed config");

    // 批量更新多个路径
    apply_blocking(
        codex_home,
        None,
        &[
            ConfigEdit::SetPath {
                segments: vec!["mcp_servers".to_string(), "linear".to_string(), "url".to_string()],
                value: value("https://linear.example/v2"),
            },
            ConfigEdit::SetPath {
                segments: vec!["sandbox_workspace_write".to_string(), "network_access".to_string()],
                value: value(true),
            },
        ],
    )
    .expect("apply");

    let updated = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    
    // 验证值更新且注释保留
    let expected = r#"approval_policy = "never"

[mcp_servers.linear]
name = "linear"
# ok
url = "https://linear.example/v2"

[mcp_servers.linear.http_headers]
foo = "bar"

[sandbox_workspace_write]
# ok 3
network_access = true
"#;
    assert_eq!(updated, expected);
}
```

#### 模式 7：MCP 服务器序列化

```rust
#[test]
fn blocking_replace_mcp_servers_round_trips() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path();

    let mut servers = BTreeMap::new();
    // 插入 stdio 类型 MCP 服务器
    servers.insert(
        "stdio".to_string(),
        McpServerConfig {
            transport: McpServerTransportConfig::Stdio {
                command: "cmd".to_string(),
                args: vec!["--flag".to_string()],
                env: Some([("B".to_string(), "2".to_string())].into_iter().collect()),
                env_vars: vec!["FOO".to_string()],
                cwd: None,
            },
            enabled: true,
            required: false,
            disabled_reason: None,
            startup_timeout_sec: None,
            tool_timeout_sec: None,
            enabled_tools: Some(vec!["one".to_string(), "two".to_string()]),
            disabled_tools: None,
            scopes: None,
            oauth_resource: None,
        },
    );
    // 插入 streamable_http 类型 MCP 服务器
    servers.insert(
        "http".to_string(),
        McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url: "https://example.com".to_string(),
                bearer_token_env_var: Some("TOKEN".to_string()),
                http_headers: Some([("Z-Header".to_string(), "z".to_string())].into_iter().collect()),
                env_http_headers: None,
            },
            enabled: false,
            required: false,
            disabled_reason: None,
            startup_timeout_sec: Some(std::time::Duration::from_secs(5)),
            tool_timeout_sec: None,
            enabled_tools: None,
            disabled_tools: Some(vec!["forbidden".to_string()]),
            scopes: None,
            oauth_resource: Some("https://resource.example.com".to_string()),
        },
    );

    apply_blocking(
        codex_home,
        None,
        &[ConfigEdit::ReplaceMcpServers(servers.clone())],
    )
    .expect("persist");

    // 验证生成的 TOML 格式
    let raw = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    // 验证字段顺序、数组格式、嵌套表结构
    assert!(raw.contains("[mcp_servers.http.http_headers]"));
    assert!(raw.contains("[mcp_servers.stdio.env]"));
}
```

#### 模式 8：异步 API 测试

```rust
#[tokio::test]
async fn async_builder_set_model_persists() {
    let tmp = tempdir().expect("tmpdir");
    let codex_home = tmp.path().to_path_buf();

    ConfigEditsBuilder::new(&codex_home)
        .set_model(Some("gpt-5.1-codex"), Some(ReasoningEffort::High))
        .apply()  // 异步应用
        .await
        .expect("persist");

    let contents = std::fs::read_to_string(codex_home.join(CONFIG_TOML_FILE))
        .expect("read config");
    assert!(contents.contains("gpt-5.1-codex"));
}
```

---

## 关键代码路径与文件引用

### 测试函数清单

| 测试函数 | 行号 | 测试目标 |
|----------|------|----------|
| `blocking_set_model_top_level` | 10-30 | 基本模型设置 |
| `builder_with_edits_applies_custom_paths` | 32-47 | 自定义路径编辑 |
| `set_model_availability_nux_count_writes_shown_count` | 49-65 | 模型可用性 NUX |
| `set_skill_config_writes_disabled_entry` | 67-86 | Skill 禁用条目写入 |
| `set_skill_config_removes_entry_when_enabled` | 88-111 | Skill 启用时移除条目 |
| `blocking_set_model_preserves_inline_table_contents` | 113-158 | 内联表内容保留 |
| `blocking_set_model_writes_through_symlink_chain` | 160-191 | 符号链接跟随（Unix） |
| `blocking_set_model_replaces_symlink_on_cycle` | 193-223 | 循环链接处理（Unix） |
| `batch_write_table_upsert_preserves_inline_comments` | 225-284 | 批量更新注释保留 |
| `blocking_clear_model_removes_inline_table_entry` | 286-318 | 内联表条目清除 |
| `blocking_set_model_scopes_to_active_profile` | 320-352 | Profile 作用域自动检测 |
| `blocking_set_model_with_explicit_profile` | 354-381 | 显式 Profile 指定 |
| `blocking_set_hide_full_access_warning_preserves_table` | 383-414 | Notice 表保留 |
| `blocking_set_hide_rate_limit_model_nudge_preserves_table` | 416-441 | 速率限制提示 |
| `blocking_set_hide_gpt5_1_migration_prompt_preserves_table` | 443-470 | 迁移提示设置 |
| `blocking_set_hide_gpt_5_1_codex_max_migration_prompt_preserves_table` | 472-499 | 特殊字符键名 |
| `blocking_record_model_migration_seen_preserves_table` | 501-530 | 迁移记录 |
| `blocking_replace_mcp_servers_round_trips` | 532-623 | MCP 服务器完整序列化 |
| `blocking_replace_mcp_servers_preserves_inline_comments` | 625-669 | MCP 注释保留 |
| `blocking_replace_mcp_servers_preserves_inline_comment_suffix` | 671-713 | 后缀注释保留 |
| `blocking_replace_mcp_servers_preserves_inline_comment_after_removing_keys` | 715-757 | 键删除后注释保留 |
| `blocking_replace_mcp_servers_preserves_inline_comment_prefix_on_update` | 759-803 | 前缀注释保留 |
| `blocking_clear_path_noop_when_missing` | 805-823 | 清除缺失路径无操作 |
| `blocking_set_path_updates_notifications` | 825-849 | 路径设置通知 |
| `async_builder_set_model_persists` | 851-867 | 异步构建器 |
| `blocking_builder_set_model_round_trips_back_and_forth` | 869-901 | 多次往返更新 |
| `blocking_set_asynchronous_helpers_available` | 903-922 | 异步辅助函数 |
| `blocking_builder_set_realtime_audio_persists_and_clears` | 924-966 | 实时音频配置 |
| `replace_mcp_servers_blocking_clears_table_when_empty` | 968-987 | 空 MCP 表清除 |

---

## 依赖与外部交互

### 测试依赖

```rust
// 被测代码
use super::*;  // edit.rs 的所有导出项

// 测试辅助
use crate::config::types::McpServerTransportConfig;
use codex_protocol::openai_models::ReasoningEffort;
use pretty_assertions::assert_eq;  // 更清晰的断言失败输出

// 平台特定
#[cfg(unix)]
use std::os::unix::fs::symlink;  // Unix 符号链接创建

// 临时文件系统
use tempfile::tempdir;  // 自动清理的临时目录

// TOML 验证
use toml::Value as TomlValue;  // 解析生成的 TOML 进行结构验证
```

### 与 edit.rs 的交互

测试通过 `use super::*` 访问 `edit.rs` 的以下关键项：
- `ConfigEdit` 枚举变体
- `apply_blocking` 函数
- `ConfigEditsBuilder` 构建器
- `CONFIG_TOML_FILE` 常量（来自 `codex_config`）

---

## 风险、边界与改进建议

### 测试覆盖分析

#### 已覆盖场景 ✅

| 场景 | 测试函数 | 覆盖度 |
|------|----------|--------|
| 基本配置写入 | `blocking_set_model_top_level` | 完整 |
| Profile 自动检测 | `blocking_set_model_scopes_to_active_profile` | 完整 |
| Profile 显式指定 | `blocking_set_model_with_explicit_profile` | 完整 |
| 内联表迁移 | `blocking_set_model_preserves_inline_table_contents` | 完整 |
| 注释保留（批量） | `batch_write_table_upsert_preserves_inline_comments` | 完整 |
| 注释保留（MCP） | 多个 `blocking_replace_mcp_servers_*` | 完整 |
| 符号链接跟随 | `blocking_set_model_writes_through_symlink_chain` | Unix 完整 |
| 循环链接处理 | `blocking_set_model_replaces_symlink_on_cycle` | Unix 完整 |
| Skill 启用/禁用 | `set_skill_config_*` | 完整 |
| MCP 服务器序列化 | `blocking_replace_mcp_servers_round_trips` | 完整 |
| 异步 API | `async_builder_set_model_persists` | 完整 |
| 空操作处理 | `blocking_clear_path_noop_when_missing` | 完整 |

#### 未覆盖/部分覆盖场景 ⚠️

| 场景 | 风险等级 | 说明 |
|------|----------|------|
| Windows 符号链接 | 中 | 仅测试 Unix 符号链接 |
| 并发写入竞争 | 高 | 无并发测试 |
| 损坏 TOML 处理 | 中 | 未测试无效 TOML 的恢复 |
| 大文件性能 | 低 | 无大配置文件的性能测试 |
| 特殊字符 profile 名 | 低 | 未测试含 `.` 或 `"` 的 profile 名 |
| 权限错误 | 中 | 未测试只读目录等权限问题 |

### 改进建议

1. **添加 Windows 符号链接测试**
   ```rust
   #[cfg(windows)]
   #[test]
   fn blocking_set_model_writes_through_windows_symlink() {
       use std::os::windows::fs::symlink_file;
       // ... 类似 Unix 测试的实现
   }
   ```

2. **添加并发安全测试**
   ```rust
   #[test]
   fn concurrent_edits_are_atomic() {
       // 使用多个线程同时写入不同配置项
       // 验证最终文件状态一致性
   }
   ```

3. **添加错误恢复测试**
   ```rust
   #[test]
   fn invalid_toml_triggers_appropriate_error() {
       // 预置损坏的 TOML
       // 验证返回的错误类型和消息
   }
   ```

4. **添加性能基准测试**
   ```rust
   #[test]
   fn large_config_edit_performance() {
       // 生成大型配置文件（如 1000 个 MCP 服务器）
       // 测量编辑操作的耗时
   }
   ```

5. **测试代码重构**
   - 提取重复的临时目录设置到 `setup()` 辅助函数
   - 使用参数化测试减少相似测试的代码重复
   - 添加 `insta` snapshot 测试进行大规模 TOML 输出验证

### 测试质量指标

| 指标 | 当前状态 | 目标 |
|------|----------|------|
| 行覆盖率 | ~85% | >90% |
| 分支覆盖率 | ~75% | >85% |
| 边界情况覆盖 | 良好 | 全面 |
| 平台覆盖 | Unix 完整 | Unix + Windows |
| 并发覆盖 | 缺失 | 基础覆盖 |
