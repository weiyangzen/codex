# prompt_args.rs 深度研究文档

## 场景与职责

`prompt_args.rs` 是 Codex TUI 中处理**自定义提示（Custom Prompts）参数解析和展开**的核心模块。自定义提示允许用户定义可重用的提示模板，通过 `/prompts:name` 命令调用，并支持变量替换。

主要场景：
1. **命名参数提示**：`/prompts:review USER=Alice BRANCH=main`
2. **位置参数提示**：`/prompts:greet Alice Bob`
3. **混合参数**：同时使用命名和位置参数
4. **文本元素保留**：在展开过程中保留占位符（placeholder）信息

## 功能点目的

### 1. 斜杠命令解析
- **功能**：解析 `/name args...` 格式的命令
- **目的**：提取命令名和参数部分

### 2. 命名参数解析
- **格式**：`KEY=value` 或 `KEY="value with spaces"`
- **解析器**：使用 `shlex` 处理引号
- **目的**：支持复杂的参数值

### 3. 位置参数解析
- **格式**：空格分隔的值
- **占位符**：`$1`, `$2`, ..., `$9`, `$ARGUMENTS`
- **目的**：简单的参数传递

### 4. 提示模板展开
- **命名占位符**：`$USER`, `$BRANCH`（大写字母+数字+下划线）
- **转义**：`$$` 表示字面量 `$`
- **目的**：将模板转换为最终文本

### 5. 文本元素跟踪
- **功能**：在展开过程中跟踪 `TextElement` 的位置
- **目的**：保留占位符信息，支持后续交互

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug)]
pub enum PromptArgsError {
    MissingAssignment { token: String },  // 缺少 = 赋值
    MissingKey { token: String },         // = 前缺少键名
}

#[derive(Debug)]
pub enum PromptExpansionError {
    Args { command: String, error: PromptArgsError },
    MissingArgs { command: String, missing: Vec<String> },
}

#[derive(Debug, Clone, PartialEq)]
pub struct PromptArg {
    pub text: String,
    pub text_elements: Vec<TextElement>,  // 参数值中的占位符
}

#[derive(Debug, Clone, PartialEq)]
pub struct PromptExpansion {
    pub text: String,
    pub text_elements: Vec<TextElement>,  // 展开结果中的占位符
}
```

### 斜杠命令解析

```rust
/// Parse a first-line slash command of the form `/name <rest>`.
pub fn parse_slash_name(line: &str) -> Option<(&str, &str, usize)> {
    let stripped = line.strip_prefix('/')?;
    let mut name_end_in_stripped = stripped.len();
    for (idx, ch) in stripped.char_indices() {
        if ch.is_whitespace() {
            name_end_in_stripped = idx;
            break;
        }
    }
    let name = &stripped[..name_end_in_stripped];
    if name.is_empty() {
        return None;
    }
    let rest_untrimmed = &stripped[name_end_in_stripped..];
    let rest = rest_untrimmed.trim_start();
    let rest_start_in_stripped = name_end_in_stripped + (rest_untrimmed.len() - rest.len());
    let rest_offset = rest_start_in_stripped + 1;  // +1 for leading '/'
    Some((name, rest, rest_offset))
}
```

### 命名参数解析流程

```rust
pub fn parse_prompt_inputs(
    rest: &str,
    text_elements: &[TextElement],
) -> Result<HashMap<String, PromptArg>, PromptArgsError> {
    let mut map = HashMap::new();
    if rest.trim().is_empty() {
        return Ok(map);
    }

    // 使用 shlex 分词，但保留 text element 信息
    for token in parse_tokens_with_elements(rest, text_elements) {
        let Some((key, value)) = token.text.split_once('=') else {
            return Err(PromptArgsError::MissingAssignment { token: token.text });
        };
        if key.is_empty() {
            return Err(PromptArgsError::MissingKey { token: token.text });
        }
        
        // 调整 text element 范围到值部分
        let value_start = key.len() + 1;
        let value_elements = token
            .text_elements
            .iter()
            .filter_map(|elem| shift_text_element_left(elem, value_start))
            .collect();
            
        map.insert(
            key.to_string(),
            PromptArg {
                text: value.to_string(),
                text_elements: value_elements,
            },
        );
    }
    Ok(map)
}
```

### 文本元素保护机制

由于 `shlex` 会重新分词，需要保护 text element 不被破坏：

```rust
fn replace_text_elements_with_sentinels(
    rest: &str,
    elements: &[TextElement],
) -> (String, Vec<ElementReplacement>) {
    let mut out = String::with_capacity(rest.len());
    let mut replacements = Vec::new();
    let mut cursor = 0;

    for (idx, elem) in elements.iter().enumerate() {
        let start = elem.byte_range.start;
        let end = elem.byte_range.end;
        out.push_str(&rest[cursor..start]);
        
        // 生成唯一哨兵
        let mut sentinel = format!("__CODEX_ELEM_{idx}__");
        while rest.contains(&sentinel) {
            sentinel.push('_');
        }
        out.push_str(&sentinel);
        
        replacements.push(ElementReplacement {
            sentinel,
            text: rest[start..end].to_string(),
            placeholder: elem.placeholder(rest).map(str::to_string),
        });
        cursor = end;
    }

    out.push_str(&rest[cursor..]);
    (out, replacements)
}
```

### 提示展开流程

```rust
pub fn expand_custom_prompt(
    text: &str,
    text_elements: &[TextElement],
    custom_prompts: &[CustomPrompt],
) -> Result<Option<PromptExpansion>, PromptExpansionError> {
    // 1. 解析斜杠命令
    let Some((name, rest, rest_offset)) = parse_slash_name(text) else {
        return Ok(None);
    };

    // 2. 确认是 prompts: 前缀
    let Some(prompt_name) = name.strip_prefix(&format!("{PROMPTS_CMD_PREFIX}:")) else {
        return Ok(None);
    };

    // 3. 查找匹配的提示
    let prompt = match custom_prompts.iter().find(|p| p.name == prompt_name) {
        Some(prompt) => prompt,
        None => return Ok(None),
    };

    // 4. 提取模板中的变量名
    let required = prompt_argument_names(&prompt.content);
    
    // 5. 调整 text elements 到参数部分
    let local_elements = /* ... */;

    // 6. 根据变量类型选择解析方式
    if !required.is_empty() {
        // 命名参数模式
        let inputs = parse_prompt_inputs(rest, &local_elements)?;
        // 检查必填变量
        let missing: Vec<String> = required
            .into_iter()
            .filter(|k| !inputs.contains_key(k))
            .collect();
        if !missing.is_empty() {
            return Err(PromptExpansionError::MissingArgs { /* ... */ });
        }
        // 展开命名占位符
        let (text, elements) = expand_named_placeholders_with_elements(&prompt.content, &inputs);
        return Ok(Some(PromptExpansion { text, text_elements: elements }));
    }

    // 7. 位置参数模式
    let pos_args = parse_positional_args(rest, &local_elements);
    Ok(Some(expand_numeric_placeholders(&prompt.content, &pos_args)))
}
```

### 命名占位符展开

```rust
fn expand_named_placeholders_with_elements(
    content: &str,
    args: &HashMap<String, PromptArg>,
) -> (String, Vec<TextElement>) {
    let mut out = String::with_capacity(content.len());
    let mut out_elements = Vec::new();
    let mut cursor = 0;
    
    // 正则匹配: $[A-Z][A-Z0-9_]*
    for m in PROMPT_ARG_REGEX.find_iter(content) {
        let start = m.start();
        let end = m.end();
        
        // 检查转义: $$USER
        if start > 0 && content.as_bytes()[start - 1] == b'$' {
            out.push_str(&content[cursor..end]);
            cursor = end;
            continue;
        }
        
        out.push_str(&content[cursor..start]);
        cursor = end;
        let key = &content[start + 1..end];  // 去掉 $
        
        if let Some(arg) = args.get(key) {
            append_arg_with_elements(&mut out, &mut out_elements, arg);
        } else {
            out.push_str(&content[start..end]);  // 保留原样
        }
    }
    out.push_str(&content[cursor..]);
    (out, out_elements)
}
```

### 位置占位符展开

```rust
pub fn expand_numeric_placeholders(content: &str, args: &[PromptArg]) -> PromptExpansion {
    let mut out = String::with_capacity(content.len());
    let mut out_elements = Vec::new();
    let mut i = 0;
    
    while let Some(off) = content[i..].find('$') {
        let j = i + off;
        out.push_str(&content[i..j]);
        let rest = &content[j..];
        let bytes = rest.as_bytes();
        
        if bytes.len() >= 2 {
            match bytes[1] {
                b'$' => { out.push_str("$$"); i = j + 2; continue; }
                b'1'..=b'9' => {
                    let idx = (bytes[1] - b'1') as usize;
                    if let Some(arg) = args.get(idx) {
                        append_arg_with_elements(&mut out, &mut out_elements, arg);
                    }
                    i = j + 2;
                    continue;
                }
                _ => {}
            }
        }
        
        // $ARGUMENTS - 连接所有参数
        if rest.len() > "ARGUMENTS".len() && rest[1..].starts_with("ARGUMENTS") {
            if !args.is_empty() {
                append_joined_args_with_elements(&mut out, &mut out_elements, args);
            }
            i = j + 1 + "ARGUMENTS".len();
            continue;
        }
        
        out.push('$');
        i = j + 1;
    }
    out.push_str(&content[i..]);
    PromptExpansion { text: out, text_elements: out_elements }
}
```

## 关键代码路径与文件引用

### 主要调用方

| 调用方 | 文件路径 | 用途 |
|--------|----------|------|
| `ChatComposer` | `codex-rs/tui/src/bottom_pane/chat_composer.rs` | 提交时展开提示 |
| `BottomPane` | `codex-rs/tui/src/bottom_pane/mod.rs` | 解析斜杠命令名 |
| `tui_app_server` | `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | 服务器端展开 |

### 集成代码

**`chat_composer.rs` 中的展开调用：**
```rust
use crate::bottom_pane::prompt_args::expand_custom_prompt;
use crate::bottom_pane::prompt_args::expand_if_numeric_with_positional_args;
use crate::bottom_pane::prompt_args::parse_slash_name;
use crate::bottom_pane::prompt_args::prompt_argument_names;
use crate::bottom_pane::prompt_args::prompt_command_with_arg_placeholders;
use crate::bottom_pane::prompt_args::prompt_has_numeric_placeholders;

// 在 prepare_submission_text 中
if let Some(expanded) = expand_custom_prompt(&text, &text_elements, &self.custom_prompts)
    .map_err(|e| SubmissionError::PromptExpansion(e.user_message()))?
{
    text = expanded.text;
    text_elements = expanded.text_elements;
}
```

**`mod.rs` 中的导出：**
```rust
mod prompt_args;
use crate::bottom_pane::prompt_args::parse_slash_name;
pub(crate) use chat_composer::ChatComposer;
```

### 辅助函数

```rust
/// 构造带参数占位符的命令文本
pub fn prompt_command_with_arg_placeholders(name: &str, args: &[String]) -> (String, usize) {
    let mut text = format!("/{PROMPTS_CMD_PREFIX}:{name}");
    let mut cursor: usize = text.len();
    for (i, arg) in args.iter().enumerate() {
        text.push_str(format!(" {arg}=\"\"").as_str());
        if i == 0 {
            cursor = text.len() - 1;  // 光标放在第一个 "" 内
        }
    }
    (text, cursor)
}

/// 检测内容是否包含数字占位符
pub fn prompt_has_numeric_placeholders(content: &str) -> bool {
    if content.contains("$ARGUMENTS") {
        return true;
    }
    // 检查 $1..$9
    /* ... */
}
```

## 依赖与外部交互

### 依赖模块

| 模块 | 用途 |
|------|------|
| `codex_protocol::custom_prompts::{CustomPrompt, PROMPTS_CMD_PREFIX}` | 自定义提示类型 |
| `codex_protocol::user_input::{ByteRange, TextElement}` | 文本元素跟踪 |
| `regex_lite::Regex` | 占位符匹配 |
| `shlex::Shlex` | Shell 风格分词 |
| `lazy_static::lazy_static` | 正则表达式静态初始化 |

### 正则表达式

```rust
lazy_static! {
    static ref PROMPT_ARG_REGEX: Regex =
        Regex::new(r"\$[A-Z][A-Z0-9_]*").unwrap_or_else(|_| std::process::abort());
}
```

匹配模式：`$` 后跟大写字母，然后是任意大写字母、数字或下划线。

### 与 TextElement 的交互

```rust
// 调整 text element 范围
fn shift_text_element_left(elem: &TextElement, offset: usize) -> Option<TextElement> {
    if elem.byte_range.end <= offset {
        return None;
    }
    let start = elem.byte_range.start.saturating_sub(offset);
    let end = elem.byte_range.end.saturating_sub(offset);
    (start < end).then_some(elem.map_range(|_| ByteRange { start, end }))
}

// 追加参数并调整元素范围
fn append_arg_with_elements(
    out: &mut String,
    out_elements: &mut Vec<TextElement>,
    arg: &PromptArg,
) {
    let start = out.len();
    out.push_str(&arg.text);
    if arg.text_elements.is_empty() {
        return;
    }
    out_elements.extend(arg.text_elements.iter().map(|elem| {
        elem.map_range(|range| ByteRange {
            start: start + range.start,
            end: start + range.end,
        })
    }));
}
```

## 风险、边界与改进建议

### 已知风险

1. **正则表达式性能**
   - 长文本中的多次正则匹配可能影响性能
   - 当前使用 `regex_lite`，权衡了性能和二进制大小

2. **shlex 分词限制**
   - `shlex` 是类 Unix shell 的分词器
   - Windows 路径可能处理不正确（如反斜杠）

3. **占位符冲突**
   - 用户内容中可能意外包含 `$VAR` 格式
   - 转义机制 `$$` 需要用户知晓

4. **递归展开风险**
   - 如果参数值包含占位符，可能导致意外行为
   - 当前实现单次展开，不处理递归

### 边界条件

| 场景 | 行为 |
|------|------|
| 缺少必填参数 | 返回 `MissingArgs` 错误 |
| 参数格式错误 | 返回 `Args` 错误 |
| 未知提示名 | 返回 `Ok(None)` |
| 非 prompts: 命令 | 返回 `Ok(None)` |
| 空参数值 | 允许，展开为空字符串 |
| 多余参数 | 忽略（命名模式）或按位置使用 |

### 测试覆盖

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn expand_arguments_basic() {
        // 测试基本命名参数展开
    }

    #[test]
    fn quoted_values_ok() {
        // 测试带空格的引号值
    }

    #[test]
    fn invalid_arg_token_reports_error() {
        // 测试缺少 = 的错误报告
    }

    #[test]
    fn missing_required_args_reports_error() {
        // 测试缺少必填参数
    }

    #[test]
    fn escaped_placeholder_is_ignored() {
        // 测试 $$ 转义
    }

    #[test]
    fn positional_args_treat_placeholder_with_spaces_as_single_token() {
        // 测试带空格的占位符作为单个 token
    }
}
```

### 改进建议

1. **更好的错误消息**
   - 提供类似 "Did you mean X?" 的建议
   - 显示可用参数列表

2. **类型检查**
   - 支持参数类型注解（如 `USER: string`, `COUNT: number`）
   - 在展开前验证参数类型

3. **默认值支持**
   - 支持模板中的默认值语法：`${USER:default}`
   - 减少必填参数数量

4. **条件展开**
   - 支持条件块：`{{#if USER}}Hello {{USER}}{{/if}}`
   - 更复杂的模板逻辑

5. **循环支持**
   - 支持 `$ARGUMENTS` 的自定义分隔符
   - 支持循环块处理列表参数

6. **性能优化**
   - 缓存解析后的提示模板
   - 避免每次提交时重新解析

7. **更好的转义支持**
   - 支持更多转义序列（如 `\n`, `\t`）
   - 支持 Unicode 转义

8. **文档生成**
   - 从提示模板自动生成帮助文档
   - 显示可用变量和示例

### 相关文件

- `codex-rs/tui/src/bottom_pane/chat_composer.rs`：主要调用方
- `codex-rs/tui/src/bottom_pane/mod.rs`：模块集成
- `codex-rs/protocol/src/custom_prompts.rs`：自定义提示类型定义
- `codex-rs/protocol/src/user_input.rs`：TextElement 定义
