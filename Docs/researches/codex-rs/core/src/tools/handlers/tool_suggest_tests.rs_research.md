# tool_suggest_tests.rs 研究文档

## 场景与职责

`tool_suggest_tests.rs` 是 `tool_suggest.rs` 的配套测试模块，负责验证工具推荐功能的正确性。测试覆盖 Elicitation 请求构建、客户端过滤逻辑、连接器验证和插件安装验证等核心功能，确保 `tool_suggest` 工具在各种场景下的行为符合预期。

## 功能点目的

### 1. Elicitation 请求构建验证
验证 `build_tool_suggestion_elicitation_request` 函数生成的请求结构符合预期的协议格式，包含正确的元数据和消息内容。

### 2. 客户端过滤测试
验证 `filter_tool_suggest_discoverable_tools_for_client` 函数正确过滤掉在特定客户端（如 codex-tui）中不支持的工具类型（Plugin）。

### 3. 安装完成验证
测试连接器和插件的安装验证逻辑：
- 连接器：检查 `is_accessible` 状态
- 插件：检查 `installed` 状态和配置重载

## 具体技术实现

### 核心测试用例

#### `build_tool_suggestion_elicitation_request_uses_expected_shape`

验证连接器推荐的 Elicitation 请求结构：

```rust
#[test]
fn build_tool_suggestion_elicitation_request_uses_expected_shape() {
    // 准备测试数据
    let args = ToolSuggestArgs {
        tool_type: DiscoverableToolType::Connector,
        action_type: DiscoverableToolAction::Install,
        tool_id: "connector_2128aebfecb84f64a069897515042a44".to_string(),
        suggest_reason: "Plan and reference events from your calendar".to_string(),
    };
    let connector = DiscoverableTool::Connector(Box::new(AppInfo {
        id: "connector_2128aebfecb84f64a069897515042a44".to_string(),
        name: "Google Calendar".to_string(),
        install_url: Some("https://chatgpt.com/apps/google-calendar/...".to_string()),
        is_accessible: false,
        is_enabled: true,
        // ...
    }));

    // 执行构建
    let request = build_tool_suggestion_elicitation_request(
        "thread-1".to_string(),
        "turn-1".to_string(),
        &args,
        "Plan and reference events from your calendar",
        &connector,
    );

    // 验证结构
    assert_eq!(request, McpServerElicitationRequestParams {
        thread_id: "thread-1".to_string(),
        turn_id: Some("turn-1".to_string()),
        server_name: CODEX_APPS_MCP_SERVER_NAME.to_string(),
        request: McpServerElicitationRequest::Form {
            meta: Some(json!(ToolSuggestMeta {
                codex_approval_kind: TOOL_SUGGEST_APPROVAL_KIND_VALUE,  // "tool_suggestion"
                tool_type: DiscoverableToolType::Connector,
                suggest_type: DiscoverableToolAction::Install,
                suggest_reason: "Plan and reference events from your calendar",
                tool_id: "connector_2128aebfecb84f64a069897515042a44",
                tool_name: "Google Calendar",
                install_url: Some("https://chatgpt.com/apps/google-calendar/..."),
            })),
            message: "Plan and reference events from your calendar".to_string(),
            requested_schema: McpElicitationSchema {
                schema_uri: None,
                type_: McpElicitationObjectType::Object,
                properties: BTreeMap::new(),
                required: None,
            },
        },
    });
}
```

**关键验证点**：
1. `thread_id` 和 `turn_id` 正确传递
2. `server_name` 固定为 `CODEX_APPS_MCP_SERVER_NAME`
3. `meta` 包含完整的 `ToolSuggestMeta` 信息
4. `install_url` 从 Connector 的 `install_url` 字段提取

#### `build_tool_suggestion_elicitation_request_for_plugin_omits_install_url`

验证插件推荐的 Elicitation 请求不包含 `install_url`：

```rust
#[test]
fn build_tool_suggestion_elicitation_request_for_plugin_omits_install_url() {
    let args = ToolSuggestArgs {
        tool_type: DiscoverableToolType::Plugin,
        // ...
    };
    let plugin = DiscoverableTool::Plugin(Box::new(DiscoverablePluginInfo {
        id: "sample@openai-curated".to_string(),
        name: "Sample Plugin".to_string(),
        // 注意：Plugin 没有 install_url
        // ...
    }));

    let request = build_tool_suggestion_elicitation_request(...);

    // 验证 install_url 为 None
    assert_eq!(
        request.request,
        McpServerElicitationRequest::Form {
            meta: Some(json!(ToolSuggestMeta {
                // ...
                install_url: None,  // 关键验证点
            })),
            // ...
        }
    );
}
```

#### `filter_tool_suggest_discoverable_tools_for_codex_tui_omits_plugins`

验证 TUI 客户端的插件过滤：

```rust
#[test]
fn filter_tool_suggest_discoverable_tools_for_codex_tui_omits_plugins() {
    let discoverable_tools = vec![
        DiscoverableTool::Connector(Box::new(AppInfo { ... })),  // Google Calendar
        DiscoverableTool::Plugin(Box::new(DiscoverablePluginInfo { ... })),  // Slack
    ];

    // 过滤后只保留 Connector
    let filtered = filter_tool_suggest_discoverable_tools_for_client(
        discoverable_tools,
        Some("codex-tui"),
    );

    assert_eq!(filtered, vec![
        DiscoverableTool::Connector(Box::new(AppInfo { ... }))  // 只有 Connector
    ]);
}
```

#### `verified_connector_suggestion_completed_requires_accessible_connector`

验证连接器安装完成检查：

```rust
#[test]
fn verified_connector_suggestion_completed_requires_accessible_connector() {
    let accessible_connectors = vec![AppInfo {
        id: "calendar".to_string(),
        is_accessible: true,  // 关键：可访问
        // ...
    }];

    // 存在的连接器且可访问 -> true
    assert!(verified_connector_suggestion_completed("calendar", &accessible_connectors));

    // 不存在的连接器 -> false
    assert!(!verified_connector_suggestion_completed("gmail", &accessible_connectors));
}
```

#### `verified_plugin_suggestion_completed_requires_installed_plugin`

验证插件安装完成检查（异步测试）：

```rust
#[tokio::test]
async fn verified_plugin_suggestion_completed_requires_installed_plugin() {
    // 创建临时测试环境
    let codex_home = tempdir().expect("tempdir should succeed");
    let curated_root = crate::plugins::curated_plugins_repo_path(codex_home.path());
    write_openai_curated_marketplace(&curated_root, &["sample"]);
    write_curated_plugin_sha(codex_home.path());
    write_plugins_feature_config(codex_home.path());

    let config = load_plugins_config(codex_home.path()).await;
    let plugins_manager = PluginsManager::new(codex_home.path().to_path_buf());

    // 安装前：未安装 -> false
    assert!(!verified_plugin_suggestion_completed(
        "sample@openai-curated",
        &config,
        &plugins_manager,
    ));

    // 安装插件
    plugins_manager.install_plugin(PluginInstallRequest {
        plugin_name: "sample".to_string(),
        marketplace_path: AbsolutePathBuf::try_from(curated_root.join(".agents/plugins/marketplace.json")).unwrap(),
    }).await.expect("plugin should install");

    // 重载配置
    let refreshed_config = load_plugins_config(codex_home.path()).await;

    // 安装后：已安装 -> true
    assert!(verified_plugin_suggestion_completed(
        "sample@openai-curated",
        &refreshed_config,
        &plugins_manager,
    ));
}
```

## 关键代码路径与文件引用

### 被测试代码
- `codex-rs/core/src/tools/handlers/tool_suggest.rs`
  - `build_tool_suggestion_elicitation_request()`
  - `build_tool_suggestion_meta()`
  - `filter_tool_suggest_discoverable_tools_for_client()`（在 discoverable.rs 中）
  - `verified_connector_suggestion_completed()`
  - `verified_plugin_suggestion_completed()`

### 依赖类型
```rust
use super::*;  // 导入 tool_suggest.rs 的所有内容
use crate::plugins::{
    PluginInstallRequest, PluginsManager,
    test_support::{
        load_plugins_config, write_curated_plugin_sha,
        write_openai_curated_marketplace, write_plugins_feature_config
    }
};
use crate::tools::discoverable::{
    DiscoverablePluginInfo, filter_tool_suggest_discoverable_tools_for_client
};
use codex_app_server_protocol::AppInfo;
use codex_utils_absolute_path::AbsolutePathBuf;
use tempfile::tempdir;
```

### 测试辅助函数
```rust
// 来自 plugins::test_support
load_plugins_config(path) -> Config                    // 加载插件配置
write_openai_curated_marketplace(root, plugins)        // 写入市场配置
write_curated_plugin_sha(path)                         // 写入校验文件
write_plugins_feature_config(path)                     // 写入特性配置
```

## 依赖与外部交互

### 测试数据流
```
测试用例
    │
    ├──> build_tool_suggestion_elicitation_request_uses_expected_shape
    │       ├── 创建 ToolSuggestArgs
    │       ├── 创建 DiscoverableTool::Connector
    │       ├── 调用 build_tool_suggestion_elicitation_request()
    │       └── 验证 McpServerElicitationRequestParams 结构
    │
    ├──> filter_tool_suggest_discoverable_tools_for_codex_tui_omits_plugins
    │       ├── 创建 Connector + Plugin 列表
    │       ├── 调用 filter_tool_suggest_discoverable_tools_for_client()
    │       └── 验证 Plugin 被过滤
    │
    └──> verified_plugin_suggestion_completed_requires_installed_plugin
            ├── 创建临时目录 (tempdir)
            ├── 写入市场配置
            ├── 创建 PluginsManager
            ├── 验证未安装状态
            ├── 调用 install_plugin()
            ├── 重载配置
            └── 验证已安装状态
```

### 文件系统交互
```rust
// 临时目录结构
tempdir/
├── .agents/
│   └── plugins/
│       └── marketplace.json  # write_openai_curated_marketplace 创建
└── ...
```

## 风险、边界与改进建议

### 潜在风险

1. **硬编码客户端名称**
   ```rust
   filter_tool_suggest_discoverable_tools_for_client(discoverable_tools, Some("codex-tui"))
   ```
   - 测试依赖硬编码的 `"codex-tui"` 字符串
   - 如果常量定义变更，测试会失败

2. **测试数据与实际数据不一致**
   ```rust
   let connector = DiscoverableTool::Connector(Box::new(AppInfo {
       plugin_display_names: Vec::new(),  // 实际可能有值
       // ...
   }));
   ```
   - 测试使用简化的 AppInfo
   - 实际字段可能更多

3. **文件系统依赖**
   ```rust
   let codex_home = tempdir().expect("tempdir should succeed");
   ```
   - 依赖系统临时目录
   - 磁盘空间不足可能导致测试失败

4. **异步测试复杂性**
   ```rust
   #[tokio::test]
   async fn verified_plugin_suggestion_completed_requires_installed_plugin() {
   ```
   - 涉及多个异步操作
   - 调试困难

### 边界情况

1. **空工具列表**
   - 未测试空 `discoverable_tools` 的过滤行为

2. **None 客户端名称**
   ```rust
   // 测试使用 Some("codex-tui")
   // 未测试 None 的情况（应返回全部）
   ```

3. **连接器不可访问**
   ```rust
   // 测试使用 is_accessible: true
   // 未测试 is_accessible: false 的场景
   ```

4. **插件安装失败**
   ```rust
   // 测试假设 install_plugin 成功
   // 未测试安装失败后的验证行为
   ```

### 改进建议

1. **使用常量替代硬编码**
   ```rust
   use crate::tools::discoverable::TUI_APP_SERVER_CLIENT_NAME;
   
   filter_tool_suggest_discoverable_tools_for_client(
       discoverable_tools,
       Some(TUI_APP_SERVER_CLIENT_NAME),
   )
   ```

2. **参数化测试**
   ```rust
   #[rstest]
   #[case(Some("codex-tui"), vec![Connector])]
   #[case(None, vec![Connector, Plugin])]
   #[case(Some("codex-vscode"), vec![Connector, Plugin])]
   fn test_filter_by_client(#[case] client: Option<&str>, #[case] expected: Vec<DiscoverableTool>) {
       // 实现参数化测试
   }
   ```

3. **添加失败场景测试**
   ```rust
   #[tokio::test]
   async fn verified_plugin_suggestion_completed_handles_install_failure() {
       // 测试安装失败后的行为
   }
   ```

4. **使用快照测试**
   ```rust
   #[test]
   fn build_tool_suggestion_elicitation_request_matches_snapshot() {
       let request = build_tool_suggestion_elicitation_request(...);
       insta::assert_json_snapshot!(request);
   }
   ```

5. **提取公共设置代码**
   ```rust
   async fn setup_plugin_test_env() -> (TempDir, Config, PluginsManager) {
       // 提取公共的测试环境设置
   }
   ```

6. **验证更多字段**
   ```rust
   // 当前测试只验证部分字段
   // 建议验证完整的 AppInfo 结构
   assert_eq!(filtered[0].name, "Google Calendar");
   assert_eq!(filtered[0].is_enabled, true);
   ```

### 维护注意事项

1. 当 `McpServerElicitationRequestParams` 结构变更时，需要同步更新测试
2. `AppInfo` 和 `DiscoverablePluginInfo` 字段变更会影响测试数据构造
3. 插件安装流程变更可能需要更新异步测试
4. 考虑使用 `pretty_assertions` 改善大型结构体的 diff 输出
