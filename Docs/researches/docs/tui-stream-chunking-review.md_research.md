# tui-stream-chunking-review.md 研究文档

## 场景与职责

tui-stream-chunking-review.md 是 Codex CLI 项目中关于 TUI 流式分块（Stream Chunking）的设计文档。该文档解释了流式分块的工作原理和实现方式，用于处理流式输出可能比逐行动画提交速度更快的问题。

**适用场景：**
- TUI 开发者需要理解流式输出处理
- 调试流式显示问题
- 优化流式性能

## 功能点目的

### 1. 问题

流式输出可能比逐行提交的动画显示得更快。如果提交速度保持固定而到达速度激增，队列行增长，可见输出滞后于接收到的输出。

### 2. 设计目标

- 在正常负载下保留现有基线行为
- 当积压建立时减少显示滞后
- 保持输出顺序稳定
- 避免看起来跳跃的突然单帧刷新
- 保持策略与传输无关，仅基于队列状态

### 3. 非目标

- 策略不调度动画 tick
- 策略不依赖于上游源身份
- 策略不重新排序队列输出

### 4. 逻辑位置

| 文件 | 说明 |
|-----|------|
| `codex-rs/tui/src/streaming/chunking.rs` | 自适应策略、模式转换和排空计划选择 |
| `codex-rs/tui/src/streaming/commit_tick.rs` | 每个提交 tick 的编排：快照、决策、排空、跟踪 |
| `codex-rs/tui/src/streaming/controller.rs` | 提交 tick 编排使用的队列/排空原语 |
| `codex-rs/tui/src/chatwidget.rs` | 调用提交 tick 编排并处理 UI 生命周期事件的集成点 |

### 5. 运行时流程

在每个提交 tick：

1. **构建队列快照**跨活动控制器
   - `queued_lines`：总队列行数
   - `oldest_age`：跨控制器的最旧队列行的最大年龄

2. **向自适应策略请求决策**
   - 输出：当前模式和排空计划

3. **将排空计划应用到每个控制器**

4. **为调用者插入发出排空的 `HistoryCell`s**

5. **为可观察性发出跟踪日志**

在 `CatchUpOnly` 范围内，策略状态仍前进，但除非当前模式是 `CatchUp`，否则跳过排空。

### 6. 模式和转换

使用两种模式：

#### `Smooth`
- 基线行为：每个基线提交 tick 排空一行
- 基线 tick 间隔目前来自 `tui/src/app.rs:COMMIT_ANIMATION_TICK`（~8.3ms，~120fps）

#### `CatchUp`
- 通过 `Batch(queued_lines)` 每个 tick 排空当前队列积压

**进入和退出使用滞后**：
- 当队列深度或队列年龄超过进入阈值时进入 `CatchUp`
- 退出要求深度和年龄都低于退出阈值持续保持窗口（`EXIT_HOLD`）

这防止负载在阈值附近时的振荡。

### 7. 当前实验调整值

这些是 `streaming/chunking.rs` 中的当前值加上 `tui/src/app.rs` 中的基线提交 tick。它们是实验性的，可能随着收集更多跟踪数据而变化。

| 参数 | 值 | 说明 |
|-----|---|------|
| 基线提交 tick | ~8.3ms | `COMMIT_ANIMATION_TICK` in `app.rs` |
| 进入 catch-up | `queued_lines >= 8` OR `oldest_age >= 120ms` | |
| 退出 catch-up 资格 | `queued_lines <= 2` AND `oldest_age <= 40ms` | |
| 退出保持 | 250ms | `CatchUp -> Smooth` |
| 重新进入保持 | 250ms | 退出 catch-up 后 |
| 严重积压阈值 | `queued_lines >= 64` OR `oldest_age >= 300ms` | |

### 8. 排空计划

在 `Smooth` 中，计划始终是 `Single`。

在 `CatchUp` 中，计划是 `Batch(queued_lines)`，它排空当前队列积压以立即收敛。

### 9. 为什么这样设计

这保持正常动画语义完整，同时使积压行为自适应：

- 在正常负载下，行为保持熟悉和稳定
- 在压力下，队列年龄快速减少而不牺牲排序
- 滞后避免快速模式翻转

### 10. 不变量

- 队列顺序被保留
- 空队列将策略重置回 `Smooth`
- `CatchUp` 仅在持续低压后才退出
- Catch-up 排空在 `CatchUp` 中是立即的

### 11. 可观察性

跟踪事件从提交 tick 编排发出：

**`stream chunking commit tick`**
- `mode`
- `queued_lines`
- `oldest_queued_age_ms`
- `drain_plan`
- `has_controller`
- `all_idle`

**`stream chunking mode transition`**
- `prior_mode`
- `new_mode`
- `queued_lines`
- `oldest_queued_age_ms`
- `entered_catch_up`

这些事件旨在通过显示队列压力、选定排空行为和随时间的模式转换来解释显示滞后。

## 具体技术实现

### 自适应策略算法

```
每个提交 tick：
    1. 快照队列状态
       - queued_lines
       - oldest_age
    
    2. 评估模式转换
       - 如果 queued_lines >= ENTER_THRESHOLD 或 oldest_age >= ENTER_AGE：
         进入 CatchUp 模式
       - 如果 queued_lines <= EXIT_THRESHOLD 且 oldest_age <= EXIT_AGE 持续 EXIT_HOLD：
         退出到 Smooth 模式
    
    3. 选择排空计划
       - Smooth: Single
       - CatchUp: Batch(queued_lines)
    
    4. 执行排空
    
    5. 发出跟踪事件
```

### 状态机

```
[Smooth] --积压超过阈值--> [CatchUp] --持续低压--> [Smooth]
    ↑                              |
    └──────── 空队列 ──────────────┘
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-stream-chunking-review.md` | 本文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/streaming/chunking.rs` | 自适应策略 |
| `/home/sansha/Github/codex/codex-rs/tui/src/streaming/commit_tick.rs` | 提交 tick 编排 |
| `/home/sansha/Github/codex/codex-rs/tui/src/streaming/controller.rs` | 队列/排空原语 |
| `/home/sansha/Github/codex/codex-rs/tui/src/chatwidget.rs` | 集成点 |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | 基线 tick 间隔 |

### 关键类型（推测）

```rust
enum Mode {
    Smooth,
    CatchUp,
}

enum DrainPlan {
    Single,
    Batch(usize),
}

struct QueueSnapshot {
    queued_lines: usize,
    oldest_age: Duration,
}
```

## 依赖与外部交互

### 外部依赖

1. **tracing**
   - 用于可观察性日志

### 内部依赖

1. **流控制器**
   - 队列管理
   - 排空操作

2. **UI 组件**
   - `ChatWidget` 集成
   - 渲染更新

## 风险、边界与改进建议

### 潜在风险

1. **模式振荡**
   - 即使使用滞后，负载波动时仍可能振荡
   - 建议：调整保持窗口

2. **用户体验不一致**
   - 不同模式下的不同行为
   - 建议：平滑过渡动画

3. **性能开销**
   - 频繁的队列快照可能影响性能
   - 建议：优化快照实现

### 边界情况

1. **极端积压**
   - 非常大的队列深度
   - 内存考虑

2. **快速模式切换**
   - 突发负载后的快速恢复

3. **控制器空闲**
   - 所有控制器空闲时的处理

### 改进建议

1. **动态阈值**
   - 基于历史数据自动调整阈值
   - 机器学习优化

2. **用户控制**
   - 可配置的动画速度
   - 禁用 catch-up 的选项

3. **可视化**
   - 显示当前模式的 UI 指示器
   - 队列深度可视化

4. **性能优化**
   - 减少锁竞争
   - 批处理优化

5. **测试**
   - 添加模拟负载测试
   - 性能基准测试
