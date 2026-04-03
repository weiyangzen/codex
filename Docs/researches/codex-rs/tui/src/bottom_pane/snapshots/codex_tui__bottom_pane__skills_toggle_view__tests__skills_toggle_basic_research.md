# Skills Toggle View - Basic Snapshot Research Document

## 场景与职责

`SkillsToggleView` 是一个用于启用/禁用技能的交互式弹窗视图。它允许用户通过搜索、选择和切换来管理可用的技能（Skills），这些技能是 Codex 的扩展功能模块，可以增强 AI 的特定领域能力。

### 核心职责
- 提供技能列表的搜索和过滤功能
- 允许用户启用或禁用特定技能
- 自动保存用户的技能配置更改
- 提供直观的键盘导航和交互体验

## 功能点目的

### 1. 技能搜索与过滤
- **目的**：当技能列表较长时，用户可以通过输入关键词快速定位目标技能
- **实现**：使用 `match_skill` 函数进行模糊匹配，支持按名称和技能标识符搜索
- **排序**：匹配结果按相关性分数排序，分数相同则按名称字母顺序排列

### 2. 技能状态切换
- **目的**：允许用户动态启用或禁用技能
- **交互**：使用空格键或回车键切换选中技能的状态
- **视觉反馈**：`[x]` 表示已启用，`[ ]` 表示未启用

### 3. 选择状态保持
- **目的**：在过滤操作后保持用户的当前选择位置
- **实现**：通过 `previously_selected` 跟踪实际索引，在过滤后重新定位到对应项

## 具体技术实现

### 数据结构
```rust
pub(crate) struct SkillsToggleView {
    items: Vec<SkillsToggleItem>,           // 所有技能项
    state: ScrollState,                     // 滚动和选择状态
    complete: bool,                         // 视图是否完成
    app_event_tx: AppEventSender,           // 应用事件发送器
    header: Box<dyn Renderable>,            // 头部渲染组件
    footer_hint: Line<'static>,             // 底部提示
    search_query: String,                   // 搜索查询
    filtered_indices: Vec<usize>,           // 过滤后的索引列表
}

pub(crate) struct SkillsToggleItem {
    pub name: String,                       // 显示名称
    pub skill_name: String,                 // 技能标识符
    pub description: String,                // 技能描述
    pub enabled: bool,                      // 是否启用
    pub path: PathBuf,                      // 技能文件路径
}
```

### 关键方法

#### `apply_filter()`
- 根据 `search_query` 过滤技能列表
- 使用 `match_skill` 进行模糊匹配并计算相关性分数
- 保持当前选择状态在过滤后的列表中的位置

#### `build_rows()`
- 将过滤后的技能项转换为可渲染的行
- 根据选择状态和启用状态添加前缀标记（`›` 表示选中，`[x]`/`[ ]` 表示启用状态）
- 使用 `truncate_skill_name` 截断过长的技能名称

#### `toggle_selected()`
- 切换当前选中技能的启用状态
- 发送 `AppEvent::SetSkillEnabled` 事件通知后端

#### `close()`
- 关闭视图并发送 `AppEvent::ManageSkillsClosed`
- 刷新技能列表以确保状态同步

### 渲染布局
```
┌─────────────────────────────────────────────┐
│  Enable/Disable Skills                      │  <- 标题（粗体）
│  Turn skills on or off. Your changes...     │  <- 描述（暗淡）
│                                             │
│  Type to search skills                      │  <- 搜索占位符
│  >                                          │  <- 搜索输入提示
│ › [x] Repo Scout        Summarize...        │  <- 技能行（选中）
│   [ ] Changelog Writer  Draft release...    │  <- 技能行（未选中）
│                                             │
│  Press space or enter to toggle; esc...     │  <- 底部提示
└─────────────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 主要文件
- `codex-rs/tui/src/bottom_pane/skills_toggle_view.rs` - 主要实现文件

### 依赖模块
- `crate::skills_helpers::match_skill` - 技能名称模糊匹配
- `crate::skills_helpers::truncate_skill_name` - 技能名称截断
- `crate::bottom_pane::selection_popup_common::render_rows_single_line` - 单行渲染
- `crate::bottom_pane::popup_consts::MAX_POPUP_ROWS` - 最大弹窗行数限制

### 关键代码段

#### 过滤逻辑（lines 86-129）
```rust
fn apply_filter(&mut self) {
    // 保存当前选择
    let previously_selected = self.state.selected_idx
        .and_then(|visible_idx| self.filtered_indices.get(visible_idx).copied());
    
    // 执行过滤和排序
    let mut matches: Vec<(usize, i32)> = Vec::new();
    for (idx, item) in self.items.iter().enumerate() {
        if let Some((_indices, score)) = match_skill(filter, display_name, &item.skill_name) {
            matches.push((idx, score));
        }
    }
    matches.sort_by(|a, b| a.1.cmp(&b.1).then_with(|| ...));
    
    // 恢复选择位置
    self.state.selected_idx = previously_selected
        .and_then(|actual_idx| self.filtered_indices.iter().position(|idx| *idx == actual_idx))
        .or_else(|| (len > 0).then_some(0));
}
```

#### 键盘事件处理（lines 205-278）
```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    match key_event {
        KeyEvent { code: KeyCode::Up, .. } => self.move_up(),
        KeyEvent { code: KeyCode::Down, .. } => self.move_down(),
        KeyEvent { code: KeyCode::Backspace, .. } => { self.search_query.pop(); }
        KeyEvent { code: KeyCode::Char(' '), .. } => self.toggle_selected(),
        KeyEvent { code: KeyCode::Esc, .. } => { self.on_ctrl_c(); }
        // ... 其他按键
    }
}
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `ratatui` | TUI 渲染框架 |
| `crossterm` | 跨平台终端事件处理 |
| `codex_protocol` | 协议定义（Op::ListSkills） |

### 应用事件交互
| 事件 | 方向 | 说明 |
|------|------|------|
| `AppEvent::SetSkillEnabled` | 发送 | 通知后端技能启用状态变更 |
| `AppEvent::ManageSkillsClosed` | 发送 | 通知技能管理视图已关闭 |
| `AppEvent::CodexOp(Op::ListSkills)` | 发送 | 请求刷新技能列表 |

### 样式依赖
- `user_message_style()` - 用户消息区域样式
- `key_hint::plain()` - 按键提示样式

## 风险边界与改进建议

### 潜在风险

1. **搜索性能问题**
   - **风险**：当技能数量极大时，每次按键都进行完整过滤可能导致性能问题
   - **边界**：当前实现是同步过滤，没有防抖或异步处理
   - **建议**：考虑添加防抖机制或虚拟滚动处理大量技能

2. **状态同步延迟**
   - **风险**：`SetSkillEnabled` 事件发送后，如果后端处理失败，UI 状态与实际状态可能不一致
   - **边界**：当前实现假设事件发送后状态变更成功
   - **建议**：添加状态确认机制或错误回滚逻辑

3. **键盘冲突**
   - **风险**：Ctrl+P/Ctrl+N 用于导航，可能与终端快捷键冲突
   - **边界**：某些终端可能拦截这些组合键
   - **建议**：提供替代导航方式或文档说明

### 改进建议

1. **搜索增强**
   - 添加搜索历史记录
   - 支持正则表达式或高级搜索语法
   - 添加搜索高亮显示

2. **批量操作**
   - 支持多选批量启用/禁用
   - 添加"全选"/"取消全选"功能

3. **可访问性**
   - 添加颜色以外的视觉指示器（如符号）
   - 支持屏幕阅读器友好的标签

4. **测试覆盖**
   - 当前只有一个基本快照测试
   - 建议添加：
     - 搜索过滤测试
     - 键盘导航测试
     - 状态切换测试
     - 边界条件测试（空列表、超长名称等）
