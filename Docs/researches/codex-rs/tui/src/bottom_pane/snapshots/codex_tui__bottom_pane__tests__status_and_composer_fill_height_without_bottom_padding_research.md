# BottomPane - Status and Composer Fill Height Without Bottom Padding Research Document

## 场景与职责

此快照测试验证当状态指示器激活时，底部面板（BottomPane）的布局能够正确填充可用高度，且不会添加不必要的底部填充。这是确保 TUI 界面紧凑、无浪费空间的关键行为。

### 核心场景
- **任务运行中**：`set_task_running(true)` 激活状态指示器
- **精确高度**：使用 `desired_height()` 计算的高度进行渲染
- **预期行为**：状态指示器、间距和编辑器紧密排列，无尾随空白

## 功能点目的

### 1. 紧凑布局
- **目的**：最大化可用空间用于内容显示
- **实现**：`FlexRenderable` 使用 flex 布局，填充可用空间
- **边界**：确保 `desired_height` 计算准确，不多不少

### 2. 高度自适应
- **目的**：根据内容动态计算所需高度
- **实现**：各组件实现 `desired_height()` 方法，父容器累加
- **关键**：状态指示器 + 间距 + 编辑器 = 总高度

### 3. 无底部填充验证
- **目的**：防止不必要的空白行浪费屏幕空间
- **测试方法**：使用精确计算的 `desired_height` 进行渲染，验证无溢出或截断

## 具体技术实现

### 测试代码分析
```rust
#[test]
fn status_and_composer_fill_height_without_bottom_padding() {
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

    // 激活状态指示器（状态视图替换编辑器）
    pane.set_task_running(true);

    // 使用 height == desired_height；期望渲染 spacer + status + composer 行，无尾随填充
    let height = pane.desired_height(30);
    assert!(height >= 3, "expected at least 3 rows to render spacer, status, and composer");
    let area = Rect::new(0, 0, 30, height);
    assert_snapshot!("status_and_composer_fill_height_without_bottom_padding", 
        render_snapshot(&pane, area));
}
```

### 渲染输出分析
```
• Working (0s • esc to interr…                   <- 状态指示器行（第1行）
                                                <- 空行（间距，第2行）
                                                <- 空行（第3行）
› Ask Codex to do anything                      <- 编辑器输入框（第4行）
                                                <- 空行（第5行）
           100% context left                     <- 底部提示栏（第6行）
```

### 布局结构分析
```
总高度 = 6 行
├── 状态指示器区域 (flex: 0) - 1行
├── 间距行 (flex: 0) - 1行  
├── 编辑器区域 (flex: 1) - 包含：
│   ├── 空行（编辑器内部）- 1行
│   ├── 输入框行 - 1行
│   └── 空行（编辑器内部）- 1行
└── 底部提示栏 - 1行
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 相关方法

#### `desired_height()` 实现
```rust
impl Renderable for BottomPane {
    fn desired_height(&self, width: u16) -> u16 {
        self.as_renderable().desired_height(width)
    }
}
```

#### `as_renderable()` 布局逻辑（lines 1130-1174）
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    // ...
    let mut flex = FlexRenderable::new();
    
    // 状态指示器（flex: 0 - 不扩展）
    if let Some(status) = &self.status {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
    }
    
    // unified_exec 摘要（仅在无状态指示器时显示）
    if self.status.is_none() && !self.unified_exec_footer.is_empty() {
        flex.push(/*flex*/ 0, RenderableItem::Borrowed(&self.unified_exec_footer));
    }
    
    // 间距控制（lines 1146-1168）
    let has_pending_thread_approvals = !self.pending_thread_approvals.is_empty();
    let has_pending_input = !self.pending_input_preview.queued_messages.is_empty()
        || !self.pending_input_preview.pending_steers.is_empty();
    let has_status_or_footer = self.status.is_some() || !self.unified_exec_footer.is_empty();
    let has_inline_previews = has_pending_thread_approvals || has_pending_input;
    
    // 条件间距插入
    if has_inline_previews && has_status_or_footer {
        flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
    }
    
    // 待处理线程审批（flex: 1 - 可扩展）
    flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_thread_approvals));
    
    // 待处理输入预览（flex: 1 - 可扩展）
    flex.push(/*flex*/ 1, RenderableItem::Borrowed(&self.pending_input_preview));
    
    // 编辑器（flex: 0 - 固定大小）
    let mut flex2 = FlexRenderable::new();
    flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
    flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
    
    RenderableItem::Owned(Box::new(flex2))
}
```

### 依赖模块
- `crate::render::renderable::FlexRenderable` - 弹性布局容器
- `crate::render::renderable::RenderableItem` - 可渲染项封装

## 依赖与外部交互

### 布局算法
| 组件 | Flex 值 | 行为 |
|------|---------|------|
| StatusIndicator | 0 | 固定高度，不扩展 |
| UnifiedExecFooter | 0 | 固定高度，不扩展 |
| PendingThreadApprovals | 1 | 可扩展，占用剩余空间 |
| PendingInputPreview | 1 | 可扩展，占用剩余空间 |
| ChatComposer | 0 | 固定高度 |

### 间距插入条件
```rust
// 条件1：有内联预览且有状态/页脚时插入间距
if has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件2：有待处理线程审批和待处理输入时插入间距
if has_pending_thread_approvals && has_pending_input {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}

// 条件3：无内联预览但有状态/页脚时插入间距
if !has_inline_previews && has_status_or_footer {
    flex.push(/*flex*/ 0, RenderableItem::Owned("".into()));
}
```

## 风险边界与改进建议

### 潜在风险

1. **高度计算不一致**
   - **风险**：如果子组件的 `desired_height()` 与实际渲染高度不一致，可能导致布局问题
   - **边界**：测试验证了特定宽度（30）下的行为
   - **建议**：在不同宽度下进行测试，验证高度计算的一致性

2. **Flex 布局竞争**
   - **风险**：多个 `flex: 1` 组件可能产生意外的空间分配
   - **边界**：当前测试中 `PendingThreadApprovals` 和 `PendingInputPreview` 都为空
   - **建议**：添加非空情况下的布局测试

3. **间距逻辑复杂性**
   - **风险**：多个条件间距插入逻辑可能导致意外的空行
   - **边界**：当前测试显示有一个空行作为间距
   - **建议**：审查间距逻辑，考虑简化或文档化

### 改进建议

1. **测试增强**
   ```rust
   // 建议添加的测试用例
   #[test]
   fn status_and_composer_different_widths() {
       // 测试不同宽度下的高度计算
       for width in [20, 30, 50, 80, 120] {
           // ...
       }
   }
   
   #[test]
   fn status_and_composer_with_queued_messages() {
       // 测试有队列消息时的布局
       // ...
   }
   ```

2. **文档完善**
   - 在 `as_renderable()` 中添加布局结构图注释
   - 解释每个间距插入条件的业务逻辑

3. **布局优化**
   - 考虑将间距逻辑提取为独立的布局策略
   - 评估是否可以减少条件分支，简化代码

4. **调试支持**
   - 添加布局调试模式，可视化 flex 空间分配
   - 在开发模式下输出高度计算详情
