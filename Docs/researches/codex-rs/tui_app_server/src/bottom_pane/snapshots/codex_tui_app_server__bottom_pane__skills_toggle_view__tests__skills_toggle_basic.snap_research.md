# Skills Toggle View Basic 研究文档

## 场景与职责

该 Snapshot 展示了 **Skills Toggle View** 组件的基本 UI 表现，用于让用户启用或禁用 Codex 的技能（Skills）。技能是可插拔的功能模块，用户可以根据需要动态开启或关闭特定功能。

**核心职责：**
- 展示可用技能列表及其当前状态（启用/禁用）
- 提供搜索功能快速定位技能
- 支持单个技能的启用/禁用切换
- 自动保存用户的更改

**典型应用场景：**
- 用户首次配置 Codex 时选择需要的技能
- 根据当前任务临时启用特定技能
- 管理已安装的技能插件

---

## 功能点目的

### 1. 技能列表展示
- **Repo Scout**：已启用（`[x]`），描述为 "Summarize the repo layout"
- **Changelog Writer**：未启用（`[ ]`），描述为 "Draft release notes"

### 2. 搜索功能
- 搜索框提示：`Type to search skills`
- 输入前缀：`>`
- 支持模糊匹配（fuzzy matching）

### 3. 状态切换
- 空格键或回车键切换选中技能的状态
- `[x]` 表示启用，`[ ]` 表示禁用

### 4. 操作提示
- `Press space or enter to toggle; esc to close`

---

## 具体技术实现

### 核心数据结构

```rust
// 技能切换项
pub(crate) struct SkillsToggleItem {
    pub name: String,           // 显示名称（如 "Repo Scout"）
    pub skill_name: String,     // 技能标识名（如 "repo_scout"）
    pub description: String,    // 技能描述
    pub enabled: bool,          // 当前是否启用
    pub path: PathBuf,          // 技能配置文件路径
}

// 技能切换视图
pub(crate) struct SkillsToggleView {
    items: Vec<SkillsToggleItem>,
    state: ScrollState,         // 滚动和选择状态
    complete: bool,             // 是否完成（关闭）
    app_event_tx: AppEventSender,
    header: Box<dyn Renderable>,
    footer_hint: Line<'static>,
    search_query: String,       // 搜索查询
    filtered_indices: Vec<usize>, // 过滤后的索引列表
}
```

### 模糊搜索实现

```rust
fn apply_filter(&mut self) {
    // 保留当前选择
    let previously_selected = self
        .state
        .selected_idx
        .and_then(|visible_idx| self.filtered_indices.get(visible_idx).copied());

    let filter = self.search_query.trim();
    if filter.is_empty() {
        // 无过滤条件，显示全部
        self.filtered_indices = (0..self.items.len()).collect();
    } else {
        // 模糊匹配
        let mut matches: Vec<(usize, i32)> = Vec::new();
        for (idx, item) in self.items.iter().enumerate() {
            let display_name = item.name.as_str();
            // 使用 skills_helpers::match_skill 进行模糊匹配
            if let Some((_indices, score)) = match_skill(filter, display_name, &item.skill_name) {
                matches.push((idx, score));
            }
        }

        // 按匹配分数排序，分数相同则按名称排序
        matches.sort_by(|a, b| {
            a.1.cmp(&b.1).then_with(|| {
                let an = self.items[a.0].name.as_str();
                let bn = self.items[b.0].name.as_str();
                an.cmp(bn)
            })
        });

        self.filtered_indices = matches.into_iter().map(|(idx, _score)| idx).collect();
    }

    // 恢复选择或重置
    let len = self.filtered_indices.len();
    self.state.selected_idx = previously_selected
        .and_then(|actual_idx| {
            self.filtered_indices
                .iter()
                .position(|idx| *idx == actual_idx)
        })
        .or_else(|| (len > 0).then_some(0));

    // 确保选择项可见
    let visible = Self::max_visible_rows(len);
    self.state.clamp_selection(len);
    self.state.ensure_visible(len, visible);
}
```

### 技能切换逻辑

```rust
fn toggle_selected(&mut self) {
    let Some(idx) = self.state.selected_idx else {
        return;
    };
    let Some(actual_idx) = self.filtered_indices.get(idx).copied() else {
        return;
    };
    let Some(item) = self.items.get_mut(actual_idx) else {
        return;
    };

    // 切换状态
    item.enabled = !item.enabled;
    
    // 发送事件通知后端
    self.app_event_tx.send(AppEvent::SetSkillEnabled {
        path: item.path.clone(),
        enabled: item.enabled,
    });
}
```

### 行构建与渲染

```rust
fn build_rows(&self) -> Vec<GenericDisplayRow> {
    self.filtered_indices
        .iter()
        .enumerate()
        .filter_map(|(visible_idx, actual_idx)| {
            self.items.get(*actual_idx).map(|item| {
                let is_selected = self.state.selected_idx == Some(visible_idx);
                let prefix = if is_selected { '›' } else { ' ' };
                let marker = if item.enabled { 'x' } else { ' ' };
                let item_name = truncate_skill_name(&item.name);
                let name = format!("{prefix} [{marker}] {item_name}");
                GenericDisplayRow {
                    name,
                    description: Some(item.description.clone()),
                    ..Default::default()
                }
            })
        })
        .collect()
}
```

### 键盘事件处理

```rust
fn handle_key_event(&mut self, key_event: KeyEvent) {
    match key_event {
        // 上下导航
        KeyEvent { code: KeyCode::Up, .. }
        | KeyEvent { code: KeyCode::Char('p'), modifiers: KeyModifiers::CONTROL, .. }
        | KeyEvent { code: KeyCode::Char('\u{0010}'), .. } /* ^P */ => self.move_up(),
        
        KeyEvent { code: KeyCode::Down, .. }
        | KeyEvent { code: KeyCode::Char('n'), modifiers: KeyModifiers::CONTROL, .. }
        | KeyEvent { code: KeyCode::Char('\u{000e}'), .. } /* ^N */ => self.move_down(),
        
        // 退格删除搜索字符
        KeyEvent { code: KeyCode::Backspace, .. } => {
            self.search_query.pop();
            self.apply_filter();
        }
        
        // 空格或回车切换状态
        KeyEvent { code: KeyCode::Char(' '), .. }
        | KeyEvent { code: KeyCode::Enter, .. } => self.toggle_selected(),
        
        // ESC 关闭
        KeyEvent { code: KeyCode::Esc, .. } => self.on_ctrl_c(),
        
        // 普通字符添加到搜索
        KeyEvent { code: KeyCode::Char(c), modifiers, .. }
            if !modifiers.contains(KeyModifiers::CONTROL)
                && !modifiers.contains(KeyModifiers::ALT) =>
        {
            self.search_query.push(c);
            self.apply_filter();
        }
        _ => {}
    }
}
```

---

## 关键代码路径与文件引用

### 主要实现文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/skills_toggle_view.rs` | Skills Toggle View 核心实现 |
| `codex-rs/tui_app_server/src/skills_helpers.rs` | 技能名称截断和模糊匹配工具 |

### 辅助函数

```rust
// skills_helpers.rs
pub fn match_skill(filter: &str, display_name: &str, skill_name: &str) -> Option<(Vec<usize>, i32)>
// 模糊匹配技能名称

pub fn truncate_skill_name(name: &str) -> &str
// 截断过长的技能名称
```

### 事件定义

```rust
// AppEvent
pub enum AppEvent {
    SetSkillEnabled {
        path: PathBuf,
        enabled: bool,
    },
    ManageSkillsClosed,
    // ...
}
```

### 测试代码

```rust
#[test]
fn renders_basic_popup() {
    let items = vec![
        SkillsToggleItem {
            name: "Repo Scout".to_string(),
            skill_name: "repo_scout".to_string(),
            description: "Summarize the repo layout".to_string(),
            enabled: true,
            path: PathBuf::from("/tmp/skills/repo_scout.toml"),
        },
        SkillsToggleItem {
            name: "Changelog Writer".to_string(),
            skill_name: "changelog_writer".to_string(),
            description: "Draft release notes".to_string(),
            enabled: false,
            path: PathBuf::from("/tmp/skills/changelog_writer.toml"),
        },
    ];
    let view = SkillsToggleView::new(items, tx);
    assert_snapshot!("skills_toggle_basic", render_lines(&view, 72));
}
```

---

## 依赖与外部交互

### 内部模块依赖

| 模块 | 用途 |
|-----|------|
| `crate::skills_helpers` | 技能名称处理和模糊匹配 |
| `crate::app_event::AppEvent` | 技能状态变更事件 |
| `crate::bottom_pane::scroll_state::ScrollState` | 滚动状态管理 |
| `crate::bottom_pane::selection_popup_common` | 通用选择弹窗组件 |

### 事件系统交互

```rust
// 切换技能状态时发送
self.app_event_tx.send(AppEvent::SetSkillEnabled {
    path: item.path.clone(),  // 技能配置文件路径
    enabled: item.enabled,     // 新的启用状态
});

// 关闭时发送
self.app_event_tx.send(AppEvent::ManageSkillsClosed);
self.app_event_tx.list_skills(Vec::new(), /*force_reload*/ true);
```

### 与配置系统的关系

- 技能状态保存在技能配置文件（如 `repo_scout.toml`）中
- TUI 通过 `SetSkillEnabled` 事件通知后端更新配置
- 更改立即生效，无需重启

---

## 风险、边界与改进建议

### 当前限制

1. **无批量操作**
   - 只能逐个切换技能状态
   - 技能较多时操作繁琐

2. **搜索结果显示**
   - 搜索时仅显示匹配项，可能让用户误以为其他技能被删除

3. **无技能分组**
   - 所有技能平铺显示，难以管理大量技能

4. **缺少技能详情**
   - 仅显示描述，无更详细的说明或使用示例

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 搜索无结果 | 显示 "no matches" |
| 技能名称过长 | 使用 `truncate_skill_name` 截断 |
| 技能列表为空 | 显示空列表（理论上不应发生）|
| 快速连续切换 | 每个切换都发送独立事件 |
| 配置文件被外部修改 | 关闭时强制重新加载 (`force_reload: true`) |

### 改进建议

1. **批量操作**
   ```rust
   // 建议：添加 "Enable All" / "Disable All" 选项
   KeyEvent { code: KeyCode::Char('a'), modifiers: KeyModifiers::CONTROL, .. } => {
       self.enable_all_visible();
   }
   ```

2. **技能分组**
   ```rust
   // 建议：按类别分组显示
   pub(crate) struct SkillsToggleItem {
       // ...
       pub category: String,  // "Development", "Documentation", etc.
   }
   ```

3. **技能详情展开**
   ```rust
   // 建议：按 'i' 键查看技能详情
   KeyEvent { code: KeyCode::Char('i'), .. } => self.show_skill_info(),
   ```

4. **最近使用排序**
   - 将最近启用/禁用的技能置顶
   - 便于用户快速找到常用技能

5. **视觉增强**
   ```rust
   // 建议：启用和禁用使用不同颜色
   let marker = if item.enabled { 'x'.green() } else { ' '.dim() };
   ```

6. **快捷键优化**
   - 数字键快速跳转到对应技能
   - `/` 键快速聚焦搜索框

7. **撤销功能**
   - 添加 `u` 键撤销最近的操作
   - 或显示 "Undo" 提示条
