# hide_users.rs 深度研究文档

## 场景与职责

`hide_users.rs` 是 Windows Sandbox 模块中的**用户隐藏管理器**，负责在 Windows 登录界面和文件系统中隐藏沙箱创建的专用用户账户。这是 Windows 平台特有的功能模块（`#![cfg(target_os = "windows")]`）。

### 核心职责
1. **Winlogon 用户列表隐藏**：在注册表中设置标志，使沙箱用户不出现在 Windows 登录界面的用户列表中
2. **用户配置文件目录隐藏**：将沙箱用户的配置文件目录标记为隐藏+系统属性
3. **最佳努力执行**：所有操作都是非阻塞的，失败仅记录日志不影响主流程

## 功能点目的

### 1. `hide_newly_created_users` - 隐藏新创建的用户
```rust
pub fn hide_newly_created_users(usernames: &[String], log_base: &Path)
```
- **触发时机**：沙箱用户创建完成后
- **作用**：在 `HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList` 下为每个用户名创建 DWORD 值 0
- **效果**：用户不会出现在登录界面的用户列表中

### 2. `hide_current_user_profile_dir` - 隐藏当前用户配置文件
```rust
pub fn hide_current_user_profile_dir(log_base: &Path)
```
- **触发时机**：命令运行器以沙箱用户身份首次登录时
- **作用**：将 `%USERPROFILE%` 目录设置为 `HIDDEN | SYSTEM` 属性
- **设计考虑**：Windows 只在用户首次登录时才创建配置文件目录，因此此操作在命令运行器中执行

### 3. `hide_directory` - 目录隐藏实现
```rust
fn hide_directory(path: &Path) -> anyhow::Result<bool>
```
- **属性设置**：`FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM`
- **返回值**：是否实际修改了属性（避免重复记录）

## 具体技术实现

### 注册表操作 (`hide_users_in_winlogon`)

**注册表路径**：
```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList
```

**操作步骤**：
1. 使用 `RegCreateKeyExW` 打开/创建 `UserList` 键
2. 对每个用户名调用 `RegSetValueExW` 设置 DWORD 值 0
3. 使用 `RegCloseKey` 关闭键句柄

**Windows API 调用**：
```rust
RegCreateKeyExW(
    HKEY_LOCAL_MACHINE,
    key_path.as_ptr(),
    0,
    std::ptr::null_mut(),
    REG_OPTION_NON_VOLATILE,
    KEY_WRITE,
    std::ptr::null_mut(),
    &mut key,
    std::ptr::null_mut(),
);
```

### 文件属性操作 (`hide_directory`)

**使用 API**：
- `GetFileAttributesW`：获取当前属性
- `SetFileAttributesW`：设置新属性

**属性标志**：
- `FILE_ATTRIBUTE_HIDDEN` (0x2)：隐藏文件
- `FILE_ATTRIBUTE_SYSTEM` (0x4)：系统文件

**逻辑**：
1. 获取当前属性
2. 检查是否已设置目标属性
3. 如未设置，添加属性标志并应用

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源模块 | 用途 |
|------|----------|------|
| `log_note` | `logging.rs` | 记录操作日志 |
| `to_wide` | `winutil.rs` | 字符串转宽字符 |
| `format_last_error` | `winutil.rs` | 格式化 Windows 错误码 |

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `setup_orchestrator.rs` (间接) | `hide_newly_created_users` | 用户创建后隐藏 |
| `command-runner` | `hide_current_user_profile_dir` | 首次登录时隐藏配置目录 |

### 导出接口
在 `lib.rs` 中导出：
```rust
#[cfg(target_os = "windows")]
pub use hide_users::hide_current_user_profile_dir;
#[cfg(target_os = "windows")]
pub use hide_users::hide_newly_created_users;
```

## 依赖与外部交互

### Windows API 依赖
```rust
use windows_sys::Win32::Storage::FileSystem::GetFileAttributesW;
use windows_sys::Win32::Storage::FileSystem::SetFileAttributesW;
use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_HIDDEN;
use windows_sys::Win32::Storage::FileSystem::FILE_ATTRIBUTE_SYSTEM;
use windows_sys::Win32::System::Registry::*;
```

### 环境依赖
- `USERPROFILE` 环境变量：定位用户配置文件目录
- `HKEY_LOCAL_MACHINE` 访问权限：需要管理员权限修改

### 错误处理策略
所有错误都是**最佳努力**（best-effort）：
- 使用 `if let Err(err) = ...` 模式
- 错误仅记录到日志，不返回错误
- 主流程继续执行

## 风险、边界与改进建议

### 已知风险

1. **权限不足**
   - 问题：非管理员无法修改 `HKEY_LOCAL_MACHINE`
   - 缓解：此模块在提权后的设置助手中调用，确保有管理员权限

2. **注册表键不存在**
   - 问题：`SpecialAccounts\UserList` 键可能不存在
   - 缓解：使用 `RegCreateKeyExW` 自动创建

3. **配置文件目录尚未创建**
   - 问题：首次登录前 `USERPROFILE` 目录不存在
   - 缓解：`hide_current_user_profile_dir` 在命令运行器中执行，此时目录已创建

### 边界条件

1. **空用户名列表**：`hide_newly_created_users` 直接返回，不执行任何操作
2. **环境变量缺失**：`hide_current_user_profile_dir` 直接返回
3. **目录不存在**：`hide_directory` 直接返回
4. **属性已设置**：检测到无需修改时返回 `Ok(false)`，避免重复日志

### 改进建议

1. **延迟隐藏**
   - 当前：`hide_current_user_profile_dir` 每次调用都检查
   - 建议：添加标记文件避免重复检查已隐藏的目录

2. **更细粒度的错误分类**
   - 当前：所有错误统一记录
   - 建议：区分权限错误、路径不存在等不同错误类型

3. **支持更多隐藏选项**
   - 考虑支持隐藏开始菜单中的用户
   - 考虑支持控制面板用户列表隐藏

4. **审计日志**
   - 当前：仅记录成功和失败
   - 建议：记录具体修改了哪些注册表值和文件属性

### 安全考虑

1. **仅隐藏不保护**
   - 隐藏用户列表仅提供视觉保护，不阻止通过用户名/密码登录
   - 配置文件隐藏仅阻止普通浏览，不阻止直接路径访问

2. **注册表权限**
   - 修改 `HKEY_LOCAL_MACHINE` 需要管理员权限
   - 确保此代码仅在提权进程中执行

### 平台限制

- **仅 Windows**：使用 `#[cfg(target_os = "windows")]` 条件编译
- **不适用于 Unix**：Unix 平台无此功能需求（使用不同隔离机制）
