# 研究文档：coalesces_sequential_reads_within_one_call.snap

## 场景与职责

此快照测试验证 Codex TUI 的 `history_cell` 模块中，单个工具调用内的顺序文件读取合并功能。与跨多个调用的合并不同，此测试专注于单个工具调用上下文内的读取优化。

## 功能点目的

1. **单调用内读取合并**：在同一个工具调用中，如果顺序读取多个文件，UI 应该合并这些读取记录
2. **减少视觉噪音**：避免在单个操作下显示过多的文件读取条目
3. **提升用户体验**：让用户快速了解一个操作涉及了哪些文件

## 具体技术实现

### 合并逻辑差异

与跨调用合并的区别：
- **跨调用合并**：检测不同工具调用间的相同文件访问
- **单调用内合并**：在同一个工具调用的执行过程中合并连续的文件读取

### 快照输出格式

```
• Explored
  └ Search shimmer_spans
    Read shimmer.rs
    Read status_indicator_widget.rs
```

注意：在此快照中，文件读取是分开显示的（每行一个），这表明在单调用内合并不总是将所有文件放在同一行，而是根据上下文智能决定。

## 关键代码路径与文件引用

1. **主要实现文件**：
   - `codex-rs/tui/src/history_cell.rs` - 包含读取合并逻辑
   - 具体在 `FileReadCell` 或类似结构的实现中

2. **测试位置**：
   - 测试函数 `coalesces_sequential_reads_within_one_call`
   - 位于 `history_cell.rs` 的 `#[cfg(test)]` 模块

## 依赖与外部交互

### 协议类型
- `codex_protocol::protocol::FileChange` - 文件变更事件
- `codex_protocol::protocol::SessionConfiguredEvent` - 会话配置事件

### 渲染依赖
- `ratatui::text::Line` - 文本行表示
- `ratatui::text::Span` - 文本片段表示

## 风险、边界与改进建议

### 边界情况
1. 读取和写入混合操作时的显示逻辑
2. 大量文件（>100）读取时的性能
3. 嵌套工具调用中的文件读取

### 改进建议
1. 考虑对大量文件读取进行分页或折叠显示
2. 添加文件类型图标，提升可读性
3. 支持点击/快捷键展开查看完整的文件列表
