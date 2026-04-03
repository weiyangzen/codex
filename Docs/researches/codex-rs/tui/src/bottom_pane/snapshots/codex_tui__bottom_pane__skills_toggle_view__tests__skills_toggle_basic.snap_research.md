# Skills Toggle Basic

## 1. 场景与职责 (Scene and Responsibility)

### 测试场景
Tests the basic rendering of the skills toggle view popup with two skills.

### 组件职责
该快照测试针对 Codex TUI 的 **SkillsToggleView** 组件，负责验证：
- Skill 管理弹出窗口的基本渲染
- 标题、说明、搜索框的正确显示
- Skill 列表项的格式（选择指示器、复选框、名称、描述）
- 底部按键提示的正确显示

## 2. 功能点目的 (Feature Purpose)

### 测试目标
Validates the basic UI layout and formatting of the skills toggle view.

### 验证要点
1. 标题 "Enable/Disable Skills" 正确显示
2. 说明文本 "Turn skills on or off. Your changes are saved automatically." 正确显示
3. 搜索占位符 "Type to search skills" 和提示符 ">" 正确显示
4. 两条 Skill 项正确显示：
   - "Repo Scout" (已启用: [x])，描述 "Summarize the repo layout"
   - "Changelog Writer" (未启用: [ ])，描述 "Draft release notes"
5. 选中指示器 "›" 显示在第一项
6. 底部按键提示 "Press space or enter to toggle; esc to close" 正确显示

## 3. 具体技术实现 (Technical Implementation)

### 核心数据结构
```rust
pub(crate) struct SkillsToggleItem {
    pub name: String,
    pub skill_name: String,
    pub description: String,
    pub enabled: bool,
    pub path: PathBuf,
}

pub(crate) struct SkillsToggleView {
    items: Vec<SkillsToggleItem>,
    state: ScrollState,
    complete: bool,
    app_event_tx: AppEventSender,
    header: Box<dyn Renderable>,
    footer_hint: Line<'static>,
    search_query: String,
    filtered_indices: Vec<usize>,
}
```

### 测试数据
```rust
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
```

### 渲染输出 (72x15)
```
                                                                        
  Enable/Disable Skills
  Turn skills on or off. Your changes are saved automatically.
                                                                        
  Type to search skills
  >
› [x] Repo Scout        Summarize the repo layout
  [ ] Changelog Writer  Draft release notes
                                                                        
  Press space or enter to toggle; esc to close
```

### 关键算法
1. **行构建**: `build_rows()` 将 `SkillsToggleItem` 转换为 `GenericDisplayRow`
2. **选择指示**: 选中项前缀为 "›"，未选中为 " "
3. **启用标记**: `[x]` 表示启用，`[ ]` 表示禁用
4. **名称截断**: 使用 `truncate_skill_name()` 处理过长名称

## 4. 关键代码路径与文件引用 (Key Code Paths)

### 源文件
- **主文件**: `codex-rs/tui/src/bottom_pane/skills_toggle_view.rs`

### 关键函数/方法
| 函数/方法 | 描述 |
|-----------|------|
| `new()` | 初始化视图，构建头部和页脚 |
| `build_rows()` | 构建显示行列表 |
| `render()` | 主渲染函数，布局头部、搜索框、列表、页脚 |
| `skills_toggle_hint_line()` | 生成底部按键提示 |

### 关键代码段
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

### 测试代码位置
```rust
#[test]
fn renders_basic_popup() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
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

## 5. 依赖与外部交互 (Dependencies)

### 外部 Crates
| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架，提供 Buffer、Rect、Layout、Block 等 |
| `crossterm` | 终端控制，提供 KeyCode |
| `tokio` | 异步运行时，提供 unbounded_channel |
| `insta` | 快照测试框架 |

### 内部模块依赖
| 模块 | 用途 |
|------|------|
| `crate::app_event::AppEvent` | 应用事件类型 |
| `crate::app_event_sender::AppEventSender` | 事件发送器 |
| `crate::key_hint` | 按键提示生成 |
| `crate::skills_helpers` | Skill 辅助函数（match_skill, truncate_skill_name） |
| `crate::render::renderable::Renderable` | 可渲染 trait |
| `super::scroll_state::ScrollState` | 滚动状态管理 |
| `super::selection_popup_common::GenericDisplayRow` | 通用显示行 |
| `super::popup_consts::MAX_POPUP_ROWS` | 最大弹出行数 (8) |

### 事件交互
- **输出事件**: `AppEvent::SetSkillEnabled`, `AppEvent::ManageSkillsClosed`, `Op::ListSkills`

## 6. 风险、边界与改进建议 (Risks, Edge Cases, Improvements)

### 潜在风险
1. **长名称截断**: `truncate_skill_name()` 可能截断重要信息
2. **描述长度**: 长描述在窄终端可能被截断
3. **空列表**: 无 Skill 时的显示未在此测试中覆盖

### 边界情况
| 场景 | 行为 |
|------|------|
| 无 Skill | 未测试，可能显示空列表 |
| 大量 Skill | 使用 `MAX_POPUP_ROWS` 限制显示行数 |
| 搜索无匹配 | 显示 "no matches" |
| 窄终端 | 描述可能被截断 |

### 改进建议
1. **测试覆盖**: 添加空列表、大量 Skill、搜索过滤的测试
2. **描述截断**: 添加描述长度限制或换行支持
3. **分组显示**: 按类别分组显示 Skill
4. **快捷键**: 添加全选/全不选快捷键
5. **状态反馈**: 显示保存成功/失败的状态提示

### 相关文档
- `Docs/researches/codex-rs/tui/src/bottom_pane/skills_toggle_view.rs_research.md` - 完整组件研究文档
- `codex-rs/tui/src/skills_helpers.rs` - Skill 辅助函数
- `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` - 通用选择弹出组件
