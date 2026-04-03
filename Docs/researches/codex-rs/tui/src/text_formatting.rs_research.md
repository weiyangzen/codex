# text_formatting.rs 深度研究文档

## 场景与职责

`text_formatting.rs` 是 Codex TUI 中负责**文本格式化和处理**的通用工具模块。它提供了多种文本处理功能，包括首字母大写、JSON 格式化、文本截断、路径截断和列表连接等。

### 核心职责

1. **首字母大写**：将字符串首字母转为大写
2. **JSON 紧凑格式化**：将 JSON 格式化为适合终端显示的紧凑单行格式
3. **文本截断**：基于 grapheme 的 Unicode 安全文本截断
4. **路径截断**：智能截断长路径，保留首尾重要部分
5. **列表连接**：使用英语语法规则连接列表项
6. **工具结果格式化**：为工具调用结果提供格式化截断

### 使用场景

- 状态指示器中的详情文本格式化
- 聊天消息中的代码块 JSON 格式化
- 文件路径显示优化
- 列表项的友好展示
- 工具调用结果的截断显示

---

## 功能点目的

### 1. 首字母大写 (`capitalize_first`)

```rust
pub(crate) fn capitalize_first(input: &str) -> String
```

将字符串的第一个字符转为大写，其余保持不变。

### 2. 工具结果格式化 (`format_and_truncate_tool_result`)

```rust
pub(crate) fn format_and_truncate_tool_result(
    text: &str,
    max_lines: usize,
    line_width: usize,
) -> String
```

- 如果文本是有效 JSON，先进行紧凑格式化
- 然后基于 grapheme 数量截断
- 用于在有限空间内显示工具调用结果

### 3. JSON 紧凑格式化 (`format_json_compact`)

```rust
pub(crate) fn format_json_compact(text: &str) -> Option<String>
```

将 JSON 格式化为紧凑单行格式，保留适当的空格以便 ratatui 换行：
- 输入：`{"a":"b",c:["d","e"]}`
- 输出：`{"a": "b", "c": ["d", "e"]}`

**设计原因**：ratatui 的换行只能在空白处分割，默认 JSON 格式（无空格）会导致无法换行。

### 4. 文本截断 (`truncate_text`)

```rust
pub(crate) fn truncate_text(text: &str, max_graphemes: usize) -> String
```

基于 Unicode grapheme 的截断，避免截断多码点字符：
- 如果文本超过限制，添加 "..." 后缀
- 如果限制小于 3，直接截断不添加后缀

### 5. 路径智能截断 (`center_truncate_path`)

```rust
pub(crate) fn center_truncate_path(path: &str, max_width: usize) -> String
```

智能截断长路径：
- 保留路径的开头和结尾部分
- 中间使用 "…" 连接
- 优先保留文件名和父目录
- 支持单个段落的头部截断

### 6. 列表连接 (`proper_join`)

```rust
pub(crate) fn proper_join<T: AsRef<str>>(items: &[T]) -> String
```

使用英语语法连接列表：
- `[]` → `""`
- `["apple"]` → `"apple"`
- `["apple", "banana"]` → `"apple and banana"`
- `["apple", "banana", "cherry"]` → `"apple, banana and cherry"`

---

## 具体技术实现

### 关键流程

#### 1. JSON 紧凑格式化流程

```rust
pub(crate) fn format_json_compact(text: &str) -> Option<String> {
    // 1. 解析 JSON
    let json = serde_json::from_str::<serde_json::Value>(text).ok()?;
    let json_pretty = serde_json::to_string_pretty(&json).unwrap_or_else(|_| json.to_string());

    // 2. 字符级处理，将多行 pretty 格式转为单行
    let mut result = String::new();
    let mut chars = json_pretty.chars().peekable();
    let mut in_string = false;
    let mut escape_next = false;

    while let Some(ch) = chars.next() {
        match ch {
            '"' if !escape_next => { in_string = !in_string; result.push(ch); }
            '\\' if in_string => { escape_next = !escape_next; result.push(ch); }
            '\n' | '\r' if !in_string => { /* 跳过 */ }
            ' ' | '\t' if !in_string => {
                // 在 : 和 , 后添加空格（如果下一个不是 } 或 ]）
                if let Some(&next_ch) = chars.peek()
                    && let Some(last_ch) = result.chars().last()
                    && (last_ch == ':' || last_ch == ',')
                    && !matches!(next_ch, '}' | ']')
                {
                    result.push(' ');
                }
            }
            _ => { result.push(ch); }
        }
    }
    Some(result)
}
```

#### 2. 路径截断算法

```rust
pub(crate) fn center_truncate_path(path: &str, max_width: usize) -> String {
    // 1. 快速路径：如果路径已适合，直接返回
    if UnicodeWidthStr::width(path) <= max_width { return path.to_string(); }

    // 2. 分割路径为段落
    let sep = std::path::MAIN_SEPARATOR;
    let raw_segments: Vec<&str> = path.split(sep).collect();

    // 3. 生成候选组合（左段数，右段数）
    let mut combos: Vec<(usize, usize)> = Vec::new();
    for left in 1..=segment_count {
        let min_right = if left == segment_count { 0 } else { 1 };
        for right in min_right..=(segment_count - left) {
            combos.push((left, right));
        }
    }

    // 4. 优先保留后缀（文件名）
    let desired_suffix = std::cmp::min(2, segment_count - 1);
    let (prioritized, fallback): partition combos...

    // 5. 尝试每个组合，找到最适合的
    for (left_count, right_count) in prioritized.chain(fallback) {
        // 构建候选路径，必要时添加省略号
        // 如果单个段落过长，进行头部截断
        if let Some(candidate) = fit_segments(&mut segments, allow_front_truncate) {
            return candidate;
        }
    }

    // 6. 回退：对整个路径进行头部截断
    front_truncate(path, max_width)
}
```

#### 3. Grapheme 截断

```rust
pub(crate) fn truncate_text(text: &str, max_graphemes: usize) -> String {
    let mut graphemes = text.grapheme_indices(true);

    // 检查是否超过限制
    if let Some((byte_index, _)) = graphemes.nth(max_graphemes) {
        // 超过限制，需要截断
        if max_graphemes >= 3 {
            // 截断到 max_graphemes - 3，为 "..." 留出空间
            let mut truncate_graphemes = text.grapheme_indices(true);
            if let Some((truncate_byte_index, _)) = truncate_graphemes.nth(max_graphemes - 3) {
                format!("{}...", &text[..truncate_byte_index])
            } else { text.to_string() }
        } else {
            // 限制太小，直接截断不添加后缀
            text[..byte_index].to_string()
        }
    } else {
        // 未超过限制，返回原文
        text.to_string()
    }
}
```

### 依赖的 Unicode crate

| Crate | 用途 |
|-------|------|
| `unicode_segmentation::UnicodeSegmentation` | Grapheme 分割 |
| `unicode_width::UnicodeWidthChar` | 字符显示宽度 |
| `unicode_width::UnicodeWidthStr` | 字符串显示宽度 |

---

## 关键代码路径与文件引用

### 内部调用方

| 文件 | 用途 |
|------|------|
| `status_indicator_widget.rs` | `capitalize_first` 用于详情文本 |
| `history_cell.rs` | 工具结果格式化 |
| `resume_picker.rs` | 路径显示 |
| `chatwidget.rs` | 列表连接 |
| `status/helpers.rs` | 文本格式化 |
| `status/rate_limits.rs` | 格式化显示 |
| `skills_helpers.rs` | 技能相关格式化 |
| `multi_agents.rs` | 多 Agent 格式化 |
| `bottom_pane/multi_select_picker.rs` | 选择器格式化 |
| `bottom_pane/mcp_server_elicitation.rs` | MCP 表单格式化 |
| `bottom_pane/skill_popup.rs` | 技能弹窗格式化 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `unicode_segmentation` | Unicode grapheme 处理 |
| `unicode_width` | Unicode 显示宽度计算 |
| `serde_json` | JSON 解析和格式化 |

---

## 依赖与外部交互

### Unicode 处理链

```
text_formatting.rs
    ├── unicode_segmentation::UnicodeSegmentation
    │       └── grapheme_indices(true) - 获取 grapheme 边界
    │
    └── unicode_width
            ├── UnicodeWidthStr::width() - 字符串显示宽度
            └── UnicodeWidthChar::width() - 字符显示宽度
```

### JSON 处理流程

```
format_json_compact
    ├── serde_json::from_str - 解析 JSON
    ├── serde_json::to_string_pretty - 美化输出
    └── 自定义字符处理 - 转为紧凑单行
```

### 路径处理流程

```
center_truncate_path
    ├── std::path::MAIN_SEPARATOR - 系统路径分隔符
    ├── UnicodeWidthStr::width - 宽度计算
    └── 迭代尝试不同组合 - 找到最佳截断方案
```

---

## 风险、边界与改进建议

### 已知风险

1. **Grapheme 与单元格不匹配**：`truncate_text` 使用 grapheme 计数，但终端单元格宽度可能不同（如全角字符）
2. **JSON 格式化复杂度**：自定义 JSON 格式化逻辑复杂，容易出错
3. **路径截断性能**：最坏情况下需要尝试 O(n²) 种组合

### 边界情况

1. **空字符串**：所有函数都正确处理空输入
2. **零宽度限制**：返回空字符串或适当处理
3. **无效 JSON**：`format_json_compact` 返回 `None`
4. **单一段落路径**：直接进行头部截断
5. **Unicode 组合字符**：`capitalize_first` 正确处理多码点首字符

### 测试覆盖

测试文件包含全面的测试用例：

| 测试 | 描述 |
|------|------|
| `test_truncate_text` | 基本截断 |
| `test_truncate_empty_string` | 空字符串处理 |
| `test_truncate_max_graphemes_zero` | 零限制 |
| `test_truncate_emoji` | Emoji 截断 |
| `test_truncate_unicode_combining_characters` | 组合字符 |
| `test_format_json_compact_simple_object` | 简单对象 |
| `test_format_json_compact_nested_object` | 嵌套对象 |
| `test_center_truncate_doesnt_truncate_short_path` | 短路径 |
| `test_center_truncate_truncates_long_path` | 长路径截断 |
| `test_center_truncate_handles_long_segment` | 长段落 |
| `test_proper_join` | 列表连接 |

### 改进建议

1. **性能优化**：
   - 路径截断使用更高效的算法
   - 缓存常用路径的截断结果

2. **功能增强**：
   - 支持更多语言的列表连接（i18n）
   - 添加 URL 截断功能
   - 支持可配置的 JSON 格式化选项

3. **可访问性**：
   - 为截断文本添加屏幕阅读器提示
   - 支持复制完整路径（即使显示截断）

4. **代码质量**：
   - 将路径截断逻辑拆分为更小的函数
   - 添加更多边界情况的测试

5. **国际化**：
   - `proper_join` 目前使用英语语法，考虑支持其他语言
   - 路径显示考虑 RTL 语言

### 代码特点

- **Unicode 安全**：所有操作都考虑 Unicode 特性
- **防御性编程**：处理各种边界情况
- **文档完善**：复杂函数有详细注释
- **测试充分**：覆盖主要功能和边界情况

### 相关文件

- 调用此模块的各组件文件
- `wrapping.rs`：文本换行相关功能
- `line_truncation.rs`：行截断相关功能
