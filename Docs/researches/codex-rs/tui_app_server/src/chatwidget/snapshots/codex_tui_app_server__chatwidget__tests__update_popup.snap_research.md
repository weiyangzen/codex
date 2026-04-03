# Research: update_popup (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中版本更新提示弹出框的渲染效果。当检测到有新版本的 Codex CLI 可用时，会显示一个模态框提示用户进行更新，提供多种选项供用户选择如何处理更新。

**测试目的**：确保版本更新提示弹出框的 UI 布局、文本格式和交互选项正确渲染。

**注意**：此 snapshot 文件在 tui_app_server 项目中为遗留/同步文件，原始测试位于 `codex-rs/tui/src/chatwidget/tests.rs`。根据 AGENTS.md 的平行实现约定，tui_app_server 与 tui 保持功能平行。

## 功能点目的

1. **版本更新检测**：检测到有新版本可用时向用户展示更新提示
2. **更新选项提供**：提供多种处理更新的选项（立即更新、稍后提醒、不再提醒）
3. **发布说明链接**：提供链接到 GitHub 发布页面查看详细更新内容
4. **键盘交互支持**：支持 Enter 确认和 Esc 返回的键盘操作

## 具体技术实现

### Snapshot 内容
```
---
source: tui/src/chatwidget/tests.rs
expression: terminal.backend().vt100().screen().contents()
---
  ✨ New version available! Would you like to update?

  Full release notes: https://github.com/openai/codex/releases/latest


› 1. Yes, update now
  2. No, not now
  3. Don't remind me

  Press enter to confirm or esc to go back
```

### 关键代码路径

1. **更新提示屏幕结构**（tui 项目参考实现）：
   - 文件：`codex-rs/tui/src/update_prompt.rs`
   - 结构：`UpdatePromptScreen`
   - 方法：`new`, `handle_key`, `render_ref`

2. **App Server 对应实现**：
   - 文件：`codex-rs/tui_app_server/src/update_prompt.rs`
   - 结构：`UpdatePromptScreen`
   - 方法：`new`, `handle_key`, `render_ref`

3. **更新检测逻辑**：
   - 文件：`codex-rs/tui_app_server/src/updates.rs`
   - 函数：`get_upgrade_version_for_popup`
   - 功能：检查是否有新版本可用

4. **更新动作执行**：
   - 文件：`codex-rs/tui_app_server/src/update_action.rs`
   - 枚举：`UpdateAction`
   - 功能：定义不同安装方式下的更新命令

### 数据结构

```rust
// 更新提示屏幕状态
struct UpdatePromptScreen {
    request_frame: FrameRequester,
    latest_version: String,
    current_version: String,
    update_action: UpdateAction,
    highlighted: UpdateSelection,
    selection: Option<UpdateSelection>,
}

// 用户选择枚举
enum UpdateSelection {
    UpdateNow,   // 立即更新
    NotNow,      // 稍后提醒
    DontRemind,  // 不再提醒
}

// 更新动作
pub(crate) enum UpdateAction {
    NpmGlobalLatest,    // npm 全局安装最新版
    BrewUpgrade,        // Homebrew 升级
    // ... 其他安装方式
}
```

### 渲染实现

```rust
impl WidgetRef for &UpdatePromptScreen {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        Clear.render(area, buf);
        let mut column = ColumnRenderable::new();
        
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
            "https://github.com/openai/codex/releases/latest"
                .dim()
                .underlined(),
        ]));
        
        // 选项列表
        column.push(selection_option_row(0, "Update now...", ...));
        column.push(selection_option_row(1, "Skip", ...));
        column.push(selection_option_row(2, "Skip until next version", ...));
        
        column.render(area, buf);
    }
}
```

### 键盘事件处理

| 按键 | 动作 |
|------|------|
| `↑` / `k` | 选择上一个选项 |
| `↓` / `j` | 选择下一个选项 |
| `1` | 直接选择"立即更新" |
| `2` | 直接选择"跳过" |
| `3` | 直接选择"跳过直到下一版本" |
| `Enter` | 确认当前选择 |
| `Esc` | 取消（等同于选择"跳过"） |
| `Ctrl+C` / `Ctrl+D` | 取消更新 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `update_prompt` | 更新提示屏幕主逻辑 |
| `update_action` | 更新动作定义和执行 |
| `updates` | 版本检测和更新检查 |
| `selection_list` | 选项列表渲染 |
| `history_cell` | 表情符号和文本格式化 |

### 外部依赖
| 类型 | 来源 |
|------|------|
| `Config` | `codex_core::config` |
| GitHub API | 检查最新版本发布 |

### 渲染依赖
- `ratatui::Terminal` + `VT100Backend`：终端渲染
- `ColumnRenderable`：列式布局渲染
- `selection_option_row`：选项行渲染

## 风险、边界与改进建议

### 当前风险
1. **网络依赖**：版本检查依赖 GitHub API 可用性
2. **版本解析**：需要正确解析语义化版本号
3. **更新命令兼容性**：不同安装方式（npm/brew/等）的更新命令可能变化

### 边界情况
1. **离线环境**：无法访问 GitHub 时应静默失败
2. **预发布版本**：如何处理 alpha/beta 版本提示
3. **版本回滚**：用户手动降级后不应立即再次提示
4. **频繁检查**：避免过于频繁的版本检查影响性能

### 改进建议
1. **更新频率控制**：添加配置选项控制检查频率（每日/每周/每月）
2. **更新日志预览**：在弹出框中显示简要的更新日志摘要
3. **自动更新选项**：提供后台自动更新功能（适用于特定安装方式）
4. **更新大小提示**：显示预计下载大小
5. **断点续传**：大文件更新支持断点续传

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__update_popup.snap` 保持平行实现
- 遵循 AGENTS.md 中 "TUI code conventions" 的平行实现约定
- `tui_app_server/src/update_prompt.rs` 与 `tui/src/update_prompt.rs` 功能对应
- 任何对 TUI 版本的修改应同步到 App Server 版本
