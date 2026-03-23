# Research: model_visible_layout_environment_context_includes_two_subagents.snap

## 场景与职责

该快照文件记录了**环境上下文包含两个子代理（Environment Context Includes Two Subagents）**场景，验证当有两个子代理活动时，环境上下文的格式。

**测试场景**：验证环境上下文如何展示多个活动子代理的信息。

---

## 功能点目的

1. **多子代理信息展示**：定义多个子代理信息在环境上下文中的格式
2. **列表渲染**：验证子代理列表的正确渲染
3. **格式一致性**：确保单/多子代理格式一致

---

## 具体技术实现

### 数据结构

**环境上下文消息**：
```
00:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>:subagents=2>
```

### 关键观察

1. **计数格式**：
   - 使用 `subagents=2` 表示子代理数量
   - 简洁的计数方式

2. **与单代理一致**：
   - 使用相同格式
   - 仅数量不同

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_environment_context_includes_two_subagents` (行 496-504)
- **快照生成**: 行 497-501

### 辅助函数
```rust
fn format_environment_context_subagents_snapshot(subagents: &[&str]) -> String {
    let subagents_block = if subagents.is_empty() {
        String::new()
    } else {
        let lines = subagents
            .iter()
            .map(|line| format!("    {line}"))
            .collect::<Vec<_>>()
            .join("\n");
        format!("\n  <subagents>\n{lines}\n  </subagents>")
    };
    // ...
}
```

### 测试调用
```rust
insta::assert_snapshot!(
    "model_visible_layout_environment_context_includes_two_subagents",
    format_environment_context_subagents_snapshot(&["- agent-1: Atlas", "- agent-2: Juniper"])
);
```

---

## 依赖与外部交互

### 外部依赖
1. **insta**: 快照测试框架

### 数据结构
- `agent-1`: 代理名称 "Atlas"
- `agent-2`: 代理名称 "Juniper"

---

## 风险、边界与改进建议

### 风险点
1. **格式限制**：简洁格式可能无法展示复杂信息
2. **排序问题**：多个子代理的排序可能不一致
3. **命名冲突**：子代理名称可能冲突

### 边界情况
1. **大量子代理**：子代理数量很多时的性能
2. **重复名称**：子代理名称重复时的处理
3. **动态变化**：子代理动态增删时的更新

### 改进建议
1. **排序规则**：定义子代理排序规则（如字母序）
2. **唯一标识**：使用唯一标识而非名称
3. **分页显示**：大量子代理时分页显示
4. **实时更新**：子代理变化时实时更新上下文

### 相关测试
- `model_visible_layout_environment_context_includes_one_subagent`: 单个子代理场景
