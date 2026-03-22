# ModeKind.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ModeKind` 定义了 Codex TUI 启动时的初始协作模式，控制 AI 代理与用户交互的方式。

**使用场景：**
- TUI 启动时选择协作模式
- 配置文件中设置默认协作模式
- 在会话中切换不同的协作模式

**职责：**
- 定义标准化的协作模式类型
- 支持向后兼容（处理旧的模式名称别名）
- 提供模式显示名称和可见性控制

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **支持不同工作流**：提供适合不同场景的工作模式
2. **向后兼容**：支持旧的模式名称（`code`, `pair_programming`, `execute`, `custom`）
3. **UI 控制**：控制哪些模式在 TUI 中可见

**模式定义：**
- `plan`：计划模式，允许请求用户输入，适合需要多步骤规划的任务
- `default`：默认模式，标准的协作模式（默认选项）

**隐藏模式（向后兼容）：**
- `PairProgramming`（别名为 `default`）
- `Execute`（别名为 `default`）

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/config_types.rs` 第 309-356 行）：

```rust
/// Initial collaboration mode to use when the TUI starts.
#[derive(
    Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq, Hash, JsonSchema, TS, Default,
)]
#[serde(rename_all = "snake_case")]
pub enum ModeKind {
    Plan,
    #[default]
    #[serde(
        alias = "code",
        alias = "pair_programming",
        alias = "execute",
        alias = "custom"
    )]
    Default,
    #[doc(hidden)]
    #[serde(skip_serializing, skip_deserializing)]
    #[schemars(skip)]
    #[ts(skip)]
    PairProgramming,
    #[doc(hidden)]
    #[serde(skip_serializing, skip_deserializing)]
    #[schemars(skip)]
    #[ts(skip)]
    Execute,
}

pub const TUI_VISIBLE_COLLABORATION_MODES: [ModeKind; 2] = [ModeKind::Default, ModeKind::Plan];

impl ModeKind {
    pub const fn display_name(self) -> &'static str {
        match self {
            Self::Plan => "Plan",
            Self::Default => "Default",
            Self::PairProgramming => "Pair Programming",
            Self::Execute => "Execute",
        }
    }

    pub const fn is_tui_visible(self) -> bool {
        matches!(self, Self::Plan | Self::Default)
    }

    pub const fn allows_request_user_input(self) -> bool {
        matches!(self, Self::Plan)
    }
}
```

**TypeScript 生成定义：**

```typescript
/**
 * Initial collaboration mode to use when the TUI starts.
 */
export type ModeKind = "plan" | "default";
```

**关键实现细节：**
- 默认值为 `Default`
- 支持多个别名用于向后兼容
- `PairProgramming` 和 `Execute` 被标记为隐藏，不参与序列化
- 提供 `is_tui_visible()` 和 `allows_request_user_input()` 辅助方法

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs`（第 309-356 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ModeKind.ts`

**使用位置：**
- `CollaborationMode` 结构体（第 358-364 行）
- `TurnStartedEvent`（protocol.rs 第 1771-1778 行）
- 测试代码（第 481-499 行）

**相关类型：**
- `CollaborationMode`：包含 `ModeKind` 和 `Settings`
- `CollaborationModeMask`：用于部分更新协作模式

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `strum`：字符串枚举处理

**序列化格式：**
- JSON 中使用 snake_case：`"plan"`, `"default"`
- 支持别名：`"code"`, `"pair_programming"`, `"execute"`, `"custom"`

**与 TUI 的交互：**
- TUI 只显示 `TUI_VISIBLE_COLLABORATION_MODES` 中定义的模式
- `Plan` 模式允许使用 `request_user_input` 工具

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **混淆**：`Default` 模式名称可能让用户困惑（"默认的默认模式"）
2. **隐藏模式**：`PairProgramming` 和 `Execute` 虽然隐藏但仍存在于代码中，可能导致维护负担
3. **模式切换**：运行时切换模式可能导致不一致的行为

**边界情况：**
1. 别名解析：反序列化时需要正确处理所有别名
2. 隐藏模式：`PairProgramming` 和 `Execute` 不应出现在 UI 或配置文件中

**改进建议：**
1. **重命名 `Default`**：考虑使用更具描述性的名称，如 `Standard` 或 `Interactive`
2. **移除隐藏模式**：在适当的时候完全移除 `PairProgramming` 和 `Execute`
3. **添加更多模式**：考虑添加 `Review` 模式（用于代码审查）或 `Debug` 模式
4. **模式描述**：为每个模式提供更详细的描述，帮助用户选择合适的模式
5. **模式特定配置**：允许每个模式有自己的默认配置（如模型、推理强度等）
