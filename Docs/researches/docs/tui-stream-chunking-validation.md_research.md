# tui-stream-chunking-validation.md 研究文档

## 场景与职责

tui-stream-chunking-validation.md 是 Codex CLI 项目中关于 TUI 流式分块验证过程的文档。该文档记录了用于验证自适应流式分块和抗抖动行为的过程。

**适用场景：**
- 验证流式分块实现
- 评估调整效果
- 回归测试

## 功能点目的

### 1. 范围

目标是验证运行时跟踪中的两个属性：
- 当队列压力上升时显示滞后减少
- 模式转换保持稳定而不是快速翻转

### 2. 跟踪目标

分块可观察性由以下发出：
- `codex_tui::streaming::commit_tick`

使用两条跟踪消息：
- `stream chunking commit tick`
- `stream chunking mode transition`

### 3. 运行时命令

启用分块跟踪运行 Codex：

```bash
RUST_LOG='codex_tui::streaming::commit_tick=trace,codex_tui=info,codex_core=info,codex_rmcp_client=info' \
  just codex --enable=responses_websockets
```

### 4. 日志捕获过程

提示：对于一次性测量，使用 `-c log_dir=...` 运行以将日志定向到新鲜目录，避免混合会话。

1. 记录 `~/.codex/log/codex-tui.log` 的当前大小作为起始偏移
2. 运行产生持续流式输出的交互式提示
3. 停止运行
4. 仅解析记录的偏移之后写入的日志字节

这避免将早期会话与当前测量窗口混合。

### 5. 审查的指标

对于每个测量窗口：

| 指标 | 说明 |
|-----|------|
| `commit_ticks` | 提交 tick 总数 |
| `mode_transitions` | 模式转换次数 |
| `smooth_ticks` | Smooth 模式 tick 数 |
| `catchup_ticks` | CatchUp 模式 tick 数 |
| drain-plan distribution | `Single`, `Batch(n)` 分布 |
| queue depth | `max`, `p95`, `p99` |
| oldest queued age | `max`, `p95`, `p99` |
| rapid re-entry count | `CatchUp -> Smooth` 转换后 1 秒内 `Smooth -> CatchUp` 转换次数 |

### 6. 解释

#### 健康行为
- 积压排空时队列年龄保持有界
- 相对于总 tick 数，转换次数低
- 快速重新进入事件不频繁且局限于突发边界

#### 退化行为
- 扩展窗口中的重复短间隔模式切换
- Smooth 模式中的持久队列年龄增长
- 无积压减少的长 catch-up 运行

### 7. 实验历史

本节捕获主要调整过程，以便未来工作可以在已尝试的基础上构建。

#### 基线
- 单行平滑排空，50ms 提交 tick
- 这保留了熟悉的节奏，但在持续积压下可能感觉滞后

#### Pass 1: 即时 catch-up，基线 tick 不变
- 保持平滑模式语义，但使 catch-up 每个 catch-up tick 排空完整队列积压
- 结果：队列滞后下降更快，但感知运动仍可能感觉阶梯，因为平滑模式节奏保持粗糙

#### Pass 2: 更快的基线 tick（25ms）
- 改进平滑模式节奏并减少可见步进
- 结果：更好，但仍未与绘制节奏对齐

#### Pass 3: 帧对齐基线 tick（~16.7ms）
- 将基线提交节奏设置为大约 60fps
- 结果：更平滑的感知进展，同时保留滞后和快速积压收敛

#### Pass 4: 更高帧对齐基线 tick（~8.3ms）
- 将基线提交节奏设置为大约 120fps
- 结果：进一步减少平滑模式步进，同时保留相同的自适应 catch-up 策略形状

#### 当前状态组合
- `CatchUp` 中的即时 catch-up 排空
- 模式进入/退出稳定性滞后
- 帧对齐平滑模式提交节奏（~8.3ms）

### 8. 注意事项

- 验证与源无关，不依赖于命名任何特定上游提供者
- 此过程故意保留现有基线平滑行为，专注于突发/积压处理行为

## 具体技术实现

### 验证工作流

```
准备测试环境
    ↓
记录日志起始偏移
    ↓
运行测试提示（产生流式输出）
    ↓
停止运行
    ↓
提取测量窗口的日志
    ↓
解析跟踪事件
    ↓
计算指标
    ↓
评估健康/退化
    ↓
记录结果
```

### 指标计算

```python
# 伪代码示例
def analyze_traces(events):
    metrics = {
        'commit_ticks': 0,
        'mode_transitions': 0,
        'smooth_ticks': 0,
        'catchup_ticks': 0,
        'queue_depths': [],
        'oldest_ages': [],
        'rapid_reentries': 0
    }
    
    last_exit_time = None
    
    for event in events:
        if event.type == 'commit_tick':
            metrics['commit_ticks'] += 1
            metrics['queue_depths'].append(event.queued_lines)
            metrics['oldest_ages'].append(event.oldest_age)
            
            if event.mode == 'Smooth':
                metrics['smooth_ticks'] += 1
            else:
                metrics['catchup_ticks'] += 1
                
        elif event.type == 'mode_transition':
            metrics['mode_transitions'] += 1
            
            if event.new_mode == 'Smooth':
                last_exit_time = event.timestamp
            elif event.new_mode == 'CatchUp' and last_exit_time:
                if event.timestamp - last_exit_time < 1_second:
                    metrics['rapid_reentries'] += 1
    
    return metrics
```

## 关键代码路径与文件引用

### 相关文件位置

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/docs/tui-stream-chunking-validation.md` | 本文档 |
| `/home/sansha/Github/codex/docs/tui-stream-chunking-tuning.md` | 调整指南 |
| `/home/sansha/Github/codex/docs/tui-stream-chunking-review.md` | 设计文档 |
| `/home/sansha/Github/codex/codex-rs/tui/src/streaming/commit_tick.rs` | 跟踪事件发出 |

### 跟踪事件格式

**`stream chunking commit tick`**:
```rust
{
    mode: Mode,
    queued_lines: usize,
    oldest_queued_age_ms: u64,
    drain_plan: DrainPlan,
    has_controller: bool,
    all_idle: bool
}
```

**`stream chunking mode transition`**:
```rust
{
    prior_mode: Mode,
    new_mode: Mode,
    queued_lines: usize,
    oldest_queued_age_ms: u64,
    entered_catch_up: bool
}
```

## 依赖与外部交互

### 外部依赖

1. **tracing 生态系统**
   - 日志收集
   - 事件解析

2. **测试提示**
   - 需要产生持续流式输出的提示

### 内部依赖

1. **流分块系统**
   - 被验证的系统

2. **日志系统**
   - 日志文件位置：`~/.codex/log/codex-tui.log`

## 风险、边界与改进建议

### 潜在风险

1. **测量准确性**
   - 日志时间戳精度
   - 系统负载影响
   - 建议：多次运行取平均

2. **提示选择偏差**
   - 不同提示产生不同负载模式
   - 建议：使用多样化提示集

3. **环境差异**
   - 不同机器上的不同行为
   - 建议：标准化测试环境

### 边界情况

1. **短会话**
   - 数据点不足
   - 统计显著性

2. **空闲期**
   - 无活动期间的处理
   - 指标计算影响

3. **并发会话**
   - 多个 Codex 实例
   - 日志混合问题

### 改进建议

1. **自动化验证**
   - 自动化测试套件
   - CI 集成

2. **可视化工具**
   - 实时指标仪表板
   - 历史趋势图表

3. **基准测试**
   - 标准化测试场景
   - 性能回归检测

4. **报告生成**
   - 自动报告生成
   - 比较分析

5. **扩展指标**
   - 更多性能指标
   - 用户体验指标

6. **A/B 测试支持**
   - 多版本比较
   - 统计测试
