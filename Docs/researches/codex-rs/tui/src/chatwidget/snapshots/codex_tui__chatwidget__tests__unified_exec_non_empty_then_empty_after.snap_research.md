# 研究报告: unified_exec_non_empty_then_empty_after.snap

## 场景与职责

该快照文件验证 **Unified Exec** 在回合完成后的历史记录渲染。这是 `unified_exec_non_empty_then_empty_snapshots` 测试的第二部分，关注回合完成后活动单元格如何转为历史记录。

测试场景：
- 完成非空交互 + 空交互序列
- 回合完成 (`TurnComplete`)
- 验证历史记录正确包含所有交互

## 功能点目的

**回合完成后的状态固化**：

1. **历史归档** - 活动单元格转为永久历史记录
2. **状态重置** - 清除临时状态，准备下一轮
3. **完整记录** - 保留完整的交互序列
4. **用户回顾** - 用户可查看完整的操作历史

## 具体技术实现

### 测试实现（续）

```rust
// tests.rs:5399-5421 (回合完成后部分)
#[tokio::test]
async fn unified_exec_non_empty_then_empty_snapshots() {
    // ... 前半部分（见 active 快照）...
    
    // 回合完成
    chat.handle_codex_event(Event {
        id: "turn-wait-3".into(),
        msg: EventMsg::TurnComplete(TurnCompleteEvent {
            turn_id: "turn-1".to_string(),
            last_agent_message: None,
        }),
    });

    // 获取回合完成后的历史
    let post_cells = drain_insert_history(&mut rx);
    let mut combined = pre_cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    let post = post_cells
        .iter()
        .map(|lines| lines_to_single_string(lines))
        .collect::<String>();
    if !combined.is_empty() && !post.is_empty() {
        combined.push('\n');
    }
    combined.push_str(&post);
    assert_snapshot!("unified_exec_non_empty_then_empty_after", combined);
}
```

### 回合完成处理

```rust
fn on_turn_complete(&mut self, event: TurnCompleteEvent) {
    // 提交活动单元格到历史
    if let Some(active) = self.active_cell.take() {
        self.history_cells.push(active);
        self.emit_insert_history_event();
    }
    
    // 提交所有 Unified Exec 等待记录
    for process in &self.unified_exec_processes {
        self.history_cells.push(Box::new(WaitCell {
            command: process.command_display.clone(),
        }));
    }
    
    // 重置状态
    self.current_status = Status::default();
    self.bottom_pane.hide_status_indicator();
}
```

### 渲染输出

```
↳ Interacted with background terminal · just fix
  └ pwd

• Waited for background terminal · just fix
```

**解析**：
- 第一组：`Interacted with background terminal` + `pwd` - 交互记录
- 空行：分隔不同记录
- 第二组：`Waited for background terminal` - 等待记录

**注意**：与 `active` 快照不同，这里包含完整的交互历史（包括等待状态）。

## 关键代码路径与文件引用

| 文件 | 行号范围 | 描述 |
|------|----------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 5399-5421 | 回合完成后历史测试 |
| `codex-rs/tui/src/chatwidget/mod.rs` | - | `on_turn_complete` 处理 |
| `codex-rs/tui/src/history_cell.rs` | - | 历史单元格类型定义 |

## 依赖与外部交互

### TurnCompleteEvent

```rust
codex_protocol::protocol::TurnCompleteEvent {
    turn_id: String,
    last_agent_message: Option<String>, // 最后的 Agent 消息
}
```

### 历史单元格类型

```rust
enum HistoryCellType {
    Interaction {  // 交互记录
        command: String,
        input: String,
        timestamp: Instant,
    },
    Wait {         // 等待记录
        command: String,
        duration: Duration,
    },
}
```

## 风险、边界与改进建议

### 特定风险

1. **数据丢失** - 回合异常结束时活动单元格可能丢失
2. **顺序错误** - 多个活动单元格的提交顺序问题
3. **内存泄漏** - 大量历史记录未清理

### 边界情况

1. **空回合** - 没有任何交互的回合完成
2. **中断回合** - 回合被中断而非正常完成
3. **嵌套回合** - 子 Agent 的回合完成处理

### 改进建议

1. **持久化** - 历史记录定期保存到磁盘
2. **搜索功能** - 在历史记录中搜索特定命令
3. **导出功能** - 导出交互历史为脚本
4. **回放功能** - 重新执行历史交互序列
5. **统计信息** - 显示每个后台进程的总交互次数

### 相关测试

- `unified_exec_non_empty_then_empty_active` - 回合进行中的状态
- `turn_complete_keeps_unified_exec_processes` - 回合完成保持后台进程
