# 研究文档：unified_exec_non_empty_then_empty_after

## 场景与职责

此 snapshot 测试验证统一执行（Unified Exec）从非空交互到空交互状态的变化（历史视角）。测试场景包括：
- 任务开始
- 统一执行启动（`just fix` 命令）
- 一次非空交互（`pwd` 命令）
- 一次空交互（仅按回车）
- 任务完成（`TurnComplete`）
- 验证历史记录中正确显示交互和等待事件

该测试确保在活动状态结束后，所有交互（包括非空和空交互）都被正确记录到历史记录中。

## 功能点目的

历史记录是 TUI 中永久保存用户与系统交互的重要机制：
1. **持久记录**：任务完成后，交互记录永久保存在历史记录中
2. **完整追溯**：提供完整的交互历史用于回顾和分析
3. **审计支持**：记录所有用户操作以满足审计需求
4. **学习参考**：用户可以参考历史交互来学习使用模式
5. **错误诊断**：帮助诊断问题发生时的具体操作序列

这种设计确保了用户与后台终端的所有交互都被妥善保存。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();
begin_unified_exec_startup(&mut chat, "call-wait-3", "proc-3", "just fix");

// 非空交互
terminal_interaction(&mut chat, "call-wait-3a", "proc-3", "pwd\n");
// 空交互
terminal_interaction(&mut chat, "call-wait-3b", "proc-3", "");

// 获取活动状态的内容
let pre_cells = drain_insert_history(&mut rx);

// 任务完成
chat.handle_codex_event(Event {
    id: "turn-wait-3".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: None,
    }),
});

// 获取任务完成后的历史记录
let post_cells = drain_insert_history(&mut rx);
let mut combined = pre_cells.iter()...collect::<String>();
combined.push_str(&post.iter()...collect::<String>());
```

### 渲染输出格式
```
↳ Interacted with background terminal · just fix
  └ pwd

• Waited for background terminal · just fix
```

格式解析：
- 第一组：非空交互记录
  - `↳ Interacted with background terminal`：交互事件标记
  - `· just fix`：关联的命令
  - `└ pwd`：用户输入的内容
- 空行：分隔不同事件
- 第二组：空交互记录（任务完成后转为等待记录）
  - `• Waited for background terminal`：等待事件标记
  - `· just fix`：关联的命令

### 活动到历史的转换
```
任务进行中：                    任务完成后：
├─ ActiveCell                   ├─ HistoryCell
│   └─ "Interacted"             │   ├─ "Interacted" (非空交互)
│       └─ "pwd"                │   │   └─ "pwd"
│                               │   └─ "Waited" (空交互)
└─ (空交互不显示)                │       └─ (无内容)
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现 `on_task_complete` 方法
   - 处理活动单元格到历史单元格的转换
   - 管理 `InsertHistoryCell` 事件的发送

2. **`codex-rs/tui/src/history_cell/`**（历史单元格子模块）
   - 实现历史单元格的最终化（finalization）
   - 处理空交互到等待记录的转换

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 5375-5421）
   - 测试函数 `unified_exec_non_empty_then_empty_snapshots`
   - 验证历史记录的完整性和正确性

### 相关数据结构
```rust
// TurnCompleteEvent - 任务完成事件
pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>,
}

// AppEvent::InsertHistoryCell - 插入历史单元格事件
pub enum AppEvent {
    InsertHistoryCell(Option<Box<dyn HistoryCell>>),
    // ... 其他变体
}
```

### 转换流程
```
TurnComplete 事件
      ↓
finalize_active_cell()
      ↓
├─ 非空交互 → InteractedHistoryCell
│              ↓
│           发送 InsertHistoryCell
│
└─ 空交互 → WaitHistoryCell
             ↓
          发送 InsertHistoryCell
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget` | 任务完成处理和历史记录生成 |
| `history_cell` | 历史单元格创建和渲染 |
| `app_event` | 事件发送机制 |

### 事件依赖
- `TurnCompleteEvent`：触发历史记录生成
- `InsertHistoryCell`：将单元格插入历史记录

### 测试辅助函数
```rust
// drain_insert_history - 收集所有 InsertHistoryCell 事件
fn drain_insert_history(
    rx: &mut tokio::sync::mpsc::UnboundedReceiver<AppEvent>,
) -> Vec<Vec<ratatui::text::Line<'static>>> {
    let mut out = Vec::new();
    while let Ok(ev) = rx.try_recv() {
        if let AppEvent::InsertHistoryCell(cell) = ev {
            let mut lines = cell.display_lines(80);
            if !cell.is_stream_continuation() && !out.is_empty() && !lines.is_empty() {
                lines.insert(0, "".into());
            }
            out.push(lines)
        }
    }
    out
}
```

## 风险、边界与改进建议

### 潜在风险
1. **事件丢失**：如果 `InsertHistoryCell` 事件丢失，历史记录将不完整
2. **顺序错误**：多个历史单元格的顺序可能因时序问题而出错
3. **内容截断**：过长的交互内容可能在历史记录中被截断

### 边界情况
1. **任务中断**：任务被中断而非正常完成时的历史记录处理
2. **无交互**：没有任何交互事件时的历史记录
3. **仅空交互**：只有空交互时的历史记录显示
4. **大量交互**：大量交互事件时的性能问题

### 改进建议
1. **事务性记录**：确保所有相关历史单元格作为一个事务记录
2. **时间戳**：为每个历史记录添加精确的时间戳
3. **折叠显示**：大量相似交互可以折叠显示（如 "3 次等待"）
4. **搜索功能**：提供历史记录的搜索和过滤功能
5. **导出功能**：允许导出历史记录为文本或 JSON
6. **持久化**：将历史记录持久化到磁盘，支持跨会话查看

### 相关测试
- `unified_exec_non_empty_then_empty_after`：本测试文件（历史视角）
- `unified_exec_non_empty_then_empty_active`：同一测试的活动视角
- `unified_exec_empty_then_non_empty_after`：反向状态变化测试
