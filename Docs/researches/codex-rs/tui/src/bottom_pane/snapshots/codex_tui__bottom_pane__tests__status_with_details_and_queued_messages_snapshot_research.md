# BottomPane - Status with Details and Queued Messages Snapshot Research Document

## 场景与职责

此快照测试验证当任务运行中、状态指示器显示详细信息、且存在队列消息时，BottomPane 的完整布局渲染。这是最复杂的 BottomPane 状态之一，涉及多个信息组件的协调显示。

### 核心场景
- **任务运行中**：`set_task_running(true)` 激活状态指示器
- **详细信息**：`update_status()` 设置多行状态详情
- **队列消息**：`set_pending_input_preview()` 设置待处理的消息队列
- **预期行为**：所有组件正确堆叠，信息层次清晰

## 功能点目的

### 1. 详细状态展示
- **目的**：向用户展示 AI 正在执行的具体操作细节
- **实现**：状态指示器支持多行详情文本
- **格式**：使用树形缩进（`└` 和 `  `）表示层次关系

### 2. 并发信息层次
- **目的**：同时展示当前操作、操作详情和待处理消息
- **层次结构**：
  1. 状态标题（Working）
  2. 状态详情（具体操作）
  3. 队列消息标题
  4. 队列消息内容
  5. 编辑器

### 3. 空间优化
- **目的**：在有限空间内最大化信息密度
- **实现**：使用间距行分隔不同信息组
- **自适应**：根据内容动态调整各区域大小

## 具体技术实现

### 测试代码分析
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
    
    // 设置详细状态信息
    pane.update_status(
        "Working".to_string(),
        Some("First detail line\nSecond detail line".to_string()),  // 多行详情
        StatusDetailsCapitalization::CapitalizeFirst,
        STATUS_DETAILS_DEFAULT_MAX_LINES,
    );
    
    // 设置队列消息
    pane.set_pending_input_preview(
        vec!["Queued follow-up question".to_string()],
        Vec::new()
    );

    let width = 48;
    let height = pane.desired_height(width);
    let area = Rect::new(0, 0, width, height);
    assert_snapshot!("status_with_details_and_queued_messages_snapshot", 
        render_snapshot(&pane, area));
}
```

### 渲染输出分析
```
• Working (0s • esc to interrupt)               <- 状态标题（第1行）
  └ First detail line                            <- 详情第1行（第2行）
    Second detail line                           <- 详情第2行（第3行）
                                                <- 间距行（第4行）
• Queued follow-up messages                      <- 队列标题（第5行）
  ↳ Queued follow-up question                    <- 队列内容（第6行）
    ⌥ + ↑ edit last queued message               <- 编辑提示（第7行）
                                                <- 间距行（第8行）
› Ask Codex to do anything                       <- 编辑器（第9行）
                                                <- 间距行（第10行）
  ? for shortcuts            100% context left   <- 底部提示（第11行）
```

### 布局结构
```
BottomPane (总高度: 11行)
├── 状态指示器区域 (3行)
│   ├── 标题行: "• Working (0s • esc to interrupt)"
│   ├── 详情行1: "  └ First detail line"
│   └── 详情行2: "    Second detail line"
├── 间距行
├── 队列消息区域 (3行)
│   ├── 标题: "• Queued follow-up messages"
│   ├── 内容: "  ↳ Queued follow-up question"
│   └── 提示: "    ⌥ + ↑ edit last queued message"
├── 间距行
├── 编辑器区域 (3行)
│   ├── 内边距
│   ├── 输入框: "› Ask Codex to do anything"
│   └── 内边距
└── 底部提示栏: "? for shortcuts ... 100% context left"
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 状态更新方法（lines 633-648）
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

### 状态指示器详情渲染

#### `StatusIndicatorWidget` 详情处理
```rust
// 详情文本处理
pub fn update_details(
    &mut self,
    details: Option<String>,
    capitalization: StatusDetailsCapitalization,
    max_lines: usize,
) {
    self.details = details.map(|text| {
        let lines: Vec<&str> = text.lines().collect();
        let processed: Vec<String> = lines.iter().enumerate()
            .map(|(i, line)| {
                let indent = if i == 0 { "└ " } else { "  " };
                format!("{}{}", indent, apply_capitalization(line, capitalization))
            })
            .take(max_lines)
            .collect();
        processed.join("\n")
    });
}
```

### 布局条件（lines 1146-1168）
```rust
let has_pending_thread_approvals = !self.pending_thread_approvals.is_empty();  // false
let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()  // true
    || !self.pending_input_preview.pending_steers.is_empty();                   // false
let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();  // true
let has_inline_previews = has_pending_thread_approvals || has_pending_input;  // true

// 条件1: has_inline_previews && has_status_or_footer = true (插入间距)
if has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件2: has_pending_thread_approvals && has_pending_input = false (不插入)
if has_pending_thread_approvals && has_pending_input {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件3: !has_inline_previews && has_status_or_footer = false (不插入)
if !has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}
```

### 依赖模块
- `crate::status_indicator_widget::StatusIndicatorWidget` - 状态指示器
- `crate::status_indicator_widget::StatusDetailsCapitalization` - 详情文本大小写处理
- `crate::bottom_pane::pending_input_preview::PendingInputPreview` - 队列消息预览
- `crate::bottom_pane::STATUS_DETAILS_DEFAULT_MAX_LINES` - 默认最大详情行数

## 依赖与外部交互

### 数据流
```
AI 操作更新
  │
  ├──► update_status(header, details)
  │      │
  │      ├──► status.update_header(header)
  │      └──► status.update_details(details, capitalization, max_lines)
  │             └── 处理多行文本，添加缩进前缀
  │
  ├──► set_pending_input_preview(queued, steers)
  │      └── pending_input_preview.queued_messages = queued
  │
  └──► request_redraw()
         └── 触发完整重新渲染
```

### 详情文本处理
| 输入 | 处理 | 输出 |
|------|------|------|
| `First detail line\nSecond detail line` | 分割行，添加缩进 | `└ First detail line\n  Second detail line` |
| 首行 | 添加 `└ ` 前缀 | 表示详情开始 |
| 后续行 | 添加 `  ` 前缀 | 保持对齐 |

## 风险边界与改进建议

### 潜在风险

1. **详情行数限制**
   - **风险**：`STATUS_DETAILS_DEFAULT_MAX_LINES` 可能截断重要信息
   - **边界**：默认限制为特定值（如 3 或 5）
   - **影响**：用户可能看不到完整的操作详情
   - **建议**：考虑可折叠的详情区域或滚动支持

2. **垂直空间竞争**
   - **风险**：状态详情 + 队列消息 + 编辑器可能在小屏幕上超出可用空间
   - **边界**：当前测试使用 48 宽度，自动计算高度
   - **建议**：添加最小高度测试，验证降级行为

3. **间距累积**
   - **风险**：多个间距插入条件可能产生过多空行
   - **边界**：当前布局有 3 个间距行（状态-队列、队列-编辑器、编辑器-提示）
   - **建议**：评估是否可以减少间距或使其可配置

4. **文本截断**
   - **风险**：长详情行在有限宽度内可能被截断
   - **边界**：当前测试使用短文本
   - **建议**：添加长文本换行/截断测试

### 改进建议

1. **详情区域增强**
   ```rust
   // 建议：支持可折叠详情
   pub struct StatusIndicatorWidget {
       // ...
       details_collapsed: bool,  // 折叠状态
       details_max_lines: usize,
   }
   
   // 用户可按 'd' 键切换详情折叠
   ```

2. **优先级布局**
   ```rust
   // 建议：当空间不足时，按优先级隐藏组件
   enum ComponentPriority {
       Critical,   // 编辑器 - 永不隐藏
       High,       // 状态标题 - 尽量显示
       Medium,     // 队列消息 - 可隐藏
       Low,        // 详情 - 优先隐藏
   }
   ```

3. **测试增强**
   ```rust
   // 建议添加的测试
   #[test]
   fn status_with_long_details() {
       // 测试长详情文本的换行/截断
       pane.update_status(
           "Working",
           Some("Very long detail line that exceeds the width..."),
           ...
       );
   }
   
   #[test]
   fn status_with_many_detail_lines() {
       // 测试超过 max_lines 的详情处理
       pane.update_status(
           "Working",
           Some("Line1\nLine2\nLine3\nLine4\nLine5"),
           ...,
           3,  // max_lines
       );
   }
   ```

4. **视觉优化**
   - 使用不同颜色区分状态详情和队列消息
   - 考虑使用分隔线替代空行间距
   - 添加图标或符号增强可读性

5. **交互增强**
   - 支持点击/快捷键展开/折叠详情
   - 支持队列消息的单独管理（删除、重新排序）
