# process_manager.rs 深度研究文档

## 场景与职责

`process_manager.rs` 是 Unified Exec 的核心 orchestration 层，负责：
1. **进程生命周期管理**：创建、复用、清理交互式进程
2. **审批与沙箱集成**：通过 `ToolOrchestrator` 统一处理审批和沙箱策略
3. **输出收集**：超时控制、暂停机制、流式收集
4. **资源管控**：进程数限制、LRU 清理、网络审批管理

这是 Unified Exec 最复杂的模块，协调了 10+ 个依赖模块。

## 功能点目的

### 核心流程

```
exec_command(request, context)
├── allocate_process_id()              # 分配唯一 ID
├── open_session_with_sandbox()        # 审批+沙箱+创建
│   ├── ToolOrchestrator::run()        # 统一审批流程
│   └── open_session_with_exec_env()   # PTY 创建
├── start_streaming_output()           # 启动流式输出
├── store_process()                    # 持久化进程（如存活）
├── collect_output_until_deadline()    # 收集输出
└── 构建 ExecCommandToolOutput 响应

write_stdin(request)
├── prepare_process_handles()          # 获取进程句柄
├── send_input()                       # 写入 stdin
├── collect_output_until_deadline()    # 收集输出
└── refresh_process_state()            # 刷新进程状态
```

### 环境变量注入

```rust
const UNIFIED_EXEC_ENV: [(&str, &str); 10] = [
    ("NO_COLOR", "1"),           // 禁用颜色输出
    ("TERM", "dumb"),            // 简单终端类型
    ("LANG", "C.UTF-8"),         // UTF-8 编码
    ("LC_CTYPE", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8"),
    ("COLORTERM", ""),           // 禁用颜色终端
    ("PAGER", "cat"),            // 禁用分页器
    ("GIT_PAGER", "cat"),
    ("GH_PAGER", "cat"),
    ("CODEX_CI", "1"),           // CI 模式标识
];
```

### 进程 ID 分配策略

```rust
fn allocate_process_id(&self) -> i32 {
    if should_use_deterministic_process_ids() {
        // 测试模式：自增，从 1000 开始
        max(reserved_ids) + 1
    } else {
        // 生产模式：随机 1000-100000
        rand::random_range(1_000..100_000)
    }
}
```

### 进程清理策略

```rust
fn process_id_to_prune_from_meta(meta: &[(i32, Instant, bool)]) -> Option<i32> {
    // 1. 按使用时间排序，保护最近 8 个
    // 2. 优先清理已退出的进程
    // 3. 其次按 LRU 清理
}
```

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct UnifiedExecProcessManager {
    process_store: Mutex<ProcessStore>,
    max_write_stdin_yield_time_ms: u64,  // 后台进程最大等待时间
}

struct ProcessStore {
    processes: HashMap<i32, ProcessEntry>,
    reserved_process_ids: HashSet<i32>,  // 已分配但未存储
}

struct ProcessEntry {
    process: Arc<UnifiedExecProcess>,
    call_id: String,
    process_id: i32,
    command: Vec<String>,
    tty: bool,
    network_approval_id: Option<String>,
    session: Weak<Session>,
    last_used: Instant,
}

struct PreparedProcessHandles {
    writer_tx: mpsc::Sender<Vec<u8>>,
    output_buffer: OutputBuffer,
    output_notify: Arc<Notify>,
    output_closed: Arc<AtomicBool>,
    output_closed_notify: Arc<Notify>,
    cancellation_token: CancellationToken,
    pause_state: Option<watch::Receiver<bool>>,
    command: Vec<String>,
    process_id: i32,
    tty: bool,
}

enum ProcessStatus {
    Alive { exit_code: Option<i32>, call_id: String, process_id: i32 },
    Exited { exit_code: Option<i32>, entry: Box<ProcessEntry> },
    Unknown,
}
```

### 输出收集算法

```rust
async fn collect_output_until_deadline(
    output_buffer: &OutputBuffer,
    output_notify: &Arc<Notify>,
    output_closed: &Arc<AtomicBool>,
    output_closed_notify: &Arc<Notify>,
    cancellation_token: &CancellationToken,
    pause_state: Option<watch::Receiver<bool>>,
    deadline: Instant,
) -> Vec<u8> {
    const POST_EXIT_CLOSE_WAIT_CAP: Duration = Duration::from_millis(50);
    
    loop {
        // 1. 处理暂停：延长 deadline
        extend_deadlines_while_paused(&mut pause_state, &mut deadline, &mut post_exit_deadline).await;
        
        // 2. 尝试 drain buffer
        let chunks = output_buffer.lock().await.drain_chunks();
        
        if chunks.is_empty() {
            // 3. 无输出时等待通知或超时
            select! {
                _ = output_notify.notified() => continue,
                _ = cancellation_token.cancelled() => exit_signal_received = true,
                _ = sleep(remaining) => break,
                _ = pause_state.changed() => continue,
            }
        } else {
            // 4. 有输出时追加到 collected
            for chunk in chunks { collected.extend_from_slice(&chunk); }
            if now >= deadline { break; }
        }
        
        // 5. 进程退出后额外等待输出关闭（最多 50ms）
        if exit_signal_received && output_closed.load(Acquire) { break; }
    }
    
    collected
}
```

### 沙箱集成流程

```rust
async fn open_session_with_sandbox(
    &self,
    request: &ExecCommandRequest,
    cwd: PathBuf,
    context: &UnifiedExecContext,
) -> Result<(UnifiedExecProcess, Option<DeferredNetworkApproval>), UnifiedExecError> {
    // 1. 准备环境变量
    let env = apply_unified_exec_env(create_env(...));
    
    // 2. 创建 ToolOrchestrator
    let mut orchestrator = ToolOrchestrator::new();
    let mut runtime = UnifiedExecRuntime::new(self, shell_mode);
    
    // 3. 创建审批需求
    let exec_approval_requirement = session.services.exec_policy
        .create_exec_approval_requirement_for_command(...).await;
    
    // 4. 构建 UnifiedExecRequest
    let req = UnifiedExecToolRequest { ... };
    
    // 5. 运行审批+沙箱流程
    orchestrator.run(&mut runtime, &req, &tool_ctx, &turn, approval_policy).await
}
```

### 进程存储与清理

```rust
async fn store_process(
    &self,
    process: Arc<UnifiedExecProcess>,
    context: &UnifiedExecContext,
    command: &[String],
    cwd: PathBuf,
    started_at: Instant,
    process_id: i32,
    tty: bool,
    network_approval_id: Option<String>,
    transcript: Arc<tokio::sync::Mutex<HeadTailBuffer>>,
) {
    // 1. 创建 ProcessEntry
    let entry = ProcessEntry { ... };
    
    // 2. 检查并执行 LRU 清理
    let (number_processes, pruned_entry) = {
        let mut store = self.process_store.lock().await;
        let pruned = Self::prune_processes_if_needed(&mut store);
        store.processes.insert(process_id, entry);
        (store.processes.len(), pruned)
    };
    
    // 3. 清理被驱逐的进程
    if let Some(pruned) = pruned_entry {
        Self::unregister_network_approval_for_entry(&pruned).await;
        pruned.process.terminate();
    }
    
    // 4. 进程数警告
    if number_processes >= WARNING_UNIFIED_EXEC_PROCESSES {
        session.record_model_warning(...).await;
    }
    
    // 5. 启动退出监控
    spawn_exit_watcher(...);
}
```

## 依赖与外部交互

| 依赖模块 | 用途 |
|---------|------|
| `ToolOrchestrator` | 统一审批、沙箱选择、重试 |
| `UnifiedExecRuntime` | ToolRuntime 实现，实际 spawn 进程 |
| `ExecPolicyManager` | 创建审批需求 |
| `NetworkApproval` | 网络代理审批管理 |
| `codex_utils_pty` | PTY 进程创建 |
| `HeadTailBuffer` | 输出缓冲 |
| `approx_token_count` | Token 计数 |

### 调用关系图

```
Session::exec_command()
└── UnifiedExecProcessManager::exec_command()
    ├── allocate_process_id()
    ├── open_session_with_sandbox()
    │   ├── ToolOrchestrator::run()
    │   │   └── UnifiedExecRuntime::run()
    │   │       └── open_session_with_exec_env()
    │   │           └── codex_utils_pty::spawn_process_xxx()
    │   └── 沙箱拒绝时重试
    ├── start_streaming_output()
    ├── store_process()
    │   └── prune_processes_if_needed()
    └── collect_output_until_deadline()

Session::write_stdin()
└── UnifiedExecProcessManager::write_stdin()
    ├── prepare_process_handles()
    ├── send_input()
    └── collect_output_until_deadline()
```

## 风险、边界与改进建议

### 复杂性与风险点

| 风险 | 描述 | 缓解 |
|-----|------|------|
| 锁粒度 | process_store Mutex 保护大范围操作 | 尽快释放锁，异步操作移到锁外 |
| 竞态条件 | 进程退出与 write_stdin 并发 | ProcessStatus 状态机检查 |
| 资源泄漏 | 网络审批未注销 | Drop 时自动清理，但依赖显式调用 |
| 死锁风险 | 锁内调用 async 可能阻塞 | 使用 `Mutex<ProcessStore>` 而非 `tokio::sync::Mutex` 的嵌套 |

### 关键边界

1. **进程数上限**：64 个，超出时 LRU 清理
2. **保护窗口**：最近 8 个进程受保护不被清理
3. **超时范围**：
   - exec_command: 250ms - 30s
   - write_stdin 空输入: 5s - 配置值（默认 5min）
4. **暂停机制**：通过 `watch::Receiver<bool>` 实现，暂停期间不计入超时

### 改进建议

1. **分层锁结构**：
   ```rust
   // 将 metadata 和 process 分离，减少锁竞争
   struct ProcessMetadata { last_used, call_id, ... }
   struct ProcessStore {
       metadata: RwLock<HashMap<i32, ProcessMetadata>>,
       processes: DashMap<i32, Arc<UnifiedExecProcess>>, // 无锁
   }
   ```

2. **状态机明确化**：
   ```rust
   enum ProcessState {
       Starting,
       Running,
       Exiting { exit_code: Option<i32> },
       Exited,
       CleanedUp,
   }
   ```

3. **批处理优化**：
   ```rust
   // 批量 drain 输出，减少锁获取次数
   const BATCH_SIZE: usize = 10;
   async fn collect_output_batched(...) -> Vec<Vec<u8>>
   ```

4. **可观测性**：
   ```rust
   // 添加结构化日志和 metrics
   metrics::histogram!("unified_exec.collect_duration", duration.as_millis() as f64);
   metrics::gauge!("unified_exec.active_processes", store.processes.len() as f64);
   ```

5. **测试覆盖**：
   - 当前 `process_manager_tests.rs` 仅测试环境变量和清理策略
   - 需要添加：并发 write_stdin、进程竞争、沙箱重试、网络审批流程
