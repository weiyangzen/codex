# TextFormatting 研究文档

## 场景与职责

`text_formatting.rs` 是 Codex TUI 的文本格式化工具模块，提供多种文本处理功能：

1. **字符串首字母大写**：将字符串首字母转换为大写
2. **工具结果格式化与截断**：格式化并截断工具输出以适应显示区域
3. **JSON 紧凑格式化**：将 JSON 格式化为适合终端显示的紧凑单行格式
4. **文本截断**：基于 grapheme 的 Unicode 安全文本截断
5. **路径中心截断**：智能截断长路径，保留首尾部分
6. **英文列表连接**：使用正确的英文标点连接列表项

该模块位于 `codex-rs/tui_app_server/src/text_formatting.rs`，是文本渲染的基础工具。

## 功能点目的

### 1. 首字母大写

```rust
pub(crate) fn capitalize_first(input: &str) -> String
```

用于状态指示器的详情文本，将工具输出或状态消息的首字母大写，提高可读性。

### 2. 工具结果格式化与截断

```rust
pub(crate) fn format_and_truncate_tool_result(
    text: &str,
    max_lines: usize,
    line_width: usize,
) -> String
```

处理工具执行结果的显示：
- 如果是有效 JSON，先格式化为紧凑格式
- 然后截断到指定的 grapheme 数量
- 保留 `(max_lines * line_width) - max_lines` 个 graphemes

### 3. JSON 紧凑格式化

```rust
pub(crate) fn format_json_compact(text: &str) -> Option<String>
```

解决 ratatui 换行限制的关键功能：
- ratatui 只能在空白字符处换行
- 标准 serde_json 紧凑格式可能产生无空格的长字符串
- 此函数在 `:` 和 `,` 后添加空格，使 ratatui 能够正确换行

**转换示例：**
```
输入:  {"a":"b",c:["d","e"]}
输出: {"a": "b", "c": ["d", "e"]}
```

### 4. Unicode 安全文本截断

```rust
pub(crate) fn truncate_text(text: &str, max_graphemes: usize) -> String
```

基于 grapheme 的截断，避免在多字节字符中间截断：
- 使用 `unicode_segmentation` 正确识别 grapheme 边界
- 如果文本超过限制，添加 "..." 省略号
- 当 `max_graphemes < 3` 时，直接截断不添加省略号

### 5. 路径中心截断

```rust
pub(crate) fn center_truncate_path(path: &str, max_width: usize) -> String
```

智能截断长路径：
- 保留路径的开头和结尾部分
- 在中间插入省略号
- 优先保留文件名和前几级目录
- 处理单个超长段落的 front-truncate

**算法核心：**
1. 分割路径为段落
2. 尝试不同的首尾段落组合
3. 优先保留更多尾部段落（通常包含文件名）
4. 必要时对超长段落进行 front-truncate

### 6. 英文列表连接

```rust
pub(crate) fn proper_join<T: AsRef<str>>(items: &[T]) -> String
```

使用正确的英文标点连接列表：
- 空列表: `""`
- 单一项: `"apple"`
- 两项: `"apple and banana"`
- 三项及以上: `"apple, banana and cherry"`

## 具体技术实现

### JSON 紧凑格式化核心逻辑

```rust
pub(crate) fn format_json_compact(text: &str) -> Option<String> {
    let json = serde_json::from_str::<serde_json::Value>(text).ok()?;
    let json_pretty = serde_json::to_string_pretty(&json).unwrap_or_else(|_| json.to_string());

    let mut result = String::new();
    let mut chars = json_pretty.chars().peekable();
    let mut in_string = false;
    let mut escape_next = false;

    while let Some(ch) = chars.next() {
        match ch {
            '"' if !escape_next => {
                in_string = !in_string;
                result.push(ch);
            }
            '\\' if in_string => {
                escape_next = !escape_next;
                result.push(ch);
            }
            '\n' | '\r' if !in_string => {
                // 跳过字符串外的换行
            }
            ' ' | '\t' if !in_string => {
                // 在 : 和 , 后添加空格（如果后面不是 } 或 ]）
                if let Some(&next_ch) = chars.peek()
                    && let Some(last_ch) = result.chars().last()
                    && (last_ch == ':' || last_ch == ',')
                    && !matches!(next_ch, '}' | ']')
                {
                    result.push(' ');
                }
            }
            _ => {
                if escape_next && in_string {
                    escape_next = false;
                }
                result.push(ch);
            }
        }
    }
    Some(result)
}
```

### 路径中心截断核心逻辑

```rust
pub(crate) fn center_truncate_path(path: &str, max_width: usize) -> String {
    // 1. 解析路径段落
    let sep = std::path::MAIN_SEPARATOR;
    let has_leading_sep = path.starts_with(sep);
    let has_trailing_sep = path.ends_with(sep);
    let mut raw_segments: Vec<&str> = path.split(sep).collect();
    // 清理空段落...

    // 2. 生成候选组合（左段数，右段数）
    let mut combos: Vec<(usize, usize)> = Vec::new();
    for left in 1..=segment_count {
        let min_right = if left == segment_count { 0 } else { 1 };
        for right in min_right..=(segment_count - left) {
            combos.push((left, right));
        }
    }

    // 3. 优先保留至少 2 个尾部段落
    let desired_suffix = std::cmp::min(2, segment_count - 1);
    let mut prioritized: Vec<(usize, usize)> = Vec::new();
    let mut fallback: Vec<(usize, usize)> = Vec::new();
    for combo in combos {
        if combo.1 >= desired_suffix {
            prioritized.push(combo);
        } else {
            fallback.push(combo);
        }
    }

    // 4. 排序：优先更多左段，然后更多右段
    let sort_combos = |items: &mut Vec<(usize, usize)>| {
        items.sort_by(|(left_a, right_a), (left_b, right_b)| {
            left_b.cmp(left_a)
                .then_with(|| right_b.cmp(right_a))
                .then_with(|| (left_b + right_b).cmp(&(left_a + right_a)))
        });
    };

    // 5. 尝试每个组合，必要时 front-truncate
    // ...
}
```

### Unicode 安全截断

```rust
pub(crate) fn truncate_text(text: &str, max_graphemes: usize) -> String {
    let mut graphemes = text.grapheme_indices(true);

    if let Some((byte_index, _)) = graphemes.nth(max_graphemes) {
        // 需要截断
        if max_graphemes >= 3 {
            // 截断到 max_graphemes - 3 并添加 "..."
            let mut truncate_graphemes = text.grapheme_indices(true);
            if let Some((truncate_byte_index, _)) = truncate_graphemes.nth(max_graphemes - 3) {
                let truncated = &text[..truncate_byte_index];
                format!("{truncated}...")
            } else {
                text.to_string()
            }
        } else {
            // max_graphemes < 3，直接截断不添加省略号
            let truncated = &text[..byte_index];
            truncated.to_string()
        }
    } else {
        // 不需要截断
        text.to_string()
    }
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/text_formatting.rs` (580 行)

### 依赖模块
| 模块 | 用途 |
|------|------|
| `unicode_segmentation` | Grapheme 边界检测 |
| `unicode_width` | 字符显示宽度计算 |
| `serde_json` | JSON 解析和格式化 |

### 调用方
- `status_indicator_widget.rs` - 详情文本格式化
- 工具结果渲染 - 截断和格式化输出
- 路径显示 - 智能路径截断

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `unicode-segmentation` | Unicode grapheme 簇边界 |
| `unicode-width` | 字符显示宽度 |
| `serde_json` | JSON 处理 |

### 内部依赖
无直接内部依赖，是纯工具模块。

## 风险、边界与改进建议

### 潜在风险

1. **JSON 格式化复杂度**：`format_json_compact` 使用状态机解析 JSON，可能无法处理所有边缘情况。

2. **路径截断性能**：路径中心截断生成所有可能的组合，对于非常深的路径可能有性能问题。

3. **平台路径分隔符**：使用 `std::path::MAIN_SEPARATOR`，但在非标准路径格式上可能行为异常。

### 边界情况

1. **空字符串**：所有函数都正确处理空字符串。

2. **零宽度限制**：`max_width == 0` 时返回空字符串。

3. **Unicode 组合字符**：`truncate_text` 使用 grapheme 边界，正确处理组合字符。

4. **表情符号**：测试确认正确处理多码点表情符号。

### 测试覆盖

模块包含全面的单元测试（约 40 个测试）：
- `test_truncate_text` - 基本截断
- `test_truncate_empty_string` - 空字符串
- `test_truncate_max_graphemes_zero/one/two/three` - 边界值
- `test_truncate_emoji` - 表情符号处理
- `test_truncate_unicode_combining_characters` - 组合字符
- `test_format_json_compact_*` - JSON 格式化各种场景
- `test_center_truncate_*` - 路径截断各种场景
- `test_proper_join` - 列表连接

### 改进建议

1. **缓存路径截断结果**：对于重复出现的相同路径，缓存截断结果。

2. **配置化 JSON 空格**：允许配置 JSON 格式化后的空格数量。

3. **更多列表格式**：`proper_join` 当前使用牛津逗号变体，可支持其他格式。

4. **路径截断优化**：对于深层路径，使用更高效的算法避免生成所有组合。

5. **支持其他语言**：当前 `proper_join` 针对英文优化，可考虑国际化支持。

6. **流式处理**：对于非常大的文本，考虑支持流式截断而不是一次性处理。
