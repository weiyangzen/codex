# ReadinessFlag 模块研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-utils-readiness` 是 Codex 项目中的一个基础工具库，提供了一个**基于 Token 授权的就绪标志（Readiness Flag）**实现。该模块解决的核心问题是：

> **如何在异步环境中协调多个任务，确保某个关键前置条件（如资源准备、状态初始化）满足后，才允许后续操作继续执行？**

### 1.2 典型使用场景

在 Codex 项目中，`ReadinessFlag` 主要用于以下场景：

| 场景 | 说明 |
|------|------|
 **Ghost Snapshot 就绪控制** | 在 `ghost_snapshot.rs` 中，确保 Git 仓库快照完成前，工具调用被阻塞 |
 **工具调用门控** | 在 `registry.rs` 中，对于可能修改环境的工具（mutating tools），等待就绪信号后才执行 |
 **Turn 生命周期管理** | 每个 `TurnContext` 包含一个 `tool_call_gate`，控制该轮次中工具调用的时序 |

### 1.3 核心职责

1. **状态管理**：维护一个布尔标志位，表示"是否已就绪"
2. **Token 授权**：通过订阅-授权模式，确保只有持有有效 Token 的调用者才能标记就绪
3. **异步等待**：提供异步等待接口，允许任务阻塞直到就绪
4. **广播通知**：使用 `tokio::sync::watch` 实现多播通知，高效唤醒等待者

---

## 2. 功能点目的

### 2.1 功能概述

```rust
// 核心 Trait 定义
#[async_trait::async_trait]
pub trait Readiness: Send + Sync + 'static {
    fn is_ready(&self) -> bool;
    async fn subscribe(&self) -> Result<Token, ReadinessError>;
    async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError>;
    async fn wait_ready(&self);
}
```

### 2.2 各功能点详细说明

#### 2.2.1 `is_ready()` - 状态查询

- **目的**：快速检查就绪状态，非阻塞
- **特殊行为**：如果没有活跃订阅者，自动标记为就绪（优化空订阅场景）
- **使用场景**：快速路径检查，避免不必要的异步等待

#### 2.2.2 `subscribe()` - 订阅授权

- **目的**：获取一个授权 Token，用于后续标记就绪
- **约束**：
  - 每个 Token 唯一（基于原子自增 ID）
  - 跳过 ID 为 0 的 Token（保留值）
  - 处理 i32 溢出的循环情况
  - 已就绪后禁止新订阅（返回 `FlagAlreadyReady`）
- **返回值**：`Result<Token, ReadinessError>`

#### 2.2.3 `mark_ready()` - 标记就绪

- **目的**：使用有效 Token 将标志位标记为就绪
- **约束**：
  - Token 必须是通过 `subscribe()` 获取的有效 Token
  - Token 0 永远无效
  - 每个 Token 只能使用一次（消费后从集合移除）
  - 标记成功后清空所有未使用的 Token（一次性状态转换）
- **返回值**：`Result<bool, ReadinessError>` - 返回 true 表示成功标记

#### 2.2.4 `wait_ready()` - 异步等待

- **目的**：阻塞当前任务直到就绪
- **实现**：基于 `tokio::sync::watch` 的高效多播等待
- **优化**：快速路径检查，避免不必要的订阅

---

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
pub struct ReadinessFlag {
    /// 原子布尔，用于快速读取就绪状态
    ready: AtomicBool,
    /// 原子计数器，生成下一个 Token ID
    next_id: AtomicI32,
    /// 活跃订阅的 Token 集合（受 Mutex 保护）
    tokens: Mutex<HashSet<Token>>,
    /// 广播通道发送端，用于通知等待者
    tx: watch::Sender<bool>,
}

/// 不透明订阅 Token
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Token(i32);
```

### 3.2 关键流程

#### 3.2.1 初始化流程

```rust
pub fn new() -> Self {
    let (tx, _rx) = watch::channel(false);  // 初始状态为 false
    Self {
        ready: AtomicBool::new(false),
        next_id: AtomicI32::new(1),  // 从 1 开始，保留 0
        tokens: Mutex::new(HashSet::new()),
        tx,
    }
}
```

#### 3.2.2 订阅流程（含竞争处理）

```rust
async fn subscribe(&self) -> Result<Token, ReadinessError> {
    // 1. 快速路径检查
    if self.load_ready() {
        return Err(FlagAlreadyReady);
    }

    // 2. 持有锁期间重新检查（防止 mark_ready 的竞态）
    let token = self.with_tokens(|tokens| {
        if self.load_ready() {
            return None;
        }

        // 3. 生成唯一 Token（处理溢出循环）
        loop {
            let token = Token(self.next_id.fetch_add(1, Ordering::Relaxed));
            if token.0 != 0 && tokens.insert(token) {
                return Some(token);
            }
        }
    }).await?;

    token.ok_or(FlagAlreadyReady)
}
```

**关键设计点**：
- **双重检查**：锁外快速检查 + 锁内确认，减少锁竞争
- **溢出处理**：当 `i32` 溢出时跳过 0 值，确保 Token 唯一性
- **循环生成**：处理极端情况下的 ID 冲突

#### 3.2.3 标记就绪流程

```rust
async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError> {
    if self.load_ready() || token.0 == 0 {
        return Ok(false);
    }

    let marked = self.with_tokens(|set| {
        // 1. 验证并消费 Token
        if !set.remove(&token) {
            return false;
        }
        // 2. 原子存储就绪状态
        self.ready.store(true, Ordering::Release);
        // 3. 清空剩余 Token（一次性转换）
        set.clear();
        true
    }).await?;

    if marked {
        // 4. 广播通知所有等待者
        let _ = self.tx.send(true);
    }
    Ok(marked)
}
```

**关键设计点**：
- **Token 消费**：每个 Token 只能使用一次，防止重放攻击
- **内存序**：使用 `Ordering::Release` 确保状态变更对其他线程可见
- **广播通知**：通过 `watch::Sender` 高效通知所有等待者

#### 3.2.4 异步等待流程

```rust
async fn wait_ready(&self) {
    // 1. 快速路径
    if self.is_ready() { return; }

    // 2. 订阅广播通道
    let mut rx = self.tx.subscribe();
    if *rx.borrow() { return; }

    // 3. 等待状态变更
    while rx.changed().await.is_ok() {
        if *rx.borrow() { break; }
    }
}
```

### 3.3 内存序与同步

| 操作 | 内存序 | 说明 |
|------|--------|------|
| `load_ready()` | `Ordering::Acquire` | 与 `store(true, Release)` 配对，确保看到完整的状态变更 |
| `ready.store(true, ...)` | `Ordering::Release` | 发布就绪状态 |
| `ready.swap(true, AcqRel)` | `Ordering::AcqRel` | 在 `is_ready()` 的空订阅优化中使用 |
| `next_id.fetch_add(1, ...)` | `Ordering::Relaxed` | Token ID 生成不需要严格同步 |

### 3.4 锁超时机制

```rust
const LOCK_TIMEOUT: Duration = Duration::from_millis(1000);

async fn with_tokens<R>(
    &self,
    f: impl FnOnce(&mut HashSet<Token>) -> R,
) -> Result<R, ReadinessError> {
    let mut guard = time::timeout(LOCK_TIMEOUT, self.tokens.lock())
        .await
        .map_err(|_| ReadinessError::TokenLockFailed)?;
    Ok(f(&mut guard))
}
```

- **目的**：防止因死锁或长时间持有导致的无限等待
- **超时错误**：返回 `TokenLockFailed`，调用者可据此决策

---

## 4. 关键代码路径与文件引用

### 4.1 模块文件结构

```
codex-rs/utils/readiness/
├── Cargo.toml          # 包配置
├── BUILD.bazel         # Bazel 构建配置
└── src/
    └── lib.rs          # 模块实现（314 行）
```

### 4.2 核心代码位置

| 功能 | 文件路径 | 行号范围 |
|------|----------|----------|
| `Readiness` Trait 定义 | `codex-rs/utils/readiness/src/lib.rs` | 20-41 |
| `ReadinessFlag` 结构体 | `codex-rs/utils/readiness/src/lib.rs` | 43-52 |
| `Token` 结构体 | `codex-rs/utils/readiness/src/lib.rs` | 14-16 |
| `is_ready()` 实现 | `codex-rs/utils/readiness/src/lib.rs` | 97-114 |
| `subscribe()` 实现 | `codex-rs/utils/readiness/src/lib.rs` | 116-140 |
| `mark_ready()` 实现 | `codex-rs/utils/readiness/src/lib.rs` | 142-166 |
| `wait_ready()` 实现 | `codex-rs/utils/readiness/src/lib.rs` | 168-183 |
| 错误类型定义 | `codex-rs/utils/readiness/src/lib.rs` | 186-196 |
| 单元测试 | `codex-rs/utils/readiness/src/lib.rs` | 198-314 |

### 4.3 调用方代码路径

#### 4.3.1 Ghost Snapshot 任务

**文件**: `codex-rs/core/src/tasks/ghost_snapshot.rs`

```rust
// 行 14-15: 导入
use codex_utils_readiness::Readiness;
use codex_utils_readiness::Token;

// 行 23-25: 结构体定义
pub(crate) struct GhostSnapshotTask {
    token: Token,
}

// 行 3794-3799: 订阅获取 Token
let token = match turn_context.tool_call_gate.subscribe().await {
    Ok(token) => token,
    Err(err) => {
        warn!("failed to subscribe to ghost snapshot readiness: {err}");
        return;
    }
};

// 行 153-157: 任务完成后标记就绪
match ctx.tool_call_gate.mark_ready(token).await {
    Ok(true) => info!("ghost snapshot gate marked ready"),
    Ok(false) => warn!("ghost snapshot gate already ready"),
    Err(err) => warn!("failed to mark ghost snapshot ready: {err}"),
}
```

**流程说明**：
1. 在 `maybe_start_ghost_snapshot()` 中订阅获取 Token
2. 创建 `GhostSnapshotTask` 并传入 Token
3. 任务异步执行 Git 快照操作
4. 快照完成后调用 `mark_ready()` 释放工具调用门控

#### 4.3.2 工具注册表（Tool Registry）

**文件**: `codex-rs/core/src/tools/registry.rs`

```rust
// 行 23: 导入
use codex_utils_readiness::Readiness;

// 行 263-267: 工具调用前等待就绪
if is_mutating {
    tracing::trace!("waiting for tool gate");
    invocation_for_tool.turn.tool_call_gate.wait_ready().await;
    tracing::trace!("tool gate released");
}
```

**流程说明**：
1. 对于可能修改环境的工具（`is_mutating = true`）
2. 在调用 `handler.handle_any()` 前等待 `tool_call_gate`
3. 确保 Ghost Snapshot 等前置任务完成后才执行修改操作

#### 4.3.3 TurnContext 初始化

**文件**: `codex-rs/core/src/codex.rs`

```rust
// 行 338-339: 导入
use codex_utils_readiness::Readiness;
use codex_utils_readiness::ReadinessFlag;

// 行 827: TurnContext 字段定义
pub(crate) tool_call_gate: Arc<ReadinessFlag>,

// 行 934: 创建新的 ReadinessFlag
tool_call_gate: Arc::new(ReadinessFlag::new()),

// 行 1380: with_model() 中创建新的 gate
tool_call_gate: Arc::new(ReadinessFlag::new()),
```

---

## 5. 依赖与外部交互

### 5.1 依赖清单

**文件**: `codex-rs/utils/readiness/Cargo.toml`

```toml
[dependencies]
async-trait = { workspace = true }   # 异步 trait 支持
thiserror = { workspace = true }     # 错误类型派生
time = { workspace = true }          # 超时功能
tokio = { workspace = true, features = ["sync", "time"] }  # 异步运行时

[dev-dependencies]
assert_matches = { workspace = true }  # 测试断言
tokio = { workspace = true, features = ["macros", "rt", "rt-multi-thread"] }
```

### 5.2 外部 crate 使用说明

| Crate | 用途 |
|-------|------|
| `tokio::sync::Mutex` | 异步互斥锁，保护 Token 集合 |
| `tokio::sync::watch` | 多播通道，用于就绪通知 |
| `tokio::time::timeout` | 锁获取超时 |
| `async_trait::async_trait` | 支持异步 trait 方法 |
| `thiserror::Error` | 错误类型派生宏 |

### 5.3 被依赖关系

**文件**: `codex-rs/core/Cargo.toml`（行 56）

```toml
codex-utils-readiness = { workspace = true }
```

**工作空间定义**（`codex-rs/Cargo.toml` 行 149）：

```toml
codex-utils-readiness = { path = "utils/readiness" }
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 Token 泄漏风险

**风险描述**：如果订阅者获取 Token 后崩溃或忘记调用 `mark_ready()`，就绪标志将永远无法被标记。

**当前缓解**：
- `is_ready()` 的空订阅优化：如果没有活跃订阅者，自动标记就绪
- 但此优化仅在调用 `is_ready()` 时触发

**建议改进**：
```rust
// 考虑添加 Token 的 Drop 实现，在 Token 被丢弃时自动清理
// 但需注意：这会改变语义（可能需要在丢弃时标记就绪或发出警告）
```

#### 6.1.2 锁超时处理

**风险描述**：在高并发场景下，1 秒的超时可能导致正常的订阅/标记操作失败。

**当前实现**：
```rust
const LOCK_TIMEOUT: Duration = Duration::from_millis(1000);
```

**建议**：考虑根据实际使用场景调整超时时间，或提供可配置选项。

#### 6.1.3 i32 溢出处理

**风险描述**：虽然代码处理了 `i32` 溢出（跳过 0），但在极端高并发场景下，Token ID 可能快速循环，导致短暂的重复风险。

**当前实现**：
```rust
loop {
    let token = Token(self.next_id.fetch_add(1, Ordering::Relaxed));
    if token.0 != 0 && tokens.insert(token) {
        return Some(token);
    }
}
```

**评估**：实际风险极低（需要 2^31 次订阅），但代码正确处理了该边界。

### 6.2 边界条件

| 边界条件 | 行为 | 测试覆盖 |
|----------|------|----------|
| 无订阅者时调用 `is_ready()` | 自动标记就绪 | 是（`is_ready_without_subscribers_marks_flag_ready`） |
| Token ID 溢出到 0 | 跳过 0，继续递增 | 是（`subscribe_skips_zero_token`） |
| 重复 Token ID | 循环直到找到唯一值 | 是（`subscribe_avoids_duplicate_tokens`） |
| 锁被长时间持有 | 超时返回 `TokenLockFailed` | 是（`subscribe_returns_error_when_lock_is_held`） |
| 使用无效 Token | 返回 `Ok(false)` | 是（`mark_ready_rejects_unknown_token`） |
| 重复标记就绪 | 第二次返回 `Ok(false)` | 是（`mark_ready_twice_uses_single_token`） |
| 已就绪后订阅 | 返回 `FlagAlreadyReady` | 是（`subscribe_after_ready_returns_none`） |

### 6.3 改进建议

#### 6.3.1 增加观测能力

当前实现缺乏内省能力，建议添加：

```rust
impl ReadinessFlag {
    /// 获取当前活跃订阅数
    pub async fn subscriber_count(&self) -> usize {
        self.tokens.lock().await.len()
    }
    
    /// 检查 Token 是否仍然有效
    pub async fn is_token_valid(&self, token: Token) -> bool {
        self.tokens.lock().await.contains(&token)
    }
}
```

#### 6.3.2 支持超时等待

当前 `wait_ready()` 无限等待，建议添加超时版本：

```rust
async fn wait_ready_timeout(&self, timeout: Duration) -> Result<(), TimeoutError> {
    tokio::time::timeout(timeout, self.wait_ready()).await
        .map_err(|_| TimeoutError)?
}
```

#### 6.3.3 考虑使用 `parking_lot`

如果性能测试显示 `tokio::sync::Mutex` 成为瓶颈，可考虑：
- 使用 `parking_lot::Mutex`（同步锁）配合 `tokio::task::spawn_blocking`
- 或使用无锁数据结构（如 `dashmap`）

**当前评估**：Token 集合通常很小（1-2 个订阅者），当前实现已足够高效。

#### 6.3.4 Token 生命周期管理

考虑实现 `Token` 的自动清理：

```rust
impl Drop for Token {
    fn drop(&mut self) {
        // 可选：在 Token 被丢弃时记录警告
        // 或自动从集合中移除（需要 Arc<ReadinessFlag>）
    }
}
```

### 6.4 测试覆盖分析

当前测试（116 行）覆盖了主要功能路径：

| 测试用例 | 验证点 |
|----------|--------|
| `subscribe_and_mark_ready_roundtrip` | 基本订阅-标记流程 |
| `subscribe_after_ready_returns_none` | 已就绪后订阅失败 |
| `mark_ready_rejects_unknown_token` | 无效 Token 被拒绝 |
| `wait_ready_unblocks_after_mark_ready` | 异步等待正确唤醒 |
| `mark_ready_twice_uses_single_token` | Token 一次性使用 |
| `is_ready_without_subscribers_marks_flag_ready` | 空订阅优化 |
| `subscribe_returns_error_when_lock_is_held` | 锁超时处理 |
| `subscribe_skips_zero_token` | Token ID 溢出处理 |
| `subscribe_avoids_duplicate_tokens` | 重复 Token 避免 |

**建议补充的测试**：
1. 多并发订阅者的竞争场景
2. `wait_ready()` 在已就绪状态下的快速路径
3. 长时间运行场景下的 Token ID 循环

---

## 7. 总结

`ReadinessFlag` 是一个设计精良的同步原语，通过 Token 授权模式解决了异步环境中的就绪协调问题。其核心优势包括：

1. **安全性**：Token 机制确保只有授权调用者能标记就绪
2. **效率**：基于 `AtomicBool` 的快速路径 + `watch` 通道的高效通知
3. **鲁棒性**：正确处理溢出、超时、竞争等边界条件
4. **简洁性**：API 简单明了，仅 4 个核心方法

在 Codex 项目中，该模块成功应用于 Ghost Snapshot 和工具调用门控场景，确保了关键前置任务完成后才执行可能修改环境的操作。
