# codex-rs/utils/elapsed 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-utils-elapsed` 是 Codex 项目中一个**轻量级的时间格式化工具库**，位于 `codex-rs/utils/elapsed` 目录下。该 crate 的核心职责是**将时间间隔（Duration/Instant）转换为人类可读的字符串表示**。

### 使用场景

1. **CLI 输出美化**：在命令行界面中显示操作耗时（如命令执行时间、工具调用耗时）
2. **TUI 界面渲染**：在终端用户界面中展示执行单元（ExecCell）的持续时间
3. **日志与监控**：为人类可读日志提供统一的时间格式化标准
4. **进度显示**：在 Agent Job 进度展示中显示预计剩余时间（ETA）

### 在架构中的定位

该 crate 属于 `utils/` 目录下的**工具类库**，遵循以下设计原则：
- **单一职责**：仅处理时间格式化，不涉及时序计算或时间获取
- **零依赖**：不依赖外部 crates，仅使用 Rust 标准库 (`std::time`)
- **跨组件复用**：被多个上层组件（exec、tui、tui_app_server）共享使用

---

## 功能点目的

### 核心 API

| 函数 | 签名 | 用途 |
|------|------|------|
| `format_elapsed` | `fn(start_time: Instant) -> String` | 从起始时刻计算已过去的时间并格式化 |
| `format_duration` | `fn(duration: Duration) -> String` | 将 Duration 直接格式化为可读字符串 |

### 格式化规则设计

库实现了**三段式格式化策略**，根据时长自动选择最合适的表示方式：

| 时长范围 | 输出格式 | 示例 |
|----------|----------|------|
| < 1 秒 | `{millis}ms` | `250ms`, `0ms` |
| 1 秒 ~ 60 秒 | `{sec:.2}s` | `1.50s`, `60.00s` |
| ≥ 60 秒 | `{min}m {sec:02}s` | `1m 15s`, `60m 01s` |

### 设计意图

1. **毫秒级精度**：对于短时间操作（<1s），使用毫秒显示精确度
2. **两位小数秒**：中等时长使用浮点秒，保留两位小数平衡精度与可读性
3. **分钟+秒**：长时间操作使用分钟和秒的组合，避免出现过大的秒数（如 3600s）
4. **无小时单位**：特意不显示小时（如 60m 00s 而非 1h 00m 00s），保持简洁

---

## 具体技术实现

### 核心实现代码

```rust
// src/lib.rs

use std::time::Duration;
use std::time::Instant;

/// Returns a string representing the elapsed time since `start_time` like
/// "1m 15s" or "1.50s".
pub fn format_elapsed(start_time: Instant) -> String {
    format_duration(start_time.elapsed())
}

/// Convert a [`std::time::Duration`] into a human-readable, compact string.
///
/// Formatting rules:
/// * < 1 s  ->  "{milli}ms"
/// * < 60 s ->  "{sec:.2}s" (two decimal places)
/// * >= 60 s ->  "{min}m {sec:02}s"
pub fn format_duration(duration: Duration) -> String {
    let millis = duration.as_millis() as i64;
    format_elapsed_millis(millis)
}

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

### 实现要点分析

1. **类型转换策略**：
   - 使用 `as_millis() as i64` 将 Duration 转换为毫秒整数
   - 选择 `i64` 而非 `u64` 是为了兼容性和可能的负数处理（尽管实际场景中不会出现）

2. **浮点计算**：
   - 秒级显示使用 `millis as f64 / 1000.0` 进行转换
   - 使用 `{:.2}` 格式控制两位小数精度

3. **整数运算**：
   - 分钟计算：`millis / 60_000`（整除）
   - 秒余数：`(millis % 60_000) / 1000`
   - 使用 `{:02}` 格式确保秒数始终两位（如 `00`, `05`）

### 测试覆盖

库包含 4 个单元测试，覆盖所有格式化规则：

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_duration_subsecond() {
        let dur = Duration::from_millis(250);
        assert_eq!(format_duration(dur), "250ms");

        let dur_zero = Duration::from_millis(0);
        assert_eq!(format_duration(dur_zero), "0ms");
    }

    #[test]
    fn test_format_duration_seconds() {
        let dur = Duration::from_millis(1_500); // 1.5s
        assert_eq!(format_duration(dur), "1.50s");

        let dur2 = Duration::from_millis(59_999);
        assert_eq!(format_duration(dur2), "60.00s");
    }

    #[test]
    fn test_format_duration_minutes() {
        let dur = Duration::from_millis(75_000); // 1m15s
        assert_eq!(format_duration(dur), "1m 15s");

        let dur_exact = Duration::from_millis(60_000); // 1m0s
        assert_eq!(format_duration(dur_exact), "1m 00s");

        let dur_long = Duration::from_millis(3_601_000);
        assert_eq!(format_duration(dur_long), "60m 01s");
    }

    #[test]
    fn test_format_duration_one_hour_has_space() {
        let dur_hour = Duration::from_millis(3_600_000);
        assert_eq!(format_duration(dur_hour), "60m 00s");
    }
}
```

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/utils/elapsed/
├── Cargo.toml          # 包配置（无外部依赖）
├── BUILD.bazel         # Bazel 构建配置
└── src/
    └── lib.rs          # 完整实现（78 行，含测试）
```

### 调用方分布

#### 1. codex-exec（命令行执行器）

**文件**: `codex-rs/exec/src/event_processor_with_human_output.rs`

```rust
use codex_utils_elapsed::format_duration;
use codex_utils_elapsed::format_elapsed;
```

**使用场景**:
- **行 381**: `ExecCommandEnd` 事件 - 显示命令执行耗时
  ```rust
  let duration = format!(" in {}", format_duration(duration));
  ```
- **行 420**: `McpToolCallEnd` 事件 - 显示 MCP 工具调用耗时
  ```rust
  let duration = format!(" in {}", format_duration(duration));
  ```
- **行 586**: `PatchApplyEnd` 事件 - 显示补丁应用耗时（使用 `format_elapsed`）
  ```rust
  format!(" in {}", format_elapsed(start_time))
  ```
- **行 1101**: Agent Job 进度 - 显示 ETA（预计剩余时间）
  ```rust
  .map(|secs| format_duration(Duration::from_secs(secs)))
  ```

#### 2. codex-tui（终端用户界面）

**文件**: `codex-rs/tui/src/exec_cell/render.rs`

```rust
use codex_utils_elapsed::format_duration;
```

**使用场景**:
- **行 234**: 渲染执行单元（ExecCell）持续时间
  ```rust
  let duration = call
      .duration
      .map(format_duration)
      .unwrap_or_else(|| "unknown".to_string());
  ```

**注意**: TUI 的 `history_cell.rs` 中有一个**同名但独立的函数** `format_duration_ms`，用于格式化毫秒为秒（如 `1.2s`），不使用本库。

#### 3. codex-tui-app-server（TUI 应用服务器）

**文件**: `codex-rs/tui_app_server/src/exec_cell/render.rs`

```rust
use codex_utils_elapsed::format_duration;
```

**使用场景**:
- **行 234**: 与 TUI 相同的渲染逻辑，显示执行单元持续时间

**注意**: 同样存在独立的 `format_duration_ms` 函数在 `history_cell.rs` 中。

### 调用关系图

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-utils-elapsed                       │
│  ┌─────────────────┐  ┌──────────────────┐                  │
│  │ format_elapsed  │  │ format_duration  │                  │
│  └────────┬────────┘  └────────┬─────────┘                  │
└───────────┼────────────────────┼────────────────────────────┘
            │                    │
            ▼                    ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   codex-exec    │    │   codex-tui     │    │codex-tui-app-svr│
│                 │    │                 │    │                 │
│ • ExecCommand   │    │ • ExecCell      │    │ • ExecCell      │
│ • McpToolCall   │    │   duration      │    │   duration      │
│ • PatchApply    │    │                 │    │                 │
│ • Agent Job ETA │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 依赖与外部交互

### 内部依赖

| 类型 | 依赖 | 说明 |
|------|------|------|
| 标准库 | `std::time::Duration` | 时间间隔类型 |
| 标准库 | `std::time::Instant` | 时间点类型 |

**零外部 crate 依赖** - 这是该库的核心优势，确保：
- 编译速度快
- 无版本冲突风险
- 可移植性高

### 反向依赖（调用方）

在 `codex-rs/Cargo.toml` workspace 中定义：

```toml
[workspace.dependencies]
codex-utils-elapsed = { path = "utils/elapsed" }
```

被以下 crate 依赖：

| Crate | 用途 |
|-------|------|
| `codex-exec` | CLI 执行器的人类可读输出 |
| `codex-tui` | TUI 界面执行单元渲染 |
| `codex-tui-app-server` | TUI 应用服务器执行单元渲染 |

### Bazel 构建配置

**文件**: `codex-rs/utils/elapsed/BUILD.bazel`

```starlark
load("//:defs.bzl", "codex_rust_crate")

codex_rust_crate(
    name = "elapsed",
    crate_name = "codex_utils_elapsed",
)
```

使用项目统一的 `codex_rust_crate` 宏进行构建配置。

---

## 风险、边界与改进建议

### 已知边界情况

#### 1. 负数输入

**风险**: `format_elapsed_millis` 接受 `i64` 参数，但负数输入会产生异常输出。

```rust
// 当前行为（未定义）
format_elapsed_millis(-100); // "-100ms"
format_elapsed_millis(-1000); // "-1.00s"
format_elapsed_millis(-60000); // "-1m -00s"（秒数显示为负数）
```

**建议**: 添加 `debug_assert!` 或在文档中明确说明前置条件。

#### 2. 极大值处理

**风险**: 当毫秒数超过 `i64::MAX`（约 2.9 亿年）时会发生溢出。

**实际影响**: 在实际应用场景中几乎不可能触发，因为 `Instant::elapsed()` 返回的 Duration 受限于程序运行时间。

#### 3. 浮点精度

**风险**: 在 59.999s 边界处，浮点转换可能导致显示为 `60.00s` 而非预期的分钟格式。

**当前行为**（来自测试）：
```rust
let dur2 = Duration::from_millis(59_999);
assert_eq!(format_duration(dur2), "60.00s"); // 秒级显示，而非 0m 59s
```

这是**有意为之的设计**，因为 59_999ms < 60_000ms，属于秒级范围。

#### 4. 无小时/天单位

**风险**: 极长时间（如数小时）会显示为很大的分钟数（如 `180m 00s` 而非 `3h 00m`）。

**当前设计意图**: 保持简洁，避免复杂的时间单位转换。测试用例明确验证了这一行为：
```rust
let dur_hour = Duration::from_millis(3_600_000);
assert_eq!(format_duration(dur_hour), "60m 00s"); // 而非 1h 00m
```

### 改进建议

#### 1. 添加 `#[inline]` 提示

```rust
#[inline]
pub fn format_elapsed(start_time: Instant) -> String { ... }

#[inline]
pub fn format_duration(duration: Duration) -> String { ... }
```

由于函数体积小且被频繁调用，内联提示可能带来性能提升。

#### 2. 扩展格式化选项

考虑添加可选参数支持自定义格式：

```rust
pub struct FormatOptions {
    pub show_hours: bool,      // 是否显示小时单位
    pub decimal_places: u8,    // 秒的小数位数
    pub subsecond_unit: SubsecondUnit, // ms / us / ns
}
```

#### 3. 国际化支持

当前格式为硬编码的英文格式（`m`, `s`, `ms`）。如需支持多语言，可考虑：

```rust
pub fn format_duration_with_locale(duration: Duration, locale: &str) -> String
```

#### 4. 添加更多测试边界

```rust
#[test]
fn test_format_duration_negative() {
    // 定义负数输入的预期行为
}

#[test]
fn test_format_duration_very_large() {
    // 测试大数值（如超过 24 小时）
}
```

#### 5. 文档改进

在函数文档中添加更多示例：

```rust
/// # Examples
///
/// ```
/// use std::time::Duration;
/// use codex_utils_elapsed::format_duration;
///
/// assert_eq!(format_duration(Duration::from_millis(500)), "500ms");
/// assert_eq!(format_duration(Duration::from_secs(5)), "5.00s");
/// assert_eq!(format_duration(Duration::from_secs(90)), "1m 30s");
/// ```
```

### 维护建议

1. **保持零依赖**: 该库的核心价值在于简单和零依赖，新增功能时应权衡复杂度
2. **统一时间格式化**: 考虑将 TUI 中的 `format_duration_ms` 函数也迁移到本库，避免重复实现
3. **性能基准**: 如需优化，可添加 `criterion` 基准测试验证格式化性能

---

## 总结

`codex-utils-elapsed` 是一个**设计精良、职责单一、零依赖**的工具库，为 Codex 项目提供了统一的时间格式化标准。其核心优势在于：

- **简洁性**: 仅 78 行代码（含测试），易于理解和维护
- **实用性**: 三段式格式化覆盖绝大多数用户场景
- **可复用性**: 被多个上层组件共享，避免重复实现
- **稳定性**: 使用标准库类型，无外部依赖风险

该库体现了 Rust 生态中"小工具库"（micro-crate）的设计哲学，是项目中工具类代码组织的良好范例。
