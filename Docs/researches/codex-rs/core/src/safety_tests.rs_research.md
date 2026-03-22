# safety_tests.rs 研究文档

## 场景与职责

本文件是 `safety.rs` 的配套测试模块，负责**验证补丁安全评估逻辑的正确性**。通过全面的单元测试确保 `assess_patch_safety` 和 `is_write_patch_constrained_to_writable_paths` 在各种场景下做出正确的安全决策。

**核心职责**：
- 验证写入路径约束检查的正确性
- 测试不同审批策略（AskForApproval）的行为
- 验证沙盒策略与审批策略的交互
- 确保外部沙盒和细粒度配置按预期工作

## 功能点目的

### 1. 写入路径约束测试 (`test_writable_roots_constraint`)
验证补丁写入操作是否被正确限制在可写根目录内：
- 工作区内写入应被允许
- 工作区外写入应被拒绝
- 显式添加的写入根应生效

### 2. 外部沙盒测试 (`external_sandbox_auto_approves_in_on_request`)
验证 `ExternalSandbox` 策略在 `OnRequest` 审批策略下自动批准：
- 外部沙盒由用户显式配置
- 信任外部沙盒的隔离能力

### 3. 细粒度审批测试
验证 `GranularApprovalConfig` 的行为：
- `granular_with_all_flags_true_matches_on_request_for_out_of_root_patch`
- `granular_sandbox_approval_false_rejects_out_of_root_patch`

### 4. 显式不可读路径测试
验证显式标记为不可读的路径阻止自动批准：
- `explicit_unreadable_paths_prevent_auto_approval_for_external_sandbox`
- `explicit_read_only_subpaths_prevent_auto_approval_for_external_sandbox`

## 具体技术实现

### 测试基础设施

```rust
use tempfile::TempDir;
use pretty_assertions::assert_eq;

// 典型测试结构
#[test]
fn test_writable_roots_constraint() {
    let tmp = TempDir::new().unwrap();
    let cwd = tmp.path().to_path_buf();
    let parent = cwd.parent().unwrap().to_path_buf();
    
    // 创建测试补丁
    let make_add_change = |p: PathBuf| ApplyPatchAction::new_add_for_test(&p, "".to_string());
    let add_inside = make_add_change(cwd.join("inner.txt"));
    let add_outside = make_add_change(parent.join("outside.txt"));
    
    // 验证结果
    assert!(is_write_patch_constrained_to_writable_paths(...));
    assert!(!is_write_patch_constrained_to_writable_paths(...));
}
```

### 测试用例详解

#### 1. 基本路径约束测试
```rust
#[test]
fn test_writable_roots_constraint() {
    // 场景：工作区 vs 外部路径
    // 策略：仅工作区可写
    let policy_workspace_only = SandboxPolicy::WorkspaceWrite {
        writable_roots: vec![],
        read_only_access: Default::default(),
        network_access: false,
        exclude_tmpdir_env_var: true,
        exclude_slash_tmp: true,
    };
    
    // 断言：内部写入允许，外部写入拒绝
    assert!(is_write_patch_constrained_to_writable_paths(&add_inside, ...));
    assert!(!is_write_patch_constrained_to_writable_paths(&add_outside, ...));
    
    // 添加父目录为可写根后，外部写入应被允许
    let policy_with_parent = SandboxPolicy::WorkspaceWrite {
        writable_roots: vec![AbsolutePathBuf::try_from(parent).unwrap()],
        ...
    };
    assert!(is_write_patch_constrained_to_writable_paths(&add_outside, ...));
}
```

#### 2. 外部沙盒自动批准
```rust
#[test]
fn external_sandbox_auto_approves_in_on_request() {
    let policy = SandboxPolicy::ExternalSandbox {
        network_access: NetworkAccess::Enabled,
    };
    
    // 即使在工作区内，ExternalSandbox + OnRequest 也应自动批准
    assert_eq!(
        assess_patch_safety(..., AskForApproval::OnRequest, ...),
        SafetyCheck::AutoApprove {
            sandbox_type: SandboxType::None,
            user_explicitly_approved: false,
        }
    );
}
```

#### 3. 细粒度审批配置
```rust
#[test]
fn granular_with_all_flags_true_matches_on_request_for_out_of_root_patch() {
    // OnRequest 和 Granular(全 true) 对外部补丁都应 AskUser
    assert_eq!(
        assess_patch_safety(..., AskForApproval::OnRequest, ...),
        SafetyCheck::AskUser,
    );
    assert_eq!(
        assess_patch_safety(..., AskForApproval::Granular(GranularApprovalConfig {
            sandbox_approval: true,
            rules: true,
            skill_approval: true,
            request_permissions: true,
            mcp_elicitations: true,
        }), ...),
        SafetyCheck::AskUser,
    );
}

#[test]
fn granular_sandbox_approval_false_rejects_out_of_root_patch() {
    // sandbox_approval = false 时应拒绝外部补丁
    assert_eq!(
        assess_patch_safety(...),
        SafetyCheck::Reject {
            reason: "writing outside of the project; rejected by user approval settings".to_string(),
        },
    );
}
```

#### 4. 显式权限限制
```rust
#[test]
fn explicit_unreadable_paths_prevent_auto_approval_for_external_sandbox() {
    // 配置：根目录可写，但特定路径不可读
    let file_system_sandbox_policy = FileSystemSandboxPolicy::restricted(vec![
        FileSystemSandboxEntry {
            path: FileSystemPath::Special { value: FileSystemSpecialPath::Root },
            access: FileSystemAccessMode::Write,
        },
        FileSystemSandboxEntry {
            path: FileSystemPath::Path { path: blocked_absolute },
            access: FileSystemAccessMode::None,  // 显式不可读
        },
    ]);
    
    // 被阻止的路径应导致 AskUser
    assert!(!is_write_patch_constrained_to_writable_paths(&action, ...));
    assert_eq!(assess_patch_safety(...), SafetyCheck::AskUser);
}
```

## 关键代码路径与文件引用

### 被测试的函数
```rust
// safety.rs
pub fn assess_patch_safety(...) -> SafetyCheck
fn is_write_patch_constrained_to_writable_paths(...) -> bool
pub fn get_platform_sandbox(...) -> Option<SandboxType>
```

### 测试模块声明
```rust
// safety.rs (line 182-184)
#[cfg(test)]
#[path = "safety_tests.rs"]
mod tests;
```

### 依赖类型
```rust
use super::*;  // safety.rs 的所有导出
use codex_protocol::protocol::{FileSystemAccessMode, FileSystemPath, ...};
use codex_utils_absolute_path::AbsolutePathBuf;
use pretty_assertions::assert_eq;
use tempfile::TempDir;
```

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建临时目录作为测试工作区 |
| `pretty_assertions::assert_eq` | 提供更清晰的测试失败输出 |
| `codex_apply_patch::ApplyPatchAction` | 创建测试补丁 |

### 被测代码
- `safety.rs` 的所有公共和私有函数（通过 `super::*`）

### 无外部 IO（除临时文件）
- 使用 `TempDir` 创建隔离的测试环境
- 不依赖真实 Git 仓库或网络

## 风险、边界与改进建议

### 潜在风险

1. **测试覆盖不足**
   - 缺少 `DangerFullAccess` 策略的测试
   - 缺少 `UnlessTrusted` 策略的测试（虽有 TODO 表明可能有问题）
   - 缺少 Windows 沙盒级别测试

2. **硬编码字符串依赖**
   - 测试依赖特定的错误消息字符串
   - 消息变更会导致测试失败

3. **测试数据构造**
   - 使用 `ApplyPatchAction::new_add_for_test`，可能无法覆盖所有场景
   - 缺少复杂补丁（多文件、移动操作）的测试

### 边界限制

1. **平台限制**
   - 测试在 Linux/macOS/Windows 上运行，但沙盒行为可能不同
   - `get_platform_sandbox` 的行为在不同平台不同

2. **模拟限制**
   - 使用临时目录模拟工作区，可能与真实场景有差异
   - 不测试实际的沙盒执行

### 改进建议

1. **增加测试覆盖**
   ```rust
   // 建议添加：
   #[test]
   fn danger_full_access_bypasses_all_checks() { ... }
   
   #[test]
   fn unless_trusted_asks_user_even_for_safe_paths() { ... }
   
   #[test]
   fn windows_sandbox_disabled_returns_none() { ... }
   ```

2. **参数化测试**
   - 使用 `rstest` 或类似框架减少重复代码
   - 为不同策略组合生成测试矩阵

3. **集成测试**
   - 添加与真实沙盒执行的集成测试
   - 验证安全决策在实际执行中的效果

4. **边界测试**
   - 空补丁测试（已有）
   - 超长路径测试
   - 包含特殊字符的路径测试
   - 符号链接路径测试

5. **性能测试**
   - 大规模补丁（1000+ 文件）的性能测试
   - 复杂路径策略的评估性能

6. **文档测试**
   - 添加示例代码的文档测试
   - 展示典型使用场景

### 测试代码改进

```rust
// 当前：重复的模式
let tmp = TempDir::new().unwrap();
let cwd = tmp.path().to_path_buf();

// 建议：提取为辅助函数或 fixture
fn setup_test_workspace() -> (TempDir, PathBuf) {
    let tmp = TempDir::new().unwrap();
    let cwd = tmp.path().to_path_buf();
    (tmp, cwd)
}

// 当前：硬编码错误消息
assert_eq!(result, SafetyCheck::Reject {
    reason: "writing outside of the project; rejected by user approval settings".to_string(),
});

// 建议：使用常量
const REJECT_REASON_OUTSIDE_PROJECT: &str = "writing outside of the project; rejected by user approval settings";
```
