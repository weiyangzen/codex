# Research: pre_turn_compaction_strips_incoming_model_switch_shapes.snap

## 场景与职责

该快照文件记录了**模型切换时的轮前压缩剥离行为（Pre-turn Compaction Strips Incoming Model Switch）**场景，验证当用户在轮前压缩期间切换模型时，`<model_switch>` 标记的处理逻辑。

**测试场景**：用户先使用 gpt-5.1-codex-max 模型对话，然后切换到 gpt-5.2-codex 模型，触发轮前压缩。

---

## 功能点目的

1. **模型切换标记管理**：正确处理 `<model_switch>` 标记的剥离和恢复
2. **压缩请求纯净性**：确保压缩请求不包含模型切换相关的元数据
3. **跟进请求完整性**：确保跟进请求恢复模型切换提示

---

## 具体技术实现

### 关键流程

```
模型A对话 → 切换模型B → 触发轮前压缩 → 压缩请求剥离model_switch → 跟进请求恢复model_switch
```

### 数据结构

**初始请求（Initial Request - Previous Model）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:BEFORE_SWITCH_USER
```

**本地压缩请求（Local Compaction Request）**:
```
00:message/developer:<PERMISSIONS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:BEFORE_SWITCH_USER
03:message/assistant:BEFORE_SWITCH_REPLY
04:message/user:<SUMMARIZATION_PROMPT>
```

**压缩后历史布局（Local Post-Compaction History Layout）**:
```
00:message/user:BEFORE_SWITCH_USER
01:message/user:<COMPACTION_SUMMARY>\nPRETURN_SWITCH_SUMMARY
02:message/developer[3]:
    [01] <model_switch>\nThe user was previously using a different model....
    [02] <PERMISSIONS_INSTRUCTIONS>
    [03] <personality_spec> The user has requested a new communication st...
03:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
04:message/user:AFTER_SWITCH_USER
```

### 关键观察

1. **剥离行为**：
   - 压缩请求中**不包含** `<model_switch>` 标记
   - 仅包含原始对话历史（用户消息 + 助手回复）

2. **恢复行为**：
   - 跟进请求中**包含** `<model_switch>` 标记
   - 位于开发者消息块中，与其他指令一起

3. **三消息开发者块**：
   - `[01]` `<model_switch>`: 模型切换提示
   - `[02]` `<PERMISSIONS_INSTRUCTIONS>`: 权限指令
   - `[03]` `<personality_spec>`: 个性规范

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/compact.rs`
- **测试函数**: `snapshot_request_shape_pre_turn_compaction_strips_incoming_model_switch` (行 3082-3209)
- **快照生成**: 行 3198-3208

### 模型配置
```rust
let previous_model = "gpt-5.1-codex-max";
let next_model = "gpt-5.2-codex";
```

### 关键断言
```rust
let compact_body = requests[1].body_json().to_string();

// 压缩请求应包含摘要提示词
assert!(body_contains_text(&compact_body, SUMMARIZATION_PROMPT));

// 压缩请求应剥离模型切换标记
assert!(!compact_body.contains("<model_switch>"));

let follow_up_body = requests[2].body_json().to_string();

// 跟进请求应包含模型切换标记
assert!(follow_up_body.contains("<model_switch>"));
```

### 操作序列
```rust
// 第一轮：使用旧模型
codex.submit(Op::UserTurn {
    model: previous_model.to_string(),
    text: "BEFORE_SWITCH_USER",
    ...
});

// 第二轮：使用新模型（触发切换）
codex.submit(Op::UserTurn {
    model: next_model.to_string(),
    text: "AFTER_SWITCH_USER",
    ...
});
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **SSE 序列**: 3 阶段响应

### 特性开关
```rust
config.features.enable(codex_core::features::Feature::RemoteModels);
```

### 模型切换检测
- 比较当前请求模型与上一轮模型
- 若不同，生成 `<model_switch>` 标记

---

## 风险、边界与改进建议

### 风险点
1. **切换信息丢失**：若压缩成功但跟进失败，模型切换信息丢失
2. **多次切换**：连续多次模型切换时的标记累积
3. **压缩与切换耦合**：压缩逻辑与模型切换逻辑紧密耦合

### 边界情况
1. **相同模型切换**：切换到相同模型时的处理
2. **切换后压缩失败**：模型切换后压缩失败的回退
3. **个性变更**：与模型切换同时发生的个性变更

### 改进建议
1. **切换信息持久化**：将模型切换信息持久化到 rollout，不依赖压缩跟进
2. **原子操作**：确保压缩和模型切换标记恢复的原子性
3. **切换预览**：向用户展示模型切换和压缩的预览
4. **失败恢复**：压缩失败时保留模型切换标记用于重试

### 相关测试
- `pre_sampling_model_switch_compaction_shapes`: 采样前模型切换压缩
- `remote_pre_turn_compaction_strips_incoming_model_switch_shapes`: 远程压缩场景
- `model_visible_layout_resume_with_personality_change`: 个性变更场景
