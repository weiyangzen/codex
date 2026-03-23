# frame_2.txt 研究文档

## 场景与职责

`frame_2.txt` 是 Codex TUI 应用服务器启动动画的第 2 帧 ASCII 艺术图像，属于 `default` 动画变体。作为 36 帧循环动画的第二帧，它承接 frame_1.txt 的初始状态，继续展示标志的动态变化。

## 功能点目的

1. **动画延续**：作为第 2 帧，承接第 1 帧的初始状态，开始展示动态效果
2. **视觉动量**：在 80ms 的短间隔内（第 1 帧后 80ms），建立动画的流畅感
3. **循环基础**：与 frame_1.txt 和 frame_36.txt 共同构成无缝循环的关键部分

## 具体技术实现

### 时间定位

```
动画时间线（前 5 帧）：

t=0ms       t=80ms      t=160ms     t=240ms     t=320ms
│           │           │           │           │
▼           ▼           ▼           ▼           ▼
┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐
│frame_1│  │frame_2│  │frame_3│  │frame_4│  │frame_5│
│ [0]   │  │ [1]   │  │ [2]   │  │ [3]   │  │ [4]   │
└───────┘  └───────┘  └───────┘  └───────┘  └───────┘
   0%        2.8%       5.6%       8.3%      11.1%

frame_2.txt 显示时机：
- 起始时间：80ms
- 结束时间：160ms
- 持续时间：80ms
- 周期位置：2.8% - 5.6%
```

### 帧索引计算

```rust
// 获取 frame_2.txt 的条件
fn is_frame_2(elapsed_ms: u128) -> bool {
    let tick_ms = 80u128;
    let idx = ((elapsed_ms / tick_ms) % 36) as usize;
    idx == 1  // frame_2.txt 在数组中的索引为 1
}

// 示例
assert!(is_frame_2(80));    // 刚好在 frame_2 开始
assert!(is_frame_2(159));   // frame_2 显示期间
assert!(!is_frame_2(160));  // frame_2 结束，frame_3 开始
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
            // ... 继续到 frame_36
        ]
    };
}
```

## 关键代码路径与文件引用

| 文件 | 行号 | 说明 |
|------|------|------|
| `frames/default/frame_2.txt` | 1-17 | 第 2 帧 ASCII 艺术内容 |
| `src/frames.rs` | 8 | `include_str!(".../frame_2.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 常量 |
| `src/ascii_animation.rs` | 36 | `start: Instant::now()` 动画开始时间 |
| `src/ascii_animation.rs` | 74-75 | 帧索引计算 |

## 依赖与外部交互

### 与 frame_1.txt 的关系

```
循环衔接示意：

frame_36.txt ──► frame_1.txt ──► frame_2.txt ──► frame_3.txt
   [35]            [0]             [1]             [2]
   末尾            开头            第 2 帧         第 3 帧

frame_1.txt 和 frame_2.txt 的关系：
- 时间相邻：frame_1 在 [0, 80)，frame_2 在 [80, 160)
- 视觉连贯：frame_2 应该是 frame_1 的自然延续
- 循环衔接：frame_36 应该能平滑过渡到 frame_1
```

### 与动画系统的集成

```rust
// 动画启动流程
impl AsciiAnimation {
    pub(crate) fn new(request_frame: FrameRequester) -> Self {
        Self::with_variants(request_frame, ALL_VARIANTS, 0)
    }
    
    pub(crate) fn with_variants(
        request_frame: FrameRequester,
        variants: &'static [&'static [&'static str]],
        variant_idx: usize,
    ) -> Self {
        Self {
            request_frame,
            variants,
            variant_idx: variant_idx.min(variants.len() - 1),
            frame_tick: FRAME_TICK_DEFAULT,  // 80ms
            start: Instant::now(),  // 动画开始计时
        }
    }
}
```

## 风险、边界与改进建议

### 风险
1. **初始帧重要性**：frame_1 和 frame_2 是用户首先看到的帧，影响第一印象
2. **循环衔接**：frame_36 到 frame_1 的过渡必须自然，否则循环会显得突兀

### 边界情况
- **启动延迟**：若应用启动耗时超过 80ms，用户可能直接看到 frame_2 或更后的帧
- **快速切换**：用户快速切换变体时，frame_2 可能只显示极短时间

### 改进建议
1. **启动同步**：确保动画与应用初始化同步，避免跳过前几帧
2. **首帧优化**：frame_1 和 frame_2 应设计得尤其精美，建立良好第一印象
3. **慢启动选项**：提供配置让动画从特定帧开始，或延长前几帧的显示时间
4. **A/B 测试**：测试不同 frame_1/frame_2 设计对用户感知启动速度的影响
