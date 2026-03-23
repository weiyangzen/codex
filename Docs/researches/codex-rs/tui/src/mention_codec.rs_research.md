# mention_codec.rs 深入研究

## 场景与职责

`mention_codec.rs` 是 Codex TUI 中负责**提及（Mention）编解码**的模块。它处理工具/插件提及（如 `$tool` 或 `@plugin`）在内部表示和 Markdown 链接格式之间的转换，支持跨客户端的提及互操作性。

### 核心场景

1. **历史记录存储**：将内部提及标记（`$tool`）转换为 Markdown 链接格式（`[$tool](path)`）以便持久化
2. **历史记录加载**：从 Markdown 链接格式解析回内部提及标记
3. **跨客户端兼容**：支持读取其他客户端（如使用 `@` 作为插件 sigil）生成的提及格式

### 提及类型

| Sigil | 用途 | 示例 |
|-------|------|------|
| `$` | 工具提及（默认） | `$figma` |
| `@` | 插件文本提及（跨客户端兼容） | `@sample` |

## 功能点目的

### 1. LinkedMention 结构体

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LinkedMention {
    pub(crate) mention: String,  // 提及名称（如 "figma"）
    pub(crate) path: String,     // 关联路径（如 "app://figma-1"）
}
```

### 2. DecodedHistoryText 结构体

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DecodedHistoryText {
    pub(crate) text: String,              // 解码后的纯文本（含 $mention）
    pub(crate) mentions: Vec<LinkedMention>,  // 提取的提及列表
}
```

### 3. 编解码函数

#### `encode_history_mentions(text, mentions) -> String`
- **输入**：带 `$mention` 标记的文本 + 提及元数据列表
- **输出**：Markdown 链接格式的文本
- **绑定逻辑**：按提及名称匹配，按顺序绑定到文本中的 `$mention`

#### `decode_history_mentions(text) -> DecodedHistoryText`
- **输入**：Markdown 链接格式的文本
- **输出**：内部表示（`$mention`）+ 提取的提及元数据
- **支持格式**：`[$name](path)` 和 `[@name](plugin://...)`

## 具体技术实现

### 编码流程

```rust
pub(crate) fn encode_history_mentions(text: &str, mentions: &[LinkedMention]) -> String {
    // 1. 构建提及名称 -> 路径队列的映射
    let mut mentions_by_name: HashMap<&str, VecDeque<&str>> = HashMap::new();
    
    // 2. 遍历文本字节，检测 $mention 模式
    while index < bytes.len() {
        if bytes[index] == TOOL_MENTION_SIGIL as u8 {
            // 解析提及名称（a-z, A-Z, 0-9, _, -）
            // 替换为 Markdown 链接格式
        }
    }
}
```

### 解码流程

```rust
pub(crate) fn decode_history_mentions(text: &str) -> DecodedHistoryText {
    // 1. 遍历文本，检测 `[` 开头
    // 2. 调用 parse_history_linked_mention 解析链接
    // 3. 支持 $ 和 @ 两种 sigil
    // 4. 过滤环境变量误匹配（PATH, HOME 等）
}
```

### 链接解析器

```rust
fn parse_linked_tool_mention<'a>(
    text: &'a str,
    text_bytes: &[u8],
    start: usize,
    sigil: char,
) -> Option<(&'a str, &'a str, usize)>
```

解析模式：`[SIGILname](path)`
- 严格的字节级解析
- 支持路径前后空白字符
- 返回 `(name, path, end_index)`

### 环境变量过滤

```rust
fn is_common_env_var(name: &str) -> bool {
    let upper = name.to_ascii_uppercase();
    matches!(upper.as_str(), "PATH" | "HOME" | "USER" | ...)
}
```

防止 `$PATH` 等环境变量被误识别为提及。

### 工具路径验证

```rust
fn is_tool_path(path: &str) -> bool {
    path.starts_with("app://")
        || path.starts_with("mcp://")
        || path.starts_with("plugin://")
        || path.starts_with("skill://")
        || path.rsplit(['/', '\\'])
            .next()
            .is_some_and(|name| name.eq_ignore_ascii_case("SKILL.md"))
}
```

确保只识别有效的工具/插件路径。

## 关键代码路径

### 1. 编码路径（行 19-71）

```rust
pub(crate) fn encode_history_mentions(text: &str, mentions: &[LinkedMention]) -> String {
    // 构建提及映射表
    let mut mentions_by_name: HashMap<&str, VecDeque<&str>> = HashMap::new();
    for mention in mentions {
        mentions_by_name
            .entry(mention.mention.as_str())
            .or_default()
            .push_back(mention.path.as_str());
    }
    
    // 字节级遍历和替换
    while index < bytes.len() {
        if bytes[index] == TOOL_MENTION_SIGIL as u8 {
            // 尝试匹配提及名称
            let name = &text[name_start..name_end];
            if let Some(path) = mentions_by_name.get_mut(name).and_then(VecDeque::pop_front) {
                // 替换为 Markdown 链接
                out.push('[');
                out.push(TOOL_MENTION_SIGIL);
                out.push_str(name);
                out.push_str("](");
                out.push_str(path);
                out.push(')');
            }
        }
    }
}
```

### 2. 解码路径（行 73-104）

```rust
pub(crate) fn decode_history_mentions(text: &str) -> DecodedHistoryText {
    while index < bytes.len() {
        if bytes[index] == b'['
            && let Some((name, path, end_index)) = parse_history_linked_mention(text, bytes, index)
        {
            // 转换回 $mention 格式
            out.push(TOOL_MENTION_SIGIL);
            out.push_str(name);
            mentions.push(LinkedMention { ... });
        }
    }
}
```

### 3. 历史链接解析（行 106-129）

```rust
fn parse_history_linked_mention<'a>(...)
    -> Option<(&'a str, &'a str, usize)>
{
    // 尝试 $  sigil（工具）
    if let Some(mention) = parse_linked_tool_mention(..., TOOL_MENTION_SIGIL)
        && !is_common_env_var(name)
        && is_tool_path(path)
    {
        return Some(mention);
    }
    
    // 尝试 @ sigil（插件，跨客户端兼容）
    if let Some(mention) = parse_linked_tool_mention(..., PLUGIN_TEXT_MENTION_SIGIL)
        && !is_common_env_var(name)
        && path.starts_with("plugin://")
    {
        return Some(mention);
    }
}
```

## 依赖与外部交互

### 直接依赖

| 模块 | 用途 |
|------|------|
| `codex_core::mention_syntax::TOOL_MENTION_SIGIL` | `$` 常量 |
| `codex_core::mention_syntax::PLUGIN_TEXT_MENTION_SIGIL` | `@` 常量 |
| `std::collections::HashMap` | 提及映射 |
| `std::collections::VecDeque` | FIFO 队列（同名提及处理） |

### 核心常量定义

```rust
// codex-rs/core/src/mention_syntax.rs
pub const TOOL_MENTION_SIGIL: char = '$';
pub const PLUGIN_TEXT_MENTION_SIGIL: char = '@';
```

### 被调用方

- **历史记录序列化**：将对话历史保存为 Markdown 格式
- **历史记录反序列化**：从 Markdown 加载对话历史
- **跨客户端数据交换**：与其他 Codex 客户端共享历史

## 风险、边界与改进建议

### 已知风险

1. **同名提及顺序依赖**：
   - 使用 `VecDeque` 处理同名提及，依赖输入顺序
   - 如果文本和 mentions 列表顺序不一致，会导致错误绑定

2. **环境变量误匹配**：
   - 虽然有过滤列表，但新的环境变量可能被误识别
   - 过滤列表需要维护更新

3. **路径验证严格性**：
   - `is_tool_path` 使用前缀匹配，可能有误报/漏报
   - `SKILL.md` 检测大小写不敏感，可能有平台差异

### 边界情况处理

| 场景 | 处理方式 |
|------|----------|
| 空提及列表 | 直接返回原文本 |
| 空文本 | 返回空字符串 |
| 未匹配的 `$mention` | 保留原样（不替换） |
| 未绑定的提及 | 忽略（不出现在输出中） |
| 无效链接格式 | 作为普通文本保留 |
| 环境变量名 | 过滤列表排除 |

### 测试覆盖

模块包含 4 个测试用例：

1. **`decode_history_mentions_restores_visible_tokens`**
   - 测试标准 `$` sigil 解码

2. **`decode_history_mentions_restores_plugin_links_with_at_sigil`**
   - 测试 `@` sigil 跨客户端兼容

3. **`decode_history_mentions_ignores_at_sigil_for_non_plugin_paths`**
   - 测试非插件路径的 `@` 不被识别

4. **`encode_history_mentions_links_bound_mentions_in_order`**
   - 测试编码时的顺序绑定

### 改进建议

1. **顺序无关绑定**：考虑使用位置信息而非 FIFO 队列进行提及绑定
2. **环境变量动态检测**：运行时检测当前 shell 环境变量，而非硬编码列表
3. **路径验证增强**：使用 URL 解析而非前缀匹配
4. **错误报告**：添加编解码失败的诊断信息
5. **性能优化**：对于长文本，考虑使用正则表达式或更高效的字符串算法

## 文件引用汇总

- **本文件**：`codex-rs/tui/src/mention_codec.rs` (305 lines)
- **提及语法常量**：`codex-rs/core/src/mention_syntax.rs`
- **核心提及处理**：`codex-rs/core/src/mentions.rs`
- **技能注入**：`codex-rs/core/src/skills/injection.rs`
