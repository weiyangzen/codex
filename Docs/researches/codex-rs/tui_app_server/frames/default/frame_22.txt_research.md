# frame_22.txt 研究文档

## 场景与职责

`frame_22.txt` 是 Codex TUI 应用服务器启动动画的第 22 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 61% 进度点，继续后半段的动画展示。

## 功能点目的

1. **动画推进**：第 22 帧推进动画叙事，展示标志的新姿态
2. **视觉连贯**：与前 21 帧保持视觉连贯性
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 1.76 秒显示

## 具体技术实现

### 帧周期中的位置

```
36 帧动画周期（2.88 秒）：

0%    25%    50%    61%    75%    100%
│      │      │      │      │      │
1      9      18     22     27     36
├──────┼──────┼──────┼──────┼──────┤
             │      │
             ▼      ▼
          中点   frame_22
                (61.1%)

frame_22 时间参数：
- 帧索引：21（0-based）
- 显示时段：[1680ms, 1760ms)
- 在周期中位置：后半段第 4 帧
```

### 编译时嵌入

```rust
// frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            // ... frame_1 到 frame_21
            include_str!(concat!("../frames/", $dir, "/frame_22.txt")),  // [21]
            // ... frame_23 到 frame_36
        ]
    };
}

pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
```

### 运行时访问

```rust
// 通过 AsciiAnimation 访问 frame_22
let animation = AsciiAnimation::new(frame_requester);

// 当时间在 [1680, 1760) ms 区间时
let frame = animation.current_frame();
// frame == FRAMES_DEFAULT[21] == include_str!(".../frame_22.txt")
```

## 关键代码路径与文件引用

| 文件路径 | 行号 | 说明 |
|---------|------|------|
| `frames/default/frame_22.txt` | 1-17 | 第 22 帧 ASCII 艺术内容 |
| `src/frames.rs` | 25 | `include_str!(".../frame_22.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量定义 |
| `src/ascii_animation.rs` | 12-18 | `AsciiAnimation` 结构体 |
| `src/ascii_animation.rs` | 98-100 | `frames()` 方法 |

## 依赖与外部交互

### 与所有变体的关系

```rust
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,   // [0] 包含 frame_22.txt
    &FRAMES_CODEX,     // [1] 有自己的 frame_22 等效帧
    &FRAMES_OPENAI,    // [2]
    &FRAMES_BLOCKS,    // [3]
    &FRAMES_DOTS,      // [4]
    &FRAMES_HASH,      // [5]
    &FRAMES_HBARS,     // [6]
    &FRAMES_VBARS,     // [7]
    &FRAMES_SHAPES,    // [8]
    &FRAMES_SLUG,      // [9]
];

// 所有变体都有 36 帧，frame_22 在每个变体中位置相同
```

### 与 FrameRateLimiter 的交互

```rust
// frame_rate_limiter.rs
pub(crate) struct FrameRateLimiter {
    last_emitted: Option<Instant>,
}

impl FrameRateLimiter {
    pub(crate) fn clamp_deadline(&self, requested: Instant) -> Instant {
        if let Some(last) = self.last_emitted {
            let earliest = last + MIN_FRAME_INTERVAL;  // 8.33ms
            // 确保 frame_22 的请求不会被过度限制
            return requested.max(earliest);
        }
        requested
    }
}
```

## 风险、边界与改进建议

### 风险
1. **变体一致性假设**：代码假设所有变体帧数相同，若不一致会导致越界
2. **硬编码帧率**：80ms 帧间隔硬编码，不支持用户自定义

### 边界情况
- **变体切换**：在显示 frame_22 时切换变体，会立即显示新变体的第 22 帧
- **时间回退**：系统时间调整可能影响动画计时

### 改进建议
1. **配置化帧率**：支持从配置文件读取帧间隔
2. **变体验证**：运行时检查所有变体帧数一致性
3. **帧预加载**：考虑预加载所有变体到内存减少切换延迟
4. **动画暂停**：支持用户暂停/恢复动画
