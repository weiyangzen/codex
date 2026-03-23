# frame_11.txt 研究文档

## 场景与职责

`frame_11.txt` 是 Codex TUI 应用服务器启动动画的第 11 帧 ASCII 艺术图像，属于 `default` 动画变体。该帧在 36 帧循环序列中位于约 30% 进度点，展示标志动画的中间过渡状态。

## 功能点目的

1. **动画平滑过渡**：作为第 11 帧，在动画序列中承接前后帧，确保视觉连续性
2. **时间定位**：在默认 80ms 帧间隔下，约在动画开始后 880ms 显示
3. **循环协调**：与前后帧配合形成无缝循环动画效果

## 具体技术实现

### 技术规格
- **序列索引**：10（0-based）/ 11（1-based）
- **显示时间**：动画开始后约 880ms（11 × 80ms）
- **循环周期**：完整 36 帧循环约 2.88 秒（36 × 80ms）

### 帧访问路径

```rust
// frames.rs: FRAMES_DEFAULT 数组定义
pub(crate) const FRAMES_DEFAULT: [&str; 36] = [
    include_str!("../frames/default/frame_1.txt"),   // [0]
    // ... frame_2 到 frame_10
    include_str!("../frames/default/frame_11.txt"),  // [10] - 本文件
    // ... frame_12 到 frame_36
];
```

### 动画控制流程

```
WelcomeWidget::render_ref()
  ├── self.animation.schedule_next_frame()  // 安排下一帧
  ├── self.animation.current_frame()        // 获取当前帧（可能返回 frame_11）
  │   └── 计算: (elapsed_ms / 80) % 36
  └── frame.lines().map(Into::into)         // 渲染为文本行
```

## 关键代码路径与文件引用

| 文件路径 | 行号 | 职责 |
|---------|------|------|
| `frames/default/frame_11.txt` | - | 第 11 帧 ASCII 艺术内容 |
| `src/frames.rs` | 17 | 宏展开嵌入 frame_11.txt |
| `src/ascii_animation.rs` | 65-77 | `current_frame()` 计算方法 |
| `src/onboarding/welcome.rs` | 82 | 调用 `current_frame()` 获取帧内容 |

## 依赖与外部交互

### 变体切换机制
用户可通过 `Ctrl + .` 快捷键切换动画变体，系统会：
1. 随机选择新变体索引（`pick_random_variant()`）
2. 重置 `variant_idx` 为新索引
3. 立即触发重绘（`schedule_frame()`）

### 与 FrameRequester 的交互
- `schedule_next_frame()` 计算到下一帧的时间间隔
- 使用 `tokio::sync::mpsc` 通道与调度器通信
- 调度器合并多个请求，限制最高 120 FPS

## 风险、边界与改进建议

### 风险
1. **硬编码路径**：`frames_for!` 宏硬编码了 frame_1.txt 到 frame_36.txt 的路径，新增帧需修改宏
2. **内存占用**：36 帧全部嵌入二进制，增加约 36KB 静态数据

### 边界情况
- **快速切换**：用户快速按 `Ctrl + .` 可能导致帧显示不完整
- **后台恢复**：应用从后台恢复时，动画继续从之前的时间点播放

### 改进建议
1. **配置化帧数**：允许变体具有不同帧数，而非固定 36 帧
2. **压缩存储**：考虑使用压缩算法减少二进制体积
3. **动态加载**：开发模式下从文件系统加载，发布模式嵌入二进制
