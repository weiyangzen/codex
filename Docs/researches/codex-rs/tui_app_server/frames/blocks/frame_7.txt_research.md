# frame_7.txt 研究文档

## 场景与职责

`frame_7.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第七帧，展示3D方块旋转动画的第七个时间切片。在36帧循环中，该帧于动画开始后的 480ms-560ms 时间段显示，代表约 19.4% 的动画周期完成。

该文件作为静态 ASCII 艺术资源，在编译时通过 Rust 的 `include_str!` 宏嵌入到应用程序中。

## 功能点目的

1. **旋转动画延续**：展示方块从 frame_6 继续旋转约 10 度后的状态
2. **视觉流畅性**：确保 frame_6 → frame_7 → frame_8 的过渡自然
3. **循环动画构建**：作为36帧序列的 7/36 部分，贡献于完整的 2.88 秒旋转周期

## 具体技术实现

### 帧参数

```rust
// 帧标识
const FRAME_INDEX: usize = 6;           // 数组索引（从0开始）
const FRAME_NUMBER: usize = 7;          // 帧号（从1开始）

// 时序参数
const DISPLAY_START_MS: u64 = 480;      // 开始显示时间 (6 * 80ms)
const DISPLAY_END_MS: u64 = 560;        // 结束显示时间 (7 * 80ms)
const CYCLE_POSITION: f64 = 19.44;      // 周期完成百分比 (7/36 * 100)

// 旋转角度（估算）
const ROTATION_ANGLE: f64 = 70.0;       // 相对于起始位置的旋转角度
```

### 嵌入机制

```rust
// frames.rs 中的宏展开
macro_rules! frames_for {
    ("blocks") => {
        [
            // frame_1 到 frame_6 ...
            include_str!("../frames/blocks/frame_7.txt"),  // [6]
            // frame_8 到 frame_36 ...
        ]
    };
}
```

### 访问方式

```rust
// 方式1: 直接数组索引
let frame_content = FRAMES_BLOCKS[6];

// 方式2: 通过变体数组
let frame_content = ALL_VARIANTS[3][6];

// 方式3: 运行时通过动画控制器
let animation = AsciiAnimation::new(frame_requester);
let frame_content = animation.current_frame(); // 当时间匹配时
```

## 关键代码路径与文件引用

### 编译时路径
| 文件 | 行号 | 说明 |
|------|------|------|
| `frames.rs` | 13 | `include_str!(concat!("../frames/", $dir, "/frame_7.txt"))` |
| `frames.rs` | 50 | `pub(crate) const FRAMES_BLOCKS: [&str; 36] = frames_for!("blocks");` |
| `frames.rs` | 62 | `ALL_VARIANTS` 数组包含 `&FRAMES_BLOCKS` |

### 运行时渲染链
```
EventLoop::run
  → App::handle_event
    → App::render
      → WelcomeWidget::render_ref
        → AsciiAnimation::schedule_next_frame()  // 调度下一帧
        → AsciiAnimation::current_frame()        // 获取当前帧
          → frames[6]  // 当 idx == 6 时返回 frame_7
        → frame.lines().map(Into::into)          // 转换为 Line 迭代器
        → Paragraph::new(lines)                  // 创建段落
        → WidgetRef::render_ref()                // 渲染到 Buffer
      → Terminal::flush()                        // 输出到终端
```

## 依赖与外部交互

### 依赖关系图
```
┌─────────────────────────────────────────────────────┐
│                  frame_7.txt                        │
│                  (静态资源文件)                      │
└──────────────────┬──────────────────────────────────┘
                   │ include_str! (编译时)
                   ▼
┌─────────────────────────────────────────────────────┐
│              FRAMES_BLOCKS[6]                       │
│              (&'static str)                         │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│              AsciiAnimation                         │
│  ┌─────────────────────────────────────────────┐    │
│  │  current_frame() → frames[time_based_index] │    │
│  └─────────────────────────────────────────────┘    │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│              WelcomeWidget                          │
│  ┌─────────────────────────────────────────────┐    │
│  │  render_ref() → 显示动画帧                   │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### 外部系统交互
| 系统 | 交互方式 | 说明 |
|------|----------|------|
| 终端 | crossterm | 输出 Unicode 块字符 |
| 渲染 | ratatui | 布局管理和缓冲区操作 |
| 调度 | FrameRequester | 定时请求下一帧渲染 |

## 风险、边界与改进建议

### 风险

1. **文件完整性**：
   - 若 frame_7.txt 被损坏或替换为不相关内容，动画会出现视觉断层
   - 建议：添加文件哈希校验

2. **编码问题**：
   - 文件必须使用 UTF-8 无 BOM 编码
   - 其他编码可能导致编译错误或运行时乱码

### 边界

1. **显示条件**：
   ```rust
   let show_animation = animations_enabled 
       && area.height >= 37 
       && area.width >= 60;
   ```
   - 所有条件必须同时满足

2. **时间精度**：
   - 实际显示时长受系统调度影响，可能偏离精确的 80ms
   - 在负载高的系统上可能出现帧丢失

### 改进建议

1. **帧间插值**：
   - 当前：离散帧，36帧/周期
   - 改进：使用缓动函数在帧之间进行颜色/位置插值

2. **响应式帧率**：
   ```rust
   let frame_tick = if battery_saving_mode {
       Duration::from_millis(160)  // 低电量模式
   } else {
       Duration::from_millis(80)   // 正常模式
   };
   ```

3. **帧内容验证**：
   ```rust
   #[test]
   fn frame_7_valid() {
       let frame = FRAMES_BLOCKS[6];
       assert_eq!(frame.lines().count(), 17);  // 验证行数
       assert!(frame.chars().all(|c| " █▓▒░\n".contains(c)));  // 验证字符集
   }
   ```

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_7.txt`
- 大小：1152 bytes
- 行数：17行
- 帧序号：7/36
- 变体：blocks
- 显示时间：480ms-560ms
- 周期位置：~19.4%
