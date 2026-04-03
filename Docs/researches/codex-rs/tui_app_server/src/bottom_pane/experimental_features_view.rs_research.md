# experimental_features_view.rs 研究文档

## 场景与职责

`experimental_features_view.rs` 是 Codex TUI 应用中用于管理和切换实验性功能（Experimental Features）的交互式弹窗组件。它提供一个带复选框的列表界面，允许用户：

1. **查看可用功能**：列出所有实验性功能及其当前状态
2. **启用/禁用功能**：通过空格键切换功能开关
3. **持久化配置**：退出时自动保存更改到 `config.toml`

该模块实现了 `BottomPaneView` trait，作为模态视图嵌入底部面板的视图栈。

## 功能点目的

### 1. 功能项表示（ExperimentalFeatureItem）
- **目的**：封装单个实验性功能的展示和状态
- **字段**：
  - `feature`: 功能标识（`Feature` 枚举）
  - `name`: 显示名称
  - `description`: 功能描述
  - `enabled`: 当前是否启用

### 2. 功能列表视图（ExperimentalFeaturesView）
- **目的**：管理功能列表的展示和交互
- **核心组件**：
  - `features`: 功能项列表
  - `state`: 滚动和选择状态（`ScrollState`）
  - `app_event_tx`: 应用事件发送器（用于保存更改）
  - `header`: 可渲染的标题区域
  - `footer_hint`: 底部操作提示

### 3. 键盘导航
- **目的**：提供熟悉的列表导航体验
- **支持操作**：
  - `Up` / `Ctrl+P` / `k`: 向上移动选择
  - `Down` / `Ctrl+N` / `j`: 向下移动选择
  - `Space`: 切换选中功能的开关状态
  - `Enter` / `Esc`: 保存更改并退出

### 4. 配置持久化
- **目的**：确保用户的选择在会话间保持
- **机制**：退出时发送 `UpdateFeatureFlags` 事件，由应用层保存到配置文件

## 具体技术实现

### 关键数据结构

```rust
pub(crate) struct ExperimentalFeatureItem {
    pub feature: Feature,
    pub name: String,
    pub description: String,
    pub enabled: bool,
}

pub(crate) struct ExperimentalFeaturesView {
    features: Vec<ExperimentalFeatureItem>,
    state: ScrollState,
    complete: bool,
    app_event_tx: AppEventSender,
    header: Box<dyn Renderable>,
    footer_hint: Line<'static>,
}
```

### 创建流程

```rust
impl ExperimentalFeaturesView {
    pub(crate) fn new(
        features: Vec<ExperimentalFeatureItem>,
        app_event_tx: AppEventSender,
    ) -> Self {
        // 构建标题："Experimental features" + 说明文字
        let mut header = ColumnRenderable::new();
        header.push(Line::from("Experimental features".bold()));
        header.push(Line::from(
            "Toggle experimental features. Changes are saved to config.toml.".dim(),
        ));
        
        let mut view = Self { ... };
        view.initialize_selection();
        view
    }
    
    fn initialize_selection(&mut self) {
        if self.visible_len() == 0 {
            self.state.selected_idx = None;
        } else if self.state.selected_idx.is_none() {
            self.state.selected_idx = Some(0);
        }
    }
}
```

### 行构建

```rust
fn build_rows(&self) -> Vec<GenericDisplayRow> {
    let mut rows = Vec::with_capacity(self.features.len());
    let selected_idx = self.state.selected_idx;
    
    for (idx, item) in self.features.iter().enumerate() {
        // 选中项前缀 '›'，未选中 ' '
        let prefix = if selected_idx == Some(idx) { '›' } else { ' ' };
        // 启用显示 'x'，未启用 ' '
        let marker = if item.enabled { 'x' } else { ' ' };
        let name = format!("{prefix} [{marker}] {}", item.name);
        
        rows.push(GenericDisplayRow {
            name,
            description: Some(item.description.clone()),
            ..Default::default()
        });
    }
    rows
}
```

### 键盘事件处理

```rust
impl BottomPaneView for ExperimentalFeaturesView {
    fn handle_key_event(&mut self, key_event: KeyEvent) {
        match key_event {
            // 向上导航：Up, Ctrl+P, Ctrl+\x10, k
            KeyEvent { code: KeyCode::Up, .. }
            | KeyEvent { code: KeyCode::Char('p'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('\u{0010}'), modifiers: KeyModifiers::NONE, .. }
            | KeyEvent { code: KeyCode::Char('k'), modifiers: KeyModifiers::NONE, .. } 
                => self.move_up(),
            
            // 向下导航：Down, Ctrl+N, Ctrl+\x0e, j
            KeyEvent { code: KeyCode::Down, .. }
            | KeyEvent { code: KeyCode::Char('n'), modifiers: KeyModifiers::CONTROL, .. }
            | KeyEvent { code: KeyCode::Char('\u{000e}'), modifiers: KeyModifiers::NONE, .. }
            | KeyEvent { code: KeyCode::Char('j'), modifiers: KeyModifiers::NONE, .. }
                => self.move_down(),
            
            // 切换：Space
            KeyEvent { code: KeyCode::Char(' '), modifiers: KeyModifiers::NONE, .. }
                => self.toggle_selected(),
            
            // 保存并退出：Enter, Esc
            KeyEvent { code: KeyCode::Enter, modifiers: KeyModifiers::NONE, .. }
            | KeyEvent { code: KeyCode::Esc, .. }
                => { self.on_ctrl_c(); }
            
            _ => {}
        }
    }
    
    fn on_ctrl_c(&mut self) -> CancellationEvent {
        // 保存更新
        if !self.features.is_empty() {
            let updates = self.features.iter()
                .map(|item| (item.feature, item.enabled))
                .collect();
            self.app_event_tx.send(AppEvent::UpdateFeatureFlags { updates });
        }
        self.complete = true;
        CancellationEvent::Handled
    }
}
```

### 导航方法

```rust
fn move_up(&mut self) {
    let len = self.visible_len();
    if len == 0 { return; }
    self.state.move_up_wrap(len);
    self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
}

fn move_down(&mut self) {
    let len = self.visible_len();
    if len == 0 { return; }
    self.state.move_down_wrap(len);
    self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
}

fn toggle_selected(&mut self) {
    let Some(selected_idx) = self.state.selected_idx else { return; };
    if let Some(item) = self.features.get_mut(selected_idx) {
        item.enabled = !item.enabled;
    }
}
```

### 渲染实现

```rust
impl Renderable for ExperimentalFeaturesView {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        // 1. 垂直分割：内容区 + 底部提示区
        let [content_area, footer_area] = Layout::vertical([
            Constraint::Fill(1), 
            Constraint::Length(1)
        ]).areas(area);
        
        // 2. 渲染菜单背景
        Block::default().style(user_message_style()).render(content_area, buf);
        
        // 3. 计算布局：标题 + 间距 + 列表
        let rows = self.build_rows();
        let rows_height = measure_rows_height(...);
        let [header_area, _, list_area] = Layout::vertical([...]).areas(content_area.inset(...));
        
        // 4. 渲染标题
        self.header.render(header_area, buf);
        
        // 5. 渲染列表
        render_rows(list_area, buf, &rows, &self.state, MAX_POPUP_ROWS, "  No experimental features available for now");
        
        // 6. 渲染底部提示
        self.footer_hint.clone().dim().render(hint_area, buf);
    }
    
    fn desired_height(&self, width: u16) -> u16 {
        let rows = self.build_rows();
        let rows_height = measure_rows_height(&rows, &self.state, MAX_POPUP_ROWS, ...);
        let mut height = self.header.desired_height(width.saturating_sub(4));
        height = height.saturating_add(rows_height + 3);
        height.saturating_add(1)
    }
}
```

### 底部提示

```rust
fn experimental_popup_hint_line() -> Line<'static> {
    Line::from(vec![
        "Press ".into(),
        key_hint::plain(KeyCode::Char(' ')).into(),
        " to select or ".into(),
        key_hint::plain(KeyCode::Enter).into(),
        " to save for next conversation".into(),
    ])
}
```

## 关键代码路径与文件引用

### 当前文件关键路径
- `ExperimentalFeaturesView::new()` (行 49-69): 创建视图
- `initialize_selection()` (行 71-77): 初始化选择状态
- `build_rows()` (行 83-102): 构建可渲染行
- `move_up/move_down()` (行 104-120): 导航方法
- `toggle_selected()` (行 122-130): 切换功能状态
- `BottomPaneView::handle_key_event()` (行 137-193): 键盘事件处理
- `BottomPaneView::on_ctrl_c()` (行 200-214): 保存并退出
- `Renderable::render()` (行 217-274): 渲染逻辑
- `experimental_popup_hint_line()` (行 292-300): 底部提示

### 调用方
- `codex-rs/tui_app_server/src/chatwidget.rs`:
  - 在测试中被引用（`chatwidget/tests.rs`）
  - 通过 `ExperimentalFeaturesView::new` 创建实例
- `codex-rs/tui_app_server/src/bottom_pane/mod.rs`:
  - 导出 `ExperimentalFeaturesView` 和 `ExperimentalFeatureItem`

### 被调用方
- `codex-rs/tui_app_server/src/bottom_pane/scroll_state.rs`:
  - `ScrollState`: 滚动和选择状态管理
- `codex-rs/tui_app_server/src/bottom_pane/selection_popup_common.rs`:
  - `GenericDisplayRow`: 行数据格式
  - `render_rows()`: 行渲染
  - `measure_rows_height()`: 高度计算
- `codex-rs/core/src/features.rs`:
  - `Feature`: 功能标识枚举
- `codex-rs/tui_app_server/src/app_event.rs`:
  - `AppEvent::UpdateFeatureFlags`: 保存功能标志更新

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `scroll_state` | 滚动和选择状态 |
| `selection_popup_common` | 通用弹窗渲染 |
| `popup_consts` | 弹窗常量 |
| `bottom_pane_view` | 底部面板视图 trait |
| `codex_core::features::Feature` | 功能标识枚举 |
| `app_event` | 应用事件定义 |

### 与 Core Features 的交互
1. **功能定义**：`Feature` 枚举定义在 `codex_core::features` 中
2. **功能元数据**：名称和描述通常从 `FEATURES` 常量获取
3. **状态同步**：更改通过 `UpdateFeatureFlags` 事件发送到应用层

### 配置持久化流程
1. 用户切换功能开关
2. 用户按 Enter/Esc 退出
3. `on_ctrl_c` 收集所有功能的当前状态
4. 发送 `AppEvent::UpdateFeatureFlags { updates }`
5. 应用层接收事件并更新配置
6. 配置写入 `config.toml`

## 风险、边界与改进建议

### 风险点

1. **功能标志同步延迟**
   - 风险：用户切换功能后，某些功能可能需要重启才能生效，但 UI 无提示
   - 建议：为需要重启的功能添加视觉标识或提示

2. **并发修改**
   - 风险：如果功能状态在视图打开时被外部修改，退出时会覆盖
   - 现状：当前实现不检测并发修改
   - 建议：添加版本号或时间戳检测冲突

3. **空列表处理**
   - 现状：显示 "No experimental features available for now"
   - 风险：如果所有功能都变为稳定版，列表为空
   - 建议：考虑隐藏实验性功能菜单入口

### 边界情况

1. **空功能列表**：正常处理，显示空提示
2. **超长描述**：`measure_rows_height` 和 `render_rows` 处理文本换行
3. **极窄屏幕**：布局自动调整，最小宽度由 `selection_popup_common` 处理
4. **快速切换**：每次空格键立即切换状态，无防抖

### 改进建议

1. **功能分类/分组**
   - 将功能按类别分组（如 Editor、Tools、UI 等），便于浏览

2. **搜索/过滤**
   - 添加搜索框，快速定位特定功能

3. **功能详情面板**
   - 选中功能时在侧边显示详细说明和可能的副作用

4. **重启提示**
   - 标记需要重启的功能，并在用户更改时提示

5. **默认值恢复**
   - 添加 "恢复默认值" 按钮

6. **键盘快捷键增强**
   - 添加数字键（1-9）快速跳转
   - 添加 'a' 键全选/取消全选

7. **测试覆盖**
   - 当前文件无单元测试，建议添加：
     - 键盘导航测试
     - 切换功能状态测试
     - 渲染输出快照测试
     - 事件发送验证测试

8. **与 tui 目录同步**
   - 根据 `AGENTS.md` 要求，`tui` 和 `tui_app_server` 应有并行实现
   - 确保两目录中的实现保持一致
