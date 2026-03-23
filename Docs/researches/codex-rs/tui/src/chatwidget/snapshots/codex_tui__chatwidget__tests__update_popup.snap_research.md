# 研究报告: update_popup.snap

## 场景与职责

该快照文件验证 **版本更新提示弹窗** 的渲染效果。当检测到有新版本可用时，Codex 会显示此弹窗提示用户更新。

**注意**：该快照的 `source` 字段指向 `tui/src/chatwidget/tests.rs`，但在当前代码库中未找到对应的测试函数。这可能是一个遗留快照，或测试已被迁移/重命名。实际实现位于 `update_prompt.rs`。

## 功能点目的

**版本更新提示**：

1. **版本感知** - 通知用户有新版本可用
2. **更新选项** - 提供多种更新选择（立即/稍后/不再提醒）
3. **发布说明** - 提供发布说明链接
4. **非强制** - 允许用户跳过更新继续使用

## 具体技术实现

### 实际实现（update_prompt.rs）

```rust
// update_prompt.rs:35-84
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

    let mut screen = UpdatePromptScreen::new(
        tui.frame_requester(), 
        latest_version.clone(), 
        update_action
    );
    
    // 渲染并处理用户输入
    // ...
    
    match screen.selection() {
        Some(UpdateSelection::UpdateNow) => {
            Ok(UpdatePromptOutcome::RunUpdate(update_action))
        }
        Some(UpdateSelection::NotNow) | None => {
            Ok(UpdatePromptOutcome::Continue)
        }
        Some(UpdateSelection::DontRemind) => {
            updates::dismiss_version(config, screen.latest_version()).await?;
            Ok(UpdatePromptOutcome::Continue)
        }
    }
}
```

### 弹窗渲染

```rust
// update_prompt.rs:184-239
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
            format!("{current} -> {latest}", 
                current = self.current_version,
                latest = self.latest_version
            ).dim(),
        ]));
        column.push("");
        column.push(
            Line::from(vec![
                "Release notes: ".dim(),
                "https://github.com/openai/codex/releases/latest"
                    .dim()
                    .underlined(),
            ])
            .inset(Insets::tlbr(0, 2, 0, 0)),
        );
        column.push("");
        column.push(selection_option_row(
            0,
            format!("Update now (runs `{update_command}`)"),
            self.highlighted == UpdateSelection::UpdateNow,
        ));
        column.push(selection_option_row(
            1,
            "Skip".to_string(),
            self.highlighted == UpdateSelection::NotNow,
        ));
        column.push(selection_option_row(
            2,
            "Skip until next version".to_string(),
            self.highlighted == UpdateSelection::DontRemind,
        ));
        // ...
    }
}
```

### 渲染输出

```
  ✨ New version available! Would you like to update?

  Full release notes: https://github.com/openai/codex/releases/latest


› 1. Yes, update now
  2. No, not now
  3. Don't remind me

  Press enter to confirm or esc to go back
```

**解析**：
- 标题 `✨ New version available!`
- 发布说明链接
- 三个选项：立即更新 / 稍后 / 不再提醒
- 底部操作提示

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/update_prompt.rs` | 1-313 | 更新提示实现 |
| `codex-rs/tui/src/updates.rs` | - | 版本检查逻辑 |
| `codex-rs/tui/src/update_action.rs` | - | 更新操作定义 |

## 依赖与外部交互

### 版本检查

```rust
// updates.rs
pub(crate) fn get_upgrade_version_for_popup(config: &Config) -> Option<String> {
    // 检查是否有新版本（排除已忽略的）
    let latest = fetch_latest_version()?;
    if is_dismissed(config, &latest) {
        return None;
    }
    Some(latest)
}
```

### UpdateAction

```rust
pub(crate) enum UpdateAction {
    NpmGlobalLatest,    // npm install -g @openai/codex@latest
    CargoInstall,       // cargo install codex
    // ...
}
```

## 风险、边界与改进建议

### 特定风险

1. **网络依赖** - 版本检查需要网络连接
2. **更新失败** - 更新命令可能执行失败
3. **配置丢失** - 更新可能导致配置重置

### 边界情况

1. **开发版本** - 本地开发版本如何处理
2. **回滚需求** - 更新后需要回滚的情况
3. **企业环境** - 受管理环境的更新限制

### 改进建议

1. **更新日志** - 弹窗中直接显示更新摘要
2. **自动更新** - 提供自动更新选项
3. **更新确认** - 更新成功后显示确认
4. **版本对比** - 显示当前和新版本的详细对比

### 相关测试

- `update_prompt_modal`（在 update_prompt.rs 内）- 实际测试位于 `update_prompt.rs:261-268`
