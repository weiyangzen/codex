# 研究文档：codex-rs/protocol/src/prompts/permissions/sandbox_mode

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`sandbox_mode` 目录位于 `codex-rs/protocol/src/prompts/permissions/` 下，是 Codex 协议层中负责**沙箱模式提示模板**的核心组件。该目录包含三个 Markdown 文件，分别定义了三种不同的文件系统沙箱模式的模型提示内容。

### 核心职责

1. **模型行为指导**：向 AI 模型传达当前文件系统沙箱的权限边界，指导模型在受限环境下做出合理的工具调用决策
2. **安全策略传达**：将技术层面的沙箱配置（SandboxPolicy）转换为模型可理解的自然语言指令
3. **权限升级引导**：在必要时指导模型如何请求额外的权限或沙箱外执行

### 使用场景

| 场景 | 说明 |
|------|------|
| 会话初始化 | 当新的对话回合开始时，将沙箱模式说明注入到 Developer Instructions 中 |
| 权限变更 | 当用户通过配置或交互修改沙箱模式时，更新模型上下文 |
| 调试输出 | 在 `/debug-config` 命令输出中显示当前沙箱模式配置 |

---

## 功能点目的

### 三种沙箱模式

#### 1. Read-Only (`read_only.md`)

```
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `read-only`: The sandbox only permits reading files. 
Network access is {network_access}.
```

**目的**：
- 提供最严格的文件系统访问控制
- 仅允许读取操作，禁止任何文件写入
- 适用于不可信代码执行或高度敏感环境

#### 2. Workspace-Write (`workspace_write.md`)

```
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `workspace-write`: The sandbox permits reading files, 
and editing files in `cwd` and `writable_roots`. 
Editing files in other directories requires approval. 
Network access is {network_access}.
```

**目的**：
- 平衡安全性与实用性
- 允许在工作目录（cwd）和配置的 writable_roots 中写入
- 编辑其他目录需要用户审批
- 这是默认推荐的沙箱模式

#### 3. Danger-Full-Access (`danger_full_access.md`)

```
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `danger-full-access`: No filesystem sandboxing - all commands are permitted. 
Network access is {network_access}.
```

**目的**：
- 完全禁用文件系统沙箱
- 所有命令都被允许执行
- 仅在受信任环境或特殊需求下使用
- 带有明确的安全警告意味（命名中的 "danger"）

### 模板变量

所有三个模板都包含一个可替换变量 `{network_access}`，该变量会被替换为：
- `enabled` - 网络访问已启用
- `restricted` - 网络访问受限

---

## 具体技术实现

### 模板加载机制

模板文件通过 Rust 的 `include_str!` 宏在编译时嵌入到二进制中：

```rust
// codex-rs/protocol/src/models.rs
const SANDBOX_MODE_DANGER_FULL_ACCESS: &str = 
    include_str!("prompts/permissions/sandbox_mode/danger_full_access.md");
const SANDBOX_MODE_WORKSPACE_WRITE: &str = 
    include_str!("prompts/permissions/sandbox_mode/workspace_write.md");
const SANDBOX_MODE_READ_ONLY: &str = 
    include_str!("prompts/permissions/sandbox_mode/read_only.md");
```

### 模板渲染流程

#### 1. DeveloperInstructions 构建

```rust
// models.rs: DeveloperInstructions::sandbox_text()
fn sandbox_text(mode: SandboxMode, network_access: NetworkAccess) -> DeveloperInstructions {
    let template = match mode {
        SandboxMode::DangerFullAccess => SANDBOX_MODE_DANGER_FULL_ACCESS.trim_end(),
        SandboxMode::WorkspaceWrite => SANDBOX_MODE_WORKSPACE_WRITE.trim_end(),
        SandboxMode::ReadOnly => SANDBOX_MODE_READ_ONLY.trim_end(),
    };
    let text = template.replace("{network_access}", &network_access.to_string());
    DeveloperInstructions::new(text)
}
```

#### 2. 完整权限指令组装

```rust
// models.rs: DeveloperInstructions::from_permissions_with_network()
fn from_permissions_with_network(
    sandbox_mode: SandboxMode,
    network_access: NetworkAccess,
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    writable_roots: Option<Vec<WritableRoot>>,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> Self {
    let start_tag = DeveloperInstructions::new("<permissions instructions>");
    let end_tag = DeveloperInstructions::new("</permissions instructions>");
    start_tag
        .concat(DeveloperInstructions::sandbox_text(sandbox_mode, network_access))
        .concat(DeveloperInstructions::from(
            approval_policy,
            exec_policy,
            exec_permission_approvals_enabled,
            request_permissions_tool_enabled,
        ))
        .concat(DeveloperInstructions::from_writable_roots(writable_roots))
        .concat(end_tag)
}
```

### 数据结构关联

#### SandboxMode 枚举

```rust
// codex-rs/protocol/src/config_types.rs
#[derive(Deserialize, Debug, Clone, Copy, PartialEq, Default, Serialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum SandboxMode {
    #[serde(rename = "read-only")]
    #[default]
    ReadOnly,

    #[serde(rename = "workspace-write")]
    WorkspaceWrite,

    #[serde(rename = "danger-full-access")]
    DangerFullAccess,
}
```

#### SandboxPolicy 枚举

```rust
// codex-rs/protocol/src/protocol.rs
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Display, JsonSchema, TS)]
#[strum(serialize_all = "kebab-case")]
#[serde(tag = "type", rename_all = "kebab-case")]
pub enum SandboxPolicy {
    #[serde(rename = "danger-full-access")]
    DangerFullAccess,

    #[serde(rename = "read-only")]
    ReadOnly {
        access: ReadOnlyAccess,
        network_access: bool,
    },

    #[serde(rename = "external-sandbox")]
    ExternalSandbox {
        network_access: NetworkAccess,
    },

    #[serde(rename = "workspace-write")]
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

### 与 Approval Policy 的协作

沙箱模式提示与审批策略提示协同工作：

```rust
// models.rs: DeveloperInstructions::from()
pub fn from(
    approval_policy: AskForApproval,
    exec_policy: &Policy,
    exec_permission_approvals_enabled: bool,
    request_permissions_tool_enabled: bool,
) -> DeveloperInstructions {
    let text = match approval_policy {
        AskForApproval::Never => APPROVAL_POLICY_NEVER.to_string(),
        AskForApproval::UnlessTrusted => {
            with_request_permissions_tool(APPROVAL_POLICY_UNLESS_TRUSTED)
        }
        AskForApproval::OnFailure => with_request_permissions_tool(APPROVAL_POLICY_ON_FAILURE),
        AskForApproval::OnRequest => on_request_instructions(),
        AskForApproval::Granular(granular_config) => granular_instructions(...),
    };
    DeveloperInstructions::new(text)
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/read_only.md` | 只读沙箱模式提示模板 |
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/workspace_write.md` | 工作区写入沙箱模式提示模板 |
| `codex-rs/protocol/src/prompts/permissions/sandbox_mode/danger_full_access.md` | 完全访问沙箱模式提示模板 |
| `codex-rs/protocol/src/models.rs` | 模板加载与渲染逻辑 |
| `codex-rs/protocol/src/config_types.rs` | SandboxMode 枚举定义 |
| `codex-rs/protocol/src/protocol.rs` | SandboxPolicy 枚举定义 |

### 调用链

```
UserTurn / OverrideTurnContext
    ↓
DeveloperInstructions::from_policy()
    ↓
DeveloperInstructions::from_permissions_with_network()
    ↓
DeveloperInstructions::sandbox_text()
    ↓
模板选择 (SANDBOX_MODE_*) + 变量替换
    ↓
DeveloperInstructions 注入到模型上下文
```

### 相关测试

```rust
// models.rs 中的测试
#[test]
fn converts_sandbox_mode_into_developer_instructions() {
    let workspace_write: DeveloperInstructions = SandboxMode::WorkspaceWrite.into();
    assert_eq!(
        workspace_write,
        DeveloperInstructions::new(
            "Filesystem sandboxing defines which files can be read or written. 
             `sandbox_mode` is `workspace-write`: The sandbox permits reading files, 
             and editing files in `cwd` and `writable_roots`. 
             Editing files in other directories requires approval. 
             Network access is restricted."
        )
    );
    // ...
}
```

---

## 依赖与外部交互

### 上游依赖（调用方）

1. **TUI 层** (`codex-rs/tui/`)
   - `tui/src/lib.rs`: 通过 CLI 参数 `--sandbox` 接收沙箱模式配置
   - `tui/src/debug_config.rs`: 在调试输出中格式化沙箱模式要求

2. **CLI 层** (`codex-rs/cli/`)
   - `cli/src/debug_sandbox.rs`: `create_sandbox_mode()` 根据 `full_auto` 标志创建沙箱模式

3. **App Server 层** (`codex-rs/app-server/`)
   - 通过协议 v1/v2 接收客户端的沙箱模式配置

### 下游依赖（被调用方）

1. **核心执行层** (`codex-rs/core/`)
   - `core/src/tools/sandboxing.rs`: 根据沙箱策略执行实际的沙箱控制
   - `core/src/config/mod.rs`: 配置加载与沙箱策略解析

2. **平台特定沙箱实现**
   - macOS: Seatbelt (`core/src/seatbelt/`)
   - Linux: Landlock/bubblewrap (`linux-sandbox/`)
   - Windows: Windows Sandbox (`core/src/windows_sandbox.rs`)

### 横向依赖

1. **Approval Policy 提示** (`prompts/permissions/approval_policy/`)
   - `never.md`: 永不审批策略
   - `unless_trusted.md`: 除非受信任
   - `on_failure.md`: 失败时审批
   - `on_request_rule.md`: 请求时审批规则
   - `on_request_rule_request_permission.md`: 带权限工具的审批规则

---

## 风险、边界与改进建议

### 当前风险

#### 1. 模板与实现不一致风险

**问题**：模板中的描述需要与实际 `SandboxPolicy` 实现保持同步。如果代码逻辑变更但模板未更新，会导致模型接收错误的权限信息。

**示例**：
- 模板说 "editing files in other directories requires approval"
- 但实际 `SandboxPolicy` 实现可能直接拒绝而非请求审批

#### 2. 变量替换简单性

**问题**：仅支持 `{network_access}` 一个变量，无法动态表达更复杂的权限边界（如具体的 writable_roots 列表）。

**当前处理**：`writable_roots` 通过单独的 `from_writable_roots()` 方法追加，而非模板变量。

#### 3. 缺乏版本控制

**问题**：模板内容变更没有版本标识，可能导致模型对相同沙箱模式产生不同理解。

### 边界情况

#### 1. ExternalSandbox 模式映射

```rust
// models.rs: from_policy()
SandboxPolicy::ExternalSandbox { .. } => (SandboxMode::DangerFullAccess, None),
```

外部沙箱模式在提示中被映射为 `DangerFullAccess`，这可能误导模型认为完全没有沙箱限制。

#### 2. 网络访问状态

```rust
// models.rs: sandbox_text() 中的网络访问判断
let network_access = match mode {
    SandboxMode::DangerFullAccess => NetworkAccess::Enabled,
    SandboxMode::WorkspaceWrite | SandboxMode::ReadOnly => NetworkAccess::Restricted,
};
```

注意：这里 `DangerFullAccess` 模式硬编码为网络启用，但实际策略可能不同。

### 改进建议

#### 1. 模板验证测试

建议增加自动化测试，验证模板渲染后的输出包含预期的关键信息：

```rust
#[test]
fn sandbox_mode_template_contains_required_elements() {
    let instructions: DeveloperInstructions = SandboxMode::WorkspaceWrite.into();
    let text = instructions.into_text();
    assert!(text.contains("workspace-write"));
    assert!(text.contains("cwd"));
    assert!(text.contains("writable_roots"));
    assert!(text.contains("Network access"));
}
```

#### 2. 结构化模板替代纯文本

考虑使用结构化数据（如 JSON）替代纯 Markdown 模板，使模型能更精确地解析权限边界：

```json
{
  "sandbox_mode": "workspace-write",
  "filesystem": {
    "read": "all",
    "write": ["cwd", "writable_roots"]
  },
  "network": "restricted"
}
```

#### 3. 版本化提示

在提示中增加版本标识，便于追踪模型行为变化：

```markdown
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `workspace-write` (v1.2): ...
```

#### 4. 动态权限边界表达

考虑扩展模板变量系统，支持更多动态内容：

```markdown
Filesystem sandboxing defines which files can be read or written. 
`sandbox_mode` is `workspace-write`: The sandbox permits reading files, 
and editing files in `cwd`{writable_roots_list}. 
Editing files in other directories requires approval. 
Network access is {network_access}.
```

其中 `{writable_roots_list}` 可动态展开为具体的可写路径列表。

#### 5. 多语言支持

当前模板仅支持英文，对于非英语用户可能需要本地化支持。

---

## 总结

`sandbox_mode` 目录是 Codex 安全架构中的关键组成部分，通过简洁的 Markdown 模板向 AI 模型传达文件系统沙箱边界。虽然当前实现简单有效，但在模板与代码同步、动态权限表达等方面仍有改进空间。理解这一机制对于维护 Codex 的安全性和模型行为一致性至关重要。
