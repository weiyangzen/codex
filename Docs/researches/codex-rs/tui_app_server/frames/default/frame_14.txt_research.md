# frame_14.txt 研究文档

## 场景与职责

`frame_14.txt` 是 Codex TUI 应用服务器启动动画的第 14 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 39% 进度点，是动画前中段的重要过渡帧。

## 功能点目的

1. **动画中段过渡**：第 14 帧标志着动画进入接近中段的位置，视觉元素开始呈现新的姿态
2. **时间节奏**：在 80ms 帧间隔下，约在动画开始后 1.12 秒显示
3. **循环协调**：与前后帧配合维持流畅的循环动画效果

## 具体技术实现

### 帧索引与时间管理

```rust
// 帧索引计算
let total_frames = 36;
let tick_ms = 80;  // FRAME_TICK_DEFAULT
let frame_14_index = 13;  // 0-based 索引

// frame_14.txt 显示的时间窗口
let start_ms = frame_14_index * tick_ms;      // 1040ms
let end_ms = (frame_14_index + 1) * tick_ms;  // 1120ms

// 当前帧计算
let idx = ((elapsed_ms / tick_ms) % total_frames) as usize;
// 当 elapsed_ms 在 [1040, 1120) 区间时，idx == 13，显示 frame_14.txt
```

### 渲染流程详解

```rust
// welcome.rs: WidgetRef 实现
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 清除背景
        Clear.render(area, buf);
        
        // 动画调度
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        
        // 获取布局区域
        let layout_area = self.layout_area.get().unwrap_or(area);
        
        // 尺寸检查
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT  // 37
            && layout_area.width >= MIN_ANIMATION_WIDTH;    // 60
        
        let mut lines: Vec<Line> = Vec::new();
        
        if show_animation {
            // 获取当前帧内容（可能是 frame_14.txt）
            let frame = self.animation.current_frame();
            // 将多行文本转换为 Line 对象
            lines.extend(frame.lines().map(Into::into));
            lines.push("".into());  // 空行分隔
        }
        
        // 添加欢迎文本
        lines.push(Line::from(vec![
            "  ".into(),
            "Welcome to ".into(),
            "Codex".bold(),
            ", OpenAI's command-line coding agent".into(),
        ]));
        
        // 渲染
        Paragraph::new(lines)
            .wrap(Wrap { trim: false })
            .render(area, buf);
    }
}
```

## 关键代码路径与文件引用

| 文件 | 行号范围 | 说明 |
|------|---------|------|
| `frames/default/frame_14.txt` | 1-17 | 第 14 帧 ASCII 艺术内容 |
| `src/frames.rs` | 18 | `include_str!("../frames/default/frame_14.txt")` |
| `src/ascii_animation.rs` | 12-18 | `AsciiAnimation` 结构体定义 |
| `src/ascii_animation.rs` | 65-77 | `current_frame()` 方法 |
| `src/onboarding/welcome.rs` | 23-24 | 最小尺寸常量定义 |
| `src/onboarding/welcome.rs` | 67-96 | `WidgetRef` 渲染实现 |

## 依赖与外部交互

### 与 FrameScheduler 的协作

```
FrameScheduler::run()
  ├── 接收 schedule_frame 请求
  ├── 计算下一帧截止时间（当前时间 + 80ms）
  ├── 应用 FrameRateLimiter（确保间隔 >= 8.33ms）
  └── 发送 draw 通知到 TUI 事件循环
```

### 与测试系统的集成

```rust
// welcome.rs 中的测试
#[test]
fn welcome_skips_animation_below_height_breakpoint() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    // 高度低于 MIN_ANIMATION_HEIGHT - 1 = 36
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT - 1);
    let mut buf = Buffer::empty(area);
    (&widget).render(area, &mut buf);
    
    // 验证欢迎文本直接出现在第 0 行（动画被跳过）
    let welcome_row = row_containing(&buf, "Welcome");
    assert_eq!(welcome_row, Some(0));
}
```

## 风险、边界与改进建议

### 风险
1. **硬编码帧数**：`frames_for!` 宏硬编码 36 帧，添加/删除帧需修改宏
2. **跨平台兼容性**：特殊字符在 Windows CMD 等旧终端可能显示异常

### 边界情况
- **尺寸临界点**：终端高度恰好为 36 时动画被隐藏（< 37）
- **快速切换变体**：连续按 `Ctrl + .` 可能导致动画"跳跃"

### 改进建议
1. **自适应帧率**：根据终端性能动态调整帧率
2. **帧内容校验**：CI 中检查所有帧尺寸一致性
3. **可访问性增强**：支持关闭动画仅显示静态标志
