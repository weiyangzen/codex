# context_snapshot.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/tests/common/context_snapshot.rs`
- **大小**: 22,560 bytes (602 行)
- **所属模块**: core_test_support

---

## 场景与职责

此文件实现了测试中的上下文快照格式化功能，用于将 Codex 的 API 请求/响应数据转换为可读的文本快照。这些快照用于：
1. **测试断言**: 验证模型接收到的输入是否符合预期
2. **调试输出**: 在测试失败时提供可读的上下文信息
3. **回归检测**: 通过快照比较检测意外的行为变更

### 核心职责
1. **格式化 Response Items**: 将 OpenAI Responses API 的输入项格式化为可读文本
2. **多种渲染模式**: 支持 RedactedText、FullText、KindOnly 和 KindWithTextPrefix 模式
3. **敏感信息脱敏**: 自动识别并替换敏感内容（如系统指令、环境上下文）
4. **选择性过滤**: 支持过滤掉能力指令和 AGENTS.md 用户上下文

---

## 功能点目的

### 1. 渲染模式枚举
```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ContextSnapshotRenderMode {
    #[default]
    RedactedText,      // 脱敏文本（默认）
    FullText,          // 完整文本
    KindOnly,          // 仅类型
    KindWithTextPrefix { max_chars: usize }, // 类型+前缀
}
```

#### RedactedText (默认)
- 将系统指令替换为 `<PERMISSIONS_INSTRUCTIONS>`, `<APPS_INSTRUCTIONS>` 等占位符
- 将 AGENTS.md 内容替换为 `<AGENTS_MD>`
- 将环境上下文替换为 `<ENVIRONMENT_CONTEXT>`
- 规范化系统技能路径

#### FullText
- 保留原始文本内容
- 仅规范化行尾符 (CRLF → LF)

#### KindOnly
- 仅显示项目类型，如 `00:message/user`, `01:function_call/shell`
- 用于快速查看消息结构

#### KindWithTextPrefix
- 显示类型和文本前缀
- 超过 `max_chars` 时截断并添加 `...`

### 2. 上下文快照选项
```rust
#[derive(Debug, Clone)]
pub struct ContextSnapshotOptions {
    render_mode: ContextSnapshotRenderMode,
    strip_capability_instructions: bool,  // 过滤能力指令
    strip_agents_md_user_context: bool,   // 过滤 AGENTS.md
}
```

### 3. 核心格式化函数

#### format_request_input_snapshot
```rust
pub fn format_request_input_snapshot(
    request: &ResponsesRequest,
    options: &ContextSnapshotOptions,
) -> String
```
- 从 `ResponsesRequest` 提取 input 数组并格式化

#### format_response_items_snapshot
```rust
pub fn format_response_items_snapshot(
    items: &[Value],
    options: &ContextSnapshotContextSnapshotOptions,
) -> String
```
- 格式化 Response Item 数组
- 支持多种 item 类型：message, function_call, function_call_output, local_shell_call, reasoning, compaction

#### format_labeled_requests_snapshot / format_labeled_items_snapshot
```rust
pub fn format_labeled_requests_snapshot(
    scenario: &str,
    sections: &[(&str, &ResponsesRequest)],
    options: &ContextSnapshotOptions,
) -> String
```
- 将多个请求分组并添加标签
- 输出格式：
```
Scenario: test_scenario

## Section 1
00:message/user:hello
01:function_call/shell

## Section 2
00:message/assistant:done
```

### 4. 特定类型格式化

#### Message 类型
```rust
"message" => {
    // 提取 role 和 content
    // 处理 input_text, input_image 等 content 类型
    // 多 part 消息显示为 role[N] 格式
}
```

#### Function Call 类型
```rust
"function_call" => format!("{idx:02}:function_call/{name}"),
```

#### Function Call Output 类型
```rust
"function_call_output" => {
    // 格式化 output 内容
    format!("{idx:02}:function_call_output:{output}")
}
```

#### Local Shell Call 类型
```rust
"local_shell_call" => {
    // 提取 command 数组并连接
    format!("{idx:02}:local_shell_call:{command}")
}
```

#### Reasoning 类型
```rust
"reasoning" => {
    // 提取 summary 和 encrypted_content 标志
    format!("{idx:02}:reasoning:summary={summary}:encrypted={has_encrypted_content}")
}
```

#### Compaction 类型
```rust
"compaction" => {
    format!("{idx:02}:compaction:encrypted={has_encrypted_content}")
}
```

### 5. 文本规范化

#### canonicalize_snapshot_text
核心脱敏逻辑：
```rust
fn canonicalize_snapshot_text(text: &str) -> String {
    if text.starts_with("<permissions instructions>") {
        return "<PERMISSIONS_INSTRUCTIONS>".to_string();
    }
    if text.starts_with(APPS_INSTRUCTIONS_OPEN_TAG) {
        return "<APPS_INSTRUCTIONS>".to_string();
    }
    // ... 其他模式匹配
}
```

#### 环境上下文解析
```rust
if text.starts_with("<environment_context>") {
    // 解析 <cwd>, <subagents> 等子元素
    // 返回格式: <ENVIRONMENT_CONTEXT:cwd=<CWD>:subagents=2>
}
```

#### 系统技能路径规范化
```rust
fn normalize_dynamic_snapshot_paths(text: &str) -> String {
    static SYSTEM_SKILL_PATH_RE: OnceLock<Regex> = OnceLock::new();
    // 将 /path/to/skills/.system/name/SKILL.md 替换为 <SYSTEM_SKILLS_ROOT>/name/SKILL.md
}
```

---

## 具体技术实现

### 数据流
```
ResponsesRequest/JSON Items
    ↓
format_request_input_snapshot / format_response_items_snapshot
    ↓
match item_type
    ├── "message" → 提取 role, content → format_snapshot_text
    ├── "function_call" → 提取 name
    ├── "function_call_output" → 提取 output
    ├── "local_shell_call" → 提取 command
    ├── "reasoning" → 提取 summary, encrypted_content
    ├── "compaction" → 检查 encrypted_content
    └── other → 直接显示类型
    ↓
规范化后的字符串
```

### 关键算法

#### 多 Part 消息处理
```rust
let role = if rendered_parts.len() > 1 {
    format!("{role}[{}]", rendered_parts.len())
} else {
    role.to_string()
};
```
- 单 part: `00:message/user:text`
- 多 part: `00:message/user[3]:\n    [01] part1\n    [02] part2...`

#### 内容项类型检测
```rust
let mut extra_keys = content_object
    .keys()
    .filter(|key| *key != "type" && *key != "text")
    .cloned()
    .collect::<Vec<String>>();
// 输出: <input_image:image_url> 或 <input_image>
```

---

## 关键代码路径与文件引用

### 模块关系
```
context_snapshot.rs
    ├── 被 lib.rs 导出: pub mod context_snapshot
    ├── 使用 responses::ResponsesRequest
    └── 依赖 codex_protocol::protocol 中的常量
```

### 协议常量引用
```rust
use codex_protocol::protocol::APPS_INSTRUCTIONS_OPEN_TAG;
use codex_protocol::protocol::PLUGINS_INSTRUCTIONS_OPEN_TAG;
use codex_protocol::protocol::SKILLS_INSTRUCTIONS_OPEN_TAG;
```
这些常量定义在 `codex-rs/protocol/src/protocol.rs` 中。

### 使用场景
在测试代码中：
```rust
use core_test_support::context_snapshot::{
    ContextSnapshotOptions, 
    ContextSnapshotRenderMode,
    format_request_input_snapshot
};

let options = ContextSnapshotOptions::default()
    .render_mode(ContextSnapshotRenderMode::RedactedText)
    .strip_capability_instructions();

let snapshot = format_request_input_snapshot(&request, &options);
assert_eq!(snapshot, "00:message/user:<ENVIRONMENT_CONTEXT>");
```

---

## 依赖与外部交互

### 内部依赖
| 依赖 | 用途 |
|-----|------|
| `responses::ResponsesRequest` | 请求数据类型 |
| `codex_protocol::protocol::*` | 协议常量 |

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `regex_lite` | 正则表达式匹配系统技能路径 |
| `serde_json::Value` | JSON 数据处理 |
| `std::sync::OnceLock` | 静态正则表达式编译 |

---

## 风险、边界与改进建议

### 潜在风险

1. **正则表达式性能**
   ```rust
   static SYSTEM_SKILL_PATH_RE: OnceLock<Regex> = OnceLock::new();
   ```
   - 使用 `OnceLock` 延迟初始化，但正则表达式在大量文本上可能较慢
   - 建议：如果性能成为问题，考虑使用字符串替换而非正则

2. **硬编码前缀匹配**
   ```rust
   if text.starts_with("<permissions instructions>")
   ```
   - 如果协议常量变更，此处需要同步更新
   - 建议：统一使用 `codex_protocol` 中定义的常量

3. **JSON 结构假设**
   - 代码假设特定的 JSON 结构（如 `item.get("type")`）
   - 如果 API 响应格式变更，可能导致 panic

### 边界条件

1. **空内容处理**
   - `rendered_parts.is_empty()` → 输出 `<NO_TEXT>`
   - 正确处理空消息场景

2. **超长文本截断**
   - `KindWithTextPrefix` 模式使用字符计数而非字节计数
   - 正确处理多字节 UTF-8 字符

3. **CRLF 规范化**
   ```rust
   fn normalize_snapshot_line_endings(text: &str) -> String {
       text.replace("\r\n", "\n").replace('\r', "\n")
   }
   ```
   - 统一处理 Windows/Unix 行尾差异

### 改进建议

1. **结构化输出**
   考虑添加 JSON 输出模式：
   ```rust
   pub enum OutputFormat {
       Text,  // 当前格式
       Json,  // 结构化 JSON
   }
   ```

2. **可配置占位符**
   允许自定义脱敏占位符：
   ```rust
   pub struct ContextSnapshotOptions {
       custom_placeholders: HashMap<String, String>,
   }
   ```

3. **增量快照**
   支持仅显示变更部分：
   ```rust
   pub fn format_diff(before: &[Value], after: &[Value]) -> String
   ```

4. **颜色支持**
   添加 ANSI 颜色支持以改善可读性：
   ```rust
   "message".cyan(),
   "function_call".yellow(),
   ```

5. **性能优化**
   对于大规模测试，考虑使用 arena 分配或字符串缓存：
   ```rust
   use string_cache::DefaultAtom;
   ```

---

## 测试覆盖

文件包含 14 个单元测试，覆盖：
1. `full_text_mode_preserves_unredacted_text` - 完整文本模式
2. `full_text_mode_normalizes_crlf_line_endings` - CRLF 规范化
3. `redacted_text_mode_keeps_canonical_placeholders` - 脱敏模式
4. `redacted_text_mode_keeps_capability_instruction_placeholders` - 能力指令占位符
5. `strip_capability_instructions_omits_capability_parts_from_developer_messages` - 过滤能力指令
6. `strip_agents_md_user_context_omits_agents_fragment_from_user_messages` - 过滤 AGENTS.md
7. `redacted_text_mode_normalizes_environment_context_with_subagents` - 环境上下文解析
8. `kind_with_text_prefix_mode_normalizes_crlf_line_endings` - 前缀模式
9. `image_only_message_is_rendered_as_non_text_span` - 图片消息
10. `mixed_text_and_image_message_keeps_image_span` - 混合消息
11. `redacted_text_mode_normalizes_system_skill_temp_paths` - 系统技能路径

---

## 相关文件
- `codex-rs/core/tests/common/lib.rs` - 模块导出
- `codex-rs/core/tests/common/responses.rs` - ResponsesRequest 定义
- `codex-rs/protocol/src/protocol.rs` - 协议常量定义
- `codex-rs/core/src/codex_tests.rs` - 使用该模块的测试
