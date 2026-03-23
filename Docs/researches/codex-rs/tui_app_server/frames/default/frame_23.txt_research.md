# frame_23.txt 研究文档

## 场景与职责

`frame_23.txt` 是 Codex TUI 应用服务器启动动画的第 23 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 64% 进度点，继续展示后半段的动画效果。

## 功能点目的

1. **动画延续**：第 23 帧继续后半段动画的视觉展示
2. **接近尾声**：距离动画结束（frame_36）还有 14 帧
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 1.84 秒显示

## 具体技术实现

### 帧时间线

```
36 帧动画的后半段时间线：

frame_19  frame_20  frame_21  frame_22  frame_23  ...  frame_36
  53%       56%       58%       61%       64%    ...    100%
 1440ms    1520ms    1600ms    1680ms    1760ms  ...   2800ms
    │         │         │         │         │           │
    └─────────┴─────────┴─────────┼─────────┴───────────┘
                                  │
                              frame_23
                            （本文件位置）

frame_23 参数：
- 索引：22（0-based）
- 显示时段：[1760ms, 1840ms)
- 距离周期结束：约 1.04 秒（13 帧 × 80ms）
```

### 代码中的定义

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-21] frame_1 到 frame_22
    include_str!("../frames/default/frame_23.txt"),  // [22]
    // [23-35] frame_24 到 frame_36
];

// 变体切换时保持帧位置
impl AsciiAnimation {
    pub(crate) fn pick_random_variant(&mut self) -> bool {
        // 切换变体但保持当前帧索引
        // 如在 frame_23 时切换，新变体也显示其第 23 帧
        self.variant_idx = new_idx;
        self.request_frame.schedule_frame();
        true
    }
}
```

### 渲染流程

```rust
// welcome.rs
impl WidgetRef for &WelcomeWidget {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 清除区域
        Clear.render(area, buf);
        
        // 安排下一帧
        if self.animations_enabled {
            self.animation.schedule_next_frame();
        }
        
        // 检查尺寸
        let show_animation = self.animations_enabled
            && layout_area.height >= MIN_ANIMATION_HEIGHT
            && layout_area.width >= MIN_ANIMATION_WIDTH;
        
        let mut lines: Vec<Line> = Vec::new();
        
        if show_animation {
            // 获取当前帧（可能是 frame_23.txt）
            let frame = self.animation.current_frame();
            lines.extend(frame.lines().map(Into::into));
            lines.push("".into());
        }
        
        // 添加欢迎文本并渲染
        lines.push(/* welcome text */);
        Paragraph::new(lines).render(area, buf);
    }
}
```

## 关键代码路径与文件引用

| 层级 | 文件 | 说明 |
|-----|------|------|
| 数据 | `frames/default/frame_23.txt` | 第 23 帧 ASCII 艺术 |
| 嵌入 | `src/frames.rs:26` | `include_str!(".../frame_23.txt")` |
| 控制 | `src/ascii_animation.rs` | 动画控制逻辑 |
| 渲染 | `src/onboarding/welcome.rs` | 欢迎界面渲染 |
| 调度 | `src/tui/frame_requester.rs` | 帧调度 |

## 依赖与外部交互

### 与测试系统的集成

```rust
// welcome.rs 测试
#[test]
fn ctrl_dot_changes_animation_variant() {
    let mut widget = WelcomeWidget {
        is_logged_in: false,
        animation: AsciiAnimation::with_variants(
            FrameRequester::test_dummy(), 
            &VARIANTS, 
            0
        ),
        animations_enabled: true,
        layout_area: Cell::new(None),
    };
    
    let before = widget.animation.current_frame();
    widget.handle_key_event(KeyEvent::new(
        KeyCode::Char('.'), 
        KeyModifiers::CONTROL
    ));
    let after = widget.animation.current_frame();
    
    assert_ne!(before, after, "expected ctrl+. to switch variant");
}
```

### 与 FrameScheduler 的协作

```
FrameScheduler 状态机：

Idle ──► Receiving ──► Scheduled ──► Emitting ──► Idle
           ▲                              │
           └──────────────────────────────┘

frame_23 的调度：
1. WelcomeWidget::render_ref() 调用 schedule_next_frame()
2. 计算 frame_24 的显示时间（当前时间 + 80ms）
3. FrameScheduler 接收请求并更新 deadline
4. 到达 deadline 后发送 draw 通知
```

## 风险、边界与改进建议

### 风险
1. **资源泄漏**：长时间运行的动画可能累积未处理的调度请求
2. **终端兼容性**：某些终端对 12.5 FPS（80ms 间隔）的刷新率支持不佳

### 边界情况
- **循环边界**：frame_36 到 frame_1 的过渡需要特别平滑
- **多显示器**：终端在显示器间移动时可能影响渲染

### 改进建议
1. **请求去重**：确保同一帧不会被调度多次
2. **终端检测**：根据终端类型调整刷新率
3. **节能模式**：笔记本电池模式下降低动画帧率
4. **帧统计**：收集帧渲染时间统计用于优化
