# Research: approval_modal_exec (App Server)

## 场景与职责

此 snapshot 测试验证 **tui_app_server** 中命令执行批准模态框的渲染效果。当 Codex 需要执行一个 shell 命令时，会显示一个模态框请求用户批准，展示命令内容、执行原因以及可用的决策选项。

**测试目的**：确保命令批准模态框的 UI 布局、文本格式和交互选项正确渲染。

## 功能点目的

1. **命令审批界面**：在执行敏感操作前获取用户明确授权
2. **信息展示**：显示待执行命令、执行原因、可用选项
3. **快捷操作**：提供键盘快捷键（y/p/esc）快速选择决策
4. **执行策略建议**：允许用户将命令前缀添加到自动执行策略中

## 具体技术实现

### Snapshot 内容
```


  Would you like to run the following command?

  Reason: this is a test reason such as one that would be produced by the model

  $ echo hello world

› 1. Yes, proceed (y)
  2. Yes, and don't ask again for commands that start with `echo hello world` (p)
  3. No, and tell Codex what to do differently (esc)

  Press enter to confirm or esc to cancel
```

### 关键代码路径

1. **测试函数**：
   - 文件：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 函数：`approval_modal_exec_snapshot` (约 line 9549)

2. **批准覆盖层创建**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 结构：`ApprovalOverlay`
   - 方法：`new`

3. **执行选项构建**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 函数：`exec_options` (约 line 646)
   - 根据 `available_decisions` 构建选项列表

4. **头部渲染**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/approval_overlay.rs`
   - 函数：`build_header` (约 line 502)
   - 渲染命令、原因、权限规则等信息

5. **列表选择视图**：
   - 文件：`codex-rs/tui_app_server/src/bottom_pane/list_selection_view.rs`
   - 结构：`ListSelectionView`
   - 处理选项的渲染和选择逻辑

### 数据结构

```rust
// 执行批准请求事件
codex_protocol::protocol::ExecApprovalRequestEvent {
    call_id: "call-approve-cmd".into(),
    approval_id: Some("call-approve-cmd".into()),
    turn_id: "turn-approve-cmd".into(),
    command: vec!["bash".into(), "-lc".into(), "echo hello world".into()],
    cwd: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    reason: Some("this is a test reason such as one that would be produced by the model".into()),
    network_approval_context: None,
    proposed_execpolicy_amendment: Some(ExecPolicyAmendment::new(vec!["echo".into(), "hello".into(), "world".into()])),
    proposed_network_policy_amendments: None,
    additional_permissions: None,
    skill_metadata: None,
    available_decisions: None,
    parsed_cmd: vec![],
}
```

### 可用决策选项

| 选项 | 快捷键 | 决策类型 |
|------|--------|----------|
| Yes, proceed | y | `ReviewDecision::Approved` |
| Yes, and don't ask again... | p | `ReviewDecision::ApprovedExecpolicyAmendment` |
| No, and tell Codex... | esc | `ReviewDecision::Abort` |

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `bottom_pane::approval_overlay` | 批准模态框主逻辑 |
| `bottom_pane::list_selection_view` | 选项列表渲染和选择 |
| `exec_command::strip_bash_lc_and_escape` | 命令字符串处理 |
| `render::highlight` | 命令语法高亮 |

### 协议依赖
| 类型 | 来源 |
|------|------|
| `ExecApprovalRequestEvent` | `codex_protocol::protocol` |
| `ExecPolicyAmendment` | `codex_protocol::protocol` |
| `ReviewDecision` | `codex_protocol::protocol` |

### 渲染依赖
- `ratatui::Terminal` + `VT100Backend`：终端渲染
- `strip_bash_lc_and_escape`：移除 bash -lc 包装并转义命令

## 风险、边界与改进建议

### 当前风险
1. **命令长度**：长命令可能导致模态框超出屏幕宽度
2. **原因长度**：过长的原因文本可能影响布局
3. **特殊字符**：包含特殊字符的命令需要正确转义显示

### 边界情况
1. **无原因场景**：参见 `approval_modal_exec_no_reason` snapshot
2. **多行命令**：参见 `approval_modal_exec_multiline_prefix_no_execpolicy` snapshot
3. **网络审批**：当 `network_approval_context` 存在时，标题和选项会变化
4. **附加权限**：当 `additional_permissions` 存在时，显示权限规则

### 改进建议
1. **命令折叠**：对于超长命令，提供折叠/展开功能
2. **语法高亮增强**：增强 shell 命令的语法高亮
3. **历史记录集成**：显示类似命令的历史审批记录
4. **风险评级**：根据命令类型显示风险等级指示器

### 与 TUI 版本的关系
- 与 `codex_tui__chatwidget__tests__approval_modal_exec.snap` 保持平行实现
- 遵循 AGENTS.md 中 "TUI code conventions" 的平行实现约定
- 任何对 TUI 版本的修改应同步到 App Server 版本
