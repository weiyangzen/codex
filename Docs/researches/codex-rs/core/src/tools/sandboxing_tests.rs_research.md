# sandboxing_tests.rs 深度研究文档

## 场景与职责

`sandboxing_tests.rs` 是 `sandboxing.rs` 的单元测试模块，主要验证：

1. **执行审批要求计算**：验证不同策略组合下的审批要求
2. **沙箱覆盖决策**：验证首次尝试跳过沙箱的条件
3. **Granular 配置处理**：验证 Granular 审批配置的边界情况

这些测试确保沙箱审批策略在各种配置组合下的正确性。

## 功能点目的

### 测试覆盖范围

1. **ExternalSandbox 策略**
   - `external_sandbox_skips_exec_approval_on_request`: 外部沙箱在 OnRequest 策略下跳过审批

2. **Restricted 沙箱策略**
   - `restricted_sandbox_requires_exec_approval_on_request`: 受限沙箱需要审批

3. **Granular 配置**
   - `default_exec_approval_requirement_rejects_sandbox_prompt_when_granular_disables_it`: 禁用沙箱审批时返回 Forbidden
   - `default_exec_approval_requirement_keeps_prompt_when_granular_allows_sandbox_approval`: 启用沙箱审批时返回 NeedsApproval

4. **沙箱覆盖**
   - `additional_permissions_allow_bypass_sandbox_first_attempt_when_execpolicy_skips`: 额外权限 + Skip 策略跳过沙箱
   - `guardian_bypasses_sandbox_for_explicit_escalation_on_first_attempt`: RequireEscalated 权限跳过沙箱

## 具体技术实现

### 测试结构

```rust
// 使用 pretty_assertions 获得更好的错误输出
use pretty_assertions::assert_eq;
```

### 核心测试用例

#### 1. ExternalSandbox 跳过审批

```rust
#[test]
fn external_sandbox_skips_exec_approval_on_request() {
    let sandbox_policy = SandboxPolicy::ExternalSandbox {
        network_access: NetworkAccess::Restricted,
    };
    assert_eq!(
        default_exec_approval_requirement(
            AskForApproval::OnRequest,
            &FileSystemSandboxPolicy::from(&sandbox_policy),
        ),
        ExecApprovalRequirement::Skip {
            bypass_sandbox: false,
            proposed_execpolicy_amendment: None,
        }
    );
}
```

**逻辑**：
- `ExternalSandbox` 使用外部隔离机制
- 不需要 Codex 的额外审批
- 返回 `Skip` 要求

#### 2. Restricted 沙箱需要审批

```rust
#[test]
fn restricted_sandbox_requires_exec_approval_on_request() {
    let sandbox_policy = SandboxPolicy::new_read_only_policy();
    assert_eq!(
        default_exec_approval_requirement(
            AskForApproval::OnRequest,
            &FileSystemSandboxPolicy::from(&sandbox_policy)
        ),
        ExecApprovalRequirement::NeedsApproval {
            reason: None,
            proposed_execpolicy_amendment: None,
        }
    );
}
```

**逻辑**：
- `ReadOnly` 策略是受限沙箱
- 在 `OnRequest` 策略下需要用户审批
- 返回 `NeedsApproval` 要求

#### 3. Granular 配置 - 禁用沙箱审批

```rust
#[test]
fn default_exec_approval_requirement_rejects_sandbox_prompt_when_granular_disables_it() {
    let policy = AskForApproval::Granular(GranularApprovalConfig {
        sandbox_approval: false,  // 禁用沙箱审批
        rules: true,
        skill_approval: true,
        request_permissions: true,
        mcp_elicitations: true,
    });

    let sandbox_policy = SandboxPolicy::new_read_only_policy();
    let requirement = default_exec_approval_requirement(policy, &FileSystemSandboxPolicy::from(&sandbox_policy));

    assert_eq!(
        requirement,
        ExecApprovalRequirement::Forbidden {
            reason: "approval policy disallowed sandbox approval prompt".to_string(),
        }
    );
}
```

**逻辑**：
- `GranularApprovalConfig.sandbox_approval = false`
- 受限沙箱需要审批，但策略禁止提示
- 返回 `Forbidden`

#### 4. Granular 配置 - 启用沙箱审批

```rust
#[test]
fn default_exec_approval_requirement_keeps_prompt_when_granular_allows_sandbox_approval() {
    let policy = AskForApproval::Granular(GranularApprovalConfig {
        sandbox_approval: true,   // 启用沙箱审批
        rules: false,
        skill_approval: true,
        request_permissions: true,
        mcp_elicitations: false,
    });

    let sandbox_policy = SandboxPolicy::new_read_only_policy();
    let requirement = default_exec_approval_requirement(policy, &FileSystemSandboxPolicy::from(&sandbox_policy));

    assert_eq!(
        requirement,
        ExecApprovalRequirement::NeedsApproval {
            reason: None,
            proposed_execpolicy_amendment: None,
        }
    );
}
```

**逻辑**：
- `GranularApprovalConfig.sandbox_approval = true`
- 允许沙箱审批提示
- 返回 `NeedsApproval`

#### 5. 沙箱覆盖 - 额外权限

```rust
#[test]
fn additional_permissions_allow_bypass_sandbox_first_attempt_when_execpolicy_skips() {
    assert_eq!(
        sandbox_override_for_first_attempt(
            SandboxPermissions::WithAdditionalPermissions,
            &ExecApprovalRequirement::Skip {
                bypass_sandbox: true,
                proposed_execpolicy_amendment: None,
            },
        ),
        SandboxOverride::BypassSandboxFirstAttempt
    );
}
```

**逻辑**：
- `SandboxPermissions::WithAdditionalPermissions` 请求额外权限
- `ExecPolicy` 允许跳过沙箱 (`bypass_sandbox: true`)
- 首次尝试跳过沙箱

#### 6. 沙箱覆盖 - Guardian 显式升级

```rust
#[test]
fn guardian_bypasses_sandbox_for_explicit_escalation_on_first_attempt() {
    assert_eq!(
        sandbox_override_for_first_attempt(
            SandboxPermissions::RequireEscalated,  // 显式请求升级
            &ExecApprovalRequirement::Skip {
                bypass_sandbox: false,
                proposed_execpolicy_amendment: None,
            },
        ),
        SandboxOverride::BypassSandboxFirstAttempt
    );
}
```

**逻辑**：
- `SandboxPermissions::RequireEscalated` 显式请求无沙箱
- 即使 `bypass_sandbox: false`
- 首次尝试跳过沙箱

### 测试流程图

```
┌─────────────────────────────────────────────────────────────────┐
│     external_sandbox_skips_exec_approval_on_request              │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建 ExternalSandbox 策略                                     │
│ 2. 转换为 FileSystemSandboxPolicy                               │
│ 3. 调用 default_exec_approval_requirement(OnRequest, policy)    │
│ 4. 验证返回 Skip { bypass_sandbox: false }                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│     restricted_sandbox_requires_exec_approval_on_request         │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建 ReadOnly 策略（受限沙箱）                               │
│ 2. 调用 default_exec_approval_requirement(OnRequest, policy)    │
│ 3. 验证返回 NeedsApproval { reason: None }                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Granular 配置测试（禁用 vs 启用 sandbox_approval）              │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建 GranularApprovalConfig（sandbox_approval: false/true）  │
│ 2. 创建 ReadOnly 策略                                            │
│ 3. 调用 default_exec_approval_requirement(Granular, policy)     │
│ 4. 验证：                                                        │
│    ├─ false → Forbidden                                          │
│    └─ true  → NeedsApproval                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│     沙箱覆盖测试（额外权限 vs 显式升级）                         │
├─────────────────────────────────────────────────────────────────┤
│ 1. 创建 SandboxPermissions（WithAdditionalPermissions/RequireEscalated）│
│ 2. 创建 ExecApprovalRequirement                                  │
│ 3. 调用 sandbox_override_for_first_attempt()                    │
│ 4. 验证返回 BypassSandboxFirstAttempt                           │
└─────────────────────────────────────────────────────────────────┘
```

## 关键代码路径与文件引用

### 被测试代码

| 被测试项 | 定义位置 |
|----------|----------|
| `default_exec_approval_requirement()` | `sandboxing.rs:167-203` |
| `sandbox_override_for_first_attempt()` | `sandboxing.rs:211-230` |

### 关键被测试代码片段

```rust
// sandboxing.rs:167-203
pub(crate) fn default_exec_approval_requirement(
    policy: AskForApproval,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
) -> ExecApprovalRequirement {
    let needs_approval = match policy {
        AskForApproval::Never | AskForApproval::OnFailure => false,
        AskForApproval::OnRequest | AskForApproval::Granular(_) => {
            matches!(
                file_system_sandbox_policy.kind,
                FileSystemSandboxKind::Restricted
            )
        }
        AskForApproval::UnlessTrusted => true,
    };

    if needs_approval
        && matches!(
            policy,
            AskForApproval::Granular(granular_config)
                if !granular_config.allows_sandbox_approval()
        )
    {
        ExecApprovalRequirement::Forbidden { ... }
    } else if needs_approval {
        ExecApprovalRequirement::NeedsApproval { ... }
    } else {
        ExecApprovalRequirement::Skip { ... }
    }
}
```

```rust
// sandboxing.rs:211-230
pub(crate) fn sandbox_override_for_first_attempt(
    sandbox_permissions: SandboxPermissions,
    exec_approval_requirement: &ExecApprovalRequirement,
) -> SandboxOverride {
    if sandbox_permissions.requires_escalated_permissions()
        || matches!(
            exec_approval_requirement,
            ExecApprovalRequirement::Skip {
                bypass_sandbox: true,
                ..
            }
        )
    {
        SandboxOverride::BypassSandboxFirstAttempt
    } else {
        SandboxOverride::NoOverride
    }
}
```

## 依赖与外部交互

### 测试依赖

| 依赖 | 用途 |
|------|------|
| `super::*` | 被测试的 sandboxing 模块 |
| `crate::sandboxing::SandboxPermissions` | 沙箱权限类型 |
| `codex_protocol::protocol::{GranularApprovalConfig, AskForApproval, NetworkAccess}` | 协议类型 |
| `pretty_assertions::assert_eq` | 更好的断言输出 |

### 测试模块声明

```rust
// sandboxing.rs:365-367
#[cfg(test)]
#[path = "sandboxing_tests.rs"]
mod tests;
```

## 风险、边界与改进建议

### 当前测试的局限性

1. **未测试所有策略组合**
   - 仅测试了 `OnRequest` 和部分 `Granular`
   - 未测试 `Never`、`OnFailure`、`UnlessTrusted`

2. **未测试 `SandboxablePreference`**
   - 未测试 `Auto`、`Require`、`Forbid` 的影响

3. **未测试 `ToolRuntime` trait**
   - 仅测试了辅助函数
   - 未测试 trait 的默认实现

4. **未测试 `with_cached_approval`**
   - 这是核心功能，但无单元测试
   - 可能通过集成测试覆盖

5. **未测试 `ApprovalStore`**
   - 序列化和反序列化逻辑未测试
   - 边界情况（空键、大键）未测试

### 边界情况未覆盖

1. **混合策略**
   ```rust
   // 未测试：Granular 配置部分启用
   GranularApprovalConfig {
       sandbox_approval: true,
       rules: false,
       // ...
   }
   ```

2. **Unrestricted 沙箱**
   ```rust
   // 未测试：无限制沙箱的策略
   FileSystemSandboxKind::Unrestricted
   ```

3. **网络策略交互**
   ```rust
   // 未测试：NetworkSandboxPolicy 对审批要求的影响
   ```

4. **ExecPolicyAmendment**
   ```rust
   // 未测试：proposed_execpolicy_amendment 的处理
   ```

### 改进建议

1. **添加完整策略矩阵测试**
   ```rust
   #[test_case(AskForApproval::Never, FileSystemSandboxKind::Restricted, ExecApprovalRequirement::Skip)]
   #[test_case(AskForApproval::OnFailure, FileSystemSandboxKind::Restricted, ExecApprovalRequirement::Skip)]
   #[test_case(AskForApproval::UnlessTrusted, FileSystemSandboxKind::Unrestricted, ExecApprovalRequirement::NeedsApproval)]
   // ...
   fn exec_approval_requirement_matrix(policy, kind, expected) { ... }
   ```

2. **添加 `with_cached_approval` 测试**
   ```rust
   #[tokio::test]
   async fn cached_approval_skips_when_all_keys_approved() {
       // 测试缓存命中场景
   }

   #[tokio::test]
   async fn cached_approval_fetches_when_partial_approved() {
       // 测试部分批准场景
   }
   ```

3. **添加 `ApprovalStore` 测试**
   ```rust
   #[test]
   fn approval_store_roundtrips_complex_keys() {
       // 测试复杂键的序列化
   }
   ```

4. **添加 trait 默认实现测试
   ```rust
   struct MockApprovable;
   impl Approvable<()> for MockApprovable { ... }

   #[test]
   fn approvable_default_should_bypass_approval() {
       // 测试默认实现
   }
   ```

5. **使用参数化测试**
   ```rust
   // 使用 test-case crate
   use test_case::test_case;

   #[test_case(SandboxPermissions::UseDefault, false)]
   #[test_case(SandboxPermissions::WithAdditionalPermissions, true)]
   #[test_case(SandboxPermissions::RequireEscalated, true)]
   fn sandbox_permissions_requires_escalated(perm, expected) { ... }
   ```

6. **添加文档测试**
   ```rust
   /// ```
   /// use codex_core::tools::sandboxing::default_exec_approval_requirement;
   /// // 示例用法
   /// ```
   ```

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/sandboxing.rs` | 被测试的主模块 |
| `codex-rs/core/src/tools/orchestrator.rs` | 使用这些函数编排执行 |
| `codex-rs/core/src/protocol.rs` | `AskForApproval`、`SandboxPolicy` 定义 |
| `codex-rs/core/src/sandboxing/mod.rs` | `SandboxPermissions` 定义 |
