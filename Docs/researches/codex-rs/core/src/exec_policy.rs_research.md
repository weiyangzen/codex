# exec_policy.rs 研究文档

## 场景与职责

`exec_policy.rs` 是 Codex 的执行策略管理模块，负责加载、解析和执行基于 Starlark 的执行策略规则。它决定哪些 shell 命令需要用户审批、哪些可以直接执行、哪些被禁止执行。这是 Codex 安全模型的核心组件之一。

### 核心职责

1. **策略加载**：从配置文件加载 `.rules` 文件
2. **规则评估**：评估命令是否符合允许/提示/禁止规则
3. **审批决策**：根据策略和配置决定是否需要用户审批
4. **策略更新**：支持运行时添加新的允许规则（用户批准后）
5. **网络规则管理**：管理网络访问的允许/禁止规则

### 在架构中的位置

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Runtime (shell, unified_exec)                         │
│  - Approvable trait implementation                          │
├─────────────────────────────────────────────────────────────┤
│  exec_policy.rs ◄── 当前模块                                │
│  - ExecPolicyManager                                        │
│  - create_exec_approval_requirement_for_command             │
├─────────────────────────────────────────────────────────────┤
│  codex_execpolicy crate                                     │
│  - Policy (Starlark-based rule engine)                      │
│  - PolicyParser                                             │
│  - Decision (Allow/Prompt/Forbidden)                        │
├─────────────────────────────────────────────────────────────┤
│  Config Layer Stack                                         │
│  - ~/.codex/rules/*.rules                                   │
│  - <project>/.codex/rules/*.rules                           │
└─────────────────────────────────────────────────────────────┘
```

## 功能点目的

### 1. 执行审批要求 (`ExecApprovalRequirement`)

三种决策结果：

```rust
pub(crate) enum ExecApprovalRequirement {
    /// 无需审批，可直接执行
    Skip {
        bypass_sandbox: bool,  // 是否跳过沙箱
        proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    },
    /// 需要用户审批
    NeedsApproval {
        reason: Option<String>,
        proposed_execpolicy_amendment: Option<ExecPolicyAmendment>,
    },
    /// 禁止执行
    Forbidden { reason: String },
}
```

### 2. 策略规则类型

**Prefix Rule**：基于命令前缀匹配
```starlark
prefix_rule(
    pattern = ["git", "status"],
    decision = "allow",
    justification = "查看 git 状态是安全的"
)
```

**Heuristics Rule**：基于启发式规则（代码内建）
- 危险命令检测（`rm -rf`, `mkfs` 等）
- 安全命令白名单（`ls`, `cat`, `echo` 等）

**Network Rule**：网络访问控制
```starlark
network_rule(
    host = "api.example.com",
    protocol = "https",
    decision = "allow"
)
```

### 3. 审批策略集成

与 `AskForApproval` 配置集成：
- `Never`: 拒绝所有需要审批的命令
- `OnFailure`: 仅在失败时需要审批（不适用于策略提示）
- `OnRequest`: 根据策略决定
- `UnlessTrusted`: 总是需要审批（除非被信任）
- `Granular`: 细粒度控制（sandbox_approval, rules 等）

### 4. 命令解析

支持复杂 shell 命令解析：
- `bash -lc "cmd1 && cmd2"` → 解析为多个独立命令
- Heredoc 支持
- 管道和逻辑运算符

### 5. 策略继承与合并

支持多层配置：
- 用户级：`~/.codex/rules/`
- 项目级：`<project>/.codex/rules/`
- 要求级：通过 `requirements.exec_policy` 强制覆盖

## 具体技术实现

### 核心结构

#### `ExecPolicyManager`

```rust
pub(crate) struct ExecPolicyManager {
    policy: ArcSwap<Policy>,           // 原子交换的策略
    update_lock: tokio::sync::Mutex<()>, // 更新锁
}
```

使用 `ArcSwap` 实现无锁读取、有锁写入。

#### `ExecApprovalRequest`

```rust
pub(crate) struct ExecApprovalRequest<'a> {
    pub(crate) command: &'a [String],
    pub(crate) approval_policy: AskForApproval,
    pub(crate) sandbox_policy: &'a SandboxPolicy,
    pub(crate) file_system_sandbox_policy: &'a FileSystemSandboxPolicy,
    pub(crate) sandbox_permissions: SandboxPermissions,
    pub(crate) prefix_rule: Option<Vec<String>>,  // 用户请求的前缀规则
}
```

### 关键流程

#### 1. 策略加载 (`load_exec_policy`)

```rust
pub async fn load_exec_policy(config_stack: &ConfigLayerStack) -> Result<Policy, ExecPolicyError>
```

流程：
1. 遍历配置层（从低优先级到高优先级）
2. 收集每个层的 `rules/` 目录下的 `.rules` 文件
3. 按文件名排序确保确定性顺序
4. 使用 `PolicyParser` 解析每个文件
5. 合并 `requirements.exec_policy` 覆盖

#### 2. 创建审批要求 (`create_exec_approval_requirement_for_command`)

核心算法：

```rust
pub(crate) async fn create_exec_approval_requirement_for_command(
    &self,
    req: ExecApprovalRequest<'_>,
) -> ExecApprovalRequirement {
    // 1. 解析命令（处理 bash -lc 等复杂情况）
    let (commands, used_complex_parsing) = commands_for_exec_policy(command);
    
    // 2. 评估每个命令
    let evaluation = exec_policy.check_multiple_with_options(
        commands.iter(),
        &exec_policy_fallback,  // 未匹配时的回退决策
        &match_options,
    );
    
    // 3. 根据决策类型和审批策略返回结果
    match evaluation.decision {
        Decision::Forbidden => ExecApprovalRequirement::Forbidden { ... },
        Decision::Prompt => {
            // 检查审批策略是否允许提示
            if prompt_is_rejected_by_policy(approval_policy, prompt_is_rule) {
                ExecApprovalRequirement::Forbidden { ... }
            } else {
                ExecApprovalRequirement::NeedsApproval { ... }
            }
        }
        Decision::Allow => ExecApprovalRequirement::Skip { ... },
    }
}
```

#### 3. 未匹配命令的回退决策 (`render_decision_for_unmatched_command`)

复杂决策逻辑：

```rust
pub fn render_decision_for_unmatched_command(
    approval_policy: AskForApproval,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    command: &[String],
    sandbox_permissions: SandboxPermissions,
    used_complex_parsing: bool,
) -> Decision
```

决策树：
1. 已知安全命令 → Allow
2. Windows ReadOnly 沙箱 → Prompt（因为不是真正的沙箱）
3. 危险命令 → 根据 approval_policy 决定 Prompt 或 Forbidden
4. 其他情况 → 根据 approval_policy 和沙箱配置决定

#### 4. 策略更新 (`append_amendment_and_update`)

```rust
pub(crate) async fn append_amendment_and_update(
    &self,
    codex_home: &Path,
    amendment: &ExecPolicyAmendment,
) -> Result<(), ExecPolicyUpdateError>
```

流程：
1. 获取更新锁
2. 追加规则到 `~/.codex/rules/default.rules`
3. 检查规则是否已存在（避免重复）
4. 更新内存中的策略

#### 5. 命令解析 (`commands_for_exec_policy`)

```rust
fn commands_for_exec_policy(command: &[String]) -> (Vec<Vec<String>>, bool)
```

解析策略：
1. 尝试 `parse_shell_lc_plain_commands` - 解析 `bash -lc "cmd1 && cmd2"`
2. 回退到 `parse_shell_lc_single_command_prefix` - 提取单个命令前缀
3. 最终回退到原始命令

返回的 `bool` 表示是否使用了复杂解析（用于决定是否允许自动策略修正）。

### 禁止的前缀建议

为防止过于宽泛的规则，以下前缀被禁止作为自动修正建议：

```rust
static BANNED_PREFIX_SUGGESTIONS: &[&[&str]] = &[
    &["python3"], &["python3", "-"], &["python3", "-c"],
    &["python"], &["python", "-"], &["python", "-c"],
    &["py"], &["py", "-3"], &["pythonw"], &["pyw"],
    &["pypy"], &["pypy3"],
    &["git"],
    &["bash"], &["bash", "-lc"], &["sh"], &["sh", "-c"],
    &["zsh"], &["zsh", "-lc"], &["/bin/zsh"], &["/bin/zsh", "-lc"],
    &["/bin/bash"], &["/bin/bash", "-lc"],
    &["pwsh"], &["pwsh", "-Command"], &["pwsh", "-c"],
    &["powershell"], &["powershell", "-Command"], &["powershell", "-c"],
    &["powershell.exe"], &["powershell.exe", "-Command"], &["powershell.exe", "-c"],
    &["env"], &["sudo"],
    &["node"], &["node", "-e"],
    &["perl"], &["perl", "-e"],
    &["ruby"], &["ruby", "-e"],
    &["php"], &["php", "-r"],
    &["lua"], &["lua", "-e"],
    &["osascript"],
];
```

### 错误处理

#### `ExecPolicyError`

```rust
pub enum ExecPolicyError {
    #[error("failed to read rules files from {dir}: {source}")]
    ReadDir { dir: PathBuf, source: std::io::Error },
    
    #[error("failed to read rules file {path}: {source}")]
    ReadFile { path: PathBuf, source: std::io::Error },
    
    #[error("failed to parse rules file {path}: {source}")]
    ParsePolicy { path: String, source: codex_execpolicy::Error },
}
```

#### `ExecPolicyUpdateError`

```rust
pub enum ExecPolicyUpdateError {
    #[error("failed to update rules file {path}: {source}")]
    AppendRule { path: PathBuf, source: AmendError },
    
    #[error("failed to join blocking rules update task: {source}")]
    JoinBlockingTask { source: tokio::task::JoinError },
    
    #[error("failed to update in-memory rules: {source}")]
    AddRule { source: ExecPolicyRuleError },
}
```

### 错误格式化

```rust
pub fn format_exec_policy_error_with_source(error: &ExecPolicyError) -> String
```

特色功能：
- 提取 Starlark 错误位置（文件:行号）
- 格式化友好的错误消息
- 显示问题所在行号

## 关键代码路径与文件引用

### 核心调用链

```
Shell tool / Code execution
    │
    ▼
ExecPolicyManager::create_exec_approval_requirement_for_command
    │
    ├── commands_for_exec_policy
    │   ├── parse_shell_lc_plain_commands (bash.rs)
    │   └── parse_shell_lc_single_command_prefix (bash.rs)
    │
    ├── Policy::check_multiple_with_options (codex_execpolicy)
    │   └── 评估每个命令
    │
    └── render_decision_for_unmatched_command (回退决策)
        ├── is_known_safe_command (codex_shell_command)
        └── command_might_be_dangerous (codex_shell_command)
```

### 策略更新链

```
User approves command
    │
    ▼
ExecPolicyManager::append_amendment_and_update
    │
    ├── blocking_append_allow_prefix_rule (codex_execpolicy)
    │   └── 写入 ~/.codex/rules/default.rules
    │
    └── 更新内存中的 Policy
```

### 相关文件

| 文件 | 关系 |
|------|------|
| `codex_execpolicy` crate | 底层策略引擎（Starlark 解析、规则评估） |
| `codex_shell_command::bash` | Shell 命令解析 |
| `codex_shell_command::is_safe_command` | 安全命令检测 |
| `codex_shell_command::is_dangerous_command` | 危险命令检测 |
| `config_loader.rs` | 配置层管理 |
| `tools/sandboxing.rs` | `ExecApprovalRequirement` 定义 |

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `codex_execpolicy` | Starlark 策略引擎 |
| `codex_shell_command` | Shell 命令解析和安全检测 |
| `arc_swap::ArcSwap` | 无锁策略读取 |
| `shlex::try_join` | 命令序列化 |
| `tokio::fs` | 异步文件操作 |
| `tokio::task::spawn_blocking` | 阻塞策略更新 |

### 配置集成

```rust
// 从配置层加载
let manager = ExecPolicyManager::load(&config.config_layer_stack).await?;

// 检查配置警告
let warning = check_execpolicy_for_warnings(&config.config_layer_stack).await?;
```

### 文件系统布局

```
~/.codex/
└── rules/
    └── default.rules          # 用户级默认规则

<project>/.codex/
└── rules/
    ├── default.rules          # 项目级规则
    └── custom.rules           # 其他规则文件
```

## 风险、边界与改进建议

### 安全风险

1. **过于宽泛的规则**
   - 禁止列表阻止了一些危险前缀，但可能不够全面
   - 建议：添加更多解释器（如 `ruby`, `node` 的更多变体）

2. **策略注入攻击**
   - 恶意项目可能通过 `.codex/rules/` 添加宽松规则
   - 缓解：用户需要显式信任项目配置

3. **命令解析绕过**
   - 复杂的 shell 脚本可能绕过解析
   - 缓解：`used_complex_parsing` 标志禁用自动修正

### 边界情况

1. **空命令**
   - 空命令列表返回 `Decision::Allow`
   - 可能导致意外行为

2. **循环依赖**
   - 策略文件之间的依赖可能导致循环
   - 当前由 `codex_execpolicy` 处理

3. **并发更新**
   - 使用 `tokio::sync::Mutex` 确保顺序更新
   - 但文件系统操作可能失败，导致内存和文件不一致

### 性能考虑

1. **策略评估**
   - 每个命令都进行完整评估
   - 对于包含数百个命令的脚本可能有性能影响

2. **文件 I/O**
   - 策略更新使用 `spawn_blocking`
   - 大策略文件可能导致阻塞

### 改进建议

#### 1. 增强安全检测

```rust
// 建议添加更多危险模式
static ADDITIONAL_BANNED_PREFIXES: &[&[&str]] = &[
    &["curl", "|", "sh"],      // curl | sh 模式
    &["wget", "-O", "-"],      // wget 管道到 shell
    &["eval"],                  // eval 命令
];
```

#### 2. 策略缓存

```rust
// 添加 LRU 缓存避免重复评估相同命令
pub(crate) struct ExecPolicyManager {
    policy: ArcSwap<Policy>,
    update_lock: tokio::sync::Mutex<()>,
    decision_cache: RwLock<LruCache<Vec<String>, Decision>>,  // 新增
}
```

#### 3. 策略版本控制

```rust
// 支持策略版本，便于迁移和兼容性
pub struct PolicyMetadata {
    version: String,
    created_at: DateTime<Utc>,
    source: ConfigLayerSource,
}
```

#### 4. 更好的错误恢复

```rust
// 部分策略失败时继续加载其他策略
pub async fn load_exec_policy resilient mode
```

#### 5. 策略验证工具

```rust
// 添加验证命令
pub fn validate_policy(policy_str: &str) -> Result<Vec<ValidationIssue>, ParseError>
```

### 测试覆盖

测试文件：`exec_policy_tests.rs`

主要测试场景：
- 策略加载和合并
- 命令评估（Allow/Prompt/Forbidden）
- 审批策略集成
- 策略更新
- 错误格式化
- 复杂命令解析

建议补充：
- 大规模策略性能测试
- 并发更新测试
- 恶意策略检测测试
