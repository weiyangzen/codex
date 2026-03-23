# frame_6.txt 研究文档

## 场景与职责

`frame_6.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 6 帧。该帧展示 Codex 标志从初始展开状态向收缩状态过渡的早期阶段。

## 功能点目的

1. **早期收缩**：作为第 6 帧，标志继续向收缩状态过渡
2. **动画建立**：建立收缩阶段的视觉节奏
3. **过渡平滑**：确保从 frame_5 到 frame_7 的平滑过渡

## 具体技术实现

### 文件规格
- **帧序号**：6 / 36
- **动画阶段**：早期收缩阶段
- **显示时间**：动画开始后 400ms
- **文件大小**：662 字节

### 时序位置
```
0ms     80ms    160ms   240ms   320ms   400ms   480ms
 |_______|_______|_______|_______|_______|_______|
frame_1 frame_2 frame_3 frame_4 frame_5 frame_6 frame_7
  (1)     (2)     (3)     (4)     (5)     (6)     (7)
```

### 技术集成
```rust
// frames.rs 中的数组定义
pub(crate) const FRAMES_CODEX: [&str; 36] = [
    include_str!("../frames/codex/frame_1.txt"),  // [0]
    include_str!("../frames/codex/frame_2.txt"),  // [1]
    include_str!("../frames/codex/frame_3.txt"),  // [2]
    include_str!("../frames/codex/frame_4.txt"),  // [3]
    include_str!("../frames/codex/frame_5.txt"),  // [4]
    include_str!("../frames/codex/frame_6.txt"),  // [5] - 本文件
    // ... 继续到 frame_36
];
```

### 帧选择
```rust
let elapsed_ms = self.start.elapsed().as_millis();  // 400ms
let tick_ms = 80;
let idx = ((elapsed_ms / tick_ms) % 36) as usize;   // (400/80) % 36 = 5
// 返回 FRAMES_CODEX[5] = frame_6.txt
```

## 关键代码路径与文件引用

### 核心文件
| 文件 | 职责 |
|------|------|
| `frame_6.txt` | 本帧数据 |
| `frames.rs:12` | 宏包含本文件 |
| `ascii_animation.rs` | 动画控制 |
| `welcome.rs` | 渲染 |

### 渲染流程
```
启动 → 400ms 后
  ↓
FrameScheduler 触发绘制
  ↓
WelcomeWidget::render_ref()
  ↓
AsciiAnimation::current_frame() → FRAMES_CODEX[5] → frame_6.txt
  ↓
渲染到终端
```

## 依赖与外部交互

### 编译依赖
- `include_str!` 宏
- 文件系统访问

### 运行时依赖
- `FrameRequester` 调度
- `ratatui` 渲染

## 风险、边界与改进建议

### 风险点
1. **过渡平滑**：必须与 frame_5 和 frame_7 平滑过渡
2. **早期印象**：作为第 6 帧，影响用户对动画质量的判断

### 边界条件
- **时间边界**：仅显示 80ms
- **序列边界**：作为早期帧，建立动画基调

### 改进建议
1. **缓动函数**：使用缓动让收缩更自然
2. **对称验证**：验证 frame_6 与 frame_30 的对称性
3. **A/B 测试**：测试不同早期帧对用户感知的影响
