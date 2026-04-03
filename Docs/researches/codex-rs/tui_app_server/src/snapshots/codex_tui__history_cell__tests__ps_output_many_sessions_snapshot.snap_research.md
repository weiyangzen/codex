# 研究文档：ps_output_many_sessions_snapshot.snap

## 场景与职责

此快照测试验证当有大量后台终端会话时 `/ps` 命令的输出显示。这是性能和可用性测试，确保在会话数量很多时 UI 仍能正常工作。

## 功能点目的

1. **大量会话支持**：支持显示大量后台会话
2. **分页/省略**：当会话过多时进行适当的省略
3. **性能保证**：确保大量会话不会导致性能问题

## 具体技术实现

### 快照输出分析

```
/ps

Background terminals

  • command 0
  • command 1
  • command 2
  ...
  • command 15
  • ... and 4 more running
```

关键设计：
- 显示最多 16 个会话（command 0-15）
- 使用 `... and 4 more running` 表示还有更多
- 保持列表的可读性

### 分页逻辑

```rust
const MAX_DISPLAYED_SESSIONS: usize = 16;

fn render_ps_output(sessions: &[Session]) -> Vec<Line> {
    let mut lines = vec![];
    // ... 标题 ...
    
    let display_count = sessions.len().min(MAX_DISPLAYED_SESSIONS);
    for i in 0..display_count {
        lines.push(format_session_line(&sessions[i]));
    }
    
    let remaining = sessions.len() - display_count;
    if remaining > 0 {
        lines.push(Line::from(format!("  • ... and {remaining} more running")));
    }
    
    lines
}
```

## 关键代码路径与文件引用

1. **会话列表渲染**：
   - `codex-rs/tui/src/history_cell.rs`
   - `codex-rs/tui/src/exec_cell.rs`

2. **会话管理**：
   - `codex_core::session`

## 依赖与外部交互

### 性能考虑
- 使用迭代器避免不必要的内存分配
- 限制渲染的会话数量

## 风险、边界与改进建议

### 潜在风险
1. **信息丢失**：用户可能看不到所有会话
2. **选择困难**：大量会话时难以找到特定会话

### 边界情况
1. 正好 16 个会话
2. 会话数量动态变化
3. 会话快速创建和销毁

### 改进建议
1. 添加搜索/过滤功能
2. 支持按状态排序（运行中优先）
3. 添加会话分组功能
4. 考虑使用表格视图，显示更多信息（PID、启动时间等）
