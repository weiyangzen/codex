# Research: approval_modal_exec_multiline_prefix_no_execpolicy (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中多行命令的批准模态框渲染效果，特别是当命令包含多行内容时，系统不会提供"添加到执行策略"的选项（因为多行前缀不适合作为执行策略模式）。

**测试目的**：确保多行命令的批准模态框正确隐藏执行策略选项，同时保持其他功能的完整性。

## 功能点目的

1. **多行命令检测**：识别包含换行符的命令
2. **选项动态调整**：根据命令特性动态调整可用选项
3. **安全策略**：防止将多行命令前缀添加到自动执行策略（避免安全风险）
4. **清晰展示**：正确渲染多行命令内容

## 具体技术实现

### Snapshot 内容
```


  Would you like to run the following command?

  $ python - <<'PY'
  print('hello')
  PY

› 1. Yes, proceed (y)
  2. No, and tell Codex what to do differently (esc)

  Press enter to confirm or esc to cancel
```

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approval_modal_exec_multiline_prefix_hides_execpolicy_option_snapshot` (约 line 9665)

2. **多行检测逻辑**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 函数：`exec_options` (约 line 664-684)
   ```rust
   let rendered_prefix = strip_bash_lc_and_escape(proposed_execpolicy_amendment.command());
   if rendered_prefix.contains('\n') || rendered_prefix.contains('\r') {
       return None;  // 隐藏执行策略选项
   }
   ```

3. **命令构建**：
   ```rust
   let script = "python - <<'PY'\nprint('hello')\nPY".to_string();
   let command = vec!["bash".into(), "-lc".into(), script];
   ```

4. **选项过滤**：
   - 当检测到多行命令时，`ReviewDecision::ApprovedExecpolicyAmendment` 选项被过滤掉
   - 只保留 `Approved` 和 `Abort` 两个基本选项

### 数据结构

```rust
// 多行命令示例
codex_protocol::protocol::ExecApprovalRequestEvent {
    call_id: "call-approve-cmd-multiline-trunc".into(),
    approval_id: Some("call-approve-cmd-multiline-trunc".into()),
    turn_id: "turn-approve-cmd-multiline-trunc".into(),
    command: vec!["bash".into(), "-lc".into(), script],  // script 包含换行符
    cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    reason: None,
    network_approval_context: None,
    proposed_execpolicy_amendment: Some(ExecPolicyAmendment::new(command)),  // 多行命令
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
}
```

### 选项对比

| 场景 | 选项数量 | 执行策略选项 |
|------|----------|--------------|
| 单行命令 | 3 | 有 (p键) |
| 多行命令 | 2 | 无 |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::approval_overlay` | 批准模态框主逻辑 |
| `exec_command::strip_bash_lc_and_escape` | 命令字符串处理和转义 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `ExecApprovalRequestEvent` | `codex_protocol::protocol` |
| `ExecPolicyAmendment` | `codex_protocol::protocol` |
| `ReviewDecision::ApprovedExecpolicyAmendment` | `codex_protocol::protocol` |

### 安全考虑
- 多行命令可能包含复杂的脚本逻辑
- 自动执行多行命令存在潜在安全风险
- 通过隐藏执行策略选项，强制用户逐行审批

## 风险、边界与改进建议

### 当前风险
1. **换行符变体**：仅检测 `\n` 和 `\r`，可能遗漏其他换行符变体
2. **命令注入**：多行命令可能包含隐藏的控制字符
3. **显示截断**：过长的多行命令可能在终端中显示不完整

### 边界情况
1. **空行**：命令中包含空行时的处理
2. **缩进**：带缩进的多行命令（如 Python 代码）
3. **混合命令**：单行和多行混合的复杂命令
4. **Here Document**：如测试中的 `<<'PY'` 语法

### 改进建议
1. **增强检测**：使用更全面的换行符检测（包括 Unicode 换行符）
2. **代码折叠**：为长多行命令提供折叠/展开功能
3. **语法高亮**：对多行命令中的代码进行语法高亮
4. **安全警告**：对多行命令显示额外的安全提示
5. **预览模式**：提供命令执行预览功能

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__approval_modal_exec_multiline_prefix_no_execpolicy.snap` 保持平行实现
- 多行命令检测逻辑在两个版本中完全一致
- 安全策略在两个版本中统一执行

### 测试验证点
1. ✅ 多行命令正确渲染
2. ✅ 执行策略选项被隐藏
3. ✅ 基本批准/拒绝选项仍然可用
4. ✅ 页脚提示正确显示
