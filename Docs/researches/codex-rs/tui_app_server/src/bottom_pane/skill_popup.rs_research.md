# skill_popup.rs 深度研究文档

## 1. 场景与职责

`skill_popup.rs` 是 Codex TUI 应用中负责**技能提及（Skill Mention）自动补全弹窗**的专用组件。当用户在聊天输入框中输入 `@` 字符触发技能提及功能时，该弹窗会显示可用的技能列表，支持模糊搜索、高亮匹配和快速选择插入。

### 核心职责
- **技能列表展示**: 显示技能名称、描述、分类标签等信息
- **模糊搜索过滤**: 支持基于技能名称和搜索词的多字段模糊匹配
- **智能排序**: 按排序等级（sort_rank）、匹配分数、名称字母顺序综合排序
- **视觉高亮**: 对匹配字符进行加粗高亮显示
- **键盘导航**: 支持上下箭头键选择和 Enter 键确认插入

## 2. 功能点目的

### 2.1 MentionItem 数据结构
```rust
pub(crate) struct MentionItem {
    pub(crate) display_name: String,      // 显示名称（用户可见）
    pub(crate) description: Option<String>, // 技能描述
    pub(crate) insert_text: String,       // 插入到输入框的文本
    pub(crate) search_terms: Vec<String>, // 额外搜索词（别名、关键词等）
    pub(crate) path: Option<String>,      // 技能文件路径
    pub(crate) category_tag: Option<String>, // 分类标签（如 "built-in"）
    pub(crate) sort_rank: u8,             // 排序优先级（越小越靠前）
}
```

**设计意图**: 将技能的展示信息与插入行为分离，允许同一个技能有不同的显示名称和插入文本，同时支持多维度搜索。

### 2.2 模糊匹配策略

技能弹窗的匹配逻辑具有以下特点：

1. **多字段匹配**: 首先匹配 `display_name`，然后遍历 `search_terms` 中的每个词
2. **分数优先级**: 保留最高匹配分数的结果
3. **高亮策略差异**: 
   - 如果匹配发生在 `display_name`，返回匹配字符的索引用于高亮
   - 如果匹配发生在 `search_terms`，不返回高亮索引（`None`）

### 2.3 排序算法

```rust
out.sort_by(|a, b| {
    self.mentions[a.0]
        .sort_rank
        .cmp(&self.mentions[b.0].sort_rank)  // 首先按 sort_rank
        .then_with(|| a.2.cmp(&b.2))          // 然后按匹配分数
        .then_with(|| {
            let an = self.mentions[a.0].display_name.as_str();
            let bn = self.mentions[b.0].display_name.as_str();
            an.cmp(bn)                         // 最后按名称字母顺序
        })
});
```

**目的**: 确保最相关、最常用的技能排在前面，同时保持相同优先级技能的字典序排列。

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
pub(crate) struct SkillPopup {
    query: String,                                    // 当前搜索查询
    mentions: Vec<MentionItem>,                       // 所有技能项
    state: ScrollState,                               // 滚动/选择状态
}
```

### 3.2 关键流程

#### 3.2.1 过滤与排序流程 (`filtered` 方法)

```
1. 遍历所有 mentions
   ├── 如果 query 为空 → 直接加入结果（无匹配高亮）
   └── 否则
       ├── 尝试匹配 display_name
       ├── 遍历 search_terms 尝试匹配（跳过与 display_name 相同的词）
       └── 保留最高分数的匹配结果
2. 按 sort_rank → score → display_name 排序
3. 返回匹配结果列表
```

#### 3.2.2 渲染流程 (`render_ref` 实现)

```
1. 分割区域：列表区域 + 提示区域
2. 将匹配结果转换为 GenericDisplayRow
   ├── 截断名称（最大24字符）
   ├── 组合分类标签和描述
   └── 设置匹配高亮索引
3. 调用 render_rows_single_line 渲染行
4. 渲染底部提示行（Enter 插入 / Esc 关闭）
```

### 3.3 依赖模块

| 模块 | 用途 |
|------|------|
| `selection_popup_common` | 提供 `GenericDisplayRow` 和 `render_rows_single_line` 统一渲染 |
| `scroll_state` | 管理列表滚动和选中状态 |
| `popup_consts` | 共享弹窗常量（如 `MAX_POPUP_ROWS = 8`） |
| `codex_utils_fuzzy_match` | 提供模糊匹配算法 |
| `text_formatting::truncate_text` | 文本截断工具 |

### 3.4 与 ChatComposer 的集成

`SkillPopup` 本身是无状态渲染组件，其生命周期由 `ChatComposer` 管理：
- `ChatComposer` 持有 `SkillPopup` 实例
- 当用户输入 `@` 时，`ChatComposer` 调用 `set_mentions` 更新技能列表
- 用户输入搜索词时，调用 `set_query` 更新过滤条件
- 用户确认选择后，`ChatComposer` 获取 `selected_mention()` 并插入文本

## 4. 关键代码路径与文件引用

### 4.1 文件位置
- **主文件**: `codex-rs/tui_app_server/src/bottom_pane/skill_popup.rs`

### 4.2 依赖文件
```
codex-rs/tui_app_server/src/bottom_pane/
├── selection_popup_common.rs    # GenericDisplayRow, render_rows_single_line
├── scroll_state.rs              # ScrollState
├── popup_consts.rs              # MAX_POPUP_ROWS
└── mod.rs                       # BottomPaneView trait

codex-rs/tui_app_server/src/
├── text_formatting.rs           # truncate_text
├── key_hint.rs                  # 键盘提示渲染
├── render/mod.rs                # Insets, RectExt
└── style.rs                     # user_message_style

codex-rs/utils/fuzzy-match/src/lib.rs  # fuzzy_match
```

### 4.3 关键代码片段

#### 模糊匹配与排序
```rust
// skill_popup.rs:130-184
fn filtered(&self) -> Vec<(usize, Option<Vec<usize>>, i32)> {
    let filter = self.query.trim();
    let mut out: Vec<(usize, Option<Vec<usize>>, i32)> = Vec::new();

    for (idx, mention) in self.mentions.iter().enumerate() {
        if filter.is_empty() {
            out.push((idx, None, 0));
            continue;
        }

        let mut best_match: Option<(Option<Vec<usize>>, i32)> = None;

        if let Some((indices, score)) = fuzzy_match(&mention.display_name, filter) {
            best_match = Some((Some(indices), score));
        }

        for term in &mention.search_terms {
            if term == &mention.display_name { continue; }
            if let Some((_indices, score)) = fuzzy_match(term, filter) {
                match best_match.as_mut() {
                    Some((best_indices, best_score)) => {
                        if score > *best_score {
                            *best_score = score;
                            *best_indices = None;  // 搜索词匹配不显示高亮
                        }
                    }
                    None => { best_match = Some((None, score)); }
                }
            }
        }

        if let Some((indices, score)) = best_match {
            out.push((idx, indices, score));
        }
    }

    out.sort_by(|a, b| { /* ... */ });
    out
}
```

#### 渲染实现
```rust
// skill_popup.rs:187-221
impl WidgetRef for SkillPopup {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        let (list_area, hint_area) = if area.height > 2 {
            let [list_area, _spacer_area, hint_area] = Layout::vertical([
                Constraint::Length(area.height - 2),
                Constraint::Length(1),
                Constraint::Length(1),
            ])
            .areas(area);
            (list_area, Some(hint_area))
        } else {
            (area, None)
        };
        let rows = self.rows_from_matches(self.filtered());
        render_rows_single_line(
            list_area.inset(Insets::tlbr(0, 2, 0, 0)),
            buf,
            &rows,
            &self.state,
            MAX_POPUP_ROWS,
            "no matches",
        );
        // ... 渲染提示行
    }
}
```

## 5. 依赖与外部交互

### 5.1 上游依赖（输入）

| 来源 | 数据 | 说明 |
|------|------|------|
| `ChatComposer` | `Vec<MentionItem>` | 技能列表数据 |
| 用户输入 | `query: String` | 搜索过滤词 |
| `fuzzy_match` | `(indices, score)` | 匹配结果和高亮索引 |

### 5.2 下游消费（输出）

| 消费者 | 数据 | 说明 |
|--------|------|------|
| `ChatComposer` | `Option<&MentionItem>` | 用户选中的技能 |
| 渲染系统 | `Buffer` | 通过 `WidgetRef` 渲染到终端 |

### 5.3 外部 crate 依赖

```toml
# Cargo.toml 依赖
crossterm = { version = "...", features = ["event-stream"] }
ratatui = "..."
codex-utils-fuzzy-match = { path = "../../utils/fuzzy-match" }
```

## 6. 风险、边界与改进建议

### 6.1 已知边界条件

1. **空查询处理**: 当 `query` 为空时，显示所有技能但不进行高亮（`indices = None`）
2. **最大行数限制**: `MAX_POPUP_ROWS = 8` 限制弹窗最大显示行数，超出内容需要滚动
3. **名称截断**: `MENTION_NAME_TRUNCATE_LEN = 24` 限制显示名称长度
4. **无匹配提示**: 当过滤结果为空时显示 "no matches"

### 6.2 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 性能问题 | 大量技能（>1000）时的模糊匹配可能变慢 | 当前使用简单的线性搜索，未来可考虑前缀树或索引 |
| Unicode 处理 | 多字节字符的截断可能导致显示异常 | 使用 `truncate_text` 工具函数处理 grapheme 边界 |
| 状态同步 | `ScrollState` 与过滤结果可能不同步 | `clamp_selection` 和 `ensure_visible` 确保选中项在可视范围内 |

### 6.3 改进建议

1. **性能优化**: 
   - 对技能列表建立倒排索引，加速模糊搜索
   - 使用异步/延迟搜索处理大量数据

2. **功能增强**:
   - 支持技能分组/折叠（按 category_tag）
   - 添加最近使用技能排序
   - 支持技能预览（hover 显示详情）

3. **可访问性**:
   - 添加屏幕阅读器支持（ARIA 标签）
   - 高对比度模式下的高亮样式优化

4. **代码重构**:
   - 将 `filtered()` 结果缓存，避免每次渲染重复计算
   - 提取通用的弹窗逻辑到共享 trait

### 6.4 相关测试

当前文件包含的测试：
- **无**: `skill_popup.rs` 本身没有单元测试，依赖集成测试验证

相关测试位置：
- `codex-rs/tui_app_server/src/bottom_pane/skills_toggle_view.rs` 有类似的快照测试可参考
