# frame_15.txt 研究文档

## 场景与职责

`frame_15.txt` 是 Codex TUI 的 ASCII 艺术动画帧文件，属于 `blocks` 动画变体的第 15 帧。作为 36 帧循环动画序列的中间帧，它接近动画循环的中点位置。

## 功能点目的

1. **中点过渡**: 接近动画循环的中点（42%），提供视觉过渡
2. **动画流畅性**: 确保从第 14 帧到第 16 帧的平滑过渡
3. **用户体验**: 在 CLI 等待期间维持用户的视觉注意力

## 具体技术实现

### 文件规格

- **路径**: `codex-rs/tui/frames/blocks/frame_15.txt`
- **大小**: 约 964 bytes
- **行数**: 17 行
- **编码**: UTF-8

### 动画时序

```rust
const FRAME_INDEX: usize = 14;
const DISPLAY_TIME_MS: u128 = 14 * 80;  // 1120ms
const LOOP_PROGRESS: f64 = 15.0 / 36.0;  // 41.7%
```

### 帧数组位置

```rust
pub(crate) const FRAMES_BLOCKS: [&str; 36] = [
    // frame_1 到 frame_14 ...
    include_str!("../frames/blocks/frame_15.txt"),  // 索引 14
    // frame_16 到 frame_36 ...
];
```

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行号 | 内容 |
|------|------|------|
| `frames.rs` | 21 | `include_str!(...frame_15.txt)` |
| `ascii_animation.rs` | 65-77 | `current_frame()` 方法 |
| `welcome.rs` | 82-83 | 帧渲染逻辑 |

### 调用链

```
frame_15.txt
  ↓ 编译时嵌入
FRAMES_BLOCKS[14]
  ↓ 数组访问
AsciiAnimation::current_frame()
  ↓ 方法调用
WelcomeWidget::render_ref()
  ↓ 渲染
终端显示
```

## 依赖与外部交互

### 序列位置

```
... → frame_14 → frame_15 → frame_16 → ...
        [14]       [15]       [16]
```

### 运行时依赖

- `ratatui::widgets::Paragraph`
- `ratatui::text::Line`
- 终端 Unicode 支持

## 风险、边界与改进建议

### 风险分析

1. **一致性**: 需确保与前后帧的视觉连贯性
2. **兼容性**: 终端必须正确显示块字符
3. **性能**: 动画不应影响 CLI 响应速度

### 边界条件

- 终端最小尺寸: 宽度 60，高度 37
- 帧间隔: 80ms
- 可禁用: 通过配置关闭动画

### 改进建议

1. **验证工具**: 创建脚本验证所有帧的一致性
2. **压缩算法**: 研究帧间差分压缩
3. **可访问性**: 提供 `--accessible` 模式禁用动画
4. **性能监控**: 添加动画性能指标收集
