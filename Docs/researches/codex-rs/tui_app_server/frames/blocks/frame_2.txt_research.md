# frame_2.txt 研究文档

## 场景与职责

`frame_2.txt` 是 Codex TUI App Server 中 ASCII 动画系统的第二帧资源文件，属于 `blocks` 动画变体。该帧展示旋转方块动画的第二个时间步，与 frame_1.txt 相比，方块图案发生了轻微旋转，形成连续的动画效果。

作为36帧循环动画的一部分，frame_2.txt 在编译时被嵌入到 `FRAMES_BLOCKS` 数组的第二个位置，在动画播放时按80ms间隔顺序显示。

## 功能点目的

1. **动画连续性**：作为 frame_1.txt 的后续帧，展示方块旋转的下一时间步
2. **视觉流畅性**：与前后帧配合形成平滑的旋转动画效果
3. **帧序列完整性**：36帧循环中的关键一环，确保动画循环无缝衔接

## 具体技术实现

### 帧内容特征

frame_2.txt 展示了一个相对于 frame_1.txt 略有旋转的3D方块图案：
- 使用相同的 Unicode 块字符集（█ ▓ ▒ ░）
- 保持17行的垂直尺寸
- 图案密度和阴影分布与 frame_1.txt 相似但角度不同

### 动画循环机制

```rust
// 帧索引计算（在 AsciiAnimation::current_frame 中）
let elapsed_ms = self.start.elapsed().as_millis();
let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
frames[idx]  // 返回 frame_2.txt 等内容
```

当 `idx == 1` 时，返回 `FRAMES_BLOCKS[1]`，即 frame_2.txt 的内容。

### 时间同步

- **帧持续时间**：80ms (FRAME_TICK_DEFAULT)
- **显示时机**：动画开始后 80ms-160ms 区间
- **循环周期**：36 × 80ms = 2880ms (约2.9秒完成一个循环)

## 关键代码路径与文件引用

### 编译时路径
```rust
// frames.rs 第8行
include_str!(concat!("../frames/", "blocks", "/frame_2.txt"))
```

### 运行时访问路径
1. `FRAMES_BLOCKS[1]` - 直接数组访问
2. `ALL_VARIANTS[3][1]` - 通过变体数组访问
3. `AsciiAnimation::current_frame()` → `frames()[1]` - 通过动画控制器

### 渲染调用链
```
WelcomeWidget::render_ref
  → self.animation.schedule_next_frame()
  → self.animation.current_frame()  // 可能返回 frame_2
  → frame.lines().map(Into::into)   // 转换为 Line 迭代器
  → Paragraph::new(lines).render()  // 渲染到终端
```

## 依赖与外部交互

### 上游依赖
- `frame_1.txt`：动画序列的前一帧
- `frame_3.txt`：动画序列的后一帧（循环时回到 frame_1）

### 运行时依赖
| 组件 | 交互方式 |
|------|----------|
| FrameRequester | 通过 `schedule_next_frame_in(Duration::from_millis(80))` 调度下一帧 |
| ratatui::Paragraph | 作为渲染目标容器 |
| WelcomeWidget | 消费帧内容并渲染到欢迎界面 |

## 风险、边界与改进建议

### 风险分析

1. **帧序列错位**：
   - 若 frame_2.txt 内容与其他帧不连贯，会导致动画闪烁
   - 建议：添加帧间相似度检查工具

2. **文件编码变更**：
   - 若文件被保存为不同编码（如 UTF-8 with BOM），编译可能失败
   - 当前：纯 UTF-8 无 BOM

### 边界条件

1. **变体切换边界**：
   - 当用户按 Ctrl+. 切换变体时，当前帧索引保持不变
   - 若新变体帧数不同，可能导致索引越界（但当前所有变体都是36帧）

2. **暂停/恢复**：
   - 动画暂停时帧冻结在当前帧
   - 恢复时从暂停点继续，frame_2 可能在非预期时间显示

### 改进建议

1. **帧插值**：
   - 当前36帧可能不足以实现完全平滑的旋转
   - 建议：增加到 60fps × 3s = 180帧，或使用程序生成

2. **帧缓存**：
   - 每次渲染都重新解析字符串为行
   - 建议：在 `AsciiAnimation` 中预解析为 `Vec<Vec<Span>>`

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_2.txt`
- 大小：1200 bytes
- 行数：17行
- 帧序号：2/36
- 变体：blocks
- 预估显示时长：80ms
