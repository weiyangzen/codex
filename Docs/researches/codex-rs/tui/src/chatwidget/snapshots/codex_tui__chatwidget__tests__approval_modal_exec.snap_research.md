# 研究文档: approval_modal_exec.snap

## 场景与职责

该快照文件测试 Codex TUI 中命令执行审批模态框的渲染效果。当 Codex 需要执行 shell 命令时，会弹出此模态框请求用户确认。

## 功能点目的

1. **命令执行审批**: 在执行敏感操作前获取用户明确授权
2. **理由展示**: 显示 AI 生成执行该命令的原因说明
3. **用户决策**: 提供 "Yes, proceed" 和 "No, and tell Codex what to do differently" 两种选项

## 具体技术实现

### 关键流程

```rust
// 触发审批流程
chat.handle_codex_event(Event {
    id: "sub-short".into(),
    msg: EventMsg::ExecApprovalRequest(ExecApprovalRequestEvent {
        call_id: "call-short".into(),
        approval_id: Some("call-short".into()),
        turn_id: "turn-short".into(),
        command: vec!["bash".into(), "-lc".into(), "echo hello world".into()],
        cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
        reason: Some("this is a test reason such as one that would be produced by the model".into()),
        // ... 其他字段
    }),
});
```

### 渲染输出

```
Buffer {
    area: Rect { x: 0, y: 0, width: 80, height: 13 },
    content: [
        "                                                                                ",
        "                                                                                ",
        "  Would you like to run the following command?                                  ",
        "                                                                                ",
        "  Reason: this is a test reason such as one that would be produced by the       ",
        "  model                                                                         ",
        "                                                                                ",
        "  $ echo hello world                                                            ",
        "                                                                                ",
        "› 1. Yes, proceed (y)                                                           ",
        "  2. No, and tell Codex what to do differently (esc)                            ",
        "                                                                                ",
        "  Press enter to confirm or esc to cancel                                       ",
    ],
    styles: [...]
}
```

### 样式应用

- 标题使用 **BOLD** 修饰符
- 原因文本使用 *ITALIC* 样式
- 命令文本使用特定 RGB 颜色 (Rgb(137, 180, 250)) - Catppuccin 主题蓝色
- 选中选项使用 Cyan + Bold 高亮

## 关键代码路径与文件引用

- **测试文件**: `codex-rs/tui/src/chatwidget/tests.rs` (行 3286-3333)
- **渲染方法**: `ChatWidget::render` 方法中的模态框渲染逻辑
- **事件处理**: `handle_codex_event` 处理 `ExecApprovalRequest`
- **底部面板**: `codex-rs/tui/src/bottom_pane/mod.rs` 中的弹窗管理

## 依赖与外部交互

1. **ratatui**: 提供 Buffer、Rect、Style 等渲染原语
2. **codex-protocol**: `ExecApprovalRequestEvent` 事件定义
3. **crossterm**: 键盘事件处理 (KeyCode, KeyModifiers)

## 风险、边界与改进建议

### 风险
- 模态框可能遮挡重要信息
- 用户可能误操作（如按错键）

### 边界情况
- 超长命令的显示截断
- 多行命令的格式化
- 特殊字符的转义显示

### 改进建议
1. 添加命令语法高亮
2. 提供命令预览/ dry-run 选项
3. 支持记住用户选择（对相似命令）
4. 添加命令风险评估等级显示
