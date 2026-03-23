# Research: model_visible_layout_cwd_change_does_not_refresh_agents.snap

## 场景与职责

该快照文件记录了**cwd 变更不刷新 AGENTS 指令（CWD Change Does Not Refresh Agents）**场景，验证当用户在不同 AGENTS.md 的目录间切换时，当前行为不会刷新 AGENTS 指令。

**测试场景**：用户在 agents_one 目录对话，然后切换到 agents_two 目录（含不同 AGENTS.md）发送消息。

---

## 功能点目的

1. **AGENTS.md 作用域验证**：验证 AGENTS.md 是会话级而非轮次级
2. **cwd 变更影响**：验证 cwd 变更不会触发 AGENTS.md 重新加载
3. **行为文档化**：记录当前行为以便未来改进

---

## 具体技术实现

### 关键流程

```
agents_one/AGENTS.md → 第一轮 → agents_two/AGENTS.md → 第二轮
```

### 数据结构

**第一轮请求（First Request - agents_one）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:first turn in agents_one
```

**第二轮请求（Second Request - agents_two cwd）**:
```
00:message/developer[2]:
    [01] <PERMISSIONS_INSTRUCTIONS>
    [02] <SKILLS_INSTRUCTIONS>
01:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
02:message/user:first turn in agents_one
03:message/assistant:turn one complete
04:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>>
05:message/user:second turn in agents_two
```

### 关键观察

1. **AGENTS.md 不刷新**：
   - 两轮请求使用相同的开发者指令
   - 未加载 agents_two 的 AGENTS.md

2. **cwd 更新**：
   - 环境上下文中的 cwd 更新
   - 但 AGENTS.md 内容不变

3. **TODO 注释**：
   - 测试文件中有 TODO 注释表明这是已知限制
   - 计划未来改进为刷新 AGENTS.md

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_cwd_change_does_not_refresh_agents` (行 177-286)
- **快照生成**: 行 274-283

### TODO 注释
```rust
// TODO(ccunningham): Diff `user_instructions` and emit updates when AGENTS.md content changes
// (for example after cwd changes), then update this test to assert refreshed AGENTS content.
```

### 目录设置
```rust
let cwd_one = test.cwd_path().join("agents_one");
let cwd_two = test.cwd_path().join("agents_two");
fs::create_dir_all(&cwd_one)?;
fs::create_dir_all(&cwd_two)?;

fs::write(
    cwd_one.join("AGENTS.md"),
    "# AGENTS one\n\n<INSTRUCTIONS>\nTurn one agents instructions.\n</INSTRUCTIONS>\n",
)?;
fs::write(
    cwd_two.join("AGENTS.md"),
    "# AGENTS two\n\n<INSTRUCTIONS>\nTurn two agents instructions.\n</INSTRUCTIONS>\n",
)?;
```

### 关键断言
```rust
assert_eq!(
    user_instructions_wrapper_count(&requests[0]),
    0,
    "expected first request to omit the serialized user-instructions wrapper..."
);
assert_eq!(
    user_instructions_wrapper_count(&requests[1]),
    0,
    "expected second request to keep omitting the serialized user-instructions wrapper..."
);
```

---

## 依赖与外部交互

### 外部依赖
1. **Mock Server**: `wiremock::MockServer`
2. **文件系统**: 创建临时目录和 AGENTS.md 文件

### 操作类型
- `Op::UserTurn`: 带 cwd 参数的用户轮次

---

## 风险、边界与改进建议

### 风险点
1. **指令过时**：cwd 变更后 AGENTS.md 指令可能过时
2. **用户困惑**：用户期望新目录的 AGENTS.md 生效
3. **安全风险**：旧目录的敏感指令可能继续生效

### 边界情况
1. **无 AGENTS.md**：新目录无 AGENTS.md 时的处理
2. **嵌套目录**：嵌套目录结构的 AGENTS.md 加载
3. **符号链接**：符号链接目录的处理

### 改进建议（基于 TODO）
1. **Diff 机制**：比较新旧 AGENTS.md 内容差异
2. **动态更新**：cwd 变更时动态更新 AGENTS 指令
3. **用户提示**：cwd 变更时提示用户 AGENTS.md 变化
4. **配置选项**：允许用户选择是否刷新 AGENTS.md
5. **作用域明确**：明确 AGENTS.md 是会话级还是轮次级

### 相关测试
- `model_visible_layout_turn_overrides`: 轮次覆盖测试
- `model_visible_layout_resume_with_personality_change`: 个性变更测试
