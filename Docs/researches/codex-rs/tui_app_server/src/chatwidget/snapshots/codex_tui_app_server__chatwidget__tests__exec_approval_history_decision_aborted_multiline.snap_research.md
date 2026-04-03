# 研究文档：exec_approval_history_decision_aborted_multiline

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中多行命令被拒绝（aborted）时在历史记录中的显示行为。当用户拒绝执行一个包含多行内容的 shell 命令时，系统需要在历史记录中生成一条简洁的决策记录，同时正确处理命令截断（truncation）以适配终端宽度。

**测试场景**：
- 用户收到一个多行命令的执行批准请求（如 `echo line1\necho line2`）
- 用户按下 `n` 键拒绝执行
- 系统在历史记录中生成拒绝决策的文本表示

**Snapshot 内容**：
```
✗ You canceled the request to run echo line1 ...
```

## 功能点目的

1. **决策历史记录**：记录用户对命令执行请求的最终决策（批准或拒绝）
2. **命令截断**：对于多行或超长命令，在历史记录中显示单行截断版本，避免占用过多屏幕空间
3. **视觉反馈**：使用 `✗` 符号和明确的文本提示，让用户清楚了解已取消的操作
4. **一致性保证**：确保历史记录格式在不同场景下保持一致

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `exec_approval_decision_truncates_multiline_and_long_commands`

### 核心测试逻辑

```rust
// 构造多行命令的批准请求事件
let ev_multi = ExecApprovalRequestEvent {
    call_id: "call-multi".into(),
    approval_id: Some("call-multi".into()),
    turn_id: "turn-multi".into(),
    command: vec!["bash".into(), "-lc".into(), "echo line1\necho line2".into()],
    cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    reason: Some("this is a test reason...".into()),
    // ... 其他字段
};

// 发送批准请求事件
chat.handle_codex_event(Event {
    id: "sub-multi".into(),
    msg: EventMsg::ExecApprovalRequest(ev_multi),
});

// 用户按下 'n' 拒绝
chat.handle_key_event(KeyEvent::new(KeyCode::Char('n'), KeyModifiers::NONE));

// 获取历史记录中的决策单元
let aborted_multi = drain_insert_history(&mut rx)
    .pop()
    .expect("expected aborted decision cell (multiline)");

// 验证 snapshot
assert_snapshot!(
    "exec_approval_history_decision_aborted_multiline",
    lines_to_single_string(&aborted_multi)
);
```

### 命令截断逻辑

当命令包含多行内容时，系统会：
1. 提取命令的第一行作为摘要
2. 如果超出长度限制，使用 `...` 进行截断
3. 确保历史记录行不超过 80 字符

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现，包含测试函数 `exec_approval_decision_truncates_multiline_and_long_commands` |
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 主逻辑，处理 `ExecApprovalRequest` 事件和键盘输入 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板管理，处理批准模态框的显示和交互 |

### 关键代码路径

1. **事件处理流程**：
   ```
   ExecApprovalRequestEvent → ChatWidget::handle_codex_event 
   → 显示批准模态框 → 等待用户输入
   ```

2. **用户决策流程**：
   ```
   键盘输入 'n' → ChatWidget::handle_key_event 
   → 发送 ExecApproval 操作（decision: Aborted）
   → 生成历史记录单元
   ```

3. **历史记录生成**：
   ```
   决策事件处理 → 构造决策文本 → 截断多行命令 
   → 发送到 AppEvent::InsertHistoryCell
   ```

### 相关数据结构

```rust
// 执行批准请求事件
codex_protocol::protocol::ExecApprovalRequestEvent {
    call_id: String,
    approval_id: Option<String>,
    turn_id: String,
    command: Vec<String>,  // 命令参数，bash -lc "实际命令"
    cwd: PathBuf,
    reason: Option<String>,
    // ...
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
| `codex_protocol::protocol::*` | 协议事件类型定义（ExecApprovalRequestEvent, ReviewDecision 等） |
| `ratatui` | TUI 渲染框架，用于模态框和历史记录显示 |
| `crossterm` | 终端事件处理（键盘输入） |
| `insta` | Snapshot 测试框架 |

### 与其他模块的交互

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   ChatWidget    │────▶│  BottomPane      │────▶│  批准模态框视图  │
│                 │     │  (模态框管理)     │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                                               │
         │                                               ▼
         │                                      ┌─────────────────┐
         │                                      │  用户输入处理    │
         │                                      │  (y/n/esc)      │
         │                                      └─────────────────┘
         │                                               │
         ▼                                               ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  历史记录单元    │◀────│  AppEvent 通道   │◀────│  决策提交       │
│  (决策记录)      │     │                  │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **截断信息丢失**：多行命令截断后可能丢失关键信息，用户无法从历史记录中了解完整的被拒绝命令
2. **国际化问题**：当前使用英文硬编码字符串，不支持多语言
3. **特殊字符处理**：命令中包含特殊字符时，截断逻辑可能产生意外结果

### 边界情况

| 场景 | 当前行为 | 注意事项 |
|-----|---------|---------|
| 超长单行命令（>200字符） | 截断至80字符并添加 `...` | 测试用例 `exec_approval_history_decision_aborted_long` 覆盖 |
| 多行命令 | 仅显示第一行并添加 `...` | 本测试用例覆盖 |
| 空命令 | 未明确测试 | 需要验证边界处理 |
| Unicode 字符 | 依赖 Rust 字符串处理 | 宽度计算可能不准确 |

### 改进建议

1. **可配置截断长度**：允许用户配置历史记录中命令显示的最大长度
2. **悬停提示**：在历史记录中支持悬停或快捷键查看完整命令
3. **多语言支持**：将硬编码字符串提取到资源文件中
4. **更智能的截断**：对于多行命令，考虑显示关键参数而非仅第一行
5. **测试覆盖**：增加对空命令、纯空格命令、特殊字符命令的测试

### 相关测试

- `exec_approval_history_decision_aborted_long`：测试超长单行命令的截断
- `exec_approval_history_decision_approved_short`：测试短命令批准场景
- `exec_approval_modal_exec`：测试批准模态框的渲染
