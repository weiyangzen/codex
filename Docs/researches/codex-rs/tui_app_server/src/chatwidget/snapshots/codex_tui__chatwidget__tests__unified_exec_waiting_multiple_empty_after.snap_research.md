# Research: Unified Exec Waiting Multiple Empty After

## 场景与职责

该 snapshot 测试验证当多个统一执行等待事件完成后，历史记录（History）中正确显示等待完成的状态。

**测试场景：**
- 用户启动了一个后台终端进程（`just fix`）
- 进程经历了多次空输入的终端交互（轮询等待）
- 任务完成后，验证历史记录中正确显示 "Waited for background terminal"

**核心职责：**
1. 确保等待状态正确累积并记录
2. 验证任务完成后历史记录的正确渲染
3. 确保 "Waited" 状态与命令正确关联

---

## 功能点目的

### 1. 统一执行等待状态累积（Unified Exec Wait Streak）
当 Codex 等待后台终端输出时，会累积等待状态。如果多次轮询都没有输出，这些等待应该被合并为一个历史记录条目。

### 2. 历史记录渲染（History Rendering）
等待完成后，需要将等待状态转换为历史记录单元格（History Cell），显示：
- 等待完成的标记（• Waited）
- 执行的命令（just fix）

### 3. 任务完成处理（Turn Complete Handling）
当 `TurnComplete` 事件到达时，需要：
- 刷新所有待处理的等待状态
- 将活动单元格转换为历史记录
- 更新 UI 状态

---

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui/src/chatwidget/tests.rs`  
**函数**: `unified_exec_waiting_multiple_empty_after_snapshot`

```rust
#[tokio::test]
async fn unified_exec_waiting_multiple_empty_after_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    begin_unified_exec_startup(&mut chat, "call-wait-1", "proc-1", "just fix");

    // 模拟两次空输入的终端交互（轮询）
    terminal_interaction(&mut chat, "call-wait-1a", "proc-1", "");
    terminal_interaction(&mut chat, "call-wait-1b", "proc-1", "");
    
    // 验证状态指示器显示正确
    assert_eq!(
        chat.current_status.header,
        "Waiting for background terminal"
    );
    let status = chat
        .bottom_pane
        .status_widget()
        .expect("status indicator should be visible");
    assert_eq!(status.header(), "Waiting for background terminal");
    assert_eq!(status.details(), Some("just fix"));

    // 完成任务
    chat.handle_codex_event(Event {
        id: "turn-wait-1".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: None,
        }),
    });

    // 验证历史记录
    let cells = drain_insert_history(&mut rx);
    let combined = cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_waiting_multiple_empty_after", combined);
}
```

### 关键实现组件

#### 1. UnifiedExecWaitStreak 管理
```rust
struct UnifiedExecWaitStreak {
    process_id: String,
    command_display: Option<String>,
}
```

当空输入的终端交互到达时：
- 如果已有相同进程的等待状态，更新命令显示
- 如果是新进程，创建新的等待状态

#### 2. 刷新等待状态
```rust
fn flush_unified_exec_wait_streak(&mut self) {
    let Some(wait) = self.unified_exec_wait_streak.take() else {
        return;
    };
    self.needs_final_message_separator = true;
    let cell = history_cell::new_unified_exec_interaction(
        wait.command_display, 
        String::new()
    );
    self.app_event_tx
        .send(AppEvent::InsertHistoryCell(Box::new(cell)));
    self.restore_reasoning_status_header();
}
```

#### 3. 任务完成处理
在 `on_turn_complete` 中：
```rust
self.flush_unified_exec_wait_streak();
// ... 其他完成处理
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 主实现，包含等待状态管理 |
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试代码 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格创建 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 底部面板状态管理 |

### 关键函数

| 函数 | 位置 | 职责 |
|-----|------|------|
| `flush_unified_exec_wait_streak` | `chatwidget.rs:1102` | 刷新等待状态到历史记录 |
| `on_terminal_interaction` | `chatwidget.rs:2661` | 处理终端交互 |
| `on_turn_complete` | `chatwidget.rs:1728` | 处理任务完成 |
| `new_unified_exec_interaction` | `history_cell.rs` | 创建统一执行交互历史单元格 |
| `drain_insert_history` | `tests.rs` | 测试辅助：获取历史记录 |

### 相关数据结构

| 结构体 | 位置 | 说明 |
|-------|------|------|
| `UnifiedExecWaitStreak` | `chatwidget.rs:345` | 等待状态跟踪 |
| `UnifiedExecProcessSummary` | `chatwidget.rs:323` | 进程摘要信息 |

---

## 依赖与外部交互

### 内部依赖

```
tui/src/chatwidget.rs
├── tui/src/bottom_pane/mod.rs (状态指示器)
├── tui/src/history_cell.rs (历史记录单元格)
└── tui/src/app_event.rs (应用事件)
```

### 协议事件

| 事件 | 说明 |
|-----|------|
| `ExecCommandBeginEvent` | 命令开始执行 |
| `TerminalInteractionEvent` | 终端交互（stdin/stdout） |
| `TurnCompleteEvent` | 任务完成 |

### 历史记录单元格类型

| 单元格类型 | 创建函数 | 说明 |
|-----------|---------|------|
| `UnifiedExecInteractionCell` | `new_unified_exec_interaction` | 统一执行交互记录 |

---

## 风险、边界与改进建议

### 潜在风险

1. **等待状态丢失**
   - 如果在等待状态刷新前发生崩溃，等待记录可能丢失
   - **缓解**: 关键操作后及时刷新状态

2. **重复记录**
   - 多次空输入可能产生重复的历史记录条目
   - **缓解**: `UnifiedExecWaitStreak` 合并相同进程的等待

3. **命令显示不一致**
   - 等待期间命令显示可能与实际执行命令不一致
   - **缓解**: 使用 `command_display` 字段保持一致性

### 边界情况

| 场景 | 行为 |
|-----|------|
| 单次空输入 | 正常记录等待状态 |
| 多次空输入 | 合并为单个等待记录 |
| 空输入后有输出 | 刷新等待，创建交互记录 |
| 任务中断 | 清空等待状态，不创建记录 |

### 改进建议

1. **添加等待时长记录**
   - 在历史记录中显示等待的总时长

2. **支持等待详情展开**
   - 允许用户查看等待期间的轮询次数

3. **优化空等待的显示**
   - 如果等待期间没有任何输出，可以简化显示

4. **添加测试场景**
   - 测试中断后的等待状态处理
   - 测试多进程并发等待的场景

---

## Snapshot 内容分析

```
• Waited for background terminal · just fix
```

**观察要点：**
1. 使用 "Waited" 表示等待已完成（过去式）
2. 使用中间点（·）分隔状态描述和命令
3. 命令简洁显示（just fix）
4. 单行显示，无额外输出内容（因为输入为空）

**与 Active 状态对比：**
- Active: "Waiting for background terminal"（现在进行时）
- Completed: "Waited for background terminal"（过去式）
