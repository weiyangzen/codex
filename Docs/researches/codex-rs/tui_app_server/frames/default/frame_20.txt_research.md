# frame_20.txt 研究文档

## 场景与职责

`frame_20.txt` 是 Codex TUI 应用服务器启动动画的第 20 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 56% 进度点，是动画后半段早期的关键帧。

## 功能点目的

1. **后半段深化**：第 20 帧继续后半段动画的视觉叙事
2. **节奏维持**：保持 80ms 帧间隔的动画节奏
3. **时间定位**：约在动画开始后 1.60 秒显示

## 具体技术实现

### 帧周期分析

```
36 帧动画周期：

前半段（1-18）          后半段（19-36）
├───────────────────────┼───────────────────────┤
      50%                       50%
                   │
                   ▼
              frame_20
             （约 56%）

frame_20 的时间参数：
- 索引：19（0-based）
- 1-based 位置：20/36 = 55.6%
- 显示时段：[1520ms, 1600ms)
- 在周期中的位置：后半段第 2 帧
```

### 数组中的位置

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0] frame_1.txt
    // [1] frame_2.txt
    // ...
    // [17] frame_18.txt (中点)
    // [18] frame_19.txt (后半段开始)
    include_str!("../frames/default/frame_20.txt"),  // [19]
    // [20] frame_21.txt
    // ... 到 frame_36.txt
];
```

### 渲染调用链

```
App::run()
  └── 事件循环
      └── TuiEvent::FrameTick
          └── app.draw(&mut tui)
              └── WelcomeWidget::render_ref()
                  ├── animation.schedule_next_frame()
                  │   └── 计算下一帧延迟（约 80ms 后）
                  └── 获取当前帧
                      └── animation.current_frame()
                          └── 当 elapsed_ms 在 [1520, 1600) 时
                              └── 返回 FRAMES_DEFAULT[19]
                                  └── frame_20.txt 内容
```

## 关键代码路径与文件引用

| 文件 | 行号 | 内容 |
|------|------|------|
| `frames/default/frame_20.txt` | 1-17 | 第 20 帧 ASCII 艺术 |
| `src/frames.rs` | 23 | `include_str!(".../frame_20.txt")` |
| `src/ascii_animation.rs` | 44-63 | `schedule_next_frame()` 方法 |
| `src/ascii_animation.rs` | 65-77 | `current_frame()` 方法 |
| `src/onboarding/welcome.rs` | 82 | 调用 `current_frame()` |

## 依赖与外部交互

### 与 FrameScheduler 的时序

```rust
// FrameScheduler 处理 frame_20 的调度
async fn run(mut self) {
    loop {
        tokio::select! {
            draw_at = self.receiver.recv() => {
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                // 合并多个请求到最早截止时间
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            }
            _ = deadline => {
                // 到达 frame_20 的显示时间点
                if next_deadline.is_some() {
                    next_deadline = None;
                    self.rate_limiter.mark_emitted(target);
                    let _ = self.draw_tx.send(());  // 通知 TUI 重绘
                }
            }
        }
    }
}
```

### 与测试的交互

```rust
// welcome.rs 测试使用测试桩
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(
        false, 
        FrameRequester::test_dummy(),  // 测试用空实现
        true
    );
    // ... 测试渲染
}
```

## 风险、边界与改进建议

### 风险
1. **调度累积**：若某帧渲染耗时超过 80ms，可能导致后续帧延迟
2. **内存对齐**：36 个字符串引用可能占用较多栈空间

### 边界情况
- **调度延迟**：系统负载高时，`schedule_next_frame` 可能延迟执行
- **变体边界**：切换变体时，frame_20 可能立即被新变体的对应帧替换

### 改进建议
1. **自适应调度**：根据实际渲染耗时动态调整下一帧调度时间
2. **帧跳过**：若严重延迟，考虑跳过中间帧直接显示当前应显示的帧
3. **性能监控**：记录每帧实际渲染耗时，用于优化
4. **懒渲染**：终端不可见时暂停动画渲染
