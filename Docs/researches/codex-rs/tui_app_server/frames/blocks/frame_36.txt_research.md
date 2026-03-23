# frame_36.txt 研究文档

## 场景与职责

`frame_36.txt` 是 Codex TUI App Server 中 `blocks` 动画变体的第三十六帧（最后一帧），展示3D方块旋转动画的最后一个时间切片。在36帧循环中，该帧于动画开始后的 2800ms-2880ms 时间段显示，代表约 100% 的动画周期完成。

该文件作为静态 ASCII 艺术资源，在编译时嵌入到应用程序二进制中。显示完毕后，动画将循环回到 frame_1，形成无缝的连续旋转效果。

## 功能点目的

1. **旋转动画收尾**：展示方块完成一个完整360度旋转前的最后状态
2. **循环衔接**：确保 frame_36 → frame_1 的过渡平滑，形成无缝循环
3. **周期完成**：标志一个完整 2.88 秒动画周期的结束

## 具体技术实现

### 帧参数

```rust
const FRAME_INDEX: usize = 35;           // 数组索引（最后一个）
const FRAME_NUMBER: usize = 36;          // 帧号（最后一个）
const DISPLAY_START_MS: u64 = 2800;      // 开始显示时间 (35 * 80ms)
const DISPLAY_END_MS: u64 = 2880;        // 结束显示时间 (36 * 80ms)
const CYCLE_POSITION: f64 = 100.0;       // 周期完成百分比
const NEXT_FRAME: &str = "frame_1.txt";  // 循环回到第一帧
```

### 嵌入与访问

```rust
// frames.rs 第42行
include_str!("../frames/blocks/frame_36.txt")  // FRAMES_BLOCKS[35]

// 运行时访问
FRAMES_BLOCKS[35]
ALL_VARIANTS[3][35]
```

### 循环机制

```rust
impl AsciiAnimation {
    pub(crate) fn current_frame(&self) -> &'static str {
        let frames = self.frames();
        let tick_ms = self.frame_tick.as_millis();      // 80
        let elapsed_ms = self.start.elapsed().as_millis();
        
        // 使用模运算实现循环
        // 当 elapsed_ms = 2800..2880 时，idx = 35 (frame_36)
        // 当 elapsed_ms = 2880.. 时，idx = 0 (frame_1，循环)
        let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
        frames[idx]
    }
}
```

## 关键代码路径与文件引用

### 编译时路径
| 文件 | 行号 | 说明 |
|------|------|------|
| `frames.rs` | 42 | `include_str!(concat!("../frames/", $dir, "/frame_36.txt"))` |
| `frames.rs` | 50 | `pub(crate) const FRAMES_BLOCKS: [&str; 36] = frames_for!("blocks");` |

### 运行时路径
```
WelcomeWidget::render_ref()
  → AsciiAnimation::schedule_next_frame()  // 调度下一帧（将回到 frame_1）
  → AsciiAnimation::current_frame()        // 获取 frame_36
  → frame.lines().map(Into::into)          // 转换为 Line
  → Paragraph::new()                       // 创建段落
  → render()                               // 渲染
```

## 依赖与外部交互

### 帧序列上下文
```
... → frame_34 → frame_35 → frame_36 → frame_1 → frame_2 → ...
                        ↑_____________|
                           (循环)
```

### 依赖关系
```
frame_36.txt
  ↑ include_str! (编译时)
FRAMES_BLOCKS[35]
  ↑
AsciiAnimation::frames()
  ↑
AsciiAnimation::current_frame() → 模36循环
  ↑
WelcomeWidget
```

## 风险、边界与改进建议

### 风险

1. **循环不连贯**：
   - 若 frame_36 与 frame_1 的视觉差异过大，会出现明显的"跳跃"
   - 当前设计：frame_36 应该与 frame_1 视觉上接近，形成平滑过渡

2. **帧数不匹配**：
   - 宏定义硬编码36帧，若实际文件数量不同会导致编译错误
   - 风险：添加/删除帧时需要同步修改宏

### 边界

1. **时间边界**：
   - 显示时间：2800ms-2880ms
   - 之后立即回到 frame_1（2880ms 时）

2. **变体切换**：
   - Ctrl+. 可在任何时候切换变体
   - 切换后从当前索引继续，可能跳到不同变体的"frame_36"

### 改进建议

1. **循环平滑度验证**：
   ```rust
   #[test]
   fn loop_smoothness() {
       let first = FRAMES_BLOCKS[0];
       let last = FRAMES_BLOCKS[35];
       // 验证首尾帧相似度...
   }
   ```

2. **可配置循环**：
   ```rust
   pub(crate) enum LoopMode {
       Continuous,   // 当前：无限循环
       Once,         // 播放一次后停止
       PingPong,     // 正放后倒放
   }
   ```

3. **动态帧率调整**：
   - 根据系统负载在最后几帧调整帧率
   - 确保循环点不掉帧

---

**文件元数据**：
- 路径：`codex-rs/tui_app_server/frames/blocks/frame_36.txt`
- 大小：1132 bytes
- 行数：17行
- 帧序号：36/36（最后一帧）
- 变体：blocks
- 显示时间：2800ms-2880ms
- 周期位置：100%（周期结束）
- 下一帧：frame_1.txt（循环）
