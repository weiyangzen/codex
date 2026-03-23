# test_sync.rs 研究文档

## 场景与职责

`test_sync.rs` 实现了 `test_sync_tool`，这是一个专门用于测试框架内部的同步原语工具。该工具提供测试场景下的并发协调能力，支持测试用例之间的同步点（barrier）和延时控制，主要用于 Codex 内部的多线程/多任务测试场景。

## 功能点目的

### 1. 测试同步协调
提供基于屏障（Barrier）的同步机制，允许多个并发测试任务在特定点等待彼此，确保测试执行顺序的可预测性。

### 2. 延时控制
支持在同步点前后添加延时，模拟真实场景中的异步延迟，测试超时和重试逻辑。

### 3. 并发参与者管理
管理多个并发参与者的注册和协调，确保所有参与者到达屏障后才能继续执行。

## 具体技术实现

### 核心数据结构

```rust
// 全局屏障状态存储
static BARRIERS: OnceLock<tokio::sync::Mutex<HashMap<String, BarrierState>>> = OnceLock::new();

struct BarrierState {
    barrier: Arc<Barrier>,      // Tokio 屏障原语
    participants: usize,        // 参与者数量
}

#[derive(Debug, Deserialize)]
struct BarrierArgs {
    id: String,                 // 屏障唯一标识
    participants: usize,        // 预期参与者数量
    #[serde(default = "default_timeout_ms")]
    timeout_ms: u64,            // 等待超时
}

#[derive(Debug, Deserialize)]
struct TestSyncArgs {
    #[serde(default)]
    sleep_before_ms: Option<u64>,  // 屏障前延时
    #[serde(default)]
    sleep_after_ms: Option<u64>,   // 屏障后延时
    #[serde(default)]
    barrier: Option<BarrierArgs>,  // 屏障配置
}
```

### 关键流程

#### 工具处理器实现
```rust
#[async_trait]
impl ToolHandler for TestSyncHandler {
    type Output = FunctionToolOutput;

    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 解析参数
        let args: TestSyncArgs = parse_arguments(&arguments)?;

        // 2. 执行前置延时
        if let Some(delay) = args.sleep_before_ms && delay > 0 {
            sleep(Duration::from_millis(delay)).await;
        }

        // 3. 等待屏障（如果配置）
        if let Some(barrier) = args.barrier {
            wait_on_barrier(barrier).await?;
        }

        // 4. 执行后置延时
        if let Some(delay) = args.sleep_after_ms && delay > 0 {
            sleep(Duration::from_millis(delay)).await;
        }

        // 5. 返回成功
        Ok(FunctionToolOutput::from_text("ok".to_string(), Some(true)))
    }
}
```

#### 屏障等待逻辑
```rust
async fn wait_on_barrier(args: BarrierArgs) -> Result<(), FunctionCallError> {
    // 参数验证
    if args.participants == 0 {
        return Err(FunctionCallError::RespondToModel(
            "barrier participants must be greater than zero".to_string(),
        ));
    }

    if args.timeout_ms == 0 {
        return Err(FunctionCallError::RespondToModel(
            "barrier timeout must be greater than zero".to_string(),
        ));
    }

    // 获取或创建屏障
    let barrier = {
        let mut map = barrier_map().lock().await;
        match map.entry(barrier_id.clone()) {
            Entry::Occupied(entry) => {
                // 验证参与者数量一致
                let state = entry.get();
                if state.participants != args.participants {
                    return Err(FunctionCallError::RespondToModel(format!(
                        "barrier {barrier_id} already registered with {existing} participants"
                    )));
                }
                state.barrier.clone()
            }
            Entry::Vacant(entry) => {
                // 创建新屏障
                let barrier = Arc::new(Barrier::new(args.participants));
                entry.insert(BarrierState { barrier: barrier.clone(), participants: args.participants });
                barrier
            }
        }
    };

    // 带超时的屏障等待
    let timeout = Duration::from_millis(args.timeout_ms);
    let wait_result = tokio::time::timeout(timeout, barrier.wait())
        .await
        .map_err(|_| FunctionCallError::RespondToModel("test_sync_tool barrier wait timed out".to_string()))?;

    // 领导者负责清理
    if wait_result.is_leader() {
        let mut map = barrier_map().lock().await;
        if let Some(state) = map.get(&barrier_id)
            && Arc::ptr_eq(&state.barrier, &barrier)
        {
            map.remove(&barrier_id);
        }
    }

    Ok(())
}
```

### 参数解析

工具接受 JSON 格式的参数：
```json
{
    "sleep_before_ms": 100,  // 可选：屏障前等待毫秒数
    "sleep_after_ms": 50,    // 可选：屏障后等待毫秒数
    "barrier": {             // 可选：屏障配置
        "id": "test_barrier_1",
        "participants": 3,
        "timeout_ms": 5000
    }
}
```

## 关键代码路径与文件引用

### 模块结构
```
test_sync.rs
├── TestSyncHandler (主处理器)
│   ├── handle() - 工具调用入口
│   └── kind() -> ToolKind::Function
├── wait_on_barrier() - 屏障等待实现
└── barrier_map() - 全局屏障存储
```

### 依赖关系
```rust
// 核心依赖
use crate::function_tool::FunctionCallError;    // 错误类型
use crate::tools::context::FunctionToolOutput;  // 输出类型
use crate::tools::context::ToolInvocation;      // 调用上下文
use crate::tools::context::ToolPayload;         // 负载类型
use crate::tools::handlers::parse_arguments;    // 参数解析
use crate::tools::registry::ToolHandler;        // 处理器 trait
use crate::tools::registry::ToolKind;           // 工具类型

// 标准库和异步运行时
use tokio::sync::Barrier;                       // 屏障原语
use std::sync::OnceLock;                        // 懒初始化
```

### 注册位置
在 `codex-rs/core/src/tools/handlers/mod.rs` 中导出：
```rust
pub use test_sync::TestSyncHandler;
```

## 依赖与外部交互

### 内部模块交互
```
TestSyncHandler
    ├── ToolRegistry (通过 ToolHandler trait)
    │   └── 注册为 function 类型工具
    ├── ToolInvocation
    │   ├── payload: ToolPayload::Function { arguments }
    │   ├── session: Arc<Session>
    │   └── turn: Arc<TurnContext>
    └── FunctionToolOutput
        └── 返回 "ok" 文本结果
```

### 全局状态管理
```rust
// 使用 OnceLock 实现线程安全的懒初始化
static BARRIERS: OnceLock<tokio::sync::Mutex<HashMap<String, BarrierState>>> = OnceLock::new();

fn barrier_map() -> &'static tokio::sync::Mutex<HashMap<String, BarrierState>> {
    BARRIERS.get_or_init(|| tokio::sync::Mutex::new(HashMap::new()))
}
```

## 风险、边界与改进建议

### 潜在风险

1. **全局状态泄漏**
   - 使用全局静态变量存储屏障状态
   - 测试崩溃可能导致屏障残留
   - 领导者清理逻辑依赖 `Arc::ptr_eq`，在极端并发下可能失效

2. **参与者数量不一致**
   ```rust
   // 如果两个调用使用相同的 barrier id 但不同的 participants：
   // 第一个调用: participants=3
   // 第二个调用: participants=5  -> 返回错误
   ```

3. **超时处理**
   - 默认超时仅 1 秒，可能在高负载测试环境中不稳定
   - 超时后屏障状态未清理，可能导致内存泄漏

### 边界情况

1. **屏障 ID 冲突**
   ```rust
   // 不同测试用例使用相同 barrier id 会导致冲突
   // 建议：使用 UUID 或测试用例前缀命名空间
   ```

2. **参与者数量变化**
   - 一旦屏障创建，参与者数量固定
   - 动态添加/移除参与者不被支持

3. **清理时序**
   ```rust
   // 领导者清理屏障后，其他参与者可能仍在等待
   // 需要确保所有参与者完成后再清理
   ```

### 改进建议

1. **增强错误处理**
   ```rust
   // 建议添加屏障状态查询接口
   pub async fn barrier_status(id: &str) -> Option<BarrierStatus> {
       let map = barrier_map().lock().await;
       map.get(id).map(|state| BarrierStatus {
           participants: state.participants,
           waiting: state.barrier.waiting_count(),
       })
   }
   ```

2. **自动清理机制**
   ```rust
   // 添加定期清理过期屏障的任务
   pub async fn cleanup_expired_barriers(max_age: Duration) {
       // 实现清理逻辑
   }
   ```

3. **命名空间隔离**
   ```rust
   // 支持测试用例级别的命名空间
   struct BarrierArgs {
       id: String,
       namespace: Option<String>,  // 新增
       participants: usize,
       timeout_ms: u64,
   }
   ```

4. **监控和可观测性**
   ```rust
   // 添加指标收集
   tracing::info!(
       barrier_id = %barrier_id,
       participants = args.participants,
       "created test_sync barrier"
   );
   ```

5. **测试覆盖增强**
   ```rust
   // 建议添加的测试用例：
   - 超时后的屏障重建
   - 多屏障并发使用
   - 参与者数量不匹配的错误处理
   - 领导者崩溃后的恢复
   ```

### 使用注意事项

1. 该工具仅在测试环境中注册，生产环境不可用
2. 屏障 ID 应具有唯一性，建议使用测试用例名称前缀
3. 超时设置应考虑测试环境的性能差异
4. 避免在屏障回调中执行阻塞操作
