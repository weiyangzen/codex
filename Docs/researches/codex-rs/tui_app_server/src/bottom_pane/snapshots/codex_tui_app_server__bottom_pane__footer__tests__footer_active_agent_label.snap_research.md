# Research: Footer Active Agent Label Snapshot

## 场景与职责

此快照展示了 TUI 底部栏（Footer）在显示活动代理（Active Agent）标签时的状态。当用户配置了特定的 AI 代理（如 "Robie"）并选择了特定模式（如 "explorer"）时，底部栏会在左侧显示代理名称和当前模式标签，帮助用户了解当前正在与哪个代理进行交互以及代理的工作模式。

## 功能点目的

- **代理身份识别**: 明确显示当前活动的 AI 代理名称（如 "Robie"）
- **代理模式标识**: 显示代理当前的工作模式（如 "explorer"），帮助用户理解代理的行为特性
- **上下文状态反馈**: 右侧显示 "100% context left"，告知用户当前会话上下文的剩余容量

## 具体技术实现

底部栏通过 `FooterProps` 接收 `active_agent_label` 参数，当该参数存在时，会在左侧显示代理信息。显示格式为 `"AgentName [mode]"`，其中：
- `AgentName` 是代理的显示名称
- `[mode]` 是方括号包裹的代理模式标识

布局上采用 `single_line_footer_layout` 进行宽度自适应：
- 左侧显示代理标签和快捷提示
- 右侧显示上下文窗口使用情况
- 中间为输入区域或状态信息

## 关键代码路径与文件引用

- **主要实现**: `codex-rs/tui_app_server/src/bottom_pane/footer.rs`
- **布局逻辑**: `single_line_footer_layout()` 函数处理单行布局
- **代理标签渲染**: 在 `FooterMode::ComposerEmpty` 或类似模式下渲染 `active_agent_label`
- **上下文显示**: `context_window_line()` 函数生成右侧上下文信息

## 依赖与外部交互

- 依赖 `FooterProps.active_agent_label: Option<String>` 接收代理标签信息
- 依赖 `Agent` 配置信息获取代理名称和模式
- 与 `CollaborationModeIndicator` 独立显示，代理标签优先于模式指示器显示

## 风险、边界与改进建议

- **边界情况**: 当代理名称过长时，可能需要截断处理以避免与右侧上下文信息重叠
- **改进建议**: 考虑在代理标签旁添加视觉指示器（如颜色或图标）区分不同代理
- **改进建议**: 当代理模式切换时，可以添加短暂的视觉反馈（如高亮）提示用户
