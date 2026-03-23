# frame_rate_limiter.rs 深度研究文档

## 场景与职责

`frame_rate_limiter.rs` 是 Codex TUI 的帧率限制模块，属于渲染流水线中的基础组件。其核心职责是**防止绘制通知过于频繁地发射**，避免不必要的重绘工作。

### 使用场景

1. **高频动画场景**：状态指示器、加载动画、实时音频波形等可能以极高频率请求重绘
2. **批量状态更新**：多个组件同时更新时可能产生大量重绘请求
3. **节能考虑**：限制不必要的渲染以降低 CPU/GPU 使用

### 设计哲学

- **小而纯（small, pure）**：模块设计为独立、可单元测试的辅助组件
- **无状态依赖**：仅依赖 `Instant` 时间戳，不依赖外部状态
- **可组合**：被 `FrameScheduler` 使用，不直接暴露给业务代码

## 功能点目的

### FrameRateLimiter 结构

```rust
#[derive(Debug, Default)]
pub(super) struct FrameRateLimiter {
    last_emitted_at: Option<Instant>,
}
```

**核心功能**：
1. **记录上次发射时间**：跟踪最近一次绘制通知的发射时刻
2. **限制最小间隔**：确保两次绘制间隔不小于 `MIN_FRAME_INTERVAL`（约 8.33ms，对应 120 FPS）
3. **向前钳制（clamp forward）**：当请求时间过早时，将其推迟到允许的最小时间

### MIN_FRAME_INTERVAL 常量

```rust
pub(super) const MIN_FRAME_INTERVAL: Duration = Duration::from_nanos(8_333_334);
```

- **数值来源**：1/120 秒 ≈ 8.333334 毫秒
- **选择理由**：120 FPS 是人眼难以察觉的流畅度上限，超过此频率的渲染是浪费
- **精度**：使用纳秒级精度避免浮点误差

## 具体技术实现

### 核心算法：clamp_deadline

```rust
pub(super) fn clamp_deadline(&self, requested: Instant) -> Instant {
    let Some(last_emitted_at) = self.last_emitted_at else {
        return requested;  // 首次请求，不限制
    };
    let min_allowed = last_emitted_at
        .checked_add(MIN_FRAME_INTERVAL)
        .unwrap_or(last_emitted_at);  // 溢出保护
    requested.max(min_allowed)  // 取较晚的时间
}
```

**算法逻辑**：
1. 如果没有上次发射记录（`None`），直接返回请求时间
2. 计算允许的最小时间 = 上次发射时间 + 最小间隔
3. 返回 `max(requested, min_allowed)`，确保不会早于允许时间

**时序示例**：
```
t0: 首次请求 → 返回 t0，记录 last_emitted_at = t0
t1 = t0 + 1ms: 第二次请求 → min_allowed = t0 + 8.33ms → 返回 t0 + 8.33ms
t2 = t0 + 10ms: 第三次请求 → min_allowed = t0 + 8.33ms → 返回 t2 (t2 > min_allowed)
```

### mark_emitted 方法

```rust
pub(super) fn mark_emitted(&mut self, emitted_at: Instant) {
    self.last_emitted_at = Some(emitted_at);
}
```

**调用时机**：
- 在 `FrameScheduler` 实际发送绘制通知后调用
- 记录发射时间用于下次限制计算

### 与 FrameScheduler 的协作

```rust
// frame_requester.rs 中的 FrameScheduler::run
async fn run(mut self) {
    // ...
    tokio::select! {
        draw_at = self.receiver.recv() => {
            let Some(draw_at) = draw_at else { break };
            let draw_at = self.rate_limiter.clamp_deadline(draw_at);  // 限制
            next_deadline = Some(next_deadline.map_or(draw_at, |cur| cur.min(draw_at)));
            continue;
        }
        _ = &mut deadline => {
            if next_deadline.is_some() {
                next_deadline = None;
                self.rate_limiter.mark_emitted(target);  // 记录发射
                let _ = self.draw_tx.send(());
            }
        }
    }
}
```

**协作流程**：
1. 收到绘制请求时，使用 `clamp_deadline` 调整目标时间
2. 多个请求合并时，取最早的有效时间（`cur.min(draw_at)`）
3. 实际发射时，使用 `mark_emitted` 记录时间

## 关键代码路径与文件引用

### 模块内引用

| 路径 | 用途 |
|------|------|
| 无 | 本模块无内部依赖 |

### 调用方（外部使用）

| 文件 | 使用方式 |
|------|----------|
| `frame_requester.rs:21` | `use super::frame_rate_limiter::FrameRateLimiter;` |
| `frame_requester.rs:79` | `FrameScheduler` 包含 `rate_limiter: FrameRateLimiter` |
| `frame_requester.rs:110` | `self.rate_limiter.clamp_deadline(draw_at)` |
| `frame_requester.rs:121` | `self.rate_limiter.mark_emitted(target)` |
| `tui.rs:57` | `pub(crate) const TARGET_FRAME_INTERVAL: Duration = frame_rate_limiter::MIN_FRAME_INTERVAL;` |

### 被调用方（依赖）

| 依赖 | 用途 |
|------|------|
| `std::time::{Duration, Instant}` | 时间计算 |

## 依赖与外部交互

### 外部 crate 依赖

```rust
use std::time::Duration;
use std::time::Instant;
```

- **纯标准库**：不依赖任何外部 crate，确保可移植性和测试简便性

### 与 frame_requester 的关系

```
frame_requester.rs
    ├── FrameRequester (公开句柄)
    ├── FrameScheduler (内部调度任务)
    │       └── FrameRateLimiter (本模块)
    └── MIN_FRAME_INTERVAL (导出到 tui.rs)
```

### 与 tui.rs 的关系

```rust
// tui.rs 重新导出帧率限制常量
pub(crate) const TARGET_FRAME_INTERVAL: Duration = frame_rate_limiter::MIN_FRAME_INTERVAL;
```

- 使其他模块可以通过 `tui::TARGET_FRAME_INTERVAL` 访问帧率限制

## 风险、边界与改进建议

### 已知风险

1. **时间回拨风险**
   - `Instant` 是单调时钟，不受系统时间调整影响
   - 但在某些虚拟化环境中，单调时钟也可能出现回拨
   - **当前处理**：`checked_add` 处理溢出，但未处理回拨
   - **风险等级**：极低

2. **精度限制**
   - 纳秒级精度在大多数平台上足够
   - 但某些平台的 `Instant` 实际精度可能只有微秒或毫秒
   - **影响**：可能无法严格达到 120 FPS 限制

### 边界情况

1. **首次发射**
   ```rust
   let limiter = FrameRateLimiter::default();
   assert_eq!(limiter.clamp_deadline(t0), t0);  // 不限制
   ```
   - 首次请求总是立即通过，确保响应性

2. **溢出处理**
   ```rust
   .checked_add(MIN_FRAME_INTERVAL)
   .unwrap_or(last_emitted_at)  // 溢出时使用原时间
   ```
   - 理论上 `Instant` 溢出需要数百年，但代码仍做了防护

3. **极短间隔请求**
   - 测试验证：1ms 间隔的请求会被钳制到 8.33ms
   - 确保不会频繁发射

### 改进建议

1. **自适应帧率**
   - 当前固定 120 FPS，可考虑根据终端能力或用户配置调整
   - 例如：高刷新率显示器可支持 144/240 FPS
   - 实现：将 `MIN_FRAME_INTERVAL` 改为可配置参数

2. **统计与监控**
   - 添加被限制的请求计数，用于性能分析
   - 例如：
     ```rust
     struct FrameRateLimiter {
         last_emitted_at: Option<Instant>,
         clamped_count: u64,  // 新增
     }
     ```

3. **动态调整**
   - 根据实际渲染耗时动态调整目标帧率
   - 如果渲染一帧需要 20ms，则目标帧率应自动降至 50 FPS

4. **与 vsync 集成**
   - 当前纯软件计时，可能与显示器刷新率不同步
   - 未来可考虑与终端的同步刷新信号集成

5. **测试扩展**
   - 当前测试覆盖基本功能，可添加：
     - 边界值测试（刚好 8.33ms 间隔）
     - 并发测试（多线程同时调用）
     - 长时间运行测试（检查漂移）

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 简洁性 | ★★★★★ | 38 行代码，职责单一 |
| 可测试性 | ★★★★★ | 纯函数，无副作用，测试覆盖完整 |
| 文档 | ★★★★☆ | 模块级文档清晰，可添加更多内联注释 |
| 性能 | ★★★★★ | 无锁、无分配、O(1) 复杂度 |
| 可维护性 | ★★★★★ | 接口简单，变更影响范围小 |

### 总结

`frame_rate_limiter.rs` 是一个**教科书级的辅助模块**：
- 职责单一且清晰
- 实现简洁无冗余
- 测试覆盖完整
- 与上下游模块解耦

作为 TUI 渲染流水线的基础组件，它有效地防止了渲染浪费，同时保持了代码的可读性和可维护性。
