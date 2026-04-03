# skill_popup.rs 研究文档

## 场景与职责

`skill_popup.rs` 是 Codex TUI 中负责 **Skill 提及（Mention）弹出选择器** 的 UI 组件。当用户在聊天输入框中触发 Skill 提及功能（通常是通过 `@` 符号或特定快捷键）时，该组件会显示一个可搜索的弹出窗口，允许用户从可用的 Skill 列表中选择并插入到输入中。

该组件的核心职责包括：
- 展示可搜索的 Skill 列表
- 支持模糊匹配搜索
- 高亮显示匹配结果
- 处理用户导航（上下移动）和选择（回车确认）
- 提供视觉反馈和操作提示

## 功能点目的

### 1. MentionItem 数据结构
```rust
pub(crate) struct MentionItem {
    pub(crate) display_name: String,      // 显示名称
    pub(crate) description: Option<String>, // 描述信息
    pub(crate) insert_text: String,       // 插入到输入框的文本
    pub(crate) search_terms: Vec<String>, // 额外的搜索词
    pub(crate) path: Option<String>,      // Skill 文件路径
    pub(crate) category_tag: Option<String>, // 分类标签
    pub(crate) sort_rank: u8,             // 排序优先级
}
```

`MentionItem` 封装了 Skill 提及项的所有元数据，支持：
- **多维度搜索**：除了 `display_name`，还可以通过 `search_terms` 进行匹配
- **分类展示**：通过 `category_tag` 对 Skill 进行分组
- **优先级排序**：`sort_rank` 控制展示顺序
- **灵活插入**：`insert_text` 可以与显示名称不同

### 2. 模糊搜索与过滤
`SkillPopup` 实现了基于 `codex_utils_fuzzy_match::fuzzy_match` 的搜索功能：
- 支持对 `display_name` 和 `search_terms` 的模糊匹配
- 匹配结果按 `sort_rank` → 匹配分数 → 名称字母顺序 排序
- 匹配字符位置会被记录用于高亮显示

### 3. 导航与选择
- **上下导航**：通过 `ScrollState` 管理选择状态，支持循环导航
- **选择确认**：回车键确认选择，返回对应的 `MentionItem`
- **实时过滤**：输入查询时实时更新匹配结果

### 4. 渲染与样式
- 使用 `GenericDisplayRow` 统一行展示格式
- 支持匹配字符高亮（bold）
- 名称截断处理（`MENTION_NAME_TRUNCATE_LEN = 24`）
- 底部显示操作提示（Enter 插入，Esc 关闭）

## 具体技术实现

### 关键流程

#### 1. 初始化流程
```rust
pub(crate) fn new(mentions: Vec<MentionItem>) -> Self {
    Self {
        query: String::new(),
        mentions,
        state: ScrollState::new(),
    }
}
```

#### 2. 过滤与排序流程
```rust
fn filtered(&self) -> Vec<(usize, Option<Vec<usize>>, i32)> {
    // 1. 遍历所有 mentions
    // 2. 对每个 mention 尝试匹配 display_name 和 search_terms
    // 3. 记录最佳匹配结果（索引、匹配位置、分数）
    // 4. 按 sort_rank -> score -> display_name 排序
}
```

#### 3. 渲染流程
```rust
impl WidgetRef for SkillPopup {
    fn render_ref(&self, area: Rect, buf: &mut Buffer) {
        // 1. 分割区域：列表区 + 提示区
        // 2. 构建 GenericDisplayRow 列表
        // 3. 调用 render_rows_single_line 渲染
        // 4. 渲染底部操作提示
    }
}
```

### 数据结构

| 结构/类型 | 用途 |
|-----------|------|
| `MentionItem` | Skill 提及项的元数据 |
| `SkillPopup` | 弹出窗口状态管理 |
| `ScrollState` | 滚动和选择状态（来自 scroll_state.rs） |
| `GenericDisplayRow` | 统一行展示格式（来自 selection_popup_common.rs） |

### 依赖模块

```rust
use super::popup_consts::MAX_POPUP_ROWS;        // 最大显示行数（8行）
use super::scroll_state::ScrollState;           // 滚动状态管理
use super::selection_popup_common::GenericDisplayRow;
use super::selection_popup_common::render_rows_single_line;
use crate::key_hint;                            // 按键提示
use crate::render::Insets;
use crate::render::RectExt;
use crate::text_formatting::truncate_text;      // 文本截断
use codex_utils_fuzzy_match::fuzzy_match;       // 模糊匹配
```

## 关键代码路径与文件引用

### 核心实现
- `codex-rs/tui/src/bottom_pane/skill_popup.rs` - 本文件，Skill 弹出选择器实现

### 依赖文件
- `codex-rs/tui/src/bottom_pane/scroll_state.rs` - 滚动状态管理
- `codex-rs/tui/src/bottom_pane/selection_popup_common.rs` - 通用选择弹出组件
- `codex-rs/tui/src/bottom_pane/popup_consts.rs` - 弹出窗口常量
- `codex-rs/tui/src/text_formatting.rs` - 文本格式化工具
- `codex-rs/tui/src/key_hint.rs` - 按键提示生成
- `codex-rs/tui/src/render/mod.rs` - 渲染工具（Insets, RectExt）

### 调用方
- `codex-rs/tui/src/bottom_pane/chat_composer.rs` - 聊天输入框，触发 Skill 提及弹出

### 外部依赖 Crate
- `codex_utils_fuzzy_match` - 模糊匹配算法
- `ratatui` - TUI 渲染框架
- `crossterm` - 终端控制

## 依赖与外部交互

### 输入依赖
1. **Skill 元数据**：从 `ChatComposer` 传入的 `Vec<MentionItem>`，来源于 `codex_core::skills::model::SkillMetadata`
2. **用户输入**：查询字符串（通过 `set_query` 设置）
3. **键盘事件**：由父组件 `BottomPane` 路由处理

### 输出交互
1. **选择结果**：通过 `selected_mention()` 返回选中的 `&MentionItem`
2. **渲染输出**：实现 `WidgetRef` trait，由 ratatui 渲染框架调用

### 与 ChatComposer 的协作
```
ChatComposer (捕获 @ 触发)
    ↓
创建 SkillPopup 实例
    ↓
BottomPane 路由键盘事件到 SkillPopup
    ↓
用户选择后，SkillPopup 返回 MentionItem
    ↓
ChatComposer 将 insert_text 插入输入框
```

## 风险、边界与改进建议

### 潜在风险

1. **性能问题**：当 Skill 数量非常大时（数千个），每次输入都进行全量模糊匹配可能导致延迟
   - 当前缓解：使用 `sort_rank` 优先级排序，但未实现异步/增量搜索

2. **内存占用**：`MentionItem` 包含多个 `String` 字段，大量 Skill 时会占用较多内存
   - 建议：考虑使用 `Arc<str>` 或字符串池化

3. **匹配精度**：`search_terms` 匹配时不返回匹配位置（`indices = None`），导致无法高亮
   - 代码位置：`filtered()` 方法中第 156 行 `*best_indices = None`

### 边界情况

1. **空列表**：当 `mentions` 为空时，`filtered()` 返回空向量，`render_ref` 显示 "no matches"
2. **超长名称**：`display_name` 超过 24 字符会被截断，但截断可能发生在多字节字符中间
3. **极窄终端**：宽度小于 2 时，布局会退化，提示区域可能无法显示

### 改进建议

1. **异步搜索**：对于大量 Skill，考虑使用异步搜索或 Web Worker 模式避免阻塞 UI

2. **搜索缓存**：缓存最近的搜索结果，避免重复计算

3. **匹配高亮优化**：为 `search_terms` 匹配也提供高亮支持
   ```rust
   // 当前代码
   if display_name != skill_name && let Some((_indices, score)) = fuzzy_match(skill_name, filter) {
       return Some((None, score));  // None 导致无法高亮
   }
   ```

4. **可配置截断长度**：`MENTION_NAME_TRUNCATE_LEN` 目前是硬编码常量，建议根据终端宽度动态调整

5. **键盘快捷键扩展**：
   - 支持数字键直接选择（1-9）
   - 支持 PageUp/PageDown 快速翻页

6. **测试覆盖**：当前文件没有单元测试，建议添加：
   - 模糊匹配排序逻辑测试
   - 边界情况测试（空列表、超长字符串）
   - 渲染输出快照测试
