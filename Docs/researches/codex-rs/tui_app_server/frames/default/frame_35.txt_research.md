# frame_35.txt 研究文档

## 场景与职责

`frame_35.txt` 是 Codex TUI 应用服务器启动动画的第 35 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 97% 进度点，是动画即将结束的关键帧，下一帧将循环回到开头。

## 功能点目的

1. **循环前最后一帧**：第 35 帧是循环回到 frame_1 之前的最后一帧
2. **最后阶段展示**：展示动画最后约 3% 阶段的视觉效果
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.80 秒显示

## 具体技术实现

### 帧周期位置

```
36 帧动画的循环边界：

94%      97%     100%      0%       3%
│        │        │        │        │
34       35       36        1        2
├────────┼────────┼────────┼────────┤
          │        │
          ▼        ▼
      frame_35  frame_36
      (97.2%)   (100%)

frame_35 参数：
- 索引：34（0-based）
- 显示时段：[2720ms, 2800ms)
- 周期位置：97.2%
- 距离结束：1 帧（80ms）
- 下一帧：frame_36（最后一帧）
```

### 代码集成

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-33] frame_1 到 frame_34
    include_str!("../frames/default/frame_35.txt"),  // [34]
    // [35] frame_36
];

// 循环回到 frame_1 的逻辑
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 当 elapsed_ms = 2880 时（frame_36 结束）：
        // (2880 / 80) % 36 = 36 % 36 = 0 -> frame_1
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        
        frames[idx]
    }
}
```

### 循环衔接

```
frame_35.txt ──► frame_36.txt ──► frame_1.txt
    [34]            [35]            [0]
   2720ms          2800ms          2880ms
                              (循环回到起点)

循环衔接要求：
- frame_36 应该能平滑过渡到 frame_1
- 视觉上应该形成无缝循环
- 时间上是连续的（2880ms 后回到 0ms 状态）
```

## 关键代码路径与文件引用

| 层级 | 文件 | 说明 |
|-----|------|------|
| 数据 | `frames/default/frame_35.txt` | 第 35 帧 ASCII 艺术 |
| 嵌入 | `src/frames.rs:38` | `include_str!(".../frame_35.txt")` |
| 控制 | `src/ascii_animation.rs` | 动画控制 |
| 渲染 | `src/onboarding/welcome.rs` | 欢迎界面 |
| 调度 | `src/tui/frame_requester.rs` | 帧调度器 |

## 依赖与外部交互

### 与 FrameRequester 的交互

```rust
#[derive(Clone, Debug)]
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    pub fn schedule_frame(&self) {
        let _ = self.frame_schedule_tx.send(Instant::now());
    }
    
    pub fn schedule_frame_in(&self, dur: Duration) {
        let _ = self.frame_schedule_tx.send(Instant::now() + dur);
    }
}
```

### 与 TUI 事件循环的集成

```
TUI Event Loop
    │
    ├── 接收 FrameScheduler 的绘制通知
    │       │
    │       ▼
    ├── App::draw()
    │       │
    │       ├── WelcomeWidget::render_ref()
    │       │       ├── animation.schedule_next_frame()
    │       │       │       └── 调度 frame_36（如果当前是 frame_35）
    │       │       └── animation.current_frame()
    │       │               └── 返回 frame_35.txt（时间匹配时）
    │       │
    │       └── 其他 widgets 渲染
    │
    └── 继续事件循环
```

## 风险、边界与改进建议

### 风险
1. **mpsc 通道关闭**：若 FrameScheduler 任务 panic，通道关闭后所有调度失败
2. **广播通道溢出**：`broadcast::channel(16)` 可能溢出

### 边界情况
- **立即调度**：`schedule_frame()` 发送 `Instant::now()`，可能立即触发
- **延迟调度**：`schedule_frame_in()` 发送未来时间点

### 改进建议
1. **错误处理**：处理 `frame_schedule_tx.send()` 失败的情况
2. **背压机制**：当渲染跟不上时自动降低帧率
3. **帧跳过**：严重延迟时跳过中间帧
4. **性能分析**：记录每帧从调度到渲染的延迟
