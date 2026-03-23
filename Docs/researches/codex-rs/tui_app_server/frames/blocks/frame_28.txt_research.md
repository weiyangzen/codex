# frame_28.txt 研究文档

## 场景与职责

`frame_28.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第二十八帧，展示3D方块旋转动画的第二十八个时间切片。在36帧循环中，该帧于动画开始后的 2160ms-2240ms 时间段显示，代表约 77.8% 的动画周期完成。

该文件作为静态 ASCII 艺术资源，在编译时嵌入到应用程序二进制中。

## 功能点目的

1. **旋转动画推进**：展示方块从 frame_27 继续旋转后的状态
2. **视觉连贯性**：确保 frame_27 → frame_28 → frame_29 的过渡平滑
3. **循环动画构建**：作为36帧序列的 28/36 部分

## 具体技术实现

### 帧参数

```rust
const FRAME_INDEX: usize = 27;           // 数组索引
const FRAME_NUMBER: usize = 28;          // 帧号
const DISPLAY_START_MS: u64 = 2160;      // 开始显示时间
const DISPLAY_END_MS: u64 = 2240;        // 结束显示时间
const CYCLE_POSITION: f64 = 77.78;       // 周期完成百分比
```

### 嵌入与访问

```rust
// frames.rs 第34行
include_str!("../frames/blocks/frame_28.txt")  // FRAMES_BLOCKS[27]

// 运行时访问
FRAMES_BLOCKS[27]
ALL_VARIANTS[3][27]
```

## 关键代码路径与文件引用

### 编译时路径
- `frames.rs:34` - 嵌入点
- `frames.rs:50` - 数组定义

### 运行时路径
```
WelcomeWidget::render_ref()
  → AsciiAnimation::current_frame() → frames[27]
  → Paragraph::new()
```

## 依赖与外部交互

### 依赖关系
```
frame_28.txt → FRAMES_BLOCKS[27] → AsciiAnimation → WelcomeWidget
```

## 风险、边界与改进建议

### 风险
- 文件缺失导致编译失败
- 内容不连贯导致动画跳跃

### 边界
- 显示时长：80ms
- 显示条件：终端 >= 37x60

### 改进建议
- 添加帧内容验证
- 支持自定义动画目录

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_28.txt`
- 大小：790 bytes
- 行数：17行
- 帧序号：28/36
- 变体：blocks
- 显示时间：2160ms-2240ms
- 周期位置：~77.8%
