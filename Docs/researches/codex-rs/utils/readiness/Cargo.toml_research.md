# Cargo.toml 研究文档

## 文件信息
- **路径**: `codex-rs/utils/readiness/Cargo.toml`
- **大小**: 447 bytes
- **所属 crate**: `codex-utils-readiness`
- **crate 类型**: 工具库 (utility library)

---

## 场景与职责

`codex-utils-readiness` 是一个提供**就绪标志 (Readiness Flag)** 功能的 Rust 工具库。它实现了基于令牌 (token-based) 授权的异步就绪通知机制，用于协调多组件系统的启动顺序和依赖管理。

**核心使用场景**:
1. **Ghost Snapshot 任务协调**: 在 `codex-core` 中，用于确保 ghost snapshot（Git 幽灵提交）完成后才允许执行可能修改环境的工具调用
2. **工具调用门控**: 防止在系统准备就绪前执行可能产生副作用的操作

---

## 功能点目的

### 1. 包元数据
```toml
[package]
name = "codex-utils-readiness"
version.workspace = true
edition.workspace = true
license.workspace = true
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `name` | `codex-utils-readiness` | crate 名称，遵循 `codex-utils-*` 命名规范 |
| `version` | `workspace = true` | 继承工作区版本 (0.0.0) |
| `edition` | `workspace = true` | 继承 Rust 2024 edition |
| `license` | `workspace = true` | 继承 Apache-2.0 许可证 |

### 2. 运行时依赖
```toml
[dependencies]
async-trait = { workspace = true }
thiserror = { workspace = true }
time = { workspace = true }
tokio = { workspace = true, features = ["sync", "time"] }
```

| 依赖 | 用途 |
|------|------|
| `async-trait` | 支持异步 trait 定义 (`#[async_trait]`) |
| `thiserror` | 简化错误类型定义 |
| `time` | 时间类型和超时处理 |
| `tokio` | 异步运行时，使用 `sync` (watch channel, Mutex) 和 `time` (timeout) 特性 |

### 3. 开发依赖
```toml
[dev-dependencies]
assert_matches = { workspace = true }
tokio = { workspace = true, features = ["macros", "rt", "rt-multi-thread"] }
```

| 依赖 | 用途 |
|------|------|
| `assert_matches` | 测试中断言模式匹配 |
| `tokio` (额外特性) | 测试所需的宏和运行时 |

### 4. 代码检查配置
```toml
[lints]
workspace = true
```
继承工作区级别的 Clippy 和其他 lint 规则。

---

## 具体技术实现

### 核心架构

该 crate 实现了**令牌授权的就绪标志模式**，主要组件：

```rust
// 核心 trait 定义
#[async_trait::async_trait]
pub trait Readiness: Send + Sync + 'static {
    fn is_ready(&self) -> bool;
    async fn subscribe(&self) -> Result<Token, ReadinessError>;
    async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError>;
    async fn wait_ready(&self);
}

// 具体实现
pub struct ReadinessFlag {
    ready: AtomicBool,           // 快速读取就绪状态
    next_id: AtomicI32,          // 令牌 ID 生成器
    tokens: Mutex<HashSet<Token>>, // 活跃订阅令牌集合
    tx: watch::Sender<bool>,     // 广播就绪状态变化
}

// 不透明令牌
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Token(i32);
```

### 关键流程

#### 1. 订阅流程 (`subscribe`)
```rust
async fn subscribe(&self) -> Result<Token, ReadinessError> {
    // 1. 快速检查：如果已就绪，返回错误
    if self.load_ready() {
        return Err(ReadinessError::FlagAlreadyReady);
    }
    
    // 2. 加锁后再次检查（防止竞态）
    // 3. 生成唯一令牌 ID（跳过 0，处理 i32 回绕）
    // 4. 插入活跃令牌集合
    // 5. 返回令牌
}
```

#### 2. 标记就绪流程 (`mark_ready`)
```rust
async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError> {
    // 1. 验证令牌有效性（必须在活跃集合中）
    // 2. 从集合移除令牌
    // 3. 设置原子标志 ready = true
    // 4. 清空所有其他令牌（一旦就绪，不再接受新订阅）
    // 5. 广播就绪状态（通过 watch channel）
}
```

#### 3. 等待就绪流程 (`wait_ready`)
```rust
async fn wait_ready(&self) {
    // 1. 快速路径检查
    if self.is_ready() { return; }
    
    // 2. 订阅 watch channel
    let mut rx = self.tx.subscribe();
    
    // 3. 等待直到收到 true
    while rx.changed().await.is_ok() {
        if *rx.borrow() { break; }
    }
}
```

### 特殊设计

#### 无订阅者自动就绪
```rust
fn is_ready(&self) -> bool {
    if self.load_ready() { return true; }
    
    // 如果没有活跃订阅者，自动标记为就绪
    if let Ok(tokens) = self.tokens.try_lock() && tokens.is_empty() {
        self.ready.swap(true, Ordering::AcqRel);
        let _ = self.tx.send(true);
        return true;
    }
    
    self.load_ready()
}
```
这个设计允许系统在没有显式订阅者时也能继续执行。

#### 令牌 ID 生成策略
```rust
loop {
    let token = Token(self.next_id.fetch_add(1, Ordering::Relaxed));
    if token.0 != 0 && tokens.insert(token) {
        return Some(token);
    }
}
```
- 跳过 0（保留值）
- 处理 i32 回绕（通过循环和集合去重）

---

## 关键代码路径与文件引用

### 内部文件
| 文件 | 说明 |
|------|------|
| `src/lib.rs` | 完整实现（314 行，包含测试） |

### 调用方（外部依赖）
| 文件 | 使用方式 |
|------|----------|
| `codex-rs/core/src/codex.rs:338-339` | `use codex_utils_readiness::{Readiness, ReadinessFlag};` |
| `codex-rs/core/src/codex.rs:827` | `tool_call_gate: Arc<ReadinessFlag>` 字段定义 |
| `codex-rs/core/src/codex.rs:934` | `tool_call_gate: Arc::new(ReadinessFlag::new())` 初始化 |
| `codex-rs/core/src/codex.rs:1380` | 另一处初始化 |
| `codex-rs/core/src/tools/registry.rs:23` | `use codex_utils_readiness::Readiness;` |
| `codex-rs/core/src/tools/registry.rs:265` | `invocation_for_tool.turn.tool_call_gate.wait_ready().await` 等待就绪 |
| `codex-rs/core/src/tasks/ghost_snapshot.rs:14-15` | `use codex_utils_readiness::{Readiness, Token};` |
| `codex-rs/core/src/tasks/ghost_snapshot.rs:153` | `ctx.tool_call_gate.mark_ready(token).await` 标记就绪 |

### 依赖图
```
codex-core
├── codex-utils-readiness (本 crate)
│   ├── async-trait
│   ├── thiserror
│   ├── time
│   └── tokio (sync, time)
```

---

## 依赖与外部交互

### 运行时依赖详解

#### `tokio = { features = ["sync", "time"] }`
- **`sync`**: 提供 `watch::channel` 用于广播就绪状态，`Mutex` 用于保护令牌集合
- **`time`**: 提供 `timeout` 用于锁获取超时处理（`LOCK_TIMEOUT = 1000ms`）

#### `async-trait`
使 trait 方法可以是异步的：
```rust
#[async_trait::async_trait]
pub trait Readiness {
    async fn subscribe(&self) -> Result<Token, ReadinessError>;
    async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError>;
    async fn wait_ready(&self);
}
```

#### `thiserror`
简化错误枚举定义：
```rust
#[derive(Debug, Error)]
pub enum ReadinessError {
    #[error("Failed to acquire readiness token lock")]
    TokenLockFailed,
    #[error("Flag is already ready. Impossible to subscribe")]
    FlagAlreadyReady,
}
```

#### `time`
用于超时处理：
```rust
const LOCK_TIMEOUT: Duration = Duration::from_millis(1000);
let mut guard = time::timeout(LOCK_TIMEOUT, self.tokens.lock()).await?;
```

---

## 风险、边界与改进建议

### 风险

1. **锁超时**
   - 令牌集合的锁获取有 1 秒超时
   - 极端情况下可能导致 `TokenLockFailed` 错误
   - 当前测试覆盖此场景（`subscribe_returns_error_when_lock_is_held`）

2. **i32 令牌 ID 回绕**
   - 理论上如果订阅/取消订阅循环超过 2^31 次，可能产生重复令牌
   - 代码通过循环检测和集合去重缓解，但仍有极小的竞态窗口

3. **内存使用**
   - 每个订阅者占用一个 `Token` 在 `HashSet` 中
   - 如果订阅者泄漏（不调用 `mark_ready`），令牌将一直占用内存

### 边界

1. **单方向状态**
   - 就绪状态是单向的：一旦就绪，不能回到未就绪
   - 适用于初始化场景，不适用于可重置的状态管理

2. **Tokio 依赖**
   - 强依赖 Tokio 运行时，不能用于其他异步运行时（如 async-std）

3. **线程安全假设**
   - `ReadinessFlag` 是 `Send + Sync`，但 `Token` 只是 `Copy`，没有访问控制
   - 令牌可以被任意克隆使用（虽然设计上每个令牌应该唯一使用）

### 改进建议

1. **使用原子计数器替代 Mutex**
   - 当前使用 `Mutex<HashSet<Token>>` 保护活跃令牌
   - 可考虑使用 `dashmap` 或原子操作优化高并发场景

2. **添加指标/观测**
   - 可添加 `tracing` 日志记录订阅/就绪事件
   - 有助于调试启动顺序问题

3. **支持超时等待**
   - 当前 `wait_ready()` 无限等待
   - 可添加 `wait_ready_timeout(duration)` 变体

4. **改进错误类型**
   - 当前 `ReadinessError` 只有两个变体
   - 可添加 `InvalidToken` 区分无效令牌和已使用令牌

5. **文档示例**
   - 建议添加 doc example 展示典型使用模式：
   ```rust
   /// # Example
   /// ```
   /// use codex_utils_readiness::{Readiness, ReadinessFlag};
   /// 
   /// #[tokio::main]
   /// async fn main() {
   ///     let flag = ReadinessFlag::new();
   ///     let token = flag.subscribe().await.unwrap();
   ///     
   ///     // 在另一个任务中等待
   ///     let flag2 = flag.clone();
   ///     let waiter = tokio::spawn(async move {
   ///         flag2.wait_ready().await;
   ///         println!("Ready!");
   ///     });
   ///     
   ///     // 标记就绪
   ///     flag.mark_ready(token).await.unwrap();
   ///     waiter.await.unwrap();
   /// }
   /// ```

### 测试覆盖

该 crate 有完善的单元测试（11 个测试用例）：
- `subscribe_and_mark_ready_roundtrip`: 基本流程
- `subscribe_after_ready_returns_none`: 就绪后拒绝订阅
- `mark_ready_rejects_unknown_token`: 无效令牌拒绝
- `wait_ready_unblocks_after_mark_ready`: 等待/通知机制
- `mark_ready_twice_uses_single_token`: 令牌一次性使用
- `is_ready_without_subscribers_marks_flag_ready`: 无订阅者自动就绪
- `subscribe_returns_error_when_lock_is_held`: 锁超时处理
- `subscribe_skips_zero_token`: 跳过零令牌
- `subscribe_avoids_duplicate_tokens`: 处理 ID 回绕

测试使用了 `tokio::test` 和 `assert_matches` 进行异步测试。
