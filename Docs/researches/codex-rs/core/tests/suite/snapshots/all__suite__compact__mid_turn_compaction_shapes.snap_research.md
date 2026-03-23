# Research: mid_turn_compaction_shapes.snap

## 场景与职责

该快照文件记录了**轮中压缩（Mid-turn Compaction）**场景，验证在单轮对话中间（如工具调用后）触发自动压缩时的请求结构和历史布局。

**测试场景**：用户发送消息触发工具调用，工具输出后令牌数超出限制，系统在单轮内执行压缩并继续完成该轮。

---

## 功能点目的

1. **轮内上下文管理**：在单轮对话中间管理上下文窗口
2. **工具调用后压缩**：确保工具调用输出被正确处理后再压缩
3. **连续性保持**：压缩后同一轮对话继续，不中断用户体验

---

## 具体技术实现

### 关键流程

```
用户输入 → 工具调用 → 工具输出 → 令牌超限 → 自动压缩 → 摘要注入 → 同轮继续
```

### 数据结构

**压缩请求（Local Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:function call limit push
03:function_call/test_tool
04:function_call_output:unsupported call: test_tool
05:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后历史布局（Local Post-Compaction History Layout）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:function call limit push
03:message/user:<COMPACTION_SUMMARY>\nAUTO_SUMMARY
```

### 关键观察

1. **压缩请求包含工具产物**：
   - 原始用户消息（`function call limit push`）
   - 工具调用（`function_call/test_tool`）
   - 工具输出（`function_call_output:unsupported call: test_tool`）
   - 摘要提示词

2. **压缩后布局特点**：
   - 保留原始用户消息
   - 工具调用和输出被压缩为摘要
   - 开发者指令和环境上下文保留
   - 同一轮继续，不添加新用户消息

3. **与轮前压缩的区别**：
   - 轮中压缩在同一轮内完成
   - 不包含"新用户消息"（因为是轮中）
   - 工具产物参与压缩

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `snapshot_request_shape_mid_turn_continuation_compaction` (行 2592-2694)
- **快照生成**: 行 2678-2693

### 核心常量
```rust
const DUMMY_FUNCTION_NAME: &str = "test_tool";
const DUMMY_CALL_ID: &str = "call-multi-auto";
const FUNCTION_CALL_LIMIT_MSG: &str = "function call limit push";
const AUTO_SUMMARY_TEXT: &str = "AUTO_SUMMARY";
```

### 测试配置
```rust
let context_window = 100;
let limit = context_window * 90 / 100;  // 90
let over_limit_tokens = context_window * 95 / 100 + 1;  // 96
```

### 关键断言
```rust
// 验证工具输出在压缩前发送
let function_call_output = auto_compact_mock
    .single_request()
    .function_call_output(DUMMY_CALL_ID);

// 验证压缩请求包含摘要提示词
assert!(body_contains_text(&auto_compact_body, SUMMARIZATION_PROMPT));
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **SSE 序列**: 三阶段响应
   - 第一轮：工具调用 + 超限令牌
   - 压缩轮：摘要生成
   - 后续轮：完成回复

### 配置参数
- `model_context_window`: 100（测试用小值）
- `model_auto_compact_token_limit`: 90（90% 阈值）

### 事件流
1. `TurnStarted`
2. `ItemStarted` (FunctionCall)
3. `ItemCompleted` (FunctionCall)
4. `ItemStarted` (ContextCompaction) - 自动触发
5. `ItemCompleted` (ContextCompaction)
6. `TurnComplete`

---

## 风险、边界与改进建议

### 风险点
1. **工具链中断**：轮中压缩可能中断工具调用链
2. **状态一致性**：确保压缩前后工具调用状态一致
3. **令牌估算精度**：轮中令牌估算需准确包含工具输出

### 边界情况
1. **多工具调用**：单轮多个工具调用后的压缩
2. **工具输出过大**：工具输出本身超出上下文窗口
3. **压缩失败**：轮中压缩失败时的回滚机制

### 改进建议
1. **工具状态保留**：确保工具调用 ID 和状态在压缩后保留
2. **智能压缩**：优先压缩非工具相关历史，保留最近工具调用
3. **压缩提示优化**：针对轮中场景优化摘要提示词
4. **监控指标**：添加轮中压缩频率和成功率监控

### 相关测试
- `pre_turn_compaction_*`: 轮前压缩场景
- `remote_mid_turn_compaction_shapes`: 远程轮中压缩
- `auto_compact_starts_after_turn_started`: 压缩启动时机
