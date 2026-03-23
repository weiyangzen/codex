# Research: remote_mid_turn_compaction_shapes.snap

## 场景与职责

该快照文件记录了**远程轮中压缩（Remote Mid-turn Compaction）**场景，验证在单轮对话中间触发远程自动压缩时的请求结构和历史布局。

**测试场景**：用户发送消息触发工具调用，工具输出后令牌数超出限制，系统在单轮内执行远程压缩并继续完成该轮。

---

## 功能点目的

1. **远程轮内压缩**：验证远程压缩 API 在轮中场景的工作
2. **工具产物处理**：确保工具调用输出参与压缩
3. **连续性保持**：压缩后同一轮对话继续

---

## 具体技术实现

### 关键流程

```
用户输入 → 工具调用 → 工具输出 → 令牌超限 → 远程自动压缩 → 压缩项注入 → 同轮继续
```

### 数据结构

**远程压缩请求（Remote Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:function_call/test_tool
04:function_call_output:unsupported call: test_tool
```

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:compaction:encrypted=true
```

### 关键观察

1. **压缩请求特点**：
   - 发送到 `/v1/responses/compact`
   - 包含工具调用和输出
   - 不包含摘要提示词（远程压缩不需要）

2. **压缩后布局特点**：
   - 保留原始用户消息
   - 工具产物被压缩为压缩项
   - 标准上下文保留

3. **与本地轮中压缩的区别**：
   - 远程压缩返回 `compaction` 项而非摘要消息
   - 不需要摘要提示词

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_mid_turn_continuation_compaction` (行 2309-2376)
- **快照生成**: 行 2364-2373

### Mock 配置
```rust
let responses_mock = responses::mount_sse_sequence(
    harness.server(),
    vec![
        // 第一轮：工具调用 + 超限
        responses::sse(vec![
            responses::ev_function_call("call-remote-mid-turn", DUMMY_FUNCTION_NAME, "{}"),
            responses::ev_completed_with_tokens("r1", 500),
        ]),
        // 第二轮：完成回复
        responses::sse(vec![
            responses::ev_assistant_message("m2", "REMOTE_MID_TURN_FINAL_REPLY"),
            responses::ev_completed_with_tokens("r2", 80),
        ]),
    ],
).await;

let compact_mock = responses::mount_compact_user_history_with_summary_once(
    harness.server(),
    &summary_with_prefix("REMOTE_MID_TURN_SUMMARY"),
).await;
```

### 关键断言
```rust
assert_eq!(compact_mock.requests().len(), 1);
let requests = responses_mock.requests();
assert_eq!(requests.len(), 2, "expected initial and post-compact requests");
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### API 端点
- `POST /v1/responses` - 正常对话
- `POST /v1/responses/compact` - 远程压缩

### 配置
- `model_auto_compact_token_limit`: 200

---

## 风险、边界与改进建议

### 风险点
1. **网络延迟**：远程压缩增加轮中延迟
2. **压缩失败**：远程压缩失败导致轮次中断
3. **工具链中断**：轮中压缩可能中断工具调用链

### 边界情况
1. **多工具调用**：单轮多个工具调用后的压缩
2. **工具输出过大**：工具输出本身超出上下文窗口
3. **压缩超时**：远程压缩超时处理

### 改进建议
1. **本地备选**：远程压缩失败时回退到本地压缩
2. **异步压缩**：考虑异步压缩减少延迟
3. **工具状态保留**：确保工具调用 ID 和状态在压缩后保留
4. **压缩缓存**：缓存压缩结果

### 相关测试
- `mid_turn_compaction_shapes`: 本地轮中压缩
- `remote_pre_turn_compaction_*`: 远程轮前压缩
