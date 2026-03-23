# frame_3.txt 研究文档

## 场景与职责

`frame_3.txt` 是 Codex TUI 应用服务器启动动画的第 3 帧 ASCII 艺术图像，属于 `default` 动画变体。作为 36 帧循环动画的早期帧，它继续展示标志从初始状态开始的动态变化。

## 功能点目的

1. **早期动画**：第 3 帧是动画序列的早期帧，建立动画的初始节奏
2. **视觉动量**：在 160ms 时展示，继续建立流畅的动画感
3. **循环基础**：与 frame_1、frame_2 和 frame_36 共同构成循环的基础

## 具体技术实现

### 时间定位

```
动画时间线（前 6 帧）：

t=0ms    t=80ms   t=160ms  t=240ms  t=320ms  t=400ms
│        │        │        │        │        │
▼        ▼        ▼        ▼        ▼        ▼
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│frame_1│ │frame_2│ │frame_3│ │frame_4│ │frame_5│ │frame_6│
│  [0]  │ │  [1]  │ │  [2]  │ │  [3]  │ │  [4]  │ │  [5]  │
└──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘
   0%      2.8%     5.6%     8.3%    11.1%    13.9%

frame_3.txt 显示时机：
- 起始时间：160ms
- 结束时间：240ms
- 持续时间：80ms
- 周期位置：5.6% - 8.3%
```

### 帧索引计算

```rust
// frame_3.txt 的索引为 2（0-based）
fn get_frame_index(elapsed_ms: u128) -> usize {
    let tick_ms = 80u128;
    ((elapsed_ms / tick_ms) % 36) as usize
}

// frame_3 显示条件
assert_eq!(get_frame_index(160), 2);   // 开始
assert_eq!(get_frame_index(200), 2);   // 中间
assert_eq!(get_frame_index(239), 2);   // 结束前
assert_eq!(get_frame_index(240), 3);   // frame_4 开始
```

### 编译时嵌入

```rust
// frames.rs
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),  // [0]
            include_str!(concat!("../frames/", $dir, "/frame_2.txt")),  // [1]
            include_str!(concat!("../frames/", $dir, "/frame_3.txt")),  // [2]
            include_str!(concat!("../frames/", $dir, "/frame_4.txt")),  // [3]
            // ... 继续到 frame_36
        ]
    };
}
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_3.txt` | 1-17 | 第 3 帧 ASCII 艺术内容 |
| `src/frames.rs` | 9 | `include_str!(".../frame_3.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量 |
| `src/ascii_animation.rs` | 74-75 | 帧索引计算 |
| `src/onboarding/welcome.rs` | 82-83 | 帧渲染 |

## 依赖与外部交互

### 与 frame_2.txt 和 frame_4.txt 的关系

```
帧序列中的位置：

frame_2.txt ──► frame_3.txt ──► frame_4.txt
    [1]            [2]            [3]
   80ms           160ms          240ms

视觉连贯性要求：
- frame_2 → frame_3 应该是自然的视觉过渡
- frame_3 → frame_4 应该保持动画流畅
- 三帧共同构成动画的早期节奏
```

### 与动画系统的集成

```rust
// AsciiAnimation 管理帧序列
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
    frame_tick: Duration,  // 80ms
    start: Instant,
}

impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();
        let elapsed_ms = self.start.elapsed().as_millis();
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]  // 当 idx == 2 时返回 frame_3.txt
    }
}
```

## 风险、边界与改进建议

### 风险
1. **早期帧重要性**：前几帧建立用户对动画质量的第一印象
2. **循环衔接**：frame_36 到 frame_1 的过渡必须自然

### 边界情况
- **启动延迟**：应用启动慢时用户可能错过前几帧
- **快速切换**：用户可能在 frame_3 显示时切换变体

### 改进建议
1. **首帧优化**：确保 frame_1 到 frame_3 设计精美
2. **启动同步**：动画与应用初始化同步
3. **慢启动模式**：允许前几帧显示更长时间
4. **A/B 测试**：测试不同早期帧设计对用户感知的影响
