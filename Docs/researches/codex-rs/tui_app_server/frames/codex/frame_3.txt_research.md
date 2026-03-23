# frame_3.txt 研究文档

## 场景与职责

`frame_3.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 3 帧，属于 `codex` 变体动画序列。该文件继续展示旋转 Codex 图标的动画效果。

**动画序列位置**：第 3/36 帧
**时序位置**：160ms（第 3 个 80ms 间隔）

## 功能点目的

1. **动画连续性**：作为 36 帧循环的第 3 帧，承接 frame_2 的视觉效果
2. **旋转效果**：通过字符位置的渐进变化模拟 3D 旋转
3. **品牌展示**：保持 Codex 品牌标识的视觉一致性

## 具体技术实现

### 帧序列特性
```
总帧数：36 帧
当前帧：第 3 帧（索引 2）
每帧时长：80ms
完整周期：2.88 秒
旋转角度：约 10°/帧（360°/36）
```

### 动画状态机
```rust
// AsciiAnimation 维护的状态
struct AsciiAnimation {
    variant_idx: usize,    // 当前变体索引（codex=1）
    start: Instant,        // 动画开始时间
    frame_tick: Duration,  // 80ms
}
```

### 帧选择逻辑
```rust
fn current_frame(&self) -> &'static str {
    let frames = self.variants[self.variant_idx];  // &FRAMES_CODEX
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / 80) % 36) as usize;   // idx=2 时返回 frame_3
    frames[idx]
}
```

## 关键代码路径与文件引用

### 文件包含链
```
codex-rs/tui_app_server/frames/codex/frame_3.txt
  └─> frames.rs (include_str! 宏)
      └─> FRAMES_CODEX[2]
          └─> ascii_animation.rs (current_frame())
              └─> welcome.rs (render_ref())
```

### 相关常量
```rust
// frames.rs
pub(crate) const FRAME_TICK_DEFAULT: Duration = Duration::from_millis(80);

// welcome.rs
const MIN_ANIMATION_HEIGHT: u16 = 37;
const MIN_ANIMATION_WIDTH: u16 = 60;
```

## 依赖与外部交互

### 上游依赖
- `frame_1.txt` 和 `frame_2.txt`：同属一个动画序列
- `AsciiAnimation::start`：时间基准点

### 下游消费
- `WelcomeWidget`：主要消费者，在欢迎界面显示
- 可能的未来扩展：加载指示器、状态指示器等

### 外部控制
| 控制方式 | 效果 |
|---------|------|
| 时间流逝 | 自动推进到下一帧 |
| `Ctrl+.` | 切换到其他变体，重置动画 |
| 终端 resize | 可能隐藏/显示动画 |

## 风险、边界与改进建议

### 性能考虑
1. **内存占用**：36 帧全部常驻内存，每帧约 662 字节，共约 23.8KB
2. **渲染开销**：每帧需要重新创建 `Line` 对象

### 边界情况
1. **系统时间回拨**：`Instant` 是单调时钟，不受系统时间影响
2. **长时间运行**：`elapsed_ms` 使用 u128，可支持极长时间运行

### 改进建议
1. **帧缓存**：在 `AsciiAnimation` 中缓存解析后的 `Vec<Line>`
2. **懒加载**：仅在需要时解析帧内容
3. **变体切换优化**：切换变体时保持时间连续性，避免动画跳跃
