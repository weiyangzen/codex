# 研究文档：execute.md 协作模式模板

## 场景与职责

`execute.md` 定义了 **Execute 模式**（执行模式）下的 AI 行为准则。Execute 模式是一种**高自主性、低交互性**的协作模式，设计用于以下场景：

1. **明确任务执行**：用户已经提供了清晰、完整的任务描述，AI 可以独立完成
2. **端到端交付**：AI 负责从任务开始到完成的整个流程，不需要中途与用户协商
3. **快速迭代**：减少交互开销，提高任务执行效率

### 核心职责

- **假设优先原则**：信息缺失时优先做合理假设，而非停下来提问
- **独立执行**：不依赖用户实时反馈，自主推进任务
- **进度报告**：通过 plan 工具定期报告进展，而非等待用户询问
- **时间管理**：意识到用户正在等待，最小化探索时间（通常几秒，最多60秒）

### 与 Plan 模式的对比

| 维度 | Execute 模式 | Plan 模式 |
|-----|-------------|----------|
| 交互频率 | 低（独立执行） | 高（持续对话） |
| 决策方式 | AI 自主决策 | 与用户协商决策 |
| 信息缺失处理 | 做假设并继续 | 询问用户澄清 |
| 适用场景 | 任务明确、执行导向 | 需求模糊、规划导向 |
| 工具使用 | plan 工具报告进度 | update_plan 不可用 |

## 功能点目的

### 1. 假设优先执行 (Assumptions-first execution)

**目的**：消除执行过程中的阻塞点，保持任务流畅推进。

**具体规则**：
- 信息缺失时不询问用户
- 做出合理假设
- 在最终消息中简要陈述假设
- 继续执行

**假设分类**：
- 架构/框架/实现选择
- 功能/行为定义
- 设计/主题/风格偏好

### 2. 执行原则 (Execution principles)

#### 2.1 思考 aloud
- **目的**：帮助用户评估权衡，但避免冗长解释
- **要求**：简短、基于后果的说明，避免设计讲座

#### 2.2 合理假设
- **目的**：当用户未明确说明时，提出合理选择而非开放式问题
- **策略**：
  - 逻辑分组假设
  - 将建议标记为临时性
  - 分享有助于评估权衡的推理
  - 如果用户无反应，视为已接受

#### 2.3 前瞻思考
- **目的**：预判用户可能需要的支持
- **行动**：
  - 考虑用户如何测试和理解成果
  - 在建构前提出用户可能需要的建议
  - 提供至少一个前瞻性建议

#### 2.4 时间意识
- **目的**：尊重用户等待时间
- **规则**：
  - 大多数回合仅花费几秒
  - 研究时间不超过60秒
  - 如果找不到信息，做合理假设继续

### 3. 长周期执行 (Long-horizon execution)

**目的**：将大型任务分解为可管理的里程碑序列。

**策略**：
- 分解为可见推进的里程碑
- 逐步执行，沿途验证
- 维护运行清单（已完成、下一步、阻塞）
- 避免在不确定性上阻塞：选择合理默认值继续

### 4. 进度报告 (Reporting progress)

**目的**：让用户了解任务状态，无需主动询问。

**要求**：
- 更新直接映射到实际工作
- 失败时报告：失败内容、尝试过的方法、下一步计划
- 完成时总结交付内容和验证方法

## 具体技术实现

### 模板使用方式

与 `default.md` 和 `plan.md` 不同，`execute.md` **不是内置预设**，而是通过以下方式使用：

1. **作为自定义模式**：用户可以通过配置定义 Execute 模式
2. **ModeKind 枚举**：`ModeKind::Execute` 已定义但标记为 `#[doc(hidden)]`
3. **序列化别名**：Execute 模式序列化为 `"execute"`，但反序列化时映射到 `ModeKind::Default`

```rust
#[derive(...)]
#[serde(rename_all = "snake_case")]
pub enum ModeKind {
    Plan,
    #[default]
    #[serde(
        alias = "code",
        alias = "pair_programming", 
        alias = "execute",  // Execute 反序列化为 Default
        alias = "custom"
    )]
    Default,
    #[doc(hidden)]
    #[serde(skip_serializing, skip_deserializing)]
    PairProgramming,
    #[doc(hidden)]
    #[serde(skip_serializing, skip_deserializing)]
    Execute,
}
```

### TUI 可见性

Execute 模式当前**不在 TUI 中可见**：

```rust
pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];

pub const fn is_tui_visible(self) -> bool {
    matches!(self, Self::Plan | Self::Default)
}
```

但 TUI 代码中保留了 Execute 模式的 UI 支持：

```rust
pub(crate) enum CollaborationModeIndicator {
    Plan,
    #[allow(dead_code)]
    PairProgramming,
    #[allow(dead_code)]
    Execute,
}
```

### 模板内容结构

```markdown
# Collaboration Style: Execute
[模式定义和核心原则]

## Assumptions-first execution
[假设优先执行规则]

## Execution principles
[四大执行原则]

## Long-horizon execution  
[长周期执行策略]

## Reporting progress
[进度报告要求]

## Executing
[执行总结]
```

## 关键代码路径与文件引用

### 模板文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/templates/collaboration_mode/execute.md` | Execute 模式模板源文件（本文件） |

### 模式定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs` | ModeKind 枚举定义，包含 Execute 变体 |
| `codex-rs/protocol/src/config_types.rs:336` | TUI_VISIBLE_COLLABORATION_MODES 常量 |
| `codex-rs/protocol/src/config_types.rs:348-349` | is_tui_visible() 方法 |

### TUI 支持

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:90-96` | CollaborationModeIndicator::Execute 定义 |
| `codex-rs/tui/src/bottom_pane/footer.rs:113` | Execute 模式标签渲染 |
| `codex-rs/tui/src/bottom_pane/footer.rs:122` | Execute 模式样式（dim 灰色） |

### 序列化处理

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs:317-322` | Execute 作为 Default 的别名 |
| `codex-rs/protocol/src/config_types.rs:481-486` | 别名反序列化测试 |

## 依赖与外部交互

### 编译时依赖

Execute 模式模板**未被编译时嵌入**，与 default.md 和 plan.md 不同：

```rust
// collaboration_mode_presets.rs 中只有 plan 和 default 被嵌入
const COLLABORATION_MODE_PLAN: &str = include_str!(".../plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!(".../default.md");
// 注意：没有 COLLABORATION_MODE_EXECUTE
```

这意味着 Execute 模式当前**不作为内置预设提供**，需要通过其他机制加载。

### 潜在使用路径

1. **用户自定义配置**：通过 config.toml 或 API 定义自定义协作模式
2. **未来功能扩展**：预留用于后续版本启用
3. **程序化使用**：通过 `CollaborationModeMask` 动态构建

### 与其他模式的关系

```
ModeKind 枚举关系：

Plan                    → TUI 可见，内置预设
Default                 → TUI 可见，内置预设  
PairProgramming (隐藏)   → TUI 不可见，预留
Execute (隐藏)           → TUI 不可见，预留
```

## 风险、边界与改进建议

### 当前状态风险

1. **模板未使用风险**：`execute.md` 模板文件存在于代码库中，但**未被任何代码引用**
   - 文件大小：3900 bytes（相对较大的模板）
   - 维护成本：模板内容变更不会生效
   - 用户困惑：文档可能提及 Execute 模式，但实际不可用

2. **反序列化陷阱**：用户配置 `"mode": "execute"` 会静默映射到 Default 模式
   - 用户可能期望 Execute 模式行为
   - 实际获得 Default 模式行为
   - 无警告或错误提示

3. **UI 残留代码**：TUI 中保留了 Execute 模式的 UI 代码但标记为 `dead_code`
   - 增加维护负担
   - 可能误导开发者认为功能已启用

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 用户配置 execute 模式 | 反序列化为 Default 模式 |
| TUI 尝试显示 Execute 模式 | 被过滤（is_tui_visible 返回 false）|
| API 查询 Execute 模式预设 | 返回空（无内置预设） |
| 模板文件变更 | 无影响（未被引用） |

### 改进建议

#### 短期（立即执行）

1. **文档化当前状态**：在模板文件顶部添加注释说明当前未被使用
   ```markdown
   <!-- NOTE: This template is currently NOT in use. Execute mode is hidden and maps to Default. -->
   ```

2. **添加反序列化警告**：当检测到 `"execute"` 别名使用时发出警告
   ```rust
   // 在 ModeKind 反序列化时记录警告
   warn!("Execute mode is deprecated and maps to Default mode");
   ```

#### 中期（功能完善）

3. **启用 Execute 模式**：
   - 将 Execute 加入 `TUI_VISIBLE_COLLABORATION_MODES`
   - 在 `collaboration_mode_presets.rs` 中添加 Execute 预设
   - 嵌入 `execute.md` 模板

4. **模式切换 UI**：在 TUI 底部状态栏启用 Execute 模式指示器

5. **配置支持**：允许用户在 config.toml 中启用 Execute 模式
   ```toml
   [collaboration_modes]
   enable_execute = true
   ```

#### 长期（架构优化）

6. **模板动态加载**：支持运行时加载自定义模式模板，而非仅编译时嵌入

7. **模式继承机制**：允许自定义模式继承内置模式并覆盖特定部分

8. **模式验证**：在 CI 中验证所有模板文件都被引用，无孤儿文件

### 决策建议

考虑到当前代码状态，建议采取以下策略之一：

**选项 A：正式启用 Execute 模式**（推荐）
- 实现成本：中等
- 用户价值：高（为高级用户提供高效执行模式）
- 风险评估：需要全面测试，但模板内容已完善

**选项 B：移除 Execute 模式代码**
- 实现成本：低
- 用户价值：无
- 风险评估：低，但浪费已完成的模板设计工作

**选项 C：保持现状（文档化）**
- 实现成本：最低
- 用户价值：无
- 风险评估：技术债务累积

### 相关参考

- `codex-rs/tui/src/bottom_pane/footer.rs` 中 `CollaborationModeIndicator::Execute` 的 `dead_code` 注释
- `codex-rs/protocol/src/config_types.rs` 中 `ModeKind::Execute` 的 `doc(hidden)` 标记
- AGENTS.md 中关于协作模式的开发指南
