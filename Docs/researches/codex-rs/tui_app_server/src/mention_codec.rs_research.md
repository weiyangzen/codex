# mention_codec.rs 深入研究

## 场景与职责

`mention_codec.rs` 是 Codex TUI 中负责**提及(mention)编解码**的模块，处理工具/插件提及在内部表示和外部链接格式之间的转换。

### 核心场景

1. **跨客户端兼容性**：TUI写入 `$name` 格式，但可能需要读取其他客户端（如VS Code插件）生成的 `[@name](plugin://...)` 链接格式
2. **历史记录持久化**：将带链接的提及编码为Markdown链接格式存储，解码时恢复为内部表示
3. **工具路径关联**：将提及名称映射到具体的工具路径（app://, mcp://, plugin://, skill://）

### 提及格式

| 格式 | 示例 | 使用场景 |
|------|------|----------|
| 内部表示 | `$figma` | TUI内部编辑、显示 |
| Markdown链接 | `[$figma](app://figma-1)` | 历史记录存储、跨客户端交换 |
| 插件格式 | `[@sample](plugin://sample@test)` | 插件客户端生成 |

## 功能点目的

### 1. 数据结构

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LinkedMention {
    pub(crate) mention: String,  // 提及名称（如 "figma"）
    pub(crate) path: String,     // 工具路径（如 "app://figma-1"）
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct DecodedHistoryText {
    pub(crate) text: String,              // 解码后的纯文本
    pub(crate) mentions: Vec<LinkedMention>, // 提取的提及列表
}
```

### 2. 编码函数 `encode_history_mentions`

**目的**：将内部 `$name` 格式转换为带链接的Markdown格式

```rust
pub(crate) fn encode_history_mentions(text: &str, mentions: &[LinkedMention]) -> String
```

**算法**：
1. 按提及名称分组，使用 `VecDeque` 维护FIFO顺序
2. 遍历文本字节，查找 `$` 开头的提及
3. 匹配时替换为 `[$name](path)` 格式
4. 未匹配的提及保持原样

### 3. 解码函数 `decode_history_mentions`

**目的**：将Markdown链接格式还原为内部 `$name` 格式

```rust
pub(crate) fn decode_history_mentions(text: &str) -> DecodedHistoryText
```

**支持格式**：
- `[$name](app://...)` - 标准工具链接
- `[@name](plugin://...)` - 插件格式（使用 `@` 符号）

**安全过滤**：
- 忽略常见环境变量名（`PATH`, `HOME`, `USER`, `SHELL`, `PWD`, `TMPDIR`, `TEMP`, `TMP`, `LANG`, `TERM`, `XDG_CONFIG_HOME`）
- 验证工具路径格式（必须以 `app://`, `mcp://`, `plugin://`, `skill://` 开头，或以 `SKILL.md` 结尾）

## 具体技术实现

### 1. 提及名称字符集

```rust
fn is_mention_name_char(byte: u8) -> bool {
    matches!(byte, b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'-')
}
```

允许：字母、数字、下划线、连字符

### 2. 链接解析状态机

```rust
fn parse_linked_tool_mention<'a>(
    text: &'a str,
    text_bytes: &[u8],
    start: usize,
    sigil: char,
) -> Option<(&'a str, &'a str, usize)>
```

解析步骤：
1. 验证起始字符 `[`
2. 验证符号（`$` 或 `@`）
3. 提取提及名称（符合 `is_mention_name_char` 的连续字符）
4. 验证闭合字符 `]`
5. 跳过可选空白
6. 验证路径起始字符 `(`
7. 提取路径（到 `)` 为止）
8. 验证路径闭合

### 3. 环境变量白名单过滤

```rust
fn is_common_env_var(name: &str) -> bool {
    let upper = name.to_ascii_uppercase();
    matches!(
        upper.as_str(),
        "PATH" | "HOME" | "USER" | "SHELL" | "PWD" | "TMPDIR" | "TEMP" | "TMP" | "LANG" | "TERM" | "XDG_CONFIG_HOME"
    )
}
```

防止将 `$PATH` 等环境变量误识别为提及。

### 4. 工具路径验证

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

## 关键代码路径与文件引用

### 直接依赖

| 文件 | 依赖类型 | 用途 |
|------|----------|------|
| `codex_core::mention_syntax` | 外部crate | `TOOL_MENTION_SIGIL` (`$`), `PLUGIN_TEXT_MENTION_SIGIL` (`@`) |

### 调用方

| 文件 | 使用方式 |
|------|----------|
| `chatwidget.rs` | 导入 `LinkedMention`, `encode_history_mentions` 用于历史记录编码 |
| `bottom_pane/chat_composer_history.rs` | 导入 `decode_history_mentions` 用于历史记录解码 |
| `tui/src/chatwidget.rs` | TUI主模块使用 |
| `tui/src/bottom_pane/chat_composer_history.rs` | TUI编辑器使用 |

### 核心常量定义

```rust
// codex-rs/core/src/mention_syntax.rs
pub const TOOL_MENTION_SIGIL: char = '$';
pub const PLUGIN_TEXT_MENTION_SIGIL: char = '@';
```

## 依赖与外部交互

### 外部crate依赖

- `std::collections::{HashMap, VecDeque}`：用于按提及名称分组和维护顺序
- `codex_core::mention_syntax`：提及符号常量

### 编解码流程

```
编码流程：
内部文本 "$figma" + LinkedMention {mention: "figma", path: "app://figma-1"}
    ↓
encode_history_mentions()
    ↓
Markdown格式 "[$figma](app://figma-1)"

解码流程：
Markdown格式 "[$figma](app://figma-1)"
    ↓
decode_history_mentions()
    ↓
内部文本 "$figma" + mentions = [LinkedMention {mention: "figma", path: "app://figma-1"}]
```

### 与chatwidget的协作

```rust
// chatwidget.rs
use crate::mention_codec::LinkedMention;
use crate::mention_codec::encode_history_mentions;

// 在历史记录提交时编码提及
let encoded = encode_history_mentions(&text, &mentions);
```

### 与chat_composer_history的协作

```rust
// bottom_pane/chat_composer_history.rs
use crate::mention_codec::decode_history_mentions;

// 在加载历史记录时解码提及
let decoded = decode_history_mentions(&stored_text);
```

## 风险、边界与改进建议

### 已知风险

1. **顺序敏感**：编码时提及必须按文本中出现的顺序提供，否则可能绑定错误
   ```rust
   // 如果有多个同名提及，按FIFO顺序绑定
   mentions_by_name.entry(name).or_default().push_back(path);
   ```

2. **环境变量误识别**：虽然有过滤，但自定义环境变量仍可能被误识别

3. **路径验证严格**：必须以特定协议开头或特定文件名结尾，可能遗漏有效路径

### 边界情况

| 场景 | 处理方式 |
|------|----------|
| 同名多个提及 | 使用 `VecDeque` 按FIFO顺序绑定 |
| 无路径的提及 | 保持原样，不转换（编码时）|
| 环境变量名 | 过滤列表检查，避免误识别 |
| 非标准路径 | `is_tool_path` 返回false，不识别为提及 |
| 插件格式 `@` | 支持解析，但内部统一转换为 `$` |

### 改进建议

1. **安全性增强**：
   - 考虑使用更严格的提及名称验证（如长度限制、保留字检查）
   - 添加路径白名单配置，允许用户自定义有效路径模式

2. **功能扩展**：
   - 支持相对路径解析（相对于当前工作目录）
   - 支持提及路径的自动补全和验证

3. **性能优化**：
   - 对于长文本，考虑使用 `memchr` 等快速字节搜索库
   - 缓存已解析的提及，避免重复解码

4. **错误处理**：
   - 当前使用 `Option` 返回，可考虑添加详细的错误类型说明失败原因
   - 添加无效提及的警告日志

5. **测试覆盖**：
   - 添加模糊测试生成随机提及文本
   - 测试极端长提及名称和路径
   - 测试Unicode提及名称（当前只支持ASCII）

### 相关测试

文件包含全面的单元测试：
- `decode_history_mentions_restores_visible_tokens`：基本解码功能
- `decode_history_mentions_restores_plugin_links_with_at_sigil`：插件格式支持
- `decode_history_mentions_ignores_at_sigil_for_non_plugin_paths`：非插件路径过滤
- `encode_history_mentions_links_bound_mentions_in_order`：编码顺序绑定
