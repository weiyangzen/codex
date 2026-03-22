# codex-rs/utils/readiness 研究文档

## 概述

`codex-utils-readiness` 是 Codex 项目中的一个基础工具库，提供了一个**基于 Token 授权的就绪状态标志（Readiness Flag）**实现。该库用于协调异步系统中多个任务之间的就绪状态通知，特别适用于需要等待某个初始化任务完成后才能继续执行的场景。

---

## 场景与职责

### 核心场景

1. **Ghost Snapshot 任务协调**
   - 在 `codex-core` 中，`ReadinessFlag` 被用作 `tool_call_gate`，控制 Ghost Snapshot（仓库快照）任务与工具调用之间的执行顺序
   - Ghost Snapshot 任务需要在后台创建 Git 幽灵提交，而工具调用（特别是 mutating 操作）需要等待快照准备就绪

2. **异步任务就绪通知**
   - 提供一种机制：一个任务可以订阅就绪状态，另一个任务在完成后标记就绪，从而解除等待者的阻塞

3. **防止竞态条件**
   - 通过 Token 机制确保只有合法的订阅者才能标记就绪状态
   - 防止重复标记或非法标记

### 职责边界

| 职责 | 说明 |
|------|------|
| 就绪状态管理 | 维护一个布尔值表示是否就绪，状态为单向（一旦就绪不可恢复） |
| Token 生成与验证 | 为每个订阅者生成唯一的 Token，标记就绪时需要提供有效 Token |
| 异步等待 | 提供 `wait_ready()` 方法供异步任务阻塞等待 |
| 广播通知 | 使用 `tokio::sync::watch` 实现多播通知 |

---

## 功能点目的

### 1. Token 机制

**目的**：确保就绪状态只能由合法的、已订阅的实体标记。

**工作流程**：
```
订阅者A --subscribe()--> 获得 TokenA
订阅者B --subscribe()--> 获得 TokenB

订阅者A --mark_ready(TokenA)--> 成功，状态变为就绪
订阅者B --mark_ready(TokenB)--> 失败（TokenB 已被清除）
```

**关键特性**：
- Token 是唯一的、不透明的 `i32` 值
- 预留 0 值作为无效 Token
- 处理 `i32` 回绕情况，避免重复 Token

### 2. 自动就绪（Auto-Ready）

**目的**：当没有活跃订阅者时，系统自动标记为就绪。

**场景**：
- 如果 `is_ready()` 被调用时没有任何订阅者，标志自动变为就绪状态
- 这防止了死锁：如果没有任务订阅，等待者将永远阻塞

### 3. 超时保护

**目的**：防止在获取 Token 锁时无限期阻塞。

**实现**：
```rust
const LOCK_TIMEOUT: Duration = Duration::from_millis(1000);
```

### 4. 广播通知

**目的**：支持多个并发等待者同时被唤醒。

**实现**：使用 `tokio::sync::watch::Sender<bool>` 进行广播。

---

## 具体技术实现

### 数据结构

#### Token
```rust
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Token(i32);
```
- 简单的 newtype 包装，保证类型安全
- 实现了 `Copy`，便于传递

#### ReadinessFlag
```rust
pub struct ReadinessFlag {
    /// 原子布尔值，用于快速读取
    ready: AtomicBool,
    /// 用于生成下一个 Token ID
    next_id: AtomicI32,
    /// 活跃订阅者的 Token 集合
    tokens: Mutex<HashSet<Token>>,
    /// 广播就绪状态给异步等待者
    tx: watch::Sender<bool>,
}
```

**设计要点**：
- `AtomicBool` 用于无锁快速检查
- `AtomicI32` 用于无锁 Token 生成
- `Mutex<HashSet<Token>>` 保护订阅者集合（仅在订阅/标记时访问）
- `watch::Sender` 实现广播语义

### 关键流程

#### 订阅流程 (`subscribe`)

```rust
async fn subscribe(&self) -> Result<Token, ReadinessError> {
    // 1. 快速检查：如果已就绪，直接返回错误
    if self.load_ready() {
        return Err(ReadinessError::FlagAlreadyReady);
    }

    // 2. 获取锁并重新检查（防止竞态）
    let token = self.with_tokens(|tokens| {
        if self.load_ready() {
            return None;
        }

        // 3. 生成唯一 Token（处理回绕）
        loop {
            let token = Token(self.next_id.fetch_add(1, Ordering::Relaxed));
            if token.0 != 0 && tokens.insert(token) {
                return Some(token);
            }
        }
    }).await?;

    token.ok_or(ReadinessError::FlagAlreadyReady)
}
```

**关键设计**：
- 双重检查锁定模式（DCL）：先无锁检查，再持锁确认
- 循环生成 Token 直到找到唯一值（处理 `i32` 回绕）
- 超时保护：`with_tokens` 使用 `time::timeout`

#### 标记就绪流程 (`mark_ready`)

```rust
async fn mark_ready(&self, token: Token) -> Result<bool, ReadinessError> {
    // 1. 快速检查
    if self.load_ready() {
        return Ok(false);
    }
    // 2. 拒绝无效 Token
    if token.0 == 0 {
        return Ok(false);
    }

    // 3. 验证 Token 并标记
    let marked = self.with_tokens(|set| {
        if !set.remove(&token) {
            return false; // Token 无效或已使用
        }
        self.ready.store(true, Ordering::Release);
        set.clear(); // 清除所有其他 Token
        true
    }).await?;

    if marked {
        let _ = self.tx.send(true); // 广播通知
    }
    Ok(marked)
}
```

**关键设计**：
- Token 验证：必须从活跃集合中移除才算有效
- 原子标记：使用 `Ordering::Release` 保证内存顺序
- 清除其他 Token：一旦就绪，其他订阅者无法标记
- 广播通知：唤醒所有等待者

#### 等待就绪流程 (`wait_ready`)

```rust
async fn wait_ready(&self) {
    // 1. 快速路径
    if self.is_ready() {
        return;
    }
    
    // 2. 订阅广播
    let mut rx = self.tx.subscribe();
    if *rx.borrow() {
        return;
    }
    
    // 3. 等待广播通知
    while rx.changed().await.is_ok() {
        if *rx.borrow() {
            break;
        }
    }
}
```

**关键设计**：
- 双重快速路径检查，避免不必要的订阅
- 使用 `watch::Receiver` 实现异步等待

#### 自动就绪逻辑 (`is_ready`)

```rust
fn is_ready(&self) -> bool {
    // 1. 快速检查
    if self.load_ready() {
        return true;
    }

    // 2. 无订阅者时自动标记就绪
    if let Ok(tokens) = self.tokens.try_lock()
        && tokens.is_empty()
    {
        let was_ready = self.ready.swap(true, Ordering::AcqRel);
        drop(tokens);
        if !was_ready {
            let _ = self.tx.send(true);
        }
        return true;
    }

    self.load_ready()
}
```

**关键设计**：
- 当没有活跃订阅者时，自动标记为就绪
- 防止系统在没有订阅者的情况下永远等待

### 错误处理

```rust
#[derive(Debug, Error)]
pub enum ReadinessError {
    #[error("Failed to acquire readiness token lock")]
    TokenLockFailed,
    #[error("Flag is already ready. Impossible to subscribe")]
    FlagAlreadyReady,
}
```

### 内存顺序

| 操作 | 顺序 | 说明 |
|------|------|------|
| `ready.load` | `Acquire` | 与 `store` 形成 happens-before 关系 |
| `ready.store` | `Release` | 确保之前的操作对后续读取可见 |
| `next_id.fetch_add` | `Relaxed` | Token 生成不需要严格顺序 |
| `ready.swap` | `AcqRel` | 同时需要获取和释放语义 |

---

## 关键代码路径与文件引用

### 本库文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `codex-rs/utils/readiness/src/lib.rs` | 314 | 完整实现，包含测试 |

### 调用方代码路径

#### 1. 订阅与使用 Token

**文件**: `codex-rs/core/src/codex.rs:3794-3800`
```rust
let token = match turn_context.tool_call_gate.subscribe().await {
    Ok(token) => token,
    Err(err) => {
        warn!("failed to subscribe to ghost snapshot readiness: {err}");
        return;
    }
};
```

**场景**: 在 `maybe_start_ghost_snapshot` 中订阅 Ghost Snapshot 任务的就绪状态。

#### 2. 等待就绪

**文件**: `codex-rs/core/src/tools/registry.rs:264-266`
```rust
if is_mutating {
    tracing::trace!("waiting for tool gate");
    invocation_for_tool.turn.tool_call_gate.wait_ready().await;
    tracing::trace!("tool gate released");
}
```

**场景**: 在工具注册表中，mutating 工具调用前等待 `tool_call_gate` 就绪。

#### 3. 标记就绪

**文件**: `codex-rs/core/src/tasks/ghost_snapshot.rs:153-157`
```rust
match ctx.tool_call_gate.mark_ready(token).await {
    Ok(true) => info!("ghost snapshot gate marked ready"),
    Ok(false) => warn!("ghost snapshot gate already ready"),
    Err(err) => warn!("failed to mark ghost snapshot ready: {err}"),
}
```

**场景**: Ghost Snapshot 任务完成后标记就绪，允许 mutating 工具执行。

#### 4. TurnContext 创建

**文件**: `codex-rs/core/src/codex.rs:934` 和 `1380`
```rust
tool_call_gate: Arc::new(ReadinessFlag::new()),
```

**场景**: 每个 TurnContext 创建时初始化新的 `ReadinessFlag`。

**文件**: `codex-rs/core/src/codex.rs:5301`
```rust
tool_call_gate: Arc::new(ReadinessFlag::new()),
```

**场景**: Review Task 的 TurnContext 创建时也初始化新的 `ReadinessFlag`。

### 数据结构定义

**文件**: `codex-rs/core/src/codex.rs:827`
```rust
pub(crate) tool_call_gate: Arc<ReadinessFlag>,
```

`TurnContext` 中的 `tool_call_gate` 字段类型。

---

## 依赖与外部交互

### 依赖 crate

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时（`sync::Mutex`, `sync::watch`, `time::timeout`） |
| `async-trait` | 异步 trait 支持 |
| `thiserror` | 错误类型定义 |

### 被依赖情况

**文件**: `codex-rs/core/Cargo.toml:56`
```toml
codex-utils-readiness = { workspace = true }
```

**文件**: `codex-rs/Cargo.toml`（workspace 定义）
```toml
codex-utils-readiness = { path = "utils/readiness" }
```

### 模块关系图

```
┌─────────────────────────────────────────────────────────────┐
│                        codex-core                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   codex.rs   │  │tools/registry│  │tasks/ghost_snapshot│  │
│  │  (TurnContext)│  │              │  │                  │  │
│  │  - subscribe │  │  - wait_ready │  │  - mark_ready    │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘  │
│         │                 │                   │            │
│         └─────────────────┴───────────────────┘            │
│                           │                                │
│                           ▼                                │
│              ┌────────────────────────┐                   │
│              │   Arc<ReadinessFlag>   │                   │
│              │     (tool_call_gate)   │                   │
│              └────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-utils-readiness                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  ReadinessFlag                        │  │
│  │  - ready: AtomicBool                                 │  │
│  │  - next_id: AtomicI32                                │  │
│  │  - tokens: Mutex<HashSet<Token>>                     │  │
│  │  - tx: watch::Sender<bool>                           │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 执行流程图

```
Turn 开始
    │
    ▼
┌─────────────────────┐
│ 创建 ReadinessFlag  │◄─────────────────────────────┐
│ (tool_call_gate)    │                              │
└──────────┬──────────┘                              │
           │                                         │
           ▼                                         │
┌─────────────────────┐     ┌─────────────────┐     │
│ GhostSnapshotTask   │     │ 工具调用（如 shell）│     │
│ 订阅: subscribe()   │     │ 等待: wait_ready()│     │
│ 获得 Token          │     │     （阻塞）      │     │
└──────────┬──────────┘     └────────┬────────┘     │
           │                         │              │
           ▼                         │              │
┌─────────────────────┐              │              │
│ 创建 Ghost Commit   │              │              │
│ （可能耗时较长）     │              │              │
└──────────┬──────────┘              │              │
           │                         │              │
           ▼                         ▼              │
┌─────────────────────┐     ┌─────────────────┐     │
│ mark_ready(Token)   │────►│  解除阻塞，继续  │     │
│ 标记就绪，广播通知   │     │  执行 mutating  │     │
└─────────────────────┘     │    工具调用      │     │
                            └─────────────────┘     │
                                     │              │
                                     ▼              │
                            ┌─────────────────┐     │
                            │   Turn 结束      │─────┘
                            │ (丢弃旧 Flag，   │     │
                            │  新 Turn 创建新的)│     │
                            └─────────────────┘─────┘
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. Token 耗尽风险
**问题**：`i32` 范围有限，极端情况下可能回绕。

**缓解**：
- 代码中通过循环 `loop { ... }` 跳过 0 值和重复值
- 实际场景中 Token 生命周期短，不太可能耗尽

#### 2. 锁超时
**问题**：如果 `tokens` 锁被长时间持有，`subscribe` 会超时失败。

**缓解**：
- 超时时间 1000ms 相对合理
- 调用方需要处理 `TokenLockFailed` 错误

#### 3. 自动就绪的副作用
**问题**：如果订阅者在 `is_ready()` 调用前退出，`is_ready()` 会立即返回 true。

**影响**：Ghost Snapshot 未完成，但工具调用可能开始执行。

**实际行为**：
```rust
// ghost_snapshot.rs 中
let token = match turn_context.tool_call_gate.subscribe().await {
    Ok(token) => token,
    Err(err) => {
        // 如果这里返回，不会创建 GhostSnapshotTask
        return;
    }
};
```

实际上，如果订阅失败，Ghost Snapshot 任务不会启动，工具调用也不会被阻塞。

### 边界情况

| 场景 | 行为 |
|------|------|
| 多次标记就绪 | 第二次及以后返回 `Ok(false)` |
| 使用无效 Token | 返回 `Ok(false)` |
| Token 为 0 | 返回 `Ok(false)`（永不授权） |
| 无订阅者时调用 `is_ready()` | 自动标记为就绪 |
| 锁获取超时 | 返回 `Err(ReadinessError::TokenLockFailed)` |
| 已就绪后订阅 | 返回 `Err(ReadinessError::FlagAlreadyReady)` |

### 测试覆盖

**单元测试**（位于 `lib.rs` 底部）：

| 测试名 | 覆盖场景 |
|--------|----------|
| `subscribe_and_mark_ready_roundtrip` | 基本订阅-标记流程 |
| `subscribe_after_ready_returns_none` | 已就绪后订阅失败 |
| `mark_ready_rejects_unknown_token` | 拒绝无效 Token |
| `wait_ready_unblocks_after_mark_ready` | 异步等待解除阻塞 |
| `mark_ready_twice_uses_single_token` | 同一 Token 只能标记一次 |
| `is_ready_without_subscribers_marks_flag_ready` | 无订阅者自动就绪 |
| `subscribe_returns_error_when_lock_is_held` | 锁超时错误 |
| `subscribe_skips_zero_token` | 跳过 0 值 Token |
| `subscribe_avoids_duplicate_tokens` | 处理 ID 回绕，避免重复 Token |

### 改进建议

#### 1. 增加观测性
```rust
// 建议：增加指标或日志
pub struct ReadinessFlag {
    // ... existing fields
    #[cfg(feature = "metrics")]
    wait_duration: Histogram,
}
```

#### 2. 支持多个就绪阶段
当前实现是二元的（就绪/未就绪）。可以考虑支持多阶段就绪：
```rust
pub enum ReadinessState {
    NotReady,
    PartiallyReady(u8),  // 0-100 进度
    Ready,
}
```

#### 3. 取消支持
当前 `wait_ready()` 无法被取消。可以考虑：
```rust
async fn wait_ready_with_cancel(&self, cancel: CancellationToken) -> Result<(), Cancelled>;
```

#### 4. 文档改进
- 添加更多使用示例
- 明确说明自动就绪行为的影响

#### 5. 性能优化
当前 `Mutex<HashSet<Token>>` 在订阅者多时可能成为瓶颈。如果预期有大量订阅者，可以考虑：
- 使用 `RwLock` 替代 `Mutex`
- 使用更高效的并发数据结构（如 `dashmap`）

### 代码质量评估

| 维度 | 评分 | 说明 |
|------|------|------|
| 正确性 | ⭐⭐⭐⭐⭐ | 正确处理竞态条件、内存顺序、边界情况 |
| 可测试性 | ⭐⭐⭐⭐⭐ | 单元测试覆盖全面 |
| 文档 | ⭐⭐⭐⭐ | 有基本文档，可增加更多示例 |
| 性能 | ⭐⭐⭐⭐ | 使用原子操作优化快速路径 |
| 可维护性 | ⭐⭐⭐⭐⭐ | 代码简洁，职责清晰 |

---

## 总结

`codex-utils-readiness` 是一个设计精良的小型工具库，解决了异步系统中常见的"等待就绪"问题。其核心设计亮点包括：

1. **Token 授权机制**：防止非法标记，确保安全性
2. **自动就绪**：防止无订阅者时的死锁
3. **快速路径优化**：使用原子操作减少锁竞争
4. **广播通知**：支持多等待者同时唤醒

在 Codex 项目中，该库主要用于协调 Ghost Snapshot 任务与 mutating 工具调用之间的执行顺序，确保在创建仓库快照之前不会执行可能修改文件系统的操作。
