# guards.rs 研究文档

## 场景与职责

`guards.rs` 实现了 Codex 多代理系统的资源限制和访问控制机制。它是 `AgentControl` 的核心依赖，负责：

1. **线程数量限制**：限制每个用户会话可以同时运行的代理线程数量
2. **昵称分配管理**：为每个子代理分配唯一的昵称，避免冲突
3. **深度限制支持**：提供工具函数计算和检查线程 spawn 深度

`Guards` 结构体被设计为在同一会话的所有代理之间共享（通过 `Arc`），确保限制的全局一致性。

## 功能点目的

### 1. 线程数量限制
- 通过 `max_threads` 配置限制并发代理数量
- 使用原子操作和 CAS 循环实现无锁计数
- 提供预留-提交模式，避免竞态条件

### 2. 昵称分配
- 从候选列表中随机选择可用昵称
- 支持昵称池耗尽时的自动重置（添加序数后缀）
- 支持偏好昵称预留（用于恢复场景）

### 3. 深度计算
- 计算线程 spawn 的嵌套深度
- 提供深度限制检查函数

## 具体技术实现

### 核心数据结构

```rust
/// 资源限制和访问控制的主结构体
#[derive(Default)]
pub(crate) struct Guards {
    /// 互斥锁保护的活动代理集合
    active_agents: Mutex<ActiveAgents>,
    /// 原子计数器，记录总创建数量
    total_count: AtomicUsize,
}

/// 活动代理的内部状态
#[derive(Default)]
struct ActiveAgents {
    /// 当前活动的线程 ID 集合
    threads_set: HashSet<ThreadId>,
    /// 线程 ID 到昵称的映射
    thread_agent_nicknames: HashMap<ThreadId, String>,
    /// 已使用的昵称集合
    used_agent_nicknames: HashSet<String>,
    /// 昵称池重置计数（用于生成序数后缀）
    nickname_reset_count: usize,
}

/// 预留的 spawn 槽位，实现 RAII 模式
pub(crate) struct SpawnReservation {
    state: Arc<Guards>,
    active: bool,
    reserved_agent_nickname: Option<String>,
}
```

### 线程数量限制算法

#### 预留槽位

```rust
pub(crate) fn reserve_spawn_slot(
    self: &Arc<Self>,
    max_threads: Option<usize>,
) -> Result<SpawnReservation> {
    if let Some(max_threads) = max_threads {
        // 有配置限制时，使用 CAS 循环尝试增加计数
        if !self.try_increment_spawned(max_threads) {
            return Err(CodexErr::AgentLimitReached { max_threads });
        }
    } else {
        // 无限制时，直接原子增加
        self.total_count.fetch_add(1, Ordering::AcqRel);
    }
    Ok(SpawnReservation {
        state: Arc::clone(self),
        active: true,
        reserved_agent_nickname: None,
    })
}

fn try_increment_spawned(&self, max_threads: usize) -> bool {
    let mut current = self.total_count.load(Ordering::Acquire);
    loop {
        if current >= max_threads {
            return false;
        }
        match self.total_count.compare_exchange_weak(
            current,
            current + 1,
            Ordering::AcqRel,
            Ordering::Acquire,
        ) {
            Ok(_) => return true,
            Err(updated) => current = updated,
        }
    }
}
```

#### 释放槽位

```rust
pub(crate) fn release_spawned_thread(&self, thread_id: ThreadId) {
    let removed = {
        let mut active_agents = self.active_agents.lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let removed = active_agents.threads_set.remove(&thread_id);
        active_agents.thread_agent_nicknames.remove(&thread_id);
        removed
    };
    if removed {
        self.total_count.fetch_sub(1, Ordering::AcqRel);
    }
}
```

### 昵称分配算法

#### 格式化和序数后缀

```rust
fn format_agent_nickname(name: &str, nickname_reset_count: usize) -> String {
    match nickname_reset_count {
        0 => name.to_string(),
        reset_count => {
            let value = reset_count + 1;
            let suffix = match value % 100 {
                11..=13 => "th",
                _ => match value % 10 {
                    1 => "st",
                    2 => "nd",
                    3 => "rd",
                    _ => "th",
                },
            };
            format!("{name} the {value}{suffix}")
        }
    }
}
```

#### 预留昵称

```rust
fn reserve_agent_nickname(&self, names: &[&str], preferred: Option<&str>) -> Option<String> {
    let mut active_agents = self.active_agents.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    
    let agent_nickname = if let Some(preferred) = preferred {
        // 恢复场景：使用存储的偏好昵称
        preferred.to_string()
    } else {
        // 正常场景：从候选列表选择
        if names.is_empty() {
            return None;
        }
        
        // 过滤掉已使用的昵称
        let available_names: Vec<String> = names
            .iter()
            .map(|name| format_agent_nickname(name, active_agents.nickname_reset_count))
            .filter(|name| !active_agents.used_agent_nicknames.contains(name))
            .collect();
        
        if let Some(name) = available_names.choose(&mut rand::rng()) {
            name.clone()
        } else {
            // 昵称池耗尽，重置并增加计数
            active_agents.used_agent_nicknames.clear();
            active_agents.nickname_reset_count += 1;
            
            // 记录指标
            if let Some(metrics) = codex_otel::metrics::global() {
                let _ = metrics.counter("codex.multi_agent.nickname_pool_reset", 1, &[]);
            }
            
            format_agent_nickname(
                names.choose(&mut rand::rng())?,
                active_agents.nickname_reset_count,
            )
        }
    };
    
    active_agents.used_agent_nicknames.insert(agent_nickname.clone());
    Some(agent_nickname)
}
```

### 深度计算

```rust
fn session_depth(session_source: &SessionSource) -> i32 {
    match session_source {
        SessionSource::SubAgent(SubAgentSource::ThreadSpawn { depth, .. }) => *depth,
        SessionSource::SubAgent(_) => 0,
        _ => 0,
    }
}

pub(crate) fn next_thread_spawn_depth(session_source: &SessionSource) -> i32 {
    session_depth(session_source).saturating_add(1)
}

pub(crate) fn exceeds_thread_spawn_depth_limit(depth: i32, max_depth: i32) -> bool {
    depth > max_depth
}
```

### RAII 模式实现

`SpawnReservation` 使用 RAII 模式确保资源正确释放：

```rust
impl SpawnReservation {
    pub(crate) fn reserve_agent_nickname(&mut self, names: &[&str]) -> Result<String> {
        self.reserve_agent_nickname_with_preference(names, None)
    }
    
    pub(crate) fn reserve_agent_nickname_with_preference(
        &mut self,
        names: &[&str],
        preferred: Option<&str>,
    ) -> Result<String> {
        let agent_nickname = self.state.reserve_agent_nickname(names, preferred)
            .ok_or_else(|| CodexErr::UnsupportedOperation("no available agent nicknames".to_string()))?;
        self.reserved_agent_nickname = Some(agent_nickname.clone());
        Ok(agent_nickname)
    }
    
    pub(crate) fn commit(self, thread_id: ThreadId) {
        self.commit_with_agent_nickname(thread_id, None);
    }
    
    pub(crate) fn commit_with_agent_nickname(
        mut self,
        thread_id: ThreadId,
        agent_nickname: Option<String>,
    ) {
        let agent_nickname = self.reserved_agent_nickname.take().or(agent_nickname);
        self.state.register_spawned_thread(thread_id, agent_nickname);
        self.active = false;  // 防止 Drop 时释放计数
    }
}

impl Drop for SpawnReservation {
    fn drop(&mut self) {
        if self.active {
            // 预留但未提交，释放计数
            self.state.total_count.fetch_sub(1, Ordering::AcqRel);
        }
    }
}
```

## 关键代码路径与文件引用

### 主要结构体和函数

| 名称 | 位置 | 说明 |
|------|------|------|
| `Guards` | 第 21-24 行 | 主结构体 |
| `ActiveAgents` | 第 27-32 行 | 内部状态 |
| `SpawnReservation` | 第 178-182 行 | 预留槽位句柄 |
| `reserve_spawn_slot` | 第 70-86 行 | 预留 spawn 槽位 |
| `release_spawned_thread` | 第 88-101 行 | 释放线程 |
| `reserve_agent_nickname` | 第 119-157 行 | 预留昵称 |
| `try_increment_spawned` | 第 159-175 行 | CAS 增加计数 |
| `format_agent_nickname` | 第 34-51 行 | 格式化昵称 |
| `session_depth` | 第 53-59 行 | 计算会话深度 |
| `next_thread_spawn_depth` | 第 61-63 行 | 计算下一级深度 |
| `exceeds_thread_spawn_depth_limit` | 第 65-67 行 | 检查深度限制 |

### 导出接口

在 `mod.rs` 中导出：

```rust
pub(crate) use guards::exceeds_thread_spawn_depth_limit;
pub(crate) use guards::next_thread_spawn_depth;
```

## 依赖与外部交互

### 内部模块依赖

```rust
use crate::error::CodexErr;
use crate::error::Result;
```

### 外部 crate 依赖

```rust
use codex_protocol::ThreadId;
use codex_protocol::protocol::SessionSource;
use codex_protocol::protocol::SubAgentSource;
use rand::prelude::IndexedRandom;
use std::collections::HashMap;
use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::AtomicUsize;
use std::sync::atomic::Ordering;
```

### 与 control.rs 的交互

| Guards 方法 | 调用位置 | 用途 |
|-------------|----------|------|
| `reserve_spawn_slot` | `control.rs:106` | 创建代理前预留槽位 |
| `release_spawned_thread` | `control.rs:324`, `control.rs:340` | 关闭代理时释放槽位 |
| `reserve_agent_nickname` | `control.rs:123` | 为子代理分配昵称 |

## 风险、边界与改进建议

### 当前风险

1. **Mutex _poisoning**：
   - 使用 `Mutex` 保护 `active_agents`
   - 如果持有锁的线程 panic，锁会被污染
   - 当前使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 恢复，但可能丢失状态

2. **昵称泄露**：
   - 释放线程时，昵称从 `thread_agent_nicknames` 移除
   - 但 `used_agent_nicknames` 中仍然保留，导致昵称无法复用
   - 这是设计选择（避免混淆），但可能导致昵称快速耗尽

3. **原子操作顺序**：
   - `total_count` 使用 `Ordering::AcqRel`
   - `active_agents` 使用 `Mutex`
   - 两者之间没有严格的顺序保证，理论上可能出现不一致

4. **随机数生成**：
   - 使用 `rand::rng()` 获取线程本地 RNG
   - 在高并发下可能有性能影响

### 边界情况

1. **max_threads = 0**：
   - `try_increment_spawned` 会立即返回 false
   - 任何创建尝试都会失败

2. **空昵称列表**：
   - `reserve_agent_nickname` 返回 `None`
   - 调用者需要处理这种情况

3. **偏好昵称已使用**：
   - 恢复场景下，偏好昵称可能已被其他代理使用
   - 当前实现直接使用偏好昵称，可能导致重复

4. **昵称池多次重置**：
   - `nickname_reset_count` 可以无限增长
   - 昵称会变成 "Plato the 999th" 这样的形式

### 改进建议

1. **使用 RwLock 替代 Mutex**：
   - 读操作远多于写操作
   - `RwLock` 可以提高并发性能

2. **昵称复用策略**：
   - 添加配置选项，允许在代理关闭后复用昵称
   - 或者添加昵称过期机制

3. **更严格的顺序保证**：
   - 考虑使用 `parking_lot` crate 的锁实现
   - 或者使用无锁数据结构

4. **偏好昵称冲突处理**：
   - 如果偏好昵称已使用，尝试添加后缀
   - 或者返回错误让调用者决定

5. **深度限制集成**：
   - 当前只提供检查函数，实际限制在调用方实现
   - 考虑将深度限制集成到 `Guards` 中

6. **指标和可观测性**：
   - 添加更多指标：当前活动代理数、昵称池大小等
   - 导出 Prometheus 格式的指标

7. **测试增强**：
   - 添加并发压力测试
   - 测试 Mutex poisoning 恢复
   - 测试昵称池多次重置的场景
