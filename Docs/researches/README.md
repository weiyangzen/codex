# Codex TUI Bottom Pane 快照测试研究文档索引

## 概述

本文档索引包含了 Codex TUI (Terminal User Interface) 项目中 `codex-rs/tui` 和 `codex-rs/tui_app_server` 两个 crate 的底部面板（Bottom Pane）组件的快照测试研究文档。

## 项目结构

### 源代码位置
- `/home/sansha/Github/codex/codex-rs/tui/src/bottom_pane/` - TUI 主实现
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/` - TUI App Server 并行实现

### 快照文件位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/bottom_pane/snapshots/` - 包含 215 个快照文件

## 快照文件命名规范

快照文件遵循以下命名模式：
```
codex_{crate}__bottom_pane__{module}__tests__{test_name}.snap
```

其中 `{crate}` 可以是：
- `tui` - 主 TUI crate
- `tui_app_server` - App Server crate（并行实现）

## 组件模块分类

### 1. App Link View (`app_link_view`)
管理 ChatGPT 应用的链接、安装和启用建议。

**关键快照**:
- `app_link_view_enable_suggestion_with_reason` - 启用应用建议
- `app_link_view_install_suggestion_with_reason` - 安装应用建议

**研究文档**:
- [App Link View - Enable Suggestion](./codex_tui__bottom_pane__app_link_view__tests__app_link_view_enable_suggestion_with_reason_research.md)
- [App Link View - Install Suggestion](./codex_tui__bottom_pane__app_link_view__tests__app_link_view_install_suggestion_with_reason_research.md)

### 2. Approval Overlay (`approval_overlay`)
处理用户审批请求，包括命令执行、权限请求、补丁应用等。

**关键快照**:
- `approval_overlay_additional_permissions_macos_prompt` - macOS 额外权限
- `approval_overlay_additional_permissions_prompt` - 通用额外权限
- `approval_overlay_cross_thread_prompt` - 跨线程审批
- `approval_overlay_permissions_prompt` - 独立权限请求
- `network_exec_prompt` - 网络访问审批

**研究文档**:
- [Approval Overlay - Additional Permissions macOS](./codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_macos_prompt_research.md)
- [Approval Overlay - Additional Permissions](./codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_additional_permissions_prompt_research.md)
- [Approval Overlay - Cross Thread](./codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_cross_thread_prompt_research.md)
- [Approval Overlay - Permissions Prompt](./codex_tui__bottom_pane__approval_overlay__tests__approval_overlay_permissions_prompt_research.md)
- [Approval Overlay - Network Exec](./codex_tui__bottom_pane__approval_overlay__tests__network_exec_prompt_research.md)

### 3. Chat Composer (`chat_composer`)
聊天输入编辑器，处理文本输入、粘贴、图片附件等。

**关键快照**:
- `backspace_after_pastes` - 粘贴后退格处理
- `empty` - 空状态渲染
- `footer_collapse_empty_full` - 底部提示完全展开
- `footer_mode_ctrl_c_interrupt` - Ctrl+C 中断模式
- `footer_mode_ctrl_c_quit` - Ctrl+C 退出模式
- `image_placeholder_multiple` - 多张图片占位符

**研究文档**:
- [Chat Composer - Backspace After Pastes](./codex_tui__bottom_pane__chat_composer__tests__backspace_after_pastes_research.md)
- [Chat Composer - Empty State](./codex_tui__bottom_pane__chat_composer__tests__empty_research.md)
- [Chat Composer - Footer Collapse Empty Full](./codex_tui__bottom_pane__chat_composer__tests__footer_collapse_empty_full_research.md)
- [Chat Composer - Footer Mode Ctrl+C Interrupt](./codex_tui__bottom_pane__chat_composer__tests__footer_mode_ctrl_c_interrupt_research.md)
- [Chat Composer - Image Placeholder Multiple](./codex_tui__bottom_pane__chat_composer__tests__image_placeholder_multiple_research.md)

### 4. Feedback View (`feedback_view`)
用户反馈收集界面。

**关键快照**:
- `feedback_view_render` - 日志上传确认界面
- `feedback_view_bad_result` - 不良结果反馈
- `feedback_view_bug` - Bug 报告
- `feedback_view_good_result` - 良好结果反馈
- `feedback_view_safety_check` - 安全检查反馈

**研究文档**:
- [Feedback View - Render](./codex_tui__bottom_pane__feedback_view__tests__feedback_view_render_research.md)

### 5. List Selection View (`list_selection_view`)
通用列表选择弹出组件。

**关键快照**:
- `list_selection_model_picker_width_80` - 模型选择器（80列）
- `list_selection_col_width_mode_auto_visible_scroll` - 自动列宽模式
- `list_selection_col_width_mode_fixed_scroll` - 固定列宽模式

**研究文档**:
- [List Selection View - Model Picker Width 80](./codex_tui__bottom_pane__list_selection_view__tests__list_selection_model_picker_width_80_research.md)

### 6. Pending Input Preview (`pending_input_preview`)
待处理输入和队列消息预览。

**关键快照**:
- `render_one_message` - 单条队列消息
- `render_two_messages` - 两条队列消息
- `render_pending_steers_above_queued_messages` - 待处理引导消息

**研究文档**:
- [Pending Input Preview - Render One Message](./codex_tui__bottom_pane__pending_input_preview__tests__render_one_message_research.md)

### 7. Footer (`footer`)
底部提示和状态显示。

**关键快照**:
- `footer_shortcuts_default` - 默认快捷键提示
- `footer_context_tokens_used` - 上下文 Token 使用
- `footer_mode_indicator_wide` - 宽屏模式指示器

### 8. Message Queue (`message_queue`)
消息队列显示。

**关键快照**:
- `render_one_message` - 单条消息
- `render_two_messages` - 两条消息

### 9. MCP Server Elicitation (`mcp_server_elicitation`)
MCP 服务器请求用户输入。

**关键快照**:
- `mcp_server_elicitation_approval_form_with_param_summary` - 带参数摘要的审批表单
- `mcp_server_elicitation_boolean_form` - 布尔值表单

### 10. Skills Toggle View (`skills_toggle_view`)
技能开关视图。

**关键快照**:
- `skills_toggle_basic` - 基础技能开关

### 11. Unified Exec Footer (`unified_exec_footer`)
统一执行页脚。

**关键快照**:
- `render_many_sessions` - 多会话显示

### 12. Status Line Setup (`status_line_setup`)
状态行设置。

**关键快照**:
- `setup_view_snapshot_uses_runtime_preview_values` - 运行时预览值

### 13. Bottom Pane 整体测试 (`mod`)

**关键快照**:
- `status_only_snapshot` - 仅状态显示
- `status_and_queued_messages_snapshot` - 状态和队列消息
- `queued_messages_visible_when_status_hidden_snapshot` - 状态隐藏时的队列消息

## TUI vs TUI App Server 关系

根据项目规范（AGENTS.md）:

> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

因此，`tui_app_server` 的快照与 `tui` 的快照内容基本一致，只是来源路径不同。研究文档主要针对 `tui` 的快照，但同样适用于 `tui_app_server` 的对应实现。

## 研究文档结构

每个研究文档包含以下部分：

1. **场景与职责** - 描述 UI 场景和组件职责
2. **功能点目的** - 解释功能的目的和用户体验目标
3. **具体技术实现** - 详细的技术实现，包括数据结构和核心流程
4. **关键代码路径与文件引用** - 列出关键源文件和代码路径
5. **依赖与外部交互** - 描述依赖和外部交互
6. **风险、边界与改进建议** - 识别风险、边界情况和改进建议

## 如何阅读研究文档

1. 根据你感兴趣的组件，在上方索引中找到对应的研究文档
2. 阅读"场景与职责"了解该组件的用途
3. 查看"具体技术实现"了解技术细节
4. 参考"关键代码路径"在源代码中定位具体实现
5. 查看"风险与改进建议"了解潜在问题和优化方向

## 贡献指南

如需添加新的研究文档，请遵循以下规范：

1. 使用中文撰写文档
2. 保持六部分结构
3. 包含具体的代码示例和路径
4. 提供实用的改进建议
5. 文件名格式：`{snapshot_name}_research.md`
