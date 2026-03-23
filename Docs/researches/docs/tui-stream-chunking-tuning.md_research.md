# tui-stream-chunking-tuning.md 研究文档

## 场景与职责

tui-stream-chunking-tuning.md 是 Codex CLI 项目中关于 TUI 流式分块调整指南的文档。该文档解释了如何调整自适应流式分块常量而不改变底层策略形状。

**适用场景：**
- 开发者需要调整流式分块行为
- 优化特定工作负载的性能
- 理解调整参数的影响

## 功能点目的

### 1. 范围

在调整 `codex-rs/tui/src/streaming/chunking.rs` 中的队列压力阈值和滞后窗口以及 `codex-rs/tui/src/app.rs` 中的基线提交节奏时使用本指南。

本指南是关于调整行为，而不是重新设计策略。

### 2. 调整前

- 保持基线行为完整：
  - `Smooth` 模式每个基线 tick 排空一行
  - `CatchUp` 模式立即排空队列积压
- 使用以下方式捕获跟踪日志：
  - `codex_tui::streaming::commit_tick`
- 在持续、突发和混合输出提示上评估

参见 `docs/tui-stream-chunking-validation.md` 了解测量过程。

### 3. 调整目标

同时调整所有三个目标：
- 突发输出下的低可见滞后
- 低模式翻转（`Smooth <-> CatchUp` 抖动）
- 混合工作负载下稳定的 catch-up 进入/退出行为

### 4. 常量及其控制内容

#### 基线提交节奏

- `COMMIT_ANIMATION_TICK` (`tui/src/app.rs`)
  - 较低值增加平滑模式更新节奏并减少稳态滞后
  - 较高值增加平滑度并可能增加感知滞后
  - 这通常应在分块阈值/保持在良好范围后移动

#### 进入/退出阈值

- `ENTER_QUEUE_DEPTH_LINES`, `ENTER_OLDEST_AGE`
  - 较低值更早进入 catch-up（较少滞后，更多模式切换风险）
  - 较高值更晚进入（更多滞后容忍，较少模式切换）

- `EXIT_QUEUE_DEPTH_LINES`, `EXIT_OLDEST_AGE`
  - 较低值保持 catch-up 活动更久
  - 较高值允许更早退出并可能增加重新进入抖动

#### 滞后保持

- `EXIT_HOLD`
  - 更长保持减少压力嘈杂时的翻转退出
  - 太长可能在压力清除后保持 catch-up 活动

- `REENTER_CATCH_UP_HOLD`
  - 更长保持抑制退出后的快速重新进入
  - 太长可能延迟近期突发所需的 catch-up
  - 严重积压按设计绕过此保持

#### 严重积压门

- `SEVERE_QUEUE_DEPTH_LINES`, `SEVERE_OLDEST_AGE`
  - 较低值更早绕过重新进入保持
  - 较高值仅为极端压力保留保持绕过

### 5. 推荐的调整顺序

按此顺序调整以保持因果关系清晰：

1. 进入/退出阈值 (`ENTER_*`, `EXIT_*`)
2. 保持窗口 (`EXIT_HOLD`, `REENTER_CATCH_UP_HOLD`)
3. 严重门 (`SEVERE_*`)
4. 基线节奏 (`COMMIT_ANIMATION_TICK`)

一次更改一个逻辑组并在下一组之前重新测量。

### 6. 症状驱动的调整

| 症状 | 调整 |
|-----|------|
| catch-up 开始前太多滞后 | 降低 `ENTER_QUEUE_DEPTH_LINES` 和/或 `ENTER_OLDEST_AGE` |
| 频繁的 `Smooth -> CatchUp -> Smooth` 抖动 | 增加 `EXIT_HOLD`；增加 `REENTER_CATCH_UP_HOLD`；收紧退出阈值（降低 `EXIT_*`） |
| catch-up 对短突发太频繁 | 增加 `ENTER_QUEUE_DEPTH_LINES` 和/或 `ENTER_OLDEST_AGE`；增加 `REENTER_CATCH_UP_HOLD` |
| catch-up 进入太晚 | 降低 `ENTER_QUEUE_DEPTH_LINES` 和/或 `ENTER_OLDEST_AGE`；降低严重门（`SEVERE_*`）以更早绕过重新进入保持 |

### 7. 每次调整后的验证清单

- `cargo test -p codex-tui` 通过
- 跟踪窗口显示有界的队列年龄行为
- 模式转换不集中在重复短间隔周期中
- Catch-up 一旦进入 `CatchUp` 模式就快速清除积压

## 具体技术实现

### 调整工作流

```
识别症状
    ↓
确定相关常量组
    ↓
进行保守调整
    ↓
运行测试
    ↓
捕获跟踪日志
    ↓
评估指标
    ↓
如果需要，重复
```

### 跟踪日志分析

```bash
# 启用跟踪
RUST_LOG='codex_tui::streaming::commit_tick=trace' codex

# 分析日志
# 关注：
# - mode_transitions 数量
# - queue depth 分布
# - rapid re-entry 事件
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-stream-chunking-tuning.md` | 本文档 |
| `/home/sansha/Github/codex/docs/tui-stream-chunking-validation.md` | 验证过程文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/streaming/chunking.rs` | 可调常量 |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | 基线 tick 间隔 |

### 可调常量（推测）

```rust
// chunking.rs
const ENTER_QUEUE_DEPTH_LINES: usize = 8;
const ENTER_OLDEST_AGE: Duration = Duration::from_millis(120);
const EXIT_QUEUE_DEPTH_LINES: usize = 2;
const EXIT_OLDEST_AGE: Duration = Duration::from_millis(40);
const EXIT_HOLD: Duration = Duration::from_millis(250);
const REENTER_CATCH_UP_HOLD: Duration = Duration::from_millis(250);
const SEVERE_QUEUE_DEPTH_LINES: usize = 64;
const SEVERE_OLDEST_AGE: Duration = Duration::from_millis(300);

// app.rs
const COMMIT_ANIMATION_TICK: Duration = Duration::from_millis(8_333_333_333u64 / 1_000_000_000); // ~8.3ms
```

## 依赖与外部交互

### 外部依赖

1. **tracing**
   - 用于性能分析

### 内部依赖

1. **流分块系统**
   - 所有调整的目标系统

2. **测试系统**
   - 验证调整

## 风险、边界与改进建议

### 潜在风险

1. **过度调整**
   - 一次更改太多参数
   - 难以确定因果关系
   - 建议：遵循推荐的调整顺序

2. **测试覆盖不足**
   - 仅测试特定场景
   - 其他工作负载可能退化
   - 建议：在多样化工作负载上测试

3. **硬件差异**
   - 不同机器上的不同行为
   - 建议：在代表性硬件上验证

### 边界情况

1. **极端工作负载**
   - 非常大的输出量
   - 非常快速的突发

2. **慢速终端**
   - 渲染性能影响

3. **远程连接**
   - 网络延迟影响

### 改进建议

1. **自动调整**
   - 基于工作负载特征的自动参数选择
   - 自适应阈值

2. **预设配置**
   - 为不同场景提供预设（如 "低延迟"、"稳定"）
   - 用户可选择预设

3. **实时监控**
   - 实时显示当前性能指标
   - 调整效果即时反馈

4. **A/B 测试框架**
   - 比较不同参数集
   - 统计显著性测试

5. **机器学习优化**
   - 基于历史数据优化参数
   - 预测性调整

6. **文档增强**
   - 添加更多示例场景
   - 提供决策树
