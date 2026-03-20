# Research: codex-rs/core/src/instructions

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

`codex-rs/core/src/instructions` 模块是 Codex CLI 项目中负责**指令注入**的核心组件。其主要职责包括：

1. **用户指令封装**：将项目级文档（`AGENTS.md`）和配置中的用户指令封装成标准化的消息格式，注入到对话上下文中
2. **Skill 指令注入**：将用户通过 `$skill-name` 语法提及的 Skill 内容封装并注入到对话中
3. **消息标准化**：统一不同来源的指令格式，确保它们能被正确识别和处理

该模块位于 Codex 核心逻辑层，作为**上下文构建**的一部分，在每次用户交互时被调用，将外部指令整合到 AI 模型的输入中。

---

## 功能点目的

### 1. UserInstructions - 用户项目指令

**目的**：将项目级文档（`AGENTS.md`）转换为标准化的 AI 消息格式。

**工作流程**：
- 从 `project_doc.rs` 获取合并后的项目文档内容
- 将文档内容与当前工作目录关联
- 封装为带有特定标记格式的消息，便于后续识别和处理

**输出格式示例**：
```
# AGENTS.md instructions for /path/to/project

<INSTRUCTIONS>
[项目文档内容]
</INSTRUCTIONS>
```

### 2. SkillInstructions - Skill 指令

**目的**：将用户显式提及的 Skill（通过 `$skill-name` 语法）内容注入对话。

**工作流程**：
- 在 `skills/injection.rs` 中解析用户输入中的 Skill 提及
- 读取对应 Skill 文件（`SKILL.md`）的内容
- 封装为标准化消息格式

**输出格式示例**：
```xml
<skill>
<name>demo-skill</name>
<path>skills/demo/SKILL.md</path>
[Skill 内容]
</skill>
```

### 3. 上下文片段定义（ContextualUserFragmentDefinition）

**目的**：提供统一的机制来定义、识别和处理各类上下文片段。

**支持的片段类型**：
- `AGENTS_MD_FRAGMENT` - 项目文档指令
- `SKILL_FRAGMENT` - Skill 指令
- `ENVIRONMENT_CONTEXT_FRAGMENT` - 环境上下文
- `USER_SHELL_COMMAND_FRAGMENT` - 用户 shell 命令
- `TURN_ABORTED_FRAGMENT` - 会话中止标记
- `SUBAGENT_NOTIFICATION_FRAGMENT` - 子代理通知

---

## 具体技术实现

### 数据结构

#### UserInstructions
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "user_instructions", rename_all = "snake_case")]
pub(crate) struct UserInstructions {
    pub directory: String,  // 指令关联的目录路径
    pub text: String,       // 指令内容
}
```

#### SkillInstructions
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "skill_instructions", rename_all = "snake_case")]
pub(crate) struct SkillInstructions {
    pub name: String,     // Skill 名称
    pub path: String,     // Skill 文件路径
    pub contents: String, // Skill 内容
}
```

#### ContextualUserFragmentDefinition
```rust
#[derive(Clone, Copy)]
pub(crate) struct ContextualUserFragmentDefinition {
    start_marker: &'static str,  // 起始标记
    end_marker: &'static str,    // 结束标记
}
```

### 关键流程

#### 1. 用户指令注入流程

```
用户输入
    ↓
codex.rs::prepare_turn_context()
    ↓
get_user_instructions(&config)  [project_doc.rs]
    ↓
读取 AGENTS.md + 配置指令 + JS REPL 指令 + 分层指令
    ↓
合并为单一字符串
    ↓
UserInstructions::serialize_to_text()
    ↓
格式化为标记文本 → 添加到 contextual_user_sections
    ↓
build_contextual_user_message() → ResponseItem
```

#### 2. Skill 指令注入流程

```
用户输入（包含 $skill-name）
    ↓
codex.rs::prepare_turn_context()
    ↓
build_skill_injections()  [skills/injection.rs]
    ↓
collect_explicit_skill_mentions() 解析提及
    ↓
遍历匹配 Skill → 读取 SKILL.md 文件
    ↓
SkillInstructions::from(skill) → ResponseItem
    ↓
添加到 items 列表
```

### 序列化实现

#### UserInstructions 序列化
```rust
pub(crate) fn serialize_to_text(&self) -> String {
    format!(
        "{prefix}{directory}\n\n<INSTRUCTIONS>\n{contents}\n{suffix}",
        prefix = AGENTS_MD_FRAGMENT.start_marker(),  // "# AGENTS.md instructions for "
        directory = self.directory,
        contents = self.text,
        suffix = AGENTS_MD_FRAGMENT.end_marker(),    // "</INSTRUCTIONS>"
    )
}
```

#### SkillInstructions 序列化
```rust
impl From<SkillInstructions> for ResponseItem {
    fn from(si: SkillInstructions) -> Self {
        SKILL_FRAGMENT.into_message(SKILL_FRAGMENT.wrap(format!(
            "<name>{}</name>\n<path>{}</path>\n{}",
            si.name, si.path, si.contents
        )))
    }
}
```

### 片段匹配逻辑

```rust
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
```

---

## 关键代码路径与文件引用

### 本模块文件

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块导出，暴露 `UserInstructions`、`SkillInstructions` 和 `USER_INSTRUCTIONS_PREFIX` |
| `user_instructions.rs` | 核心实现：数据结构定义、序列化逻辑、From 转换实现 |
| `user_instructions_tests.rs` | 单元测试：验证序列化格式和匹配逻辑 |

### 调用方（上游）

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex.rs:216` | `use crate::instructions::UserInstructions` | 导入用户指令类型 |
| `codex.rs:3510-3518` | `UserInstructions::serialize_to_text()` | 将项目文档封装为上下文消息 |
| `skills/injection.rs:9` | `use crate::instructions::SkillInstructions` | 导入 Skill 指令类型 |
| `skills/injection.rs:50` | `ResponseItem::from(SkillInstructions {...})` | 将 Skill 内容转换为消息项 |

### 被调用方（下游）

| 文件 | 依赖内容 | 用途 |
|------|----------|------|
| `contextual_user_message.rs:66` | `AGENTS_MD_FRAGMENT` | 定义 AGENTS.md 片段标记 |
| `contextual_user_message.rs:73` | `SKILL_FRAGMENT` | 定义 Skill 片段标记 |
| `contextual_user_message.rs:17-64` | `ContextualUserFragmentDefinition` | 片段定义基础结构 |
| `protocol/src/models.rs:295` | `ResponseItem` | 消息项枚举定义 |
| `protocol/src/models.rs` | `ContentItem` | 内容项枚举定义 |

### 配置与项目文档

| 文件 | 职责 |
|------|------|
| `project_doc.rs:79` | `get_user_instructions()` - 获取合并后的用户指令 |
| `config/mod.rs` | `Config::user_instructions` - 配置中的用户指令 |
| `config/mod.rs` | `Config::project_doc_max_bytes` - 项目文档大小限制 |

---

## 依赖与外部交互

### 内部依赖

```
instructions/
├── contextual_user_message  (AGENTS_MD_FRAGMENT, SKILL_FRAGMENT)
├── project_doc              (get_user_instructions)
├── skills/injection         (Skill 提及解析和注入)
└── codex.rs                 (TurnContext 构建)
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 `UserInstructions` 和 `SkillInstructions` |
| `codex_protocol::models::ResponseItem` | 消息项类型 |
| `codex_protocol::models::ContentItem` | 内容项类型 |

### 协议集成

`ResponseItem` 是 Codex 协议的核心消息类型，定义于 `codex-rs/protocol/src/models.rs`：

```rust
pub enum ResponseItem {
    Message { role, content, ... },
    Reasoning { ... },
    LocalShellCall { ... },
    FunctionCall { ... },
    ...
}
```

`instructions` 模块通过 `From<T> for ResponseItem` 实现将指令无缝转换为 `Message` 类型的 `ResponseItem`。

---

## 风险、边界与改进建议

### 潜在风险

1. **序列化格式硬编码**
   - 标记字符串（如 `# AGENTS.md instructions for `）在多处硬编码
   - 修改格式需要同步更新 `contextual_user_message.rs` 和本模块
   - **建议**：将标记定义集中管理，通过常量或配置驱动

2. **文本匹配大小写敏感问题**
   - `matches_text()` 使用 `eq_ignore_ascii_case` 进行大小写不敏感匹配
   - 但序列化时使用的是原始标记字符串
   - **风险**：如果标记被修改，匹配逻辑可能失效

3. **内存排除逻辑耦合**
   - `is_memory_excluded_contextual_user_fragment()` 在 `contextual_user_message.rs` 中硬编码排除 `AGENTS_MD_FRAGMENT` 和 `SKILL_FRAGMENT`
   - 新增片段类型时需要同步更新该函数
   - **建议**：在 `ContextualUserFragmentDefinition` 中添加 `exclude_from_memory` 标志

### 边界情况

1. **空内容处理**
   - `UserInstructions.text` 为空时仍会生成带标记的包装文本
   - 测试用例显示这是预期行为

2. **路径编码**
   - `SkillInstructions.path` 使用 `to_string_lossy()` 转换，可能丢失非 UTF-8 路径信息

3. **Skill 文件读取失败**
   - 在 `skills/injection.rs` 中，Skill 文件读取失败会记录警告但不会阻止流程
   - 失败信息通过 `SkillInjections.warnings` 返回

### 改进建议

1. **API 一致性**
   - `UserInstructions` 和 `SkillInstructions` 的序列化方式不一致：
     - `UserInstructions` 使用 `serialize_to_text()` 方法
     - `SkillInstructions` 仅通过 `From` trait 转换
   - **建议**：统一为两者都提供显式的序列化方法

2. **类型安全**
   - `directory` 和 `path` 字段使用 `String` 而非 `PathBuf`
   - **建议**：使用路径类型增强类型安全

3. **测试覆盖**
   - 当前测试仅验证序列化格式和匹配逻辑
   - **建议**：增加边界测试（空内容、特殊字符、长文本等）

4. **文档完善**
   - 模块缺少顶层文档注释
   - **建议**：添加模块级文档说明整体设计和使用方式

### 性能考量

1. **字符串拼接**
   - 使用 `format!` 进行字符串拼接，对于大文档可能产生多次内存分配
   - **建议**：对于超大文档考虑使用 `String::with_capacity` 预分配

2. **重复序列化**
   - 每次 turn 都会重新序列化项目文档
   - **建议**：考虑缓存机制（需注意配置变更失效）

---

## 附录：常量定义

```rust
// AGENTS.md 片段标记
pub(crate) const AGENTS_MD_START_MARKER: &str = "# AGENTS.md instructions for ";
pub(crate) const AGENTS_MD_END_MARKER: &str = "</INSTRUCTIONS>";

// Skill 片段标记
pub(crate) const SKILL_OPEN_TAG: &str = "<skill>";
pub(crate) const SKILL_CLOSE_TAG: &str = "</skill>";

// 导出常量
pub const USER_INSTRUCTIONS_PREFIX: &str = "# AGENTS.md instructions for ";
```

---

*研究完成时间：2026-03-21*
*研究者：Kimi Code CLI*
