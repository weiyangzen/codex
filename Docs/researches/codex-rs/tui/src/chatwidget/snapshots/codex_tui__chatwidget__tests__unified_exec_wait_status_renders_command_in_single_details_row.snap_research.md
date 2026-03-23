# 研究报告: unified_exec_wait_status_renders_command_in_single_details_row.snap

## 场景与职责

该快照文件验证 **Unified Exec 等待状态**在**窄宽度弹窗**中的命令显示。当终端宽度有限时，长命令需要正确换行或截断显示。

测试场景：
- 启动 Unified Exec，使用长命令
- 发送空交互进入等待
- 在 48 列宽度下渲染弹窗
- 验证命令正确显示在详情行

## 功能点目的

**窄宽度适配**：

1. **信息完整** - 即使宽度有限也显示关键信息
2. **可读性** - 长命令合理换行或截断
3. **布局稳定** - 弹窗布局不因内容长度而混乱
4. **用户体验** - 小窗口也能正常使用

## 具体技术实现

### 测试实现

```rust
// tests.rs:5337-5355
#[tokio::test]
async fn unified_exec_wait_status_renders_command_in_single_details_row_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    // 使用长命令
    begin_unified_exec_startup(
        &mut chat,
        "call-wait-ui",
        "proc-ui",
        "cargo test -p codex-core -- --exact some::very::long::test::name",
    );

    terminal_interaction(&mut chat, "call-wait-ui-stdin", "proc-ui", "");

    // 48 列窄宽度渲染
    let rendered = render_bottom_popup(&chat, 48);
    assert_snapshot!("unified_exec_wait_status_renders_command_in_single_details_row", rendered);
}
```

### 渲染输出

```
• Waiting for background terminal (0s • esc to …
  └ cargo test -p codex-core -- --exact…


› Ask Codex to do anything

  ? for shortcuts            100% context left
```

**解析**：
- 第一行：`Waiting for background terminal` - 状态标题（截断）
- `  └ cargo test -p codex-core -- --exact…` - 命令详情（截断显示 `…`）
- 底部：`Ask Codex to do anything` 和快捷键提示

**注意**：48 列宽度下内容被截断，但关键信息仍可见。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5337-5355 | 窄宽度命令显示测试 |
| `codex-rs/tui/src/wrapping.rs` | - | 文本换行工具 |

## 文本处理

```rust
// 使用 textwrap 进行智能换行
fn wrap_command(command: &str, width: usize) -> Vec<String> {
    textwrap::wrap(command, width)
        .into_iter()
        .map(|s| s.to_string())
        .collect()
}
```

## 风险、边界与改进建议

### 特定风险

1. **信息丢失** - 截断导致关键参数不可见
2. **布局混乱** - 极端窄宽度下布局崩溃
3. **复制困难** - 截断的命令难以复制

### 改进建议

1. **悬停显示** - 鼠标悬停显示完整命令
2. **展开按钮** - 提供展开查看完整命令的选项
3. **智能截断** - 保留命令的关键部分（如子命令）
4. **最小宽度** - 定义弹窗可接受的最小宽度

### 相关测试

- `realtime_audio_selection_popup_narrow` - 窄宽度音频弹窗
