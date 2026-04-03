# 研究文档：unified_exec_empty_then_non_empty_after

## 场景与职责

此 snapshot 测试验证统一执行（Unified Exec）从空交互到非空交互状态的变化（历史视角）。测试场景包括：
- 任务开始
- 统一执行启动（`just fix` 命令）
- 两次空交互（仅按回车，无实际输入）
- 一次非空交互（`ls` 命令）
- 任务完成（`TurnComplete`）
- 验证历史记录中正确显示等待和交互事件

该测试确保空交互（用户只按回车）和非空交互（用户输入内容）在历史记录中正确区分显示。

## 功能点目的

统一执行交互记录是 TUI 中跟踪用户与后台终端交互的重要机制：
1. **交互可见性**：记录用户与后台终端的所有交互
2. **空交互识别**：区分用户主动按回车（空交互）和实际输入内容
3. **历史追溯**：帮助用户回顾与后台终端的完整交互过程
4. **命令审计**：提供命令执行的历史记录用于审计
5. **状态转换**：清晰展示从 "等待" 到 "交互" 的状态变化

这种设计使用户能够完整了解后台终端的使用情况。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 开始统一执行
begin_unified_exec_startup(&mut chat, "call-wait-2", "proc-2", "just fix");

// 2. 两次空交互（stdin 为空字符串）
terminal_interaction(&mut chat, "call-wait-2a", "proc-2", "");
terminal_interaction(&mut chat, "call-wait-2b", "proc-2", "");

// 3. 一次非空交互（stdin 为 "ls"）
terminal_interaction(&mut chat, "call-wait-2c", "proc-2", "ls");

// 4. 任务完成
chat.handle_codex_event(Event {
    id: "turn-wait-2".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: None,
    }),
});
```

### 渲染输出格式
```
• Waited for background terminal · just fix

↳ Interacted with background terminal · just fix
  └ ls
```

格式解析：
- 第一组：等待记录
  - `• Waited for background terminal`：等待事件标记
  - `· just fix`：关联的命令
- 空行：分隔不同事件
- 第二组：交互记录
  - `↳ Interacted with background terminal`：交互事件标记
  - `· just fix`：关联的命令
  - `└ ls`：用户输入的内容（树形缩进）

### 交互类型区分
```rust
// 空交互 - 仅按回车
TerminalInteractionEvent {
    call_id: "...",
    process_id: "...",
    stdin: "",  // 空字符串
}
// 显示为："Waited for background terminal"

// 非空交互 - 有实际输入
TerminalInteractionEvent {
    call_id: "...",
    process_id: "...",
    stdin: "ls\n",  // 有内容
}
// 显示为："Interacted with background terminal" + 输入内容
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现 `on_terminal_interaction` 方法
   - 处理 `TerminalInteractionEvent`
   - 区分空交互和非空交互

2. **`codex-rs/tui/src/history_cell/`**（历史单元格子模块）
   - 实现等待和交互历史单元格的渲染
   - 树形缩进和符号显示

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 5339-5372）
   - 测试函数 `unified_exec_empty_then_non_empty_snapshots`
   - 验证空交互和非空交互的历史记录

### 相关数据结构
```rust
// TerminalInteractionEvent - 终端交互事件
pub struct TerminalInteractionEvent {
    pub call_id: String,
    pub process_id: String,
    pub stdin: String,  // 用户输入内容（可能为空）
}

// 历史单元格类型（概念性）
enum HistoryCellType {
    UnifiedExecWait {       // 空交互
        command: String,
    },
    UnifiedExecInteract {   // 非空交互
        command: String,
        input: String,
    },
}
```

### 交互处理流程
```
TerminalInteractionEvent
       ↓
  stdin.is_empty()?
   ↓ yes      ↓ no
   ↓          ↓
WaitCell   InteractCell
   ↓          ↓
"Waited"   "Interacted"
             ↓
           显示输入内容
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget` | 交互事件处理和状态管理 |
| `history_cell` | 历史单元格渲染 |
| `bottom_pane` | 统一执行状态跟踪 |

### 事件依赖
- `TerminalInteractionEvent`：终端交互事件
- `TurnCompleteEvent`：任务完成，触发历史记录刷新

### 测试辅助函数
```rust
// 测试辅助函数：模拟终端交互
fn terminal_interaction(chat: &mut ChatWidget, call_id: &str, process_id: &str, stdin: &str) {
    chat.handle_codex_event(Event {
        id: call_id.to_string(),
        msg: EventMsg::TerminalInteraction(TerminalInteractionEvent {
            call_id: call_id.to_string(),
            process_id: process_id.to_string(),
            stdin: stdin.to_string(),
        }),
    });
}
```

## 风险、边界与改进建议

### 潜在风险
1. **空交互累积**：用户多次按回车可能产生大量空交互记录
2. **输入内容过长**：非常长的输入可能导致历史记录显示混乱
3. **时序问题**：交互事件和任务完成事件的顺序可能影响历史记录

### 边界情况
1. **仅空交互**：如果只有空交互，历史记录应正确显示等待事件
2. **仅非空交互**：如果只有非空交互，应正确显示交互事件
3. **混合顺序**：空交互和非空交互的混合顺序应正确记录
4. **特殊字符**：输入中包含特殊字符（如控制字符）的处理

### 改进建议
1. **空交互合并**：连续的空交互可以合并为单个等待记录
2. **输入截断**：过长的输入可以在历史记录中截断显示，提供展开选项
3. **时间戳**：在交互记录中显示时间戳，帮助用户了解交互时序
4. **输出关联**：将交互输入与对应的命令输出关联显示
5. **交互统计**：在任务总结中显示交互次数统计
6. **快捷导航**：提供快捷键快速跳转到最近的交互记录

### 相关测试
- `unified_exec_empty_then_non_empty_after`：本测试文件
- `unified_exec_non_empty_then_empty_active`：反向状态变化测试
- `unified_exec_non_empty_then_empty_after`：反向历史记录测试
