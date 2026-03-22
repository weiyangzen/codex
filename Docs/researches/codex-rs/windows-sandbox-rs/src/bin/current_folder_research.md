# Windows Sandbox-rs src/bin 目录研究文档

## 目录

- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 整体定位

`codex-rs/windows-sandbox-rs/src/bin/` 目录包含两个 Windows 专用的可执行二进制入口点，是 Codex CLI 在 Windows 平台上实现**特权级沙箱隔离**的核心组件。这两个二进制文件与主 CLI 形成"双进程架构"：

- **主 CLI 进程**：以普通用户权限运行，负责 UI 交互和协调
- **沙箱辅助进程**：以提升的权限（或不同的用户上下文）运行，执行实际的沙箱操作

### 两个二进制文件的职责划分

| 二进制文件 | 主要职责 | 运行上下文 |
|-----------|---------|-----------|
| `codex-windows-sandbox-setup.exe` | 沙箱环境初始化、用户创建、ACL 配置、防火墙规则设置 | 需要管理员权限（UAC 提升） |
| `codex-command-runner.exe` | 在沙箱用户上下文中执行命令、处理 IPC 通信、流式传输 stdout/stderr | 以沙箱用户身份运行（通过 `CreateProcessWithLogonW`） |

### 解决的问题

1. **权限边界**：Windows 的权限模型要求修改系统级安全设置（如创建用户、修改 ACL）需要管理员权限，但主 CLI 不应长期以管理员身份运行
2. **进程隔离**：通过创建专用的沙箱用户（`CodexSandboxOffline`/`CodexSandboxOnline`）实现进程级隔离
3. **文件系统隔离**：通过 Capability SID 和 ACL 实现细粒度的文件访问控制
4. **网络隔离**：通过 Windows 防火墙规则限制沙箱用户的网络访问

---

## 功能点目的

### 1. codex-windows-sandbox-setup（设置二进制）

#### 核心功能

```rust
// 主要入口: src/bin/setup_main.rs -> src/setup_main_win.rs
pub fn main() -> Result<()> {
    // 1. 解析 Base64 编码的 payload 参数
    // 2. 初始化日志系统
    // 3. 根据模式执行不同逻辑
    match payload.mode {
        SetupMode::ReadAclsOnly => run_read_acl_only(payload, log),
        SetupMode::Full => run_setup_full(payload, log, sbx_dir),
    }
}
```

#### 功能模块

| 模块 | 目的 | 关键操作 |
|-----|------|---------|
| **用户管理** | 创建和管理沙箱专用用户 | `provision_sandbox_users()` - 创建 `CodexSandboxOffline` 和 `CodexSandboxOnline` 用户，密码使用 DPAPI 加密存储 |
| **组管理** | 组织沙箱用户权限 | `ensure_sandbox_users_group()` - 创建 `CodexSandboxUsers` 本地组 |
| **防火墙配置** | 实现网络隔离 | `firewall::ensure_offline_outbound_block()` - 为离线用户添加入站/出站阻止规则 |
| **ACL 配置** | 文件系统访问控制 | `apply_read_acls()` / `ensure_allow_write_aces()` - 为读取根目录和写入根目录配置 ACL |
| **目录锁定** | 保护沙箱内部文件 | `lock_sandbox_dir()` - 使用显式 ACL 保护 `.sandbox`、`.sandbox-bin`、`.sandbox-secrets` 目录 |
| **工作区保护** | 防止工作区元数据被篡改 | `protect_workspace_codex_dir()` / `protect_workspace_agents_dir()` - 保护 `.codex` 和 `.agents` 目录 |

#### 双模式设计

```rust
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(rename_all = "kebab-case")]
enum SetupMode {
    #[default]
    Full,           // 完整设置：用户创建 + ACL 配置
    ReadAclsOnly,   // 仅 ACL 刷新：用于后台辅助进程
}
```

- **Full 模式**：首次设置或需要创建用户时运行，需要 UAC 提升
- **ReadAclsOnly 模式**：后台 ACL 辅助进程使用，仅刷新读取权限 ACL

### 2. codex-command-runner（命令运行器）

#### 核心功能

```rust
// 主要入口: src/bin/command_runner.rs -> src/elevated/command_runner_win.rs
pub fn main() -> Result<()> {
    // 1. 解析 --pipe-in 和 --pipe-out 参数（命名管道路径）
    // 2. 连接到父进程创建的命名管道
    // 3. 读取 SpawnRequest 帧
    // 4. 创建受限令牌并启动目标进程
    // 5. 循环处理 IPC 消息（stdin、terminate、output）
}
```

#### 功能模块

| 模块 | 目的 | 关键操作 |
|-----|------|---------|
| **IPC 通信** | 与父进程双向通信 | 使用命名管道（Named Pipes）进行长度前缀的 JSON 帧通信 |
| **令牌管理** | 创建受限执行上下文 | `create_readonly_token_with_caps_from()` / `create_workspace_write_token_with_caps_from()` |
| **进程创建** | 在受限上下文中启动命令 | `spawn_conpty_process_as_user()`（TTY 模式）或 `spawn_process_with_pipes()`（管道模式） |
| **I/O 流式传输** | 实时转发进程输出 | `spawn_output_reader()` - 在独立线程中读取 stdout/stderr 并通过 IPC 发送 |
| **输入处理** | 接收并转发 stdin | `spawn_input_loop()` - 处理来自父进程的 Stdin 和 Terminate 消息 |
| **作业对象** | 进程生命周期管理 | `create_job_kill_on_close()` - 创建 Job Object 确保子进程在 runner 退出时被终止 |

---

## 具体技术实现

### 1. IPC 协议（ipc_framed 模块）

#### 协议设计

```rust
// src/elevated/ipc_framed.rs
/// 长度前缀的 JSON 帧结构
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FramedMessage {
    pub version: u8,        // 协议版本，当前为 1
    #[serde(flatten)]
    pub message: Message,
}

/// 消息类型（使用 tag 进行反序列化）
#[derive(Debug, Serialize, Deserialize, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
    SpawnRequest { payload: Box<SpawnRequest> },  // 父 -> 子：启动命令
    SpawnReady { payload: SpawnReady },           // 子 -> 父：进程已启动
    Output { payload: OutputPayload },            // 子 -> 父：stdout/stderr 数据
    Stdin { payload: StdinPayload },              // 父 -> 子：stdin 数据
    Exit { payload: ExitPayload },                // 子 -> 父：进程退出
    Error { payload: ErrorPayload },              // 子 -> 父：错误报告
    Terminate { payload: EmptyPayload },          // 父 -> 子：请求终止
}
```

#### 帧格式

```
[4 bytes: payload length (little-endian)] [N bytes: JSON payload]
```

最大帧大小限制：8MB（防止内存耗尽攻击）

### 2. 安全令牌创建（token 模块）

#### 受限令牌创建流程

```rust
// src/token.rs
unsafe fn create_token_with_caps_from(
    base_token: HANDLE,
    psid_capabilities: &[*mut c_void],
) -> Result<HANDLE> {
    // 1. 获取 Logon SID（用于会话标识）
    let mut logon_sid_bytes = get_logon_sid_bytes(base_token)?;
    
    // 2. 获取 Everyone SID（用于基本访问）
    let mut everyone = world_sid()?;
    
    // 3. 构建 SID 列表：Capabilities + Logon + Everyone
    let mut entries: Vec<SID_AND_ATTRIBUTES> = vec![...];
    
    // 4. 创建受限令牌
    let flags = DISABLE_MAX_PRIVILEGE | LUA_TOKEN | WRITE_RESTRICTED;
    CreateRestrictedToken(
        base_token,
        flags,           // 禁用特权 + LUA 令牌 + 写入限制
        0, std::ptr::null(),  // 禁用 SID 列表（空）
        0, std::ptr::null(),  // 删除特权列表（空）
        entries.len() as u32,
        entries.as_mut_ptr(), // 限制 SID 列表（Capabilities）
        &mut new_token,
    );
    
    // 5. 设置默认 DACL（允许管道/IPC 创建）
    set_default_dacl(new_token, &dacl_sids)?;
    
    // 6. 启用 SeChangeNotifyPrivilege（绕过遍历检查）
    enable_single_privilege(new_token, "SeChangeNotifyPrivilege")?;
}
```

#### 令牌类型

| 策略 | 令牌类型 | Capability SID |
|-----|---------|---------------|
| ReadOnly | `create_readonly_token_with_cap_from` | `caps.readonly` |
| WorkspaceWrite | `create_workspace_write_token_with_caps_from` | `caps.workspace` + `workspace_cap_sid_for_cwd()` |

### 3. ACL 计算与应用（allow/acl 模块）

#### 路径分类逻辑

```rust
// src/allow.rs
pub struct AllowDenyPaths {
    pub allow: Vec<PathBuf>,  // 允许读取的路径
    pub deny: Vec<PathBuf>,   // 明确拒绝写入的路径
}

pub fn compute_allow_paths(
    policy: &SandboxPolicy,
    policy_cwd: &Path,      // 策略解析的基准目录
    command_cwd: &Path,     // 命令执行的当前目录
    env_map: &HashMap<String, String>,
) -> AllowDenyPaths {
    // 1. 根据策略确定可写根目录
    // 2. 根据环境变量（如 TEMP、TMP）确定临时目录
    // 3. 计算允许读取的根目录（平台默认 + 策略指定）
    // 4. 排除策略指定的拒绝路径
}
```

#### ACL 应用策略

```rust
// src/setup_main_win.rs
// 写入根目录的 ACL 配置
let write_mask = FILE_GENERIC_READ | FILE_GENERIC_WRITE | FILE_GENERIC_EXECUTE | DELETE | FILE_DELETE_CHILD;

// 为沙箱用户组和 Capability SID 授予写入权限
for root in &write_roots {
    ensure_allow_write_aces(&root, &[sandbox_group_psid, cap_psid])?;
}

// 读取根目录的 ACL 配置（使用继承）
let read_mask = FILE_GENERIC_READ | FILE_GENERIC_EXECUTE;
apply_read_acls(&read_roots, &subjects, log, &mut refresh_errors, read_mask, "read", 
    OBJECT_INHERIT_ACE | CONTAINER_INHERIT_ACE)?;
```

### 4. Capability SID 管理（cap 模块）

#### SID 生成与持久化

```rust
// src/cap.rs
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapSids {
    pub workspace: String,                    // 通用工作区 Capability SID
    pub readonly: String,                     // 只读模式 Capability SID
    pub workspace_by_cwd: HashMap<String, String>, // 每个 CWD 的专用 SID
}

fn make_random_cap_sid_string() -> String {
    // 生成格式: S-1-5-21-{a}-{b}-{c}-{d}
    // 使用随机数确保每个安装的 SID 唯一
    format!("S-1-5-21-{}-{}-{}-{}", a, b, c, d)
}
```

Capability SID 用于：
1. **标识沙箱实例**：每个安装的 Capability SID 唯一，防止跨安装访问
2. **工作区隔离**：每个工作区（CWD）有独立的 SID，防止工作区之间的文件访问
3. **ACL 粒度控制**：比传统用户/组更细粒度的访问控制

### 5. 沙箱用户管理（sandbox_users 模块）

#### 用户创建流程

```rust
// src/setup_main_win.rs -> sandbox_users.rs
pub fn provision_sandbox_users(
    codex_home: &Path,
    offline_username: &str,
    online_username: &str,
    log: &mut File,
) -> Result<()> {
    // 1. 确保沙箱用户组存在
    ensure_sandbox_users_group(log)?;
    
    // 2. 生成随机密码
    let offline_password = random_password(); // 24 字符随机密码
    let online_password = random_password();
    
    // 3. 创建或更新用户
    ensure_sandbox_user(offline_username, &offline_password, log)?;
    ensure_sandbox_user(online_username, &online_password, log)?;
    
    // 4. 使用 DPAPI 加密密码并存储
    write_secrets(codex_home, offline_username, &offline_password, 
                  online_username, &online_password)?;
}
```

#### 密码管理

- 密码使用 Windows DPAPI（Data Protection API）加密
- 加密后的密码存储在 `CODEX_HOME/.sandbox-secrets/sandbox_users.json`
- 只有创建这些密码的 Windows 用户账户才能解密

### 6. 命名管道安全（elevated_impl 模块）

#### 管道创建与 ACL

```rust
// src/elevated_impl.rs
fn create_named_pipe(name: &str, access: u32, sandbox_sid: &str) -> io::Result<HANDLE> {
    // 使用 SDDL 定义安全描述符
    // D:(A;;GA;;;{sandbox_sid}) - 仅允许指定 SID 完全访问
    let sddl = to_wide(format!("D:(A;;GA;;;{sandbox_sid})"));
    
    ConvertStringSecurityDescriptorToSecurityDescriptorW(
        sddl.as_ptr(),
        1, // SDDL_REVISION_1
        &mut sd,
        ptr::null_mut(),
    );
    
    // 创建命名管道，应用自定义安全描述符
    CreateNamedPipeW(wide.as_ptr(), access, ...)
}
```

---

## 关键代码路径与文件引用

### 二进制入口点

```
src/bin/
├── setup_main.rs          # codex-windows-sandbox-setup 入口
│   └── #[path = "../setup_main_win.rs"] mod win;
│
└── command_runner.rs      # codex-command-runner 入口
    └── #[path = "../elevated/command_runner_win.rs"] mod win;
```

### 核心实现文件

| 文件 | 功能 | 关键函数/结构 |
|-----|------|--------------|
| `src/setup_main_win.rs` | 设置二进制主实现 | `real_main()`, `run_setup()`, `Payload`, `SetupMode` |
| `src/setup_orchestrator.rs` | 设置协调（非特权部分） | `run_elevated_setup()`, `run_setup_refresh()`, `ElevationPayload` |
| `src/elevated/command_runner_win.rs` | 命令运行器主实现 | `main()`, `spawn_ipc_process()`, `IpcSpawnedProcess` |
| `src/elevated_impl.rs` | 特权执行实现（CLI 侧） | `run_windows_sandbox_capture()`, `create_named_pipe()` |
| `src/elevated/ipc_framed.rs` | IPC 协议定义 | `FramedMessage`, `Message`, `SpawnRequest`, `write_frame()`, `read_frame()` |
| `src/token.rs` | 安全令牌操作 | `create_restricted_token()`, `get_logon_sid_bytes()` |
| `src/cap.rs` | Capability SID 管理 | `CapSids`, `load_or_create_cap_sids()`, `workspace_cap_sid_for_cwd()` |
| `src/acl.rs` | ACL 操作 | `add_allow_ace()`, `add_deny_write_ace()`, `allow_null_device()` |
| `src/allow.rs` | 允许/拒绝路径计算 | `compute_allow_paths()`, `AllowDenyPaths` |
| `src/sandbox_users.rs` | 沙箱用户管理 | `provision_sandbox_users()`, `ensure_sandbox_user()` |
| `src/setup_error.rs` | 错误处理与报告 | `SetupErrorCode`, `SetupFailure`, `write_setup_error_report()` |
| `src/process.rs` | 进程创建 | `create_process_as_user()`, `spawn_process_with_pipes()` |
| `src/helper_materialization.rs` | 辅助二进制部署 | `resolve_helper_for_launch()`, `copy_helper_if_needed()` |

### 调用关系图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Codex CLI (主进程)                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │ run_elevated_   │  │ run_setup_      │  │ run_windows_sandbox_capture │  │
│  │ setup()         │  │ refresh()       │  │ _elevated()                 │  │
│  └────────┬────────┘  └────────┬────────┘  └─────────────┬───────────────┘  │
│           │                    │                          │                 │
│           │    ShellExecuteExW │                          │                 │
│           │    (runas)         │    CreateProcessWithLogonW                  │
│           ▼                    ▼                          ▼                 │
└─────────────────────────────────────────────────────────────────────────────┘
           │                    │                          │
           ▼                    ▼                          ▼
┌──────────────────────┐  ┌──────────────────────┐  ┌────────────────────────┐
│ codex-windows-       │  │ codex-windows-       │  │ codex-command-runner   │
│ sandbox-setup        │  │ sandbox-setup        │  │ (以沙箱用户身份运行)     │
│ (Full 模式)          │  │ (ReadAclsOnly 模式)  │  │                        │
│                      │  │                      │  │ ┌────────────────────┐ │
│ ┌──────────────────┐ │  │ ┌──────────────────┐ │  │ │ Named Pipe IPC     │ │
│ │ provision_       │ │  │ │ apply_read_acls()│ │  │ │ (SpawnRequest)     │ │
│ │ sandbox_users()  │ │  │ └──────────────────┘ │  │ └─────────┬──────────┘ │
│ ├──────────────────┤ │  └──────────────────────┘  │           │            │
│ │ firewall::       │ │                            │           ▼            │
│ │ ensure_offline_  │ │                            │ ┌────────────────────┐ │
│ │ outbound_block() │ │                            │ │ spawn_ipc_process()│ │
│ ├──────────────────┤ │                            │ ├────────────────────┤ │
│ │ apply_read_acls()│ │                            │ │ create_restricted_ │ │
│ │ ensure_allow_    │ │                            │ │ token_with_caps()  │ │
│ │ write_aces()     │ │                            │ ├────────────────────┤ │
│ └──────────────────┘ │                            │ │ CreateProcessAsUser│ │
└──────────────────────┘                            │ │ (启动目标命令)      │ │
                                                    │ └────────────────────┘ │
                                                    └────────────────────────┘
```

---

## 依赖与外部交互

### 1. Windows API 依赖

#### 安全相关 API（advapi32）

| API | 用途 | 所在文件 |
|-----|------|---------|
| `CreateRestrictedToken` | 创建受限安全令牌 | `token.rs` |
| `OpenProcessToken` | 获取当前进程令牌 | `token.rs` |
| `SetEntriesInAclW` / `SetNamedSecurityInfoW` | ACL 修改 | `acl.rs`, `setup_main_win.rs` |
| `ConvertStringSidToSidW` | SID 字符串转换 | `token.rs`, `sandbox_users.rs` |
| `LookupAccountNameW` / `LookupAccountSidW` | 账户名称/SID 查询 | `sandbox_users.rs` |
| `NetUserAdd` / `NetUserSetInfo` | 用户账户管理 | `sandbox_users.rs` |
| `NetLocalGroupAdd` / `NetLocalGroupAddMembers` | 本地组管理 | `sandbox_users.rs` |
| `AllocateAndInitializeSid` / `CheckTokenMembership` | 管理员权限检查 | `setup_orchestrator.rs` |
| `DPAPI` (CryptProtectData/CryptUnprotectData) | 密码加密 | `dpapi.rs` |

#### 进程与 IPC API（kernel32）

| API | 用途 | 所在文件 |
|-----|------|---------|
| `CreateProcessAsUserW` | 以指定用户创建进程 | `process.rs`, `command_runner_win.rs` |
| `CreateProcessWithLogonW` | 以指定凭据创建进程 | `elevated_impl.rs` |
| `CreateNamedPipeW` / `ConnectNamedPipe` | 命名管道创建 | `elevated_impl.rs` |
| `CreatePipe` | 匿名管道创建 | `process.rs`, `command_runner_win.rs` |
| `CreateJobObjectW` / `AssignProcessToJobObject` | 作业对象管理 | `command_runner_win.rs` |
| `WaitForSingleObject` / `GetExitCodeProcess` | 进程等待与退出码 | `command_runner_win.rs`, `elevated_impl.rs` |

#### 其他 Windows API

| API | 用途 | 所在文件 |
|-----|------|---------|
| `ShellExecuteExW` | UAC 提升启动 | `setup_orchestrator.rs` |
| `CreatePseudoConsole` / `ClosePseudoConsole` | ConPTY 支持 | `conpty/mod.rs` |
| `ConvertStringSecurityDescriptorToSecurityDescriptorW` | SDDL 解析 | `elevated_impl.rs` |

### 2. 外部 crate 依赖

```toml
[dependencies]
anyhow = "1.0"                    # 错误处理
base64 = { workspace = true }     # Base64 编码（IPC 负载）
chrono = "0.4"                    # 时间戳（日志）
codex-utils-pty = { workspace = true }      # PTY 支持
codex-utils-absolute-path = { workspace = true }  # 路径处理
codex-utils-string = { workspace = true }   # 字符串工具
dunce = "1.0"                     # 路径规范化
serde = { version = "1.0", features = ["derive"] }  # 序列化
serde_json = "1.0"                # JSON 处理
tempfile = "3"                    # 临时文件（辅助二进制复制）
tokio = { workspace = true, features = ["sync", "rt"] }  # 异步运行时
rand = { version = "0.8", features = ["std", "small_rng"] }  # 随机数（密码、SID）
dirs-next = "2.0"                 # 目录路径
windows = "0.58"                  # Windows API 绑定（COM 等）
windows-sys = "0.52"              # 底层 Windows API 绑定
```

### 3. 文件系统交互

#### 沙箱目录结构

```
CODEX_HOME/
├── .sandbox/                     # 沙箱运行时数据
│   ├── setup_marker.json         # 设置版本标记
│   ├── setup_error.json          # 错误报告（临时）
│   └── log.txt                   # 设置日志
├── .sandbox-bin/                 # 辅助二进制文件
│   └── codex-command-runner.exe  # 复制的命令运行器
├── .sandbox-secrets/             # 加密敏感数据
│   └── sandbox_users.json        # DPAPI 加密的用户密码
└── cap_sid                       # Capability SID 存储
```

### 4. 与主 CLI 的交互接口

#### 库接口（lib.rs 导出）

```rust
// 主 CLI 使用的公共 API
pub use setup::run_elevated_setup;           // 初始设置
pub use setup::run_setup_refresh;            // ACL 刷新
pub use windows_impl::run_windows_sandbox_capture;  // 传统路径（受限令牌）
pub use elevated_impl::run_windows_sandbox_capture_elevated;  // 特权路径（沙箱用户）
```

---

## 风险、边界与改进建议

### 1. 已知风险

#### 安全风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| **密码泄露** | 沙箱用户密码存储在 DPAPI 加密文件中，但 DPAPI 依赖于用户登录会话 | 密码随机生成且长度足够（24字符），仅用于沙箱用户 |
| **ACL 竞态条件** | 多进程同时修改 ACL 可能导致权限临时不一致 | 使用 `read_acl_mutex` 进行互斥控制 |
| **命名管道劫持** | 命名管道路径包含随机数，但理论上存在预测可能 | 使用 128 位随机数，生命周期短（单次命令） |
| **沙箱逃逸** | Windows 沙箱依赖 ACL 和令牌，存在已知绕过技术 | 定期审计 ACL 配置，使用 Capability SID 增加粒度 |

#### 稳定性风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| **UAC 提示疲劳** | 每次初始设置都需要 UAC 提升 | 设置完成后使用 `refresh_only` 模式避免重复提升 |
| **防火墙规则累积** | 重复创建防火墙规则可能导致规则累积 | 使用特定名称的规则，存在时更新而非创建 |
| **临时文件泄漏** | 辅助二进制复制使用临时文件，崩溃时可能残留 | 使用 `NamedTempFile` 的自动清理机制 |

### 2. 边界条件

#### 已处理的边界

```rust
// 1. 路径规范化差异（Windows 大小写不敏感）
// cap.rs 中使用 canonical_path_key() 统一路径键
let key = canonical_path_key(cwd);

// 2. 并发 ACL 修改
// read_acl_mutex.rs 使用命名互斥体
pub fn acquire_read_acl_mutex() -> Result<Option<ReadAclGuard>> {
    // 使用 CreateMutexW 实现跨进程互斥
}

// 3. 缺失的目录
// 所有目录创建都使用 create_dir_all 并处理错误
std::fs::create_dir_all(&sbx_dir).map_err(|err| { ... })?;

// 4. 版本兼容性
// SETUP_VERSION 常量用于检测设置过期
pub const SETUP_VERSION: u32 = 5;
```

#### 未处理的边界/限制

1. **长路径支持**：未显式启用 Windows 长路径支持（`\\?\` 前缀）
2. **非 ASCII 用户名**：部分 SID 查找可能对某些 Unicode 用户名处理不当
3. **域环境**：沙箱用户创建假设本地账户，未测试域环境
4. **容器环境**：未测试在 Windows 容器（Docker/ContainerD）中的行为

### 3. 改进建议

#### 高优先级

1. **原子性 ACL 更新**
   - 当前 ACL 更新是增量式的，失败时可能部分应用
   - 建议：使用事务性 NTFS（TxF）或备份/恢复机制实现原子更新

2. **健康检查端点**
   - 添加 `codex-windows-sandbox-setup --health-check` 模式
   - 验证用户存在、密码有效、ACL 正确配置

3. **日志轮转**
   - 当前日志无限追加
   - 建议：实现基于大小的日志轮转

#### 中优先级

4. **并发命令优化**
   - 当前每个命令都创建新的命名管道和 runner 进程
   - 建议：考虑 runner 进程池复用

5. **ACL 缓存**
   - 每次命令都重新计算和验证 ACL
   - 建议：添加基于文件时间戳的 ACL 缓存

6. **PowerShell 7+ 支持**
   - 当前 ConPTY 实现针对 Windows PowerShell 优化
   - 建议：测试并优化 PowerShell Core 支持

#### 低优先级

7. **WSL 集成**
   - 考虑支持在 WSL 中运行 Windows 沙箱命令
   - 需要处理路径转换和互操作性

8. **组策略兼容性**
   - 某些企业环境使用严格组策略
   - 建议：添加组策略检测和友好错误消息

### 4. 测试覆盖

#### 现有测试

```
src/
├── cap.rs              # workspace_cap_sid_for_cwd 测试
├── setup_orchestrator.rs  # gather_read_roots 测试
├── helper_materialization.rs  # copy_helper 测试
└── elevated/ipc_framed.rs  # framed_round_trip 测试
```

#### 测试缺口

1. **集成测试**：缺少与真实 Windows API 的集成测试（需要管理员权限）
2. **并发测试**：缺少多命令并发执行的测试
3. **错误恢复测试**：缺少 ACL 部分失败后的恢复测试
4. **性能测试**：缺少大规模 ACL 操作的性能基准

### 5. 监控与可观测性

#### 当前指标

- 设置错误码（SetupErrorCode）用于分类失败
- 日志文件记录详细操作

#### 建议增强

1. **结构化日志**：从文本日志迁移到结构化 JSON 日志
2. **性能指标**：记录 ACL 应用时间、用户创建时间
3. **审计日志**：记录所有安全相关操作（用户创建、ACL 修改）

---

## 附录：关键数据结构

### Payload（设置参数）

```rust
#[derive(Debug, Clone, Deserialize, Serialize)]
struct Payload {
    version: u32,                    // SETUP_VERSION (当前为 5)
    offline_username: String,        // "CodexSandboxOffline"
    online_username: String,         // "CodexSandboxOnline"
    codex_home: PathBuf,             // CODEX_HOME 路径
    command_cwd: PathBuf,            // 命令执行目录
    read_roots: Vec<PathBuf>,        // 允许读取的根目录
    write_roots: Vec<PathBuf>,       // 允许写入的根目录
    real_user: String,               // 当前 Windows 用户名
    mode: SetupMode,                 // Full 或 ReadAclsOnly
    refresh_only: bool,              // 是否为刷新模式
}
```

### SpawnRequest（IPC 启动请求）

```rust
pub struct SpawnRequest {
    pub command: Vec<String>,        // 要执行的命令及参数
    pub cwd: PathBuf,                // 工作目录
    pub env: HashMap<String, String>, // 环境变量
    pub policy_json_or_preset: String, // 沙箱策略
    pub sandbox_policy_cwd: PathBuf, // 策略基准目录
    pub codex_home: PathBuf,         // 沙箱使用的 CODEX_HOME
    pub real_codex_home: PathBuf,    // 真实的 CODEX_HOME
    pub cap_sids: Vec<String>,       // Capability SID 列表
    pub timeout_ms: Option<u64>,     // 超时（毫秒）
    pub tty: bool,                   // 是否使用 TTY
    pub stdin_open: bool,            // 是否保持 stdin 打开
    pub use_private_desktop: bool,   // 是否使用私有桌面
}
```

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/windows-sandbox-rs/src/bin/*
