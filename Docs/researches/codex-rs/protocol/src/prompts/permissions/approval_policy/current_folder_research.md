# DIR Research: codex-rs/protocol/src/prompts/permissions/approval_policy

## 场景与职责

该目录包含 Codex CLI 的**命令执行审批策略提示模板**，用于指导 AI 模型在不同审批策略下如何请求用户授权执行 shell 命令。这些模板被嵌入到发送给模型的 developer instructions 中，是 Codex 安全架构的关键组成部分。

**核心职责：**
1. 定义不同审批策略下模型应如何请求命令执行权限
2. 指导模型何时应该请求权限提升（escalation）
3. 规范 `prefix_rule` 的使用，允许用户持久化批准特定命令前缀
4. 支持 `request_permissions` 工具的使用指导

**使用场景：**
- 用户通过 CLI 或 TUI 与 Codex 交互时，系统根据配置的 `approval_policy` 加载对应的提示模板
- 模型根据这些指导决定何时需要请求用户批准执行命令
- 在安全沙箱环境中，指导模型如何请求额外的权限

---

## 功能点目的

### 1. never.md - 完全禁止审批策略

**目的：** 当 `approval_policy` 设置为 `never` 时，告知模型不提供 `sandbox_permissions` 参数，所有命令将被拒绝。

**内容：**
```
Approval policy is currently never. Do not provide the `sandbox_permissions` for any reason, commands will be rejected.
```

**使用场景：** 非交互式环境或完全自动化的 CI/CD 场景，禁止任何需要用户交互的命令执行。

### 2. unless_trusted.md - 非信任命令需审批

**目的：** 当 `approval_policy` 设置为 `unless-trusted` 时，告知模型大部分命令需要用户批准，只有有限的安全"读取"命令白名单可以自动执行。

**内容：**
```
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `unless-trusted`: The harness will escalate most commands for user approval, apart from a limited allowlist of safe "read" commands.
```

**使用场景：** 交互式开发环境，用户希望保持控制但允许安全的读取操作自动执行。

### 3. on_failure.md - 失败时请求审批

**目的：** 当 `approval_policy` 设置为 `on-failure` 时，告知模型所有命令先在沙箱中运行，失败时再升级请求用户批准无沙箱运行。

**内容：**
```
Approvals are your mechanism to get user consent to run shell commands without the sandbox. `approval_policy` is `on-failure`: The harness will allow all commands to run in the sandbox (if enabled), and failures will be escalated to the user for approval to run again without the sandbox.
```

**使用场景：** 希望最大化自动化，只在必要时才打扰用户。

### 4. on_request_rule.md - 按需请求审批（基础版）

**目的：** 当 `approval_policy` 设置为 `on-request` 且未启用 `request_permissions` 工具时，提供详细的权限升级指导。

**关键功能点：**
- **命令分段逻辑：** 命令在管道符、逻辑运算符、分号、子shell边界处被分割为独立段，每段独立评估
- **权限升级请求方式：**
  - 使用 `sandbox_permissions: "require_escalated"`
  - 在 `justification` 参数中包含简短问题询问用户
  - 可选提供 `prefix_rule` 建议持久化规则
- **何时请求升级：**
  - 需要写入受限目录（如 `/var`）
  - 需要运行 GUI 应用
  - 沙箱相关网络错误（DNS、注册表访问、依赖下载失败）
  - 潜在的破坏性操作（`rm`、`git reset`）
- **prefix_rule 指导：**
  - 禁止：`["python3"]`、`["python", "-"]` 等过于宽泛的前缀
  - 禁止为破坏性命令（如 `rm`）提供 prefix_rule
  - 禁止使用 heredoc 或 herestring 时提供 prefix_rule
  - 推荐：`["npm", "run", "dev"]`、`["pytest"]`、`["cargo", "test"]` 等

### 5. on_request_rule_request_permission.md - 按需请求审批（完整版）

**目的：** 当 `approval_policy` 设置为 `on-request` 且启用了 `request_permissions` 工具时，提供更全面的权限管理指导。

**额外功能：**
- **首选请求模式：** 优先使用 `sandbox_permissions: "with_additional_permissions"` 和 `additional_permissions` 参数请求沙箱内额外权限
- **支持的网络权限：** `network.enabled`
- **支持的文件系统权限：** `file_system.read`、`file_system.write`
- **完整升级请求：** 当沙箱内权限无法满足时才使用 `require_escalated`

---

## 具体技术实现

### 模板加载与使用流程

```rust
// 在 codex-rs/protocol/src/models.rs 中定义
const APPROVAL_POLICY_NEVER: &str = include_str!("prompts/permissions/approval_policy/never.md");
const APPROVAL_POLICY_UNLESS_TRUSTED: &str = include_str!("prompts/permissions/approval_policy/unless_trusted.md");
const APPROVAL_POLICY_ON_FAILURE: &str = include_str!("prompts/permissions/approval_policy/on_failure.md");
const APPROVAL_POLICY_ON_REQUEST_RULE: &str = include_str!("prompts/permissions/approval_policy/on_request_rule.md");
const APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION: &str = include_str!("prompts/permissions/approval_policy/on_request_rule_request_permission.md");
```

### DeveloperInstructions 生成逻辑

```rust
// DeveloperInstructions::from() 方法
impl DeveloperInstructions {
    pub fn from(
        approval_policy: AskForApproval,
        exec_policy: &Policy,
        exec_permission_approvals_enabled: bool,
        request_permissions_tool_enabled: bool,
    ) -> DeveloperInstructions {
        let with_request_permissions_tool = |text: &str| {
            if request_permissions_tool_enabled {
                format!("{text}\n\n{}", request_permissions_tool_prompt_section())
            } else {
                text.to_string()
            }
        };
        
        let on_request_instructions = || {
            let on_request_rule = if exec_permission_approvals_enabled {
                APPROVAL_POLICY_ON_REQUEST_RULE_REQUEST_PERMISSION.to_string()
            } else {
                APPROVAL_POLICY_ON_REQUEST_RULE.to_string()
            };
            // ... 构建完整指令
        };
        
        let text = match approval_policy {
            AskForApproval::Never => APPROVAL_POLICY_NEVER.to_string(),
            AskForApproval::UnlessTrusted => with_request_permissions_tool(APPROVAL_POLICY_UNLESS_TRUSTED),
            AskForApproval::OnFailure => with_request_permissions_tool(APPROVAL_POLICY_ON_FAILURE),
            AskForApproval::OnRequest => on_request_instructions(),
            AskForApproval::Granular(granular_config) => granular_instructions(...),
        };
        
        DeveloperInstructions::new(text)
    }
}
```

### 相关数据结构

#### AskForApproval 枚举

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, Display, JsonSchema, TS)]
#[serde(rename_all = "kebab-case")]
#[strum(serialize_all = "kebab-case")]
pub enum AskForApproval {
    /// 只有"已知安全"的命令自动批准，其他都需要询问
    #[serde(rename = "untrusted")]
    #[strum(serialize = "untrusted")]
    UnlessTrusted,

    /// 所有命令在沙箱中自动运行，失败时升级
    OnFailure,

    /// 模型决定何时询问（默认）
    #[default]
    OnRequest,

    /// 细粒度控制
    #[strum(serialize = "granular")]
    Granular(GranularApprovalConfig),

    /// 从不询问，直接返回失败
    Never,
}
```

#### SandboxPermissions 枚举

```rust
#[derive(Debug, Clone, Copy, Default, Eq, Hash, PartialEq, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
pub enum SandboxPermissions {
    /// 使用回合配置的默认沙箱策略
    #[default]
    UseDefault,
    /// 请求在无沙箱环境下运行
    RequireEscalated,
    /// 请求在沙箱内但放宽权限
    WithAdditionalPermissions,
}
```

#### ShellToolCallParams 结构体

```rust
#[derive(Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
pub struct ShellToolCallParams {
    pub command: Vec<String>,
    pub workdir: Option<String>,
    pub timeout_ms: Option<u64>,
    pub sandbox_permissions: Option<SandboxPermissions>,
    pub prefix_rule: Option<Vec<String>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub justification: Option<String>,
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 作用 |
|------|------|
| `codex-rs/protocol/src/prompts/permissions/approval_policy/never.md` | 完全禁止审批策略模板 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/unless_trusted.md` | 非信任命令需审批模板 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_failure.md` | 失败时请求审批模板 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule.md` | 按需请求审批基础模板 |
| `codex-rs/protocol/src/prompts/permissions/approval_policy/on_request_rule_request_permission.md` | 按需请求审批完整模板 |
| `codex-rs/protocol/src/models.rs` | 模板加载和 DeveloperInstructions 生成 |
| `codex-rs/protocol/src/protocol.rs` | AskForApproval 枚举定义 |
| `codex-rs/protocol/src/approvals.rs` | 审批相关事件和结构体 |
| `codex-rs/protocol/src/permissions.rs` | 文件系统和网络沙箱策略 |

### 调用链

```
1. CLI/TUI 启动时配置 approval_policy
   ↓
2. codex-core 创建 CodexThread 时传入配置
   ↓
3. 每轮对话开始时生成 DeveloperInstructions
   ↓
4. DeveloperInstructions::from() 根据 approval_policy 选择对应模板
   ↓
5. 模板内容嵌入到发送给模型的 developer message
   ↓
6. 模型根据指导决定何时请求权限
   ↓
7. 模型调用 shell 工具时传入 sandbox_permissions/justification/prefix_rule
   ↓
8. exec_policy 评估命令并决定是否触发审批流程
```

### 测试覆盖

- `codex-rs/core/tests/suite/approvals.rs` - 审批流程测试
- `codex-rs/core/tests/suite/request_permissions.rs` - 权限请求测试
- `codex-rs/core/tests/suite/exec_policy.rs` - 执行策略测试
- `codex-rs/protocol/src/models.rs` 中的单元测试 - DeveloperInstructions 生成测试

---

## 依赖与外部交互

### 内部依赖

| 模块 | 依赖关系 |
|------|----------|
| `codex-execpolicy` | 执行策略评估，`Decision` 枚举（Allow/Prompt/Forbidden）|
| `codex-protocol` | 本目录所属 crate，提供协议类型定义 |
| `codex-core` | 使用 DeveloperInstructions 构建对话上下文 |
| `codex-utils-absolute-path` | 路径处理 |

### 外部交互

| 交互方 | 交互方式 |
|--------|----------|
| OpenAI API | 模板内容通过 developer message 发送给模型 |
| 用户 | 通过 CLI/TUI 响应审批请求 |
| 配置文件 | `approval_policy` 从 config.toml 读取 |

### 配置关联

```toml
# ~/.codex/config.toml 示例
[permissions]
approval_policy = "on-request"  # 可选: never, unless-trusted, on-failure, on-request

[permissions.granular]
sandbox_approval = true
rules = true
skill_approval = true
request_permissions = true
mcp_elicitations = true
```

---

## 风险、边界与改进建议

### 潜在风险

1. **提示注入风险**
   - 用户输入可能通过某种方式影响模型对审批策略的理解
   - 缓解：模板内容固定，不直接包含用户输入

2. **模型误解风险**
   - 模型可能错误理解 `prefix_rule` 的使用限制
   - 缓解：模板中明确禁止某些危险的 prefix_rule 模式

3. **过度授权风险**
   - 用户可能批准过于宽泛的 prefix_rule（如 `["python3"]`）
   - 缓解：模板明确警告不要批准过于宽泛的前缀

4. **沙箱逃逸风险**
   - 如果模型不正确使用 `sandbox_permissions` 参数
   - 缓解：后端有独立的 exec_policy 评估层

### 边界情况

1. **命令分段边界**
   - 复杂命令如 `git pull | tee output.txt` 被分为多个段
   - 每段独立评估，可能产生多个审批请求

2. **Granular 策略**
   - 当使用 `Granular` 策略时，模板内容由 `granular_instructions()` 函数动态生成
   - 不是直接使用本目录的静态模板

3. **网络审批**
   - 网络访问审批有独立的 `NetworkApprovalContext` 和 `NetworkPolicyAmendment`
   - 不通过本目录的模板处理

### 改进建议

1. **模板国际化**
   - 当前模板只有英文版本
   - 建议：支持多语言模板，根据用户 locale 自动选择

2. **动态示例**
   - 当前示例是静态的
   - 建议：根据用户历史行为提供个性化的 prefix_rule 示例

3. **可视化指导**
   - 纯文本模板可能不够直观
   - 建议：在 TUI 中提供交互式的权限指导界面

4. **审批策略继承**
   - 当前策略是全局的
   - 建议：支持按项目、按目录继承不同的审批策略

5. **审计日志**
   - 建议：记录所有审批决策和使用的模板版本，便于安全审计

6. **模板版本控制**
   - 建议：为模板添加版本号，便于追踪变更和回滚

---

## 总结

`approval_policy` 目录是 Codex CLI 安全架构的**策略表达层**，通过精心设计的提示模板，指导 AI 模型在不同场景下正确地请求用户授权。这些模板与底层的 `exec_policy` 执行策略、`SandboxPolicy` 沙箱策略相互配合，形成了完整的安全防护体系。

模板的设计体现了以下安全原则：
1. **最小权限原则**：默认使用沙箱，只在必要时请求升级
2. **用户控制原则**：用户始终保有最终决策权
3. **透明性原则**：模型必须说明请求权限的理由
4. **持久化便利**：通过 prefix_rule 减少重复审批
