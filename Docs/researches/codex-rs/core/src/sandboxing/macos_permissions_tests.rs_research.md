# macos_permissions_tests.rs 研究文档

## 场景与职责

`macos_permissions_tests.rs` 是 `macos_permissions.rs` 模块的单元测试文件，负责验证 macOS Seatbelt 权限扩展的合并（union）和交集（intersect）逻辑的正确性。该测试模块确保：

1. **权限合并的正确性**：验证权限配置合并时取最宽松权限的逻辑
2. **权限交集的正确性**：验证权限请求与已授予权限的交集计算
3. **权限不降级保证**：验证高权限不会被低权限配置覆盖
4. **Bundle ID 处理**：验证 Bundle ID 列表的合并与交集逻辑

该测试模块仅在 macOS 平台上编译运行（`#[cfg(all(test, target_os = "macos"))]`）。

## 功能点目的

### 测试覆盖的功能点

| 测试函数 | 验证功能 |
|---------|---------|
| `merge_extensions_widens_permissions` | 完整权限配置合并流程 |
| `union_macos_preferences_permission_does_not_downgrade` | 偏好设置权限不降级 |
| `union_macos_automation_permission_all_is_dominant` | All 权限的覆盖性 |
| `intersect_macos_automation_permission_keeps_common_bundle_ids` | Bundle ID 交集计算 |
| `intersect_macos_seatbelt_profile_extensions_preserves_default_grant` | 默认授权保留 |
| `union_macos_contacts_permission_does_not_downgrade` | 通讯录权限不降级 |

## 具体技术实现

### 测试结构

```rust
use super::intersect_macos_automation_permission;
use super::intersect_macos_seatbelt_profile_extensions;
use super::merge_macos_seatbelt_profile_extensions;
use super::union_macos_automation_permission;
use super::union_macos_contacts_permission;
use super::union_macos_preferences_permission;
```

测试直接导入被测模块的私有函数，进行白盒测试。

### 核心测试用例分析

#### 1. 完整权限合并测试 (`merge_extensions_widens_permissions`)

**测试场景**：基础配置与请求配置合并

```rust
let base = MacOsSeatbeltProfileExtensions {
    macos_preferences: MacOsPreferencesPermission::ReadOnly,
    macos_automation: MacOsAutomationPermission::BundleIds(vec!["com.apple.Calendar"]),
    macos_launch_services: false,
    macos_accessibility: false,
    macos_calendar: false,
    macos_reminders: false,
    macos_contacts: MacOsContactsPermission::ReadOnly,
};

let requested = MacOsSeatbeltProfileExtensions {
    macos_preferences: MacOsPreferencesPermission::ReadWrite,  // 升级
    macos_automation: MacOsAutomationPermission::BundleIds(vec![
        "com.apple.Notes",      // 新增
        "com.apple.Calendar",   // 重复
    ]),
    macos_launch_services: true,   // 开启
    macos_accessibility: true,     // 开启
    macos_calendar: true,          // 开启
    macos_reminders: true,         // 开启
    macos_contacts: MacOsContactsPermission::ReadWrite,  // 升级
};
```

**验证点**：
- 分级权限升级：ReadOnly → ReadWrite
- Bundle ID 合并去重：Calendar + Notes，且 Calendar 不重复
- 布尔权限 OR：false → true

#### 2. 权限不降级测试 (`union_macos_preferences_permission_does_not_downgrade`)

```rust
let base = MacOsPreferencesPermission::ReadWrite;
let requested = MacOsPreferencesPermission::ReadOnly;
let merged = union_macos_preferences_permission(&base, &requested);
assert_eq!(merged, MacOsPreferencesPermission::ReadWrite);  // 保持高级别
```

**关键验证**：即使请求的权限更低，合并结果仍保持原有高权限。

#### 3. All 权限覆盖测试 (`union_macos_automation_permission_all_is_dominant`)

```rust
let base = MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]);
let requested = MacOsAutomationPermission::All;
let merged = union_macos_automation_permission(&base, &requested);
assert_eq!(merged, MacOsAutomationPermission::All);  // All 覆盖一切
```

#### 4. Bundle ID 交集测试 (`intersect_macos_automation_permission_keeps_common_bundle_ids`)

```rust
let requested = MacOsAutomationPermission::BundleIds(vec![
    "com.apple.Notes",
    "com.apple.Calendar",
]);
let granted = MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]);
let intersected = intersect_macos_automation_permission(&requested, &granted);
assert_eq!(intersected, MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]));
```

**验证点**：只保留共同存在的 Bundle ID。

#### 5. 默认授权保留测试 (`intersect_macos_seatbelt_profile_extensions_preserves_default_grant`)

```rust
let requested = MacOsSeatbeltProfileExtensions { /* 各种权限请求 */ };
let granted = MacOsSeatbeltProfileExtensions::default();  // 全部默认
let intersected = intersect_macos_seatbelt_profile_extensions(Some(requested), Some(granted));
assert_eq!(intersected, Some(MacOsSeatbeltProfileExtensions::default()));
```

**验证点**：当授予的权限是默认值时，交集结果也是默认值。

## 关键代码路径与文件引用

### 测试文件位置

- **路径**: `codex-rs/core/src/sandboxing/macos_permissions_tests.rs`
- **模块声明**: 在 `macos_permissions.rs` 末尾通过 `#[path = "macos_permissions_tests.rs"]` 引入

### 被测函数映射

| 测试函数 | 被测函数 | 所在文件 |
|---------|---------|---------|
| `merge_extensions_widens_permissions` | `merge_macos_seatbelt_profile_extensions` | macos_permissions.rs:10 |
| `union_macos_preferences_permission_does_not_downgrade` | `union_macos_preferences_permission` | macos_permissions.rs:71 |
| `union_macos_automation_permission_all_is_dominant` | `union_macos_automation_permission` | macos_permissions.rs:97 |
| `intersect_macos_automation_permission_keeps_common_bundle_ids` | `intersect_macos_automation_permission` | macos_permissions.rs:122 |
| `intersect_macos_seatbelt_profile_extensions_preserves_default_grant` | `intersect_macos_seatbelt_profile_extensions` | macos_permissions.rs:41 |
| `union_macos_contacts_permission_does_not_downgrade` | `union_macos_contacts_permission` | macos_permissions.rs:82 |

### 依赖类型

```rust
use codex_protocol::models::MacOsAutomationPermission;
use codex_protocol::models::MacOsContactsPermission;
use codex_protocol::models::MacOsPreferencesPermission;
use codex_protocol::models::MacOsSeatbeltProfileExtensions;
use pretty_assertions::assert_eq;
```

## 依赖与外部交互

### 测试框架

- **断言库**: `pretty_assertions::assert_eq` - 提供差异化的测试失败输出
- **标准测试**: 使用 Rust 内置 `#[test]` 属性

### 数据模型依赖

所有测试数据来自 `codex_protocol::models`：
- `MacOsSeatbeltProfileExtensions` - 权限配置结构体
- `MacOsPreferencesPermission` - 偏好设置权限枚举
- `MacOsContactsPermission` - 通讯录权限枚举
- `MacOsAutomationPermission` - 自动化权限枚举

### 平台限制

```rust
#[cfg(all(test, target_os = "macos"))]
```

- 仅在测试模式下编译
- 仅在 macOS 平台上编译

## 风险、边界与改进建议

### 当前测试覆盖度

**已覆盖场景**:
- ✅ 完整权限配置合并
- ✅ 分级权限不降级
- ✅ All 权限覆盖性
- ✅ Bundle ID 交集
- ✅ 默认授权保留
- ✅ 通讯录权限不降级

**未覆盖场景**:

1. **空 Bundle ID 列表处理**
   - 未测试 `BundleIds([])` 与 `None` 的转换

2. **交集为空的情况**
   - 未测试当 Bundle ID 无交集时返回 `None` 的场景

3. **边界值测试**
   - 未测试极大数量的 Bundle ID 性能
   - 未测试特殊字符 Bundle ID

4. **错误输入处理**
   - 未测试无效 Bundle ID 格式（但验证逻辑在 seatbelt_permissions.rs）

### 建议增加的测试

```rust
#[test]
fn intersect_macos_automation_permission_empty_result_becomes_none() {
    let requested = MacOsAutomationPermission::BundleIds(vec!["com.apple.Notes"]);
    let granted = MacOsAutomationPermission::BundleIds(vec!["com.apple.Calendar"]);
    let intersected = intersect_macos_automation_permission(&requested, &granted);
    assert_eq!(intersected, MacOsAutomationPermission::None);
}

#[test]
fn union_macos_automation_permission_dedupes_bundle_ids() {
    let base = MacOsAutomationPermission::BundleIds(vec![
        "com.apple.Notes",
        "com.apple.Notes",  // 重复
    ]);
    let requested = MacOsAutomationPermission::BundleIds(vec![
        "com.apple.Notes",  // 与 base 重复
        "com.apple.Calendar",
    ]);
    let merged = union_macos_automation_permission(&base, &requested);
    // 验证去重后只有 2 个
    if let MacOsAutomationPermission::BundleIds(ids) = merged {
        assert_eq!(ids.len(), 2);
    }
}
```

### 测试执行

```bash
# 在 macOS 上运行测试
cd codex-rs
cargo test -p codex-core macos_permissions

# 运行所有沙箱相关测试
cargo test -p codex-core sandboxing
```

### 与主模块的关系

该测试模块是 `macos_permissions.rs` 的内联测试模块，通过 `#[path]` 属性关联：

```rust
#[cfg(all(test, target_os = "macos"))]
#[path = "macos_permissions_tests.rs"]
mod tests;
```

这种组织方式：
- 保持生产代码与测试代码分离
- 允许测试访问私有函数（白盒测试）
- 条件编译确保非 macOS 平台不编译 macOS 特定测试
