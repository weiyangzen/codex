# identity.rs 深度研究文档

## 场景与职责

`identity.rs` 是 Windows Sandbox 模块中的**身份认证管理器**，负责管理沙箱用户的身份验证和凭据获取。它是连接沙箱策略执行与 Windows 用户账户系统的关键桥梁。

### 核心职责
1. **沙箱设置状态检查**：验证沙箱用户是否已正确配置
2. **凭据获取**：根据策略（在线/离线）选择合适的沙箱用户凭据
3. **凭据解密**：使用 DPAPI 解密存储的密码
4. **设置触发**：在需要时触发提权设置流程

## 功能点目的

### 1. `SandboxIdentity` / `SandboxCreds` - 凭据结构
```rust
struct SandboxIdentity {
    username: String,
    password: String,
}

pub struct SandboxCreds {
    pub username: String,
    pub password: String,
}
```
- `SandboxIdentity`：内部使用的完整凭据结构
- `SandboxCreds`：对外暴露的凭据结构（用于进程创建）

### 2. `sandbox_setup_is_complete` - 设置完整性检查
```rust
pub fn sandbox_setup_is_complete(codex_home: &Path) -> bool
```
- **用途**：快速检查沙箱是否已配置完成
- **检查内容**：
  1. 设置标记文件存在且版本匹配
  2. 用户文件存在且版本匹配
- **使用场景**：启动前预检，避免不必要的设置流程

### 3. `require_logon_sandbox_creds` - 核心凭据获取
```rust
pub fn require_logon_sandbox_creds(
    policy: &SandboxPolicy,
    policy_cwd: &Path,
    command_cwd: &Path,
    env_map: &HashMap<String, String>,
    codex_home: &Path,
) -> Result<SandboxCreds>
```
- **用途**：获取用于登录的沙箱用户凭据
- **流程**：
  1. 收集所需的读写根目录
  2. 检查现有设置标记和用户文件
  3. 如无效，触发提权设置流程
  4. 执行设置刷新（非提权）
  5. 返回解密后的凭据

### 4. `select_identity` - 策略驱动的用户选择
```rust
fn select_identity(policy: &SandboxPolicy, codex_home: &Path) -> Result<Option<SandboxIdentity>>
```
- **逻辑**：
  - 无网络访问权限 → 选择 `offline` 用户
  - 有网络访问权限 → 选择 `online` 用户
- **密码解密**：使用 `decode_password` 通过 DPAPI 解密

### 5. `decode_password` - 密码解密
```rust
fn decode_password(record: &SandboxUserRecord) -> Result<String>
```
- **流程**：
  1. Base64 解码
  2. DPAPI 解密
  3. UTF-8 字符串转换

## 具体技术实现

### 文件加载与验证

#### `load_marker` - 加载设置标记
```rust
fn load_marker(codex_home: &Path) -> Result<Option<SetupMarker>>
```
- 读取 `codex_home/.sandbox/setup_marker.json`
- 处理文件不存在和解析错误（返回 `None` 而非错误）
- 使用 `debug_log` 记录调试信息

#### `load_users` - 加载用户配置
```rust
fn load_users(codex_home: &Path) -> Result<Option<SandboxUsersFile>>
```
- 读取 `codex_home/.sandbox-secrets/sandbox_users.json`
- 包含离线/在线用户的用户名和加密密码

### 版本匹配逻辑

```rust
// SetupMarker
pub fn version_matches(&self) -> bool {
    self.version == SETUP_VERSION  // 当前版本为 5
}

// SandboxUsersFile
pub fn version_matches(&self) -> bool {
    self.version == SETUP_VERSION
}
```

### 设置触发决策

```rust
let mut identity = match load_marker(codex_home)? {
    Some(marker) if marker.version_matches() => {
        // 标记有效，尝试选择身份
        select_identity(policy, codex_home)?
    }
    _ => {
        setup_reason = Some("sandbox setup marker missing or incompatible".to_string());
        None
    }
};

if identity.is_none() {
    // 触发提权设置
    run_elevated_setup(...)?;
    identity = select_identity(policy, codex_home)?;
}
```

## 关键代码路径与文件引用

### 内部依赖
| 函数/模块 | 来源 | 用途 |
|-----------|------|------|
| `dpapi::unprotect` | `dpapi.rs` | 解密密码 |
| `setup::gather_read_roots` | `setup_orchestrator.rs` | 收集读权限根目录 |
| `setup::gather_write_roots` | `setup_orchestrator.rs` | 收集写权限根目录 |
| `run_elevated_setup` | `setup_orchestrator.rs` | 执行提权设置 |
| `run_setup_refresh` | `setup_orchestrator.rs` | 执行设置刷新 |
| `debug_log` | `logging.rs` | 调试日志 |

### 数据结构依赖
```rust
use crate::setup::SetupMarker;
use crate::setup::SandboxUserRecord;
use crate::setup::SandboxUsersFile;
use crate::policy::SandboxPolicy;
```

### 被调用方
| 调用方 | 函数 | 场景 |
|--------|------|------|
| `elevated_impl.rs` | `require_logon_sandbox_creds` | 获取沙箱用户凭据 |
| `lib.rs` | `sandbox_setup_is_complete` | 导出供外部检查 |
| 外部模块 | `require_logon_sandbox_creds` | 通过 lib.rs 导出 |

### 导出接口
```rust
#[cfg(target_os = "windows")]
pub use identity::require_logon_sandbox_creds;
#[cfg(target_os = "windows")]
pub use identity::sandbox_setup_is_complete;
```

## 依赖与外部交互

### 外部 Crate
- `anyhow`：错误处理和上下文
- `base64`：密码 Base64 解码
- `serde_json`：配置文件解析
- `std::collections::HashMap`：环境变量映射

### 文件系统交互
- 读取设置标记文件（`setup_marker.json`）
- 读取用户配置文件（`sandbox_users.json`）

### 加密依赖
- **DPAPI**（Data Protection API）：Windows 平台加密服务
- 使用 `CRYPTPROTECT_LOCAL_MACHINE` 标志，允许提权和非提权进程互相解密

## 风险、边界与改进建议

### 已知风险

1. **密码泄露风险**
   - 问题：解密后的密码在内存中以明文形式存在
   - 缓解：密码仅在必要时解密，使用后尽快释放
   - 建议：考虑使用 `secrecy` crate 包装敏感字符串

2. **版本不兼容**
   - 问题：SETUP_VERSION 变更后，旧设置被视为无效
   - 缓解：强制重新设置，确保兼容性
   - 注意：这可能导致用户体验中断

3. **DPAPI 依赖**
   - 问题：DPAPI 加密绑定到机器和用户
   - 风险：用户配置文件迁移后可能无法解密
   - 缓解：使用 `CRYPTPROTECT_LOCAL_MACHINE` 减少用户绑定

### 边界条件

1. **文件不存在**：返回 `Ok(None)`，触发重新设置
2. **JSON 解析失败**：记录调试日志，返回 `Ok(None)`
3. **密码解密失败**：返回错误，设置流程失败
4. **UTF-8 转换失败**：返回错误，密码格式损坏

### 改进建议

1. **凭据缓存**
   - 当前：每次调用都重新读取和解密
   - 建议：添加内存缓存，减少文件 I/O 和 DPAPI 调用

2. **更细粒度的错误处理**
   - 当前：解析错误统一返回 None
   - 建议：区分"文件不存在"和"文件损坏"，后者应报告错误

3. **密码轮换**
   - 当前：密码创建后固定不变
   - 建议：定期轮换密码，增强安全性

4. **多用户支持**
   - 当前：仅支持离线/在线两个固定用户
   - 建议：考虑支持动态创建的用户池

5. **异步设置**
   - 当前：`run_elevated_setup` 是同步阻塞调用
   - 建议：考虑异步设置流程，避免阻塞主线程

### 安全最佳实践

1. **最小权限原则**
   - 离线用户：无网络访问权限
   - 在线用户：有网络访问权限
   - 通过不同用户隔离权限

2. **密码复杂度**
   - 查看 `sandbox_users.rs` 中的 `random_password` 实现
   - 使用 24 字符随机密码，包含大小写字母、数字和特殊字符

3. **安全存储**
   - 密码使用 DPAPI 加密后存储
   - 存储在 `codex_home/.sandbox-secrets/` 目录
   - 该目录应具有严格的 ACL 限制

### 调试与监控

- 使用 `debug_log` 记录设置标记和用户文件的加载状态
- 设置原因（`setup_reason`）记录到日志，便于故障排查
- 可通过 `SBX_DEBUG=1` 环境变量启用详细日志
