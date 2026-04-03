# Diff Render - 空白上下文行渲染测试

## 场景与职责

该快照测试验证 TUI 中**空白上下文行**的 diff 渲染效果。当 diff 的上下文行（未变更的行）内容为空（空字符串或仅空白字符）时，需要正确处理行号显示、缩进和样式，确保空白行与有内容的行在视觉上保持一致的对齐。

这是 diff 渲染的边界情况测试，确保空白内容不会导致渲染异常或对齐问题。

## 功能点目的

1. **空白行正确处理**：空字符串上下文行正确显示行号
2. **对齐保持**：空白行与有内容行的行号列对齐一致
3. **上下文展示**：即使内容为空也显示上下文行，保持代码结构完整
4. **样式一致性**：空白上下文行使用与其他上下文行相同的样式
5. **变更对比**：在空白上下文行之后正确展示实际的变更行

## 具体技术实现

### 测试数据构造

```rust
// 测试用例构造了一个特殊的 diff 场景：
// 第 1 行是空行（上下文）
// 第 2 行是变更行
let change = FileChange::Update {
    unified_diff: "...",  // 包含空白上下文行的 diff
    move_path: None,
};
```

### 上下文行渲染逻辑

```rust
// diff_render.rs:696-730
diffy::Line::Context(text) => {
    let s = text.trim_end_matches('\n');
    if let Some(syn) = syntax_spans {
        out.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
            new_ln,
            DiffLineType::Context,  // 上下文类型
            s,  // 内容（可能为空）
            width,
            line_number_width,
            Some(syn),
            style_context,
        ));
    } else {
        // 无语法高亮的渲染
        out.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
            new_ln,
            DiffLineType::Context,
            s,
            width,
            line_number_width,
            None,
            style_context,
        ));
    }
    old_ln += 1;
    new_ln += 1;
}
```

### 单行渲染处理

```rust
// diff_render.rs:837-938
fn push_wrapped_diff_line_inner_with_theme_and_color_level(
    line_number: usize,
    kind: DiffLineType,
    text: &str,  // 可能为空字符串
    // ...
) -> Vec<RtLine<'static>> {
    // 即使 text 为空，也会渲染行号和标记
    let ln_str = line_number.to_string();
    let gutter = format!("{ln_str:>gutter_width$} ");
    
    // Context 类型使用 ' ' 作为标记
    let (sign_char, sign_style, content_style) = match kind {
        DiffLineType::Insert => ('+', ...),
        DiffLineType::Delete => ('-', ...),
        DiffLineType::Context => (' ', style_context(), style_context()),
    };
    
    // 渲染...
}
```

### 关键代码路径

```rust
// diff_render.rs 中的相关部分

// 1. 解析 diff 并识别 Context 行
for h in patch.hunks() {
    for (line_idx, l) in h.lines().iter().enumerate() {
        match l {
            diffy::Line::Context(text) => {
                // 2. 渲染上下文行（包括空白行）
                let s = text.trim_end_matches('\n');
                out.extend(push_wrapped_diff_line_inner_with_theme_and_color_level(
                    new_ln,
                    DiffLineType::Context,
                    s,  // 可能为空
                    width,
                    line_number_width,
                    syntax_spans,
                    style_context,
                ));
                old_ln += 1;
                new_ln += 1;
            }
            // ... Insert, Delete
        }
    }
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| Context 行渲染 | `diff_render.rs:696-730` | 上下文行（含空白）的渲染逻辑 |
| 单行渲染 | `diff_render.rs:837-938` | `push_wrapped_diff_line_inner_with_theme_and_color_level` |
| 样式定义 | `diff_render.rs:1152-1154` | `style_context()` 函数 |
| 测试用例 | `diff_render.rs`（ assertion_line: 765） | 空白上下文行测试 |

### DiffLineType 枚举

```rust
// diff_render.rs:100-110
pub(crate) enum DiffLineType {
    Insert,   // 新增行，标记 +
    Delete,   // 删除行，标记 -
    Context,  // 上下文行，标记 ' '（空格）
}
```

## 依赖与外部交互

### 外部依赖

1. **diffy**：统一 diff 格式解析，提供 `Line::Context` 变体
2. **ratatui**：终端 UI 渲染

### 内部依赖

- `DiffLineType::Context` - 上下文行类型标识
- `style_context()` - 上下文行样式

### 渲染样式

| 属性 | Context 行 |
|------|-----------|
| 标记符 | 空格 `' '` |
| 前景色 | 默认 |
| 背景色 | 默认（无特殊背景） |
| 特殊修饰 | 无 |

## 风险、边界与改进建议

### 潜在风险

1. **空行与空白行混淆**：空字符串行与包含空格的行在视觉上难以区分
2. **尾部空白丢失**：`trim_end_matches('\n')` 可能意外移除有意义的尾部空白
3. **行号对齐**：空白行可能导致行号列对齐计算错误

### 边界情况

1. **纯空行**：`"\n"` 经过 trim 后变为 `""`
2. **仅空白字符行**：`"   \n"`（空格）或 `"\t\n"`（Tab）
3. **换行符处理**：不同换行符（`\n`, `\r\n`）的处理一致性
4. **连续空白行**：多行连续的空白上下文行

### 测试输出分析

预期输出：
```
"• Proposed Change example.txt (+1 -1)"
"    1           "      // 第 1 行：空白上下文行
"    2     -Y    "      // 第 2 行：删除行
"    2     +Y changed" // 第 2 行：新增行
```

验证点：
1. **空白行渲染**：第 1 行正确显示行号但内容为空
2. **对齐一致**：第 1 行与第 2 行的行号列对齐
3. **变更行正确**：删除和新增行正确显示
4. **标题正确**：显示 "Proposed Change" 而非 "Edited"

### 改进建议

1. **空白可视化**：
   - 可选显示空白字符（如使用 `·` 表示空格，`→` 表示 Tab）
   - 添加尾部空白警告指示

2. **行号优化**：
   - 考虑对空白行使用特殊标记（如 `~`）
   - 保持与周围行的对齐一致性

3. **配置选项**：
   - 是否显示空白上下文行
   - 空白字符显示模式
   - 最小上下文行数配置

4. **可访问性**：
   - 屏幕阅读器提示空白行
   - 高对比度模式下的空白指示

5. **调试支持**：
   - 添加空白行调试信息
   - 显示不可见字符的十六进制值

### 相关考虑

空白上下文行的正确处理对于以下场景很重要：
- **代码格式化工具**：可能引入或删除空白行
- **空函数/类**：包含空行的代码结构
- **段落分隔**：Markdown 等格式中的空行
- **导入/头文件**：代码文件开头的空行

### 测试补充建议

```rust
// 建议添加的测试场景
#[test]
fn blank_context_lines_with_whitespace() {
    // 测试包含空格和 Tab 的"空白"行
}

#[test]
fn consecutive_blank_context_lines() {
    // 测试多行连续的空白上下文行
}

#[test]
fn blank_line_at_diff_boundary() {
    // 测试位于 diff 边界的空白行
}
```
