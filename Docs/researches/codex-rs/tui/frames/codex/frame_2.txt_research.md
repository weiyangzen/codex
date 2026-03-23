# frame_2.txt 研究文档

## 场景与职责

`frame_2.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 2 帧。该帧展示 Codex 标志从初始展开状态向收缩状态过渡的早期阶段，紧随 frame_1.txt 之后。

## 功能点目的

1. **动画起始过渡**：作为第 2 帧，承接 frame_1 的初始状态
2. **动态展示开始**：标志开始从展开状态产生变化
3. **视觉引导**：引导用户进入动画循环

## 具体技术实现

### 文件规格
- **帧序号**：2 / 36
- **动画阶段**：初始过渡阶段
- **显示时间**：动画开始后 80ms
- **文件大小**：662 字节

### 与 frame_1 的关系
```
frame_1.txt: 初始展开状态（最展开）
    ↓ 80ms
frame_2.txt: 开始收缩（本文件）
    ↓ 80ms
frame_3.txt: 继续收缩
```

### 技术实现
```rust
// frames.rs - 数组定义
pub(crate) const FRAMES_CODEX: [&str; 36] = [
    include_str!("../frames/codex/frame_1.txt"),  // [0] - 初始
    include_str!("../frames/codex/frame_2.txt"),  // [1] - 本文件
    include_str!("../frames/codex/frame_3.txt"),  // [2]
    // ... 继续到 frame_36
];
```

### 时序计算
```rust
// 当前帧选择逻辑
let elapsed_ms = self.start.elapsed().as_millis();  // 例如 80ms
let tick_ms = 80;
let idx = ((elapsed_ms / tick_ms) % 36) as usize;   // (80/80) % 36 = 1
// 返回 FRAMES_CODEX[1] = frame_2.txt
```

## 关键代码路径与文件引用

### 核心文件
| 文件 | 行号 | 内容 |
|------|------|------|
| `frames.rs` | 8 | `include_str!(concat!("../frames/", $dir, "/frame_2.txt"))` |
| `ascii_animation.rs` | 65-77 | `current_frame()` 方法 |
| `welcome.rs` | 82-84 | 动画渲染逻辑 |

### 渲染流程
```
启动
  ↓
AsciiAnimation::new() - start = Instant::now()
  ↓
80ms 后
  ↓
schedule_next_frame() → current_frame() → FRAMES_CODEX[1]
  ↓
渲染 frame_2.txt
```

## 依赖与外部交互

### 编译依赖
- 文件必须在编译时存在
- 通过 `include_str!` 嵌入二进制

### 运行时依赖
- `FrameRequester` 提供时序
- `ratatui::Paragraph` 负责渲染

## 风险、边界与改进建议

### 风险点
1. **首帧体验**：作为早期帧，影响用户对动画的第一印象
2. **过渡平滑**：与 frame_1 和 frame_3 的过渡必须平滑

### 边界条件
- **时间边界**：仅显示 80ms，是最短显示时间的帧之一
- **序列边界**：作为第 2 帧，不能独立存在

### 改进建议
1. **首帧优化**：考虑延长前几帧显示时间，让用户看清初始状态
2. **缓动开始**：使用缓动函数让开始更自然
3. **预览模式**：添加命令行选项预览单帧效果
