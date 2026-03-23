# 研究文档：plan.md 协作模式模板

## 场景与职责

`plan.md` 是 Codex 协作模式系统中**最复杂、最结构化**的模板，定义了 **Plan 模式**（规划模式）下的 AI 行为准则。Plan 模式是一种**高规划性、低执行性**的协作模式，专门设计用于：

1. **需求澄清**：在动手实现前充分理解用户意图
2. **方案设计**：制定详细的实现计划，包括架构、接口、数据流
3. **决策完备**：确保计划达到"决策完备"（decision complete）状态
4. **计划交接**：生成可供其他工程师或 AI 直接执行的计划文档

### 核心职责

- **分阶段推进**：通过三个阶段（环境探索 → 意图澄清 → 实现规划）逐步完善计划
- **非变异探索**：在规划阶段只允许读取和探索，禁止修改文件
- **结构化提问**：使用 `request_user_input` 工具进行关键决策提问
- **计划最终化**：输出格式化的 `<proposed_plan>` 块作为交付物

### 与其他模式的对比

| 维度 | Plan 模式 | Execute 模式 | Default 模式 |
|-----|----------|-------------|-------------|
| 主要目标 | 制定完备计划 | 独立执行任务 | 平衡协作与执行 |
| 文件修改 | 禁止（规划阶段） | 允许 | 允许 |
| 交互深度 | 深（多轮澄清） | 浅（假设优先） | 中等 |
| 输出格式 | `<proposed_plan>` 块 | 执行结果 | 灵活 |
| 工具使用 | `request_user_input` 推荐 | 假设优先 | 根据配置 |

## 功能点目的

### 1. 三阶段规划流程

#### Phase 1 — 环境探索 (Ground in the environment)
**目的**：消除提示中的未知因素，通过发现事实而非询问用户。

**规则**：
- 探索优先，询问次之
- 在询问用户前，执行至少一次有针对性的非变异探索
- 除非提示本身存在明显歧义或矛盾
- 绝不询问可以从仓库或系统回答的问题

**例外**：
- 提示本身存在明显歧义时可以优先询问
- 如果歧义可以通过探索解决，总是优先探索

#### Phase 2 — 意图澄清 (Intent chat)
**目的**：明确用户真正想要什么。

**澄清维度**：
- 目标 + 成功标准
- 受众
- 范围边界（in/out of scope）
- 约束条件
- 当前状态
- 关键偏好/权衡

**原则**：
- 偏向提问而非猜测
- 高影响歧义未解决前不要开始规划

#### Phase 3 — 实现规划 (Implementation chat)
**目的**：制定决策完备的实现规范。

**规划维度**：
- 方案方法
- 接口（APIs/schemas/I/O）
- 数据流
- 边界情况/失败模式
- 测试 + 验收标准
- 发布/监控
- 迁移/兼容性约束

### 2. 非变异执行规则

**目的**：确保规划阶段只进行规划，不实施。

**允许的操作（非变异）**：
- 读取/搜索文件、配置、模式、类型、清单
- 静态分析、检查、仓库探索
- 不编辑仓库跟踪文件的干运行命令
- 写入缓存或构建产物的测试/构建/检查

**禁止的操作（变异）**：
- 编辑或写入文件
- 运行会重写文件的格式化工具或 linter
- 应用补丁、迁移或代码生成
- 执行计划的副作用命令

**判断标准**：
> 如果操作可以被合理描述为"做工作"而非"规划工作"，则不要做。

### 3. 提问策略

**工具使用**：
- 强烈优先使用 `request_user_input` 工具提问
- 提供有意义的多选题选项
- 避免填充明显错误或无关的选项

**问题质量标准**：
每个问题必须：
- 实质性地改变规范/计划，或
- 确认/锁定假设，或
- 在有意义的选择之间做出选择
- 不能通过非变异命令回答

**两种未知类型**：

1. **可发现事实**（仓库/系统真相）：
   - 询问前先运行有针对性的搜索
   - 检查可能的事实来源（配置/清单/入口点/模式/类型/常量）
   - 仅在以下情况询问：
     - 多个合理候选
     - 未找到但需要缺失的标识符/上下文
     - 歧义实际上是产品意图

2. **偏好/权衡**（不可发现）：
   - 尽早询问
   - 提供 2-4 个互斥选项 + 推荐默认值
   - 如果未回答，使用推荐选项并记录为假设

### 4. 计划最终化规则

**决策完备标准**：
- 计划达到决策完备
- 不给实施者留下任何决策

**输出格式**：
```markdown
<proposed_plan>
计划内容（Markdown 格式）
</proposed_plan>
```

**格式要求**：
1. 开始标签必须单独一行
2. 计划内容从下一行开始（标签行无其他文本）
3. 结束标签必须单独一行
4. 块内使用 Markdown
5. 标签保持原样（不翻译或重命名）

**内容结构**：
- 清晰的标题
- 简要总结部分
- 公共 APIs/接口/类型的重要变更
- 测试用例和场景
- 需要时明确的假设和默认选择

**结构偏好**：
- 紧凑结构，3-5 个短部分
- 通常包括：Summary, Key Changes/Implementation Changes, Test Plan, Assumptions
- 按子系统或行为分组实现要点
- 仅在需要消除非明显变更歧义时提及文件
- 行为级描述优于符号级移除列表

### 5. Plan 模式 vs update_plan 工具

**关键区分**：
- **Plan 模式**：协作模式，可以请求用户输入，最终发出 `<proposed_plan>` 块
- **update_plan**：清单/进度/TODO 工具，不进入或退出 Plan 模式

**重要规则**：
- 在 Plan 模式下使用 `update_plan` 会返回错误
- 不要混淆两者

## 具体技术实现

### 模板嵌入

Plan 模式模板是**内置预设**，在编译时嵌入：

```rust
// codex-rs/core/src/models_manager/collaboration_mode_presets.rs
const COLLABORATION_MODE_PLAN: &str = include_str!("../../templates/collaboration_mode/plan.md");
```

### 预设生成

```rust
fn plan_preset() -> CollaborationModeMask {
    CollaborationModeMask {
        name: ModeKind::Plan.display_name().to_string(),
        mode: Some(ModeKind::Plan),
        model: None,
        reasoning_effort: Some(Some(ReasoningEffort::Medium)),
        developer_instructions: Some(Some(COLLABORATION_MODE_PLAN.to_string())),
    }
}
```

**特点**：
- 固定使用 Medium 推理强度
- 指令直接嵌入（无占位符替换）
- 名称为 "Plan"

### TUI 可见性

Plan 模式是**TUI 可见模式**之一：

```rust
pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];

pub const fn is_tui_visible(self) -> bool {
    matches!(self, Self::Plan | Self::Default)
}
```

### 工具可用性

Plan 模式**允许使用 `request_user_input` 工具**：

```rust
pub const fn allows_request_user_input(self) -> bool {
    matches!(self, Self::Plan)
}
```

这是唯一一个明确允许该工具的模式（Default 模式取决于配置）。

### 指令注入

```rust
// DeveloperInstructions::from_collaboration_mode
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
```

指令被包装在 `<collaboration_mode>` XML 标签中注入。

## 关键代码路径与文件引用

### 模板文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/templates/collaboration_mode/plan.md` | Plan 模式模板源文件（本文件，8777 bytes） |

### 预设实现

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/src/models_manager/collaboration_mode_presets.rs:30-38` | plan_preset() 函数 |
| `codex-rs/core/src/models_manager/collaboration_mode_presets.rs:6` | 模板嵌入 |
| `codex-rs/core/src/models_manager/collaboration_mode_presets_tests.rs:4-15` | 预设名称和推理强度测试 |

### 模式定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs:309-335` | ModeKind 枚举，Plan 变体 |
| `codex-rs/protocol/src/config_types.rs:336` | TUI_VISIBLE_COLLABORATION_MODES |
| `codex-rs/protocol/src/config_types.rs:341` | display_name() 返回 "Plan" |
| `codex-rs/protocol/src/config_types.rs:348-349` | is_tui_visible() 返回 true |
| `codex-rs/protocol/src/config_types.rs:352-354` | allows_request_user_input() 返回 true |

### 协议常量

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs:94-95` | COLLABORATION_MODE_OPEN_TAG/CLOSE_TAG |

### 指令注入

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/models.rs:625-637` | DeveloperInstructions::from_collaboration_mode() |

### TUI 支持

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/collaboration_modes.rs` | TUI 协作模式过滤与选择 |
| `codex-rs/tui/src/bottom_pane/footer.rs:91` | CollaborationModeIndicator::Plan |
| `codex-rs/tui/src/bottom_pane/footer.rs:109` | Plan 模式标签（magenta 洋红色） |
| `codex-rs/tui/src/bottom_pane/footer.rs:120` | Plan 模式样式 |

### API 支持

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:1801-1833` | CollaborationModeList API 类型 |
| `codex-rs/app-server/src/codex_message_processor.rs:4445-4458` | collaborationMode/list RPC 处理 |

### 测试文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/tests/suite/collaboration_instructions.rs` | 协作模式指令注入集成测试 |
| `codex-rs/app-server/tests/suite/v2/collaboration_mode_list.rs` | collaborationMode/list API 测试 |
| `codex-rs/app-server/tests/suite/v2/plan_item.rs` | Plan 工具相关测试 |

## 依赖与外部交互

### 编译时依赖

1. **模板嵌入**：通过 `include_str!` 宏嵌入
2. **Bazel 导出**：BUILD.bazel 显式导出 plan.md
   ```starlark
   exports_files([
       "templates/collaboration_mode/default.md",
       "templates/collaboration_mode/plan.md",
   ])
   ```

### 运行时依赖

1. **推理强度**：固定使用 `ReasoningEffort::Medium`
2. **工具可用性**：`allows_request_user_input()` 返回 true
3. **TUI 切换**：用户可通过 Shift+Tab 在 Default 和 Plan 模式间切换

### API 交互

1. **v2 API**：通过 `collaborationMode/list` 暴露
2. **模式切换**：通过 `OverrideTurnContext` 操作切换模式

### 与工具的关系

| 工具 | Plan 模式中的使用 |
|-----|-----------------|
| `request_user_input` | 强烈推荐用于关键决策 |
| `update_plan` | **禁止使用**（会返回错误） |
| plan 工具 | 用于报告规划进度 |

## 风险、边界与改进建议

### 当前风险

1. **模板大小风险**：8777 bytes 是最大的模板，可能增加上下文窗口压力
   - 缓解：模板内容紧凑，无冗余

2. **规则复杂性**：三阶段流程和严格的非变异规则对 AI 要求较高
   - 缓解：详细的示例和明确的判断标准

3. **模式混淆风险**：用户可能混淆 Plan 模式和 plan 工具
   - 缓解：模板中明确区分两者

### 边界情况

| 场景 | 行为 |
|-----|------|
| 空计划内容 | 不注入指令（`filter(|instructions| !instructions.is_empty())`）|
| 用户要求执行 | 视为"规划执行"而非直接执行 |
| 计划未完成时用户切换模式 | 按模式切换规则处理 |
| 重复相同计划 | 不追加新指令（去重逻辑） |

### 改进建议

#### 短期

1. **添加示例计划**：在模板中添加一个简化的示例计划，帮助 AI 理解格式
2. **阶段检查清单**：为每个阶段提供检查清单，帮助 AI 确认阶段完成

#### 中期

3. **动态推理强度**：根据任务复杂度调整推理强度
   ```rust
   reasoning_effort: match task_complexity {
       Low => Some(ReasoningEffort::Low),
       Medium => Some(ReasoningEffort::Medium),
       High => Some(ReasoningEffort::High),
   }
   ```

4. **计划验证工具**：添加工具验证计划是否达到决策完备标准

#### 长期

5. **计划模板库**：支持用户保存和复用计划模板
6. **计划版本控制**：跟踪计划的版本历史，支持比较和回滚
7. **计划执行跟踪**：将计划与后续执行关联，验证计划准确性

### 模板内容亮点

1. **明确的阶段划分**：三阶段流程清晰可执行
2. **详细的格式规范**：`<proposed_plan>` 块格式要求精确
3. **实用的判断标准**："做工作 vs 规划工作"的判断标准易于应用
4. **两种未知类型区分**：可发现事实 vs 偏好/权衡的分类实用

### 与其他模板的对比

| 特性 | plan.md | execute.md | pair_programming.md | default.md |
|-----|---------|-----------|-------------------|-----------|
| 大小 | 8777 bytes | 3900 bytes | 1126 bytes | 495 bytes |
| 复杂度 | 高 | 中 | 低 | 低 |
| 结构化 | 强（三阶段） | 中（四原则） | 弱（两主题） | 弱（动态） |
| 占位符 | 无 | 无 | 无 | 3个 |
| 内置预设 | 是 | 否 | 否 | 是 |
| TUI 可见 | 是 | 否 | 否 | 是 |

### 相关参考

- `codex-rs/core/templates/collaboration_mode/plan.md` 完整模板内容
- `codex-rs/protocol/src/config_types.rs` ModeKind 详细定义
- AGENTS.md 中关于测试和代码规范的指南
- `docs/protocol_v1.md` 协议文档
