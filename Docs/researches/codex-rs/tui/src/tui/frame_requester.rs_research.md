# frame_requester.rs 深度研究文档

## 场景与职责

`frame_requester.rs` 是 Codex TUI 的**帧绘制调度中心**，实现了 Actor 模式的设计，用于协调和优化 UI 重绘请求。核心职责包括：

1. **请求合并（Coalescing）**：将多个并发的绘制请求合并为单一实际绘制，避免重复渲染
2. **帧率限制**：与 `FrameRateLimiter` 配合，限制最大绘制频率为 120 FPS
3. **延迟调度**：支持延迟绘制（`schedule_frame_in`），用于动画和定时更新
4. **广播通知**：通过 `broadcast::channel` 通知所有订阅者进行绘制

设计模式参考：[Actors with Tokio](https://ryhl.io/blog/actors-with-tokio/)

## 功能点目的

### FrameRequester - 轻量级请求句柄
- **Cloneable**：可自由复制并在多任务间共享
- **非阻塞**：发送请求后立即返回，不等待实际绘制
- **两种调度方式**：
  - `schedule_frame()`：立即请求绘制
  - `schedule_frame_in(duration)`：延迟指定时间后绘制

### FrameScheduler - 后台调度任务
- **Actor 模式**：独立任务运行调度逻辑
- **请求合并**：多个请求在截止时间前到达时合并为一次绘制
- **生命周期管理**：当所有 `FrameRequester` 被丢弃时自动退出

### 测试辅助
- `test_dummy()`：创建无操作的请求器，用于单元测试

## 具体技术实现

### 关键数据结构

```rust
/// 帧请求句柄（克隆共享）
#[derive(Clone, Debug)]
pub struct FrameRequester {
    frame_schedule_tx: mpsc::UnboundedSender<Instant>,
}

/// 帧调度器（内部 Actor）
struct FrameScheduler {
    receiver: mpsc::UnboundedReceiver<Instant>,
    draw_tx: broadcast::Sender<()>,
    rate_limiter: FrameRateLimiter,
}
```

### 核心算法流程

#### 1. 创建与启动
```rust
impl FrameRequester {
    pub fn new(draw_tx: broadcast::Sender<()>) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let scheduler = FrameScheduler::new(rx, draw_tx);
        tokio::spawn(scheduler.run());  // 启动 Actor 任务
        Self { frame_schedule_tx: tx }
    }
}
```

#### 2. 调度循环 (FrameScheduler::run)
```rust
async fn run(mut self) {
    const ONE_YEAR: Duration = Duration::from_secs(60 * 60 * 24 * 365);
    let mut next_deadline: Option<Instant> = None;
    
    loop {
        // 计算等待目标：有截止时间则等截止，否则等一年（ effectively 无限）
        let target = next_deadline.unwrap_or_else(|| Instant::now() + ONE_YEAR);
        let deadline = tokio::time::sleep_until(target.into());
        tokio::pin!(deadline);
        
        tokio::select! {
            // 分支 1：接收新的绘制请求
            draw_at = self.receiver.recv() => {
                let Some(draw_at) = draw_at else { break };  // 所有发送者被丢弃
                
                // 应用帧率限制
                let draw_at = self.rate_limiter.clamp_deadline(draw_at);
                
                // 合并到最早截止时间
                next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
                
                // 关键：不立即发送，继续循环让 sleep 分支处理
                continue;
            }
            
            // 分支 2：截止时间到达
            _ = &mut deadline => {
                if next_deadline.is_some() {
                    next_deadline = None;
                    self.rate_limiter.mark_emitted(target);
                    let _ = self.draw_tx.send(());  // 广播绘制通知
                }
            }
        }
    }
}
```

#### 3. 请求合并策略
- **多个立即请求**：合并为单一绘制（通过 `continue` 让定时器触发）
- **立即 + 延迟请求**：取最早时间（`cur.min(draw_at)`）
- **多个延迟请求**：取最早截止时间

### 时序示例

```
时间线 ──────────────────────────────────────────────▶

请求:  [A:now]  [B:now]    [C:+50ms]        [D:now]
       │        │          │              │
       ▼        ▼          ▼              ▼
合并:  └─ 单次绘制 ─┘      └── 绘制 ─┘    └── 绘制 ─┘
       (t=0)              (t=50ms)        (t=~58ms)
                                         (受 120fps 限制)
```

## 关键代码路径与文件引用

### 本文件关键行
| 行号 | 内容 | 说明 |
|-----|------|------|
| 24-34 | `FrameRequester` 结构体 | 公开 API |
| 36-57 | `FrameRequester` 实现 | 构造函数和调度方法 |
| 59-68 | `test_dummy()` | 测试辅助 |
| 70-80 | `FrameScheduler` 结构体 | Actor 状态 |
| 82-128 | `FrameScheduler::run` | 核心调度循环 |
| 130-354 | 测试模块 | 全面测试覆盖 |

### 调用方文件（广泛使用）
| 文件 | 使用场景 |
|------|----------|
| `app.rs` (多处) | 各种 UI 状态变化时请求重绘 |
| `chatwidget.rs` | 聊天内容更新、流式输出 |
| `status_indicator_widget.rs` | 动画帧更新 |
| `pager_overlay.rs` | 滚动动画 |
| `ascii_animation.rs` | ASCII 动画帧 |
| `model_migration.rs` | 模型迁移 UI 更新 |
| `cwd_prompt.rs` | 路径提示更新 |
| `app_backtrack.rs` | 回溯 UI 更新 |
| `resume_picker.rs` | 恢复选择器更新 |
| `bottom_pane/chat_composer.rs` | 输入框更新 |
| `bottom_pane/mod.rs` | 底部面板更新 |
| `onboarding/*.rs` | 引导界面动画 |

### 依赖文件
| 文件 | 依赖内容 |
|------|----------|
| `frame_rate_limiter.rs` | `FrameRateLimiter`, `MIN_FRAME_INTERVAL` |
| `tui.rs:262-263` | `Tui::new` 中创建 `FrameRequester` |
| `tui.rs:298-300` | `frame_requester()` 方法暴露句柄 |

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `tokio::sync` | `broadcast`, `mpsc` 异步通道 |
| `std::time` | `Duration`, `Instant` 时间类型 |

### 模块关系图
```
┌─────────────────────────────────────────────────────────────┐
│                        Tui                                  │
│  ┌─────────────────┐      ┌─────────────────────────────┐  │
│  │  FrameRequester │─────▶│  broadcast::Sender<()>      │  │
│  │  (克隆分发)      │      │  (draw_tx)                  │  │
│  └─────────────────┘      └──────────────┬──────────────┘  │
│         │                                  │                │
│         │  spawn                           │ subscribe      │
│         ▼                                  ▼                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              FrameScheduler (Actor 任务)             │   │
│  │  ┌─────────────┐    ┌─────────────────────────────┐ │   │
│  │  │ mpsc::recv  │◀───│  schedule_frame()           │ │   │
│  │  └─────────────┘    │  schedule_frame_in()        │ │   │
│  │         │           └─────────────────────────────┘ │   │
│  │         ▼                                          │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │ FrameRateLimiter::clamp_deadline()          │   │   │
│  │  │ (限制 120 FPS)                               │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  │         │                                          │   │
│  │         ▼                                          │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │ broadcast::Sender::send(())  // 通知绘制     │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    TuiEventStream                           │
│              (订阅 draw_rx，生成 TuiEvent::Draw)             │
└─────────────────────────────────────────────────────────────┘
```

### 与 EventStream 的协作
1. `FrameScheduler` 通过 `draw_tx.send(())` 广播绘制通知
2. `TuiEventStream` 订阅 `draw_rx`，接收后生成 `TuiEvent::Draw`
3. 应用主循环处理 `TuiEvent::Draw` 调用渲染逻辑

## 风险、边界与改进建议

### 潜在风险

1. **任务泄漏**
   - 如果 `FrameRequester` 被泄漏（未 drop），`FrameScheduler` 任务将持续运行
   - 缓解：通常与 `Tui` 生命周期绑定，应用退出时整体清理

2. **广播 channel 满**
   - 如果消费者（`TuiEventStream`）处理缓慢，广播可能失败
   - 缓解：使用 `let _ =` 忽略发送错误，旧绘制通知可丢弃

3. **定时器精度**
   - `tokio::time` 的精度取决于运行时配置和系统负载
   - 缓解：120 FPS 目标留有足够余量，轻微抖动可接受

4. **时间溢出**
   - `ONE_YEAR` 常量 + `Instant::now()` 在极长时间运行后可能溢出
   - 缓解：实际应用不可能连续运行一年不重启

### 边界情况

| 场景 | 行为 |
|------|------|
| 所有 requester 被丢弃 | `recv()` 返回 `None`，Actor 任务退出 |
| 快速连续请求 | 合并为单一绘制，受 120 FPS 限制 |
| 延迟请求早于当前 | 立即触发（经过 clamp） |
| 系统时间跳跃 | `Instant` 单调，不受影响 |
| 广播无订阅者 | 消息被丢弃，不影响调度 |

### 测试覆盖

| 测试 | 验证内容 |
|------|----------|
| `test_schedule_frame_immediate_triggers_once` | 立即请求只触发一次绘制 |
| `test_schedule_frame_in_triggers_at_delay` | 延迟请求在指定时间触发 |
| `test_coalesces_multiple_requests_into_single_draw` | 多个请求合并为一次绘制 |
| `test_coalesces_mixed_immediate_and_delayed_requests` | 混合请求取最早时间 |
| `test_limits_draw_notifications_to_120fps` | 帧率限制生效 |
| `test_rate_limit_clamps_early_delayed_requests` | 早期延迟请求被限制 |
| `test_rate_limit_does_not_delay_future_draws` | 不影响未来的正常请求 |
| `test_multiple_delayed_requests_coalesce_to_earliest` | 多个延迟请求合并到最早 |

### 改进建议

1. **优先级调度**
   - 当前所有请求平等，可添加优先级（如用户输入 > 动画）
   - 高优先级请求可中断当前等待

2. **批量通知**
   - 当前每次绘制是单一通知，可考虑批量（如 "绘制 3 帧"）
   - 对慢速消费者更友好

3. **统计与监控**
   - 添加绘制计数器、延迟直方图
   - 检测帧率下降并警告

4. **自适应帧率**
   - 根据系统负载动态调整目标帧率
   - 电池模式降低帧率

5. **取消机制**
   - 添加 `cancel_frame()` 允许取消待处理的绘制
   - 对快速变化的状态有用（如输入框）

6. **多显示器支持**
   - 根据显示器刷新率调整目标帧率
   - 需要检测显示器 VRR 能力

7. **代码优化**
   - `ONE_YEAR` 可替换为 `Option::None` 表示无限等待
   - 使用 `tokio::select!` 的 `biased` 模式控制优先级

### 性能特征

- **消息传递**：`O(1)` - 无界 channel 发送
- **合并操作**：`O(1)` - 简单的 `min` 比较
- **内存使用**：`O(1)` - 固定大小的状态
- **任务开销**：单一轻量级 tokio 任务
