# guards_tests.rs 研究文档

## 场景与职责

`guards_tests.rs` 是 `guards.rs` 的配套测试模块，包含 14 个单元测试，全面验证 `Guards` 和 `SpawnReservation` 的功能。测试覆盖以下核心场景：

1. **昵称格式化测试**：验证序数后缀的正确生成
2. **深度计算测试**：验证会话深度计算和限制检查
3. **预留槽位测试**：验证预留-提交-释放的生命周期
4. **资源限制测试**：验证 max_threads 限制的强制执行
5. **昵称分配测试**：验证昵称池管理和重置逻辑
6. **边界情况测试**：验证异常输入的处理

## 功能点目的

### 1. 昵称格式化测试
- `format_agent_nickname_adds_ordinals_after_reset`: 验证序数后缀生成规则

### 2. 深度计算测试
- `session_depth_defaults_to_zero_for_root_sources`: 验证根会话深度为 0
- `thread_spawn_depth_increments_and_enforces_limit`: 验证深度递增和限制
- `non_thread_spawn_subagents_default_to_depth_zero`: 验证非 ThreadSpawn 类型深度为 0

### 3. 预留槽位测试
- `reservation_drop_releases_slot`: 验证 RAII 释放机制
- `commit_holds_slot_until_release`: 验证提交后槽位保持
- `release_ignores_unknown_thread_id`: 验证释放未知 ID 的安全处理
- `release_is_idempotent_for_registered_threads`: 验证释放的幂等性

### 4. 昵称分配测试
- `failed_spawn_keeps_nickname_marked_used`: 验证失败 spawn 的昵称保持占用
- `agent_nickname_resets_used_pool_when_exhausted`: 验证昵称池耗尽重置
- `released_nickname_stays_used_until_pool_reset`: 验证释放昵称保持占用
- `repeated_resets_advance_the_ordinal_suffix`: 验证多次重置的序数递增

## 具体技术实现

### 测试组织结构

测试模块使用标准 Rust 测试组织：

```rust
#[cfg(test)]
#[path = "guards_tests.rs"]
mod tests;
```

所有测试都是简单的单元测试，不需要异步运行时。

### 关键测试详解

#### 1. 昵称格式化测试

```rust
#[test]
fn format_agent_nickname_adds_ordinals_after_reset() {
    assert_eq!(format_agent_nickname("Plato", 0), "Plato");
    assert_eq!(format_agent_nickname("Plato", 1), "Plato the 2nd");
    assert_eq!(format_agent_nickname("Plato", 2), "Plato the 3rd");
    assert_eq!(format_agent_nickname("Plato", 10), "Plato the 11th");
    assert_eq!(format_agent_nickname("Plato", 20), "Plato the 21st");
}
```

测试覆盖：
- 重置计数为 0：无后缀
- 重置计数为 1："the 2nd"
- 重置计数为 2："the 3rd"
- 特殊规则（11-13）："the 11th"（不是 "11st"）
- 个位数规则（1, 2, 3）："the 21st"

#### 2. 深度计算测试

```rust
#[test]
fn thread_spawn_depth_increments_and_enforces_limit() {
    let session_source = SessionSource::SubAgent(SubAgentSource::ThreadSpawn {
        parent_thread_id: ThreadId::new(),
        depth: 1,
        agent_nickname: None,
        agent_role: None,
    });
    let child_depth = next_thread_spawn_depth(&session_source);
    assert_eq!(child_depth, 2);
    assert!(exceeds_thread_spawn_depth_limit(child_depth, 1));
}
```

测试验证：
- 当前深度为 1 时，子代理深度为 2
- 最大深度为 1 时，深度 2 超过限制

#### 3. 预留槽位测试

```rust
#[test]
fn reservation_drop_releases_slot() {
    let guards = Arc::new(Guards::default());
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("reserve slot");
    drop(reservation);  // 未提交，应该释放槽位
    
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("slot released");
    drop(reservation);
}
```

验证 RAII 模式：
- 预留槽位但未提交
- Drop 时自动释放
- 可以再次预留

#### 4. 提交和释放测试

```rust
#[test]
fn commit_holds_slot_until_release() {
    let guards = Arc::new(Guards::default());
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("reserve slot");
    let thread_id = ThreadId::new();
    reservation.commit(thread_id);  // 提交后槽位被占用
    
    // 尝试预留第二个槽位应该失败
    let err = match guards.reserve_spawn_slot(Some(1)) {
        Ok(_) => panic!("limit should be enforced"),
        Err(err) => err,
    };
    let CodexErr::AgentLimitReached { max_threads } = err else {
        panic!("expected CodexErr::AgentLimitReached");
    };
    assert_eq!(max_threads, 1);
    
    // 释放后可以再次预留
    guards.release_spawned_thread(thread_id);
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("slot released after thread removal");
    drop(reservation);
}
```

验证完整生命周期：
- 预留并提交，槽位被占用
- 再次预留失败，返回 `AgentLimitReached`
- 释放后可以再次预留

#### 5. 释放幂等性测试

```rust
#[test]
fn release_is_idempotent_for_registered_threads() {
    let guards = Arc::new(Guards::default());
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("reserve slot");
    let first_id = ThreadId::new();
    reservation.commit(first_id);
    
    guards.release_spawned_thread(first_id);  // 第一次释放
    
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("slot reused");
    let second_id = ThreadId::new();
    reservation.commit(second_id);
    
    guards.release_spawned_thread(first_id);  // 重复释放第一个 ID，应该无影响
    
    // 槽位仍然被占用
    let err = match guards.reserve_spawn_slot(Some(1)) {
        Ok(_) => panic!("limit should still be enforced"),
        Err(err) => err,
    };
    let CodexErr::AgentLimitReached { max_threads } = err else {
        panic!("expected CodexErr::AgentLimitReached");
    };
    assert_eq!(max_threads, 1);
    
    // 释放第二个 ID 后才能真正释放
    guards.release_spawned_thread(second_id);
    let reservation = guards.reserve_spawn_slot(Some(1)).expect("slot released after second thread removal");
    drop(reservation);
}
```

验证：
- 释放已释放的 ID 不会导致计数错误
- 只有实际注册的 ID 释放才有效

#### 6. 昵称池重置测试

```rust
#[test]
fn agent_nickname_resets_used_pool_when_exhausted() {
    let guards = Arc::new(Guards::default());
    let mut first = guards.reserve_spawn_slot(None).expect("reserve first slot");
    let first_name = first.reserve_agent_nickname(&["alpha"])
        .expect("reserve first agent name");
    let first_id = ThreadId::new();
    first.commit(first_id);
    assert_eq!(first_name, "alpha");
    
    // 所有昵称都被使用，应该触发重置
    let mut second = guards.reserve_spawn_slot(None).expect("reserve second slot");
    let second_name = second.reserve_agent_nickname(&["alpha"])
        .expect("name should be reused after pool reset");
    assert_eq!(second_name, "alpha the 2nd");
    
    let active_agents = guards.active_agents.lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    assert_eq!(active_agents.nickname_reset_count, 1);
}
```

验证昵称池重置逻辑：
- 只有一个候选昵称 "alpha"
- 第一个代理使用 "alpha"
- 第二个代理触发重置，使用 "alpha the 2nd"
- `nickname_reset_count` 增加到 1

#### 7. 释放昵称保持占用测试

```rust
#[test]
fn released_nickname_stays_used_until_pool_reset() {
    let guards = Arc::new(Guards::default());
    
    let mut first = guards.reserve_spawn_slot(None).expect("reserve first slot");
    let first_name = first.reserve_agent_nickname(&["alpha"])
        .expect("reserve first agent name");
    let first_id = ThreadId::new();
    first.commit(first_id);
    assert_eq!(first_name, "alpha");
    
    guards.release_spawned_thread(first_id);  // 释放线程
    
    // 昵称仍然被标记为已使用
    let mut second = guards.reserve_spawn_slot(None).expect("reserve second slot");
    let second_name = second.reserve_agent_nickname(&["alpha", "beta"])
        .expect("released name should still be marked used");
    assert_eq!(second_name, "beta");
    
    // ... 继续测试直到触发重置
}
```

验证设计决策：
- 即使线程释放，昵称仍然被标记为已使用
- 避免昵称复用导致的混淆
- 只有昵称池重置后才能复用

## 关键代码路径与文件引用

### 测试函数列表

| 测试函数 | 行号 | 测试目的 |
|----------|------|----------|
| `format_agent_nickname_adds_ordinals_after_reset` | 6-12 | 序数后缀生成 |
| `session_depth_defaults_to_zero_for_root_sources` | 15-17 | 根会话深度 |
| `thread_spawn_depth_increments_and_enforces_limit` | 20-30 | 深度递增和限制 |
| `non_thread_spawn_subagents_default_to_depth_zero` | 33-38 | 非 ThreadSpawn 深度 |
| `reservation_drop_releases_slot` | 41-48 | RAII 释放 |
| `commit_holds_slot_until_release` | 51-71 | 提交保持槽位 |
| `release_ignores_unknown_thread_id` | 74-96 | 释放未知 ID |
| `release_is_idempotent_for_registered_threads` | 99-127 | 释放幂等性 |
| `failed_spawn_keeps_nickname_marked_used` | 130-144 | 失败 spawn 昵称保持 |
| `agent_nickname_resets_used_pool_when_exhausted` | 147-169 | 昵称池重置 |
| `released_nickname_stays_used_until_pool_reset` | 172-207 | 释放昵称保持 |
| `repeated_resets_advance_the_ordinal_suffix` | 210-243 | 多次重置 |

### 依赖

```rust
use super::*;  // 导入 guards.rs 的所有内容
use pretty_assertions::assert_eq;
use std::collections::HashSet;
```

## 依赖与外部交互

### 内部模块依赖

- `guards.rs`: 被测模块的所有导出内容

### 外部 crate 依赖

- `pretty_assertions`: 提供更清晰的断言失败输出

### 测试框架

- 使用标准 Rust 测试框架（`#[test]`）
- 同步测试，不需要 tokio 运行时

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不完整**：
   - 没有测试 `max_threads = None` 的场景
   - 没有测试并发预留槽位的竞争条件
   - 没有测试 `Mutex` poisoning 的恢复

2. **硬编码值**：
   - 测试使用硬编码的昵称列表和限制值
   - 可能错过边界值问题

3. **随机性测试不足**：
   - `reserve_agent_nickname` 使用随机选择
   - 测试可能偶尔通过或失败（虽然概率很低）

### 边界情况

1. **空昵称列表**：
   - 没有测试空列表的处理
   - `reserve_agent_nickname` 会返回 `None`

2. **大量重置**：
   - 测试最多到 2 次重置
   - 没有测试 `nickname_reset_count` 溢出的情况

3. **深度限制边界**：
   - 测试 `depth > max_depth`
   - 没有测试 `depth == max_depth`（应该允许）

### 改进建议

1. **增加并发测试**：
   ```rust
   #[test]
   fn concurrent_reservations_respect_limit() {
       use std::thread;
       let guards = Arc::new(Guards::default());
       let mut handles = vec![];
       
       for _ in 0..10 {
           let guards = Arc::clone(&guards);
           handles.push(thread::spawn(move || {
               guards.reserve_spawn_slot(Some(5))
           }));
       }
       
       let results: Vec<_> = handles.into_iter()
           .map(|h| h.join().unwrap())
           .collect();
       
       // 验证最多 5 个成功
       let success_count = results.iter().filter(|r| r.is_ok()).count();
       assert_eq!(success_count, 5);
   }
   ```

2. **增加属性测试**：
   - 使用 `proptest` 生成随机输入
   - 验证昵称格式化的各种边界

3. **增加边界值测试**：
   ```rust
   #[test]
   fn max_threads_zero_blocks_all() {
       let guards = Arc::new(Guards::default());
       let result = guards.reserve_spawn_slot(Some(0));
       assert!(matches!(result, Err(CodexErr::AgentLimitReached { max_threads: 0 })));
   }
   
   #[test]
   fn depth_at_limit_is_allowed() {
       assert!(!exceeds_thread_spawn_depth_limit(5, 5));  // 等于应该允许
       assert!(exceeds_thread_spawn_depth_limit(6, 5));   // 超过应该拒绝
   }
   ```

4. **测试 Mutex poisoning**：
   ```rust
   #[test]
   fn recovers_from_mutex_poisoning() {
       let guards = Arc::new(Guards::default());
       let guards_clone = Arc::clone(&guards);
       
       // 在一个线程中 panic 以污染锁
       let _ = std::panic::catch_unwind(move || {
           let _lock = guards_clone.active_agents.lock().unwrap();
           panic!("intentional panic");
       });
       
       // 验证后续操作仍然可以工作
       let result = guards.reserve_spawn_slot(Some(1));
       assert!(result.is_ok());
   }
   ```

5. **使用参数化测试**：
   - 使用 `rstest` crate 减少重复代码
   - 测试多种配置组合

6. **添加性能测试**：
   - 测量高并发下的预留性能
   - 检测性能回归
