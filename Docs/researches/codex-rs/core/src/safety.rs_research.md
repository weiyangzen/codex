# safety.rs 研究文档

## 场景与职责

本文件是 Codex 核心安全模块，负责**补丁应用操作的安全评估**。它决定一个代码补丁（ApplyPatchAction）是否可以自动执行、需要用户确认，或应该被拒绝。这是 Codex **安全边界**的关键组件，防止恶意或意外的代码修改。

**核心职责**：
- 评估补丁操作的安全风险
- 根据沙盒策略和用户配置决定执行方式
- 确定适用的沙盒类型（macOS Seatbelt / Linux Seccomp / Windows）
- 验证补丁路径是否在允许的写入范围内

## 功能点目的

### 1. 补丁安全评估 (`assess_patch_safety`)
综合评估补丁操作，返回 `SafetyCheck` 结果：

```rust
pub enum SafetyCheck {
    AutoApprove { sandbox_type: SandboxType, user_explicitly_approved: bool },
    AskUser,
    Reject { reason: String },
}
```

### 2. 平台沙盒选择 (`get_platform_sandbox`)
根据平台选择可用的沙盒机制：
- **macOS**: `MacosSeatbelt` (Seatbelt)
- **Linux**: `LinuxSeccomp` (Seccomp + Landlock)
- **Windows**: `WindowsRestrictedToken`（可选）

### 3. 写入路径约束检查 (`is_write_patch_constrained_to_writable_paths`)
验证补丁的所有写入操作是否都在允许的根目录内：
- 支持文件添加、删除、更新（含移动）
- 路径归一化处理（处理 `.` 和 `..`）
- 与 `FileSystemSandboxPolicy` 集成

## 具体技术实现

### 安全评估流程

```rust
pub fn assess_patch_safety(
    action: &ApplyPatchAction,
    policy: AskForApproval,                    // 用户审批策略
    sandbox_policy: &SandboxPolicy,            // 沙盒策略
    file_system_sandbox_policy: &FileSystemSandboxPolicy,  // 文件系统策略
    cwd: &Path,
    windows_sandbox_level: WindowsSandboxLevel,
) -> SafetyCheck
```

#### 决策流程

```
┌─────────────────────────────────────────────────────────────┐
│ 1. 空补丁检查                                                │
│    └── 空 → Reject("empty patch")                           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. 审批策略检查                                              │
│    ├── UnlessTrusted → AskUser                              │
│    └── 其他 → 继续评估                                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. 路径约束检查                                              │
│    └── 写入是否都在允许路径内？                              │
└─────────────────────────────────────────────────────────────┘
              ↓ 是                           ↓ 否
┌─────────────────────────────┐    ┌─────────────────────────────┐
│ 4a. 沙盒可用性检查           │    │ 4b. 拒绝策略检查             │
│    ├── DangerFullAccess →   │    │    ├── Never/Granular(sandbox_approval=false)
│    │   AutoApprove(None)     │    │    │   → Reject             │
│    └── 其他 → 检查平台沙盒   │    │    └── 其他 → AskUser       │
└─────────────────────────────┘    └─────────────────────────────┘
              ↓
┌─────────────────────────────┐
│ 5. 平台沙盒可用性            │
│    ├── 有 → AutoApprove      │
│    └── 无 → AskUser/Reject   │
└─────────────────────────────┘
```

### 路径约束检查实现

```rust
fn is_write_patch_constrained_to_writable_paths(
    action: &ApplyPatchAction,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    cwd: &Path,
) -> bool
```

#### 路径归一化
```rust
fn normalize(path: &Path) -> Option<PathBuf> {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::ParentDir => { out.pop(); }
            Component::CurDir => { /* skip */ }
            other => out.push(other.as_os_str()),
        }
    }
    Some(out)
}
```

#### 写入检查逻辑
- **Add/Delete**: 检查目标路径是否可写
- **Update**: 检查源路径和目标路径（如有移动）是否可写
- 使用 `FileSystemSandboxPolicy::can_write_path_with_cwd` 验证

### 平台沙盒映射

```rust
pub fn get_platform_sandbox(windows_sandbox_enabled: bool) -> Option<SandboxType> {
    if cfg!(target_os = "macos") {
        Some(SandboxType::MacosSeatbelt)
    } else if cfg!(target_os = "linux") {
        Some(SandboxType::LinuxSeccomp)
    } else if cfg!(target_os = "windows") {
        if windows_sandbox_enabled {
            Some(SandboxType::WindowsRestrictedToken)
        } else {
            None
        }
    } else {
        None
    }
}
```

## 关键代码路径与文件引用

### 调用关系
```
tools/handlers/apply_patch.rs
  └── assess_patch_safety()  [处理 apply_patch 工具调用]

apply_patch.rs (internal)
  └── assess_patch_safety()  [内部补丁应用]

sandbox_tags.rs
  └── get_platform_sandbox()  [获取沙盒标签]
```

### 依赖类型
```rust
// 输入
use codex_apply_patch::ApplyPatchAction;
use codex_apply_patch::ApplyPatchFileChange;
use crate::protocol::AskForApproval;
use crate::protocol::FileSystemSandboxPolicy;
use crate::protocol::SandboxPolicy;
use codex_protocol::config_types::WindowsSandboxLevel;

// 输出
use crate::exec::SandboxType;
use crate::safety::SafetyCheck;
```

### 相关文件
- `apply_patch.rs` - 补丁应用实现
- `exec.rs` - 执行层，定义 `SandboxType`
- `sandbox_tags.rs` - 沙盒标签生成
- `safety_tests.rs` - 单元测试

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `codex_apply_patch` | 补丁解析和操作类型 |
| `codex_protocol` | 策略和配置类型 |
| `std::path` | 路径处理 |

### 与沙盒系统集成

```
safety.rs
  └── SafetyCheck::AutoApprove { sandbox_type }
        └── exec.rs::SandboxType
              ├── MacosSeatbelt → seatbelt.rs
              ├── LinuxSeccomp → sandboxing/mod.rs
              └── WindowsRestrictedToken → windows 实现
```

### 配置依赖
- `AskForApproval` - 用户审批偏好
- `SandboxPolicy` - 沙盒策略配置
- `FileSystemSandboxPolicy` - 文件系统访问策略
- `WindowsSandboxLevel` - Windows 沙盒级别

## 风险、边界与改进建议

### 潜在风险

1. **硬链接攻击**
   ```rust
   // 代码注释中提到：
   // Even though the patch appears to be constrained to writable paths, it is
   // possible that paths in the patch are hard links to files outside the
   // writable roots
   ```
   - 补丁路径可能是指向可写区域外文件的硬链接
   - 当前通过沙盒执行缓解，但依赖沙盒正确配置

2. **路径遍历攻击**
   - 归一化逻辑处理 `..` 和 `.`
   - 需要确保所有路径在检查前都已归一化

3. **竞争条件**
   - 路径检查和实际写入之间可能存在 TOCTOU 竞争
   - 沙盒应在独立进程中强制执行

4. **Windows 沙盒限制**
   - Windows 沙盒默认禁用（`WindowsSandboxLevel::Disabled`）
   - 可能导致 Windows 平台无沙盒保护

### 边界限制

1. **策略复杂性**
   - `UnlessTrusted` 策略有 TODO 注释表明可能不正确
   - 复杂的 Granular 配置容易出错

2. **平台差异**
   - 不同平台的沙盒能力不一致
   - Windows 需要显式启用

3. **无内容检查**
   - 仅检查路径，不检查补丁内容
   - 恶意代码在允许路径内仍可执行

### 改进建议

1. **安全加固**
   - 修复 `UnlessTrusted` 策略的 TODO 问题
   - 添加硬链接检测机制
   - 实现路径访问审计日志

2. **代码改进**
   ```rust
   // 当前代码
   AskForApproval::UnlessTrusted => {
       return SafetyCheck::AskUser;  // TODO: 可能不正确
   }
   
   // 建议：明确策略意图或移除
   ```

3. **测试增强**
   - 添加硬链接攻击场景测试
   - 添加符号链接竞争测试
   - 增加跨平台沙盒一致性测试

4. **可观测性**
   - 记录每个安全决策的详细原因
   - 提供安全审计日志
   - 添加调试模式显示路径检查详情

5. **用户体验**
   - 当拒绝时提供更详细的解释
   - 建议用户如何修改配置以允许操作
   - 提供模拟模式（dry-run）预览安全决策

6. **Windows 支持**
   - 默认启用 Windows 沙盒
   - 提供更细粒度的 Windows 沙盒配置
