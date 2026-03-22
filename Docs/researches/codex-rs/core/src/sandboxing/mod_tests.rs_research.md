# sandboxing/mod_tests.rs 研究文档

## 场景与职责

`mod_tests.rs` 是 `sandboxing/mod.rs` 模块的单元测试文件，负责验证沙箱系统的核心功能：

1. **沙箱选择逻辑**：验证 `SandboxManager::select_initial()` 根据不同策略正确选择沙箱类型
2. **权限配置处理**：验证附加权限的规范化、合并和交集计算
3. **文件系统策略**：验证受限策略与附加权限的正确合并
4. **网络权限**：验证网络启用/禁用的各种场景
5. **跨平台行为**：通过条件编译测试平台特定功能

该测试模块是确保沙箱系统安全性和正确性的关键保障。

## 功能点目的

### 测试覆盖的功能矩阵

| 功能类别 | 测试函数 | 验证内容 |
|---------|---------|---------|
| 沙箱选择 | `danger_full_access_defaults_to_no_sandbox_without_network_requirements` | 无网络要求时默认无沙箱 |
| 沙箱选择 | `danger_full_access_uses_platform_sandbox_with_network_requirements` | 托管网络强制沙箱 |
| 沙箱选择 | `restricted_file_system_uses_platform_sandbox_without_managed_network` | 受限文件系统使用沙箱 |
| 沙箱选择 | `full_access_restricted_policy_skips_platform_sandbox_when_network_is_enabled` | 全盘写+网络启用跳过沙箱 |
| 沙箱选择 | `root_write_policy_with_carveouts_still_uses_platform_sandbox` | 有排除路径时仍用沙箱 |
| 沙箱选择 | `full_access_restricted_policy_still_uses_platform_sandbox_for_restricted_network` | 受限网络强制沙箱 |
| 权限规范化 | `normalize_additional_permissions_preserves_network` | 网络权限保留 |
| 权限规范化 | `normalize_additional_permissions_canonicalizes_symlinked_write_paths` | 符号链接规范化 |
| 权限规范化 | `normalize_additional_permissions_drops_empty_nested_profiles` | 空配置过滤 |
| 权限合并 | `read_only_additional_permissions_can_enable_network_without_writes` | 只读+网络权限 |
| 权限合并 | `external_sandbox_additional_permissions_can_enable_network` | 外部沙箱网络启用 |
| 权限合并 | `transform_additional_permissions_enable_network_for_external_sandbox` | 转换时网络启用 |
| 权限合并 | `transform_additional_permissions_preserves_denied_entries` | 拒绝条目保留 |
| 权限合并 | `merge_file_system_policy_with_additional_permissions_preserves_unreadable_roots` | 不可读根保留 |
| 权限交集 | `intersect_permission_profiles_preserves_default_macos_grants` | macOS 默认授权保留 |
| 有效策略 | `effective_file_system_sandbox_policy_returns_base_policy_without_additional_permissions` | 无附加权限时返回基础策略 |
| 有效策略 | `effective_file_system_sandbox_policy_merges_additional_write_roots` | 附加写路径合并 |
| 平台特定 | `normalize_additional_permissions_preserves_default_macos_preferences_permission` | macOS 偏好设置保留 |
| 平台特定 | `normalize_additional_permissions_preserves_macos_permissions` | macOS 权限保留 |
| 平台特定 | `effective_permissions_merge_macos_extensions_with_additional_permissions` | macOS 扩展合并 |

## 具体技术实现

### 测试结构

```rust
#[cfg(target_os = "macos")]
use super::EffectiveSandboxPermissions;
use super::SandboxManager;
use super::effective_file_system_sandbox_policy;
#[cfg(target_os = "macos")]
use super::intersect_permission_profiles;
use super::merge_file_system_policy_with_additional_permissions;
use super::normalize_additional_permissions;
use super::sandbox_policy_with_additional_permissions;
use super::should_require_platform_sandbox;
```

测试使用白盒测试方式，直接导入被测模块的私有函数。

### 核心测试用例分析

#### 1. 沙箱选择基础测试

```rust
#[test]
fn danger_full_access_defaults_to_no_sandbox_without_network_requirements() {
    let manager = SandboxManager::new();
    let sandbox = manager.select_initial(
        &FileSystemSandboxPolicy::unrestricted(),  // 无限制文件系统
        NetworkSandboxPolicy::Enabled,              // 网络启用
        SandboxablePreference::Auto,                // 自动模式
        WindowsSandboxLevel::Disabled,
        false,  // 无托管网络要求
    );
    assert_eq!(sandbox, SandboxType::None);  // 期望无沙箱
}
```

**验证逻辑**：当文件系统无限制且无托管网络要求时，即使网络启用也不使用沙箱。

#### 2. 托管网络强制沙箱测试

```rust
#[test]
fn danger_full_access_uses_platform_sandbox_with_network_requirements() {
    let manager = SandboxManager::new();
    let expected = crate::safety::get_platform_sandbox(false).unwrap_or(SandboxType::None);
    let sandbox = manager.select_initial(
        &FileSystemSandboxPolicy::unrestricted(),
        NetworkSandboxPolicy::Enabled,
        SandboxablePreference::Auto,
        WindowsSandboxLevel::Disabled,
        true,  // 有托管网络要求
    );
    assert_eq!(sandbox, expected);  // 强制使用平台沙箱
}
```

**验证逻辑**：`has_managed_network_requirements` 为 true 时，无论其他条件如何都使用平台沙箱。

#### 3. 全盘写权限跳过沙箱测试

```rust
#[test]
fn full_access_restricted_policy_skips_platform_sandbox_when_network_is_enabled() {
    let policy = FileSystemSandboxPolicy::restricted(vec![FileSystemSandboxEntry {
        path: FileSystemPath::Special {
            value: FileSystemSpecialPath::Root,
        },
        access: FileSystemAccessMode::Write,  // 根目录写权限
    }]);

    assert_eq!(
        should_require_platform_sandbox(&policy, NetworkSandboxPolicy::Enabled, false),
        false  // 不需要平台沙箱
    );
}
```

**验证逻辑**：当策略允许全盘写且网络启用时，不需要额外平台沙箱。

#### 4. 有排除路径时仍使用沙箱测试

```rust
#[test]
fn root_write_policy_with_carveouts_still_uses_platform_sandbox() {
    let blocked = AbsolutePathBuf::resolve_path_against_base("blocked", cwd)
        .expect("blocked path");
    let policy = FileSystemSandboxPolicy::restricted(vec![
        FileSystemSandboxEntry {
            path: FileSystemPath::Special {
                value: FileSystemSpecialPath::Root,
            },
            access: FileSystemAccessMode::Write,
        },
        FileSystemSandboxEntry {
            path: FileSystemPath::Path { path: blocked },
            access: FileSystemAccessMode::None,  // 排除路径
        },
    ]);

    assert_eq!(
        should_require_platform_sandbox(&policy, NetworkSandboxPolicy::Enabled, false),
        true  // 仍需要平台沙箱
    );
}
```

**验证逻辑**：虽然有根目录写权限，但存在排除路径（`access: None`），需要平台沙箱来强制执行排除。

#### 5. 符号链接路径规范化测试

```rust
#[cfg(unix)]
#[test]
fn normalize_additional_permissions_canonicalizes_symlinked_write_paths() {
    let temp_dir = TempDir::new().expect("create temp dir");
    let real_root = temp_dir.path().join("real");
    let link_root = temp_dir.path().join("link");
    let write_dir = real_root.join("write");
    std::fs::create_dir_all(&write_dir).expect("create write dir");
    symlink_dir(&real_root, &link_root).expect("create symlinked root");

    let link_write_dir = AbsolutePathBuf::from_absolute_path(link_root.join("write"))
        .expect("link write dir");
    let expected_write_dir = AbsolutePathBuf::from_absolute_path(
        write_dir.canonicalize().expect("canonicalize write dir"),
    )
    .expect("absolute canonical write dir");

    let permissions = normalize_additional_permissions(PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec![]),
            write: Some(vec![link_write_dir]),  // 使用符号链接路径
        }),
        ..Default::default()
    })
    .expect("permissions");

    // 验证符号链接被解析为真实路径
    assert_eq!(
        permissions.file_system,
        Some(FileSystemPermissions {
            read: Some(vec![]),
            write: Some(vec![expected_write_dir]),  // 期望真实路径
        })
    );
}
```

**验证逻辑**：通过符号链接指定的路径在规范化后应解析为真实路径，防止沙箱绕过。

#### 6. 权限交集保留默认授权测试

```rust
#[cfg(target_os = "macos")]
#[test]
fn intersect_permission_profiles_preserves_default_macos_grants() {
    let requested = PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec!["/tmp/requested".try_into().expect("absolute path")]),
            write: None,
        }),
        macos: Some(MacOsSeatbeltProfileExtensions {
            macos_preferences: MacOsPreferencesPermission::ReadWrite,
            macos_automation: MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]),
            macos_launch_services: false,
            macos_accessibility: true,
            macos_calendar: true,
            macos_reminders: false,
            macos_contacts: MacOsContactsPermission::None,
        }),
        ..Default::default()
    };
    let granted = PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(Vec::new()),  // 空列表，不包含请求的路径
            write: None,
        }),
        macos: Some(MacOsSeatbeltProfileExtensions::default()),  // 默认授权
        ..Default::default()
    };

    // 交集结果应保留默认授权
    assert_eq!(
        intersect_permission_profiles(requested, granted),
        PermissionProfile {
            macos: Some(MacOsSeatbeltProfileExtensions::default()),
            ..Default::default()
        }
    );
}
```

**验证逻辑**：当请求的文件系统权限未被授予时，交集结果应仅保留已授予的 macOS 权限（默认值）。

#### 7. 附加权限启用网络测试

```rust
#[test]
fn transform_additional_permissions_enable_network_for_external_sandbox() {
    let manager = SandboxManager::new();
    let exec_request = manager
        .transform(super::SandboxTransformRequest {
            spec: super::CommandSpec {
                sandbox_permissions: super::SandboxPermissions::WithAdditionalPermissions,
                additional_permissions: Some(PermissionProfile {
                    network: Some(NetworkPermissions { enabled: Some(true) }),
                    file_system: Some(FileSystemPermissions {
                        read: Some(vec![path]),
                        write: Some(Vec::new()),
                    }),
                    ..Default::default()
                }),
                ...
            },
            policy: &SandboxPolicy::ExternalSandbox {
                network_access: NetworkAccess::Restricted,  // 基础策略禁用网络
            },
            network_policy: NetworkSandboxPolicy::Restricted,
            ...
        })
        .expect("transform");

    // 附加权限应启用网络
    assert_eq!(
        exec_request.sandbox_policy,
        SandboxPolicy::ExternalSandbox {
            network_access: NetworkAccess::Enabled,
        }
    );
    assert_eq!(
        exec_request.network_sandbox_policy,
        NetworkSandboxPolicy::Enabled
    );
}
```

**验证逻辑**：即使基础策略禁用网络，附加权限可以启用网络访问。

#### 8. 拒绝条目保留测试

```rust
#[test]
fn transform_additional_permissions_preserves_denied_entries() {
    let manager = SandboxManager::new();
    let exec_request = manager
        .transform(super::SandboxTransformRequest {
            spec: super::CommandSpec {
                additional_permissions: Some(PermissionProfile {
                    file_system: Some(FileSystemPermissions {
                        read: None,
                        write: Some(vec![allowed_path.clone()]),
                    }),
                    ..Default::default()
                }),
                ...
            },
            file_system_policy: &FileSystemSandboxPolicy::restricted(vec![
                FileSystemSandboxEntry {
                    path: FileSystemPath::Special {
                        value: FileSystemSpecialPath::Root,
                    },
                    access: FileSystemAccessMode::Read,
                },
                FileSystemSandboxEntry {
                    path: FileSystemPath::Path { path: denied_path.clone() },
                    access: FileSystemAccessMode::None,  // 明确拒绝
                },
            ]),
            ...
        })
        .expect("transform");

    // 验证拒绝条目和允许条目都保留
    assert!(exec_request.file_system_sandbox_policy.entries.contains(&FileSystemSandboxEntry {
        path: FileSystemPath::Path { path: denied_path },
        access: FileSystemAccessMode::None,
    }));
    assert!(exec_request.file_system_sandbox_policy.entries.contains(&FileSystemSandboxEntry {
        path: FileSystemPath::Path { path: allowed_path },
        access: FileSystemAccessMode::Write,
    }));
}
```

**验证逻辑**：合并附加权限时，原有的拒绝条目（`access: None`）必须保留。

#### 9. macOS 权限合并测试

```rust
#[cfg(target_os = "macos")]
#[test]
fn effective_permissions_merge_macos_extensions_with_additional_permissions() {
    let effective_permissions = EffectiveSandboxPermissions::new(
        &SandboxPolicy::ReadOnly { ... },
        Some(&MacOsSeatbeltProfileExtensions {
            macos_preferences: MacOsPreferencesPermission::ReadOnly,
            macos_automation: MacOsAutomationPermission::BundleIds(vec!["com.apple.Calendar"]),
            ...
        }),
        Some(&PermissionProfile {
            macos: Some(MacOsSeatbeltProfileExtensions {
                macos_preferences: MacOsPreferencesPermission::ReadWrite,  // 升级
                macos_automation: MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]),
                macos_launch_services: true,
                macos_accessibility: true,
                macos_calendar: true,
                ...
            }),
            ...
        }),
    );

    // 验证合并结果
    assert_eq!(
        effective_permissions.macos_seatbelt_profile_extensions,
        Some(MacOsSeatbeltProfileExtensions {
            macos_preferences: MacOsPreferencesPermission::ReadWrite,  // 已升级
            macos_automation: MacOsAutomationPermission::BundleIds(vec![
                "com.apple.Calendar",  // 基础
                "com.apple.Notes",     // 附加
            ]),
            macos_launch_services: true,
            macos_accessibility: true,
            macos_calendar: true,
            ...
        })
    );
}
```

**验证逻辑**：macOS 权限扩展正确合并，分级权限升级，Bundle ID 列表合并去重。

## 关键代码路径与文件引用

### 测试文件位置

- **路径**: `codex-rs/core/src/sandboxing/mod_tests.rs`
- **模块声明**: 在 `mod.rs` 末尾通过 `#[path = "mod_tests.rs"]` 引入

### 被测函数映射

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `danger_full_access_*` | `SandboxManager::select_initial` | mod.rs:545 |
| `full_access_restricted_policy_*` | `should_require_platform_sandbox` | mod.rs:515 |
| `normalize_additional_permissions_*` | `normalize_additional_permissions` | mod.rs:150 |
| `intersect_permission_profiles_*` | `intersect_permission_profiles` | mod.rs:230 |
| `read_only_additional_permissions_*` | `sandbox_policy_with_additional_permissions` | mod.rs:445 |
| `transform_additional_permissions_*` | `SandboxManager::transform` | mod.rs:580 |
| `merge_file_system_policy_*` | `merge_file_system_policy_with_additional_permissions` | mod.rs:359 |
| `effective_file_system_sandbox_policy_*` | `effective_file_system_sandbox_policy` | mod.rs:393 |
| `effective_permissions_merge_*` | `EffectiveSandboxPermissions::new` | mod.rs:125 |

### 依赖类型

```rust
use codex_protocol::models::FileSystemPermissions;
use codex_protocol::models::NetworkPermissions;
use codex_protocol::models::PermissionProfile;
use codex_protocol::permissions::FileSystemAccessMode;
use codex_protocol::permissions::FileSystemPath;
use codex_protocol::permissions::FileSystemSandboxEntry;
use codex_protocol::permissions::FileSystemSandboxPolicy;
use codex_protocol::permissions::NetworkSandboxPolicy;
use codex_utils_absolute_path::AbsolutePathBuf;
use dunce::canonicalize;
use pretty_assertions::assert_eq;
use tempfile::TempDir;
```

## 依赖与外部交互

### 测试框架

- **断言库**: `pretty_assertions::assert_eq` - 提供结构化的差异输出
- **临时目录**: `tempfile::TempDir` - 创建隔离的测试环境
- **路径处理**: `dunce::canonicalize` - 跨平台路径规范化

### 平台特定测试

```rust
#[cfg(target_os = "macos")]
```

- macOS 特定测试仅在 macOS 平台上编译运行
- 测试 macOS Seatbelt 权限扩展的合并和交集

```rust
#[cfg(unix)]
```

- Unix 特定测试（包括 Linux 和 macOS）
- 主要用于符号链接相关测试

### 测试工具函数

```rust
#[cfg(unix)]
fn symlink_dir(original: &Path, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(original, link)
}
```

## 风险、边界与改进建议

### 当前测试覆盖度分析

**已充分覆盖**:
- ✅ 沙箱选择的基本逻辑
- ✅ 权限规范化（网络、文件系统、空配置）
- ✅ 文件系统策略合并
- ✅ 网络权限启用/禁用
- ✅ macOS 权限扩展合并（平台特定）

**覆盖不足**:

1. **错误处理路径**
   - 未测试 `SandboxTransformError::MissingLinuxSandboxExecutable`
   - 未测试 `SandboxTransformError::SeatbeltUnavailable`

2. **Windows 沙箱**
   - 无 Windows 特定测试
   - `WindowsSandboxLevel` 和 `windows_sandbox_private_desktop` 测试有限

3. **并发场景**
   - 未测试并发权限操作
   - 未测试 `SandboxManager` 的线程安全性

4. **边界值**
   - 未测试极大数量的路径列表
   - 未测试特殊字符路径
   - 未测试空字符串路径

5. **超时和取消**
   - 未测试 `ExecExpiration` 的各种变体

### 建议增加的测试

```rust
#[test]
fn transform_fails_without_linux_sandbox_exe() {
    let manager = SandboxManager::new();
    let result = manager.transform(super::SandboxTransformRequest {
        sandbox: SandboxType::LinuxSeccomp,
        codex_linux_sandbox_exe: None,  // 未提供
        ...
    });
    assert!(matches!(result, Err(SandboxTransformError::MissingLinuxSandboxExecutable)));
}

#[test]
fn sandbox_manager_is_thread_safe() {
    // 验证 SandboxManager 可以安全地跨线程使用
    use std::sync::Arc;
    use std::thread;
    
    let manager = Arc::new(SandboxManager::new());
    let handles: Vec<_> = (0..10)
        .map(|_| {
            let m = Arc::clone(&manager);
            thread::spawn(move || {
                m.select_initial(...)
            })
        })
        .collect();
    
    for h in handles {
        h.join().unwrap();
    }
}

#[test]
fn normalize_handles_invalid_paths() {
    // 测试无效路径的处理
    let permissions = normalize_additional_permissions(PermissionProfile {
        file_system: Some(FileSystemPermissions {
            read: Some(vec!["relative/path".try_into().unwrap()]),  // 相对路径
            write: None,
        }),
        ..Default::default()
    });
    // 验证行为
}
```

### 测试执行

```bash
# 运行所有沙箱测试
cd codex-rs
cargo test -p codex-core sandboxing::

# 仅运行非平台特定测试
cargo test -p codex-core sandboxing:: -- --skip macos

# 在 macOS 上运行所有测试（包括平台特定）
cargo test -p codex-core sandboxing::
```

### 与主模块的关系

该测试模块是 `mod.rs` 的内联测试模块：

```rust
#[cfg(test)]
#[path = "mod_tests.rs"]
mod tests;
```

优势：
- 测试可以访问私有函数（白盒测试）
- 生产代码与测试代码分离
- 清晰的模块边界

### 测试数据构造模式

测试中使用的一致模式：

1. **临时目录创建**
   ```rust
   let temp_dir = TempDir::new().expect("create temp dir");
   ```

2. **绝对路径构造**
   ```rust
   let path = AbsolutePathBuf::from_absolute_path(
       canonicalize(temp_dir.path()).expect("canonicalize temp dir"),
   )
   .expect("absolute temp dir");
   ```

3. **权限配置构造**
   ```rust
   let permissions = PermissionProfile {
       network: Some(NetworkPermissions { enabled: Some(true) }),
       file_system: Some(FileSystemPermissions { read: Some(vec![path]), write: None }),
       ..Default::default()
   };
   ```

这种模式确保了测试的可重复性和跨平台兼容性。
