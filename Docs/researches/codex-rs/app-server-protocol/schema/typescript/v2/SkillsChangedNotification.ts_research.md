# SkillsChangedNotification.ts 研究文档

## 场景与职责

`SkillsChangedNotification.ts` 定义了技能变更通知的数据结构，用于在监视的本地技能文件发生变化时通知客户端。这是 Codex 技能系统的实时更新机制，支持技能的热重载和动态发现。

## 功能点目的

该类型用于：
1. **变更检测**：检测技能文件的变化（创建、修改、删除）
2. **缓存失效**：通知客户端重新获取技能列表
3. **实时同步**：保持客户端技能列表与文件系统同步
4. **开发体验**：支持技能开发时的实时反馈

## 具体技术实现

### 数据结构定义

```typescript
/**
 * Notification emitted when watched local skill files change.
 *
 * Treat this as an invalidation signal and re-run `skills/list` with the
 * client's current parameters when refreshed skill metadata is needed.
 */
export type SkillsChangedNotification = Record<string, never>;
```

### 设计说明

`SkillsChangedNotification` 是一个空对象类型（`Record<string, never>`），这意味着：
1. **信号通知**：它只作为变更发生的信号，不包含具体变更详情
2. **缓存失效**：客户端收到后应视为缓存失效信号
3. **重新获取**：客户端需要重新调用 `skills/list` 获取最新技能列表
4. **简化设计**：避免复杂的变更差异计算和传输

### Rust 协议定义

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
/// Notification emitted when watched local skill files change.
///
/// Treat this as an invalidation signal and re-run `skills/list` with the
/// client's current parameters when refreshed skill metadata is needed.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub struct SkillsChangedNotification;
```

### 文件监视实现

在 `codex-rs/app-server/src/bespoke_event_handling.rs` 中：

```rust
use notify::{Watcher, RecursiveMode, DebouncedEvent};
use std::sync::mpsc::channel;
use std::time::Duration;

pub struct SkillWatcher {
    watcher: notify::RecommendedWatcher,
    watched_paths: HashSet<PathBuf>,
}

impl SkillWatcher {
    pub fn new() -> Result<Self, notify::Error> {
        let (tx, rx) = channel();
        let watcher = notify::watcher(tx, Duration::from_secs(2))?;
        
        // 启动监视循环
        std::thread::spawn(move || {
            loop {
                match rx.recv() {
                    Ok(event) => handle_skill_event(event),
                    Err(e) => error!("Watch error: {:?}", e),
                }
            }
        });
        
        Ok(Self {
            watcher,
            watched_paths: HashSet::new(),
        })
    }
    
    pub fn watch_skill_root(&mut self, path: &Path) -> Result<(), notify::Error> {
        if !self.watched_paths.contains(path) {
            self.watcher.watch(path, RecursiveMode::Recursive)?;
            self.watched_paths.insert(path.to_path_buf());
        }
        Ok(())
    }
}

fn handle_skill_event(event: DebouncedEvent) {
    match event {
        DebouncedEvent::Create(path) | 
        DebouncedEvent::Write(path) | 
        DebouncedEvent::Remove(path) => {
            if is_skill_file(&path) {
                notify_skills_changed();
            }
        }
        _ => {}
    }
}

fn notify_skills_changed() {
    let notification = SkillsChangedNotification;
    broadcast_to_clients(notification);
}
```

### 客户端处理

在 `codex-rs/tui_app_server/src/app.rs` 中：

```rust
match notification {
    ServerNotification::SkillsChanged(_) => {
        // 标记技能缓存为失效
        self.skills_cache.invalidate();
        
        // 可选：自动刷新技能列表
        if self.config.auto_refresh_skills {
            self.refresh_skills().await;
        }
    }
}
```

### 测试覆盖

在 `codex-rs/app-server/tests/suite/v2/skills_list.rs` 中：

```rust
#[tokio::test]
async fn test_skills_changed_notification() {
    let (client, temp_dir) = setup_test_environment().await;
    
    // 创建新技能文件
    let skill_file = temp_dir.path().join(".codex/skills/test/SKILL.json");
    fs::write(&skill_file, r#"{"name": "test"}"#).await.unwrap();
    
    // 等待并验证通知
    let notification = client.wait_for_notification::<SkillsChangedNotification>().await;
    assert!(notification.is_some());
    
    // 重新获取技能列表验证变更
    let skills = client.list_skills().await;
    assert!(skills.iter().any(|s| s.name == "test"));
}
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/SkillsChangedNotification.ts`

### Rust 协议定义
- V2 协议：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 通用协议：`codex-rs/app-server-protocol/src/protocol/common.rs`

### 服务端实现
- 事件处理：`codex-rs/app-server/src/bespoke_event_handling.rs`

### 客户端消费
- TUI 应用：`codex-rs/tui_app_server/src/app.rs`

### 父类型引用
- ServerNotification：`codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`

### 测试覆盖
- 技能列表测试：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

## 依赖与外部交互

### 上游依赖
- 文件系统监视：使用 notify crate 监视文件变化
- 技能根目录：监视的技能根目录列表

### 下游消费
- 客户端缓存：触发客户端技能缓存失效
- UI 更新：可选触发技能列表自动刷新

### 通知流程

```
文件系统变化
    ↓
notify crate 检测
    ↓
SkillsChangedNotification
    ↓
广播到所有连接的客户端
    ↓
客户端缓存失效
    ↓
客户端重新获取 skills/list (可选)
```

## 风险、边界与改进建议

### 边界情况
1. **高频变更**：快速连续的文件变化可能导致通知风暴
2. **临时文件**：编辑器临时文件可能触发不必要的通知
3. **大目录**：监视大型技能目录可能影响性能

### 潜在风险
1. **资源消耗**：文件监视消耗系统资源
2. **通知丢失**：客户端断开期间可能错过通知
3. **竞态条件**：通知和实际文件状态可能不一致

### 改进建议
1. **变更详情**：考虑添加变更类型和文件路径信息
2. **去抖动**：优化去抖动逻辑减少重复通知
3. **批量通知**：批量处理短时间内的多个变更
4. **选择性监视**：允许客户端指定感兴趣的变更类型
5. **差异计算**：服务器端计算差异减少客户端工作量
6. **重连同步**：客户端重连时自动同步最新状态
