# 研究文档：experimental_features_popup

## 场景与职责

此 snapshot 测试用例验证 **tui_app_server** 中实验性功能弹出框的渲染效果。该弹出框允许用户查看和切换实验性功能的状态，如 "Ghost snapshots" 和 "Shell tool" 等。

**测试场景**：
- 用户打开实验性功能设置界面
- 界面显示两个实验性功能项：
  - "Ghost snapshots"（未启用）：每轮对话捕获撤销快照
  - "Shell tool"（已启用）：允许模型运行 shell 命令
- 渲染弹出框并验证显示效果

**Snapshot 内容**：
```
  Experimental features
  Toggle experimental features. Changes are saved to config.toml.

› [ ] Ghost snapshots  Capture undo snapshots each turn.
  [x] Shell tool       Allow the model to run shell commands.

  Press space to select or enter to save for next conversation
```

## 功能点目的

1. **功能发现**：让用户了解可用的实验性功能
2. **状态管理**：显示每个功能的当前启用状态（`[ ]` 未启用 / `[x]` 已启用）
3. **交互控制**：允许用户切换功能开关
4. **配置持久化**：提示更改将保存到 `config.toml`
5. **键盘操作**：支持空格键切换、回车键保存

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` - 函数 `experimental_features_popup_snapshot`

### 核心测试逻辑

```rust
#[tokio::test]
async fn experimental_features_popup_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    // 构造实验性功能列表
    let features = vec![
        ExperimentalFeatureItem {
            feature: Feature::GhostCommit,
            name: "Ghost snapshots".to_string(),
            description: "Capture undo snapshots each turn.".to_string(),
            enabled: false,
        },
        ExperimentalFeatureItem {
            feature: Feature::ShellTool,
            name: "Shell tool".to_string(),
            description: "Allow the model to run shell commands.".to_string(),
            enabled: true,
        },
    ];
    
    // 创建实验性功能视图
    let view = ExperimentalFeaturesView::new(features, chat.app_event_tx.clone());
    chat.bottom_pane.show_view(Box::new(view));

    // 渲染并验证 snapshot
    let popup = render_bottom_popup(&chat, 80);
    assert_snapshot!("experimental_features_popup", popup);
}
```

### ExperimentalFeaturesView 实现

位于 `codex-rs/tui_app_server/src/bottom_pane/experimental_features_view.rs`：

```rust
pub(crate) struct ExperimentalFeaturesView {
    features: Vec<ExperimentalFeatureItem>,
    state: ScrollState,
    complete: bool,
    app_event_tx: AppEventSender,
    header: Box<dyn Renderable>,
    footer_hint: Line<'static>,
}

pub(crate) struct ExperimentalFeatureItem {
    pub feature: Feature,
    pub name: String,
    pub description: String,
    pub enabled: bool,
}
```

### 渲染逻辑

```rust
impl Renderable for ExperimentalFeaturesView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 1. 布局分割：内容区 + 底部提示区
        let [content_area, footer_area] =
            Layout::vertical([Constraint::Fill(1), Constraint::Length(1)]).areas(area);

        // 2. 渲染内容块
        Block::default()
            .style(user_message_style())
            .render(content_area, buf);

        // 3. 渲染标题
        self.header.render(header_area, buf);

        // 4. 渲染功能列表行
        render_rows(render_area, buf, &rows, &self.state, MAX_POPUP_ROWS, "...");

        // 5. 渲染底部提示
        self.footer_hint.clone().dim().render(hint_area, buf);
    }
}
```

### 键盘事件处理

```rust
impl BottomPaneView for ExperimentalFeaturesView {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        match key_event {
            // 上下移动选择
            KeyEvent { code: KeyCode::Up, .. } => self.move_up(),
            KeyEvent { code: KeyCode::Down, .. } => self.move_down(),
            
            // 空格键切换选中项
            KeyEvent { code: KeyCode::Char(' '), .. } => self.toggle_selected(),
            
            // 回车或 Esc 保存并退出
            KeyEvent { code: KeyCode::Enter, .. }
            | KeyEvent { code: KeyCode::Esc, .. } => self.on_ctrl_c(),
            _ => {}
        }
    }

    fn on_ctrl_c(&mut self) -> CancellationEvent {
        // 保存更新到配置
        if !self.features.is_empty() {
            let updates = self
                .features
                .iter()
                .map(|item| (item.feature, item.enabled))
                .collect();
            self.app_event_tx
                .send(AppEvent::UpdateFeatureFlags { updates });
        }
        self.complete = true;
        CancellationEvent::Handled
    }
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试用例实现 |
| `codex-rs/tui_app_server/src/bottom_pane/experimental_features_view.rs` | 实验性功能视图实现 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | 底部面板管理 |
| `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs` | 通用选择弹出框渲染辅助 |
| `codex-rs/tui_app_server/src/app_event.rs` | AppEvent 定义（UpdateFeatureFlags） |

### Feature 枚举定义

```rust
// codex-rs/core/src/features.rs
codex_core::features::Feature {
    GhostCommit,    // Ghost snapshots
    ShellTool,      // Shell tool
    // ... 其他功能
}
```

### 代码调用链

```
测试函数
    ↓
ExperimentalFeaturesView::new(features, app_event_tx)
    ↓
BottomPane::show_view(Box::new(view))
    ↓
render_bottom_popup(&chat, 80)
    ↓
ChatWidget::render → BottomPane::render
    ↓
ExperimentalFeaturesView::render
    ↓
生成 snapshot 字符串
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui::layout::*` | 布局管理（Layout, Constraint, Rect） |
| `ratatui::widgets::*` | UI 组件（Block, Widget） |
| `ratatui::style::Stylize` | 样式辅助方法（bold, dim 等） |
| `crossterm::event::*` | 键盘事件处理 |
| `codex_core::features::Feature` | 功能标志枚举 |

### 模块交互

```
┌─────────────────────────────────────────────────────────────────────┐
│                        测试层                                        │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ experimental_features_popup_snapshot()                     │   │
│  │  - 构造 ExperimentalFeatureItem 列表                        │   │
│  │  - 创建 ExperimentalFeaturesView                            │   │
│  │  - 调用 render_bottom_popup()                               │   │
│  └────────────────────────┬────────────────────────────────────┘   │
└───────────────────────────┼─────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ExperimentalFeaturesView                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  状态管理        │    │  键盘事件处理    │    │  渲染输出        │ │
│  │  (ScrollState)  │    │  (toggle/move)  │    │  (render_rows)  │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
┌─────────────────────┐           ┌─────────────────────┐
│   AppEvent 通道      │           │   渲染缓冲区         │
│  UpdateFeatureFlags  │           │  (snapshot 捕获)    │
└─────────────────────┘           └─────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **功能标志同步**：视图中的功能状态与实际配置可能不同步
2. **配置持久化失败**：保存到 `config.toml` 可能失败，但用户无感知
3. **长描述溢出**：功能描述过长时可能换行不美观

### 边界情况

| 场景 | 当前行为 | 改进建议 |
|-----|---------|---------|
| 空功能列表 | 显示 "No experimental features available" | ✅ 已处理 |
| 功能描述超长 | 依赖通用渲染逻辑 | 考虑截断或滚动 |
| 大量功能项 | 使用 MAX_POPUP_ROWS 限制 | 考虑分页或搜索 |
| 配置保存失败 | 静默失败 | 添加错误提示 |

### 改进建议

1. **用户体验优化**：
   - 添加功能项的悬停提示，显示更详细的说明
   - 支持搜索/过滤功能列表
   - 添加功能的风险等级标识（实验性/稳定/已弃用）

2. **配置管理增强**：
   ```rust
   // 建议添加配置验证
   fn validate_feature_toggle(&self, feature: Feature) -> Result<(), FeatureError> {
       // 检查功能依赖关系
       // 检查系统兼容性
   }
   ```

3. **测试覆盖扩展**：
   ```rust
   // 建议添加的测试
   #[tokio::test]
   async fn experimental_features_toggle_saves_config() {
       // 验证切换后配置正确保存
   }
   
   #[tokio::test]
   async fn experimental_features_empty_list() {
       // 测试空功能列表的显示
   }
   
   #[tokio::test]
   async fn experimental_features_many_items() {
       // 测试大量功能项的滚动行为
   }
   ```

4. **代码重构建议**：
   - 将功能元数据（名称、描述）提取到配置文件
   - 使用宏简化 FeatureItem 构造
   - 添加功能分类/分组支持

5. **国际化**：
   - 功能名称和描述支持多语言
   - 键盘快捷键提示本地化

### 相关测试

- `experimental_features_popup_snapshot`：本测试，验证渲染
- `experimental_features_toggle_saves_on_exit`：验证切换和保存逻辑
- `experimental_features_empty_list`（建议添加）：空列表场景
