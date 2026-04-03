# Research: user_shell_ls_output (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中用户通过 `!` 前缀执行的 shell 命令输出渲染效果。当用户在聊天输入框中使用 `!ls` 等命令时，Codex 会执行该命令并将输出以特定的格式显示在历史记录中。

**测试目的**：确保用户 shell 命令的输出在历史记录中正确渲染，包括命令标识、输出内容和格式化。

## 功能点目的

1. **用户命令标识**：区分用户主动执行的命令和 Agent 执行的工具调用
2. **输出展示**：清晰展示命令的输出结果
3. **格式化渲染**：使用合适的缩进和样式区分命令和输出
4. **历史记录集成**：将用户命令执行结果纳入对话历史

## 具体技术实现

### Snapshot 内容
```
---
source: tui_app_server/src/chatwidget/tests.rs
expression: blob
---
• You ran ls
  └ file1
    file2
```

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`user_shell_command_renders_output_not_exploring` (约 line 8820)

2. **测试执行流程**：
```rust
#[tokio::test]
async fn user_shell_command_renders_output_not_exploring() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

    // 1. 开始执行用户 shell 命令
    let begin_ls = begin_exec_with_source(
        &mut chat,
        "user-shell-ls",
        "ls",
        ExecCommandSource::UserShell,  // 关键：指定来源为用户 shell
    );
    
    // 2. 结束执行，设置输出
    end_exec(&mut chat, begin_ls, "file1\nfile2\n", "", 0);

    // 3. 获取历史记录单元格
    let cells = drain_insert_history(&mut rx);
    let blob = lines_to_single_string(cells.first().unwrap());
    
    // 4. 验证 snapshot
    assert_snapshot!("user_shell_ls_output", blob);
}
```

3. **执行单元格创建**：
   - 文件：`codex-rs/tui_app_server/src/exec_cell/render.rs`
   - 函数：`new_active_exec_command` (约 line 40)
   - 关键参数：`source: ExecCommandSource::UserShell`

4. **命令显示渲染**：
   - 文件：`codex-rs/tui_app_server/src/exec_cell/render.rs`
   - 方法：`ExecCell::command_display_lines` (约 line 356)
   - 关键逻辑：根据 `call.is_user_shell_command()` 显示 "You ran" 标题

5. **用户 shell 命令检测**：
   - 文件：`codex-rs/tui_app_server/src/exec_cell/model.rs`
   - 方法：`ExecCall::is_user_shell_command()`
   - 实现：
```rust
pub(crate) fn is_user_shell_command(&self) -> bool {
    matches!(self.source, ExecCommandSource::UserShell)
}
```

6. **输出格式化**：
   - 文件：`codex-rs/tui_app_server/src/exec_cell/render.rs`
   - 函数：`output_lines` (约 line 99)
   - 常量：`USER_SHELL_TOOL_CALL_MAX_LINES = 50`（用户 shell 命令输出限制）

### 数据结构

```rust
// 执行调用
pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,
    pub(crate) source: ExecCommandSource,  // 命令来源
    pub(crate) start_time: Option<Instant>,
    pub(crate) duration: Option<Duration>,
    pub(crate) interaction_input: Option<String>,
}

// 命令来源枚举
pub(crate) enum ExecCommandSource {
    Agent,           // Agent 执行的工具调用
    UserShell,       // 用户通过 ! 前缀执行的命令
    UnifiedExecStartup,     // 统一执行启动
    UnifiedExecInteraction, // 统一执行交互
}

// 命令输出
pub(crate) struct CommandOutput {
    pub(crate) exit_code: i32,
    pub(crate) aggregated_output: String,  // 原始输出
    pub(crate) formatted_output: String,   // 格式化后的输出
}
```

### 渲染逻辑

```rust
fn command_display_lines(&self, width: u16) -> Vec<Line<'static>> {
    // ...
    let title = if is_interaction {
        ""
    } else if self.is_active() {
        "Running"
    } else if call.is_user_shell_command() {
        "You ran"  // 用户 shell 命令特殊标题
    } else {
        "Ran"
    };
    // ...
}
```

### 输出渲染参数

对于用户 shell 命令，使用特殊的输出限制：

```rust
let line_limit = if call.is_user_shell_command() {
    USER_SHELL_TOOL_CALL_MAX_LINES  // 50 行
} else {
    TOOL_CALL_MAX_LINES  // 5 行
};
```

### 显示布局

```rust
const EXEC_DISPLAY_LAYOUT: ExecDisplayLayout = ExecDisplayLayout::new(
    PrefixedBlock::new("  │ ", "  │ "),  // 命令续行前缀
    /*command_continuation_max_lines*/ 2,
    PrefixedBlock::new("  └ ", "    "),  // 输出块前缀
    /*output_max_lines*/ 5,
);
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `exec_cell::model` | ExecCell 和 ExecCall 数据结构 |
| `exec_cell::render` | 渲染逻辑和输出格式化 |
| `exec_command` | 命令处理和 bash 转义 |
| `render::highlight` | 命令语法高亮 |
| `wrapping` | 文本换行处理 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `ExecCommandSource` | `codex_protocol::protocol` |
| `ExecCommandBeginEvent` | `codex_protocol::protocol` |
| `ExecCommandEndEvent` | `codex_protocol::protocol` |

### 渲染依赖
- `ratatui::text::Line`：文本行渲染
- `ansi_escape_line`：ANSI 转义序列处理
- `adaptive_wrap_lines`：自适应文本换行

## 风险、边界与改进建议

### 当前风险
1. **输出长度**：用户 shell 命令可能产生大量输出，需要适当的截断和提示
2. **特殊字符**：命令输出可能包含 ANSI 转义序列，需要正确处理
3. **二进制输出**：用户可能意外执行产生二进制输出的命令
4. **安全提示**：执行某些命令（如 `rm`）时可能需要额外的警告

### 边界情况
1. **空输出**：命令执行成功但无输出时的显示
2. **错误输出**：命令执行失败时的错误信息显示
3. **长行截断**：单行输出过长时的换行处理
4. **多行命令**：复杂命令的显示和换行
5. **交互式命令**：需要用户输入的命令处理

### 改进建议
1. **输出折叠**：对于长输出，提供折叠/展开功能
2. **语法高亮**：对命令输出进行语法高亮（如 JSON、XML）
3. **复制功能**：允许用户复制命令输出
4. **输出搜索**：在历史记录中搜索命令输出
5. **命令历史**：记录和快速访问常用的用户 shell 命令
6. **安全确认**：对危险命令（如 `rm -rf`）添加确认提示
7. **超时处理**：为长时间运行的命令添加超时提示

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__user_shell_ls_output.snap` 保持平行实现
- 遵循 AGENTS.md 中 "TUI code conventions" 的平行实现约定
- `tui_app_server/src/exec_cell/` 与 `tui/src/exec_cell/` 功能对应
- 任何对 TUI 版本的修改应同步到 App Server 版本

### 相关测试
- `bang_shell_command_submits_run_user_shell_command_in_app_server_tui`：测试 `!` 命令提交
- `user_shell_output_is_limited_by_screen_lines`：测试输出截断逻辑
- `exploring_stepX_*` 系列测试：测试 Agent 执行的探索性命令（与用户 shell 命令区分）
