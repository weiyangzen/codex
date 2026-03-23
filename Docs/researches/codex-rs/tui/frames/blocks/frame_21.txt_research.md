# frame_21.txt 研究文档

## 场景与职责

`frame_21.txt` 是 Codex TUI 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 21 帧。作为 36 帧循环动画序列的后半段帧，它接近动画循环的 60% 位置。

## 功能点目的

1. **后期过渡**: 第 21 帧位于动画循环的 58.3% 位置
2. **图案演变**: 展示从第 20 帧到第 22 帧的过渡
3. **视觉维持**: 保持动画的连续性和吸引力

## 具体技术实现

### 文件属性

- **路径**: `codex-rs/tui/frames/blocks/frame_21.txt`
- **大小**: 约 1084 bytes
- **行数**: 17 行
- **编码**: UTF-8

### 时序信息

```rust
const FRAME_INDEX: usize = 20;
const DISPLAY_TIME_MS: u128 = 20 * 80;  // 1600ms
const LOOP_PROGRESS: f64 = 21.0 / 36.0;  // 58.3%
```

## 关键代码路径与文件引用

### 编译引用

```rust
// frames.rs:27
include_str!(concat!("../frames/blocks/frame_21.txt"))
```

### 数组访问

```rust
FRAMES_BLOCKS[20]  // 第 21 帧
```

## 依赖与外部交互

### 序列

```
frame_20 → frame_21 → frame_22
  [19]      [20]      [21]
```

### 运行时

- `AsciiAnimation`
- `WelcomeWidget`

## 风险、边界与改进建议

### 风险

- 文件缺失
- 编码问题
- 终端兼容性

### 边界

- 最小终端尺寸
- 可配置禁用

### 建议

1. 验证帧一致性
2. 添加性能监控
3. 支持用户自定义
