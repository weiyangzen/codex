# codex-rs/ollama/src/pull.rs 研究文档

## 场景与职责

`pull.rs` 是 `codex-ollama` crate 的进度报告模块，负责定义模型拉取过程中的事件类型和进度报告接口。它提供了：

1. **事件类型定义**：`PullEvent` 枚举表示拉取过程中的各种状态变化
2. **报告器 trait**：`PullProgressReporter` 定义了处理事件的接口
3. **CLI 实现**：`CliProgressReporter` 提供命令行进度显示
4. **TUI 实现**：`TuiProgressReporter` 为 TUI 模式提供进度报告（当前委托给 CLI 实现）

该模块是展示层和核心业务逻辑的桥梁，将技术事件转换为用户可理解的进度信息。

## 功能点目的

### 1. PullEvent 枚举

```rust
#[derive(Debug, Clone)]
pub enum PullEvent {
    Status(String),
    ChunkProgress { digest: String, total: Option<u64>, completed: Option<u64> },
    Success,
    Error(String),
}
```

| 变体 | 用途 |
|------|------|
| `Status` | 状态消息（如 "pulling manifest", "verifying"）|
| `ChunkProgress` | 层的下载进度，包含 digest、总大小、已完成大小 |
| `Success` | 拉取完成 |
| `Error` | 拉取失败，包含错误消息 |

### 2. PullProgressReporter trait

```rust
pub trait PullProgressReporter {
    fn on_event(&mut self, event: &PullEvent) -> io::Result<()>;
}
```

抽象接口，允许不同的 UI 模式（CLI、TUI、静默）实现自己的进度显示逻辑。

### 3. CliProgressReporter

命令行模式下的进度显示实现，特点：
- 写入 stderr（避免污染 stdout）
- 使用 `\r` 回车实现行内更新
- 计算下载速度和 ETA
- 过滤掉 "pulling manifest" 的噪音消息

### 4. TuiProgressReporter

TUI 模式的进度报告器，当前是 `CliProgressReporter` 的透明包装：

```rust
#[derive(Default)]
pub struct TuiProgressReporter(CliProgressReporter);
```

这是临时实现，未来可能替换为专门的 TUI 进度组件。

## 具体技术实现

### CliProgressReporter 状态管理

```rust
pub struct CliProgressReporter {
    printed_header: bool,      // 是否已打印表头
    last_line_len: usize,      // 上一行长度（用于清除）
    last_completed_sum: u64,   // 上次完成的字节数（用于计算速度）
    last_instant: Instant,     // 上次更新时间
    totals_by_digest: HashMap<String, (u64, u64)>, // 每个 digest 的 (total, completed)
}
```

### 进度计算逻辑

1. **累积进度**：按 digest 聚合，计算全局总进度
   ```rust
   let (sum_total, sum_completed) = self
       .totals_by_digest
       .values()
       .fold((0u64, 0u64), |acc, (t, c)| (acc.0 + *t, acc.1 + *c));
   ```

2. **速度计算**：基于时间差和字节差计算 MB/s
   ```rust
   let dt = now.duration_since(self.last_instant).as_secs_f64().max(0.001);
   let dbytes = sum_completed.saturating_sub(self.last_completed_sum) as f64;
   let speed_mb_s = dbytes / (1024.0 * 1024.0) / dt;
   ```

3. **格式化显示**：
   ```
   Downloading model: total 4.50 GB
   1.23/4.50 GB (27.3%) 45.2 MB/s
   ```

### 行内更新技术

使用 ANSI 控制序列实现动态更新：

```rust
// 清除当前行并移动光标到行首
let line = format!("\r{status}{}", " ".repeat(pad));
out.write_all(line.as_bytes())?;
out.flush()
```

- `\r`：回车，移动光标到行首
- `" ".repeat(pad)`：用空格覆盖残留字符

### 事件处理分支

| 事件类型 | 处理逻辑 |
|----------|----------|
| `Status` | 过滤 "pulling manifest"，显示其他状态 |
| `ChunkProgress` | 更新哈希表，计算全局进度，显示下载速度和百分比 |
| `Error` | 不处理（由调用方处理，避免重复打印）|
| `Success` | 打印换行，结束进度显示 |

## 关键代码路径与文件引用

### 模块依赖

```
pull.rs
    └── 无内部依赖（纯定义模块）
```

### 调用方

| 调用方 | 使用类型 | 场景 |
|--------|----------|------|
| `parser.rs` | `PullEvent` | 生成事件 |
| `client.rs` | `PullEvent`, `PullProgressReporter`, `CliProgressReporter` | `pull_with_reporter` |
| `lib.rs` | `CliProgressReporter`, `PullEvent`, `PullProgressReporter`, `TuiProgressReporter` | 重新导出 |

### 调用链

```
lib.rs::ensure_oss_ready
    └── client.rs::pull_with_reporter
            ├── client.rs::pull_model_stream
            │       └── parser.rs::pull_events_from_value (生成 PullEvent)
            └── pull.rs::CliProgressReporter::on_event (处理事件)
```

## 依赖与外部交互

### 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `std::collections::HashMap` | 存储每个 digest 的进度 |
| `std::io::Write` | 写入 stderr |
| `std::time::Instant` | 计算下载速度 |

### 标准库使用

```rust
use std::collections::HashMap;
use std::io;
use std::io::Write;
```

无外部 crate 依赖，仅使用标准库。

## 风险、边界与改进建议

### 已知风险

1. **终端宽度假设**：代码假设终端足够宽，不处理行截断或换行。

2. **速度计算抖动**：短时间内的速度计算可能波动较大，未使用平滑算法。

3. **多 digest 聚合误差**：不同 digest 的 total 可能在不同时间到达，导致临时性的进度回退或跳跃。

4. **TUI 委托实现**：`TuiProgressReporter` 直接委托给 CLI 实现，在 TUI 环境中可能破坏 UI 布局。

### 边界情况

| 场景 | 行为 |
|------|------|
| total = 0 | 不显示进度（避免除零）|
| completed > total | 百分比 > 100%，原样显示 |
| 时间差 < 1ms | 使用 1ms 作为最小值，避免除零 |
| 同一 digest 多次更新 total | 使用最新值覆盖 |
| 空 digest | 使用空字符串作为 key，可能合并不同层 |

### 改进建议

1. **平滑速度计算**：使用移动平均或指数平滑减少速度显示抖动：
   ```rust
   let alpha = 0.3; // 平滑因子
   self.smoothed_speed = alpha * instant_speed + (1.0 - alpha) * self.smoothed_speed;
   ```

2. **终端宽度感知**：使用 `crossterm` 或 `term_size` 获取终端宽度，处理窄终端场景。

3. **TUI 专用实现**：为 TUI 模式实现真正的图形化进度条，而非委托给 CLI 实现。

4. **ETA 计算**：基于当前速度和剩余大小，计算并显示预计完成时间。

5. **并发安全**：当前 `CliProgressReporter` 不是 `Send` + `Sync`，如果需要在多线程环境使用需要重构。

6. **进度持久化**：对于大模型，考虑持久化进度，支持断点续传。

7. **单位自适应**：根据大小自动选择单位（MB/GB/TB）：
   ```rust
   fn format_size(bytes: u64) -> String {
       const UNITS: &[&str] = &["B", "KB", "MB", "GB", "TB"];
       let mut size = bytes as f64;
       let mut unit_idx = 0;
       while size >= 1024.0 && unit_idx < UNITS.len() - 1 {
           size /= 1024.0;
           unit_idx += 1;
       }
       format!("{:.2} {}", size, UNITS[unit_idx])
   }
   ```

### 与 LM Studio 对比

| 特性 | Ollama | LM Studio |
|------|--------|-----------|
| 进度粒度 | 层级别（digest）| 无原生进度报告 |
| 速度计算 | 实时计算 | 不支持 |
| 报告器 trait | 有（`PullProgressReporter`）| 无 |
| CLI/TUI 分离 | 有（虽然 TUI 委托给 CLI）| 无 |

LM Studio 的模型下载没有流式进度，因此不需要复杂的进度报告机制。Ollama 的实现更完善，提供了更好的用户体验。

### 测试覆盖

当前文件没有单元测试，测试主要通过 `client.rs` 的集成测试间接覆盖。建议添加：

1. `CliProgressReporter` 的事件处理测试
2. 进度计算准确性测试
3. 边界情况测试（零 total、溢出等）
