# ChatWidget Markdown 代码块 VT100 快照测试

## 场景与职责

该 snapshot 测试验证 `ChatWidget` 对复杂 Markdown 代码块的渲染能力，包括缩进代码块、嵌套围栏代码块和 JSONC（带注释的 JSON）语法高亮。

### 测试目的
- 验证 Markdown 解析和渲染的正确性
- 确保代码块在终端中的正确显示
- 测试嵌套和缩进代码块的处理

### 业务场景
- Codex 返回包含代码示例的技术解释
- 用户查看 SQL 查询、Shell 脚本或配置文件
- 代码块嵌套在列表或其他格式化内容中

## 功能点目的

### 1. Markdown 代码块支持
测试覆盖以下代码块类型：
- **缩进代码块** - 4空格缩进的代码
- **围栏代码块** - 使用 ``` 包裹的代码
- **嵌套代码块** - 代码块内的代码块
- **语法高亮** - 语言标识（如 `sh`, `jsonc`）

### 2. 终端渲染优化
- 保持代码格式（缩进、换行）
- 适当的语法高亮（如果支持）
- 与周围文本的正确分隔

## 具体技术实现

### 测试代码位置
```rust
// codex-rs/tui_app_server/src/chatwidget/tests.rs
#[tokio::test]
async fn chatwidget_markdown_code_blocks_vt100_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 1. 发送 TurnStarted 事件
    chat.handle_codex_event(Event {
        id: "t1".into(),
        msg: EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
    });

    // 2. 设置 VT100 终端
    let width: u16 = 80;
    let height: u16 = 50;
    let backend = VT100Backend::new(width, height);
    let mut term = crate::custom_terminal::Terminal::with_options(backend).expect("terminal");
    term.set_viewport_area(Rect::new(0, height - 1, width, 1));

    // 3. 模拟流式 Markdown 内容（2字符分块）
    let source: &str = r#"

    -- Indented code block (4 spaces)
    SELECT *
    FROM "users"
    WHERE "email" LIKE '%@example.com';

````markdown
```sh
printf 'fenced within fenced\n'
```

{
  // comment allowed in jsonc
  "path": "C:\\Program Files\\App",
  "regex": "^foo.*(bar)?$"
}
```
"#;

    // 4. 流式发送内容（模拟真实场景）
    let mut chars = source.chars().collect::<Vec<_>>();
    while !chars.is_empty() {
        let chunk: String = chars.drain(..2.min(chars.len())).collect();
        chat.handle_codex_event(Event {
            id: "t1".into(),
            msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent { chunk }),
        });
    }

    // 5. 提交内容到历史
    chat.on_commit_tick();
    drain_insert_history(&mut rx);

    // 6. 渲染并捕获
    term.draw(|f| {
        chat.render(f.area(), f.buffer_mut());
    }).unwrap();

    assert_snapshot!(term.backend().vt100().screen().contents());
}
```

### Snapshot 内容分析
```
（空行 x 29）
•     -- Indented code block (4 spaces)
      SELECT *
      FROM "users"
      WHERE "email" LIKE '%@example.com';

  ```sh
  printf 'fenced within fenced\n'
  ```

  {
    // comment allowed in jsonc
    "path": "C:\\Program Files\\App",
    "regex": "^foo.*(bar)?$"
  }
```

**内容解析**：
1. **缩进代码块**（4空格缩进）：
   ```sql
   -- Indented code block (4 spaces)
   SELECT *
   FROM "users"
   WHERE "email" LIKE '%@example.com';
   ```

2. **围栏代码块**（```sh）：
   ```sh
   printf 'fenced within fenced\n'
   ```

3. **JSONC 代码块**：
   ```jsonc
   {
     // comment allowed in jsonc
     "path": "C:\\Program Files\\App",
     "regex": "^foo.*(bar)?$"
   }
   ```

## 关键代码路径与文件引用

### Markdown 处理
```rust
// codex-rs/tui_app_server/src/markdown.rs

/// 追加 Markdown 内容到现有文本
pub fn append_markdown(
    existing: &mut Vec<Line>,
    new_text: &str,
    style: Style,
    width: usize,
) {
    // 解析 Markdown 并渲染为 Lines
    // 处理代码块、列表、强调等
}

/// 渲染代码块
fn render_code_block(
    lines: &mut Vec<Line>,
    code: &str,
    language: Option<&str>,
    style: Style,
) {
    // 根据语言应用语法高亮
    // 保持缩进和格式
}
```

### 流式内容处理
```rust
// codex-rs/tui_app_server/src/chatwidget.rs

/// 处理 AgentMessageDelta 事件
fn on_agent_message_delta(&mut self, chunk: String) {
    // 累积增量内容
    self.message_buffer.push_str(&chunk);
    
    // 更新活跃单元格
    if let Some(cell) = self.active_cell.as_mut() {
        cell.update_content(&chunk);
    }
}

/// 提交刻度 - 将缓冲内容刷新到历史
fn on_commit_tick(&mut self) {
    if !self.message_buffer.is_empty() {
        // 创建新的历史单元格
        let cell = AgentMessageCell::new(&self.message_buffer);
        self.insert_history_cell(cell);
        self.message_buffer.clear();
    }
}
```

### AgentMessageCell
```rust
// codex-rs/tui_app_server/src/history_cell.rs

pub struct AgentMessageCell {
    content: Vec<AgentMessageContent>,
    phase: Option<MessagePhase>,
}

impl HistoryCell for AgentMessageCell {
    fn display_lines(&self, width: usize) -> Vec<Line> {
        let mut lines = Vec::new();
        
        for content in &self.content {
            match content {
                AgentMessageContent::Text { text } => {
                    // 解析 Markdown 并渲染
                    append_markdown(&mut lines, text, Style::default(), width);
                }
                // ... 其他内容类型
            }
        }
        
        lines
    }
}
```

## 依赖与外部交互

### Markdown 解析依赖
| 依赖 | 用途 |
|------|------|
| `pulldown-cmark` | Markdown 解析器（可能使用） |
| 自定义解析器 | 处理特定于 Codex 的 Markdown 扩展 |

### 语法高亮
| 组件 | 职责 |
|------|------|
| `syntect` 或自定义 | 代码语法高亮 |
| 语言检测 | 从围栏标识符识别语言 |

### 流式架构
```
AgentMessageDeltaEvent (chunk)
           ↓
    message_buffer (累积)
           ↓
    on_commit_tick() (定期刷新)
           ↓
    AgentMessageCell (创建)
           ↓
    append_markdown() (渲染)
           ↓
    VT100 屏幕输出
```

## 风险、边界与改进建议

### 当前限制

1. **分块大小敏感**
   - 测试使用2字符分块，可能无法覆盖所有边界情况
   - Markdown 解析可能在分块边界处出现问题

2. **无语法高亮验证**
   - Snapshot 仅捕获文本内容，不验证颜色
   - 语法高亮回归可能无法被检测

3. **固定尺寸**
   - 80x50 可能不代表所有用户终端
   - 长代码行可能被截断或换行

### 改进建议

1. **边界测试**
   ```rust
   // 测试不同分块大小
   for chunk_size in [1, 2, 5, 10, 100] {
       test_markdown_rendering(source, chunk_size).await;
   }
   ```

2. **颜色验证**
   ```rust
   // 验证语法高亮颜色
   let screen = term.backend().vt100().screen();
   let cell = screen.cell(35, 10); // 第35行第10列
   assert_eq!(cell.fgcolor(), Some(Color::Green)); // 注释应为绿色
   ```

3. **更多 Markdown 特性**
   ```rust
   let test_cases = vec![
       ("table", "| a | b |\n|---|---|\n| 1 | 2 |"),
       ("blockquote", "> quoted text"),
       ("heading", "# Heading 1\n## Heading 2"),
       ("link", "[link](http://example.com)"),
   ];
   ```

4. **性能测试**
   ```rust
   #[tokio::test]
   async fn large_code_block_performance() {
       let large_code = "x".repeat(100_000);
       let start = Instant::now();
       // 渲染大代码块
       assert!(start.elapsed() < Duration::from_millis(100));
   }
   ```

### 相关测试
- `chatwidget_exec_and_status_layout_vt100_snapshot` - 执行布局
- `final_reasoning_then_message_without_deltas_are_rendered` - 推理内容渲染
- `deltas_then_same_final_message_are_rendered_snapshot` - 增量消息处理

---

*文档生成时间：2026-03-23*
*对应 snapshot：codex_tui_app_server__chatwidget__tests__chatwidget_markdown_code_blocks_vt100_snapshot.snap*
