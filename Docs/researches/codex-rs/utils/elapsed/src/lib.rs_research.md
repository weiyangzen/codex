# 研究文档：codex-rs/utils/elapsed/src/lib.rs

## 概述

`codex-utils-elapsed` 是一个轻量级的 Rust 工具库，提供时间持续时间的格式化功能。该库位于 `codex-rs/utils/elapsed` 目录下，是 Codex CLI 项目中用于时间显示的基础工具组件。

---

## 1. 场景与职责

### 1.1 使用场景

该库主要用于以下场景：

1. **命令执行时间显示**：在 TUI（终端用户界面）中显示 shell 命令、MCP 工具调用的执行耗时
2. **实时进度反馈**：在异步任务执行过程中向用户展示已消耗的时间
3. **性能指标展示**：在遥测和监控界面中格式化显示 API 调用、推理时间等性能数据
4. **日志输出**：为人类可读的日志输出格式化时间信息

### 1.2 核心职责

- 将 `std::time::Duration` 转换为人类可读的时间字符串
- 根据时间长度自动选择合适的格式（毫秒/秒/分钟）
- 提供从 `Instant` 开始时间计算经过时间的便捷函数

---

## 2. 功能点目的

### 2.1 公共 API

| 函数 | 签名 | 目的 |
|------|------|------|
| `format_elapsed` | `fn(start_time: Instant) -> String` | 计算从给定时间点到现在的时间差并格式化 |
| `format_duration` | `fn(duration: Duration) -> String` | 将 Duration 直接格式化为可读字符串 |

### 2.2 格式化规则

库实现了三级格式化策略，根据时间长度自动选择：

| 时间范围 | 格式示例 | 说明 |
|----------|----------|------|
| < 1 秒 | `"250ms"` | 毫秒级精度，无小数 |
| 1 秒 ~ 60 秒 | `"1.50s"` | 秒级精度，保留两位小数 |
| ≥ 60 秒 | `"1m 15s"` | 分钟:秒格式，秒数补零 |

**设计考量**：
- 亚秒级使用毫秒而非小数秒，避免 `"0.25s"` 这种不够直观的形式
- 秒级保留两位小数，平衡精度与可读性（如 `"1.50s"`）
- 分钟级使用 `"Xm YZs"` 格式而非 `"X:YZ"`，更符合自然语言习惯
- 不处理小时级别（超过60分钟显示为 `"60m 00s"` 而非 `"1h 00m"`）

---

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
// 输入类型（标准库）
std::time::Instant  // 时间点
std::time::Duration // 时间间隔

// 内部转换
millis: i64  // 毫秒级整数，用于格式化计算
```

### 3.2 关键流程

```
format_elapsed(start_time: Instant)
    └── start_time.elapsed() -> Duration
        └── format_duration(duration: Duration)
            └── duration.as_millis() as i64
                └── format_elapsed_millis(millis: i64)
                    ├── millis < 1000     -> "{millis}ms"
                    ├── millis < 60_000   -> "{:.2}s" (秒，两位小数)
                    └── millis >= 60_000  -> "{min}m {sec:02}s"
```

### 3.3 关键代码实现

```rust
// 从 Instant 计算经过时间
pub fn format_elapsed(start_time: Instant) -> String {
    format_duration(start_time.elapsed())
}

// Duration 直接格式化
pub fn format_duration(duration: Duration) -> String {
    let millis = duration.as_millis() as i64;
    format_elapsed_millis(millis)
}

// 核心格式化逻辑
fn format_elapsed_millis(millis: i64) -> String {
    if millis < 1000 {
        format!("{millis}ms")
    } else if millis < 60_000 {
        format!("{:.2}s", millis as f64 / 1000.0)
    } else {
        let minutes = millis / 60_000;
        let seconds = (millis % 60_000) / 1000;
        format!("{minutes}m {seconds:02}s")
    }
}
```

### 3.4 边界值处理

测试用例显示以下边界行为：

- **0ms**: `"0ms"` - 正常处理零值
- **999ms**: `"999ms"` - 毫秒级上限
- **1000ms (1s)**: `"1.00s"` - 秒级下限，两位小数
- **59,999ms**: `"60.00s"` - 秒级上限，会显示为60秒而非1分钟
- **60,000ms (1m)**: `"1m 00s"` - 分钟级下限，秒数补零
- **3,600,000ms (1h)**: `"60m 00s"` - 不转换为小时，继续以分钟显示

---

## 4. 关键代码路径与文件引用

### 4.1 库本身

| 文件 | 说明 |
|------|------|
| `codex-rs/utils/elapsed/src/lib.rs` | 主库代码，包含公共 API 和测试 |
| `codex-rs/utils/elapsed/Cargo.toml` | 包配置，crate 名 `codex-utils-elapsed` |
| `codex-rs/utils/elapsed/BUILD.bazel` | Bazel 构建配置 |

### 4.2 调用方（使用者）

| 文件 | 使用方式 | 场景 |
|------|----------|------|
| `codex-rs/exec/src/event_processor_with_human_output.rs` | `use codex_utils_elapsed::{format_duration, format_elapsed}` | CLI 人类可读输出，显示 exec/MCP 工具执行时间 |
| `codex-rs/tui/src/exec_cell/render.rs` | `use codex_utils_elapsed::format_duration` | TUI 执行单元格渲染，显示命令耗时 |
| `codex-rs/tui_app_server/src/exec_cell/render.rs` | `use codex_utils_elapsed::format_duration` | TUI App Server 执行单元格渲染 |

### 4.3 相关但独立的实现

以下文件实现了类似功能但未直接使用本库：

| 文件 | 说明 |
|------|------|
| `codex-rs/tui/src/history_cell.rs` | 自定义 `format_duration_ms(u64) -> String`，用于运行时指标 |
| `codex-rs/tui_app_server/src/history_cell.rs` | 同上，TUI App Server 版本 |
| `codex-rs/core/src/user_shell_command.rs` | 自定义 `format_duration_line`，用于用户 shell 命令记录 |

---

## 5. 依赖与外部交互

### 5.1 依赖关系

```
codex-utils-elapsed
├── 标准库依赖
│   ├── std::time::Duration
│   └── std::time::Instant
└── 无外部 crate 依赖
```

### 5.2 被依赖关系

```
codex-rs/workspace
├── codex-utils-elapsed (本库)
│   ├── codex-rs/exec (通过 workspace 依赖)
│   ├── codex-rs/tui (通过 workspace 依赖)
│   └── codex-rs/tui_app_server (通过 workspace 依赖)
```

Cargo.toml 中的依赖声明：
```toml
# codex-rs/Cargo.toml (workspace)
[workspace.dependencies]
codex-utils-elapsed = { path = "utils/elapsed" }

# 使用者的 Cargo.toml
codex-utils-elapsed = { workspace = true }
```

### 5.3 与相关组件的关系

| 组件 | 关系 | 说明 |
|------|------|------|
| `shell-escalation/src/unix/stopwatch.rs` | 功能互补 | Stopwatch 提供计时功能，elapsed 提供格式化功能，但两者未直接交互 |
| `otel/src/metrics/timer.rs` | 功能互补 | Timer 用于指标收集，使用 Duration 但不使用本库的格式化 |
| `core/src/exec.rs` | 上游数据生产者 | 执行模块产生 Duration 数据，通过事件传递给消费者格式化 |

---

## 6. 风险、边界与改进建议

### 6.1 已知限制与风险

1. **小时级时间显示不友好**
   - 超过1小时显示为 `"60m 00s"` 而非 `"1h 00m"`
   - 长时间运行的任务可读性较差

2. **毫秒级精度丢失**
   - 使用 `as_millis()` 截断到毫秒，微秒级精度丢失
   - 对于亚毫秒级操作可能显示为 `"0ms"`

3. **i64 转换潜在溢出**
   ```rust
   let millis = duration.as_millis() as i64;
   ```
   - `as_millis()` 返回 `u128`，转换为 `i64` 可能在极端长时间（约2.9亿年）下溢出
   - 实际场景中不太可能发生

4. **代码重复**
   - `tui/src/history_cell.rs` 和 `tui_app_server/src/history_cell.rs` 各自实现了类似的 `format_duration_ms`
   - 未复用本库，维护成本增加

### 6.2 测试覆盖

测试用例位于 `lib.rs` 底部，覆盖：
- `test_format_duration_subsecond`: 亚秒级格式化
- `test_format_duration_seconds`: 秒级格式化
- `test_format_duration_minutes`: 分钟级格式化
- `test_format_duration_one_hour_has_space`: 小时边界行为

**测试缺口**：
- 未测试 `format_elapsed` 函数
- 未测试极端值（如 `Duration::MAX`）
- 未测试负数 Duration（虽然标准库不允许）

### 6.3 改进建议

1. **统一格式化函数**
   - 将 `history_cell.rs` 中的 `format_duration_ms` 合并到本库
   - 提供 `format_duration_ms(u64) -> String` 公共 API

2. **支持小时级显示**
   ```rust
   // 建议添加
   if millis >= 3_600_000 {
       let hours = millis / 3_600_000;
       let minutes = (millis % 3_600_000) / 60_000;
       format!("{hours}h {minutes:02}m")
   }
   ```

3. **添加配置选项**
   - 允许调用者指定精度（小数位数）
   - 允许选择是否显示小时

4. **使用 `u64` 替代 `i64`**
   - 时间值不应为负，使用无符号类型更符合语义

5. **添加 `format_elapsed` 测试**
   - 当前只有 `format_duration` 的测试
   - 应添加从 `Instant` 开始的集成测试

### 6.4 代码风格建议

根据项目 `AGENTS.md` 的规范：
- 函数符合 Rust 命名规范
- 使用了内联变量格式化（`{millis}ms`）
- 文档注释完整，包含格式化规则说明
- 建议添加 `#![warn(missing_docs)]` 确保文档完整性

---

## 7. 总结

`codex-utils-elapsed` 是一个简洁、专注的时间格式化工具库。其设计遵循"足够好"原则，覆盖了 Codex CLI 项目中绝大多数时间显示需求。主要改进空间在于统一项目中分散的类似实现，以及扩展对长时间运行的支持。

该库作为基础工具组件，稳定性要求高但变更频率低，适合保持其简单性，避免过度设计。
