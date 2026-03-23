# Research: remote_mid_turn_compaction_multi_summary_reinjects_above_last_summary_shapes.snap

## 场景与职责

该快照文件记录了**远程轮中压缩多摘要重新注入（Remote Mid-turn Compaction Multi Summary Reinjects）**场景，验证当存在多个历史压缩项时，轮中压缩如何携带旧摘要并重新注入上下文。

**测试场景**：用户对话，执行手动压缩（产生旧摘要），再发送消息触发工具调用和自动压缩，验证压缩请求包含旧摘要，跟进请求正确布局。

---

## 功能点目的

1. **多摘要累积**：验证多个压缩摘要的累积和传递
2. **上下文重新注入**：验证压缩后上下文正确重新注入
3. **摘要链完整性**：确保摘要链在多次压缩中保持完整

---

## 具体技术实现

### 关键流程

```
USER_ONE → 手动压缩（REMOTE_OLDER_SUMMARY）→ USER_TWO → 轮中压缩（REMOTE_LATEST_SUMMARY）→ 完成
```

### 数据结构

**远程压缩请求（Remote Compaction Request）**:
```
00:message/user:USER_ONE
01:compaction:encrypted=true
```

**第二轮请求（After Compaction）**:
```
00:message/user:USER_ONE
01:compaction:encrypted=true
02:message/developer:<PERMISSIONS_INSTRUCTIONS>
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/user:USER_TWO
```

### 关键观察

1. **压缩请求特点**：
   - 包含原始用户消息（USER_ONE）
   - 包含旧的压缩项（`compaction:encrypted=true`）
   - 这是之前手动压缩产生的摘要

2. **跟进请求特点**：
   - 保留旧用户消息
   - 保留旧压缩项
   - 重新注入上下文（开发者指令、环境上下文）
   - 追加新用户消息（USER_TWO）

3. **摘要累积**：
   - 旧摘要（REMOTE_OLDER_SUMMARY）在压缩请求中可见
   - 新摘要（REMOTE_LATEST_SUMMARY）将在压缩响应中生成

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_mid_turn_compaction_multi_summary_reinjects_above_last_summary` (行 2461-2566)
- **快照生成**: 行 2551-2563

### Mock 配置
```rust
// 设置轮
let setup_turn_request_mock = responses::mount_sse_once(...).await;

// 第二轮（触发压缩）
let second_turn_request_mock = responses::mount_sse_once(...).await;

// 两次压缩响应
let compact_mock = responses::mount_compact_user_history_with_summary_sequence(
    harness.server(),
    vec![
        summary_with_prefix("REMOTE_OLDER_SUMMARY"),   // 第一次手动压缩
        summary_with_prefix("REMOTE_LATEST_SUMMARY"),  // 第二次轮中压缩
    ],
).await;
```

### 关键断言
```rust
let compact_requests = compact_mock.requests();
assert_eq!(compact_requests.len(), 2);

let compact_request = compact_requests[1].clone();
assert!(
    compact_request.body_contains_text("REMOTE_OLDER_SUMMARY"),
    "older summary should round-trip from conversation history into the next compact request"
);
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **序列压缩响应**: `mount_compact_user_history_with_summary_sequence`

### 操作序列
```rust
// 第一轮
codex.submit(Op::UserInput { text: "USER_ONE" }).await?;

// 手动压缩
codex.submit(Op::Compact).await?;

// 第二轮（触发轮中压缩）
codex.submit(Op::UserInput { text: "USER_TWO" }).await?;
```

---

## 风险、边界与改进建议

### 风险点
1. **摘要膨胀**：多次压缩后摘要链可能过长
2. **信息稀释**：旧摘要可能稀释新摘要的重要性
3. **压缩效率**：携带多个摘要的压缩请求效率降低

### 边界情况
1. **大量摘要**：数十次压缩后的摘要链处理
2. **摘要合并**：是否应合并多个旧摘要
3. **选择性保留**：是否应选择性保留重要摘要

### 改进建议
1. **摘要合并**：定期合并多个旧摘要为一个
2. **分层摘要**：支持分层摘要结构
3. **摘要重要性标记**：标记重要摘要避免被合并
4. **摘要清理**：提供手动清理旧摘要的功能

### 相关测试
- `remote_mid_turn_compaction_summary_only_reinjects_context_shapes`: 仅摘要场景
- `multiple_auto_compact_per_task_runs_after_token_limit_hit`: 多次自动压缩
