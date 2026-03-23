# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Codex 工具系统的根模块，负责组织和导出工具子模块，同时提供工具输出格式化的共享功能。它是工具系统的入口点，定义了：

1. **子模块组织结构**：声明所有工具相关的子模块
2. **工具输出格式化**：提供 exec 工具输出的标准化格式化功能
3. **遥测预览常量**：定义遥测日志的截断限制

## 功能点目的

### 1. 模块组织
声明并导出工具系统的所有子模块：
- `code_mode`：Code Mode 工具执行
- `code_mode_description`：Code Mode 工具描述生成
- `context`：工具调用上下文和输出抽象
- `discoverable`：可发现工具管理
- `events`：工具事件发射
- `handlers`：工具处理器实现
- `js_repl`：JavaScript REPL 工具
- `network_approval`：网络访问审批管理
- `orchestrator`：工具执行编排
- `parallel`：并行工具执行
- `registry`：工具注册表
- `router`：工具路由
- `runtimes`：工具运行时实现
- `sandboxing`：沙箱和审批抽象
- `spec`：工具规范定义

### 2. 遥测预览限制常量
定义遥测日志的截断参数：
- `TELEMETRY_PREVIEW_MAX_BYTES`：2 KiB（最大字节数）
- `TELEMETRY_PREVIEW_MAX_LINES`：64 行（最大行数）
- `TELEMETRY_PREVIEW_TRUNCATION_NOTICE`：截断提示文本

### 3. Exec 输出格式化
提供三种格式化模式：
- **结构化格式** (`format_exec_output_for_model_structured`)：JSON 格式，包含元数据
- **自由格式** (`format_exec_output_for_model_freeform`)：人类可读格式
- **字符串格式** (`format_exec_output_str`)：纯文本截断

## 具体技术实现

### 模块导出结构

```rust
// 公开子模块
pub mod code_mode;
pub mod context;
pub mod events;
pub mod handlers;
pub mod js_repl;
pub mod orchestrator;
pub mod parallel;
pub mod registry;
pub mod router;
pub mod runtimes;
pub mod sandboxing;
pub mod spec;

// 内部子模块
pub(crate) mod code_mode_description;
pub(crate) mod discoverable;
pub(crate) mod network_approval;
```

### 遥测预览常量

```rust
// 遥测预览限制：保持日志事件小于模型预算
pub(crate) const TELEMETRY_PREVIEW_MAX_BYTES: usize = 2 * 1024; // 2 KiB
pub(crate) const TELEMETRY_PREVIEW_MAX_LINES: usize = 64; // 行数
pub(crate) const TELEMETRY_PREVIEW_TRUNCATION_NOTICE: &str =
    "[... telemetry preview truncated ...]";
```

### Exec 输出格式化

#### 1. 结构化格式
```rust
pub fn format_exec_output_for_model_structured(
    exec_output: &ExecToolCallOutput,
    truncation_policy: TruncationPolicy,
) -> String {
    // 序列化为 JSON 格式：
    // {
    //   "output": "...",
    //   "metadata": {
    //     "exit_code": 0,
    //     "duration_seconds": 1.2
    //   }
    // }
}
```

**特点**：
- 使用 `serde::Serialize` 生成 JSON
- 持续时间四舍五入到 1 位小数
- 包含退出码和执行时间元数据

#### 2. 自由格式
```rust
pub fn format_exec_output_for_model_freeform(
    exec_output: &ExecToolCallOutput,
    truncation_policy: TruncationPolicy,
) -> String {
    // 生成人类可读格式：
    // Exit code: 0
    // Wall time: 1.2 seconds
    // Total output lines: 100
    // Output:
    // ...
}
```

**特点**：
- 更易读的格式
- 显示总行数（如果发生截断）
- 包含超时提示（如果命令超时）

#### 3. 字符串格式
```rust
pub fn format_exec_output_str(
    exec_output: &ExecToolCallOutput,
    truncation_policy: TruncationPolicy,
) -> String {
    // 提取内容并截断
}
```

**内部辅助函数**：
```rust
fn build_content_with_timeout(exec_output: &ExecToolCallOutput) -> String {
    if exec_output.timed_out {
        format!("command timed out after {} milliseconds\n{}", ...)
    } else {
        exec_output.aggregated_output.text.clone()
    }
}
```

### 关键代码路径

| 类型/函数 | 行号 | 职责 |
|-----------|------|------|
| 模块声明 | 1-16 | 声明所有子模块 |
| `ToolRouter` 重导出 | 21 | 便捷导出路由类型 |
| 遥测常量 | 24-28 | 定义预览限制 |
| `format_exec_output_for_model_structured` | 32-69 | 结构化 JSON 格式化 |
| `format_exec_output_for_model_freeform` | 71-96 | 自由文本格式化 |
| `format_exec_output_str` | 98-106 | 字符串格式化入口 |
| `build_content_with_timeout` | 109-119 | 内容提取（含超时提示）|

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::exec::ExecToolCallOutput` | Exec 工具输出类型 |
| `crate::truncate::{TruncationPolicy, formatted_truncate_text, truncate_text}` | 文本截断 |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde::Serialize` | JSON 序列化 |

### 调用关系

```
工具运行时 (runtimes/)
    └── 生成 ExecToolCallOutput
        └── format_exec_output_for_model_structured/freeform
            └── 返回格式化字符串给模型

遥测系统 (通过 context.rs)
    └── telemetry_preview
        └── 使用 TELEMETRY_PREVIEW_MAX_* 常量
```

## 风险、边界与改进建议

### 已知风险

1. **JSON 序列化 panic**
   ```rust
   #[expect(clippy::expect_used)]
   serde_json::to_string(&payload).expect("serialize ExecOutput")
   ```
   使用 `expect` 可能导致 panic，虽然理论上不会失败。

2. **时间精度丢失**
   ```rust
   let duration_seconds = ((duration.as_secs_f32()) * 10.0).round() / 10.0;
   ```
   四舍五入到 1 位小数可能丢失精度。

3. **模块可见性不一致**
   - 部分模块使用 `pub`，部分使用 `pub(crate)`
   - 没有统一的可见性策略文档

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 超时命令 | 在输出前添加超时提示 |
| 空输出 | 返回空字符串或 `{}` |
| 极大输出 | 通过 `truncation_policy` 截断 |
| 负退出码 | 直接序列化 |

### 改进建议

1. **移除 expect 使用**
   ```rust
   // 当前
   serde_json::to_string(&payload).expect("serialize ExecOutput")
   
   // 建议
   serde_json::to_string(&payload)
       .unwrap_or_else(|e| format!("{{\"error\":\"serialization failed: {e}\"}}"))
   ```

2. **使用 Duration 的 Display 实现**
   ```rust
   // 当前：手动格式化
   format!("{:.1}", duration.as_secs_f32())
   
   // 建议：使用 humantime 或标准库
   format!("{:?}", duration) // 或 humantime::format_duration
   ```

3. **添加模块文档**
   ```rust
   //! Codex tool system root module.
   //!
   //! This module organizes all tool-related functionality including:
   //! - Tool execution runtimes
   //! - Tool registration and routing
   //! - Sandboxing and approval flows
   //! - Output formatting and event emission
   ```

4. **统一模块可见性**
   ```rust
   // 建议文档化可见性策略
   // pub - 外部 crate 可用
   // pub(crate) - 仅本 crate 可用
   // mod - 仅父模块可用
   ```

5. **添加格式化选项结构**
   ```rust
   pub struct FormatOptions {
       pub include_timeout_message: bool,
       pub duration_precision: u32,
       pub max_output_lines: Option<usize>,
   }
   ```

6. **添加测试**
   - 当前 `mod.rs` 没有对应的测试文件
   - 建议添加 `mod_tests.rs` 测试格式化函数

### 设计决策说明

1. **为何两种格式化模式**
   - 结构化格式：便于模型解析，适合自动化处理
   - 自由格式：更易读，适合人类查看和调试

2. **为何常量定义在根模块**
   - 遥测限制是全局策略
   - 多个子模块需要共享（context.rs、events.rs 等）

3. **为何使用 `pub(crate)` 限制部分模块**
   - `code_mode_description`：仅在工具注册时使用
   - `discoverable`：仅在 spec 构建时使用
   - `network_approval`：仅在 orchestrator 和 runtimes 中使用
