# Clear UI After Long Transcript - Fresh Header Only - Technical Research Document

## Snapshot File
`codex_tui_app_server__app__tests__clear_ui_after_long_transcript_fresh_header_only.snap`

## Snapshot Content
```
╭─────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                │
│                                             │
│ model:     gpt-test high   /model to change │
│ directory: /tmp/project                     │
╰─────────────────────────────────────────────╯
```

---

## 1. 场景与职责 (Scenario & Responsibilities)

### 1.1 功能场景
此快照测试验证 `/clear` 命令或 `Ctrl+L` 快捷键执行后的UI刷新行为。当用户长时间使用Codex后，终端积累了大量对话历史，需要一种快速清理屏幕并显示当前会话状态的方式。

### 1.2 业务职责
- **屏幕清理**: 清除终端上的所有历史输出和滚动缓冲区
- **状态重置**: 重新显示会话头部信息，提供当前配置的快速概览
- **上下文保持**: 清理后保持会话活跃，不中断当前对话上下文
- **视觉刷新**: 提供"重新开始"的视觉感受，同时保留会话连续性

### 1.3 使用场景
1. 用户执行 `/clear` 斜杠命令
2. 用户按 `Ctrl+L` 快捷键
3. 长时间会话后清理视觉噪音
4. 演示或截图前整理界面

---

## 2. 功能点目的 (Feature Purpose)

### 2.1 核心功能
| 组件 | 内容 | 目的 |
|------|------|------|
| 标题行 | `>_ OpenAI Codex (v<VERSION>)` | 品牌标识和版本信息 |
| 模型信息 | `model: gpt-test high` | 当前使用的AI模型 |
| 修改提示 | `/model to change` | 提示用户如何切换模型 |
| 工作目录 | `directory: /tmp/project` | 当前工作目录 |

### 2.2 设计目的
1. **信息密度**: 在最小空间内展示最关键的会话信息
2. **可操作性**: 提示 `/model` 命令，引导用户发现更多功能
3. **一致性**: 与会话启动时的头部显示保持一致
4. **简洁性**: 清理后不显示历史消息、欢迎语或启动提示

---

## 3. 具体技术实现 (Technical Implementation)

### 3.1 核心流程
```rust
// app.rs
fn clear_terminal_ui(&mut self, tui: &mut tui::Tui, redraw_header: bool) -> Result<()> {
    // 1. 清除待处理的历史行
    tui.clear_pending_history_lines();

    // 2. 根据终端类型选择清理方式
    if is_alt_screen_active {
        tui.terminal.clear_visible_screen()?;
    } else {
        // 使用ANSI序列清理滚动缓冲区和可见屏幕
        tui.terminal.clear_scrollback_and_visible_screen_ansi()?;
    }

    // 3. 重新定位视口
    let mut area = tui.terminal.viewport_area;
    if area.y > 0 {
        area.y = 0;
        tui.terminal.set_viewport_area(area);
    }

    // 4. 可选：重绘头部
    if redraw_header {
        self.queue_clear_ui_header(tui)?;
    }
}
```

### 3.2 头部生成
```rust
// app.rs:1402-1418
fn clear_ui_header_lines_with_version(
    &self,
    width: u16,
    version: &'static str,
) -> Vec<Line<'static>> {
    history_cell::SessionHeaderHistoryCell::new(
        self.chat_widget.current_model().to_string(),
        self.chat_widget.current_reasoning_effort(),
        self.chat_widget.should_show_fast_status(
            self.chat_widget.current_model(),
            self.chat_widget.current_service_tier(),
        ),
        self.config.cwd.clone(),
        version,
    )
    .display_lines(width)
}
```

### 3.3 测试实现
```rust
// app.rs:7670-7709
async fn render_clear_ui_header_after_long_transcript_for_snapshot() -> String {
    let mut app = make_test_app().await;
    
    // 模拟长对话历史
    app.chat_widget.add_info_message(
        "startup tip that used to replay".to_string(),
        None,
    );
    app.chat_widget.add_user_history_cell(
        "Bracken Ferry".to_string(),
        Vec::new(),
        None,
        Vec::new(),
        Vec::new(),
    );

    // 生成清理后的头部
    let rendered = app
        .clear_ui_header_lines_with_version(80, "<VERSION>")
        .iter()
        .map(|line| line.spans.iter().map(|span| span.content.as_ref()).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n");

    // 验证：不应包含历史内容
    assert!(!rendered.contains("startup tip that used to replay"));
    assert!(!rendered.contains("Bracken Ferry"));
    
    rendered
}
```

---

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 4.1 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/app.rs` | 清理逻辑、测试用例 |
| `codex-rs/tui_app_server/src/history_cell.rs` | SessionHeaderHistoryCell实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 历史记录管理 |
| `codex-rs/tui_app_server/src/tui.rs` | 终端操作封装 |

### 4.2 调用链
```
用户输入 /clear 或 Ctrl+L
  └── App::handle_app_command() / handle_key_event()
        └── App::clear_terminal_ui()
              ├── tui.clear_pending_history_lines()
              ├── tui.terminal.clear_scrollback_and_visible_screen_ansi()
              └── App::queue_clear_ui_header()
                    └── SessionHeaderHistoryCell::new()
                          └── display_lines()
```

### 4.3 SessionHeaderHistoryCell 结构
```rust
// history_cell.rs:1227-1261
pub(crate) struct SessionHeaderHistoryCell {
    version: &'static str,
    model: String,
    model_style: Style,
    reasoning_effort: Option<ReasoningEffortConfig>,
    show_fast_status: bool,
    directory: PathBuf,
}

impl SessionHeaderHistoryCell {
    pub(crate) fn new(
        model: String,
        reasoning_effort: Option<ReasoningEffortConfig>,
        show_fast_status: bool,
        directory: PathBuf,
        version: &'static str,
    ) -> Self { ... }
}
```

### 4.4 渲染实现
```rust
// history_cell.rs:1311-1380
impl HistoryCell for SessionHeaderHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 计算卡片内部宽度
        let inner_width = card_inner_width(width, SESSION_HEADER_MAX_INNER_WIDTH)?;
        
        // 构建标题行: ">_ OpenAI Codex (vX.Y.Z)"
        let title_spans = vec![
            Span::from(">_ ").dim(),
            Span::from("OpenAI Codex").bold(),
            Span::from(" ").dim(),
            Span::from(format!("(v{})", self.version)).dim(),
        ];
        
        // 构建模型信息行
        let model_spans = vec![
            Span::from("model: ").dim(),
            Span::styled(self.model.clone(), self.model_style),
            // ... reasoning effort, fast status
            Span::from(" /model to change").dim(),
        ];
        
        // 构建目录行
        let dir_spans = vec![
            Span::from("directory: ").dim(),
            Span::from(formatted_directory),
        ];
        
        // 使用卡片边框包装
        card_border_wrap(lines, width)
    }
}
```

---

## 5. 依赖与外部交互 (Dependencies & External Interactions)

### 5.1 内部依赖
| 模块 | 用途 |
|------|------|
| `ratatui` | 终端UI渲染、布局、样式 |
| `crossterm` | 终端控制、清屏ANSI序列 |
| `codex_protocol::ReasoningEffort` | 推理努力程度配置 |
| `codex_protocol::ServiceTier` | 服务等级(Fast模式) |

### 5.2 配置依赖
```rust
// 依赖的App状态
self.chat_widget.current_model()           // 当前模型名称
self.chat_widget.current_reasoning_effort() // 推理努力程度
self.chat_widget.current_service_tier()     // 服务等级
self.config.cwd                             // 当前工作目录
CODEX_CLI_VERSION                           // 编译时版本常量
```

### 5.3 ANSI序列
```rust
// 清理滚动缓冲区和可见屏幕
const CLEAR_SCROLLBACK_AND_VISIBLE: &str = "\x1b[3J\x1b[2J\x1b[H";
// 解释:
// \x1b[3J - ESC[3J: 清除滚动缓冲区 (ED 3)
// \x1b[2J - ESC[2J: 清除整个屏幕 (ED 2)
// \x1b[H  - ESC[H:  光标移至左上角 (CUP)
```

---

## 6. 风险、边界与改进建议 (Risks, Edge Cases & Improvements)

### 6.1 已知风险
| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 终端兼容性 | 部分终端(Terminal.app, Warp)不支持单独的滚动缓冲区清理 | 使用组合ANSI序列 |
| 视口定位 | 清理后视口位置可能不正确 | 强制设置 area.y = 0 |
| 历史丢失 | 用户可能误以为 `/clear` 删除会话数据 | 仅清理显示，保留会话状态 |

### 6.2 边界情况
1. **备用屏幕模式**: 在备用屏幕(alternate screen)中使用不同的清理策略
2. **零宽度终端**: 宽度为0时不渲染头部
3. **超长路径**: 工作目录使用智能截断算法
   ```rust
   // 中心截断: /very/long/path → /very/…/path
   SessionHeaderHistoryCell::format_directory_inner(&dir, Some(max_width))
   ```

### 6.3 改进建议
1. **可配置头部**: 允许用户自定义清理后显示的内容
   ```toml
   [ui.clear_header]
   show_model = true
   show_directory = true
   show_git_branch = true
   ```

2. **动画过渡**: 添加清理动画提升用户体验
   ```rust
   tui.animate_clear(Duration::from_millis(200));
   ```

3. **历史备份**: 提供选项将清理前的内容保存到文件
   ```rust
   /clear --save-to transcript.txt
   ```

4. **部分清理**: 支持仅清理指定数量的最近行
   ```rust
   /clear 100  // 保留最后100行
   ```

5. **快捷键自定义**: 允许用户自定义清屏快捷键
   ```toml
   [keybindings]
   clear_screen = "Ctrl+L"  # 或 "Cmd+K" 等
   ```

### 6.4 测试覆盖
当前测试覆盖：
- ✅ 头部渲染内容验证
- ✅ 历史内容不残留验证
- ✅ Ctrl+L 复用相同快照

建议增加：
- 不同终端宽度下的布局测试
- 超长目录路径截断测试
- 备用屏幕模式测试

---

## 7. 相关文档链接

- [AGENTS.md](../../../../../../AGENTS.md) - 项目开发指南
- [TUI Code Conventions](../../../../../../AGENTS.md#tui-code-conventions)
- [ratatui documentation](https://docs.rs/ratatui/)
