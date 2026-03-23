# apply_patch_tests.rs 深入研究

## 场景与职责

`apply_patch_tests.rs` 是 `apply_patch.rs` 的单元测试模块，通过 `#[path = "apply_patch_tests.rs"]` 在 `apply_patch.rs` 末尾条件编译引入。该测试文件专注于验证 `ApplyPatchRuntime` 的核心行为，特别是审批策略和 Guardian 集成相关的逻辑。

**测试覆盖范围：**
1. **审批策略测试**：验证不同 `AskForApproval` 策略下的沙箱审批行为
2. **Guardian 请求构建测试**：验证 `build_guardian_review_request` 正确构造审批请求

---

## 功能点目的

### 测试 1: `wants_no_sandbox_approval_granular_respects_sandbox_flag`

**目的**：验证 `wants_no_sandbox_approval` 方法在不同审批策略下的行为，特别是 `Granular` 配置中的 `sandbox_approval` 标志。

**测试场景：**
- `AskForApproval::OnRequest` → 应返回 `true`（允许无沙箱审批）
- `Granular { sandbox_approval: false, ... }` → 应返回 `false`（禁止无沙箱审批）
- `Granular { sandbox_approval: true, ... }` → 应返回 `true`（允许无沙箱审批）

**代码逻辑：**
```rust
#[test]
fn wants_no_sandbox_approval_granular_respects_sandbox_flag() {
    let runtime = ApplyPatchRuntime::new();
    assert!(runtime.wants_no_sandbox_approval(AskForApproval::OnRequest));
    assert!(
        !runtime.wants_no_sandbox_approval(AskForApproval::Granular(GranularApprovalConfig {
            sandbox_approval: false,
            rules: true,
            skill_approval: true,
            request_permissions: true,
            mcp_elicitations: true,
        }))
    );
    // ... 类似地测试 sandbox_approval: true 的情况
}
```

**业务意义：**
- 确保细粒度审批配置正确控制无沙箱执行权限
- 防止在 `sandbox_approval: false` 时意外允许无沙箱执行

### 测试 2: `guardian_review_request_includes_patch_context`

**目的**：验证 `build_guardian_review_request` 方法正确构建 `GuardianApprovalRequest::ApplyPatch` 请求，包含所有必要的上下文信息。

**测试场景：**
- 创建临时文件路径
- 构建 `ApplyPatchAction`（添加文件操作）
- 构造 `ApplyPatchRequest`
- 验证生成的 `GuardianApprovalRequest` 包含正确的字段值

**代码逻辑：**
```rust
#[test]
fn guardian_review_request_includes_patch_context() {
    let path = std::env::temp_dir().join("guardian-apply-patch-test.txt");
    let action = ApplyPatchAction::new_add_for_test(&path, "hello".to_string());
    // ... 构建请求 ...
    let guardian_request = ApplyPatchRuntime::build_guardian_review_request(&request, "call-1");
    
    assert_eq!(guardian_request, GuardianApprovalRequest::ApplyPatch {
        id: "call-1".to_string(),
        cwd: expected_cwd,
        files: request.file_paths,
        change_count: 1usize,
        patch: expected_patch,
    });
}
```

**验证要点：**
- `id`: 调用 ID 正确传递
- `cwd`: 工作目录正确
- `files`: 文件路径列表正确
- `change_count`: 变更数量正确（本例为 1）
- `patch`: 补丁内容正确

---

## 具体技术实现

### 测试基础设施

**依赖：**
```rust
use super::*;  // 引入 apply_patch.rs 的所有导出
use codex_protocol::protocol::GranularApprovalConfig;
use pretty_assertions::assert_eq;
use std::collections::HashMap;
```

**测试辅助方法：**
- `ApplyPatchAction::new_add_for_test`: 测试辅助方法，快速创建添加文件的补丁操作

### 测试数据构造

**ApplyPatchRequest 构造示例：**
```rust
let request = ApplyPatchRequest {
    action,  // ApplyPatchAction，包含 cwd 和 patch 内容
    file_paths: vec![AbsolutePathBuf::from_absolute_path(&path).unwrap()],
    changes: HashMap::from([(
        path,
        FileChange::Add {
            content: "hello".to_string(),
        },
    )]),
    exec_approval_requirement: ExecApprovalRequirement::NeedsApproval {
        reason: None,
        proposed_execpolicy_amendment: None,
    },
    sandbox_permissions: SandboxPermissions::UseDefault,
    additional_permissions: None,
    permissions_preapproved: false,
    timeout_ms: None,
    codex_exe: None,
};
```

---

## 关键代码路径与文件引用

### 文件关系

```
codex-rs/core/src/tools/runtimes/apply_patch.rs
├── mod tests (line 218-220)
│   └── #[path = "apply_patch_tests.rs"]
│       └── apply_patch_tests.rs (本文件)
```

### 被测试的方法

| 方法 | 所在文件 | 行号 |
|------|----------|------|
| `ApplyPatchRuntime::new()` | apply_patch.rs | 52-54 |
| `wants_no_sandbox_approval()` | apply_patch.rs | 178-186 |
| `build_guardian_review_request()` | apply_patch.rs | 56-67 |

### 依赖类型

| 类型 | 来源 |
|------|------|
| `ApplyPatchAction` | `codex_apply_patch` crate |
| `GranularApprovalConfig` | `codex_protocol::protocol` |
| `FileChange` | `codex_protocol::protocol` |
| `AbsolutePathBuf` | `codex_utils_absolute_path` |

---

## 依赖与外部交互

### 外部 crate 依赖

1. **`codex_apply_patch`**
   - `ApplyPatchAction`: 补丁操作结构
   - `new_add_for_test()`: 测试辅助方法

2. **`codex_protocol`**
   - `GranularApprovalConfig`: 细粒度审批配置
   - `AskForApproval`: 审批策略枚举
   - `FileChange`: 文件变更类型

3. **`codex_utils_absolute_path`**
   - `AbsolutePathBuf`: 绝对路径类型

4. **`pretty_assertions`**
   - 提供更清晰的测试失败 diff 输出

### 测试环境

- 使用 `std::env::temp_dir()` 创建临时文件路径
- 不实际创建文件（仅路径操作）
- 纯单元测试，无外部服务依赖

---

## 风险、边界与改进建议

### 当前测试覆盖缺口

| 缺口 | 风险 | 建议 |
|------|------|------|
| 无 `start_approval_async` 测试 | 审批流程逻辑未验证 | 添加 mock session 测试审批流程 |
| 无 `run` 方法测试 | 实际执行逻辑未验证 | 需要集成测试或 mock `execute_env` |
| 无 `build_command_spec` 测试 | 命令构建逻辑未验证 | 测试不同平台下的命令构建 |
| 无 `approval_keys` 测试 | 多文件审批键生成未验证 | 测试多文件场景的键生成 |

### 测试改进建议

1. **增加审批流程测试**
   ```rust
   // 建议添加：
   #[tokio::test]
   async fn start_approval_async_uses_cache_when_available() { ... }
   
   #[tokio::test]
   async fn start_approval_async_requests_approval_when_needed() { ... }
   ```

2. **增加边界条件测试**
   ```rust
   // 建议添加：
   #[test]
   fn approval_keys_empty_when_no_files() { ... }
   
   #[test]
   fn approval_keys_multiple_files() { ... }
   ```

3. **增加平台特定测试**
   ```rust
   #[cfg(target_os = "windows")]
   #[test]
   fn build_command_spec_uses_windows_resolver() { ... }
   ```

4. **增加错误处理测试**
   ```rust
   #[test]
   fn build_command_spec_fails_when_exe_not_found() { ... }
   ```

### 测试维护建议

1. **使用 tempfile crate**
   - 当前：手动构造临时路径
   - 建议：使用 `tempfile::NamedTempFile` 确保清理

2. **参数化测试**
   - 当前：多个 `assert!` 组合
   - 建议：使用 `rstest` 或类似 crate 进行参数化测试

3. **文档化测试意图**
   - 当前：测试名较清晰，但缺少注释说明业务场景
   - 建议：添加文档注释说明每个测试的业务场景

### 与主代码的同步风险

- `ApplyPatchRequest` 结构变更需要同步更新测试构造代码
- `GuardianApprovalRequest` 变体变更需要同步更新断言
- 建议使用构造函数而非字面量构造，减少维护负担
