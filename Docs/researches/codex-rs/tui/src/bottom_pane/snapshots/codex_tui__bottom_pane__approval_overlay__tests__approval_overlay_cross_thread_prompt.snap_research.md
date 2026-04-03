# Approval Overlay Cross Thread Prompt Snapshot 研究文档

## 场景与职责

此快照文件是 `codex_tui` crate 中 `approval_overlay` 模块的测试快照，用于验证 **Approval Overlay** 在跨线程（cross-thread）审批场景下的 UI 渲染输出。这是 Codex TUI 多线程/多代理模式的关键组件，帮助用户识别和管理来自非当前活跃线程的审批请求。

### 业务场景
- 当用户在一个线程（如主线程）工作时，另一个后台线程（如代理线程）发出审批请求
- 多代理模式下，不同代理可能并发执行需要用户审批的操作
- 用户需要识别审批来源，决定是否切换到对应线程处理

### 跨线程审批的特点
| 特征 | 单线程审批 | 跨线程审批 |
|------|-----------|-----------|
| 线程标签 | 无 | 显示 `Thread: Label [type]` |
| 额外快捷键 | 无 | `o` 键打开对应线程 |
| 页脚提示 | 标准提示 | 包含 `or o to open thread` |
| 历史记录 | 记录到当前线程 | 记录到对应线程 |

## 功能点目的

### 核心功能
1. **来源识别**：清晰标识审批请求来自哪个线程
2. **上下文切换**：提供快捷键快速跳转到对应线程
3. **线程隔离**：确保审批决策发送到正确的线程
4. **历史隔离**：审批历史记录到对应的线程中

### UI 元素（从快照可见）
```
Would you like to run the following command?

Thread: Robie [explorer]           # 线程标签（粗体）

$ echo hi

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

Press enter to confirm or esc to cancel or o to open thread  # 包含 o 快捷键
```

### 线程标签格式
```
Thread: {thread_label}             # thread_label 由调用方提供
```

## 具体技术实现

### 关键数据结构

```rust
// ApprovalRequest::Exec 变体中的线程相关字段
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,  // 跨线程时提供标签
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,
    },
    // ... 其他变体也有 thread_id 和 thread_label
}

impl ApprovalRequest {
    fn thread_id(&self) -> ThreadId {
        match self {
            ApprovalRequest::Exec { thread_id, .. }
            | ApprovalRequest::Permissions { thread_id, .. }
            | ApprovalRequest::ApplyPatch { thread_id, .. }
            | ApprovalRequest::McpElicitation { thread_id, .. } => *thread_id,
        }
    }

    fn thread_label(&self) -> Option<&str> {
        match self {
            ApprovalRequest::Exec { thread_label, .. }
            | ApprovalRequest::Permissions { thread_label, .. }
            | ApprovalRequest::ApplyPatch { thread_label, .. }
            | ApprovalRequest::McpElicitation { thread_label, .. } => thread_label.as_deref(),
        }
    }
}
```

### 线程标签显示

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec { thread_label, reason, command, .. } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // 显示线程标签（如果存在）
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec![
                    "Thread: ".into(),
                    thread_label.clone().bold(),  // 粗体强调
                ]));
                header.push(Line::from(""));
            }
            
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // ... 命令片段
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ...
    }
}
```

### 页脚提示生成

```rust
fn approval_footer_hint(request: &ApprovalRequest) -> Line<'static> {
    let mut spans = vec![
        "Press ".into(),
        key_hint::plain(KeyCode::Enter).into(),
        " to confirm or ".into(),
        key_hint::plain(KeyCode::Esc).into(),
        " to cancel".into(),
    ];
    
    // 跨线程时添加 o 快捷键提示
    if request.thread_label().is_some() {
        spans.extend([
            " or ".into(),
            key_hint::plain(KeyCode::Char('o')).into(),
            " to open thread".into(),
        ]);
    }
    
    Line::from(spans)
}
```

### o 快捷键处理

```rust
fn try_handle_shortcut(&mut self, key_event: &KeyEvent) -> bool {
    match key_event {
        // ... 其他快捷键
        KeyEvent {
            kind: KeyEventKind::Press,
            code: KeyCode::Char('o'),
            ..
        } => {
            if let Some(request) = self.current_request.as_ref() {
                if request.thread_label().is_some() {
                    // 发送切换到对应线程的事件
                    self.app_event_tx
                        .send(AppEvent::SelectAgentThread(request.thread_id()));
                    true
                } else {
                    false
                }
            } else {
                false
            }
        }
        // ...
    }
}
```

### 历史记录处理

```rust
fn handle_exec_decision(&self, id: &str, command: &[String], decision: ReviewDecision) {
    let Some(request) = self.current_request.as_ref() else { return; };
    
    // 仅当没有线程标签时（即非跨线程）记录到历史
    if request.thread_label().is_none() {
        let cell = history_cell::new_approval_decision_cell(
            command.to_vec(),
            decision.clone(),
            history_cell::ApprovalDecisionActor::User,
        );
        self.app_event_tx.send(AppEvent::InsertHistoryCell(cell));
    }
    
    // 发送审批决策到对应线程
    let thread_id = request.thread_id();
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        thread_id,
        op: Op::ExecApproval {
            id: id.to_string(),
            turn_id: None,
            decision,
        },
    });
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:83-101` | `thread_id()` 和 `thread_label()` 方法 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:498-514` | `approval_footer_hint` 函数 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:372-418` | `try_handle_shortcut` 方法（含 'o' 键处理） |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:254-275` | `handle_exec_decision` 方法 |
| `codex-rs/tui/src/bottom_pane/approval_overlay.rs:1041-1064` | 跨线程审批快照测试 |

### 相关测试用例

```rust
#[test]
fn cross_thread_footer_hint_mentions_o_shortcut() {
    let (tx, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let view = ApprovalOverlay::new(
        ApprovalRequest::Exec {
            thread_id: ThreadId::new(),
            thread_label: Some("Robie [explorer]".to_string()),  // 跨线程标签
            id: "test".to_string(),
            command: vec!["echo".to_string(), "hi".to_string()],
            reason: None,
            available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
            network_approval_context: None,
            additional_permissions: None,
        },
        tx,
        Features::with_defaults(),
    );

    assert_snapshot!(
        "approval_overlay_cross_thread_prompt",
        render_overlay_lines(&view, 80)
    );
}

#[test]
fn o_opens_source_thread_for_cross_thread_approval() {
    let (tx, mut rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx);
    let thread_id = ThreadId::new();
    let mut view = ApprovalOverlay::new(
        ApprovalRequest::Exec {
            thread_id,
            thread_label: Some("Robie [explorer]".to_string()),
            // ...
        },
        tx,
        Features::with_defaults(),
    );

    view.handle_key_event(KeyEvent::new(KeyCode::Char('o'), KeyModifiers::NONE));

    let event = rx.try_recv().expect("expected select-agent-thread event");
    assert_eq!(
        matches!(event, AppEvent::SelectAgentThread(id) if id == thread_id),
        true
    );
}
```

## 依赖与外部交互

### 事件系统

| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::SelectAgentThread(ThreadId)` | TUI → 应用 | 切换到指定线程 |
| `AppEvent::SubmitThreadOp { thread_id, op }` | TUI → 后端 | 发送操作到指定线程 |
| `AppEvent::InsertHistoryCell` | TUI → 历史 | 记录审批决策（仅非跨线程） |

### 线程标识

```rust
// codex-protocol/src/lib.rs
pub struct ThreadId(Uuid);

impl ThreadId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}
```

## 风险、边界与改进建议

### 用户体验边界

1. **线程标签可读性**:
   - 当前格式 `Robie [explorer]` 依赖调用方提供有意义的标签
   - 建议标准化标签格式，如 `{agent_name} [{task_type}]`

2. **多线程并发**:
   - 多个线程同时发出审批请求时，队列可能堆积
   - 建议添加队列长度指示

3. **上下文丢失**:
   - 用户切换到其他线程后，可能忘记原线程的上下文
   - 建议添加"返回上一线程"功能

### 安全边界

1. **线程欺骗**:
   - 恶意代码可能伪造线程标签误导用户
   - 建议添加线程身份验证机制

2. **权限扩散**:
   - 跨线程审批的权限可能不适用于当前线程
   - 建议明确显示权限适用范围

### 改进建议

1. **线程队列指示器**:
   ```rust
   // 在页脚显示待处理审批数量
   "3 pending approvals from other threads · press 'a' to view"
   ```

2. **线程预览**:
   - 在审批覆盖层中显示对应线程的最近活动摘要
   - 帮助用户判断是否需要切换线程

3. **批量审批**:
   - 允许用户一次性处理同一来源的多个审批
   - 减少上下文切换开销

4. **线程优先级**:
   - 根据线程重要性调整审批请求的显示优先级
   - 紧急线程的审批应突出显示

5. **审批超时**:
   - 跨线程审批应有过期机制
   - 超时后自动拒绝或提示用户

```rust
// 建议添加审批超时
struct ApprovalRequest {
    // ... 现有字段
    timeout: Option<Duration>,
    submitted_at: Instant,
}

impl ApprovalOverlay {
    fn check_timeouts(&mut self) {
        if let Some(request) = &self.current_request {
            if let Some(timeout) = request.timeout {
                if request.submitted_at.elapsed() > timeout {
                    self.auto_reject_current();
                }
            }
        }
    }
}
```
