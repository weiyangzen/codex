# mention_syntax.rs 研究文档

## 场景与职责

`mention_syntax.rs` 是 Codex 核心库中定义提及（mention）语法符号的极简模块。它负责：

1. **定义工具提及符号**：指定在文本中引用工具时使用的默认符号
2. **定义插件提及符号**：指定在文本中引用插件时使用的符号
3. **提供统一的符号常量**：供其他模块（如 `mentions.rs`、`skills/injection.rs`）使用

该模块是整个提及系统的语法基础，确保不同组件使用一致的符号约定。

## 功能点目的

### 1. 工具提及符号

**常量**：`TOOL_MENTION_SIGIL`

**值**：`'$'`（美元符号）

**用途**：
- 在文本中引用工具时使用，如 `$calendar`
- 支持链接格式：`[$calendar](app://calendar)`
- 用于技能（skill）提及，如 `$my-skill`

**设计理由**：
- `$` 是常见的变量/值引用符号，用户熟悉
- 在 Markdown 中不会与标准语法冲突
- 易于输入和识别

### 2. 插件提及符号

**常量**：`PLUGIN_TEXT_MENTION_SIGIL`

**值**：`'@'`（at 符号）

**用途**：
- 在文本中引用插件时使用，如 `@sample`
- 支持链接格式：`[@sample](plugin://sample@test)`
- 区分于工具提及，使用不同的命名空间

**设计理由**：
- `@` 是常见的提及/引用符号（如社交媒体中的用户提及）
- 与 `$` 区分，避免工具和插件的命名冲突
- 语义上表示"寻址"某个插件

## 具体技术实现

### 完整代码

```rust
// Default plaintext sigil for tools.
pub const TOOL_MENTION_SIGIL: char = '$';
// Plugins use `@` in linked plaintext outside TUI.
pub const PLUGIN_TEXT_MENTION_SIGIL: char = '@';
```

### 使用示例

在其他模块中的使用：

```rust
// mentions.rs
use crate::mention_syntax::TOOL_MENTION_SIGIL;

pub(crate) fn collect_tool_mentions_from_messages(messages: &[String]) -> CollectedToolMentions {
    collect_tool_mentions_from_messages_with_sigil(messages, TOOL_MENTION_SIGIL)
}
```

```rust
// skills/injection.rs
use crate::mention_syntax::TOOL_MENTION_SIGIL;

pub(crate) fn extract_tool_mentions(text: &str) -> ToolMentions<'_> {
    extract_tool_mentions_with_sigil(text, TOOL_MENTION_SIGIL)
}
```

```rust
// mentions.rs
use crate::mention_syntax::PLUGIN_TEXT_MENTION_SIGIL;

// 插件提及使用 @ 符号
let mentioned_config_names: HashSet<String> = input
    .iter()
    .filter_map(|item| match item {
        UserInput::Mention { path, .. } => Some(path.clone()),
        _ => None,
    })
    .chain(
        collect_tool_mentions_from_messages_with_sigil(&messages, PLUGIN_TEXT_MENTION_SIGIL)
            .paths,
    )
    .filter(|path| tool_kind_for_path(path.as_str()) == ToolMentionKind::Plugin)
    .filter_map(|path| plugin_config_name_from_path(path.as_str()).map(str::to_string))
    .collect();
```

## 关键代码路径与文件引用

### 使用者

| 文件 | 使用方式 |
|------|----------|
| `mentions.rs` | `TOOL_MENTION_SIGIL` 用于工具提及，`PLUGIN_TEXT_MENTION_SIGIL` 用于插件提及 |
| `skills/injection.rs` | `TOOL_MENTION_SIGIL` 用于技能提及提取 |

### 引用链

```
mention_syntax.rs
├── mentions.rs
│   ├── collect_tool_mentions_from_messages (使用 TOOL_MENTION_SIGIL)
│   └── collect_explicit_plugin_mentions (使用 PLUGIN_TEXT_MENTION_SIGIL)
└── skills/injection.rs
    └── extract_tool_mentions (使用 TOOL_MENTION_SIGIL)
```

## 依赖与外部交互

该模块无任何外部依赖，也不与其他模块产生运行时交互。它仅提供编译时常量。

## 风险、边界与改进建议

### 已知风险

1. **硬编码符号**：符号是硬编码的，无法通过配置更改，可能不适合所有用户场景

2. **无验证**：模块本身不验证提及格式的正确性，仅提供符号常量

3. **扩展性**：如果需要添加新的提及类型（如 `@` 用于用户提及），可能需要引入新的常量

### 边界情况

该模块非常简单，没有复杂的边界情况需要考虑。

### 改进建议

1. **配置化**：考虑将符号常量改为可从配置读取，允许用户自定义

2. **文档扩展**：添加更多使用示例和格式说明

3. **验证函数**：添加提及格式验证的辅助函数，如：

```rust
pub fn is_valid_mention(text: &str) -> bool {
    text.starts_with(TOOL_MENTION_SIGIL) || 
    text.starts_with(PLUGIN_TEXT_MENTION_SIGIL)
}
```

4. **提取函数**：将提及提取的核心逻辑移到该模块，使其成为完整的提及语法模块：

```rust
pub fn extract_mentions(text: &str, sigil: char) -> Vec<&str> {
    // 提取逻辑...
}
```

5. **国际化考虑**：如果未来支持非 ASCII 提及符号，需要考虑 Unicode 处理

6. **常量文档**：为常量添加更详细的文档注释，说明使用场景和约束：

```rust
/// Default plaintext sigil for tools.
/// 
/// Used to reference tools in user input, e.g., `$calendar`.
/// Supports linked format: `[$calendar](app://calendar)`.
/// 
/// # Constraints
/// - Must be a single ASCII character
/// - Must not conflict with Markdown syntax
pub const TOOL_MENTION_SIGIL: char = '$';
```
