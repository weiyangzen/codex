# Chat Composer Mention Popup Type Prefixes Snapshot 研究文档

## 场景与职责

该快照文件是 `codex_tui_app_server` crate 中 `chat_composer.rs` 模块的测试快照，用于验证**提及弹出层的类型前缀显示**。当用户输入 `$` 后输入搜索词时，显示匹配的提及项（插件、技能、应用）。

### 业务场景
- 用户想要引用某个文件、技能或应用
- 用户输入 `$` 触发提及弹出层
- 系统显示匹配的结果，按类型分类

### 提及类型
- **[Plugin]** - ChatGPT 插件
- **[Skill]** - Codex 技能
- **[App]** - 已安装的应用

## 功能点目的

### 核心功能
1. **智能搜索**：根据输入过滤匹配的提及项
2. **类型标识**：清晰标识每个结果的类型
3. **描述展示**：显示每个选项的简要描述
4. **键盘导航**：支持上下键选择和 Enter 确认

### 用户体验目标
- **快速查找**：用户可以快速找到需要的资源
- **类型区分**：不同类型的资源有不同的用途
- **信息丰富**：描述帮助用户做出正确选择

## 具体技术实现

### 关键数据结构
```rust
pub(crate) struct SkillPopup {
    items: Vec<MentionItem>,
    filtered_indices: Vec<usize>,
    state: ScrollState,
    // ...
}

pub(crate) struct MentionItem {
    pub name: String,
    pub description: String,
    pub mention_type: MentionType,
    pub binding: MentionBinding,
}

pub(crate) enum MentionType {
    Plugin,
    Skill,
    App,
}
```

### 弹出层触发
```rust
fn sync_popups(&mut self) {
    let text = self.textarea.text();
    let cursor = self.textarea.cursor();
    
    // 检测 $ 触发
    if let Some(query) = extract_mention_query(text, cursor) {
        if self.dismissed_mention_popup_token.as_ref() != Some(&query) {
            self.show_skill_popup(&query);
        }
    } else {
        self.dismiss_skill_popup();
    }
}

fn show_skill_popup(&mut self, query: &str) {
    let items = self.build_mention_items();
    let filtered: Vec<_> = items
        .into_iter()
        .filter(|item| fuzzy_match(&item.name, query))
        .collect();
    
    self.active_popup = ActivePopup::Skill(SkillPopup::new(filtered));
}
```

### 渲染逻辑
```rust
impl Renderable for SkillPopup {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        for (idx, item) in self.visible_items().iter().enumerate() {
            let line = format!(
                "  {}  [{}] {}",
                item.name,
                mention_type_label(item.mention_type),
                truncate(&item.description, max_desc_width)
            );
            // 渲染行...
        }
    }
}

fn mention_type_label(mention_type: MentionType) -> &'static str {
    match mention_type {
        MentionType::Plugin => "Plugin",
        MentionType::Skill => "Skill",
        MentionType::App => "App",
    }
}
```

### 关键代码路径
- **源文件**: `codex-rs/tui_app_server/src/bottom_pane/skill_popup.rs`
- **测试函数**: `mention_popup_type_prefixes` (在 chat_composer tests 中)
- **提及集成**: `chat_composer.rs` 中的 `sync_popups`

### 渲染输出分析
```
"                                                                        "
"› $goog                                                                 "
"                                                                        "
"                                                                        "
"  Google Calendar  [Plugin] Connect Google Calendar for scheduling, ava…"
"  Google Calendar  [Skill] Find availability and plan event changes     "
"  Google Calendar  [App] Look up events and availability                "
"                                                                        "
"  Press enter to insert or esc to close                                 "
```

- 第 2 行：输入框显示 `$goog`
- 第 5-7 行：三个 Google Calendar 选项，分别标注类型
- 描述过长时截断并显示 `…`

## 依赖与外部交互

### 内部依赖
- `SkillPopup` - 技能弹出层组件
- `fuzzy_match` - 模糊匹配算法
- `MentionBinding` - 提及绑定信息

### 外部交互
- **技能注册表**：获取可用技能列表
- **插件管理器**：获取已安装插件
- **应用连接器**：获取已配置应用

## 风险、边界与改进建议

### 潜在风险
1. **名称冲突**：不同类型可能有相同名称
2. **性能问题**：大量提及项时的搜索性能
3. **描述截断**：过长的描述可能丢失重要信息

### 边界情况
1. **无匹配结果**：搜索词无匹配时的处理
2. **空搜索词**：仅输入 `$` 时的默认显示
3. **重复项**：同名但不同类型的资源

### 改进建议
1. **图标支持**：使用图标代替文字标签
2. **颜色区分**：不同类型使用不同颜色
3. **最近使用**：优先显示最近使用的提及项
4. **收藏功能**：允许用户收藏常用提及项
5. **预览功能**：悬停时显示更详细的描述

### 相关文件引用
- 源文件: `codex-rs/tui_app_server/src/bottom_pane/skill_popup.rs`
- 模糊匹配: `codex-rs/utils/fuzzy_match/src/lib.rs`
