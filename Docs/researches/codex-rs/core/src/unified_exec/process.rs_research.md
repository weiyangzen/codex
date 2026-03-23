# process.rs 深度研究文档

## 场景与职责

`process.rs` 定义了 `UnifiedExecProcess` 结构体，封装单个 PTY 进程的生命周期管理。它是 Unified Exec 与底层 `codex_utils_pty` 库的桥梁，负责：
1. **进程创建**：从 `SpawnedPty` 构建管理对象
2. **输出收集**：后台任务持续读取 stdout/stderr
3. **状态查询**：提供进程退出状态、exit code 查询
4. **沙箱检测**：识别沙箱拒绝并生成相应错误
5. **资源清理**：Drop 时确保进程终止

## 功能点目的

### 核心能力

| 能力 | 实现 |
|-----|------|
| 输出广播 | `broadcast::Receiver<Vec<u8>>` 支持多订阅者 |
| 缓冲管理 | `Arc<Mutex<HeadTailBuffer>>` 线程安全共享 |
| 取消信号 | `CancellationToken` 协调退出 |
| 生命周期钩子 | `SpawnLifecycle` trait 支持文件描述符继承 |

### 沙箱检测

```rust
pub(super) async fn check_for_sandbox_denial(&self) -> Result<(), UnifiedExecError>
```
- 等待最多 20ms 收集初始输出
- 检查输出中是否包含沙箱拒绝关键词（如 "operation not permitted"）
- 使用 `is_likely_sandbox_denied` 启发式判断

## 具体技术实现

### 数据结构

```rust
pub(crate) struct UnifiedExecProcess {
    process_handle: ExecCommandSession,      // PTY 会话句柄
    output_rx: broadcast::Receiver<Vec<u8>>, // 输出订阅
    output_buffer: OutputBuffer,             // 共享缓冲
    output_notify: Arc<Notify>,              // 新输出通知
    output_closed: Arc<AtomicBool>,          // 输出结束标志
    output_closed_notify: Arc<Notify>,       // 输出关闭通知
    cancellation_token: CancellationToken,   // 取消信号
    output_drained: Arc<Notify>,             // 输出排空通知
    output_task: JoinHandle<()>,             // 后台收集任务
    sandbox_type: SandboxType,               // 沙箱类型
    _spawn_lifecycle: SpawnLifecycleHandle,  // 生命周期管理
}

pub(crate) struct OutputHandles {
    pub(crate) output_buffer: OutputBuffer,
    pub(crate) output_notify: Arc<Notify>,
    pub(crate) output_closed: Arc<AtomicBool>,
    pub(crate) output_closed_notify: Arc<Notify>,
    pub(crate) cancellation_token: CancellationToken,
}

pub(crate) type OutputBuffer = Arc<Mutex<HeadTailBuffer>>;
```

### 生命周期钩子 trait

```rust
pub(crate) trait SpawnLifecycle: std::fmt::Debug + Send + Sync {
    /// 返回需要在子进程 exec() 中保持打开的文件描述符
    fn inherited_fds(&self) -> Vec<i32> { Vec::new() }
    
    /// spawn 完成后调用，父进程可释放资源
    fn after_spawn(&mut self) {}
}

pub(crate) struct NoopSpawnLifecycle;
impl SpawnLifecycle for NoopSpawnLifecycle {}
```

### 构造流程

```
UnifiedExecProcess::new()
├── 创建输出缓冲和通知原语
├── resubscribe() 创建独立接收器
├── tokio::spawn 启动后台收集任务
│   └── loop:
│       ├── receiver.recv().await
│       ├── buffer.lock().await.push_chunk()
│       └── notify_clone.notify_waiters()
└── 返回管理对象

UnifiedExecProcess::from_spawned()
├── 合并 stdout/stderr 接收器
├── UnifiedExecProcess::new()
├── 检查进程是否已退出
│   ├── 已退出：signal_exit() + check_for_sandbox_denial()
│   └── 未退出：spawn 后台退出监控
└── 返回管理对象
```

### 后台输出收集任务

```rust
let output_task = tokio::spawn(async move {
    loop {
        match receiver.recv().await {
            Ok(chunk) => {
                let mut guard = buffer_clone.lock().await;
                guard.push_chunk(chunk);
                drop(guard);
                notify_clone.notify_waiters();
            }
            Err(RecvError::Lagged(_)) => continue,
            Err(RecvError::Closed) => {
                output_closed_clone.store(true, Ordering::Release);
                output_closed_notify_clone.notify_waiters();
                break;
            }
        }
    }
});
```

## 依赖与外部交互

| 依赖 | 用途 |
|-----|------|
| `codex_utils_pty::ExecCommandSession` | PTY 会话管理 |
| `codex_utils_pty::SpawnedPty` | spawn 结果封装 |
| `HeadTailBuffer` | 输出缓冲 |
| `is_likely_sandbox_denied` | 沙箱拒绝检测 |
| `CancellationToken` | 异步取消协调 |

### 调用关系

```
process_manager::open_session_with_exec_env()
├── codex_utils_pty::spawn_process_xxx()
│   └── SpawnedPty
└── UnifiedExecProcess::from_spawned()
    ├── combine_output_receivers()  # 合并 stdout/stderr
    ├── Self::new()                 # 创建管理对象
    └── 启动退出监控任务

async_watcher::start_streaming_output()
├── process.output_receiver()       # 订阅输出
└── 转发到 Session 事件
```

## 风险、边界与改进建议

### 并发安全

| 组件 | 同步机制 | 风险 |
|-----|---------|------|
| `output_buffer` | `Mutex` | 高频锁竞争可能影响性能 |
| `output_notify` | `Notify` | 可能丢失通知（需配合状态检查）|
| `output_closed` | `AtomicBool` + `Acquire/Release` | 正确内存序保证可见性 |

### 已知边界

1. **广播 lag**：`broadcast::channel` 有界，慢消费者可能 lag，当前策略是忽略 lag 继续接收
2. **快速退出**：进程在 150ms 内退出视为"快速退出"，立即进行沙箱检测
3. **Drop 清理**：Drop 时调用 `terminate()`，但无法保证子进程完全清理（孤儿进程风险）

### 改进建议

1. **无锁缓冲**：
   ```rust
   // 使用 crossbeam 无锁队列减少锁竞争
   use crossbeam::queue::SegQueue;
   ```

2. **背压机制**：
   ```rust
   // 当 buffer 超过阈值时，通知上游降速
   if buffer.retained_bytes() > HIGH_WATER_MARK {
       self.apply_backpressure().await;
   }
   ```

3. **进程组管理**：
   ```rust
   // 使用进程组确保子进程和孙子进程一起终止
   fn terminate(&self) {
       kill_process_group(self.pid);
   }
   ```

4. **沙箱检测优化**：
   ```rust
   // 添加更多检测模式
   const SANDBOX_PATTERNS: &[Regex] = &[
       regex!(r"(?i)operation not permitted"),
       regex!(r"(?i)permission denied"),
       regex!(r"(?i)seccomp.*violation"),
   ];
   ```
