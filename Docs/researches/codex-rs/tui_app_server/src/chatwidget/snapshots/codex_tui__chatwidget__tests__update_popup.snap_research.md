# Research: Update Popup

## 场景与职责

该 snapshot 测试验证当有新版本可用时，Codex TUI 显示的更新提示弹出框（Update Popup）的 UI 布局和文本内容。

**测试场景：**
- 检测到新版本可用（通过 npm 或 GitHub releases）
- 显示更新提示弹出框，提供更新选项
- 用户可以选择立即更新、稍后更新或不再提醒

**核心职责：**
1. 确保更新提示的 UI 布局稳定
2. 验证更新选项的显示和排序
3. 确保版本信息和发布说明链接正确显示

---

## 功能点目的

### 1. 版本检测与提示
Codex CLI 会定期检查是否有新版本可用。检测方式包括：
- npm 注册表查询（对于 npm 安装）
- GitHub releases API 查询

### 2. 更新选项提供
用户可以选择：
- **Yes, update now**: 立即执行更新命令
- **No, not now**: 跳过本次提示，下次启动再次提示
- **Don't remind me**: 不再提示，直到下一个版本

### 3. 更新操作执行
根据安装方式不同，执行不同的更新命令：
- npm: `npm install -g @openai/codex`
- 其他: 跳转到 GitHub releases 页面

---

## 具体技术实现

### 历史测试代码
**注意**: 该测试的原始代码已在后续版本中被移除，但 snapshot 文件保留用于参考。

**原始测试代码**（来自 git 历史）：
```rust
#[test]
fn update_popup_snapshot() {
    let _guard = EnvVarGuard::set("CODEX_MANAGED_BY_NPM", "1");
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual();

    chat.open_update_popup();

    let height = chat.desired_height(80);
    let mut terminal =
        crate::custom_terminal::Terminal::with_options(VT100Backend::new(80, height))
            .expect("create terminal");
    terminal.set_viewport_area(Rect::new(0, 0, 80, height));
    terminal
        .draw(|f| f.render_widget_ref(&chat, f.area()))
        .expect("render update popup");
    assert_snapshot!(
        "update_popup",
        terminal.backend().vt100().screen().contents()
    );
}
```

### 当前实现
当前更新提示功能已迁移到独立的 `update_prompt.rs` 模块：

**文件**: `codex-rs/tui/src/update_prompt.rs`

```rust
pub(crate) async fn run_update_prompt_if_needed(
    tui: &mut Tui,
    config: &Config,
) -> Result<UpdatePromptOutcome> {
    let Some(latest_version) = updates::get_upgrade_version_for_popup(config) else {
        return Ok(UpdatePromptOutcome::Continue);
    };
    let Some(update_action) = crate::update_action::get_update_action() else {
        return Ok(UpdatePromptOutcome::Continue);
    };

    let mut screen = UpdatePromptScreen::new(tui.frame_requester(), latest_version.clone(), update_action);
    // ... 渲染和事件处理
}
```

### UpdatePromptScreen 结构
```rust
struct UpdatePromptScreen {
    request_frame: FrameRequester,
    latest_version: String,
    current_version: String,
    update_action: UpdateAction,
    highlighted: UpdateSelection,
    selection: Option<UpdateSelection>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum UpdateSelection {
    UpdateNow,
    NotNow,
    DontRemind,
}
```

### 渲染实现
```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        let mut column = ColumnRenderable::new();

        let update_command = self.update_action.command_str();

        column.push("");
        column.push(Line::from(vec![
            padded_emoji("  ✨").bold().cyan(),
            "Update available!".bold(),
            " ".into(),
            format!("{current} -> {latest}", ...).dim(),
        ]));
        column.push("");
        column.push(Line::from(vec![
            "Release notes: ".dim(),
            "https://github.com/openai/codex/releases/latest"
                .dim()
                .underlined(),
        ]));
        // ... 选项渲染
    }
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/update_prompt.rs` | 更新提示屏幕实现 |
| `codex-rs/tui/src/updates.rs` | 版本检测逻辑 |
| `codex-rs/tui/src/update_action.rs` | 更新操作定义 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录中的更新提示单元格 |

### 关键类型和函数

| 类型/函数 | 位置 | 职责 |
|----------|------|------|
| `UpdatePromptScreen` | `update_prompt.rs:93` | 更新提示屏幕状态 |
| `UpdateSelection` | `update_prompt.rs:87` | 用户选择枚举 |
| `run_update_prompt_if_needed` | `update_prompt.rs:35` | 主入口函数 |
| `UpdateAction` | `update_action.rs` | 更新操作类型 |
| `UpdateAvailableHistoryCell` | `history_cell.rs:492` | 历史记录中的更新提示 |

### 更新操作类型

| 操作 | 命令 |
|-----|------|
| `NpmGlobalLatest` | `npm install -g @openai/codex@latest` |
| `NpmGlobalSpecific` | `npm install -g @openai/codex@{version}` |
| `CargoInstall` | `cargo install codex-cli` |

---

## 依赖与外部交互

### 内部依赖

```
tui/src/update_prompt.rs
├── tui/src/updates.rs (版本检测)
├── tui/src/update_action.rs (更新操作)
├── tui/src/render/ (渲染工具)
├── tui/src/selection_list.rs (选择列表)
└── codex_core::config::Config (配置)
```

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| npm registry API | 检测最新版本（npm 安装） |
| GitHub releases API | 检测最新版本（其他安装方式） |
| `CARGO_PKG_VERSION` | 获取当前版本 |

### 配置项

| 配置 | 说明 |
|-----|------|
| `CODEX_MANAGED_BY_NPM` | 环境变量，指示是否由 npm 管理 |
| `dismissed_version` | 用户选择"不再提醒"的版本 |

---

## 风险、边界与改进建议

### 潜在风险

1. **版本检测失败**
   - 网络问题可能导致版本检测失败
   - **缓解**: 静默失败，不显示更新提示

2. **更新命令执行失败**
   - 权限问题可能导致更新命令失败
   - **缓解**: 显示错误信息，提供手动更新指导

3. **版本比较错误**
   - 版本号解析错误可能导致错误提示
   - **缓解**: 使用语义化版本规范进行比较

### 边界情况

| 场景 | 行为 |
|-----|------|
| 无网络连接 | 静默跳过版本检测 |
| 已是最新版本 | 不显示更新提示 |
| 用户选择"不再提醒" | 记录版本，下次跳过 |
| 开发版本（git） | 不显示更新提示 |
| 未知安装方式 | 显示 GitHub releases 链接 |

### 改进建议

1. **添加强制更新选项**
   - 对于关键安全更新，可以强制用户更新

2. **显示更新日志摘要**
   - 在弹出框中显示新版本的亮点功能

3. **支持自动更新**
   - 允许用户配置自动更新

4. **改进版本检测**
   - 添加缓存机制，减少 API 调用
   - 支持离线模式

5. **添加更新进度显示**
   - 更新过程中显示进度条

---

## Snapshot 内容分析

```
  ✨ New version available! Would you like to update?

  Full release notes: https://github.com/openai/codex/releases/latest


› 1. Yes, update now
  2. No, not now
  3. Don't remind me

  Press enter to confirm or esc to go back
```

**观察要点：**
1. 使用 ✨ 表情符号吸引注意
2. 提供完整的发布说明链接
3. 选项使用编号列表，默认选中第一项
4. 底部显示操作提示（Enter 确认，Esc 返回）
5. 整体布局居中，视觉层次清晰

**注意**: 当前 snapshot 中的文本与 `update_prompt.rs` 中的实现略有不同，说明 UI 已经过迭代优化。
