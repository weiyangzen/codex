# unified_exec.rs 研究文档

## 场景与职责

`unified_exec.rs` 是 Codex 核心测试套件中最关键的集成测试文件之一，负责验证 **Unified Exec** 子系统的完整功能。Unified Exec 是 Codex 中用于执行 shell 命令的现代化统一执行框架，它取代了传统的 shell 工具执行方式，提供了更强大的交互式进程管理能力。

该测试文件位于 `codex-rs/core/tests/suite/unified_exec.rs`，包含 30+ 个集成测试用例，总代码量约 3000 行，是 core 测试中规模最大的测试文件之一。

### 核心职责

1. **验证 Unified Exec 工具的核心功能**：包括命令执行、会话管理、TTY 支持、输出截断等
2. **测试进程生命周期管理**：验证长时间运行的后台进程、进程复用、优雅退出等
3. **验证沙箱集成**：确保 Unified Exec 在各种沙箱策略下正确工作
4. **测试事件系统**：验证 ExecCommandBegin/End、TerminalInteraction 等事件的正确发射
5. **验证 apply_patch 拦截**：测试 Unified Exec 对 apply_patch 命令的特殊处理

---

## 功能点目的

### 1. Unified Exec 核心功能测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_intercepts_apply_patch_exec_command` | 验证 apply_patch 命令被正确拦截并转换为 PatchApply 事件 |
| `unified_exec_emits_exec_command_begin_event` | 验证 ExecCommandBegin 事件的正确发射 |
| `unified_exec_emits_exec_command_end_event` | 验证 ExecCommandEnd 事件的正确发射 |
| `unified_exec_emits_output_delta_for_exec_command` | 验证输出增量事件（ExecCommandOutputDelta） |
| `unified_exec_full_lifecycle_with_background_end_event` | 验证完整生命周期包括后台结束事件 |

### 2. 工作目录与路径解析测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_resolves_relative_workdir` | 验证相对工作目录正确解析 |
| `unified_exec_respects_workdir_override` | 验证工作目录覆盖配置生效 |

### 3. TTY 与终端交互测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_emits_terminal_interaction_for_write_stdin` | 验证 TerminalInteraction 事件 |
| `unified_exec_terminal_interaction_captures_delayed_output` | 验证延迟输出捕获 |
| `unified_exec_defaults_to_pipe` | 验证默认使用 pipe 模式（非 TTY） |
| `unified_exec_can_enable_tty` | 验证 TTY 模式可启用 |

### 4. 会话管理与进程复用测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_keeps_long_running_session_after_turn_end` | 验证回合结束后长时间运行的会话保持 |
| `unified_exec_interrupt_preserves_long_running_session` | 验证中断后长时间运行的会话保持 |
| `unified_exec_reuses_session_via_stdin` | 验证通过 write_stdin 复用会话 |
| `write_stdin_returns_exit_metadata_and_clears_session` | 验证 write_stdin 返回退出元数据并清理会话 |
| `unified_exec_emits_end_event_when_session_dies_via_stdin` | 验证会话通过 stdin 结束时发射事件 |

### 5. 输出处理与截断测试

| 测试函数 | 目的 |
|---------|------|
| `exec_command_reports_chunk_and_exit_metadata` | 验证 chunk ID 和退出元数据报告 |
| `unified_exec_formats_large_output_summary` | 验证大输出格式化摘要 |
| `unified_exec_streams_after_lagged_output` | 验证滞后输出后的流式处理 |
| `unified_exec_respects_early_exit_notifications` | 验证提前退出通知 |

### 6. 超时与轮询测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_timeout_and_followup_poll` | 验证超时和后续轮询 |

### 7. 沙箱与跨平台测试

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_runs_under_sandbox` | 验证在沙箱下运行 |
| `unified_exec_python_prompt_under_seatbelt` | 验证 macOS Seatbelt 下的 Python 交互 |
| `unified_exec_runs_on_all_platforms` | 验证跨平台运行 |

### 8. 会话修剪测试（被忽略）

| 测试函数 | 目的 |
|---------|------|
| `unified_exec_prunes_exited_sessions_first` | 验证优先修剪已退出会话（标记为 `#[ignore]`） |

---

## 具体技术实现

### 关键数据结构

#### ParsedUnifiedExecOutput

```rust
#[derive(Debug)]
struct ParsedUnifiedExecOutput {
    chunk_id: Option<String>,           // 6位十六进制 chunk ID
    wall_time_seconds: f64,             // 执行耗时（秒）
    process_id: Option<String>,         // 进程/会话 ID
    exit_code: Option<i32>,             // 退出码
    original_token_count: Option<usize>, // 原始 token 数量
    output: String,                     // 实际输出内容
}
```

该结构用于解析 Unified Exec 工具的输出格式，输出格式示例：
```
Chunk ID: a3f7b2
Wall time: 0.523 seconds
Process exited with code 0
Original token count: 42

Output:
<实际输出内容>
```

### 关键流程

#### 1. 测试初始化流程

```rust
let server = start_mock_server().await;
let mut builder = test_codex().with_config(|config| {
    config.use_experimental_unified_exec_tool = true;
    config.features.enable(Feature::UnifiedExec).expect(...);
});
let TestCodex { codex, cwd, session_configured, .. } = builder.build(&server).await?;
```

所有测试遵循以下初始化模式：
1. 启动 Mock SSE 服务器 (`start_mock_server`)
2. 配置测试 Codex 实例，启用 UnifiedExec 特性
3. 构建 TestCodex 获取测试句柄

#### 2. SSE 响应序列设置

```rust
let responses = vec![
    sse(vec![
        ev_response_created("resp-1"),
        ev_function_call(call_id, "exec_command", &serde_json::to_string(&args)?),
        ev_completed("resp-1"),
    ]),
    sse(vec![
        ev_response_created("resp-2"),
        ev_assistant_message("msg-1", "done"),
        ev_completed("resp-2"),
    ]),
];
mount_sse_sequence(&server, responses).await;
```

使用 `mount_sse_sequence` 设置模拟的 SSE 响应序列，测试可以控制模型返回的函数调用。

#### 3. 事件等待与验证

```rust
let begin_event = wait_for_event_match(&codex, |msg| match msg {
    EventMsg::ExecCommandBegin(event) if event.call_id == call_id => Some(event.clone()),
    _ => None,
}).await;
```

使用 `wait_for_event_match` 等待特定事件并验证其内容。

### 输出解析实现

```rust
fn parse_unified_exec_output(raw: &str) -> Result<ParsedUnifiedExecOutput> {
    let cleaned = raw.replace("\r\n", "\n");
    let (metadata, output) = cleaned
        .rsplit_once("\nOutput:")
        .ok_or_else(|| anyhow::anyhow!("missing Output section"))?;
    // 解析各个字段...
}
```

### 工具输出收集

```rust
fn collect_tool_outputs(bodies: &[Value]) -> Result<HashMap<String, ParsedUnifiedExecOutput>> {
    let mut outputs = HashMap::new();
    for body in bodies {
        if let Some(items) = body.get("input").and_then(Value::as_array) {
            for item in items {
                // 过滤 function_call_output 类型的项
                // 解析并存储输出
            }
        }
    }
    Ok(outputs)
}
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/unified_exec/mod.rs` | Unified Exec 模块入口，定义核心类型和常量 |
| `codex-rs/core/src/unified_exec/process.rs` | PTY 进程生命周期管理 |
| `codex-rs/core/src/unified_exec/process_manager.rs` | 进程管理器（orchestration、 approvals、sandboxing） |
| `codex-rs/core/src/unified_exec/async_watcher.rs` | 异步退出监视器和输出流 |
| `codex-rs/core/src/tools/handlers/unified_exec.rs` | Unified Exec 工具处理器 |
| `codex-rs/core/src/tools/runtimes/unified_exec.rs` | Unified Exec 运行时 |
| `codex-rs/core/src/features.rs` | 特性标志定义（Feature::UnifiedExec） |

### 测试支持代码

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/common/lib.rs` | 测试公共库，包含事件等待辅助函数 |
| `codex-rs/core/tests/common/responses.rs` | Mock SSE 服务器和响应辅助函数 |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodex 构建器和测试基础设施 |
| `codex-rs/core/tests/common/process.rs` | 进程等待和生命周期辅助函数 |

### 关键常量

```rust
// codex-rs/core/src/unified_exec/mod.rs
pub(crate) const MIN_YIELD_TIME_MS: u64 = 250;
pub(crate) const MIN_EMPTY_YIELD_TIME_MS: u64 = 5_000;
pub(crate) const MAX_YIELD_TIME_MS: u64 = 30_000;
pub(crate) const DEFAULT_MAX_BACKGROUND_TERMINAL_TIMEOUT_MS: u64 = 300_000;
pub(crate) const DEFAULT_MAX_OUTPUT_TOKENS: usize = 10_000;
pub(crate) const UNIFIED_EXEC_OUTPUT_MAX_BYTES: usize = 1024 * 1024; // 1 MiB
pub(crate) const MAX_UNIFIED_EXEC_PROCESSES: usize = 64;
pub(crate) const WARNING_UNIFIED_EXEC_PROCESSES: usize = 60;
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `wiremock` | Mock HTTP 服务器，模拟 OpenAI API |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化/反序列化 |
| `tempfile` | 临时目录管理 |
| `which` | 查找可执行文件路径 |
| `pretty_assertions` | 更好的测试断言输出 |

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `core_test_support` | 测试支持库（等待事件、Mock 服务器等） |
| `codex_core::features::Feature` | 特性标志 |
| `codex_protocol::protocol::*` | 协议事件类型 |
| `codex_utils_pty` | PTY（伪终端）操作 |

### 测试前置条件

所有测试都使用以下宏进行条件跳过：

```rust
skip_if_no_network!(Ok(()));    // 无网络时跳过
skip_if_sandbox!(Ok(()));       // 沙箱环境中跳过
skip_if_windows!(Ok(()));       // Windows 平台跳过（大部分测试）
```

---

## 风险、边界与改进建议

### 已知风险

1. **平台限制**：大部分测试在非 Windows 平台运行，Windows 覆盖有限
2. **沙箱限制**：测试在沙箱环境中会被跳过，可能影响 CI 覆盖
3. **网络依赖**：需要网络连接，在离线环境无法运行
4. **测试时间**：部分测试涉及超时和等待，执行时间较长

### 边界情况

1. **进程 ID 冲突**：测试使用确定性进程 ID（1000+），与生产环境随机 ID 不同
2. **并发限制**：`MAX_UNIFIED_EXEC_PROCESSES = 64` 限制同时运行的进程数
3. **输出截断**：大输出会被截断到 `DEFAULT_MAX_OUTPUT_TOKENS`（10,000 tokens）
4. **超时边界**：`MIN_YIELD_TIME_MS` (250ms) 到 `MAX_YIELD_TIME_MS` (30s) 的 yield 时间范围

### 被忽略的测试

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "flaky"]
async fn unified_exec_respects_workdir_override() -> Result<()> { ... }

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore]
async fn unified_exec_prunes_exited_sessions_first() -> Result<()> { ... }
```

- `unified_exec_respects_workdir_override`：标记为 flaky，可能因时序问题不稳定
- `unified_exec_prunes_exited_sessions_first`：会话修剪逻辑测试，可能因实现变更而失效

### 改进建议

1. **增加 Windows 覆盖**：为 Windows 平台添加专门的测试用例
2. **减少测试时间**：优化超时测试，使用更短的 yield 时间
3. **稳定 flaky 测试**：修复 `unified_exec_respects_workdir_override` 的时序问题
4. **文档完善**：添加更多内联注释说明测试意图
5. **并发测试**：添加多线程并发使用 Unified Exec 的测试
6. **错误场景**：增加更多错误处理场景的测试（如权限拒绝、命令不存在等）

### 相关配置项

```rust
// Config 中影响 Unified Exec 的配置
config.use_experimental_unified_exec_tool = true;  // 启用实验性 Unified Exec
config.features.enable(Feature::UnifiedExec);      // 启用特性标志
config.include_apply_patch_tool = true;            // 包含 apply_patch 工具
```
