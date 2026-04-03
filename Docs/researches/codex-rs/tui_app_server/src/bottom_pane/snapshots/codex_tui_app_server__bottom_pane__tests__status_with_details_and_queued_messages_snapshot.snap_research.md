# status_with_details_and_queued_messages_snapshot 研究文档

## 场景与职责

本快照测试展示了 `BottomPane` 在**状态指示器包含详情行且同时有排队消息**时的渲染行为。验证复杂布局下的正确渲染，包括状态详情、排队消息和 Composer 的共存。

**典型使用场景**：
- 后台任务执行期间显示详细进度信息
- 用户同时排队了后续问题
- 需要展示丰富的状态信息和待处理消息

## 功能点目的

该测试验证以下核心功能：

1. **状态详情显示**：状态指示器支持多行详情文本
2. **详情缩进**：详情行使用树形缩进（`└`）提高可读性
3. **元素共存**：状态（含详情）、排队消息、Composer 同时正确渲染
4. **视觉层次**：清晰的视觉层次：状态标题 → 详情 → 空行 → 排队消息 → Composer

**渲染输出特征**：
```
• Working (0s • esc to interrupt)                <- 状态指示器标题
  └ First detail line                            <- 详情行 1（树形缩进）
    Second detail line                           <- 详情行 2
                                                 <- 空行分隔
• Queued follow-up messages                      <- 排队消息标题
  ↳ Queued follow-up question                    <- 排队消息内容
    ⌥ + ↑ edit last queued message               <- 编辑提示
                                                 <- 空行
› Ask Codex to do anything                       <- Composer 占位符
                                                 <- 空行
  ? for shortcuts            100% context left   <- 底部状态栏
```

## 具体技术实现

### 测试设置
```rust
#[test]
fn status_with_details_and_queued_messages_snapshot() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let mut pane = BottomPane::new(BottomPaneParams {
        app_event_tx: tx,
        frame_requester: FrameRequester::test_dummy(),
        has_input_focus: true,
        enhanced_keys_supported: false,
        placeholder_text: "Ask Codex to do anything".to_string(),
        disable_paste_burst: false,
        animations_enabled: true,
        skills: Some(Vec::new()),
    });

    pane.set_task_running(true);
    pane.update_status(
        "Working".to_string(),
        Some("First detail line\nSecond detail line".to_string()),  // 多行详情
        StatusDetailsCapitalization::CapitalizeFirst,
        STATUS_DETAILS_DEFAULT_MAX_LINES,
    );
    pane.set_pending_input_preview(vec!["Queued follow-up question".to_string()], Vec::new());

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_with_details_and_queued_messages_snapshot", 
                     render_snapshot(&pane, area));
}
```

### 状态详情更新
```rust
pub(crate) fn update_status(
    &mut self,
    header: String,
    details: Option<String>,
    details_capitalization: StatusDetailsCapitalization,
    details_max_lines: usize,
) {
    if let Some(status) = self.status.as_mut() {
        status.update_header(header);
        status.update_details(details, details_capitalization, details_max_lines.max(1));
        self.request_redraw();
    }
}
```

### 详情渲染（StatusIndicatorWidget）
```rust
// 详情行使用树形缩进
"  └ First detail line"   // 第一行使用 └ 符号
"    Second detail line"  // 后续行使用空格缩进
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs` - BottomPane 组件实现
- `codex-rs/tui_app_server/src/status_indicator_widget.rs` - 状态指示器
- `codex-rs/tui_app_server/src/bottom_pane/pending_input_preview.rs` - 排队消息预览

### 关键函数
| 函数 | 行号 | 职责 |
|------|------|------|
| `status_with_details_and_queued_messages_snapshot` (test) | 1523-1553 | 本测试用例 |
| `update_status()` | 635-647 | 更新状态标题和详情 |
| `set_pending_input_preview()` | 815-823 | 设置排队消息 |
| `StatusIndicatorWidget::update_details()` | status_indicator_widget.rs | 更新详情文本 |

### 详情大写选项
```rust
pub enum StatusDetailsCapitalization {
    CapitalizeFirst,  // 首字母大写
    Preserve,         // 保持原样
}
```

## 依赖与外部交互

### 依赖模块
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::status_indicator_widget::StatusDetailsCapitalization` - 详情大写选项
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 排队消息预览

### 详情文本处理
1. 接收原始详情字符串（可能包含 `\n`）
2. 按 `STATUS_DETAILS_DEFAULT_MAX_LINES` 截断
3. 应用 `StatusDetailsCapitalization` 转换
4. 使用树形缩进渲染

## 风险、边界与改进建议

### 当前边界情况
1. **两行详情**：测试使用恰好两行详情文本
2. **首字母大写**：使用 `CapitalizeFirst` 选项
3. **单条排队消息**：仅一条排队消息

### 潜在风险
1. **详情过长**：详情文本可能超出 `STATUS_DETAILS_DEFAULT_MAX_LINES` 限制
2. **高度膨胀**：状态详情 + 排队消息可能导致总高度过高
3. **换行问题**：详情文本中的长单词可能在不合适的位置换行

### 改进建议
1. **详情折叠**：允许用户折叠/展开状态详情
2. **详情滚动**：当详情过多时提供滚动功能
3. **详情历史**：保留最近的详情历史，支持查看之前的进度
4. **智能截断**：在句子边界而非单词边界截断详情
5. **详情动画**：详情更新时添加平滑过渡动画
6. **优先级调整**：当空间不足时，优先显示排队消息而非状态详情
7. **详情格式化**：支持 Markdown 或简单格式化（如粗体、代码块）
