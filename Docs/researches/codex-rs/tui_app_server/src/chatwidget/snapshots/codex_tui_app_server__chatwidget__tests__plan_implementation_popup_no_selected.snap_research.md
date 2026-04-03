# 计划实现弹出框无选中测试研究文档

## 场景与职责

该 snapshot 测试验证 tui_app_server 的 ChatWidget 在计划实现确认弹出框中，当用户导航到 "No" 选项时，UI 能够正确显示未选中状态。

**测试场景**：
1. 用户当前处于 Plan（计划）协作模式
2. 使用 gpt-5 模型
3. AI 完成了计划制定，显示确认弹出框
4. 用户按 Down 键导航到 "No, stay in Plan mode" 选项

**职责**：确保用户可以在两个选项间自由导航，清晰看到当前选中的是哪个选项，提供直观的键盘导航体验。

## 功能点目的

- **键盘导航支持**：支持使用方向键在选项间导航
- **视觉反馈**：清晰显示当前选中的选项
- **用户选择尊重**：允许用户选择继续留在计划模式
- **确认前预览**：在确认前可以看到自己的选择

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 2479-2486 行

```rust
#[tokio::test]
async fn plan_implementation_popup_no_selected_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(Some("gpt-5")).await;
    chat.open_plan_implementation_prompt();
    chat.handle_key_event(KeyEvent::from(KeyCode::Down));

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("plan_implementation_popup_no_selected", popup);
}
```

### 关键实现细节

1. **初始化 ChatWidget**：
   - 使用 `make_chatwidget_manual` 创建测试实例
   - 指定当前模型为 gpt-5

2. **打开计划实现提示**：
   - 调用 `open_plan_implementation_prompt()` 触发确认对话框
   - 默认选中第一个选项（"Yes"）

3. **键盘导航**：
   - 发送 Down 键事件 (`KeyCode::Down`)
   - 导航到第二个选项（"No"）

4. **渲染捕获**：
   - 使用 `render_bottom_popup` 在 80 列宽度下渲染弹出框内容
   - 捕获并验证 UI 输出，验证选中指示器（`›`）正确显示

### Snapshot 输出内容

```
Implement this plan?

  1. Yes, implement this plan  Switch to Default and start coding.
› 2. No, stay in Plan mode     Continue planning with the model.

Press enter to confirm or esc to go back
```

与默认状态（plan_implementation_popup）的区别：
- **默认状态**：`›` 在第一个选项前（Yes）
- **此状态**：`›` 在第二个选项前（No）

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`plan_implementation_popup_no_selected_snapshot` (第 2479 行)
   - 相关测试：`plan_implementation_popup_snapshot` (第 2470 行)

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`open_plan_implementation_prompt`
   - 键盘事件处理：`handle_key_event`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 选择列表渲染
   - 键盘导航处理

4. **选择视图**：`codex-rs/tui_app_server/src/bottom_pane/selection_view.rs`（假设位置）
   - 选项列表管理
   - 选中状态管理

### 键盘导航实现

```rust
// 伪代码示意
match key_code {
    KeyCode::Down => {
        // 移动到下一个可用选项
        self.selected_index = self.next_enabled_index();
    }
    KeyCode::Up => {
        // 移动到上一个可用选项
        self.selected_index = self.prev_enabled_index();
    }
    KeyCode::Enter => {
        // 确认当前选择
        self.confirm_selection();
    }
    KeyCode::Esc => {
        // 取消/关闭弹出框
        self.close();
    }
    // ...
}
```

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，处理键盘事件 |
| `BottomPane` | 渲染选择弹出框 |
| `SelectionView` | 管理选项列表和选中状态 |
| `KeyEvent` | 键盘事件处理 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `crossterm`：终端输入处理（KeyEvent, KeyCode）
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 键盘事件流

1. 用户按 Down 键
2. `crossterm` 捕获键盘事件
3. `ChatWidget::handle_key_event` 接收事件
4. 如果当前有弹出框，转发给 `BottomPane` 处理
5. `SelectionView` 更新选中索引
6. UI 重新渲染，更新选中指示器位置

## 风险、边界与改进建议

### 潜在风险

1. **导航循环**：用户可能期望在最后一个选项按 Down 键回到第一个选项（循环导航）
2. **禁用选项**：如果某些选项被禁用，导航应该跳过它们
3. **快捷键冲突**：数字快捷键（如按 "1" 选择第一个选项）可能与导航键冲突

### 边界情况

1. **单选项**：如果只有一个选项，导航应该正确处理
2. **所有选项禁用**：极端情况下所有选项都被禁用时的处理
3. **快速按键**：用户快速连续按键时的防抖处理

### 改进建议

1. **循环导航**：在最后一个选项按 Down 键回到第一个选项
2. **数字快捷键**：支持按数字键直接选择对应选项
3. **搜索过滤**：选项较多时支持搜索过滤
4. **悬停提示**：鼠标悬停时显示选项的详细说明
5. **动画效果**：选项切换时添加平滑的动画效果

### 相关测试

- `plan_implementation_popup_snapshot`：默认选中状态测试
- `plan_implementation_popup_yes_emits_submit_message_event`：确认选择测试
- `approvals_popup_navigation_skips_disabled`：禁用选项导航测试
- 其他键盘导航相关测试

### UI/UX 考虑

1. **选中指示器**：使用 `›` 字符作为选中指示器，清晰且与终端风格一致
2. **对比度**：确保选中项与未选中项有足够的视觉对比
3. **键盘可访问性**：所有功能都应可通过键盘访问
4. **屏幕阅读器**：考虑为视障用户提供屏幕阅读器支持
