# codex-rs/core/src/sandboxing 深度研究文档

## 概述

`sandboxing` 模块是 Codex 核心安全架构的关键组件，负责构建平台特定的沙箱包装器，并将可移植的 `CommandSpec` 转换为可执行的运行环境。该模块拥有低级别沙箱放置和策略转换的核心逻辑。

---

## 场景与职责

### 核心职责

1. **沙箱策略转换**: 将高层次的 `SandboxPolicy` 转换为平台特定的执行参数
2. **权限管理**: 处理文件系统、网络和 macOS 特定权限的合并与交集
3. **命令构建**: 生成最终的 `ExecRequest`，包含完整的命令行参数和环境变量
4. **跨平台抽象**: 统一处理 macOS Seatbelt、Linux Seccomp/bubblewrap 和 Windows Restricted Token

### 使用场景

| 场景 | 描述 |
|------|------|
| Shell 工具执行 | 用户命令通过沙箱隔离执行 |
| Apply Patch 操作 | 文件修改操作的安全约束 |
| JS REPL 执行 | JavaScript 代码的受限运行 |
| 权限升级请求 | 处理额外的权限申请 |

---

## 功能点目的

### 1. CommandSpec - 命令规范

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

**目的**: 定义一个与平台无关的命令执行请求，包含所有必要的执行参数和沙箱配置。

### 2. ExecRequest - 执行请求

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

**目的**: 转换后的完整执行请求，可直接传递给 `execute_exec_request` 执行。

### 3. SandboxManager - 沙箱管理器

核心方法：
- `select_initial()`: 根据策略选择初始沙箱类型
- `transform()`: 将 `CommandSpec` 转换为 `ExecRequest`
- `denied()`: 检测执行结果是否因沙箱限制而失败

### 4. 权限合并与交集

**merge_permission_profiles**: 合并两个权限配置，取最宽松的权限
**intersect_permission_profiles**: 计算两个权限配置的交集，用于权限验证

### 5. macOS 特定权限处理 (macos_permissions.rs)

处理 macOS Seatbelt 扩展权限：
- `macos_preferences`: 系统偏好设置访问 (None/ReadOnly/ReadWrite)
- `macos_automation`: 自动化权限 (None/All/BundleIds)
- `macos_launch_services`: 启动服务访问
- `macos_accessibility`: 辅助功能访问
- `macos_calendar`: 日历访问
- `macos_reminders`: 提醒事项访问
- `macos_contacts`: 联系人访问 (None/ReadOnly/ReadWrite)

---

## 具体技术实现

### 关键流程

#### 1. 沙箱选择流程 (`should_require_platform_sandbox`)

```
是否需要平台沙箱?
├── 有托管网络需求? → 是
├── 网络被禁用? 
│   └── 文件系统策略不是 ExternalSandbox? → 是
└── 文件系统策略类型:
    ├── Restricted → 没有全盘写入权限? → 是
    ├── Unrestricted → 否
    └── ExternalSandbox → 否
```

#### 2. 命令转换流程 (`SandboxManager::transform`)

```
CommandSpec
    ↓
计算 EffectiveSandboxPermissions (合并 additional_permissions)
    ↓
计算 effective_file_system_policy 和 effective_network_policy
    ↓
设置环境变量 (CODEX_SANDBOX_NETWORK_DISABLED)
    ↓
根据 SandboxType 构建最终命令:
    ├── None → 原命令
    ├── MacosSeatbelt → /usr/bin/sandbox-exec + seatbelt 参数
    ├── LinuxSeccomp → codex-linux-sandbox + JSON 策略参数
    └── WindowsRestrictedToken → 原命令 (Windows 内部处理)
    ↓
ExecRequest
```

#### 3. 执行流程 (`execute_env`)

```
ExecRequest
    ↓
execute_exec_request (exec.rs)
    ↓
根据 sandbox 类型分发:
    ├── None → 直接执行
    ├── MacosSeatbelt → spawn_command_under_seatbelt
    ├── LinuxSeccomp → spawn_command_under_linux_sandbox
    └── WindowsRestrictedToken → Windows 沙箱执行
```

### 关键数据结构

#### SandboxType

```rust
pub enum SandboxType {
    None,
    MacosSeatbelt,        // macOS 专用
    LinuxSeccomp,         // Linux 专用
    WindowsRestrictedToken, // Windows 专用
}
```

#### SandboxPermissions

```rust
pub enum SandboxPermissions {
    UseDefault,              // 使用默认策略
    RequireEscalated,        // 请求无沙箱执行
    WithAdditionalPermissions, // 使用额外权限在沙箱中执行
}
```

#### SandboxPolicy (协议层定义)

```rust
pub enum SandboxPolicy {
    DangerFullAccess,           // 无限制
    ReadOnly { access, network_access },  // 只读
    ExternalSandbox { network_access },   // 外部沙箱
    WorkspaceWrite {            // 工作区写入
        writable_roots,
        read_only_access,
        network_access,
        exclude_tmpdir_env_var,
        exclude_slash_tmp,
    },
}
```

### 协议与命令

#### macOS Seatbelt 命令构建

```rust
// 最终命令格式:
/usr/bin/sandbox-exec \
    -f <seatbelt_profile.sbpl> \
    -D COMMAND_CWD=<cwd> \
    -D POLICY_CWD=<policy_cwd> \
    -- <original_command...>
```

Seatbelt profile 包含：
- 基础策略 (`seatbelt_base_policy.sbpl`)
- 网络策略 (`seatbelt_network_policy.sbpl`)
- 平台默认只读策略 (`restricted_read_only_platform_defaults.sbpl`)
- 扩展权限 (通过 `build_seatbelt_extensions` 生成)

#### Linux Sandbox 命令构建

```rust
// 最终命令格式:
codex-linux-sandbox \
    --sandbox-policy-cwd <policy_cwd> \
    --command-cwd <command_cwd> \
    --sandbox-policy <json> \
    --file-system-sandbox-policy <json> \
    --network-sandbox-policy <json> \
    [--use-legacy-landlock] \
    [--allow-network-for-proxy] \
    -- <original_command...>
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 752 | 主模块，包含 SandboxManager、权限合并逻辑 |
| `macos_permissions.rs` | 154 | macOS Seatbelt 扩展权限处理 |
| `mod_tests.rs` | 768 | 主模块测试 |
| `macos_permissions_tests.rs` | 121 | macOS 权限测试 |

### 依赖模块

```
sandboxing/
├── 调用方:
│   ├── exec.rs (主要调用者)
│   ├── tools/sandboxing.rs (工具层沙箱逻辑)
│   ├── tools/orchestrator.rs (工具编排)
│   ├── tools/runtimes/*.rs (各种运行时)
│   ├── state/session.rs (权限合并)
│   ├── state/turn.rs (权限合并)
│   └── app-server/src/command_exec.rs (应用服务器)
│
└── 被调用方:
    ├── seatbelt.rs (macOS Seatbelt 实现)
    ├── seatbelt_permissions.rs (Seatbelt 权限构建)
    ├── landlock.rs (Linux Landlock/seccomp 实现)
    ├── spawn.rs (进程生成)
    └── safety.rs (平台沙箱选择)
```

### 关键函数路径

1. **策略转换**: `SandboxManager::transform()` → `SandboxTransformRequest` → `ExecRequest`
2. **权限合并**: `merge_permission_profiles()` → `merge_macos_seatbelt_profile_extensions()`
3. **权限交集**: `intersect_permission_profiles()` → `intersect_macos_seatbelt_profile_extensions()`
4. **文件系统策略**: `effective_file_system_sandbox_policy()` → `merge_file_system_policy_with_additional_permissions()`
5. **执行入口**: `execute_env()` → `execute_exec_request()` (exec.rs)

---

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::exec` | ExecExpiration、ExecToolCallOutput、SandboxType、StdoutStream、execute_exec_request |
| `crate::landlock` | Linux Landlock 策略构建 |
| `crate::seatbelt` | macOS Seatbelt 策略构建 |
| `crate::spawn` | 环境变量常量、进程生成 |
| `crate::safety` | 平台沙箱选择 |
| `crate::tools::sandboxing` | SandboxablePreference |
| `crate::protocol` | SandboxPolicy、NetworkAccess、ReadOnlyAccess |

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_network_proxy` | NetworkProxy、代理 URL 处理 |
| `codex_protocol` | FileSystemPermissions、NetworkPermissions、PermissionProfile、MacOsSeatbeltProfileExtensions 等 |
| `codex_protocol::permissions` | FileSystemAccessMode、FileSystemPath、FileSystemSandboxEntry、FileSystemSandboxPolicy、NetworkSandboxPolicy |
| `codex_utils_absolute_path` | AbsolutePathBuf |
| `dunce` | 路径规范化 |

### 环境变量

| 变量 | 设置位置 | 用途 |
|------|----------|------|
| `CODEX_SANDBOX` | spawn.rs, seatbelt.rs | 标识沙箱类型 ("seatbelt") |
| `CODEX_SANDBOX_NETWORK_DISABLED` | spawn.rs, mod.rs | 标识网络是否被禁用 |

---

## 风险、边界与改进建议

### 潜在风险

1. **权限升级漏洞**
   - `additional_permissions` 的合并逻辑需要严格审查
   - `merge_permission_profiles` 取并集的策略可能导致意外权限扩大
   - 建议: 增加权限变更的审计日志

2. **路径规范化问题**
   - `normalize_permission_paths` 使用 `dunce::canonicalize`，在符号链接处理上可能存在竞态条件
   - 建议: 考虑使用更安全的路径解析策略

3. **平台特定代码的维护**
   - `#[cfg(target_os = "macos")]` 等条件编译增加了代码复杂度
   - 非 macOS 平台无法编译 macOS 相关代码，可能导致跨平台测试遗漏

4. **Linux Sandbox 可执行文件依赖**
   - `codex_linux_sandbox_exe` 必须存在，否则返回 `MissingLinuxSandboxExecutable` 错误
   - 建议: 提供更友好的错误提示和安装指导

### 边界情况

1. **空权限处理**
   - `PermissionProfile::is_empty()` 用于过滤空权限
   - `normalize_additional_permissions` 会移除空的嵌套配置

2. **沙箱类型回退**
   - 当平台沙箱不可用时，自动回退到 `SandboxType::None`
   - 这可能导致意外的无沙箱执行

3. **Windows 沙箱特殊处理**
   - Windows 沙箱在 `transform()` 中不修改命令，实际沙箱逻辑在执行阶段
   - 这种不一致性可能导致理解困难

### 改进建议

1. **代码结构优化**
   - `mod.rs` 752 行，接近 AGENTS.md 建议的 800 行上限
   - 建议: 将权限合并逻辑提取到独立模块

2. **测试覆盖**
   - 增加跨平台模拟测试
   - 增加权限边界情况的测试

3. **文档完善**
   - 添加更多关于 `SandboxTransformRequest` 字段的文档
   - 说明各种 `SandboxPolicy` 变体的使用场景

4. **错误处理增强**
   - `SandboxTransformError` 目前只有两种变体
   - 建议: 增加更详细的错误类型，如 `InvalidPermissionPath`、`UnsupportedSandboxConfig` 等

5. **性能优化**
   - `dedup_absolute_paths` 使用 `HashSet` 去重，可考虑使用 `IndexSet` 保持顺序
   - 权限合并涉及多次克隆，可考虑使用引用计数

### 安全注意事项

1. **AGENTS.md 明确禁止**: 不要修改 `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` 或 `CODEX_SANDBOX_ENV_VAR` 相关代码
2. **Seatbelt 可执行文件路径**: 硬编码为 `/usr/bin/sandbox-exec`，防止 PATH 注入攻击
3. **权限交集验证**: `intersect_permission_profiles` 用于验证请求权限是否在已授权范围内

---

## 总结

`sandboxing` 模块是 Codex 安全架构的核心，负责将高层次的沙箱策略转换为平台特定的执行参数。其设计考虑了跨平台兼容性（macOS Seatbelt、Linux seccomp/bubblewrap、Windows Restricted Token），同时提供了灵活的权限管理机制（`additional_permissions`）。

模块的主要复杂度来自于：
1. 跨平台抽象的差异处理
2. 权限合并与交集的复杂逻辑
3. 与多个外部模块的协调

理解该模块对于理解 Codex 的安全模型至关重要。
