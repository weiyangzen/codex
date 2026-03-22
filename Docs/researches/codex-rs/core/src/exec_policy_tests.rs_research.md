# exec_policy_tests.rs 研究文档

## 场景与职责

`exec_policy_tests.rs` 是 `codex-core`  crate 中执行策略（Exec Policy）模块的测试文件，位于 `codex-rs/core/src/` 目录下。该文件包含了对执行策略管理器（`ExecPolicyManager`）的全面测试，确保命令执行前的安全审批流程正确工作。

执行策略是 Codex 安全模型的核心组件，负责：
- 决定哪些命令需要用户审批
- 解析和应用基于 Starlark 的规则文件（`.rules`）
- 管理命令前缀匹配规则（prefix rules）
- 处理沙箱权限升级请求
- 支持网络规则（network rules）和主机可执行文件规则（host executable rules）

## 功能点目的

### 1. 父子配置策略继承测试
测试 `child_uses_parent_exec_policy` 函数，验证子进程是否应该使用父进程的执行策略：
- 当配置层栈匹配时，子进程应使用父策略
- 当非执行策略层不同时，子进程仍可使用父策略
- 当需求执行策略不同时，子进程不应使用父策略

### 2. 策略文件加载测试
- `returns_empty_policy_when_no_policy_files_exist`: 无规则文件时返回空策略
- `collect_policy_files_returns_empty_when_dir_missing`: 规则目录不存在时返回空
- `loads_policies_from_policy_subdirectory`: 从 `.codex/rules/` 子目录加载规则
- `ignores_policies_outside_policy_dir`: 忽略规则目录外的 `.rules` 文件
- `ignores_rules_from_untrusted_project_layers`: 忽略不可信项目层的规则
- `loads_policies_from_multiple_config_layers`: 从多个配置层（用户+项目）加载并合并规则

### 3. 策略解析错误处理测试
- `format_exec_policy_error_with_source_renders_range`: 格式化策略解析错误，显示文件名和行号
- `parse_starlark_line_from_message_extracts_path_and_line`: 从 Starlark 错误消息中提取路径和行号
- `parse_starlark_line_from_message_rejects_zero_line`: 拒绝零行号

### 4. 需求执行策略合并测试
- `merges_requirements_exec_policy_network_rules`: 合并需求层中的网络规则
- `preserves_host_executables_when_requirements_overlay_is_present`: 在需求覆盖层存在时保留主机可执行文件配置

### 5. Bash 脚本命令解析测试
- `evaluates_bash_lc_inner_commands`: 解析 `bash -lc` 内联命令并应用前缀规则
- `commands_for_exec_policy_falls_back_for_empty_shell_script`: 空脚本回退到原始命令
- `commands_for_exec_policy_falls_back_for_whitespace_shell_script`: 空白脚本回退到原始命令
- `evaluates_heredoc_script_against_prefix_rules`: 对 heredoc 脚本应用前缀规则
- `omits_auto_amendment_for_heredoc_fallback_prompts`: heredoc 回退时不生成自动修正建议
- `drops_requested_amendment_for_heredoc_fallback_prompts_when_it_wont_match`: 当修正建议不匹配时丢弃

### 6. 执行审批需求生成测试
- `justification_is_included_in_forbidden_exec_approval_requirement`: 禁止命令时包含理由
- `exec_approval_requirement_prefers_execpolicy_match`: 优先匹配执行策略规则
- `absolute_path_exec_approval_requirement_matches_host_executable_rules`: 绝对路径命令匹配主机可执行文件规则
- `absolute_path_exec_approval_requirement_ignores_disallowed_host_executable_paths`: 忽略不允许的主机可执行文件路径
- `requested_prefix_rule_can_approve_absolute_path_commands`: 请求的前缀规则可批准绝对路径命令
- `exec_approval_requirement_respects_approval_policy`: 遵守审批策略设置

### 7. 沙箱权限和审批策略测试
- `unmatched_granular_policy_still_prompts_for_restricted_sandbox_escalation`: 细粒度策略下无匹配规则时仍提示沙箱升级
- `unmatched_on_request_uses_split_filesystem_policy_for_escalation_prompts`: OnRequest 策略使用分割文件系统策略进行升级提示
- `exec_approval_requirement_rejects_unmatched_sandbox_escalation_when_granular_sandbox_is_disabled`: 细粒度沙箱禁用时拒绝升级
- `mixed_rule_and_sandbox_prompt_prioritizes_rule_for_rejection_decision`: 规则提示优先于沙箱提示
- `mixed_rule_and_sandbox_prompt_rejects_when_granular_rules_are_disabled`: 细粒度规则禁用时拒绝

### 8. 执行策略修正建议测试
- `exec_approval_requirement_falls_back_to_heuristics`: 回退到启发式规则
- `empty_bash_lc_script_falls_back_to_original_command`: 空 bash 脚本回退
- `whitespace_bash_lc_script_falls_back_to_original_command`: 空白 bash 脚本回退
- `request_rule_uses_prefix_rule`: 请求规则使用前缀规则
- `request_rule_falls_back_when_prefix_rule_does_not_approve_all_commands`: 前缀规则不批准所有命令时回退
- `heuristics_apply_when_other_commands_match_policy`: 其他命令匹配策略时应用启发式规则
- `append_execpolicy_amendment_updates_policy_and_file`: 追加修正建议更新策略和文件
- `append_execpolicy_amendment_rejects_empty_prefix`: 拒绝空前缀修正建议

### 9. 修正建议生成逻辑测试
- `proposed_execpolicy_amendment_is_present_for_single_command_without_policy_match`: 单命令无策略匹配时生成修正建议
- `proposed_execpolicy_amendment_is_omitted_when_policy_prompts`: 策略提示时省略修正建议
- `proposed_execpolicy_amendment_is_present_for_multi_command_scripts`: 多命令脚本生成修正建议
- `proposed_execpolicy_amendment_uses_first_no_match_in_multi_command_scripts`: 使用第一个不匹配的命令生成修正建议
- `proposed_execpolicy_amendment_is_present_when_heuristics_allow`: 启发式允许时生成修正建议
- `proposed_execpolicy_amendment_is_suppressed_when_policy_matches_allow`: 策略匹配允许时抑制修正建议

### 10. 前缀规则推导测试
- `derive_requested_execpolicy_amendment_returns_none_for_missing_prefix_rule`: 缺失前缀规则返回 None
- `derive_requested_execpolicy_amendment_returns_none_for_empty_prefix_rule`: 空前缀规则返回 None
- `derive_requested_execpolicy_amendment_returns_none_for_exact_banned_prefix_rule`: 精确禁止的前缀返回 None
- `derive_requested_execpolicy_amendment_returns_none_for_windows_and_pypy_variants`: Windows 和 PyPy 变体返回 None
- `derive_requested_execpolicy_amendment_returns_none_for_shell_and_powershell_variants`: Shell 和 PowerShell 变体返回 None
- `derive_requested_execpolicy_amendment_allows_non_exact_banned_prefix_rule_match`: 非精确禁止的前缀允许匹配
- `derive_requested_execpolicy_amendment_returns_none_when_policy_matches`: 策略匹配时返回 None

### 11. 危险命令和 PowerShell 测试
- `dangerous_rm_rf_requires_approval_in_danger_full_access`: 危险 `rm -rf` 命令需要审批
- `verify_approval_requirement_for_unsafe_powershell_command`: 验证不安全 PowerShell 命令的审批需求

## 具体技术实现

### 关键数据结构

```rust
// 执行审批请求
pub(crate) struct ExecApprovalRequest<'a> {
    pub(crate) command: &'a [String],
    pub(crate) approval_policy: AskForApproval,
    pub(crate) sandbox_policy: &'a SandboxPolicy,
    pub(crate) file_system_sandbox_policy: &'a FileSystemSandboxPolicy,
    pub(crate) sandbox_permissions: SandboxPermissions,
    pub(crate) prefix_rule: Option<Vec<String>>,
}

// 执行审批需求结果
pub enum ExecApprovalRequirement {
    Skip { bypass_sandbox: bool, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    NeedsApproval { reason: Option<String>, proposed_execpolicy_amendment: Option<ExecPolicyAmendment> },
    Forbidden { reason: String },
}

// 策略评估结果
pub struct Evaluation {
    pub decision: Decision,  // Allow | Prompt | Forbidden
    pub matched_rules: Vec<RuleMatch>,
}
```

### 关键流程

1. **策略加载流程** (`load_exec_policy`):
   ```
   ConfigLayerStack -> 遍历各层 -> 收集 .rules 文件 -> PolicyParser 解析 -> 合并需求层策略
   ```

2. **命令检查流程** (`create_exec_approval_requirement_for_command`):
   ```
   输入命令 -> 解析 bash -lc 脚本 -> 多命令检查 -> 匹配前缀规则 -> 启发式回退 -> 生成审批需求
   ```

3. **决策优先级** (Decision Priority):
   - Forbidden > Prompt > Allow
   - 策略规则匹配优先于启发式规则
   - 最长前缀匹配优先

4. **修正建议生成**:
   - 从启发式规则的 Prompt/Allow 决策生成
   - 排除禁止的前缀（如 `python -c`, `bash -lc` 等）
   - 验证修正建议能批准所有命令

### 测试辅助函数

```rust
// 创建测试配置
async fn test_config() -> (TempDir, Config)

// 创建配置层栈
fn config_stack_for_dot_codex_folder(dot_codex_folder: &Path) -> ConfigLayerStack

// 生成主机绝对路径（跨平台）
fn host_absolute_path(segments: &[&str]) -> String

// 生成主机程序路径
fn host_program_path(name: &str) -> String

// 转义 Starlark 字符串
fn starlark_string(value: &str) -> String

// 只读文件系统沙箱策略
fn read_only_file_system_sandbox_policy() -> FileSystemSandboxPolicy

// 无限制文件系统沙箱策略
fn unrestricted_file_system_sandbox_policy() -> FileSystemSandboxPolicy
```

## 关键代码路径与文件引用

### 被测试的主要源文件

| 文件 | 职责 |
|------|------|
| `codex-rs/core/src/exec_policy.rs` | 执行策略管理器实现 |
| `codex-rs/execpolicy/src/policy.rs` | 策略核心逻辑（Policy, Evaluation） |
| `codex-rs/execpolicy/src/parser.rs` | Starlark 规则解析器（PolicyParser） |
| `codex-rs/execpolicy/src/rule.rs` | 规则定义（PrefixRule, NetworkRule, RuleMatch） |
| `codex-rs/execpolicy/src/decision.rs` | 决策枚举（Decision） |
| `codex-rs/protocol/src/approvals.rs` | ExecPolicyAmendment 定义 |

### 关键依赖 crate

- `codex_execpolicy`: 执行策略核心库
- `codex_protocol`: 协议类型定义
- `codex_config`: 配置层管理
- `codex_utils_absolute_path`: 绝对路径工具

### 测试使用的常量

```rust
const RULES_DIR_NAME: &str = "rules";           // 规则子目录名
const RULE_EXTENSION: &str = "rules";           // 规则文件扩展名
const DEFAULT_POLICY_FILE: &str = "default.rules"; // 默认策略文件名
```

### 禁止的前缀建议列表

```rust
static BANNED_PREFIX_SUGGESTIONS: &[&[&str]] = &[
    &["python3"], &["python3", "-"], &["python3", "-c"],
    &["python"], &["python", "-"], &["python", "-c"],
    &["py"], &["py", "-3"], &["pythonw"], &["pyw"],
    &["pypy"], &["pypy3"], &["git"],
    &["bash"], &["bash", "-lc"], &["sh"], &["sh", "-c"],
    // ... 更多
];
```

## 依赖与外部交互

### 内部模块依赖

```rust
use crate::config::Config;
use crate::config::ConfigBuilder;
use crate::config_loader::ConfigLayerEntry;
use crate::config_loader::ConfigLayerStack;
use crate::config_loader::ConfigRequirements;
use crate::bash::parse_shell_lc_plain_commands;
use crate::is_dangerous_command::command_might_be_dangerous;
use crate::is_safe_command::is_known_safe_command;
```

### 外部 crate 依赖

```rust
use codex_execpolicy::Policy;
use codex_execpolicy::PolicyParser;
use codex_execpolicy::Decision;
use codex_execpolicy::Evaluation;
use codex_execpolicy::RuleMatch;
use codex_protocol::protocol::AskForApproval;
use codex_protocol::protocol::SandboxPolicy;
use codex_protocol::permissions::FileSystemSandboxPolicy;
```

### 测试框架依赖

```rust
use pretty_assertions::assert_eq;
use tempfile::tempdir;
use tokio::test;
```

## 风险、边界与改进建议

### 已知风险

1. **命令注入风险**: `bash -lc` 脚本解析可能无法覆盖所有复杂的 shell 语法，存在命令注入绕过检测的风险
2. **路径遍历风险**: 主机可执行文件规则依赖路径匹配，符号链接可能导致绕过
3. **规则优先级复杂性**: 多配置层合并时规则优先级可能产生意外行为
4. **Windows 特殊处理**: Windows 平台对 `ReadOnly` 沙箱的特殊处理可能导致安全策略不一致

### 边界情况

1. **空命令/空白命令**: 测试覆盖了空字符串和纯空白字符的脚本回退
2. **Heredoc 脚本**: 复杂的 heredoc 语法可能导致解析失败，回退到原始命令
3. **多命令脚本**: `&&` 和 `|` 连接的多命令脚本需要逐一检查
4. **跨平台路径**: 测试使用 `host_absolute_path` 和 `host_program_path` 处理 Windows/Unix 路径差异

### 改进建议

1. **增强测试覆盖**:
   - 添加更多复杂 shell 语法的测试用例（如子 shell、命令替换）
   - 增加并发场景下的策略更新测试
   - 添加性能测试，评估大量规则时的匹配效率

2. **安全加固**:
   - 考虑使用更严格的 shell 解析器替代简单的正则/启发式解析
   - 对主机可执行文件路径进行规范化（canonicalization）处理
   - 增加规则冲突检测和警告

3. **代码质量**:
   - 部分测试函数较长，可拆分为更小的测试单元
   - 增加测试文档，说明每个测试的具体安全场景
   - 使用参数化测试减少重复代码

4. **可维护性**:
   - 将 `BANNED_PREFIX_SUGGESTIONS` 移至配置文件
   - 提供规则调试工具，帮助用户理解规则匹配过程
   - 增加规则热重载功能，无需重启应用

### 相关测试文件

- `codex-rs/core/src/exec_tests.rs`: 执行工具调用的测试
- `codex-rs/core/src/sandboxing/tests.rs`: 沙箱模块测试
- `codex-rs/execpolicy/tests/basic.rs`: execpolicy crate 的基础测试
