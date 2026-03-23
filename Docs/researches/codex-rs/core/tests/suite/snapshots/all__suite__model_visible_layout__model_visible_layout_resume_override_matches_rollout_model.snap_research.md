# Research: model_visible_layout_resume_override_matches_rollout_model.snap

## 场景与职责

该快照文件记录了**恢复后覆盖模型与 Rollout 模型匹配（Resume Override Matches Rollout Model）**场景，验证当恢复会话后使用 OverrideTurnContext 设置模型与 rollout 中记录的模型一致时，不产生模型切换提示。

**测试场景**：用户使用 gpt-5.2 模型对话，恢复会话后通过 OverrideTurnContext 设置模型为 gpt-5.2（与 rollout 一致），验证无模型切换提示。

---

## 功能点目的

1. **模型匹配检测**：检测覆盖模型与 rollout 模型是否一致
2. **避免冗余提示**：模型一致时不产生切换提示
3. **优化请求大小**：减少不必要的指令开销

---

## 具体技术实现

### 关键流程

```
gpt-5.2 对话 → 关闭会话 → 恢复会话 → OverrideTurnContext(model=gpt-5.2) → 新轮次
```

### 数据结构

**恢复前最后请求（Last Request Before Resume）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:seed resume history
```

**恢复后第一请求（First Request After Resume + Override）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:seed resume history
03:message/assistant:recorded before resume
04:message/user:<ENVIRONMENT_CONTEXT:cwd=PRETURN_CONTEXT_DIFF_CWD>
05:message/user:first resumed turn after model override
```

### 关键观察

1. **无模型切换提示**：
   - 恢复后请求不包含 `<model_switch>`
   - 因为覆盖模型与 rollout 模型一致

2. **上下文差异**：
   - 包含 cwd 变更（`PRETURN_CONTEXT_DIFF_CWD`）
   - 这是 OverrideTurnContext 中的设置

3. **历史保留**：
   - 恢复前历史完整保留
   - 助手回复（`recorded before resume`）保留

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_resume_override_matches_rollout_model` (行 386-484)
- **快照生成**: 行 472-481

### 测试配置
```rust
// 初始模型
let mut initial_builder = test_codex().with_config(|config| {
    config.model = Some("gpt-5.2".to_string());
});

// 恢复后覆盖模型（与 rollout 一致）
resumed.codex.submit(Op::OverrideTurnContext {
    cwd: Some(resume_override_cwd),
    model: Some("gpt-5.2".to_string()),  // 与 rollout 一致
    ...
}).await?;
```

### 关键断言
```rust
// 验证恢复后请求不包含模型切换标记
let resumed_request = resumed_mock.single_request();
// 通过快照隐式验证
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **文件系统**: 创建临时目录

### 操作类型
- `Op::OverrideTurnContext`: 覆盖轮次上下文

### 恢复流程
```rust
let resumed = resume_builder.resume(&server, home, rollout_path).await?;
```

---

## 风险、边界与改进建议

### 风险点
1. **模型别名**：不同名称的相同模型可能误判
2. **版本差异**：相同模型不同版本的处理
3. **回滚后模型**：回滚后模型与当前配置不一致

### 边界情况
1. **模型为 None**：覆盖时模型为 None 的处理
2. **无效模型**：覆盖无效模型名称的处理
3. **并发覆盖**：多次覆盖的模型冲突

### 改进建议
1. **模型规范化**：规范化模型名称避免误判
2. **版本追踪**：追踪模型版本信息
3. **用户提示**：模型一致时提示用户"继续使用相同模型"
4. **配置同步**：确保覆盖与配置同步

### 相关测试
- `model_visible_layout_resume_with_personality_change`: 个性变更场景
- `model_visible_layout_turn_overrides`: 轮次覆盖场景
