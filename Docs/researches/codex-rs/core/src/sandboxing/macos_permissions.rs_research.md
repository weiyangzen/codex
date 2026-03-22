# macos_permissions.rs 研究文档

## 场景与职责

`macos_permissions.rs` 是 Codex 沙箱系统的 macOS 特定权限处理模块，负责处理 macOS Seatbelt 沙箱配置文件扩展（Profile Extensions）的合并、交集计算。该模块主要服务于以下场景：

1. **权限配置合并**：当基础配置与附加权限配置（如技能系统或用户自定义配置）需要合并时，计算最宽松的权限并集
2. **权限请求验证**：当用户或技能请求特定 macOS 权限时，与已授予权限进行交集计算，确保不超出授权范围
3. **Seatbelt 策略生成**：为 macOS Seatbelt 沙箱生成具体的权限策略片段

该模块是 `codex-core` crate 的一部分，仅在 macOS 平台上编译使用（通过 `#[cfg(target_os = "macos")]` 条件编译）。

## 功能点目的

### 1. 权限配置合并 (`merge_macos_seatbelt_profile_extensions`)

**目的**：将两个 `MacOsSeatbeltProfileExtensions` 配置合并，取最宽松的权限并集。

**设计原则**：
- 布尔权限（如 `macos_launch_services`）使用逻辑 OR
- 分级权限（如 `macos_preferences`）取较高等级
- Bundle ID 列表使用集合合并去重

### 2. 权限配置交集 (`intersect_macos_seatbelt_profile_extensions`)

**目的**：计算请求的权限与已授予权限的交集，用于权限验证。

**设计原则**：
- 布尔权限使用逻辑 AND
- 分级权限取较低等级
- Bundle ID 列表只保留共同存在的 ID

### 3. 分级权限处理

模块处理三种分级权限类型：
- `MacOsPreferencesPermission`: None < ReadOnly < ReadWrite
- `MacOsContactsPermission`: None < ReadOnly < ReadWrite  
- `MacOsAutomationPermission`: None < BundleIds < All

## 具体技术实现

### 关键数据结构

```rust
// 来自 codex_protocol::models
pub struct MacOsSeatbeltProfileExtensions {
    pub macos_preferences: MacOsPreferencesPermission,  // 系统偏好设置访问
    pub macos_automation: MacOsAutomationPermission,      // AppleScript/自动化
    pub macos_launch_services: bool,                      // 启动服务
    pub macos_accessibility: bool,                        // 辅助功能
    pub macos_calendar: bool,                             // 日历访问
    pub macos_reminders: bool,                            // 提醒事项
    pub macos_contacts: MacOsContactsPermission,          // 通讯录
}
```

### 核心算法实现

#### 合并算法 (`union`)

```rust
fn union_macos_preferences_permission(
    base: &MacOsPreferencesPermission,
    requested: &MacOsPreferencesPermission,
) -> MacOsPreferencesPermission {
    if base < requested {
        requested.clone()
    } else {
        base.clone()
    }
}
```

分级权限通过 `PartialOrd` 比较，取较大值（更宽松）。

#### 自动化权限合并

```rust
fn union_macos_automation_permission(
    base: &MacOsAutomationPermission,
    requested: &MacOsAutomationPermission,
) -> MacOsAutomationPermission {
    match (base, requested) {
        // All 权限覆盖一切
        (MacOsAutomationPermission::All, _) | (_, MacOsAutomationPermission::All) => {
            MacOsAutomationPermission::All
        }
        // None 让位于对方
        (MacOsAutomationPermission::None, _) => requested.clone(),
        (_, MacOsAutomationPermission::None) => base.clone(),
        // BundleIds 合并去重
        (BundleIds(base_ids), BundleIds(requested_ids)) => {
            MacOsAutomationPermission::BundleIds(
                base_ids.iter()
                    .chain(requested_ids.iter())
                    .cloned()
                    .collect::<BTreeSet<_>>()  // 去重
                    .into_iter()
                    .collect()
            )
        }
    }
}
```

#### 交集算法 (`intersect`)

```rust
fn intersect_macos_automation_permission(
    requested: &MacOsAutomationPermission,
    granted: &MacOsAutomationPermission,
) -> MacOsAutomationPermission {
    match (requested, granted) {
        // 任一方为 None，结果为 None
        (_, MacOsAutomationPermission::None) | (MacOsAutomationPermission::None, _) => {
            MacOsAutomationPermission::None
        }
        // 请求 All，返回授予的内容
        (MacOsAutomationPermission::All, granted) => granted.clone(),
        // 授予 All，返回请求的内容
        (BundleIds(requested), MacOsAutomationPermission::All) => BundleIds(requested.clone()),
        // BundleIds 取交集
        (BundleIds(requested), BundleIds(granted)) => {
            let bundle_ids = requested
                .iter()
                .filter(|bundle_id| granted.contains(bundle_id))
                .cloned()
                .collect::<Vec<String>>();
            if bundle_ids.is_empty() {
                MacOsAutomationPermission::None
            } else {
                MacOsAutomationPermission::BundleIds(bundle_ids)
            }
        }
    }
}
```

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 用途 |
|------|------|------|
| `merge_macos_seatbelt_profile_extensions` | 10-39 | 合并两个权限配置 |
| `intersect_macos_seatbelt_profile_extensions` | 41-65 | 计算权限交集 |
| `union_macos_preferences_permission` | 71-80 | 合并偏好设置权限 |
| `union_macos_contacts_permission` | 82-91 | 合并通讯录权限 |
| `union_macos_automation_permission` | 97-120 | 合并自动化权限 |
| `intersect_macos_automation_permission` | 122-150 | 计算自动化权限交集 |

### 调用方

1. **`mod.rs` 中的 `EffectiveSandboxPermissions::new`** (line 125-148)
   - 使用 `merge_macos_seatbelt_profile_extensions` 合并基础配置与附加权限

2. **`mod.rs` 中的 `intersect_permission_profiles`** (line 230-282)
   - 使用 `intersect_macos_seatbelt_profile_extensions` 验证权限请求

3. **`mod.rs` 中的 `merge_permission_profiles`** (line 177-228)
   - 使用 `merge_macos_seatbelt_profile_extensions` 合并权限配置

### 被调用方（依赖）

1. **`codex_protocol::models`** - 权限类型定义
   - `MacOsSeatbeltProfileExtensions`
   - `MacOsPreferencesPermission`
   - `MacOsContactsPermission`
   - `MacOsAutomationPermission`

## 依赖与外部交互

### 外部 Crate 依赖

```rust
use codex_protocol::models::MacOsAutomationPermission;
use codex_protocol::models::MacOsContactsPermission;
use codex_protocol::models::MacOsPreferencesPermission;
use codex_protocol::models::MacOsSeatbeltProfileExtensions;
```

### 平台限制

- **仅 macOS**: 整个模块通过 `#![cfg(target_os = "macos")]` 限制
- **测试模块**: `macos_permissions_tests.rs` 同样仅在 macOS 上编译

### 与 Seatbelt 策略生成的关系

该模块计算的权限配置最终传递给 `seatbelt_permissions.rs` 中的 `build_seatbelt_extensions` 函数，生成具体的 Seatbelt SBPL（Sandbox Profile Language）策略代码。

流程：
```
PermissionProfile → MacOsSeatbeltProfileExtensions → merge/intersect → 
seatbelt_permissions::build_seatbelt_extensions → SBPL 策略代码
```

## 风险、边界与改进建议

### 潜在风险

1. **权限升级风险**
   - 合并算法总是取更宽松的权限，如果基础配置被恶意修改，可能导致权限提升
   - 建议：在合并前验证基础配置的签名或来源

2. **Bundle ID 验证不足**
   - 当前仅验证 Bundle ID 格式（长度、字符、包含点号），但不验证其真实性
   - 恶意 Bundle ID 可能被用于权限绕过

3. **空集合处理**
   - 当 BundleIds 交集为空时降级为 `None`，这可能与某些场景下"明确拒绝"的语义不符

### 边界情况

1. **None 与空 BundleIds 的区别**
   - `None` 表示"无权限"
   - `BundleIds([])` 在序列化后可能被反序列化为 `None`
   - 代码中通过 `normalize_bundle_ids` 处理，空列表统一转为 `None`

2. **PartialOrd 依赖**
   - 分级权限的合并依赖 `PartialOrd` 实现，需确保枚举定义顺序与权限等级一致
   - 当前顺序：None < ReadOnly < ReadWrite（正确）

### 改进建议

1. **增加权限审计日志**
   ```rust
   // 建议添加
   tracing::info!(
       "Merging macOS permissions: base={:?}, requested={:?}, result={:?}",
       base, requested, result
   );
   ```

2. **Bundle ID 白名单验证**
   - 考虑增加系统 Bundle ID 白名单验证，防止随意指定 Bundle ID

3. **单元测试增强**
   - 当前测试覆盖基本场景，建议增加：
     - 大规模 Bundle ID 列表性能测试
     - 并发合并操作测试
     - 边界值测试（空字符串、特殊字符等）

4. **代码简化**
   - `union_macos_preferences_permission` 和 `union_macos_contacts_permission` 逻辑相同，可考虑泛型化
   - 但当前显式实现更利于代码可读性和编译优化

### 相关测试文件

- `macos_permissions_tests.rs` - 本模块的单元测试
- 测试覆盖：合并、交集、权限不降级、Bundle ID 交集等场景
