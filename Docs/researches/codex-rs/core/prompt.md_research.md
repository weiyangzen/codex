# prompt.md 研究文档

## 场景与职责

`codex-rs/core/prompt.md` 是 Codex CLI 的核心系统提示词（System Prompt）文件，定义了 AI 编码助手的基础行为准则、能力边界和交互规范。该文件作为基础指令（base instructions）被注入到所有模型交互中，是塑造 AI 助手"人格"和"工作方式"的核心配置。

该 prompt 适用于 OpenAI Codex CLI 这一开源终端编码助手项目，旨在确保 AI 助手在多轮对话中保持一致性、安全性和高效性。

## 功能点目的

### 1. 身份定义与能力声明
- 明确 AI 作为"coding agent"的身份定位
- 声明核心能力：接收用户提示、流式思考与响应、执行终端命令、应用代码补丁
- 区分 Codex（开源 agentic 编码界面）与旧版 Codex 语言模型

### 2. 行为规范与个性设定
- **个性基调**：简洁、直接、友好（concise, direct, and friendly）
- **沟通原则**：高效沟通、优先提供可执行指导、明确假设和前提条件
- **避免过度冗长**：除非用户明确要求，否则避免过度详细的解释

### 3. AGENTS.md 规范
- 定义 AGENTS.md 文件的用途：为人类向 AI 代理提供指令或提示
- 作用域规则：文件作用域为所在文件夹及其子树
- 优先级规则：嵌套越深的 AGENTS.md 优先级越高，直接指令优先于 AGENTS.md

### 4. 响应与前置消息规范
- **前置消息（Preamble）**：工具调用前向用户简要说明即将执行的操作
- 分组原则：相关操作逻辑分组，在一个前置消息中描述
- 简洁性：1-2 句话，8-12 词快速更新
- 上下文关联：非首次调用时，关联之前的工作进展
- 语气：轻松、友好、好奇，增加协作感

### 5. 计划（Planning）规范
- `update_plan` 工具的使用场景和最佳实践
- 高质量计划的特征：具体、可验证的步骤（5-7 词/步）
- 低质量计划的反例：过于笼统、缺乏可验证性
- 计划更新规则：标记完成状态、解释变更理由

### 6. 任务执行规范
- **核心原则**：自主解决问题，不猜测、不编造答案
- **工具使用**：必须使用 `apply_patch` 工具编辑文件（禁止 `applypatch` 或 `apply-patch`）
- **代码修改原则**：修复根本原因、避免不必要复杂性、不修复无关 bug
- **版本控制**：不自动执行 git commit/branch，除非明确要求
- **验证工作**：优先使用特定测试，逐步扩展到更广泛的测试

### 7. 野心与精确度平衡
- **新任务**：可以雄心勃勃，展示创造力
- **现有代码库**：精确执行用户要求，尊重现有代码，不过度修改

### 8. 进度更新与工作汇报
- 长任务需要定期进度更新（8-10 词）
- 大段工作前发送简洁消息说明即将做什么
- 最终消息应自然、像队友交接工作

### 9. 最终答案格式规范
- **节标题**：使用 `**Title Case**` 格式，1-3 词，仅在提升清晰度时使用
- **项目符号**：使用 `-` 开头，合并相关点，每组 4-6 个
- **等宽字体**：命令、路径、环境变量、代码标识符使用反引号
- **文件引用**：包含行号，不使用 URI 格式
- **结构**：相关项目分组，从一般到具体
- **语气**：协作自然、简洁事实、现在时主动语态

### 10. 工具使用指南
- **Shell 命令**：优先使用 `rg` 搜索，不使用 Python 脚本输出大文件
- **`update_plan`**：创建、更新计划的规范
- **`apply_patch`**：详细的补丁格式规范

## 具体技术实现

### 编译时嵌入
```rust
// codex-rs/core/src/models_manager/model_info.rs:17
pub const BASE_INSTRUCTIONS: &str = include_str!("../../prompt.md");
```

### 模型信息构建流程
1. `model_info_from_slug()` 函数创建回退模型描述符时使用 `BASE_INSTRUCTIONS`
2. `with_config_overrides()` 函数根据配置覆盖基础指令
3. 支持通过 `config.base_instructions` 完全自定义基础指令

### 个性化消息模板
```rust
// model_info.rs:96-110
fn local_personality_messages_for_slug(slug: &str) -> Option<ModelMessages> {
    match slug {
        "gpt-5.2-codex" | "exp-codex-personality" => Some(ModelMessages {
            instructions_template: Some(format!(
                "{DEFAULT_PERSONALITY_HEADER}\n\n{PERSONALITY_PLACEHOLDER}\n\n{BASE_INSTRUCTIONS}"
            )),
            instructions_variables: Some(ModelInstructionsVariables {
                personality_default: Some(String::new()),
                personality_friendly: Some(LOCAL_FRIENDLY_TEMPLATE.to_string()),
                personality_pragmatic: Some(LOCAL_PRAGMATIC_TEMPLATE.to_string()),
            }),
        }),
        _ => None,
    }
}
```

## 关键代码路径与文件引用

### 主要引用点
| 文件 | 行号 | 用途 |
|------|------|------|
| `codex-rs/core/src/models_manager/model_info.rs` | 17 | 定义 `BASE_INSTRUCTIONS` 常量 |
| `codex-rs/core/src/models_manager/model_info.rs` | 75 | 回退模型元数据使用基础指令 |
| `codex-rs/core/src/models_manager/model_info.rs` | 100 | 个性化模板嵌入基础指令 |

### 配置覆盖路径
```
Config::base_instructions -> model_info::with_config_overrides() -> ModelInfo::base_instructions
```

### 测试验证
- `codex-rs/core/src/codex_tests.rs`：测试基础指令的生成和覆盖逻辑

## 依赖与外部交互

### 内部依赖
- `codex_protocol::openai_models::ModelInfo`：模型信息结构体
- `codex_protocol::openai_models::ModelMessages`：模型消息模板
- `codex_protocol::openai_models::ModelInstructionsVariables`：指令变量

### 配置系统交互
- `Config::base_instructions`：用户自定义基础指令配置
- `Config::features`：特性开关（如 Personality 特性影响指令生成）

### 模型提供者交互
- 模型元数据通过 `models.json` 加载
- 未知模型 slug 时使用 `BASE_INSTRUCTIONS` 作为回退

## 风险、边界与改进建议

### 风险点
1. **指令注入风险**：`prompt.md` 内容直接嵌入到模型指令中，若被篡改可能导致 AI 行为异常
2. **版本兼容性**：prompt 修改可能影响所有模型的行为，需要广泛的回归测试
3. **配置覆盖复杂性**：多层配置覆盖（默认 → 配置文件 → 运行时覆盖）可能导致指令内容难以预测

### 边界条件
1. **模型特定处理**：仅特定模型（如 `gpt-5.2-codex`）支持个性化消息模板
2. **特性开关依赖**：Personality 特性禁用时会简化指令生成
3. **最大 Token 限制**：基础指令长度受模型上下文窗口限制

### 改进建议
1. **版本化 Prompt**：考虑为 prompt.md 引入版本号，便于追踪变更影响
2. **A/B 测试支持**：增加按会话或用户分组的 prompt 实验能力
3. **动态加载**：当前为编译时嵌入，可考虑支持运行时热更新（开发模式）
4. **文档化变更影响**：建立 prompt 变更的自动化测试套件，验证对模型输出的影响
5. **多语言支持**：当前仅支持英文，考虑国际化支持架构

### 相关文件监控
- 修改 `prompt.md` 后需同步检查：
  - `codex-rs/core/src/models_manager/model_info.rs`：确保正确加载
  - `codex-rs/core/src/codex_tests.rs`：更新相关测试预期
  - `codex-rs/core/BUILD.bazel`：确保文件被包含在编译数据中
