# exec_tests.rs 研究文档

## 场景与职责

`exec_tests.rs` 是 `codex-core` crate 中命令执行模块的测试文件，位于 `codex-rs/core/src/` 目录下。该文件包含了对命令执行核心功能（`exec.rs`）的全面测试，主要关注：

- 沙箱拒绝检测（sandbox denial detection）
- 命令输出读取和截断（output capping）
- 输出聚合（stdout/stderr aggregation）
- Windows 受限令牌沙箱支持
- 进程组管理和超时处理
- 取消令牌支持

执行模块负责实际运行外部命令，管理进程生命周期，处理 I/O 流，并与沙箱系统协作确保安全性。

## 功能点目的

### 1. 沙箱拒绝检测测试 (`is_likely_sandbox_denied`)

检测命令执行是否因沙箱限制而失败：

- `sandbox_detection_requires_keywords`: 需要特定关键词才能触发检测
- `sandbox_detection_identifies_keyword_in_stderr`: 在 stderr 中识别沙箱拒绝关键词
- `sandbox_detection_respects_quick_reject_exit_codes`: 尊重快速拒绝退出码（2, 126, 127）
- `sandbox_detection_ignores_non_sandbox_mode`: 非沙箱模式下忽略检测
- `sandbox_detection_ignores_network_policy_text_in_non_sandbox_mode`: 非沙箱模式下忽略网络策略文本
- `sandbox_detection_uses_aggregated_output`: 使用聚合输出进行检测
- `sandbox_detection_ignores_network_policy_text_with_zero_exit_code`: 零退出码时忽略网络策略文本
- `sandbox_detection_flags_sigsys_exit_code` (Unix): 检测 SIGSYS 信号退出码

### 2. 输出读取和截断测试

- `read_capped_limits_retained_bytes`: 验证输出字节数上限（`EXEC_OUTPUT_MAX_BYTES`）

### 3. 输出聚合测试 (`aggregate_output`)

- `aggregate_output_prefers_stderr_on_contention`: 竞争时优先保留 stderr（2/3 容量）
- `aggregate_output_fills_remaining_capacity_with_stderr`: 用 stderr 填充剩余容量
- `aggregate_output_rebalances_when_stderr_is_small`: stderr 较小时重新平衡分配
- `aggregate_output_keeps_stdout_then_stderr_when_under_cap`: 未超限时保持 stdout + stderr 顺序

### 4. Windows 受限令牌沙箱支持测试

- `windows_restricted_token_skips_external_sandbox_policies`: 跳过外部沙箱策略
- `windows_restricted_token_runs_for_legacy_restricted_policies`: 支持传统受限策略
- `windows_restricted_token_rejects_network_only_restrictions`: 拒绝仅网络限制
- `windows_restricted_token_allows_legacy_restricted_policies`: 允许传统受限策略
- `windows_restricted_token_rejects_restricted_read_only_policies`: 拒绝受限只读策略
- `windows_restricted_token_allows_legacy_workspace_write_policies`: 允许传统工作区写入策略
- `windows_elevated_sandbox_allows_restricted_read_only_policies`: 提升沙箱允许受限只读策略

### 5. 沙箱类型选择测试

- `process_exec_tool_call_uses_platform_sandbox_for_network_only_restrictions`: 仅网络限制时使用平台沙箱

### 6. 进程管理和超时测试

- `kill_child_process_group_kills_grandchildren_on_timeout` (Unix): 超时杀死子进程组及其孙进程
- `process_exec_tool_call_respects_cancellation_token`: 尊重取消令牌

## 具体技术实现

### 关键数据结构

```rust
// 执行参数
pub struct ExecParams {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub expiration: ExecExpiration,  // 超时或取消
    pub env: HashMap<String, String>,
    pub network: Option<NetworkProxy>,
    pub sandbox_permissions: SandboxPermissions,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
    pub justification: Option<String>,
    pub arg0: Option<String>,
}

// 执行过期机制
pub enum ExecExpiration {
    Timeout(Duration),
    DefaultTimeout,  // 10 秒
    Cancellation(CancellationToken),
}

// 沙箱类型
pub enum SandboxType {
    None,
    MacosSeatbelt,          // macOS 专用
    LinuxSeccomp,           // Linux 专用
    WindowsRestrictedToken, // Windows 专用
}

// 执行工具调用输出
pub struct ExecToolCallOutput {
    pub exit_code: i32,
    pub stdout: StreamOutput<String>,
    pub stderr: StreamOutput<String>,
    pub aggregated_output: StreamOutput<String>,
    pub duration: Duration,
    pub timed_out: bool,
}

// 流输出（泛型）
pub struct StreamOutput<T: Clone> {
    pub text: T,
    pub truncated_after_lines: Option<u32>,
}
```

### 关键常量

```rust
pub const DEFAULT_EXEC_COMMAND_TIMEOUT_MS: u64 = 10_000;  // 默认超时 10 秒
const SIGKILL_CODE: i32 = 9;
const TIMEOUT_CODE: i32 = 64;
const EXIT_CODE_SIGNAL_BASE: i32 = 128;  // 128 + signal
const EXEC_TIMEOUT_EXIT_CODE: i32 = 124;  // 传统超时退出码
const READ_CHUNK_SIZE: usize = 8192;       // 每次读取 8KB
const AGGREGATE_BUFFER_INITIAL_CAPACITY: usize = 8 * 1024;  // 8 KiB
const EXEC_OUTPUT_MAX_BYTES: usize = DEFAULT_OUTPUT_BYTES_CAP;  // 输出上限
pub(crate) const MAX_EXEC_OUTPUT_DELTAS_PER_CALL: usize = 10_000;  // 事件上限
pub const IO_DRAIN_TIMEOUT_MS: u64 = 2_000;  // I/O 排空超时 2 秒
```

### 沙箱拒绝检测算法

```rust
pub(crate) fn is_likely_sandbox_denied(
    sandbox_type: SandboxType,
    exec_output: &ExecToolCallOutput,
) -> bool {
    // 快速排除
    if sandbox_type == SandboxType::None || exec_output.exit_code == 0 {
        return false;
    }
    
    // 快速拒绝退出码
    const QUICK_REJECT_EXIT_CODES: [i32; 3] = [2, 126, 127];
    
    // 沙箱拒绝关键词
    const SANDBOX_DENIED_KEYWORDS: [&str; 7] = [
        "operation not permitted",
        "permission denied",
        "read-only file system",
        "seccomp",
        "sandbox",
        "landlock",
        "failed to write file",
    ];
    
    // 检查输出中是否包含关键词
    // 检查 SIGSYS 信号（Linux seccomp）
}
```

### 输出聚合算法

```rust
fn aggregate_output(
    stdout: &StreamOutput<Vec<u8>>,
    stderr: &StreamOutput<Vec<u8>>,
) -> StreamOutput<Vec<u8>> {
    let total_len = stdout.text.len().saturating_add(stderr.text.len());
    let max_bytes = EXEC_OUTPUT_MAX_BYTES;
    
    if total_len <= max_bytes {
        // 未超限时直接合并
        aggregated.extend_from_slice(&stdout.text);
        aggregated.extend_from_slice(&stderr.text);
    } else {
        // 超限时：stdout 占 1/3，stderr 占 2/3
        let want_stdout = stdout.text.len().min(max_bytes / 3);
        let want_stderr = stderr.text.len();
        let stderr_take = want_stderr.min(max_bytes.saturating_sub(want_stdout));
        let remaining = max_bytes.saturating_sub(want_stdout + stderr_take);
        let stdout_take = want_stdout + remaining.min(stdout.text.len().saturating_sub(want_stdout));
        
        aggregated.extend_from_slice(&stdout.text[..stdout_take]);
        aggregated.extend_from_slice(&stderr.text[..stderr_take]);
    }
}
```

### Windows 受限令牌沙箱支持检查

```rust
fn windows_restricted_token_sandbox_support(
    sandbox: SandboxType,
    windows_sandbox_level: WindowsSandboxLevel,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
) -> WindowsRestrictedTokenSandboxSupport {
    // 检查文件系统策略类型
    // 检查沙箱策略类型（拒绝 DangerFullAccess 和 ExternalSandbox）
    // 检查 Windows 沙箱级别（Elevated 或传统策略）
    // 返回是否支持及不支持的原因
}
```

### 进程执行流程

```rust
async fn exec(
    params: ExecParams,
    sandbox: SandboxType,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    stdout_stream: Option<StdoutStream>,
    after_spawn: Option<Box<dyn FnOnce() + Send>>,
) -> Result<RawExecToolCallOutput> {
    // Windows 特殊处理
    // 解析命令
    // 生成子进程
    // 消费截断输出
}

async fn consume_truncated_output(
    child: Child,
    expiration: ExecExpiration,
    stdout_stream: Option<StdoutStream>,
) -> Result<RawExecToolCallOutput> {
    // 创建 stdout/stderr 读取任务
    // 等待进程结束或超时
    // 处理 Ctrl+C 信号
    // 超时后排空 I/O
}
```

## 关键代码路径与文件引用

### 被测试的主要源文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/exec.rs` | 命令执行核心实现 |
| `codex-rs/core/src/spawn.rs` | 子进程生成 |
| `codex-rs/core/src/sandboxing/mod.rs` | 沙箱管理 |

### 关键依赖

```rust
// 内部模块
use crate::error::CodexErr;
use crate::error::SandboxErr;
use crate::spawn::spawn_child_async;
use crate::sandboxing::SandboxManager;
use crate::sandboxing::CommandSpec;
use crate::sandboxing::ExecRequest;

// 外部 crate
use codex_network_proxy::NetworkProxy;
use codex_protocol::permissions::FileSystemSandboxPolicy;
use codex_protocol::permissions::NetworkSandboxPolicy;
use codex_utils_pty::DEFAULT_OUTPUT_BYTES_CAP;
use codex_utils_pty::process_group::kill_child_process_group;
use tokio_util::sync::CancellationToken;
```

### 平台特定代码

```rust
#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;

#[cfg(target_os = "windows")]
fn exec_windows_sandbox(...) -> Result<RawExecToolCallOutput>

#[cfg(unix)]
fn synthetic_exit_status(code: i32) -> ExitStatus

#[cfg(windows)]
fn synthetic_exit_status(code: i32) -> ExitStatus
```

## 依赖与外部交互

### 操作系统交互

1. **进程管理**: 使用 `tokio::process` 进行异步进程管理
2. **信号处理**: Unix 平台使用 `libc` 处理进程组和信号
3. **I/O 重定向**: 管道重定向 stdout/stderr

### 沙箱系统集成

```rust
// 沙箱管理器
SandboxManager::new().select_initial(
    file_system_sandbox_policy,
    network_sandbox_policy,
    SandboxablePreference::Auto,
    windows_sandbox_level,
    enforce_managed_network,
)

// 执行请求转换
SandboxManager::new().transform(SandboxTransformRequest { ... })
```

### 网络代理集成

```rust
if let Some(network) = network.as_ref() {
    network.apply_to_env(&mut env);
}
```

## 风险、边界与改进建议

### 已知风险

1. **I/O 排空超时**: 当子进程生成孙进程并继承 stdout/stderr 时，管道可能保持打开状态，导致 `IO_DRAIN_TIMEOUT_MS` 超时后强制中止读取任务，可能丢失部分输出

2. **沙箱检测误报**: `is_likely_sandbox_denied` 基于关键词匹配，可能产生误报（如用户程序输出恰好包含 "permission denied"）

3. **Windows 沙箱限制**: Windows 受限令牌沙箱对某些策略组合不支持，可能导致意外拒绝执行

4. **输出截断信息丢失**: 当输出超过 `EXEC_OUTPUT_MAX_BYTES` 时，截断后的信息可能不足以诊断问题

### 边界情况

1. **大输出处理**: 测试验证了 `EXEC_OUTPUT_MAX_BYTES` 上限，但未测试极端大输出（GB 级别）的内存行为

2. **多字节字符**: 输出处理使用字节级别截断，可能在多字节 UTF-8 字符边界处截断，导致乱码

3. **并发执行**: 测试主要关注单命令执行，未覆盖高并发场景下的资源竞争

4. **跨平台差异**: Windows 和 Unix 的信号处理、进程组管理存在显著差异

### 改进建议

1. **增强沙箱检测**:
   ```rust
   // 建议：增加更多上下文信息
   pub struct SandboxDenialInfo {
       pub detected_keyword: String,
       pub exit_code: i32,
       pub confidence: f32,  // 置信度评分
   }
   ```

2. **改进输出处理**:
   - 使用字符级别而非字节级别的截断
   - 添加截断指示器，明确告知用户输出被截断
   - 考虑流式输出，避免内存中保留完整输出

3. **增强测试覆盖**:
   - 添加大文件输出测试（> 100MB）
   - 添加多字节字符截断测试
   - 添加高并发执行测试
   - 添加网络代理故障恢复测试

4. **性能优化**:
   - 考虑使用 `tokio::io::copy` 的零拷贝优化
   - 评估 `BufReader` 的缓冲区大小（当前 8KB）
   - 考虑使用内存池减少分配

5. **可观测性**:
   - 增加详细的执行指标（启动时间、I/O 等待时间）
   - 添加结构化日志，便于调试沙箱问题
   - 提供执行追踪功能

6. **安全加固**:
   - 考虑使用 `prctl(PR_SET_PDEATHSIG)` 确保子进程在父进程退出时终止
   - 添加命令执行审计日志
   - 实现更严格的资源限制（CPU、内存）

### 相关测试文件

- `codex-rs/core/src/exec_policy_tests.rs`: 执行策略测试
- `codex-rs/core/src/sandboxing/tests.rs`: 沙箱模块测试
- `codex-rs/core/src/spawn_tests.rs`: 进程生成测试
- `codex-rs/core/src/seatbelt_tests.rs`: macOS Seatbelt 测试
- `codex-rs/core/src/landlock_tests.rs`: Linux Landlock 测试
