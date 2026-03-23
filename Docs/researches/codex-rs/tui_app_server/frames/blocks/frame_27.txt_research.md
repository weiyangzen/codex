# frame_27.txt 研究文档

## 场景与职责

`frame_27.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第二十七帧，展示3D方块旋转动画的第二十七个时间切片。在36帧循环中，该帧于动画开始后的 2080ms-2160ms 时间段显示，代表约 75% 的动画周期完成（3/4 周期）。

该文件作为静态 ASCII 艺术资源，在编译时嵌入到应用程序二进制中。

## 功能点目的

1. **旋转动画推进**：展示方块从 frame_26 继续旋转后的状态
2. **视觉连贯性**：确保 frame_26 → frame_27 → frame_28 的过渡平滑
3. **周期里程碑**：完成四分之三周期（75%）

## 具体技术实现

### 帧参数

```rust
const FRAME_INDEX: usize = 26;           // 数组索引
const FRAME_NUMBER: usize = 27;          // 帧号
const DISPLAY_START_MS: u64 = 2080;      // 开始显示时间
const DISPLAY_END_MS: u64 = 2160;        // 结束显示时间
const CYCLE_POSITION: f64 = 75.0;        // 周期完成百分比 (27/36 = 3/4)
```

### 嵌入与访问

```rust
// frames.rs 第33行
include_str!("../frames/blocks/frame_27.txt")  // FRAMES_BLOCKS[26]

// 运行时访问
FRAMES_BLOCKS[26]
ALL_VARIANTS[3][26]
```

## 关键代码路径与文件引用

### 编译时路径
- `frames.rs:33` - 嵌入点
- `frames.rs:50` - 数组定义

### 运行时路径
```
WelcomeWidget::render_ref()
  → AsciiAnimation::current_frame() → frames[26]
  → Paragraph::new()
```

## 依赖与外部交互

### 依赖关系
```
frame_27.txt → FRAMES_BLOCKS[26] → AsciiAnimation → WelcomeWidget
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
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_27.txt`
- 大小：900 bytes
- 行数：17行
- 帧序号：27/36
- 变体：blocks
- 显示时间：2080ms-2160ms
- 周期位置：75% (3/4 周期)
