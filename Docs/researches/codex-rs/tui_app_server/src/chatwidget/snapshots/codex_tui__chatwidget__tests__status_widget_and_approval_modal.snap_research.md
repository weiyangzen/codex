# 研究文档：status_widget_and_approval_modal

## 场景与职责

此 snapshot 测试验证状态小部件（Status Widget）和批准模态框（Approval Modal）同时显示时的布局。测试场景包括：
- 一个正在运行的任务（状态指示器活动）
- 显示 "Analyzing" 状态头
- 同时弹出一个执行批准模态框
- 模态框询问用户是否运行命令 `echo 'hello world'`
- 提供三个选项：是、是且不再询问、否

该测试确保在需要用户批准时，模态框能够正确覆盖状态指示器，同时保持界面布局的完整性。

## 功能点目的

批准模态框与安全执行机制紧密集成：
1. **执行拦截**：在运行潜在危险命令前暂停并请求用户确认
2. **上下文提供**：显示命令内容和执行原因，帮助用户做出明智决策
3. **策略学习**：允许用户选择 "是且不再询问" 来建立自动批准规则
4. **状态保持**：后台任务状态仍然保持活动，模态框关闭后可继续
5. **键盘导航**：支持数字键（1/2/3）和字母键（y/p/esc）快速选择

这种设计在安全性和便利性之间取得了平衡。

## 具体技术实现

### 测试设置
```rust
let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. 开始运行任务，激活状态指示器
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: "turn-1".to_string(),
        model_context_window: None,
        collaboration_mode_kind: ModeKind::Default,
    }),
});

// 2. 设置确定性状态头
chat.handle_codex_event(Event {
    id: "task-1".into(),
    msg: EventMsg::AgentReasoningDelta(AgentReasoningDeltaEvent {
        delta: "**Analyzing**".into(),
    }),
});

// 3. 显示执行批准模态框
let ev = ExecApprovalRequestEvent {
    call_id: "call-approve-exec".into(),
    approval_id: Some("call-approve-exec".into()),
    turn_id: "turn-approve-exec".into(),
    command: vec!["echo".into(), "hello world".into()],
    cwd: PathBuf::from("/tmp"),
    reason: Some("this is a test reason such as one that would be produced by the model".into()),
    network_approval_context: None,
    proposed_execpolicy_amendment: Some(ExecPolicyAmendment::new(vec![
        "echo".into(),
        "hello world".into(),
    ])),
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
};
chat.handle_codex_event(Event {
    id: "sub-approve-exec".into(),
    msg: EventMsg::ExecApprovalRequest(ev),
});
```

### 渲染输出格式
```
"                                                                                                    "
"                                                                                                    "
"  Would you like to run the following command?                                                      "
"                                                                                                    "
"  Reason: this is a test reason such as one that would be produced by the model                     "
"                                                                                                    "
"  $ echo 'hello world'                                                                              "
"                                                                                                    "
"› 1. Yes, proceed (y)                                                                               "
"  2. Yes, and don't ask again for commands that start with `echo 'hello world'` (p)                 "
"  3. No, and tell Codex what to do differently (esc)                                                "
"                                                                                                    "
"  Press enter to confirm or esc to cancel                                                           "
```

格式解析：
- 第1-2行：空行（顶部边距）
- 第3行：模态框标题
- 第4行：空行（间距）
- 第5行：执行原因说明
- 第6行：空行
- 第7行：要执行的命令（带 `$` 前缀）
- 第8行：空行
- 第9-11行：三个选项（带键盘快捷键提示）
  - `›` 表示当前选中项
- 第12行：空行
- 第13行：操作提示

### 模态框层次结构
```
┌─────────────────────────────────────┐
│  Bottom Pane (底层)                  │
│  ├─ Status Indicator (被覆盖)        │
│  ├─ Composer (被覆盖)                │
│  └─ Footer (被覆盖)                  │
├─────────────────────────────────────┤
│  Approval Overlay (覆盖层)           │
│  ├─ Title                           │
│  ├─ Reason                          │
│  ├─ Command                         │
│  ├─ Options (1/2/3)                 │
│  └─ Hint                            │
└─────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/bottom_pane/approval_overlay.rs`**
   - 实现批准模态框的渲染逻辑
   - 处理选项选择和键盘导航
   - 管理模态框的显示/隐藏

2. **`codex-rs/tui/src/bottom_pane/bottom_pane_view.rs`**
   - 定义 `BottomPaneView` trait
   - 管理视图层次和覆盖逻辑

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 9430-9487）
   - 测试函数 `status_widget_and_approval_modal_snapshot`
   - 验证模态框与状态指示器的组合渲染

### 相关数据结构
```rust
// ExecApprovalRequestEvent - 执行批准请求
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub approval_id: Option<String>,
    pub turn_id: String,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    // ... 其他字段
}

// ExecPolicyAmendment - 执行策略修正案
pub struct ExecPolicyAmendment {
    pub command_prefix: Vec<String>,
}
```

### 模态框状态机
```
Idle → ApprovalRequested → UserDecision
         ↓
    ┌────┴────┐
    ↓         ↓
 Approved   Denied
    ↓         ↓
 Executed   Cancelled
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::approval_overlay` | 批准模态框实现 |
| `bottom_pane::bottom_pane_view` | 视图管理和覆盖逻辑 |
| `chatwidget::ChatWidget` | 事件路由和状态协调 |

### 事件依赖
- `ExecApprovalRequestEvent`：触发批准模态框显示
- `TurnStartedEvent`：激活后台任务状态
- `AgentReasoningDeltaEvent`：更新状态头

### 安全依赖
- `ExecPolicyAmendment`：记录用户的自动批准偏好
- `SandboxPolicy`：执行环境安全策略

## 风险、边界与改进建议

### 潜在风险
1. **模态框堆叠**：多个批准请求同时到达时可能导致模态框堆叠混乱
2. **状态丢失**：模态框关闭后，后台任务状态可能未正确恢复
3. **键盘冲突**：模态框快捷键与全局快捷键可能冲突

### 边界情况
1. **超长命令**：命令过长时应在模态框中换行或截断
2. **多行原因**：执行原因可能跨越多行，需要正确处理换行
3. **窄终端**：终端宽度不足时，选项文本可能被截断
4. **超时处理**：用户长时间不响应时的默认行为

### 改进建议
1. **命令语法高亮**：在模态框中对命令进行语法高亮显示
2. **风险评级**：根据命令类型显示风险级别（低/中/高）
3. **历史参考**：显示类似命令的历史批准记录
4. **批量批准**：对于相关命令组提供批量批准选项
5. **模态框动画**：添加淡入淡出动画提升用户体验
6. **声音提示**：重要批准请求播放提示音

### 相关测试
- `status_widget_and_approval_modal_snapshot`：本测试文件
- `status_widget_active_snapshot`：状态小部件单独测试
- `approval_modal_exec_snapshot`：执行批准模态框单独测试
