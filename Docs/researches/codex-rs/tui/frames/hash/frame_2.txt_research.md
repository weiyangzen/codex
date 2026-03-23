# frame_2.txt 研究文档

## 场景与职责

`frame_2.txt` 是 Codex TUI `hash` 动画变体的第 2 帧，是 36 帧动画序列中的第二帧。它延续了第 1 帧的视觉风格，展示了一个向外扩散的哈希图案动画。

### 在动画序列中的位置
- **前一帧**: `frame_1.txt`
- **后一帧**: `frame_3.txt`
- **序列索引**: 1 (0-based) / 2 (1-based)

### 视觉演变
从第 1 帧到第 2 帧，图案呈现出轻微的扩张和变形效果，字符分布更加分散，营造出动态流动的视觉效果。

## 功能点目的

### 动画连续性
作为序列中的第 2 帧，它的作用是：
1. 承接第 1 帧的视觉状态
2. 展示图案的微小变化
3. 为后续帧的动画效果铺垫

### 字符构成分析
```
主要字符:
- █ (完整块): 构成图案主体
- # (井号): 轮廓和结构线
- * (星号): 装饰性细节，比第 1 帧更分散
- - (连字符): 连接线
- . (点): 点缀元素
- A (字母): 特殊标记
```

## 具体技术实现

### 编译时嵌入
```rust
// frames.rs - 第 8 行
include_str!(concat!("../frames/", $dir, "/frame_2.txt"))
```

### 运行时访问
```rust
// 通过 FRAMES_HASH 数组访问
let frame_2_content = FRAMES_HASH[1];  // 0-based index
```

### 渲染时机
```
时间线 (假设从 t=0 开始):
t=0ms     -> frame_1.txt (索引 0)
t=80ms    -> frame_2.txt (索引 1)  <-- 本帧
t=160ms   -> frame_3.txt (索引 2)
...
```

## 关键代码路径与文件引用

### 完整调用链
```
frame_2.txt
  ↓ 编译时
frames.rs:FRAMES_HASH[1]
  ↓ 运行时
ascii_animation.rs
  - start: Instant (动画开始时间)
  - frame_tick: Duration::from_millis(80)
  - current_frame() 计算索引
      idx = (elapsed_ms / 80) % 36
      当 elapsed_ms = 80 时，idx = 1
  ↓
welcome.rs:WelcomeWidget
  ↓
ratatui::Paragraph::new(frame_content)
  ↓
终端渲染
```

### 核心算法
```rust
// ascii_animation.rs:65-77
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    if frames.is_empty() { return ""; }
    
    let tick_ms = self.frame_tick.as_millis();  // 80
    if tick_ms == 0 { return frames[0]; }
    
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / tick_ms) % frames.len() as u128) as usize;
    // 当 elapsed_ms = 80..159 时，idx = 1
    frames[idx]  // frame_2.txt
}
```

## 依赖与外部交互

### 与第 1 帧的关系
- 视觉风格保持一致
- 字符分布略有变化，形成动画效果
- 尺寸相同（17 行）

### 与动画系统的交互
| 组件 | 交互方式 | 说明 |
|------|----------|------|
| `FrameRequester` | 调度渲染 | 每 80ms 请求重绘 |
| `FrameScheduler` | 合并请求 | 避免过度渲染 |
| `FrameRateLimiter` | 限制 120 FPS | 防止资源浪费 |

### 尺寸对比
```
frame_1.txt: 712 bytes
frame_2.txt: 708 bytes  (-4 bytes，字符分布更紧凑)
```

## 风险、边界与改进建议

### 动画同步风险
1. **帧率变化**: 如果 `FRAME_TICK_DEFAULT` 被修改，动画速度会改变
2. **跳帧**: 如果渲染延迟，可能会跳过某些帧

### 视觉一致性
- 与第 1 帧相比，图案中心区域的 `█` 字符分布略有不同
- 边缘的 `#` 和 `*` 字符位置有所调整

### 改进建议
1. **帧间差异验证**: 添加测试确保相邻帧有可见变化但不过于剧烈
2. **循环平滑性**: 验证 frame_36 到 frame_1 的过渡是否自然
3. **文件大小优化**: 当前 708 bytes，可考虑压缩或优化字符布局

### 调试信息
如需调试该帧的渲染：
```rust
// 在 welcome.rs 中添加日志
 tracing::debug!("Rendering frame: idx={}, content_len={}", 
     idx, 
     frame.len()
 );
```

### 相关测试
```rust
// ascii_animation.rs:103-110
#[test]
fn frame_tick_must_be_nonzero() {
    assert!(FRAME_TICK_DEFAULT.as_millis() > 0);
}
```

### 文件引用汇总
- 本文件: `codex-rs/tui/frames/hash/frame_2.txt`
- 编译定义: `codex-rs/tui/src/frames.rs`
- 动画逻辑: `codex-rs/tui/src/ascii_animation.rs`
- 渲染位置: `codex-rs/tui/src/onboarding/welcome.rs`
