# 研究文档：探索步骤1 - 开始 ls 命令

## 场景与职责

该快照测试是探索模式系列测试的第一步，验证当 Codex 开始执行目录列表命令（`ls -la`）时，活动单元格的显示状态。

**测试场景**：
- Codex 开始探索工作目录
- 第一个操作是列出目录内容 (`ls -la`)
- 验证活动单元格显示 "Exploring" 状态

## 功能点目的

1. **探索模式识别**：区分探索性命令（ls、cat、grep 等）和普通命令执行
2. **状态可视化**：显示当前正在进行的探索操作
3. **进度跟踪**：让用户了解 Codex 正在进行的文件系统探索

## 具体技术实现

### 测试代码路径
- **文件**: `codex-rs/tui/src/chatwidget/tests.rs` (第 8191-8219 行)
- **测试函数**: `exec_history_extends_previous_when_consecutive`

### 核心测试逻辑

```rust
// 1. 开始 "ls -la" 命令（List 操作）
let begin_ls = begin_exec(&mut chat, "call-ls", "ls -la");

// 2. 验证活动单元格显示
assert_snapshot!("exploring_step1_start_ls", active_blob(&chat));
```

### 辅助函数

```rust
fn begin_exec(chat: &mut ChatWidget, call_id: &str, raw_cmd: &str) -> ExecCommandBeginEvent {
    let command = vec!["bash".to_string(), "-lc".to_string(), raw_cmd.to_string()];
    let parsed_cmd = codex_shell_command::parse_command::parse_command(&command);
    let event = ExecCommandBeginEvent {
        call_id: call_id.to_string(),
        process_id: None,
        turn_id: "turn-1".to_string(),
        command,
        cwd: std::env::current_dir().unwrap(),
        parsed_cmd,
        source: ExecCommandSource::Model,  // 模型发起的命令
        interaction_input: None,
    };
    chat.handle_codex_event(Event {
        id: call_id.into(),
        msg: EventMsg::ExecCommandBegin(event.clone()),
    });
    event
}
```

### 快照内容分析

```
• Exploring
  └ List ls -la
```

- `•`：旋转指示器（表示活动状态）
- `Exploring`：探索模式标题（加粗显示）
- `└`：树形连接线
- `List`：操作类型（青色）
- `ls -la`：命令/路径

### 探索模式判定

```rust
// exec_cell/render.rs
fn is_exploring_cell(&self) -> bool {
    // 判断是否为探索性命令
    self.calls.iter().all(|call| {
        call.parsed.iter().all(|parsed| {
            matches!(parsed, 
                ParsedCommand::Read { .. } |
                ParsedCommand::ListFiles { .. } |
                ParsedCommand::Search { .. }
            )
        })
    })
}
```

## 关键代码路径与文件引用

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/exec_cell/render.rs` | `exploring_display_lines` 方法，第 253-354 行 |
| `codex-rs/tui/src/exec_cell/model.rs` | `ExecCell` 数据结构 |
| `codex-shell-command/src/parse_command.rs` | 命令解析，识别 Read/List/Search |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试用例，第 8191 行 |

## 依赖与外部交互

### 命令解析
- `ParsedCommand::ListFiles`：目录列表命令
- `ParsedCommand::Read`：文件读取命令
- `ParsedCommand::Search`：搜索命令

### 事件流
```
ExecCommandBeginEvent
  ↓
ChatWidget::handle_codex_event
  ↓
ExecCell 创建/更新
  ↓
exploring_display_lines 渲染
```

## 风险、边界与改进建议

### 潜在风险
1. **误判**：某些复杂命令可能被误判为非探索性命令
2. **性能**：大量文件操作时渲染开销
3. **状态同步**：命令完成状态更新延迟

### 边界情况
- 命令解析失败（Unknown 类型）
- 混合类型命令（List + Read）
- 用户 shell 命令与模型命令区分

### 改进建议
1. **图标区分**：为不同操作类型使用不同图标（📁 目录，📄 文件）
2. **路径折叠**：显示相对路径而非完整路径
3. **时间显示**：添加命令执行时间
4. **取消操作**：允许用户中断探索过程

### 系列测试
- `exploring_step2_finish_ls`：完成 ls 命令
- `exploring_step3_start_cat_foo`：开始读取文件
- `exploring_step4_finish_cat_foo`：完成读取文件
