# Research: remote_pre_turn_compaction_restates_realtime_end_shapes.snap

## 场景与职责

该快照文件记录了**远程轮前压缩后重述实时结束指令（Remote Pre-turn Compaction Restates Realtime End）**场景，验证当实时对话在轮次之间关闭后，轮前压缩后的跟进请求如何重述实时结束指令。

**测试场景**：用户开启实时对话，发送消息，关闭实时对话，发送新消息触发轮前压缩，验证跟进请求重述实时结束指令。

---

## 功能点目的

1. **实时状态恢复**：压缩后从上一轮设置恢复实时结束指令
2. **基线清除处理**：压缩清除基线后正确重建指令
3. **轮次间状态保持**：确保轮次之间实时状态正确传递

---

## 具体技术实现

### 关键流程

```
开启实时 → USER_ONE → 关闭实时 → USER_TWO → 轮前压缩 → 跟进请求（重述实时结束）
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
    [02] <realtime_conversation>\nRealtime conversation ended.\n\nSubsequ...
02:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
03:message/user:USER_TWO
```

### 关键观察

1. **压缩请求特点**：
   - 包含实时开始指令（历史遗留）
   - 包含完整对话历史

2. **跟进请求特点**：
   - 以压缩项开头
   - 包含实时结束指令（从上一轮设置重建）
   - 即使压缩清除了基线，仍能恢复指令

3. **指令重建机制**：
   - 从 `previous-turn settings` 重建
   - 不依赖压缩响应内容

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_pre_turn_compaction_restates_realtime_end` (行 1588-1673)
- **快照生成**: 行 1657-1669

### 关键断言
```rust
let compact_request = compact_mock.single_request();
let post_compact_request = &requests[1];
assert_request_contains_realtime_end(post_compact_request);
```

### 辅助函数
```rust
fn assert_request_contains_realtime_end(request: &responses::ResponsesRequest) {
    let body = request.body_json().to_string();
    assert!(body.contains("<realtime_conversation>"));
    assert!(body.contains("Reason: inactive"));
}
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **WebSocket Server**: 实时对话后端

### 操作序列
```rust
// 开启实时对话
start_realtime_conversation(test.codex.as_ref()).await?;

// 第一轮
test.codex.submit(Op::UserInput { text: "USER_ONE" }).await?;
wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;

// 关闭实时对话
close_realtime_conversation(test.codex.as_ref()).await?;

// 第二轮（触发轮前压缩）
test.codex.submit(Op::UserInput { text: "USER_TWO" }).await?;
wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
```

---

## 风险、边界与改进建议

### 风险点
1. **状态重建失败**：若上一轮设置丢失，无法正确重述指令
2. **压缩与状态冲突**：远程压缩可能不包含实时状态信息
3. **指令重复**：频繁压缩导致指令重复

### 边界情况
1. **实时未关闭**：若实时对话未关闭就压缩
2. **多次压缩**：连续多次压缩的指令处理
3. **恢复后压缩**：恢复会话后的压缩处理

### 改进建议
1. **状态持久化**：将实时对话状态持久化到 rollout
2. **状态验证**：压缩后验证实时状态的一致性
3. **去重机制**：避免指令重复
4. **用户提示**：向用户提示当前实时对话状态

### 相关测试
- `remote_pre_turn_compaction_restates_realtime_start_shapes`: 实时开始场景
- `remote_compact_resume_restates_realtime_end_shapes`: 恢复后场景
