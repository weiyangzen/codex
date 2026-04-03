# 研究文档：带名称的分支线程历史行

## 场景与职责

本快照测试验证 Codex TUI 在线程分叉（Thread Fork）场景下的历史记录渲染行为。当用户从一个**已命名**的线程创建分支时，系统会在历史记录中显示一条特殊的分支记录，包含原线程的名称和 ID。

线程分叉是 Codex 的多线程协作功能的一部分，允许用户基于现有对话创建新的分支线程进行并行探索。

## 功能点目的

1. **线程溯源**：让用户清楚知道当前线程是从哪个线程分支出来的
2. **命名线程识别**：对于已命名的线程，显示名称便于用户识别
3. **ID 备用**：即使线程有名称，也保留 ID 用于精确引用
4. **历史记录完整性**：在会话历史中记录分支事件

## 具体技术实现

### 核心数据结构

```rust
// ThreadId 定义
pub struct ThreadId(Uuid);

// 会话索引条目
struct SessionIndexEntry {
    id: ThreadId,
    thread_name: Option<String>,  // 线程名称
    updated_at: DateTime<Utc>,
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn forked_thread_history_line_includes_name_and_id_snapshot() {
    let (chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    let mut chat = chat;
    let temp = tempdir().expect("tempdir");
    chat.config.codex_home = temp.path().to_path_buf();

    // 创建会话索引，包含命名线程
    let forked_from_id =
        ThreadId::from_string("e9f18a88-8081-4e51-9d4e-8af5cde2d8dd").expect("forked id");
    let session_index_entry = format!(
        "{{\"id\":\"{forked_from_id}\",\"thread_name\":\"named-thread\",\"updated_at\":\"2024-01-02T00:00:00Z\"}}\n"
    );
    std::fs::write(temp.path().join("session_index.jsonl"), session_index_entry)
        .expect("write session index");

    // 触发分支事件
    chat.emit_forked_thread_event(forked_from_id);

    // 等待并捕获历史记录单元格
    let history_cell = tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            match rx.recv().await {
                Some(AppEvent::InsertHistoryCell(cell)) => break cell,
                Some(_) => continue,
                None => panic!("app event channel closed before forked thread history was emitted"),
            }
        }
    })
    .await
    .expect("timed out waiting for forked thread history");
    
    let combined = lines_to_single_string(&history_cell.display_lines(80));
    assert_snapshot!("forked_thread_history_line", combined);
}
```

### 分支事件处理

```rust
// chatwidget.rs
fn emit_forked_thread_event(&mut self, forked_from_id: ThreadId) {
    // 从会话索引查找原线程信息
    let thread_info = self.session_index.get(&forked_from_id);
    
    // 构建历史记录行
    let display_text = if let Some(name) = thread_info.and_then(|t| t.thread_name.as_ref()) {
        format!("Thread forked from {} ({})", name, forked_from_id)
    } else {
        format!("Thread forked from {}", forked_from_id)
    };
    
    // 发送历史记录事件
    self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        PlainHistoryCell::new(vec![Line::from(display_text)])
    )));
}
```

### 快照输出解析

```
• Thread forked from named-thread (e9f18a88-8081-4e51-9d4e-8af5cde2d8dd)
```

关键观察：
- 使用 `•` 作为列表标记
- 格式：`Thread forked from {name} ({id})`
- 同时显示线程名称（`named-thread`）和 ID
- 名称在前便于识别，ID 在后用于精确引用

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 实现，包含 `emit_forked_thread_event` 方法 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 563-599 行） |
| `codex-rs/tui/src/history_cell.rs` | PlainHistoryCell 实现 |
| `codex-protocol/src/thread_id.rs` | ThreadId 定义和序列化 |
| `codex-rs/tui/src/session_index.rs` | 会话索引管理 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__forked_thread_history_line.snap` | 本快照文件 |

### 相关测试函数

- `forked_thread_history_line_includes_name_and_id_snapshot()` - 本测试（命名线程）
- `forked_thread_history_line_without_name_shows_id_once_snapshot()` - 对比测试（未命名线程）
- `emit_forked_thread_event()` - 分支事件触发方法
- `lines_to_single_string()` - 测试辅助函数

## 依赖与外部交互

### 依赖模块

1. **会话索引（Session Index）**
   - 存储在 `codex_home/session_index.jsonl`
   - 包含线程 ID、名称、更新时间
   - 用于查找原线程信息

2. **ThreadId**
   ```rust
   pub struct ThreadId(Uuid);
   
   impl ThreadId {
       pub fn from_string(s: &str) -> Option<Self>;
       // Display 实现用于格式化输出
   }
   ```

3. **AppEvent 系统**
   ```rust
   pub enum AppEvent {
       InsertHistoryCell(Box<dyn HistoryCell>),
       // ...
   }
   ```

4. **tempfile crate**
   - 测试中用于创建临时目录模拟 codex_home

### 文件系统交互

```
~/.codex/
└── session_index.jsonl   # 会话索引文件
    
内容示例：
{"id":"e9f18a88-8081-4e51-9d4e-8af5cde2d8dd","thread_name":"named-thread","updated_at":"2024-01-02T00:00:00Z"}
```

## 风险、边界与改进建议

### 潜在风险

1. **会话索引不一致**
   - 如果会话索引文件损坏或丢失，无法获取线程名称
   - 需要处理回退到只显示 ID 的情况

2. **名称冲突**
   - 多个线程可能有相同名称，需要 ID 区分
   - 当前实现已经同时显示名称和 ID，缓解了这个问题

3. **长名称截断**
   - 线程名称很长时可能在终端显示不全
   - 需要处理长名称的截断或换行

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 会话索引中找不到线程 | 只显示 ID（参考对比测试） |
| 线程名称为空字符串 | 视为无名称，只显示 ID |
| 会话索引文件损坏 | 优雅降级，只显示 ID |
| 超长线程名称 | 可能需要截断显示 |
| 特殊字符在名称中 | 需要正确转义显示 |

### 改进建议

1. **用户体验优化**
   - 添加点击/快捷键导航到原线程的功能
   - 考虑添加分支时间戳
   - 添加分支原因或描述（如果可用）

2. **健壮性增强**
   - 缓存会话索引到内存减少文件 IO
   - 添加会话索引的自动修复机制
   - 处理并发修改会话索引的情况

3. **测试覆盖**
   - 添加会话索引损坏的测试
   - 测试超长名称的显示
   - 测试特殊字符名称
   - 测试并发分支场景

4. **文档完善**
   - 文档化线程命名最佳实践
   - 说明分支线程的使用场景
   - 添加会话索引文件格式文档
