# UpdatePrompt - 更新提示模态框快照研究文档

## 场景与职责

`UpdatePrompt` 是 Codex TUI 的**版本更新提示组件**，在应用启动时检测到有新版本可用时显示模态框，引导用户选择更新策略。该组件仅在 Release 模式下生效（`#![cfg(not(debug_assertions))]`），避免开发时频繁触发。

**核心职责：**
- 检测新版本并显示更新提示弹窗
- 提供三种更新选项：立即更新、跳过本次、跳过至下一版本
- 支持键盘导航和快捷键选择
- 持久化用户的选择（跳过至下一版本）

**本快照场景：** 测试更新提示模态框的 UI 渲染，验证版本信息、发布说明链接、选项列表和操作提示的正确显示。

---

## 功能点目的

### 1. 版本检测与提示
- **目的**：确保用户及时获取最新功能和修复
- **触发条件**：
  - `config.check_for_update_on_startup = true`
  - 检测到新版本可用
  - 用户未选择跳过当前版本
- **版本源**：
  - npm/bun 安装：GitHub Releases API
  - Homebrew 安装：Homebrew Cask API

### 2. 更新选项
| 选项 | 快捷键 | 行为 |
|-----|-------|------|
| Update now | `1` / Enter | 执行更新命令后退出 TUI |
| Skip | `2` / Esc | 关闭提示，继续当前会话 |
| Skip until next version | `3` | 记录跳过决定，下次检测新版本时再提示 |

### 3. 更新方式检测
根据安装方式自动选择更新命令：
- **npm**: `npm install -g @openai/codex`
- **bun**: `bun install -g @openai/codex`
- **Homebrew**: `brew upgrade --cask codex`

### 4. 持久化跳过决定
- 将跳过的版本号写入 `~/.codex/version.json`
- 格式：`{"latest_version": "x.x.x", "last_checked_at": "...", "dismissed_version": "x.x.x"}`

---

## 具体技术实现

### 核心数据结构

```rust
// 更新提示结果
pub(crate) enum UpdatePromptOutcome {
    Continue,           // 继续正常启动
    RunUpdate(UpdateAction),  // 执行更新
}

// 更新操作类型
pub enum UpdateAction {
    NpmGlobalLatest,    // npm 全局安装
    BunGlobalLatest,    // bun 全局安装
    BrewUpgrade,        // Homebrew 升级
}

// 用户选择
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum UpdateSelection {
    UpdateNow,
    NotNow,
    DontRemind,
}

// 提示屏幕状态
struct UpdatePromptScreen {
    request_frame: FrameRequester,
    latest_version: String,
    current_version: String,      // 从 CARGO_PKG_VERSION 读取
    update_action: UpdateAction,
    highlighted: UpdateSelection, // 当前高亮选项
    selection: Option<UpdateSelection>, // 用户已选择的选项
}
```

### 主流程

```rust
pub(crate) async fn run_update_prompt_if_needed(
    tui: &mut Tui,
    config: &Config,
) -> Result<UpdatePromptOutcome> {
    // 1. 检查是否有新版本需要提示
    let Some(latest_version) = updates::get_upgrade_version_for_popup(config) else {
        return Ok(UpdatePromptOutcome::Continue);
    };
    
    // 2. 确定更新方式
    let Some(update_action) = crate::update_action::get_update_action() else {
        return Ok(UpdatePromptOutcome::Continue);
    };

    // 3. 创建提示屏幕并渲染
    let mut screen = UpdatePromptScreen::new(...);
    tui.draw(u16::MAX, |frame| {
        frame.render_widget_ref(&screen, frame.area());
    })?;

    // 4. 事件循环等待用户选择
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

    // 5. 处理用户选择
    match screen.selection() {
        Some(UpdateSelection::UpdateNow) => {
            tui.terminal.clear()?;
            Ok(UpdatePromptOutcome::RunUpdate(update_action))
        }
        Some(UpdateSelection::DontRemind) => {
            updates::dismiss_version(config, screen.latest_version()).await?;
            Ok(UpdatePromptOutcome::Continue)
        }
        _ => Ok(UpdatePromptOutcome::Continue),
    }
}
```

### 键盘事件处理

```rust
fn handle_key(&mut self, key_event: KeyEvent) {
    if key_event.kind == KeyEventKind::Release {
        return;
    }
    
    // Ctrl+C / Ctrl+D 视为跳过
    if key_event.modifiers.contains(KeyModifiers::CONTROL)
        && matches!(key_event.code, KeyCode::Char('c') | KeyCode::Char('d'))
    {
        self.select(UpdateSelection::NotNow);
        return;
    }
    
    match key_event.code {
        KeyCode::Up | KeyCode::Char('k') => self.set_highlight(self.highlighted.prev()),
        KeyCode::Down | KeyCode::Char('j') => self.set_highlight(self.highlighted.next()),
        KeyCode::Char('1') => self.select(UpdateSelection::UpdateNow),
        KeyCode::Char('2') => self.select(UpdateSelection::NotNow),
        KeyCode::Char('3') => self.select(UpdateSelection::DontRemind),
        KeyCode::Enter => self.select(self.highlighted),
        KeyCode::Esc => self.select(UpdateSelection::NotNow),
        _ => {}
    }
}
```

### 渲染实现

```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);  // 清空背景
        let mut column = ColumnRenderable::new();

        let update_command = self.update_action.command_str();

        // 标题行
        column.push(Line::from(vec![
            padded_emoji("  ✨").bold().cyan(),
            "Update available!".bold(),
            " ".into(),
            format!("{current} -> {latest}", ...).dim(),
        ]));
        
        // 发布说明链接
        column.push(Line::from(vec![
            "Release notes: ".dim(),
            "https://github.com/openai/codex/releases/latest".dim().underlined(),
        ]).inset(Insets::tlbr(0, 2, 0, 0)));
        
        // 选项列表
        column.push(selection_option_row(0, format!("Update now (runs `{update_command}`)"), ...));
        column.push(selection_option_row(1, "Skip".to_string(), ...));
        column.push(selection_option_row(2, "Skip until next version".to_string(), ...));
        
        // 操作提示
        column.push(Line::from(vec![
            "Press ".dim(),
            key_hint::plain(KeyCode::Enter).into(),
            " to continue".dim(),
        ]).inset(Insets::tlbr(0, 2, 0, 0)));
        
        column.render(area, buf);
    }
}
```

---

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/update_prompt.rs` | 主组件实现，包含事件循环和渲染逻辑 |
| `codex-rs/tui/src/update_action.rs` | 更新操作类型定义和安装方式检测 |
| `codex-rs/tui/src/updates.rs` | 版本检测、API 调用、持久化逻辑 |
| `codex-rs/tui/src/selection_list.rs` | 选项行渲染组件（`selection_option_row`） |
| `codex-rs/tui/src/key_hint.rs` | 键盘提示渲染（`key_hint::plain`） |
| `codex-rs/tui/src/history_cell.rs` | `padded_emoji` 工具函数 |
| `codex-rs/tui/src/render/` | 渲染基础设施（`ColumnRenderable`, `Insets`） |

### 测试代码位置

```rust
// codex-rs/tui/src/update_prompt.rs:261-268
#[test]
fn update_prompt_snapshot() {
    let screen = new_prompt();
    let mut terminal = Terminal::new(VT100Backend::new(80, 12)).expect("terminal");
    terminal
        .draw(|frame| frame.render_widget_ref(&screen, frame.area()))
        .expect("render update prompt");
    insta::assert_snapshot!("update_prompt_modal", terminal.backend());
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 键盘事件处理 |
| `tokio` | 异步运行时（事件流处理） |
| `tokio-stream` | 事件流扩展（`StreamExt`） |
| `chrono` | 时间处理（版本检查时间戳） |
| `serde` | 版本信息 JSON 序列化 |
| `color-eyre` | 错误处理 |
| `shlex` | 命令行参数转义（`UpdateAction::command_str`） |

### 内部模块交互

```
update_prompt.rs
├── UpdateAction ← update_action.rs
│   ├── NpmGlobalLatest
│   ├── BunGlobalLatest
│   └── BrewUpgrade
├── updates::get_upgrade_version_for_popup() ← updates.rs
│   ├── GitHub Releases API
│   └── Homebrew Cask API
├── updates::dismiss_version() ← updates.rs
├── selection_option_row() ← selection_list.rs
├── key_hint::plain() ← key_hint.rs
└── padded_emoji() ← history_cell.rs
```

### 网络交互

```
updates.rs
├── 非 Homebrew:
│   └── GET https://api.github.com/repos/openai/codex/releases/latest
│       └── { "tag_name": "rust-vX.X.X" }
└── Homebrew:
    └── GET https://formulae.brew.sh/api/cask/codex.json
        └── { "version": "X.X.X" }
```

### 文件系统交互

```
~/.codex/version.json
{
    "latest_version": "0.11.0",
    "last_checked_at": "2024-01-15T10:30:00Z",
    "dismissed_version": "0.10.0"  // 用户跳过的版本
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 启动时需要访问 GitHub API 或 Homebrew API
   - 网络不可用时可能阻塞或失败
   - 缓解措施：后台异步检查，使用缓存值

2. **版本解析失败**
   - GitHub tag 格式不符合预期（`rust-vX.X.X`）
   - 预发布版本（`-beta`, `-rc`）比较可能不准确
   - 缓解措施：`is_newer()` 返回 `Option<bool>`，失败时视为不更新

3. **更新命令执行风险**
   - 自动执行包管理器命令可能失败
   - 权限问题（全局安装需要 sudo）
   - 缓解措施：仅显示命令，由用户确认后执行

4. **平台差异**
   - Homebrew 仅支持 macOS
   - Windows 更新方式未明确定义

### 边界情况

| 场景 | 行为 |
|-----|------|
| 首次使用（无 version.json） | 创建新文件，记录检查结果 |
| 用户跳过版本后又有新版本 | 显示提示（因为 dismissed_version ≠ latest） |
| 检查间隔 < 20小时 | 使用缓存值，不发起网络请求 |
| 网络请求失败 | 使用缓存值，后台记录错误 |
| 无法检测安装方式 | 不显示提示（`get_update_action()` 返回 None） |
| 当前版本 > 最新版本 | 不显示提示（本地使用开发版本） |

### 改进建议

1. **离线模式支持**
   ```rust
   // 添加配置项
   pub check_for_update_on_startup: bool,  // 已有
   pub update_check_timeout: Duration,      // 新增：超时时间
   pub offline_mode: bool,                  // 新增：完全禁用更新检查
   ```

2. **更灵活的更新源**
   - 支持自定义镜像源（企业内网）
   - 支持代理配置

3. **更新日志预览**
   - 在 TUI 内显示 release notes 摘要
   - 避免用户需要打开浏览器

4. **自动更新选项**
   ```rust
   pub enum UpdatePreference {
       Ask,           // 当前行为
       AutoUpdate,    // 自动下载并提示重启
       NotifyOnly,    // 仅通知，不执行
       Silent,        // 完全静默
   }
   ```

5. **安全增强**
   - 验证下载包的签名
   - 支持 checksum 校验

6. **测试改进**
   - 添加模拟 API 服务器的集成测试
   - 测试各种版本号比较边界
   - 测试网络超时和错误处理

7. **可访问性**
   - 为屏幕阅读器优化提示文本
   - 支持高对比度主题

8. **国际化**
   - 更新提示文本本地化
   - 版本号格式遵循区域设置
