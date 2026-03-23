# frame_29.txt 研究文档

## 场景与职责

`frame_29.txt` 是 Codex TUI 应用服务器启动动画的第 29 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 81% 进度点，继续展示动画最后阶段的视觉效果。

## 功能点目的

1. **最后阶段动画**：第 29 帧继续动画最后约 19% 阶段的展示
2. **接近循环结束**：距离动画周期结束还有 8 帧
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.32 秒显示

## 具体技术实现

### 帧定位

```
36 帧动画的最后阶段：

75%      81%      86%      92%     100%
│        │        │        │        │
27       29       31       33       36
├────────┼────────┼────────┼────────┤
          │
          ▼
      frame_29
      (80.6%)

frame_29 参数：
- 索引：28（0-based）
- 显示时段：[2240ms, 2320ms)
- 周期位置：80.6%
- 距离结束：7 帧（560ms）
```

### 代码集成

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-27] frame_1 到 frame_28
    include_str!("../frames/default/frame_29.txt"),  // [28]
    // [29-35] frame_30 到 frame_36
];

// 访问 frame_29
const FRAME_29_INDEX: usize = 28;
let frame_29: &str = FRAMES_DEFAULT[FRAME_29_INDEX];
```

### 动画循环结构

```
36 帧动画循环：

┌─────────────────────────────────────────┐
│                                         │
│   frame_1 ──► ... ──► frame_29 ──► ... ──► frame_36
│      │                                 │
│      └─────────────────────────────────┘
│              循环回到 frame_1
│
frame_29 在循环中的位置：
- 前向：frame_30, frame_31, ..., frame_36
- 后向：frame_28, frame_27, ..., frame_1
- 循环：frame_36 之后回到 frame_1
```

## 关键代码路径与文件引用

| 层级 | 文件 | 说明 |
|-----|------|------|
| 数据 | `frames/default/frame_29.txt` | 第 29 帧 ASCII 艺术 |
| 嵌入 | `src/frames.rs:32` | `include_str!(".../frame_29.txt")` |
| 控制 | `src/ascii_animation.rs` | 动画控制 |
| 渲染 | `src/onboarding/welcome.rs` | 欢迎界面 |
| 调度 | `src/tui/frame_requester.rs` | 帧调度 |

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
    │       │       │       └── 调度 frame_30（如果当前是 frame_29）
    │       │       └── animation.current_frame()
    │       │               └── 返回 frame_29.txt（时间匹配时）
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
