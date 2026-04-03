# 研究文档：ps_output_long_command_snapshot.snap

## 场景与职责

此快照测试验证 `/ps` 命令输出中长命令的截断显示。当后台会话的命令很长时，需要适当截断以保持 UI 整洁。

## 功能点目的

1. **长命令截断**：防止过长的命令占用过多空间
2. **状态指示**：显示会话的当前状态（如 "searching..."）
3. **可读性**：即使截断也要保持可识别性

## 具体技术实现

### 快照输出分析

```
/ps

Background terminals

  • rg "foo" src --glob '**/*. [...]
    ↳ searching...
```

关键元素：
- 命令被截断，显示 `[...]` 表示省略
- `↳` 符号指向会话状态
- `searching...` 表示会话正在运行

### 截断逻辑

```rust
fn truncate_command(command: &str, max_width: usize) -> String {
    if command.width() > max_width {
        format!("{} [...]", &command[..max_width - 5])
    } else {
        command.to_string()
    }
}
```

## 关键代码路径与文件引用

1. **命令截断**：
   - `crate::text_formatting::truncate_text`
   - `codex-rs/tui/src/text_formatting.rs`

2. **PS 显示**：
   - `codex-rs/tui/src/history_cell.rs`

## 依赖与外部交互

### 相关常量
- 最大显示宽度常量

## 风险、边界与改进建议

### 潜在风险
1. **截断位置不当**：可能在关键参数处截断
2. **无法识别**：截断后可能无法区分相似命令

### 改进建议
1. 智能截断，优先保留命令名和关键参数
2. 添加悬停/点击显示完整命令的功能
3. 支持水平滚动查看完整命令
