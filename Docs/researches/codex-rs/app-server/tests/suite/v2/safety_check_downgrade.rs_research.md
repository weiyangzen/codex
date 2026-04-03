# safety_check_downgrade.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**安全检查降级通知** (`model/rerouted`)。当请求的模型因安全风险（如高风险网络活动）被服务器降级到更安全的模型时，系统会发出通知告知客户端这一变更。

测试场景覆盖：
1. **OpenAI-Model 头不匹配** - 当响应头中的模型与请求模型不一致时触发降级通知
2. **响应体模型字段不匹配** - 当响应体中的模型字段与请求模型不一致时触发降级通知
3. **降级原因验证** - 验证降级原因正确标识为 `HighRiskCyberActivity`

## 功能点目的

### 1. 模型降级机制
出于安全考虑，当用户请求高风险模型（如 `gpt-5.1-codex-max`）执行可能存在风险的查询时，服务器可能自动降级到更安全的模型（如 `gpt-5.2-codex`）。这种降级需要通知客户端，以便：
- UI 显示模型变更警告
- 客户端了解实际使用的模型
- 用户知晓安全限制已生效

### 2. 降级检测方式
| 检测方式 | 说明 |
|---------|------|
| HTTP 头 `OpenAI-Model` | 检查响应头中的模型标识 |
| 响应体 `response.headers.OpenAI-Model` | 检查 SSE 事件中的模型字段 |

### 3. 降级数据结构
- **From Model**: 用户请求的原始模型
- **To Model**: 实际使用的降级后模型
- **Reason**: 降级原因（`HighRiskCyberActivity`）

### 4. 警告项过滤
测试验证了降级通知不会生成传统的警告用户消息项，而是通过专门的 `model/rerouted` 通知通道传达。

## 具体技术实现

### 关键流程

```
测试用例: openai_model_header_mismatch_emits_model_rerouted_notification_v2
1. 创建 mock Responses API 服务器
2. 配置响应包含不同的 OpenAI-Model 头
   - 请求模型: gpt-5.1-codex-max
   - 响应头模型: gpt-5.2-codex
3. 初始化 MCP 连接
4. 启动线程，指定高风险模型
5. 开始回合，触发安全检查
6. 收集回合通知
7. 验证收到 model/rerouted 通知
8. 验证没有生成警告用户消息项

测试用例: response_model_field_mismatch_emits_model_rerouted_notification_v2_when_header_matches_requested
1-4. 同上
5. 配置 SSE 响应体包含不同的模型字段
   - 响应头: gpt-5.1-codex-max (匹配请求)
   - 响应体: gpt-5.2-codex (不匹配)
6-8. 同上
```

### 核心数据结构

```rust
// 降级通知
ModelReroutedNotification {
    thread_id: String,
    turn_id: String,
    from_model: String,      // "gpt-5.1-codex-max"
    to_model: String,        // "gpt-5.2-codex"
    reason: ModelRerouteReason::HighRiskCyberActivity,
}

// 降级原因枚举
enum ModelRerouteReason {
    HighRiskCyberActivity,
}
```

### 响应构造示例

```rust
// 测试 1: 头不匹配
let response = responses::sse_response(body)
    .insert_header("OpenAI-Model", SERVER_MODEL);  // gpt-5.2-codex

// 测试 2: 体字段不匹配  
let body = responses::sse(vec![
    serde_json::json!({
        "type": "response.created",
        "response": {
            "id": "resp-1",
            "headers": {
                "OpenAI-Model": SERVER_MODEL  // gpt-5.2-codex
            }
        }
    }),
    responses::ev_assistant_message("msg-1", "Done"),
    responses::ev_completed("resp-1"),
]);
let response = responses::sse_response(body)
    .insert_header("OpenAI-Model", REQUESTED_MODEL);  // gpt-5.1-codex-max
```

### 通知收集逻辑

```rust
async fn collect_turn_notifications_and_validate_no_warning_item(
    mcp: &mut McpProcess,
) -> Result<ModelReroutedNotification> {
    loop {
        let message = timeout(DEFAULT_READ_TIMEOUT, mcp.read_next_message()).await??;
        match notification.method.as_str() {
            "model/rerouted" => {
                // 解析并保存降级通知
                let payload: ModelReroutedNotification = serde_json::from_value(params)?;
                rerouted = Some(payload);
            }
            "item/started" | "item/completed" => {
                // 验证没有警告用户消息项
                assert!(!is_warning_user_message_item(&payload.item));
            }
            "turn/completed" => {
                return rerouted.ok_or_else(|| ...);
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/safety_check_downgrade.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `read_next_message()` - 读取下一条消息

- `codex-rs/core_test_support/src/responses.rs`
  - `start_mock_server()` - 启动 Mock 服务器
  - `sse_response()` - SSE 响应构造
  - `mount_response_once()` - 单次响应挂载

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ModelRerouted => "model/rerouted"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ModelReroutedNotification`
  - `ModelRerouteReason` (HighRiskCyberActivity)

### 核心实现
- `codex-rs/core/src/safety/` - 安全检查模块
- `codex-rs/app-server/src/bespoke_event_handling.rs` - 自定义事件处理
- `codex-rs/app-server/src/codex_message_processor.rs` - 消息处理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `core_test_support::responses` | Mock 服务器和响应构造 |
| `core_test_support::skip_if_no_network` | 网络检查 |
| `tokio::time::timeout` | 异步超时控制 |
| `pretty_assertions::assert_eq` | 断言增强 |

### 网络检查
```rust
#[tokio::test]
async fn openai_model_header_mismatch_emits_model_rerouted_notification_v2() -> Result<()> {
    skip_if_no_network!(Ok(()));  // 需要网络连接
    ...
}
```

### 配置要求
```toml
model = "gpt-5.1-codex-max"  # 高风险模型触发降级

[features]
remote_models = false
personality = true
```

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**
   - 测试需要实际网络连接
   - 在无网络 CI 中被跳过
   - 建议: 提供离线 Mock 模式

2. **模型名称硬编码**
   - 使用特定模型名称 (`gpt-5.1-codex-max`, `gpt-5.2-codex`)
   - 模型名称变更会导致测试失败
   - 建议: 使用配置或常量定义

3. **降级原因单一**
   - 仅测试了 `HighRiskCyberActivity` 原因
   - 可能存在其他降级原因未覆盖
   - 建议: 扩展原因覆盖

### 边界情况

1. **多次降级**
   - 未测试一次回合中多次模型变更
   - 建议: 添加多次降级测试

2. **降级后恢复**
   - 未测试降级后恢复正常模型的场景
   - 建议: 添加恢复测试

3. **降级与错误组合**
   - 未测试降级同时发生其他错误的情况
   - 建议: 添加组合场景测试

4. **空降级通知**
   - 未测试降级通知字段缺失的情况
   - 建议: 添加健壮性测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn multiple_model_reroutes_in_single_turn()  // 多次降级
   - async fn model_reroute_with_error()  // 降级+错误
   - async fn model_reroute_recovery()  // 降级恢复
   - async fn model_reroute_other_reasons()  // 其他原因
   ```

2. **离线测试模式**
   - 允许在无网络环境下运行
   - 使用本地 Mock 完全模拟响应

3. **配置化模型名称**
   ```rust
   const REQUESTED_MODEL: &str = env!("TEST_HIGH_RISK_MODEL", "gpt-5.1-codex-max");
   const SERVER_MODEL: &str = env!("TEST_SAFE_MODEL", "gpt-5.2-codex");
   ```

4. **性能测试**
   - 测试降级检测的延迟
   - 验证降级不影响正常响应流

### 相关测试文件
- `codex-rs/core/tests/suite/safety.rs` - 核心安全检查测试
- `codex-rs/app-server/tests/suite/v2/turn_start.rs` - 回合启动测试
