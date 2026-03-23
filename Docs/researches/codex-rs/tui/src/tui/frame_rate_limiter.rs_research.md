# frame_rate_limiter.rs 深度研究文档

## 场景与职责

`frame_rate_limiter.rs` 是 Codex TUI 的帧率限制器，核心职责是**限制绘制通知的最大频率为 120 FPS**。这是 TUI 渲染流水线中的关键性能优化组件：

1. **防止过度绘制**：Widgets 可能以高于用户感知能力的频率调用 `FrameRequester::schedule_frame()`，导致不必要的 CPU/GPU 开销
2. **平滑动画**：确保动画和状态更新以一致、可预测的帧率呈现
3. **资源节约**：避免在快速连续的状态更新中浪费渲染工作

该模块被设计为**小而纯的辅助模块**，可独立单元测试，并被异步帧调度器使用而不增加应用/事件循环的复杂性。

## 功能点目的

### FrameRateLimiter 结构体
- **核心功能**：记忆上次绘制发出时间，允许将请求的截止时间向前调整（clamp）以满足最小帧间隔
- **无状态默认**：首次绘制前不施加任何限制
- **线程安全**：通过 `&self` / `&mut self` 区分查询/更新操作，由调用者保证同步

### MIN_FRAME_INTERVAL 常量
- **值**：`Duration::from_nanos(8_333_334)`（约 8.33ms）
- **对应帧率**：120 FPS
- **选择理由**：
  - 高于典型显示器刷新率（60Hz）
  - 提供平滑的视觉体验
  - 不过度消耗 CPU 资源

## 具体技术实现

### 关键数据结构

```rust
/// 120 FPS 最小帧间隔（≈8.33ms）
pub(super) const MIN_FRAME_INTERVAL: Duration = Duration::from_nanos(8_333_334);

/// 记忆最近发出的绘制，允许将截止时间向前调整
#[derive(Debug, Default)]
pub(super) struct FrameRateLimiter {
    last_emitted_at: Option<Instant>,
}
```

### 核心算法

#### 1. 截止时间限制 (clamp_deadline)
```rust
pub(super) fn clamp_deadline(&self, requested: Instant) -> Instant {
    let Some(last_emitted_at) = self.last_emitted_at else {
        return requested;  // 首次绘制，不限制
    };
    
    // 计算最早允许的绘制时间
    let min_allowed = last_emitted_at
        .checked_add(MIN_FRAME_INTERVAL)
        .unwrap_or(last_emitted_at);
    
    // 取请求时间和最早允许时间的较大值
    requested.max(min_allowed)
}
```

**算法说明**：
- 如果 `requested` 早于 `min_allowed`，则推迟到 `min_allowed`
- 如果 `requested` 晚于 `min_allowed`，则保持原时间
- 使用 `checked_add` 防止 `Instant` 溢出（虽然实际不太可能发生）

#### 2. 标记已发出 (mark_emitted)
```rust
pub(super) fn mark_emitted(&mut self, emitted_at: Instant) {
    self.last_emitted_at = Some(emitted_at);
}
```

### 使用模式（与 FrameScheduler 配合）

```rust
// FrameScheduler::run 中的使用
async fn run(mut self) {
    let mut next_deadline: Option<Instant> = None;
    loop {
        // ... select 监听 ...
        
        draw_at = self.receiver.recv() => {
            let Some(draw_at) = draw_at else { break };
            
            // 关键：限制帧率
            let draw_at = self.rate_limiter.clamp_deadline(draw_at);
            
            // 合并多个请求到最早时间
            next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            continue;
        }
        
        _ = &mut deadline => {
            if next_deadline.is_some() {
                next_deadline = None;
                // 关键：记录发出时间
                self.rate_limiter.mark_emitted(target);
                let _ = self.draw_tx.send(());
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 本文件关键行
| 行号 | 内容 | 说明 |
|-----|------|------|
| 13 | `MIN_FRAME_INTERVAL` | 120 FPS 间隔常量 |
| 16-19 | `FrameRateLimiter` 结构体 | 核心数据结构 |
| 23-31 | `clamp_deadline` | 截止时间限制算法 |
| 34-36 | `mark_emitted` | 记录发出时间 |
| 39-62 | 测试模块 | 单元测试 |

### 调用方文件
| 文件 | 使用方式 |
|------|----------|
| `frame_requester.rs:79` | `FrameScheduler` 持有 `rate_limiter: FrameRateLimiter` |
| `frame_requester.rs:110` | `clamp_deadline(draw_at)` 限制请求时间 |
| `frame_requester.rs:121` | `mark_emitted(target)` 记录发出时间 |

### 被引用
| 文件 | 引用内容 |
|------|----------|
| `tui.rs:57` | `pub(crate) const TARGET_FRAME_INTERVAL: Duration = frame_rate_limiter::MIN_FRAME_INTERVAL;` |
| `app.rs:153` | `const COMMIT_ANIMATION_TICK: Duration = tui::TARGET_FRAME_INTERVAL;` |

## 依赖与外部交互

### 外部 crate
| Crate | 用途 |
|-------|------|
| `std::time` | `Duration`, `Instant` 时间类型 |

### 模块关系
```
frame_rate_limiter.rs
         │
         ▼
frame_requester.rs (FrameScheduler)
         │
         ▼
      tui.rs (Tui)
         │
         ▼
   各 UI 组件
```

### 与 FrameScheduler 的协作
1. `FrameScheduler` 接收绘制请求（`Instant`）
2. 通过 `clamp_deadline` 调整请求时间以满足 120 FPS 限制
3. 多个请求合并为最早的合法时间
4. 定时器触发后，通过 `mark_emitted` 记录实际发出时间
5. 发送绘制通知到广播 channel

## 风险、边界与改进建议

### 潜在风险

1. **时间溢出**
   - `Instant` 在极长时间运行后可能溢出
   - 缓解：使用 `checked_add`，溢出时回退到 `last_emitted_at`

2. **系统时间调整**
   - `Instant` 是单调时钟，不受系统时间调整影响，安全

3. **多线程竞争**
   - `FrameRateLimiter` 不是 `Sync`，但 `FrameScheduler` 是单任务运行，安全

### 边界情况

| 场景 | 行为 |
|------|------|
| 首次绘制 | `last_emitted_at` 为 `None`，不限制 |
| 请求时间早于上次 | 限制到 `last + MIN_FRAME_INTERVAL` |
| 请求时间晚于限制 | 保持原请求时间 |
| 溢出 | `checked_add` 失败，回退到 `last_emitted_at` |
| 连续快速请求 | 合并到单一绘制，间隔至少 8.33ms |

### 测试覆盖

| 测试 | 验证内容 |
|------|----------|
| `default_does_not_clamp` | 首次绘制不限制 |
| `clamps_to_min_interval_since_last_emit` | 限制到最小间隔 |

### 改进建议

1. **可配置帧率**
   - 当前 120 FPS 是硬编码，可考虑根据显示器刷新率或用户配置调整
   - 添加 `FrameRateLimiter::with_fps(fps: u32)` 构造函数

2. **自适应帧率**
   - 检测到连续丢帧时可自动降低目标帧率
   - 需要与性能监控集成

3. **更精确的定时**
   - 当前使用 `tokio::time::sleep_until`，精度取决于运行时
   - 可考虑使用更精确的定时器（如 `timerfd` on Linux）

4. **统计信息**
   - 添加被限制的请求计数，用于性能分析
   - 记录实际帧率与目标帧率的偏差

5. **文档增强**
   - 添加帧率限制对用户体验影响的说明
   - 说明 120 FPS 选择的技术依据

### 性能特征

- **时间复杂度**：`O(1)` - 简单的比较和赋值操作
- **空间复杂度**：`O(1)` - 仅存储一个 `Option<Instant>`
- **无堆分配**：完全栈上操作
- **无锁**：单线程使用，无需同步原语
