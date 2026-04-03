# Diff Render - 长行自动换行渲染测试（纯文本视图）

## 场景与职责

该快照测试验证 TUI 中**超长代码行的自动换行**的纯文本输出效果。与 backend 视图测试不同，此测试使用 `snapshot_lines_text` 函数提取纯文本内容，便于验证换行逻辑的正确性和缩进对齐，而不受样式信息干扰。

此测试特别适用于验证复杂的换行边界情况，如长单词截断、多行连续换行等。

## 功能点目的

1. **纯文本验证**：去除样式信息后验证换行逻辑
2. **缩进对齐检查**：验证续行的缩进是否正确
3. **长单词截断**：验证超长单词（无空白字符）的截断换行
4. **多行换行**：验证同一 diff 中多行长行的换行处理
5. **边界可视化**：便于人工审查换行结果

## 具体技术实现

### 纯文本提取

```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    // 将 RtLine 转换为纯文本，去除样式
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())
                .collect::<String>()
        })
        .map(|s| s.trim_end().to_string())  // 去除尾部空格
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(name, text);
}
```

### 测试数据构造

```rust
#[test]
fn ui_snapshot_apply_update_block_wraps_long_lines_text() {
    // 构造包含长行的测试数据
    let original = "1\n2\n3\n4\n";
    let modified = "1\n\
        added long line which wraps and_if_there_is_a_long_token_it_will_be_broken\n\
        3\n\
        4 context line which also wraps across\n";
    let patch = diffy::create_patch(original, modified).to_string();

    let mut changes: HashMap<PathBuf, FileChange> = HashMap::new();
    changes.insert(
        PathBuf::from("wrap_demo.txt"),
        FileChange::Update {
            unified_diff: patch,
            move_path: None,
        },
    );

    // 使用较窄的宽度（28）强制换行
    let lines = create_diff_summary(&changes, &PathBuf::from("/"), 28);
    snapshot_lines_text("apply_update_block_wraps_long_lines_text", &lines);
}
```

### 换行宽度计算

```rust
// wrap_cols = 28（内容区域宽度）
// 实际可用内容宽度 = wrap_cols - 4（缩进） - line_number_width - 1（标记）
// 对于 1-2 位行号：28 - 4 - 2 - 1 = 21 字符
```

### 长单词截断逻辑

```rust
// 当单个字符超过剩余空间时
if byte_end == 0 {
    // 强制取至少一个字符，避免死循环
    let ch = remaining.chars().next().unwrap();
    let ch_len = ch.len_utf8();
    current_line.push(RtSpan::styled(remaining[..ch_len].to_string(), style));
    col = ch.width().unwrap_or(1);
    remaining = &remaining[ch_len..];
}
```

### 关键代码路径

```rust
// diff_render.rs:1627-1646
#[test]
fn ui_snapshot_apply_update_block_wraps_long_lines_text() {
    let original = "1\n2\n3\n4\n";
    let modified = "1\n\
        added long line which wraps and_if_there_is_a_long_token_it_will_be_broken\n\
        3\n\
        4 context line which also wraps across\n";
    let patch = diffy::create_patch(original, modified).to_string();
    // ...
    let lines = create_diff_summary(&changes, &PathBuf::from("/"), 28);
    snapshot_lines_text("apply_update_block_wraps_long_lines_text", &lines);
}

// diff_render.rs:1387-1402
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())
                .collect::<String>()
        })
        .map(|s| s.trim_end().to_string())
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!(name, text);
}
```

## 关键代码路径与文件引用

| 组件 | 文件路径 | 职责 |
|------|----------|------|
| 纯文本快照 | `diff_render.rs:1387-1402` | `snapshot_lines_text` 函数 |
| 换行核心 | `diff_render.rs:940-1020` | `wrap_styled_spans` 函数 |
| 测试用例 | `diff_render.rs:1627-1646` | `ui_snapshot_apply_update_block_wraps_long_lines_text` |
| 差异汇总 | `diff_render.rs:345-352` | `create_diff_summary` 函数 |

### 辅助函数

```rust
// diff_render.rs:1374-1385
fn display_width(text: &str) -> usize {
    text.chars()
        .map(|ch| ch.width().unwrap_or(if ch == '\t' { TAB_WIDTH } else { 0 }))
        .sum()
}

fn line_display_width(line: &RtLine<'static>) -> usize {
    line.spans
        .iter()
        .map(|span| display_width(span.content.as_ref()))
        .sum()
}
```

## 依赖与外部交互

### 外部依赖

1. **unicode-width**：Unicode 字符显示宽度计算
2. **insta**：快照测试框架

### 内部依赖

- `create_diff_summary()` - 创建 diff 汇总
- `wrap_styled_spans()` - 样式化文本换行

### 数据流

```
原始内容 + 修改内容
    ↓ diffy::create_patch()
统一 diff 字符串
    ↓ create_diff_summary(wrap_cols=28)
Vec<RtLine>（包含换行后的行）
    ↓ snapshot_lines_text()
纯文本字符串（用于快照比较）
```

## 风险、边界与改进建议

### 潜在风险

1. **测试脆弱性**：纯文本输出对空格敏感，格式微调可能导致测试失败
2. **宽度计算差异**：实际渲染宽度与计算宽度可能存在偏差
3. **平台差异**：不同平台的换行符处理

### 边界情况

1. **精确边界**：内容恰好等于可用宽度时的处理
2. **空续行**：换行后内容为空的情况
3. **多连续换行**：单行需要多次换行的场景
4. **混合宽度字符**：ASCII 和 CJK 字符混合的换行

### 测试输出分析

预期输出：
```
• Edited wrap_demo.txt (+2 -2)
    1  1
    2 -2
    2 +added long line which
        wraps and_if_there_i
       s_a_long_token_it_wil
       l_be_broken
    3  3
    4 -4
    4 +4 context line which
       also wraps across
```

验证点：
1. **文件头**：正确显示文件名和统计
2. **删除行**：`2 -2` 正确标记
3. **新增长行**：
   - 首行：`2 +added long line which`（行号 + 标记 + 内容）
   - 续行：`        wraps...`（8空格缩进）
   - 长单词截断：`s_a_long_token_it_wil` 和 `l_be_broken`
4. **上下文行**：`3  3` 正确显示
5. **第二行长行**：`4 context line which` 和 `       also wraps across`

### 缩进分析

```
文件级缩进：4 空格
行号列：2 字符（对于 1-9 行）+ 1 空格 = 3 字符
标记列：1 字符
内容起始位置：4 + 3 + 1 = 8 列

续行缩进：
- 行号占位：2 字符（与行号同宽）
- 标记占位：2 空格（替代 +/-/ ）
- 总缩进：4（文件）+ 2（行号）+ 2（标记）= 8 空格
```

### 改进建议

1. **测试增强**：
   - 添加更多边界测试（如恰好填满一行的内容）
   - 添加 CJK 字符换行测试
   - 添加 Emoji 换行测试

2. **可视化改进**：
   - 续行添加视觉指示符（如 `↪`）
   - 行号续行指示（如 `|` 或 `⋮`）

3. **配置选项**：
   - 允许用户配置换行宽度
   - 提供不换行模式（水平滚动）
   - 配置续行缩进量

4. **算法优化**：
   - 实现更智能的单词边界检测
   - 支持连字符断词
   - 考虑语言特定的换行规则

5. **调试支持**：
   - 添加换行调试信息输出
   - 提供换行可视化工具

### 相关测试

```rust
// diff_render.rs:2183-2226
#[test]
fn wrap_styled_spans_single_line() { /* ... */ }

#[test]
fn wrap_styled_spans_splits_long_content() { /* ... */ }

#[test]
fn wrap_styled_spans_flushes_at_span_boundary() { /* ... */ }

#[test]
fn wrap_styled_spans_preserves_styles() { /* ... */ }

#[test]
fn wrap_styled_spans_tabs_have_visible_width() { /* ... */ }
```

这些单元测试覆盖了 `wrap_styled_spans` 函数的各种边界情况。
