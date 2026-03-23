# Research: remote_mid_turn_compaction_summary_only_reinjects_context_shapes.snap

## 场景与职责

该快照文件记录了**远程轮中压缩仅返回摘要项时的上下文重新注入（Remote Mid-turn Compaction Summary Only Reinjects Context）**场景，验证当远程压缩仅返回压缩项（无用户历史）时，系统如何重新注入上下文。

**测试场景**：用户发送消息触发工具调用，工具输出后触发远程压缩，压缩响应仅包含压缩项，验证跟进请求正确重新注入上下文。

---

## 功能点目的

1. **最小压缩输出处理**：处理仅返回压缩项的远程压缩响应
2. **上下文重新注入**：在压缩项前重新注入标准上下文
3. **布局正确性**：确保压缩后历史布局正确

---

## 具体技术实现

### 关键流程

```
用户输入 → 工具调用 → 远程压缩（仅返回compaction项）→ 上下文重新注入 → 完成
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
02:compaction:encrypted=true
```

### 关键观察

1. **压缩响应特点**：
   - 仅返回 `ResponseItem::Compaction`
   - 不包含用户消息历史

2. **上下文重新注入**：
   - 开发者指令重新注入
   - 环境上下文重新注入
   - 位于压缩项之前

3. **与带历史压缩的区别**：
   - 无历史压缩：上下文 + compaction
   - 带历史压缩：历史 + compaction（上下文可能在历史中）

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_mid_turn_compaction_summary_only_reinjects_context` (行 2378-2459)
- **快照生成**: 行 2444-2456

### Mock 配置
```rust
let compacted_history = vec![ResponseItem::Compaction {
    encrypted_content: summary_with_prefix("REMOTE_SUMMARY_ONLY"),
}];
let compact_mock = responses::mount_compact_json_once(
    harness.server(),
    serde_json::json!({ "output": compacted_history }),
).await;
```

### 关键断言
```rust
assert_eq!(compact_mock.requests().len(), 1);
assert_eq!(initial_turn_request_mock.requests().len(), 1);
assert_eq!(post_compact_turn_request_mock.requests().len(), 1);
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### 压缩响应格式
```json
{
  "output": [
    {
      "type": "compaction",
      "encrypted_content": "<COMPACTION_SUMMARY>\nREMOTE_SUMMARY_ONLY"
    }
  ]
}
```

---

## 风险、边界与改进建议

### 风险点
1. **上下文丢失**：若重新注入失败，可能导致上下文丢失
2. **重复注入**：多次压缩可能导致上下文重复
3. **顺序错误**：上下文和压缩项顺序错误

### 边界情况
1. **空上下文**：某些配置下上下文为空
2. **大上下文**：上下文本身很大时的处理
3. **上下文变更**：压缩期间上下文变更

### 改进建议
1. **注入验证**：验证上下文正确注入
2. **去重机制**：避免上下文重复
3. **顺序保证**：确保上下文始终在压缩项前
4. **配置选项**：允许配置是否重新注入上下文

### 相关测试
- `remote_mid_turn_compaction_shapes`: 带历史的轮中压缩
- `remote_mid_turn_compaction_multi_summary_reinjects_above_last_summary_shapes`: 多摘要场景
