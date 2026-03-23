# frame_36.txt 研究文档

## 场景与职责

`frame_36.txt` 是 Codex TUI 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 36 帧（最后一帧）。作为 36 帧循环动画序列的终点，它位于动画循环的 100% 位置，之后动画将循环回到第 1 帧。

## 功能点目的

1. **循环终点**: 第 36 帧是动画循环的最后一帧（100%）
2. **循环衔接**: 展示图案状态，为平滑循环回第 1 帧做准备
3. **视觉完成**: 完成一个完整的动画循环

## 具体技术实现

### 文件规格

- **路径**: `codex-rs/tui/frames/blocks/frame_36.txt`
- **大小**: 约 1132 bytes
- **行数**: 17 行
- **编码**: UTF-8

### 时序数据

| 属性 | 值 |
|------|-----|
| 帧索引 | 35 |
| 显示时间 | 2800ms |
| 循环进度 | 100.0% |
| 下一帧 | frame_1.txt（循环） |

### 编译嵌入

```rust
// codex-rs/tui/src/frames.rs:42
include_str!(concat!("../frames/blocks/frame_36.txt"))
```

### 循环逻辑

```rust
// 当 idx 达到 35（第 36 帧）后，下一帧回到 0（第 1 帧）
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
// frames.len() == 36
// 所以 idx 范围是 0-35，达到 35 后下一个周期回到 0
```

## 关键代码路径与文件引用

### 引用链

```
frame_36.txt → FRAMES_BLOCKS[35] → AsciiAnimation → WelcomeWidget
```

### 核心文件

- `frames.rs`: 第 42 行
- `ascii_animation.rs`: 动画控制
- `welcome.rs`: 界面渲染

## 依赖与外部交互

### 序列

```
frame_35 → frame_36 → frame_1 (循环)
  [34]      [35]       [0]
```

### 环境

- Unicode 终端
- 最小尺寸 60×37

## 风险、边界与改进建议

### 风险

- 编译时文件缺失
- 运行时渲染问题
- 循环衔接不流畅

### 边界

- 动画可禁用
- 终端尺寸限制
- 循环时间: 2880ms (36 × 80ms)

### 建议

1. 添加帧验证
2. 确保 frame_36 到 frame_1 的过渡平滑
3. 支持速度调整
4. 优化存储格式

### 循环优化

建议检查 frame_36.txt 和 frame_1.txt 的视觉连贯性，确保循环时无明显跳跃感。
