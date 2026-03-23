# frame_29.txt 研究文档

## 场景与职责

`frame_29.txt` 是 Codex TUI 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 29 帧。作为 36 帧循环动画序列的末期帧，它位于动画循环的约 81% 位置。

## 功能点目的

1. **末期动画**: 第 29 帧位于动画循环的 80.6% 位置
2. **过渡作用**: 连接第 28 帧和第 30 帧
3. **视觉维持**: 保持动画的连续性，准备进入最后几帧

## 具体技术实现

### 文件属性

- **路径**: `codex-rs/tui/frames/blocks/frame_29.txt`
- **大小**: 约 852 bytes
- **行数**: 17 行
- **编码**: UTF-8

### 时序信息

```rust
const FRAME_INDEX: usize = 28;
const DISPLAY_TIME_MS: u128 = 28 * 80;  // 2240ms
const LOOP_PROGRESS: f64 = 29.0 / 36.0;  // 80.6%
```

## 关键代码路径与文件引用

### 编译引用

```rust
// frames.rs:35
include_str!(concat!("../frames/blocks/frame_29.txt"))
```

### 数组访问

```rust
FRAMES_BLOCKS[28]  // 第 29 帧
```

## 依赖与外部交互

### 序列

```
frame_28 → frame_29 → frame_30
  [27]      [28]      [29]
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
