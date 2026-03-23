# frame_4.txt 研究文档

## 场景与职责

`frame_4.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第四帧，负责展示3D方块旋转动画的第四个时间切片。在36帧循环中，该帧对应动画开始后的 240ms-320ms 时间段。

该文件作为静态资源在编译时嵌入，是构成完整旋转动画的关键帧之一。

## 功能点目的

1. **动画序列延续**：作为 frame_3 的后续帧，保持旋转的连续性
2. **视觉流畅度贡献**：与相邻帧共同构建平滑的旋转效果
3. **品牌展示**：通过动态 ASCII 艺术增强 Codex 品牌识别度

## 具体技术实现

### 帧时序计算

```rust
// 帧索引: 3 (从0开始)
// 显示条件: elapsed_ms >= 240 && elapsed_ms < 320

let frame_index = (elapsed_ms / 80) % 36;  // 当结果为 3 时显示 frame_4
```

### 嵌入与访问

```rust
// frames.rs 宏展开
const FRAMES_BLOCKS: [&str; 36] = [
    include_str!("../frames/blocks/frame_1.txt"),  // [0]
    include_str!("../frames/blocks/frame_2.txt"),  // [1]
    include_str!("../frames/blocks/frame_3.txt"),  // [2]
    include_str!("../frames/blocks/frame_4.txt"),  // [3] <- 当前
    // ... frame_5 到 frame_36
];
```

### 渲染管线

```
Terminal::draw
  → WelcomeWidget::render_ref
    → AsciiAnimation::schedule_next_frame()  // 调度 80ms 后的下一帧
    → AsciiAnimation::current_frame()        // 获取 frame_4
    → frame.lines()                          // 迭代每一行
    → Line::from()                           // 转换为 ratatui Line
    → Paragraph::new()                       // 创建段落
    → Widget::render()                       // 渲染到 Buffer
```

## 关键代码路径与文件引用

### 定义位置
| 文件 | 行号 | 内容 |
|------|------|------|
| `frames.rs` | 10 | `include_str!(concat!("../frames/", $dir, "/frame_4.txt"))` |
| `frames.rs` | 50 | `pub(crate) const FRAMES_BLOCKS: [&str; 36] = frames_for!("blocks");` |

### 使用位置
| 文件 | 函数/代码 | 用途 |
|------|-----------|------|
| `ascii_animation.rs` | `current_frame()` | 获取当前应显示的帧 |
| `onboarding/welcome.rs` | `render_ref()` | 渲染欢迎界面动画 |

## 依赖与外部交互

### 系统架构位置

```
┌─────────────────────────────────────────┐
│           WelcomeWidget                 │
│  ┌─────────────────────────────────┐    │
│  │      AsciiAnimation             │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │   ALL_VARIANTS[3]       │    │    │
│  │  │   (= FRAMES_BLOCKS)     │    │    │
│  │  │   ┌─────────────────┐   │    │    │
│  │  │   │  [3] frame_4    │   │    │    │
│  │  │   └─────────────────┘   │    │    │
│  │  └─────────────────────────┘    │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

### 外部接口
- **输入**: 无（静态资源）
- **输出**: 字符串切片 `&str`，包含17行 ASCII 艺术
- **触发**: 时间驱动（每80ms）

## 风险、边界与改进建议

### 风险

1. **序列完整性**：
   - 若 frame_4.txt 缺失，编译错误：`error: couldn't read frames/blocks/frame_4.txt`
   - 严重性：高（阻断编译）

2. **视觉一致性**：
   - 若内容与其他帧风格不一致，动画会出现明显"断层"
   - 检查：所有帧应使用相同的字符密度和图案风格

### 边界

1. **固定帧率**：
   - 80ms/帧 = 12.5fps，在现代终端上可能显得不够流畅
   - 对比：现代显示器 60fps = 16.7ms/帧

2. **尺寸限制**：
   - 图案宽度约 40-50 字符，高度 17 行
   - 超出终端边界时会被截断

### 改进建议

1. **自适应帧率**：
   ```rust
   // 根据终端支持的能力调整
   let frame_tick = if terminal.supports_sixel() {
       Duration::from_millis(16)  // 60fps
   } else {
       Duration::from_millis(80)  // 12.5fps
   };
   ```

2. **帧验证测试**：
   ```rust
   #[test]
   fn all_frames_same_dimensions() {
       for variant in ALL_VARIANTS {
           let line_counts: Vec<_> = variant.iter().map(|f| f.lines().count()).collect();
           assert!(line_counts.windows(2).all(|w| w[0] == w[1]));
       }
   }
   ```

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_4.txt`
- 大小：1190 bytes
- 行数：17行
- 帧序号：4/36
- 变体：blocks
- 显示时间：240ms-320ms
