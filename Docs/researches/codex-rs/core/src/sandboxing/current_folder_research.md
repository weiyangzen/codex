# Research: codex-rs/core/src/sandboxing

## 概述

`sandboxing` 模块是 Codex 核心库中的**沙箱编排与执行入口层**，负责将高层的工具执行请求转换为平台特定的沙箱命令。它是连接「策略定义」与「实际沙箱执行」的关键桥梁，支持 macOS Seatbelt、Linux Landlock/seccomp 和 Windows 受限令牌三种平台沙箱机制。

---

## 场景与职责

### 核心职责

1. **沙箱策略转换**：将抽象的 `SandboxPolicy` 和 `FileSystemSandboxPolicy` 转换为平台特定的命令行参数
2. **执行请求构建**：将 `CommandSpec` 转换为可直接执行的 `ExecRequest`
3. **权限合并与交集**：处理基础权限与额外权限（`additional_permissions`）的合并逻辑
4. **平台沙箱选择**：根据当前平台和配置自动选择合适的沙箱类型

### 使用场景

| 场景 | 说明 |
|------|------|
| Shell 工具执行 | 通过 `shell` 工具执行用户命令时的沙箱包装 |
| 补丁应用 | `apply_patch` 工具在受限文件系统上下文中执行 |
| 统一执行 | `unified_exec` 工具的通用执行路径 |
| MCP 工具 | 外部 MCP 工具调用的沙箱隔离 |

---

## 功能点目的

### 1. CommandSpec → ExecRequest 转换

```rust
pub struct CommandSpec {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
    pub expiration: ExecExpiration,
    pub sandbox_permissions: SandboxPermissions,
    pub additional_permissions: Option<PermissionProfile>,
    pub justification: Option<String>,
}
```

**目的**：标准化工具执行请求的输入格式，包含执行所需的所有上下文信息。

### 2. SandboxManager - 沙箱编排核心

```rust
pub struct SandboxManager;

impl SandboxManager {
    pub fn select_initial(...) -> SandboxType;  // 选择初始沙箱类型
    pub fn transform(...) -> Result<ExecRequest, SandboxTransformError>;  // 转换执行请求
    pub fn denied(...) -> bool;  // 检测沙箱拒绝
}
```

**目的**：
- `select_initial`：根据文件系统策略、网络策略和用户偏好决定使用哪种沙箱
- `transform`：将 `CommandSpec` 包装为平台特定的沙箱命令
- `denied`：检测执行失败是否由沙箱限制导致

### 3. 权限合并系统

```rust
pub(crate) fn merge_permission_profiles(...)
pub(crate) fn intersect_permission_profiles(...)
pub(crate) fn effective_file_system_sandbox_policy(...)
```

**目的**：处理基础策略与用户请求的额外权限之间的合并与交集运算，确保权限计算的准确性。

### 4. macOS 特定权限扩展 (macos_permissions.rs)

```rust
pub(crate) fn merge_macos_seatbelt_profile_extensions(...)
pub(crate) fn intersect_macos_seatbelt_profile_extensions(...)
```

**目的**：处理 macOS Seatbelt 特有的权限扩展（如自动化、通讯录、日历等），支持权限的并集和交集运算。

---

## 具体技术实现

### 关键流程

#### 1. 沙箱选择流程 (`should_require_platform_sandbox`)

```rust
pub(crate) fn should_require_platform_sandbox(
    file_system_policy: &FileSystemSandboxPolicy,
    network_policy: NetworkSandboxPolicy,
    has_managed_network_requirements: bool,
) -> bool {
    // 1. 如果有托管网络需求，必须使用平台沙箱
    if has_managed_network_requirements { return true; }
    
    // 2. 如果网络被禁用且不是外部沙箱，需要平台沙箱
    if !network_policy.is_enabled() {
        return !matches!(file_system_policy.kind, FileSystemSandboxKind::ExternalSandbox);
    }
    
    // 3. 根据文件系统策略决定
    match file_system_policy.kind {
        FileSystemSandboxKind::Restricted => !file_system_policy.has_full_disk_write_access(),
        _ => false,
    }
}
```

#### 2. 沙箱转换流程 (`SandboxManager::transform`)

```rust
pub(crate) fn transform(&self, request: SandboxTransformRequest<'_>) -> Result<ExecRequest, SandboxTransformError> {
    // 1. 计算有效权限（合并基础策略和额外权限）
    let EffectiveSandboxPermissions { sandbox_policy, macos_seatbelt_profile_extensions } = 
        EffectiveSandboxPermissions::new(policy, macos_extensions, additional_permissions);
    
    // 2. 计算有效的文件系统和网络策略
    let (effective_file_system_policy, effective_network_policy) = ...;
    
    // 3. 设置网络禁用环境变量
    if !effective_network_policy.is_enabled() {
        env.insert(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR, "1");
    }
    
    // 4. 根据沙箱类型包装命令
    let (command, sandbox_env, arg0_override) = match sandbox {
        SandboxType::None => (command, HashMap::new(), None),
        SandboxType::MacosSeatbelt => { /* 包装 seatbelt 命令 */ },
        SandboxType::LinuxSeccomp => { /* 包装 codex-linux-sandbox */ },
        SandboxType::WindowsRestrictedToken => (command, HashMap::new(), None),
    };
    
    // 5. 返回 ExecRequest
    Ok(ExecRequest { ... })
}
```

#### 3. 权限合并算法 (`sandbox_policy_with_additional_permissions`)

```rust
fn sandbox_policy_with_additional_permissions(
    sandbox_policy: &SandboxPolicy,
    additional_permissions: &PermissionProfile,
) -> SandboxPolicy {
    match sandbox_policy {
        SandboxPolicy::DangerFullAccess => SandboxPolicy::DangerFullAccess,  // 完全访问不修改
        SandboxPolicy::ExternalSandbox { network_access } => { /* 合并网络权限 */ },
        SandboxPolicy::WorkspaceWrite { writable_roots, read_only_access, network_access, ... } => {
            // 合并读写根目录
            let mut merged_writes = writable_roots.clone();
            merged_writes.extend(extra_writes);
            SandboxPolicy::WorkspaceWrite { ... }
        }
        SandboxPolicy::ReadOnly { access, network_access } => {
            // 如果有写权限请求，升级为 WorkspaceWrite
            if extra_writes.is_empty() { ... } else { SandboxPolicy::WorkspaceWrite { ... } }
        }
    }
}
```

### 关键数据结构

| 结构 | 用途 |
|------|------|
| `CommandSpec` | 工具执行请求的输入规格 |
| `ExecRequest` | 转换后的可执行请求，包含完整的沙箱配置 |
| `SandboxTransformRequest` | 沙箱转换的参数捆绑，提高代码可读性 |
| `EffectiveSandboxPermissions` | 计算后的有效权限，包含合并后的策略和 macOS 扩展 |
| `SandboxManager` | 沙箱编排的核心管理器 |

### 平台特定处理

#### macOS Seatbelt
- 使用 `/usr/bin/sandbox-exec` 作为沙箱可执行文件
- 通过 `create_seatbelt_command_args_for_policies_with_extensions` 生成策略参数
- 支持动态网络策略（基于代理配置）
- 支持 macOS 特定权限扩展（自动化、通讯录等）

#### Linux Landlock/seccomp
- 使用 `codex-linux-sandbox` 外部可执行文件
- 通过 `create_linux_sandbox_command_args_for_policies` 生成命令参数
- 支持 `--use-legacy-landlock` 标志
- 支持 `--allow-network-for-proxy` 标志用于托管网络

#### Windows 受限令牌
- 在进程内通过 `codex-windows-sandbox` crate 执行
- 命令在此模块中保持不变，实际沙箱在 `exec.rs` 中处理
- 支持 `Elevated` 和 `Legacy` 两种级别

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 752 | 主模块，包含 SandboxManager 和权限合并逻辑 |
| `macos_permissions.rs` | 154 | macOS 特定权限扩展的合并与交集 |
| `mod_tests.rs` | 768 | 单元测试 |
| `macos_permissions_tests.rs` | 121 | macOS 权限测试 |

### 调用方（上游依赖）

```
codex-rs/core/src/tools/sandboxing.rs      # 工具运行时沙箱接口
codex-rs/core/src/tools/orchestrator.rs    # 工具编排器
codex-rs/core/src/exec.rs                  # 执行引擎
codex-rs/core/src/landlock.rs              # Linux 沙箱包装
codex-rs/core/src/seatbelt.rs              # macOS 沙箱包装
```

### 被调用方（下游依赖）

```
codex-rs/core/src/landlock.rs              # Linux 沙箱命令生成
codex-rs/core/src/seatbelt.rs              # macOS Seatbelt 命令生成
codex-rs/core/src/exec.rs                  # 实际执行
codex-protocol/permissions                 # 权限类型定义
```

### 关键代码路径

```
1. 工具调用入口
   tools/handlers/shell.rs
   └── tools/runtimes/shell.rs
       └── tools/orchestrator.rs::ToolOrchestrator::run()
           └── sandboxing/mod.rs::SandboxManager::select_initial()
           └── sandboxing/mod.rs::SandboxManager::transform()
               └── 平台特定命令生成
                   ├── seatbelt.rs (macOS)
                   └── landlock.rs (Linux)

2. 直接执行路径
   exec.rs::process_exec_tool_call()
   └── sandboxing/mod.rs::build_exec_request()
       └── sandboxing/mod.rs::SandboxManager::transform()
```

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::exec` | `SandboxType`, `ExecExpiration`, `ExecToolCallOutput` |
| `crate::landlock` | Linux 沙箱命令生成 |
| `crate::seatbelt` | macOS 沙箱命令生成 |
| `crate::spawn` | 环境变量常量 |
| `crate::protocol` | `SandboxPolicy` 等协议类型 |
| `crate::tools::sandboxing` | `SandboxablePreference` |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | `SandboxPermissions`, `PermissionProfile`, `FileSystemSandboxPolicy` 等 |
| `codex_network_proxy` | `NetworkProxy` 网络代理配置 |
| `codex_utils_absolute_path` | `AbsolutePathBuf` 绝对路径处理 |
| `dunce` | `canonicalize` 路径规范化 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_SANDBOX_NETWORK_DISABLED` | 标记网络是否被禁用 |
| `CODEX_SANDBOX` | 标记沙箱类型（如 `seatbelt`） |

---

## 风险、边界与改进建议

### 已知风险

1. **权限升级近似问题**（代码注释标记）
   ```rust
   // todo(dylan) - for now, this grants more access than the request.
   // We should restrict this, but we should add a new SandboxPolicy variant.
   ```
   当 `ReadOnly` 策略遇到写权限请求时，直接升级为 `WorkspaceWrite`，这可能授予比请求更多的访问权限。

2. **符号链接处理**
   - `normalize_permission_paths` 使用 `canonicalize` 解析符号链接
   - 如果符号链接在权限检查后、执行前被修改，可能导致权限绕过

3. **平台沙箱可用性**
   - 非 macOS 平台调用 `MacosSeatbelt` 会返回 `SeatbeltUnavailable` 错误
   - 需要调用方正确处理此错误

### 边界情况

1. **空权限处理**
   - `normalize_additional_permissions` 会过滤掉空的权限配置
   - 使用 `filter(|p| !p.is_empty())` 模式避免空权限污染

2. **路径规范化失败**
   - 如果 `canonicalize` 失败，保留原始路径
   - 可能导致路径不匹配，沙箱策略无法正确应用

3. **Windows 沙箱降级**
   - 当 Windows 沙箱不可用时，可能静默降级为无沙箱执行
   - 依赖 `get_platform_sandbox` 的返回值判断

### 改进建议

1. **权限计算优化**
   - 考虑引入更细粒度的权限升级策略，避免过度授权
   - 添加权限计算日志，便于审计和调试

2. **错误处理增强**
   - 为 `SandboxTransformError` 添加更多变体，提供更具体的错误信息
   - 考虑添加权限验证步骤，在转换前检查权限一致性

3. **测试覆盖**
   - 增加跨平台行为一致性测试
   - 添加符号链接攻击场景的测试用例
   - 补充 Windows 沙箱的测试覆盖

4. **文档完善**
   - 添加更多关于权限合并算法的文档
   - 明确说明各种边界情况的处理策略

5. **性能优化**
   - `dedup_absolute_paths` 使用 `HashSet` 去重，考虑使用 `BTreeSet` 保证确定性
   - 权限合并涉及多次克隆，考虑使用 `Arc` 减少拷贝

---

## 总结

`sandboxing` 模块是 Codex 安全架构的核心组件，负责将高层策略转换为平台特定的沙箱实现。其设计充分考虑了跨平台兼容性、权限合并的复杂性以及用户体验（如自动重试无沙箱执行）。理解此模块对于维护和扩展 Codex 的安全功能至关重要。

关键要点：
1. **策略转换是核心**：将抽象策略转换为具体命令参数
2. **权限合并需谨慎**：处理基础权限与额外权限的复杂交互
3. **平台差异要封装**：通过 `SandboxType` 统一不同平台的沙箱机制
4. **安全与体验平衡**：支持沙箱失败后的用户确认重试机制
