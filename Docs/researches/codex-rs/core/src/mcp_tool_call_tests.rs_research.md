# mcp_tool_call_tests.rs 研究文档

## 场景与职责

`mcp_tool_call_tests.rs` 是 `mcp_tool_call.rs` 的配套测试模块，使用 Rust 的 `#[cfg(test)]` 条件编译属性嵌入到主模块中。该测试文件负责：

1. **单元测试覆盖**：对 `mcp_tool_call.rs` 中的公共和私有函数进行全面的单元测试
2. **审批逻辑验证**：验证各种审批模式、决策转换和边界条件
3. **集成测试支持**：通过 mock 服务器测试与外部服务（ARC、Guardian）的交互
4. **配置持久化测试**：验证审批设置的持久化和重新加载
5. **模板渲染测试**：验证 MCP 工具审批提示模板的正确性

该测试模块是确保 MCP 工具调用系统正确性和稳定性的关键保障。

## 功能点目的

### 1. 审批注解判断测试

**目的**：验证 `requires_mcp_tool_approval` 函数对各种工具注解的正确判断。

**测试用例**：
- `approval_required_when_read_only_false_and_destructive`：破坏性操作必须审批
- `approval_required_when_read_only_false_and_open_world`：涉及外部世界的非只读操作需要审批
- `approval_required_when_destructive_even_if_read_only_true`：即使标记为只读，破坏性操作仍需审批

### 2. 审批决策模式测试

**目的**：验证不同审批模式下的决策转换逻辑。

**测试用例**：
- `prompt_mode_does_not_allow_persistent_remember`：Prompt 模式下不接受持久化记忆选项
- `normalize_approval_decision_for_mode` 相关测试：验证决策在模式转换时的正确性

### 3. 审批提示构建测试

**目的**：验证审批提示（question）的构建逻辑，包括文本生成和选项设置。

**测试用例**：
- `approval_question_text_prepends_safety_reason`：安全监控原因正确附加到问题文本
- `custom_mcp_tool_question_mentions_server_name`：自定义服务器正确显示服务器名称
- `codex_apps_tool_question_uses_fallback_app_label`：codex_apps 工具使用默认标签
- `trusted_codex_apps_tool_question_offers_always_allow`：受信任的 codex_apps 工具提供"始终允许"选项
- `codex_apps_tool_question_without_elicitation_omits_always_allow`：无 elicitation 时省略持久化选项
- `custom_mcp_tool_question_offers_session_remember_without_always_allow`：自定义服务器仅提供会话记忆

### 4. 审批键值生成测试

**目的**：验证会话级和持久化审批键值的生成逻辑。

**测试用例**：
- `custom_servers_keep_session_remember_without_persistent_approval`：自定义服务器仅支持会话记忆
- `codex_apps_connectors_support_persistent_approval`：codex_apps 连接器支持持久化审批

### 5. 工具结果清理测试

**目的**：验证 `sanitize_mcp_tool_result_for_model` 函数对工具结果的正确处理。

**测试用例**：
- `sanitize_mcp_tool_result_for_model_rewrites_image_content`：不支持图像时重写图像内容
- `sanitize_mcp_tool_result_for_model_preserves_image_when_supported`：支持图像时保留原始内容

### 6. Elicitation 请求构建测试

**目的**：验证 MCP Elicitation 请求的构建和解析。

**测试用例**：
- `approval_elicitation_request_uses_message_override_and_preserves_tool_params_keys`：请求正确包含工具参数
- `approval_elicitation_meta_marks_tool_approvals`：元数据正确标记工具审批
- `approval_elicitation_meta_keeps_session_persist_behavior_for_custom_servers`：自定义服务器会话持久化行为
- `approval_elicitation_meta_includes_connector_source_for_codex_apps`：codex_apps 包含连接器源信息
- `approval_elicitation_meta_merges_session_and_always_persist_with_connector_source`：合并会话和持久化选项

### 7. Guardian 集成测试

**目的**：验证与 Guardian 审批代理的集成。

**测试用例**：
- `guardian_mcp_review_request_includes_invocation_metadata`：请求包含调用元数据
- `guardian_mcp_review_request_includes_annotations_when_present`：请求包含工具注解
- `guardian_review_decision_maps_to_mcp_tool_decision`：Guardian 决策正确映射到 MCP 决策
- `approve_mode_routes_arc_ask_user_to_guardian_when_guardian_reviewer_is_enabled`：ARC 询问用户时路由到 Guardian

### 8. ARC 集成测试

**目的**：验证与 ARC 安全监控系统的集成。

**测试用例**：
- `approve_mode_blocks_when_arc_returns_interrupt_for_model`：ARC 返回中断时阻止执行
- `prepare_arc_request_action_serializes_mcp_tool_call_shape`：ARC 请求正确序列化

### 9. 配置持久化测试

**目的**：验证审批设置的持久化和重新加载。

**测试用例**：
- `persist_codex_app_tool_approval_writes_tool_override`：正确写入工具覆盖配置
- `maybe_persist_mcp_tool_approval_reloads_session_config`：持久化后重新加载配置

### 10. Elicitation 响应解析测试

**目的**：验证 Elicitation 响应的正确解析。

**测试用例**：
- `accepted_elicitation_content_converts_to_request_user_input_response`：接受响应正确转换
- `declined_elicitation_response_stays_decline`：拒绝响应保持拒绝状态
- `synthetic_decline_request_user_input_response_stays_decline`：合成拒绝令牌正确处理
- `accepted_elicitation_response_uses_always_persist_meta`：持久化元数据正确使用
- `accepted_elicitation_response_uses_session_persist_meta`：会话持久化元数据正确使用
- `accepted_elicitation_without_content_defaults_to_accept`：无内容时默认接受

### 11. 请求元数据构建测试

**目的**：验证工具调用请求元数据的构建。

**测试用例**：
- `codex_apps_tool_call_request_meta_includes_codex_apps_meta`：codex_apps 元数据正确包含

## 具体技术实现

### 测试辅助函数

```rust
// 构建工具注解
fn annotations(
    read_only: Option<bool>,
    destructive: Option<bool>,
    open_world: Option<bool>,
) -> ToolAnnotations {
    ToolAnnotations {
        destructive_hint: destructive,
        idempotent_hint: None,
        open_world_hint: open_world,
        read_only_hint: read_only,
        title: None,
    }
}

// 构建审批元数据
fn approval_metadata(
    connector_id: Option<&str>,
    connector_name: Option<&str>,
    connector_description: Option<&str>,
    tool_title: Option<&str>,
    tool_description: Option<&str>,
) -> McpToolApprovalMetadata {
    McpToolApprovalMetadata {
        annotations: None,
        connector_id: connector_id.map(str::to_string),
        connector_name: connector_name.map(str::to_string),
        connector_description: connector_description.map(str::to_string),
        tool_title: tool_title.map(str::to_string),
        tool_description: tool_description.map(str::to_string),
        codex_apps_meta: None,
    }
}

// 构建提示选项
fn prompt_options(
    allow_session_remember: bool,
    allow_persistent_approval: bool,
) -> McpToolApprovalPromptOptions {
    McpToolApprovalPromptOptions {
        allow_session_remember,
        allow_persistent_approval,
    }
}
```

### Mock 服务器测试模式

```rust
// 使用 wiremock 创建 ARC mock 服务器
let server = MockServer::start().await;
Mock::given(method("POST"))
    .and(path("/codex/safety/arc"))
    .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
        "outcome": "steer-model",
        "short_reason": "needs approval",
        "rationale": "high-risk action",
        "risk_score": 96,
        "risk_level": "critical",
        "evidence": [...],
    })))
    .expect(1)
    .mount(&server)
    .await;
```

### Guardian 集成测试模式

```rust
// 使用 core_test_support 的 mock SSE 响应
let guardian_request_log = mount_sse_once(
    &server,
    sse(vec![
        ev_response_created("resp-guardian"),
        ev_assistant_message("msg-guardian", &risk_assessment_json),
        ev_completed("resp-guardian"),
    ]),
).await;

// 验证 Guardian 请求
assert_eq!(
    guardian_request_log.single_request().path(),
    "/v1/responses"
);
```

### 配置持久化测试模式

```rust
// 使用临时目录测试配置写入
let tmp = tempdir().expect("tempdir");
persist_codex_app_tool_approval(tmp.path(), "calendar", "calendar/list_events")
    .await
    .expect("persist approval");

// 读取并验证配置内容
let contents = std::fs::read_to_string(tmp.path().join(CONFIG_TOML_FILE)).expect("read config");
let parsed: ConfigToml = toml::from_str(&contents).expect("parse config");
assert!(contents.contains("[apps.calendar.tools.\"calendar/list_events\"]"));
```

## 关键代码路径与文件引用

### 测试框架依赖

| Crate/模块 | 用途 |
|------------|------|
| `tokio::test` | 异步测试运行时 |
| `wiremock` | HTTP mock 服务器 |
| `tempfile::tempdir` | 临时目录创建 |
| `pretty_assertions::assert_eq` | 美观的断言输出 |
| `core_test_support` | 核心测试支持库（mock SSE 等） |

### 被测试的模块

| 被测试项 | 测试覆盖 |
|----------|----------|
| `requires_mcp_tool_approval` | 注解判断逻辑 |
| `normalize_approval_decision_for_mode` | 决策模式转换 |
| `mcp_tool_approval_question_text` | 问题文本构建 |
| `build_mcp_tool_approval_question` | 审批问题构建 |
| `session_mcp_tool_approval_key` | 会话键值生成 |
| `persistent_mcp_tool_approval_key` | 持久化键值生成 |
| `sanitize_mcp_tool_result_for_model` | 结果清理 |
| `build_mcp_tool_approval_elicitation_request` | Elicitation 请求构建 |
| `build_mcp_tool_approval_elicitation_meta` | Elicitation 元数据构建 |
| `build_guardian_mcp_tool_review_request` | Guardian 请求构建 |
| `mcp_tool_approval_decision_from_guardian` | Guardian 决策映射 |
| `prepare_arc_request_action` | ARC 请求准备 |
| `parse_mcp_tool_approval_elicitation_response` | Elicitation 响应解析 |
| `parse_mcp_tool_approval_response` | 审批响应解析 |
| `request_user_input_response_from_elicitation_content` | 响应转换 |
| `build_mcp_tool_call_request_meta` | 请求元数据构建 |
| `persist_codex_app_tool_approval` | 配置持久化 |
| `maybe_persist_mcp_tool_approval` | 条件持久化 |
| `maybe_request_mcp_tool_approval` | 完整审批流程（集成测试） |

### 测试常量使用

```rust
// 来自主模块的常量
CODEX_APPS_MCP_SERVER_NAME  // "codex_apps"
MCP_TOOL_APPROVAL_ACCEPT
MCP_TOOL_APPROVAL_ACCEPT_FOR_SESSION
MCP_TOOL_APPROVAL_ACCEPT_AND_REMEMBER
MCP_TOOL_APPROVAL_CANCEL
MCP_TOOL_APPROVAL_DECLINE_SYNTHETIC
MCP_TOOL_APPROVAL_KIND_KEY
MCP_TOOL_APPROVAL_KIND_MCP_TOOL_CALL
MCP_TOOL_APPROVAL_PERSIST_KEY
MCP_TOOL_APPROVAL_PERSIST_SESSION
MCP_TOOL_APPROVAL_PERSIST_ALWAYS
MCP_TOOL_APPROVAL_SOURCE_KEY
MCP_TOOL_APPROVAL_SOURCE_CONNECTOR
// ... 其他常量
```

## 依赖与外部交互

### 测试环境设置

```rust
// 创建测试会话和上下文
let (session, turn_context) = make_session_and_context().await;
let session = Arc::new(session);
let turn_context = Arc::new(turn_context);
```

### Mock 外部服务

1. **ARC 服务**：使用 wiremock 模拟 `/codex/safety/arc` 端点
2. **Guardian 服务**：使用 `core_test_support::responses` 模拟 SSE 响应流
3. **模型服务**：通过 `mount_sse_once` 模拟模型响应

### 配置测试

```rust
// 修改配置进行测试
let mut config = (*turn_context.config).clone();
config.chatgpt_base_url = server.uri();
config.model_provider.base_url = Some(format!("{}/v1", server.uri()));
config.approvals_reviewer = ApprovalsReviewer::GuardianSubagent;
turn_context.config = Arc::new(config);
```

## 风险、边界与改进建议

### 测试覆盖分析

**覆盖良好的区域**：
- 审批决策逻辑（各种模式组合）
- 提示构建和选项生成
- Elicitation 请求/响应解析
- 配置持久化
- Guardian 和 ARC 集成

**潜在覆盖不足**：
- 并发场景下的审批状态竞争
- 大规模工具列表的性能测试
- 网络超时和重试逻辑
- 配置文件损坏的恢复逻辑

### 已知测试限制

1. **Mock 依赖**：测试大量依赖 mock 服务器，可能与真实服务行为存在差异
2. **单线程执行**：异步测试使用单线程运行时，可能无法发现真正的并发问题
3. **配置隔离**：部分测试修改全局配置状态，可能影响其他测试（虽然使用临时目录缓解）

### 改进建议

1. **属性测试**：使用 `proptest` 对审批决策逻辑进行属性测试，覆盖更多输入组合

2. **并发测试**：添加多线程并发调用同一工具审批的测试，验证状态一致性

3. **性能测试**：添加大规模工具列表（1000+）的查询性能测试

4. **故障注入**：测试 MCP 连接管理器不可用、配置文件只读等故障场景

5. **端到端测试**：添加更完整的端到端测试，模拟真实用户交互流程

6. **测试数据生成**：使用工厂模式生成测试数据，减少重复代码

7. **测试文档化**：为复杂测试添加更多注释，说明测试意图和预期行为

8. **覆盖率监控**：集成代码覆盖率工具，确保关键路径的测试覆盖
