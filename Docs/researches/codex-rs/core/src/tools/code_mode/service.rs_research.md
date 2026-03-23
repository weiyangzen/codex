# service.rs 研究文档

## 场景与职责

`service.rs` 是 Code Mode 的**服务管理层**，负责 `CodeModeService` 的生命周期管理。它是 Code Mode 功能在应用层的入口，协调进程管理、存储管理和 Worker 创建。

**核心定位**：
- 单例服务：每个 Session 拥有一个 `CodeModeService` 实例
- 进程管理：按需启动和维护 Node.js 进程
- 存储管理：管理跨调用的键值存储
- Worker 工厂：为每个 Turn 创建后台 Worker

## 功能点目的

### 1. 服务结构（CodeModeService）
```rust
pub(crate) struct CodeModeService {
    js_repl_node_path: Option<PathBuf>,  // Node.js 路径配置
    stored_values: Mutex<HashMap<String, JsonValue>>,  // 键值存储
    process: Arc<Mutex<Option<CodeModeProcess>>>,  // 进程句柄
    next_cell_id: Mutex<u64>,  // cell ID 计数器
}
```

### 2. 存储值管理
```rust
pub(crate) async fn stored_values(&self) -> HashMap<String, JsonValue>
pub(crate) async fn replace_stored_values(&self, values: HashMap<String, JsonValue>)
```
- `stored_values()`：获取当前存储值的副本
- `replace_stored_values()`：完全替换存储值
- 用于在 `exec` 调用之间持久化数据

### 3. 进程生命周期管理（ensure_started）
```rust
pub(super) async fn ensure_started(
    &self,
) -> Result<tokio::sync::OwnedMutexGuard<Option<CodeModeProcess>>, std::io::Error>
```
流程：
1. 获取进程锁
2. 检查进程是否存在且存活
3. 如果需要，解析 Node.js 路径
4. 启动新进程
5. 返回进程锁的 OwnedGuard

### 4. Turn Worker 创建（start_turn_worker）
```rust
pub(crate) async fn start_turn_worker(
    &self,
    session: &Arc<Session>,
    turn: &Arc<TurnContext>,
    router: Arc<ToolRouter>,
    tracker: SharedTurnDiffTracker,
) -> Option<CodeModeWorker>
```
流程：
1. 检查 `Feature::CodeMode` 是否启用
2. 构建 `ExecContext`
3. 创建 `ToolCallRuntime`
4. 确保进程已启动
5. 创建并返回 `CodeModeWorker`

### 5. ID 分配
```rust
pub(crate) async fn allocate_cell_id(&self) -> String
pub(crate) async fn allocate_request_id(&self) -> String
```
- `allocate_cell_id()`：递增计数器，返回数字字符串
- `allocate_request_id()`：生成 UUID v4

## 具体技术实现

### 数据结构

**CodeModeService**：
```rust
pub(crate) struct CodeModeService {
    js_repl_node_path: Option<PathBuf>,
    stored_values: Mutex<HashMap<String, JsonValue>>,
    process: Arc<Mutex<Option<CodeModeProcess>>>,
    next_cell_id: Mutex<u64>,
}
```

**构造**：
```rust
impl CodeModeService {
    pub(crate) fn new(js_repl_node_path: Option<PathBuf>) -> Self {
        Self {
            js_repl_node_path,
            stored_values: Mutex::new(HashMap::new()),
            process: Arc::new(Mutex::new(None)),
            next_cell_id: Mutex::new(1),
        }
    }
}
```

### 关键流程详解

#### 进程启动流程
```
ensure_started()
    │
    ├──> 获取 process_slot = self.process.lock().await
    │
    ├──> 检查是否需要启动
    │       ├──> process_slot 为 None → 需要启动
    │       └──> process.has_exited()? → 需要启动
    │
    ├──> 如果需要启动
    │       │
    │       ├──> resolve_compatible_node(self.js_repl_node_path.as_deref())
    │       │       → Result<PathBuf, String>
    │       │
    │       └──> spawn_code_mode_process(&node_path).await
    │               → Result<CodeModeProcess, std::io::Error>
    │
    ├──> drop(process_slot)  // 释放锁
    │
    └──> 返回 self.process.clone().lock_owned().await
```

#### Worker 创建流程
```
start_turn_worker(session, turn, router, tracker)
    │
    ├──> 检查 turn.features.enabled(Feature::CodeMode)
    │       └──> false → 返回 None
    │
    ├──> 构建 ExecContext { session, turn }
    │
    ├──> 创建 ToolCallRuntime::new(router, session, turn, tracker)
    │
    ├──> self.ensure_started().await
    │       └──> Err(err) → 记录警告，返回 None
    │
    ├──> 获取 process_slot
    │
    ├──> 检查 process 是否存在且存活
    │       └──> 失败 → 记录警告，返回 None
    │
    └──> 返回 Some(process.worker(exec, tool_runtime))
```

### 进程存活检查
```rust
let needs_spawn = match process_slot.as_mut() {
    Some(process) => !matches!(process.has_exited(), Ok(false)),
    None => true,
};
```
- `has_exited()` 返回 `Ok(false)` 表示进程仍在运行
- 其他情况（`Ok(true)` 或 `Err`）都需要重新启动

### Node.js 路径解析
```rust
let node_path = resolve_compatible_node(self.js_repl_node_path.as_deref())
    .await
    .map_err(std::io::Error::other)?;
```
- 优先使用配置的 `js_repl_node_path`
- 如果未配置，自动在 PATH 中查找
- 验证 Node.js 版本兼容性

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/service.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/state/service.rs`
  - 创建 `CodeModeService` 实例
- `/home/sansha/Github/codex/codex-rs/core/src/codex.rs`
  - 配置验证时检查 Node.js 可用性
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`
  - `stored_values()`, `allocate_cell_id()`, `allocate_request_id()`, `ensure_started()`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs`
  - `allocate_request_id()`, `ensure_started()`
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `replace_stored_values()`（在 `handle_node_message` 中）
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/worker.rs`
  - `start_turn_worker()`（通过 `process.worker()`）

### 依赖项
| 文件 | 用途 |
|------|------|
| `process.rs` | `CodeModeProcess`, `spawn_code_mode_process` |
| `mod.rs` | `ExecContext`, `PUBLIC_TOOL_NAME` |
| `worker.rs` | `CodeModeWorker` |
| `js_repl/mod.rs` | `resolve_compatible_node` |

### 外部依赖
| crate | 用途 |
|-------|------|
| `tokio::sync::Mutex` | 异步互斥锁 |
| `tracing::warn` | 日志记录 |
| `serde_json::Value` | JSON 值类型 |

## 依赖与外部交互

### 与 Session 的交互
```rust
// 在 start_turn_worker 中
let exec = ExecContext {
    session: Arc::clone(session),
    turn: Arc::clone(turn),
};
let tool_runtime = ToolCallRuntime::new(router, Arc::clone(session), Arc::clone(turn), tracker);
```

### 与 Features 的交互
```rust
use crate::features::Feature;

if !turn.features.enabled(Feature::CodeMode) {
    return None;
}
```

### 存储值的数据流
```
JavaScript (runner.cjs)
    │
    ├──> store(key, value) → state.storedValues[key] = value
    │
    └──> 执行完成 → result.stored_values
            │
            └──> Rust (mod.rs:handle_node_message)
                    │
                    └──> service.replace_stored_values(stored_values).await
                            │
                            └──> 下次执行时通过 stored_values() 获取
```

## 风险、边界与改进建议

### 风险点

1. **进程单点故障**
   - 所有 cell 共享同一个 Node.js 进程
   - 进程崩溃会导致所有正在执行的 cell 失败

2. **存储值竞争**
   ```rust
   pub(crate) async fn replace_stored_values(&self, values: HashMap<String, JsonValue>) {
       *self.stored_values.lock().await = values;
   }
   ```
   多个并发执行可能互相覆盖存储值

3. **ID 溢出**
   ```rust
   *next_cell_id = next_cell_id.saturating_add(1);
   ```
   使用 `saturating_add` 防止溢出，但达到 `u64::MAX` 后会一直返回 `u64::MAX`

4. **进程泄漏**
   - 如果 `ensure_started` 后没有正确使用进程，可能导致资源浪费
   - `OwnedMutexGuard` 确保排他访问，但需要及时释放

### 边界情况

1. **Node.js 不可用**
   ```rust
   let node_path = resolve_compatible_node(self.js_repl_node_path.as_deref())
       .await
       .map_err(std::io::Error::other)?;
   ```
   返回错误，上层记录警告并返回 None

2. **进程启动失败**
   ```rust
   *process_slot = Some(spawn_code_mode_process(&node_path).await?);
   ```
   IO 错误会传播给调用者

3. **Feature 禁用**
   - `start_turn_worker` 在 `CodeMode` 功能禁用时返回 None
   - 这是正常行为，不是错误

4. **并发启动**
   - `ensure_started` 使用 `Mutex` 确保只有一个任务能启动进程
   - 其他任务会等待锁释放后获取已启动的进程

### 改进建议

1. **进程池化**
   - 维护多个 Node.js 进程，分散负载
   - 提高容错性（一个进程崩溃不影响其他）

2. **存储值命名空间**
   ```rust
   pub(crate) async fn stored_values_for_cell(&self, cell_id: &str) -> HashMap<String, JsonValue> {
       // 为每个 cell 提供独立的存储命名空间
   }
   ```

3. **健康检查**
   ```rust
   pub(crate) async fn health_check(&self) -> Result<(), CodeModeHealthError> {
       // 定期检查进程健康
       // 自动重启不健康的进程
   }
   ```

4. **指标收集**
   ```rust
   pub(crate) async fn stats(&self) -> CodeModeStats {
       CodeModeStats {
           process_restart_count: self.process_restart_count.load(Ordering::Relaxed),
           total_cells_executed: self.total_cells_executed.load(Ordering::Relaxed),
           stored_values_count: self.stored_values.lock().await.len(),
       }
   }
   ```

5. **优雅关闭**
   ```rust
   impl Drop for CodeModeService {
       fn drop(&mut self) {
           // 等待所有 cell 完成或超时
           // 终止 Node.js 进程
       }
   }
   ```

6. **配置热更新**
   ```rust
   pub(crate) async fn update_node_path(&self, path: Option<PathBuf>) {
       // 允许运行时更新 Node.js 路径
       // 下次 ensure_started 时使用新路径
   }
   ```

7. **测试覆盖**
   - 当前无直接测试
   - 建议添加：
     - 进程启动/重启测试
     - 存储值读写测试
     - ID 分配测试
     - Worker 创建测试
