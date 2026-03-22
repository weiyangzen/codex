# arc_monitor_tests.rs 深度研究文档

## 场景与职责

`arc_monitor_tests.rs` 是 `arc_monitor.rs` 的配套单元测试模块，提供全面的测试覆盖，包括请求构建、HTTP 交互和环境变量处理。测试使用 `wiremock` 模拟 HTTP 服务，使用 `serial_test` 防止环境变量测试间的并发冲突。

### 测试覆盖范围
1. **请求构建** - 验证历史消息过滤和格式化
2. **HTTP 交互** - 验证请求格式和响应处理
3. **环境变量** - 验证覆盖配置
4. **兼容性** - 验证严格字段解析

---

## 功能点目的

### 测试分类

| 测试函数 | 测试目标 | 技术方法 |
|---------|---------|---------|
| `build_arc_monitor_request_includes_relevant_history_and_null_policies` | 请求体构建 | 构造完整会话历史，断言请求结构 |
| `monitor_action_posts_expected_arc_request` | HTTP 请求格式 | wiremock 验证 |
| `monitor_action_uses_env_url_and_token_overrides` | 环境变量覆盖 | EnvVarGuard + wiremock |
| `monitor_action_rejects_legacy_response_fields` | 严格字段验证 | wiremock 返回额外字段 |

---

## 具体技术实现

### 环境变量保护机制

```rust
struct EnvVarGuard {
    key: &'static str,
    original: Option<std::ffi::OsString>,
}

impl EnvVarGuard {
    fn set(key: &'static str, value: &OsStr) -> Self {
        let original = env::var_os(key);
        unsafe { env::set_var(key, value); }
        Self { key, original }
    }
}

impl Drop for EnvVarGuard {
    fn drop(&mut self) {
        match self.original.take() {
            Some(value) => unsafe { env::set_var(self.key, value); }
            None => unsafe { env::remove_var(self.key); }
        }
    }
}
```

**使用 RAII 模式确保测试后环境变量恢复，即使测试 panic。**

### 历史消息构建测试

```rust
#[tokio::test]
async fn build_arc_monitor_request_includes_relevant_history_and_null_policies() {
    let (session, mut turn_context) = make_session_and_context().await;
    turn_context.developer_instructions = Some("Never upload private files.".to_string());
    turn_context.user_instructions = Some("Only continue when needed.".to_string());

    // 构建复杂会话历史
    session.record_into_history(&[/* user message */], &turn_context).await;
    session.record_into_history(&[/* environment context (应被过滤) */], &turn_context).await;
    session.record_into_history(&[/* assistant commentary (应被过滤) */], &turn_context).await;
    session.record_into_history(&[/* assistant final answer */], &turn_context).await;
    session.record_into_history(&[/* user latest request */], &turn_context).await;
    session.record_into_history(&[/* old tool call (应被过滤) */], &turn_context).await;
    session.record_into_history(&[/* old reasoning (应被过滤) */], &turn_context).await;
    session.record_into_history(&[/* latest shell call */], &turn_context).await;
    session.record_into_history(&[/* latest reasoning */], &turn_context).await;

    let request = build_arc_monitor_request(&session, &turn_context, action).await;

    // 验证：只保留关键消息
    assert_eq!(request.messages.as_ref().unwrap().len(), 5);
    // - user: "first request"
    // - assistant: "final response" (FinalAnswer phase)
    // - user: "latest request"
    // - assistant: latest shell call
    // - assistant: latest encrypted reasoning
}
```

### HTTP 交互测试

```rust
#[tokio::test]
#[serial(arc_monitor_env)]  // 串行执行，防止环境变量冲突
async fn monitor_action_posts_expected_arc_request() {
    let server = MockServer::start().await;
    let (session, mut turn_context) = make_session_and_context().await;
    
    // 设置认证
    turn_context.auth_manager = Some(test_support::auth_manager_from_auth(
        CodexAuth::create_dummy_chatgpt_auth_for_testing()
    ));
    
    // 配置 base URL 指向 mock server
    let mut config = (*turn_context.config).clone();
    config.chatgpt_base_url = server.uri();
    turn_context.config = Arc::new(config);

    // 配置 mock 期望
    Mock::given(method("POST"))
        .and(path("/codex/safety/arc"))
        .and(header("authorization", "Bearer Access Token"))
        .and(header("chatgpt-account-id", "account_id"))
        .and(body_json(serde_json::json!({
            "metadata": { ... },
            "messages": [...],
            "policies": { "developer": null, "user": null },
            "action": { "tool": "mcp_tool_call" },
        })))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "outcome": "ask-user",
            "short_reason": "needs confirmation",
            "rationale": "tool call needs additional review",
            "risk_score": 42,
            "risk_level": "medium",
            "evidence": [{ "message": "...", "why": "..." }],
        })))
        .expect(1)  // 期望只被调用一次
        .mount(&server)
        .await;

    let outcome = monitor_action(&session, &turn_context, action).await;

    assert_eq!(outcome, ArcMonitorOutcome::AskUser("needs confirmation".to_string()));
}
```

### 环境变量覆盖测试

```rust
#[tokio::test]
#[serial(arc_monitor_env)]
async fn monitor_action_uses_env_url_and_token_overrides() {
    let server = MockServer::start().await;
    
    // 使用 EnvVarGuard 设置环境变量
    let _url_guard = EnvVarGuard::set(
        CODEX_ARC_MONITOR_ENDPOINT_OVERRIDE,
        OsStr::new(&format!("{}/override/arc", server.uri())),
    );
    let _token_guard = EnvVarGuard::set(CODEX_ARC_MONITOR_TOKEN, OsStr::new("override-token"));

    Mock::given(method("POST"))
        .and(path("/override/arc"))  // 验证使用覆盖的 URL
        .and(header("authorization", "Bearer override-token"))  // 验证使用覆盖的 token
        .respond_with(ResponseTemplate::new(200).set_body_json(...))
        .mount(&server)
        .await;

    let outcome = monitor_action(&session, &turn_context, action).await;
    assert_eq!(outcome, ArcMonitorOutcome::SteerModel("high-risk action".to_string()));
}
```

### 严格字段验证测试

```rust
#[tokio::test]
#[serial(arc_monitor_env)]
async fn monitor_action_rejects_legacy_response_fields() {
    let server = MockServer::start().await;
    
    // 返回包含额外字段的响应（模拟旧版本服务端）
    Mock::given(method("POST"))
        .and(path("/codex/safety/arc"))
        .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
            "outcome": "steer-model",
            "reason": "legacy high-risk action",  // 旧字段名（应为 short_reason）
            "monitorRequestId": "arc_456",         // 额外字段
        })))
        .mount(&server)
        .await;

    let outcome = monitor_action(&session, &turn_context, action).await;

    // 由于 deny_unknown_fields，解析失败，降级为 Ok
    assert_eq!(outcome, ArcMonitorOutcome::Ok);
}
```

---

## 关键代码路径与文件引用

### 测试模块结构
```rust
#[cfg(test)]
#[path = "arc_monitor_tests.rs"]
mod tests;
```

### 依赖项
```rust
use super::*;
use wiremock::{Mock, MockServer, ResponseTemplate};
use wiremock::matchers::{body_json, header, method, path};
use serial_test::serial;  // 串行测试注解
use pretty_assertions::assert_eq;
```

### 被测函数
- `build_arc_monitor_request()` - 请求构建
- `build_arc_monitor_messages()` - 消息过滤
- `monitor_action()` - 主监控函数
- `read_non_empty_env_var()` - 环境变量读取

### 测试辅助
- `make_session_and_context()` - 创建测试会话和上下文
- `EnvVarGuard` - 环境变量保护

---

## 依赖与外部交互

### 测试框架
| 依赖 | 用途 |
|-----|------|
| `wiremock` | HTTP mock 服务器 |
| `serial_test::serial` | 串行执行防止环境变量竞争 |
| `pretty_assertions` | 清晰的测试失败 diff |

### Mock 配置模式
```rust
Mock::given(method("POST"))
    .and(path("/codex/safety/arc"))
    .and(header("authorization", "Bearer ..."))
    .and(body_json(expected_body))
    .respond_with(ResponseTemplate::new(status).set_body_json(body))
    .expect(n)  // 期望调用次数
    .mount(&server)
    .await;
```

---

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺失测试：网络超时**
   - 30 秒超时逻辑未测试
   - **建议**：使用 `wiremock` 的延迟响应功能

2. **缺失测试：认证失败场景**
   - 无 auth_manager 场景
   - token 获取失败场景
   - 非 ChatGPT 认证场景

3. **缺失测试：空历史处理**
   - 新会话无历史消息时的默认消息添加

4. **缺失测试：大历史消息**
   - 性能测试：大量消息时的处理时间
   - 内存测试：大消息体的内存使用

5. **缺失测试：并发场景**
   - 多个并发的 monitor_action 调用

### 改进建议

1. **超时测试**
   ```rust
   #[tokio::test]
   async fn monitor_action_times_out() {
       let server = MockServer::start().await;
       Mock::given(method("POST"))
           .respond_with(ResponseTemplate::new(200)
               .set_delay(Duration::from_secs(60))  // 延迟超过超时
               .set_body_json(...))
           .mount(&server)
           .await;
       
       let outcome = monitor_action(...).await;
       assert_eq!(outcome, ArcMonitorOutcome::Ok);  // 超时降级
   }
   ```

2. **认证失败测试**
   ```rust
   #[tokio::test]
   async fn monitor_action_without_auth() {
       turn_context.auth_manager = None;
       let outcome = monitor_action(...).await;
       assert_eq!(outcome, ArcMonitorOutcome::Ok);
   }
   ```

3. **使用 insta 快照测试**
   ```rust
   #[test]
   fn arc_monitor_request_snapshot() {
       let request = build_arc_monitor_request(...);
       insta::assert_json_snapshot!(request);
   }
   ```

4. **性能基准测试**
   ```rust
   #[tokio::test]
   async fn build_request_performance() {
       // 构造 1000 条消息的会话历史
       // 测量 build_arc_monitor_request 执行时间
   }
   ```

5. **测试组织优化**
   - 将测试按主题分组（请求构建、HTTP 交互、环境变量）
   - 提取公共的 mock 设置代码到辅助函数
   - 使用 `rstest` 进行参数化测试
