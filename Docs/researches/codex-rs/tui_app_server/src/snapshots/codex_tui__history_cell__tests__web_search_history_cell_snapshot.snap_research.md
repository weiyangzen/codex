# 研究文档：web_search_history_cell_snapshot.snap

## 场景与职责

此快照测试验证网页搜索历史记录单元格的显示效果。当 Codex 执行网页搜索时，搜索查询应该在历史记录中正确显示。

## 功能点目的

1. **搜索操作展示**：显示网页搜索操作和查询
2. **查询换行**：长查询需要正确换行
3. **状态标识**：标识搜索操作类型

## 具体技术实现

### 快照输出分析

```
• Searched example search query with several generic words to
  exercise wrapping
```

设计特点：
- `• Searched` - 操作类型标识
- 查询文本换行显示
- 后续行有缩进对齐

### 搜索单元格实现

```rust
pub struct WebSearchCell {
    pub query: String,
    pub results: Vec<WebSearchResult>,
}

impl HistoryCell for WebSearchCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let mut lines = vec![];
        let prefix = "• Searched ";
        let wrapped = textwrap::wrap(&self.query, width as usize - prefix.width());
        
        for (i, line) in wrapped.iter().enumerate() {
            if i == 0 {
                lines.push(Line::from(format!("{prefix}{line}")));
            } else {
                lines.push(Line::from(format!("  {line}")));
            }
        }
        
        lines
    }
}
```

## 关键代码路径与文件引用

1. **搜索处理**：
   - `codex-rs/tui/src/history_cell.rs`
   - `codex_core::web_search::web_search_detail`

2. **协议类型**：
   - `codex_protocol::models::WebSearchAction`

## 依赖与外部交互

### 搜索相关
- `codex_core::web_search` - 网页搜索功能

## 风险、边界与改进建议

### 潜在风险
1. **查询过长**：非常长的查询可能影响可读性
2. **隐私问题**：搜索查询可能包含敏感信息

### 边界情况
1. 空查询
2. 查询包含特殊字符
3. 多语言查询

### 改进建议
1. 添加搜索结果数量显示
2. 支持点击搜索查询重新搜索
3. 添加搜索时间显示
4. 支持搜索历史管理
