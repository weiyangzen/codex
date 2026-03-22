# Collaboration Mode Templates 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与作用

`codex-rs/core/templates/collaboration_mode/` 目录包含 Codex 系统的**协作模式指令模板**，用于定义不同协作风格下 AI Agent 的行为准则。这些模板是 Codex 核心功能的一部分，直接影响模型在交互过程中的行为方式、决策逻辑和输出风格。

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **TUI 交互** | 终端用户界面通过快捷键或命令切换协作模式 |
| **App-Server API** | 客户端通过 `collaborationMode/list` 和 `turn/start` 等 RPC 方法获取和设置协作模式 |
| **会话初始化** | 新会话启动时加载默认协作模式配置 |
| **模式切换** | 用户在会话过程中动态切换协作风格 |
| **Plan 模式检测** | 系统根据当前协作模式判断是否启用 Plan 模式的特殊流处理逻辑 |

### 1.3 核心职责

1. **行为定义**：为每种协作模式提供详细的系统指令（system instructions）
2. **模板渲染**：支持动态占位符替换（如 `{{KNOWN_MODE_NAMES}}`）
3. **模式生命周期管理**：支持模式的获取、应用、切换和持久化
4. **与模型配置集成**：协作模式与模型选择、推理努力度（reasoning effort）等配置协同工作

---

## 功能点目的

### 2.1 四种协作模式

| 模式 | 文件 | 目的 | 适用场景 |
|------|------|------|----------|
| **Default** | `default.md` | 提供标准协作行为，平衡自主执行与用户确认 | 日常开发任务，通用场景 |
| **Plan** | `plan.md` | 强制规划优先，禁止变异操作，要求详细计划 | 复杂任务分解、架构设计 |
| **Execute** | `execute.md` | 高度自主执行，最小化用户交互 | 明确定义的重复性任务 |
| **Pair Programming** | `pair_programming.md` | 结对编程风格，紧密协作、逐步确认 | 探索性开发、调试会话 |

### 2.2 各模式核心特性

#### Default 模式
- 清除之前模式的指令残留
- 支持 `request_user_input` 工具的可用性配置
- 提供已知模式名称列表供模型参考
- 鼓励合理假设而非频繁提问

#### Plan 模式
- **三阶段流程**：环境探索 → 意图确认 → 实现规划
- **严格限制**：禁止文件修改、格式化、补丁应用等变异操作
- **计划完整性要求**：输出必须包含在 `<proposed_plan>` 标签中
- **决策完备性**：计划必须让执行者无需再做决策

#### Execute 模式
- **假设优先**：信息缺失时做合理假设而非提问
- **独立执行**：端到端自主完成任务
- **进度报告**：使用 plan 工具报告进展
- **前瞻性思考**：预判用户可能需要的额外支持

#### Pair Programming 模式
- **小步快跑**：避免长时间操作，保持用户参与
- **动态调整**：根据用户信号调整深度
- **调试协作**：将用户视为团队成员，可请求环境信息

### 2.3 动态配置能力

协作模式支持以下动态配置：

```rust
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,           // Plan / Default / PairProgramming / Execute
    pub model: Option<String>,            // 覆盖模型选择
    pub reasoning_effort: Option<Option<ReasoningEffort>>, // 推理努力度
    pub developer_instructions: Option<Option<String>>,    // 自定义指令
}
```

---

## 具体技术实现

### 3.1 模板文件结构

```
codex-rs/core/templates/collaboration_mode/
├── default.md           # 11 行，基础模板
├── execute.md           # 45 行，执行模式详细指令
├── pair_programming.md  # 7 行，结对编程风格
└── plan.md              # 128 行，Plan 模式完整规范
```

### 3.2 模板编译时嵌入

模板通过 `include_str!` 宏在编译时嵌入二进制：

```rust
// codex-rs/core/src/models_manager/collaboration_mode_presets.rs
const COLLABORATION_MODE_PLAN: &str = include_str!("../../templates/collaboration_mode/plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!("../../templates/collaboration_mode/default.md");
```

### 3.3 占位符替换机制

Default 模式支持动态占位符：

```rust
const KNOWN_MODE_NAMES_PLACEHOLDER: &str = "{{KNOWN_MODE_NAMES}}";
const REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER: &str = "{{REQUEST_USER_INPUT_AVAILABILITY}}";
const ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER: &str = "{{ASKING_QUESTIONS_GUIDANCE}}";

fn default_mode_instructions(collaboration_modes_config: CollaborationModesConfig) -> String {
    let known_mode_names = format_mode_names(&TUI_VISIBLE_COLLABORATION_MODES);
    let request_user_input_availability = request_user_input_availability_message(...);
    let asking_questions_guidance = asking_questions_guidance_message(...);
    
    COLLABORATION_MODE_DEFAULT
        .replace(KNOWN_MODE_NAMES_PLACEHOLDER, &known_mode_names)
        .replace(REQUEST_USER_INPUT_AVAILABILITY_PLACEHOLDER, &request_user_input_availability)
        .replace(ASKING_QUESTIONS_GUIDANCE_PLACEHOLDER, &asking_questions_guidance)
}
```

### 3.4 预设生成流程

```rust
pub(crate) fn builtin_collaboration_mode_presets(
    collaboration_modes_config: CollaborationModesConfig,
) -> Vec<CollaborationModeMask> {
    vec![
        plan_preset(),      // Plan 模式预设
        default_preset(collaboration_modes_config),  // Default 模式预设（动态渲染）
    ]
}
```

### 3.5 指令注入流程

协作模式指令通过 `DeveloperInstructions` 注入到模型上下文：

```rust
// codex-rs/protocol/src/models.rs
impl DeveloperInstructions {
    pub fn from_collaboration_mode(collaboration_mode: &CollaborationMode) -> Option<Self> {
        collaboration_mode
            .settings
            .developer_instructions
            .as_ref()
            .filter(|instructions| !instructions.is_empty())
            .map(|instructions| {
                DeveloperInstructions::new(format!(
                    "{COLLABORATION_MODE_OPEN_TAG}{instructions}{COLLABORATION_MODE_CLOSE_TAG}"
                ))
            })
    }
}
```

注入位置（`codex-rs/core/src/codex.rs`）：

```rust
// Add developer instructions from collaboration_mode if they exist and are non-empty
if let Some(collab_instructions) =
    DeveloperInstructions::from_collaboration_mode(&collaboration_mode)
{
    developer_sections.push(collab_instructions.into_text());
}
```

### 3.6 Plan 模式特殊处理

Plan 模式在流处理中有特殊逻辑：

```rust
// codex-rs/core/src/codex.rs
let plan_mode = turn_context.collaboration_mode.mode == ModeKind::Plan;
let mut assistant_message_stream_parsers = AssistantMessageStreamParsers::new(plan_mode);
let mut plan_mode_state = plan_mode.then(|| PlanModeStreamState::new(&turn_context.sub_id));
```

### 3.7 API 暴露

App-Server 协议暴露协作模式相关接口：

```rust
// app-server-protocol/src/protocol/common.rs
CollaborationModeList => "collaborationMode/list" {
    params: v2::CollaborationModeListParams,
    response: v2::CollaborationModeListResponse,
}
```

---

## 关键代码路径与文件引用

### 4.1 核心数据类型

| 文件 | 类型 | 说明 |
|------|------|------|
| `protocol/src/config_types.rs` | `ModeKind` | 协作模式枚举（Plan/Default/PairProgramming/Execute） |
| `protocol/src/config_types.rs` | `CollaborationMode` | 完整协作模式结构（mode + settings） |
| `protocol/src/config_types.rs` | `CollaborationModeMask` | 部分更新掩码 |
| `protocol/src/config_types.rs` | `Settings` | 协作模式设置（model/reasoning_effort/developer_instructions） |
| `protocol/src/models.rs` | `DeveloperInstructions` | 开发者指令封装 |

### 4.2 模板与预设

| 文件 | 职责 |
|------|------|
| `core/templates/collaboration_mode/*.md` | 原始模板文件 |
| `core/src/models_manager/collaboration_mode_presets.rs` | 模板加载、渲染、预设生成 |
| `core/src/models_manager/manager.rs` | ModelsManager 暴露 `list_collaboration_modes` |

### 4.3 指令注入

| 文件 | 函数/位置 | 职责 |
|------|-----------|------|
| `protocol/src/models.rs` | `DeveloperInstructions::from_collaboration_mode` | 将协作模式转换为开发者指令 |
| `core/src/codex.rs` | `prepare_turn_context` (~3454行) | 将协作模式指令注入到 developer_sections |
| `protocol/src/protocol.rs` | `COLLABORATION_MODE_OPEN_TAG/CLOSE_TAG` | XML 标签常量定义 |

### 4.4 配置与状态

| 文件 | 职责 |
|------|------|
| `core/src/codex.rs` | `SessionConfiguration` 包含 `collaboration_mode: CollaborationMode` |
| `core/src/codex.rs` | `TurnContext` 包含 `collaboration_mode: CollaborationMode` |
| `core/src/codex.rs` | `configure_session` 初始化协作模式 |

### 4.5 API 层

| 文件 | 职责 |
|------|------|
| `app-server-protocol/src/protocol/v2.rs` | v2 API 类型定义（CollaborationModeListParams/Response） |
| `app-server-protocol/src/protocol/common.rs` | ClientRequest 枚举包含 CollaborationModeList |
| `app-server/src/codex_message_processor.rs` | `list_collaboration_modes` 处理函数 |
| `app-server/src/codex_message_processor.rs` | `normalize_turn_start_collaboration_mode` 规范化处理 |

### 4.6 TUI 层

| 文件 | 职责 |
|------|------|
| `tui/src/collaboration_modes.rs` | TUI 协作模式过滤与切换逻辑 |
| `tui_app_server/src/collaboration_modes.rs` | TUI App Server 适配层 |
| `tui_app_server/src/model_catalog.rs` | 模型目录包含协作模式列表 |

### 4.7 测试

| 文件 | 职责 |
|------|------|
| `core/tests/suite/collaboration_instructions.rs` | 协作模式指令注入的完整测试套件 |
| `app-server/tests/suite/v2/collaboration_mode_list.rs` | API 列表接口测试 |
| `core/src/models_manager/collaboration_mode_presets_tests.rs` | 预设生成单元测试 |

---

## 依赖与外部交互

### 5.1 内部依赖关系

```
codex-rs/core/templates/collaboration_mode/*.md
    ↓ (include_str!)
codex-rs/core/src/models_manager/collaboration_mode_presets.rs
    ↓ (builtin_collaboration_mode_presets)
codex-rs/core/src/models_manager/manager.rs (ModelsManager)
    ↓ (list_collaboration_modes)
codex-rs/core/src/thread_manager.rs
    ↓
codex-rs/core/src/codex.rs (注入到 TurnContext)
    ↓
OpenAI Responses API (作为 developer instructions)
```

### 5.2 协议依赖

```
codex-rs/protocol/src/config_types.rs (CollaborationMode 定义)
    ↑
codex-rs/app-server-protocol/src/protocol/v2.rs (API 类型)
    ↑
codex-rs/app-server-protocol/src/protocol/common.rs (ClientRequest)
    ↑
codex-rs/app-server/src/codex_message_processor.rs (请求处理)
```

### 5.3 配置集成

协作模式与以下配置项协同工作：

- `model`：模型选择
- `reasoning_effort`：推理努力度（low/medium/high）
- `developer_instructions`：自定义开发者指令
- `approval_policy`：审批策略
- `sandbox_policy`：沙箱策略

### 5.4 外部 API 交互

1. **OpenAI Responses API**：协作模式指令作为 `developer` 角色的消息注入
2. **App-Server MCP 协议**：通过 `collaborationMode/list` 暴露可用模式
3. **TUI 状态同步**：模式切换通过事件通知 UI 更新

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 模板内容风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 指令注入 | 模板中的占位符替换可能被滥用 | 所有替换内容来自内部常量或配置，不接受用户输入 |
| 模式逃逸 | Plan 模式的变异操作限制可能被绕过 | 通过工具权限系统二次校验 |
| 指令冲突 | 协作模式指令与其他开发者指令可能冲突 | 按固定顺序拼接，协作模式指令在权限指令之后 |

#### 6.1.2 实现风险

| 风险 | 描述 | 位置 |
|------|------|------|
| 空指令处理 | 空字符串指令被过滤，但 `Some("")` 与 `None` 处理需一致 | `from_collaboration_mode` 方法 |
| 模式切换竞态 | 并发模式下切换可能产生不一致状态 | `OverrideTurnContext` 操作 |
| Plan 模式检测 | 流处理中的 Plan 模式判断与指令注入可能不一致 | `codex.rs:7039` |

### 6.2 边界情况

1. **隐藏模式**：`PairProgramming` 和 `Execute` 被标记为 `#[doc(hidden)]`，不在 TUI 中显示，但可通过配置使用
2. **别名处理**：`ModeKind::Default` 接受 `"code"`、`"pair_programming"`、`"execute"`、`"custom"` 等别名
3. **指令覆盖优先级**：`turn/start` 传入的 `developer_instructions` 会覆盖预设模板
4. **空模式名称**：`format_mode_names` 处理空列表时返回 `"none"`

### 6.3 改进建议

#### 6.3.1 架构层面

1. **模板热重载**：当前模板编译时嵌入，建议开发模式支持文件系统热重载
   ```rust
   // 建议：开发配置下从文件系统加载
   #[cfg(debug_assertions)]
   const COLLABORATION_MODE_PLAN: &str = include_str!(...); // 或文件系统读取
   ```

2. **模式扩展机制**：当前预设硬编码，建议支持用户自定义模式配置文件
   ```
   ~/.codex/collaboration_modes/custom_mode.md
   ```

3. **指令版本控制**：模板更新可能导致行为变化，建议添加版本标识
   ```markdown
   <!-- version: 1.2.0 -->
   ```

#### 6.3.2 代码层面

1. **占位符类型安全**：当前字符串替换，建议使用模板引擎（如 `handlebars`）
   ```rust
   // 当前
   .replace(KNOWN_MODE_NAMES_PLACEHOLDER, &known_mode_names)
   
   // 建议
   handlebars.render("default", &json!({"known_mode_names": ...}))
   ```

2. **测试覆盖**：`pair_programming.md` 和 `execute.md` 的预设生成缺少专门测试

3. **文档同步**：模板内容变更需同步更新用户文档，建议添加一致性检查 CI

#### 6.3.3 协议层面

1. **实验性标记**：`collaborationMode/list` 当前标记为 `#[experimental]`，建议根据稳定性评估提升为正式 API

2. **模式验证**：建议在 `TurnStartParams` 中添加模式有效性验证，提前返回清晰错误

### 6.4 监控与调试

建议添加以下可观测性指标：

1. **模式使用统计**：各模式的使用频率
2. **指令长度监控**：渲染后指令长度，防止上下文窗口溢出
3. **模式切换追踪**：记录模式切换历史，便于问题排查

---

## 附录：关键代码片段

### A.1 协作模式 XML 标签

```rust
// protocol/src/protocol.rs
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
pub const COLLABORATION_MODE_CLOSE_TAG: &str = "</collaboration_mode>";
```

### A.2 TUI 可见模式

```rust
// protocol/src/config_types.rs
pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];

impl ModeKind {
    pub const fn is_tui_visible(self) -> bool {
        matches!(self, Self::Plan | Self::Default)
    }
    
    pub const fn allows_request_user_input(self) -> bool {
        matches!(self, Self::Plan)
    }
}
```

### A.3 模式切换测试用例

```rust
// core/tests/suite/collaboration_instructions.rs
async fn collaboration_mode_update_emits_new_instruction_message() {
    // 验证模式切换时新指令被注入
    // 验证相同模式重复设置不会重复注入
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs 主干*
