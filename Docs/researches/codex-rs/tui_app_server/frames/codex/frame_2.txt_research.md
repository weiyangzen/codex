# frame_2.txt 研究文档

## 场景与职责

`frame_2.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 2 帧，属于 `codex` 变体动画序列。该文件与 `frame_1.txt` 共同构成旋转 Codex 图标动画的连续帧序列。

**动画序列位置**：第 2/36 帧
**视觉作用**：展示 Codex 图标旋转动画的第二个状态，与 frame_1 形成平滑过渡

## 功能点目的

1. **连续动画**：作为 36 帧循环动画的一部分，提供流畅的视觉旋转效果
2. **品牌一致性**：与 frame_1 保持相同的视觉风格（17x40 ASCII 艺术）
3. **时序控制**：在 80ms 的帧间隔中与相邻帧形成连续动画

## 具体技术实现

### 帧间差异分析
与 frame_1 相比，frame_2 的图案有细微变化：
- 字符位置微调，模拟旋转效果
- 使用相同的字符集（`e`, `o`, `c`, `d`, `x`）
- 保持中心对称的 Codex 图标形状

### 技术规格
```
文件：frame_2.txt
尺寸：17 行 x 40 列
大小：662 字节
帧率：12.5 FPS（80ms/帧）
动画周期：36 帧 × 80ms = 2.88 秒/循环
```

### 动画时序计算
```rust
// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    frames[idx]  // 当 idx=1 时返回 frame_2.txt 内容
}
```

## 关键代码路径与文件引用

### 帧索引映射
```rustn// frames.rs
pub(crate) const FRAMES_CODEX: [&str; 36] = [
    include_str!("../frames/codex/frame_1.txt"),  // idx=0
    include_str!("../frames/codex/frame_2.txt"),  // idx=1 (本文件)
    include_str!("../frames/codex/frame_3.txt"),  // idx=2
    // ... 继续到 frame_36
];
```

### 渲染调用链
```
TUI Event Loop
  └─> FrameScheduler (80ms 定时)
      └─> WelcomeWidget::render_ref()
          └─> AsciiAnimation::schedule_next_frame()
              └─> AsciiAnimation::current_frame() -> &str (frame_2.txt 内容)
```

## 依赖与外部交互

### 与 frame_1 的关系
- 同属 `FRAMES_CODEX` 数组
- 共享相同的 `AsciiAnimation` 实例
- 通过时间索引顺序切换

### 与相邻帧的过渡
| 帧 | 时间偏移 | 说明 |
|---|---------|------|
| frame_1 | 0ms | 起始帧 |
| frame_2 | 80ms | 本文件，第 2 帧 |
| frame_3 | 160ms | 下一帧 |

## 风险、边界与改进建议

### 帧同步风险
1. **丢帧处理**：如果渲染耗时超过 80ms，动画可能跳帧
2. **时间漂移**：长时间运行后，`Instant` 精度可能影响帧索引计算

### 改进建议
1. **帧插值**：考虑在关键帧之间进行字符级插值，减少所需帧数
2. **预渲染**：将 ASCII 艺术预渲染为 ratatui 的 `Line` 结构，减少运行时开销
3. **帧压缩**：36 帧中有大量重复空格，可使用游程编码压缩

### 测试覆盖
```rust
// welcome.rs 中的测试用例
#[test]
fn welcome_renders_animation_on_first_draw() {
    let widget = WelcomeWidget::new(false, FrameRequester::test_dummy(), true);
    let area = Rect::new(0, 0, MIN_ANIMATION_WIDTH, MIN_ANIMATION_HEIGHT);
    let mut buf = Buffer::empty(area);
    let frame_lines = widget.animation.current_frame().lines().count() as u16;
    (&widget).render(area, &mut buf);
    // 验证动画正确渲染
}
```
