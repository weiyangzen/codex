# Research: `codex-rs/core/src/context_manager/updates.rs`

## 1. 场景与职责

### 1.1 文件定位

`updates.rs` 是 Codex 核心会话管理模块 (`context_manager`) 的关键组成部分，负责在对话回合 (turn) 之间生成**增量式上下文更新项**。它与 `history.rs`（管理对话历史存储和检索）和 `normalize.rs`（规范化历史记录）共同构成完整的上下文管理体系。

### 1.2 核心职责

该模块的核心职责是**智能地检测和传达会话状态变化**给 AI 模型：

1. **环境上下文变更检测**：监测工作目录、时间、时区、网络策略等环境变化
2. **权限策略变更通知**：当沙箱策略或审批策略变化时通知模型
3. **协作模式切换**：处理协作模式 (Collaboration Mode) 的变更通知
4. **实时会话生命周期**：管理实时语音对话模式的启动和结束通知
5. **模型切换指令**：当模型发生变化时注入新模型的指令
6. **人格 (Personality) 切换**：处理模型人格/风格的变化通知

### 1.3 业务场景

| 场景 | 说明 |
|------|------|
| 用户切换工作目录 (`/cd`) | 需要通知模型新的 cwd，以便后续文件操作正确解析 |
| 时间/时区变化 | 跨时区使用时，确保模型了解当前时间上下文 |
| 网络策略变更 | 用户修改允许/拒绝的域名列表 |
| 权限策略切换 | 从 `on-request` 切换到 `never` 等 |
| 实时语音模式 | 用户进入或退出实时语音对话 |
| 模型切换 | 用户在同一会话中切换不同模型 |
| 人格切换 | 用户改变模型的沟通风格 |

---

## 2. 功能点目的

### 2.1 增量更新机制

```rust
pub(crate) fn build_settings_update_items(
    previous: Option<&TurnContextItem>,
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
    shell: &Shell,
    exec_policy: &Policy,
    personality_feature_enabled: bool,
) -> Vec<ResponseItem>
```

**设计目的**：
- **最小化 Token 开销**：只发送实际发生变化的上下文，而非完整上下文
- **保持对话连贯性**：让模型了解状态变化，避免产生困惑
- **支持会话恢复**：通过 `reference_context_item` 机制支持断点续传

### 2.2 各更新项功能详解

#### 2.2.1 环境上下文更新 (`build_environment_update_item`)

```rust
fn build_environment_update_item(
    previous: Option<&TurnContextItem>,
    next: &TurnContext,
    shell: &Shell,
) -> Option<ResponseItem>
```

**检测的变更**：
- 当前工作目录 (`cwd`)
- 当前日期 (`current_date`)
- 时区 (`timezone`)
- 网络配置（允许/拒绝的域名）

**输出格式**：XML 格式的用户消息
```xml
<environment_context>
  <cwd>/home/user/project</cwd>
  <shell>zsh</shell>
  <current_date>2026-03-23</current_date>
  <timezone>Asia/Shanghai</timezone>
  <network enabled="true">
    <allowed>api.example.com</allowed>
    <denied>blocked.example.com</denied>
  </network>
</environment_context>
```

#### 2.2.2 权限策略更新 (`build_permissions_update_item`)

```rust
fn build_permissions_update_item(
    previous: Option<&TurnContextItem>,
    next: &TurnContext,
    exec_policy: &Policy,
) -> Option<DeveloperInstructions>
```

**检测的变更**：
- 沙箱策略 (`sandbox_policy`)
- 审批策略 (`approval_policy`)

**输出**：Developer 角色的指令消息，包含权限说明

#### 2.2.3 协作模式更新 (`build_collaboration_mode_update_item`)

```rust
fn build_collaboration_mode_update_item(
    previous: Option<&TurnContextItem>,
    next: &TurnContext,
) -> Option<DeveloperInstructions>
```

**检测的变更**：
- 协作模式配置变化（如从 Plan 模式切换到 Default 模式）

#### 2.2.4 实时会话更新 (`build_realtime_update_item`)

```rust
pub(crate) fn build_realtime_update_item(
    previous: Option<&TurnContextItem>,
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions>
```

**状态转换**：
| 前一状态 | 当前状态 | 操作 |
|---------|---------|------|
| `true` | `false` | 发送实时结束消息 |
| `false`/`None` | `true` | 发送实时开始消息（可带自定义指令） |
| `true` | `true` | 无操作 |
| `false` | `false` | 无操作 |

**特殊处理**：当 `previous` 中没有 `realtime_active` 信息时，会回退到 `previous_turn_settings` 检测。

#### 2.2.5 人格更新 (`build_personality_update_item`)

```rust
fn build_personality_update_item(
    previous: Option<&TurnContextItem>,
    next: &TurnContext,
    personality_feature_enabled: bool,
) -> Option<DeveloperInstructions>
```

**条件**：仅在 `Personality` 特性启用时生效，且模型未变更时（模型切换由 `build_model_instructions_update_item` 处理）。

#### 2.2.6 模型指令更新 (`build_model_instructions_update_item`)

```rust
pub(crate) fn build_model_instructions_update_item(
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions>
```

**触发条件**：当前模型与上一回合模型不同。

**优先级**：在 `build_settings_update_items` 中，此项**最先**被添加到开发者消息中，确保模型特定的指导在其他上下文差异之前被读取。

---

## 3. 具体技术实现

### 3.1 数据结构

#### 3.1.1 TurnContextItem

```rust
// 定义于 codex-rs/protocol/src/protocol.rs
pub struct TurnContextItem {
    pub turn_id: Option<String>,
    pub trace_id: Option<String>,
    pub cwd: PathBuf,
    pub current_date: Option<String>,
    pub timezone: Option<String>,
    pub approval_policy: AskForApproval,
    pub sandbox_policy: SandboxPolicy,
    pub network: Option<TurnContextNetworkItem>,
    pub model: String,
    pub personality: Option<Personality>,
    pub collaboration_mode: Option<CollaborationMode>,
    pub realtime_active: Option<bool>,
    pub effort: Option<ReasoningEffort>,
    pub summary: ReasoningSummary,
    pub user_instructions: Option<String>,
    pub developer_instructions: Option<String>,
    pub final_output_json_schema: Option<Value>,
    pub truncation_policy: Option<TruncationPolicy>,
}
```

这是**持久化的上下文快照**，用于回合间的差异比较。

#### 3.1.2 TurnContext

```rust
// 定义于 codex-rs/core/src/codex.rs
pub(crate) struct TurnContext {
    pub(crate) sub_id: String,
    pub(crate) trace_id: Option<String>,
    pub(crate) realtime_active: bool,
    pub(crate) config: Arc<Config>,
    pub(crate) model_info: ModelInfo,
    // ... 其他字段
}
```

这是**运行时上下文**，包含当前回合的完整配置和状态。

#### 3.1.3 PreviousTurnSettings

```rust
// 定义于 codex-rs/core/src/codex.rs
pub(crate) struct PreviousTurnSettings {
    pub(crate) model: String,
    pub(crate) realtime_active: Option<bool>,
}
```

用于在 `TurnContextItem` 不可用时（如会话恢复后）提供回退比较基准。

### 3.2 关键流程

#### 3.2.1 主流程：构建设置更新项

```
build_settings_update_items
├── build_environment_update_item          → ResponseItem (user role)
└── 构建 developer_update_sections
    ├── build_model_instructions_update_item  → DeveloperInstructions (最高优先级)
    ├── build_permissions_update_item         → DeveloperInstructions
    ├── build_collaboration_mode_update_item  → DeveloperInstructions
    ├── build_realtime_update_item            → DeveloperInstructions
    └── build_personality_update_item         → DeveloperInstructions
    
→ build_developer_update_item(developer_update_sections)  → ResponseItem (developer role)
→ build_contextual_user_message(...) [如果有环境更新]
```

#### 3.2.2 初始上下文构建流程

```rust
// codex-rs/core/src/codex.rs:3390-3553
async fn build_initial_context(&self, turn_context: &TurnContext) -> Vec<ResponseItem>
```

当 `reference_context_item` 为 `None` 时（新会话或恢复后），构建完整的初始上下文：

1. 添加模型切换指令（如果适用）
2. 添加权限策略指令
3. 添加开发者指令
4. 添加记忆工具指令
5. 添加协作模式指令
6. 添加实时会话指令
7. 添加人格指令
8. 添加 Apps/Skills/Plugins 部分
9. 添加 Git 提交指令
10. 添加用户指令
11. 添加环境上下文（带 subagents）

### 3.3 差异比较逻辑

#### 3.3.1 环境上下文比较

```rust
// environment_context.rs
pub fn equals_except_shell(&self, other: &EnvironmentContext) -> bool {
    let EnvironmentContext {
        cwd,
        current_date,
        timezone,
        network,
        subagents,
        shell: _,  // 忽略 shell 比较
    } = other;
    self.cwd == *cwd
        && self.current_date == *current_date
        && self.timezone == *timezone
        && self.network == *network
        && self.subagents == *subagents
}
```

**设计理由**：Shell 在初始环境上下文后不可配置，因此回合间比较时忽略。

#### 3.3.2 权限策略比较

```rust
fn build_permissions_update_item(...) -> Option<DeveloperInstructions> {
    let prev = previous?;
    if prev.sandbox_policy == *next.sandbox_policy.get()
        && prev.approval_policy == next.approval_policy.value()
    {
        return None;  // 无变化，不生成更新
    }
    // ... 生成更新
}
```

### 3.4 消息构建辅助函数

```rust
fn build_text_message(role: &str, text_sections: Vec<String>) -> Option<ResponseItem>
```

将文本段落列表转换为指定角色的 `ResponseItem::Message`：
- 空列表返回 `None`
- 每个段落转换为 `ContentItem::InputText`

---

## 4. 关键代码路径与文件引用

### 4.1 调用链

```
Session::record_context_updates_and_set_reference_context_item
    [codex-rs/core/src/codex.rs:3590-3620]
    │
    ├── 如果 reference_context_item 为 None:
    │   └── Session::build_initial_context
    │       [codex-rs/core/src/codex.rs:3390-3553]
    │       └── 直接调用 updates 模块的独立函数
    │
    └── 否则:
        └── Session::build_settings_update_items
            [codex-rs/core/src/codex.rs:2529-2552]
            └── crate::context_manager::updates::build_settings_update_items
                [updates.rs:187-218]
```

### 4.2 核心文件依赖图

```
updates.rs
├── 输入依赖
│   ├── TurnContext         [codex.rs]
│   ├── PreviousTurnSettings [codex.rs]
│   ├── TurnContextItem     [protocol/src/protocol.rs]
│   ├── Shell               [shell.rs]
│   ├── Policy              [codex_execpolicy]
│   ├── EnvironmentContext  [environment_context.rs]
│   ├── DeveloperInstructions [protocol/src/models.rs]
│   └── ResponseItem        [protocol/src/models.rs]
│
└── 输出使用
    ├── ResponseItem → Session::record_conversation_items
    └── 最终发送到模型 API
```

### 4.3 相关测试文件

| 文件 | 测试内容 |
|------|---------|
| `codex-rs/core/src/codex_tests.rs:3450-3630` | `build_settings_update_items` 系列测试 |
| `codex-rs/core/tests/suite/permissions_messages.rs` | 权限消息集成测试 |
| `codex-rs/core/src/context_manager/history_tests.rs` | 历史记录管理测试 |

---

## 5. 依赖与外部交互

### 5.1 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | `ResponseItem`, `DeveloperInstructions`, `TurnContextItem`, `Personality` |
| `codex_execpolicy` | `Policy`（执行策略管理） |
| `codex_protocol::config_types` | `CollaborationMode` |
| `codex_protocol::openai_models` | `ModelInfo` |

### 5.2 内部模块依赖

| 模块 | 用途 |
|------|------|
| `crate::codex` | `TurnContext`, `PreviousTurnSettings` |
| `crate::environment_context` | `EnvironmentContext` |
| `crate::shell` | `Shell` |
| `crate::features` | `Feature`（特性开关） |

### 5.3 配置集成

```rust
// 特性开关检查
personality_feature_enabled: bool  // Feature::Personality

// 配置访问
next.config.experimental_realtime_start_instructions  // 自定义实时开始指令
```

### 5.4 Prompt 模板文件

| 模板文件 | 用途 |
|---------|------|
| `protocol/src/prompts/permissions/approval_policy/*.md` | 审批策略指令模板 |
| `protocol/src/prompts/permissions/sandbox_mode/*.md` | 沙箱模式指令模板 |
| `protocol/src/prompts/realtime/realtime_start.md` | 实时会话开始指令 |
| `protocol/src/prompts/realtime/realtime_end.md` | 实时会话结束指令 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 状态不一致风险

**问题**：`build_settings_update_items` 的注释明确指出：

```rust
// TODO: Make context updates a pure diff of persisted previous/current TurnContextItem
// state so replay/backtracking is deterministic. Runtime inputs that affect model-visible
// context (shell, exec policy, feature gates, previous-turn bridge) should be persisted
// state or explicit non-state replay events.
```

**影响**：会话恢复或回放时，运行时输入（如 shell、exec policy）可能与原始会话不同，导致非确定性行为。

**缓解**：当前通过 `previous_turn_settings` 提供回退机制。

#### 6.1.2 实时状态检测复杂性

`build_realtime_update_item` 需要同时考虑：
- `previous.and_then(|item| item.realtime_active)`
- `previous_turn_settings.and_then(|settings| settings.realtime_active)`
- `next.realtime_active`

这种多层回退增加了理解难度和潜在的错误风险。

#### 6.1.3 人格与模型切换的竞合

```rust
// build_personality_update_item 中
if next.model_info.slug != previous.model {
    return None;  // 模型切换时不处理人格
}
```

人格更新和模型切换更新是互斥的，这可能导致在同时切换模型和人格时，人格变化被忽略。

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| `previous` 为 `None` | 所有更新项都返回 `None`（首次回合由 `build_initial_context` 处理） |
| 空文本段落 | `build_text_message` 返回 `None` |
| 人格特性禁用 | `build_personality_update_item` 立即返回 `None` |
| 协作模式开发者指令为空 | `build_collaboration_mode_update_item` 返回 `None`，保留之前的协作指令 |
| 模型指令为空 | `build_model_instructions_update_item` 返回 `None` |

### 6.3 改进建议

#### 6.3.1 架构层面

1. **统一状态管理**
   - 将所有影响模型可见上下文的运行时输入（shell、exec policy、feature gates）纳入 `TurnContextItem` 持久化
   - 消除 `previous_turn_settings` 和 `TurnContextItem` 之间的冗余和歧义

2. **显式状态转换事件**
   - 为重要的状态变更（如实时模式切换）引入显式的事件日志
   - 支持更可靠的会话回放和调试

#### 6.3.2 代码层面

1. **增强类型安全**
   ```rust
   // 建议：使用新类型模式避免 bool 参数
   pub struct PersonalityFeatureEnabled(bool);
   ```

2. **简化实时状态检测**
   - 考虑将 `realtime_active` 的追踪统一到单一来源
   - 减少 `Option<bool>` 的嵌套层级

3. **提取公共模式**
   - `build_*_update_item` 函数遵循相似的模式（比较 → 决定是否生成 → 构建）
   - 可以考虑使用宏或 trait 减少样板代码

#### 6.3.3 测试层面

1. **增加边界测试**
   - 同时切换多个设置时的行为
   - 快速连续切换同一设置的累积效果

2. **增加回归测试**
   - 会话恢复后上下文更新的正确性
   - 长时间运行会话的内存和性能特征

### 6.4 性能考量

| 方面 | 现状 | 建议 |
|------|------|------|
| 比较操作 | 字段逐一比较 | 已实现，开销可忽略 |
| 内存分配 | 每次更新创建新的 `ResponseItem` | 考虑对象池优化（高频场景） |
| XML 序列化 | 运行时字符串拼接 | 当前实现简单，如需优化可考虑模板 |

---

## 7. 总结

`updates.rs` 是 Codex 上下文管理系统的**增量更新引擎**，通过智能差异检测最小化模型输入的 Token 开销，同时确保模型始终了解最新的会话状态。

其核心设计原则：
1. **懒加载**：只在变化时生成更新
2. **优先级排序**：模型指令先于其他上下文差异
3. **回退机制**：支持多种历史状态来源
4. **可扩展性**：通过特性开关控制可选功能

理解该模块对于维护 Codex 的上下文一致性、支持会话恢复功能以及添加新的上下文类型至关重要。
