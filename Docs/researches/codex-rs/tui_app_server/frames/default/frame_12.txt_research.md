# frame_12.txt 研究文档

## 场景与职责

`frame_12.txt` 是 Codex TUI 应用服务器启动动画的第 12 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧循环中位于 1/3 进度点，展示标志动画的重要过渡姿态。

## 功能点目的

1. **三分之一里程碑**：在 36 帧循环中位于第 12 帧，是动画的重要时间节点
2. **视觉节奏控制**：配合 80ms 帧间隔，约在动画开始后 960ms 显示
3. **状态展示**：展示 Codex 标志在动画周期中的特定变形状态

## 具体技术实现

### 帧定位计算

```rust
// 计算当前帧索引的数学公式
fn calculate_frame_index(elapsed_ms: u128, tick_ms: u128, total_frames: usize) -> usize {
    ((elapsed_ms / tick_ms) % total_frames as u128) as usize
}

// frame_12.txt 被选中当：
// ((elapsed_ms / 80) % 36) == 11
// 即 elapsed_ms 在 [880, 960) 毫秒区间
```

### 渲染集成

```rust
// welcome.rs: WidgetRef 实现
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 1. 清除区域
        Clear.render(area, buf);
        
        // 2. 安排下一帧（如果动画启用）
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        
        // 3. 检查尺寸是否足够显示动画
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT  // 37
            && layout_area.width >= MIN_ANIMATION_WIDTH;    // 60
        
        // 4. 获取并渲染当前帧
        if show_animation {
            let frame = self.animation.current_frame();  // 可能返回 frame_12.txt
            lines.extend(frame.lines().map(Into::into));
        }
        
        // 5. 渲染欢迎文本
        lines.push(Line::from(vec![...]));
        Paragraph::new(lines).render(area, buf);
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 相关代码 |
|------|---------|---------|
| 帧数据 | `frames/default/frame_12.txt` | ASCII 艺术内容 |
| 帧集合 | `src/frames.rs` | `FRAMES_DEFAULT[11]` |
| 动画控制器 | `src/ascii_animation.rs` | `current_frame()`, `schedule_next_frame()` |
| 渲染器 | `src/onboarding/welcome.rs` | `WidgetRef::render_ref()` |
| 调度器 | `src/tui/frame_requester.rs` | `FrameRequester::schedule_frame_in()` |

## 依赖与外部交互

### 与 TUI 事件循环的集成

```
TUI Event Loop
  ├── AppEvent::FrameTick
  │   └── welcome_widget.render()
  │       └── animation.current_frame() -> frame_12.txt
  └── FrameScheduler
      └── schedule_next_frame_in(80ms)
```

### 测试覆盖

```rust
// welcome.rs 测试
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT);
    let mut buf = Buffer::empty(area);
    let frame_lines = widget.animation.current_frame().lines().count() as u16;
    (&widget).render(area, &mut buf);
    
    // 验证欢迎文本出现在动画帧之后
    let welcome_row = row_containing(&buf, "Welcome");
    assert_eq!(welcome_row, Some(frame_lines + 1));
}
```

## 风险、边界与改进建议

### 风险
1. **静态数组限制**：`FRAMES_DEFAULT` 是固定大小数组 `[&str; 36]`，修改帧数需改动多处代码
2. **编译时嵌入**：所有帧在编译时嵌入，运行时无法热更新

### 边界情况
- **终端缩放**：终端尺寸动态变化时，动画可能突然显示/隐藏
- **焦点丢失**：终端失去焦点时动画继续运行，可能浪费 CPU

### 改进建议
1. **暂停机制**：终端失去焦点时暂停动画以节省资源
2. **帧缓存**：考虑缓存已渲染帧的 ratatui Buffer 以提高性能
3. **可访问性**：为高对比度终端提供简化版 ASCII 艺术选项
