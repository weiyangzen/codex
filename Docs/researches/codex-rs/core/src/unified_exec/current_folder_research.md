# unified_exec 目录研究报告

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`unified_exec` 是 Codex 核心中负责**交互式进程执行**的模块，提供了一套完整的进程生命周期管理能力，包括创建、复用、输出缓冲、沙箱隔离和用户审批流程。

### 核心职责

1. **交互式进程管理**：支持长时间运行的交互式 shell 会话（如 `bash -i`），允许模型通过 `write_stdin` 向进程发送输入
2. **进程复用**：通过 `process_id` 机制让多个命令在同一个 shell 会话中执行，保持环境变量和状态
3. **沙箱集成**：与系统的沙箱机制（Seatbelt、Landlock 等）集成，在受限环境中执行命令
4. **审批流程**：通过 `ToolOrchestrator` 统一管理命令审批、沙箱选择和重试逻辑
5. **输出管理**：使用 Head-Tail 缓冲区限制输出大小，同时保留开头和结尾的关键信息

### 使用场景

- **持久化 Shell 会话**：模型启动交互式 shell，后续通过 `write_stdin` 发送命令
- **短命令执行**：一次性命令执行，完成后自动清理
- **带网络代理的执行**：支持通过 `NetworkProxy` 进行网络访问控制
- **多进程管理**：同时管理最多 64 个后台进程，支持 LRU 清理策略

---

## 功能点目的

### 1. 进程生命周期管理 (`process.rs`)

**目的**：封装 PTY 进程的生命周期，提供统一的进程控制接口。

**关键功能**：
- 通过 `ExecCommandSession` 与底层 PTY 交互
- 使用广播通道 (`broadcast::Receiver`) 实现多消费者输出订阅
- 支持进程终止、退出码查询、沙箱拒绝检测

### 2. 进程管理器 (`process_manager.rs`)

**目的**：提供高层次的进程管理 API，协调审批、沙箱、输出收集等流程。

**关键功能**：
- `exec_command`：执行新命令，处理审批和沙箱逻辑
- `write_stdin`：向现有进程发送输入
- `allocate_process_id`：分配唯一进程 ID（生产环境随机，测试环境顺序）
- 进程清理策略：优先清理已退出进程，保护最近使用的 8 个进程

### 3. 异步监视器 (`async_watcher.rs`)

**目的**：后台任务管理，处理输出流和进程退出事件。

**关键功能**：
- `start_streaming_output`：持续读取 PTY 输出并发送 `ExecCommandOutputDelta` 事件
- `spawn_exit_watcher`：监听进程退出并发送 `ExecCommandEnd` 事件
- UTF-8 边界处理：确保输出事件在有效的 UTF-8 边界处分割

### 4. 头尾缓冲区 (`head_tail_buffer.rs`)

**目的**：在内存受限情况下保留最有价值的输出信息。

**设计原理**：
- 总容量 1 MiB (`UNIFIED_EXEC_OUTPUT_MAX_BYTES`)
- 对称设计：50% 头部（开头）+ 50% 尾部（结尾）
- 中间内容被截断，保留 `... omitted X bytes ...` 提示

### 5. 错误处理 (`errors.rs`)

**目的**：定义统一的错误类型，支持沙箱拒绝等特殊场景。

**错误类型**：
- `CreateProcess`：进程创建失败
- `UnknownProcessId`：无效的进程 ID
- `SandboxDenied`：沙箱拒绝执行（包含输出用于重试）
- `StdinClosed`：尝试向非 TTY 进程写入 stdin

---

## 具体技术实现

### 关键流程

#### 1. 进程创建流程 (`exec_command`)

```
┌─────────────────┐
│  分配 process_id  │
└────────┬────────┘
         ▼
┌─────────────────┐
│ 构建 ExecCommandRequest │
└────────┬────────┘
         ▼
┌─────────────────┐
│ open_session_with_sandbox │
│  - 创建 ToolOrchestrator   │
│  - 构建 UnifiedExecRuntime │
│  - 获取审批要求            │
└────────┬────────┘
         ▼
┌─────────────────┐
│ ToolOrchestrator::run │
│  - 审批检查（缓存/提示）  │
│  - 选择沙箱类型          │
│  - 执行并处理重试        │
└────────┬────────┘
         ▼
┌─────────────────┐
│ open_session_with_exec_env │
│  - 构建 CommandSpec        │
│  - 应用沙箱转换            │
│  - 调用 PTY 创建           │
└────────┬────────┘
         ▼
┌─────────────────┐
│ UnifiedExecProcess::new │
│  - 创建输出缓冲区        │
│  - 启动输出收集任务      │
└─────────────────┘
```

**代码位置**：`process_manager.rs:155-306`

#### 2. 输出收集流程

```rust
// 1. 启动后台流式输出任务
start_streaming_output(&process, context, Arc::clone(&transcript));

// 2. 等待 yield_time_ms 或进程退出
let collected = Self::collect_output_until_deadline(
    &output_buffer,
    &output_notify,
    &output_closed,
    &output_closed_notify,
    &cancellation_token,
    pause_state,
    deadline,
).await;
```

**关键机制**：
- `output_notify`：有新输出时通知等待者
- `cancellation_token`：进程退出信号
- `pause_state`：支持外部暂停（如 out-of-band elicitation）
- 退出后额外等待 50ms (`POST_EXIT_CLOSE_WAIT_CAP`) 确保输出完整

**代码位置**：`process_manager.rs:645-732`

#### 3. 沙箱拒绝处理流程

```rust
// 1. 进程退出后检查是否为沙箱拒绝
pub(super) async fn check_for_sandbox_denial(&self) -> Result<(), UnifiedExecError> {
    let collected_chunks = self.snapshot_output().await;
    let aggregated_text = String::from_utf8_lossy(&aggregated).to_string();
    self.check_for_sandbox_denial_with_text(&aggregated_text).await
}

// 2. 使用共享启发式函数判断
if is_likely_sandbox_denied(sandbox_type, &exec_output) {
    return Err(UnifiedExecError::sandbox_denied(message, exec_output));
}
```

**重试逻辑**：`ToolOrchestrator` 捕获 `SandboxDenied` 错误后，在无沙箱模式下重试。

**代码位置**：`process.rs:176-221`

### 数据结构

#### `UnifiedExecProcessManager`

```rust
pub(crate) struct UnifiedExecProcessManager {
    process_store: Mutex<ProcessStore>,
    max_write_stdin_yield_time_ms: u64,
}

struct ProcessStore {
    processes: HashMap<i32, ProcessEntry>,
    reserved_process_ids: HashSet<i32>,
}

struct ProcessEntry {
    process: Arc<UnifiedExecProcess>,
    call_id: String,
    process_id: i32,
    command: Vec<String>,
    tty: bool,
    network_approval_id: Option<String>,
    session: Weak<Session>,
    last_used: tokio::time::Instant,
}
```

#### `UnifiedExecProcess`

```rust
pub(crate) struct UnifiedExecProcess {
    process_handle: ExecCommandSession,      // PTY 会话句柄
    output_rx: broadcast::Receiver<Vec<u8>>, // 输出订阅
    output_buffer: OutputBuffer,             // 共享缓冲区
    output_notify: Arc<Notify>,              // 新输出通知
    output_closed: Arc<AtomicBool>,          // 输出结束标记
    cancellation_token: CancellationToken,   // 退出信号
    output_task: JoinHandle<()>,             // 输出收集任务
    sandbox_type: SandboxType,
}
```

#### `HeadTailBuffer`

```rust
pub(crate) struct HeadTailBuffer {
    max_bytes: usize,
    head_budget: usize,      // max_bytes / 2
    tail_budget: usize,      // max_bytes - head_budget
    head: VecDeque<Vec<u8>>, // 前缀数据
    tail: VecDeque<Vec<u8>>, // 后缀数据
    head_bytes: usize,
    tail_bytes: usize,
    omitted_bytes: usize,    // 被截断的字节数
}
```

### 协议与常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `MIN_YIELD_TIME_MS` | 250 | 最小等待时间 |
| `MAX_YIELD_TIME_MS` | 30,000 | 最大等待时间 |
| `MIN_EMPTY_YIELD_TIME_MS` | 5,000 | 空输入时的最小等待 |
| `DEFAULT_MAX_BACKGROUND_TERMINAL_TIMEOUT_MS` | 300,000 | 后台终端默认超时 |
| `DEFAULT_MAX_OUTPUT_TOKENS` | 10,000 | 默认最大输出 token |
| `UNIFIED_EXEC_OUTPUT_MAX_BYTES` | 1 MiB | 输出缓冲区上限 |
| `MAX_UNIFIED_EXEC_PROCESSES` | 64 | 最大进程数 |
| `WARNING_UNIFIED_EXEC_PROCESSES` | 60 | 警告阈值 |

### 环境变量注入

```rust
const UNIFIED_EXEC_ENV: [(&str, &str); 10] = [
    ("NO_COLOR", "1"),           // 禁用颜色输出
    ("TERM", "dumb"),            // 终端类型
    ("LANG", "C.UTF-8"),         // 字符编码
    ("LC_CTYPE", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
    ("COLORTERM", ""),           // 禁用颜色终端
    ("PAGER", "cat"),            // 禁用分页器
    ("GIT_PAGER", "cat"),
    ("GH_PAGER", "cat"),
    ("CODEX_CI", "1"),           // CI 环境标记
];
```

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/core/src/unified_exec/
├── mod.rs                      # 模块入口，定义核心结构和常量
├── mod_tests.rs               # 集成测试
├── errors.rs                   # 错误类型定义
├── process.rs                  # PTY 进程生命周期管理
├── process_manager.rs          # 进程管理器和主流程
├── process_manager_tests.rs    # 进程管理器单元测试
├── async_watcher.rs            # 异步输出流和退出监视
├── async_watcher_tests.rs      # 异步监视器测试
├── head_tail_buffer.rs         # 头尾缓冲区实现
└── head_tail_buffer_tests.rs   # 缓冲区测试
```

### 关键代码路径

| 功能 | 文件 | 行号 |
|------|------|------|
| 模块入口和常量定义 | `mod.rs` | 1-173 |
| `UnifiedExecContext` 定义 | `mod.rs` | 70-84 |
| `ExecCommandRequest` 定义 | `mod.rs` | 86-100 |
| `UnifiedExecProcessManager` 定义 | `mod.rs` | 123-142 |
| 错误类型定义 | `errors.rs` | 1-34 |
| `UnifiedExecProcess` 定义 | `process.rs` | 57-70 |
| 进程创建 | `process.rs` | 72-123 |
| 沙箱拒绝检测 | `process.rs` | 176-221 |
| 从 SpawnedPty 构建 | `process.rs` | 223-263 |
| `exec_command` 主流程 | `process_manager.rs` | 155-306 |
| `write_stdin` 实现 | `process_manager.rs` | 308-401 |
| 输出收集 | `process_manager.rs` | 645-732 |
| 进程清理策略 | `process_manager.rs` | 770-815 |
| 流式输出启动 | `async_watcher.rs` | 39-101 |
| 退出监视器 | `async_watcher.rs` | 106-140 |
| UTF-8 分割 | `async_watcher.rs` | 216-244 |
| `HeadTailBuffer` 实现 | `head_tail_buffer.rs` | 9-179 |

### 调用方引用

| 调用方 | 用途 |
|--------|------|
| `codex.rs:1789` | 创建 `UnifiedExecProcessManager` |
| `codex.rs:5102` | 会话关闭时终止所有进程 |
| `tools/handlers/unified_exec.rs` | 处理 `exec_command` 和 `write_stdin` 工具调用 |
| `tools/runtimes/unified_exec.rs` | 实现 `ToolRuntime` trait，集成审批和沙箱 |
| `state/service.rs:36` | 在 `SessionServices` 中持有管理器实例 |

---

## 依赖与外部交互

### 内部依赖

```rust
// 核心模块
crate::codex::{Session, TurnContext}
crate::sandboxing::{SandboxPermissions, ExecRequest}
crate::exec_policy::ExecPolicyManager
crate::tools::orchestrator::ToolOrchestrator
crate::tools::sandboxing::{Approvable, Sandboxable, ToolRuntime}

// 子模块间依赖
async_watcher -> process, head_tail_buffer
process_manager -> process, async_watcher, errors
mod -> process_manager, errors, async_watcher, head_tail_buffer
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_utils_pty` | PTY 创建和管理 (`ExecCommandSession`, `SpawnedPty`) |
| `codex_network_proxy` | 网络代理 (`NetworkProxy`) |
| `codex_protocol` | 协议类型 (`PermissionProfile`, `SandboxPolicy`) |
| `tokio` | 异步运行时 (sync, time, task) |
| `tokio_util` | `CancellationToken` |
| `rand` | 随机 process_id 生成 |

### 交互流程图

```
┌─────────────────────────────────────────────────────────────┐
│                    UnifiedExecProcessManager                 │
└──────────────┬────────────────────────────────┬─────────────┘
               │                                │
      ┌────────▼────────┐              ┌────────▼────────┐
      │  ToolOrchestrator │              │  ProcessStore   │
      │  (审批+沙箱)      │              │  (进程存储)      │
      └────────┬────────┘              └────────┬────────┘
               │                                │
      ┌────────▼────────┐              ┌────────▼────────┐
      │ UnifiedExecRuntime│            │ UnifiedExecProcess│
      │ (ToolRuntime impl)│            │ (PTY 包装)        │
      └────────┬────────┘              └────────┬────────┘
               │                                │
      ┌────────▼────────┐              ┌────────▼────────┐
      │   SandboxManager  │            │ ExecCommandSession│
      │   (沙箱转换)       │            │ (codex_utils_pty) │
      └─────────────────┘              └─────────────────┘
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 进程泄漏风险

**风险**：如果 `refresh_process_state` 未被调用，已退出进程可能一直驻留在 `ProcessStore` 中。

**缓解**：
- `spawn_exit_watcher` 后台任务会在进程退出时清理
- `prune_processes_if_needed` 在存储新进程时触发清理
- `terminate_all_processes` 在会话关闭时强制清理

**代码参考**：`process_manager.rs:527-538` (exit_watcher 启动)

#### 2. 内存溢出风险

**风险**：`HeadTailBuffer` 虽然限制了总大小，但 `output_buffer` 的 `Mutex` 可能在极端并发下堆积。

**缓解**：
- 缓冲区上限 1 MiB，64 个进程最多 64 MiB
- 使用 `tokio::sync::Mutex` 避免阻塞线程

#### 3. 僵尸进程风险

**风险**：PTY 子进程可能成为僵尸进程。

**缓解**：
- `UnifiedExecProcess::Drop` 自动调用 `terminate()`
- `ExecCommandSession` 负责底层进程回收

### 边界条件

| 边界 | 行为 |
|------|------|
| process_id 冲突 | 生产环境随机生成，冲突概率极低；测试环境顺序分配 |
| 超过最大进程数 (64) | LRU 清理，优先清理已退出进程，保护最近 8 个 |
| 空输入 write_stdin | 使用 `MIN_EMPTY_YIELD_TIME_MS` (5s) 作为等待时间 |
| TTY=false 时 write_stdin | 返回 `StdinClosed` 错误 |
| 沙箱拒绝 | 自动重试（如策略允许），无需重新提示用户 |
| 暂停状态 | `collect_output_until_deadline` 会延长截止时间 |

### 改进建议

#### 1. 进程 ID 生成策略优化

**现状**：生产环境使用 `rand::rng().random_range(1_000..100_000)`，范围较小。

**建议**：
- 扩大范围到 `1_000..1_000_000`
- 或考虑使用 UUID 子串

#### 2. 进程清理策略增强

**现状**：仅基于 LRU 和退出状态。

**建议**：
- 添加内存使用阈值触发清理
- 添加进程存活时间上限（TTL）

#### 3. 错误信息改进

**现状**：`UnknownProcessId` 仅包含 ID。

**建议**：
- 添加可能的进程状态（是否已退出、是否被清理）
- 建议用户操作（如重新创建进程）

#### 4. 测试覆盖增强

**现状**：部分测试被 `#[ignore]` 标记。

**建议**：
- 恢复 `requests_with_large_timeout_are_capped` 测试
- 恢复 `completed_commands_do_not_persist_sessions` 测试
- 添加沙箱拒绝重试的集成测试

#### 5. 监控和可观测性

**建议**：
- 添加进程创建/销毁的 metrics
- 记录进程存活时间分布
- 监控缓冲区截断频率

### 关键测试用例

| 测试文件 | 测试用例 | 验证点 |
|----------|----------|--------|
| `mod_tests.rs` | `unified_exec_persists_across_requests` | 进程状态持久化 |
| `mod_tests.rs` | `multi_unified_exec_sessions` | 多进程隔离 |
| `mod_tests.rs` | `unified_exec_timeouts` | 超时和后续轮询 |
| `mod_tests.rs` | `unified_exec_pause_blocks_yield_timeout` | 暂停机制 |
| `process_manager_tests.rs` | `pruning_prefers_exited_processes` | 清理策略 |
| `head_tail_buffer_tests.rs` | `keeps_prefix_and_suffix_when_over_budget` | 缓冲区行为 |

---

## 总结

`unified_exec` 是 Codex 核心的关键组件，提供了健壮的交互式进程执行能力。其设计亮点包括：

1. **分层架构**：清晰的职责分离（process → process_manager → handler）
2. **资源管理**：Head-Tail 缓冲区、进程数限制、LRU 清理
3. **沙箱集成**：与审批流程紧密结合，支持自动重试
4. **可测试性**：支持确定性 process_id 生成，便于测试

潜在的关注点包括进程生命周期管理的边界情况，以及在极端负载下的性能表现。
