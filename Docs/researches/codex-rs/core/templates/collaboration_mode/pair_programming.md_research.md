# 研究文档：pair_programming.md 协作模式模板

## 场景与职责

`pair_programming.md` 定义了 **Pair Programming 模式**（结对编程模式）下的 AI 行为准则。Pair Programming 模式是一种**高交互性、协作性**的协作模式，设计用于以下场景：

1. **实时协作开发**：用户与 AI 并肩工作，像在终端中结对编程一样
2. **小步快跑**：避免执行耗时过长或步骤过大的操作
3. **动态调整**：根据用户反馈实时调整深度和方向
4. **共同调试**：将调试视为团队协作，主动询问用户观察到的现象

### 核心职责

- **保持同步**：确保 AI 和用户在同一节奏上，避免"一言不合就开干"
- **及时对齐**：在采取较大步骤前检查用户是否舒适
- **解释推理**：逐步解释思考过程，而非直接给出结论
- **友好选项**：当有多种可行路径时，提供清晰选项并邀请用户参与决策

### 与 Execute 模式的对比

| 维度 | Pair Programming 模式 | Execute 模式 |
|-----|---------------------|-------------|
| 交互频率 | 高（持续对话） | 低（独立执行） |
| 步骤大小 | 小（增量构建） | 大（端到端交付） |
| 用户参与 | 持续参与决策 | 最小化交互 |
| 适用场景 | 探索性开发、学习、调试 | 明确任务、重复性工作 |
| 工具使用 | 大量使用 plan 工具保持更新 | plan 工具用于报告进度 |

## 功能点目的

### 1. 共建原则 (Build together as you go)

**目的**：建立"我们一起构建"的协作心态，而非"我为你构建"的服务心态。

**核心规则**：
- 将协作视为默认的结对编程
- 用户就在终端旁，避免执行耗时过长的操作
- 在继续前进前检查对齐和舒适度
- 根据用户信号动态调整深度
- 无需多轮提问——边构建边进行

**多路径决策策略**：
- 提供 2-4 个清晰选项
- 使用友好的框架呈现
- 用示例和直觉 grounding
- 明确邀请用户参与决策
- 让选择感到赋能而非负担

### 2. 调试协作 (Debugging)

**目的**：将调试从"AI 独自排查"转变为"团队协作诊断"。

**协作规则**：
- 假设与用户是团队
- 询问用户看到了什么
- 请求用户提供 AI 无法访问的信息
  - 开发者工具中的错误消息
  - 屏幕截图
  - 本地环境状态

这与传统 AI 工具形成对比——传统工具试图独自解决所有问题，而 Pair Programming 模式承认有些信息需要用户协助获取。

## 具体技术实现

### 模板使用方式

与 `execute.md` 类似，`pair_programming.md` **不是内置预设**，当前处于**预留但未启用**状态：

1. **ModeKind 枚举**：`ModeKind::PairProgramming` 已定义但标记为 `#[doc(hidden)]`
2. **序列化别名**：PairProgramming 序列化为 `"pair_programming"`，但反序列化时映射到 `ModeKind::Default`
3. **TUI 不可见**：不在 `TUI_VISIBLE_COLLABORATION_MODES` 中

```rust
#[derive(...)]
#[serde(rename_all = "snake_case")]
pub enum ModeKind {
    Plan,
    #[default]
    #[serde(
        alias = "code",
        alias = "pair_programming",  // PairProgramming 反序列化为 Default
        alias = "execute",
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

### TUI 支持代码

虽然模式被隐藏，TUI 中保留了 UI 支持代码：

```rust
// codex-rs/tui/src/bottom_pane/footer.rs
pub(crate) enum CollaborationModeIndicator {
    Plan,
    #[allow(dead_code)]
    PairProgramming,
    #[allow(dead_code)]
    Execute,
}

impl CollaborationModeIndicator {
    fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
        let label = self.label(show_cycle_hint);
        match self {
            CollaborationModeIndicator::Plan => Span::from(label).magenta(),
            CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
            CollaborationModeIndicator::Execute => Span::from(label).dim(),
        }
    }
}
```

Pair Programming 模式在 UI 中使用**青色 (cyan)** 标识，与 Plan 模式的洋红色 (magenta) 和 Execute 模式的灰色 (dim) 形成视觉区分。

### 模板内容结构

```markdown
# Collaboration Style: Pair Programming

## Build together as you go
[共建原则详细说明]
- 协作节奏
- 步骤大小控制
- 对齐检查
- 动态调整
- 多路径决策

## Debugging
[调试协作指南]
- 团队心态
- 信息请求
- 用户协助事项
```

### 文件大小分析

- **pair_programming.md**: 1126 bytes
- **execute.md**: 3900 bytes
- **plan.md**: 8777 bytes
- **default.md**: 495 bytes

Pair Programming 模板是**最简洁的模板**之一，仅包含核心原则描述，没有复杂的阶段划分或详细的执行规则。这与其"轻量级、灵活"的设计理念一致。

## 关键代码路径与文件引用

### 模板文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/core/templates/collaboration_mode/pair_programming.md` | Pair Programming 模式模板源文件（本文件） |

### 模式定义

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs:314-328` | ModeKind 枚举，PairProgramming 变体定义 |
| `codex-rs/protocol/src/config_types.rs:336` | TUI_VISIBLE_COLLABORATION_MODES 常量（不含 PairProgramming） |
| `codex-rs/protocol/src/config_types.rs:343-344` | display_name() 返回 "Pair Programming" |
| `codex-rs/protocol/src/config_types.rs:348-349` | is_tui_visible() 返回 false |

### TUI 支持

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:90-96` | CollaborationModeIndicator 枚举定义 |
| `codex-rs/tui/src/bottom_pane/footer.rs:110-112` | Pair Programming 标签渲染 |
| `codex-rs/tui/src/bottom_pane/footer.rs:121` | Pair Programming 样式（cyan 青色） |

### 测试文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/config_types.rs:488-499` | TUI 可见性测试，验证 PairProgramming 不可见 |

## 依赖与外部交互

### 编译时依赖

与 execute.md 相同，`pair_programming.md` **未被编译时嵌入**：

```rust
// collaboration_mode_presets.rs 中仅嵌入 plan 和 default
const COLLABORATION_MODE_PLAN: &str = include_str!(".../plan.md");
const COLLABORATION_MODE_DEFAULT: &str = include_str!(".../default.md");
// 注意：没有 COLLABORATION_MODE_PAIR_PROGRAMMING
```

### 潜在使用场景

尽管当前未启用，Pair Programming 模式模板设计用于：

1. **教学场景**：用户学习新技术时，需要 AI 逐步解释
2. **探索性开发**：需求不明确，需要与 AI 共同探索
3. **复杂调试**：需要用户和 AI 共同诊断问题
4. **代码审查**：与 AI 一起审查和改进代码

### 与其他模式的关系

```
协作模式谱系：

低交互 ←——————————————————————————→ 高交互
Execute    Default    Pair Programming    Plan
(独立)     (平衡)      (协作)            (规划)
```

Pair Programming 位于 Default 和 Plan 之间，但更偏向高交互端。

## 风险、边界与改进建议

### 当前状态风险

1. **模板孤儿风险**：`pair_programming.md` 存在于代码库但**未被任何代码引用**
   - 文件大小：1126 bytes
   - 内容质量：内容完整但无法使用
   - 维护问题：变更不会生效，可能导致文档与代码不一致

2. **反序列化静默映射**：用户配置 `"pair_programming"` 会静默变为 Default 模式
   - 用户期望：结对编程式的协作体验
   - 实际获得：标准 Default 模式行为
   - 体验落差：可能感到困惑或失望

3. **UI 代码维护负担**：TUI 中保留了未使用模式的 UI 代码
   - `#[allow(dead_code)]` 标记表明这是已知问题
   - 每次修改 footer.rs 都需要考虑这些未使用的变体

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 用户配置 pair_programming 模式 | 反序列化为 Default 模式 |
| TUI 尝试显示 PairProgramming | 被过滤（is_tui_visible 返回 false）|
| 模板文件变更 | 无影响（未被引用） |
| 别名 "code" 使用 | 同样映射到 Default（共享别名）|

### 改进建议

#### 短期（立即执行）

1. **添加文件头注释**：明确标注当前状态
   ```markdown
   <!-- 
   NOTE: Pair Programming mode is currently HIDDEN and maps to Default mode.
   This template exists for future use but is not currently active.
   See: codex-rs/protocol/src/config_types.rs ModeKind::PairProgramming
   -->
   ```

2. **统一别名处理**：考虑为 pair_programming 别名添加反序列化警告

#### 中期（功能决策）

3. **启用 Pair Programming 模式**：
   - 评估是否将其作为正式模式启用
   - 如果启用，需要：
     - 添加到 `TUI_VISIBLE_COLLABORATION_MODES`
     - 在 `collaboration_mode_presets.rs` 中创建预设
     - 嵌入模板文件
     - 添加切换 UI

4. **或者彻底移除**：
   - 如果决定不启用，应移除模板文件和相关代码
   - 减少技术债务

#### 长期（架构优化）

5. **动态模式注册**：允许插件或配置动态注册新模式
   ```rust
   pub struct CollaborationModeRegistry {
       modes: HashMap<ModeKind, CollaborationModeDefinition>,
   }
   ```

6. **模板热重载**：开发模式下支持模板文件热重载，便于调试

### 设计亮点

尽管当前未启用，pair_programming.md 模板的设计值得肯定：

1. **简洁性**：相比 execute.md 和 plan.md，更加简洁聚焦
2. **实用性**："边构建边进行"的原则避免了过度规划
3. **协作性**：强调用户是团队一员，而非服务对象
4. **灵活性**：没有严格的阶段划分，适应性强

### 决策建议

建议采取**选项 A：正式启用 Pair Programming 模式**：

**理由**：
1. 模板内容已完善，设计质量高
2. 与 Execute 模式形成互补（高交互 vs 低交互）
3. 满足特定用户群体需求（学习者、探索性开发者）
4. UI 代码已预留，启用成本低

**实施步骤**：
1. 在 `collaboration_mode_presets.rs` 中添加 `pair_programming_preset()`
2. 将 `ModeKind::PairProgramming` 加入 `TUI_VISIBLE_COLLABORATION_MODES`
3. 移除 `#[doc(hidden)]` 和 `#[allow(dead_code)]` 标记
4. 添加集成测试
5. 更新文档

### 相关参考

- `codex-rs/tui/src/bottom_pane/footer.rs` 中关于 `CollaborationModeIndicator` 的注释
- `codex-rs/protocol/src/config_types.rs` 中 `ModeKind` 的详细文档
- AGENTS.md 中关于 TUI 代码规范的说明
