# frame_7.txt 研究文档

## 场景与职责

`frame_7.txt` 是 Codex TUI 应用服务器启动动画的第 7 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 19% 进度点，继续展示标志的动态变化。

## 功能点目的

1. **早期动画推进**：第 7 帧继续推进动画序列的早期展示
2. **视觉节奏维持**：在 480ms 时展示，维持动画的视觉节奏
3. **循环基础**：与前后帧配合构成完整的动画循环

## 具体技术实现

### 时间定位

```
动画时间线（帧 5-9）：

t=320ms  t=400ms  t=480ms  t=560ms  t=640ms  t=720ms
│        │        │        │        │        │
▼        ▼        ▼        ▼        ▼        ▼
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│frame_5│ │frame_6│ │frame_7│ │frame_8│ │frame_9│ │frame_10│
│  [4]  │ │  [5]  │ │  [6]  │ │  [7]  │ │  [8]  │ │  [9]  │
└──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘
 11.1%    13.9%    16.7%    19.4%    22.2%    25.0%

frame_7.txt 显示时机：
- 起始时间：480ms
- 结束时间：560ms
- 持续时间：80ms
- 周期位置：16.7% - 19.4%
```

### 帧索引计算

```rust
// frame_7.txt 的索引为 6（0-based）
fn get_frame_index(elapsed_ms: u128) -> usize {
    let tick_ms = 80u128;
    ((elapsed_ms / tick_ms) % 36) as usize
}

// frame_7 显示条件
assert_eq!(get_frame_index(480), 6);   // 开始
assert_eq!(get_frame_index(520), 6);   // 中间
assert_eq!(get_frame_index(559), 6);   // 结束前
assert_eq!(get_frame_index(560), 7);   // frame_8 开始
```

### 编译时嵌入

```rust
// frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            // ... frame_1 到 frame_6
            include_str!(concat!("../frames/", $dir, "/frame_7.txt")),  // [6]
            // ... frame_8 到 frame_36
        ]
    };
}
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_7.txt` | 1-17 | 第 7 帧 ASCII 艺术内容 |
| `src/frames.rs` | 13 | `include_str!(".../frame_7.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量 |
| `src/ascii_animation.rs` | 74-75 | 帧索引计算 |
| `src/onboarding/welcome.rs` | 82-83 | 帧渲染 |

## 依赖与外部交互

### 与相邻帧的关系

```
帧序列中的位置：

frame_6.txt ──► frame_7.txt ──► frame_8.txt
    [5]            [6]            [7]
   400ms          480ms          560ms

视觉连贯性要求：
- frame_6 → frame_7 应该是自然的视觉过渡
- frame_7 → frame_8 应该保持动画流畅
```

### 与动画系统的集成

```rust
// AsciiAnimation 管理帧序列
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]  // 当 idx == 6 时返回 frame_7.txt
    }
}
```

## 风险、边界与改进建议

### 风险
1. **早期帧重要性**：前几帧建立用户对动画质量的第一印象
2. **循环衔接**：frame_36 到 frame_1 的过渡必须自然

### 边界情况
- **启动延迟**：应用启动慢时用户可能错过前几帧
- **快速切换**：用户可能在 frame_7 显示时切换变体

### 改进建议
1. **首帧优化**：确保早期帧设计精美
2. **启动同步**：动画与应用初始化同步
3. **慢启动模式**：允许前几帧显示更长时间
