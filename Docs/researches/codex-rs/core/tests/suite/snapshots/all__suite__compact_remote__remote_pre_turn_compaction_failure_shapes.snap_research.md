# Research: remote_pre_turn_compaction_failure_shapes.snap

## 场景与职责

该快照文件记录了**远程轮前压缩解析失败（Remote Pre-turn Compaction Parse Failure）**场景，验证当远程压缩返回无法解析的响应时的错误处理。

**测试场景**：用户对话后触发自动压缩，远程压缩端点返回无效格式的响应，系统正确处理错误。

---

## 功能点目的

1. **解析错误处理**：正确处理远程压缩响应解析失败
2. **轮次停止**：解析失败时停止当前轮次
3. **错误信息**：提供清晰的错误提示

---

## 具体技术实现

### 关键流程

```
对话 → 触发自动压缩 → 远程压缩返回无效响应 → 解析失败 → 轮次停止
```

### 数据结构

**远程压缩请求（Remote Compaction Request - Incoming User Excluded）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:turn that exceeds token threshold
03:message/assistant:initial turn complete
```

### 关键观察

1. **请求结构**：
   - 包含开发者指令
   - 环境上下文
   - 先前对话历史
   - 不包含新用户消息

2. **无效响应**：
   - 返回字符串而非预期的数组格式
   - 示例：`{ "output": "invalid compact payload shape" }`

3. **错误处理**：
   - 解析失败
   - 轮次停止
   - 不发送跟进请求

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `auto_remote_compact_failure_stops_agent_loop` (行 657-748)
- **快照生成**: 行 736-745

### Mock 配置
```rust
let first_compact_mock = responses::mount_compact_json_once(
    harness.server(),
    serde_json::json!({ "output": "invalid compact payload shape" }),
).await;

let post_compact_turn_mock = mount_sse_once(
    harness.server(),
    sse(vec![
        responses::ev_assistant_message("post-compact-assistant", "should not run"),
        responses::ev_completed("post-compact-response"),
    ]),
).await;
```

### 关键断言
```rust
let error_message = wait_for_event_match(&codex, |event| match event {
    EventMsg::Error(err) => Some(err.message.clone()),
    _ => None,
}).await;

assert!(error_message.contains("Error running remote compact task"));
assert_eq!(first_compact_mock.requests().len(), 1);
assert!(post_compact_turn_mock.requests().is_empty());
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### 无效响应示例
```json
{
  "output": "invalid compact payload shape"
}
```

### 期望响应格式
```json
{
  "output": [
    {
      "type": "compaction",
      "encrypted_content": "..."
    }
  ]
}
```

---

## 风险、边界与改进建议

### 风险点
1. **API 变更**：远程压缩 API 格式变更导致解析失败
2. **版本不兼容**：客户端与服务器版本不兼容
3. **数据丢失**：新用户消息因解析失败而丢失

### 边界情况
1. **部分有效响应**：响应部分有效时的处理
2. **空响应**：空响应的处理
3. **网络错误**：网络错误与解析错误的区分

### 改进建议
1. **版本协商**：客户端与服务器协商 API 版本
2. **向后兼容**：支持多种响应格式
3. **详细错误**：提供更详细的解析错误信息
4. **重试机制**：解析失败时尝试重试或回退
5. **日志记录**：记录解析失败的响应内容便于调试

### 相关测试
- `remote_pre_turn_compaction_context_window_exceeded_shapes`: 上下文溢出
- `remote_manual_compact_failure_emits_task_error_event`: 手动压缩失败
