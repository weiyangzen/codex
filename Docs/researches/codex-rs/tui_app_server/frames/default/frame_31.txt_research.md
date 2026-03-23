# frame_31.txt 研究文档

## 场景与职责

`frame_31.txt` 是 Codex TUI 应用服务器启动动画的第 31 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 86% 进度点，是动画接近尾声阶段的关键帧。

## 功能点目的

1. **接近结束**：第 31 帧距离动画周期结束还有 6 帧
2. **最后阶段展示**：继续展示动画最后约 14% 阶段的视觉效果
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.48 秒显示

## 具体技术实现

### 帧周期位置

```
36 帧动画的最后阶段：

83%      86%      89%      92%     100%
│        │        │        │        │
30       31       32       33       36
├────────┼────────┼────────┼────────┤
          │
          ▼
      frame_31
      (86.1%)

frame_31 参数：
- 索引：30（0-based）
- 显示时段：[2400ms, 2480ms)
- 周期位置：86.1%
- 距离结束：5 帧（400ms）
```

### 代码集成

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-29] frame_1 到 frame_30
    include_str!("../frames/default/frame_31.txt"),  // [30]
    // [31-35] frame_32 到 frame_36
];

// 变体集合
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // [0] 包含 frame_31.txt
    &FRAMES_CODEX,     // [1]
    &FRAMES_OPENAI,    // [2]
    // ... 其他变体
];
```

### 渲染调用链

```
App::run()
  └── 事件循环
      └── TuiEvent::FrameTick
          └── App::draw(&mut tui)
              └── WelcomeWidget::render_ref()
                  ├── animation.schedule_next_frame()
                  │   └── 调度 frame_32（80ms 后）
                  └── 获取当前帧
                      └── animation.current_frame()
                          └── 当 elapsed_ms 在 [2400, 2480)
                              └── 返回 FRAMES_DEFAULT[30]
                                  └── frame_31.txt 内容
```

## 关键代码路径与文件引用

| 文件 | 行号 | 内容 |
|------|------|------|
| `frames/default/frame_31.txt` | 1-17 | 第 31 帧 ASCII 艺术 |
| `src/frames.rs` | 34 | `include_str!(".../frame_31.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 定义 |
| `src/ascii_animation.rs` | 44-63 | `schedule_next_frame()` 方法 |
| `src/onboarding/welcome.rs` | 71 | `schedule_next_frame()` 调用 |

## 依赖与外部交互

### 与 FrameRateLimiter 的协作

```rust
// frame_rate_limiter.rs
pub(crate) const MAX_FPS: u32 = 120;
pub(crate) const MIN_FRAME_INTERVAL: Duration = 
    Duration::from_nanos(83_333_333);  // ~8.33ms

// frame_31 的调度受限于 MIN_FRAME_INTERVAL
// 确保帧率不超过 120 FPS
```

### 与测试的交互

```rust
// welcome.rs 测试
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT);
    let mut buf = Buffer::empty(area);
    let frame_lines = widget.animation.current_frame().lines().count() as u16;
    (&widget).render(area, &mut buf);
    
    let welcome_row = row_containing(&buf, "Welcome");
    assert_eq!(welcome_row, Some(frame_lines + 1));
}
```

## 风险、边界与改进建议

### 风险
1. **调度累积**：若某帧渲染耗时超过 80ms，可能导致后续帧延迟
2. **内存对齐**：36 个字符串引用可能占用较多栈空间

### 边界情况
- **调度延迟**：系统负载高时，`schedule_next_frame` 可能延迟执行
- **变体边界**：切换变体时，frame_31 可能立即被新变体的对应帧替换

### 改进建议
1. **自适应调度**：根据实际渲染耗时动态调整下一帧调度时间
2. **帧跳过**：若严重延迟，考虑跳过中间帧直接显示当前应显示的帧
3. **性能监控**：记录每帧实际渲染耗时，用于优化
4. **懒渲染**：终端不可见时暂停动画渲染
