# frame_22.txt 研究文档

## 场景与职责

`frame_22.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 22 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 22/36 帧
**时序位置**：1680ms（第 22 个 80ms 间隔）

## 功能点目的

1. **动画序列延续**：作为 36 帧循环的第 22 帧，超过 60% 周期点
2. **旋转展示**：展示 Codex 图标旋转约 210° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 帧时序
```
frame_22: 1680ms (索引 21)
周期进度: 22/36 ≈ 61.1%
剩余帧数: 14 帧
剩余时间: 1120ms
```

### 帧访问
```rust
// 直接访问
let frame_22 = FRAMES_CODEX[21];

// 时间计算
let elapsed = 1680;
let idx = (elapsed / 80) % 36;  // = 21
```

### 动画状态
```rust
struct AsciiAnimation {
    start: Instant,        // 动画开始
    frame_tick: 80ms,      // 帧间隔
    variant_idx: usize,    // 当前变体
}
```

## 关键代码路径与文件引用

### 文件包含
```rust
// frames.rs 宏展开
[
    // ... frame_1 到 frame_21
    include_str!("../frames/codex/frame_22.txt"),  // 索引 21
    // ... frame_23 到 frame_36
]
```

### 渲染路径
```
frame_22.txt
  ↓ compile-time
FRAMES_CODEX[21]
  ↓ run-time
AsciiAnimation::current_frame()
  ↓ (idx=21)
WelcomeWidget::render_ref()
  ↓
终端显示
```

## 依赖与外部交互

### 上游依赖
- `frame_21.txt`
- 时间流逝

### 下游消费
- `frame_23.txt`
- 终端显示

### 外部控制
- 变体切换
- 动画开关

## 风险、边界与改进建议

### 边界情况
1. **后半周期**：frame_22 已进入后半周期
2. **接近循环**：还有 14 帧回到 frame_1
3. **视觉一致性**：需要确保循环平滑

### 改进建议
1. **循环平滑**：验证 frame_36 到 frame_1 的过渡
2. **帧压缩**：后半周期帧可以压缩存储
3. **性能监控**：监控后半周期的渲染性能

### 测试建议
```rust
#[test]
fn test_frame_22_rendering() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    // 模拟 1680ms 后的渲染
}
```
