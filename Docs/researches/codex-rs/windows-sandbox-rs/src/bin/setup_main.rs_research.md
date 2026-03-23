# setup_main.rs 深度研究文档

## 场景与职责

`setup_main.rs` 是 Codex Windows Sandbox 的**沙箱设置工具入口文件**，作为 `codex-windows-sandbox-setup.exe` 二进制文件的入口点。该可执行文件负责在 Windows 系统上配置沙箱环境，包括用户创建、ACL（访问控制列表）配置、防火墙规则设置等。

### 核心职责

1. **平台适配**：提供 Windows 平台的沙箱设置能力，非 Windows 平台直接 panic
2. **权限提升**：支持以管理员权限运行以执行系统级配置
3. **委托执行**：将实际工作委托给 `setup_main_win.rs` 模块

### 在沙箱架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                    Setup Orchestrator (Parent)                   │
│  - Detects if setup is needed                                    │
│  - Spawns setup_main.exe with or without elevation               │
│  - Handles UAC prompts when necessary                            │
└───────────────────────┬─────────────────────────────────────────┘
                        │ Spawn (potentially elevated)
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                 codex-windows-sandbox-setup.exe                  │
│  - Parses base64-encoded payload                                 │
│  - Provisions sandbox users (CodexSandboxOffline/Online)        │
│  - Applies ACLs to read/write roots                              │
│  - Configures Windows Firewall                                   │
│  - Protects workspace directories                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 平台检测与编译时条件

```rust
#[cfg(target_os = "windows")]
fn main() -> anyhow::Result<()> {
    win::main()
}

#[cfg(not(target_os = "windows"))]
fn main() {
    panic!("codex-windows-sandbox-setup is Windows-only");
}
```

- **Windows 平台**：调用实际的 Windows 实现
- **非 Windows 平台**：编译通过但运行时 panic

### 2. 模块路径重定向

```rust
#[path = "../setup_main_win.rs"]
mod win;
```

使用 `#[path]` 属性将模块指向实际实现文件。

---

## 具体技术实现

### 实际实现：setup_main_win.rs

#### 核心数据结构

```rust
/// Setup payload passed from orchestrator to setup helper
#[derive(Debug, Clone, Deserialize, Serialize)]
struct Payload {
    version: u32,                    // 协议版本（当前为 5）
    offline_username: String,        // 离线沙箱用户名
    online_username: String,         // 在线沙箱用户名
    codex_home: PathBuf,             // Codex 主目录
    command_cwd: PathBuf,            // 命令执行目录
    read_roots: Vec<PathBuf>,        // 需要读取权限的根目录
    write_roots: Vec<PathBuf>,       // 需要写入权限的根目录
    real_user: String,               // 实际用户名称
    #[serde(default)]
    mode: SetupMode,                 // Full 或 ReadAclsOnly
    #[serde(default)]
    refresh_only: bool,              // 是否仅刷新 ACL
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(rename_all = "kebab-case")]
enum SetupMode {
    #[default]
    Full,           // 完整设置（创建用户、配置 ACL、防火墙等）
    ReadAclsOnly,   // 仅配置读取 ACL（用于后台辅助进程）
}
```

#### 主要执行流程

```
main()
  └── real_main()
        ├── 解析 base64 编码的命令行参数
        ├── 验证协议版本
        ├── 创建沙箱目录和日志文件
        └── run_setup()
              ├── SetupMode::ReadAclsOnly → run_read_acl_only()
              └── SetupMode::Full → run_setup_full()
```

#### 完整设置流程 (run_setup_full)

```rust
fn run_setup_full(payload: &Payload, log: &mut File, sbx_dir: &Path) -> Result<()> {
    // 1. 配置沙箱用户（如果不是仅刷新模式）
    if !refresh_only {
        provision_sandbox_users(...)?;
        hide_newly_created_users(&users, sbx_dir);
    }
    
    // 2. 解析各种 SID
    let offline_sid = resolve_sid(&payload.offline_username)?;
    let sandbox_group_sid = resolve_sandbox_users_group_sid()?;
    let caps = load_or_create_cap_sids(&payload.codex_home)?;
    
    // 3. 配置防火墙（阻止离线用户出站连接）
    firewall::ensure_offline_outbound_block(&offline_sid_str, log)?;
    
    // 4. 启动读取 ACL 辅助进程（异步处理大量读取 ACL）
    spawn_read_acl_helper(payload, log)?;
    
    // 5. 应用写入 ACL（使用多线程并行处理）
    apply_write_acls_parallel(...)?;
    
    // 6. 锁定沙箱目录
    lock_sandbox_dir(&sandbox_bin_dir, ...)?;
    lock_sandbox_dir(&sandbox_dir, ...)?;
    lock_sandbox_dir(&sandbox_secrets_dir, ...)?;  // 拒绝访问
    
    // 7. 保护工作区目录（.codex 和 .agents）
    protect_workspace_codex_dir(&payload.command_cwd, workspace_psid)?;
    protect_workspace_agents_dir(&payload.command_cwd, workspace_psid)?;
}
```

#### 用户配置流程

```rust
pub fn provision_sandbox_users(
    codex_home: &Path,
    offline_username: &str,
    online_username: &str,
    log: &mut File,
) -> Result<()> {
    // 1. 确保沙箱用户组存在
    ensure_sandbox_users_group(log)?;
    
    // 2. 生成随机密码
    let offline_password = random_password();
    let online_password = random_password();
    
    // 3. 创建或更新用户
    ensure_sandbox_user(offline_username, &offline_password, log)?;
    ensure_sandbox_user(online_username, &online_password, log)?;
    
    // 4. 使用 DPAPI 加密密码并保存
    write_secrets(codex_home, ...)?;
}
```

#### ACL 应用策略

**读取 ACL 处理**：
- 检查内置组（Users、Authenticated Users、Everyone）是否已有权限
- 检查沙箱用户组是否已有权限
- 如没有，授予 `FILE_GENERIC_READ | FILE_GENERIC_EXECUTE` 权限

**写入 ACL 处理**：
- 使用多线程并行处理多个写入根目录
- 为沙箱用户组和能力 SID 授予完整写入权限
- 权限包括：`FILE_GENERIC_READ | FILE_GENERIC_WRITE | FILE_GENERIC_EXECUTE | DELETE | FILE_DELETE_CHILD`

#### 读取 ACL 辅助进程

```rust
fn spawn_read_acl_helper(payload: &Payload, _log: &mut File) -> Result<()> {
    let mut read_payload = payload.clone();
    read_payload.mode = SetupMode::ReadAclsOnly;
    read_payload.refresh_only = true;
    
    // 使用 mutex 确保只有一个辅助进程在运行
    let payload_json = serde_json::to_vec(&read_payload)?;
    let payload_b64 = BASE64.encode(payload_json);
    
    Command::new(&exe)
        .arg(payload_b64)
        .creation_flags(0x08000000) // CREATE_NO_WINDOW
        .spawn()?;
}
```

使用命名互斥锁 `Local\CodexSandboxReadAcl` 防止多个辅助进程同时运行。

---

## 关键代码路径与文件引用

### 文件依赖关系

```
src/bin/setup_main.rs
    └── src/setup_main_win.rs (实际实现)
        ├── src/sandbox_users.rs (用户管理)
        │   └── Windows NetUserAdd/NetLocalGroupAdd APIs
        ├── src/read_acl_mutex.rs (ACL 互斥锁)
        ├── src/firewall.rs (防火墙配置)
        ├── src/token.rs (SID/令牌操作)
        ├── src/acl.rs (ACL 操作)
        ├── src/cap.rs (能力 SID 管理)
        ├── src/workspace_acl.rs (工作区 ACL)
        └── src/setup_error.rs (错误处理)
            └── src/lib.rs (公共 API)
```

### 关键 Windows API 使用

| API 类别 | 具体 API | 用途 |
|---------|---------|------|
| 用户管理 | `NetUserAdd`, `NetUserSetInfo` | 创建/更新沙箱用户 |
| 用户管理 | `NetLocalGroupAdd`, `NetLocalGroupAddMembers` | 创建用户组、添加成员 |
| 安全 | `LookupAccountNameW`, `LookupAccountSidW` | SID 解析 |
| 安全 | `ConvertStringSidToSidW` | 字符串 SID 转换 |
| 安全 | `SetEntriesInAclW`, `SetNamedSecurityInfoW` | ACL 设置 |
| 同步 | `CreateMutexW`, `OpenMutexW` | 读取 ACL 互斥锁 |
| 加密 | `CryptProtectData` (via DPAPI) | 密码加密存储 |

### 错误处理体系

```rust
pub struct SetupFailure {
    pub code: SetupErrorCode,
    pub message: String,
}

pub enum SetupErrorCode {
    HelperRequestArgsFailed = 1,
    HelperSandboxDirCreateFailed,
    HelperLogFailed,
    HelperUserProvisionFailed,
    HelperSidResolveFailed,
    HelperCapabilitySidFailed,
    HelperFirewallRuleCreateOrAddFailed,
    HelperReadAclHelperSpawnFailed,
    HelperSandboxLockFailed,
    HelperUserCreateOrUpdateFailed,
    HelperUsersGroupCreateFailed,
    HelperDpapiProtectFailed,
    HelperUsersFileWriteFailed,
    HelperSetupMarkerWriteFailed,
    HelperUnknownError,
    // Orchestrator errors...
}
```

---

## 依赖与外部交互

### 编译依赖

```toml
[[bin]]
name = "codex-windows-sandbox-setup"
path = "src/bin/setup_main.rs"
```

### 运行时依赖

1. **调用方**：由 `setup_orchestrator.rs` 通过 `run_elevated_setup()` 或 `run_setup_refresh()` 调用
2. **Windows 系统服务**：
   - SAM（Security Accounts Manager）- 用户管理
   - Windows Firewall - 防火墙规则
   - NTFS - ACL 配置
3. **特权要求**：
   - 用户创建：需要管理员权限
   - ACL 配置：需要管理员权限或文件所有者
   - 防火墙配置：需要管理员权限

### 输入/输出

**输入**：
- 命令行参数：base64 编码的 JSON payload
- 环境变量：`USERNAME`（用于确定真实用户）

**输出**：
- 日志文件：`%CODEX_HOME%/.sandbox/setup.log`
- 错误报告：`%CODEX_HOME%/.sandbox/setup_error.json`
- 用户凭证：`%CODEX_HOME%/.sandbox-secrets/sandbox_users.json`（DPAPI 加密）
- 设置标记：`%CODEX_HOME%/.sandbox/setup_marker.json`
- 进程退出码：0 表示成功，非 0 表示失败

### 目录结构

```
%CODEX_HOME%/
├── .sandbox/
│   ├── setup.log              # 设置日志
│   ├── setup_error.json       # 错误报告（如有）
│   ├── setup_marker.json      # 版本标记
│   └── notes.log              # 运行时笔记
├── .sandbox-bin/              # 沙箱二进制文件（只读访问）
└── .sandbox-secrets/          # 加密凭证（真实用户独占访问）
    └── sandbox_users.json     # DPAPI 加密的用户凭证
```

---

## 风险、边界与改进建议

### 已知风险

1. **权限提升风险**
   - 需要管理员权限执行敏感操作
   - UAC 绕过可能导致安全风险
   - 错误处理不当可能留下部分配置状态

2. **凭证安全**
   - 使用 DPAPI 加密用户密码，但依赖于当前用户账户
   - 如果用户账户被破解，凭证可能泄露
   - 密码在内存中以明文形式短暂存在

3. **ACL 配置风险**
   - 错误的 ACL 配置可能导致权限过宽或过窄
   - 并发 ACL 操作可能导致竞态条件
   - 大量 ACL 操作可能影响文件系统性能

4. **防火墙规则冲突**
   - 与其他安全软件可能产生冲突
   - 规则优先级可能影响预期行为

### 边界条件

| 场景 | 处理方式 |
|------|----------|
| 用户已存在 | 更新密码，保留用户 |
| 用户组已存在 | 忽略创建错误（ERROR_ALIAS_EXISTS） |
| ACL 已存在 | 检查现有权限，必要时添加 |
| 读取 ACL 辅助进程已在运行 | 通过互斥锁检测，跳过启动 |
| 目录不存在 | 创建目录或跳过（取决于场景） |
| 版本不匹配 | 返回 SetupErrorCode::HelperRequestArgsFailed |
| 非管理员运行需要提升的操作 | 由 orchestrator 使用 ShellExecuteExW 提升 |

### 改进建议

1. **安全性增强**
   - 考虑使用 Windows Credential Manager 替代 DPAPI
   - 实现更细粒度的权限控制（如使用 AppContainer）
   - 添加配置审计日志，记录所有权限变更

2. **可靠性改进**
   - 实现配置回滚机制，失败时自动清理
   - 添加配置验证步骤，确保所有设置生效
   - 改进错误报告，包含更多上下文信息

3. **性能优化**
   - 优化 ACL 批量操作，减少系统调用
   - 实现增量更新，避免重复配置
   - 考虑使用异步 I/O 处理文件操作

4. **可观测性**
   - 添加结构化日志（JSON 格式）
   - 导出设置指标（配置时间、成功率等）
   - 添加详细的事件追踪

5. **用户体验**
   - 提供更清晰的进度反馈
   - 优化 UAC 提示频率
   - 添加配置预览功能

### 测试建议

1. **单元测试**：
   - SID 解析和转换
   - ACL 计算逻辑
   - Payload 序列化/反序列化

2. **集成测试**：
   - 完整设置流程
   - 刷新模式
   - 错误恢复

3. **安全测试**：
   - 权限边界验证
   - 凭证加密验证
   - ACL 有效性检查

4. **压力测试**：
   - 大量目录的 ACL 配置
   - 并发设置调用
   - 长时间运行稳定性
