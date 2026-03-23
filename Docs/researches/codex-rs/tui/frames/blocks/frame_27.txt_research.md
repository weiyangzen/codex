# frame_27.txt 研究文档

## 场景与职责

`frame_27.txt` 是 Codex TUI 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 27 帧。作为 36 帧循环动画序列的后期帧，它位于动画循环的 75% 位置（3/4 节点）。

## 功能点目的

1. **3/4 节点**: 第 27 帧正好是动画循环的 75% 位置
2. **过渡作用**: 连接第 26 帧和第 28 帧
3. **视觉维持**: 保持动画的连续性和流畅性

## 具体技术实现

### 文件属性

- **路径**: `codex-rs/tui/frames/blocks/frame_27.txt`
- **大小**: 约 900 bytes
- **行数**: 17 行
- **编码**: UTF-8

### 时序信息

```rust
const FRAME_INDEX: usize = 26;
const DISPLAY_TIME_MS: u128 = 26 * 80;  // 2080ms
const LOOP_PROGRESS: f64 = 27.0 / 36.0;  // 75.0%
```

## 关键代码路径与文件引用

### 编译引用

```rust
// frames.rs:33
include_str!(concat!("../frames/blocks/frame_27.txt"))
```

### 数组位置

```rust
FRAMES_BLOCKS[26]  // 第 27 帧
```

## 依赖与外部交互

### 序列

```
frame_26 → frame_27 → frame_28
  [25]      [26]      [27]
```

### 运行时

- `AsciiAnimation::current_frame()`
- `WelcomeWidget::render_ref()`

## 风险、边界与改进建议

### 风险

- 文件缺失导致编译失败
- 终端不支持 Unicode

### 边界

- 最小终端尺寸
- 动画可配置禁用

### 建议

1. 添加帧验证
2. 优化存储
3. 支持自定义
