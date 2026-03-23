# Research: model_visible_layout_turn_overrides.snap

## 场景与职责

该快照文件记录了**轮次覆盖（Turn Overrides）**场景，验证当用户在第二轮变更 cwd、审批策略和个性时的请求结构变化。

**测试场景**：用户第一轮使用默认设置，第二轮变更 cwd、approval_policy 和 personality，验证请求结构正确反映这些变更。

---

## 功能点目的

1. **上下文覆盖验证**：验证 `OverrideTurnContext` 的效果
2. **差异检测**：检测并展示轮次间的上下文差异
3. **指令更新**：验证变更后指令正确更新

---

## 具体技术实现

### 关键流程

```
第一轮（默认设置）→ 第二轮（cwd变更 + approval_policy变更 + personality变更）
```

### 数据结构

**第一轮请求（First Request - Baseline）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:first turn
```

**第二轮请求（Second Request - Turn Overrides）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:first turn
03:message/assistant:turn one complete
04:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <personality_spec> The user has requested a new communication style. Future messages should adhe...
05:message/user:<ENVIRONMENT_CONTEXT:cwd=PRETURN_CONTEXT_DIFF_CWD>
06:message/user:second turn with context updates
```

### 关键观察

1. **cwd 变更**：
   - 环境上下文更新为 `PRETURN_CONTEXT_DIFF_CWD`

2. **审批策略变更**：
   - 从 `AskForApproval::Never` 变为 `AskForApproval::OnRequest`
   - 影响权限指令内容

3. **个性变更**：
   - 注入 `<personality_spec>` 标记
   - 提示新的沟通风格

4. **历史保留**：
   - 第一轮历史完整保留
   - 助手回复保留

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_turn_overrides` (行 80-175)
- **快照生成**: 行 163-172

### 测试配置
```rust
// 第一轮
Op::UserTurn {
    cwd: test.cwd_path().to_path_buf(),
    approval_policy: AskForApproval::Never,
    sandbox_policy: SandboxPolicy::new_read_only_policy(),
    personality: None,
    ...
}

// 第二轮
Op::UserTurn {
    cwd: preturn_context_diff_cwd,  // 变更
    approval_policy: AskForApproval::OnRequest,  // 变更
    sandbox_policy: SandboxPolicy::new_read_only_policy(),
    personality: Some(Personality::Friendly),  // 变更
    ...
}
```

### 关键断言
```rust
let requests = responses.requests();
assert_eq!(requests.len(), 2, "expected two requests");
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **文件系统**: 创建临时目录

### 特性开关
```rust
config.features.enable(Feature::Personality).expect(...);
config.personality = Some(Personality::Pragmatic);
```

### 审批策略
```rust
pub enum AskForApproval {
    Never,
    OnRequest,
    Always,
}
```

---

## 风险、边界与改进建议

### 风险点
1. **变更累积**：多次变更可能导致指令膨胀
2. **冲突解决**：多个变更冲突时的处理
3. **回滚复杂**：变更后回滚的复杂性

### 边界情况
1. **相同变更**：变更为相同值时的处理
2. **无效变更**：无效值的处理
3. **并发变更**：多次快速变更的处理

### 改进建议
1. **变更预览**：变更前预览效果
2. **变更历史**：记录变更历史便于回滚
3. **批量变更**：支持一次变更多个属性
4. **变更验证**：变更前验证有效性
5. **撤销功能**：支持撤销最近变更

### 相关测试
- `model_visible_layout_cwd_change_does_not_refresh_agents`: cwd 变更场景
- `model_visible_layout_resume_with_personality_change`: 个性变更场景
