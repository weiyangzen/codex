# frame_25.txt 研究文档

## 场景与职责

`frame_25.txt` 是 Codex TUI 应用服务器启动动画的第 25 帧 ASCII 艺术图像，属于 `default` 动画变体。在 36 帧动画循环中位于约 69% 进度点，继续展示动画后半段的视觉效果。

## 功能点目的

1. **动画推进**：第 25 帧继续推进动画叙事，展示标志的新姿态
2. **接近循环结束**：距离动画周期结束还有 12 帧
3. **时间定位**：在 80ms 帧间隔下，约在动画开始后 2.00 秒显示

## 具体技术实现

### 帧周期分析

```
36 帧动画周期：

0%      25%      50%      69%      75%     100%
│        │        │        │        │        │
1        9       18       25       27       36
├────────┼────────┼────────┼────────┼────────┤
                   │        │
                   ▼        ▼
                中点    frame_25
                       (69.4%)

frame_25 时间参数：
- 帧索引：24（0-based）
- 显示时段：[1920ms, 2000ms)
- 周期位置：约 69.4%
- 距离结束：11 帧（880ms）
```

### 代码中的位置

```rust
// frames.rs
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    // [0-23] frame_1 到 frame_24
    include_str!("../frames/default/frame_25.txt"),  // [24]
    // [25-35] frame_26 到 frame_36
];

// ALL_VARIANTS 中的位置
pub(crate) const ALL_VARIANTS: &[&[&str]] = &[
    &FRAMES_DEFAULT,  // [0] - 包含 frame_25.txt
    // ... 其他 9 个变体
];
```

### 渲染调用链

```
App::run() 主循环
    └── 处理 TuiEvent::FrameTick
        └── App::draw(&mut tui)
            └── 遍历所有 widget
                └── WelcomeWidget::render_ref(area, buf)
                    ├── Clear.render(area, buf)
                    ├── animation.schedule_next_frame()
                    │   └── FrameRequester::schedule_frame_in(80ms)
                    └── let frame = animation.current_frame()
                        └── 当 elapsed_ms ∈ [1920, 2000)
                            └── 返回 FRAMES_DEFAULT[24]
                                └── frame_25.txt 内容
```

## 关键代码路径与文件引用

| 文件 | 行号 | 内容 |
|------|------|------|
| `frames/default/frame_25.txt` | 1-17 | 第 25 帧 ASCII 艺术 |
| `src/frames.rs` | 28 | `include_str!(".../frame_25.txt")` |
| `src/frames.rs` | 47 | `FRAMES_DEFAULT` 定义 |
| `src/ascii_animation.rs` | 44-63 | `schedule_next_frame()` |
| `src/onboarding/welcome.rs` | 71 | `schedule_next_frame()` 调用 |

## 依赖与外部交互

### 与 FrameRateLimiter 的协作

```rust
// frame_rate_limiter.rs
pub(crate) const MAX_FPS: u32 = 120;
pub(crate) const MIN_FRAME_INTERVAL: Duration = 
    Duration::from_nanos(83_333_333);  // ~8.33ms

// frame_25 的调度受限于 MIN_FRAME_INTERVAL
// 即使请求更频繁，实际帧率也不会超过 120 FPS
```

### 与测试的交互

```rust
// ascii_animation.rs 测试
#[test]
fn frame_tick_must_be_nonzero() {
    assert!(FRAME_TICK_DEFAULT.as_millis() > 0);
    // 确保 80ms 的帧间隔不为零
}
```

## 风险、边界与改进建议

### 风险
1. **静态数组大小**：`[&str; 36]` 类型固定，修改帧数需改动多处
2. **编译时依赖**：帧文件必须在编译时存在

### 边界情况
- **空变体**：`AsciiAnimation::with_variants` 断言变体非空
- **索引越界**：`variant_idx.min(variants.len() - 1)` 防止越界

### 改进建议
1. **动态帧数**：支持运行时确定帧数
2. **热重载**：开发模式下支持运行时修改帧文件
3. **帧压缩**：使用压缩算法减少内存占用
4. **GPU 渲染**：对于复杂动画使用 GPU 加速
