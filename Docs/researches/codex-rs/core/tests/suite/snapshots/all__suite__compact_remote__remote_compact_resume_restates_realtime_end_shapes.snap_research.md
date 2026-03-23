# Research: remote_compact_resume_restates_realtime_end_shapes.snap

## 场景与职责

该快照文件记录了**远程压缩恢复后重述实时结束指令（Remote Compact Resume Restates Realtime End）**场景，验证当会话经历远程压缩、关闭实时对话、恢复后，首轮回合如何正确重述实时结束指令。

**测试场景**：用户开启实时对话，发送消息，关闭实时对话，执行远程压缩，关闭会话，恢复会话后发送新消息。

---

## 功能点目的

1. **实时状态恢复**：恢复会话后正确重建实时对话状态
2. **指令重述**：在压缩后基线被清除的情况下，仍能从上一轮设置中恢复实时结束指令
3. **远程压缩兼容**：确保远程压缩与实时对话状态管理兼容

---

## 具体技术实现

### 关键流程

```
开启实时对话 → USER_ONE → 关闭实时对话 → 远程压缩 → 关闭会话 → 恢复会话 → USER_TWO
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

**恢复后历史布局（Remote Post-Resume History Layout）**:
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
   - 包含实时开始指令（`Realtime conversation started`）
   - 包含完整对话历史
   - 发送到远程压缩端点（`/v1/responses/compact`）

2. **恢复后布局特点**：
   - 以 `compaction:encrypted=true` 开头（远程压缩项）
   - 包含实时结束指令（`Realtime conversation ended`）
   - 从上一轮设置重建实时结束状态

3. **指令状态转换**：
   - 压缩前：实时已开始（`started`）
   - 压缩时：包含开始指令
   - 恢复后：重述结束指令（`ended`）

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_compact_resume_restates_realtime_end` (行 1863-1964)
- **快照生成**: 行 1951-1960

### 测试配置
```rust
let realtime_server = start_remote_realtime_server().await;
let mut builder = remote_realtime_test_codex_builder(&realtime_server);
```

### 关键操作序列
```rust
// 1. 开启实时对话
start_realtime_conversation(test.codex.as_ref()).await?;

// 2. 第一轮对话
test.codex.submit(Op::UserInput { text: "USER_ONE" }).await?;

// 3. 关闭实时对话
close_realtime_conversation(test.codex.as_ref()).await?;

// 4. 执行远程压缩
test.codex.submit(Op::Compact).await?;

// 5. 关闭会话
test.codex.submit(Op::Shutdown).await?;

// 6. 恢复会话
let resumed = resume_builder.resume(&server, home, rollout_path).await?;

// 7. 恢复后第一轮
resumed.codex.submit(Op::UserInput { text: "USER_TWO" }).await?;
```

### 关键断言
```rust
let after_resume_request = &requests[1];
assert_request_contains_realtime_end(after_resume_request);
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
1. **Mock Server**: `wiremock::MockServer` 用于响应 API
2. **WebSocket Server**: 模拟实时对话后端

### API 端点
- `/v1/responses` - 正常对话
- `/v1/responses/compact` - 远程压缩

### 实时对话事件
- `RealtimeConversationStarted`
- `RealtimeConversationClosed`
- `SessionUpdated`

---

## 风险、边界与改进建议

### 风险点
1. **状态重建失败**：若上一轮设置丢失，无法正确重述指令
2. **压缩与状态冲突**：远程压缩可能不包含实时状态信息
3. **恢复后状态不一致**：恢复后的实时状态与实际可能不一致

### 边界情况
1. **实时未关闭**：若实时对话未关闭就压缩，恢复后状态
2. **多次恢复**：连续多次恢复后的状态累积
3. **压缩失败**：远程压缩失败时的实时状态处理

### 改进建议
1. **状态持久化**：将实时对话状态持久化到 rollout
2. **状态验证**：恢复后验证实时状态的一致性
3. **用户提示**：恢复后向用户提示当前实时对话状态
4. **压缩包含状态**：远程压缩输出包含实时状态信息

### 相关测试
- `remote_manual_compact_restates_realtime_start_shapes`: 实时开始指令重述
- `remote_pre_turn_compaction_restates_realtime_end_shapes`: 轮前压缩场景
- `remote_mid_turn_compaction_does_not_restate_realtime_end_shapes`: 轮中压缩场景
