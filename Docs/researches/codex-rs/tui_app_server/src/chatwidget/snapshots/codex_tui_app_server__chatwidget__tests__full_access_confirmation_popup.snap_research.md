# full_access_confirmation_popup 快照研究文档

## 场景与职责

此快照测试验证 **tui_app_server** 中**完全访问权限确认弹出框**的渲染。当用户尝试启用"完全访问"（full access）权限模式时，系统显示此确认对话框，警告用户该模式的安全风险并请求明确确认。

这是安全关键功能，确保用户充分了解完全访问模式的潜在风险后再做决定。

## 功能点目的

1. **安全警告**：明确告知用户完全访问模式的安全风险
2. **知情同意**：确保用户在充分了解风险的情况下做出选择
3. **防止误操作**：通过额外的确认步骤防止意外启用高风险模式
4. **选项持久化**：允许用户选择是否记住此选择以供将来使用

### 完全访问模式的风险说明

根据弹出框内容，完全访问模式允许 Codex：
- 编辑计算机上的任何文件
- 无需批准即可运行网络命令
- 显著增加数据丢失、泄露或意外行为的风险

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 8548-8559 行

```rust
#[tokio::test]
async fn full_access_confirmation_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    let preset = builtin_approval_presets()
        .into_iter()
        .find(|preset| preset.id == "full-access")
        .expect("full access preset");
    chat.open_full_access_confirmation(preset, false);

    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("full_access_confirmation_popup", popup);
}
```

### 快照内容
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

### 核心实现逻辑

1. **预设查找**：
   - 使用 `builtin_approval_presets()` 获取内置审批预设
   - 查找 ID 为 `"full-access"` 的预设

2. **弹出框打开** (`open_full_access_confirmation`):
   - 位于 `codex-rs/tui_app_server/src/chatwidget.rs` 第 8451-8490 行
   - 构建 `SelectionViewParams` 显示确认选项

   ```rust
   pub(crate) fn open_full_access_confirmation(
       &mut self,
       preset: ApprovalPreset,
       return_to_permissions: bool,
   ) {
       let selected_name = preset.label.to_string();
       let params = crate::bottom_pane::full_access_confirmation_params(
           self.app_event_tx.clone(),
           preset,
           selected_name,
           return_to_permissions,
       );
       self.show_selection_view(params);
   }
   ```

3. **参数构建** (`full_access_confirmation_params`):
   - 位于 `codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 构建三个选项：
     - **Yes, continue anyway**：仅当前会话启用
     - **Yes, and don't ask again**：启用并记住选择
     - **Cancel**：取消并返回

4. **风险提示文本**：
   - 详细说明完全访问模式的能力范围
   - 强调潜在风险（数据丢失、泄露、意外行为）

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例定义 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | `open_full_access_confirmation` 方法 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 确认弹出框参数构建 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 选择弹出框渲染 |
| `codex-utils-approval-presets` | 内置审批预设定义 |

### 关键数据结构

```rust
// ApprovalPreset 结构
pub struct ApprovalPreset {
    pub id: String,
    pub label: String,
    pub description: Option<String>,
    pub approval_policy: AskForApproval,
    pub sandbox_policy: SandboxPolicy,
}

// SelectionViewParams 结构
pub struct SelectionViewParams {
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub header: Box<dyn Renderable>,
    pub items: Vec<SelectionItem>,
    pub footer_hint: Option<Line<'static>>,
}
```

## 依赖与外部交互

### 外部 crate 依赖
- **codex-utils-approval-presets**: 提供内置审批预设
  - `builtin_approval_presets()`: 返回所有可用预设
  - `"full-access"` 预设定义

### 内部模块交互
```
用户选择 full-access 预设
    └── open_full_access_confirmation()
            └── full_access_confirmation_params()
                    └── 构建 SelectionViewParams
                            └── show_selection_view()
                                    └── render_bottom_popup()
```

### 用户选择处理
| 选项 | 动作 |
|------|------|
| Yes, continue anyway | 应用完全访问到当前会话 |
| Yes, and don't ask again | 应用完全访问并持久化到配置 |
| Cancel | 关闭弹出框，不更改权限 |

## 风险、边界与改进建议

### 潜在风险

1. **用户忽视警告**：
   - 用户可能习惯性点击"Yes"而不阅读警告
   - 缓解措施：使用强调色和清晰的警告文本

2. **权限持久化风险**：
   - "don't ask again" 选项可能让用户忘记当前处于高风险模式
   - 需要在 UI 中持续显示当前权限状态

3. **社会工程攻击**：
   - 恶意技能可能尝试诱导用户启用完全访问
   - 需要确保确认对话框不能被自动化绕过

### 边界情况

1. **窄屏幕适配**：
   - 测试使用 80 字符宽度
   - 长描述文本需要正确换行

2. **键盘导航**：
   - 支持上下箭头选择
   - Enter 确认，Esc 取消

3. **重复确认**：
   - 如果用户已选择"don't ask again"，不应再次显示
   - 测试参数 `return_to_permissions` 控制返回行为

4. **配置冲突**：
   - 与其他权限设置的冲突处理
   - 需要明确的优先级规则

### 改进建议

1. **视觉警告增强**：
   - 使用红色或橙色边框突出警告性质
   - 添加警告图标（⚠️）增强视觉提示

2. **风险量化**：
   - 显示当前工作目录和可访问文件范围
   - 让用户了解具体的风险范围

3. **临时启用选项**：
   - 添加"仅本次命令启用"选项
   - 提供更细粒度的控制

4. **二次确认**：
   - 对于"don't ask again"选项，添加二次确认
   - 防止误点击导致持久化高风险设置

5. **撤销机制**：
   - 提供快速撤销完全访问的快捷方式
   - 在状态栏显示当前模式并提供切换入口

6. **审计日志**：
   - 记录完全访问模式的启用/禁用操作
   - 便于安全审计和问题追溯

7. **智能建议**：
   - 根据当前任务分析是否真的需要完全访问
   - 建议更安全的替代方案

### 相关测试

- `windows_auto_mode_prompt_requests_enabling_sandbox_feature`：Windows 自动模式提示
- `startup_prompts_for_windows_sandbox_when_agent_requested`：启动时 Windows 沙盒提示
- `permissions_selection_history_*`：权限选择历史记录测试

### 安全最佳实践

1. **默认安全**：默认使用最严格的权限模式
2. **最小权限**：仅在必要时请求完全访问
3. **透明性**：明确告知用户当前权限状态
4. **可逆性**：允许用户随时撤销高风险权限

此弹出框是实现这些安全原则的关键组件。
