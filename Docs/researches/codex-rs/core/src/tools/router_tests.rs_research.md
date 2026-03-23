# router_tests.rs 深度研究文档

## 场景与职责

`router_tests.rs` 是 `router.rs` 的单元测试模块，主要验证工具路由层的以下功能：

1. **JS REPL 工具限制**：验证 `js_repl_tools_only` 配置正确阻止/允许工具调用
2. **命名空间处理**：验证工具调用构建时正确处理命名空间
3. **权限控制**：验证不同调用来源（Direct vs JsRepl）的权限差异

这些测试确保工具路由层在安全和功能方面的正确性。

## 功能点目的

### 测试覆盖范围

1. **JS REPL 工具限制测试**
   - `js_repl_tools_only_blocks_direct_tool_calls`: 验证直接调用被阻止
   - `js_repl_tools_only_allows_js_repl_source_calls`: 验证 JsRepl 来源可绕过限制

2. **命名空间处理测试**
   - `build_tool_call_uses_namespace_for_registry_name`: 验证命名空间正确传递到 ToolCall

### 测试策略

- 使用 `make_session_and_context()` 创建测试会话
- 修改配置以启用特定功能（如 `js_repl_tools_only`）
- 验证成功和失败场景

## 具体技术实现

### 测试辅助

```rust
// 使用 codex.rs 中的测试辅助函数
let (session, mut turn) = make_session_and_context().await;
turn.tools_config.js_repl_tools_only = true;
```

### 核心测试用例

#### 1. JS REPL 工具限制 - 阻止直接调用

```rust
#[tokio::test]
async fn js_repl_tools_only_blocks_direct_tool_calls() -> anyhow::Result<()> {
    // 设置：启用 js_repl_tools_only
    let (session, mut turn) = make_session_and_context().await;
    turn.tools_config.js_repl_tools_only = true;

    // 构建路由器和工具调用
    let router = build_test_router(&session, &turn).await;
    let call = ToolCall {
        tool_name: "shell".to_string(),  // 非 js_repl 工具
        tool_namespace: None,
        call_id: "call-1".to_string(),
        payload: ToolPayload::Function { arguments: "{}".to_string() },
    };

    // 执行：Direct 来源调用
    let err = router
        .dispatch_tool_call_with_code_mode_result(..., ToolCallSource::Direct)
        .await
        .err()
        .expect("direct tool calls should be blocked");

    // 验证：返回 RespondToModel 错误
    let FunctionCallError::RespondToModel(message) = err else {
        panic!("expected RespondToModel, got {err:?}");
    };
    assert!(message.contains("direct tool calls are disabled"));

    Ok(())
}
```

#### 2. JS REPL 工具限制 - 允许 JsRepl 来源

```rust
#[tokio::test]
async fn js_repl_tools_only_allows_js_repl_source_calls() -> anyhow::Result<()> {
    // 设置同上...

    // 执行：JsRepl 来源调用
    let err = router
        .dispatch_tool_call_with_code_mode_result(..., ToolCallSource::JsRepl)
        .await
        .err()
        .expect("shell call with empty args should fail");

    // 验证：错误不包含 "direct tool calls are disabled"
    let message = err.to_string();
    assert!(
        !message.contains("direct tool calls are disabled"),
        "js_repl source should bypass direct-call policy gate"
    );

    Ok(())
}
```

#### 3. 命名空间处理

```rust
#[tokio::test]
async fn build_tool_call_uses_namespace_for_registry_name() -> anyhow::Result<()> {
    let (session, _) = make_session_and_context().await;

    // 构建带命名空间的 FunctionCall
    let call = ToolRouter::build_tool_call(
        &session,
        ResponseItem::FunctionCall {
            id: None,
            name: "create_event".to_string(),
            namespace: Some("mcp__codex_apps__calendar".to_string()),
            arguments: "{}".to_string(),
            call_id: "call-namespace".to_string(),
        },
    )
    .await?
    .expect("function_call should produce a tool call");

    // 验证：命名空间正确传递
    assert_eq!(call.tool_name, "create_event");
    assert_eq!(call.tool_namespace, Some("mcp__codex_apps__calendar".to_string()));
    assert_eq!(call.call_id, "call-namespace");

    Ok(())
}
```

### 测试流程图

```
┌─────────────────────────────────────────────────────────────────┐
│          js_repl_tools_only_blocks_direct_tool_calls             │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建会话和回合                                                │
│ 2. 启用 js_repl_tools_only                                       │
│ 3. 构建 ToolRouter                                               │
│ 4. 创建 shell 工具调用（非 js_repl 工具）                       │
│ 5. 使用 ToolCallSource::Direct 分发                             │
│ 6. 验证返回 RespondToModel 错误                                  │
│ 7. 验证错误消息包含 "direct tool calls are disabled"            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│          js_repl_tools_only_allows_js_repl_source_calls          │
├─────────────────────────────────────────────────────────────────┤
│ 1-4. 同上                                                        │
│ 5. 使用 ToolCallSource::JsRepl 分发                             │
│ 6. 验证调用未被阻止（虽然可能因其他原因失败）                   │
│ 7. 验证错误消息不包含 "direct tool calls are disabled"          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│          build_tool_call_uses_namespace_for_registry_name        │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建会话                                                      │
│ 2. 构建带 namespace 的 ResponseItem::FunctionCall               │
│ 3. 调用 ToolRouter::build_tool_call()                           │
│ 4. 验证返回 Some(ToolCall)                                      │
│ 5. 验证 tool_name、tool_namespace、call_id 正确                 │
│ 6. 验证 payload 类型正确                                         │
└─────────────────────────────────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `ToolRouter::dispatch_tool_call_with_code_mode_result()` | `router.rs:215-251` |
| `ToolRouter::build_tool_call()` | `router.rs:117-212` |
| `js_repl_tools_only` 检查 | `router.rs:230-238` |

### 关键被测试代码片段

```rust
// router.rs:230-238
if source == ToolCallSource::Direct
    && turn.tools_config.js_repl_tools_only
    && !matches!(tool_name.as_str(), "js_repl" | "js_repl_reset")
{
    return Err(FunctionCallError::RespondToModel(
        "direct tool calls are disabled; use js_repl and codex.tool(...) instead"
            .to_string(),
    ));
}
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `crate::codex::make_session_and_context` | 创建测试会话 |
| `crate::tools::context::{ToolPayload, ToolCallSource}` | 工具调用类型 |
| `crate::turn_diff_tracker::TurnDiffTracker` | 差异跟踪 |
| `codex_protocol::models::ResponseItem` | 响应项类型 |

### 测试模块声明

```rust
// router.rs:253-255
#[cfg(test)]
#[path = "router_tests.rs"]
mod tests;
```

## 风险、边界与改进建议

### 当前测试的局限性

1. **未测试 Code Mode 来源**
   - 仅测试了 Direct 和 JsRepl 来源
   - 未测试 `ToolCallSource::CodeMode`

2. **未测试其他工具类型**
   - 仅测试了 `ToolPayload::Function`
   - 未测试 ToolSearch、Custom、LocalShell、Mcp

3. **未测试错误边界**
   - 未测试 `build_tool_call` 返回 `Ok(None)` 的场景
   - 未测试参数解析失败

4. **MCP 工具测试不完整**
   - 命名空间测试未涉及 MCP 解析逻辑
   - 未测试 `parse_mcp_tool_name` 的返回值影响

### 边界情况未覆盖

1. **空工具名**
   ```rust
   // 未测试：tool_name = ""
   ```

2. **特殊字符命名空间**
   ```rust
   // 未测试：namespace 包含特殊字符
   ```

3. **并发调用**
   - 未测试多线程环境下的路由行为

4. **配置热更新**
   - 未测试 `js_repl_tools_only` 在运行时的变更

### 改进建议

1. **添加 Code Mode 来源测试**
   ```rust
   #[tokio::test]
   async fn js_repl_tools_only_allows_code_mode_source_calls() {
       // 验证 Code Mode 来源也可绕过限制
   }
   ```

2. **添加其他工具类型测试**
   ```rust
   #[tokio::test]
   async fn build_tool_call_handles_tool_search() {
       // 测试 ToolSearchCall 构建
   }
   
   #[tokio::test]
   async fn build_tool_call_handles_local_shell() {
       // 测试 LocalShellCall 构建
   }
   ```

3. **添加错误场景测试**
   ```rust
   #[tokio::test]
   async fn build_tool_call_returns_none_for_server_execution() {
       // 测试 execution != "client" 返回 None
   }
   ```

4. **添加 MCP 解析测试**
   ```rust
   #[tokio::test]
   async fn build_tool_call_parses_mcp_tool_name() {
       // 测试 MCP 工具名解析为 Mcp payload
   }
   ```

5. **添加并发测试**
   ```rust
   #[tokio::test]
   async fn concurrent_dispatch_is_safe() {
       // 测试多线程分发安全性
   }
   ```

6. **提取测试辅助函数**
   ```rust
   // 当前每个测试都重复构建 router 的代码
   // 建议提取辅助函数
   async fn setup_test_router(js_repl_only: bool) -> (Arc<Session>, Arc<TurnContext>, ToolRouter) {
       // ...
   }
   ```

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/router.rs` | 被测试的主模块 |
| `codex-rs/core/src/tools/registry.rs` | 被 router 调用 |
| `codex-rs/core/src/codex.rs` | `make_session_and_context` 定义 |
| `codex-rs/core/src/turn_diff_tracker.rs` | `TurnDiffTracker` 定义 |
