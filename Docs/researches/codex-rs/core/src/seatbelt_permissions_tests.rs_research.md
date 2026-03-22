# seatbelt_permissions_tests.rs 研究文档

## 场景与职责

本文件是 `seatbelt_permissions.rs` 的配套测试模块，负责**验证 macOS Seatbelt 权限扩展策略生成逻辑的正确性**。通过全面的单元测试确保各种权限配置正确转换为 SBPL 策略语句。

**核心职责**：
- 验证 Preferences 权限的读写策略生成
- 验证 Automation 权限的各种模式（All、BundleIds）
- 验证 Launch Services、Accessibility、Calendar、Reminders 权限
- 验证 Contacts 权限的读写差异
- 确保默认扩展配置符合预期

## 功能点目的

### 1. Preferences 权限测试
验证 `MacOsPreferencesPermission` 的不同级别生成正确的策略：
- `ReadOnly` 仅生成读取相关子句
- `ReadWrite` 额外生成写入相关子句

### 2. Automation 权限测试
验证 `MacOsAutomationPermission` 的两种模式：
- `All` 生成无限制的 `appleevent-send`
- `BundleIds` 生成带目标限制的规则，并验证归一化逻辑

### 3. 其他权限测试
- `Launch Services` - 验证 Mach 服务和 `lsopen`
- `Accessibility` - 验证 `axserver` 查找
- `Calendar` - 验证 `CalendarAgent` 查找
- `Reminders` - 验证 `CalendarAgent` 和 `remindd` 查找

### 4. Contacts 权限测试
验证 `MacOsContactsPermission` 的详细差异：
- `ReadOnly` 的文件读取和 Mach 查找
- `ReadWrite` 的额外写入权限和安全守护进程访问

### 5. 默认配置测试
验证 `MacOsSeatbeltProfileExtensions::default()` 生成预期的默认策略。

## 具体技术实现

### 测试结构

```rust
use super::{
    MacOsAutomationPermission,
    MacOsContactsPermission,
    MacOsPreferencesPermission,
    MacOsSeatbeltProfileExtensions,
    build_seatbelt_extensions,
};
```

### 测试用例详解

#### 1. Preferences 只读测试
```rust
#[test]
fn preferences_read_only_emits_read_clauses_only() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_preferences: MacOsPreferencesPermission::ReadOnly,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("(allow user-preference-read)"));
    assert!(!policy.policy.contains("(allow user-preference-write)"));
}
```

**验证点**：
- 包含 `user-preference-read`
- 不包含 `user-preference-write`

#### 2. Preferences 读写测试
```rust
#[test]
fn preferences_read_write_emits_write_clauses() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_preferences: MacOsPreferencesPermission::ReadWrite,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("(allow user-preference-read)"));
    assert!(policy.policy.contains("(allow user-preference-write)"));
    assert!(policy.policy.contains(
        "(allow ipc-posix-shm-write-create (ipc-posix-name-prefix \"apple.cfprefs.\"))"
    ));
}
```

**验证点**：
- 包含读写权限
- 包含 POSIX shared memory 写入

#### 3. Automation All 测试
```rust
#[test]
fn automation_all_emits_unscoped_appleevents() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_automation: MacOsAutomationPermission::All,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("(allow appleevent-send)"));
    assert!(policy.policy.contains("com.apple.coreservices.appleevents"));
}
```

**验证点**：
- 包含无限制的 `appleevent-send`
- 包含 Apple Events 服务查找

#### 4. Automation BundleIds 测试
```rust
#[test]
fn automation_bundle_ids_are_normalized_and_scoped() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_automation: MacOsAutomationPermission::BundleIds(vec![
            " com.apple.Notes ".to_string(),    // 带空格，应 trim
            "com.apple.Calendar".to_string(),
            "bad bundle".to_string(),           // 无效，应过滤
            "com.apple.Notes".to_string(),      // 重复，应去重
        ]),
        ..Default::default()
    });
    
    // 验证有效 bundle ID 存在
    assert!(policy.policy.contains("(appleevent-destination \"com.apple.Calendar\")"));
    assert!(policy.policy.contains("(appleevent-destination \"com.apple.Notes\")"));
    
    // 验证无效的被过滤
    assert!(!policy.policy.contains("bad bundle"));
    
    // 验证重复只出现一次（通过计数或模式匹配）
}
```

**验证点**：
- Trim 处理
- 无效 bundle ID 过滤
- 重复去重

#### 5. Launch Services 测试
```rust
#[test]
fn launch_services_emit_launch_clauses() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_launch_services: true,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("com.apple.coreservices.launchservicesd"));
    assert!(policy.policy.contains("com.apple.lsd.mapdb"));
    assert!(policy.policy.contains("com.apple.coreservices.quarantine-resolver"));
    assert!(policy.policy.contains("com.apple.lsd.modifydb"));
    assert!(policy.policy.contains("(allow lsopen)"));
}
```

#### 6. Accessibility 和 Calendar 测试
```rust
#[test]
fn accessibility_and_calendar_emit_mach_lookups() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_accessibility: true,
        macos_calendar: true,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("com.apple.axserver"));
    assert!(policy.policy.contains("com.apple.CalendarAgent"));
}
```

#### 7. Reminders 测试
```rust
#[test]
fn reminders_emit_calendar_agent_and_remindd_lookups() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_reminders: true,
        ..Default::default()
    });
    
    assert!(policy.policy.contains("com.apple.CalendarAgent"));
    assert!(policy.policy.contains("com.apple.remindd"));
}
```

#### 8. Contacts 只读测试
```rust
#[test]
fn contacts_read_only_emit_contacts_read_clauses() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_contacts: MacOsContactsPermission::ReadOnly,
        ..Default::default()
    });
    
    // 文件访问
    assert!(policy.policy.contains("(subpath \"/System/Library/Address Book Plug-Ins\")"));
    assert!(policy.policy.contains("(subpath (param \"ADDRESSBOOK_DIR\"))"));
    
    // Mach 服务
    assert!(policy.policy.contains("com.apple.contactsd.persistence"));
    assert!(policy.policy.contains("com.apple.accountsd.accountmanager"));
    
    // 不应包含安全守护进程
    assert!(!policy.policy.contains("com.apple.securityd.xpc"));
    
    // 验证参数
    assert!(policy.dir_params.iter().any(|(key, _)| key == "ADDRESSBOOK_DIR"));
}
```

#### 9. Contacts 读写测试
```rust
#[test]
fn contacts_read_write_emit_write_clauses() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
        macos_contacts: MacOsContactsPermission::ReadWrite,
        ..Default::default()
    });
    
    // 额外写入路径
    assert!(policy.policy.contains("(subpath \"/var/folders\")"));
    assert!(policy.policy.contains("(subpath \"/private/var/folders\")"));
    
    // 安全守护进程访问
    assert!(policy.policy.contains("com.apple.securityd.xpc"));
}
```

#### 10. 默认配置测试
```rust
#[test]
fn default_extensions_emit_preferences_read_only_policy() {
    let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions::default());
    
    assert!(policy.policy.contains("(allow user-preference-read)"));
    assert!(!policy.policy.contains("(allow user-preference-write)"));
}
```

## 关键代码路径与文件引用

### 被测试的函数
```rust
// seatbelt_permissions.rs
pub(crate) fn build_seatbelt_extensions(
    extensions: &MacOsSeatbeltProfileExtensions,
) -> SeatbeltExtensionPolicy

fn normalized_extensions(...) -> MacOsSeatbeltProfileExtensions
fn normalize_bundle_ids(...) -> Vec<String>
fn is_valid_bundle_id(...) -> bool
fn addressbook_dir() -> Option<PathBuf>
```

### 测试模块声明
```rust
// seatbelt_permissions.rs (line 190-192)
#[cfg(test)]
#[path = "seatbelt_permissions_tests.rs"]
mod tests;
```

### 依赖类型
```rust
use super::{  // 被测函数和类型
    MacOsAutomationPermission,
    MacOsContactsPermission,
    MacOsPreferencesPermission,
    MacOsSeatbeltProfileExtensions,
    build_seatbelt_extensions,
};
```

## 依赖与外部交互

### 测试依赖
| 依赖 | 用途 |
|-----|------|
| `super::*` | 被测模块的所有导出 |
| `pretty_assertions::assert_eq` | 清晰的测试失败输出 |

### 被测代码
- `seatbelt_permissions.rs` 的所有公共和 crate 可见函数

### 无外部 IO
- 纯计算逻辑测试，无副作用
- 不访问文件系统、网络或环境变量

## 风险、边界与改进建议

### 潜在风险

1. **字符串匹配脆弱性**
   - 测试依赖特定的策略字符串格式
   - 策略格式变更可能导致测试失败

2. **覆盖不完整**
   - 缺少对 `dir_params` 内容的详细验证
   - 缺少对策略整体结构的验证

3. **边界情况**
   - 缺少空 bundle ID 列表测试
   - 缺少超长 bundle ID 测试
   - 缺少特殊字符 bundle ID 测试

### 边界限制

1. **静态验证**
   - 仅验证生成的策略字符串
   - 不验证策略在 Seatbelt 中的实际效果

2. **平台限制**
   - 测试在任何平台运行，但策略仅用于 macOS
   - 无法验证 macOS 特定行为

3. **无集成测试**
   - 不测试与 `seatbelt.rs` 的集成
   - 不测试实际沙盒执行

### 改进建议

1. **增强验证**
   ```rust
   // 建议：验证策略结构
   #[test]
   fn generated_policy_is_valid_sbpl_syntax() {
       let policy = build_seatbelt_extensions(&complex_config());
       // 使用 SBPL 解析器验证语法
       assert!(sbpl::parse(&policy.policy).is_ok());
   }
   ```

2. **参数化测试**
   ```rust
   // 使用 rstest 减少重复
   #[rstest]
   #[case(MacOsPreferencesPermission::ReadOnly, vec!["user-preference-read"], vec!["user-preference-write"])]
   #[case(MacOsPreferencesPermission::ReadWrite, vec!["user-preference-read", "user-preference-write"], vec![])]
   fn test_preferences_permissions(
       #[case] permission: MacOsPreferencesPermission,
       #[case] should_contain: Vec<&str>,
       #[case] should_not_contain: Vec<&str>,
   ) { ... }
   ```

3. **边界测试**
   ```rust
   #[test]
   fn empty_bundle_ids_result_in_no_automation() {
       let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
           macos_automation: MacOsAutomationPermission::BundleIds(vec![]),
           ..Default::default()
       });
       assert!(!policy.policy.contains("appleevent-send"));
   }
   
   #[test]
   fn all_invalid_bundle_ids_filtered() {
       let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
           macos_automation: MacOsAutomationPermission::BundleIds(vec![
               "a".to_string(),      // 太短
               "no dot".to_string(), // 无点号
           ]),
           ..Default::default()
       });
       assert!(!policy.policy.contains("appleevent-send"));
   }
   ```

4. **快照测试**
   ```rust
   #[test]
   fn complex_extensions_snapshot() {
       let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
           macos_preferences: MacOsPreferencesPermission::ReadWrite,
           macos_automation: MacOsAutomationPermission::All,
           macos_launch_services: true,
           macos_accessibility: true,
           macos_calendar: true,
           macos_reminders: true,
           macos_contacts: MacOsContactsPermission::ReadWrite,
       });
       
       insta::assert_snapshot!(policy.policy);
   }
   ```

5. **性能测试**
   ```rust
   #[test]
   fn large_bundle_id_list_performance() {
       let bundle_ids: Vec<String> = (0..1000)
           .map(|i| format!("com.example.app{}", i))
           .collect();
       
       let start = Instant::now();
       let policy = build_seatbelt_extensions(&MacOsSeatbeltProfileExtensions {
           macos_automation: MacOsAutomationPermission::BundleIds(bundle_ids),
           ..Default::default()
       });
       let elapsed = start.elapsed();
       
       assert!(elapsed < Duration::from_millis(100));
       assert!(policy.policy.len() < 100_000); // 策略大小限制
   }
   ```

6. **文档测试**
   ```rust
   /// Builds Seatbelt policy extensions from configuration.
   ///
   /// # Examples
   ///
   /// ```
   /// use codex_core::seatbelt_permissions::build_seatbelt_extensions;
   /// use codex_protocol::models::MacOsSeatbeltProfileExtensions;
   ///
   /// let extensions = MacOsSeatbeltProfileExtensions {
   ///     macos_calendar: true,
   ///     ..Default::default()
   /// };
   /// let policy = build_seatbelt_extensions(&extensions);
   /// assert!(policy.policy.contains("com.apple.CalendarAgent"));
   /// ```
   pub(crate) fn build_seatbelt_extensions(...) -> SeatbeltExtensionPolicy { ... }
   ```
