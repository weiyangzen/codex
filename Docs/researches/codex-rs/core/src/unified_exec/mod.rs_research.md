# mod.rs 深度研究文档

## 场景与职责

`mod.rs` 是 Unified Exec 模块的根模块，定义了模块的公共接口、配置常量和核心数据结构。它作为协调层，将 `process.rs`、`process_manager.rs`、`async_watcher.rs` 等子模块整合为统一的交互式进程执行能力。

Unified Exec 的核心价值：
1. **会话持久化**：进程在多次 `exec_command` / `write_stdin` 调用间保持状态
2. **交互式支持**：TTY 模式支持 vim、less 等交互式程序
3. **统一策略**：复用现有的审批、沙箱、重试机制（通过 `ToolOrchestrator`）
4. **资源管控**：进程数上限、输出上限、超时控制

## 功能点目的

### 核心常量配置

| 常量 | 值 | 用途 |
|-----|-----|------|
| `MIN_YIELD_TIME_MS` | 250 | 最小等待时间，避免过频轮询 |
| `MIN_EMPTY_YIELD_TIME_MS` | 5,000 | 空输入时的最小等待（后台进程保活）|
| `MAX_YIELD_TIME_MS` | 30,000 | 最大等待时间上限 |
| `DEFAULT_MAX_BACKGROUND_TERMINAL_TIMEOUT_MS` | 300,000 | 默认后台进程超时（5分钟）|
| `DEFAULT_MAX_OUTPUT_TOKENS` | 10,000 | 默认输出 token 限制 |
| `UNIFIED_EXEC_OUTPUT_MAX_BYTES` | 1 MiB | 输出缓冲区硬上限 |
| `MAX_UNIFIED_EXEC_PROCESSES` | 64 | 最大并发进程数 |
| `WARNING_UNIFIED_EXEC_PROCESSES` | 60 | 进程数警告阈值 |

### 核心数据结构

```rust
/// 执行上下文，贯穿单次工具调用
pub(crate) struct UnifiedExecContext {
    pub session: Arc<Session>,
    pub turn: Arc<TurnContext>,
    pub call_id: String,
}

/// exec_command 工具调用请求
pub(crate) struct ExecCommandRequest {
    pub command: Vec<String>,      // 命令及参数
    pub process_id: i32,           // 分配的进程 ID
    pub yield_time_ms: u64,        // 等待输出的时间
    pub max_output_tokens: Option<usize>,
    pub workdir: Option<PathBuf>,
    pub network: Option<NetworkProxy>,
    pub tty: bool,                 // 是否分配 TTY
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
    pub additional_permissions_preapproved: bool,
    pub justification: Option<String>,
    pub prefix_rule: Option<Vec<String>>,
}

/// write_stdin 请求
pub(crate) struct WriteStdinRequest<'a> {
    pub process_id: i32,
    pub input: &'a str,
    pub yield_time_ms: u64,
    pub max_output_tokens: Option<usize>,
}

/// 进程存储管理
pub(crate) struct ProcessStore {
    processes: HashMap<i32, ProcessEntry>,
    reserved_process_ids: HashSet<i32>,  // 已分配但未存储的 ID
}

/// 进程管理器（主入口）
pub(crate) struct UnifiedExecProcessManager {
    process_store: Mutex<ProcessStore>,
    max_write_stdin_yield_time_ms: u64,
}
```

### 进程条目元数据

```rust
struct ProcessEntry {
    process: Arc<UnifiedExecProcess>,
    call_id: String,              // 创建时的调用 ID
    process_id: i32,
    command: Vec<String>,         // 启动命令
    tty: bool,
    network_approval_id: Option<String>,
    session: Weak<Session>,       // 弱引用避免循环
    last_used: Instant,           // 用于 LRU 清理
}
```

## 具体技术实现

### 模块结构

```
unified_exec/
├── mod.rs              # 本文件：公共接口和常量
├── mod_tests.rs        # 集成测试
├── errors.rs           # 错误类型
├── head_tail_buffer.rs # 输出缓冲
├── head_tail_buffer_tests.rs
├── process.rs          # PTY 进程生命周期
├── process_manager.rs  # 进程管理、审批、沙箱
├── process_manager_tests.rs
├── async_watcher.rs    # 异步输出监控
└── async_watcher_tests.rs
```

### 公共导出

```rust
pub(crate) use errors::UnifiedExecError;
pub(crate) use process::{
    NoopSpawnLifecycle, 
    SpawnLifecycle, 
    SpawnLifecycleHandle, 
    UnifiedExecProcess
};

// 测试辅助
pub(crate) fn set_deterministic_process_ids_for_tests(enabled: bool);
```

### 辅助函数

```rust
/// 限制 yield_time 在 [MIN, MAX] 范围内
pub(crate) fn clamp_yield_time(yield_time_ms: u64) -> u64;

/// 解析 max_tokens，None 时使用默认值
pub(crate) fn resolve_max_tokens(max_tokens: Option<usize>) -> usize;

/// 生成 6 位十六进制 chunk ID（用于输出分片）
pub(crate) fn generate_chunk_id() -> String;
```

## 依赖与外部交互

| 依赖模块 | 用途 |
|---------|------|
| `ToolOrchestrator` | 审批、沙箱选择、重试策略 |
| `SandboxManager` | 平台沙箱（Seatbelt/Seccomp）管理 |
| `NetworkProxy` | 网络代理配置 |
| `codex_utils_pty` | PTY 进程创建和管理 |
| `PermissionProfile` | 额外权限配置 |

### 调用关系

```
工具调用入口
├── exec_command()
│   └── process_manager::exec_command()
│       ├── open_session_with_sandbox()  # 审批+沙箱
│       ├── start_streaming_output()     # 流式输出
│       └── store_process()              # 持久化进程
└── write_stdin()
    └── process_manager::write_stdin()
        ├── prepare_process_handles()    # 获取进程句柄
        ├── send_input()                 # 写入 stdin
        └── collect_output_until_deadline()
```

## 风险、边界与改进建议

### 资源限制风险

| 限制 | 风险 | 缓解措施 |
|-----|------|---------|
| 64 进程上限 | 高频创建可能导致旧进程被清理 | LRU 清理策略，保留最近 8 个 |
| 1 MiB 输出上限 | 大输出被截断，可能丢失关键信息 | Head/Tail 保留策略 |
| 30s 最大等待 | 长时间运行命令被截断 | 支持多次 poll，后台进程保持运行 |

### 已知边界

1. **进程 ID 分配**：
   - 生产环境：随机 1000-100000
   - 测试环境：自增 1000+

2. **TTY 限制**：
   - 非 TTY 进程 stdin 一次性写入后关闭
   - 只有 TTY 进程支持 `write_stdin`

3. **会话隔离**：
   - 进程绑定到创建时的 Session
   - Session 结束时应清理关联进程

### 改进建议

1. **动态预算调整**：
   ```rust
   // 根据命令类型调整输出预算
   fn resolve_output_budget(command: &[String]) -> usize {
       match command[0].as_str() {
           "git" | "cargo" => 2 * UNIFIED_EXEC_OUTPUT_MAX_BYTES,
           _ => UNIFIED_EXEC_OUTPUT_MAX_BYTES,
       }
   }
   ```

2. **进程健康检查**：
   ```rust
   // 定期 ping 后台进程，自动清理僵尸进程
   async fn health_check(&self) {
       for (id, entry) in &store.processes {
           if entry.process.is_zombie() {
               self.release_process_id(id).await;
           }
       }
   }
   ```

3. **输出压缩**：
   - 对重复内容（如进度条）进行去重
   - 支持 gzip 压缩大输出

4. **可观测性增强**：
   - 添加进程生命周期 metrics
   - 输出缓冲区使用率监控
   - 沙箱拒绝率统计
