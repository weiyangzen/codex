# seatbelt_permissions.rs 研究文档

## 场景与职责

本文件负责**构建 macOS Seatbelt 沙盒的权限扩展策略**。它将高层的 `MacOsSeatbeltProfileExtensions` 配置转换为具体的 SBPL（Seatbelt Profile Language）规则，支持 Contacts、Calendar、Automation 等 macOS 特定权限。

**核心职责**：
- 将权限配置转换为 SBPL 策略语句
- 支持 Preferences（用户偏好设置）访问
- 支持 Automation（Apple Events）控制
- 支持 Launch Services、Accessibility、Calendar、Reminders、Contacts
- 管理权限特定的目录参数

## 功能点目的

### 1. 用户偏好设置 (`macos_preferences`)
支持访问和修改 macOS 用户偏好设置：
- `None` - 无访问
- `ReadOnly` - 只读访问（`user-preference-read`）
- `ReadWrite` - 读写访问（包括 POSIX shared memory 写入）

### 2. 自动化控制 (`macos_automation`)
控制 Apple Events 发送，用于自动化其他应用程序：
- `None` - 不允许
- `All` - 允许所有 Apple Events
- `BundleIds(Vec<String>)` - 仅允许特定应用

### 3. 启动服务 (`macos_launch_services`)
允许使用 Launch Services 打开文件和应用程序：
- 与 `lsd`（launchservicesd）通信
- 支持 `lsopen` 操作

### 4. 辅助功能 (`macos_accessibility`)
允许访问辅助功能 API：
- 与 `com.apple.axserver` 通信

### 5. 日历和提醒事项 (`macos_calendar`, `macos_reminders`)
允许访问 CalendarAgent 和 remindd 服务。

### 6. 通讯录 (`macos_contacts`)
支持通讯录访问：
- `None` - 无访问
- `ReadOnly` - 只读访问
- `ReadWrite` - 读写访问（包括 `/var/folders` 写入）

## 具体技术实现

### 数据结构

```rust
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub(crate) struct SeatbeltExtensionPolicy {
    pub(crate) policy: String,           // 生成的 SBPL 策略
    pub(crate) dir_params: Vec<(String, PathBuf)>,  // 参数化的目录路径
}
```

### 核心函数

#### `build_seatbelt_extensions`
```rust
pub(crate) fn build_seatbelt_extensions(
    extensions: &MacOsSeatbeltProfileExtensions,
) -> SeatbeltExtensionPolicy
```

**处理流程**：
```
1. 归一化扩展配置
   └── normalize_bundle_ids() - 去重和验证 bundle ID

2. 构建策略子句
   ├── macos_preferences → IPC + Mach + user-preference-*
   ├── macos_automation → appleevent-send（可能带目标限制）
   ├── macos_launch_services → lsopen + lsd 查找
   ├── macos_accessibility → axserver 查找
   ├── macos_calendar → CalendarAgent 查找
   ├── macos_reminders → CalendarAgent + remindd 查找
   └── macos_contacts → 文件访问 + Mach 查找 + ADDRESSBOOK_DIR 参数

3. 组装策略
   └── 合并所有子句，添加注释头
```

### 权限实现详解

#### Preferences 权限
```rust
MacOsPreferencesPermission::ReadOnly => {
    // POSIX shared memory 读取
    "(allow ipc-posix-shm-read* (ipc-posix-name-prefix \"apple.cfprefs.\"))"
    // cfprefsd 守护进程查找
    "(allow mach-lookup (global-name \"com.apple.cfprefsd.daemon") ...)"
    // 用户偏好读取
    "(allow user-preference-read)"
}
MacOsPreferencesPermission::ReadWrite => {
    // ... 以上所有 ...
    // 用户偏好写入
    "(allow user-preference-write)"
    // POSIX shared memory 写入
    "(allow ipc-posix-shm-write-data ...)"
    "(allow ipc-posix-shm-write-create ...)"
}
```

#### Automation 权限
```rust
MacOsAutomationPermission::All => {
    "(allow mach-lookup (global-name \"com.apple.coreservices.appleevents\"))"
    "(allow appleevent-send)"  // 无限制
}
MacOsAutomationPermission::BundleIds(bundle_ids) => {
    "(allow mach-lookup ...)"
    "(allow appleevent-send
       (appleevent-destination \"com.apple.Notes\")
       (appleevent-destination \"com.apple.Calendar\"))"
}
```

#### Contacts 权限
```rust
MacOsContactsPermission::ReadOnly => {
    // 地址簿插件目录
    "(allow file-read* (subpath \"/System/Library/Address Book Plug-Ins\"))"
    // 用户地址簿目录（参数化）
    "(allow file-read* (subpath (param \"ADDRESSBOOK_DIR\")))"
    // 多个 Mach 服务
    "(allow mach-lookup (global-name \"com.apple.tccd\") ...)"
}
MacOsContactsPermission::ReadWrite => {
    // ... 以上所有 ...
    // 额外写入权限
    "(allow file-write* (subpath \"/var/folders\"))"
    "(allow file-write* (subpath \"/private/var/folders\"))"
    // 安全守护进程
    "(allow mach-lookup (global-name \"com.apple.securityd.xpc\"))"
}
```

### Bundle ID 处理

#### 归一化
```rust
fn normalize_bundle_ids(bundle_ids: &[String]) -> Vec<String> {
    let mut unique = BTreeSet::new();
    for bundle_id in bundle_ids {
        let candidate = bundle_id.trim();
        if is_valid_bundle_id(candidate) {
            unique.insert(candidate.to_string());
        }
    }
    unique.into_iter().collect()
}
```

#### 验证规则
```rust
fn is_valid_bundle_id(bundle_id: &str) -> bool {
    if bundle_id.len() < 3 || !bundle_id.contains('.') {
        return false;
    }
    bundle_id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_')
}
```

规则：
- 至少 3 个字符
- 必须包含 `.`
- 只允许字母、数字、`.`、`-`、`_`

### 目录参数

```rust
fn addressbook_dir() -> Option<PathBuf> {
    Some(dirs::home_dir()?.join("Library/Application Support/AddressBook"))
}
```

生成参数：
```
-DADDRESSBOOK_DIR=/Users/<user>/Library/Application Support/AddressBook
```

## 关键代码路径与文件引用

### 调用关系
```
seatbelt.rs
  └── create_seatbelt_command_args_for_policies_with_extensions()
        └── build_seatbelt_extensions()
              └── SeatbeltExtensionPolicy { policy, dir_params }
```

### 依赖类型
```rust
// 输入（来自 protocol）
pub use codex_protocol::models::{
    MacOsAutomationPermission,
    MacOsContactsPermission,
    MacOsPreferencesPermission,
    MacOsSeatbeltProfileExtensions,
};

// 输出
pub(crate) struct SeatbeltExtensionPolicy {
    pub(crate) policy: String,
    pub(crate) dir_params: Vec<(String, PathBuf)>,
}
```

### 相关文件
- `seatbelt.rs` - 主策略构建，使用本模块输出
- `seatbelt_permissions_tests.rs` - 单元测试
- `protocol/src/models.rs` - 权限类型定义

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `codex_protocol::models::*` | 权限配置类型 |
| `dirs::home_dir()` | 获取用户主目录 |
| `std::collections::BTreeSet` | Bundle ID 去重 |

### 系统服务
本文件引用的 macOS 系统服务：

| 服务 | 用途 |
|-----|------|
| `com.apple.cfprefsd.*` | 用户偏好设置 |
| `com.apple.coreservices.appleevents` | Apple Events |
| `com.apple.coreservices.launchservicesd` | 启动服务 |
| `com.apple.axserver` | 辅助功能 |
| `com.apple.CalendarAgent` | 日历 |
| `com.apple.remindd` | 提醒事项 |
| `com.apple.contactsd.*` | 通讯录 |
| `com.apple.tccd.*` | 透明同意与控制（隐私权限） |

### 无外部 IO（除 home_dir）
- 主要进行字符串处理
- 仅通过 `dirs::home_dir()` 访问文件系统

## 风险、边界与改进建议

### 潜在风险

1. **Bundle ID 注入**
   - 用户提供的 bundle ID 直接嵌入策略
   - 需要确保验证规则足够严格

2. **权限升级**
   - `ReadWrite` 权限可能允许修改系统设置
   - Contacts 写入涉及安全守护进程访问

3. **策略注入**
   - 虽然 bundle ID 有验证，但其他参数可能有问题
   - 需要确保所有用户输入都经过验证

### 边界限制

1. **macOS 专属**
   - 仅适用于 macOS Seatbelt 沙盒
   - 其他平台需要不同实现

2. **静态策略**
   - 策略在进程启动时确定
   - 无法动态调整权限

3. **服务依赖性**
   - 依赖特定 macOS 版本的服务名称
   - 系统升级可能破坏策略

### 改进建议

1. **增强验证**
   ```rust
   // 建议：限制 bundle ID 长度
   const MAX_BUNDLE_ID_LEN: usize = 256;
   
   // 建议：验证 bundle ID 格式（反向域名）
   fn is_valid_bundle_id(bundle_id: &str) -> bool {
       // 当前实现...
       // 添加：检查不以 . 开头或结尾
       // 添加：检查没有连续的 .
   }
   ```

2. **策略优化**
   - 合并重复的 Mach 查找规则
   - 按字母顺序排序规则便于阅读

3. **错误处理**
   ```rust
   // 建议：记录无效的 bundle ID
   for bundle_id in bundle_ids {
       if !is_valid_bundle_id(bundle_id) {
           warn!("Invalid bundle ID filtered: {}", bundle_id);
       }
   }
   ```

4. **可观测性**
   - 记录生成的策略摘要
   - 记录权限扩展的使用情况

5. **文档完善**
   - 为每个权限级别添加详细说明
   - 提供配置示例

6. **测试增强**
   - 添加边界 bundle ID 测试
   - 添加策略注入尝试测试
   - 添加性能测试（大量 bundle ID）

7. **版本兼容性**
   - 检测 macOS 版本，适配不同服务名称
   - 提供向后兼容的策略变体
