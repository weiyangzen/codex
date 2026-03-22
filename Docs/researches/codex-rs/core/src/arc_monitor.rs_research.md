# arc_monitor.rs 深度研究文档

## 场景与职责

`arc_monitor.rs` 是 Codex CLI 的**安全监控与风险评估模块**（ARC = Agent Risk Classification），负责在工具调用执行前进行安全风险评估。该模块将当前会话上下文发送到远程安全服务，根据返回的风险评分决定是继续执行、询问用户还是取消操作。

### 核心职责
1. **风险评估**：将工具调用动作发送到 ARC 服务进行评估
2. **决策执行**：根据评估结果决定后续流程
3. **上下文构建**：从会话历史中提取相关消息构建评估上下文
4. **降级策略**：服务不可用时优雅降级（默认允许执行）

---

## 功能点目的

### 1. 评估结果类型

```rust
pub(crate) enum ArcMonitorOutcome {
    Ok,                           // 风险评估通过，继续执行
    SteerModel(String),          // 取消工具调用，向模型返回理由
    AskUser(String),             // 暂停执行，向用户请求确认
}
```

### 2. 风险等级

```rust
enum ArcMonitorRiskLevel {
    Low,      // 低风险
    Medium,   // 中等风险
    High,     // 高风险
    Critical, // 严重风险
}
```

### 3. 评估结果处理

| ARC 结果 | 短理由非空 | 详细理由非空 | 最终行为 |
|---------|-----------|-------------|---------|
| `Ok` | - | - | `ArcMonitorOutcome::Ok` |
| `AskUser` | ✓ | - | `AskUser(short_reason)` |
| `AskUser` | - | ✓ | `AskUser(rationale)` |
| `AskUser` | - | - | `AskUser(默认消息)` |
| `SteerModel` | - | ✓ | `SteerModel(rationale)` |
| `SteerModel` | ✓ | - | `SteerModel(short_reason)` |
| `SteerModel` | - | - | `SteerModel(默认消息)` |

### 4. 环境变量配置

| 环境变量 | 用途 | 默认值 |
|---------|------|-------|
| `CODEX_ARC_MONITOR_ENDPOINT_OVERRIDE` | 自定义 ARC 服务端点 | `{chatgpt_base_url}/codex/safety/arc` |
| `CODEX_ARC_MONITOR_TOKEN` | 自定义认证令牌 | 使用当前用户 auth token |

---

## 具体技术实现

### 核心函数：monitor_action

```rust
pub(crate) async fn monitor_action(
    sess: &Session,
    turn_context: &TurnContext,
    action: serde_json::Value,
) -> ArcMonitorOutcome {
    // 1. 获取认证令牌（优先环境变量，否则使用用户 token）
    let token = if let Some(token) = read_non_empty_env_var(CODEX_ARC_MONITOR_TOKEN) {
        token
    } else {
        // 从 auth_manager 获取
        let Some(auth) = auth else { return ArcMonitorOutcome::Ok; };
        match auth.get_token() { ... }
    };

    // 2. 确定服务端点
    let url = read_non_empty_env_var(CODEX_ARC_MONITOR_ENDPOINT_OVERRIDE)
        .unwrap_or_else(|| format!("{}/codex/safety/arc", base_url));

    // 3. 构建请求体
    let body = build_arc_monitor_request(sess, turn_context, action).await;

    // 4. 发送请求（30秒超时）
    let response = client.post(&url).timeout(ARC_MONITOR_TIMEOUT).json(&body).send().await;

    // 5. 处理响应（任何错误都降级为 Ok）
    match response {
        Ok(response) if response.status().is_success() => {
            match response.json::<ArcMonitorResult>().await {
                Ok(result) => map_result_to_outcome(result),
                Err(_) => ArcMonitorOutcome::Ok,  // 解析失败，降级
            }
        }
        Ok(response) => { /* 记录警告，降级 */ ArcMonitorOutcome::Ok }
        Err(err) => { /* 记录警告，降级 */ ArcMonitorOutcome::Ok }
    }
}
```

### 请求体构建

```rust
#[derive(Debug, Serialize, PartialEq)]
struct ArcMonitorRequest {
    metadata: ArcMonitorMetadata,
    messages: Option<Vec<ArcMonitorChatMessage>>,
    input: Option<Vec<ResponseItem>>,  // 当前未使用
    policies: Option<ArcMonitorPolicies>,
    action: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Serialize, PartialEq)]
struct ArcMonitorMetadata {
    codex_thread_id: String,
    codex_turn_id: String,
    conversation_id: Option<String>,
    protection_client_callsite: Option<String>,
}
```

### 历史消息过滤逻辑

```rust
fn build_arc_monitor_messages(items: &[ResponseItem]) -> Vec<ArcMonitorChatMessage> {
    // 找到最后一个工具调用和加密推理的索引
    let last_tool_call_index = items.iter().enumerate().rev()
        .find(|(_, item)| matches!(item, LocalShellCall | FunctionCall | CustomToolCall | WebSearchCall))
        .map(|(index, _)| index);
    
    let last_encrypted_reasoning_index = items.iter().enumerate().rev()
        .find(|(_, item)| matches!(item, Reasoning { encrypted_content: Some(_), .. }))
        .map(|(index, _)| index);

    items.iter().enumerate()
        .filter_map(|(index, item)| build_arc_monitor_message_item(
            item, index, last_tool_call_index, last_encrypted_reasoning_index
        ))
        .collect()
}
```

### 消息类型映射

| ResponseItem 类型 | 条件 | 映射为 | 内容 |
|------------------|------|-------|------|
| `Message { role: "user", ... }` | 非上下文消息 | user | `{"type": "input_text", "text": ...}` |
| `Message { role: "assistant", phase: FinalAnswer }` | - | assistant | `{"type": "output_text", "text": ...}` |
| `Reasoning { encrypted_content: Some(_) }` | 最后一个加密推理 | assistant | `{"type": "encrypted_reasoning", ...}` |
| `LocalShellCall` | 最后一个工具调用 | assistant | `{"type": "tool_call", "tool_name": "shell", ...}` |
| `FunctionCall` | 最后一个工具调用 | assistant | `{"type": "tool_call", "tool_name": name, ...}` |
| `CustomToolCall` | 最后一个工具调用 | assistant | `{"type": "tool_call", "tool_name": name, ...}` |
| `WebSearchCall` | 最后一个工具调用 | assistant | `{"type": "tool_call", "tool_name": "web_search", ...}` |
| 其他 | - | 过滤掉 | - |

### 响应解析

```rust
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]  // 拒绝未知字段，严格模式
struct ArcMonitorResult {
    outcome: ArcMonitorResultOutcome,
    short_reason: String,
    rationale: String,
    risk_score: u8,           // 0-255
    risk_level: ArcMonitorRiskLevel,
    evidence: Vec<ArcMonitorEvidence>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ArcMonitorEvidence {
    message: String,
    why: String,
}
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 说明 |
|-----|------|
| `codex-rs/core/src/arc_monitor.rs` | 主实现文件（429行） |
| `codex-rs/core/src/arc_monitor_tests.rs` | 单元测试（435行） |

### 调用方（上游）
- `codex-rs/core/src/codex.rs` - 主会话循环
  - 在工具调用前调用 `monitor_action()`
- `codex-rs/core/src/tools/` - 工具执行模块

### 被调用方（下游）
- `codex-rs/core/src/codex.rs`
  - `Session::clone_history()` - 获取会话历史
  - `TurnContext` - 获取当前 turn 上下文
- `codex-rs/core/src/compact.rs`
  - `content_items_to_text()` - 内容项转文本
- `codex-rs/core/src/event_mapping.rs`
  - `is_contextual_user_message_content()` - 识别上下文消息
- `codex-rs/core/src/default_client.rs`
  - `build_reqwest_client()` - 创建 HTTP 客户端

### 外部协议类型
- `codex_protocol::models::ResponseItem` - 响应项类型
- `codex_protocol::models::ContentItem` - 内容项类型
- `codex_protocol::models::MessagePhase` - 消息阶段

---

## 依赖与外部交互

### HTTP 请求格式
```
POST {endpoint}/codex/safety/arc
Headers:
  - Authorization: Bearer {token}
  - chatgpt-account-id: {account_id} (可选)
  - Content-Type: application/json
Body:
  {
    "metadata": {
      "codex_thread_id": "...",
      "codex_turn_id": "...",
      "conversation_id": "..."
    },
    "messages": [...],
    "policies": { "user": null, "developer": null },
    "action": { "tool": "...", ... }
  }
```

### 响应格式
```json
{
  "outcome": "ok" | "ask-user" | "steer-model",
  "short_reason": "...",
  "rationale": "...",
  "risk_score": 42,
  "risk_level": "low" | "medium" | "high" | "critical",
  "evidence": [
    { "message": "...", "why": "..." }
  ]
}
```

### 降级策略
任何以下情况都导致 `ArcMonitorOutcome::Ok`：
- 环境变量 token 未设置且用户未认证
- 认证令牌获取失败
- action 不是 JSON 对象
- HTTP 请求失败
- 非 2xx 响应
- 响应解析失败
- 响应包含未知字段（`deny_unknown_fields`）

---

## 风险、边界与改进建议

### 已知风险

1. **降级过于激进**
   - 几乎所有错误都降级为 `Ok`
   - 可能导致高风险操作被静默允许
   - **建议**：区分可恢复错误和严重错误，后者应阻止执行

2. **超时设置**
   - 固定 30 秒超时可能过长或过短
   - **建议**：根据网络环境动态调整或配置化

3. **历史消息截断**
   - 仅保留最后一个工具调用和加密推理
   - 可能丢失重要的上下文信息
   - **建议**：添加配置控制保留的消息数量

4. **严格字段验证**
   - `deny_unknown_fields` 导致向前不兼容
   - 服务端添加新字段会导致解析失败
   - **建议**：移除 `deny_unknown_fields` 或使用 `#[serde(default)]`

5. **环境变量竞争**
   - 使用 `std::env::var` 而非配置系统
   - 可能导致测试间相互影响
   - **建议**：通过 `TurnContext` 传递配置

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 空会话历史 | 添加默认消息："No prior conversation history..." |
| 无工具调用历史 | `last_tool_call_index = None`，不映射任何工具调用 |
| 无加密推理 | `last_encrypted_reasoning_index = None` |
| action 非对象 | 记录警告，降级为 `Ok` |
| 环境变量非 Unicode | 记录警告，忽略该变量 |
| 响应包含额外字段 | 解析失败，降级为 `Ok` |

### 改进建议

1. **分级降级策略**
   ```rust
   enum ArcMonitorError {
       NetworkError,      // 网络问题 → 重试或询问用户
       AuthError,         // 认证问题 → 阻止执行
       ParseError,        // 解析问题 → 记录并继续
       ServerError,       // 服务端错误 → 询问用户
   }
   ```

2. **可配置超时**
   ```rust
   const ARC_MONITOR_TIMEOUT: Duration = 
       match read_non_empty_env_var("CODEX_ARC_MONITOR_TIMEOUT_SECS") {
           Some(secs) => Duration::from_secs(secs.parse().unwrap_or(30)),
           None => Duration::from_secs(30),
       };
   ```

3. **增强日志**
   ```rust
   tracing::info!(
       risk_score = result.risk_score,
       risk_level = ?result.risk_level,
       outcome = ?result.outcome,
       "ARC evaluation completed"
   );
   ```

4. **响应兼容性**
   ```rust
   #[derive(Debug, Deserialize)]
   struct ArcMonitorResult {
       // 移除 deny_unknown_fields 或添加默认处理
       #[serde(default)]
       new_field: Option<String>,
   }
   ```

5. **测试增强**
   - 添加超时场景测试
   - 添加网络失败重试测试
   - 添加大历史消息性能测试
