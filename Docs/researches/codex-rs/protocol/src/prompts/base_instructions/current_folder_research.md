# DIR codex-rs/protocol/src/prompts/base_instructions 研究文档

## 场景与职责

`base_instructions` 目录是 Codex CLI 项目的核心提示词（prompt）模板存储位置之一，位于 `codex-rs/protocol/src/prompts/` 下。该目录专门存放用于定义 AI Agent 基础行为指令的 Markdown 模板文件。

**核心职责：**
1. **定义 Agent 基础人格与行为准则** - 向 AI 模型说明其身份（Codex CLI 中的编码助手）、工作方式和交互规范
2. **提供系统级指令模板** - 作为 `DeveloperInstructions` 结构的默认内容源，通过 `include_str!` 宏在编译期嵌入 Rust 代码
3. **规范工具使用协议** - 详细说明 `apply_patch` 等关键工具的正确使用方式
4. **建立安全与审批边界** - 明确 Agent 在沙箱环境中的权限范围和用户审批机制

**使用场景：**
- 新会话启动时，作为系统消息（developer role message）注入到模型上下文
- 与 `permissions/` 和 `realtime/` 目录下的模板协同工作，构建完整的指令集
- 通过 `BaseInstructions` 结构封装，供 `codex-core` 等上层 crate 调用

---

## 功能点目的

### 1. 默认基础指令 (`default.md`)

**文件路径：** `codex-rs/protocol/src/prompts/base_instructions/default.md`

**功能目的：**
- **身份定义**：明确告知模型其为 "coding agent running in the Codex CLI"，由 OpenAI 领导的开源项目
- **能力说明**：列出 Agent 的核心能力（接收提示、流式响应、函数调用、补丁应用）
- **AGENTS.md 规范**：详细说明项目中 `AGENTS.md` 文件的作用、作用域和优先级规则
- **响应风格指南**：
  - 前置消息（Preamble）编写规范：简洁、1-2 句话、逻辑分组
  - 计划工具（`update_plan`）使用指南
  - 任务执行准则：自主解决问题、使用 `apply_patch` 工具、遵循代码风格
- **工具使用规范**：
  - `apply_patch` 命令的精确格式要求（`*** Begin Patch` / `*** End Patch` 标记）
  - 禁止使用的替代工具（`applypatch`, `apply-patch`）
- **最终答案格式**：
  - 标题格式（`**Title Case**`）
  - 列表格式（`- ` 前缀）
  - 代码引用格式（反引号包裹）
  - 文件引用规范（支持绝对路径、工作区相对路径、行号标注）

### 2. 指令组合机制

**在 `models.rs` 中的整合：**

```rust
pub const BASE_INSTRUCTIONS_DEFAULT: &str = include_str!("prompts/base_instructions/default.md");

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

**组合流程：**
1. `DeveloperInstructions::from_policy()` 整合沙箱策略和审批策略
2. `DeveloperInstructions::from_permissions_with_network()` 组合多个指令片段
3. 使用 `concat()` 方法按顺序拼接：沙箱指令 → 审批策略指令 → 可写根目录指令
4. 最终包装在 `<permissions instructions>` 标签中

---

## 具体技术实现

### 关键数据结构

#### 1. `BaseInstructions` 结构

```rust
// codex-rs/protocol/src/models.rs:453-465
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(rename = "base_instructions", rename_all = "snake_case")]
pub struct BaseInstructions {
    pub text: String,
}
```

- 对应 Responses API 中的 `instructions` 字段
- 通过 `include_str!` 在编译期加载 `default.md` 内容
- 支持序列化/反序列化（用于配置持久化）

#### 2. `DeveloperInstructions` 结构

```rust
// codex-rs/protocol/src/models.rs:469-473
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(rename = "developer_instructions", rename_all = "snake_case")]
pub struct DeveloperInstructions {
    text: String,
}
```

- 表示开发者提供的指导，以 developer role message 形式注入
- 提供丰富的工厂方法构建不同场景的指令：
  - `from()` - 基于审批策略和 exec 策略构建
  - `from_policy()` - 基于沙箱策略构建
  - `realtime_start_message()` / `realtime_end_message()` - 实时会话控制
  - `model_switch_message()` - 模型切换场景
  - `personality_spec_message()` - 人格定制场景

#### 3. 指令片段常量

```rust
// codex-rs/protocol/src/models.rs:475-492
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str = include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str = include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str = include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str = include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");

const SANDBOX_MODE_DANGER_FULL_ACCESS: &str = include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str = include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = include_str!("prompts/permissions/sandbox_mode/read_only.md");

const REALTIME_START_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_start.md");
const REALTIME_END_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_end.md");
```

### 关键流程

#### 1. 指令构建流程

```
DeveloperInstructions::from_policy()
    ├── sandbox_text() - 加载沙箱模式模板
    │   └── 替换 {network_access} 占位符
    ├── DeveloperInstructions::from() - 加载审批策略模板
    │   ├── Never → never.md
    │   ├── UnlessTrusted → unless_trusted.md (+ request_permissions tool)
    │   ├── OnFailure → on_failure.md (+ request_permissions tool)
    │   ├── OnRequest → on_request_rule.md (+ request_permissions tool + approved prefixes)
    │   └── Granular → granular_instructions() (动态构建)
    ├── from_writable_roots() - 添加可写目录列表
    └── 包装在 <permissions instructions> 标签中
```

#### 2. 转换为 ResponseItem

```rust
// codex-rs/protocol/src/models.rs:839-851
impl From<DeveloperInstructions> for ResponseItem {
    fn from(di: DeveloperInstructions) -> Self {
        ResponseItem::Message {
            id: None,
            role: "developer".to_string(),
            content: vec![ContentItem::InputText {
                text: di.into_text(),
            }],
            end_turn: None,
            phase: None,
        }
    }
}
```

### 协议与标签

**关键 XML 标签（定义于 `protocol.rs`）：**

```rust
// codex-rs/protocol/src/protocol.rs:82-98
pub const USER_INSTRUCTIONS_OPEN_TAG: &str = "<user_instructions>";
pub const USER_INSTRUCTIONS_CLOSE_TAG: &str = "</user_instructions>";
pub const ENVIRONMENT_CONTEXT_OPEN_TAG: &str = "<environment_context>";
pub const ENVIRONMENT_CONTEXT_CLOSE_TAG: &str = "</environment_context>";
pub const COLLABORATION_MODE_OPEN_TAG: &str = "<collaboration_mode>";
pub const COLLABORATION_MODE_CLOSE_TAG: &str = "</collaboration_mode>";
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const REALTIME_CONVERSATION_CLOSE_TAG: &str = "</realtime_conversation>";
pub const USER_MESSAGE_BEGIN: &str = "## My request for Codex:";
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/base_instructions/default.md` | 默认基础指令模板（275 行） |
| `codex-rs/protocol/src/models.rs` | `BaseInstructions` 和 `DeveloperInstructions` 定义与实现 |
| `codex-rs/protocol/src/protocol.rs` | 协议标签常量、审批策略和沙箱策略枚举 |
| `codex-rs/protocol/src/config_types.rs` | `SandboxMode`、`CollaborationMode` 等配置类型 |

### 相关提示词模板文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/never.md` | 永不审批策略说明 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/unless_trusted.md` | 除非信任否则审批策略 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_failure.md` | 失败时审批策略 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule.md` | 请求时审批策略（56 行详细说明） |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule_request_permission.md` | 带 request_permissions 工具的审批策略（33 行） |
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/danger_full_access.md` | 危险完全访问沙箱模式 |
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/read_only.md` | 只读沙箱模式 |
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/workspace_write.md` | 工作区写入沙箱模式 |
| `codex-rs/protocol/src/prompts/realtime/realtime_start.md` | 实时会话开始指令（9 行） |
| `codex-rs/protocol/src/prompts/realtime/realtime_end.md` | 实时会话结束指令（3 行） |

### 关键代码位置

```rust
// 基础指令常量定义
// codex-rs/protocol/src/models.rs:450
pub const BASE_INSTRUCTIONS_DEFAULT: &str = include_str!("prompts/base_instructions/default.md");

// DeveloperInstructions 构建逻辑
// codex-rs/protocol/src/models.rs:499-545
impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions { ... }
}

// 从沙箱策略构建指令
// codex-rs/protocol/src/models.rs:590-623
pub fn from_policy(
    sandbox_policy: &SandboxPolicy,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    cwd: &Path,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self { ... }

// 沙箱文本模板替换
// codex-rs/protocol/src/models.rs:686-695
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode { ... };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

---

## 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 |
|---------|------|
| `codex-rs/protocol/src/protocol.rs` | `AskForApproval`、`SandboxPolicy`、`NetworkAccess` 等策略枚举 |
| `codex-rs/protocol/src/config_types.rs` | `SandboxMode`、`CollaborationMode` 等配置类型 |
| `codex-rs/protocol/src/permissions.rs` | 文件系统权限策略实现 |
| `codex-execpolicy` | 执行策略（`Policy`）用于命令前缀规则 |

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|---------|------|
| OpenAI Responses API | 协议对齐 | `BaseInstructions` 对应 API 的 `instructions` 字段 |
| codex-core | 调用 | `CodexThread` 调用 `DeveloperInstructions::from_policy()` 构建每轮指令 |
| codex-tui | 调用 | TUI 层通过协议提交 `UserTurn` 时携带上下文 |
| 编译时 | `include_str!` | Markdown 模板在编译期嵌入二进制 |

### 编译时依赖

所有 `.md` 文件通过 `include_str!` 宏在编译期加载，这意味着：
- 模板修改需要重新编译 `codex-protocol` crate
- 运行时无文件 I/O 开销
- 二进制文件自包含所有提示词模板

---

## 风险、边界与改进建议

### 已知风险

1. **模板内容膨胀风险**
   - `default.md` 已达 275 行，包含大量规范说明
   - 过长的指令会增加 token 消耗和上下文窗口压力
   - **缓解措施：** 已按功能拆分到多个子目录（`permissions/`、`realtime/`）

2. **占位符替换边界**
   - 沙箱模板使用 `{network_access}` 占位符
   - 若模板修改导致占位符名称变化，但代码未同步更新，会导致未替换的占位符残留
   - **代码位置：** `models.rs:692`

3. **指令顺序依赖**
   - `from_permissions_with_network()` 方法中指令按固定顺序拼接
   - 顺序变更可能影响模型理解
   - **代码位置：** `models.rs:648-663`

4. **跨平台路径处理**
   - 可写根目录列表在 Windows/Unix 上格式可能不一致
   - 使用 `` ` `` 包裹路径，依赖模型理解不同路径格式

### 边界情况

1. **空指令处理**
   - `from_writable_roots()` 在无可写根时返回空字符串
   - 空字符串与后续 `concat()` 不会产生额外换行

2. **Granular 审批策略复杂性**
   - `granular_instructions()` 函数动态构建指令（`models.rs:711-781`）
   - 涉及多个布尔标志组合，测试覆盖需全面

3. **实时会话状态切换**
   - `realtime_start_message()` 和 `realtime_end_message()` 使用 XML 标签包裹
   - 标签不匹配可能导致模型混淆会话状态

### 改进建议

1. **模板验证机制**
   - 建议在 CI 中添加模板语法检查，确保：
     - 所有占位符（如 `{network_access}`）都有对应的替换逻辑
     - Markdown 格式正确（无未闭合的代码块）
   - 可添加单元测试验证模板加载成功

2. **动态模板加载（可选）**
   - 当前编译期嵌入适合发布版本
   - 开发环境可考虑运行时加载，便于快速迭代提示词
   - 通过 feature flag 控制（如 `dynamic-prompts`）

3. **指令版本控制**
   - 建议在 `BaseInstructions` 中添加版本字段
   - 便于 A/B 测试和回滚
   - 格式：`base_instructions_v1`, `base_instructions_v2`

4. **国际化准备**
   - 当前模板全为英文
   - 若未来需要多语言支持，建议：
     - 按语言拆分目录（`prompts/en/base_instructions/`）
     - 或使用 gettext 风格的 key-value 替换

5. **文档同步**
   - `default.md` 中的规范（如文件引用格式）与 `AGENTS.md` 中的规范需保持一致
   - 建议添加同步检查脚本

6. **Token 优化**
   - 评估 `default.md` 中各部分的实际必要性
   - 考虑将部分详细说明移至文档链接，减少指令长度
   - 例如：工具使用规范可精简为关键要点 + 链接到完整文档

---

## 总结

`codex-rs/protocol/src/prompts/base_instructions/` 目录虽然只包含一个 `default.md` 文件，但它是整个 Codex CLI Agent 行为的基石。该文件定义了：

1. **Agent 的身份认知** - 我是谁、我能做什么
2. **交互协议** - 如何与用户沟通、如何使用工具
3. **代码规范** - 如何修改文件、如何格式化输出
4. **安全边界** - 沙箱环境的基本约束

通过与 `permissions/` 和 `realtime/` 目录的模板组合，构建了完整的上下文指令系统。这种模块化设计使得：
- 基础行为与权限策略解耦
- 实时会话场景可独立控制
- 新增审批策略只需添加模板文件

理解此目录的工作原理，对于调试 Agent 行为、优化提示词效果、以及扩展新功能场景都至关重要。
