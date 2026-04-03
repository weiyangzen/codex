# Approval Overlay Cross Thread Prompt Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `approval_overlay.rs` 模块的测试快照，用于验证**跨线程审批覆盖层**的渲染输出。当用户需要审批来自非当前活动线程（如后台 Agent）的请求时，展示此界面。

### 业务场景
- 多 Agent 协作场景，后台 Agent 需要执行命令
- 用户当前在一个线程，但需要审批另一个线程的操作
- 需要明确标识请求来源，避免混淆

### 跨线程特性
与常规审批覆盖层相比，跨线程提示额外显示：
- **Thread 标签**：明确显示请求来源的线程名称（如 "Robie [explorer]"）
- **打开线程快捷键**：提供 `o` 快捷键跳转到该线程

## 功能点目的

### 核心功能
1. **来源标识**：清晰显示请求来自哪个线程
2. **命令预览**：展示将要执行的命令
3. **快速跳转**：允许用户直接跳转到源线程查看上下文
4. **标准决策**：提供批准或拒绝的选项

### 用户体验目标
- **上下文感知**：用户知道这不是当前线程的请求
- **便捷导航**：一键跳转到相关线程查看详情
- **安全决策**：即使跨线程，也能做出明智的审批决定

## 具体技术实现

### 关键数据结构
```rust
pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,  // 跨线程时 Some("Thread Name")
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,
    },
    // ... 其他变体
}
```

### 头部构建逻辑
```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec { thread_label, reason, command, .. } => {
            let mut header: Vec<Line<'static>> = Vec::new();
            
            // 跨线程标识
            if let Some(thread_label) = thread_label {
                header.push(Line::from(vec![
                    "Thread: ".into(),
                    thread_label.clone().bold(),
                ]));
                header.push(Line::from(""));
            }
            
            // 理由说明
            if let Some(reason) = reason {
                header.push(Line::from(vec!["Reason: ".into(), reason.clone().italic()]));
                header.push(Line::from(""));
            }
            
            // 命令预览
            let full_cmd = strip_bash_lc_and_escape(command);
            let mut full_cmd_lines = highlight_bash_to_lines(&full_cmd);
            if let Some(first) = full_cmd_lines.first_mut() {
                first.spans.insert(0, Span::from("$ "));
            }
            header.extend(full_cmd_lines);
            
            Box::new(Paragraph::new(header).wrap(Wrap { trim: false }))
        }
        // ... 其他变体
    }
}
```

### 底部提示生成
```rust
fn approval_footer_hint(request: &ApprovalRequest) -> Line<'static> {
    let mut spans = vec![
        "Press ".into(),
        key_hint::plain(KeyCode::Enter).into(),
        " to confirm or ".into(),
        key_hint::plain(KeyCode::Esc).into(),
        " to cancel".into(),
    ];
    
    // 跨线程时添加 "o to open thread"
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

### 快捷键处理
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

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- **测试函数**: `cross_thread_footer_hint_mentions_o_shortcut` (行 1027-1050)
- **测试函数**: `o_opens_source_thread_for_cross_thread_approval` (行 998-1025)

### 测试参数
```rust
ApprovalRequest::Exec {
    thread_id: ThreadId::new(),
    thread_label: Some("Robie [explorer]".to_string()),  // 跨线程标识
    id: "test".to_string(),
    command: vec!["echo".to_string(), "hi".to_string()],
    reason: None,
    available_decisions: vec![ReviewDecision::Approved, ReviewDecision::Abort],
    network_approval_context: None,
    additional_permissions: None,
}
```

## 依赖与外部交互

### 内部依赖
- `codex_protocol::ThreadId` - 线程标识
- `AppEvent::SelectAgentThread` - 切换线程事件

### 外部交互
- **线程管理器**: 处理 `SelectAgentThread` 事件，切换当前活动线程
- **Agent 系统**: 后台 Agent 提交审批请求

## 风险、边界与改进建议

### 潜在风险
1. **线程混淆**: 用户可能误以为是当前线程的请求而批准
2. **上下文缺失**: 用户无法直接看到源线程的完整上下文
3. **并发冲突**: 多个线程同时请求审批时的处理

### 边界情况
1. **线程已关闭**: 如果用户跳转到线程时它已关闭
2. **线程标签为空**: `thread_label` 为 `None` 时退化为普通审批
3. **长线程名称**: 过长的线程名称可能导致显示问题

### 改进建议
1. **线程预览**: 在审批界面显示源线程的最近几条消息
2. **线程状态指示**: 显示线程是否仍在运行、是否被阻塞
3. **批量审批**: 支持同时审批来自同一线程的多个请求
4. **自动跳转选项**: 提供"批准并跳转"的组合操作
5. **线程颜色编码**: 为不同线程分配不同颜色，便于区分

### 测试覆盖
- 跨线程底部提示: `cross_thread_footer_hint_mentions_o_shortcut`
- 打开源线程: `o_opens_source_thread_for_cross_thread_approval`

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
- 线程管理: `codex-rs/tui_app_server/src/` 下的线程相关模块
