# sandboxing/mod.rs 研究文档

## 场景与职责

`sandboxing/mod.rs` 是 Codex 核心沙箱系统的中央协调模块，负责：

1. **沙箱策略管理**：管理文件系统、网络、平台特定（macOS Seatbelt）的沙箱策略
2. **权限配置处理**：处理基础权限配置与附加权限（additional_permissions）的合并与验证
3. **命令转换**：将高层的 `CommandSpec` 转换为可执行的 `ExecRequest`
4. **跨平台沙箱抽象**：统一处理 macOS Seatbelt、Linux Seccomp、Windows Restricted Token 三种沙箱机制

该模块是 `codex-core` crate 的核心组件，被 `exec.rs`、`tools` 模块等调用。

## 功能点目的

### 1. 命令规范定义 (`CommandSpec`)

定义待执行命令的完整规范：
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

### 2. 执行请求生成 (`ExecRequest`)

转换后的可执行请求：
```rust
pub struct ExecRequest {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
    pub network: Option<NetworkProxy>,
    pub expiration: ExecExpiration,
    pub sandbox: SandboxType,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
    pub sandbox_permissions: SandboxPermissions,
    pub sandbox_policy: SandboxPolicy,
    pub file_system_sandbox_policy: FileSystemSandboxPolicy,
    pub network_sandbox_policy: NetworkSandboxPolicy,
    pub justification: Option<String>,
    pub arg0: Option<String>,
}
```

### 3. 沙箱管理器 (`SandboxManager`)

核心状态机，提供：
- `select_initial()`：根据策略和用户偏好选择初始沙箱类型
- `transform()`：将 `CommandSpec` 转换为 `ExecRequest`
- `denied()`：检测沙箱拒绝信号

### 4. 权限配置处理

- `normalize_additional_permissions()`：规范化附加权限配置
- `merge_permission_profiles()`：合并两个权限配置（取并集）
- `intersect_permission_profiles()`：计算权限交集（用于验证）
- `EffectiveSandboxPermissions`：计算实际生效的权限

## 具体技术实现

### 关键数据结构

#### 沙箱偏好 (`SandboxPreference`)

```rust
pub enum SandboxPreference {
    Auto,      // 自动根据策略决定
    Require,   // 强制使用平台沙箱
    Forbid,    // 禁止使用沙箱
}
```

#### 沙箱类型 (`SandboxType`)

```rust
pub enum SandboxType {
    None,
    MacosSeatbelt,           // macOS
    LinuxSeccomp,            // Linux
    WindowsRestrictedToken,  // Windows
}
```

#### 沙箱转换请求 (`SandboxTransformRequest`)

```rust
pub(crate) struct SandboxTransformRequest<'a> {
    pub spec: CommandSpec,
    pub policy: &'a SandboxPolicy,
    pub file_system_policy: &'a FileSystemSandboxPolicy,
    pub network_policy: NetworkSandboxPolicy,
    pub sandbox: SandboxType,
    pub enforce_managed_network: bool,
    pub network: Option<&'a NetworkProxy>,
    pub sandbox_policy_cwd: &'a Path,
    #[cfg(target_os = "macos")]
    pub macos_seatbelt_profile_extensions: Option<&'a MacOsSeatbeltProfileExtensions>,
    pub codex_linux_sandbox_exe: Option<&'a PathBuf>,
    pub use_legacy_landlock: bool,
    pub windows_sandbox_level: WindowsSandboxLevel,
    pub windows_sandbox_private_desktop: bool,
}
```

### 核心算法实现

#### 1. 初始沙箱选择逻辑 (`select_initial`)

```rust
pub(crate) fn select_initial(
    &self,
    file_system_policy: &FileSystemSandboxPolicy,
    network_policy: NetworkSandboxPolicy,
    pref: SandboxablePreference,
    windows_sandbox_level: WindowsSandboxLevel,
    has_managed_network_requirements: bool,
) -> SandboxType {
    match pref {
        SandboxablePreference::Forbid => SandboxType::None,
        SandboxablePreference::Require => {
            // 强制使用平台沙箱
            crate::safety::get_platform_sandbox(
                windows_sandbox_level != WindowsSandboxLevel::Disabled,
            )
            .unwrap_or(SandboxType::None)
        }
        SandboxablePreference::Auto => {
            if should_require_platform_sandbox(
                file_system_policy,
                network_policy,
                has_managed_network_requirements,
            ) {
                crate::safety::get_platform_sandbox(
                    windows_sandbox_level != WindowsSandboxLevel::Disabled,
                )
                .unwrap_or(SandboxType::None)
            } else {
                SandboxType::None
            }
        }
    }
}
```

#### 2. 平台沙箱必要性判断 (`should_require_platform_sandbox`)

```rust
pub(crate) fn should_require_platform_sandbox(
    file_system_policy: &FileSystemSandboxPolicy,
    network_policy: NetworkSandboxPolicy,
    has_managed_network_requirements: bool,
) -> bool {
    // 托管网络要求强制使用沙箱
    if has_managed_network_requirements {
        return true;
    }

    // 网络受限时，非外部沙箱需要平台沙箱
    if !network_policy.is_enabled() {
        return !matches!(
            file_system_policy.kind,
            FileSystemSandboxKind::ExternalSandbox
        );
    }

    // 文件系统受限且无全盘写权限时需要平台沙箱
    match file_system_policy.kind {
        FileSystemSandboxKind::Restricted => !file_system_policy.has_full_disk_write_access(),
        FileSystemSandboxKind::Unrestricted | FileSystemSandboxKind::ExternalSandbox => false,
    }
}
```

#### 3. 权限配置合并 (`merge_permission_profiles`)

```rust
pub(crate) fn merge_permission_profiles(
    base: Option<&PermissionProfile>,
    permissions: Option<&PermissionProfile>,
) -> Option<PermissionProfile> {
    let Some(permissions) = permissions else {
        return base.cloned();
    };

    match base {
        Some(base) => {
            let network = match (base.network.as_ref(), permissions.network.as_ref()) {
                // 任一方启用网络，则启用
                (Some(NetworkPermissions { enabled: Some(true) }), _)
                | (_, Some(NetworkPermissions { enabled: Some(true) })) => {
                    Some(NetworkPermissions { enabled: Some(true) })
                }
                _ => None,
            };
            
            let file_system = match (base.file_system.as_ref(), permissions.file_system.as_ref()) {
                (Some(base), Some(permissions)) => Some(FileSystemPermissions {
                    read: merge_permission_paths(base.read.as_ref(), permissions.read.as_ref()),
                    write: merge_permission_paths(base.write.as_ref(), permissions.write.as_ref()),
                })
                .filter(|file_system| !file_system.is_empty()),
                (Some(base), None) => Some(base.clone()),
                (None, Some(permissions)) => Some(permissions.clone()),
                (None, None) => None,
            };
            
            let macos = merge_macos_seatbelt_profile_extensions(
                base.macos.as_ref(),
                permissions.macos.as_ref(),
            );

            Some(PermissionProfile { network, file_system, macos })
                .filter(|permissions| !permissions.is_empty())
        }
        None => Some(permissions.clone()).filter(|permissions| !permissions.is_empty()),
    }
}
```

#### 4. 权限配置交集 (`intersect_permission_profiles`)

```rust
pub fn intersect_permission_profiles(
    requested: PermissionProfile,
    granted: PermissionProfile,
) -> PermissionProfile {
    let file_system = requested
        .file_system
        .map(|requested_file_system| {
            let granted_file_system = granted.file_system.unwrap_or_default();
            let read = requested_file_system
                .read
                .map(|requested_read| {
                    let granted_read = granted_file_system.read.unwrap_or_default();
                    requested_read
                        .into_iter()
                        .filter(|path| granted_read.contains(path))
                        .collect()
                })
                .filter(|paths: &Vec<_>| !paths.is_empty());
            let write = requested_file_system
                .write
                .map(|requested_write| {
                    let granted_write = granted_file_system.write.unwrap_or_default();
                    requested_write
                        .into_iter()
                        .filter(|path| granted_write.contains(path))
                        .collect()
                })
                .filter(|paths: &Vec<_>| !paths.is_empty());
            FileSystemPermissions { read, write }
        })
        .filter(|file_system| !file_system.is_empty());
    
    let network = match (requested.network, granted.network) {
        (Some(NetworkPermissions { enabled: Some(true) }), 
         Some(NetworkPermissions { enabled: Some(true) })) => {
            Some(NetworkPermissions { enabled: Some(true) })
        }
        _ => None,
    };

    let macos = intersect_macos_seatbelt_profile_extensions(requested.macos, granted.macos);

    PermissionProfile { network, file_system, macos }
}
```

#### 5. 沙箱转换核心逻辑 (`transform`)

```rust
pub(crate) fn transform(
    &self,
    request: SandboxTransformRequest<'_>,
) -> Result<ExecRequest, SandboxTransformError> {
    // 1. 解构请求
    let SandboxTransformRequest { mut spec, policy, ... } = request;
    
    // 2. 计算有效权限
    let additional_permissions = spec.additional_permissions.take();
    let EffectiveSandboxPermissions { sandbox_policy: effective_policy, ... } = 
        EffectiveSandboxPermissions::new(policy, macos_seatbelt_profile_extensions, additional_permissions.as_ref());
    
    // 3. 计算有效文件系统和网络策略
    let (effective_file_system_policy, effective_network_policy) = 
        if let Some(additional_permissions) = additional_permissions {
            // 合并附加权限
            ...
        } else {
            (file_system_policy.clone(), network_policy)
        };
    
    // 4. 设置网络禁用环境变量
    if !effective_network_policy.is_enabled() {
        env.insert(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR.to_string(), "1".to_string());
    }
    
    // 5. 根据沙箱类型构建命令
    let (command, sandbox_env, arg0_override) = match sandbox {
        SandboxType::None => (command, HashMap::new(), None),
        
        #[cfg(target_os = "macos")]
        SandboxType::MacosSeatbelt => {
            // 构建 Seatbelt 命令
            let mut args = create_seatbelt_command_args_for_policies_with_extensions(...);
            let mut full_command = vec![MACOS_PATH_TO_SEATBELT_EXECUTABLE.to_string()];
            full_command.append(&mut args);
            (full_command, seatbelt_env, None)
        }
        
        SandboxType::LinuxSeccomp => {
            // 构建 Linux 沙箱命令
            let exe = codex_linux_sandbox_exe
                .ok_or(SandboxTransformError::MissingLinuxSandboxExecutable)?;
            let mut args = create_linux_sandbox_command_args_for_policies(...);
            ...
        }
        
        // Windows 在运行时处理
        SandboxType::WindowsRestrictedToken => (command, HashMap::new(), None),
    };
    
    // 6. 返回 ExecRequest
    Ok(ExecRequest { ... })
}
```

## 关键代码路径与文件引用

### 本文件关键组件

| 组件 | 行号 | 用途 |
|------|------|------|
| `CommandSpec` | 52-61 | 命令规范定义 |
| `ExecRequest` | 64-79 | 执行请求定义 |
| `SandboxTransformRequest` | 84-101 | 沙箱转换请求 |
| `SandboxPreference` | 103-107 | 沙箱偏好枚举 |
| `EffectiveSandboxPermissions` | 118-148 | 有效权限计算 |
| `normalize_additional_permissions` | 150-175 | 权限规范化 |
| `merge_permission_profiles` | 177-228 | 权限合并 |
| `intersect_permission_profiles` | 230-282 | 权限交集 |
| `should_require_platform_sandbox` | 515-535 | 沙箱必要性判断 |
| `SandboxManager` | 537-725 | 沙箱管理器 |
| `execute_env` | 727-739 | 执行环境 |

### 调用方

1. **`exec.rs`** - 执行引擎
   - 调用 `SandboxManager::select_initial()` 选择沙箱
   - 调用 `SandboxManager::transform()` 转换命令
   - 调用 `execute_env()` 执行命令

2. **`tools/runtimes/shell/unix_escalation.rs`** - Unix 权限升级
   - 调用 `intersect_permission_profiles()` 验证权限

3. **`skills/loader.rs`** - 技能加载器
   - 调用 `merge_permission_profiles()` 合并技能权限

### 被调用方（依赖）

1. **`macos_permissions.rs`** - macOS 权限处理
   - `merge_macos_seatbelt_profile_extensions`
   - `intersect_macos_seatbelt_profile_extensions`

2. **`seatbelt.rs`** - macOS Seatbelt 沙箱
   - `create_seatbelt_command_args_for_policies_with_extensions`
   - `MACOS_PATH_TO_SEATBELT_EXECUTABLE`

3. **`landlock.rs`** - Linux Landlock 沙箱
   - `create_linux_sandbox_command_args_for_policies`
   - `allow_network_for_proxy`

4. **`safety.rs`** - 安全检查
   - `get_platform_sandbox()`

5. **`spawn.rs`** - 进程 spawning
   - `CODEX_SANDBOX_ENV_VAR`
   - `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR`

## 依赖与外部交互

### 外部 Crate 依赖

```rust
use codex_protocol::models::FileSystemPermissions;
use codex_protocol::models::MacOsSeatbeltProfileExtensions;
use codex_protocol::models::NetworkPermissions;
use codex_protocol::models::PermissionProfile;
use codex_protocol::permissions::FileSystemAccessMode;
use codex_protocol::permissions::FileSystemPath;
use codex_protocol::permissions::FileSystemSandboxEntry;
use codex_protocol::permissions::FileSystemSandboxKind;
use codex_protocol::permissions::FileSystemSandboxPolicy;
use codex_protocol::permissions::NetworkSandboxPolicy;
use codex_utils_absolute_path::AbsolutePathBuf;
use dunce::canonicalize;
```

### 跨平台处理

| 平台 | 沙箱类型 | 处理方式 |
|------|---------|---------|
| macOS | Seatbelt | 通过 `sandbox-exec` 命令包装 |
| Linux | Seccomp/Landlock | 通过 `codex-linux-sandbox` 辅助程序 |
| Windows | Restricted Token | 进程内通过 `codex-windows-sandbox` crate |

### 环境变量

- `CODEX_SANDBOX` - 沙箱类型标识（如 "seatbelt"）
- `CODEX_SANDBOX_NETWORK_DISABLED` - 网络禁用标志

## 风险、边界与改进建议

### 潜在风险

1. **权限升级漏洞**
   - `merge_permission_profiles` 总是取最宽松权限，恶意配置可能导致权限提升
   - 建议：增加权限来源验证和审计日志

2. **Linux 沙箱可执行文件缺失**
   - 如果 `codex_linux_sandbox_exe` 未配置，会返回 `MissingLinuxSandboxExecutable` 错误
   - 建议：在启动时验证必要组件存在性

3. **Windows 沙箱处理不一致**
   - Windows 沙箱在 `transform()` 中不修改命令，而在执行时处理
   - 这可能导致命令行预览与实际执行不一致

4. **路径规范化竞争条件**
   - `normalize_permission_paths` 使用 `canonicalize()` 需要访问文件系统
   - 如果路径在检查和执行之间被替换，可能导致 TOCTOU 问题

### 边界情况

1. **空权限配置**
   - `PermissionProfile::is_empty()` 用于过滤空配置
   - 但空配置与 `None` 的语义差异需要小心处理

2. **ReadOnly + Write 附加权限**
   - 当基础策略为 ReadOnly 但附加权限包含写路径时，会升级为 WorkspaceWrite
   - 代码注释说明这是近似行为，未来可能需要新策略变体

3. **macOS 非 macOS 编译**
   - macOS 特定字段通过 `#[cfg(target_os = "macos")]` 条件编译
   - 非 macOS 平台这些字段为 `None`

### 改进建议

1. **增加结构化日志**
   ```rust
   tracing::info!(
       sandbox_type = ?sandbox,
       policy = ?effective_policy,
       "Transforming command for sandbox execution"
   );
   ```

2. **统一 Windows 沙箱处理**
   - 考虑在 `transform()` 中生成 Windows 沙箱配置，即使不修改命令

3. **权限变更审计**
   - 记录所有权限合并和升级的决策原因

4. **配置验证增强**
   - 在 `normalize_additional_permissions` 中增加更多验证规则
   - 例如：检查路径是否在允许范围内

5. **错误信息改进**
   - `SandboxTransformError` 目前只有两种变体，可以增加更多上下文

### 测试覆盖

测试模块 `mod_tests.rs` 覆盖：
- 沙箱选择逻辑
- 权限规范化
- 权限合并
- 权限交集
- 文件系统策略合并
- 网络权限处理

建议增加：
- 并发权限操作测试
- 大规模路径列表性能测试
- 错误路径恢复测试
