# Research: remote_manual_compact_with_history_shapes.snap

## 场景与职责

该快照文件记录了**远程手动压缩带历史（Remote Manual Compact with History）**场景，验证远程压缩 API 的基本工作流程和请求/响应结构。

**测试场景**：用户发送消息，收到回复，执行手动远程压缩，然后发送新消息。

---

## 功能点目的

1. **远程压缩 API 验证**：验证 `/v1/responses/compact` 端点的基本功能
2. **历史替换**：验证远程压缩返回的压缩项替换原始历史
3. **会话一致性**：验证压缩后会话 ID 和认证信息保持一致

---

## 具体技术实现

### 关键流程

```
USER_ONE → 助手回复 → 手动远程压缩 → 压缩项替换历史 → USER_TWO
```

### 数据结构

**远程压缩请求（Remote Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:hello remote compact
03:message/assistant:FIRST_REMOTE_REPLY
```

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:compaction:encrypted=true
01:message/developer:<PERMISSIONS_INSTRUCTIONS>
02:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
03:message/user:after compact
```

### 关键观察

1. **压缩请求特点**：
   - 发送到 `/v1/responses/compact` 端点
   - 包含完整对话历史
   - 包含标准头部（authorization, session_id, chatgpt-account-id）

2. **压缩响应**：
   - 返回 `ResponseItem::Compaction` 项
   - `encrypted_content` 包含加密的历史摘要

3. **压缩后布局特点**：
   - 以 `compaction:encrypted=true` 项开头
   - 不包含原始用户消息和助手回复
   - 新用户消息追加到末尾

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `remote_compact_replaces_history_for_followups` (行 196-339)
- **快照生成**: 行 327-336

### Mock 配置
```rust
// 正常对话响应
let responses_mock = responses::mount_sse_sequence(
    harness.server(),
    vec![
        responses::sse(vec![
            responses::ev_assistant_message("m1", "FIRST_REMOTE_REPLY"),
            responses::ev_completed("resp-1"),
        ]),
        responses::sse(vec![
            responses::ev_assistant_message("m2", "AFTER_COMPACT_REPLY"),
            responses::ev_completed("resp-2"),
        ]),
    ],
).await;

// 远程压缩响应
let compacted_history = vec![ResponseItem::Compaction {
    encrypted_content: "ENCRYPTED_COMPACTION_SUMMARY".to_string(),
}];
let compact_mock = responses::mount_compact_json_once(
    harness.server(),
    serde_json::json!({ "output": compacted_history }),
).await;
```

### 关键断言
```rust
// 验证压缩请求路径
let compact_request = compact_mock.single_request();
assert_eq!(compact_request.path(), "/v1/responses/compact");

// 验证头部
assert_eq!(
    compact_request.header("chatgpt-account-id").as_deref(),
    Some("account_id")
);
assert_eq!(
    compact_request.header("authorization").as_deref(),
    Some("Bearer Access Token")
);
assert_eq!(
    compact_request.header("session_id").as_deref(),
    Some(session_id.as_str())
);

// 验证跟进请求包含压缩项
let follow_up_body = follow_up_request.body_json().to_string();
assert!(follow_up_body.contains("\"type\":\"compaction\""));
assert!(follow_up_body.contains("ENCRYPTED_COMPACTION_SUMMARY"));
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **ChatGPT Auth**: 使用 `CodexAuth::create_dummy_chatgpt_auth_for_testing()`

### API 端点
- `POST /v1/responses` - 正常对话
- `POST /v1/responses/compact` - 远程压缩

### 请求头部
- `authorization`: Bearer 令牌
- `session_id`: 会话标识
- `chatgpt-account-id`: 账户标识

---

## 风险、边界与改进建议

### 风险点
1. **API 兼容性**：远程压缩 API 格式变更可能导致不兼容
2. **加密内容**：压缩项内容加密，客户端无法验证
3. **网络依赖**：远程压缩依赖网络，可能失败

### 边界情况
1. **空历史压缩**：无历史时的远程压缩行为
2. **压缩失败**：远程压缩失败时的回退
3. **大历史压缩**：超大历史的压缩性能

### 改进建议
1. **本地压缩备选**：远程压缩失败时回退到本地压缩
2. **压缩验证**：提供压缩内容验证机制
3. **压缩缓存**：缓存压缩结果避免重复请求
4. **压缩进度**：大历史压缩时显示进度

### 相关测试
- `remote_manual_compact_without_prev_user_shapes`: 无历史压缩
- `remote_compact_runs_automatically`: 自动远程压缩
