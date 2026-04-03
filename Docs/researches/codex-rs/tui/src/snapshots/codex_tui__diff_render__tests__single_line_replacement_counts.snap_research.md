# Single Line Replacement Counts Snapshot 研究文档

## 场景与职责

此快照测试验证了单行替换场景下的 diff 渲染和行数统计功能。具体场景是：README.md 文件中的一行被替换为另一行（`+1 -1`）。

该测试确保：
1. 单行替换的统计正确显示为 `(+1 -1)`
2. 行号正确对齐（删除行和新增行都显示为行号 1）
3. Header 正确显示 "Proposed Change" 前缀

## 功能点目的

### 行数统计功能

```rust
pub(crate) fn calculate_add_remove_from_diff(diff: &str) -> (usize, usize) {
    if let Ok(patch) = diffy::Patch::from_str(diff) {
        patch
            .hunks()
            .iter()
            .flat_map(Hunk::lines)
            .fold((0, 0), |(a, d), l| match l {
                diffy::Line::Insert(_) => (a + 1, d),
                diffy::Line::Delete(_) => (a, d + 1),
                diffy::Line::Context(_) => (a, d),
            })
    } else {
        (0, 0)
    }
}
```

该函数统计 diff 中的：
- `Insert` 行数 → 添加行数 (+)
- `Delete` 行数 → 删除行数 (-)
- `Context` 行数 → 不参与统计

### 单行替换的特殊处理

对于单行替换（一行删除 + 一行新增）：
- 删除行显示：行号 1 + `-` + 旧内容
- 新增行显示：行号 1 + `+` + 新内容
- 统计：(+1 -1)

## 具体技术实现

### 统计渲染

```rust
fn render_line_count_summary(added: usize, removed: usize) -> Vec<RtSpan<'static>> {
    let mut spans = Vec::new();
    spans.push("(".into());
    spans.push(format!("+{added}").green());  // 绿色显示添加
    spans.push(" ".into());
    spans.push(format!("-{removed}").red());  // 红色显示删除
    spans.push(")".into());
    spans
}
```

### Header 生成

```rust
let mut header_spans: Vec<RtSpan<'static>> = vec!["• ".dim()];
if let [row] = &rows[..] {
    let verb = match &row.change {
        FileChange::Add { .. } => "Added",
        FileChange::Delete { .. } => "Deleted",
        _ => "Edited",  // Update 类型使用 "Edited"
    };
    header_spans.push(verb.bold());
    header_spans.push(" ".into());
    header_spans.extend(render_path(row));
    header_spans.push(" ".into());
    header_spans.extend(render_line_count_summary(row.added, row.removed));
}
```

### 测试构造

从测试代码可以看出，该场景构造了一个简单的单行替换：

```rust
// 原始行
# Codex CLI (Rust Implementation)

// 替换为
# Codex CLI (Rust Implementation) banana
```

这是一个典型的 "Proposed Change" 场景，用于展示待应用的代码变更。

## 关键代码路径与文件引用

### 核心代码位置

| 文件 | 函数/代码 | 行号 | 说明 |
|------|-----------|------|------|
| `diff_render.rs` | `calculate_add_remove_from_diff` | 764-779 | 统计 diff 添加/删除行数 |
| `diff_render.rs` | `render_line_count_summary` | 392-400 | 渲染 (+N -M) 统计 |
| `diff_render.rs` | `render_changes_block` | 402-464 | 渲染变更块 header |

### 测试相关代码

```rust
// 测试断言位置
assertion_line: 765
expression: terminal.backend()
```

测试使用 `assert_snapshot!` 宏验证渲染输出。

## 依赖与外部交互

### Diff 解析依赖

- `diffy::Patch::from_str`：解析 unified diff 字符串
- `diffy::Hunk`：表示 diff 中的一个 hunk
- `diffy::Line`：表示 diff 中的一行（Insert/Delete/Context）

### 样式依赖

- `ratatui::style::Stylize`：提供 `.green()`、`.red()`、`.dim()` 等样式方法
- 颜色使用语义化命名，不依赖具体颜色值

## 风险、边界与改进建议

### 边界情况

1. **零行变更**：
   - 如果 diff 只包含 context 行（无实际变更）
   - 统计显示 `(+0 -0)`，可能令人困惑

2. **大数字显示**：
   - 超过 4 位数的行数统计可能导致布局错位
   - 当前未对超大数字做特殊处理

3. **空 diff**：
   - 如果 `diffy::Patch::from_str` 失败，返回 `(0, 0)`
   - 调用者需要处理这种情况

### 潜在风险

1. **统计准确性**：
   ```rust
   // 当前实现
   diffy::Line::Insert(_) => (a + 1, d),
   ```
   某些特殊 diff 格式（如二进制 diff）可能无法正确统计

2. **国际化**：
   - "Proposed Change"、"Added"、"Deleted"、"Edited" 为硬编码英文
   - 不支持本地化

### 改进建议

1. **用户体验**：
   - 当添加和删除行数相同时，显示 "Changed N lines" 而非 "Edited"
   - 添加百分比变化指示

2. **可访问性**：
   - 不仅依赖颜色区分添加/删除，添加图标或文字标签
   - 支持色盲友好的配色方案

3. **功能扩展**：
   - 显示净变更行数（添加 - 删除）
   - 对于大变更，显示 "+999 -999 (truncated)" 提示

4. **代码质量**：
   - 将统计逻辑和渲染逻辑分离，便于单元测试
   - 添加对无效 diff 的错误处理
