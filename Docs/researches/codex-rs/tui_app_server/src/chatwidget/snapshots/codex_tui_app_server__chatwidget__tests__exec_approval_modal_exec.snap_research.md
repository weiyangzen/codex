# 研究文档：exec_approval_modal_exec

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中命令执行批准模态框的渲染效果。当系统需要用户批准执行 shell 命令时，会显示一个模态框，展示命令详情、执行原因以及用户可选择的操作选项。

**测试场景**：
- 系统请求用户批准执行命令 `echo hello world`
- 提供执行原因（reason）："this is a test reason such as one that would be produced by the model"
- 渲染模态框，显示命令、原因和选项

**Snapshot 内容**（渲染后的 Buffer）：
```
Buffer {
    area: Rect { x: 0, y: 0, width: 80, height: 13 },
    content: [
        "                                                                                ",
        "                                                                                ",
        "  Would you like to run the following command?                                  ",
        "                                                                                ",
        "  Reason: this is a test reason such as one that would be produced by the       ",
        "  model                                                                         ",
        "                                                                                ",
        "  $ echo hello world                                                            ",
        "                                                                                ",
        "› 1. Yes, proceed (y)                                                           ",
        "  2. No, and tell Codex what to do differently (esc)                            ",
        "                                                                                ",
        "  Press enter to confirm or esc to cancel                                       ",
    ],
    styles: [...]  // 样式信息
}
```

## 功能点目的

1. **安全确认**：在执行潜在危险操作前，强制用户确认，防止意外执行
2. **信息透明**：向用户展示将要执行的完整命令和执行原因
3. **决策选项**：提供明确的批准（Yes）和拒绝（No）选项
4. **键盘友好**：支持键盘快捷键（y/esc/enter）进行操作
5. **视觉层次**：通过样式区分标题、原因、命令和选项区域

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `exec_approval_emits_proposed_command_and_decision_history`

### 核心测试逻辑

```rust
// 构造执行批准请求事件
let ev = ExecApprovalRequestEvent {
    call_id: "call-short".into(),
    approval_id: Some("call-short".into()),
    turn_id: "turn-short".into(),
    command: vec!["bash".into(), "-lc".into(), "echo hello world".into()],
    cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    reason: Some("this is a test reason such as one that would be produced by the model".into()),
    network_approval_context: None,
    proposed_execpolicy_amendment: None,
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
};

// 发送批准请求事件
chat.handle_codex_event(Event {
    id: "sub-short".into(),
    msg: EventMsg::ExecApprovalRequest(ev),
});

// 验证不生成历史记录单元（仅通过模态框显示）
let proposed_cells = drain_insert_history(&mut rx);
assert!(
    proposed_cells.is_empty(),
    "expected approval request to render via modal without emitting history cells"
);

// 渲染模态框并验证 snapshot
let area = Rect::new(0, 0, 80, chat.desired_height(80));
let mut buf = ratatui::buffer::Buffer::empty(area);
chat.render(area, &mut buf);
assert_snapshot!("exec_approval_modal_exec", format!("{buf:?}"));
```

### 模态框渲染流程

1. **事件处理**：`ChatWidget::handle_codex_event` 接收 `ExecApprovalRequestEvent`
2. **模态框创建**：构造批准模态框视图，传入命令、原因等参数
3. **模态框显示**：通过 `bottom_pane.show_view()` 显示模态框
4. **渲染输出**：`ChatWidget::render` 方法渲染当前状态，包括活动的模态框

### 样式应用

```rust
// 样式配置（基于 snapshot 中的 styles 数组）
- 标题（"Would you like to run..."）: BOLD 加粗
- 原因文本: ITALIC 斜体
- 命令（"$ echo hello world"）: Rgb(137, 180, 250) 蓝色前缀，Rgb(205, 214, 244) 白色文本
- 选中选项（"› 1. Yes..."）: Cyan + BOLD
- 提示文本（"Press enter..."）: DIM 暗淡
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 主逻辑，事件处理和渲染协调 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板管理，模态框显示控制 |
| `codex-rs/tui_app_server/src/bottom_pane/approval_modal.rs` | 批准模态框视图实现（推测） |

### 关键代码路径

```
ExecApprovalRequestEvent
    ↓
ChatWidget::handle_codex_event
    ↓
构造批准模态框视图
    ↓
BottomPane::show_view(模态框)
    ↓
ChatWidget::render
    ↓
BottomPane::render → 渲染模态框
    ↓
生成 Buffer（snapshot 捕获的内容）
```

### 相关数据结构

```rust
// 执行批准请求事件
codex_protocol::protocol::ExecApprovalRequestEvent {
    call_id: String,
    approval_id: Option<String>,  // 用于子命令批准
    turn_id: String,
    command: Vec<String>,         // ["bash", "-lc", "实际命令"]
    cwd: PathBuf,                 // 执行目录
    reason: Option<String>,       // 模型提供的执行原因
    network_approval_context: Option<NetworkApprovalContext>,
    proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    proposed_network_policy_amendments: Option<Vec<NetworkPolicyAmendment>>,
    additional_permissions: Option<Vec<Permission>>,
    skill_metadata: Option<SkillMetadata>,
    available_decisions: Option<Vec<ReviewDecision>>,  // 可用决策选项
    parsed_cmd: Vec<ParsedCommand>,
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui::buffer::Buffer` | TUI 缓冲区，用于捕获渲染输出 |
| `ratatui::layout::Rect` | 定义渲染区域 |
| `codex_protocol::protocol::*` | 协议事件类型 |
| `insta::assert_snapshot` | Snapshot 测试 |

### 架构交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                           协议层                                     │
│  ┌─────────────────┐                                                │
│  │ ExecApprovalRequestEvent │ ← 来自 codex_protocol                │
│  └────────┬────────┘                                                │
└───────────┼─────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ChatWidget 层                                │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  handle_codex   │───▶│  构造模态框视图  │───▶│  show_view()    │ │
│  │  _event()       │    │                 │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └────────┬────────┘ │
└─────────────────────────────────────────────────────────┼───────────┘
                                                          │
            ┌─────────────────────────────────────────────┘
            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        BottomPane 层                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  管理活动视图    │───▶│  委托渲染        │───▶│  捕获键盘事件    │ │
│  │                 │    │                 │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **布局溢出**：长命令或长原因文本可能导致模态框内容溢出或换行不美观
2. **样式一致性**：不同模态框之间的样式可能不一致
3. **可访问性**：纯文本界面可能不适用于屏幕阅读器等辅助技术

### 边界情况

| 场景 | 当前行为 | 注意事项 |
|-----|---------|---------|
| 无 reason | 不显示 Reason 行 | 测试用例 `approval_modal_exec_no_reason` 覆盖 |
| 多行命令 | 完整显示多行 | 测试用例 `approval_modal_exec_multiline_prefix_no_execpolicy` 覆盖 |
| 超长命令 | 可能换行或截断 | 需验证 |
| 窄终端（<80列） | 未测试 | 可能需要响应式布局 |

### 改进建议

1. **响应式布局**：
   - 测试不同终端宽度下的渲染效果
   - 对窄终端优化换行逻辑

2. **增强信息展示**：
   - 显示命令的执行目录（cwd）
   - 显示预计执行时间或风险等级
   - 添加命令的语法高亮

3. **交互优化**：
   - 支持方向键切换选项
   - 添加 "始终允许此类型命令" 选项
   - 支持预览命令输出（dry-run）

4. **测试增强**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn exec_approval_modal_narrow_terminal() {
       // 测试窄终端宽度（40列）下的渲染
   }
   
   #[tokio::test]
   async fn exec_approval_modal_long_command() {
       // 测试超长命令的显示
   }
   ```

5. **代码重构建议**：
   - 将模态框的样式配置提取为常量或主题配置
   - 使用 Builder 模式构造复杂的批准请求事件

### 相关测试

- `exec_approval_emits_proposed_command_and_decision_history`：主测试函数
- `approval_modal_exec_no_reason`：测试无原因时的模态框
- `approval_modal_exec_multiline_prefix_no_execpolicy`：测试多行命令
- `approval_modal_patch`：测试 Patch 批准模态框
- `exec_approval_uses_approval_id_when_present`：测试 approval_id 逻辑
