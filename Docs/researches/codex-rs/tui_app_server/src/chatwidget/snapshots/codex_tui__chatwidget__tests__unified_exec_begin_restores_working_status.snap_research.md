# 研究文档：unified_exec_begin_restores_working_status

## 场景与职责

此 snapshot 测试验证统一执行（Unified Exec）开始时如何恢复工作状态显示。测试场景包括：
- 任务已开始（`on_task_started`）
- 代理消息增量到达（"Preamble line\n"）
- 统一执行启动（`begin_unified_exec_startup`）
- 验证状态指示器显示 "Working" 状态
- 显示后台终端运行信息

该测试确保当后台执行开始时，状态指示器能够正确地从其他状态（如 "Analyzing"）切换回 "Working" 状态。

## 功能点目的

统一执行状态管理是 TUI 中处理后台进程的核心机制：
1. **状态一致性**：确保状态指示器始终反映实际工作状态
2. **后台进程可见性**：让用户知道有后台终端正在运行
3. **上下文切换**：在 AI 推理和代码执行之间平滑切换状态显示
4. **操作提示**：提供 `/ps` 查看和 `/stop` 关闭的命令提示
5. **中断能力**：保持 ESC 中断功能可用

这种设计使用户能够同时监控 AI 活动和后台进程执行。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. 任务开始
chat.on_task_started();

// 2. 代理消息增量（模拟 AI 正在输出内容）
chat.on_agent_message_delta("Preamble line\n".to_string());
chat.on_commit_tick();
drain_insert_history(&mut rx);

// 3. 开始统一执行启动
begin_unified_exec_startup(&mut chat, "call-1", "proc-1", "sleep 2");
```

### 渲染输出格式
```
"                                                                                "
"• Working (0s • esc to interrupt) · 1 background terminal running · /ps to view…"
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

格式解析：
- 第1行：空行
- 第2行：状态指示器行
  - `• Working`：工作状态指示
  - `(0s • esc to interrupt)`：时间计数和中断提示
  - `· 1 background terminal running`：后台终端数量
  - `· /ps to view…`：查看命令提示（截断）
- 第3-4行：空行
- 第5行：输入提示符
- 第6行：空行
- 第7行：页脚（快捷键提示 + 上下文剩余）

### 状态恢复机制
当 `begin_unified_exec_startup` 被调用时：
1. 创建新的 `UnifiedExecProcessSummary` 记录
2. 更新 `unified_exec_processes` 列表
3. 触发状态指示器更新为 "Working"
4. 在状态详情中显示后台终端信息

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/bottom_pane/unified_exec_footer.rs`**
   - 实现统一执行页脚的渲染
   - `UnifiedExecFooter` 结构体管理后台进程列表
   - `summary_text()` 生成摘要文本

2. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现 `begin_unified_exec_startup` 函数
   - 管理 `unified_exec_processes` 状态
   - 协调状态指示器更新

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 3999-4021）
   - 测试函数 `unified_exec_begin_restores_working_status_snapshot`
   - 验证状态恢复行为

### 相关数据结构
```rust
// UnifiedExecProcessSummary - 统一执行进程摘要
pub struct UnifiedExecProcessSummary {
    pub key: String,           // 进程标识
    pub call_id: String,       // 调用 ID
    pub command_display: String, // 显示命令
    pub recent_chunks: Vec<String>, // 最近输出块
}

// UnifiedExecFooter - 统一执行页脚
pub struct UnifiedExecFooter {
    processes: Vec<String>,
}
```

### 状态转换流程
```
Analyzing/Other → begin_unified_exec_startup → Working
                      ↓
              unified_exec_processes.push()
                      ↓
              current_status = StatusIndicatorState::working()
                      ↓
              Render: "Working · N background terminal(s) running"
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::unified_exec_footer` | 后台进程页脚渲染 |
| `chatwidget` | 统一执行状态管理 |
| `status` 子模块 | 状态指示器实现 |

### 事件依赖
- `ExecCommandBeginEvent`：命令开始执行
- `TerminalInteractionEvent`：终端交互事件
- `TurnStartedEvent`：任务开始

### 测试辅助函数
```rust
// 测试辅助函数：开始统一执行启动
fn begin_unified_exec_startup(
    chat: &mut ChatWidget,
    call_id: &str,
    process_id: &str,
    command: &str,
) -> String {
    // 模拟统一执行启动事件
    chat.handle_codex_event(Event {
        id: call_id.into(),
        msg: EventMsg::ExecCommandBegin(ExecCommandBeginEvent {
            call_id: call_id.into(),
            command: command.split_whitespace().map(String::from).collect(),
            cwd: PathBuf::from("/tmp"),
            source: ExecCommandSource::UnifiedExecStartup,
            process_id: Some(process_id.into()),
        }),
    });
    call_id.to_string()
}
```

## 风险、边界与改进建议

### 潜在风险
1. **状态竞争**：多个并发执行可能导致状态指示器闪烁
2. **进程泄漏**：如果进程结束事件丢失，`unified_exec_processes` 可能累积过期条目
3. **显示截断**：当后台终端数量多时，状态文本可能被截断

### 边界情况
1. **零个进程**：`unified_exec_processes` 为空时不应显示后台终端信息
2. **进程快速结束**：开始和结束事件几乎同时到达时的处理
3. **命令显示长度**：超长命令应截断显示
4. **终端宽度**：窄终端中后台终端信息可能完全不可见

### 改进建议
1. **进程分组**：按类型分组显示后台进程（如 "2 shells, 1 build"）
2. **活动指示**：为每个后台终端显示活动指示器（是否有新输出）
3. **快捷操作**：在状态行提供快速关闭后台终端的快捷键
4. **进程详情**：`/ps` 命令显示更详细的进程信息（CPU、内存）
5. **自动清理**：定期清理已结束但未收到事件的进程记录
6. **状态优先级**：定义清晰的状态优先级（Error > Running > Waiting > Idle）

### 相关测试
- `unified_exec_begin_restores_working_status_snapshot`：本测试文件
- `unified_exec_waiting_multiple_empty_snapshots`：多等待状态测试
- `unified_exec_wait_status_renders_command_in_single_details_row`：状态详情测试
