# WebSearchCell 历史记录渲染测试

## 场景与职责

该快照测试验证 `WebSearchCell` 在完成状态下的渲染行为。当Codex执行网络搜索工具调用后，TUI需要向用户展示：

1. 搜索已完成的状态指示
2. 搜索查询内容
3. 适当的视觉格式（前缀、换行等）

这是工具调用历史展示的一部分，帮助用户追踪AI执行的操作。

## 功能点目的

### 核心功能
- **搜索状态展示**：显示 "Searched" 表示搜索已完成
- **查询内容展示**：显示实际的搜索查询文本
- **自动换行**：长查询自动换行并正确缩进

### 测试场景
```rust
let query = "example search query with several generic words to exercise wrapping".to_string();
let cell = new_web_search_call(
    "call-1".to_string(),
    query.clone(),
    WebSearchAction::Search {
        query: Some(query),
        queries: None,
    },
);
```

测试使用较长的查询文本（包含多个单词）来验证换行行为。

## 具体技术实现

### 数据结构
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

### 渲染流程

1. **状态判断**（`web_search_header` 函数，第1591-1597行）：
   ```rust
   fn web_search_header(completed: bool) -> &'static str {
       if completed {
           "Searched"
       } else {
           "Searching the web"
       }
   }
   ```

2. **详情生成**（`web_search_detail` 函数，来自 `codex_core::web_search`）：
   ```rust
   let detail = web_search_detail(self.action.as_ref(), &self.query);
   ```

3. **文本组装**（第1648-1653行）：
   ```rust
   let text: Text<'static> = if detail.is_empty() {
       Line::from(vec![header.bold()]).into()
   } else {
       Line::from(vec![header.bold(), " ".into(), detail.into()]).into()
   };
   ```

4. **前缀包装**（第1654行）：
   ```rust
   PrefixedWrappedHistoryCell::new(
       text,
       vec![bullet, " ".into()],  // 首行前缀："• "
       "  "                        // 续行前缀：两个空格
   ).display_lines(width)
   ```

### 快照输出解析
```
• Searched example search query with several generic words to
  exercise wrapping
```

- 前缀：`• `（暗淡色子弹 + 空格）
- 标题：`Searched`（粗体）
- 查询内容：自动换行，续行缩进两个空格

## 关键代码路径与文件引用

### 核心实现
| 位置 | 描述 |
|-----|------|
| `history_cell.rs:1599-1656` | `WebSearchCell` 结构体和实现 |
| `history_cell.rs:1591-1597` | `web_search_header` 函数 |
| `history_cell.rs:1640-1656` | `HistoryCell for WebSearchCell` |

### 辅助结构
| 结构/函数 | 位置 | 用途 |
|----------|------|------|
| `PrefixedWrappedHistoryCell` | `history_cell.rs:544-575` | 带前缀的包装单元格 |
| `web_search_detail` | `codex_core::web_search` | 生成搜索详情文本 |

### 测试代码
- 位置：`history_cell.rs:3102-3116`
- 函数：`web_search_history_cell_snapshot`

## 依赖与外部交互

### 外部依赖
```rust
use codex_core::web_search::web_search_detail;
use codex_protocol::models::WebSearchAction;
```

### WebSearchAction 类型
```rust
pub enum WebSearchAction {
    Search { query: Option<String>, queries: Option<Vec<String>> },
    // ... 其他变体
}
```

### 样式系统
- 完成状态：`"•".dim()`（暗淡色）
- 进行中：`spinner(Some(self.start_time), self.animations_enabled)`（动画）
- 标题：`.bold()`（粗体）

## 风险、边界与改进建议

### 边界情况

| 场景 | 当前行为 | 说明 |
|-----|---------|------|
| 空查询 | 只显示 "Searched" | 通过 `detail.is_empty()` 判断 |
| 非常长的查询 | 自动换行 | 依赖 `PrefixedWrappedHistoryCell` |
| 多查询（queries） | 显示详情 | `web_search_detail` 处理 |

### 潜在问题

1. **查询隐私**
   - 搜索查询可能包含敏感信息
   - 历史记录中明文显示，无脱敏处理

2. **编码问题**
   - 查询中的特殊字符可能在终端显示异常
   - 需要确保URL解码正确

3. **换行一致性**
   - 当前使用 `PrefixedWrappedHistoryCell` 的通用换行
   - 对于搜索查询，可能需要在语义边界（如单词边界）换行

### 改进建议

1. **添加搜索来源指示**
   ```rust
   // 当前: • Searched ...
   // 建议: • [Web] Searched ... 或 • [Bing] Searched ...
   ```

2. **搜索结果数量**
   ```rust
   // 如果知道结果数量，可以显示
   "• Searched (5 results) ..."
   ```

3. **可折叠详情**
   - 长查询可以折叠显示
   - 用户按回车展开完整查询

4. **搜索时间**
   ```rust
   // 显示搜索耗时
   "• Searched (0.8s) ..."
   ```

### 相关测试
| 测试名称 | 描述 |
|---------|------|
| `web_search_history_cell_transcript_snapshot` | Transcript视图 |
| `web_search_history_cell_wraps_with_indented_continuation` | 换行验证 |
| `web_search_history_cell_short_query_does_not_wrap` | 短查询不折行 |
