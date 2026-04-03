# forked_thread_history_line_without_name 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中**无名称分支线程历史行**的渲染。当用户从现有线程创建分支，但源线程没有设置名称（或无法从会话索引中获取名称）时，系统需要优雅地降级显示，仅显示线程 ID。

这是 `forked_thread_history_line` 测试的互补测试，确保在缺少线程名称的边界情况下 UI 仍能正确渲染。

## 功能点目的

1. **优雅降级**：当无法获取线程名称时，确保 UI 不会崩溃或显示错误
2. **信息完整性**：即使没有名称，仍显示线程 ID 以提供可追溯性
3. **一致性保证**：保持与有名称时相同的视觉风格和格式
4. **容错性**：处理会话索引缺失、损坏或条目不存在的情况

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 624-648 行

```rust
#[tokio::test]
async fn forked_thread_history_line_without_name_shows_id_once_snapshot() {
    let (chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    let mut chat = chat;
    let temp = tempdir().expect("tempdir");
    chat.config.codex_home = temp.path().to_path_buf();

    let forked_from_id =
        ThreadId::from_string("019c2d47-4935-7423-a190-05691f566092").expect("forked id");
    // 注意：没有创建 session_index.jsonl，模拟线程名称不可用的情况
    chat.emit_forked_thread_event(forked_from_id);

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

### 快照内容
```
• Thread forked from 019c2d47-4935-7423-a190-05691f566092
```

### 与有名称测试的关键区别

| 方面 | 有名称测试 | 无名称测试 |
|------|-----------|-----------|
| 会话索引文件 | 创建 `session_index.jsonl` | 不创建 |
| 线程名称 | `named-thread` | 无（`None`）|
| 显示格式 | `name (id)` | 仅 `id` |
| ID 样式 | 灰色（`dim()`）| 正常样式 |

### 核心实现逻辑

1. **降级渲染逻辑** (`emit_forked_thread_event`):
   - 位于 `codex-rs/tui_app_server/src/chatwidget.rs`
   - 当无法获取线程名称时，仅发送 ID

   ```rust
   let send_id_only = || {
       let lines = vec![Line::from(vec![
           "• ".into(),
           "Thread forked from ".into(),
           forked_from_id_text.clone().into(),  // 注意：无 dim() 样式
       ])];
       app_event_tx.send(AppEvent::InsertHistoryCell(Box::new(
           history_cell::PlainHistoryCell::new(lines),
       )));
   };
   ```

2. **会话索引查询失败处理**：
   - 尝试读取 `session_index.jsonl`
   - 如果文件不存在或解析失败，调用 `send_id_only()`
   - 如果找不到对应 ID 的条目，调用 `send_id_only()`

3. **样式差异**：
   - 有名称时：ID 使用 `dim()` 样式（灰色）
   - 无名称时：ID 使用正常样式，确保可读性

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 实现，包含降级逻辑 |
| `codex-rs/tui_app_server/src/history_cell.rs` | PlainHistoryCell 实现 |
| `codex-core/src/lib.rs` | `find_thread_name_by_id` 函数（返回 `Option`）|

### 关键代码片段

```rust
// 查询线程名称的异步逻辑
match find_thread_name_by_id(&codex_home, &forked_from_id_text).await {
    Some(name) if !name.is_empty() => {
        send_name_and_id(name);
    }
    _ => {
        send_id_only();  // 降级处理
    }
}
```

## 依赖与外部交互

### 外部依赖
- **tokio**: 异步运行时
- **tempfile**: 测试临时目录

### 内部依赖
- `find_thread_name_by_id`: 返回 `Option<String>`，为 `None` 时触发降级

### 降级流程
```
emit_forked_thread_event()
    └── tokio::spawn
            └── 尝试读取 session_index.jsonl
                    └── 文件不存在
                            └── find_thread_name_by_id 返回 None
                                    └── send_id_only()
                                            └── 渲染仅含 ID 的历史行
```

## 风险、边界与改进建议

### 潜在风险

1. **ID 可读性差**：
   - UUID 格式对用户不够友好
   - 长 UUID 可能换行或截断

2. **信息不足**：
   - 仅显示 ID 可能难以识别源线程
   - 用户可能需要手动查找线程

3. **重复信息**：
   - 如果分支链很长，多个 "Thread forked from ID" 可能令人困惑

### 边界情况

1. **空会话索引文件**：
   - 文件存在但内容为空
   - 应正确处理为无名称

2. **损坏的 JSON**：
   - 文件存在但包含无效 JSON
   - 解析错误应优雅处理

3. **部分匹配的条目**：
   - 条目存在但 `thread_name` 字段为 `null` 或空字符串
   - 应视为无名称处理

4. **权限问题**：
   - 文件存在但无读取权限
   - 应降级为无名称显示

### 改进建议

1. **添加时间戳**：
   - 即使没有名称，也显示分支时间
   - 帮助用户区分不同的分支事件

2. **ID 缩短显示**：
   - 显示 UUID 的前 8 位，如 `019c2d47...`
   - 鼠标悬停或点击显示完整 ID

3. **最近线程建议**：
   - 当无法获取名称时，显示 "可能是以下线程之一"
   - 列出最近的几个线程供用户选择

4. **错误提示优化**：
   - 添加 subtle 的提示，说明为什么只显示 ID
   - 例如：`Thread forked from 019c2d47... (name unavailable)`

5. **索引修复建议**：
   - 如果检测到会话索引损坏，提示用户如何修复
   - 或提供自动修复选项

6. **缓存机制**：
   - 即使当前无法获取名称，也记录 ID
   - 后台尝试重新查询，成功后更新显示

### 相关测试

- `forked_thread_history_line_includes_name_and_id_snapshot`：有名称的正常情况
- 两个测试共同覆盖完整的功能场景

### 测试策略说明

这两个测试采用**对比测试策略**：

1. **正向测试**（有名称）：验证正常功能路径
2. **降级测试**（无名称）：验证异常处理路径

这种策略确保：
- 功能在理想条件下工作
- 功能在非理想条件下优雅降级
- 两种情况的输出都符合预期

### UI 一致性考虑

| 元素 | 有名称 | 无名称 |
|------|--------|--------|
| 前缀 | `• Thread forked from` | 相同 |
| 主内容 | `name` | `id` |
| 辅助内容 | `(id)` 灰色 | 无 |
| 整体长度 | 较长 | 较短 |

保持前缀一致有助于用户识别这是分支事件，即使在没有名称的情况下。
