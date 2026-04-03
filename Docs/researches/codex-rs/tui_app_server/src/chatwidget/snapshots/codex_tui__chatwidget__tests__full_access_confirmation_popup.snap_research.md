# 研究文档：完全访问权限确认弹出框

## 场景与职责

本快照测试验证 Codex TUI 在启用"完全访问权限"(Full Access)模式前的安全警告界面。当用户尝试切换到完全访问权限模式时，系统显示此确认弹窗，明确告知用户该模式的风险，并要求用户明确确认。

完全访问权限模式允许 Codex 无需用户批准即可编辑任何文件和运行网络命令，这是一个高风险的安全设置。

## 功能点目的

1. **安全风险告知**：明确告知用户完全访问权限的风险
2. **用户明确同意**：要求用户主动选择，避免误操作
3. **多选项设计**：提供"仅本次"、"记住选择"和"取消"三种选项
4. **视觉警示**：使用红色文本强调风险警告

## 具体技术实现

### 核心数据结构

```rust
// ApprovalPreset 定义
pub struct ApprovalPreset {
    pub id: String,           // "full-access"
    pub label: String,        // 显示名称
    pub approval: ApprovalMode,
    pub sandbox: SandboxMode,
}

// 审批模式
pub enum ApprovalMode {
    FullAccess,      // 完全访问
    Auto,            // 自动审批
    Manual,          // 手动审批
}
```

### 完全访问权限确认弹窗实现

```rust
// chatwidget.rs
pub(crate) fn open_full_access_confirmation(
    &mut self,
    preset: ApprovalPreset,
    return_to_permissions: bool,
) {
    let selected_name = preset.label.to_string();
    let approval = preset.approval;
    let sandbox = preset.sandbox;
    let mut header_children: Vec<Box<dyn Renderable>> = Vec::new();
    
    // 标题
    let title_line = Line::from("Enable full access?").bold();
    
    // 警告信息，使用红色强调
    let info_line = Line::from(vec![
        "When Codex runs with full access, it can edit any file on your computer and run commands with network, without your approval. "
            .into(),
        "Exercise caution when enabling full access. This significantly increases the risk of data loss, leaks, or unexpected behavior."
            .fg(Color::Red),  // 红色警告
    ]);
    
    header_children.push(Box::new(title_line));
    header_children.push(Box::new(
        Paragraph::new(vec![info_line]).wrap(Wrap { trim: false }),
    ));
    let header = ColumnRenderable::with(header_children);

    // 构建选项动作
    let mut accept_actions = Self::approval_preset_actions(
        approval,
        sandbox.clone(),
        selected_name.clone(),
        ApprovalsReviewer::User,
    );
    accept_actions.push(Box::new(|tx| {
        tx.send(AppEvent::UpdateFullAccessWarningAcknowledged(true));
    }));
    
    // 显示选择弹窗...
}
```

### 测试代码（来自 tests.rs）

```rust
// tui/src/chatwidget/tests.rs
#[tokio::test]
async fn full_access_confirmation_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // 获取 full-access 预设
    let preset = builtin_approval_presets()
        .into_iter()
        .find(|preset| preset.id == "full-access")
        .expect("full access preset");
    
    // 打开完全访问权限确认弹窗
    chat.open_full_access_confirmation(preset, false);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("full_access_confirmation_popup", popup);
}
```

### 快照输出解析

```
  Enable full access?
  When Codex runs with full access, it can edit any file on your computer and
  run commands with network, without your approval. Exercise caution when
  enabling full access. This significantly increases the risk of data loss,
  leaks, or unexpected behavior.

› 1. Yes, continue anyway      Apply full access for this session
  2. Yes, and don't ask again  Enable full access and remember this choice
  3. Cancel                    Go back without enabling full access

  Press enter to confirm or esc to go back
```

UI 元素分析：
- **标题**：`Enable full access?` - 明确询问
- **警告文本**：详细说明风险，第二段使用红色显示
- **三个选项**：
  1. `Yes, continue anyway` - 仅本次会话启用
  2. `Yes, and don't ask again` - 启用并记住选择
  3. `Cancel` - 取消，不启用
- **操作提示**：Enter 确认，Esc 返回

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget.rs` | ChatWidget 实现，包含 `open_full_access_confirmation` 方法（约第 7372 行开始） |
| `codex-rs/tui/src/chatwidget/tests.rs` | 快照测试定义（约第 7950-7961 行） |
| `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 列表选择视图实现 |
| `codex-rs/tui/src/approval_preset.rs` | 审批预设定义（builtin_approval_presets） |
| `codex-protocol/src/models/permission_profile.rs` | 权限模型定义 |
| `codex-rs/tui/src/chatwidget/snapshots/codex_tui__chatwidget__tests__full_access_confirmation_popup.snap` | 本快照文件 |

### 相关测试函数

- `full_access_confirmation_popup_snapshot()` - 本测试
- `open_full_access_confirmation()` - 确认弹窗打开方法
- `builtin_approval_presets()` - 内置审批预设

### 相关权限预设

```rust
// 内置审批预设
fn builtin_approval_presets() -> Vec<ApprovalPreset> {
    vec![
        ApprovalPreset {
            id: "full-access".to_string(),
            label: "Full Access".to_string(),
            approval: ApprovalMode::FullAccess,
            sandbox: SandboxMode::None,
        },
        // ... 其他预设
    ]
}
```

## 依赖与外部交互

### 依赖模块

1. **ApprovalPreset 系统**
   ```rust
   pub struct ApprovalPreset {
       pub id: String,
       pub label: String,
       pub approval: ApprovalMode,
       pub sandbox: SandboxMode,
   }
   ```

2. **权限模型**
   ```rust
   pub enum ApprovalMode {
       FullAccess,  // 无需批准
       Auto,        // 自动审批（基于 Guardian）
       Manual,      // 始终需要用户批准
   }
   ```

3. **AppEvent 系统**
   ```rust
   pub enum AppEvent {
       UpdateFullAccessWarningAcknowledged(bool),
       // ...
   }
   ```

4. **ratatui**
   - 使用 `Color::Red` 显示警告文本
   - 使用 `Wrap` 处理长文本换行

### 安全考虑

1. **警告确认状态**
   - `UpdateFullAccessWarningAcknowledged` 事件记录用户已确认警告
   - 用于避免重复显示警告

2. **选项设计**
   - "don't ask again" 选项需要额外确认，防止误选
   - 默认选中 "Cancel" 或 "continue anyway"（最安全选项）

## 风险、边界与改进建议

### 潜在风险

1. **用户忽视警告**
   - 用户可能不阅读警告文本直接确认
   - 红色警告可能被某些终端主题淡化

2. **误选 "don't ask again"**
   - 用户可能误选永久启用，之后忘记
   - 需要更明显的确认流程

3. **权限提升攻击**
   - 恶意代码可能尝试自动启用完全访问
   - 需要确保确认弹窗不能被自动绕过

### 边界情况

| 场景 | 预期行为 |
|------|---------|
| 用户按 Esc | 取消，不启用完全访问 |
| 用户选择选项 1 | 仅当前会话启用，下次仍询问 |
| 用户选择选项 2 | 启用并记住，更新配置 |
| 用户选择选项 3 | 取消，返回权限选择 |
| 配置已启用完全访问 | 可能不需要再次确认 |

### 改进建议

1. **安全增强**
   - 添加 "don't ask again" 的二次确认
   - 要求用户输入 "I understand" 才能启用
   - 添加启用完全访问的审计日志

2. **用户体验优化**
   - 添加风险等级的可视化指示（如红色警告图标）
   - 提供快速切换到更安全模式的快捷方式
   - 显示当前模式的安全等级对比

3. **教育引导**
   - 添加链接到安全最佳实践文档
   - 提供完全访问模式的使用场景说明
   - 解释 Guardian 审核作为替代方案

4. **测试覆盖**
   - 添加测试验证警告确认状态的持久化
   - 测试不同终端主题下的警告可见性
   - 测试权限切换的边界情况

5. **合规考虑**
   - 记录用户同意启用完全访问的日志
   - 提供撤销同意的机制
   - 考虑企业环境的策略限制
