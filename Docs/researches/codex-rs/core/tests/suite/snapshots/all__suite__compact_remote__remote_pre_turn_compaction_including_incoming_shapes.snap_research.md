# Research: remote_pre_turn_compaction_including_incoming_shapes.snap

## 场景与职责

该快照文件记录了**带上下文覆盖的远程轮前压缩（Remote Pre-turn Compaction with Context Override）**场景，验证当用户在轮前压缩时提供上下文覆盖时的请求结构。

**测试场景**：用户进行两轮对话后，第三轮发送消息前变更 cwd，触发轮前自动压缩。

---

## 功能点目的

1. **上下文差异处理**：在压缩请求中体现上下文覆盖
2. **环境上下文更新**：压缩后使用新的环境上下文
3. **远程压缩兼容性**：验证远程压缩与上下文覆盖的兼容性

---

## 具体技术实现

### 关键流程

```
USER_ONE → USER_TWO → OverrideTurnContext(cwd) + USER_THREE → 轮前压缩 → 跟进请求
```

### 数据结构

**远程压缩请求（Remote Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:USER_ONE
03:message/assistant:REMOTE_FIRST_REPLY
04:message/user:USER_TWO
05:message/assistant:REMOTE_SECOND_REPLY
```

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:message/user:USER_ONE
01:message/user:USER_TWO
02:compaction:encrypted=true
03:message/developer:<PERMISSIONS_INSTRUCTIONS>
04:message/user:<ENVIRONMENT_CONTEXT:cwd=PRETURN_CONTEXT_DIFF_CWD>
05:message/user:USER_THREE
```

### 关键观察

1. **压缩请求特点**：
   - 包含前两轮完整历史
   - 使用原始环境上下文（`<CWD>`）
   - 不包含新用户消息（USER_THREE）

2. **跟进请求特点**：
   - 压缩项替代助手回复
   - 更新环境上下文（`PRETURN_CONTEXT_DIFF_CWD`）
   - 新用户消息追加

3. **与本地压缩的区别**：
   - 远程压缩返回 `compaction` 项
   - 不包含摘要提示词

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_pre_turn_compaction_including_incoming_user_message` (行 1966-2067)
- **快照生成**: 行 2046-2055

### 测试流程
```rust
for user in ["USER_ONE", "USER_TWO", "USER_THREE"] {
    if user == "USER_THREE" {
        // 第三轮前覆盖上下文
        codex.submit(Op::OverrideTurnContext {
            cwd: Some(PathBuf::from(PRETURN_CONTEXT_DIFF_CWD)),
            ...
        }).await?;
    }
    codex.submit(Op::UserInput { text: user.to_string() }).await?;
}
```

### 关键断言
```rust
assert_eq!(
    requests[2]
        .message_input_texts("user")
        .iter()
        .filter(|text| text.as_str() == "USER_THREE")
        .count(),
    1,
    "post-compaction request should contain incoming user exactly once from runtime append"
);
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **TestCodexHarness**: 测试工具

### 操作类型
- `Op::UserInput`: 用户输入
- `Op::OverrideTurnContext`: 上下文覆盖

---

## 风险、边界与改进建议

### 风险点
1. **上下文不一致**：压缩请求和跟进请求使用不同上下文
2. **覆盖操作丢失**：若压缩失败，覆盖操作可能丢失
3. **cwd 变更影响**：cwd 变更可能影响工具调用路径

### 边界情况
1. **多次覆盖**：单轮多次上下文覆盖
2. **覆盖与压缩冲突**：覆盖参数影响压缩决策
3. **大上下文差异**：上下文差异很大时的处理

### 改进建议
1. **上下文差异提示**：向用户展示上下文变更
2. **原子操作**：确保上下文覆盖与压缩的原子性
3. **预览模式**：压缩前预览将要发送的内容
4. **覆盖验证**：验证上下文覆盖的有效性

### 相关测试
- `pre_turn_compaction_including_incoming_shapes`: 本地压缩场景
- `remote_pre_turn_compaction_strips_incoming_model_switch_shapes`: 模型切换场景
