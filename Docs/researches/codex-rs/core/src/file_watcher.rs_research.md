# file_watcher.rs 研究文档

## 场景与职责

本文件实现了一个基于 `notify` crate 的文件系统监视器，专门用于监视 Skill 根目录的变化。核心职责包括：

1. **技能目录监视**：递归监视技能根目录的文件变化
2. **事件节流**：对高频文件变化事件进行 10 秒节流，避免频繁触发
3. **引用计数管理**：支持多个消费者注册/注销同一目录的监视
4. **异步事件广播**：通过 Tokio broadcast channel 向订阅者发送变化通知
5. **生命周期管理**：通过 `WatchRegistration` RAII 模式自动清理资源

## 功能点目的

### 1. 文件监视核心 (`FileWatcher`)

```rust
pub(crate) struct FileWatcher {
    inner: Option<Mutex<FileWatcherInner>>,  // None 表示 noop 模式
    state: Arc<RwLock<WatchState>>,          // 引用计数状态
    tx: broadcast::Sender<FileWatcherEvent>, // 事件广播通道
}
```

主要方法：
- `new(codex_home)`：创建实际的文件监视器
- `noop()`：创建无操作模式（用于测试或禁用场景）
- `subscribe()`：订阅文件变化事件
- `register_config()`：基于 Config 和 SkillsManager 注册监视

### 2. 引用计数管理 (`WatchState`)

```rust
struct WatchState {
    skills_root_ref_counts: HashMap<PathBuf, usize>,
}
```

- 同一目录可被多次注册，引用计数递增
- 注销时引用计数递减，归零时停止监视
- 使用 `RwLock` 支持并发读写

### 3. 事件节流 (`ThrottledPaths`)

```rust
const WATCHER_THROTTLE_INTERVAL: Duration = Duration::from_secs(10);

struct ThrottledPaths {
    pending: HashSet<PathBuf>,
    next_allowed_at: Instant,
}
```

- 合并 10 秒窗口内的所有变化路径
- 使用 `HashSet` 自动去重
- 支持立即刷新（`take_pending`）用于关闭场景

### 4. RAII 资源管理 (`WatchRegistration`)

```rust
pub(crate) struct WatchRegistration {
    file_watcher: std::sync::Weak<FileWatcher>,
    roots: Vec<PathBuf>,
}

impl Drop for WatchRegistration {
    fn drop(&mut self) {
        if let Some(file_watcher) = self.file_watcher.upgrade() {
            file_watcher.unregister_roots(&self.roots);
        }
    }
}
```

- 注册时返回 `WatchRegistration`，持有弱引用避免循环引用
- Drop 时自动注销所有根目录

### 5. 事件分类 (`classify_event`)

```rust
fn classify_event(event: &Event, state: &RwLock<WatchState>) -> Vec<PathBuf>
```

- 过滤非变更事件（Access、Any、Other）
- 只关注 Create、Modify、Remove 事件
- 返回属于技能目录的路径列表

## 具体技术实现

### 事件循环架构

```
notify::recommended_watcher (OS 原生)
    ↓ callback
mpsc::unbounded_channel (跨线程)
    ↓ async recv
spawn_event_loop (Tokio task)
    ↓ classify
ThrottledPaths (节流)
    ↓ broadcast
broadcast::channel (128 容量)
    ↓ subscribe
订阅者 (SkillsManager 等)
```

### 节流器实现细节

```rust
impl ThrottledPaths {
    fn add(&mut self, paths: Vec<PathBuf>) {
        self.pending.extend(paths);
    }

    fn next_deadline(&self, now: Instant) -> Option<Instant> {
        (!self.pending.is_empty() && now < self.next_allowed_at)
            .then_some(self.next_allowed_at)
    }

    fn take_ready(&mut self, now: Instant) -> Option<Vec<PathBuf>> {
        if self.pending.is_empty() || now < self.next_allowed_at {
            return None;
        }
        Some(self.take_with_next_allowed(now))
    }

    fn take_with_next_allowed(&mut self, now: Instant) -> Vec<PathBuf> {
        let mut paths: Vec<PathBuf> = self.pending.drain().collect();
        paths.sort_unstable_by(|a, b| a.as_os_str().cmp(b.as_os_str()));
        self.next_allowed_at = now + WATCHER_THROTTLE_INTERVAL;
        paths
    }
}
```

### 事件循环逻辑

```rust
fn spawn_event_loop(...) {
    handle.spawn(async move {
        let now = Instant::now();
        let mut skills = ThrottledPaths::new(now);

        loop {
            let now = Instant::now();
            let next_deadline = skills.next_deadline(now);
            let timer_deadline = next_deadline
                .unwrap_or_else(|| now + Duration::from_secs(60 * 60 * 24 * 365));
            let timer = sleep_until(timer_deadline);
            tokio::pin!(timer);

            tokio::select! {
                res = raw_rx.recv() => {
                    match res {
                        Some(Ok(event)) => {
                            let skills_paths = classify_event(&event, &state);
                            skills.add(skills_paths);
                            if let Some(paths) = skills.take_ready(now) {
                                let _ = tx.send(FileWatcherEvent::SkillsChanged { paths });
                            }
                        }
                        Some(Err(err)) => warn!("file watcher error: {err}"),
                        None => {
                            // 关闭前刷新
                            if let Some(paths) = skills.take_pending(now) {
                                let _ = tx.send(FileWatcherEvent::SkillsChanged { paths });
                            }
                            break;
                        }
                    }
                }
                _ = &mut timer => {
                    if let Some(paths) = skills.take_ready(now) {
                        let _ = tx.send(FileWatcherEvent::SkillsChanged { paths });
                    }
                }
            }
        }
    });
}
```

### 引用计数注册/注销

```rust
fn register_skills_root(&self, root: PathBuf) {
    let mut state = self.state.write().unwrap_or_else(...);
    let count = state.skills_root_ref_counts.entry(root.clone()).or_insert(0);
    *count += 1;
    if *count == 1 {
        self.watch_path(root, RecursiveMode::Recursive);
    }
}

fn unregister_roots(&self, roots: &[PathBuf]) {
    let mut state = self.state.write().unwrap_or_else(...);
    for root in roots {
        if let Some(count) = state.skills_root_ref_counts.get_mut(root) {
            if *count > 1 {
                *count -= 1;
            } else {
                state.skills_root_ref_counts.remove(root);
                // ... 停止监视
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 核心结构

| 结构/枚举 | 职责 |
|----------|------|
| `FileWatcher` | 主监视器，管理生命周期 |
| `FileWatcherInner` | 内部状态（watcher 实例、已监视路径） |
| `WatchState` | 引用计数状态 |
| `ThrottledPaths` | 节流状态 |
| `WatchRegistration` | RAII 注册句柄 |
| `FileWatcherEvent` | 事件类型 |

### 事件类型

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileWatcherEvent {
    SkillsChanged { paths: Vec<PathBuf> },
}
```

### 调用方

| 调用方 | 用途 |
|-------|------|
| `SkillsManager` | 注册技能目录监视，响应变化重载技能 |
| `Config` 初始化 | 在应用启动时设置监视 |

### 关键方法

| 方法 | 可见性 | 职责 |
|-----|-------|------|
| `new()` | `pub(crate)` | 创建监视器 |
| `noop()` | `pub(crate)` | 创建无操作实例 |
| `subscribe()` | `pub(crate)` | 订阅事件 |
| `register_config()` | `pub(crate)` | 基于配置注册 |
| `register_skills_root()` | private | 注册技能根目录 |
| `unregister_roots()` | private | 注销根目录 |
| `watch_path()` | private | 开始监视路径 |
| `spawn_event_loop()` | private | 启动事件循环 |
| `classify_event()` | private | 分类事件 |

## 依赖与外部交互

### 外部 crate

| crate | 用途 |
|-------|------|
| `notify` | 跨平台文件系统监视 |
| `tokio` | 异步运行时、channel、time |
| `tracing` | 日志记录 |

### 内部模块

| 模块 | 用途 |
|-----|------|
| `config::Config` | 获取配置信息 |
| `skills::SkillsManager` | 获取技能根目录列表 |

### 平台抽象

使用 `notify::RecommendedWatcher`，自动选择平台最优实现：
- Linux: inotify
- macOS: FSEvents
- Windows: ReadDirectoryChangesW

## 风险、边界与改进建议

### 当前风险点

1. **Poisoned Lock 处理**：使用 `unwrap_or_else(std::sync::PoisonError::into_inner)` 在锁中毒时继续，可能隐藏问题
2. **广播通道容量**：128 容量在极端情况下可能溢出（`send` 使用 `let _ =` 忽略错误）
3. **路径排序开销**：每次节流刷新时对路径排序，大数据量时有开销

### 边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| 目录不存在 | `watch_path` 中检查 `path.exists()`，跳过不存在的路径 |
| 监视失败 | 记录警告日志，继续运行 |
| 重复注册同一目录 | 引用计数递增，不重复监视 |
| 关闭时 pending 事件 | `take_pending` 确保刷新 |
| 无 Tokio 运行时 | 记录警告，跳过事件循环 |

### 性能考量

1. **节流间隔**：10 秒是硬编码的，可能不适合所有场景
2. **递归监视**：使用 `RecursiveMode::Recursive`，大目录树可能有性能影响
3. **内存使用**：`ThrottledPaths` 使用 `HashSet` 去重，路径数量多时内存占用增加

### 改进建议

1. **可配置节流间隔**：
   ```rust
   pub struct FileWatcherConfig {
       pub throttle_interval: Duration,
       pub broadcast_capacity: usize,
   }
   ```

2. **事件类型细化**：
   当前只有 `SkillsChanged`，可细分为：
   ```rust
   pub enum FileWatcherEvent {
       SkillsCreated { paths: Vec<PathBuf> },
       SkillsModified { paths: Vec<PathBuf> },
       SkillsRemoved { paths: Vec<PathBuf> },
   }
   ```

3. **错误处理增强**：
   - 暴露监视错误给订阅者
   - 支持重试机制

4. **选择性递归**：
   支持非递归监视，由调用方决定监视深度

5. **指标集成**：
   增加遥测指标：
   - 监视目录数量
   - 事件处理延迟
   - 节流合并次数

6. **并发优化**：
   - 考虑使用 `parking_lot` 替代标准锁
   - 路径排序可延迟到实际需要时

### 测试覆盖

测试文件 `file_watcher_tests.rs` 覆盖：
- 节流逻辑
- 关闭刷新
- 事件分类
- 引用计数
- RAII 注销
- 并发注销/注册

建议增加：
- 大目录树性能测试
- 长时间运行稳定性测试
- 跨平台行为一致性测试
