# frame_28.txt 研究文档

## 场景与职责

`frame_28.txt` 是 Codex TUI 欢迎界面 ASCII 动画序列的第 28 帧。该帧展示 Codex 标志在展开过程中的一个过渡形态，位于 36 帧动画循环的后段。

## 功能点目的

1. **接近完成**：作为第 28 帧，标志接近完全展开状态
2. **循环尾声**：距离完成循环还有 8 帧
3. **准备循环**：为无缝回到 frame_1 做准备

## 具体技术实现

### 文件规格
- **帧序号**：28 / 36
- **循环位置**：77.8%（28/36）
- **显示时间**：动画开始后约 2160ms
- **文件大小**：662 字节

### 剩余循环
```
已完成: 28 帧 = 2240ms
剩余: 8 帧 = 640ms
完成度: 77.8%
```

### 技术实现细节
```rust
// FrameScheduler 调度逻辑
async fn run(mut self) {
    const ONE_YEAR: Duration = Duration::from_secs(60 * 60 * 24 * 365);
    let mut next_deadline: Option<Instant> = None;
    
    loop {
        let target = next_deadline.unwrap_or_else(|| Instant::now() + ONE_YEAR);
        let deadline = tokio::time::sleep_until(target.into());
        tokio::pin!(deadline);
        
        tokio::select! {
            draw_at = self.receiver.recv() => {
                let Some(draw_at) = draw_at else { break };
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
                continue;
            }
            _ = &mut deadline => {
                if next_deadline.is_some() {
                    next_deadline = None;
                    self.rate_limiter.mark_emitted(target);
                    let _ = self.draw_tx.send(());  // 触发绘制
                }
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 文件链
```
frame_28.txt
  → include_str! → FRAMES_CODEX[27]
    → AsciiAnimation
      → WelcomeWidget
        → 终端显示
```

### 相关测试
- `frame_requester.rs:136-157`：测试立即触发帧
- `frame_requester.rs:159-183`：测试延迟帧

## 依赖与外部交互

### 编译时依赖
- `include_str!` 宏
- 文件路径解析

### 运行时依赖
- Tokio 异步运行时
- `FrameRateLimiter` 限制最大 120 FPS

## 风险、边界与改进建议

### 风险点
1. **循环衔接**：frame_36 到 frame_1 的过渡必须自然
2. **时序精度**：长时间运行后的时钟漂移

### 改进建议
1. **循环验证**：添加测试验证 36 帧循环的连续性
2. **自适应帧率**：根据系统负载动态调整
3. **暂停/恢复**：支持用户暂停动画
