# frame_5.txt 研究文档

## 场景与职责

`frame_5.txt` 是 Codex TUI `hash` 动画变体的第 5 帧，在 36 帧动画序列中继续展示哈希图案的动态演变。

### 动画序列位置
- **帧索引**: 4 (0-based)
- **时间范围**: 320-399ms (80ms 帧间隔)
- **动画阶段**: 早期阶段，图案继续演变

### 视觉特征
该帧展示了图案向外扩散的效果，字符分布更加开阔，边缘的 `#` 和 `*` 字符形成了更清晰的轮廓。

## 功能点目的

### 动画连续性
作为第 5 帧，它在动画中承担：
1. 延续前 4 帧的视觉流动
2. 展示图案的扩张效果
3. 为中期帧（6-18）的复杂变化过渡

### 字符构成分析
```
frame_5.txt 视觉元素:
- 中心: █ 字符形成核心图案
- 中层: # 和 * 字符构成分层结构
- 外层: - 和 . 字符填充边缘
- 点缀: A 字符作为特殊标记
```

## 具体技术实现

### 编译时嵌入
```rust
// frames.rs 宏展开 (第 11 行)
include_str!(concat!("../frames/", $dir, "/frame_5.txt"))
```

### 运行时索引
```rust
// 在 AsciiAnimation::current_frame() 中
let idx = ((elapsed_ms / 80) % 36) as usize;
// 当 elapsed_ms = 320..399 时，idx = 4
let frame_content = FRAMES_HASH[4];  // frame_5.txt
```

### 帧调度逻辑
```rust
// 每帧调度间隔计算
let tick_ms = 80;
let elapsed_ms = start.elapsed().as_millis();
let frame_idx = (elapsed_ms / tick_ms) % 36;
// frame_5.txt 在 frame_idx = 4 时显示
```

## 关键代码路径与文件引用

### 渲染调用链
```
Terminal::draw()
  └─ WelcomeWidget::render_ref()
       ├─ Clear.render()  // 清屏
       ├─ AsciiAnimation::schedule_next_frame()  // 调度下一帧
       │    └─ FrameRequester::schedule_frame_in(Duration::from_millis(delay))
       ├─ AsciiAnimation::current_frame()  // 获取当前帧
       │    └─ FRAMES_HASH[4]  // frame_5.txt
       └─ Paragraph::new(frame_content).render()  // 渲染
```

### 关键代码位置

**帧数组访问** (`ascii_animation.rs:98-100`):
```rust
fn frames(&self) -> &'static [&'static str] {
    self.variants[self.variant_idx]  // 返回 FRAMES_HASH 等
}
```

**当前帧计算** (`ascii_animation.rs:65-77`):
```rust
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    // ... 索引计算
    frames[idx]  // 返回 frame_5.txt 等内容
}
```

**渲染** (`onboarding/welcome.rs:81-84`):
```rust
if show_animation {
    let frame = self.animation.current_frame();
    lines.extend(frame.lines().map(Into::into));
    lines.push("".into());
}
```

## 依赖与外部交互

### 动画系统组件
```
┌────────────────────────────────────────┐
│         AsciiAnimation                 │
│  - variant_idx: 5 (FRAMES_HASH 索引)   │
│  - frame_tick: 80ms                    │
│  - start: Instant                      │
└────────────┬───────────────────────────┘
             │
             ▼
┌────────────────────────────────────────┐
│         FrameRequester                 │
│  (请求重绘的轻量级句柄)                 │
└────────────────────────────────────────┘
```

### 与其他帧的关系
```
frame_1.txt ─┐
frame_2.txt ─┤
frame_3.txt ─┤ 早期帧
frame_4.txt ─┘
frame_5.txt ──> 当前帧 (图案扩张)
frame_6.txt ─┐
...          ├ 后续帧
frame_36.txt─┘
```

### 外部依赖
| 依赖 | 用途 | 版本 |
|------|------|------|
| ratatui | 终端 UI 渲染 | workspace |
| tokio | 异步调度 | workspace |
| crossterm | 终端控制 | workspace |

## 风险、边界与改进建议

### 潜在风险

1. **帧率限制**
   ```rust
   // FrameRateLimiter 限制 120 FPS
   // 如果 FRAME_TICK_DEFAULT < 8.33ms，会被限制
   const MIN_FRAME_INTERVAL: Duration = Duration::from_nanos(8_333_334);
   ```

2. **终端兼容性**
   - Unicode 字符 `█` 需要终端支持
   - 旧终端可能显示为方块或问号

### 边界情况

| 条件 | 处理 |
|------|------|
| 终端高度 < 37 | 跳过动画 |
| 终端宽度 < 60 | 跳过动画 |
| animations_enabled = false | 跳过动画 |
| 系统负载高 | 可能跳帧，但无错误 |

### 改进建议

1. **帧验证**
   ```rust
   // 编译时验证帧格式
   const _: () = {
       let frame = FRAMES_HASH[4];
       assert!(frame.is_ascii() || is_valid_utf8(frame));
   };
   ```

2. **性能监控**
   ```rust
   // 添加渲染时间追踪
   let start = Instant::now();
   // ... 渲染逻辑
   tracing::trace!("Frame render took {:?}", start.elapsed());
   ```

3. **可访问性**
   ```rust
   // 考虑添加 reduced-motion 支持
   if std::env::var("REDUCED_MOTION").is_ok() {
       // 显示静态帧或禁用动画
   }
   ```

### 相关测试
```rust
// frame_requester.rs 中的测试模式
#[tokio::test(flavor = "current_thread", start_paused = true)]
async fn test_animation_frame_timing() {
    // 验证帧切换时机
}
```

### 文件信息
```
路径: codex-rs/tui/frames/hash/frame_5.txt
大小: 702 bytes
行数: 17
相对大小: 比平均帧大 2 bytes
字符分布: █ # * - . A 混合
```
