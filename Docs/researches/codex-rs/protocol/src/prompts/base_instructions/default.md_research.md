# Research: codex-rs/protocol/src/prompts/base_instructions/default.md

## 场景与职责

`default.md` 是 Codex CLI 的核心系统提示词（System Prompt）模板文件，定义了 AI 编码助手的基础行为准则、人格特质和工具使用规范。该文件作为编译期资源嵌入到 `codex-protocol` crate 中，通过 `include_str!` 宏加载，成为所有 Codex 会话的默认基础指令（Base Instructions）。

**核心职责：**
1. **身份定义**：明确 Codex 作为开源终端编码助手的定位，区别于旧版 OpenAI Codex 语言模型
2. **行为规范**：定义 AI 的人格特质（简洁、直接、友好）、响应风格和工作流程
3. **工具使用指南**：详细说明 `apply_patch` 工具的正确使用方式、补丁格式规范
4. **AGENTS.md 规范**：定义仓库级代理指令文件的解析和优先级规则
5. **沙箱与审批策略**：说明命令执行的安全边界和用户审批流程

**使用场景：**
- 新会话启动时作为系统级基础指令注入
- 作为 `BaseInstructions` 类型的默认值（`BASE_INSTRUCTIONS_DEFAULT` 常量）
- 通过配置层（config）可被用户自定义指令覆盖
- 在模型切换时保持会话行为一致性

---

## 功能点目的

### 1. 身份与能力声明
- **目的**：建立 AI 助手的身份认知，明确其运行环境（终端 CLI）和核心能力（接收提示、流式响应、函数调用）
- **关键内容**：强调 Codex 是开源项目，与旧版 Codex 模型区分，设定"精确、安全、有帮助"的核心价值观

### 2. 人格与沟通风格（Personality）
- **目的**：确保 AI 输出风格一致，符合开发者协作场景的需求
- **关键要素**：
  - 简洁直接，避免冗余解释
  - 优先提供可操作的指导
  - 明确假设、环境前提和后续步骤
  - 避免过度热情或空洞的鼓励性语言

### 3. AGENTS.md 规范系统
- **目的**：支持仓库级别的自定义指令，使 AI 能适配不同项目的编码规范
- **核心规则**：
  - 文件作用域：包含该文件的目录树
  - 优先级：嵌套越深优先级越高
  - 显式指令优先于 AGENTS.md 指令
  - 自动包含从 CWD 到根路径的所有 AGENTS.md 文件

### 4. 前置消息规范（Preamble Messages）
- **目的**：在执行工具调用前向用户提供上下文说明，增强透明度和用户体验
- **规范要求**：
  - 逻辑分组相关操作
  - 保持简洁（1-2 句话，8-12 词）
  - 建立上下文连续性
  - 保持轻松友好的语调

### 5. 计划工具使用规范（Planning）
- **目的**：指导 AI 正确使用 `update_plan` 工具进行任务规划
- **质量标准**：
  - 高质量计划：具体、可验证的步骤
  - 避免填充式步骤或显而易见的陈述
  - 适时更新计划并提供变更理由

### 6. 补丁应用规范（Patch Application）
- **目的**：确保代码修改的格式正确、可验证、安全
- **详细规则**：
  - 统一补丁格式（`*** Begin Patch` / `*** End Patch`）
  - 文件路径规范（支持工作区相对路径、绝对路径）
  - 变更标记规范（`+` 添加、`-` 删除、` ` 上下文）
  - 多文件补丁支持
  - 移动/重命名检测（低置信度时提示用户）

### 7. 沙箱与审批策略（Sandbox & Approvals）
- **目的**：定义命令执行的安全边界和用户审批流程
- **覆盖场景**：
  - 沙箱模式（只读、工作区写入、完全访问）
  - 网络访问控制
  - 命令前缀规则（自动审批可信命令）
  - 失败时的升级审批流程

### 8. 任务执行准则
- **目的**：确保 AI 自主、完整地解决用户问题
- **核心原则**：
  - 持续工作直到问题完全解决
  - 使用可用工具自主解决问题
  - 不猜测或编造答案
  - 遵循代码库现有风格

### 9. 工作验证规范
- **目的**：确保代码修改的正确性和完整性
- **要求**：
  - 优先使用具体测试验证
  - 渐进式扩大测试范围
  - 不修复无关的 bug 或测试失败

### 10. 最终回复格式规范
- **目的**：统一 AI 输出格式，提升可读性和实用性
- **规范细节**：
  - 章节标题格式（`**Title Case**`）
  - 项目符号使用（`- ` 开头）
  - 代码和路径使用反引号包裹
  - 文件引用格式（支持行号）
  - 避免 ANSI 转义码和深层嵌套

---

## 具体技术实现

### 编译期嵌入机制

```rust
// codex-rs/protocol/src/models.rs:450
pub const BASE_INSTRUCTIONS_DEFAULT: &str = include_str!("prompts/base_instructions/default.md");
```

该常量通过 Rust 的 `include_str!` 宏在编译时将文件内容嵌入二进制，确保：
- 运行时无需文件系统访问即可获取基础指令
- 指令内容与代码版本强绑定
- 分发时无需额外资源文件

### Bazel 构建配置

```bazel
# codex-rs/protocol/BUILD.bazel
codex_rust_crate(
    name = "protocol",
    crate_name = "codex_protocol",
    compile_data = glob(["src/prompts/**/*.md"]),
)
```

`compile_data` 属性确保所有 `.md` 提示词文件在编译时可用，支持 `include_str!` 宏的解析。

### 数据结构定义

```rust
// codex-rs/protocol/src/models.rs:453-465
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(rename = "base_instructions", rename_all = "snake_case")]
pub struct BaseInstructions {
    pub text: String,
}

impl Default for BaseInstructions {
    fn default() -> Self {
        Self {
            text: BASE_INSTRUCTIONS_DEFAULT.to_string(),
        }
    }
}
```

`BaseInstructions` 结构体封装基础指令文本，支持序列化（JSON/TypeScript）和默认值。

### 指令解析优先级链

在 `codex-core` 中，基础指令的解析遵循以下优先级（`codex.rs:520-529`）：

1. **配置层覆盖**：`config.base_instructions`（用户自定义）
2. **会话历史**：`conversation_history.get_base_instructions()`（恢复会话）
3. **模型默认**：`model_info.get_model_instructions()`（模型特定指令）

```rust
let base_instructions = config
    .base_instructions
    .clone()
    .or_else(|| conversation_history.get_base_instructions().map(|s| s.text))
    .unwrap_or_else(|| model_info.get_model_instructions(config.personality));
```

### 模型特定指令模板

`codex-core` 中的 `model_info.rs` 支持基于模板的个性化指令：

```rust
const DEFAULT_PERSONALITY_HEADER: &str = "You are Codex, a coding agent based on GPT-5...";
const PERSONALITY_PLACEHOLDER: &str = "{{ personality }}";

// 模板结构：Header + Personality + Base Instructions
let template = format!(
    "{DEFAULT_PERSONALITY_HEADER}\n\n{PERSONALITY_PLACEHOLDER}\n\n{BASE_INSTRUCTIONS}"
);
```

支持三种人格变体：
- `None`：无个性化
- `Friendly`：支持型队友风格
- `Pragmatic`：深度务实工程师风格

### 与 Responses API 的集成

在 `client.rs` 中，基础指令作为 `instructions` 参数传递给 OpenAI Responses API：

```rust
let instructions = prompt.base_instructions.text.clone();
let payload = ApiCompactionInput {
    model: &model_info.slug,
    input: &input,
    instructions: &instructions,  // 基础指令注入
    tools,
    // ...
};
```

---

## 关键代码路径与文件引用

### 定义与嵌入

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/prompts/base_instructions/default.md` | 1-275 | 基础指令模板文件（本文档研究对象） |
| `codex-rs/protocol/src/models.rs` | 450 | `BASE_INSTRUCTIONS_DEFAULT` 常量定义 |
| `codex-rs/protocol/src/models.rs` | 453-465 | `BaseInstructions` 结构体定义 |
| `codex-rs/protocol/BUILD.bazel` | 6 | Bazel 编译数据配置（`compile_data`） |

### 核心使用路径

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/core/src/codex.rs` | 520-529 | 基础指令优先级解析逻辑 |
| `codex-rs/core/src/codex.rs` | 576 | `SessionConfiguration` 中存储基础指令 |
| `codex-rs/core/src/codex.rs` | 2067-2071 | `get_base_instructions()` 方法实现 |
| `codex-rs/core/src/client.rs` | 369 | 从 prompt 提取基础指令传递给 API |
| `codex-rs/core/src/models_manager/model_info.rs` | 17 | 本地基础指令（`prompt.md`）定义 |
| `codex-rs/core/src/models_manager/model_info.rs` | 50-55 | 配置覆盖逻辑 |

### 配置与覆盖

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/core/src/config/mod.rs` | 290 | `base_instructions` 配置字段定义 |
| `codex-rs/core/src/config/mod.rs` | 2519-2521 | 配置文件加载逻辑 |
| `codex-rs/protocol/src/openai_models.rs` | 257 | `ModelInfo.base_instructions` 字段 |
| `codex-rs/protocol/src/openai_models.rs` | 316-336 | `get_model_instructions()` 方法 |

### 序列化与持久化

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/protocol.rs` | 2378-2381 | `TurnContext` 中 `base_instructions` 字段 |
| `codex-rs/protocol/src/protocol.rs` | 2225-2236 | `get_base_instructions()` 从历史恢复 |
| `codex-rs/core/src/rollout/recorder.rs` | 84, 113, 382, 410 | 会话元数据记录基础指令 |

### 测试覆盖

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/core/src/codex_tests.rs` | 501-552 | 基础指令获取测试 |
| `codex-rs/core/src/codex_tests.rs` | 1021-1045 | Token 计算包含基础指令测试 |
| `codex-rs/core/tests/suite/personality.rs` | 44-74 | 人格模板不修改基础指令测试 |
| `codex-rs/core/tests/suite/client.rs` | 662-690 | 基础指令覆盖传递给 API 测试 |
| `codex-rs/protocol/src/openai_models.rs` | 576-632 | 人格消息替换测试 |

---

## 依赖与外部交互

### 内部依赖

```
default.md
    ↓ include_str!
codex-protocol (models.rs)
    ↓ BaseInstructions 类型
codex-core
    ├── codex.rs (会话初始化、指令优先级解析)
    ├── client.rs (API 调用注入)
    ├── models_manager/model_info.rs (模型特定指令)
    └── config/mod.rs (用户配置覆盖)
```

### 外部 API 交互

1. **OpenAI Responses API**：基础指令作为 `instructions` 参数传递给 `/v1/responses` 端点
2. **模型元数据服务**：`core/models.json` 包含各模型的基础指令覆盖
3. **配置系统**：用户可通过 `~/.codex/config.toml` 或 CLI 参数覆盖基础指令

### 配置覆盖机制

用户可通过以下方式自定义基础指令：

```toml
# ~/.codex/config.toml
base_instructions = "自定义系统提示词"
# 或指向文件
base_instructions_file = "/path/to/custom_instructions.md"
```

CLI 参数：
```bash
codex --base-instructions "自定义提示词"
codex --base-instructions-file /path/to/file.md
```

### 相关提示词文件

| 文件 | 用途 |
|------|------|
| `prompts/permissions/approval_policy/*.md` | 审批策略说明（Never/UnlessTrusted/OnFailure/OnRequest） |
| `prompts/permissions/sandbox_mode/*.md` | 沙箱模式说明（ReadOnly/WorkspaceWrite/DangerFullAccess） |
| `prompts/realtime/realtime_start.md` | 实时对话开始指令 |
| `prompts/realtime/realtime_end.md` | 实时对话结束指令 |

---

## 风险、边界与改进建议

### 已知风险

1. **指令注入风险**
   - 用户自定义基础指令可能包含恶意提示注入
   - 缓解：通过配置系统限制，但无运行时过滤

2. **版本不一致**
   - 编译期嵌入的指令与运行时模型元数据中的指令可能不同步
   - 表现：`core/models.json` 中的 `base_instructions` 可能与 `default.md` 内容冲突

3. **Token 开销**
   - 基础指令约 275 行，每次请求都会占用显著 Token
   - 影响：增加 API 成本和延迟

4. **人格模板覆盖**
   - 当使用人格模板时，`{{ personality }}` 占位符替换可能失败
   - 回退逻辑：使用原始 `base_instructions`（`openai_models.rs:331`）

### 边界条件

1. **空指令处理**
   - 空字符串基础指令被视为有效，可能导致模型行为不可预测
   - 无强制最小长度验证

2. **超长指令**
   - 无最大长度限制，极端情况下可能超出 API 上下文窗口
   - 依赖上游 API 的错误处理

3. **编码问题**
   - 文件使用 UTF-8 编码，无 BOM 处理
   - 非 ASCII 字符在旧版终端可能显示异常

4. **并发修改**
   - 编译期嵌入意味着运行时无法热更新指令
   - 需要重新编译才能更新基础行为

### 改进建议

1. **指令版本控制**
   ```rust
   // 建议添加版本标识
   pub const BASE_INSTRUCTIONS_VERSION: &str = "2025.03.23";
   ```
   便于追踪指令变更和兼容性管理。

2. **动态指令加载**
   - 支持从远程配置中心加载基础指令
   - 允许 A/B 测试不同指令版本
   - 保持编译期默认值作为回退

3. **Token 优化**
   - 压缩指令文本（去除冗余空格、注释）
   - 提供精简版基础指令选项
   - 按需加载（如非代码任务可省略代码特定指令）

4. **指令验证**
   ```rust
   // 建议添加验证逻辑
   impl BaseInstructions {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 检查最小长度
           // 检查必需章节存在
           // 检查格式规范
       }
   }
   ```

5. **多语言支持**
   - 当前仅英文，考虑 i18n 框架
   - 根据用户 locale 自动选择对应语言版本

6. **指令组合机制**
   - 支持模块化指令（核心 + 可选扩展）
   - 例如：基础指令 + 语言特定指令 + 项目特定指令

7. **运行时调试**
   - 添加指令内容日志（脱敏后）
   - 提供 `/debug base_instructions` 命令查看实际发送的指令

8. **与 AGENTS.md 的协同**
   - 优化 AGENTS.md 和基础指令的合并逻辑
   - 避免重复或冲突的指令内容
   - 提供合并预览功能

### 监控指标建议

- 基础指令 Token 占用比例
- 用户自定义指令使用率
- 指令版本与模型响应质量相关性
- 不同人格模板的采用率

---

## 附录：文件内容摘要

`default.md` 包含以下主要章节：

1. **身份声明**（Lines 1-9）：Codex CLI 开源项目介绍
2. **How you work**（Lines 11-15）：人格特质概述
3. **AGENTS.md spec**（Lines 17-27）：仓库级指令规范
4. **Responsiveness**（Lines 29-50）：前置消息规范
5. **Planning**（Lines 52-121）：计划工具使用指南
6. **Task execution**（Lines 123-147）：任务执行准则
7. **Validating your work**（Lines 149-163）：工作验证规范
8. **Ambition vs. precision**（Lines 165-171）：精确性与创造性平衡
9. **Sharing progress updates**（Lines 173-178）：进度更新规范
10. **Presenting your work**（Lines 181-256）：最终回复格式规范
11. **Tool Guidelines**（Lines 258-275）：工具使用指南（Shell、update_plan）
