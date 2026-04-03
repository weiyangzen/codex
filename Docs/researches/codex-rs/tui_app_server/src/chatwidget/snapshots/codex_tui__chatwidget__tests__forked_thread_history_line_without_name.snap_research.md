# 研究文档：不带名称的分支线程历史行

## 场景与职责

本快照测试验证 Codex TUI 在线程分叉（Thread Fork）场景下的历史记录渲染行为，特别是当原线程**未命名**时的显示格式。当用户从一个没有名称的线程创建分支时，系统仅显示原线程的 ID。

与带名称线程的显示形成对比，本测试验证系统能够优雅地处理缺少名称的情况，避免显示空括号或重复 ID。

## 功能点目的

1. **优雅降级**：当原线程没有名称时，仅显示 ID 而不显示空名称
2. **ID 唯一性保证**：即使没有名称，ID 也能唯一标识原线程
3. **格式一致性**：保持与带名称线程相似的格式，只是省略名称部分
4. **避免重复**：确保 ID 只显示一次（不像带名称时显示在括号中）

## 具体技术实现

### 核心数据结构

```rust
// 会话索引条目
struct SessionIndexEntry {
    id: ThreadId,
    thread_name: Option<String>,  // 可能为 None
    updated_at: DateTime<Utc>,
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn forked_thread_history_line_without_name_shows_id_once_snapshot() {
    let (chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    let mut chat = chat;
    let temp = tempdir().expect("tempdir");
    chat.config.codex_home = temp.path().to_path_buf();

    // 注意：这里没有创建会话索引文件
    // 因此无法找到线程名称
    let forked_from_id =
        ThreadId::from_string("019c2d47-4935-7423-a190-05691f566092").expect("forked id");
    
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
    assert_snapshot!("forked_thread_history_line_without_name", combined);
}
```

### 分支事件处理逻辑

```rust
// chatwidget.rs
fn emit_forked_thread_event(&mut self, forked_from_id: ThreadId) {
    // 从会话索引查找原线程信息
    let thread_info = self.session_index.get(&forked_from_id);
    
    // 构建历史记录行
    let display_text = if let Some(name) = thread_info.and_then(|t| t.thread_name.as_ref()) {
        // 有名称：显示名称和 ID
        format!("Thread forked from {} ({})", name, forked_from_id)
    } else {
        // 无名称：只显示 ID
        format!("Thread forked from {}", forked_from_id)
    };
    
    // 发送历史记录事件
    self.app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
        PlainHistoryCell::new(vec![Line::from(display_text)])
    )));
}
```

### 与带名称线程的对比

| 场景 | 显示格式 |
|------|---------|
| 带名称线程 | `Thread forked from {name} ({id})` |
| 不带名称线程 | `Thread forked from {id}` |

### 快照输出解析

```
• Thread forked from 019c2d47-4935-7423-a190-05691f566092
```

关键观察：
- 使用 `•` 作为列表标记
- 格式：`Thread forked from {id}`
- **没有括号**，ID 直接跟在文本后面
- ID 只显示一次
- 与带名称线程的格式保持一致的简洁性

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 实现，包含 `emit_forked_thread_event` 方法 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 600-624 行） |
| `codex-rs/tui/src/history_cell.rs` | PlainHistoryCell 实现 |
| `codex-protocol/src/thread_id.rs` | ThreadId 定义和序列化 |
| `codex-rs/tui/src/session_index.rs` | 会话索引管理 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__forked_thread_history_line_without_name.snap` | 本快照文件 |

### 相关测试函数

- `forked_thread_history_line_without_name_shows_id_once_snapshot()` - 本测试（未命名线程）
- `forked_thread_history_line_includes_name_and_id_snapshot()` - 对比测试（命名线程）
- `emit_forked_thread_event()` - 分支事件触发方法

## 依赖与外部交互

### 依赖模块

1. **会话索引（Session Index）**
   - 本测试中**没有创建**会话索引文件
   - 模拟了找不到线程信息的场景
   - 验证系统的优雅降级能力

2. **ThreadId**
   ```rust
   pub struct ThreadId(Uuid);
   
   impl Display for ThreadId {
       fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
           // 标准 UUID 格式输出
           write!(f, "{}", self.0)
       }
   }
   ```

3. **AppEvent 系统**
   ```rust
   pub enum AppEvent {
       InsertHistoryCell(Box<dyn HistoryCell>),
       // ...
   }
   ```

### 测试策略对比

两个相关测试的对比：

| 测试 | 会话索引 | 预期输出 |
|------|---------|---------|
| `forked_thread_history_line` | 创建索引，包含名称 | `named-thread (id)` |
| `forked_thread_history_line_without_name` | 不创建索引 | 仅 `id` |

这种对比测试确保了两种场景都被正确覆盖。

## 风险、边界与改进建议

### 潜在风险

1. **ID 可读性差**
   - UUID 很长且难以人工识别
   - 没有名称时用户难以区分不同线程

2. **ID 格式不一致**
   - 需要确保 ThreadId 的 Display 实现一致
   - 不同平台或版本的 UUID 格式可能不同

3. **会话索引查找失败**
   - 除了未命名，还可能有其他原因导致查找不到（如文件损坏）
   - 需要确保所有失败场景都降级为仅显示 ID

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 会话索引存在但名称为空字符串 | 视为无名称，只显示 ID |
| 会话索引存在但名称为空白字符 | 可能需要 trim 后判断 |
| 会话索引文件权限问题 | 优雅降级，只显示 ID |
| 无效的线程 ID | 可能需要错误处理 |
| 极长的 UUID 格式 | 确保显示不会被截断 |

### 改进建议

1. **用户体验优化**
   - 考虑为未命名线程生成默认名称（如 "Thread-1234"）
   - 添加提示鼓励用户为重要线程命名
   - 显示线程创建时间作为额外上下文

2. **ID 显示优化**
   - 考虑显示缩短的 ID（如前 8 位）节省空间
   - 添加复制 ID 的快捷键

3. **测试覆盖增强**
   - 添加名称为空字符串的测试
   - 添加名称为空白字符的测试
   - 添加会话索引损坏的测试

4. **调试支持**
   - 在调试模式下显示更多信息
   - 添加查看完整线程信息的命令

5. **文档完善**
   - 文档化线程命名的最佳实践
   - 说明未命名线程的显示格式
   - 添加如何重命名线程的指南
