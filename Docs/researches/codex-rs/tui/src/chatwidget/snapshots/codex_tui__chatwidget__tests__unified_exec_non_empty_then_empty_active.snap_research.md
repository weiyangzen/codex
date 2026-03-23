# 研究报告: unified_exec_non_empty_then_empty_active.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在非空交互后接收到空交互时的**活动状态**渲染。与 `unified_exec_empty_then_non_empty_after` 测试相反，此测试关注交互顺序反转时的行为。

测试场景：
- 启动 Unified Exec（`just fix` 命令）
- 发送非空交互（`pwd\n`）
- 发送空交互（仅按回车查看）
- 验证活动单元格正确显示当前状态

## 功能点目的

**活动状态可视化**：

1. **实时反馈** - 显示当前正在进行的交互
2. **进程关联** - 明确显示交互所属的后台进程
3. **输入历史** - 保留最近输入的命令
4. **等待状态** - 空交互表示等待/查看状态

## 具体技术实现

### 测试实现

```rust
// tests.rs:5374-5421 (部分)
#[tokio::test]
async fn unified_exec_non_empty_then_empty_snapshots() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.on_task_started();
    begin_unified_exec_startup(&mut chat, "call-wait-3", "proc-3", "just fix");

    // 非空交互
    terminal_interaction(&mut chat, "call-wait-3a", "proc-3", "pwd\n");
    // 空交互
    terminal_interaction(&mut chat, "call-wait-3b", "proc-3", "");
    
    assert_eq!(
        chat.current_status.header,
        "Waiting for background terminal"
    );
    let status = chat.bottom_pane.status_widget()
        .expect("status indicator should be visible");
    assert_eq!(status.header(), "Waiting for background terminal");
    assert_eq!(status.details(), Some("just fix"));
    
    // 获取活动单元格快照
    let pre_cells = drain_insert_history(&mut rx);
    let active_combined = pre_cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    assert_snapshot!("unified_exec_non_empty_then_empty_active", active_combined);
    
    // ... 回合完成后测试
}
```

### 状态转换

```
非空交互 (pwd) → 活动单元格显示 "Interacted..."
     ↓
空交互 () → 状态变为 "Waiting for background terminal"
```

### 渲染输出

```
↳ Interacted with background terminal · just fix
  └ pwd
```

**解析**：
- `↳ Interacted with background terminal` - 交互记录
- `· just fix` - 关联的进程命令
- `  └ pwd` - 用户输入的具体命令（树形分支符号）

**注意**：此快照仅显示活动单元格内容，不包含等待状态的历史记录。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5374-5421 | 非空/空交互组合测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | 活动单元格管理 |
| `codex-rs/tui/src/history_cell.rs` | - | 活动单元格渲染 |

## 依赖与外部交互

### 活动单元格 vs 历史单元格

```rust
struct ChatWidget {
    active_cell: Option<Box<dyn HistoryCell>>, // 当前活动单元格
    history_cells: Vec<Box<dyn HistoryCell>>,  // 已完成的历史
}
```

### 状态转换逻辑

```rust
fn on_terminal_interaction(&mut self, event: TerminalInteractionEvent) {
    if event.stdin.is_empty() {
        // 空交互：进入等待状态
        self.current_status.header = "Waiting for background terminal".to_string();
    } else {
        // 非空交互：创建/更新交互记录
        self.active_cell = Some(Box::new(InteractionCell {
            command: command_display,
            input: event.stdin,
        }));
    }
}
```

## 风险、边界与改进建议

### 特定风险

1. **状态丢失** - 空交互可能覆盖重要的非空交互记录
2. **显示混乱** - 频繁的交互切换导致 UI 闪烁
3. **历史不完整** - 活动单元格未及时转为历史记录

### 边界情况

1. **快速连续交互** - 用户快速发送多个命令
2. **交互取消** - 交互过程中任务被中断
3. **进程结束** - 后台进程在交互期间结束

### 改进建议

1. **交互堆叠** - 同一进程的多次交互堆叠显示
2. **动画过渡** - 状态切换时添加平滑动画
3. **输入预览** - 显示待发送的输入（在按回车前）
4. **自动提交** - 长时间无新交互时自动提交活动单元格

### 相关测试

- `unified_exec_empty_then_non_empty_after` - 相反顺序的交互
- `unified_exec_non_empty_then_empty_after` - 回合完成后的状态
