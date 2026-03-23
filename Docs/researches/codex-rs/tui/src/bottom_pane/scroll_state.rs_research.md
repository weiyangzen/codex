# scroll_state.rs 深度研究文档

## 场景与职责

`ScrollState` 是 Codex TUI 中用于**垂直列表菜单的通用滚动/选择状态**管理模块。该模块封装了可选择列表的常见行为，为各种弹出窗口（如命令选择、技能选择、文件搜索等）提供统一的导航和滚动逻辑。

主要场景：
1. **命令弹出窗口**：`/` 触发的斜杠命令列表
2. **技能弹出窗口**：`$` 触发的 mention 列表
3. **文件搜索弹出窗口**：文件选择列表
4. **模型选择**：`/model` 命令的模型列表
5. **任何需要滚动选择的 UI 组件**

## 功能点目的

### 1. 可选选择支持
- **功能**：`selected_idx: Option<usize>`
- **目的**：支持空列表状态（`None`），避免空列表时的无效选择

### 2. 循环导航
- **功能**：`move_up_wrap` 和 `move_down_wrap`
- **行为**：在列表顶部按上键跳到底部，反之亦然
- **目的**：提供流畅的键盘导航体验

### 3. 滚动窗口管理
- **功能**：`scroll_top` 和 `ensure_visible`
- **目的**：确保选中项始终可见，自动滚动视口

### 4. 选择边界限制
- **功能**：`clamp_selection`
- **目的**：当列表长度变化时，将选择限制在有效范围内

## 具体技术实现

### 核心数据结构

```rust
/// Generic scroll/selection state for a vertical list menu.
///
/// Encapsulates the common behavior of a selectable list that supports:
/// - Optional selection (None when list is empty)
/// - Wrap-around navigation on Up/Down
/// - Maintaining a scroll window (`scroll_top`) so the selected row stays visible
#[derive(Debug, Default, Clone, Copy)]
pub(crate) struct ScrollState {
    pub selected_idx: Option<usize>,  // 当前选中索引，None 表示空列表
    pub scroll_top: usize,             // 视口顶部索引
}
```

### 构造函数

```rust
impl ScrollState {
    pub fn new() -> Self {
        Self {
            selected_idx: None,
            scroll_top: 0,
        }
    }

    /// Reset selection and scroll.
    pub fn reset(&mut self) {
        self.selected_idx = None;
        self.scroll_top = 0;
    }
}
```

### 选择边界限制

```rust
/// Clamp selection to be within the [0, len-1] range, or None when empty.
pub fn clamp_selection(&mut self, len: usize) {
    self.selected_idx = match len {
        0 => None,
        _ => Some(self.selected_idx.unwrap_or(0).min(len - 1)),
    };
    if len == 0 {
        self.scroll_top = 0;
    }
}
```

**逻辑说明**：
- 空列表（`len == 0`）：选择设为 `None`
- 非空列表：如果当前无选择，默认选择第 0 项；否则限制在 `len - 1` 范围内

### 循环导航 - 向上

```rust
/// Move selection up by one, wrapping to the bottom when necessary.
pub fn move_up_wrap(&mut self, len: usize) {
    if len == 0 {
        self.selected_idx = None;
        self.scroll_top = 0;
        return;
    }
    self.selected_idx = Some(match self.selected_idx {
        Some(idx) if idx > 0 => idx - 1,  // 正常上移
        Some(_) => len - 1,                // 在顶部，循环到底部
        None => 0,                         // 从无选择开始，选择底部
    });
}
```

### 循环导航 - 向下

```rust
/// Move selection down by one, wrapping to the top when necessary.
pub fn move_down_wrap(&mut self, len: usize) {
    if len == 0 {
        self.selected_idx = None;
        self.scroll_top = 0;
        return;
    }
    self.selected_idx = Some(match self.selected_idx {
        Some(idx) if idx + 1 < len => idx + 1,  // 正常下移
        _ => 0,                                  // 在底部或无从选择，循环到顶部
    });
}
```

### 可见性确保

```rust
/// Adjust `scroll_top` so that the current `selected_idx` is visible within
/// the window of `visible_rows`.
pub fn ensure_visible(&mut self, len: usize, visible_rows: usize) {
    if len == 0 || visible_rows == 0 {
        self.scroll_top = 0;
        return;
    }
    
    if let Some(sel) = self.selected_idx {
        if sel < self.scroll_top {
            // 选中项在视口上方，向上滚动
            self.scroll_top = sel;
        } else {
            // 检查是否在视口下方
            let bottom = self.scroll_top + visible_rows - 1;
            if sel > bottom {
                // 选中项在视口下方，向下滚动
                self.scroll_top = sel + 1 - visible_rows;
            }
        }
    } else {
        self.scroll_top = 0;
    }
}
```

## 关键代码路径与文件引用

### 主要使用者

| 使用者 | 文件路径 | 使用场景 |
|--------|----------|----------|
| `CommandPopup` | `codex-rs/tui/src/bottom_pane/command_popup.rs` | 斜杠命令列表 |
| `SkillPopup` | `codex-rs/tui/src/bottom_pane/skill_popup.rs` | 技能 mention 列表 |
| `FileSearchPopup` | `codex-rs/tui/src/bottom_pane/file_search_popup.rs` | 文件搜索结果 |
| `ListSelectionView` | `codex-rs/tui/src/bottom_pane/list_selection_view.rs` | 通用选择列表 |
| `MultiSelectPicker` | `codex-rs/tui/src/bottom_pane/multi_select_picker.rs` | 多选列表 |
| `McpServerElicitationOverlay` | `codex-rs/tui/src/bottom_pane/mcp_server_elicitation.rs` | MCP 服务器表单 |
| `ExperimentalFeaturesView` | `codex-rs/tui/src/bottom_pane/experimental_features_view.rs` | 实验性功能开关 |
| `SkillsToggleView` | `codex-rs/tui/src/bottom_pane/skills_toggle_view.rs` | 技能开关列表 |
| `AppLinkView` | `codex-rs/tui/src/bottom_pane/app_link_view.rs` | 应用链接视图 |
| `RequestUserInputOverlay` | `codex-rs/tui/src/bottom_pane/request_user_input/mod.rs` | 用户输入请求 |

### 集成代码示例

**`command_popup.rs` 中的使用：**
```rust
use super::scroll_state::ScrollState;

pub(crate) struct CommandPopup {
    command_filter: String,
    builtins: Vec<(&'static str, SlashCommand)>,
    prompts: Vec<CustomPrompt>,
    state: ScrollState,  // 滚动状态
}

impl CommandPopup {
    pub(crate) fn new(mut prompts: Vec<CustomPrompt>, flags: CommandPopupFlags) -> Self {
        // ...
        Self {
            command_filter: String::new(),
            builtins,
            prompts,
            state: ScrollState::new(),  // 初始化
        }
    }

    fn clamp_selection(&mut self) {
        let matches_len = self.filtered_items().len();
        self.state.clamp_selection(matches_len);  // 限制选择范围
        self.state.ensure_visible(matches_len, MAX_POPUP_ROWS.min(matches_len));
    }

    pub(crate) fn move_up(&mut self) {
        let len = self.filtered_items().len();
        self.state.move_up_wrap(len);  // 循环上移
        self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
    }

    pub(crate) fn move_down(&mut self) {
        let len = self.filtered_items().len();
        self.state.move_down_wrap(len);  // 循环下移
        self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
    }
}
```

**`skill_popup.rs` 中的使用：**
```rust
pub(crate) struct SkillPopup {
    query: String,
    mentions: Vec<MentionItem>,
    state: ScrollState,
}

impl SkillPopup {
    pub(crate) fn move_up(&mut self) {
        let len = self.filtered_items().len();
        self.state.move_up_wrap(len);
        self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
    }

    pub(crate) fn move_down(&mut self) {
        let len = self.filtered_items().len();
        self.state.move_down_wrap(len);
        self.state.ensure_visible(len, MAX_POPUP_ROWS.min(len));
    }

    pub(crate) fn selected_mention(&self) -> Option<&MentionItem> {
        let matches = self.filtered_items();
        let idx = self.state.selected_idx?;  // 使用 Option 传播
        let mention_idx = matches.get(idx)?;
        self.mentions.get(*mention_idx)
    }
}
```

### 模块导出

在 `bottom_pane/mod.rs` 中：

```rust
mod scroll_state;
// 内部使用，不公开导出
```

## 依赖与外部交互

### 依赖模块

| 模块 | 关系 | 说明 |
|------|------|------|
| `std` | 核心依赖 | 仅使用标准库类型（`Option`, `usize`） |
| 无其他依赖 | - | 完全自包含的模块 |

### 设计特点

1. **纯逻辑**：不涉及任何 UI 渲染，仅管理状态
2. **零依赖**：仅使用 Rust 标准库
3. **Copy 语义**：实现 `Clone, Copy`，便于值传递
4. **Default 派生**：支持 `ScrollState::default()`

## 风险、边界与改进建议

### 已知风险

1. **可见行数计算**
   - `ensure_visible` 依赖调用方提供正确的 `visible_rows`
   - 如果计算错误（如未考虑包装行），选中项可能实际不可见

2. **列表长度变化**
   - 过滤列表时长度可能突然变化
   - 必须在过滤后调用 `clamp_selection`，否则可能指向无效索引

3. **大列表性能**
   - 当前实现使用 `usize` 索引，理论上支持极大列表
   - 但实际 UI 渲染可能成为瓶颈

### 边界条件

| 场景 | 行为 |
|------|------|
| 空列表（len=0） | `selected_idx` 设为 `None`，`scroll_top` 设为 0 |
| 无从选择开始上移 | 选择最后一项（循环） |
| 无从选择开始下移 | 选择第一项 |
| 选择超出新长度 | `clamp_selection` 限制到最后一项 |
| visible_rows=0 | `scroll_top` 设为 0 |
| 选中项已在视口内 | `scroll_top` 不变 |

### 测试覆盖

```rust
#[cfg(test)]
mod tests {
    use super::ScrollState;

    #[test]
    fn wrap_navigation_and_visibility() {
        let mut s = ScrollState::new();
        let len = 10;
        let vis = 5;

        // 初始状态：无选择
        s.clamp_selection(len);
        assert_eq!(s.selected_idx, Some(0));  // 默认选择第一项
        s.ensure_visible(len, vis);
        assert_eq!(s.scroll_top, 0);

        // 上移循环
        s.move_up_wrap(len);
        s.ensure_visible(len, vis);
        assert_eq!(s.selected_idx, Some(len - 1));  // 跳到最后

        // 下移循环
        s.move_down_wrap(len);
        s.ensure_visible(len, vis);
        assert_eq!(s.selected_idx, Some(0));  // 回到第一项
        assert_eq!(s.scroll_top, 0);
    }
}
```

### 改进建议

1. **动画支持**
   - 添加平滑滚动动画选项
   - 使用 `scroll_top` 插值实现视觉平滑过渡

2. **多选支持**
   - 当前仅支持单选
   - 可扩展为 `selected_indices: Vec<usize>` 支持多选

3. **键盘快捷键扩展**
   - 支持 PageUp/PageDown 快速滚动
   - 支持 Home/End 跳到首尾

4. **搜索集成**
   - 添加 `search_match_indices` 字段
   - 支持在搜索结果间快速跳转

5. **持久化**
   - 支持保存/恢复滚动位置
   - 在弹出窗口重新打开时恢复上次选择

6. **可见性优化**
   - 当前 `ensure_visible` 使用最小滚动策略
   - 可添加选项使用居中策略（将选中项置于视口中央）

7. **虚拟列表支持**
   - 对于极大列表，添加虚拟滚动支持
   - 仅渲染可见区域内的项目

### 相关文件

- `codex-rs/tui/src/bottom_pane/command_popup.rs`：命令弹出窗口
- `codex-rs/tui/src/bottom_pane/skill_popup.rs`：技能弹出窗口
- `codex-rs/tui/src/bottom_pane/file_search_popup.rs`：文件搜索
- `codex-rs/tui/src/bottom_pane/list_selection_view.rs`：通用选择视图
- `codex-rs/tui/src/bottom_pane/selection_popup_common.rs`：选择弹出窗口通用渲染
