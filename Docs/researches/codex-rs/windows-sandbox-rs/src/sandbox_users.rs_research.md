# sandbox_users.rs 深度研究文档

## 场景与职责

`sandbox_users.rs` 是 Windows Sandbox 设置助手中的**用户管理模块**，负责创建和管理沙箱专用的 Windows 本地用户账户。该模块在提权设置助手中运行，执行需要管理员权限的用户管理操作。

### 核心职责
1. **用户组管理**：创建和管理 `CodexSandboxUsers` 本地组
2. **用户账户创建**：创建离线/在线沙箱用户账户
3. **密码管理**：生成随机密码并使用 DPAPI 加密存储
4. **SID 解析**：解析用户名到 SID（安全标识符）

## 功能点目的

### 1. 常量定义
```rust
pub const SANDBOX_USERS_GROUP: &str = "CodexSandboxUsers";
const SANDBOX_USERS_GROUP_COMMENT: &str = "Codex sandbox internal group (managed)";
const SID_ADMINISTRATORS: &str = "S-1-5-32-544";
const SID_USERS: &str = "S-1-5-32-545";
const SID_AUTHENTICATED_USERS: &str = "S-1-5-11";
const SID_EVERYONE: &str = "S-1-1-0";
const SID_SYSTEM: &str = "S-1-5-18";
```

### 2. `provision_sandbox_users` - 用户配置主函数
```rust
pub fn provision_sandbox_users(
    codex_home: &Path,
    offline_username: &str,
    online_username: &str,
    log: &mut File,
) -> Result<()>
```
- **流程**：
  1. 确保沙箱用户组存在
  2. 生成两个随机密码（离线/在线用户）
  3. 创建/更新离线用户
  4. 创建/更新在线用户
  5. 使用 DPAPI 加密密码并写入文件

### 3. `ensure_sandbox_user` - 确保用户存在
```rust
pub fn ensure_sandbox_user(username: &str, password: &str, log: &mut File) -> Result<()>
```
- 创建本地用户
- 将用户添加到 `CodexSandboxUsers` 组

### 4. `ensure_local_user` - 本地用户创建/更新
```rust
pub fn ensure_local_user(name: &str, password: &str, log: &mut File) -> Result<()>
```
- **创建**：使用 `NetUserAdd` 创建新用户
- **更新**：如果用户已存在，使用 `NetUserSetInfo`（level 1003）更新密码
- **属性**：
  - 权限：`USER_PRIV_USER`（普通用户）
  - 标志：`UF_SCRIPT | UF_DONT_EXPIRE_PASSWD`（密码永不过期）
- **组成员**：自动添加到 `Users` 组

### 5. `ensure_local_group` - 本地组创建
```rust
pub fn ensure_local_group(name: &str, comment: &str, log: &mut File) -> Result<()>
```
- 使用 `NetLocalGroupAdd` 创建组
- 处理已存在错误（`ERROR_ALIAS_EXISTS`, `NERR_GROUP_EXISTS`）

### 6. `ensure_local_group_member` - 组成员添加
```rust
pub fn ensure_local_group_member(group_name: &str, member_name: &str) -> Result<()>
```
- 使用 `NetLocalGroupAddMembers` 添加成员
- 忽略已存在错误（幂等操作）

### 7. SID 解析函数

#### `resolve_sid`
```rust
pub fn resolve_sid(name: &str) -> Result<Vec<u8>>
```
- 支持已知 SID 字符串直接转换
- 使用 `LookupAccountNameW` 解析用户名
- 处理缓冲区不足，动态调整大小

#### `sid_bytes_to_psid`
```rust
pub fn sid_bytes_to_psid(sid: &[u8]) -> Result<*mut c_void>
```
- 将 SID 字节转换为可用于 API 调用的指针

### 8. 密码生成
```rust
fn random_password() -> String
```
- 长度：24 字符
- 字符集：大小写字母、数字、特殊字符
- 使用 `SmallRng` 从熵源生成

### 9. 凭据存储
```rust
fn write_secrets(
    codex_home: &Path,
    offline_user: &str,
    offline_pwd: &str,
    online_user: &str,
    online_pwd: &str,
) -> Result<()>
```
- 使用 DPAPI 加密密码
- Base64 编码后存储
- 写入 `codex_home/.sandbox-secrets/sandbox_users.json`
- 同时创建 `codex_home/.sandbox/setup_marker.json`

## 具体技术实现

### NetUserAdd 调用
```rust
let info = USER_INFO_1 {
    usri1_name: name_w.as_ptr() as *mut u16,
    usri1_password: pwd_w.as_ptr() as *mut u16,
    usri1_password_age: 0,
    usri1_priv: USER_PRIV_USER,
    usri1_home_dir: std::ptr::null_mut(),
    usri1_comment: std::ptr::null_mut(),
    usri1_flags: UF_SCRIPT | UF_DONT_EXPIRE_PASSWD,
    usri1_script_path: std::ptr::null_mut(),
};
let status = NetUserAdd(
    std::ptr::null(),
    1,  // level
    &info as *const _ as *mut u8,
    std::ptr::null_mut(),
);
```

### NetUserSetInfo 密码更新
```rust
let pw_info = USER_INFO_1003 {
    usri1003_password: pwd_w.as_ptr() as *mut u16,
};
let upd = NetUserSetInfo(
    std::ptr::null(),
    name_w.as_ptr(),
    1003,  // level (password only)
    &pw_info as *const _ as *mut u8,
    std::ptr::null_mut(),
);
```

### DPAPI 加密
```rust
let offline_blob = dpapi_protect(offline_pwd.as_bytes()).map_err(|err| {
    anyhow::Error::new(SetupFailure::new(
        SetupErrorCode::HelperDpapiProtectFailed,
        format!("dpapi protect failed for offline user: {err}"),
    ))
})?;
```

### 文件结构

#### `sandbox_users.json`
```json
{
  "version": 5,
  "offline": {
    "username": "CodexSandboxOffline",
    "password": "base64-encoded-encrypted-password"
  },
  "online": {
    "username": "CodexSandboxOnline",
    "password": "base64-encoded-encrypted-password"
  }
}
```

#### `setup_marker.json`
```json
{
  "version": 5,
  "offline_username": "CodexSandboxOffline",
  "online_username": "CodexSandboxOnline",
  "created_at": "2024-01-15T09:30:45Z",
  "read_roots": [],
  "write_roots": []
}
```

## 关键代码路径与文件引用

### 内部依赖
| 函数 | 来源 | 用途 |
|------|------|------|
| `dpapi_protect` | `codex_windows_sandbox` | 密码加密 |
| `sandbox_dir` | `codex_windows_sandbox` | 目录路径 |
| `sandbox_secrets_dir` | `codex_windows_sandbox` | 密钥目录 |
| `to_wide` | `codex_windows_sandbox` | 字符串转换 |
| `string_from_sid_bytes` | `codex_windows_sandbox` | SID 转换 |
| `SetupFailure` / `SetupErrorCode` | `codex_windows_sandbox` | 错误处理 |
| `SETUP_VERSION` | `codex_windows_sandbox` | 版本常量 |

### 被调用方
| 调用方 | 场景 |
|--------|------|
| 设置助手主函数 | 用户配置阶段 |

### 数据结构
```rust
#[derive(Serialize)]
struct SandboxUserRecord {
    username: String,
    password: String,  // base64-encoded DPAPI blob
}

#[derive(Serialize)]
struct SandboxUsersFile {
    version: u32,
    offline: SandboxUserRecord,
    online: SandboxUserRecord,
}

#[derive(Serialize)]
struct SetupMarker {
    version: u32,
    offline_username: String,
    online_username: String,
    created_at: String,
    read_roots: Vec<PathBuf>,
    write_roots: Vec<PathBuf>,
}
```

## 依赖与外部交互

### Windows API (Netapi32)
- `NetUserAdd`：创建用户
- `NetUserSetInfo`：更新用户信息
- `NetLocalGroupAdd`：创建本地组
- `NetLocalGroupAddMembers`：添加组成员

### Windows API (Advapi32)
- `LookupAccountNameW`：用户名转 SID
- `LookupAccountSidW`：SID 转用户名
- `ConvertStringSidToSidW`：字符串 SID 转 SID
- `GetLengthSid` / `CopySid`：SID 操作

### 外部 Crate
- `base64`：密码编码
- `rand`：随机密码生成
- `serde`：JSON 序列化
- `chrono`：时间戳生成

## 风险、边界与改进建议

### 已知风险

1. **密码泄露**
   - 问题：密码在内存中短暂存在
   - 缓解：尽快加密，减少明文暴露时间
   - 建议：使用 `secrecy` crate 管理敏感数据

2. **用户已存在**
   - 问题：如果用户已存在但由其他程序创建
   - 缓解：更新密码确保一致性
   - 风险：可能覆盖其他用途的账户

3. **DPAPI 绑定**
   - 问题：DPAPI 加密绑定到机器和用户
   - 风险：用户配置文件迁移后无法解密
   - 缓解：使用 `CRYPTPROTECT_LOCAL_MACHINE`

### 边界条件

1. **用户名冲突**：更新现有用户密码
2. **组已存在**：静默处理，继续添加成员
3. **成员已存在**：静默处理
4. **SID 解析失败**：返回错误
5. **DPAPI 失败**：返回 `SetupErrorCode::HelperDpapiProtectFailed`
6. **文件写入失败**：返回相应的 `SetupErrorCode`

### 改进建议

1. **用户验证**
   - 当前：假设用户名未被其他用途使用
   - 建议：验证用户是否由 Codex 创建（检查注释或配置文件）

2. **密码策略**
   - 当前：固定 24 字符随机密码
   - 建议：支持配置密码复杂度策略

3. **审计日志**
   - 当前：仅记录到设置日志
   - 建议：集成 Windows 安全日志

4. **用户清理**
   - 当前：无自动清理机制
   - 建议：提供卸载/清理功能

5. **多机器同步**
   - 当前：每台机器独立用户
   - 建议：支持域环境或漫游配置文件

### 安全最佳实践

1. **最小权限**
   - 用户创建为普通用户（`USER_PRIV_USER`）
   - 非管理员权限

2. **密码永不过期**
   - 避免用户被锁定
   - 密码由系统管理，用户无需知道

3. **组成员控制**
   - 专用组 `CodexSandboxUsers` 便于批量管理
   - 同时加入 `Users` 组确保基本权限

4. **加密存储**
   - 密码使用 DPAPI 加密
   - 仅当前机器可解密

### 错误处理

使用 `SetupFailure` 结构化错误：
- `HelperUserCreateOrUpdateFailed`：用户创建/更新失败
- `HelperUsersGroupCreateFailed`：组创建失败
- `HelperDpapiProtectFailed`：加密失败
- `HelperUsersFileWriteFailed`：文件写入失败
- `HelperSetupMarkerWriteFailed`：标记文件写入失败
