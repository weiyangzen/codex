# Research: remote_manual_compact_without_prev_user_shapes.snap

## 场景与职责

该快照文件记录了**无先前用户消息时的远程手动压缩（Remote Manual Compact without Previous User）**场景，验证当没有对话历史时执行远程压缩的行为。

**测试场景**：用户直接执行手动 `/compact` 命令，没有任何先前的用户输入。

---

## 功能点目的

1. **空历史优化**：无历史时跳过不必要的远程压缩请求
2. **资源节省**：避免无意义的 API 调用
3. **快速响应**：空历史时快速完成压缩操作

---

## 具体技术实现

### 关键流程

```
手动/compact（无历史）→ 跳过远程压缩请求 → 直接返回成功 → 后续轮次正常
```

### 数据结构

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
```

### 关键观察

1. **无压缩请求**：
   - 当没有先前用户消息时，**不发送**远程压缩请求
   - `compact_mock.requests().len() == 0`

2. **直接跟进**：
   - 压缩操作直接完成
   - 后续对话轮次正常进行

3. **标准上下文注入**：
   - 开发者指令
   - 环境上下文
   - 新用户消息

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_manual_compact_without_previous_user_messages` (行 2568-2621)
- **快照生成**: 行 2612-2618

### Mock 配置
```rust
// 仅配置跟进响应
let responses_mock = responses::mount_sse_once(
    harness.server(),
    responses::sse(vec![
        responses::ev_assistant_message("m1", "REMOTE_MANUAL_EMPTY_FOLLOW_UP_REPLY"),
        responses::ev_completed_with_tokens("r1", 80),
    ]),
).await;

// 配置压缩响应（但预期不会被调用）
let compact_mock =
    responses::mount_compact_json_once(harness.server(), serde_json::json!({ "output": [] }))
        .await;
```

### 关键断言
```rust
// 验证没有发送压缩请求
assert_eq!(
    compact_mock.requests().len(),
    0,
    "manual /compact without prior user should not issue a remote compaction request"
);

// 验证跟进请求正常
let follow_up_request = responses_mock.single_request();
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### 行为差异
| 场景 | 本地压缩 | 远程压缩 |
|------|----------|----------|
| 有历史 | 发送压缩请求 | 发送压缩请求 |
| 无历史 | 发送压缩请求（仅含摘要提示词） | **跳过压缩请求** |

---

## 风险、边界与改进建议

### 风险点
1. **行为不一致**：本地和远程压缩在空历史时的行为不一致
2. **用户困惑**：用户可能不理解为什么压缩"瞬间完成"
3. **状态验证**：需要确保空历史检测准确

### 边界情况
1. **仅系统消息**：只有系统消息时的处理
2. **已压缩历史**：上一轮已压缩，本轮无新历史
3. **恢复后压缩**：恢复会话后立即压缩

### 改进建议
1. **行为统一**：考虑统一本地和远程压缩的空历史行为
2. **用户提示**：空历史时提示用户"没有可压缩的内容"
3. **日志记录**：记录跳过的压缩请求便于调试
4. **文档说明**：明确说明空历史时的压缩行为

### 相关测试
- `manual_compact_without_prev_user_shapes`: 本地空历史压缩
- `remote_manual_compact_with_history_shapes`: 有历史远程压缩
