# DIR codex-rs/core/templates 研究文档

## 场景与职责

`codex-rs/core/templates` 目录是 Codex 核心模块的**提示词模板仓库**，负责存储所有用于与 LLM 交互的静态和动态模板文件。这些模板定义了：

1. **Agent 行为准则**：Orchestrator Agent 的核心指令
2. **协作模式**：Plan/Execute/Default/Pair Programming 四种协作模式的系统提示
3. **记忆系统**：Phase 1/Phase 2 记忆提取和整合的完整提示词流程
4. **工具描述**：tool_search、tool_suggest、presentation_artifact 等工具的动态描述模板
5. **Review 流程**：代码审查成功/中断的 XML 消息模板
6. **人格化配置**：Friendly/Pragmatic 两种人格的模板定义
7. **上下文压缩**：Compact 模式的总结提示词

该目录是 Codex "大脑" 的重要组成部分，直接影响模型的行为模式、输出格式和交互风格。

## 功能点目的

### 1. Agent 指令模板 (`agents/`)
- **orchestrator.md**: 定义主 Agent 的核心身份、工具使用规范、子 Agent 管理策略
- 目的：确保主 Agent 在多 Agent 协作场景下正确调度任务

### 2. 协作模式模板 (`collaboration_mode/`)
- **plan.md**: 规划模式的 3 阶段流程（环境探索→意图确认→实现规划）
- **execute.md**: 执行模式的假设优先、里程碑驱动执行策略
- **default.md**: 默认协作模式，支持动态变量替换（`{{KNOWN_MODE_NAMES}}` 等）
- **pair_programming.md**: 结对编程的实时协作风格
- 目的：通过不同的系统提示词切换 Agent 的行为模式

### 3. 记忆系统模板 (`memories/`)
- **stage_one_system.md**: Phase 1 记忆提取的完整系统提示（569 行）
- **stage_one_input.md**: Phase 1 用户消息模板（Askama 模板）
- **consolidation.md**: Phase 2 记忆整合的完整系统提示（835 行）
- **read_path.md**: Memory Tool 的开发者指令模板
- 目的：实现从原始对话到结构化记忆的自动化提取和整合

### 4. 工具描述模板 (`search_tool/`, `tools/`)
- **tool_description.md**: tool_search 工具的动态描述，支持 `{{app_descriptions}}` 变量
- **tool_suggest_description.md**: tool_suggest 工具的动态描述，支持 `{{discoverable_tools}}` 变量
- **presentation_artifact.md**: PPT 工具（200 行完整功能描述）
- 目的：允许工具描述根据运行时上下文动态生成

### 5. Review 模板 (`review/`)
- **exit_success.xml**: Review 成功时的用户消息模板（`{results}` 变量）
- **exit_interrupted.xml**: Review 中断时的用户消息模板
- **history_message_completed.md/interrupted.md**: 历史消息格式
- 目的：统一 Review 流程的用户反馈格式

### 6. 人格化模板 (`personalities/`)
- **gpt-5.2-codex_friendly.md**: 友好型人格（强调同理心、协作、鼓励）
- **gpt-5.2-codex_pragmatic.md**: 务实型人格（强调清晰、实用、严谨）
- 目的：支持不同用户偏好的交互风格

### 7. 上下文压缩模板 (`compact/`)
- **prompt.md**: 上下文检查点压缩的指令
- **summary_prefix.md**: 总结消息的前缀标记
- 目的：在长对话中压缩历史上下文，减少 Token 消耗

### 8. 实验性协作提示 (`collab/`)
- **experimental_prompt.md**: 多 Agent 协作的实验性提示
- 目的：支持子 Agent 的并行调度和管理

### 9. 模型指令模板 (`model_instructions/`)
- **gpt-5.2-codex_instructions_template.md**: 基础指令模板（80 行）
- 目的：定义模型的基础行为约束和输出格式

## 具体技术实现

### 模板加载机制

```rust
// 静态编译时加载（include_str!）
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");

// 动态模板渲染（Askama）
#[derive(Template)]
#[template(path = "memories/consolidation.md", escape = "none")]
struct ConsolidationPromptTemplate<'a> {
    memory_root: &'a str,
    phase2_input_selection: &'a str,
}
```

### 变量替换机制

**简单字符串替换**（`collaboration_mode_presets.rs`）：
```rust
const KNOWN_MODE_NAMES_PLACEHOLDER: &str = "{{KNOWN_MODE_NAMES}}";
const REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER: &str = "{{REQUEST_USER_INPUT_AVAILABILITY}}";

COLLABORATION_MODE_DEFAULT
    .replace(KNOWN_MODE_NAMES_PLACEHOLDER, &known_mode_names)
    .replace(REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER, &request_user_input_availability)
```

**工具描述动态生成**（`tools/spec.rs`）：
```rust
const TOOL_SEARCH_DESCRIPTION_TEMPLATE: &str = include_str!("../../templates/search_tool/tool_description.md");

let description = TOOL_SEARCH_DESCRIPTION_TEMPLATE.replace("{{app_descriptions}}", app_descriptions.as_str());
```

### Askama 模板渲染（`memories/prompts.rs`）

```rust
#[derive(Template)]
#[template(path = "memories/stage_one_input.md", escape = "none")]
struct StageOneInputTemplate<'a> {
    rollout_path: &'a str,
    rollout_cwd: &'a str,
    rollout_contents: &'a str,
}

pub(super) fn build_stage_one_input_message(...) -> anyhow::Result<String> {
    let truncated_rollout_contents = truncate_text(rollout_contents, TruncationPolicy::Tokens(rollout_token_limit));
    StageOneInputTemplate {
        rollout_path: &rollout_path,
        rollout_cwd: &rollout_cwd,
        rollout_contents: &truncated_rollout_contents,
    }.render()
}
```

### Review 消息构建（`client_common.rs`）

```rust
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str = include_str!("../templates/review/exit_interrupted.xml");

// 使用时通过 format! 替换变量
let message = REVIEW_EXIT_SUCCESS_TMPL.replace("{results}", &findings);
```

## 关键代码路径与文件引用

### 模板定义文件

| 模板文件 | 用途 | 调用方 |
|---------|------|--------|
| `agents/orchestrator.md` | 主 Agent 指令 | （被引用但未直接加载） |
| `collaboration_mode/plan.md` | Plan 模式 | `models_manager/collaboration_mode_presets.rs:6` |
| `collaboration_mode/default.md` | Default 模式 | `models_manager/collaboration_mode_presets.rs:8` |
| `collaboration_mode/execute.md` | Execute 模式 | （被引用） |
| `collaboration_mode/pair_programming.md` | Pair 模式 | （被引用） |
| `compact/prompt.md` | 压缩提示 | `compact.rs:31` |
| `compact/summary_prefix.md` | 总结前缀 | `compact.rs:32` |
| `memories/stage_one_system.md` | Phase 1 系统提示 | `memories/mod.rs:39` |
| `memories/stage_one_input.md` | Phase 1 输入模板 | `memories/prompts.rs:24` (Askama) |
| `memories/consolidation.md` | Phase 2 整合提示 | `memories/prompts.rs:16` (Askama) |
| `memories/read_path.md` | Memory Tool 指令 | `memories/prompts.rs:31` (Askama) |
| `personalities/gpt-5.2-codex_*.md` | 人格模板 | （被引用） |
| `review/exit_success.xml` | Review 成功消息 | `client_common.rs:21` |
| `review/exit_interrupted.xml` | Review 中断消息 | `client_common.rs:23` |
| `search_tool/tool_description.md` | 工具搜索描述 | `tools/spec.rs:62` |
| `search_tool/tool_suggest_description.md` | 工具建议描述 | `tools/spec.rs:64` |
| `tools/presentation_artifact.md` | PPT 工具描述 | （被引用） |

### 核心调用代码

1. **协作模式初始化**: `codex-rs/core/src/models_manager/collaboration_mode_presets.rs`
   - `builtin_collaboration_mode_presets()` 加载 Plan/Default 模式
   - `default_mode_instructions()` 执行变量替换

2. **上下文压缩**: `codex-rs/core/src/compact.rs`
   - `SUMMARIZATION_PROMPT` 用于压缩任务
   - `SUMMARY_PREFIX` 用于标记总结消息

3. **记忆系统**: `codex-rs/core/src/memories/prompts.rs`
   - `build_consolidation_prompt()` 渲染整合提示
   - `build_stage_one_input_message()` 渲染 Phase 1 输入
   - `build_memory_tool_developer_instructions()` 渲染 Memory Tool 指令

4. **工具描述**: `codex-rs/core/src/tools/spec.rs`
   - `create_tool_search_tool()` 动态生成工具搜索描述
   - `create_tool_suggest_tool()` 动态生成工具建议描述

5. **Review 流程**: `codex-rs/core/src/client_common.rs`
   - `REVIEW_PROMPT` 主 Review 提示
   - `REVIEW_EXIT_SUCCESS_TMPL` / `REVIEW_EXIT_INTERRUPTED_TMPL` 结果消息

6. **模型信息**: `codex-rs/core/src/models_manager/model_info.rs`
   - `BASE_INSTRUCTIONS` 基础指令
   - `local_personality_messages_for_slug()` 人格化消息

## 依赖与外部交互

### 编译时依赖

1. **Rust `include_str!` 宏**: 所有 `.md` 文件在编译时嵌入二进制
2. **Askama 模板引擎**: `memories/*.md` 使用 Askama 进行运行时渲染
   - 模板路径解析依赖 `CARGO_MANIFEST_DIR` 环境变量
   - Bazel 构建时需特殊处理（见 `BUILD.bazel:35-39`）

### Bazel 构建配置

```bazel
# BUILD.bazel
exports_files([
    "templates/collaboration_mode/default.md",
    "templates/collaboration_mode/plan.md",
], visibility = ["//visibility:public"])

codex_rust_crate(
    name = "core",
    compile_data = glob(include = ["**"], ...),
    rustc_env = {
        "CARGO_MANIFEST_DIR": "codex-rs/core",
    },
)
```

### 运行时依赖

1. **变量替换数据源**:
   - `app_descriptions`: MCP 服务器提供的工具元数据
   - `discoverable_tools`: 插件市场发现的工具列表
   - `memory_summary`: 用户记忆摘要文件内容
   - `rollout_contents`: 原始对话记录

2. **配置系统**:
   - `CollaborationModesConfig`: 控制 Default 模式的 `request_user_input` 可用性
   - `ModelInfo`: 提供模型上下文窗口等元数据

### 跨模块交互

```
templates/
  ├── collaboration_mode/  ←→  models_manager/collaboration_mode_presets.rs
  ├── compact/             ←→  compact.rs
  ├── memories/            ←→  memories/prompts.rs (Askama)
  ├── review/              ←→  client_common.rs
  ├── search_tool/         ←→  tools/spec.rs
  └── personalities/       ←→  models_manager/model_info.rs
```

## 风险、边界与改进建议

### 当前风险

1. **模板膨胀风险**: `memories/consolidation.md` (835 行) 和 `stage_one_system.md` (569 行) 过大
   - 影响：增加编译后二进制体积
   - 缓解：已使用 `include_str!` 避免运行时文件读取

2. **变量替换脆弱性**: 简单字符串替换（`replace()`）没有类型检查
   - 风险：模板变量名拼写错误导致静默失败
   - 示例：`{{KNOWN_MODE_NAMES}}` vs `{{KNOWN_MODE_NAME}}`

3. **Askama 模板路径硬编码**: 模板路径在 Rust 代码中硬编码
   - 风险：重命名模板文件会导致编译失败
   - 位置：`memories/prompts.rs:16,24,31`

4. **Bazel/Cargo 路径差异**: `CARGO_MANIFEST_DIR` 在 Bazel 中需要手动设置
   - 风险：模板路径解析在两种构建系统中行为不一致
   - 缓解：`BUILD.bazel:38` 显式设置 `rustc_env`

### 边界情况

1. **Token 限制处理**: Phase 1 输入模板会根据模型上下文窗口自动截断
   ```rust
   // memories/prompts.rs:133-139
   let rollout_token_limit = model_info
       .context_window
       .map(|limit| limit * effective_context_window_percent / 100)
       .map(|limit| limit * CONTEXT_WINDOW_PERCENT / 100)
   ```

2. **空记忆处理**: Memory Tool 在 `memory_summary.md` 为空时返回 `None`
   ```rust
   // memories/prompts.rs:170-172
   if memory_summary.is_empty() {
       return None;
   }
   ```

3. **模板渲染失败回退**: Askama 渲染失败时使用简化提示
   ```rust
   // memories/prompts.rs:48-53
   template.render().unwrap_or_else(|err| {
       warn!("failed to render...");
       format!("## Memory Phase 2...")
   })
   ```

### 改进建议

1. **模板验证测试**: 添加编译时模板变量检查
   ```rust
   // 建议：在 tests/ 中添加模板变量完整性检查
   assert!(COLLABORATION_MODE_DEFAULT.contains("{{KNOWN_MODE_NAMES}}"));
   ```

2. **模板分片**: 将大型模板（如 `consolidation.md`）按功能拆分为多个小模板
   - 好处：提高可维护性，支持更细粒度的复用

3. **类型安全变量**: 使用结构化数据替代字符串替换
   ```rust
   // 当前
   .replace("{{app_descriptions}}", app_descriptions)
   
   // 建议：使用 serde_json + minijinja
   template.render(context! { app_descriptions => descriptions })
   ```

4. **模板热重载（开发模式）**: 在 debug 模式下支持从文件系统加载模板
   - 好处：开发时无需重新编译即可测试提示词调整

5. **国际化准备**: 模板中硬编码的英文提示应考虑提取到独立文件
   - 当前：所有模板都是英文
   - 未来：支持多语言提示词

6. **文档化模板变量**: 为每个模板添加变量文档注释
   ```markdown
   <!-- templates/collaboration_mode/default.md -->
   <!-- Variables: {{KNOWN_MODE_NAMES}} - comma-separated list of available modes -->
   <!--           {{REQUEST_USER_INPUT_AVAILABILITY}} - availability message -->
   ```

7. **模板版本控制**: 考虑在模板中添加版本标记
   - 好处：支持模板升级时的向后兼容
   - 形式：YAML frontmatter 或特殊注释
