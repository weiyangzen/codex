# update_prompt.rs 研究文档

## 场景与职责

`update_prompt.rs` 是 Codex TUI 应用服务器的更新提示界面模块，负责：

1. **更新提示显示**：在有新版本可用时，向用户显示模态更新提示界面
2. **用户交互处理**：处理用户的选择（立即更新、跳过、不再提醒）
3. **更新执行协调**：根据用户选择执行更新或跳过
4. **版本忽略持久化**：将用户的"不再提醒"选择保存到配置文件

该模块仅在非调试构建（`not(debug_assertions)`）中启用，调试构建中更新提示被完全禁用。

## 功能点目的

### 1. 更新提示入口

**目的**：在 TUI 启动时检查并显示更新提示。

**函数**：`run_update_prompt_if_needed()`

**流程**：
1. 检查是否有可用的新版本（`updates::get_upgrade_version_for_popup()`）
2. 检查是否能确定更新方式（`update_action::get_update_action()`）
3. 创建并显示更新提示界面
4. 处理用户输入事件
5. 根据用户选择返回相应的 `UpdatePromptOutcome`

### 2. 更新提示界面

**目的**：提供美观的模态界面展示更新信息。

**组件**：
- 当前版本 → 最新版本的对比
- 发布说明链接
- 三个选项：更新现在、跳过、跳过直到下个版本
- 键盘快捷键提示

### 3. 用户选择处理

**目的**：响应用户的键盘输入，更新选择状态。

**支持的输入**：
- `↑`/`k`：向上导航
- `↓`/`j`：向下导航
- `1`：选择"更新现在"
- `2`：选择"跳过"
- `3`：选择"跳过直到下个版本"
- `Enter`：确认当前选择
- `Esc` / `Ctrl+C` / `Ctrl+D`：取消（等同于跳过）

### 4. 选择结果处理

**目的**：根据用户选择执行相应操作。

**结果类型**：
- `UpdateNow`：清除终端，返回 `RunUpdate` 结果
- `NotNow`：直接返回 `Continue`
- `DontRemind`：持久化忽略信息，返回 `Continue`

## 具体技术实现

### 数据结构

```rust
pub(crate) enum UpdatePromptOutcome {
    Continue,           // 继续正常运行
    RunUpdate(UpdateAction), // 执行更新
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum UpdateSelection {
    UpdateNow,
    NotNow,
    DontRemind,
}

struct UpdatePromptScreen {
    request_frame: FrameRequester,    // 帧请求器，用于触发重绘
    latest_version: String,           // 最新版本号
    current_version: String,          // 当前版本号
    update_action: UpdateAction,      // 更新动作
    highlighted: UpdateSelection,     // 当前高亮选项
    selection: Option<UpdateSelection>, // 用户最终选择
}
```

### 渲染实现

`UpdatePromptScreen` 实现 `WidgetRef` trait，使用 `ColumnRenderable` 进行布局：

```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清除背景
        let mut column = ColumnRenderable::new();
        
        // 标题行：✨ Update available! 1.0.0 -> 1.1.0
        column.push(Line::from(vec![
            padded_emoji("  ✨").bold().cyan(),
            "Update available!".bold(),
            format!("{current} -> {latest}", ...).dim(),
        ]));
        
        // 发布说明链接
        column.push(Line::from(vec![
            "Release notes: ".dim(),
            "https://github.com/openai/codex/releases/latest".dim().underlined(),
        ]));
        
        // 三个选项（带高亮指示器）
        column.push(selection_option_row(...));
        
        // 键盘提示
        column.push(Line::from(vec![
            "Press ".dim(),
            key_hint::plain(KeyCode::Enter).into(),
            " to continue".dim(),
        ]));
        
        column.render(area, buf);
    }
}
```

### 事件循环

```rust
let events = tui.event_stream();
tokio::pin!(events);

while !screen.is_done() {
    if let Some(event) = events.next().await {
        match event {
            TuiEvent::Key(key_event) => screen.handle_key(key_event),
            TuiEvent::Draw => {
                tui.draw(u16::MAX, |frame| {
                    frame.render_widget_ref(&screen, frame.area());
                })?;
            }
            _ => {}
        }
    }
}
```

### 导航逻辑

```rust
impl UpdateSelection {
    fn next(self) -> Self {
        match self {
            UpdateSelection::UpdateNow => UpdateSelection::NotNow,
            UpdateSelection::NotNow => UpdateSelection::DontRemind,
            UpdateSelection::DontRemind => UpdateSelection::UpdateNow,
        }
    }

    fn prev(self) -> Self {
        match self {
            UpdateSelection::UpdateNow => UpdateSelection::DontRemind,
            UpdateSelection::NotNow => UpdateSelection::UpdateNow,
            UpdateSelection::DontRemind => UpdateSelection::NotNow,
        }
    }
}
```

## 关键代码路径与文件引用

### 依赖模块

| 模块 | 文件 | 用途 |
|------|------|------|
| `update_action` | `update_action.rs` | 更新动作定义和检测 |
| `updates` | `updates.rs` | 版本检查和持久化 |
| `FrameRequester` | `tui/frame_requester.rs` | 触发界面重绘 |
| `Tui` | `tui.rs` | 终端界面管理 |
| `selection_option_row` | `selection_list.rs` | 选项行渲染 |
| `padded_emoji` | `history_cell.rs` | Emoji 前缀格式化 |
| `key_hint` | `key_hint.rs` | 键盘提示渲染 |

### 调用方

| 文件 | 用途 |
|------|------|
| `lib.rs` | TUI 启动时调用 `run_update_prompt_if_needed()` |

### 测试

模块包含单元测试和快照测试：

```rust
#[test]
fn update_prompt_snapshot() {
    // 使用 VT100Backend 捕获渲染输出
    // 验证界面外观
}

#[test]
fn update_prompt_confirm_selects_update() {
    // 测试 Enter 键选择更新
}

#[test]
fn update_prompt_navigation_wraps_between_entries() {
    // 测试导航循环（上/下箭头）
}
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 键盘事件处理 |
| `color-eyre` | 错误处理 |
| `tokio-stream` | 异步流支持 |

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::Config` | 配置读取 |

### 配置交互

- 通过 `updates::dismiss_version()` 持久化"不再提醒"选择
- 忽略信息存储在 `version.json` 文件中

## 风险、边界与改进建议

### 已知风险

1. **阻塞启动**：
   - 更新提示会阻塞 TUI 启动，直到用户做出选择
   - 如果用户不响应，TUI 无法使用

2. **网络依赖**：
   - 版本检查需要网络访问
   - 如果网络不可用，提示可能基于过期的缓存版本

3. **版本比较**：
   - 依赖 `updates::is_newer()` 进行版本比较
   - 预发布版本（如 `1.0.0-beta`）可能处理不当

### 边界条件

1. **并发安全**：
   - `dismiss_version()` 是异步操作，如果用户在短时间内多次选择"不再提醒"，可能导致竞态条件

2. **终端大小**：
   - 界面使用 `u16::MAX` 高度绘制，假设终端足够大
   - 极小终端可能导致布局问题

3. **信号处理**：
   - 如果用户在提示界面收到 `SIGINT`，终端状态可能无法正确恢复

### 改进建议

1. **非阻塞提示**：
   - 考虑在后台显示更新提示，不阻塞主界面
   - 或者在状态栏显示更新指示器，用户主动触发更新流程

2. **自动超时**：
   - 添加超时机制，如果用户 30 秒内无响应，自动选择"跳过"

3. **更新日志预览**：
   - 在提示界面显示简要的更新日志摘要
   - 帮助用户决定是否立即更新

4. **批量更新提示**：
   - 如果用户长时间未更新，考虑显示累积的更新内容

5. **A/B 测试支持**：
   - 添加配置项控制提示频率和样式
   - 支持实验性的提示改进

6. **可访问性**：
   - 增加对屏幕阅读器的支持
   - 确保颜色不是唯一的区分方式（当前高亮使用青色）

7. **测试增强**：
   - 增加终端大小变化的测试
   - 增加网络故障场景的测试
   - 增加长时间运行的稳定性测试
