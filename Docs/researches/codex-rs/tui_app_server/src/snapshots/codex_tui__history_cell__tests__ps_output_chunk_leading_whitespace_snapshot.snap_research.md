# 研究文档：ps_output_chunk_leading_whitespace_snapshot.snap

## 场景与职责

此快照测试验证 `/ps` 命令输出中前导空白字符的处理。`/ps` 命令显示后台终端会话列表，此测试确保输出中的缩进空白被正确保留和显示。

## 功能点目的

1. **保留前导空白**：命令输出中的前导空格和制表符应该被保留
2. **缩进层次显示**：正确显示嵌套或缩进的输出内容
3. **格式化输出**：保持原始输出的格式和结构

## 具体技术实现

### 快照输出分析

```
/ps

Background terminals

  • just fix
    ↳   indented first
          more indented
```

关键观察：
- `/ps` - 命令本身
- `Background terminals` - 标题
- `• just fix` - 会话条目
- `↳   indented first` - 输出内容，保留前导空格
- `      more indented` - 更多缩进

### 空白处理逻辑

```rust
// 在显示输出时保留前导空白
fn format_output_line(line: &str) -> Line {
    // 不 trim 前导空白，保留原始格式
    Line::from(line.to_string())
}
```

## 关键代码路径与文件引用

1. **PS 命令处理**：
   - `codex-rs/tui/src/exec_cell.rs` - 命令输出处理
   - `codex-rs/tui/src/history_cell.rs` - 历史记录显示

2. **会话管理**：
   - `codex_core::session` - 会话管理

## 依赖与外部交互

### 相关类型
- `CommandOutput` - 命令输出结构
- `OutputLinesParams` - 输出行参数

## 风险、边界与改进建议

### 潜在风险
1. **空白字符可视化**：用户可能无法区分空格和制表符
2. **过度缩进**：非常深的缩进可能导致内容被推出可视区域

### 边界情况
1. 全空白行
2. 混合使用空格和制表符
3. 极长的缩进（>100 字符）

### 改进建议
1. 考虑将制表符转换为可见数量的空格
2. 添加选项显示/隐藏空白字符
3. 对过深的缩进进行限制或警告
