# mod.rs 研究文档

## 场景与职责

`codex-rs/core/src/instructions/mod.rs` 是 `instructions` 模块的入口文件（模块根），负责统一暴露子模块的公共 API。该模块整体负责将用户指令（来自 AGENTS.md 文件）和 Skill 指令转换为模型可消费的 `ResponseItem` 消息格式。

在 Codex 架构中，instructions 模块位于核心层（core），承上启下：
- **上游**：被 `codex.rs`（主会话逻辑）和 `skills/injection.rs`（Skill 注入逻辑）调用
- **下游**：依赖 `contextual_user_message.rs` 提供的片段定义和 `protocol` crate 提供的 `ResponseItem` 模型

## 功能点目的

该文件仅包含模块声明和符号重导出，具体功能在子模块实现：

| 导出符号 | 来源 | 用途 |
|---------|------|------|
| `SkillInstructions` | `user_instructions` | 封装 Skill 的指令内容（SKILL.md），用于注入到对话上下文 |
| `USER_INSTRUCTIONS_PREFIX` | `user_instructions` | AGENTS.md 指令消息的前缀标记常量 |
| `UserInstructions` | `user_instructions` | 封装项目级 AGENTS.md 指令，关联到特定目录 |

## 具体技术实现

### 模块结构
```
instructions/
├── mod.rs                 # 本文件：模块入口，API 暴露
├── user_instructions.rs   # 核心实现：UserInstructions 和 SkillInstructions 结构体
└── user_instructions_tests.rs  # 单元测试
```

### 导出策略
- `pub(crate) use`：模块内部可见，用于 `codex.rs` 和 `skills/injection.rs`
- `pub use`：完全公开，供外部 crate 使用（如 `USER_INSTRUCTIONS_PREFIX`）

## 关键代码路径与文件引用

### 调用方（上游）
1. **`codex-rs/core/src/codex.rs`**（行 216, 3510-3517）
   - 导入 `UserInstructions`
   - 在构建对话上下文时，将 `turn_context.user_instructions` 序列化为文本格式
   
2. **`codex-rs/core/src/skills/injection.rs`**（行 9, 50-54）
   - 导入 `SkillInstructions`
   - 在 `build_skill_injections` 函数中，将读取的 SKILL.md 内容包装为 `SkillInstructions`，并转换为 `ResponseItem`

### 被调用方（下游）
- **`codex-rs/core/src/instructions/user_instructions.rs`**：实际实现
- **`codex-rs/core/src/contextual_user_message.rs`**：提供 `AGENTS_MD_FRAGMENT` 和 `SKILL_FRAGMENT` 用于消息格式化

## 依赖与外部交互

### 内部依赖
| 依赖 | 用途 |
|-----|------|
| `user_instructions` 子模块 | 结构体和实现 |

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `codex_protocol::models::ResponseItem` | 目标消息格式 |

## 风险、边界与改进建议

### 风险
1. **API 稳定性**：`pub use` 暴露的 `USER_INSTRUCTIONS_PREFIX` 被外部依赖后，修改会影响兼容性
2. **模块职责单一**：本文件过于简单，仅做重导出，未来若增加更多指令类型可能需要重构

### 边界情况
- 无直接边界处理逻辑（均在子模块实现）

### 改进建议
1. **文档增强**：可添加模块级文档注释说明整体职责
2. **可见性审查**：`SkillInstructions` 目前为 `pub(crate)`，若未来 Skill 功能需要外部扩展，可能需要提升为 `pub`
3. **合并考虑**：若模块长期保持简单，可考虑与父模块合并，减少文件数量
