# prompt_args.rs 深入研究

## 场景与职责

`prompt_args.rs` 是 TUI 应用服务器中负责**自定义提示词（Custom Prompt）参数解析和展开**的核心模块。该模块处理用户通过 `/prompts:name` 命令调用自定义提示词时的参数绑定、验证和模板展开。

### 核心功能

1. **斜杠命令解析**：解析 `/prompts:name key=value ...` 格式的命令
2. **参数提取**：支持命名参数（`$USER`）和位置参数（`$1`, `$ARGUMENTS`）
3. **模板展开**：将参数值填充到提示词模板中
4. **文本元素跟踪**：维护 `TextElement` 范围信息，支持富文本渲染

### 架构定位

该模块位于输入处理层，被 `ChatComposer` 调用以在消息提交前展开自定义提示词。它与 `codex_protocol::custom_prompts` 模块紧密协作，实现客户端侧的提示词处理。

---

## 功能点目的

### 1. 自定义提示词调用

用户可以通过 `/prompts:prompt_name arg1 arg2` 或 `/prompts:prompt_name KEY=value` 的方式调用预定义的提示词模板。

### 2. 命名参数支持

提示词模板使用 `$UPPERCASE` 格式定义占位符：
```
Review $USER changes on $BRANCH
```
调用时：`/prompts:review USER=Alice BRANCH=main`

### 3. 位置参数支持

提示词模板使用 `$1` 到 `$9` 和 `$ARGUMENTS`：
```
Explain $1 in the context of $2
```
调用时：`/prompts:explain function_name codebase`

### 4. 带空格的参数值

使用引号支持包含空格的参数值：
```
/prompts:greet USER="Alice Smith"
```

### 5. 富文本元素保留

在参数解析过程中维护 `TextElement` 信息，确保图像占位符等特殊元素在展开后仍能正确渲染。

---

## 具体技术实现

### 核心数据结构

```rust
/// 参数解析错误
#[derive(Debug)]
pub enum PromptArgsError {
    MissingAssignment { token: String },  // 缺少 = 赋值
    MissingKey { token: String },         // 键名为空
}

/// 提示词展开错误
#[derive(Debug)]
pub enum PromptExpansionError {
    Args { command: String, error: PromptArgsError },
    MissingArgs { command: String, missing: Vec<String> },
}

/// 解析后的参数
#[derive(Debug, Clone, PartialEq)]
pub struct PromptArg {
    pub text: String,
    pub text_elements: Vec<TextElement>,  // 相对于 text 的范围
}

/// 展开后的提示词
#[derive(Debug, Clone, PartialEq)]
pub struct PromptExpansion {
    pub text: String,
    pub text_elements: Vec<TextElement>,
}
```

### 斜杠命令解析

```rust
/// 解析 /name rest 格式
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

### 占位符提取

```rust
lazy_static! {
    static ref PROMPT_ARG_REGEX: Regex =
        Regex::new(r"\$[A-Z][A-Z0-9_]*").unwrap_or_else(|_| std::process::abort());
}

/// 从提示词内容中提取占位符名称（去重，按首次出现顺序）
pub fn prompt_argument_names(content: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut names = Vec::new();
    for m in PROMPT_ARG_REGEX.find_iter(content) {
        // 跳过转义的 $$VAR
        if m.start() > 0 && content.as_bytes()[m.start() - 1] == b'$' {
            continue;
        }
        let name = &content[m.start() + 1..m.end()];
        if name == "ARGUMENTS" {  // 排除特殊聚合占位符
            continue;
        }
        let name = name.to_string();
        if seen.insert(name.clone()) {
            names.push(name);
        }
    }
    names
}
```

### 命名参数解析

```rust
/// 解析 key=value 格式的参数
pub fn parse_prompt_inputs(
    rest: &str,
    text_elements: &[TextElement],
) -> Result<HashMap<String, PromptArg>, PromptArgsError> {
    let mut map = HashMap::new();
    if rest.trim().is_empty() {
        return Ok(map);
    }

    for token in parse_tokens_with_elements(rest, text_elements) {
        let Some((key, value)) = token.text.split_once('=') else {
            return Err(PromptArgsError::MissingAssignment { token: token.text });
        };
        if key.is_empty() {
            return Err(PromptArgsError::MissingKey { token: token.text });
        }
        // 调整 text_elements 到 value-only 坐标空间
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

### 文本元素处理

```rust
/// 将 text element 向左偏移，用于提取 value 部分的元素
fn shift_text_element_left(elem: &TextElement, offset: usize) -> Option<TextElement> {
    if elem.byte_range.end <= offset {
        return None;
    }
    let start = elem.byte_range.start.saturating_sub(offset);
    let end = elem.byte_range.end.saturating_sub(offset);
    (start < end).then_some(elem.map_range(|_| ByteRange { start, end }))
}
```

### 带文本元素的 Token 解析

核心挑战：在使用 `shlex` 分割引号包围的 token 时，需要保留 `TextElement` 的范围信息。

解决方案：使用哨兵标记（sentinel）替换文本元素范围，分割后再恢复：

```rust
#[derive(Debug, Clone)]
struct ElementReplacement {
    sentinel: String,       // 唯一标记，如 "__CODEX_ELEM_0__"
    text: String,           // 原始文本
    placeholder: Option<String>,
}

/// 将文本元素替换为哨兵标记
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
        let mut sentinel = format!("__CODEX_ELEM_{idx}__");
        // 确保哨兵不与用户内容冲突
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

/// 在 shlex 分割后的 token 中恢复文本元素
fn apply_replacements_to_token(
    token: String,
    replacements: &[ElementReplacement],
) -> PromptArg {
    // ... 恢复原始文本和 text_elements
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
    
    for m in PROMPT_ARG_REGEX.find_iter(content) {
        let start = m.start();
        let end = m.end();
        // 跳过转义的 $$
        if start > 0 && content.as_bytes()[start - 1] == b'$' {
            out.push_str(&content[cursor..end]);
            cursor = end;
            continue;
        }
        out.push_str(&content[cursor..start]);
        cursor = end;
        let key = &content[start + 1..end];
        if let Some(arg) = args.get(key) {
            append_arg_with_elements(&mut out, &mut out_elements, arg);
        } else {
            out.push_str(&content[start..end]);  // 保留未匹配的占位符
        }
    }
    out.push_str(&content[cursor..]);
    (out, out_elements)
}
```

### 位置占位符展开

```rust
/// 展开 $1..$9 和 $ARGUMENTS
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
                b'$' => {
                    out.push_str("$$");  // 转义序列 -> 单个 $
                    i = j + 2;
                    continue;
                }
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

### 主展开函数

```rust
pub fn expand_custom_prompt(
    text: &str,
    text_elements: &[TextElement],
    custom_prompts: &[CustomPrompt],
) -> Result<Option<PromptExpansion>, PromptExpansionError> {
    let Some((name, rest, rest_offset)) = parse_slash_name(text) else {
        return Ok(None);
    };

    // 只处理 /prompts: 前缀
    let Some(prompt_name) = name.strip_prefix(&format!("{PROMPTS_CMD_PREFIX}:")) else {
        return Ok(None);
    };

    let prompt = match custom_prompts.iter().find(|p| p.name == prompt_name) {
        Some(prompt) => prompt,
        None => return Ok(None),
    };

    // 提取占位符并调整 text_elements 到 rest 坐标空间
    let required = prompt_argument_names(&prompt.content);
    let local_elements: Vec<TextElement> = text_elements
        .iter()
        .filter_map(|elem| {
            let mut shifted = shift_text_element_left(elem, rest_offset)?;
            if shifted.byte_range.start >= rest.len() {
                return None;
            }
            let end = shifted.byte_range.end.min(rest.len());
            shifted.byte_range.end = end;
            (shifted.byte_range.start < shifted.byte_range.end).then_some(shifted)
        })
        .collect();

    if !required.is_empty() {
        // 命名参数路径
        let inputs = parse_prompt_inputs(rest, &local_elements).map_err(|error| {
            PromptExpansionError::Args { command: format!("/{name}"), error }
        })?;
        let missing: Vec<String> = required
            .into_iter()
            .filter(|k| !inputs.contains_key(k))
            .collect();
        if !missing.is_empty() {
            return Err(PromptExpansionError::MissingArgs {
                command: format!("/{name}"),
                missing,
            });
        }
        let (text, elements) = expand_named_placeholders_with_elements(&prompt.content, &inputs);
        return Ok(Some(PromptExpansion { text, text_elements: elements }));
    }

    // 位置参数路径
    let pos_args = parse_positional_args(rest, &local_elements);
    Ok(Some(expand_numeric_placeholders(&prompt.content, &pos_args)))
}
```

---

## 关键代码路径与文件引用

### 核心实现文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui_app_server/src/bottom_pane/prompt_args.rs` | 参数解析和模板展开实现 |
| `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs` | 调用者，集成到输入处理 |

### 依赖模块

| 模块 | 用途 |
|------|------|
| `codex_protocol::custom_prompts` | `CustomPrompt` 定义和 `PROMPTS_CMD_PREFIX` |
| `codex_protocol::user_input` | `TextElement`, `ByteRange` |
| `shlex` | Shell 风格的引号分割 |
| `regex_lite` | 占位符正则匹配 |

### 集成点（ChatComposer）

```rust
// 在 chat_composer.rs 中
use crate::bottom_pane::prompt_args::expand_custom_prompt;

// 提交前展开自定义提示词
fn maybe_expand_custom_prompt(&mut self, text: &str) -> Option<String> {
    match expand_custom_prompt(text, &self.text_elements, &self.custom_prompts) {
        Ok(Some(expansion)) => Some(expansion.text),
        Ok(None) => None,  // 不是自定义提示词调用
        Err(e) => {
            self.show_error(e.user_message());
            None
        }
    }
}
```

### 命令构建辅助

```rust
/// 构建带参数占位符的提示词命令
/// 返回 (命令文本, 光标位置)
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
```

---

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `shlex` | Shell 风格的引号分割 |
| `regex_lite` | 轻量级正则表达式 |
| `lazy_static` | 静态正则编译 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `codex_protocol::custom_prompts` | `CustomPrompt`, `PROMPTS_CMD_PREFIX` |
| `codex_protocol::user_input` | `TextElement`, `ByteRange` |

### 协议类型

```rust
// codex_protocol::custom_prompts
pub const PROMPTS_CMD_PREFIX: &str = "prompts";

pub struct CustomPrompt {
    pub name: String,
    pub path: PathBuf,
    pub content: String,
    pub description: Option<String>,
    pub argument_hint: Option<String>,
}

// codex_protocol::user_input
pub struct TextElement {
    pub byte_range: ByteRange,
    placeholder: Option<String>,
}

pub struct ByteRange {
    pub start: usize,
    pub end: usize,
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **正则表达式复杂性**
   - 占位符匹配使用 `$[A-Z][A-Z0-9_]*`，可能无法覆盖所有有效变量名
   - 转义处理（`$$`）可能在边界情况下出错

2. **TextElement 范围计算**
   - 多次坐标空间转换（原始文本 → rest → token → value）容易出错
   - 中文字符等多字节字符可能导致范围偏移错误

3. **shlex 分割限制**
   - `shlex` 的引号处理可能与用户预期不同
   - 嵌套引号或复杂转义序列可能解析错误

4. **哨兵冲突**
   - 虽然会动态扩展哨兵字符串避免冲突，但理论上仍存在冲突可能

### 边界条件

| 边界 | 处理 |
|------|------|
| 空参数列表 | 返回空展开或保留原模板 |
| 缺少必需参数 | 返回 `MissingArgs` 错误 |
| 无效 key=value 格式 | 返回 `MissingAssignment` 错误 |
| 空键名 | 返回 `MissingKey` 错误 |
| 未匹配的 `$N` | 保留原样（不替换） |
| 转义 `$$` | 展开为单个 `$` |
| 超出 $1..$9 | 忽略（不替换） |

### 测试覆盖

模块包含全面的单元测试：
- `expand_arguments_basic`：基本命名参数展开
- `quoted_values_ok`：引号包围的值
- `invalid_arg_token_reports_error`：无效参数格式错误
- `missing_required_args_reports_error`：缺少必需参数错误
- `escaped_placeholder_is_ignored`：转义占位符处理
- `escaped_placeholder_remains_literal`：转义保留原样
- `positional_args_treat_placeholder_with_spaces_as_single_token`：位置参数与占位符
- `extract_positional_args_shifts_element_offsets_into_args_str`：TextElement 偏移调整
- `key_value_args_treat_placeholder_with_spaces_as_single_token`：key=value 与占位符
- `positional_args_allow_placeholder_inside_quotes`：引号内的占位符
- `key_value_args_allow_placeholder_inside_quotes`：key=value 引号内的占位符

### 改进建议

1. **增强错误信息**
   - 提供参数位置信息（第几个参数出错）
   - 建议可能的参数名（拼写纠错）

2. **支持更多占位符类型**
   - 环境变量展开（`$ENV_VAR`）
   - 默认值语法（`${USER:-default}`）
   - 条件展开（`${USER:+present}`）

3. **性能优化**
   - 缓存已编译的正则表达式（已部分实现）
   - 对频繁使用的提示词预计算占位符位置

4. **安全性增强**
   - 限制参数值长度，防止 DoS
   - 验证参数值不包含控制字符

5. **调试支持**
   - 添加展开过程的详细日志
   - 提供展开预览功能（不实际提交）

6. **国际化**
   - 错误信息支持多语言
   - 考虑不同语言的占位符命名约定

### 相关文档

- `codex_protocol::custom_prompts`：自定义提示词协议定义
- `codex_protocol::user_input`：TextElement 和 ByteRange 定义
- `docs/tui-chat-composer.md`：ChatComposer 集成文档
