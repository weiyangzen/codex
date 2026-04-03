# WebSearchCell Transcript 视图渲染测试

## 场景与职责

该快照测试验证 `WebSearchCell` 在 Transcript 视图（`Ctrl+T` 快捷键打开）中的渲染行为。Transcript 视图是 Codex TUI 的一个特殊视图，用于显示完整的对话记录，包括：

1. 用户输入
2. AI响应
3. 工具调用及其结果

此测试确保 Web 搜索工具调用在 Transcript 视图中的显示格式正确。

## 功能点目的

### Transcript 视图 vs 主视图
| 特性 | 主视图 | Transcript 视图 |
|-----|--------|----------------|
| 用途 | 实时交互 | 查看完整记录 |
| 内容 | 当前会话 | 所有历史 |
| 格式 | 富文本、动画 | 简洁、静态 |

### 测试目的
- 验证 `WebSearchCell` 的 `transcript_lines` 方法正确实现
- 确保 Transcript 视图中的搜索记录格式正确
- 验证 `display_lines` 和 `transcript_lines` 的一致性（当前实现相同）

## 具体技术实现

### 默认实现
`WebSearchCell` 没有显式实现 `transcript_lines`，因此使用 `HistoryCell` trait 的默认实现：

```rust
// history_cell.rs:122-124
default fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
    self.display_lines(width)
}
```

这意味着 Transcript 视图和主视图的渲染结果相同。

### 渲染流程
与 `web_search_history_cell_snapshot` 相同：

1. **状态判断**：`completed = true` → "Searched"
2. **详情生成**：`web_search_detail()`
3. **文本组装**：`header.bold() + detail`
4. **前缀包装**：`PrefixedWrappedHistoryCell`

### 快照输出
```
• Searched example search query with several generic words to
  exercise wrapping
```

输出与主视图测试完全一致。

## 关键代码路径与文件引用

### 默认 Trait 实现
```rust
// history_cell.rs:117-149
trait HistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>>;
    
    // 默认实现：直接委托给 display_lines
    fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
        self.display_lines(width)
    }
    
    fn desired_transcript_height(&self, width: u16) -> u16 {
        // 使用 Paragraph::line_count 计算高度
        // 包含 ratatui bug 的 workaround
    }
}
```

### WebSearchCell 实现
| 位置 | 描述 |
|-----|------|
| `history_cell.rs:1640-1656` | `HistoryCell for WebSearchCell` |
| `history_cell.rs:1658-1663` | `new_active_web_search_call` |
| `history_cell.rs:1666-1679` | `new_web_search_call` |

### 测试代码
- 位置：`history_cell.rs:3158-3172`
- 函数：`web_search_history_cell_transcript_snapshot`

## 依赖与外部交互

### Transcript 系统集成
```rust
// ChatWidget 中缓存 transcript 尾部
fn cached_transcript_tail(&mut self) -> (&[Line<'static>], u64) {
    // 使用 active_cell_cache_key 判断是否需要刷新
    // 调用 cell.transcript_lines(width)
}
```

### 动画处理
```rust
fn transcript_animation_tick(&self) -> Option<u64> {
    if !self.animations_enabled || self.completed {
        return None;
    }
    Some((self.start_time.elapsed().as_millis() / 50) as u64)
}
```

对于已完成的搜索，`transcript_animation_tick` 返回 `None`，表示内容稳定。

## 风险、边界与改进建议

### 当前设计分析

**优点**：
- 简单：复用 `display_lines` 实现
- 一致：用户在不同视图看到相同格式
- 维护成本低

**潜在问题**：
- 缺乏 Transcript 特有的格式优化
- 对于历史记录，可能需要更紧凑的格式

### 改进建议

1. **Transcript 专用格式**
   ```rust
   impl HistoryCell for WebSearchCell {
       fn transcript_lines(&self, width: u16) -> Vec<Line<'static>> {
           // Transcript 视图使用更紧凑的格式
           // 例如："[Search] example search query..."
       }
       
       fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
           // 主视图使用更详细的格式
       }
   }
   ```

2. **添加时间戳**
   ```rust
   // Transcript 视图中添加搜索时间
   "[10:23:45] • Searched ..."
   ```

3. **搜索结果摘要**
   ```rust
   // 在 Transcript 中显示搜索结果数量
   "• Searched (5 results) ..."
   ```

4. **可点击链接**
   - Transcript 视图中支持点击搜索查询复制到剪贴板
   - 或直接在浏览器中打开搜索

### 相关测试
| 测试名称 | 描述 |
|---------|------|
| `web_search_history_cell_snapshot` | 主视图渲染 |
| `active_mcp_tool_call_snapshot` | 活动工具调用（对比） |

### 需要覆盖的场景
- 进行中的搜索（`completed = false`）在 Transcript 中的显示
- 搜索失败的错误处理
- 多查询搜索（`queries` 字段）的显示
