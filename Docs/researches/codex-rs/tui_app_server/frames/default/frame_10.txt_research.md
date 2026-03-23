# frame_10.txt 研究文档

## 场景与职责

`frame_10.txt` 是 Codex TUI 应用服务器启动动画的第 10 帧 ASCII 艺术图像，属于 `default` 动画变体的中间帧。该帧展示 Codex 标志在动画序列中的特定姿态，构成 36 帧循环动画的约 28% 进度点。

## 功能点目的

1. **动画连续性**：作为第 10 帧，承接前 9 帧的动画状态，为后续帧提供平滑过渡
2. **视觉节奏**：在 80ms 帧间隔下，此帧约在动画开始后 720ms 显示
3. **循环完整性**：36 帧设计确保动画循环时首尾衔接自然

## 具体技术实现

### 帧数据特征
- **序列位置**：第 10/36 帧（约 28% 进度）
- **显示时机**：动画开始后约 720ms（10 × 80ms）
- **内容特征**：展示 Codex 标志的旋转/变形中间状态

### 帧切换算法

```rust
// ascii_animation.rs: current_frame()
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    if frames.is_empty() {
        return "";
    }
    let tick_ms = self.frame_tick.as_millis();
    if tick_ms == 0 {
        return frames[0];
    }
    let elapsed_ms = self.start.elapsed().as_millis();
    // 第 10 帧在此计算中被选中
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 当 idx == 9 时返回 frame_10.txt
}
```

### 调度机制

```rust
// 安排下一帧重绘
pub(crate) fn schedule_next_frame(&self) {
    let tick_ms = self.frame_tick.as_millis();
    let elapsed_ms = self.start.elapsed().as_millis();
    let rem_ms = elapsed_ms % tick_ms;
    let delay_ms = if rem_ms == 0 { tick_ms } else { tick_ms - rem_ms };
    // 使用 FrameRequester 调度，限制最高 120 FPS
    self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms_u64));
}
```

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/frames/default/frame_10.txt` | 第 10 帧 ASCII 艺术数据 |
| `codex-rs/tui_app_server/src/frames.rs:17` | `include_str!` 嵌入第 10 帧 |
| `codex-rs/tui_app_server/src/ascii_animation.rs:65-77` | 帧索引计算逻辑 |
| `codex-rs/tui_app_server/src/tui/frame_rate_limiter.rs` | 120 FPS 速率限制 |

## 依赖与外部交互

### 时间线依赖
- **前置帧**：frame_1.txt 至 frame_9.txt
- **后置帧**：frame_11.txt 至 frame_36.txt
- **循环衔接**：frame_36.txt 后回到 frame_1.txt

### 渲染依赖
- **FrameRequester**：通过 `schedule_frame_in` 触发重绘
- **FrameRateLimiter**：确保帧率不超过 120 FPS（`MIN_FRAME_INTERVAL = 8.33ms`）

## 风险、边界与改进建议

### 风险
1. **帧顺序敏感**：文件命名必须严格按顺序（frame_1.txt 到 frame_36.txt），否则动画错乱
2. **内容一致性**：所有帧应保持相同尺寸，否则渲染时可能出现闪烁

### 边界情况
- 若动画开始 720ms 后终端尺寸小于最小要求，此帧不会显示
- 用户按 `Ctrl + .` 切换变体时，可能跳过此帧直接显示新变体的对应位置帧

### 改进建议
1. **帧插值**：考虑在帧之间进行平滑插值，减少所需帧数
2. **预加载**：对于慢速 IO 环境，考虑预加载所有帧到内存
3. **帧校验**：添加编译时断言确保所有帧尺寸一致
