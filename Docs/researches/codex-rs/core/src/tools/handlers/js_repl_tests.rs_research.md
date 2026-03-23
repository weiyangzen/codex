# js_repl_tests.rs 深度研究文档

## 场景与职责

`js_repl_tests.rs` 是 `js_repl.rs` 的单元测试模块，负责验证 JavaScript REPL 工具的参数解析和事件发射功能。该测试文件作为内联测试模块被包含在 `js_repl.rs` 中。

## 功能点目的

### 测试覆盖范围

1. **参数解析测试** - 验证 `parse_freeform_args` 对各种输入格式的处理
2. **Pragma 解析测试** - 验证超时配置解析
3. **错误场景测试** - 验证无效输入的错误处理
4. **事件发射测试** - 验证 `emit_js_repl_exec_end` 正确发送事件

## 具体技术实现

### 测试用例详情

#### 1. `parse_freeform_args_without_pragma`

```rust
#[test]
fn parse_freeform_args_without_pragma() {
    let args = parse_freeform_args("console.log('ok');").expect("parse args");
    assert_eq!(args.code, "console.log('ok');");
    assert_eq!(args.timeout_ms, None);
}
```

**测试目的：** 验证无 pragma 的普通 JavaScript 代码正确解析

#### 2. `parse_freeform_args_with_pragma`

```rust
#[test]
fn parse_freeform_args_with_pragma() {
    let input = "// codex-js-repl: timeout_ms=15000\nconsole.log('ok');";
    let args = parse_freeform_args(input).expect("parse args");
    assert_eq!(args.code, "console.log('ok');");
    assert_eq!(args.timeout_ms, Some(15_000));
}
```

**测试目的：** 验证 pragma 正确解析，超时设置提取成功

#### 3. `parse_freeform_args_rejects_unknown_key`

```rust
#[test]
fn parse_freeform_args_rejects_unknown_key() {
    let err = parse_freeform_args("// codex-js-repl: nope=1\nconsole.log('ok');")
        .expect_err("expected error");
    assert_eq!(
        err.to_string(),
        "js_repl pragma only supports timeout_ms; got `nope`"
    );
}
```

**测试目的：** 验证未知 pragma 键被拒绝

#### 4. `parse_freeform_args_rejects_reset_key`

```rust
#[test]
fn parse_freeform_args_rejects_reset_key() {
    let err = parse_freeform_args("// codex-js-repl: reset=true\nconsole.log('ok');")
        .expect_err("expected error");
    assert_eq!(
        err.to_string(),
        "js_repl pragma only supports timeout_ms; got `reset`"
    );
}
```

**测试目的：** 验证 `reset` 键被拒绝（应使用 `js_repl_reset` 工具）

#### 5. `parse_freeform_args_rejects_json_wrapped_code`

```rust
#[test]
fn parse_freeform_args_rejects_json_wrapped_code() {
    let err = parse_freeform_args(r#"{"code":"await doThing()"}"#).expect_err("expected error");
    assert_eq!(
        err.to_string(),
        "js_repl is a freeform tool and expects raw JavaScript source..."
    );
}
```

**测试目的：** 验证拒绝 JSON 包装的代码输入

#### 6. `emit_js_repl_exec_end_sends_event`

```rust
#[tokio::test]
async fn emit_js_repl_exec_end_sends_event() {
    let (session, turn, rx) = make_session_and_context_with_rx().await;
    super::emit_js_repl_exec_end(
        session.as_ref(),
        turn.as_ref(),
        "call-1",
        "hello",
        None,
        Duration::from_millis(12),
    )
    .await;

    // 等待并验证事件
    let event = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let event = rx.recv().await.expect("event");
            if let EventMsg::ExecCommandEnd(end) = event.msg {
                break end;
            }
        }
    })
    .await
    .expect("timed out waiting for exec end");

    // 验证事件字段
    assert_eq!(event.call_id, "call-1");
    assert_eq!(event.turn_id, turn.sub_id);
    assert_eq!(event.command, vec!["js_repl".to_string()]);
    assert_eq!(event.cwd, turn.cwd);
    assert_eq!(event.source, ExecCommandSource::Agent);
    assert_eq!(event.stdout, "hello");
    assert_eq!(event.exit_code, 0);
    assert_eq!(event.duration, Duration::from_millis(12));
}
```

**测试目的：** 验证 `emit_js_repl_exec_end` 正确发送 `ExecCommandEnd` 事件

## 关键代码路径与文件引用

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `parse_freeform_args_without_pragma` | `parse_freeform_args` | js_repl.rs:208 |
| `parse_freeform_args_with_pragma` | `parse_freeform_args` | js_repl.rs:208 |
| `parse_freeform_args_rejects_unknown_key` | `parse_freeform_args` | js_repl.rs:208 |
| `parse_freeform_args_rejects_reset_key` | `parse_freeform_args` | js_repl.rs:208 |
| `parse_freeform_args_rejects_json_wrapped_code` | `parse_freeform_args` | js_repl.rs:208 |
| `emit_js_repl_exec_end_sends_event` | `emit_js_repl_exec_end` | js_repl.rs:72 |

## 依赖与外部交互

### 测试依赖

```rust
use std::time::Duration;
use super::parse_freeform_args;
use crate::codex::make_session_and_context_with_rx;  // 测试辅助函数
use crate::protocol::EventMsg;
use crate::protocol::ExecCommandSource;
use pretty_assertions::assert_eq;
```

### 外部依赖

| 模块 | 用途 |
|------|------|
| `make_session_and_context_with_rx` | 创建测试会话和事件接收器 |
| `EventMsg::ExecCommandEnd` | 验证事件类型 |
| `ExecCommandSource::Agent` | 验证事件来源 |

## 风险、边界与改进建议

### 测试覆盖缺口

1. **缺少 Handler 层测试**
   - `JsReplHandler::handle` 完整流程
   - `JsReplResetHandler::handle` 流程
   - 功能开关检查

2. **缺少边界测试**
   - 空代码输入
   - 只有 pragma 无代码
   - Markdown 代码块拒绝

3. **缺少集成测试**
   - 与 `JsReplManager` 集成
   - 嵌套工具调用
   - 图像发射

### 改进建议

1. **添加 Handler 测试**
   ```rust
   #[tokio::test]
   async fn test_js_repl_handler_disabled() {
       // 测试功能禁用场景
   }
   ```

2. **添加边界测试**
   ```rust
   #[test]
   fn parse_freeform_args_rejects_empty_code() {
       let err = parse_freeform_args("").expect_err("expected error");
       assert!(err.to_string().contains("non-empty"));
   }
   
   #[test]
   fn parse_freeform_args_rejects_markdown_fences() {
       let err = parse_freeform_args("```js\nconsole.log('ok');\n```").expect_err("expected error");
       assert!(err.to_string().contains("markdown code fences"));
   }
   ```

3. **添加集成测试**
   ```rust
   #[tokio::test]
   async fn test_js_repl_full_flow() {
       // 使用 Mock JsReplManager 测试完整流程
   }
   ```

4. **测试组织建议**
   - 当前测试文件 90 行，可保持内联
   - 如添加更多集成测试，建议拆分为独立文件
