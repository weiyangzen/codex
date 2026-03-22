# apply_patch.rs 深度研究文档

## 场景与职责

`apply_patch.rs` 是 Codex CLI 的**代码补丁应用协调模块**，负责将 LLM 生成的代码修改（patch）安全地应用到文件系统。该模块在沙箱安全策略和用户审批流程之间起到桥梁作用。

### 核心职责
1. **安全评估**：评估补丁操作是否符合当前安全策略
2. **审批协调**：决定是否需要用户显式审批
3. **执行委托**：将实际补丁应用委托给沙箱化的执行环境
4. **协议转换**：在内部补丁格式和协议消息格式之间转换

---

## 功能点目的

### 1. 补丁应用结果类型

```rust
pub(crate) enum InternalApplyPatchInvocation {
    /// 用户已显式批准，直接返回结果（无沙箱）
    Output(Result<String, FunctionCallError>),

    /// 需要委托给 exec 执行（自动批准或需要审批）
    DelegateToExec(ApplyPatchExec),
}
```

### 2. 执行参数结构

```rust
#[derive(Debug)]
pub(crate) struct ApplyPatchExec {
    pub(crate) action: ApplyPatchAction,           // 补丁操作
    pub(crate) auto_approved: bool,                // 是否自动批准
    pub(crate) exec_approval_requirement: ExecApprovalRequirement,  // 审批要求
}
```

### 3. 安全评估流程

```
┌─────────────────────────────────────────────────────────────┐
│                     apply_patch()                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              assess_patch_safety()                    │   │
│  │                                                      │   │
│  │  1. 空补丁检查 ──▶ Reject("empty patch")              │   │
│  │                                                      │   │
│  │  2. 策略检查                                         │   │
│  │     - UnlessTrusted ──▶ AskUser                      │   │
│  │                                                      │   │
│  │  3. 路径约束检查                                      │   │
│  │     - 写入路径是否在允许范围内？                      │   │
│  │                                                      │   │
│  │  4. 沙箱可用性检查                                    │   │
│  │     - 有沙箱 ──▶ AutoApprove(sandbox_type)           │   │
│  │     - 无沙箱 ──▶ AskUser 或 Reject                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                   │
│          ┌───────────────┼───────────────┐                   │
│          ▼               ▼               ▼                   │
│    AutoApprove      AskUser          Reject                  │
│          │               │               │                   │
│          ▼               ▼               ▼                   │
│  DelegateToExec   DelegateToExec      Output(Err)            │
│  (auto_approved)  (needs approval)                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 具体技术实现

### 核心函数：apply_patch

```rust
pub(crate) async fn apply_patch(
    turn_context: &TurnContext,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    action: ApplyPatchAction,
) -> InternalApplyPatchInvocation {
    // 调用安全评估模块
    match assess_patch_safety(
        &action,
        turn_context.approval_policy.value(),      // 用户审批策略
        turn_context.sandbox_policy.get(),          // 沙箱策略
        file_system_sandbox_policy,                 // 文件系统沙箱策略
        &turn_context.cwd,                          // 当前工作目录
        turn_context.windows_sandbox_level,         // Windows 沙箱级别
    ) {
        SafetyCheck::AutoApprove { user_explicitly_approved, .. } => {
            InternalApplyPatchInvocation::DelegateToExec(ApplyPatchExec {
                action,
                auto_approved: !user_explicitly_approved,
                exec_approval_requirement: ExecApprovalRequirement::Skip { ... },
            })
        }
        SafetyCheck::AskUser => {
            InternalApplyPatchInvocation::DelegateToExec(ApplyPatchExec {
                action,
                auto_approved: false,
                exec_approval_requirement: ExecApprovalRequirement::NeedsApproval { ... },
            })
        }
        SafetyCheck::Reject { reason } => {
            InternalApplyPatchInvocation::Output(Err(
                FunctionCallError::RespondToModel(format!("patch rejected: {reason}"))
            ))
        }
    }
}
```

### 安全评估关键逻辑（safety.rs）

```rust
pub fn assess_patch_safety(
    action: &ApplyPatchAction,
    policy: AskForApproval,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    cwd: &Path,
    windows_sandbox_level: WindowsSandboxLevel,
) -> SafetyCheck {
    // 空补丁检查
    if action.is_empty() {
        return SafetyCheck::Reject { reason: "empty patch".to_string() };
    }

    // UnlessTrusted 策略直接询问用户
    if matches!(policy, AskForApproval::UnlessTrusted) {
        return SafetyCheck::AskUser;
    }

    // 检查写入路径是否在允许范围内
    let constrained = is_write_patch_constrained_to_writable_paths(
        action, file_system_sandbox_policy, cwd
    );

    if constrained || matches!(policy, AskForApproval::OnFailure) {
        // DangerFullAccess 策略：无沙箱
        if matches!(sandbox_policy, SandboxPolicy::DangerFullAccess | SandboxPolicy::ExternalSandbox { .. }) {
            return SafetyCheck::AutoApprove { sandbox_type: SandboxType::None, user_explicitly_approved: false };
        }

        // 检查平台沙箱可用性
        match get_platform_sandbox(windows_sandbox_level != WindowsSandboxLevel::Disabled) {
            Some(sandbox_type) => SafetyCheck::AutoApprove { sandbox_type, user_explicitly_approved: false },
            None => {
                // 无沙箱可用，根据策略决定
                if rejects_sandbox_approval {
                    SafetyCheck::Reject { reason: "writing outside of the project".to_string() }
                } else {
                    SafetyCheck::AskUser
                }
            }
        }
    }
    // ...
}
```

### 协议转换函数

```rust
pub(crate) fn convert_apply_patch_to_protocol(
    action: &ApplyPatchAction,
) -> HashMap<PathBuf, FileChange> {
    let changes = action.changes();
    let mut result = HashMap::with_capacity(changes.len());
    
    for (path, change) in changes {
        let protocol_change = match change {
            ApplyPatchFileChange::Add { content } => FileChange::Add { content },
            ApplyPatchFileChange::Delete { content } => FileChange::Delete { content },
            ApplyPatchFileChange::Update { unified_diff, move_path, .. } => {
                FileChange::Update { unified_diff, move_path }
            }
        };
        result.insert(path.clone(), protocol_change);
    }
    result
}
```

### 路径约束检查

```rust
fn is_write_patch_constrained_to_writable_paths(
    action: &ApplyPatchAction,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    cwd: &Path,
) -> bool {
    // 归一化路径（处理 . 和 ..）
    fn normalize(path: &Path) -> Option<PathBuf> {
        let mut out = PathBuf::new();
        for comp in path.components() {
            match comp {
                Component::ParentDir => { out.pop(); }
                Component::CurDir => {}
                other => out.push(other.as_os_str()),
            }
        }
        Some(out)
    }

    let is_path_writable = |p: &PathBuf| {
        let abs = resolve_path(cwd, p);
        let abs = normalize(&abs)?;
        file_system_sandbox_policy.can_write_path_with_cwd(&abs, cwd)
    };

    // 检查所有变更路径
    for (path, change) in action.changes() {
        match change {
            ApplyPatchFileChange::Add { .. } | ApplyPatchFileChange::Delete { .. } => {
                if !is_path_writable(path) { return false; }
            }
            ApplyPatchFileChange::Update { move_path, .. } => {
                if !is_path_writable(path) { return false; }
                if let Some(dest) = move_path && !is_path_writable(dest) {
                    return false;
                }
            }
        }
    }
    true
}
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 说明 |
|-----|------|
| `codex-rs/core/src/apply_patch.rs` | 主实现文件（108行） |
| `codex-rs/core/src/apply_patch_tests.rs` | 单元测试（21行） |
| `codex-rs/core/src/safety.rs` | 安全评估实现 |

### 调用方（上游）
- `codex-rs/core/src/tools/` - 工具调用处理
  - 当 LLM 调用 `apply_patch` 工具时触发

### 被调用方（下游）
- `codex-rs/core/src/safety.rs`
  - `assess_patch_safety()` - 安全评估核心
  - `is_write_patch_constrained_to_writable_paths()` - 路径约束检查
  - `get_platform_sandbox()` - 平台沙箱检测
- `codex_apply_patch` crate
  - `ApplyPatchAction` - 补丁操作结构
  - `ApplyPatchFileChange` - 文件变更枚举
- `codex-rs/core/src/tools/sandboxing.rs`
  - `ExecApprovalRequirement` - 执行审批要求

### 相关协议类型
- `codex_protocol::protocol::FileChange` - 协议层文件变更
- `codex_protocol::protocol::FileSystemSandboxPolicy` - 文件系统沙箱策略
- `codex_protocol::config_types::SandboxPolicy` - 沙箱策略
- `codex_protocol::config_types::AskForApproval` - 审批策略

---

## 依赖与外部交互

### 外部 Crate 依赖
```rust
use codex_apply_patch::{ApplyPatchAction, ApplyPatchFileChange};
```

### 内部模块依赖
```rust
use crate::codex::TurnContext;
use crate::function_tool::FunctionCallError;
use crate::protocol::{FileChange, FileSystemSandboxPolicy};
use crate::safety::{SafetyCheck, assess_patch_safety};
use crate::tools::sandboxing::ExecApprovalRequirement;
```

### 与沙箱系统的交互
```
apply_patch.rs
    │
    ├──▶ safety.rs (评估安全)
    │       ├──▶ 检查路径约束
    │       └──▶ 检查沙箱可用性
    │
    └──▶ tools/sandboxing.rs (执行委托)
            └──▶ ExecApprovalRequirement
```

---

## 风险、边界与改进建议

### 已知风险

1. **硬链接攻击**
   - 注释中明确提到：即使路径在允许范围内，也可能是指向外部文件的硬链接
   - 当前缓解措施：在可用时使用沙箱执行
   - **建议**：添加硬链接检测（使用 `std::fs::metadata()` 比较 inode）

2. **路径遍历攻击**
   - `normalize()` 函数处理 `..` 但不解析符号链接
   - **建议**：添加符号链接解析和验证

3. **竞态条件**
   - 路径检查和应用之间有时间窗口
   - **建议**：使用文件描述符级别的操作（`O_NOFOLLOW`）

4. **Windows 沙箱依赖**
   - Windows 平台沙箱需要显式启用
   - **建议**：默认启用或添加更明显的警告

### 边界情况

| 场景 | 当前行为 |
|-----|---------|
| 空补丁 | Reject("empty patch") |
| UnlessTrusted 策略 | 总是 AskUser |
| DangerFullAccess 策略 | AutoApprove(无沙箱) |
| 无沙箱可用 + 拒绝策略 | Reject |
| 无沙箱可用 + 允许策略 | AskUser |
| 文件移动（rename） | 检查源和目标路径 |

### 改进建议

1. **增强路径验证**
   ```rust
   // 添加符号链接检测
   fn is_symlink_outside_sandbox(path: &Path, sandbox_root: &Path) -> bool {
       if let Ok(canonical) = std::fs::canonicalize(path) {
           !canonical.starts_with(sandbox_root)
       } else {
           false
       }
   }
   ```

2. **原子性检查与应用**
   ```rust
   // 使用文件锁或事务
   let _lock = FileLock::new(&path)?;
   if is_path_writable(&path) {
       apply_patch(&path)?;
   }
   ```

3. **更好的错误信息**
   ```rust
   SafetyCheck::Reject { 
       reason: format!(
           "patch rejected: path '{}' is outside allowed directories: {:?}",
           path, allowed_dirs
       )
   }
   ```

4. **测试覆盖增强**
   - 添加硬链接场景测试
   - 添加符号链接场景测试
   - 添加并发修改场景测试
   - 添加大文件补丁测试
