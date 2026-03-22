# Windows Sandbox RS 研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/windows-sandbox-rs` 是 Codex CLI 在 Windows 平台上的**沙箱执行引擎**，负责在 Windows 系统上安全地执行用户命令，提供与 macOS Seatbelt、Linux Landlock/Seccomp 同等的安全隔离能力。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **进程隔离** | 通过 Windows 受限令牌 (Restricted Token) 或独立用户账户执行命令 |
| **文件系统访问控制** | 基于 ACL (Access Control List) 精确控制读写权限 |
| **网络隔离** | 通过 Windows 防火墙规则阻止出站连接 |
| **特权管理** | 区分 Elevated (需要管理员权限) 和 Unelevated (受限令牌) 两种模式 |
| **沙箱生命周期** | 用户创建、权限配置、命令执行、清理的完整流程 |

### 1.3 两种运行模式

```
┌─────────────────────────────────────────────────────────────────┐
│                    Windows Sandbox 架构                          │
├─────────────────────────────────────────────────────────────────┤
│  Elevated Mode (高权限模式)                                      │
│  ├── 创建独立 Windows 用户 (CodexSandboxOffline/Online)         │
│  ├── 通过 CreateProcessWithLogonW 以独立用户运行                │
│  ├── 使用命名管道进行 IPC 通信                                   │
│  └── 需要管理员权限进行初始设置                                  │
├─────────────────────────────────────────────────────────────────┤
│  Unelevated Mode (受限令牌模式)                                  │
│  ├── 基于当前用户的受限令牌 (CreateRestrictedToken)             │
│  ├── 通过 Capability SID 实现文件系统隔离                       │
│  ├── 无需管理员权限                                             │
│  └── 功能相对受限                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 主要功能模块

| 模块 | 文件 | 目的 |
|-----|------|------|
| **沙箱执行入口** | `lib.rs` | 提供统一的 `run_windows_sandbox_capture` API |
| **策略解析** | `policy.rs` | 解析 SandboxPolicy 配置 (read-only/workspace-write) |
| **令牌管理** | `token.rs` | 创建和管理 Windows 受限令牌 |
| **ACL 管理** | `acl.rs` | 文件系统访问控制列表的增删改查 |
| **路径计算** | `allow.rs` | 计算允许/拒绝访问的路径集合 |
| **Capability SID** | `cap.rs` | 生成和管理能力安全标识符 |
| **进程创建** | `process.rs` | 使用受限令牌创建进程 |
| **设置编排器** | `setup_orchestrator.rs` | Elevated 模式的设置流程编排 |
| **设置主程序** | `setup_main_win.rs` | 高权限设置助手的实现 |
| **用户管理** | `sandbox_users.rs` | 沙箱用户的创建和管理 |
| **防火墙** | `firewall.rs` | 出站网络阻断规则配置 |
| **身份管理** | `identity.rs` | 凭证加载和验证 |
| **IPC 协议** | `elevated/ipc_framed.rs` | 命名管道通信协议 |
| **命令运行器** | `elevated/command_runner_win.rs` | Elevated 模式下的命令执行器 |
| **ConPTY** | `conpty/mod.rs` | 伪终端支持 |
| **桌面隔离** | `desktop.rs` | 私有桌面创建 (防止 UI 逃逸) |
| **审计** | `audit.rs` | 世界可写目录扫描 |
| **DPAPI** | `dpapi.rs` | 用户凭证加密存储 |

### 2.2 安全策略

```rust
// SandboxPolicy 定义 (来自 codex-protocol)
pub enum SandboxPolicy {
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    WorkspaceWrite { 
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
    DangerFullAccess,      // 不支持沙箱
    ExternalSandbox { network_access: NetworkAccess }, // 不支持
}
```

---

## 3. 具体技术实现

### 3.1 受限令牌创建流程 (Unelevated Mode)

```rust
// token.rs: create_token_with_caps_from
unsafe fn create_token_with_caps_from(
    base_token: HANDLE,
    psid_capabilities: &[*mut c_void],
) -> Result<HANDLE> {
    // 1. 获取 Logon SID
    let mut logon_sid_bytes = get_logon_sid_bytes(base_token)?;
    let psid_logon = logon_sid_bytes.as_mut_ptr() as *mut c_void;
    
    // 2. 获取 Everyone SID
    let mut everyone = world_sid()?;
    let psid_everyone = everyone.as_mut_ptr() as *mut c_void;

    // 3. 构建 SID 列表: [Capabilities..., Logon, Everyone]
    let mut entries: Vec<SID_AND_ATTRIBUTES> = ...;
    
    // 4. 创建受限令牌
    let flags = DISABLE_MAX_PRIVILEGE | LUA_TOKEN | WRITE_RESTRICTED;
    CreateRestrictedToken(
        base_token,
        flags,
        0, ptr::null(),  // 删除的 SIDs
        0, ptr::null(),  // 限制的 SIDs
        entries.len() as u32, entries.as_mut_ptr(), // 能力 SID
        &mut new_token,
    )
    
    // 5. 设置默认 DACL 以允许管道/IPC 创建
    set_default_dacl(new_token, &dacl_sids)?;
    
    // 6. 启用 SeChangeNotifyPrivilege
    enable_single_privilege(new_token, "SeChangeNotifyPrivilege")?;
}
```

### 3.2 ACL 权限管理

```rust
// acl.rs: 添加允许 ACE
pub unsafe fn add_allow_ace(path: &Path, psid: *mut c_void) -> Result<bool> {
    // 检查是否已有写权限
    if dacl_has_write_allow_for_sid(p_dacl, psid) {
        return Ok(false); // 已存在，跳过
    }
    
    // 使用 EXPLICIT_ACCESS_W 构建 ACE
    let mut explicit: EXPLICIT_ACCESS_W = std::mem::zeroed();
    explicit.grfAccessPermissions = FILE_GENERIC_READ | FILE_GENERIC_WRITE | FILE_GENERIC_EXECUTE;
    explicit.grfAccessMode = 2; // SET_ACCESS
    explicit.grfInheritance = CONTAINER_INHERIT_ACE | OBJECT_INHERIT_ACE;
    
    // 应用新 DACL
    SetEntriesInAclW(1, &explicit, p_dacl, &mut p_new_dacl)?;
    SetNamedSecurityInfoW(..., p_new_dacl, ...)?;
}
```

### 3.3 Elevated 模式 IPC 协议

```rust
// elevated/ipc_framed.rs
pub struct FramedMessage {
    pub version: u8,
    pub message: Message,
}

pub enum Message {
    SpawnRequest { payload: Box<SpawnRequest> },   // 父进程 -> Runner
    SpawnReady { payload: SpawnReady },            // Runner -> 父进程
    Output { payload: OutputPayload },             // Runner -> 父进程 (stdout/stderr)
    Stdin { payload: StdinPayload },               // 父进程 -> Runner
    Exit { payload: ExitPayload },                 // Runner -> 父进程
    Error { payload: ErrorPayload },               // Runner -> 父进程
    Terminate { payload: EmptyPayload },           // 父进程 -> Runner
}

// 长度前缀的 JSON 帧格式
// [4 bytes: payload length (little-endian)] [N bytes: JSON payload]
```

### 3.4 Elevated 模式执行流程

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Codex CLI  │────▶│  Setup Helper    │────▶│  Sandbox Users  │
│  (普通用户)  │     │  (管理员权限)     │     │  (创建/验证)    │
└─────────────┘     └──────────────────┘     └─────────────────┘
       │                       │                       │
       │                       ▼                       │
       │              ┌──────────────────┐            │
       │              │  Firewall Rules  │            │
       │              │  (出站阻断)       │            │
       │              └──────────────────┘            │
       │                       │                       │
       ▼                       ▼                       ▼
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Named Pipes │◀───▶│ Command Runner   │◀────│  Restricted     │
│ (IPC 通信)  │     │ (Sandbox 用户)   │     │  Token          │
└─────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Child Process  │
                     │  (用户命令)      │
                     └─────────────────┘
```

### 3.5 Capability SID 设计

```rust
// cap.rs
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapSids {
    pub workspace: String,      // 通用 workspace 能力 SID
    pub readonly: String,       // 只读能力 SID
    pub workspace_by_cwd: HashMap<String, String>, // 每个 CWD 独有的 SID
}

// SID 格式: S-1-5-21-{随机数}-{随机数}-{随机数}-{随机数}
// 用于: 1) 区分不同工作区的权限 2) 防止跨工作区访问
```

### 3.6 防火墙规则 (离线用户)

```rust
// firewall.rs
const OFFLINE_BLOCK_RULE_NAME: &str = "codex_sandbox_offline_block_outbound";

pub fn ensure_offline_outbound_block(offline_sid: &str, log: &mut File) -> Result<()> {
    // 1. 初始化 COM
    CoInitializeEx(None, COINIT_APARTMENTTHREADED)?;
    
    // 2. 获取防火墙策略
    let policy: INetFwPolicy2 = CoCreateInstance(&NetFwPolicy2, ...)?;
    let rules = policy.Rules()?;
    
    // 3. 创建/更新出站阻断规则
    ensure_block_rule(
        &rules,
        OFFLINE_BLOCK_RULE_NAME,
        NET_FW_IP_PROTOCOL_ANY.0,  // 所有协议
        &format!("O:LSD:(A;;CC;;;{offline_sid})"), // 仅针对离线用户 SID
    )?;
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心 API 入口

| 函数 | 位置 | 用途 |
|-----|------|------|
| `run_windows_sandbox_capture` | `lib.rs:261` | 主入口：受限令牌模式 |
| `run_windows_sandbox_capture_elevated` | `elevated_impl.rs:205` | Elevated 模式入口 |
| `run_elevated_setup` | `setup_orchestrator.rs:576` | 高权限设置流程 |
| `run_setup_refresh` | `setup_orchestrator.rs:81` | 刷新 ACL 权限 |

### 4.2 关键数据结构

```rust
// setup_orchestrator.rs
pub const SETUP_VERSION: u32 = 5;
pub const OFFLINE_USERNAME: &str = "CodexSandboxOffline";
pub const ONLINE_USERNAME: &str = "CodexSandboxOnline";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SetupMarker {
    pub version: u32,
    pub offline_username: String,
    pub online_username: String,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandboxUserRecord {
    pub username: String,
    pub password: String,  // DPAPI 加密后 base64
}
```

### 4.3 错误处理体系

```rust
// setup_error.rs
pub enum SetupErrorCode {
    // Orchestrator 错误 (CLI 侧)
    OrchestratorSandboxDirCreateFailed,
    OrchestratorElevationCheckFailed,
    OrchestratorHelperLaunchFailed,
    OrchestratorHelperLaunchCanceled,
    
    // Helper 错误 (设置助手侧)
    HelperUserProvisionFailed,
    HelperFirewallRuleCreateOrAddFailed,
    HelperSandboxLockFailed,
    // ... 共 20+ 个错误码
}
```

### 4.4 测试文件

| 文件 | 内容 |
|-----|------|
| `sandbox_smoketests.py` | Python 冒烟测试 (41 个测试用例) |
| `cap.rs` (tests) | Capability SID 测试 |
| `allow.rs` (tests) | 路径计算测试 |
| `setup_orchestrator.rs` (tests) | 读取根目录收集测试 |
| `helper_materialization.rs` (tests) | 助手二进制复制测试 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```toml
# Cargo.toml
[dependencies]
codex-protocol = { path = "../protocol" }  # SandboxPolicy 定义
codex-utils-pty = { workspace = true }      # ConPTY 支持
codex-utils-absolute-path = { workspace = true }
codex-utils-string = { workspace = true }
```

### 5.2 Windows API 依赖

```toml
[target.'cfg(windows)'.dependencies.windows-sys]
features = [
    "Win32_Security",           # 令牌、SID、ACL
    "Win32_System_Threading",   # 进程创建
    "Win32_System_JobObjects",  # Job Object (kill on close)
    "Win32_System_Pipes",       # 命名管道
    "Win32_System_StationsAndDesktops", # 桌面隔离
    "Win32_NetworkManagement_NetManagement", # 用户管理
    "Win32_NetworkManagement_WindowsFirewall", # 防火墙
    "Win32_Security_Cryptography", # DPAPI
]
```

### 5.3 调用方 (core crate)

```rust
// core/src/exec.rs
// 通过 SandboxType::WindowsRestrictedToken 调用

// core/src/sandboxing/mod.rs
// 在 transform 中处理 Windows 沙箱类型

// core/src/windows_sandbox.rs
// Windows 沙箱配置和设置管理
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| **UAC 提示** | Elevated 模式需要管理员权限，用户可能拒绝 | 提供 Unelevated 降级方案 |
| **防火墙冲突** | 第三方防火墙可能覆盖 Windows 防火墙规则 | 文档说明，建议检查 |
| **符号链接逃逸** | 精心构造的符号链接可能绕过路径检查 | 使用 junction 点而非符号链接进行 CWD 处理 |
| **时间竞争** | ACL 设置和命令执行之间存在时间窗口 | 使用原子操作，最小化窗口 |
| **DPAPI 依赖** | 凭证加密依赖机器密钥 | 使用 LOCAL_MACHINE 作用域 |

### 6.2 边界限制

1. **不支持 DangerFullAccess/ExternalSandbox**: 这两种策略会拒绝沙箱执行
2. **受限读取模式需 Elevated**: `!has_full_disk_read_access()` 时需要 Elevated 后端
3. **TEMP 目录行为不一致**: 某些主机上 TEMP 可能允许写入，即使只读策略
4. **PATHEXT 重新排序**: 为了阻止工具调用，需要修改 PATHEXT 顺序

### 6.3 改进建议

#### 短期改进

1. **增强日志记录**
   - 当前日志分散在多个文件，建议统一结构化日志
   - 增加更多诊断信息便于问题排查

2. **优化 ACL 应用性能**
   - 当前使用单线程顺序应用 ACL，可考虑并行化
   - 使用 `std::thread::scope` 已实现部分并行，可进一步优化

3. **改进错误信息**
   - 某些 Win32 错误码转换不够友好
   - 建议增加更多上下文信息

#### 中期改进

1. **支持更多沙箱策略**
   - 当前不支持 DangerFullAccess，可考虑实现警告模式
   - 支持更细粒度的网络访问控制

2. **增强安全审计**
   - 当前 `audit.rs` 扫描世界可写目录，但有时间限制
   - 考虑持久化审计结果，避免重复扫描

3. **改进设置流程**
   - Elevated 设置需要 UAC，用户体验不佳
   - 考虑使用 Windows 服务或计划任务减少 UAC 频率

#### 长期改进

1. **探索 Windows Container 支持**
   - 当前基于用户/令牌隔离，可考虑 Windows Sandbox/Container
   - 更强的隔离性，但兼容性可能降低

2. **统一跨平台沙箱接口**
   - 当前 Windows 实现与 macOS/Linux 差异较大
   - 抽象更通用的沙箱接口，降低维护成本

3. **支持 WSL 集成**
   - 检测 WSL 环境，提供原生 Linux 沙箱体验
   - 避免 Windows 沙箱在 WSL 中的兼容性问题

### 6.4 代码质量建议

1. **unsafe 代码封装**: 当前大量直接使用 Windows API，建议增加更多安全封装
2. **错误处理统一**: 使用 `SetupFailure` 结构体统一错误处理，但部分地方仍使用裸 `anyhow`
3. **测试覆盖率**: Python 冒烟测试覆盖较全，但 Rust 单元测试可进一步增强
4. **文档完善**: 部分内部函数缺少文档注释，建议补充

---

## 7. 附录

### 7.1 目录结构

```
codex-rs/windows-sandbox-rs/
├── src/
│   ├── lib.rs                    # 主库入口
│   ├── bin/
│   │   ├── setup_main.rs         # 设置助手二进制入口
│   │   └── command_runner.rs     # 命令运行器二进制入口
│   ├── setup_orchestrator.rs     # 设置编排器
│   ├── setup_main_win.rs         # 设置主逻辑
│   ├── setup_error.rs            # 错误定义
│   ├── elevated_impl.rs          # Elevated 模式实现
│   ├── elevated/
│   │   ├── ipc_framed.rs         # IPC 协议
│   │   ├── command_runner_win.rs # 命令运行器实现
│   │   ├── cwd_junction.rs       # CWD 连接点处理
│   │   └── runner_pipe.rs        # 管道处理
│   ├── token.rs                  # 令牌管理
│   ├── acl.rs                    # ACL 管理
│   ├── cap.rs                    # Capability SID
│   ├── allow.rs                  # 路径计算
│   ├── process.rs                # 进程创建
│   ├── policy.rs                 # 策略解析
│   ├── sandbox_users.rs          # 用户管理
│   ├── firewall.rs               # 防火墙
│   ├── identity.rs               # 身份管理
│   ├── dpapi.rs                  # 加密存储
│   ├── desktop.rs                # 桌面隔离
│   ├── conpty/                   # ConPTY 支持
│   ├── audit.rs                  # 安全审计
│   ├── env.rs                    # 环境变量处理
│   ├── workspace_acl.rs          # 工作区 ACL
│   ├── helper_materialization.rs # 助手二进制管理
│   ├── hide_users.rs             # 用户隐藏
│   ├── logging.rs                # 日志
│   ├── winutil.rs                # Windows 工具
│   ├── path_normalization.rs     # 路径规范化
│   └── read_acl_mutex.rs         # ACL 互斥锁
├── sandbox_smoketests.py         # Python 冒烟测试
├── Cargo.toml
├── build.rs                      # 嵌入 manifest
└── codex-windows-sandbox-setup.manifest
```

### 7.2 关键常量

| 常量 | 值 | 说明 |
|-----|---|------|
| `SETUP_VERSION` | 5 | 设置版本号 |
| `OFFLINE_USERNAME` | "CodexSandboxOffline" | 离线用户 |
| `ONLINE_USERNAME` | "CodexSandboxOnline" | 在线用户 |
| `SANDBOX_USERS_GROUP` | "CodexSandboxUsers" | 用户组 |
| `LOG_FILE_NAME` | "sandbox.log" | 日志文件名 |
| `MAX_FRAME_LEN` | 8MB | IPC 帧大小限制 |
