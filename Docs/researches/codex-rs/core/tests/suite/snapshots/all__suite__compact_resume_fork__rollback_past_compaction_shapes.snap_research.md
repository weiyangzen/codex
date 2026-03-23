# Research: rollback_past_compaction_shapes.snap

## 场景与职责

该快照文件记录了**压缩后回滚（Rollback Past Compaction）**场景，验证当用户在压缩后执行回滚操作时的历史重建行为。

**测试场景**：用户发送消息，执行压缩，发送新消息，然后回滚到压缩前状态，验证历史正确重建。

---

## 功能点目的

1. **回滚与压缩兼容性**：验证回滚操作与压缩历史的兼容性
2. **历史重建**：从 rollout 文件重建压缩后的历史
3. **一致性保持**：确保回滚后模型可见历史一致

---

## 具体技术实现

### 关键流程

```
hello world → 压缩 → EDITED_AFTER_COMPACT → 回滚1轮 → AFTER_ROLLBACK
```

### 数据结构

**压缩请求（Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:hello world
03:message/assistant:FIRST_REPLY
04:message/user:<SUMMARIZATION_PROMPT>
```

**回滚前（Before Rollback）**:
```
00:message/user:hello world
01:message/user:<COMPACTION_SUMMARY>\nSUMMARY_ONLY_CONTEXT
02:message/developer:<PERMISSIONS_INSTRUCTIONS>
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/user:EDITED_AFTER_COMPACT
```

**回滚后（After Rollback）**:
```
00:message/user:hello world
01:message/user:<COMPACTION_SUMMARY>\nSUMMARY_ONLY_CONTEXT
02:message/developer:<PERMISSIONS_INSTRUCTIONS>
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/developer:<PERMISSIONS_INSTRUCTIONS>
05:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
06:message/user:AFTER_ROLLBACK
```

### 关键观察

1. **压缩请求**：
   - 包含原始对话历史
   - 包含摘要提示词

2. **回滚前布局**：
   - 压缩摘要替代助手回复
   - 包含 EDITED_AFTER_COMPACT 消息

3. **回滚后布局**：
   - 保留压缩摘要
   - EDITED_AFTER_COMPACT 被移除
   - 开发者指令和环境上下文重复（重建产物）
   - 新消息 AFTER_ROLLBACK 追加

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_resume_fork.rs`
- **测试函数**: `snapshot_rollback_past_compaction_replays_append_only_history` (行 415-503)
- **快照生成**: 行 487-500

### 关键断言
```rust
let after_rollback_user_texts = requests[3].message_input_texts("user");
let after_rollback_last = after_rollback_user_texts.last().unwrap();
assert_eq!(after_rollback_last, AFTER_ROLLBACK);

// 第一轮应保留
assert!(requests[3].body_contains_text("hello world"));
assert!(requests[3].body_contains_text(SUMMARY_TEXT));

// 回滚的消息应移除
assert!(!requests[3].body_contains_text(EDITED_AFTER_COMPACT));
```

### 回滚操作
```rust
codex.submit(Op::ThreadRollback { num_turns: 1 }).await?;
let rollback_event = wait_for_event(&codex, |ev| matches!(ev, EventMsg::ThreadRolledBack(_))).await;
assert_eq!(rollback_event.num_turns, 1);
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **Rollout 文件**: 持久化对话历史

### 操作类型
- `Op::Compact`: 压缩操作
- `Op::ThreadRollback`: 回滚操作

### 事件
- `ThreadRolledBack`: 回滚完成事件

---

## 风险、边界与改进建议

### 风险点
1. **历史丢失**：回滚后某些历史可能无法完全恢复
2. **摘要失效**：回滚后摘要可能与实际历史不符
3. **重复上下文**：回滚后可能出现重复的上下文项

### 边界情况
1. **多次回滚**：连续多次回滚的处理
2. **回滚到压缩前**：回滚到压缩前的原始历史
3. **回滚后压缩**：回滚后立即压缩

### 改进建议
1. **回滚预览**：回滚前预览将要恢复的历史
2. **摘要验证**：回滚后验证摘要与历史的一致性
3. **去重优化**：回滚后去重重复的上下文项
4. **回滚限制**：限制回滚范围避免过度回滚

### 相关测试
- `compact_resume_and_fork_preserve_model_history_view`: 压缩恢复和分叉
- `compact_resume_after_second_compaction_preserves_history`: 多次压缩恢复
