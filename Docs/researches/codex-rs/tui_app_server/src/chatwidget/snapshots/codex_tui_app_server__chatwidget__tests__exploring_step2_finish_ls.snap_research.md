# 研究文档：exploring_step2_finish_ls

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中 "Exploring" 功能的第二步：完成文件列表命令（`ls -la`）的执行。这是探索模式系列测试的第二步，验证命令完成后的状态转换。

**测试场景**：
- 代理已完成执行 `ls -la` 命令
- 命令成功结束（exit code 0）
- ExecCell 从活动状态（"Exploring"）转换为完成状态（"Explored"）
- 验证完成后的显示内容

**Snapshot 内容**：
```
• Explored
  └ List ls -la
```

## 功能点目的

1. **状态转换指示**：清晰区分正在进行的探索（"Exploring"）和已完成的探索（"Explored"）
2. **完成确认**：使用静态的 `•` 符号替代旋转器，表示操作已完成
3. **历史记录保留**：保留已完成的探索命令，便于用户回顾代理的操作轨迹
4. **视觉一致性**：保持与活动状态相同的布局结构，仅改变状态标签

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

    // 2) Finish "ls -la"
    end_exec(&mut chat, begin_ls, "", "", 0);
    assert_snapshot!("exploring_step2_finish_ls", active_blob(&chat));
    
    // 后续步骤...
}

// 辅助函数：结束命令执行
fn end_exec(
    chat: &mut ChatWidget,
    begin_event: ExecCommandBeginEvent,
    stdout: &str,
    stderr: &str,
    exit_code: i32,
) {
    // 合并 stdout 和 stderr
    let aggregated = if stderr.is_empty() {
        stdout.to_string()
    } else {
        format!("{stdout}{stderr}")
    };
    
    let ExecCommandBeginEvent {
        call_id,
        turn_id,
        command,
        cwd,
        parsed_cmd,
        source,
        interaction_input,
        process_id,
    } = begin_event;
    
    // 发送命令结束事件
    chat.handle_codex_event(Event {
        id: call_id.clone(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id,
            turn_id,
            command,
            cwd,
            parsed_cmd,
            source,
            interaction_input,
            process_id,
            aggregated_output: aggregated,
            formatted_output: stdout.to_string(),
            exit_code,
            // ... 其他字段
        }),
    });
}
```

### 状态判定逻辑

位于 `codex-rs/tui_app_server/src/exec_cell/model.rs`：

```rust
impl ExecCell {
    pub(crate) fn is_active(&self) -> bool {
        // 只要有一个调用没有输出，就认为是活动状态
        self.calls.iter().any(|c| c.output.is_none())
    }
    
    pub(crate) fn active_start_time(&self) -> Option<Instant> {
        // 返回第一个活动调用的开始时间
        self.calls
            .iter()
            .find(|c| c.output.is_none())
            .and_then(|c| c.start_time)
    }
}
```

### 渲染状态差异

位于 `codex-rs/tui_app_server/src/exec_cell/render.rs`：

```rust
impl ExecCell {
    fn exploring_display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut out: Vec<Line<'static>> = Vec::new();
        
        // 根据 is_active() 决定显示 "Exploring" 还是 "Explored"
        out.push(Line::from(vec![
            if self.is_active() {
                // 活动状态：显示动画旋转器
                spinner(self.active_start_time(), self.animations_enabled())
            } else {
                // 完成状态：显示静态圆点
                "•".dim()
            },
            " ".into(),
            if self.is_active() {
                "Exploring".bold()
            } else {
                "Explored".bold()
            },
        ]));
        
        // ... 命令列表渲染
    }
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现 |
| `codex-rs/tui_app_server/src/exec_cell/model.rs` | ExecCell 状态管理 |
| `codex-rs/tui_app_server/src/exec_cell/render.rs` | 状态敏感的渲染逻辑 |

### 相关数据结构

```rust
// 命令结束事件
codex_protocol::protocol::ExecCommandEndEvent {
    call_id: String,
    turn_id: String,
    command: Vec<String>,
    cwd: PathBuf,
    parsed_cmd: Vec<ParsedCommand>,
    source: ExecCommandSource,
    interaction_input: Option<String>,
    process_id: Option<u32>,
    aggregated_output: String,    // 合并的输出
    formatted_output: String,     // 格式化后的输出
    exit_code: i32,               // 退出码（0 表示成功）
    // ... 其他字段
}

// ExecCall 结构（内部状态）
pub(crate) struct ExecCall {
    pub(crate) call_id: String,
    pub(crate) command: Vec<String>,
    pub(crate) parsed: Vec<ParsedCommand>,
    pub(crate) output: Option<CommandOutput>,  // None = 活动，Some = 完成
    pub(crate) source: ExecCommandSource,
    pub(crate) start_time: Option<Instant>,    // 活动时有值
    pub(crate) duration: Option<Duration>,     // 完成后设置
    pub(crate) interaction_input: Option<String>,
}
```

### 状态转换流程

```
ExecCommandBeginEvent
    ↓
创建 ExecCell，ExecCall.output = None
    ↓
is_active() = true → 显示 "Exploring" + 旋转器
    ↓
ExecCommandEndEvent
    ↓
ExecCell::complete_call() 设置 output = Some(...)
    ↓
is_active() = false → 显示 "Explored" + 静态圆点
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::protocol::ExecCommandEndEvent` | 命令结束事件定义 |
| `ratatui::style::Stylize` | 样式控制（dim, bold） |
| `std::time::{Instant, Duration}` | 时间追踪 |

### 模块交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                        事件流                                        │
│                                                                     │
│  ExecCommandBeginEvent                                              │
│       │                                                             │
│       ▼                                                             │
│  ┌─────────────┐    output: None    ┌─────────────┐                │
│  │  ExecCall   │───────────────────▶│  活动状态    │                │
│  │   创建      │                    │             │                │
│  └─────────────┘                    └──────┬──────┘                │
│                                            │                        │
│  ExecCommandEndEvent                       │                        │
│       │                                    │                        │
│       ▼                                    ▼                        │
│  ┌─────────────┐    output: Some   ┌─────────────┐                │
│  │ complete_   │──────────────────▶│  完成状态    │                │
│  │ _call()     │    duration: Some │  "Explored"  │                │
│  └─────────────┘                   └─────────────┘                │
└─────────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **状态竞争**：如果在处理 `ExecCommandEndEvent` 时发生中断，可能导致状态不一致
2. **输出丢失**：`aggregated_output` 为空时，用户无法了解命令实际做了什么
3. **错误处理**：当前 snapshot 使用 exit_code 0（成功），失败情况未在此测试覆盖

### 边界情况

| 场景 | 当前行为 | 测试覆盖 |
|-----|---------|---------|
| 成功完成（exit_code 0） | 显示 "Explored" | ✅ 本测试覆盖 |
| 失败完成（exit_code ≠ 0） | 未明确测试 | ❌ 需额外测试 |
| 无输出完成 | 显示空内容 | ⚠️ 本测试 stdout="" |
| 大量输出 | 可能截断 | ❌ 未测试 |

### 改进建议

1. **失败状态区分**：
   ```rust
   // 建议：区分成功和失败的探索
   if self.is_active() {
       "Exploring".bold()
   } else if self.all_succeeded() {
       "Explored".bold()
   } else {
       "Explored (with errors)".red().bold()
   }
   ```

2. **输出摘要**：
   ```rust
   // 建议：显示输出摘要
   if !aggregated_output.is_empty() {
       let summary = summarize_output(&aggregated_output);
       lines.push(format!("  └ {} files found", summary.file_count).dim());
   }
   ```

3. **测试扩展**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn exploring_step_with_error() {
       // 测试命令失败时的显示（exit_code ≠ 0）
       let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
       end_exec(&mut chat, begin_ls, "", "Permission denied", 1);
       // 验证错误状态显示
   }
   
   #[tokio::test]
   async fn exploring_step_with_output() {
       // 测试有输出的命令完成
       let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");
       end_exec(&mut chat, begin_ls, "file1\nfile2\n", "", 0);
       // 验证输出摘要显示
   }
   ```

4. **性能优化**：
   - 对于大量输出，考虑延迟加载或分页显示
   - 缓存渲染结果，避免重复计算

### 系列测试上下文

本测试是 "exploring" 系列测试的第二步：

| 步骤 | Snapshot | 状态 | 操作 |
|-----|----------|------|------|
| 1 | `exploring_step1_start_ls` | Exploring | 开始 `ls -la` |
| 2 | `exploring_step2_finish_ls` | **Explored** | **完成 `ls -la`** |
| 3 | `exploring_step3_start_cat_foo` | Exploring | 开始读取 `foo.txt` |
| 4 | `exploring_step4_finish_cat_foo` | Explored | 完成读取 `foo.txt` |
| 5 | `exploring_step5_finish_sed_range` | Explored | 完成 `sed` 范围读取 |
| 6 | `exploring_step6_finish_cat_bar` | Explored | 完成读取 `bar.txt` |

从本测试开始，后续测试都基于 "Explored" 状态，验证探索模式的命令追加和合并行为。
