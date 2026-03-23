# Research: remote_mid_turn_compaction_does_not_restate_realtime_end_shapes.snap

## 场景与职责

该快照文件记录了**远程轮中压缩不重述实时结束指令（Remote Mid-turn Compaction Does Not Restate Realtime End）**场景，验证当实时对话在轮次开始前已关闭，轮中压缩后不重复陈述实时结束指令。

**测试场景**：用户开启实时对话，发送消息，关闭实时对话，发送新消息（触发工具调用），轮中压缩，完成该轮。

---

## 功能点目的

1. **避免指令重复**：当前轮次已建立非活动基线时，压缩后不重复陈述
2. **状态一致性**：确保实时状态在轮次内保持一致
3. **优化请求大小**：避免不必要的指令重复，减少令牌消耗

---

## 具体技术实现

### 关键流程

```
开启实时 → USER_ONE → 关闭实时 → USER_TWO（触发工具调用）→ 轮中压缩 → 完成
```

### 数据结构

**第二轮初始请求（Second Turn Initial Request）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <realtime_conversation>\nRealtime conversation started.\n\nYou a...
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:SETUP_USER
03:message/assistant:REMOTE_SETUP_REPLY
04:message/developer:<realtime_conversation>\nRealtime conversation ended.\n\nSubsequ...
05:message/user:USER_TWO
```

**远程压缩请求（Remote Compaction Request）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <realtime_conversation>\nRealtime conversation started.\n\nYou a...
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:SETUP_USER
03:message/assistant:REMOTE_SETUP_REPLY
04:message/developer:<realtime_conversation>\nRealtime conversation ended.\n\nSubsequ...
05:message/user:USER_TWO
06:function_call/test_tool
07:function_call_output:unsupported call: test_tool
```

**压缩后历史布局（Remote Post-Compaction History Layout）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:compaction:encrypted=true
```

### 关键观察

1. **第二轮初始请求特点**：
   - 包含实时开始指令（历史遗留）
   - 包含实时结束指令（`<realtime_conversation>...ended`）
   - 已建立非活动基线

2. **压缩请求特点**：
   - 包含完整历史（包括实时指令）
   - 包含工具调用和输出

3. **压缩后布局特点**：
   - **不包含** `<realtime_conversation>` 指令
   - 仅包含标准开发者和环境上下文
   - 压缩项

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact_remote.rs`
- **测试函数**: `snapshot_request_shape_remote_mid_turn_compaction_does_not_restate_realtime_end` (行 1762-1861)
- **快照生成**: 行 1844-1857

### 关键断言
```rust
let second_turn_request = &requests[1];
let compact_request = compact_mock.single_request();
let post_compact_request = &requests[2];

// 第二轮请求应包含实时结束指令
assert_request_contains_realtime_end(second_turn_request);

// 压缩后请求不应包含实时指令
assert!(
    !post_compact_request
        .body_json()
        .to_string()
        .contains("<realtime_conversation>"),
    "did not expect post-compaction history to restate realtime instructions once the current turn had already established an inactive baseline"
);
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
test.codex.submit(Op::UserInput { text: "SETUP_USER" }).await?;

// 关闭实时对话
close_realtime_conversation(test.codex.as_ref()).await?;

// 第二轮（触发工具调用和压缩）
test.codex.submit(Op::UserInput { text: "USER_TWO" }).await?;
```

---

## 风险、边界与改进建议

### 风险点
1. **状态丢失**：若压缩后需要实时状态信息，可能丢失
2. **轮次边界混淆**：轮中压缩与轮次边界的关系复杂
3. **调试困难**：不陈述指令可能使调试更困难

### 边界情况
1. **压缩失败**：轮中压缩失败时的实时状态
2. **多轮压缩**：单轮多次压缩的指令处理
3. **实时重新开启**：压缩后重新开启实时对话

### 改进建议
1. **状态注释**：在压缩项中注释实时状态
2. **调试模式**：调试模式下保留所有指令
3. **状态追踪**：更清晰的实时状态追踪机制
4. **文档说明**：明确说明轮中压缩的指令处理逻辑

### 相关测试
- `remote_pre_turn_compaction_restates_realtime_end_shapes`: 轮前压缩重述
- `remote_compact_resume_restates_realtime_end_shapes`: 恢复后重述
