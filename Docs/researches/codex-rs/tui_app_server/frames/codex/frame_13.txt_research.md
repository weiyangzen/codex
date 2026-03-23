# frame_13.txt 研究文档

## 场景与职责

`frame_13.txt` 是 Codex TUI 应用服务器中 ASCII 动画系统的第 13 帧，属于 `codex` 变体动画序列。

**动画序列位置**：第 13/36 帧
**时序位置**：960ms（第 13 个 80ms 间隔）

## 功能点目的

1. **动画序列延续**：作为 36 帧循环的第 13 帧，接近 1/3 周期点
2. **旋转效果**：展示 Codex 图标旋转约 120° 后的状态
3. **用户体验**：在终端启动期间提供持续的视觉反馈

## 具体技术实现

### 帧时序表
| 帧 | 索引 | 时间 | 角度 |
|---|------|------|------|
| frame_1 | 0 | 0ms | 0° |
| ... | ... | ... | ... |
| frame_13 | 12 | 960ms | 120° |
| ... | ... | ... | ... |
| frame_36 | 35 | 2800ms | 350° |

### 帧访问
```rust
// 直接索引访问
let content: &str = FRAMES_CODEX[12];

// 通过动画访问
let animation = AsciiAnimation::new(requester);
// 960ms 后调用 current_frame() 返回本帧
```

### 渲染流程
```rust
// 1. 调度器触发 (每 80ms)
frame_requester.schedule_frame_in(Duration::from_millis(80));

// 2. 计算当前帧
let idx = (elapsed_ms / 80) % 36;  // = 12

// 3. 获取内容
let frame = FRAMES_CODEX[idx as usize];

// 4. 渲染
Paragraph::new(frame).render(area, buf);
```

## 关键代码路径与文件引用

### 核心代码
```rust
// frames.rs
pub(crate) const FRAMES_CODEX: [&str; 36] = frames_for!("codex");
// 展开后包含 frame_13.txt

// ascii_animation.rs
pub(crate) fn current_frame(&self) -> &'static str {
    let frames = self.frames();
    let elapsed_ms = self.start.elapsed().as_millis();
    let idx = ((elapsed_ms / self.frame_tick.as_millis()) % frames.len() as u128) as usize;
    frames.get(idx).copied().unwrap_or("")
}
```

### 文件依赖
```
frame_13.txt
    ├── 编译依赖: 文件存在且可读
    ├── 格式要求: UTF-8 文本，17 行
    └── 运行时: 无文件系统依赖
```

## 依赖与外部交互

### 上游依赖
- `frame_12.txt`：前序帧
- `frame_14.txt`：后续帧

### 下游消费
- `WelcomeWidget`：主要消费者
- 可能的扩展：其他加载状态指示器

### 外部接口
```rust
// 用户控制
impl KeyboardHandler for WelcomeWidget {
    fn handle_key_event(&mut self, event: KeyEvent) {
        if event.code == KeyCode::Char('.') && event.modifiers == CONTROL {
            // 切换变体，重置到 frame_1
            self.animation.pick_random_variant();
        }
    }
}
```

## 风险、边界与改进建议

### 边界情况
1. **长时间运行**：动画无限循环，每 2.88 秒一个周期
2. **系统休眠**：`Instant` 是单调的，不受系统时间影响
3. **高负载**：帧率限制器确保不超过 120 FPS

### 改进建议
1. **暂停恢复**：检测终端失去焦点时暂停动画
2. **节能模式**：提供低帧率选项（如 5 FPS）
3. **无障碍支持**：提供关闭动画的选项

### 维护检查清单
- [ ] 所有 36 帧文件存在
- [ ] 所有帧尺寸一致（17x40）
- [ ] 帧序列形成连贯动画
- [ ] 编译无警告
