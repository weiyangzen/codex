# MCP Connection Manager Tests 研究文档

## 文件信息
- **文件路径**: `codex-rs/core/src/mcp_connection_manager_tests.rs`
- **代码行数**: 649 行
- **主要功能**: `mcp_connection_manager.rs` 的单元测试

---

## 一、场景与职责

### 1.1 测试定位
本测试文件是 `mcp_connection_manager.rs` 的配套单元测试模块，采用 Rust 的 `#[cfg(test)]` 条件编译机制。它通过 `mod tests;` 和 `#[path = "mcp_connection_manager_tests.rs"]` 属性被包含在主文件中。

### 1.2 测试覆盖范围
1. **Elicitation 策略验证**: 确保不同审批策略正确处理 MCP 交互请求
2. **工具名称规范化**: 验证工具名称的格式化、冲突处理和长度限制
3. **工具过滤逻辑**: 测试白名单/黑名单机制
4. **Codex Apps 工具缓存**: 验证缓存的读写、隔离和失效处理
5. **启动快照机制**: 测试异步初始化期间的工具可用性
6. **错误消息格式化**: 验证用户友好的错误提示
7. **传输层工具函数**: 测试 origin 提取逻辑

---

## 二、功能点目的

### 2.1 Elicitation 策略测试

**目的**: 验证 `elicitation_is_rejected_by_policy` 函数在各种审批策略下的行为

**关键场景**:
- `AskForApproval::Never`: 应拒绝所有 elicitation
- `AskForApproval::OnFailure/OnRequest/UnlessTrusted`: 应允许 elicitation
- `AskForApproval::Granular` with `mcp_elicitations: false`: 应拒绝
- `AskForApproval::Granular` with `mcp_elicitations: true`: 应允许

### 2.2 工具名称规范化测试

**目的**: 确保工具名称符合 OpenAI Responses API 规范，同时处理冲突

**测试维度**:
- 正常短名称: `mcp__server1__tool1`
- 重复名称处理: 仅保留第一个
- 超长名称截断: 使用 SHA1 哈希确保唯一性
- 非法字符清理: 替换为下划线

### 2.3 工具过滤测试

**目的**: 验证 `ToolFilter` 的白名单/黑名单逻辑

**测试场景**:
- 默认允许所有
- 白名单模式: 仅允许指定工具
- 黑名单模式: 排除指定工具
- 组合模式: 先应用白名单，再应用黑名单

### 2.4 缓存机制测试

**目的**: 验证 `codex_apps` 工具缓存的正确性

**测试场景**:
- 缓存写入与读取
- 多用户隔离（基于 account_id + chatgpt_user_id）
- 被禁用的 connector 过滤
- Schema 版本不匹配处理
- 无效 JSON 处理

### 2.5 启动快照测试

**目的**: 验证异步初始化期间的工具可用性

**测试场景**:
- 使用 startup snapshot 避免阻塞
- 无 snapshot 时的阻塞行为
- 空 snapshot 的非阻塞行为
- 启动失败时的 fallback

---

## 三、具体技术实现

### 3.1 测试辅助函数

```rust
// 创建测试用的 ToolInfo
fn create_test_tool(server_name: &str, tool_name: &str) -> ToolInfo {
    ToolInfo {
        server_name: server_name.to_string(),
        tool_name: tool_name.to_string(),
        tool_namespace: if server_name == CODEX_APPS_MCP_SERVER_NAME {
            format!("mcp__{server_name}__")
        } else {
            server_name.to_string()
        },
        tool: Tool { ... },
        connector_id: None,
        connector_name: None,
        plugin_display_names: Vec::new(),
        connector_description: None,
    }
}

// 创建带 connector 的测试工具
fn create_test_tool_with_connector(
    server_name: &str,
    tool_name: &str,
    connector_id: &str,
    connector_name: Option<&str>,
) -> ToolInfo

// 创建缓存上下文
fn create_codex_apps_tools_cache_context(
    codex_home: PathBuf,
    account_id: Option<&str>,
    chatgpt_user_id: Option<&str>,
) -> CodexAppsToolsCacheContext
```

### 3.2 测试用例详解

#### 3.2.1 Elicitation 策略测试

```rust
#[test]
fn elicitation_granular_policy_defaults_to_prompting() {
    // 验证默认策略允许 elicitation
    assert!(!elicitation_is_rejected_by_policy(AskForApproval::OnFailure));
    assert!(!elicitation_is_rejected_by_policy(AskForApproval::OnRequest));
    assert!(!elicitation_is_rejected_by_policy(AskForApproval::UnlessTrusted));
    
    // 验证 Granular 策略可禁用 elicitation
    assert!(elicitation_is_rejected_by_policy(AskForApproval::Granular(
        GranularApprovalConfig {
            sandbox_approval: true,
            rules: true,
            skill_approval: true,
            request_permissions: true,
            mcp_elicitations: false,  // 禁用
        }
    )));
}
```

#### 3.2.2 工具名称规范化测试

```rust
#[test]
fn test_qualify_tools_long_names_same_server() {
    let tools = vec![
        create_test_tool(server_name, "extremely_lengthy_function_name..."),
        create_test_tool(server_name, "yet_another_extremely_lengthy_function_name..."),
    ];
    
    let qualified_tools = qualify_tools(tools);
    
    // 验证长度限制为 64 字符
    assert_eq!(keys[0].len(), 64);
    // 验证哈希后缀格式
    assert_eq!(keys[0], "mcp__my_server__extremel119a2b97664e41363932dc84de21e2ff1b93b3e9");
}

#[test]
fn test_qualify_tools_sanitizes_invalid_characters() {
    let tools = vec![create_test_tool("server.one", "tool.two-three")];
    let qualified_tools = qualify_tools(tools);
    
    // 验证非法字符被替换
    assert_eq!(qualified_name, "mcp__server_one__tool_two_three");
    // 验证原始信息保留
    assert_eq!(tool.server_name, "server.one");
    assert_eq!(tool.tool_name, "tool.two-three");
}
```

#### 3.2.3 工具过滤测试

```rust
#[test]
fn tool_filter_applies_enabled_then_disabled() {
    let filter = ToolFilter {
        enabled: Some(HashSet::from(["keep".to_string(), "remove".to_string()])),
        disabled: HashSet::from(["remove".to_string()]),
    };
    
    assert!(filter.allows("keep"));      // 在白名单中，不在黑名单中
    assert!(!filter.allows("remove"));   // 在白名单中，但被黑名单排除
    assert!(!filter.allows("unknown"));  // 不在白名单中
}
```

#### 3.2.4 缓存隔离测试

```rust
#[test]
fn codex_apps_tools_cache_is_scoped_per_user() {
    let cache_context_user_1 = create_codex_apps_tools_cache_context(..., Some("account-one"), Some("user-one"));
    let cache_context_user_2 = create_codex_apps_tools_cache_context(..., Some("account-two"), Some("user-two"));
    
    // 写入不同数据
    write_cached_codex_apps_tools(&cache_context_user_1, &tools_user_1);
    write_cached_codex_apps_tools(&cache_context_user_2, &tools_user_2);
    
    // 验证隔离性
    assert_eq!(read_user_1[0].tool_name, "one");
    assert_eq!(read_user_2[0].tool_name, "two");
    assert_ne!(cache_context_user_1.cache_path(), cache_context_user_2.cache_path());
}
```

#### 3.2.5 启动快照测试

```rust
#[tokio::test]
async fn list_all_tools_uses_startup_snapshot_while_client_is_pending() {
    // 创建永远 pending 的 client
    let pending_client = futures::future::pending::<Result<ManagedClient, StartupOutcomeError>>()
        .boxed()
        .shared();
    
    // 配置 startup snapshot
    let async_client = AsyncManagedClient {
        client: pending_client,
        startup_snapshot: Some(startup_tools),
        startup_complete: Arc::new(AtomicBool::new(false)),
        ...
    };
    
    // 验证 snapshot 立即可用，不阻塞
    let tools = manager.list_all_tools().await;
    assert!(tools.contains_key("mcp__codex_apps__calendar_create_event"));
}

#[tokio::test]
async fn list_all_tools_blocks_while_client_is_pending_without_startup_snapshot() {
    // 无 snapshot 时应该阻塞
    let timeout_result = tokio::time::timeout(
        Duration::from_millis(10), 
        manager.list_all_tools()
    ).await;
    assert!(timeout_result.is_err());
}
```

#### 3.2.6 错误消息测试

```rust
#[test]
fn mcp_init_error_display_prompts_for_github_pat() {
    let entry = McpAuthStatusEntry {
        config: McpServerConfig {
            transport: McpServerTransportConfig::StreamableHttp {
                url: "https://api.githubcopilot.com/mcp/".to_string(),
                bearer_token_env_var: None,  // 未配置 token
                ...
            },
            ...
        },
        auth_status: McpAuthStatus::Unsupported,
    };
    
    let display = mcp_init_error_display(server_name, Some(&entry), &err);
    
    // 验证提示用户配置 PAT
    assert!(display.contains("personal access token"));
    assert!(display.contains("CODEX_GITHUB_PERSONAL_ACCESS_TOKEN"));
}

#[test]
fn mcp_init_error_display_includes_startup_timeout_hint() {
    let err: StartupOutcomeError = anyhow::anyhow!("request timed out").into();
    let display = mcp_init_error_display(server_name, None, &err);
    
    // 验证提示调整超时配置
    assert!(display.contains("startup_timeout_sec"));
}
```

---

## 四、关键代码路径与文件引用

### 4.1 被测试的函数

| 被测试函数 | 测试用例 |
|-----------|---------|
| `elicitation_is_rejected_by_policy` | `elicitation_granular_policy_defaults_to_prompting`, `elicitation_granular_policy_respects_never_and_config` |
| `qualify_tools` | `test_qualify_tools_short_non_duplicated_names`, `test_qualify_tools_duplicated_names_skipped`, `test_qualify_tools_long_names_same_server`, `test_qualify_tools_sanitizes_invalid_characters` |
| `ToolFilter::allows` | `tool_filter_allows_by_default`, `tool_filter_applies_enabled_list`, `tool_filter_applies_disabled_list`, `tool_filter_applies_enabled_then_disabled` |
| `filter_tools` | `filter_tools_applies_per_server_filters` |
| `write_cached_codex_apps_tools` / `read_cached_codex_apps_tools` | `codex_apps_tools_cache_is_overwritten_by_last_write`, `codex_apps_tools_cache_is_scoped_per_user`, `codex_apps_tools_cache_filters_disallowed_connectors` |
| `load_cached_codex_apps_tools` | `codex_apps_tools_cache_is_ignored_when_schema_version_mismatches`, `codex_apps_tools_cache_is_ignored_when_json_is_invalid` |
| `load_startup_cached_codex_apps_tools_snapshot` | `startup_cached_codex_apps_tools_loads_from_disk_cache` |
| `McpConnectionManager::list_all_tools` | `list_all_tools_uses_startup_snapshot_while_client_is_pending`, `list_all_tools_blocks_while_client_is_pending_without_startup_snapshot`, `list_all_tools_does_not_block_when_startup_snapshot_cache_hit_is_empty`, `list_all_tools_uses_startup_snapshot_when_client_startup_fails` |
| `elicitation_capability_for_server` | `elicitation_capability_enabled_only_for_codex_apps` |
| `mcp_init_error_display` | `mcp_init_error_display_prompts_for_github_pat`, `mcp_init_error_display_prompts_for_login_when_auth_required`, `mcp_init_error_display_reports_generic_errors`, `mcp_init_error_display_includes_startup_timeout_hint` |
| `transport_origin` | `transport_origin_extracts_http_origin`, `transport_origin_is_stdio_for_stdio_transport` |

### 4.2 依赖模块

```rust
use super::*;  // 导入主模块所有内容
use codex_protocol::protocol::GranularApprovalConfig;
use codex_protocol::protocol::McpAuthStatus;
use rmcp::model::JsonObject;
use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use tempfile::tempdir;  // 临时目录用于缓存测试
```

---

## 五、依赖与外部交互

### 5.1 测试框架

- **标准测试**: `#[test]` 用于同步测试
- **异步测试**: `#[tokio::test]` 用于异步测试
- **临时文件**: `tempfile::tempdir()` 创建隔离的测试环境

### 5.2 测试数据构造

| 构造目标 | 方法 |
|---------|------|
| ToolInfo | `create_test_tool()` |
| 带 connector 的 ToolInfo | `create_test_tool_with_connector()` |
| 缓存上下文 | `create_codex_apps_tools_cache_context()` |
| AsyncManagedClient | 直接构造结构体（测试专用） |
| McpAuthStatusEntry | 手动构造 |

### 5.3 特殊测试技巧

**Pending Future 模拟**:
```rust
let pending_client = futures::future::pending::<Result<ManagedClient, StartupOutcomeError>>()
    .boxed()
    .shared();
```

**Failed Future 模拟**:
```rust
let failed_client = futures::future::ready::<Result<ManagedClient, StartupOutcomeError>>(
    Err(StartupOutcomeError::Failed { error: "startup failed".to_string() })
)
.boxed()
.shared();
```

**Timeout 测试**:
```rust
let timeout_result = tokio::time::timeout(
    Duration::from_millis(10), 
    manager.list_all_tools()
).await;
assert!(timeout_result.is_err());
```

---

## 六、风险、边界与改进建议

### 6.1 测试覆盖分析

**覆盖良好**:
- 工具名称规范化逻辑
- 缓存读写和隔离
- 启动快照机制
- 错误消息格式化
- 工具过滤逻辑

**覆盖不足**:
- `call_tool` 的实际调用（需要 mock MCP 服务器）
- `list_all_resources` / `list_all_resource_templates`
- `notify_sandbox_state_change`
- `hard_refresh_codex_apps_tools_cache`
- `resolve_elicitation` 的完整流程

### 6.2 测试局限性

1. **集成测试缺失**
   - 当前主要是单元测试，缺少与真实/模拟 MCP 服务器的集成测试
   - 建议: 添加 `wiremock` 或类似工具模拟 HTTP MCP 服务器

2. **并发测试不足**
   - 缺少多线程并发访问测试
   - 建议: 添加 `tokio::spawn` 并发调用测试

3. **错误场景覆盖有限**
   - 主要测试正常路径和简单错误
   - 建议: 添加网络超时、协议错误、序列化失败等场景

### 6.3 改进建议

1. **添加属性测试 (Property-based Testing)**
   ```rust
   // 使用 proptest 验证工具名称规范化的不变性
   proptest! {
       #[test]
       fn qualify_tools_never_panics(tool_name in "[a-zA-Z0-9._-]{1,100}") {
           let tools = vec![create_test_tool("server", &tool_name)];
           let _ = qualify_tools(tools);
       }
   }
   ```

2. **添加基准测试**
   ```rust
   #[bench]
   fn bench_qualify_tools(b: &mut Bencher) {
       let tools = (0..1000).map(|i| create_test_tool("server", &format!("tool_{}", i))).collect();
       b.iter(|| qualify_tools(tools.clone()));
   }
   ```

3. **完善文档测试**
   - 为公共 API 添加 `/// # Examples` 文档测试

4. **添加模糊测试**
   - 对 JSON 解析和工具名称处理进行模糊测试

---

## 七、相关文件

| 文件 | 关系 |
|------|------|
| `mcp_connection_manager.rs` | 被测试的主模块 |
| `mcp/mod.rs` | 提供 `CODEX_APPS_MCP_SERVER_NAME`, `ToolPluginProvenance` |
| `mcp/auth.rs` | 提供 `McpAuthStatusEntry`, `McpAuthStatus` |
| `config/types.rs` | 提供 `McpServerConfig`, `McpServerTransportConfig` |

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/core/src/mcp_connection_manager_tests.rs (649 lines)*
