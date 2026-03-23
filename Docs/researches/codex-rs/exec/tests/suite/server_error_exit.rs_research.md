# server_error_exit.rs 深度研究文档

## 场景与职责

`server_error_exit.rs` 是 `codex-exec` CLI 工具的错误处理测试模块，专门验证当服务器报告错误时，CLI 能够正确返回非零退出码。这是自动化和 CI/CD 集成的关键功能。

**核心场景**：
- API 返回错误（如速率限制、认证失败）
- 自动化脚本需要检测执行失败
- 与 shell 管道和条件执行集成

## 功能点目的

### 单测试函数 (`exits_non_zero_when_server_reports_error`)

验证当服务器返回 `response.failed` 事件时：
1. `codex-exec` 返回退出码 1（非零）
2. 自动化工具能够通过 `$?` 检测失败
3. 错误信息被正确处理

## 具体技术实现

### SSE 错误事件格式

**`response.failed` 事件**:
```json
{
    "type": "response.failed",
    "response": {
        "id": "resp_err_1",
        "error": {
            "code": "rate_limit_exceeded",
            "message": "synthetic server error"
        }
    }
}
```

### 测试流程

```
创建 TestCodexExec 环境
  ↓
启动 Mock SSE 服务器
  ↓
挂载错误响应
  ├─ 事件类型: response.failed
  ├─ 错误码: rate_limit_exceeded
  └─ 错误消息: synthetic server error
  ↓
执行 codex-exec 命令
  ├─ --skip-git-repo-check
  ├─ "tell me something"
  └─ --experimental-json
  ↓
验证退出码为 1（非零）
```

### 关键代码

**Mock 错误响应**:
```rust
let body = responses::sse(vec![serde_json::json!({
    "type": "response.failed",
    "response": {
        "id": "resp_err_1",
        "error": {"code": "rate_limit_exceeded", "message": "synthetic server error"}
    }
})]);
responses::mount_sse_once(&server, body).await;
```

**退出码验证**:
```rust
test.cmd_with_server(&server)
    .arg("--skip-git-repo-check")
    .arg("tell me something")
    .arg("--experimental-json")
    .assert()
    .code(1);  // 验证退出码为 1
```

## 关键代码路径与文件引用

### 被测试代码路径

1. **错误检测**: `codex-rs/exec/src/lib.rs:779-822`
   ```rust
   InProcessServerEvent::LegacyNotification(notification) => {
       let decoded = decode_legacy_notification(notification)?;
       if matches!(event.msg, EventMsg::Error(_)) {
           error_seen = true;  // 标记错误
       }
       match &event.msg {
           EventMsg::TurnComplete(payload) => { ... }
           EventMsg::TurnAborted(payload) => { ... }
           ...
       }
   }
   ```

2. **错误退出**: `codex-rs/exec/src/lib.rs:891-899`
   ```rust
   if let Err(err) = client.shutdown().await {
       warn!("in-process app-server shutdown failed: {err}");
   }
   event_processor.print_final_output();
   if error_seen {
       std::process::exit(1);  // 错误时退出码 1
   }
   ```

3. **事件解码**: `codex-rs/exec/src/lib.rs:1086-1129`
   ```rust
   fn decode_legacy_notification(notification: JSONRPCNotification) 
       -> Result<DecodedLegacyNotification, String> {
       // 解析 JSONRPC 通知为内部事件格式
   }
   ```

### 错误事件类型

**`codex-rs/protocol/src/protocol.rs`**:
```rust
pub enum EventMsg {
    Error(ErrorEvent),
    TurnComplete(TurnCompleteEvent),
    TurnAborted(TurnAbortedEvent),
    // ...
}

pub struct ErrorEvent {
    pub message: String,
    pub codex_error_info: Option<CodexErrorInfo>,
}
```

### 测试依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `test_codex_exec` | `codex-rs/core/tests/common/test_codex_exec.rs` | 测试环境 |
| `responses` | `codex-rs/core/tests/common/responses.rs` | Mock 工具 |

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `wiremock` | HTTP Mock 服务器 |
| `assert_cmd` | CLI 测试断言（包括 `.code(1)`） |
| `tokio` | 异步运行时 |

### 环境变量

- `CODEX_API_KEY` - 自动设置为 "dummy"
- `CODEX_HOME` - 临时目录

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

### 退出码约定

| 退出码 | 含义 |
|--------|------|
| 0 | 成功 |
| 1 | 服务器错误或执行失败 |
| 其他 | 程序内部错误 |

## 风险、边界与改进建议

### 当前风险

1. **单一错误类型**: 仅测试 `response.failed`，未覆盖其他错误路径
2. **错误信息未验证**: 未验证错误信息是否正确输出到 stderr
3. **部分失败**: 未测试部分成功后的失败场景

### 边界情况

1. **多种错误码**: 不同错误码（rate_limit、auth_failed 等）的处理
2. **重试后失败**: 重试机制耗尽后的退出
3. **连接错误**: 网络连接失败 vs API 错误返回
4. **超时**: 请求超时的退出码
5. **信号中断**: 被信号中断的退出码

### 改进建议

1. **增加错误类型覆盖**:
   ```rust
   #[tokio::test]
   async fn exits_non_zero_on_auth_failure() { ... }
   
   #[tokio::test]
   async fn exits_non_zero_on_rate_limit() { ... }
   
   #[tokio::test]
   async fn exits_non_zero_on_connection_error() { ... }
   ```

2. **验证错误输出**:
   ```rust
   .assert()
   .code(1)
   .stderr(contains("synthetic server error"));
   ```

3. **区分退出码**: 使用不同退出码区分错误类型
   ```rust
   const EXIT_SERVER_ERROR: i32 = 1;
   const EXIT_NETWORK_ERROR: i32 = 2;
   const EXIT_AUTH_ERROR: i32 = 3;
   ```

4. **测试重试行为**: 验证重试次数和最终退出

5. **与 shell 集成测试**: 测试在管道和条件语句中的行为
   ```bash
   codex-exec "prompt" || echo "Failed"
   codex-exec "prompt" && echo "Success"
   ```

### 相关文件

- `codex-rs/exec/src/lib.rs` - 主逻辑和错误处理
- `codex-rs/exec/src/event_processor.rs` - 事件处理
- `codex-rs/protocol/src/protocol.rs` - 错误事件定义

### 错误处理流程

```
┌─────────────────┐
│   SSE 事件流    │
│ response.failed │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ decode_legacy   │
│ _notification   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  EventMsg::Error│
│  error_seen =   │
│      true       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   事件循环结束   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ if error_seen   │
│   exit(1)       │
└─────────────────┘
```
