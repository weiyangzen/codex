# Research: pre_sampling_model_switch_compaction_shapes.snap

## 场景与职责

该快照文件记录了**模型切换时的采样前压缩（Pre-sampling Compaction on Model Switch）**场景，验证当用户切换到上下文窗口更小的模型时，系统在发送新用户消息前自动压缩历史记录的行为。

**测试场景**：用户先使用大上下文窗口模型（gpt-5.2-codex, 273K），然后切换到小上下文窗口模型（gpt-5.1-codex-max, 125K），系统在新模型采样前自动压缩历史。

---

## 功能点目的

1. **模型切换适配**：自动适配不同模型的上下文窗口限制
2. **采样前压缩**：在新模型处理新消息前压缩历史，确保适配新模型限制
3. **历史完整性**：压缩时排除新用户消息，仅压缩已有历史

---

## 具体技术实现

### 关键流程

```
大模型对话 → 切换小模型 → 检测窗口差异 → 采样前压缩 → 压缩历史+新消息发送
```

### 数据结构

**初始请求（Initial Request - Previous Model）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:before switch
```

**采样前压缩请求（Pre-sampling Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:before switch
03:message/assistant:before switch
04:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后跟进请求（Post-Compaction Follow-up Request - Next Model）**:
```
00:message/user:before switch
01:message/user:<COMPACTION_SUMMARY>\nPRE_SAMPLING_SUMMARY
02:message/developer[2]:
    [01] <model_switch>\nThe user was previously using a different model....
    [02] <PERMISSIONS_INSTRUCTIONS>
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/user:after switch
```

### 关键观察

1. **三阶段请求序列**：
   - 初始请求：使用大模型（gpt-5.2-codex）
   - 压缩请求：仍使用大模型（历史模型）
   - 跟进请求：使用小模型（gpt-5.1-codex-max）

2. **压缩请求特点**：
   - 包含完整历史（用户消息 + 助手回复）
   - 不包含新用户消息（"after switch"）
   - 包含摘要提示词

3. **跟进请求特点**：
   - 包含模型切换提示（`<model_switch>`）
   - 压缩摘要替代原始助手回复
   - 新用户消息追加到末尾

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `pre_sampling_compact_runs_on_switch_to_smaller_context_model` (行 1693-1815)
- **快照生成**: 行 1801-1814

### 模型配置
```rust
let previous_model = "gpt-5.2-codex";
let next_model = "gpt-5.1-codex-max";

// 上下文窗口配置
previous_model: 273_000
next_model: 125_000
```

### 关键断言
```rust
assert_pre_sampling_switch_compaction_requests(
    &requests[0].body_json(),  // 初始请求
    &requests[1].body_json(),  // 压缩请求
    &requests[2].body_json(),  // 跟进请求
    previous_model,
    next_model,
);
```

### 验证函数
```rust
fn assert_pre_sampling_switch_compaction_requests(
    first: &serde_json::Value,
    compact: &serde_json::Value,
    follow_up: &serde_json::Value,
    previous_model: &str,
    next_model: &str,
) {
    assert_eq!(first["model"].as_str(), Some(previous_model));
    assert_eq!(compact["model"].as_str(), Some(previous_model));
    assert_eq!(follow_up["model"].as_str(), Some(next_model));
    
    // 压缩请求应包含摘要提示词
    assert!(body_contains_text(&compact_body, SUMMARIZATION_PROMPT));
    
    // 压缩请求应剥离模型切换标记
    assert!(!compact_body.contains("<model_switch>"));
    
    // 跟进请求应包含模型切换标记
    assert!(follow_up_body.contains("<model_switch>"));
}
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **Models API**: `mount_models_once` 模拟模型列表查询

### API 调用序列
1. `GET /v1/models` - 查询模型列表获取上下文窗口
2. `POST /v1/responses` (model: gpt-5.2-codex) - 初始对话
3. `POST /v1/responses` (model: gpt-5.2-codex) - 压缩请求
4. `POST /v1/responses` (model: gpt-5.1-codex-max) - 跟进请求

### 事件系统
- `TurnStarted` - 使用相同事件 ID
- `ItemStarted` (ContextCompaction)
- `ItemCompleted` (ContextCompaction)
- `TurnComplete`

---

## 风险、边界与改进建议

### 风险点
1. **模型切换提示丢失**：压缩请求剥离 `<model_switch>`，若跟进失败可能丢失切换信息
2. **窗口计算误差**：模型间令牌计算差异可能导致压缩不足或过度
3. **多轮切换**：连续多次模型切换时的压缩策略

### 边界情况
1. **相同大小窗口切换**：窗口相同时是否跳过压缩
2. **大窗口切换**：从小窗口切换到大窗口时的行为
3. **压缩失败**：采样前压缩失败时的回退策略

### 改进建议
1. **智能压缩阈值**：根据两模型窗口差异动态计算压缩目标
2. **模型切换保留**：考虑在压缩摘要中保留模型切换信息
3. **压缩预览**：向用户展示因模型切换触发的压缩
4. **渐进压缩**：支持多次渐进压缩以适应大幅窗口差异

### 相关测试
- `pre_sampling_compact_runs_after_resume_and_switch_to_smaller_model`: 恢复后切换
- `pre_turn_compaction_strips_incoming_model_switch_shapes`: 轮前压缩剥离模型切换
- `remote_pre_turn_compaction_strips_incoming_model_switch_shapes`: 远程压缩场景
