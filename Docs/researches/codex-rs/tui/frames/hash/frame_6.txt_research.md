# frame_6.txt 研究文档

## 场景与职责

`frame_6.txt` 是 Codex TUI `hash` 动画变体的第 6 帧，在 36 帧动画序列中展示哈希图案的动态演变。

### 动画序列位置
- **帧索引**: 5 (0-based)
- **时间范围**: 400-479ms (80ms 帧间隔)
- **动画阶段**: 早期向中期过渡阶段

### 视觉特征
该帧展示了图案从中心向外扩散的效果，字符分布呈现出更加开放的形态，边缘的 `#` 和 `*` 字符形成了流动的轮廓。

## 功能点目的

### 动画过渡
作为第 6 帧，它标志着动画从早期阶段向中期阶段的过渡：
1. 延续前 5 帧建立的视觉节奏
2. 展示图案的进一步扩张
3. 为后续更复杂的变化做准备

### 字符构成
```
frame_6.txt 字符分析:
- █ (完整块): 中心区域的主要视觉元素
- # (井号): 构成图案的结构框架
- * (星号): 装饰性细节，分布较分散
- - (连字符): 连接和过渡
- . (点): 点缀填充
- A (字母): 特殊标记点
```

## 具体技术实现

### 编译时嵌入
```rust
// frames.rs 宏展开 (第 12 行)
include_str!(concat!("../frames/", $dir, "/frame_6.txt"))
```

### 运行时访问
```rust
// FRAMES_HASH 数组中的位置
pub(crate) const FRAMES_HASH: [&str; 36] = [
    // frame_1.txt ... frame_5.txt
    include_str!("../frames/hash/frame_6.txt"),  // 索引 5
    // frame_7.txt ... frame_36.txt
];
```

### 索引计算
```rust
// AsciiAnimation::current_frame()
let elapsed_ms = self.start.elapsed().as_millis();
let idx = ((elapsed_ms / 80) % 36) as usize;
// elapsed_ms = 400..479 -> idx = 5 -> frame_6.txt
```

## 关键代码路径与文件引用

### 完整渲染流程
```
1. TUI Event Loop 启动
   └─ FrameRequester::new(draw_tx)
      └─ FrameScheduler::run() (后台任务)

2. 动画调度
   └─ WelcomeWidget::render_ref()
      ├─ AsciiAnimation::schedule_next_frame()
      │   ├─ 计算延迟: delay_ms = 80 - (elapsed_ms % 80)
      │   └─ FrameRequester::schedule_frame_in(delay)
      └─ AsciiAnimation::current_frame()
          ├─ 计算索引: idx = (elapsed_ms / 80) % 36
          └─ 返回 FRAMES_HASH[5] (frame_6.txt)

3. 终端渲染
   └─ Paragraph::new(frame_content).render(area, buf)
```

### 代码引用

**帧数组定义** (`frames.rs:52`):
```rust
pub(crate) const FRAMES_HASH: [&str; 36] = frames_for!("hash");
```

**动画变体列表** (`frames.rs:64`):
```rust
&FRAMES_HASH,  // 在 ALL_VARIANTS 中，索引 5
```

**当前帧获取** (`ascii_animation.rs:65-77`):
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    if frames.is_empty() { return ""; }
    let tick_ms = self.frame_tick.as_millis();
    if tick_ms == 0 { return frames[0]; }
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]
}
```

## 依赖与外部交互

### 动画系统架构
```
┌─────────────────────────────────────────┐
│           AsciiAnimation                │
│  ├─ request_frame: FrameRequester       │
│  ├─ variants: &'static [&'static str]   │
│  ├─ variant_idx: usize (5 for HASH)     │
│  ├─ frame_tick: Duration (80ms)         │
│  └─ start: Instant                      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│           FrameRequester                │
│  ├─ schedule_frame()                    │
│  └─ schedule_frame_in(duration)         │
└─────────────────────────────────────────┘
```

### 与其他组件的关系
| 组件 | 关系 | 说明 |
|------|------|------|
| `frame_5.txt` | 前一帧 | 视觉延续，图案更扩张 |
| `frame_7.txt` | 后一帧 | 动画继续 |
| `WelcomeWidget` | 渲染容器 | 在欢迎界面显示 |
| `FrameScheduler` | 调度器 | 控制渲染时机 |

### 外部配置
```rust
// 影响本帧渲染的配置
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);
```

## 风险、边界与改进建议

### 技术风险

1. **编译时依赖**
   - 文件必须在编译时存在
   - 使用 `include_str!` 编译时嵌入

2. **内存占用**
   - 本帧: 690 bytes
   - 所有 hash 帧总计: ~25 KB
   - 所有动画变体总计: ~250 KB

### 边界情况

| 场景 | 行为 |
|------|------|
| 终端尺寸不足 | 跳过动画，仅显示文字 |
| 动画禁用 | 不渲染任何帧 |
| 快速切换变体 | 重置动画到第 1 帧 |
| 系统负载高 | 可能跳帧，但无错误 |

### 改进建议

1. **帧内容验证**
   ```rust
   // 编译时验证
   const _: () = {
       assert!(FRAMES_HASH[5].len() > 0);
       assert!(FRAMES_HASH[5].lines().count() == 17);
   };
   ```

2. **动态帧率**
   ```rust
   // 根据系统负载调整帧率
   impl AsciiAnimation {
       pub fn set_frame_tick(&mut self, tick: Duration) {
           self.frame_tick = tick;
       }
   }
   ```

3. **调试支持**
   ```rust
   // 添加帧信息输出
   tracing::debug!(
       "Rendering hash frame 6, size={}, lines={}",
       frame.len(),
       frame.lines().count()
   );
   ```

### 测试覆盖
```rust
#[test]
fn test_frame_6_properties() {
    let frame = FRAMES_HASH[5];
    assert!(!frame.is_empty());
    assert_eq!(frame.lines().count(), 17);
    // 验证包含预期的字符类型
    assert!(frame.chars().any(|c| c == '█'));
}
```

### 文件元数据
```
路径: codex-rs/tui/frames/hash/frame_6.txt
大小: 690 bytes (比平均小 ~10 bytes)
行数: 17
索引: 5 (0-based)
时间位置: 400-479ms
```
