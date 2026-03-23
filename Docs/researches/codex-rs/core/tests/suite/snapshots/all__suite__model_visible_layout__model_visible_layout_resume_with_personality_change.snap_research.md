# Research: model_visible_layout_resume_with_personality_change.snap

## 场景与职责

该快照文件记录了**恢复后会话个性变更（Resume with Personality Change）**场景，验证当恢复会话后模型和个性都发生变化时的请求结构。

**测试场景**：用户使用 gpt-5.2 模型对话，恢复会话后使用 gpt-5.2-codex 模型和 Friendly 个性，验证模型切换提示和个性规范正确注入。

---

## 功能点目的

1. **模型切换提示**：模型变化时注入 `<model_switch>` 提示
2. **个性规范注入**：个性变化时注入 `<personality_spec>` 提示
3. **多变更处理**：同时处理模型和个性变更

---

## 具体技术实现

### 关键流程

```
gpt-5.2 对话 → 关闭会话 → 恢复会话（gpt-5.2-codex + Friendly）→ 新轮次
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

**恢复后第一请求（First Request After Resume）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:seed resume history
03:message/assistant:recorded before resume
04:message/developer[2]:
    [01] <model_switch>\nThe user was previously using a different model. Please continue the conversatio...
    [02] <PERMISSIONS_INSTRUCTIONS>
05:message/user:<ENVIRONMENT_CONTEXT:cwd=PRETURN_CONTEXT_DIFF_CWD>
06:message/user:resume and change personality
```

### 关键观察

1. **模型切换提示**：
   - 包含 `<model_switch>` 标记
   - 提示模型已变更

2. **个性规范**：
   - 恢复后配置中设置个性
   - 在后续轮次中生效

3. **历史保留**：
   - 恢复前历史完整保留
   - 助手回复保留

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_resume_with_personality_change` (行 288-384)
- **快照生成**: 行 372-381

### 测试配置
```rust
// 初始模型
let mut initial_builder = test_codex().with_config(|config| {
    config.model = Some("gpt-5.2".to_string());
});

// 恢复后配置
let mut resume_builder = test_codex().with_config(|config| {
    config.model = Some("gpt-5.2-codex".to_string());
    config.features.enable(Feature::Personality).expect(...);
    config.personality = Some(Personality::Pragmatic);  // 配置个性
});

// 恢复后发送带个性的轮次
resumed.codex.submit(Op::UserTurn {
    personality: Some(Personality::Friendly),  // 轮次个性
    ...
}).await?;
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **文件系统**: 创建临时目录

### 特性开关
```rust
config.features.enable(Feature::Personality)
```

### 个性类型
```rust
pub enum Personality {
    Pragmatic,
    Friendly,
    // ...
}
```

---

## 风险、边界与改进建议

### 风险点
1. **个性冲突**：配置个性与轮次个性冲突
2. **模型不支持**：某些模型可能不支持个性
3. **提示过长**：模型切换 + 个性规范可能过长

### 边界情况
1. **个性为 None**：无个性时的处理
2. **相同个性**：个性未变更时的处理
3. **无效个性**：无效个性名称的处理

### 改进建议
1. **个性预览**：变更前预览个性效果
2. **个性冲突解决**：明确配置个性与轮次个性的优先级
3. **模型兼容性检查**：检查模型是否支持个性
4. **渐进变更**：支持个性的渐进式变更

### 相关测试
- `model_visible_layout_resume_override_matches_rollout_model`: 模型匹配场景
- `model_visible_layout_turn_overrides`: 轮次覆盖场景
