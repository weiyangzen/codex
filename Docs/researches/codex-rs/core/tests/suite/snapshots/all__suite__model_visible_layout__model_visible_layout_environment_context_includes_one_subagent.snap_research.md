# Research: model_visible_layout_environment_context_includes_one_subagent.snap

## 场景与职责

该快照文件记录了**环境上下文包含单个子代理（Environment Context Includes One Subagent）**场景，验证当有一个子代理活动时，环境上下文的格式。

**测试场景**：验证环境上下文如何展示单个活动子代理的信息。

---

## 功能点目的

1. **子代理信息展示**：定义子代理信息在环境上下文中的格式
2. **单代理场景**：验证单个子代理的正确渲染
3. **格式一致性**：确保环境上下文格式一致

---

## 具体技术实现

### 数据结构

**环境上下文消息**：
```
00:message/user:<ENVIRONMENT_CONTEXT:cwd=<CWD>:subagents=1>
```

### 关键观察

1. **简洁格式**：
   - 使用 `subagents=1` 表示子代理数量
   - 不展开子代理详细信息

2. **格式一致性**：
   - 与多子代理场景使用相同格式
   - 仅数量不同

---

## 关键代码路径与文件引用

### 测试源文件
- **文件**: `codex-rs/core/tests/suite/model_visible_layout.rs`
- **测试函数**: `snapshot_model_visible_layout_environment_context_includes_one_subagent` (行 486-494)
- **快照生成**: 行 487-490

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
    
    let items = vec![json!({
        "type": "message",
        "role": "user",
        "content": [{
            "type": "input_text",
            "text": format!(
                "<environment_context>\n  <cwd>/tmp/example</cwd>\n  <shell>bash</shell>{subagents_block}\n</environment_context>"
            ),
        }],
    })];
    
    context_snapshot::format_response_items_snapshot(items.as_slice(), &context_snapshot_options())
}
```

### 测试调用
```rust
insta::assert_snapshot!(
    "model_visible_layout_environment_context_includes_one_subagent",
    format_environment_context_subagents_snapshot(&["- agent-1: Atlas"])
);
```

---

## 依赖与外部交互

### 外部依赖
1. **insta**: 快照测试框架

### 数据结构
- `subagents`: 子代理列表
- `agent-1`: 代理名称 "Atlas"

---

## 风险、边界与改进建议

### 风险点
1. **格式变更**：环境上下文格式变更可能影响解析
2. **信息不足**：简洁格式可能不包含足够信息
3. **扩展性**：未来扩展时格式可能需要调整

### 边界情况
1. **空子代理列表**：无子代理时的格式
2. **大量子代理**：子代理数量很多时的格式
3. **特殊字符**：子代理名称含特殊字符时的处理

### 改进建议
1. **详细模式**：提供详细模式展示更多子代理信息
2. **可配置格式**：允许配置环境上下文格式
3. **动态更新**：子代理变化时动态更新上下文
4. **交互式查看**：提供交互式方式查看子代理详情

### 相关测试
- `model_visible_layout_environment_context_includes_two_subagents`: 两个子代理场景
