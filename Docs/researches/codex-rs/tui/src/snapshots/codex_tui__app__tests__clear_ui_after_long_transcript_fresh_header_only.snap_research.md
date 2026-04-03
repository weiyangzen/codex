# Clear UI Fresh Header 研究文档

## 场景与职责

该组件负责在 Codex TUI 执行 `/clear` 命令后，重新渲染一个干净的 UI 头部区域。当用户长时间使用 Codex 后，终端历史记录可能变得非常长，此时用户可以通过 `/clear` 命令清除界面并重新开始，而这个快照展示了清除后显示的全新头部信息。

## 功能点目的

`clear_ui_header_lines` 函数的主要目的是：

1. **提供干净的启动界面**：在清除长对话历史后，给用户一个清新的视觉起点
2. **显示关键配置信息**：展示当前模型、推理努力级别和工作目录
3. **保持上下文连续性**：即使清除 UI，用户仍能看到当前会话的配置状态
4. **支持版本信息展示**：显示 Codex CLI 的版本号

## 具体技术实现

### 核心函数
```rust
fn clear_ui_header_lines(&self, width: u16) -> Vec<Line<'static>> {
    self.clear_ui_header_lines_with_version(width, CODEX_CLI_VERSION)
}

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

### 头部信息结构

头部区域采用带边框的卡片式布局，包含以下信息：

```
╭─────────────────────────────────────────────╮
│ >_ OpenAI Codex (v<VERSION>)                │  <- 标题行
│                                             │  <- 空行
│ model:     gpt-test high   /model to change │  <- 模型信息
│ directory: /tmp/project                     │  <- 工作目录
╰─────────────────────────────────────────────╯
```

### 数据流

1. **触发清除**：用户输入 `/clear` 命令
2. **调用链**：`AppEvent::ClearUi` → `clear_terminal_ui()` → `queue_clear_ui_header()`
3. **头部生成**：`clear_ui_header_lines()` 收集当前配置状态
4. **渲染输出**：通过 `tui.insert_history_lines()` 将头部行插入终端历史

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `clear_ui_header_lines` 方法（第 1201-1203 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `clear_ui_header_lines_with_version` 方法（第 1183-1199 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `queue_clear_ui_header` 方法（第 1205-1212 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `clear_terminal_ui` 方法（第 1214-1241 行） |
| `/home/sansha/Github/codex/codex-rs/tui/src/history_cell.rs` | `SessionHeaderHistoryCell` 结构体定义 |
| `/home/sansha/Github/codex/codex-rs/tui/src/app.rs` | `reset_app_ui_state_after_clear` 方法（第 1243-1250 行） |

### 调用流程
```
/clear 命令
    └── AppEvent::ClearUi
        ├── clear_terminal_ui(tui, redraw_header: false)
        ├── reset_app_ui_state_after_clear()
        └── start_fresh_session_with_summary_hint(tui)
            └── queue_clear_ui_header(tui)
                └── clear_ui_header_lines(width)
```

## 依赖与外部交互

### 依赖模块
- `history_cell::SessionHeaderHistoryCell` - 会话头部历史单元格
- `CODEX_CLI_VERSION` - 版本常量
- `ChatWidget` - 提供模型、推理努力级别等配置信息

### 配置信息来源
| 信息项 | 来源 |
|-------|------|
| 模型名称 | `chat_widget.current_model()` |
| 推理努力级别 | `chat_widget.current_reasoning_effort()` |
| Fast 状态 | `chat_widget.should_show_fast_status()` |
| 工作目录 | `config.cwd` |
| 版本号 | `CODEX_CLI_VERSION` 常量 |

### 渲染系统交互
- `tui.insert_history_lines()` - 将头部行插入终端历史
- `tui.terminal.set_viewport_area()` - 设置视口区域
- `tui.terminal.clear_scrollback_and_visible_screen_ansi()` - 清除屏幕

## 风险、边界与改进建议

### 边界情况

1. **窄终端宽度**：当终端宽度小于头部内容最小宽度时，可能导致布局错乱
2. **特殊路径字符**：工作目录包含特殊字符时可能影响显示
3. **模型名称长度**：超长模型名称可能破坏布局

### 潜在风险

1. **状态不同步**：如果 `ChatWidget` 和 `Config` 状态不一致，可能显示错误信息
2. **版本信息缺失**：`CODEX_CLI_VERSION` 未定义时编译失败
3. **清除后数据丢失**：`reset_app_ui_state_after_clear` 会清空 `transcript_cells`

### 改进建议

1. **响应式布局**：
   ```rust
   // 建议根据终端宽度动态调整布局
   fn adaptive_header_layout(width: u16) -> HeaderLayout {
       if width < 60 {
           HeaderLayout::Compact
       } else if width < 100 {
           HeaderLayout::Standard
       } else {
           HeaderLayout::Extended
       }
   }
   ```

2. **持久化头部信息**：
   ```rust
   // 建议将头部信息保存，支持恢复
   struct HeaderState {
       model: String,
       effort: ReasoningEffort,
       cwd: PathBuf,
       timestamp: Instant,
   }
   ```

3. **可定制头部**：
   ```rust
   // 建议支持用户自定义显示项
   struct HeaderConfig {
       show_version: bool,
       show_model: bool,
       show_cwd: bool,
       show_timestamp: bool,
   }
   ```

4. **主题支持**：
   - 当前使用固定颜色方案
   - 建议支持主题系统，允许自定义边框和文字颜色

### 相关测试
- `clear_ui_after_long_transcript_fresh_header_only` - 验证清除后头部显示
- `clear_ui_header_fast_status_gpt54_only` - 验证 Fast 状态显示
- 测试覆盖不同模型配置和终端宽度场景
