# Research: codex-rs/core/src/instructions

## 概述

`codex-rs/core/src/instructions` 目录是 Codex 核心库中负责**指令封装与序列化**的模块。它将项目级文档（AGENTS.md）和 Skill 指令转换为模型可消费的 `ResponseItem` 格式，是连接用户配置与 LLM 交互的关键桥梁。

---

## 场景与职责

### 核心场景

1. **项目文档注入**：将项目中的 `AGENTS.md` 文件内容封装为结构化消息，注入到对话上下文中
2. **Skill 指令注入**：将 Skill（技能）的 `SKILL.md` 内容封装后注入模型上下文
3. **指令序列化**：提供统一的文本格式，便于模型识别和处理特殊指令

### 职责边界

| 职责 | 说明 |
|------|------|
| 封装 | 将原始指令文本包装为带标记的格式 |
| 序列化 | 将结构化数据转换为 `ResponseItem` |
| 标记识别 | 与 `contextual_user_message.rs` 配合，提供标记前缀常量 |

---

## 功能点目的

### 1. UserInstructions - AGENTS.md 指令封装

**目的**：将项目目录中的 `AGENTS.md` 指令封装为模型可识别的格式。

**序列化格式**：
```text
# AGENTS.md instructions for {directory}

<INSTRUCTIONS>
{text}
</INSTRUCTIONS>
```

**使用场景**：
- 会话启动时，从项目根目录到当前工作目录的所有 `AGENTS.md` 文件被收集
- 通过 `project_doc.rs` 的 `get_user_instructions()` 函数获取
- 最终通过 `UserInstructions::serialize_to_text()` 序列化并注入对话

### 2. SkillInstructions - Skill 指令封装

**目的**：将 Skill（技能）的 `SKILL.md` 内容封装为模型可识别的格式。

**序列化格式**：
```xml
<skill>
<name>{name}</name>
<path>{path}</path>
{contents}
</skill>
```

**使用场景**：
- 用户在输入中显式提及 Skill（如 `$skill-name`）
- 通过 `skills/injection.rs` 的 `build_skill_injections()` 函数加载并封装
- 注入到对话上下文中，让模型了解可用技能

---

## 具体技术实现

### 数据结构

#### UserInstructions
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "user_instructions", rename_all = "snake_case")]
pub(crate) struct UserInstructions {
    pub directory: String,  // AGENTS.md 所在目录
    pub text: String,       // 文件内容
}
```

#### SkillInstructions
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "skill_instructions", rename_all = "snake_case")]
pub(crate) struct SkillInstructions {
    pub name: String,       // Skill 名称
    pub path: String,       // Skill 文件路径
    pub contents: String,   // SKILL.md 内容
}
```

### 关键流程

#### 1. AGENTS.md 注入流程

```
Codex::spawn()
  └─> get_user_instructions(&config).await
        ├─> read_project_docs(config)     // 发现 AGENTS.md 文件
        │     └─> discover_project_doc_paths()
        │           └─> 从 cwd 向上遍历到项目根目录
        └─> 合并配置中的 instructions 和项目文档
  └─> user_instructions 存入 SessionConfiguration
        └─> 后续转为 UserInstructions 并序列化注入
```

#### 2. Skill 注入流程

```
用户输入包含 $skill-name
  └─> collect_explicit_skill_mentions()   // skills/injection.rs
        └─> 解析提及的 Skill
  └─> build_skill_injections()
        ├─> 读取 SKILL.md 文件
        └─> 创建 SkillInstructions
              └─> ResponseItem::from(SkillInstructions)
                    └─> SKILL_FRAGMENT.into_message(wrapped_text)
```

### 协议与标记

#### 标记常量（定义在 contextual_user_message.rs）

| 常量 | 值 | 用途 |
|------|-----|------|
| `AGENTS_MD_START_MARKER` | `# AGENTS.md instructions for ` | UserInstructions 开始标记 |
| `AGENTS_MD_END_MARKER` | `</INSTRUCTIONS>` | UserInstructions 结束标记 |
| `SKILL_OPEN_TAG` | `<skill>` | SkillInstructions 开始标记 |
| `SKILL_CLOSE_TAG` | `</skill>` | SkillInstructions 结束标记 |

#### ContextualUserFragmentDefinition

提供统一的片段处理能力：
- `matches_text()`：检测文本是否匹配标记
- `wrap()`：包装内容
- `into_message()`：转换为 `ResponseItem::Message`

### 内存排除策略

在 `contextual_user_message.rs` 中定义：

```rust
pub(crate) fn is_memory_excluded_contextual_user_fragment(content_item: &ContentItem) -> bool {
    // AGENTS.md 和 Skill 指令被排除在内存阶段1输入之外
    // 因为它们是提示脚手架而非对话内容
    AGENTS_MD_FRAGMENT.matches_text(text) || SKILL_FRAGMENT.matches_text(text)
}
```

---

## 关键代码路径与文件引用

### 本目录文件

| 文件 | 职责 |
|------|------|
| `mod.rs` | 模块导出，暴露 `UserInstructions`, `SkillInstructions`, `USER_INSTRUCTIONS_PREFIX` |
| `user_instructions.rs` | 核心数据结构定义和 `From` 转换实现 |
| `user_instructions_tests.rs` | 单元测试 |

### 调用方（上游）

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex.rs:216` | `use crate::instructions::UserInstructions;` | 导入模块 |
| `codex.rs:486` | `let user_instructions = get_user_instructions(&config).await;` | 获取用户指令 |
| `skills/injection.rs:9` | `use crate::instructions::SkillInstructions;` | 导入 Skill 指令 |
| `skills/injection.rs:50-54` | `ResponseItem::from(SkillInstructions { ... })` | 创建 Skill 指令项 |

### 被调用方（下游）

| 文件 | 关系 |
|------|------|
| `contextual_user_message.rs` | 提供 `AGENTS_MD_FRAGMENT` 和 `SKILL_FRAGMENT` 用于序列化 |
| `project_doc.rs` | 实现 `get_user_instructions()`，提供原始指令文本 |

### 依赖模块

```
instructions/
  ├─> contextual_user_message.rs  (AGENTS_MD_FRAGMENT, SKILL_FRAGMENT)
  ├─> project_doc.rs              (get_user_instructions)
  └─> codex_protocol::models::ResponseItem (目标类型)
```

---

## 依赖与外部交互

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化支持 |
| `codex_protocol::models::ResponseItem` | 目标消息类型 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `contextual_user_message` | 获取片段定义和标记常量 |
| `project_doc` | 获取项目级文档内容 |
| `skills/injection` | 调用 SkillInstructions 创建 |

### 配置影响

| 配置项 | 影响 |
|--------|------|
| `config.user_instructions` | 用户自定义指令，与 AGENTS.md 合并 |
| `config.project_doc_max_bytes` | 项目文档大小限制 |
| `config.project_doc_fallback_filenames` | 备选文档文件名 |
| `Feature::ChildAgentsMd` | 启用分层 AGENTS.md 支持 |

---

## 风险、边界与改进建议

### 风险点

1. **标记冲突风险**
   - 如果用户消息恰好以 `# AGENTS.md instructions for ` 开头，可能被误判为指令
   - 当前通过 `matches_text()` 的精确匹配降低风险

2. **序列化格式稳定性**
   - XML 格式的 `<skill>` 标记是硬编码的，变更会影响下游解析
   - 需要保持与模型训练数据的一致性

3. **内存排除副作用**
   - AGENTS.md 和 Skill 指令被排除在内存生成之外
   - 这可能导致长对话中模型"忘记"项目指令

### 边界条件

| 场景 | 行为 |
|------|------|
| AGENTS.md 不存在 | `get_user_instructions()` 返回 `None`，不注入 |
| AGENTS.md 为空 | 被过滤掉，不注入空内容 |
| Skill 文件读取失败 | 记录警告，不中断流程 |
| 项目文档超过大小限制 | 截断处理，记录警告 |

### 改进建议

1. **标记版本控制**
   - 考虑在标记中加入版本信息（如 `<INSTRUCTIONS v2>`）
   - 便于未来格式演进时向后兼容

2. **动态指令刷新**
   - 当前 AGENTS.md 只在会话启动时加载
   - 可考虑文件监视器检测变更并支持热刷新

3. **指令优先级**
   - 当前多个 AGENTS.md 按目录层级简单合并
   - 可考虑添加优先级标记或覆盖机制

4. **测试覆盖**
   - 当前测试仅覆盖基本序列化
   - 建议增加边界条件测试（超大文件、特殊字符等）

---

## 测试说明

测试文件：`user_instructions_tests.rs`

| 测试函数 | 覆盖内容 |
|----------|----------|
| `test_user_instructions()` | UserInstructions 序列化格式验证 |
| `test_is_user_instructions()` | AGENTS_MD_FRAGMENT 匹配逻辑验证 |
| `test_skill_instructions()` | SkillInstructions 序列化格式验证 |
| `test_is_skill_instructions()` | SKILL_FRAGMENT 匹配逻辑验证 |

---

## 总结

`instructions` 模块是 Codex 中**指令管道**的关键组件，负责将外部配置（AGENTS.md、Skills）转换为模型可消费的标准格式。其设计简洁，通过 `ContextualUserFragmentDefinition` 实现了统一的标记处理，同时与 `project_doc` 和 `skills/injection` 紧密协作，构成了完整的指令注入体系。

理解此模块有助于把握 Codex 如何将项目上下文和技能知识注入到 LLM 对话中，是定制和扩展 Codex 行为的重要切入点。
