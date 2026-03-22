# file_watcher_tests.rs 研究文档

## 场景与职责

本文件是 `file_watcher.rs` 模块的单元测试文件，负责验证文件监视器的核心行为。测试覆盖以下关键场景：

1. **节流逻辑**：验证事件节流器的合并和定时行为
2. **事件分类**：验证文件系统事件的正确分类和过滤
3. **引用计数**：验证目录注册/注销的引用计数机制
4. **RAII 资源管理**：验证 `WatchRegistration` 的自动清理
5. **并发安全**：验证多线程环境下的锁行为
6. **关闭刷新**：验证关闭时 pending 事件的刷新

## 功能点目的

### 1. 节流逻辑测试

**测试目标**：验证 `ThrottledPaths` 的节流行为

| 测试函数 | 验证内容 |
|---------|---------|
| `throttles_and_coalesces_within_interval` | 10秒窗口内的事件合并，窗口结束后统一发送 |
| `flushes_pending_on_shutdown` | 关闭时立即刷新 pending 事件，不等待窗口 |

关键验证点：
- 首次事件立即发送
- 窗口期内事件被合并
- 窗口结束后批量发送
- 关闭时强制刷新

### 2. 事件分类测试

**测试目标**：验证 `classify_event` 函数的行为

| 测试函数 | 验证内容 |
|---------|---------|
| `classify_event_filters_to_skills_roots` | 只返回属于技能根目录的路径 |
| `classify_event_supports_multiple_roots_without_prefix_false_positives` | 多根目录场景，避免前缀误判 |
| `classify_event_ignores_non_mutating_event_kinds` | 忽略 Access、Any、Other 等非变更事件 |

事件类型处理：
- ✅ `Create` / `Modify` / `Remove`：处理
- ❌ `Access`：忽略
- ❌ `Any` / `Other`：忽略

### 3. 引用计数测试

**测试目标**：验证 `WatchState` 的引用计数

| 测试函数 | 验证内容 |
|---------|---------|
| `register_skills_root_dedupes_state_entries` | 同一目录多次注册，引用计数递增 |

### 4. RAII 资源管理测试

**测试目标**：验证 `WatchRegistration` 的 Drop 行为

| 测试函数 | 验证内容 |
|---------|---------|
| `watch_registration_drop_unregisters_roots` | Drop 时自动注销所有根目录 |

### 5. 并发安全测试

**测试目标**：验证锁的正确使用

| 测试函数 | 验证内容 |
|---------|---------|
| `unregister_holds_state_lock_until_unwatch_finishes` | 注销时持有 state 锁直到 unwatch 完成 |

测试方法：
- 主线程获取 `inner` 锁
- 启动注销线程，验证其等待 state 锁
- 启动注册线程，验证其等待
- 释放锁后验证两个线程完成
- 最终状态验证引用计数和监视路径

### 6. 关闭刷新测试

**测试目标**：验证关闭时的事件刷新

| 测试函数 | 验证内容 |
|---------|---------|
| `spawn_event_loop_flushes_pending_changes_on_shutdown` | 关闭时发送 pending 的变更事件 |

测试流程：
1. 创建 noop watcher 和模拟状态
2. 启动事件循环
3. 发送第一个事件，验证立即收到
4. 发送第二个事件后立即关闭通道
5. 验证第二个事件在关闭前被刷新发送

## 具体技术实现

### 测试辅助函数

```rust
// 快速创建 PathBuf
fn path(name: &str) -> PathBuf {
    PathBuf::from(name)
}

// 创建 notify Event
fn notify_event(kind: EventKind, paths: Vec<PathBuf>) -> Event {
    let mut event = Event::new(kind);
    for path in paths {
        event = event.add_path(path);
    }
    event
}
```

### 节流测试详解

```rust
#[test]
fn throttles_and_coalesces_within_interval() {
    let start = Instant::now();
    let mut throttled = ThrottledPaths::new(start);

    // 首次事件立即发送
    throttled.add(vec![path("a")]);
    let first = throttled.take_ready(start).expect("first emit");
    assert_eq!(first, vec![path("a")]);

    // 窗口期内事件不发送
    throttled.add(vec![path("b"), path("c")]);
    assert_eq!(throttled.take_ready(start), None);

    // 窗口结束后批量发送
    let second = throttled
        .take_ready(start + WATCHER_THROTTLE_INTERVAL)
        .expect("coalesced emit");
    assert_eq!(second, vec![path("b"), path("c")]);
}
```

### 多根目录分类测试

```rust
#[test]
fn classify_event_supports_multiple_roots_without_prefix_false_positives() {
    let root_a = path("/tmp/skills");
    let root_b = path("/tmp/workspace/.codex/skills");
    let state = RwLock::new(WatchState {
        skills_root_ref_counts: HashMap::from([
            (root_a.clone(), 1),
            (root_b.clone(), 1),
        ]),
    });
    
    // /tmp/skills-extra 不应被误判为 /tmp/skills 的子目录
    let event = notify_event(
        EventKind::Modify(ModifyKind::Any),
        vec![
            root_a.join("alpha/SKILL.md"),
            path("/tmp/skills-extra/not-under-skills.txt"),  // 应被过滤
            root_b.join("beta/SKILL.md"),
        ],
    );

    let classified = classify_event(&event, &state);
    assert_eq!(
        classified,
        vec![root_a.join("alpha/SKILL.md"), root_b.join("beta/SKILL.md")]
    );
}
```

### 并发测试详解

```rust
#[test]
fn unregister_holds_state_lock_until_unwatch_finishes() {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let root = temp_dir.path().join("skills");
    std::fs::create_dir(&root).expect("create root");

    let watcher = Arc::new(FileWatcher::new(temp_dir.path().to_path_buf()).expect("watcher"));
    watcher.register_skills_root(root.clone());

    // 主线程获取 inner 锁
    let inner = watcher.inner.as_ref().expect("watcher inner");
    let inner_guard = inner.lock().expect("inner lock");

    // 启动注销线程
    let unregister_watcher = Arc::clone(&watcher);
    let unregister_root = root.clone();
    let unregister_thread = std::thread::spawn(move || {
        unregister_watcher.unregister_roots(&[unregister_root]);
    });

    // 验证注销线程正在等待 state 锁
    let state_lock_observed = (0..100).any(|_| {
        let locked = watcher.state.try_write().is_err();
        if !locked {
            std::thread::sleep(Duration::from_millis(10));
        }
        locked
    });
    assert_eq!(state_lock_observed, true);

    // 启动注册线程
    let register_watcher = Arc::clone(&watcher);
    let register_root = root.clone();
    let register_thread = std::thread::spawn(move || {
        register_watcher.register_skills_root(register_root);
    });

    // 释放锁，让两个线程完成
    drop(inner_guard);

    unregister_thread.join().expect("unregister join");
    register_thread.join().expect("register join");

    // 验证最终状态
    let state = watcher.state.read().expect("state lock");
    assert_eq!(state.skills_root_ref_counts.get(&root), Some(&1));
}
```

### 异步事件循环测试

```rust
#[tokio::test]
async fn spawn_event_loop_flushes_pending_changes_on_shutdown() {
    let watcher = FileWatcher::noop();
    let root = path("/tmp/skills");
    {
        let mut state = watcher.state.write().expect("state lock");
        state.skills_root_ref_counts.insert(root.clone(), 1);
    }

    let (raw_tx, raw_rx) = mpsc::unbounded_channel();
    let (tx, mut rx) = broadcast::channel(8);
    watcher.spawn_event_loop(raw_rx, Arc::clone(&watcher.state), tx);

    // 发送第一个事件
    raw_tx.send(Ok(notify_event(
        EventKind::Create(CreateKind::File),
        vec![root.join("a/SKILL.md")],
    ))).expect("send first event");
    
    let first = timeout(Duration::from_secs(2), rx.recv())
        .await
        .expect("first watcher event")
        .expect("broadcast recv first");
    assert_eq!(first, FileWatcherEvent::SkillsChanged {
        paths: vec![root.join("a/SKILL.md")]
    });

    // 发送第二个事件后立即关闭
    raw_tx.send(Ok(notify_event(
        EventKind::Remove(RemoveKind::File),
        vec![root.join("b/SKILL.md")],
    ))).expect("send second event");
    drop(raw_tx);  // 关闭通道

    // 验证第二个事件被刷新发送
    let second = timeout(Duration::from_secs(2), rx.recv())
        .await
        .expect("second watcher event")
        .expect("broadcast recv second");
    assert_eq!(second, FileWatcherEvent::SkillsChanged {
        paths: vec![root.join("b/SKILL.md")]
    });
}
```

## 关键代码路径与文件引用

### 被测试的核心组件

| 测试函数 | 被测组件/方法 |
|---------|--------------|
| `throttles_*` | `ThrottledPaths` |
| `classify_event_*` | `classify_event()` |
| `register_skills_root_*` | `FileWatcher::register_skills_root()` |
| `watch_registration_*` | `WatchRegistration::drop()` |
| `unregister_*` | `FileWatcher::unregister_roots()` |
| `spawn_event_loop_*` | `FileWatcher::spawn_event_loop()` |

### 测试使用的 notify 事件类型

```rust
use notify::EventKind;
use notify::event::AccessKind;
use notify::event::AccessMode;
use notify::event::CreateKind;
use notify::event::ModifyKind;
use notify::event::RemoveKind;
```

### 测试依赖

| 依赖 | 用途 |
|-----|------|
| `pretty_assertions::assert_eq` | 清晰的断言差异 |
| `tokio::time::timeout` | 异步测试超时 |
| `tempfile::tempdir` | 临时目录 |

## 依赖与外部交互

### 被测模块的依赖

| 依赖 | 在测试中的使用 |
|-----|--------------|
| `notify` | 创建模拟事件 |
| `tokio::sync::{broadcast, mpsc}` | 测试事件循环 |
| `std::sync::{Arc, RwLock}` | 状态管理 |

### 测试隔离策略

1. **时间控制**：使用 `Instant` 和固定时间间隔，不依赖真实时间
2. **Noop Watcher**：使用 `FileWatcher::noop()` 避免实际文件系统操作
3. **临时目录**：并发测试使用 `tempfile::tempdir()` 创建隔离目录
4. **通道模拟**：使用 `mpsc` 通道模拟 notify 事件

## 风险、边界与改进建议

### 当前风险点

1. **硬编码路径**：测试中使用 `/tmp/skills` 等路径，在 Windows 上可能失败
2. **超时依赖**：异步测试依赖 2 秒超时，在慢机器上可能 flaky
3. **notify 版本依赖**：测试直接构造 `notify::Event`，与 notify crate API 耦合

### 边界情况覆盖

| 边界情况 | 覆盖状态 |
|---------|---------|
| 空 pending 集合 | ✅ `take_ready` 返回 None |
| 单一路径 | ✅ 基础测试覆盖 |
| 多路径合并 | ✅ `throttles_and_coalesces_within_interval` |
| 非变更事件 | ✅ `classify_event_ignores_non_mutating_event_kinds` |
| 多根目录 | ✅ `classify_event_supports_multiple_roots_*` |
| 前缀误判 | ✅ 同上 |
| 并发注销/注册 | ✅ `unregister_holds_state_lock_*` |
| 关闭刷新 | ✅ `spawn_event_loop_flushes_pending_*` |

### 未覆盖场景

| 场景 | 建议测试 |
|-----|---------|
| 实际文件系统变化 | 集成测试（需要实际文件操作） |
| 大目录树性能 | 性能基准测试 |
| 长时间运行稳定性 | 压力测试 |
| 错误事件处理 | `raw_tx.send(Err(...))` 场景 |
| 广播通道溢出 | 128+ 事件快速发送 |

### 改进建议

1. **跨平台路径**：
   ```rust
   #[cfg(unix)]
   const TEST_ROOT: &str = "/tmp/skills";
   #[cfg(windows)]
   const TEST_ROOT: &str = "C:\\temp\\skills";
   ```

2. **参数化测试**：
   使用 `test_case` crate 参数化节流间隔测试

3. **Mock Notify**：
   抽象 `notify::Event` 构造，降低与 notify crate 的耦合

4. **并发测试增强**：
   ```rust
   #[test]
   fn concurrent_register_unregister_is_safe() {
       // 多线程并发注册/注销同一目录
   }
   ```

5. **错误路径测试**：
   ```rust
   #[tokio::test]
   async fn event_loop_handles_notify_errors() {
       // 验证 notify 错误被正确记录和处理
   }
   ```
