# thread_manager.rs 研究文档

## 场景与职责

`thread_manager.rs` 是 Codex 核心 crate 中负责**线程生命周期管理**的中心化模块。它作为线程（Thread）的工厂和管理器，承担着以下核心职责：

1. **线程创建与初始化**：创建新的 Codex 会话线程，配置必要的依赖（认证、模型管理器、技能管理等）
2. **线程追踪与索引**：维护活跃的线程映射表，支持按 ID 查询和列举
3. **线程恢复与分叉**：支持从 rollout 历史记录恢复线程，以及基于历史创建分支（fork）
4. **线程关闭与清理**：提供有界关闭机制，确保所有线程在超时前优雅终止
5. **多代理协调**：通过 `AgentControl` 支持子代理（sub-agent）的创建和管理

该模块是连接上层应用（TUI/App Server）与底层 Codex 执行引擎的关键桥梁。

## 功能点目的

### 1. ThreadManager 结构体

```rust
pub struct ThreadManager {
    state: Arc<ThreadManagerState>,
    _test_codex_home_guard: Option<TempCodexHomeGuard>,
}
```

- **生产环境**：通过 `ThreadManager::new()` 创建，使用真实配置和持久化存储
- **测试环境**：通过 `with_models_provider_for_tests()` 创建，使用临时目录隔离

### 2. ThreadManagerState 共享状态

```rust
pub(crate) struct ThreadManagerState {
    threads: Arc<RwLock<HashMap<ThreadId, Arc<CodexThread>>>>,
    thread_created_tx: broadcast::Sender<ThreadId>,
    auth_manager: Arc<AuthManager>,
    models_manager: Arc<ModelsManager>,
    skills_manager: Arc<SkillsManager>,
    plugins_manager: Arc<PluginsManager>,
    mcp_manager: Arc<McpManager>,
    file_watcher: Arc<FileWatcher>,
    session_source: SessionSource,
    ops_log: Option<SharedCapturedOps>,  // 测试模式专用
}
```

所有子管理器通过 `Arc` 共享，确保多线程安全。

### 3. 线程创建变体

| 方法 | 用途 |
|------|------|
| `start_thread()` | 基础线程创建 |
| `start_thread_with_tools()` | 带动态工具的线程 |
| `start_thread_with_tools_and_service_name()` | 附加指标服务名和追踪上下文 |
| `resume_thread_from_rollout()` | 从 rollout 文件恢复 |
| `resume_thread_with_history()` | 从 InitialHistory 恢复 |
| `fork_thread()` | 基于历史创建分支 |

### 4. 有界关闭机制

```rust
pub async fn shutdown_all_threads_bounded(&self, timeout: Duration) -> ThreadShutdownReport
```

返回三种结果分类：
- `completed`：成功关闭的线程
- `submit_failed`：提交关闭操作失败的线程
- `timed_out`：超时未完成的线程

## 具体技术实现

### 核心流程：线程创建

```rust
// 1. 注册文件 watcher
let watch_registration = self.file_watcher.register_config(&config, self.skills_manager.as_ref());

// 2. 调用 Codex::spawn 创建底层会话
let CodexSpawnOk { codex, thread_id, .. } = Codex::spawn(CodexSpawnArgs { ... }).await?;

// 3. 等待首个 SessionConfigured 事件
let event = codex.next_event().await?;
let session_configured = match event { ... };

// 4. 包装为 CodexThread 并注册
let thread = Arc::new(CodexThread::new(codex, session_configured.rollout_path.clone(), watch_registration));
threads.insert(thread_id, thread.clone());
```

### 核心流程：Fork 线程

```rust
pub async fn fork_thread(&self, nth_user_message: usize, ...) -> CodexResult<NewThread> {
    let history = RolloutRecorder::get_rollout_history(&path).await?;
    let history = truncate_before_nth_user_message(history, nth_user_message);
    // 使用截断后的历史创建新线程
}
```

Fork 逻辑通过 `truncate_before_nth_user_message` 实现，保留前 N 个用户消息之前的所有内容。

### 测试模式行为

通过原子变量 `FORCE_TEST_THREAD_MANAGER_BEHAVIOR` 控制：
- 启用 Noop 文件 watcher（避免当前线程运行时饿死）
- 启用操作日志捕获（用于测试断言）

```rust
fn should_use_test_thread_manager_behavior() -> bool {
    FORCE_TEST_THREAD_MANAGER_BEHAVIOR.load(Ordering::Relaxed)
}
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| Codex | `codex.rs` | 底层会话执行引擎 |
| CodexThread | `codex_thread.rs` | 线程包装器，提供高层 API |
| AgentControl | `agent/control.rs` | 多代理控制句柄 |
| RolloutRecorder | `rollout/recorder.rs` | 历史记录读写 |
| truncation | `rollout/truncation.rs` | 历史截断逻辑 |

### 协议依赖

| 类型 | 路径 | 用途 |
|------|------|------|
| ThreadId | `codex_protocol::ThreadId` | 线程唯一标识 |
| InitialHistory | `protocol::InitialHistory` | 初始历史状态 |
| Op | `protocol::Op` | 操作指令枚举 |
| SessionSource | `protocol::SessionSource` | 会话来源标记 |

### 配置依赖

```rust
// 来自 config 模块
Config, AuthManager, ModelsManager, SkillsManager, PluginsManager, McpManager
```

## 依赖与外部交互

### 文件系统交互

- **codex_home**：用户配置和数据根目录
- **rollout 文件**：会话历史持久化（通过 `RolloutRecorder`）
- **临时目录**：测试模式下自动创建和清理

### 进程间通信

- **broadcast channel**：`thread_created_tx` 通知新线程创建事件
- **RwLock**：线程映射表的并发访问控制

### 异步运行时

- 依赖 Tokio 运行时
- 使用 `FuturesUnordered` 实现并发关闭

## 风险、边界与改进建议

### 已知风险

1. **内存泄漏风险**：`ThreadManagerState` 持有所有线程的 `Arc`，如果线程未正确关闭，内存无法释放
2. **死锁风险**：`RwLock` 在 `send_op` 和 `get_thread` 组合调用时可能产生嵌套锁
3. **测试污染**：全局原子变量 `FORCE_TEST_THREAD_MANAGER_BEHAVIOR` 可能影响并行测试

### 边界情况

1. **线程 ID 冲突**：UUID 生成理论上不会冲突，但需确保 `ThreadId` 全局唯一
2. **文件 watcher 失败**：降级为 Noop watcher，不影响核心功能
3. **历史截断越界**：`nth_user_message` 超过实际数量时返回空历史

### 改进建议

1. **线程数限制**：当前无硬限制，建议添加 `max_threads` 配置
2. **优雅关闭**：`shutdown_all_threads_bounded` 可考虑添加渐进式超时
3. **指标监控**：建议添加线程生命周期指标（创建/销毁计数、存活时间）
4. **测试隔离**：考虑使用线程局部存储替代全局原子变量

### 代码质量

- 模块行数：833 行（适中）
- 测试覆盖：包含单元测试和集成测试（`thread_manager_tests.rs`）
- 文档：关键公共方法有文档注释
