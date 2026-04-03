# 研究文档：unified_exec_unknown_end_with_active_exploring_cell

## 场景与职责

此 snapshot 测试验证执行结束时未知状态的活动探索单元格显示。测试场景包括：
- 任务开始
- 开始执行命令（`cat /dev/null`）- 创建 "Exploring" 单元格
- 开始另一个统一执行（`echo repro-marker`）- 创建孤儿进程
- 结束第二个执行（产生输出 "repro-marker\n"）
- 验证历史记录和活动中单元格的正确显示

该测试确保当一个执行命令结束时，如果存在其他活动的探索单元格，系统能够正确处理这种复杂的并发状态。

## 功能点目的

探索单元格是 TUI 中显示 AI 探索活动（如文件读取、命令执行）的组件：
1. **活动跟踪**：显示 AI 当前正在进行的探索操作
2. **并发管理**：处理多个并发执行命令的状态
3. **孤儿进程处理**：正确处理父单元格已结束但子进程仍在运行的情况
4. **状态一致性**：确保历史记录和活动单元格的状态一致
5. **输出关联**：将命令输出与正确的执行单元格关联

这种设计确保了复杂的并发执行场景下的状态一致性。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
chat.on_task_started();

// 1. 开始执行命令 - 创建 Exploring 单元格
begin_exec(&mut chat, "call-exploring", "cat /dev/null");

// 2. 开始另一个统一执行（孤儿进程）
let orphan = begin_unified_exec_startup(
    &mut chat, 
    "call-orphan", 
    "proc-1", 
    "echo repro-marker"
);

// 3. 结束第二个执行
end_exec(&mut chat, orphan, "repro-marker\n", "", 0);

// 4. 收集历史记录和活动单元格
let cells = drain_insert_history(&mut rx);
let history = cells.iter().map(...).collect::<String>();
let active = active_blob(&chat);
let snapshot = format!("History:\n{history}\nActive:\n{active}");
```

### 渲染输出格式
```
History:
• Ran echo repro-marker
  └ repro-marker

Active:
• Exploring
  └ Read null
```

格式解析：
- **History 部分**：
  - `• Ran echo repro-marker`：已完成的执行命令
  - `└ repro-marker`：命令输出
- **Active 部分**：
  - `• Exploring`：正在进行的探索活动
  - `└ Read null`：具体探索操作（读取 /dev/null）

### 并发状态管理
```
时间线：
T1: begin_exec("cat /dev/null") → 创建 Exploring 单元格（Active）
T2: begin_unified_exec_startup("echo repro-marker") → 创建第二个执行
T3: end_exec("echo repro-marker") → 第二个执行完成，移入 History
T4: （测试断言点）→ Exploring 单元格仍在 Active
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现 `begin_exec` 和 `end_exec` 方法
   - 管理执行命令的生命周期
   - 处理探索单元格的创建和更新

2. **`codex-rs/tui/src/history_cell/exploring_cell.rs`**（探索单元格实现）
   - 实现探索单元格的渲染逻辑
   - 处理 "Read"、"List" 等探索操作

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 5131-5151）
   - 测试函数 `unified_exec_unknown_end_with_active_exploring_cell_snapshot`
   - 验证复杂并发场景下的状态一致性

### 相关数据结构
```rust
// ExecCommandBeginEvent - 执行命令开始事件
pub struct ExecCommandBeginEvent {
    pub call_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub source: ExecCommandSource,
    pub process_id: Option<String>,
}

// ExecCommandEndEvent - 执行命令结束事件
pub struct ExecCommandEndEvent {
    pub call_id: String,
    pub stdout: String,
    pub stderr: String,
    pub exit_code: i32,
}

// 探索单元格（概念性）
struct ExploringCell {
    operation: String,  // "Read", "List", etc.
    target: String,     // 操作目标
    status: ExploringStatus,
}
```

### 执行命令生命周期
```
begin_exec
    ↓
创建 ExploringCell (Active)
    ↓
（可能并发其他执行）
    ↓
end_exec
    ↓
├─ 如果是独立命令 → 移入 History
└─ 如果是子进程 → 根据父单元格状态决定
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget` | 执行命令生命周期管理 |
| `history_cell::exploring` | 探索单元格实现 |
| `bottom_pane` | 统一执行状态跟踪 |

### 事件依赖
- `ExecCommandBeginEvent`：触发执行命令开始
- `ExecCommandEndEvent`：触发执行命令结束
- `ItemCompletedEvent`：项目完成事件

### 测试辅助函数
```rust
// 开始执行命令
fn begin_exec(chat: &mut ChatWidget, call_id: &str, command: &str) -> String {
    chat.handle_codex_event(Event {
        id: call_id.into(),
        msg: EventMsg::ExecCommandBegin(ExecCommandBeginEvent {
            call_id: call_id.into(),
            command: command.split_whitespace().map(String::from).collect(),
            cwd: PathBuf::from("/tmp"),
            source: ExecCommandSource::ToolCall,
            process_id: None,
        }),
    });
    call_id.to_string()
}

// 结束执行命令
fn end_exec(chat: &mut ChatWidget, call_id: String, stdout: &str, stderr: &str, code: i32) {
    chat.handle_codex_event(Event {
        id: call_id.clone().into(),
        msg: EventMsg::ExecCommandEnd(ExecCommandEndEvent {
            call_id,
            stdout: stdout.to_string(),
            stderr: stderr.to_string(),
            exit_code: code,
        }),
    });
}
```

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**：多个并发执行命令可能导致状态竞争
2. **孤儿进程**：父单元格结束后，子进程的输出可能无法正确关联
3. **内存泄漏**：未正确结束的执行命令可能导致单元格累积

### 边界情况
1. **嵌套执行**：多层嵌套的执行命令（A 启动 B，B 启动 C）
2. **快速开始结束**：执行命令快速开始和结束时的处理
3. **失败执行**：执行命令失败（非零退出码）时的显示
4. **大量并发**：大量并发执行命令时的性能问题

### 改进建议
1. **执行树显示**：以树形结构显示嵌套执行关系
2. **进程分组**：将相关进程分组显示，提高可读性
3. **超时处理**：为长时间运行的执行命令添加超时警告
4. **资源监控**：显示执行命令的资源使用情况（CPU、内存）
5. **快捷操作**：提供快捷方式终止或重启特定执行命令
6. **输出流式**：实时流式显示执行命令的输出

### 相关测试
- `unified_exec_unknown_end_with_active_exploring_cell_snapshot`：本测试文件
- `unified_exec_end_after_task_complete_is_suppressed`：任务完成后执行结束测试
- `unified_exec_interaction_after_task_complete_is_suppressed`：任务完成后交互测试
