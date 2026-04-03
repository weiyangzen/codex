# 长行自动换行文本快照研究文档

## 场景与职责

### 测试场景
本快照测试是 `apply_update_block_wraps_long_lines` 的文本版本，验证在极窄终端宽度（28列）下diff长行折行的纯文本输出。与UI快照不同，本测试专注于文本内容的准确性，忽略样式和颜色信息。

### 测试设计意图
1. **纯文本验证**: 排除颜色和样式干扰，专注于内容正确性
2. **窄宽度场景**: 使用28列宽度，强制产生多行折行
3. **混合内容**: 同时包含插入行、删除行和上下文行的折行

### 组件职责
- **文本提取** (`snapshot_lines_text`): 从 `RtLine` 中提取纯文本内容
- **折行算法验证**: 确保在极端宽度下仍能正确分割
- **边界测试**: 验证长token（无空格）的强制分割逻辑

## 功能点目的

### 核心功能
1. **极端宽度适配**: 在极窄终端（如移动设备、分屏场景）下保持可读性
2. **长token处理**: 对于无法找到自然断点的长单词，强制字符级分割
3. **一致性验证**: 确保UI渲染和文本内容的一致性

### 测试构造
```rust
let original = "1\n2\n3\n4\n";
let modified = "1\nadded long line which wraps and_if_there_is_a_long_token_it_will_be_broken\n3\n4 context line which also wraps across\n";
let patch = diffy::create_patch(original, modified).to_string();

// 使用 28 列的极窄宽度
let lines = create_diff_summary(&changes, &PathBuf::from("/"), 28);
snapshot_lines_text("apply_update_block_wraps_long_lines_text", &lines);
```

### 预期输出分析
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

内容解析：
- **第2行修改**: 删除 "2"，插入超长行，折行为4行
- **第4行修改**: 删除 "4"，插入长行，折行为2行
- **长token分割**: `and_if_there_is_a_long_token_it_will_be_broken` 被强制分割

## 具体技术实现

### 文本提取函数
```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    // 将 RtLine 转换为纯文本行
    let text = lines
        .iter()
        .map(|l| {
            l.spans
                .iter()
                .map(|s| s.content.as_ref())  // 提取span内容
                .collect::<String>()          // 合并为字符串
        })
        .map(|s| s.trim_end().to_string())  // 去除行尾空格
        .collect::<Vec<_>>()
        .join("\n");
    
    assert_snapshot!(name, text);
}
```

### 折行宽度计算
```rust
// 可用宽度 = 总宽度 - 前缀宽度（行号+符号+空格）
// 28列宽度下的计算：
// - 行号列：最大行号4，宽度1
// - 符号列：1（+/-/空格）
// - 分隔空格：1
// - 可用内容宽度：28 - 4 = 24列
let available_content_cols = width.saturating_sub(prefix_cols + 1).max(1);
```

### 长token强制分割
当单词长度超过可用宽度时：

```rust
if byte_end == 0 {
    // 单个字符超过剩余宽度
    if !current_line.is_empty() {
        result.push(std::mem::take(&mut current_line));
    }
    // 强制取至少一个字符
    let ch = remaining.chars().next().unwrap();
    let ch_len = ch.len_utf8();
    current_line.push(RtSpan::styled(remaining[..ch_len].to_string(), style));
    col = ch.width().unwrap_or(1);
    remaining = &remaining[ch_len..];
}
```

在本测试中，`and_if_there_is_a_long_token_it_will_be_broken` 被分割为：
- `and_if_there_i` (14字符)
- `s_a_long_token_it_wil` (21字符)
- `l_be_broken` (11字符)

注意：实际分割点取决于每行的可用空间和字符宽度。

## 关键代码路径与文件引用

### 核心实现文件
| 文件路径 | 功能描述 |
|---------|---------|
| `codex-rs/tui/src/diff_render.rs` | 包含测试代码和 `wrap_styled_spans` 实现 |
| `codex-rs/tui/src/snapshots/codex_tui__diff_render__tests__apply_update_block_wraps_long_lines_text.snap` | 本快照文件 |

### 测试函数调用链
```
ui_snapshot_apply_update_block_wraps_long_lines_text (test)
  ├── create_diff_summary(&changes, &PathBuf::from("/"), 28)
  │   └── render_changes_block(rows, 28, cwd)
  │       └── render_change(&r.change, &mut lines, 28 - 4, lang)
  │           └── FileChange::Update 分支
  │               ├── 计算 max_line_number → 4
  │               ├── line_number_width(4) → 1
  │               └── 对每个 diff line:
  │                   └── push_wrapped_diff_line_inner_with_theme_and_color_level
  │                       ├── available_content_cols = 28 - 4 = 24
  │                       └── wrap_styled_spans(&styled, 24)
  └── snapshot_lines_text("apply_update_block_wraps_long_lines_text", &lines)
      ├── 提取每个 RtLine 的 span 内容
      ├── 合并为字符串
      ├── trim_end() 去除行尾空格
      └── join("\n") 生成最终文本
```

### 与UI快照的对比
| 特性 | UI快照 (`wraps_long_lines`) | 文本快照 (`wraps_long_lines_text`) |
|-----|---------------------------|----------------------------------|
| 宽度 | 72列 | 28列 |
| 输出 | 终端后端状态（含空格填充） | 纯文本（trim后） |
| 目的 | 验证视觉布局 | 验证内容正确性 |
| 内容 | 长单行 | 混合多行修改 |
| 可读性 | 需要可视化工具 | 直接可读 |

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|-----|------|
| `insta::assert_snapshot!` | 快照断言 |
| `ratatui::text::RtLine` | 行数据结构的文本提取 |

### 数据结构
```rust
// RtLine 结构（来自 ratatui）
pub struct Line<'a> {
    pub spans: Vec<Span<'a>>,
    pub style: Style,
    // ...
}

// Span 结构
pub struct Span<'a> {
    pub content: Cow<'a, str>,
    pub style: Style,
}
```

### 文本处理流程
```
Vec<RtLine>
    │
    ├─ 每行 ─┬─ spans.iter()
    │        │      │
    │        │      ├─ map(|s| s.content.as_ref()) → &[str]
    │        │      │
    │        │      └─ collect::<String>() → String
    │        │
    │        └─ trim_end() → String（去除行尾空格）
    │
    └─ collect::<Vec<_>>() → Vec<String>
              │
              └─ join("\n") → String（最终快照内容）
```

## 风险、边界与改进建议

### 已知风险

1. **行尾空格丢失**
   - 风险：`trim_end()` 会移除所有行尾空格
   - 影响：无法验证 intentional trailing spaces（如Markdown）
   - 建议：对于需要保留空格的场景，使用特殊标记或单独测试

2. **极窄宽度下的可读性**
   - 风险：28列下每行内容极少，实用性有限
   - 现状：这是极端边界测试，非典型使用场景

3. **字符分割语义破坏**
   - 风险：强制分割可能破坏标识符可读性
   - 示例：`it_will_be_broken` → `it_wil` + `l_be_broken`
   - 缓解：这是终端限制的必然结果

### 边界条件

| 场景 | 预期行为 | 测试状态 |
|-----|---------|---------|
| 宽度=1 | 每行仅1字符 | 未测试 |
| 宽度=0 | 至少1字符 | 未测试 |
| 空内容行 | 仅显示行号和符号 | 未测试 |
| 全空格内容 | 显示为空 | 未测试 |
| 混合Tab和空格 | Tab扩展为4空格 | 未测试 |

### 改进建议

1. **保留有意义的空格**
   ```rust
   // 当前：trim_end() 移除所有行尾空格
   // 建议：保留至少一个空格以指示续行
   fn trim_end_preserve_indent(s: &str) -> &str {
       let trimmed = s.trim_end();
       if trimmed.is_empty() {
           s  // 保留原始空格行
       } else {
           trimmed
       }
   }
   ```

2. **添加最小宽度限制**
   ```rust
   const MIN_WRAP_WIDTH: usize = 20;
   let effective_width = width.max(MIN_WRAP_WIDTH);
   ```

3. **增强测试覆盖**
   ```rust
   #[test]
   fn wrap_at_single_column() {
       // 测试极端情况：宽度=10
   }
   
   #[test]
   fn wrap_preserves_leading_spaces() {
       // 验证缩进空格不被截断
   }
   
   #[test]
   fn wrap_empty_lines() {
       // 验证空行的处理
   }
   ```

4. **添加可视化辅助**
   ```rust
   // 在文本快照中添加边界标记
   fn snapshot_lines_text_with_markers(name: &str, lines: &[RtLine], width: usize) {
       let marked: Vec<String> = lines.iter()
           .map(|l| {
               let text: String = l.spans.iter().map(|s| s.content.as_ref()).collect();
               format!("|{}|", text)  // 添加边界标记
           })
           .collect();
       assert_snapshot!(name, marked.join("\n"));
   }
   ```

5. **对比UI和文本快照**
   ```rust
   #[test]
   fn ui_and_text_snapshots_consistent() {
       // 确保同一输入在UI和文本快照中产生一致的内容
       let lines = create_diff_summary(&changes, &cwd, width);
       let ui_text = extract_text_from_backend(&lines);
       let text_snapshot = extract_text_from_lines(&lines);
       assert_eq!(ui_text, text_snapshot);
   }
   ```

6. **性能考虑**
   - 当前：每次测试都重新渲染
   - 建议：对于大量相似测试，考虑参数化测试
   ```rust
   #[test_case(28)]
   #[test_case(40)]
   #[test_case(80)]
   fn wrap_at_various_widths(width: usize) {
       // 使用 test-case crate 进行参数化测试
   }
   ```

### 相关代码审查建议
`trim_end()` 的使用虽然使快照更易读，但可能掩盖某些bug。建议：

1. 添加一个未trim的版本用于调试
2. 在CI失败时输出完整（未trim）的差异

```rust
fn snapshot_lines_text(name: &str, lines: &[RtLine<'static>]) {
    let text = /* ... */;
    let trimmed_text = text.lines().map(|l| l.trim_end()).collect::<Vec<_>>().join("\n");
    
    // 使用trimmed版本进行快照比较
    assert_snapshot!(name, trimmed_text);
    
    // 但保留原始版本用于调试
    std::env::set_var("INSTA_DEBUG_TEXT", text);
}
```
