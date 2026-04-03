# Research Document: Web Search History Cell Transcript Snapshot

## 场景与职责

此快照测试验证 **WebSearchCell** 组件在转录模式（transcript mode）下的渲染行为。转录模式（`Ctrl+T`）用于展示会话的完整文本记录，与普通显示模式相比，可能包含更详细或不同格式的信息。

该组件负责：
- 在转录视图中展示搜索操作
- 保持与普通视图一致的信息结构
- 支持转录模式的特殊格式要求

## 功能点目的

**主要功能**：验证 WebSearchCell 在转录模式下的渲染效果：

1. **转录一致性**：转录视图与普通视图展示相同的核心信息
2. **格式统一**：使用相同的换行和缩进策略
3. **信息完整**：包含搜索状态和查询内容

**预期输出结构**：
```
• Searched example search query with several generic words to
  exercise wrapping
```

**注意**：当前快照与普通视图相同，说明 `WebSearchCell` 未自定义 `transcript_lines` 方法，使用默认实现（即调用 `display_lines`）。

## 具体技术实现

### 转录模式默认实现

**HistoryCell trait**（`history_cell.rs` 第 98-168 行）：
```rust
pub(crate) trait HistoryCell: std::fmt::Debug + Send + Sync + Any {
    /// 普通视图的行
    fn display_lines(&self, width: u16) -> Vec<Line<'static>>;
    
    /// 转录视图的行（默认使用 display_lines）
    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
        self.display_lines(width)
    }
    
    /// 转录视图高度（默认使用 desired_height）
    fn desired_transcript_height(&self, width: u16) -> u16 {
        let lines = self.transcript_lines(width);
        // ratatui bug 处理：单行空白返回 2 行的问题
        if let [line] = &lines[..]
            && line.spans.iter().all(|s| s.content.chars().all(char::is_whitespace))
        {
            return 1;
        }
        Paragraph::new(Text::from(lines))
            .wrap(Wrap { trim: false })
            .line_count(width)
            .try_into()
            .unwrap_or(0)
    }
}
```

### WebSearchCell 实现

**当前实现**（`history_cell.rs` 第 1640-1656 行）：
```rust
impl HistoryCell for WebSearchCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let bullet = if self.completed {
            "•".dim()
        } else {
            spinner(Some(self.start_time), self.animations_enabled)
        };
        let header = web_search_header(self.completed);
        let detail = web_search_detail(self.action.as_ref(), &self.query);
        let text: Text<'static> = if detail.is_empty() {
            Line::from(vec![header.bold()]).into()
        } else {
            Line::from(vec![header.bold(), " ".into(), detail.into()]).into()
        };
        PrefixedWrappedHistoryCell::new(
            text,
            vec![bullet, " ".into()],
            "  "
        ).display_lines(width)
    }
    
    // 未覆盖 transcript_lines，使用默认实现
}
```

### 转录视图触发

**转录模式激活**：
- 用户按下 `Ctrl+T`
- `ChatWidget` 切换到转录覆盖层
- 调用各 `HistoryCell` 的 `transcript_lines` 方法

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `HistoryCell` trait 定义（第 98-168 行） |
| `codex-rs/tui/src/history_cell.rs` | `WebSearchCell` 实现（第 1599-1679 行） |
| `codex-rs/tui/src/history_cell.rs` | `PrefixedWrappedHistoryCell`（第 544-575 行） |
| `codex-rs/tui/src/history_cell.rs` | 测试用例（第 3158-3172 行） |

### 测试代码位置

```rust
// history_cell.rs 第 3158-3172 行
#[test]
fn web_search_history_cell_transcript_snapshot() {
    let query = "example search query with several generic words to exercise wrapping".to_string();
    let cell = new_web_search_call(
        "call-1".to_string(),
        query.clone(),
        WebSearchAction::Search {
            query: Some(query),
            queries: None,
        },
    );
    // 使用 transcript_lines 而非 display_lines
    let rendered = render_lines(&cell.transcript_lines(64)).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 转录模式 vs 普通模式

| 特性 | 普通模式 | 转录模式 |
|------|---------|---------|
| 方法 | `display_lines` | `transcript_lines` |
| 用途 | 主聊天视图 | `Ctrl+T` 覆盖层 |
| 动画 | 支持 | 通常禁用或简化 |
| 格式 | 可能更紧凑 | 可能更详细 |

### 自定义转录视图的组件

某些组件（如 `ExecCell`）自定义了 `transcript_lines`：
```rust
// ExecCell 的自定义实现
impl HistoryCell for ExecCell {
    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
        // 显示 $ 前缀的命令
        // 显示退出状态和时间
    }
}
```

## 风险、边界与改进建议

### 当前限制

1. **无差异化**：转录视图与普通视图完全相同
2. **信息密度**：未利用转录模式展示更多信息
3. **格式一致性**：与其他组件的转录格式可能不一致

### 改进建议

1. **增强转录视图**：
   - 显示搜索时间戳
   - 显示搜索结果数量
   - 显示搜索耗时

2. **格式标准化**：
   - 统一使用 `$` 前缀表示系统操作
   - 添加时间戳前缀

3. **可配置性**：
   - 允许用户选择转录视图的详细程度
   - 支持转录视图的自定义格式

4. **测试覆盖**：
   - 增加转录视图与普通视图的对比测试
   - 测试转录视图的边界情况
