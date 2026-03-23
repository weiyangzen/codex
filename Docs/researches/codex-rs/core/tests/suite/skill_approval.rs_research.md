# skill_approval.rs 研究文档

## 场景与职责

`skill_approval.rs` 是 Codex Core 的集成测试套件，专注于验证 **Skill（技能）执行审批** 机制。该测试文件确保当 Agent 执行 Skill 脚本时，系统能够正确评估权限、触发审批流程，并在用户批准后应用适当的沙箱策略。

核心测试场景包括：
1. **Skill 执行审批** - 验证 Skill 脚本执行前的审批提示
2. **权限继承** - 验证无权限 Skill 继承回合沙箱策略
3. **显式权限验证** - 验证声明权限的 Skill 正确限制文件系统访问
4. **审批策略组合** - 验证不同审批策略（GranularApprovalConfig）的行为
5. **会话级审批缓存** - 验证 `ApprovedForSession` 决策的缓存行为

## 功能点目的

### 1. Skill 权限模型

Skill 可以通过 `agents/openai.yaml` 声明权限：

```yaml
permissions:
  file_system:
    read:
      - "./data"
    write:
      - "./output"
```

### 2. 审批决策类型

```rust
pub enum ReviewDecision {
    Approved,           // 单次批准
    ApprovedForSession, // 会话级批准（缓存）
    Denied,             // 拒绝
    Abort,              // 中止
}
```

### 3. 细粒度审批配置

```rust
pub struct GranularApprovalConfig {
    pub sandbox_approval: bool,      // 沙箱审批
    pub rules: bool,                 // 规则审批
    pub skill_approval: bool,        // Skill 审批
    pub request_permissions: bool,   // 权限请求
    pub mcp_elicitations: bool,      // MCP 请求
}
```

### 4. 执行审批请求事件

```rust
pub struct ExecApprovalRequestEvent {
    pub call_id: String,
    pub command: Vec<String>,
    pub available_decisions: Option<Vec<ReviewDecision>>,
    pub additional_permissions: Option<PermissionProfile>,
    pub skill_metadata: Option<ExecApprovalRequestSkillMetadata>,
}
```

## 具体技术实现

### 关键测试流程

#### 1. Skill 创建辅助函数

```rust
fn write_skill_with_shell_script(home: &Path, name: &str, script_name: &str) -> Result<PathBuf> {
    let skill_dir = home.join("skills").join(name);
    let scripts_dir = skill_dir.join("scripts");
    fs::create_dir_all(&scripts_dir)?;
    
    // 写入 SKILL.md
    fs::write(
        skill_dir.join("SKILL.md"),
        format!("---\nname: {name}\ndescription: {name} skill\n---\n"),
    )?;
    
    // 写入脚本并设置可执行权限
    let script_path = scripts_dir.join(script_name);
    fs::write(&script_path, script_contents)?;
    #[cfg(unix)]
    {
        let mut permissions = fs::metadata(&script_path)?.permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&script_path, permissions)?;
    }
    Ok(script_path)
}
```

#### 2. Skill 元数据写入

```rust
fn write_skill_metadata(home: &Path, name: &str, contents: &str) -> Result<()> {
    let metadata_dir = home.join("skills").join(name).join("agents");
    fs::create_dir_all(&metadata_dir)?;
    fs::write(metadata_dir.join("openai.yaml"), contents)?;
    Ok(())
}
```

#### 3. Zsh Fork 测试构建

```rust
let test = build_zsh_fork_test(
    &server,
    runtime,
    AskForApproval::OnRequest,
    SandboxPolicy::new_workspace_write_policy(),
    |home| {
        write_skill_with_shell_script(home, "mbolin-test-skill", "hello-mbolin.sh").unwrap();
        write_skill_metadata(
            home,
            "mbolin-test-skill",
            r#"
permissions:
  file_system:
    read:
      - "./data"
    write:
      - "./output"
"#,
        ).unwrap();
    },
).await?;
```

#### 4. 审批等待和响应

```rust
async fn wait_for_exec_approval_request(test: &TestCodex) -> Option<ExecApprovalRequestEvent> {
    wait_for_event_match(test.codex.as_ref(), |event| match event {
        EventMsg::ExecApprovalRequest(request) => Some(Some(request.clone())),
        EventMsg::TurnComplete(_) => Some(None),
        _ => None,
    }).await
}

// 提交审批决策
test.codex
    .submit(Op::ExecApproval {
        id: approval.effective_approval_id(),
        turn_id: None,
        decision: ReviewDecision::Denied,
    })
    .await?;
```

### 关键数据结构

#### PermissionProfile

```rust
pub struct PermissionProfile {
    pub file_system: Option<FileSystemPermissions>,
    pub network: Option<NetworkPermissions>,
}

pub struct FileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}
```

#### SandboxPolicy

```rust
pub enum SandboxPolicy {
    DangerFullAccess,  // 完全访问
    WorkspaceWrite {   // 工作区写入
        writable_roots: Vec<PathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
    // ...
}
```

### 审批验证断言

```rust
// 验证审批请求内容
assert_eq!(approval.call_id, tool_call_id);
assert_eq!(approval.command, vec![script_path_str.clone()]);
assert_eq!(
    approval.available_decisions,
    Some(vec![
        ReviewDecision::Approved,
        ReviewDecision::ApprovedForSession,
        ReviewDecision::Abort,
    ])
);

// 验证附加权限
assert_eq!(
    approval.additional_permissions,
    Some(PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec![absolute_path(&test.codex_home_path().join("skills/mbolin-test-skill/data"))]),
            write: Some(vec![absolute_path(&test.codex_home_path().join("skills/mbolin-test-skill/output"))]),
        }),
        ..Default::default()
    })
);

// 验证 Skill 元数据
assert_eq!(
    approval.skill_metadata,
    Some(ExecApprovalRequestSkillMetadata {
        path_to_skills_md: test.codex_home_path().join("skills/mbolin-test-skill/agents/openai.yaml"),
    })
);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/skill_approval.rs` - 本测试文件
- `codex-rs/core/tests/common/test_codex.rs` - 测试基础设施
- `codex-rs/core/tests/common/zsh_fork.rs` - Zsh fork 测试辅助

### 被测试的源代码
- `codex-rs/core/src/skills/mod.rs` - Skill 模块
- `codex-rs/core/src/skills/model.rs` - Skill 模型定义
- `codex-rs/core/src/skills/manager.rs` - Skill 管理器
- `codex-rs/core/src/guardian/mod.rs` - 审批系统
- `codex-rs/core/src/exec_policy.rs` - 执行策略
- `codex-rs/core/src/tools/handlers/shell.rs` - Shell 工具处理器
- `codex-rs/core/src/tools/runtimes/shell/zsh_fork_backend.rs` - Zsh fork 后端

### 核心测试用例

| 测试用例 | 描述 |
|---------|------|
| `shell_zsh_fork_prompts_for_skill_script_execution` | 验证 Skill 脚本执行前触发审批 |
| `shell_zsh_fork_skill_script_reject_policy_with_sandbox_approval_false_still_prompts` | 验证 sandbox_approval=false 仍触发审批 |
| `shell_zsh_fork_skill_script_reject_policy_with_sandbox_approval_true_still_prompts` | 验证 sandbox_approval=true 仍触发审批 |
| `shell_zsh_fork_skill_script_reject_policy_with_skill_approval_true_skips_prompt` | 验证 skill_approval=false 跳过审批 |
| `shell_zsh_fork_skill_without_permissions_inherits_turn_sandbox` | 验证无权限 Skill 继承回合沙箱 |
| `shell_zsh_fork_skill_with_empty_permissions_inherits_turn_sandbox` | 验证空权限 Skill 继承回合沙箱 |
| `shell_zsh_fork_skill_session_approval_enforces_skill_permissions` | 验证会话审批强制执行 Skill 权限 |
| `shell_zsh_fork_still_enforces_workspace_write_sandbox` | 验证 WorkspaceWrite 沙箱仍然生效 |

### 审批流程代码路径

1. **Skill 检测** - `skills::invocation_utils::maybe_emit_implicit_skill_invocation`
2. **权限计算** - `tools::handlers::apply_granted_turn_permissions`
3. **审批要求创建** - `exec_policy::create_exec_approval_requirement_for_command`
4. **审批请求发送** - `guardian::send_exec_approval_request`
5. **审批响应处理** - `guardian::handle_exec_approval_response`

## 依赖与外部交互

### 测试依赖

1. **core_test_support**
   - `build_zsh_fork_test` - 构建 Zsh fork 测试环境
   - `zsh_fork_runtime` - 获取 Zsh fork 运行时
   - `restrictive_workspace_write_policy` - 限制性工作区写入策略
   - `mount_function_call_agent_response` - 挂载函数调用响应

2. **codex_protocol**
   - `ExecApprovalRequestEvent` - 执行审批请求事件
   - `ExecApprovalRequestSkillMetadata` - Skill 元数据
   - `GranularApprovalConfig` - 细粒度审批配置
   - `ReviewDecision` - 审批决策枚举

3. **codex_utils_absolute_path**
   - `AbsolutePathBuf` - 绝对路径缓冲区

### 外部命令依赖

测试执行以下外部命令：
- Skill 脚本（通过 `write_skill_with_shell_script` 创建）
- `printf` - 格式化输出
- `cat` - 文件读取

### 文件系统布局

测试创建的 Skill 目录结构：
```
<CODEX_HOME>/
  skills/
    <skill-name>/
      SKILL.md              # Skill 定义
      scripts/
        <script-name>       # 可执行脚本
      agents/
        openai.yaml         # 权限元数据
```

### 协议事件

测试涉及的事件：
- `EventMsg::ExecCommandBegin` - 命令开始
- `EventMsg::ExecCommandEnd` - 命令结束
- `EventMsg::ExecApprovalRequest` - 执行审批请求
- `EventMsg::TurnComplete` - 回合完成

## 风险、边界与改进建议

### 当前风险

1. **Unix 限制** - 测试标记为 `#!cfg(unix)`，Windows 平台无覆盖
2. **网络依赖** - 使用 `skip_if_no_network!`，无网络时测试被跳过
3. **Zsh 依赖** - 测试依赖 Zsh fork 运行时，非 Zsh 环境无法运行
4. **硬编码路径** - 测试使用硬编码的 Skill 名称和路径

### 边界情况

1. **权限路径解析** - `./data` 等相对路径解析为绝对路径的边界
2. **并发审批** - 多个 Skill 同时请求审批的场景未测试
3. **权限冲突** - Skill 权限与回合沙箱权限冲突的处理
4. **审批超时** - 用户长时间不响应审批请求的行为

### 改进建议

1. **增加 Windows 支持** - 为 Windows 平台添加等效测试
2. **增加并发测试** - 验证多 Skill 并发执行的审批行为
3. **增加权限冲突测试** - 验证 Skill 权限与沙箱权限的交集/并集行为
4. **增加审批超时测试** - 验证审批超时后的默认行为
5. **增加嵌套 Skill 测试** - 验证 Skill 调用其他 Skill 的审批传播
6. **增加权限变更测试** - 验证运行中修改 Skill 权限的行为

### 相关配置项

```rust
config.features.enable(Feature::ZshFork)?;
config.permissions.shell_environment_policy.r#set = ...;
```

### 审批策略矩阵

测试覆盖的审批策略组合：

| sandbox_approval | skill_approval | 行为 |
|-----------------|----------------|------|
| true | true | 触发审批 |
| false | true | 触发审批 |
| true | false | 跳过审批，执行策略检查 |
| OnRequest | - | 触发审批 |

### 安全考虑

1. **路径遍历防护** - 测试验证 Skill 不能访问声明路径之外的文件
2. **权限降级** - 验证无权限 Skill 不会获得额外权限
3. **会话隔离** - 验证 `ApprovedForSession` 不会跨会话传播
