# unix_escalation_tests.rs 研究文档

## 场景与职责

`unix_escalation_tests.rs` 是 `unix_escalation.rs` 的配套测试文件，位于同一目录下通过 `#[path = "unix_escalation_tests.rs"]` 引入。该文件包含对 Unix 平台 Zsh Fork 权限升级系统的**单元测试和集成测试**，确保策略决策、命令解析、权限计算等核心逻辑的正确性。

### 测试范围

1. **策略拒绝逻辑**：验证不同 `AskForApproval` 配置下的拒绝行为
2. **沙箱权限计算**：测试权限降级和升级场景
3. **命令解析**：验证 shell 命令提取的准确性
4. **策略评估**：测试执行策略的匹配逻辑
5. **macOS Seatbelt 扩展**：验证平台特定的权限扩展处理

---

## 功能点目的

### 1. 策略拒绝测试

**目的**：确保 `execve_prompt_is_rejected_by_policy` 函数在各种配置组合下正确判断是否拒绝执行。

**测试场景**：
- Skill 脚本的批准检查（`skill_approval` 标志）
- 前缀规则批准检查（`rules` 标志）
- 未匹配命令的批准检查（`sandbox_approval` 标志）

### 2. 沙箱权限测试

**目的**：验证 `approval_sandbox_permissions` 函数正确处理预批准的额外权限。

**核心逻辑**：
- 当 `additional_permissions_preapproved = true` 时，`WithAdditionalPermissions` 应降级为 `UseDefault`
- 其他情况保持原权限级别

### 3. 命令解析测试

**目的**：确保 `extract_shell_script` 正确解析各种 shell 命令格式。

**覆盖场景**：
- 标准 `-c` 和 `-lc` 标志
- 环境包装器前缀（`env VAR=val /bin/zsh -lc`）
- 沙盒包装器前缀（`sandbox-exec -p policy /bin/zsh -c`）
- 不支持格式的错误处理

### 4. 策略评估测试

**目的**：验证 `evaluate_intercepted_exec_policy` 的策略匹配逻辑。

**测试重点**：
- Shell wrapper 解析启用/禁用的差异
- 主机可执行文件映射（`host_executable`）
- 预批准权限的处理
- 不匹配路径的拒绝

### 5. macOS Seatbelt 扩展测试

**目的**：验证 macOS 平台特定的 Seatbelt 配置文件扩展处理。

**测试场景**：
- `TurnDefault` 执行模式下的扩展保留
- `Permissions` 执行模式下的扩展应用
- 权限配置文件的扩展合并

---

## 具体技术实现

### 测试辅助函数

#### `host_absolute_path`
```rust
fn host_absolute_path(segments: &[&str]) -> String {
    let mut path = if cfg!(windows) {
        PathBuf::from(r"C:\")
    } else {
        PathBuf::from("/")
    };
    for segment in segments {
        path.push(segment);
    }
    path.to_string_lossy().into_owned()
}
```
**用途**：生成跨平台测试路径（Windows 使用 `C:\`，Unix 使用 `/`）。

#### `starlark_string`
```rust
fn starlark_string(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}
```
**用途**：转义字符串用于 Starlark 规则文件（`.rules`）的嵌入。

#### `read_only_file_system_sandbox_policy`
```rust
fn read_only_file_system_sandbox_policy() -> FileSystemSandboxPolicy {
    FileSystemSandboxPolicy::restricted(vec![FileSystemSandboxEntry {
        path: FileSystemPath::Special {
            value: FileSystemSpecialPath::Root,
        },
        access: FileSystemAccessMode::Read,
    }])
}
```
**用途**：创建只读根目录的沙箱策略，用于测试默认场景。

#### `test_skill_metadata`
```rust
fn test_skill_metadata(permission_profile: Option<PermissionProfile>) -> SkillMetadata {
    SkillMetadata {
        name: "skill".to_string(),
        description: "description".to_string(),
        short_description: None,
        interface: None,
        dependencies: None,
        policy: None,
        permission_profile,
        managed_network_override: None,
        path_to_skills_md: PathBuf::from("/tmp/skill/SKILL.md"),
        scope: SkillScope::User,
    }
}
```
**用途**：创建测试用的 Skill 元数据，可指定权限配置。

### 测试用例详解

#### 1. 策略拒绝测试

**`execve_prompt_rejection_uses_skill_approval_for_skill_scripts`**
```rust
#[test]
fn execve_prompt_rejection_uses_skill_approval_for_skill_scripts() {
    let decision_source = super::DecisionSource::SkillScript {
        skill: test_skill_metadata(None),
    };

    // 所有批准标志启用 → 不拒绝
    assert_eq!(
        super::execve_prompt_is_rejected_by_policy(
            AskForApproval::Granular(GranularApprovalConfig {
                sandbox_approval: true,
                rules: true,
                skill_approval: true,
                request_permissions: true,
                mcp_elicitations: true,
            }),
            &decision_source,
        ),
        None,
    );

    // skill_approval 禁用 → 拒绝
    assert_eq!(
        super::execve_prompt_is_rejected_by_policy(
            AskForApproval::Granular(GranularApprovalConfig {
                sandbox_approval: true,
                rules: true,
                skill_approval: false,  // 禁用
                request_permissions: true,
                mcp_elicitations: true,
            }),
            &decision_source,
        ),
        Some("approval required by skill, but AskForApproval::Granular.skill_approval is false"),
    );
}
```

**`execve_prompt_rejection_keeps_prefix_rules_on_rules_flag`**
```rust
#[test]
fn execve_prompt_rejection_keeps_prefix_rules_on_rules_flag() {
    assert_eq!(
        super::execve_prompt_is_rejected_by_policy(
            AskForApproval::Granular(GranularApprovalConfig {
                sandbox_approval: true,
                rules: false,  // 禁用规则批准
                skill_approval: true,
                request_permissions: true,
                mcp_elicitations: true,
            }),
            &super::DecisionSource::PrefixRule,
        ),
        Some("approval required by policy rule, but AskForApproval::Granular.rules is false"),
    );
}
```

**`execve_prompt_rejection_keeps_unmatched_commands_on_sandbox_flag`**
```rust
#[test]
fn execve_prompt_rejection_keeps_unmatched_commands_on_sandbox_flag() {
    assert_eq!(
        super::execve_prompt_is_rejected_by_policy(
            AskForApproval::Granular(GranularApprovalConfig {
                sandbox_approval: false,  // 禁用沙箱批准
                rules: true,
                skill_approval: true,
                request_permissions: true,
                mcp_elicitations: true,
            }),
            &super::DecisionSource::UnmatchedCommandFallback,
        ),
        Some("approval required by policy, but AskForApproval::Granular.sandbox_approval is false"),
    );
}
```

#### 2. 沙箱权限测试

**`approval_sandbox_permissions_only_downgrades_preapproved_additional_permissions`**
```rust
#[test]
fn approval_sandbox_permissions_only_downgrades_preapproved_additional_permissions() {
    // 预批准 + WithAdditionalPermissions → 降级为 UseDefault
    assert_eq!(
        super::approval_sandbox_permissions(SandboxPermissions::WithAdditionalPermissions, true),
        SandboxPermissions::UseDefault,
    );
    // 未预批准 → 保持原样
    assert_eq!(
        super::approval_sandbox_permissions(SandboxPermissions::WithAdditionalPermissions, false),
        SandboxPermissions::WithAdditionalPermissions,
    );
    // RequireEscalated 永不降级
    assert_eq!(
        super::approval_sandbox_permissions(SandboxPermissions::RequireEscalated, true),
        SandboxPermissions::RequireEscalated,
    );
}
```

#### 3. 命令解析测试

**`extract_shell_script_preserves_login_flag`**
```rust
#[test]
fn extract_shell_script_preserves_login_flag() {
    // -lc → login = true
    assert_eq!(
        extract_shell_script(&["/bin/zsh".into(), "-lc".into(), "echo hi".into()]).unwrap(),
        ParsedShellCommand {
            program: "/bin/zsh".to_string(),
            script: "echo hi".to_string(),
            login: true,
        }
    );
    // -c → login = false
    assert_eq!(
        extract_shell_script(&["/bin/zsh".into(), "-c".into(), "echo hi".into()]).unwrap(),
        ParsedShellCommand {
            program: "/bin/zsh".to_string(),
            script: "echo hi".to_string(),
            login: false,
        }
    );
}
```

**`extract_shell_script_supports_wrapped_command_prefixes`**
```rust
#[test]
fn extract_shell_script_supports_wrapped_command_prefixes() {
    // env 包装器
    assert_eq!(
        extract_shell_script(&[
            "/usr/bin/env".into(),
            "CODEX_EXECVE_WRAPPER=1".into(),
            "/bin/zsh".into(),
            "-lc".into(),
            "echo hello".into()
        ])
        .unwrap(),
        ParsedShellCommand {
            program: "/bin/zsh".to_string(),
            script: "echo hello".to_string(),
            login: true,
        }
    );

    // sandbox-exec 包装器
    assert_eq!(
        extract_shell_script(&[
            "sandbox-exec".into(),
            "-p".into(),
            "sandbox_policy".into(),
            "/bin/zsh".into(),
            "-c".into(),
            "pwd".into(),
        ])
        .unwrap(),
        ParsedShellCommand {
            program: "/bin/zsh".to_string(),
            script: "pwd".to_string(),
            login: false,
        }
    );
}
```

**`extract_shell_script_rejects_unsupported_shell_invocation`**
```rust
#[test]
fn extract_shell_script_rejects_unsupported_shell_invocation() {
    let err = extract_shell_script(&[
        "sandbox-exec".into(),
        "-fc".into(),  // 不支持 -fc
        "echo not supported".into(),
    ])
    .unwrap_err();
    assert!(matches!(err, super::ToolError::Rejected(_)));
    assert_eq!(
        match err {
            super::ToolError::Rejected(reason) => reason,
            _ => "".to_string(),
        },
        "unexpected shell command format for zsh-fork execution"
    );
}
```

#### 4. 命令连接测试

**`join_program_and_argv_replaces_original_argv_zero`**
```rust
#[test]
fn join_program_and_argv_replaces_original_argv_zero() {
    // 相对路径 argv[0] 被替换为绝对路径 program
    assert_eq!(
        join_program_and_argv(
            &AbsolutePathBuf::from_absolute_path("/tmp/tool").unwrap(),
            &["./tool".into(), "--flag".into(), "value".into()],
        ),
        vec!["/tmp/tool", "--flag", "value"]
    );
    // 单参数情况
    assert_eq!(
        join_program_and_argv(
            &AbsolutePathBuf::from_absolute_path("/tmp/tool").unwrap(),
            &["./tool".into()]
        ),
        vec!["/tmp/tool"]
    );
}
```

#### 5. 策略评估测试

**`evaluate_intercepted_exec_policy_uses_wrapper_command_when_shell_wrapper_parsing_disabled`**
```rust
#[test]
fn evaluate_intercepted_exec_policy_uses_wrapper_command_when_shell_wrapper_parsing_disabled() {
    let policy_src = r#"prefix_rule(pattern = ["npm", "publish"], decision = "prompt")"#;
    let mut parser = PolicyParser::new();
    parser.parse("test.rules", policy_src).unwrap();
    let policy = parser.build();
    let program = AbsolutePathBuf::try_from(host_absolute_path(&["bin", "zsh"])).unwrap();

    let enable_intercepted_exec_policy_shell_wrapper_parsing = false;
    let evaluation = evaluate_intercepted_exec_policy(
        &policy,
        &program,
        &[
            "zsh".to_string(),
            "-lc".to_string(),
            "npm publish".to_string(),
        ],
        InterceptedExecPolicyContext {
            approval_policy: AskForApproval::OnRequest,
            sandbox_policy: &SandboxPolicy::new_read_only_policy(),
            file_system_sandbox_policy: &read_only_file_system_sandbox_policy(),
            sandbox_permissions: SandboxPermissions::UseDefault,
            enable_shell_wrapper_parsing: enable_intercepted_exec_policy_shell_wrapper_parsing,
        },
    );

    // 禁用 wrapper 解析时，整个命令行被当作一个单元处理
    // 由于策略中没有 /bin/zsh 的规则，使用启发式规则允许
    assert!(
        matches!(
            evaluation.matched_rules.as_slice(),
            [RuleMatch::HeuristicsRuleMatch { command, decision: Decision::Allow }]
                if command == &vec![
                    program.to_string_lossy().to_string(),
                    "-lc".to_string(),
                    "npm publish".to_string(),
                ]
        ),
        // 详细注释说明行为...
    );
}
```

**`evaluate_intercepted_exec_policy_matches_inner_shell_commands_when_enabled`**
```rust
#[test]
fn evaluate_intercepted_exec_policy_matches_inner_shell_commands_when_enabled() {
    let policy_src = r#"prefix_rule(pattern = ["npm", "publish"], decision = "prompt")"#;
    let mut parser = PolicyParser::new();
    parser.parse("test.rules", policy_src).unwrap();
    let policy = parser.build();
    let program = AbsolutePathBuf::try_from(host_absolute_path(&["bin", "bash"])).unwrap();

    let enable_intercepted_exec_policy_shell_wrapper_parsing = true;
    let evaluation = evaluate_intercepted_exec_policy(
        &policy,
        &program,
        &[
            "bash".to_string(),
            "-lc".to_string(),
            "npm publish".to_string(),
        ],
        InterceptedExecPolicyContext {
            approval_policy: AskForApproval::OnRequest,
            sandbox_policy: &SandboxPolicy::new_read_only_policy(),
            file_system_sandbox_policy: &read_only_file_system_sandbox_policy(),
            sandbox_permissions: SandboxPermissions::UseDefault,
            enable_shell_wrapper_parsing: enable_intercepted_exec_policy_shell_wrapper_parsing,
        },
    );

    // 启用 wrapper 解析时，内部命令 "npm publish" 被匹配
    assert_eq!(
        evaluation,
        Evaluation {
            decision: Decision::Prompt,
            matched_rules: vec![RuleMatch::PrefixRuleMatch {
                matched_prefix: vec!["npm".to_string(), "publish".to_string()],
                decision: Decision::Prompt,
                resolved_program: None,
                justification: None,
            }],
        }
    );
}
```

**`intercepted_exec_policy_uses_host_executable_mappings`**
```rust
#[test]
fn intercepted_exec_policy_uses_host_executable_mappings() {
    let git_path = host_absolute_path(&["usr", "bin", "git"]);
    let git_path_literal = starlark_string(&git_path);
    let policy_src = format!(
        r#"
prefix_rule(pattern = ["git", "status"], decision = "prompt")
host_executable(name = "git", paths = ["{git_path_literal}"])
"#
    );
    let mut parser = PolicyParser::new();
    parser.parse("test.rules", &policy_src).unwrap();
    let policy = parser.build();
    let program = AbsolutePathBuf::try_from(git_path).unwrap();

    let evaluation = evaluate_intercepted_exec_policy(
        &policy,
        &program,
        &["git".to_string(), "status".to_string()],
        // ...
    );

    // host_executable 映射使规则匹配成功
    assert_eq!(
        evaluation,
        Evaluation {
            decision: Decision::Prompt,
            matched_rules: vec![RuleMatch::PrefixRuleMatch {
                matched_prefix: vec!["git".to_string(), "status".to_string()],
                decision: Decision::Prompt,
                resolved_program: Some(program),
                justification: None,
            }],
        }
    );
    assert!(CoreShellActionProvider::decision_driven_by_policy(
        &evaluation.matched_rules,
        evaluation.decision
    ));
}
```

**`intercepted_exec_policy_treats_preapproved_additional_permissions_as_default`**
```rust
#[test]
fn intercepted_exec_policy_treats_preapproved_additional_permissions_as_default() {
    let policy = PolicyParser::new().build();
    let program = AbsolutePathBuf::try_from(host_absolute_path(&["usr", "bin", "printf"])).unwrap();
    let argv = ["printf".to_string(), "hello".to_string()];
    let approval_policy = AskForApproval::OnRequest;
    let sandbox_policy = SandboxPolicy::new_workspace_write_policy();
    let file_system_sandbox_policy = read_only_file_system_sandbox_policy();

    // 预批准情况
    let preapproved = evaluate_intercepted_exec_policy(
        &policy,
        &program,
        &argv,
        InterceptedExecPolicyContext {
            approval_policy,
            sandbox_policy: &sandbox_policy,
            file_system_sandbox_policy: &file_system_sandbox_policy,
            sandbox_permissions: super::approval_sandbox_permissions(
                SandboxPermissions::WithAdditionalPermissions,
                true,  // 预批准
            ),
            enable_shell_wrapper_parsing: false,
        },
    );
    
    // 新鲜请求情况
    let fresh_request = evaluate_intercepted_exec_policy(
        &policy,
        &program,
        &argv,
        InterceptedExecPolicyContext {
            approval_policy,
            sandbox_policy: &sandbox_policy,
            file_system_sandbox_policy: &file_system_sandbox_policy,
            sandbox_permissions: SandboxPermissions::WithAdditionalPermissions,
            enable_shell_wrapper_parsing: false,
        },
    );

    // 预批准 → Allow（不提示）
    assert_eq!(preapproved.decision, Decision::Allow);
    // 未预批准 → Prompt（需要批准）
    assert_eq!(fresh_request.decision, Decision::Prompt);
}
```

#### 6. 升级执行测试

**`shell_request_escalation_execution_is_explicit`**
```rust
#[test]
fn shell_request_escalation_execution_is_explicit() {
    let requested_permissions = PermissionProfile { /* ... */ };
    let sandbox_policy = SandboxPolicy::WorkspaceWrite { /* ... */ };
    let file_system_sandbox_policy = FileSystemSandboxPolicy::restricted(/* ... */);
    let network_sandbox_policy = NetworkSandboxPolicy::Restricted;
    let macos_seatbelt_profile_extensions = MacOsSeatbeltProfileExtensions { /* ... */ };

    // UseDefault → TurnDefault
    assert_eq!(
        CoreShellActionProvider::shell_request_escalation_execution(
            SandboxPermissions::UseDefault,
            &sandbox_policy,
            &file_system_sandbox_policy,
            network_sandbox_policy,
            None,
            Some(&macos_seatbelt_profile_extensions),
        ),
        EscalationExecution::TurnDefault,
    );
    
    // RequireEscalated → Unsandboxed
    assert_eq!(
        CoreShellActionProvider::shell_request_escalation_execution(
            SandboxPermissions::RequireEscalated,
            &sandbox_policy,
            &file_system_sandbox_policy,
            network_sandbox_policy,
            None,
            Some(&macos_seatbelt_profile_extensions),
        ),
        EscalationExecution::Unsandboxed,
    );
    
    // WithAdditionalPermissions + 权限 → Permissions
    assert_eq!(
        CoreShellActionProvider::shell_request_escalation_execution(
            SandboxPermissions::WithAdditionalPermissions,
            &sandbox_policy,
            &file_system_sandbox_policy,
            network_sandbox_policy,
            Some(&requested_permissions),
            Some(&macos_seatbelt_profile_extensions),
        ),
        EscalationExecution::Permissions(EscalationPermissions::Permissions(
            EscalatedPermissions {
                sandbox_policy,
                file_system_sandbox_policy,
                network_sandbox_policy,
                macos_seatbelt_profile_extensions: Some(macos_seatbelt_profile_extensions),
            },
        )),
    );
}
```

**`skill_escalation_execution_uses_additional_permissions`**
```rust
#[test]
fn skill_escalation_execution_uses_additional_permissions() {
    let requested_permissions = PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: None,
            write: Some(vec![
                AbsolutePathBuf::from_absolute_path("/tmp/output").unwrap(),
            ]),
        }),
        ..Default::default()
    };

    // 有权限声明的 Skill → Permissions
    assert_eq!(
        CoreShellActionProvider::skill_escalation_execution(&test_skill_metadata(Some(
            requested_permissions.clone(),
        ))),
        EscalationExecution::Permissions(EscalationPermissions::PermissionProfile(
            requested_permissions,
        )),
    );
}
```

**`skill_escalation_execution_ignores_empty_permissions`**
```rust
#[test]
fn skill_escalation_execution_ignores_empty_permissions() {
    // 空权限 → TurnDefault
    assert_eq!(
        CoreShellActionProvider::skill_escalation_execution(&test_skill_metadata(Some(
            PermissionProfile::default(),
        ))),
        EscalationExecution::TurnDefault,
    );
    // 无权限声明 → TurnDefault
    assert_eq!(
        CoreShellActionProvider::skill_escalation_execution(&test_skill_metadata(None)),
        EscalationExecution::TurnDefault,
    );
}
```

#### 7. macOS Seatbelt 扩展测试

**`prepare_escalated_exec_turn_default_preserves_macos_seatbelt_extensions`**
```rust
#[cfg(target_os = "macos")]
#[tokio::test]
async fn prepare_escalated_exec_turn_default_preserves_macos_seatbelt_extensions() {
    let cwd = AbsolutePathBuf::from_absolute_path(std::env::temp_dir()).unwrap();
    let executor = CoreShellCommandExecutor {
        // ... 配置 executor，包含 macos_seatbelt_profile_extensions
        macos_seatbelt_profile_extensions: Some(MacOsSeatbeltProfileExtensions {
            macos_preferences: MacOsPreferencesPermission::ReadWrite,
            ..Default::default()
        }),
        // ...
    };

    let prepared = executor
        .prepare_escalated_exec(
            &AbsolutePathBuf::from_absolute_path("/bin/echo").unwrap(),
            &["echo".to_string(), "ok".to_string()],
            &cwd,
            HashMap::new(),
            EscalationExecution::TurnDefault,
        )
        .await
        .unwrap();

    // 验证使用 seatbelt 可执行文件
    assert_eq!(
        prepared.command.first().map(String::as_str),
        Some(MACOS_PATH_TO_SEATBELT_EXECUTABLE)
    );
    // 验证包含用户偏好写入权限
    assert!(
        prepared
            .command
            .get(2)
            .is_some_and(|policy| policy.contains("(allow user-preference-write)")),
        "expected seatbelt policy to include macOS extension profile: {:?}",
        prepared.command
    );
}
```

**`prepare_escalated_exec_permissions_preserve_macos_seatbelt_extensions`**
```rust
#[cfg(target_os = "macos")]
#[tokio::test]
async fn prepare_escalated_exec_permissions_preserve_macos_seatbelt_extensions() {
    // 测试完全指定的 Permissions 执行模式下的扩展保留
    // ... 类似结构，验证 EscalationExecution::Permissions(EscalationPermissions::Permissions(...))
}
```

**`prepare_escalated_exec_permission_profile_unions_turn_and_requested_macos_extensions`**
```rust
#[cfg(target_os = "macos")]
#[tokio::test]
async fn prepare_escalated_exec_permission_profile_unions_turn_and_requested_macos_extensions() {
    // 测试 PermissionProfile 模式下的扩展合并
    // Turn 配置有 macos_preferences: ReadOnly
    // 请求配置有 macos_calendar: true
    // 验证最终策略同时包含两者
}
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 被测函数/结构 | 定义位置 |
|-------------|---------|
| `execve_prompt_is_rejected_by_policy` | `unix_escalation.rs:335-358` |
| `approval_sandbox_permissions` | `unix_escalation.rs:74-88` |
| `extract_shell_script` | `unix_escalation.rs:1087-1110` |
| `join_program_and_argv` | `unix_escalation.rs:1147-1151` |
| `map_exec_result` | `unix_escalation.rs:1112-1139` |
| `evaluate_intercepted_exec_policy` | `unix_escalation.rs:754-802` |
| `shell_request_escalation_execution` | `unix_escalation.rs:368-395` |
| `skill_escalation_execution` | `unix_escalation.rs:397-406` |
| `CoreShellCommandExecutor::prepare_escalated_exec` | `unix_escalation.rs:931-1006` |

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `pretty_assertions::assert_eq` | 更好的测试失败输出 |
| `codex_execpolicy` | 策略解析和评估 |
| `codex_protocol` | 权限和策略类型 |
| `codex_shell_escalation` | 升级执行类型 |
| `codex_utils_absolute_path` | 绝对路径处理 |

---

## 依赖与外部交互

### 测试组织方式

```rust
#[cfg(test)]
#[path = "unix_escalation_tests.rs"]
mod tests;
```

这种组织方式：
- 保持测试代码与实现代码分离
- 允许测试访问模块私有成员
- 通过 `super::` 访问被测函数

### 条件编译

```rust
#[cfg(target_os = "macos")]
#[tokio::test]
async fn prepare_escalated_exec_...() { ... }
```

macOS 特定测试只在 macOS 平台编译和运行。

---

## 风险、边界与改进建议

### 测试覆盖分析

| 功能 | 覆盖状态 | 备注 |
|------|---------|------|
| 策略拒绝逻辑 | ✅ 完整 | 所有三种 DecisionSource 都有测试 |
| 沙箱权限降级 | ✅ 完整 | 三种权限级别的组合 |
| 命令解析 | ⚠️ 部分 | 只覆盖 `-c`/`-lc`，未覆盖其他 flag |
| 策略评估 | ✅ 完整 | wrapper 解析开关、host_executable、预批准 |
| macOS Seatbelt | ⚠️ 平台限制 | 仅在 macOS 运行，CI 可能跳过 |
| 超时处理 | ❌ 缺失 | Stopwatch 交互无测试 |
| Skill 查找 | ❌ 缺失 | `find_skill` 无直接测试 |
| 用户提示 | ❌ 缺失 | `prompt` 方法无直接测试 |

### 改进建议

1. **增加负面测试**
   - 测试畸形命令输入的处理
   - 测试策略解析失败场景

2. **增加集成测试**
   - 与 `EscalateServer` 的端到端测试
   - 与 Skill 系统的集成测试

3. **改进可维护性**
   - 使用参数化测试（如 `rstest`）减少重复代码
   - 提取公共的测试夹具（fixtures）

4. **平台覆盖**
   - 考虑使用 mock 测试 macOS 特定逻辑在非 macOS 平台运行
   - 添加 Linux Seatbelt/Landlock 的类似测试

5. **性能测试**
   - 策略评估的性能基准测试
   - 大规模规则集的匹配性能
