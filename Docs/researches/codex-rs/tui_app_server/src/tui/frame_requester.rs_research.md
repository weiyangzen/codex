# frame_requester.rs 深度研究文档

## 场景与职责

`frame_requester.rs` 是 Codex TUI 的帧调度核心模块，实现了**绘制请求的合并与调度**机制。它解决了 TUI 中多个组件可能同时请求重绘时的效率问题。

### 核心问题

在复杂的 TUI 应用中，以下场景会频繁触发重绘请求：
1. **动画效果**：加载指示器、状态点闪烁、进度条
2. **实时数据**：日志流、音频波形、网络状态
3. **用户交互**：键盘输入、鼠标移动、窗口调整

如果这些请求都立即触发重绘，会导致：
- CPU/GPU 资源浪费
- 终端闪烁
- 电池消耗（笔记本）

### 解决方案

`FrameRequester` + `FrameScheduler` 采用**Actor 模式**：
- **FrameRequester**：轻量级句柄，可克隆分发到各处
- **FrameScheduler**：后台任务，合并请求并按时调度

### 设计参考

明确参考了 ["Actors with Tokio"](https://ryhl.io/blog/actors-with-tokio/) 博客文章，采用经典的 Actor 设计模式：
- 消息传递（`mpsc::UnboundedSender<Instant>`）
- 单线程处理（`tokio::spawn`）
- 状态封装（`FrameScheduler` 持有所有状态）

## 功能点目的

### FrameRequester - 公开句柄

```rust
#[derive(Clone, Debug)]
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}
```

**核心方法**：
| 方法 | 用途 |
|------|------|
| `schedule_frame()` | 立即请求重绘 |
| `schedule_frame_in(dur)` | 延迟一段时间后请求重绘 |

**设计特点**：
- `Clone`：可自由分发到多个任务和组件
- `UnboundedSender`：发送不会阻塞，简化调用方逻辑
- 发送失败静默处理（`let _ = ...`）：调度器关闭时无需处理错误

### FrameScheduler - 内部调度器

```rust
struct FrameScheduler {
    receiver: mpsc::UnboundedReceiver<Instant>,
    draw_tx: broadcast::Sender<()>,
    rate_limiter: FrameRateLimiter,
}
```

**核心职责**：
1. **请求合并**：多个请求在截止时间前到达，合并为一次绘制
2. **时间调度**：使用 `tokio::time::sleep_until` 精确控制绘制时机
3. **帧率限制**：通过 `FrameRateLimiter` 限制最高 120 FPS

### 测试专用接口

```rust
#[cfg(test)]
impl FrameRequester {
    pub(crate) fn test_dummy() -> Self {
        let (tx, _rx) = mpsc::unbounded_channel();
        FrameRequester { frame_schedule_tx: tx }
    }
}
```

- 允许测试代码创建无实际效果的 `FrameRequester`
- 避免在测试中启动后台任务

## 具体技术实现

### 关键流程 1：调度循环

```rust
async fn run(mut self) {
    const ONE_YEAR: Duration = Duration::from_secs(60 * 60 * 24 * 365);
    let mut next_deadline: Option<Instant> = None;
    loop {
        let target = next_deadline.unwrap_or_else(|| Instant::now() + ONE_YEAR);
        let deadline = tokio::time::sleep_until(target.into());
        tokio::pin!(deadline);

        tokio::select! {
            draw_at = self.receiver.recv() => {
                let Some(draw_at) = draw_at else { break };  // 所有发送者关闭
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
                continue;  // 不立即发送，继续循环等待截止时间
            }
            _ = &mut deadline => {
                if next_deadline.is_some() {
                    next_deadline = None;
                    self.rate_limiter.mark_emitted(target);
                    let _ = self.draw_tx.send(());  // 通知 TUI 重绘
                }
            }
        }
    }
}
```

**算法解析**：

1. **等待策略**：
   - 有截止时间时：`sleep_until(target)`
   - 无截止时间时：`sleep_until(now + ONE_YEAR)`（实际上无限等待）

2. **请求处理分支**：
   - 接收新请求时间 `draw_at`
   - 通过 `rate_limiter.clamp_deadline` 限制最早时间
   - 与当前截止时间比较，取更早者（`cur.min(draw_at)`）
   - **关键**：`continue` 不立即发送，等待 sleep 分支触发

3. **截止时间到达分支**：
   - 发送广播通知 `draw_tx.send(())`
   - 记录发射时间 `mark_emitted`
   - 重置 `next_deadline`

**合并机制示例**：
```
t=0ms: 请求 A (立即) → next_deadline = max(now, last+8.33ms) = t+8.33ms
       继续循环，等待 sleep_until(t+8.33ms)
t=1ms: 请求 B (立即) → next_deadline = min(t+8.33ms, t+8.33ms) = t+8.33ms
       继续循环，等待 sleep_until(t+8.33ms)
t=8.33ms: sleep 到期 → 发送一次绘制通知，合并了 A 和 B
```

### 关键流程 2：创建与启动

```rust
impl FrameRequester {
    pub fn new(draw_tx: broadcast::Sender<()>) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let scheduler = FrameScheduler::new(rx, draw_tx);
        tokio::spawn(scheduler.run());  // 启动后台任务
        Self { frame_schedule_tx: tx }
    }
}
```

**生命周期管理**：
- `FrameRequester` 持有 `frame_schedule_tx`
- 当最后一个 `FrameRequester` 被 drop，`tx` 被 drop
- `scheduler.run()` 中 `receiver.recv()` 返回 `None`，任务退出
- 无需显式停止，自动清理

### 数据结构详解

#### 消息流

```
调用方 (任意任务)
    │ schedule_frame() / schedule_frame_in()
    ▼
frame_schedule_tx (mpsc::UnboundedSender<Instant>)
    │
    ▼
FrameScheduler::receiver (mpsc::UnboundedReceiver<Instant>)
    │ 合并 + 限制
    ▼
draw_tx (broadcast::Sender<()>) ──► TuiEventStream::draw_stream
    │
    ▼
TUI 事件循环处理 TuiEvent::Draw
```

#### 时间线示例

```
时间轴:
  0ms    1ms    8ms    9ms    16ms   20ms
   │      │      │      │      │      │
   ▼      ▼      ▼      ▼      ▼      ▼
  [请求A] [请求B]      [请求C]       [请求D]
     \    /            │             │
      \  /             │             │
   合并为一次          │             │
   在 t=8.33ms        │             │
      │               │             │
      ▼               ▼             ▼
   [绘制1]         [绘制2]      [绘制3]
   (A+B)            (C)          (D)
```

## 关键代码路径与文件引用

### 模块内引用

| 路径 | 用途 |
|------|------|
| `super::frame_rate_limiter::FrameRateLimiter` | 帧率限制 |
| `super::frame_rate_limiter::MIN_FRAME_INTERVAL` | 测试中使用 |

### 调用方（外部使用）

| 文件 | 使用方式 |
|------|----------|
| `tui.rs:39` | `pub use self::frame_requester::FrameRequester;` |
| `tui.rs:263` | `let frame_requester = FrameRequester::new(draw_tx.clone());` |
| `tui.rs:298-300` | `pub fn frame_requester(&self) -> FrameRequester { self.frame_requester.clone() }` |
| `tui.rs:445` | `self.frame_requester().schedule_frame();`（插入历史行后） |

### 被调用方（依赖）

| 依赖 | 用途 |
|------|------|
| `tokio::sync::{broadcast, mpsc}` | 异步通道 |
| `std::time::{Duration, Instant}` | 时间计算 |

### 跨模块调用链

```
chatwidget.rs / status_indicator_widget.rs / etc.
    │
    ▼ 调用
Tui::frame_requester().schedule_frame()
    │
    ▼ 内部调用
FrameRequester::schedule_frame()
    │
    ▼ mpsc 发送
FrameScheduler::run()
    │
    ▼ broadcast 发送
TuiEventStream::poll_draw_event()
    │
    ▼ Stream::poll_next
App 事件循环
```

## 依赖与外部交互

### 外部 crate 依赖

```rust
use std::time::{Duration, Instant};
use tokio::sync::{broadcast, mpsc};
```

### 与 frame_rate_limiter 的交互

```rust
// 请求时限制
let draw_at = self.rate_limiter.clamp_deadline(draw_at);

// 发射时记录
self.rate_limiter.mark_emitted(target);
```

- `FrameRateLimiter` 是私有依赖，对调用方透明
- 限制逻辑封装在调度器内部

### 与 event_stream 的交互

```rust
// FrameRequester::new 接收 draw_tx
draw_tx: broadcast::Sender<()>

// TuiEventStream 订阅 draw_rx
draw_stream: BroadcastStream<()>
```

- 使用 `broadcast::channel(1)`，容量为 1（最新值足够）
- `TuiEventStream` 将 `()` 转换为 `TuiEvent::Draw`

## 风险、边界与改进建议

### 已知风险

1. **无界通道风险**
   - 使用 `mpsc::unbounded_channel`，可能无限堆积
   - **缓解**：请求只是 `Instant`（16 字节），堆积内存影响小
   - **极端场景**：如果调度任务被阻塞，发送方可能堆积大量请求

2. **广播通道 lagged**
   - `broadcast::channel(1)` 容量小，慢消费者可能 lagged
   - **处理**：`event_stream.rs` 中 lagged 也触发 `TuiEvent::Draw`
   - **影响**：只是多绘制一次，无功能性影响

3. **时间精度**
   - `tokio::time` 基于协作式调度，非硬实时
   - 实际绘制时间可能晚于目标时间
   - **影响**：低，TUI 不需要严格实时

### 边界情况

1. **所有发送者关闭**
   ```rust
   let Some(draw_at) = draw_at else { break };
   ```
   - 优雅退出，无资源泄漏

2. **立即请求与延迟请求合并**
   ```rust
   requester.schedule_frame_in(Duration::from_millis(100));
   requester.schedule_frame();  // 合并到立即执行
   ```
   - 测试验证：取最早时间，立即执行

3. **高频率请求（>120 FPS）**
   - `FrameRateLimiter` 将请求钳制到最小间隔
   - 测试验证：即使连续请求，也限制在 120 FPS

4. **极长延迟请求**
   ```rust
   const ONE_YEAR: Duration = Duration::from_secs(60 * 60 * 24 * 365);
   ```
   - 无截止时间时用 `now + ONE_YEAR` 代替无限等待
   - 实际上等同于无限等待，但避免了特殊值

### 改进建议

1. **有界通道**
   - 考虑使用有界通道防止极端情况下的内存增长
   - 例如：`mpsc::channel(1000)`，满时丢弃最旧请求

2. **优先级请求**
   - 添加 `schedule_frame_priority()` 方法，绕过合并立即执行
   - 用于紧急场景（如错误提示）

3. **统计与可观测性**
   - 添加指标：
     - 请求计数
     - 合并计数
     - 实际 FPS
     - 延迟分布

4. **自适应帧率**
   - 根据实际渲染耗时调整目标帧率
   - 如果渲染一帧需要 20ms，自动降至 50 FPS

5. **批量通知**
   - 当前使用 `()` 作为通知，可考虑携带更多信息：
     ```rust
     struct DrawRequest {
         reason: DrawReason,  // Animation, Input, Resize, etc.
         priority: Priority,
     }
     ```
   - 允许 TUI 根据原因优化渲染

6. **测试扩展**
   - 当前测试覆盖：
     - 立即请求
     - 延迟请求
     - 合并请求
     - 帧率限制
   - 可添加：
     - 长时间运行稳定性
     - 并发压力测试
     - 与 event_stream 集成测试

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 设计模式 | ★★★★★ | Actor 模式应用恰当 |
| 简洁性 | ★★★★★ | 128 行代码，职责清晰 |
| 可测试性 | ★★★★★ | 使用 `tokio::time::pause` 精确控制时间 |
| 文档 | ★★★★★ | 模块级文档详细，引用外部博客 |
| 性能 | ★★★★☆ | 无界通道有潜在风险 |

### 总结

`frame_requester.rs` 是 TUI 渲染流水线的**调度中枢**，通过 Actor 模式实现了：
- **请求合并**：减少不必要的重绘
- **帧率限制**：防止资源浪费
- **异步解耦**：调用方无需等待渲染完成

其设计简洁、测试完善，是异步 Rust TUI 应用的优秀参考实现。
