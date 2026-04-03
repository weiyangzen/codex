# BottomPane - Status Hidden When Height Too Small (Height 1) Research Document

## 场景与职责

此快照测试验证当可用高度极小时（仅1行），BottomPane 能够优雅降级，优先保证编辑器输入框的显示，而隐藏状态指示器等次要组件。这是确保 TUI 在极端受限环境下仍保持基本可用性的关键行为。

### 核心场景
- **极端高度限制**：可用高度仅为 1 行
- **任务运行中**：`set_task_running(true)` 理论上应显示状态指示器
- **预期行为**：状态指示器被隐藏，仅显示编辑器输入框的部分内容

## 功能点目的

### 1. 优雅降级
- **目的**：在空间极度受限时保持核心功能可用
- **优先级**：编辑器输入 > 状态指示器 > 队列消息 > 其他
- **实现**：渲染系统根据可用空间自动调整显示内容

### 2. 核心功能保护
- **目的**：确保用户始终能够输入和提交消息
- **边界**：即使只能显示一行，也要保证输入框可见
- **价值**：避免用户完全无法与系统交互的死锁状态

### 3. 空间自适应布局
- **目的**：布局系统能够处理从1行到全屏的各种高度
- **实现**：`FlexRenderable` 根据约束条件分配空间
- **测试**：验证极端情况下的行为

## 具体技术实现

### 测试代码分析
```rust
#[test]
fn status_hidden_when_height_too_small_height_1() {
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

    pane.set_task_running(true);  // 激活任务状态

    // 高度为 1 行 - 状态指示器应被隐藏
    let area1 = Rect::new(0, 0, 20, 1);
    assert_snapshot!("status_hidden_when_height_too_small_height_1", 
        render_snapshot(&pane, area1));
}
```

### 渲染输出分析
```
› Ask Codex to do a
```

### 关键观察
1. **仅显示编辑器**：输出中只有编辑器输入框的内容
2. **状态指示器隐藏**：没有 `• Working` 状态行
3. **内容截断**：由于宽度限制（20字符），占位文本被截断为 `"Ask Codex to do a"`
4. **输入提示符保留**：`›` 前缀显示输入框处于激活状态

### 布局行为推断
```
可用高度: 1 行
├── 理想布局: 状态指示器(1) + 间距(1) + 编辑器(3+) = 5+ 行
├── 实际约束: 仅 1 行可用
└── 降级策略: 隐藏状态指示器，仅渲染编辑器核心部分
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/mod.rs` - BottomPane 实现

### 渲染降级逻辑

#### `as_renderable()` 中的空间分配（lines 1130-1174）
```rust
fn as_renderable(&'_ self) -> RenderableItem<'_> {
    if let Some(view) = self.active_view() {
        // 如果有活动视图（弹窗等），优先显示
        RenderableItem::Borrowed(view)
    } else {
        let mut flex = FlexRenderable::new();
        
        // 状态指示器 (flex: 0 - 固定高度)
        if let Some(status) = &self.status {
            flex.push(/*flex*/ 0, RenderableItem::Borrowed(status));
        }
        
        // ... 其他组件
        
        // 编辑器 (flex: 0 - 固定高度，但在空间不足时可能被截断)
        let mut flex2 = FlexRenderable::new();
        flex2.push(/*flex*/ 1, RenderableItem::Owned(flex.into()));
        flex2.push(/*flex*/ 0, RenderableItem::Borrowed(&self.composer));
        
        RenderableItem::Owned(Box::new(flex2))
    }
}
```

### ChatComposer 的空间处理

#### `render()` 方法（chat_composer.rs）
```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    let [composer_rect, remote_images_rect, textarea_rect, popup_rect] = 
        self.layout_areas(area);
    
    // 如果 area.height 太小，layout_areas 会返回最小可行区域
    // 编辑器核心输入框优先于其他元素
}
```

#### `layout_areas()` 空间分配（chat_composer.rs lines 658-700）
```rust
fn layout_areas(&self, area: Rect) -> [Rect; 4] {
    // 根据可用空间分配区域
    // 优先级: 编辑器 > 弹窗 > 远程图片
    let [composer_rect, popup_rect] =
        Layout::vertical([Constraint::Min(3), popup_constraint]).areas(area);
    
    // 如果空间不足，textarea_rect 可能被压缩
}
```

### 依赖模块
- `ratatui::layout::Layout` - 布局约束系统
- `ratatui::layout::Constraint` - 空间约束定义
- `crate::render::renderable::FlexRenderable` - 弹性布局容器

## 依赖与外部交互

### 约束系统
| 约束类型 | 行为 | 在高度1时的表现 |
|----------|------|-----------------|
| `Constraint::Min(n)` | 最小 n 行，可扩展 | 尝试分配 n 行，但可能被强制压缩 |
| `Constraint::Max(n)` | 最大 n 行 | 限制为 n 行或更少 |
| `Constraint::Length(n)` | 固定 n 行 | 强制 n 行，可能溢出 |
| `Constraint::Fill(n)` | 填充剩余空间 | 分配 0 行（无剩余空间） |

### 降级优先级
```
1. 活动视图/弹窗（最高优先级）
2. 编辑器核心输入框
3. 编辑器底部提示栏
4. 状态指示器
5. 队列消息预览
6. unified_exec 摘要
```

## 风险边界与改进建议

### 潜在风险

1. **信息丢失**
   - **风险**：用户无法知道任务是否正在运行
   - **边界**：高度为1时状态指示器完全隐藏
   - **影响**：用户可能重复提交或困惑于系统无响应
   - **建议**：考虑在输入框中嵌入最小化状态指示（如改变前缀符号）

2. **输入框截断**
   - **风险**：占位文本截断可能导致用户困惑
   - **边界**：当前显示 `› Ask Codex to do a` 而非完整文本
   - **建议**：为极小宽度提供短占位文本变体

3. **光标位置问题**
   - **风险**：极端压缩可能导致光标位置计算错误
   - **边界**：需要验证光标在1行高度时的行为
   - **建议**：添加光标位置测试

4. **键盘交互**
   - **风险**：某些快捷键提示可能不可见
   - **边界**：底部提示栏在高度1时无法显示
   - **建议**：确保核心功能（如 Enter 提交）无需提示即可工作

### 改进建议

1. **最小状态指示**
   ```rust
   // 建议：在输入框前缀中嵌入状态
   正常: "› "
   运行中: "•› " 或 "⏵› "
   等待输入: "⏸› "
   ```

2. **动态占位文本**
   ```rust
   fn placeholder_for_dimensions(width: u16, height: u16) -> &'static str {
       match (width, height) {
           (0..=20, _) => "Ask...",      // 极窄
           (21..=40, 1) => "Ask Codex",  // 高度为1
           _ => "Ask Codex to do anything",
       }
   }
   ```

3. **测试增强**
   ```rust
   // 建议添加的测试
   #[test]
   fn status_hidden_height_2() {
       // 验证高度为2时的行为
   }
   
   #[test]
   fn status_hidden_width_10() {
       // 验证极窄宽度下的行为
   }
   
   #[test]
   fn cursor_position_extreme_dimensions() {
       // 验证极端尺寸下的光标位置
   }
   ```

4. **文档和提示**
   - 在文档中说明最小支持尺寸
   - 考虑在启动时检测终端尺寸并给出警告

5. **替代输出模式**
   - 当检测到极小时，考虑切换到替代 UI 模式
   - 例如：简化状态行，合并多个信息源
