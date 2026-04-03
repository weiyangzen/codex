# 研究文档：renders_truncated.snap

## 场景与职责

此快照测试验证状态指示器组件在终端宽度不足时的截断显示。当状态文本很长而终端很窄时，应该适当截断。

## 功能点目的

1. **截断显示**：在窄终端上适当截断状态文本
2. **关键信息保留**：保留最重要的状态信息
3. **截断指示**：用 `…` 表示文本被截断

## 具体技术实现

### 快照输出分析

```
"• Working (0s • esc…"
"                    "
```

关键观察：
- `• Working (0s • esc…` - 状态文本被截断
- `…` 表示有更多内容
- 第二行是空的（保留空间）

### 截断逻辑

```rust
fn truncate_status(text: &str, max_width: usize) -> String {
    if text.width() <= max_width {
        text.to_string()
    } else {
        // 预留 1 个字符位置给省略号
        let truncated = truncate_to_width(text, max_width - 1);
        format!("{}…", truncated)
    }
}
```

## 关键代码路径与文件引用

1. **状态指示器**：
   - `codex-rs/tui/src/status_indicator_widget.rs`
   - `codex-rs/tui_app_server/src/status_indicator_widget.rs`

## 依赖与外部交互

### 宽度计算
- `unicode_width::UnicodeWidthStr` - Unicode 字符宽度计算

## 风险、边界与改进建议

### 潜在风险
1. **信息丢失**：截断可能隐藏关键信息
2. **歧义**：截断后的文本可能有歧义

### 边界情况
1. 终端宽度极窄（<10 字符）
2. 状态文本包含多字节字符
3. 状态频繁变化

### 改进建议
1. 优先保留关键信息（如时间）
2. 添加悬停显示完整状态
3. 支持垂直堆叠显示（多行）
4. 添加状态图标减少文字依赖
