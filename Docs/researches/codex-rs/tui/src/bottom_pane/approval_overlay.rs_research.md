# approval_overlay.rs 研究文档

## 场景与职责

`ApprovalOverlay` 是 TUI 中处理用户审批请求的核心组件，负责展示来自 Agent 的各类审批请求并收集用户决策。它支持四种类型的审批请求：

1. **Exec 审批**：命令执行审批（如 shell 命令）
2. **Permissions 审批**：权限授予审批
3. **ApplyPatch 审批**：代码补丁应用审批
4. **McpElicitation 审批**：MCP 服务器诱导请求审批

该组件采用队列设计，可以顺序处理多个审批请求。

## 功能点目的

### 核心功能

| 功能 | 说明 |
|------|------|
| 多类型审批支持 | Exec/Permissions/ApplyPatch/McpElicitation |
| 队列管理 | 支持多个审批请求排队处理 |
| 决策选项生成 | 根据请求类型和上下文生成可用决策 |
| 快捷键支持 | 数字键、字母快捷键快速选择 |
| 全屏审批 | Ctrl+A 切换到全屏审批视图 |
| 跨线程导航 | 'o' 键跳转到请求来源线程 |
| 历史记录 | 将审批决策记录到历史单元格 |

### 决策类型

```rust
enum ApprovalDecision {
    Review(ReviewDecision),           // 标准审批决策
    McpElicitation(ElicitationAction), // MCP 诱导动作
}
```

### 审批选项结构

```rust
struct ApprovalOption {
    label: String,
    decision: ApprovalDecision,
    display_shortcut: Option<KeyBinding>,
    additional_shortcuts: Vec<KeyBinding>,
}
```

## 具体技术实现

### 数据结构

```rust
pub(crate) struct ApprovalOverlay {
    current_request: Option<ApprovalRequest>,
    queue: Vec<ApprovalRequest>,
    app_event_tx: AppEventSender,
    list: ListSelectionView,
    options: Vec<ApprovalOption>,
    current_complete: bool,
    done: bool,
    features: Features,
}

pub(crate) enum ApprovalRequest {
    Exec {
        thread_id: ThreadId,
        thread_label: Option<String>,
        id: String,
        command: Vec<String>,
        reason: Option<String>,
        available_decisions: Vec<ReviewDecision>,
        network_approval_context: Option<NetworkApprovalContext>,
        additional_permissions: Option<PermissionProfile>,
    },
    Permissions { ... },
    ApplyPatch { ... },
    McpElicitation { ... },
}
```

### 关键流程

#### 1. 创建和初始化

```rust
pub fn new(request: ApprovalRequest, app_event_tx: AppEventSender, features: Features) -> Self {
    let mut view = Self {
        current_request: None,
        queue: Vec::new(),
        app_event_tx: app_event_tx.clone(),
        list: ListSelectionView::new(Default::default(), app_event_tx),
        options: Vec::new(),
        current_complete: false,
        done: false,
        features,
    };
    view.set_current(request);
    view
}
```

#### 2. 构建审批选项

根据请求类型构建不同的选项：

```rust
fn build_options(
    request: &ApprovalRequest,
    header: Box<dyn Renderable>,
    _features: &Features,
) -> (Vec<ApprovalOption>, SelectionViewParams) {
    let (options, title) = match request {
        ApprovalRequest::Exec { available_decisions, network_approval_context, additional_permissions, .. } => {
            (exec_options(available_decisions, network_approval_context.as_ref(), additional_permissions.as_ref()),
             network_approval_context.as_ref().map_or_else(
                || "Would you like to run the following command?".to_string(),
                |ctx| format!("Do you want to approve network access to \"{}\"?", ctx.host)
            ))
        }
        ApprovalRequest::Permissions { .. } => (permissions_options(), "Would you like to grant these permissions?".to_string()),
        ApprovalRequest::ApplyPatch { .. } => (patch_options(), "Would you like to make the following edits?".to_string()),
        ApprovalRequest::McpElicitation { server_name, .. } => (elicitation_options(), format!("{server_name} needs your approval.")),
    };
    // ...
}
```

#### 3. Exec 选项生成

```rust
fn exec_options(
    available_decisions: &[ReviewDecision],
    network_approval_context: Option<&NetworkApprovalContext>,
    additional_permissions: Option<&PermissionProfile>,
) -> Vec<ApprovalOption> {
    available_decisions.iter().filter_map(|decision| match decision {
        ReviewDecision::Approved => Some(ApprovalOption {
            label: if network_approval_context.is_some() { 
                "Yes, just this once".to_string() 
            } else { 
                "Yes, proceed".to_string() 
            },
            decision: ApprovalDecision::Review(ReviewDecision::Approved),
            display_shortcut: None,
            additional_shortcuts: vec![key_hint::plain(KeyCode::Char('y'))],
        }),
        ReviewDecision::ApprovedExecpolicyAmendment { proposed_execpolicy_amendment } => {
            // 生成前缀匹配选项
        }
        ReviewDecision::ApprovedForSession => Some(ApprovalOption {
            label: "Yes, and don't ask again for this command in this session".to_string(),
            // ...
        }),
        ReviewDecision::NetworkPolicyAmendment { network_policy_amendment } => {
            // 网络策略修正选项
        }
        // ...
    }).collect()
}
```

#### 4. 应用选择

```rust
fn apply_selection(&mut self, actual_idx: usize) {
    if self.current_complete { return; }
    let Some(option) = self.options.get(actual_idx) else { return };
    
    if let Some(request) = self.current_request.as_ref() {
        match (request, &option.decision) {
            (ApprovalRequest::Exec { id, command, .. }, ApprovalDecision::Review(decision)) => {
                self.handle_exec_decision(id, command, decision.clone());
            }
            (ApprovalRequest::Permissions { call_id, permissions, .. }, ApprovalDecision::Review(decision)) => {
                self.handle_permissions_decision(call_id, permissions, decision.clone());
            }
            (ApprovalRequest::ApplyPatch { id, .. }, ApprovalDecision::Review(decision)) => {
                self.handle_patch_decision(id, decision.clone());
            }
            (ApprovalRequest::McpElicitation { server_name, request_id, .. }, ApprovalDecision::McpElicitation(decision)) => {
                self.handle_elicitation_decision(server_name, request_id, *decision);
            }
            _ => {}
        }
    }
    
    self.current_complete = true;
    self.advance_queue();
}
```

#### 5. 处理 Exec 决策

```rust
fn handle_exec_decision(&self, id: &str, command: &[String], decision: ReviewDecision) {
    let Some(request) = self.current_request.as_ref() else { return };
    
    // 记录历史（仅非线程标签请求）
    if request.thread_label().is_none() {
        let cell = history_cell::new_approval_decision_cell(
            command.to_vec(),
            decision.clone(),
            history_cell::ApprovalDecisionActor::User,
        );
        self.app_event_tx.send(AppEvent::InsertHistoryCell(cell));
    }
    
    // 提交审批决策
    let thread_id = request.thread_id();
    self.app_event_tx.send(AppEvent::SubmitThreadOp {
        thread_id,
        op: Op::ExecApproval { id: id.to_string(), turn_id: None, decision },
    });
}
```

### 快捷键处理

```rust
fn try_handle_shortcut(&mut self, key_event: &KeyEvent) -> bool {
    match key_event {
        // Ctrl+A: 全屏审批
        KeyEvent { code: KeyCode::Char('a'), modifiers, .. } 
            if modifiers.contains(KeyModifiers::CONTROL) => {
            self.app_event_tx.send(AppEvent::FullScreenApprovalRequest(request.clone()));
            true
        }
        // 'o': 打开来源线程
        KeyEvent { code: KeyCode::Char('o'), .. } => {
            if request.thread_label().is_some() {
                self.app_event_tx.send(AppEvent::SelectAgentThread(request.thread_id()));
                true
            } else { false }
        }
        // 选项快捷键
        e => {
            if let Some(idx) = self.options.iter().position(|opt| opt.shortcuts().any(|s| s.is_press(*e))) {
                self.apply_selection(idx);
                true
            } else { false }
        }
    }
}
```

### Header 构建

不同类型的请求构建不同的 header 内容：

```rust
fn build_header(request: &ApprovalRequest) -> Box<dyn Renderable> {
    match request {
        ApprovalRequest::Exec { thread_label, reason, command, network_approval_context, additional_permissions, .. } => {
            // 构建命令展示 header，包含线程标签、原因、权限规则、命令高亮
        }
        ApprovalRequest::Permissions { thread_label, reason, permissions, .. } => {
            // 构建权限请求 header
        }
        ApprovalRequest::ApplyPatch { thread_label, reason, cwd, changes, .. } => {
            // 构建补丁 header，使用 DiffSummary 展示变更
        }
        ApprovalRequest::McpElicitation { thread_label, server_name, message, .. } => {
            // 构建 MCP 诱导 header
        }
    }
}
```

## 关键代码路径与文件引用

### 当前文件

- `codex-rs/tui/src/bottom_pane/approval_overlay.rs` (1556 行)

### 依赖文件

```
codex-rs/tui/src/bottom_pane/
├── bottom_pane_view.rs       # BottomPaneView trait
├── list_selection_view.rs    # ListSelectionView
├── scroll_state.rs           # ScrollState
├── selection_popup_common.rs # GenericDisplayRow
└── mod.rs                    # 模块导出

codex-rs/tui/src/
├── app_event.rs              # AppEvent
├── app_event_sender.rs       # AppEventSender
├── diff_render.rs            # DiffSummary
├── exec_command.rs           # strip_bash_lc_and_escape
├── history_cell.rs           # 历史单元格
├── key_hint.rs               # KeyBinding
└── render/                   # 渲染工具

codex-core/src/
└── features.rs               # Features

codex-protocol/src/
├── models.rs                 # PermissionProfile, MacOs*Permission
├── protocol.rs               # ReviewDecision, Op, NetworkApprovalContext
└── request_permissions.rs    # RequestPermissionProfile
```

### 调用方

- `mod.rs` 中的 `push_approval_request` 方法

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `codex_core` | Features, PermissionProfile |
| `codex_protocol` | ThreadId, ReviewDecision, Op, NetworkApprovalContext 等 |
| `crossterm` | 键盘事件 |
| `ratatui` | TUI 渲染 |

### 发送的 AppEvent

- `InsertHistoryCell` - 记录历史
- `SubmitThreadOp` - 提交审批决策（ExecApproval, RequestPermissionsResponse, PatchApproval, ResolveElicitation）
- `FullScreenApprovalRequest` - 请求全屏审批
- `SelectAgentThread` - 选择线程

## 风险、边界与改进建议

### 风险点

1. **队列状态复杂性**：`current_complete` 和 `done` 两个标志位管理复杂，容易出错
2. **历史记录条件**：仅在 `thread_label.is_none()` 时记录历史，这个逻辑可能不透明
3. **权限格式化**：`format_additional_permissions_rule` 函数较长，维护成本高
4. **网络审批隐藏**：网络审批时隐藏 execpolicy 修正选项的逻辑可能令人困惑

### 边界情况

1. **空队列处理**：`advance_queue` 正确处理空队列情况
2. **Ctrl+C 处理**：即使已完成也会清空队列
3. **跨线程审批**：'o' 快捷键仅在 `thread_label` 存在时可用
4. **网络审批**：网络请求审批时不显示命令行，也不显示 "don't ask again" 选项

### 测试覆盖

文件包含约 556 行测试代码，覆盖：
- Ctrl+C 中止和队列清空
- 快捷键触发选择
- 跨线程审批的 'o' 快捷键
- ExecPolicy 修正选项
- 网络拒绝快捷键绑定
- Header 命令片段包含
- 网络审批提示标题
- 历史单元格换行

### 改进建议

1. **状态机重构**：考虑使用更明确的状态枚举替代 `current_complete` 和 `done`
2. **权限格式化拆分**：将 `format_additional_permissions_rule` 拆分为多个小函数
3. **快捷键发现性**：考虑在 footer hint 中显示更多可用快捷键
4. **错误处理**：当前某些路径静默失败（如 `handle_exec_decision` 中的 early return），可考虑添加日志
5. **测试组织**：测试代码较长，可考虑拆分到单独文件
