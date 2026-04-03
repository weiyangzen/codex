# ascii_animation.rs 研究文档

## 场景与职责

`ascii_animation.rs` 是 Codex TUI 的 ASCII 艺术动画驱动模块，负责管理和渲染终端中的 ASCII 动画效果。该模块主要用于：

1. **加载动画**：在 AI 思考、网络请求等待时显示动态 ASCII 艺术
2. **弹窗装饰**：为各种弹窗（popups）和引导界面（onboarding widgets）提供视觉反馈
3. **品牌展示**：显示 Codex/OpenAI 相关的品牌动画

### 核心职责
- 管理多个动画变体（variants）的帧序列
- 控制动画播放时序和帧率
- 提供随机变体切换功能
- 与 TUI 帧调度系统集成

## 功能点目的

### 1. AsciiAnimation 结构体
```rust
pub(crate) struct AsciiAnimation {
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
    frame_tick: Duration,
    start: Instant,
}
```

| 字段 | 类型 | 用途 |
|------|------|------|
| `request_frame` | `FrameRequester` | 向 TUI 事件循环请求重绘的句柄 |
| `variants` | 静态帧数组的切片 | 所有可用的动画变体集合 |
| `variant_idx` | `usize` | 当前活动的变体索引 |
| `frame_tick` | `Duration` | 每帧显示的时长（默认 80ms） |
| `start` | `Instant` | 动画开始时间，用于计算当前帧 |

### 2. 动画变体系统
支持 10 种不同的动画变体（定义在 `frames.rs`）：
- `FRAMES_DEFAULT` - 默认动画
- `FRAMES_CODEX` - Codex 品牌动画
- `FRAMES_OPENAI` - OpenAI 品牌动画
- `FRAMES_BLOCKS` - 方块动画
- `FRAMES_DOTS` - 点阵动画
- `FRAMES_HASH` - 哈希图案动画
- `FRAMES_HBARS` - 水平条动画
- `FRAMES_VBARS` - 垂直条动画
- `FRAMES_SHAPES` - 几何形状动画
- `FRAMES_SLUG` -  slug 图案动画

每个变体包含 36 帧（frame_1.txt 到 frame_36.txt），在编译时通过宏嵌入二进制。

## 具体技术实现

### 关键流程

#### 1. 动画初始化
```rust
pub(crate) fn new(request_frame: FrameRequester) -> Self {
    Self::with_variants(request_frame, ALL_VARIANTS, /*variant_idx*/ 0)
}

pub(crate) fn with_variants(
    request_frame: FrameRequester,
    variants: &'static [&'static [&'static str]],
    variant_idx: usize,
) -> Self {
    assert!(!variants.is_empty(), "AsciiAnimation requires at least one animation variant");
    let clamped_idx = variant_idx.min(variants.len() - 1);
    Self {
        request_frame,
        variants,
        variant_idx: clamped_idx,
        frame_tick: FRAME_TICK_DEFAULT,
        start: Instant::now(),
    }
}
```
- 使用 `assert!` 确保至少有一个变体
- `variant_idx` 被限制在有效范围内（`min` 操作）

#### 2. 帧调度算法
```rust
pub(crate) fn schedule_next_frame(&self) {
    let tick_ms = self.frame_tick.as_millis();
    if tick_ms == 0 {
        self.request_frame.schedule_frame();
        return;
    }
    let elapsed_ms = self.start.elapsed().as_millis();
    let rem_ms = elapsed_ms % tick_ms;
    let delay_ms = if rem_ms == 0 { tick_ms } else { tick_ms - rem_ms };
    if let Ok(delay_ms_u64) = u64::try_from(delay_ms) {
        self.request_frame.schedule_frame_in(Duration::from_millis(delay_ms_u64));
    } else {
        self.request_frame.schedule_frame();
    }
}
```

算法逻辑：
1. 计算已经过去的时间 `elapsed_ms`
2. 计算当前帧剩余时间 `rem_ms = elapsed_ms % tick_ms`
3. 计算下一帧延迟 `delay_ms = tick_ms - rem_ms`
4. 使用 `schedule_frame_in` 精确调度下一帧

这种设计确保动画帧率稳定，即使 UI 有其他延迟也能保持相对准确的时序。

#### 3. 当前帧计算
```rust
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
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]
}
```

使用模运算循环播放帧序列：
- `elapsed_ms / tick_ms` 计算当前应该显示第几帧
- `% frames.len()` 确保循环播放
- 返回静态字符串切片，零拷贝

#### 4. 随机变体切换
```rust
pub(crate) fn pick_random_variant(&mut self) -> bool {
    if self.variants.len() <= 1 {
        return false;
    }
    let mut rng = rand::rng();
    let mut next = self.variant_idx;
    while next == self.variant_idx {
        next = rng.random_range(0..self.variants.len());
    }
    self.variant_idx = next;
    self.request_frame.schedule_frame();
    true
}
```

- 使用 `rand::rng()` 获取线程本地 RNG
- 确保新变体与当前不同（`while next == self.variant_idx`）
- 切换后立即请求重绘

### 数据结构

#### 帧存储（frames.rs）
```rust
macro_rules! frames_for {
    ($dir:literal) => {
        [
            include_str!(concat!("../frames/", $dir, "/frame_1.txt")),
            // ... frame_2.txt 到 frame_36.txt
        ]
    };
}

pub(crate) const FRAMES_DEFAULT: [&str; 36] = frames_for!("default");
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,
    &FRAMES_CODEX,
    // ... 其他变体
];
```

- 使用 `include_str!` 宏在编译时将帧文件嵌入二进制
- 每个变体 36 帧，每帧是一个 ASCII 艺术文本文件
- 静态存储，运行时零分配

#### 默认帧率
```rust
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```
- 80ms 每帧 ≈ 12.5 FPS
- 平衡了流畅度和终端渲染性能

## 关键代码路径与文件引用

### 文件依赖关系

```
ascii_animation.rs
    ↓ 使用
frames.rs
    ↓ 包含（编译时）
frames/*/frame_*.txt (36 files per variant)
    ↓ 使用
FrameRequester (tui/frame_requester.rs)
    ↓ 发送
TuiEvent::Draw (tui.rs)
```

### 主要调用方

| 调用模块 | 用途 |
|---------|------|
| `shimmer.rs` | 闪烁效果的加载指示器 |
| `onboarding/` 目录下的组件 | 新用户引导动画 |
| `popup/` 目录下的组件 | 弹窗装饰动画 |

### 帧文件位置
```
codex-rs/tui_app_server/frames/
├── blocks/
├── codex/
├── default/
├── dots/
├── hash/
├── hbars/
├── openai/
├── shapes/
├── slug/
└── vbars/
    └── frame_1.txt ... frame_36.txt
```

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `rand` | 随机数生成，用于变体切换 |
| `std::time` | 时间测量（Duration, Instant） |

### 内部模块依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `frames` | `frames.rs` | 帧数据定义 |
| `FrameRequester` | `tui/frame_requester.rs` | 帧调度请求 |

### FrameRequester 交互

```rust
// FrameRequester 接口（简化）
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

impl FrameRequester {
    pub fn schedule_frame(&self) { ... }
    pub fn schedule_frame_in(&self, dur: Duration) { ... }
}
```

`AsciiAnimation` 通过 `FrameRequester` 向 TUI 事件循环发送重绘请求，而不是直接渲染。这遵循了 TUI 的"请求-调度"模式，确保：
1. 帧率限制（最高 120 FPS）
2. 多动画实例的帧请求合并
3. 与终端事件循环的正确同步

## 风险、边界与改进建议

### 潜在风险

1. **空变体 panic**：
   ```rust
   assert!(!variants.is_empty(), "...");
   ```
   如果传入空变体数组会 panic。虽然 `new()` 构造函数使用 `ALL_VARIANTS` 是安全的，但 `with_variants` 是 `pub(crate)` 的，调用方可能误用。

2. **时间溢出**：
   ```rust
   let elapsed_ms = self.start.elapsed().as_millis();
   ```
   `Instant` 的 `elapsed()` 在极长时间运行（数年）后可能溢出，但实践中几乎不可能发生。

3. **u64 转换失败**：
   ```rust
   if let Ok(delay_ms_u64) = u64::try_from(delay_ms) { ... }
   ```
   在 128 位平台上 `as_millis()` 返回 `u128`，转换可能失败，但代码已处理（fallback 到立即调度）。

### 边界情况

1. **零帧率**：
   ```rust
   if tick_ms == 0 {
       return frames[0];
   }
   ```
   如果 `frame_tick` 被设置为 0，动画会停留在第一帧。

2. **单变体随机切换**：
   ```rust
   if self.variants.len() <= 1 {
       return false;
   }
   ```
   只有一个变体时，`pick_random_variant` 返回 `false` 表示未切换。

3. **空帧数组**：
   ```rust
   if frames.is_empty() {
       return "";
   }
   ```
   防御性编程，虽然编译时嵌入的帧不应该为空。

### 改进建议

1. **动画暂停/恢复**：
   当前没有暂停功能，可以添加：
   ```rust
   pub(crate) fn pause(&mut self) { ... }
   pub(crate) fn resume(&mut self) { ... }
   ```

2. **可配置帧率**：
   当前帧率是编译时常量，可以改为运行时配置：
   ```rust
   pub(crate) fn set_frame_rate(&mut self, fps: u32) { ... }
   ```

3. **变体预加载**：
   当前所有变体都编译进二进制，可以考虑按需加载以减小编译产物：
   ```rust
   #[cfg(feature = "all-variants")]
   const ALL_VARIANTS: &[&[&str]] = &[...];
   
   #[cfg(not(feature = "all-variants"))]
   const ALL_VARIANTS: &[&[&str]] = &[&FRAMES_DEFAULT];
   ```

4. **动画事件回调**：
   添加帧切换回调，用于同步音频或其他效果：
   ```rust
   pub(crate) fn on_frame_change<F: Fn(usize)>(&mut self, callback: F) { ... }
   ```

5. **测试增强**：
   当前只有一个基本测试：
   ```rust
   #[test]
   fn frame_tick_must_be_nonzero() {
       assert!(FRAME_TICK_DEFAULT.as_millis() > 0);
   }
   ```
   可以增加：
   - 帧索引计算正确性测试
   - 变体切换测试
   - 调度时间计算测试

### 性能考虑

1. **零分配设计**：
   - 所有帧数据是编译时嵌入的静态字符串
   - `current_frame()` 返回 `&'static str`，无堆分配
   - 适合高频调用（每帧一次）

2. **帧调度优化**：
   - 使用 `schedule_frame_in` 精确调度，避免忙等待
   - 与 TUI 的 120 FPS 限制配合，避免过度渲染

3. **内存占用**：
   - 10 变体 × 36 帧 = 360 个 ASCII 艺术文件
   - 每个文件约 1KB，总计约 360KB 静态数据
   - 如果二进制大小敏感，可以考虑压缩或按需加载

### 可访问性考虑

1. **动画可关闭**：
   对于对动画敏感的用户（前庭功能障碍），应该提供关闭动画的选项：
   ```rust
   // 建议添加
   pub(crate) fn disable_animation(&mut self) {
       self.frame_tick = Duration::MAX;
   }
   ```

2. **减少闪烁**：
   ASCII 动画在终端中可能导致屏幕闪烁，建议：
   - 使用双缓冲渲染
   - 考虑提供静态替代方案
