# user_instructions.rs 研究文档

## 场景与职责

`codex-rs/core/src/instructions/user_instructions.rs` 是 instructions 模块的核心实现文件，负责将两种类型的指令源转换为标准化的 `ResponseItem` 消息格式：

1. **UserInstructions**：来自项目级 `AGENTS.md` 文件的指令，按目录层级组织
2. **SkillInstructions**：来自 `SKILL.md` 文件的 Skill 指令，用于动态注入特定能力

这些指令被包装为特殊的用户消息格式，注入到模型对话上下文中，作为系统级指导。

## 功能点目的

| 功能 | 目的 |
|-----|------|
| `UserInstructions` 结构体 | 封装 AGENTS.md 的指令内容和关联目录 |
| `SkillInstructions` 结构体 | 封装 Skill 的名称、路径和内容 |
| `serialize_to_text()` | 将 AGENTS.md 指令序列化为带标记的文本格式 |
| `From<...> for ResponseItem` | 实现类型转换，统一输出为标准消息格式 |

### 序列化格式

**UserInstructions 输出格式**：
```
# AGENTS.md instructions for {directory}

<INSTRUCTIONS>
{text}
</INSTRUCTIONS>
```

**SkillInstructions 输出格式**：
```xml
<skill>
<name>{name}</name>
<path>{path}</path>
{contents}
</skill>
```

## 具体技术实现

### 数据结构

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "user_instructions", rename_all = "snake_case")]
pub(crate) struct UserInstructions {
    pub directory: String,  // 指令关联的目录路径
    pub text: String,       // 指令内容
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename = "skill_instructions", rename_all = "snake_case")]
pub(crate) struct SkillInstructions {
    pub name: String,       // Skill 名称
    pub path: String,       // SKILL.md 文件路径
    pub contents: String,   // 文件内容
}
```

### 关键流程

#### 1. UserInstructions 序列化流程
```rust
pub(crate) fn serialize_to_text(&self) -> String {
    format!(
        "{prefix}{directory}\n\n<INSTRUCTIONS>\n{contents}\n{suffix}",
        prefix = AGENTS_MD_FRAGMENT.start_marker(),   // "# AGENTS.md instructions for "
        directory = self.directory,
        contents = self.text,
        suffix = AGENTS_MD_FRAGMENT.end_marker(),     // "</INSTRUCTIONS>"
    )
}
```

#### 2. 转换为 ResponseItem 流程
```rust
impl From<UserInstructions> for ResponseItem {
    fn from(ui: UserInstructions) -> Self {
        AGENTS_MD_FRAGMENT.into_message(ui.serialize_to_text())
    }
}

impl From<SkillInstructions> for ResponseItem {
    fn from(si: SkillInstructions) -> Self {
        SKILL_FRAGMENT.into_message(SKILL_FRAGMENT.wrap(format!(
            "<name>{}</name>\n<path>{}</path>\n{}",
            si.name, si.path, si.contents
        )))
    }
}
```

### 依赖的片段定义（来自 contextual_user_message.rs）

| 常量 | 值 | 用途 |
|-----|---|------|
| `AGENTS_MD_START_MARKER` | `"# AGENTS.md instructions for "` | 消息起始标记 |
| `AGENTS_MD_END_MARKER` | `"</INSTRUCTIONS>"` | 消息结束标记 |
| `SKILL_OPEN_TAG` | `"<skill>"` | Skill 消息起始标记 |
| `SKILL_CLOSE_TAG` | `"</skill>"` | Skill 消息结束标记 |

## 关键代码路径与文件引用

### 调用方

1. **`codex-rs/core/src/codex.rs`**（行 3510-3517）
   ```rust
   if let Some(user_instructions) = turn_context.user_instructions.as_deref() {
       contextual_user_sections.push(
           UserInstructions {
               text: user_instructions.to_string(),
               directory: turn_context.cwd.to_string_lossy().into_owned(),
           }
           .serialize_to_text(),
       );
   }
   ```
   - 在构建每轮对话上下文时调用
   - 将 `turn_context` 中的用户指令序列化为文本

2. **`codex-rs/core/src/skills/injection.rs`**（行 50-54）
   ```rust
   result.items.push(ResponseItem::from(SkillInstructions {
       name: skill.name.clone(),
       path: skill.path_to_skills_md.to_string_lossy().into_owned(),
       contents,
   }));
   ```
   - 在构建 Skill 注入时调用
   - 将读取的 SKILL.md 内容转换为 `ResponseItem`

### 被调用方

- **`codex-rs/core/src/contextual_user_message.rs`**
  - `AGENTS_MD_FRAGMENT`：提供 AGENTS.md 消息的格式化能力
  - `SKILL_FRAGMENT`：提供 Skill 消息的格式化能力
  - `ContextualUserFragmentDefinition`：片段定义的通用实现

## 依赖与外部交互

### 内部依赖
| 依赖 | 用途 |
|-----|------|
| `crate::contextual_user_message::AGENTS_MD_FRAGMENT` | AGENTS.md 消息格式定义 |
| `crate::contextual_user_message::SKILL_FRAGMENT` | Skill 消息格式定义 |

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `serde::Deserialize` / `serde::Serialize` | 结构体序列化支持 |
| `codex_protocol::models::ResponseItem` | 目标消息类型 |

## 风险、边界与改进建议

### 风险

1. **序列化格式硬编码**：消息格式（如 `<INSTRUCTIONS>` 标签）分散在多处，修改时需同步更新：
   - `contextual_user_message.rs` 中的常量定义
   - 本文件的 `serialize_to_text` 和 `From` 实现
   - 测试文件中的预期输出

2. **SkillInstructions 内容注入**：`SkillInstructions::contents` 直接嵌入 XML 格式，若内容包含特殊字符（如 `<`, `>`）可能导致格式问题（当前无转义处理）

3. **路径编码**：使用 `to_string_lossy()` 处理路径，非 UTF-8 路径会丢失信息

### 边界情况

1. **空内容处理**：依赖调用方确保 `text` 和 `contents` 非空，本模块无空值检查
2. **特殊字符**：XML/HTML 特殊字符未转义，依赖内容提供者确保格式安全

### 改进建议

1. **集中格式定义**：将消息格式模板集中到 `contextual_user_message.rs`，本模块仅调用模板方法
2. **添加 XML 转义**：对 `SkillInstructions::contents` 进行 XML 特殊字符转义，防止格式破坏
3. **路径处理优化**：考虑使用 `PathBuf` 替代 `String` 存储路径，在序列化时再转换
4. **空值检查**：在 `serialize_to_text` 中添加空内容警告或跳过逻辑
5. **文档完善**：为 `SkillInstructions` 添加使用文档（当前为空实现 `impl SkillInstructions {}`）

### 测试覆盖

测试位于 `user_instructions_tests.rs`，覆盖：
- `UserInstructions` 序列化和转换
- `SkillInstructions` 序列化和转换
- `AGENTS_MD_FRAGMENT.matches_text()` 验证
- `SKILL_FRAGMENT.matches_text()` 验证

建议补充：
- 特殊字符处理测试
- 空内容处理测试
- 非 UTF-8 路径处理测试
