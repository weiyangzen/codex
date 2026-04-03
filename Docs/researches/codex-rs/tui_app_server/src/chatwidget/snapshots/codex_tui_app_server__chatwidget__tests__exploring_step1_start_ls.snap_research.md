# 研究文档：exploring_step1_start_ls

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中 "Exploring" 功能的第一步：开始执行文件列表命令（`ls -la`）。这是测试命令执行单元（ExecCell）探索模式（exploring mode）的系列测试的第一步。

**测试场景**：
- 代理开始执行探索性命令 `ls -la`
- 命令被解析为 `ListFiles` 类型
- ExecCell 处于活动状态（active），显示 "Exploring"
- 验证活动单元的显示内容

**Snapshot 内容**：
```
• Exploring
  └ List ls -la
```

## 功能点目的

1. **探索模式识别**：将 `ls` 等文件浏览命令识别为探索性操作
2. **活动状态指示**：使用 `•` 旋转器和 "Exploring" 标签表示命令正在执行
3. **命令分类显示**：将命令分类为 "List" 类型，而非通用的 "Run"
4. **视觉层次**：使用缩进和树形结构展示命令层级

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
#[tokio::test]
async fn exec_history_extends_previous_when_consecutive() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // 1) Start "ls -la" (List)
    let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
    assert_snapshot!("exploring_step1_start_ls", active_blob(&chat));
    
    // 后续步骤...
}

// 辅助函数：开始执行命令
fn begin_exec(chat: &mut ChatWidget, call_id: &str, raw_cmd: &str) -> ExecCommandBeginEvent {
    begin_exec_with_source(chat, call_id, raw_cmd, ExecCommandSource::Agent)
}

// 辅助函数：开始执行命令（带源）
fn begin_exec_with_source(
    chat: &mut ChatWidget,
    call_id: &str,
    raw_cmd: &str,
    source: ExecCommandSource,
) -> ExecCommandBeginEvent {
    // 构建命令向量
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    
    // 解析命令
    let parsed_cmd: Vec<ParsedCommand> =
        codex_shell_command::parse_command::parse_command(&command);
    
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let interaction_input = None;
    
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: None,
        turn_id: "turn-1".to_string(),
        command,
        cwd,
        parsed_cmd,
        source,
        interaction_input,
    };
    
    // 发送命令开始事件
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    
    event
}

// 辅助函数：获取活动单元内容
fn active_blob(chat: &ChatWidget) -> String {
    let lines = chat
        .active_cell
        .as_ref()
        .expect("active cell present")
        .display_lines(80);
    lines_to_single_string(&lines)
}
```

### 探索模式判定

位于 `codex-rs/tui_app_server/src/exec_cell/model.rs`：

```rust
impl ExecCell {
    pub(super) fn is_exploring_call(call: &ExecCall) -> bool {
        !matches!(call.source, ExecCommandSource::UserShell)
            && !call.parsed.is_empty()
            && call.parsed.iter().all(|p| {
                matches!(
                    p,
                    ParsedCommand::Read { .. }
                        | ParsedCommand::ListFiles { .. }
                        | ParsedCommand::Search { .. }
                )
            })
    }
}
```

### 渲染逻辑

位于 `codex-rs/tui_app_server/src/exec_cell/render.rs`：

```rust
impl ExecCell {
    fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut out: Vec<Line<'static>> = Vec::new();
        
        // 标题行：• Exploring（活动）或 • Explored（完成）
        out.push(Line::from(vec![
            if self.is_active() {
                spinner(self.active_start_time(), self.animations_enabled())
            } else {
                "•".dim()
            },
            " ".into(),
            if self.is_active() {
                "Exploring".bold()
            } else {
                "Explored".bold()
            },
        ]));
        
        // 命令列表...
        for call in &self.calls {
            // 根据命令类型生成显示文本
            for parsed in &call.parsed {
                match parsed {
                    ParsedCommand::ListFiles { cmd, path } => {
                        lines.push(("List", vec![path.clone().unwrap_or(cmd.clone()).into()]));
                    }
                    // ...
                }
            }
        }
        
        // 添加缩进前缀
        out.extend(prefix_lines(out_indented, "  └ ".dim(), "    ".into()));
        out
    }
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现 |
| `codex-rs/tui_app_server/src/exec_cell/model.rs` | ExecCell 数据模型，探索模式判定 |
| `codex-rs/tui_app_server/src/exec_cell/render.rs` | ExecCell 渲染逻辑 |
| `codex-rs/tui_app_server/src/exec_cell/mod.rs` | ExecCell 模块导出 |

### 相关数据结构

```rust
// 命令解析结果
codex_protocol::parse_command::ParsedCommand {
    Read { name: String, .. },           // 读取文件
    ListFiles { cmd: String, path: Option<String> },  // 列出文件
    Search { cmd: String, query: Option<String>, path: Option<String> },  // 搜索
    Unknown { cmd: String },             // 未知命令
}

// 命令执行事件
codex_protocol::protocol::ExecCommandBeginEvent {
    call_id: String,
    process_id: Option<u32>,
    turn_id: String,
    command: Vec<String>,      // ["bash", "-lc", "ls -la"]
    cwd: PathBuf,
    parsed_cmd: Vec<ParsedCommand>,
    source: ExecCommandSource, // Agent | UserShell | UnifiedExecInteraction
    interaction_input: Option<String>,
}
```

### 代码调用链

```
测试函数
    ↓
begin_exec(chat, "call-ls", "ls -la")
    ↓
parse_command(&command)  // 解析为 ListFiles
    ↓
ExecCommandBeginEvent → ChatWidget::handle_codex_event
    ↓
创建/更新 ExecCell（探索模式）
    ↓
active_blob(&chat) → ExecCell::display_lines()
    ↓
exploring_display_lines()（因为 is_exploring_cell() == true）
    ↓
生成 snapshot 内容
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_shell_command::parse_command` | 命令解析，识别命令类型 |
| `codex_protocol::parse_command::ParsedCommand` | 解析后的命令类型枚举 |
| `codex_protocol::protocol::ExecCommandBeginEvent` | 命令开始事件 |
| `ratatui::text::Line` | 文本行渲染 |

### 模块交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ChatWidget 层                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ handle_codex    │───▶│  更新/创建      │───▶│  active_cell    │ │
│  │ _event()        │    │  ExecCell       │    │  (探索模式)      │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        ExecCell 层                                   │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ is_exploring    │───▶│ exploring_      │───▶│ 分类显示        │ │
│  │ _cell()         │    │ display_lines() │    │ (List/Read/...) │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        渲染输出                                      │
│  • Exploring                                                        │
│    └ List ls -la                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **命令解析失败**：如果 `parse_command` 无法正确识别命令类型，可能无法进入探索模式
2. **源类型误判**：`UserShell` 源的命令不会进入探索模式，可能导致显示不一致
3. **旋转器性能**：动画旋转器在高频更新时可能影响性能

### 边界情况

| 场景 | 当前行为 | 注意事项 |
|-----|---------|---------|
| 空命令 | 不创建 ExecCell | 需确保事件处理健壮 |
| 解析失败 | `parsed_cmd` 为空，不进入探索模式 | 回退到普通命令显示 |
| 混合命令 | 不满足探索模式条件 | 按普通命令处理 |
| 超长路径 | 自动换行 | 需验证布局 |

### 改进建议

1. **命令解析增强**：
   - 支持更多文件浏览命令变体（如 `find`, `tree`）
   - 添加命令别名识别（如 `ll` → `ls -la`）

2. **显示优化**：
   ```rust
   // 建议：添加执行时间预估
   out.push(Line::from(vec![
       spinner(...),
       " ".into(),
       "Exploring".bold(),
       " (est. 2s)".dim(),  // 预估时间
   ]));
   ```

3. **测试扩展**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn exploring_step_with_parse_failure() {
       // 测试命令解析失败时的回退行为
   }
   
   #[tokio::test]
   async fn exploring_step_usershell_source() {
       // 测试 UserShell 源不进入探索模式
   }
   ```

4. **可访问性**：
   - 为非图形终端提供纯文本替代显示
   - 添加音频反馈选项

### 系列测试说明

本测试是 "exploring" 系列测试的第一步：

1. **`exploring_step1_start_ls`**（本测试）：开始 `ls -la`，状态 "Exploring"
2. **`exploring_step2_finish_ls`**：完成 `ls -la`，状态变为 "Explored"
3. **`exploring_step3_start_cat_foo`**：开始读取 `foo.txt`，追加到探索列表
4. **`exploring_step4_finish_cat_foo`**：完成读取 `foo.txt`
5. **`exploring_step5_finish_sed_range`**：完成 `sed` 范围读取（合并到同一文件）
6. **`exploring_step6_finish_cat_bar`**：完成读取 `bar.txt`（多个文件）

该系列测试完整验证了探索模式的：
- 活动/完成状态转换
- 多命令追加
- 同类操作合并（多个 Read 合并显示）
- 多文件显示
