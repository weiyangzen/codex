# CWD Prompt Modal 快照研究文档

## 快照文件信息
- **快照名称**: `codex_tui_app_server__cwd_prompt__tests__cwd_prompt_modal.snap`
- **源文件**: `tui_app_server/src/cwd_prompt.rs`
- **测试函数**: `cwd_prompt_snapshot()`
- **对应测试行**: 第 268-276 行

---

## 场景与职责

### 功能场景
此快照捕获的是 **会话恢复时的工作目录选择提示模态框**。当用户尝试恢复一个之前保存的 Codex 会话时，系统需要确认使用哪个工作目录：

1. **Session 目录**: 之前会话记录的工作目录（保存在会话元数据中）
2. **Current 目录**: 用户当前的工作目录

### 业务职责
- **会话恢复决策**: 允许用户选择继续使用原会话目录或切换到当前目录
- **路径冲突处理**: 解决会话保存路径与当前工作路径不一致的问题
- **用户体验保障**: 通过清晰的 UI 提示避免用户在不正确的目录下操作

### 触发时机
该提示在以下场景出现：
- 用户执行 `codex resume <session_id>` 命令
- 会话元数据中记录的工作目录与当前 shell 的工作目录不同
- 需要用户确认工作目录选择后才能继续恢复会话

---

## 功能点目的

### 核心功能
1. **工作目录选择界面**: 提供交互式选择界面让用户决定使用哪个工作目录
2. **路径信息展示**: 清晰显示两个候选目录的绝对路径
3. **默认选项预设**: 默认选中 "Session" 目录（更符合用户恢复会话的预期）

### UI 元素解析
```
Choose working directory to resume this session

  Session = latest cwd recorded in the resumed session                          
  Current = your current working directory

› 1. Use session directory (/Users/example/session)                             
  2. Use current directory (/Users/example/current)

  Press enter to continue
```

| 元素 | 说明 |
|------|------|
| 标题 | "Choose working directory to resume this session" |
| 说明文本 | 解释 Session 和 Current 的含义 |
| 选项 1 | 使用会话目录，带路径显示，默认选中（› 标记） |
| 选项 2 | 使用当前目录，带路径显示 |
| 操作提示 | "Press enter to continue" |

### 交互设计
- **默认选中**: Session 目录（索引 0）
- **键盘导航**: ↑/↓ 或 j/k 切换选项，1/2 直接选择，Enter 确认
- **退出机制**: Esc 默认选择 Session，Ctrl+C/D 退出不恢复

---

## 具体技术实现

### 数据结构

```rust
// 动作类型枚举（第 26-46 行）
pub(crate) enum CwdPromptAction {
    Resume,  // 恢复会话
    Fork,    // 派生/分支会话
}

// 选择类型枚举（第 48-74 行）
pub(crate) enum CwdSelection {
    Current,  // 使用当前目录
    Session,  // 使用会话目录
}

// 结果类型（第 55-58 行）
pub(crate) enum CwdPromptOutcome {
    Selection(CwdSelection),
    Exit,
}
```

### 核心渲染逻辑

**`CwdPromptScreen` 结构体**（第 120-128 行）：
```rust
struct CwdPromptScreen {
    request_frame: FrameRequester,  // 帧请求器，用于触发重绘
    action: CwdPromptAction,        // 当前动作类型（Resume/Fork）
    current_cwd: String,            // 当前工作目录路径
    session_cwd: String,            // 会话工作目录路径
    highlighted: CwdSelection,      // 当前高亮选项
    selection: Option<CwdSelection>, // 用户最终选择
    should_exit: bool,              // 是否应退出
}
```

**渲染实现**（第 193-248 行 `WidgetRef` trait 实现）：
```rust
impl WidgetRef for &CwdPromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清空区域
        let mut column = ColumnRenderable::new();

        // 动态构建标题（根据 action 类型变化）
        let action_verb = self.action.verb();  // "resume" 或 "fork"
        column.push(Line::from(vec![
            "Choose working directory to ".into(),
            action_verb.bold(),
            " this session".into(),
        ]));

        // 选项行使用 selection_option_row 辅助函数渲染
        column.push(selection_option_row(
            0,
            format!("Use session directory ({session_cwd})"),
            self.highlighted == CwdSelection::Session,
        ));
        // ...
    }
}
```

### 事件处理

**键盘事件处理**（第 148-168 行）：
```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    // Ctrl+C/D 退出
    if key_event.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key_event.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        self.selection = None;
        self.should_exit = true;
        return;
    }
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(CwdSelection::Session),
        KeyCode::Char('2') => self.select(CwdSelection::Current),
        KeyCode::Enter => self.select(self.highlighted),
        KeyCode::Esc => self.select(CwdSelection::Session),
        _ => {}
    }
}
```

### 异步主循环

**`run_cwd_selection_prompt` 函数**（第 76-118 行）：
```rust
pub(crate) async fn run_cwd_selection_prompt(
    tui: &mut Tui,
    action: CwdPromptAction,
    current_cwd: &Path,
    session_cwd: &Path,
) -> Result<CwdPromptOutcome> {
    let mut screen = CwdPromptScreen::new(...);
    
    // 初始绘制
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    })?;

    // 事件循环
    let events = tui.event_stream();
    tokio::pin!(events);

    while !screen.is_done() {
        if let Some(event) = events.next().await {
            match event {
                TuiEvent::Key(key_event) => screen.handle_key(key_event),
                TuiEvent::Draw => { /* 重绘 */ }
                _ => {}
            }
        }
    }
    // 返回结果
}
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件路径 | 职责 |
|---------|------|
| `tui_app_server/src/cwd_prompt.rs` | CWD 提示模态框完整实现 |
| `tui_app_server/src/selection_list.rs` | `selection_option_row` 辅助函数 |
| `tui_app_server/src/render/renderable.rs` | `ColumnRenderable`, `Renderable` trait |
| `tui_app_server/src/key_hint.rs` | 键盘提示渲染 |
| `tui_app_server/src/tui.rs` | TUI 基础框架和事件循环 |

### 关键函数调用链
```
run_cwd_selection_prompt()
├── CwdPromptScreen::new()              # 创建屏幕状态
├── tui.draw()                          # 初始渲染
│   └── CwdPromptScreen::render_ref()   # WidgetRef 实现
│       ├── Clear.render()              # 清空背景
│       ├── ColumnRenderable::new()     # 创建列布局
│       ├── selection_option_row()      # 渲染选项行
│       └── Line::from()                # 构建文本行
└── 事件循环
    └── handle_key()                    # 处理键盘输入
        ├── set_highlight()             # 切换高亮
        └── select()                    # 确认选择
```

### 测试代码位置
```rust
// 第 259-276 行
fn new_prompt() -> CwdPromptScreen {
    CwdPromptScreen::new(
        FrameRequester::test_dummy(),
        CwdPromptAction::Resume,              // 测试 Resume 动作
        "/Users/example/current".to_string(),
        "/Users/example/session".to_string(),
    )
}

#[test]
fn cwd_prompt_snapshot() {
    let screen = new_prompt();
    let mut terminal = Terminal::new(VT100Backend::new(80, 14)).expect("terminal");
    terminal.draw(|frame| frame.render_widget_ref(&screen, frame.area()))
        .expect("render cwd prompt");
    insta::assert_snapshot!("cwd_prompt_modal", terminal.backend());
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖包 | 用途 |
|--------|------|
| `ratatui` | TUI 渲染框架，提供 `Buffer`, `Rect`, `Widget` 等 |
| `crossterm` | 跨平台终端控制，处理键盘事件 |
| `tokio_stream` | 异步事件流处理 |
| `color-eyre` | 错误处理和报告 |

### 内部模块依赖

```rust
use crate::key_hint;                                    // 键盘提示
use crate::render::Insets;                              // 边距工具
use crate::render::renderable::{ColumnRenderable, Renderable, RenderableExt};
use crate::selection_list::selection_option_row;       // 选项行渲染
use crate::tui::{FrameRequester, Tui, TuiEvent};       // TUI 核心
```

### 与 TUI 框架的交互
- **帧请求**: 通过 `FrameRequester::schedule_frame()` 触发重绘
- **事件流**: 通过 `tui.event_stream()` 获取异步事件流
- **渲染上下文**: 使用 `VT100Backend` 进行测试渲染，模拟终端输出

---

## 风险、边界与改进建议

### 潜在风险

1. **路径显示截断**
   - **问题**: 长路径可能在窄终端中被截断，用户无法看到完整路径
   - **当前处理**: 依赖终端宽度，测试使用 80 列宽度
   - **建议**: 添加路径悬停提示或水平滚动支持

2. **默认选择假设**
   - **问题**: 默认选择 Session 目录可能不符合所有用户预期
   - **建议**: 考虑记住用户上次选择，或提供配置选项

3. **国际化缺失**
   - **问题**: 所有文本硬编码为英文
   - **建议**: 添加 i18n 支持

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|---------|------|
| 两个目录相同 | 仍显示选择界面 | 可优化：自动跳过选择 |
| 会话目录不存在 | 显示路径但不验证 | 风险：用户可能选择无效目录 |
| 极窄终端 (<40列) | 路径严重截断 | 需要响应式布局 |
| 非交互式环境 | 需外部处理 | 应有非交互式默认值 |

### 改进建议

1. **智能跳过**
   ```rust
   // 当两个目录相同时自动跳过选择
   if current_cwd == session_cwd {
       return Ok(CwdPromptOutcome::Selection(CwdSelection::Session));
   }
   ```

2. **路径验证**
   ```rust
   // 在显示前验证目录是否存在
   if !Path::new(&session_cwd).exists() {
       // 显示警告或禁用该选项
   }
   ```

3. **响应式布局**
   - 窄终端下使用路径缩写（如 `~/project` 代替完整路径）
   - 考虑垂直堆叠选项而非水平布局

4. **测试覆盖扩展**
   - 添加长路径测试用例
   - 添加窄终端测试用例
   - 添加目录不存在场景测试

### 相关快照对比
- `cwd_prompt_fork_modal.snap`: Fork 动作变体，标题显示 "fork" 而非 "resume"
- 两个快照 UI 结构相同，仅动词变化，体现了 `CwdPromptAction` 的设计

---

## 总结

此快照展示了 Codex TUI 应用中一个关键的会话恢复交互组件。通过清晰的视觉层次和直观的键盘导航，帮助用户在恢复会话时做出正确的工作目录选择。代码实现遵循了 Rust 的强类型原则，使用枚举明确表达各种状态和选择，并通过 ratatui 框架实现了跨平台的终端 UI 渲染。
