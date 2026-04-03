# Research Document: Web Search History Cell Snapshot

## 场景与职责

此快照测试验证 **WebSearchCell** 组件在渲染网络搜索历史记录时的行为。当 Codex 执行网络搜索操作后，需要在历史记录中展示搜索动作和查询内容。

该组件负责：
- 展示搜索状态（Searching/Searched）
- 显示搜索查询内容
- 支持搜索过程中的动画效果
- 处理长查询的自动换行

## 功能点目的

**主要功能**：验证 WebSearchCell 对搜索操作的渲染效果：

1. **状态标识**：已完成搜索显示 `"• Searched"`
2. **查询展示**：显示搜索查询文本
3. **自动换行**：长查询在宽度 64 时正确换行
4. **视觉层次**：使用项目符号和缩进保持层次

**预期输出结构**（宽度 64）：
```
• Searched example search query with several generic words to
  exercise wrapping
```

## 具体技术实现

### 核心数据结构

**WebSearchCell**（位于 `history_cell.rs` 第 1599-1638 行）：
```rust
#[derive(Debug)]
pub(crate) struct WebSearchCell {
    call_id: String,
    query: String,
    action: Option<WebSearchAction>,
    start_time: Instant,
    completed: bool,
    animations_enabled: bool,
}
```

**WebSearchAction**（位于 `codex-protocol/src/models.rs`）：
```rust
pub enum WebSearchAction {
    Search { query: Option<String>, queries: Option<Vec<String>> },
    OpenPage { url: Option<String> },
    FindInPage { url: Option<String>, pattern: Option<String> },
    Other,
}
```

### 渲染流程

**display_lines 方法**（第 1640-1656 行）：
```rust
impl HistoryCell for WebSearchCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 1. 选择状态符号
        let bullet = if self.completed {
            "•".dim()
        } else {
            spinner(Some(self.start_time), self.animations_enabled)
        };
        
        // 2. 获取状态标题
        let header = web_search_header(self.completed);  // "Searched" 或 "Searching the web"
        
        // 3. 获取搜索详情
        let detail = web_search_detail(self.action.as_ref(), &self.query);
        
        // 4. 组装文本
        let text: Text<'static> = if detail.is_empty() {
            Line::from(vec![header.bold()]).into()
        } else {
            Line::from(vec![header.bold(), " ".into(), detail.into()]).into()
        };
        
        // 5. 使用 PrefixedWrappedHistoryCell 渲染
        PrefixedWrappedHistoryCell::new(
            text,
            vec![bullet, " ".into()],  // 首行前缀
            "  "                         // 续行前缀
        ).display_lines(width)
    }
}
```

### 辅助函数

**web_search_header**（第 1591-1597 行）：
```rust
fn web_search_header(completed: bool) -> &'static str {
    if completed {
        "Searched"
    } else {
        "Searching the web"
    }
}
```

**web_search_detail**（位于 `codex-core/src/web_search.rs`）：
```rust
pub fn web_search_detail(action: Option<&WebSearchAction>, query: &str) -> String {
    let detail = action.map(web_search_action_detail).unwrap_or_default();
    if detail.is_empty() {
        query.to_string()
    } else {
        detail
    }
}
```

### 样式应用

- 项目符号：已完成 `"•".dim()`，进行中 `spinner()` 动画
- 标题：`"Searched".bold()`
- 详情：普通文本

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `WebSearchCell` 实现（第 1599-1679 行） |
| `codex-rs/tui/src/history_cell.rs` | `web_search_header` 函数（第 1591-1597 行） |
| `codex-rs/core/src/web_search.rs` | `web_search_detail`、`web_search_action_detail` |
| `codex-rs/tui/src/history_cell.rs` | `PrefixedWrappedHistoryCell`（第 544-575 行） |
| `codex-rs/tui/src/history_cell.rs` | 测试用例（第 3102-3116 行） |

### 测试代码位置

```rust
// history_cell.rs 第 3102-3116 行
#[test]
fn web_search_history_cell_snapshot() {
    let query = "example search query with several generic words to exercise wrapping".to_string();
    let cell = new_web_search_call(
        "call-1".to_string(),
        query.clone(),
        WebSearchAction::Search {
            query: Some(query),
            queries: None,
        },
    );
    let rendered = render_lines(&cell.display_lines(64)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **codex-core**: `web_search_detail` 函数
- **codex-protocol**: `WebSearchAction` 类型
- **ratatui**: 文本渲染

### 状态流转

```
new_active_web_search_call (创建，completed=false)
    └── update (更新 action 和 query)
            └── complete (标记 completed=true)
                    └── display_lines 显示 "Searched"
```

## 风险、边界与改进建议

### 已知风险

1. **查询长度**：超长查询可能导致历史记录过长
2. **特殊字符**：查询中的特殊字符可能影响渲染
3. **国际化**：非 ASCII 查询的宽度计算可能不准确

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| query 为空 | 仅显示 `"• Searched"` |
| action 为 None | 使用 query 作为详情 |
| 多查询（queries） | 显示第一个查询 + `" ..."` |
| 搜索中 | 显示 `"Searching the web"` + spinner |

### 改进建议

1. **结果展示**：
   - 显示搜索结果数量
   - 提供搜索结果预览

2. **交互性**：
   - 点击搜索记录重新执行搜索
   - 支持搜索历史管理

3. **可访问性**：
   - 为搜索操作提供声音提示
   - 增加搜索完成通知

4. **性能优化**：
   - 缓存搜索结果摘要
   - 延迟加载搜索详情
