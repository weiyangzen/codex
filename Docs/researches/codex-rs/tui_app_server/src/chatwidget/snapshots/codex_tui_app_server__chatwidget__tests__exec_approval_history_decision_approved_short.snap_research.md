# 研究文档：exec_approval_history_decision_approved_short

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中短命令被批准（approved）时在历史记录中的显示行为。当用户批准执行一个简短的单条 shell 命令时，系统需要在历史记录中生成一条清晰、完整的决策记录。

**测试场景**：
- 用户收到一个短命令的执行批准请求（如 `echo hello world`）
- 用户按下 `y` 键批准执行
- 系统在历史记录中生成批准决策的文本表示

**Snapshot 内容**：
```
✔ You approved codex to run echo hello world this time
```

## 功能点目的

1. **决策确认记录**：记录用户批准命令执行的决定，提供审计追踪
2. **完整命令显示**：对于短命令，在历史记录中完整显示命令内容，无需截断
3. **积极反馈**：使用 `✔` 符号和明确的批准文本，提供正向视觉反馈
4. **时态表达**：使用 "this time" 表达，暗示这是一次性批准，非永久性授权

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `exec_approval_emits_proposed_command_and_decision_history`

### 核心测试逻辑

```rust
// 构造短命令的批准请求事件
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

// 验证批准请求不生成历史记录单元（仅通过模态框显示）
let proposed_cells = drain_insert_history(&mut rx);
assert!(
    proposed_cells.is_empty(),
    "expected approval request to render via modal without emitting history cells"
);

// 用户按下 'y' 批准
chat.handle_key_event(KeyEvent::new(KeyCode::Char('y'), KeyModifiers::NONE));

// 获取历史记录中的决策单元
let decision = drain_insert_history(&mut rx)
    .pop()
    .expect("expected decision cell in history");

// 验证 snapshot
assert_snapshot!(
    "exec_approval_history_decision_approved_short",
    lines_to_single_string(&decision)
);
```

### 决策文本生成逻辑

当用户批准命令执行时，系统生成格式化的决策文本：

```rust
// 伪代码表示
let decision_text = format!(
    "✔ You approved codex to run {} this time",
    command_snippet
);
```

其中 `command_snippet` 的生成规则：
- 短命令（< 80字符）：完整显示
- 长命令：截断并添加 `...`

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现，包含测试函数 `exec_approval_emits_proposed_command_and_decision_history` |
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 主逻辑，处理批准事件和键盘输入 |
| `codex-rs/tui_app_server/src/history_cell/` | 历史记录单元类型定义和渲染 |

### 关键代码路径

1. **批准请求处理**：
   ```
   ExecApprovalRequestEvent → ChatWidget::handle_codex_event
   → 提取 command 和 reason
   → 显示批准模态框（不生成历史记录）
   ```

2. **用户批准流程**：
   ```
   键盘输入 'y' → ChatWidget::handle_key_event
   → 构造 Op::ExecApproval { decision: Approved }
   → 通过 app_event_tx 发送操作
   → 生成批准历史记录单元
   ```

3. **历史记录渲染**：
   ```
   决策文本构造 → 命令片段提取 → 格式化输出
   → AppEvent::InsertHistoryCell
   ```

### 相关数据结构

```rust
// 执行批准操作
codex_protocol::protocol::Op::ExecApproval {
    id: String,           // approval_id 或 call_id
    decision: ReviewDecision,
    call_id: String,
}

// 审查决策枚举
codex_protocol::protocol::ReviewDecision {
    Approved,
    Aborted,
    // ...
}
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `codex_protocol::protocol::*` | 协议事件和操作类型定义 |
| `ratatui` | TUI 渲染框架 |
| `crossterm::event::*` | 键盘事件处理 |
| `insta::assert_snapshot` | Snapshot 测试断言 |

### 模块交互图

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户交互层                                │
│  ┌─────────────┐    按下 'y'    ┌─────────────┐                 │
│  │  批准模态框  │───────────────▶│  键盘处理器  │                 │
│  └─────────────┘                └──────┬──────┘                 │
└────────────────────────────────────────┼────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        业务逻辑层                                │
│  ┌─────────────┐    ExecApproval   ┌─────────────┐              │
│  │ ChatWidget  │──────────────────▶│  Op 通道    │              │
│  │             │                   │             │              │
│  │  构造决策文本 │──────────────────▶│ AppEvent通道 │              │
│  └─────────────┘  InsertHistoryCell └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        渲染层                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  历史记录面板（显示：✔ You approved codex to run...）    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **文本硬编码**：决策文本中的 "You approved codex to run ... this time" 是硬编码英文，不支持国际化
2. **命令注入显示**：如果命令包含特殊字符或换行符，显示可能不美观
3. **重复记录**：频繁的小命令批准可能导致历史记录过于冗长

### 边界情况

| 场景 | 预期行为 | 测试覆盖 |
|-----|---------|---------|
| 短命令（<80字符） | 完整显示命令 | ✅ 本测试覆盖 |
| 包含引号的命令 | 正确转义显示 | ⚠️ 需验证 |
| 包含换行符的命令 | 视为长命令截断 | ✅ `aborted_multiline` 测试覆盖 |
| 空命令 | 未定义行为 | ❌ 未测试 |

### 改进建议

1. **国际化（i18n）**：
   - 将用户可见字符串提取到资源文件
   - 支持多语言切换

2. **可配置性**：
   - 允许用户配置是否显示批准历史记录
   - 提供简洁模式（仅显示 ✔/✗ 符号）

3. **命令格式化**：
   - 对命令进行语法高亮
   - 对过长命令提供折叠/展开功能

4. **测试增强**：
   ```rust
   // 建议添加的测试用例
   #[tokio::test]
   async fn exec_approval_history_with_special_chars() {
       // 测试包含引号、反斜杠等特殊字符的命令
   }
   
   #[tokio::test]
   async fn exec_approval_history_with_unicode() {
       // 测试包含 Unicode 字符的命令
   }
   ```

5. **用户体验优化**：
   - 考虑添加时间戳到决策记录
   - 支持点击历史记录中的命令重新执行
   - 提供批量批准模式，减少重复确认

### 相关测试

- `exec_approval_emits_proposed_command_and_decision_history`：主测试函数
- `exec_approval_modal_exec`：测试批准模态框渲染
- `exec_approval_history_decision_aborted_multiline`：测试拒绝多行命令
- `exec_approval_uses_approval_id_when_present`：测试 approval_id 使用
