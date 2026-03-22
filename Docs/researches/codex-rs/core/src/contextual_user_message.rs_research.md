# contextual_user_message.rs 研究文档

## 场景与职责

`contextual_user_message.rs` 是 Codex 核心模块中负责**识别和处理上下文用户消息片段**的轻量级工具模块。在 Codex 的协议中，某些消息虽然以用户消息的形式出现，但实际上是由系统自动注入的上下文信息（如 AGENTS.md 指令、环境上下文、skill 内容等）。

### 主要职责
1. **片段识别**：识别消息内容是否为特定的上下文片段类型
2. **内存排除决策**：决定哪些片段不应进入记忆系统
3. **消息包装**：为特定类型的内容提供统一的包装格式

### 业务场景
- **记忆系统过滤**：在生成长期记忆时，排除系统注入的指令性内容
- **消息分类**：区分真实用户输入和系统自动添加的上下文
- **协议解析**：处理来自不同来源的结构化消息片段

---

## 功能点目的

### 1. 上下文片段定义
定义六种标准的上下文片段类型，每种类型有特定的开始和结束标记：

| 片段类型 | 开始标记 | 结束标记 | 用途 |
|----------|----------|----------|------|
| AGENTS_MD | `# AGENTS.md instructions for ` | `</INSTRUCTIONS>` | 项目特定指令 |
| ENVIRONMENT_CONTEXT | `<environment_context>` | `</environment_context>` | 环境信息（cwd, env 等） |
| SKILL | `<skill>` | `</skill>` | Skill 系统内容 |
| USER_SHELL_COMMAND | `<user_shell_command>` | `</user_shell_command>` | 用户 shell 命令 |
| TURN_ABORTED | `<turn_aborted>` | `</turn_aborted>` | 回合中止标记 |
| SUBAGENT_NOTIFICATION | `<subagent_notification>` | `</subagent_notification>` | 子代理通知 |

### 2. 片段识别
通过标记匹配判断消息内容是否为特定上下文片段：
- 支持大小写不敏感匹配（`eq_ignore_ascii_case`）
- 自动去除首尾空白后匹配

### 3. 内存排除策略
区分应进入记忆和不应进入记忆的内容：
- **排除**：AGENTS.md 指令、Skill 内容（属于提示脚手架）
- **保留**：环境上下文、子代理通知（包含有价值的执行上下文）

---

## 具体技术实现

### 核心结构

```rust
#[derive(Clone, Copy)]
pub(crate) struct ContextualUserFragmentDefinition {
    start_marker: &'static str,
    end_marker: &'static str,
}

impl ContextualUserFragmentDefinition {
    pub(crate) const fn new(start_marker: &'static str, end_marker: &'static str) -> Self {
        Self { start_marker, end_marker }
    }

    // 检查文本是否匹配此片段定义
    pub(crate) fn matches_text(&self, text: &str) -> bool {
        let trimmed = text.trim_start();
        let starts_with_marker = trimmed
            .get(..self.start_marker.len())
            .is_some_and(|candidate| candidate.eq_ignore_ascii_case(self.start_marker));
        let trimmed = trimmed.trim_end();
        let ends_with_marker = trimmed
            .get(trimmed.len().saturating_sub(self.end_marker.len())..)
            .is_some_and(|candidate| candidate.eq_ignore_ascii_case(self.end_marker));
        starts_with_marker && ends_with_marker
    }

    // 包装内容为此片段格式
    pub(crate) fn wrap(&self, body: String) -> String {
        format!("{}\n{}\n{}", self.start_marker, body, self.end_marker)
    }

    // 转换为 ResponseItem 消息
    pub(crate) fn into_message(self, text: String) -> ResponseItem {
        ResponseItem::Message {
            id: None,
            role: "user".to_string(),
            content: vec![ContentItem::InputText { text }],
            end_turn: None,
            phase: None,
        }
    }
}
```

### 预定义片段常量

```rust
pub(crate) const AGENTS_MD_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new(
        "# AGENTS.md instructions for ", 
        "</INSTRUCTIONS>"
    );

pub(crate) const ENVIRONMENT_CONTEXT_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new(
        ENVIRONMENT_CONTEXT_OPEN_TAG,  // "<environment_context>"
        ENVIRONMENT_CONTEXT_CLOSE_TAG, // "</environment_context>"
    );

pub(crate) const SKILL_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new("<skill>", "</skill>");

pub(crate) const USER_SHELL_COMMAND_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new("<user_shell_command>", "</user_shell_command>");

pub(crate) const TURN_ABORTED_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new("<turn_aborted>", "</turn_aborted>");

pub(crate) const SUBAGENT_NOTIFICATION_FRAGMENT: ContextualUserFragmentDefinition =
    ContextualUserFragmentDefinition::new("<subagent_notification>", "</subagent_notification>");
```

### 片段检测函数

```rust
// 所有已知上下文片段的列表
const CONTEXTUAL_USER_FRAGMENTS: &[ContextualUserFragmentDefinition] = &[
    AGENTS_MD_FRAGMENT,
    ENVIRONMENT_CONTEXT_FRAGMENT,
    SKILL_FRAGMENT,
    USER_SHELL_COMMAND_FRAGMENT,
    TURN_ABORTED_FRAGMENT,
    SUBAGENT_NOTIFICATION_FRAGMENT,
];

// 检查 ContentItem 是否为任何上下文片段
pub(crate) fn is_contextual_user_fragment(content_item: &ContentItem) -> bool {
    let ContentItem::InputText { text } = content_item else {
        return false;
    };
    CONTEXTUAL_USER_FRAGMENTS
        .iter()
        .any(|definition| definition.matches_text(text))
}

// 检查是否应从记忆中排除
pub(crate) fn is_memory_excluded_contextual_user_fragment(content_item: &ContentItem) -> bool {
    let ContentItem::InputText { text } = content_item else {
        return false;
    };
    AGENTS_MD_FRAGMENT.matches_text(text) || SKILL_FRAGMENT.matches_text(text)
}
```

---

## 关键代码路径与文件引用

### 本文件位置
- `codex-rs/core/src/contextual_user_message.rs`
- `codex-rs/core/src/contextual_user_message_tests.rs`（测试文件）

### 调用方
| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/memories/phase1.rs` | 记忆生成时排除特定片段 |
| `codex-rs/core/src/event_mapping.rs` | 事件映射处理 |

### 依赖类型
| 来源 | 类型 |
|------|------|
| `codex_protocol::models::ContentItem` | 内容项类型 |
| `codex_protocol::models::ResponseItem` | 响应项类型 |
| `codex_protocol::protocol` | 环境上下文标记常量 |

---

## 依赖与外部交互

### 外部 crate 依赖
- `codex_protocol`：提供 `ContentItem`, `ResponseItem` 等协议类型

### 内部模块依赖
- 无直接内部模块依赖，保持轻量级

### 标记常量来源
```rust
// 来自 codex_protocol::protocol
pub const ENVIRONMENT_CONTEXT_OPEN_TAG: &str = "<environment_context>";
pub const ENVIRONMENT_CONTEXT_CLOSE_TAG: &str = "</environment_context>";
```

---

## 风险、边界与改进建议

### 已知风险

1. **标记冲突风险**
   - 如果用户真实输入恰好以 `# AGENTS.md instructions for ` 开头，会被误判为上下文片段
   - 虽然概率极低，但理论上存在

2. **大小写不敏感匹配的边界**
   - 使用 `eq_ignore_ascii_case` 可能导致某些 Unicode 字符的意外匹配
   - 例如土耳其语中的点less i 问题

3. **性能考虑**
   - `matches_text` 在大量消息处理时可能产生多次字符串扫描
   - 当前实现每次调用都进行 `trim_start` 和 `trim_end`

### 边界情况

1. **空字符串处理**
   - 空字符串不会匹配任何片段（`starts_with_marker` 和 `ends_with_marker` 都为 false）

2. **部分匹配**
   - 只有开始标记或只有结束标记：不匹配
   - 标记之间有额外内容：正常匹配

3. **嵌套标记**
   - 如果内容包含多个相同类型的标记，以首尾为准

### 改进建议

1. **前缀哈希优化**
   ```rust
   // 建议：使用前缀哈希快速排除非匹配项
   const AGENTS_MD_PREFIX_HASH: u64 = ...;
   
   pub(crate) fn matches_text(&self, text: &str) -> bool {
       // 快速前缀检查
       if !has_prefix_hash(text, self.prefix_hash) {
           return false;
       }
       // 完整匹配检查
       ...
   }
   ```

2. **更精确的标记设计**
   - 考虑使用更独特的标记，如 `<codex:agents_md>` 替代简单的文本前缀
   - 添加版本标识便于未来扩展

3. **配置化片段类型**
   - 允许通过配置动态注册新的上下文片段类型
   - 便于插件系统扩展

4. **增强文档**
   - 添加更多使用示例
   - 说明每种片段类型的典型使用场景

5. **性能优化**
   - 对于高频调用场景，考虑使用 `memchr` 等快速字符串搜索库
   - 缓存已解析的片段类型避免重复匹配

### 测试覆盖分析

当前测试覆盖：
- ✅ 环境上下文片段检测
- ✅ AGENTS.md 指令片段检测
- ✅ 大小写不敏感匹配
- ✅ 普通用户文本忽略
- ✅ 内存排除分类

建议补充：
- ⚠️ 边界情况：空字符串、仅开始标记、仅结束标记
- ⚠️ 性能测试：大规模消息列表的处理速度
- ⚠️ Unicode 边界情况测试
