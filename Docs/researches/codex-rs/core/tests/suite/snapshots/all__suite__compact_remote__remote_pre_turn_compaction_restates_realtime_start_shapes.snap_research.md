# Research: remote_pre_turn_compaction_restates_realtime_start_shapes.snap

## 场景与职责

该快照文件记录了**远程轮前压缩后重述实时开始指令（Remote Pre-turn Compaction Restates Realtime Start）**场景，验证当实时对话仍处于活动状态时，轮前压缩后的跟进请求如何重述实时开始指令。

**测试场景**：用户开启实时对话，发送消息，再发送新消息触发轮前压缩（实时仍活动），验证跟进请求重述实时开始指令。

---

## 功能点目的

1. **活动实时状态保持**：压缩后保持实时对话活动状态
2. **指令重述**：压缩清除基线后，重新陈述实时开始指令
3. **无缝继续**：确保压缩后实时对话无缝继续

---

## 具体技术实现

### 关键流程

```
开启实时 → USER_ONE → USER_TWO（触发轮前压缩，实时仍活动）→ 跟进请求（重述实时开始）
```

### 数据结构

**远程压缩请求（Remote Compaction Request）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <realtime_conversation>\nRealtime conversation started.\n\nYou a...
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:message/assistant:REMOTE_FIRST_REPLY
```

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:compaction:encrypted=true
01:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <realtime_conversation>\nRealtime conversation started.\n\nYou a...
02:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
03:message/user:USER_TWO
```

### 关键观察

1. **压缩请求特点**：
   - 包含实时开始指令
   - 包含完整对话历史
   - 实时对话仍处于活动状态

2. **跟进请求特点**：
   - 以压缩项开头
   - **重新陈述实时开始指令**
   - 这是因为实时对话仍活动，需要保持状态

3. **与实时结束场景的区别**：
   - 实时活动：重述 `started` 指令
   - 实时关闭：重述 `ended` 指令

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_pre_turn_compaction_restates_realtime_start` (行 1455-1539)
- **快照生成**: 行 1522-1534

### 测试配置
```rust
let mut builder = remote_realtime_test_codex_builder(&realtime_server).with_config(|config| {
    config.model_auto_compact_token_limit = Some(200);
});
```

### 关键断言
```rust
let post_compact_request = &requests[1];
assert_request_contains_realtime_start(post_compact_request);
```

### 辅助函数
```rust
fn assert_request_contains_realtime_start(request: &responses::ResponsesRequest) {
    let body = request.body_json().to_string();
    assert!(body.contains("<realtime_conversation>"));
    assert!(!body.contains("Reason: inactive"));
}
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **WebSocket Server**: 实时对话后端

### Mock 配置
```rust
let responses_mock = responses::mount_sse_sequence(
    &server,
    vec![
        responses::sse(vec![
            responses::ev_assistant_message("m1", "REMOTE_FIRST_REPLY"),
            responses::ev_completed_with_tokens("r1", 500),
        ]),
        responses::sse(vec![
            responses::ev_assistant_message("m2", "REMOTE_SECOND_REPLY"),
            responses::ev_completed_with_tokens("r2", 80),
        ]),
    ],
).await;

let compact_mock = responses::mount_compact_json_once(
    &server,
    serde_json::json!({
        "output": compacted_summary_only_output("REMOTE_PRETURN_REALTIME_STILL_ACTIVE_SUMMARY")
    }),
).await;
```

---

## 风险、边界与改进建议

### 风险点
1. **实时连接中断**：压缩期间实时 WebSocket 连接可能中断
2. **状态不一致**：压缩后实时状态与实际 WebSocket 状态可能不一致
3. **指令重复**：频繁压缩导致实时开始指令重复

### 边界情况
1. **压缩时实时关闭**：压缩过程中实时对话被关闭
2. **压缩失败**：远程压缩失败时的实时状态
3. **长时间压缩**：压缩耗时较长时的实时保持

### 改进建议
1. **实时状态同步**：压缩前后同步实时对话状态
2. **连接保持**：压缩期间保持 WebSocket 连接
3. **状态校验**：压缩后校验实时状态一致性
4. **用户提示**：压缩后提示用户实时对话仍活动

### 相关测试
- `remote_pre_turn_compaction_restates_realtime_end_shapes`: 实时结束场景
- `remote_manual_compact_restates_realtime_start_shapes`: 手动压缩场景
