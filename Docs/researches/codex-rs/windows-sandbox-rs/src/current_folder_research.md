# Windows Sandbox RS 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 项目定位

`windows-sandbox-rs` 是 Codex CLI 的 **Windows 平台专用沙箱实现**，提供两种运行模式：

| 模式 | 技术方案 | 权限要求 | 适用场景 |
|------|----------|----------|----------|
| **Elevated (特权模式)** | 独立沙箱用户 + Windows 防火墙规则 | 需要管理员权限一次性设置 | 生产环境推荐 |
| **Unelevated/Legacy (受限令牌模式)** | Restricted Token + Capability SID | 无需管理员权限 | 快速体验/受限环境 |

### 1.2 核心职责

1. **进程隔离**：通过受限令牌或独立用户运行子进程
2. **文件系统访问控制**：基于 ACL 的读写权限管理
3. **网络隔离**：通过防火墙规则或代理环境变量阻断网络
4. **安全审计**：扫描并阻止对全局可写目录的访问
5. **权限升级管理**：处理 UAC 提权流程

### 1.3 调用方与被调用方

```
┌─────────────────────────────────────────────────────────────────┐
│                         调用方 (Callers)                         │
├─────────────────────────────────────────────────────────────────┤
│  codex-cli/src/debug_sandbox.rs    - 沙箱调试命令               │
│  codex-core/src/windows_sandbox.rs - 核心沙箱逻辑封装           │
│  codex-core/src/exec.rs            - 命令执行入口               │
│  codex-tui/src/app.rs              - TUI 应用层                 │
│  codex-app-server/src/command_exec.rs - App Server 命令执行     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              windows-sandbox-rs (本 crate)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │  lib.rs     │  │ setup_main  │  │ command_runner (bin)    │ │
│  │  (核心API)  │  │ (setup bin) │  │ (elevated 模式下使用)    │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      被调用方 (Dependencies)                     │
├─────────────────────────────────────────────────────────────────┤
│  Windows API: CreateProcessAsUserW, CreateRestrictedToken       │
│  Windows Firewall: INetFwPolicy2 (COM 接口)                     │
│  DPAPI: CryptProtectData/CryptUnprotectData (密码加密)          │
│  Local Users: NetUserAdd, NetLocalGroupAdd (用户管理)           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 双模式沙箱架构

#### Elevated 模式（推荐）

**目的**：提供最强隔离，通过独立 Windows 用户账户运行沙箱进程

**关键组件**：
- **Sandbox Users**: 创建 `CodexSandboxOffline` 和 `CodexSandboxOnline` 两个本地用户
- **Capability SID**: 动态生成的安全标识符，用于细粒度 ACL 控制
- **Windows Firewall**: 为离线用户配置出站阻断规则
- **Command Runner**: 独立的可执行文件，以沙箱用户身份运行命令

**工作流程**：
```
1. 首次运行检测 setup_marker.json 和 sandbox_users.json
2. 若未设置，通过 ShellExecuteExW 启动提权设置程序
3. 设置程序创建沙箱用户、配置防火墙、设置目录 ACL
4. 后续命令通过 CreateProcessWithLogonW 以沙箱用户启动 runner
5. Runner 通过命名管道与父进程通信，传输 stdout/stderr/exit code
```

#### Legacy/Unelevated 模式

**目的**：无需管理员权限即可体验沙箱功能

**技术方案**：
- 使用 `CreateRestrictedToken` 创建受限令牌
- 通过 Capability SID 标记沙箱进程
- 动态添加/移除 ACL 条目控制文件访问

**限制**：
- 无法真正隔离网络（仅通过环境变量设置代理）
- 受限令牌在某些系统上可能无法完全阻止写入

### 2.2 文件系统访问控制

| 策略类型 | 读取权限 | 写入权限 | 实现机制 |
|----------|----------|----------|----------|
| `ReadOnly` | 全磁盘或受限 | 无 | 受限令牌 + 可选 ACL |
| `WorkspaceWrite` | 全磁盘或受限 | 仅工作目录 | Capability SID + ACL |
| `DangerFullAccess` | 全部 | 全部 | 不启用沙箱 |
| `ExternalSandbox` | 全部 | 全部 | 外部沙箱工具 |

### 2.3 网络隔离策略

**Elevated 模式**：
- 使用 Windows 防火墙规则 `codex_sandbox_offline_block_outbound`
- 仅对 `CodexSandboxOffline` 用户生效
- 阻断所有出站 IP 协议

**Legacy 模式**：
- 设置环境变量 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY` 指向无效地址 `http://127.0.0.1:9`
- 创建 `denybin` 目录，放置返回 exit 1 的 `ssh.bat`, `scp.bat` 等 stub

### 2.4 安全审计功能

**World-Writable 扫描** (`audit.rs`)：
- 扫描 CWD、TEMP、USERPROFILE 等关键目录
- 检测 Everyone 组具有写入权限的目录
- 自动添加 Capability SID 的 Deny ACE 阻止写入

---

## 具体技术实现

### 3.1 核心数据结构

#### Capability SID 管理 (`cap.rs`)

```rust
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct CapSids {
    pub workspace: String,      // 通用 workspace capability SID
    pub readonly: String,       // readonly capability SID
    pub workspace_by_cwd: HashMap<String, String>, // 按 CWD 隔离的 SID
}
```

- SID 格式：`S-1-5-21-{随机32位}-{随机32位}-{随机32位}-{随机32位}`
- 存储位置：`$CODEX_HOME/cap_sid`
- 每个工作目录拥有独立的 Capability SID，实现工作目录间隔离

#### 沙箱策略 (`policy.rs`)

```rust
pub fn parse_policy(value: &str) -> Result<SandboxPolicy> {
    match value {
        "read-only" => Ok(SandboxPolicy::new_read_only_policy()),
        "workspace-write" => Ok(SandboxPolicy::new_workspace_write_policy()),
        other => serde_json::from_str(other), // 完整 JSON 策略
    }
}
```

### 3.2 关键流程实现

#### 3.2.1 Elevated 设置流程 (`setup_main_win.rs`)

```rust
pub fn main() -> Result<()> {
    // 1. 解析 Base64 编码的 payload
    let payload: Payload = serde_json::from_slice(&payload_json)?;
    
    // 2. 验证版本号
    if payload.version != SETUP_VERSION { ... }
    
    // 3. 根据模式执行
    match payload.mode {
        SetupMode::ReadAclsOnly => run_read_acl_only(payload, log),
        SetupMode::Full => run_setup_full(payload, log, sbx_dir),
    }
}
```

**Full 设置流程**：
1. `provision_sandbox_users()` - 创建离线/在线沙箱用户
2. `hide_newly_created_users()` - 在登录界面隐藏这些用户
3. `firewall::ensure_offline_outbound_block()` - 配置防火墙规则
4. `spawn_read_acl_helper()` - 异步授予读取 ACL
5. `lock_sandbox_dir()` - 锁定沙箱目录权限
6. `protect_workspace_codex_dir()` - 保护工作区 .codex 目录

#### 3.2.2 命令执行流程（Elevated 模式）

```rust
// elevated_impl.rs: run_windows_sandbox_capture()

// 1. 获取沙箱用户凭据
let sandbox_creds = require_logon_sandbox_creds(...)?;

// 2. 创建命名管道（仅沙箱用户可访问）
let h_pipe_in = create_named_pipe(&pipe_in_name, PIPE_ACCESS_OUTBOUND, &sandbox_sid)?;
let h_pipe_out = create_named_pipe(&pipe_out_name, PIPE_ACCESS_INBOUND, &sandbox_sid)?;

// 3. 以沙箱用户启动 command_runner
CreateProcessWithLogonW(
    user_w.as_ptr(),
    domain_w.as_ptr(),
    password_w.as_ptr(),
    LOGON_WITH_PROFILE,
    exe_w.as_ptr(),
    cmdline_vec.as_mut_ptr(),
    CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
    ...
);

// 4. 发送 SpawnRequest 到 runner
write_frame(&mut pipe_write, &spawn_request)?;

// 5. 循环读取输出帧
loop {
    let msg = read_frame(&mut pipe_read)?;
    match msg.message {
        Message::Output { payload } => { /* 处理 stdout/stderr */ }
        Message::Exit { payload } => break,
        ...
    }
}
```

#### 3.2.3 受限令牌创建 (`token.rs`)

```rust
unsafe fn create_token_with_caps_from(
    base_token: HANDLE,
    psid_capabilities: &[*mut c_void],
) -> Result<HANDLE> {
    // 1. 获取 Logon SID 和 Everyone SID
    let logon_sid_bytes = get_logon_sid_bytes(base_token)?;
    let everyone = world_sid()?;
    
    // 2. 构建 SID 列表: [Capabilities..., Logon, Everyone]
    let mut entries: Vec<SID_AND_ATTRIBUTES> = ...;
    
    // 3. 创建受限令牌
    let flags = DISABLE_MAX_PRIVILEGE | LUA_TOKEN | WRITE_RESTRICTED;
    CreateRestrictedToken(
        base_token,
        flags,
        0, ptr::null(),  // 禁用 SID 列表（空）
        0, ptr::null(),  // 删除权限列表（空）
        entries.len() as u32,
        entries.as_mut_ptr(), // 仅保留的 SID 列表
        &mut new_token,
    );
    
    // 4. 设置默认 DACL，允许管道/IPC 对象创建
    set_default_dacl(new_token, &dacl_sids)?;
    
    // 5. 启用 SeChangeNotifyPrivilege（绕过遍历检查）
    enable_single_privilege(new_token, "SeChangeNotifyPrivilege")?;
}
```

### 3.3 IPC 协议 (`ipc_framed.rs`)

**帧格式**：
```
[4 bytes: payload length (little-endian)]
[N bytes: JSON payload]
```

**消息类型**：

| 方向 | 消息 | 说明 |
|------|------|------|
| Parent → Runner | `SpawnRequest` | 启动命令请求 |
| Parent → Runner | `Stdin` | 标准输入数据 |
| Parent → Runner | `Terminate` | 终止命令 |
| Runner → Parent | `SpawnReady` | 进程已启动 |
| Runner → Parent | `Output` | stdout/stderr 输出 |
| Runner → Parent | `Exit` | 进程退出 |
| Runner → Parent | `Error` | 错误信息 |

### 3.4 ACL 管理 (`acl.rs`)

**核心函数**：

```rust
// 添加允许 ACE
pub unsafe fn add_allow_ace(path: &Path, psid: *mut c_void) -> Result<bool>;

// 添加拒绝写入 ACE
pub unsafe fn add_deny_write_ace(path: &Path, psid: *mut c_void) -> Result<bool>;

// 撤销 ACE
pub unsafe fn revoke_ace(path: &Path, psid: *mut c_void);

// 检查掩码权限
pub unsafe fn dacl_mask_allows(
    p_dacl: *mut ACL,
    psids: &[*mut c_void],
    desired_mask: u32,
    require_all_bits: bool,
) -> bool;
```

### 3.5 ConPTY 支持 (`conpty/`)

用于 TTY 模式的伪终端实现：

```rust
pub fn spawn_conpty_process_as_user(
    h_token: HANDLE,
    argv: &[String],
    cwd: &Path,
    env_map: &HashMap<String, String>,
    use_private_desktop: bool,
    logs_base_dir: Option<&Path>,
) -> Result<(PROCESS_INFORMATION, ConptyInstance)> {
    // 1. 创建 ConPTY 实例
    let conpty = create_conpty(80, 24)?;
    
    // 2. 设置 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE
    let mut attrs = ProcThreadAttributeList::new(1)?;
    attrs.set_pseudoconsole(conpty.hpc)?;
    si.lpAttributeList = attrs.as_mut_ptr();
    
    // 3. 使用 EXTENDED_STARTUPINFO_PRESENT 创建进程
    CreateProcessAsUserW(
        h_token, ..., 
        EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
        ...
    );
}
```

---

## 关键代码路径与文件引用

### 4.1 文件组织结构

```
codex-rs/windows-sandbox-rs/src/
├── lib.rs                      # 主入口，条件编译 Windows/Stub 实现
├── windows_impl                # Windows 实现模块（内联）
│   ├── run_windows_sandbox_capture()      # 主捕获函数
│   └── run_windows_sandbox_legacy_preflight()  # 预检函数
│
├── policy.rs                   # 策略解析
├── token.rs                    # 受限令牌创建
├── acl.rs                      # ACL 操作
├── cap.rs                      # Capability SID 管理
├── process.rs                  # 进程创建（CreateProcessAsUserW）
├── desktop.rs                  # 私有桌面创建
├── env.rs                      # 环境变量处理（网络隔离）
├── identity.rs                 # 沙箱用户身份验证
├── setup_orchestrator.rs       # 设置流程编排
├── setup_error.rs              # 错误代码定义
├── logging.rs                  # 日志记录
├── audit.rs                    # 安全审计扫描
├── hide_users.rs               # 隐藏沙箱用户
├── helper_materialization.rs   # 辅助程序复制管理
├── workspace_acl.rs            # 工作区 ACL 保护
├── path_normalization.rs       # 路径规范化
├── winutil.rs                  # Windows 工具函数
├── dpapi.rs                    # DPAPI 加密
├── firewall.rs                 # Windows 防火墙配置
├── read_acl_mutex.rs           # ACL 互斥锁
│
├── elevated/                   # Elevated 模式专用
│   ├── ipc_framed.rs           # IPC 帧协议
│   ├── command_runner_win.rs   # 命令运行器实现
│   ├── runner_pipe.rs          # 命名管道辅助
│   └── cwd_junction.rs         # CWD 连接点处理
│
├── conpty/                     # ConPTY 支持
│   ├── mod.rs                  # ConPTY 创建和进程启动
│   └── proc_thread_attr.rs     # 线程属性列表
│
└── bin/
    ├── setup_main.rs           # codex-windows-sandbox-setup 入口
    └── command_runner.rs       # codex-command-runner 入口
```

### 4.2 关键代码路径

#### 路径 1: Elevated 命令执行

```
codex-core/src/exec.rs
    └── windows_sandbox.rs::run_elevated_setup()
        └── codex_windows_sandbox::run_elevated_setup()
            └── setup_orchestrator.rs::run_elevated_setup()
                └── setup_orchestrator.rs::run_setup_exe()
                    └── ShellExecuteExW (提权)
                        └── setup_main_win.rs::main()
                            └── run_setup_full()
                                ├── sandbox_users.rs::provision_sandbox_users()
                                ├── firewall.rs::ensure_offline_outbound_block()
                                └── lock_sandbox_dir()

后续命令执行:
codex-core/src/exec.rs
    └── elevated_impl.rs::run_windows_sandbox_capture()
        ├── identity.rs::require_logon_sandbox_creds()
        ├── create_named_pipe() (IPC)
        ├── CreateProcessWithLogonW() (启动 runner)
        └── IPC 帧交换
```

#### 路径 2: Legacy 命令执行

```
codex-core/src/exec.rs
    └── lib.rs::windows_impl::run_windows_sandbox_capture()
        ├── token.rs::create_readonly_token_with_cap()
        ├── acl.rs::add_allow_ace() / add_deny_write_ace()
        ├── process.rs::create_process_as_user()
        └── 直接 stdout/stderr 捕获
```

#### 路径 3: 设置刷新

```
codex-core/src/windows_sandbox_read_grants.rs
    └── setup_orchestrator.rs::run_setup_refresh()
        └── setup_main_win.rs (非提权模式)
            └── run_read_acl_only()
```

### 4.3 配置与状态文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `cap_sid` | `$CODEX_HOME/` | Capability SID 存储 |
| `setup_marker.json` | `$CODEX_HOME/.sandbox/` | 设置版本标记 |
| `sandbox_users.json` | `$CODEX_HOME/.sandbox-secrets/` | 加密用户凭据 |
| `sandbox.log` | `$CODEX_HOME/.sandbox/` | 运行日志 |
| `setup_error.json` | `$CODEX_HOME/.sandbox/` | 设置错误报告 |

---

## 依赖与外部交互

### 5.1 内部依赖

```toml
[dependencies]
codex-protocol = { path = "../protocol" }      # SandboxPolicy 定义
codex-utils-pty = { workspace = true }          # RawConPty
codex-utils-absolute-path = { workspace = true } # AbsolutePathBuf
codex-utils-string = { workspace = true }       # sanitize_metric_tag_value
```

### 5.2 Windows API 依赖

| 功能 | API | 头文件 |
|------|-----|--------|
| 进程创建 | `CreateProcessAsUserW`, `CreateProcessWithLogonW` | `processthreadsapi.h` |
| 令牌操作 | `CreateRestrictedToken`, `OpenProcessToken` | `securitybaseapi.h` |
| ACL 管理 | `SetEntriesInAclW`, `SetNamedSecurityInfoW` | `aclapi.h` |
| 用户管理 | `NetUserAdd`, `NetLocalGroupAdd` | `lmaccess.h` |
| 防火墙 | `INetFwPolicy2` (COM) | `netfw.h` |
| 加密 | `CryptProtectData`, `CryptUnprotectData` | `dpapi.h` |
| ConPTY | `CreatePseudoConsole`, `ClosePseudoConsole` | `consoleapi.h` |

### 5.3 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Windows 操作系统                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ 本地用户数据库 │  │ Windows 防火墙 │  │ 文件系统 (ACL)       │ │
│  │ (SAM)        │  │ (WFAS)       │  │ (NTFS)              │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│ 沙箱用户创建   │    │ 出站规则配置   │    │ 目录 ACL 修改  │
│ NetUserAdd    │    │ INetFwRule    │    │ SetNamed      │
│               │    │               │    │ SecurityInfoW │
└───────────────┘    └───────────────┘    └───────────────┘
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全边界

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **GUI 逃逸** | 沙箱进程可能通过 GUI  API 与外部交互 | 使用 `use_private_desktop` 创建隔离桌面 |
| **符号链接竞争** | 攻击者可能在 ACL 检查和访问之间切换符号链接 | 使用连接点 (junction) 替代，定期审计 |
| **World-Writable 目录** | 全局可写目录允许沙箱进程写入任意位置 | `audit.rs` 扫描并添加 Deny ACE |
| **受限令牌绕过** | 某些系统服务可能不尊重受限令牌 | Elevated 模式使用独立用户，完全隔离 |
| **命名管道注入** | 其他进程可能连接到沙箱命名管道 | 管道 ACL 仅允许沙箱用户 SID |

#### 6.1.2 稳定性风险

| 风险 | 说明 |
|------|------|
| **UAC 取消** | 用户可能取消提权提示，导致设置失败 |
| **防火墙冲突** | 第三方防火墙可能覆盖 Windows 防火墙规则 |
| **杀毒软件干扰** | 可能拦截沙箱用户创建或进程启动 |
| **路径过长** | Windows 路径长度限制 (260/32767 字符) |

### 6.2 边界条件

1. **路径规范化**：使用 `dunce::canonicalize` 和自定义 `canonical_path_key` 处理大小写不敏感、斜杠差异
2. **TEMP 目录处理**：某些主机允许受限令牌写入 TEMP，通过 `exclude_tmpdir_env_var` 选项控制
3. **并发 ACL 修改**：使用 `ReadAclMutex` 防止多个进程同时修改 ACL
4. **工作目录连接点**：当 ACL 助手运行时，通过 junction 访问 CWD 避免权限问题

### 6.3 改进建议

#### 6.3.1 架构层面

1. **统一策略执行**：当前策略在多处解析（`policy.rs`, `allow.rs`, `setup_main_win.rs`），建议统一策略评估引擎
2. **异步 ACL 应用**：大型目录树的 ACL 设置可能阻塞，考虑使用 Windows 后台服务
3. **沙箱健康检查**：定期验证沙箱用户、防火墙规则、ACL 的完整性

#### 6.3.2 安全加固

1. **AppContainer 集成**：考虑使用 Windows AppContainer 提供额外隔离层
2. **WSL2 隔离**：对于支持 WSL2 的系统，考虑在 WSL2 内运行 Linux 沙箱
3. **内核回调**：使用 Windows 筛选器驱动（Minifilter）实现更细粒度的文件访问控制

#### 6.3.3 可观测性

1. **结构化日志**：当前日志为文本格式，建议增加结构化 JSON 日志
2. **性能指标**：收集 ACL 设置时间、进程启动延迟等指标
3. **审计日志**：记录所有策略变更和权限提升操作

#### 6.3.4 代码质量

1. **减少 unsafe 代码**：当前大量 Windows API 调用需要 unsafe，考虑使用 `windows-rs` crate 的安全封装
2. **错误分类**：细化 `SetupErrorCode`，增加可恢复错误的自动重试
3. **测试覆盖**：增加集成测试，特别是 ACL 竞争条件和符号链接场景

### 6.4 关键代码审查点

| 文件 | 审查重点 |
|------|----------|
| `token.rs` | 确保所有创建的 SID 都被正确释放 (`LocalFree`) |
| `acl.rs` | 验证 ACL 修改的原子性，防止并发问题 |
| `firewall.rs` | 确认防火墙规则作用域正确，不影响其他用户 |
| `elevated/command_runner_win.rs` | 检查进程终止时资源清理是否完整 |
| `sandbox_users.rs` | 验证密码生成强度，确保符合安全策略 |

---

## 附录

### A. 相关文档

- `AGENTS.md` - 项目级开发规范
- `codex-rs/app-server/README.md` - App Server API 文档
- `codex-rs/protocol/src/protocol.rs` - 协议定义

### B. 测试

- 单元测试：`cargo test -p codex-windows-sandbox`
- 冒烟测试：`python sandbox_smoketests.py`（需要构建 CLI）

### C. 调试

设置环境变量启用调试日志：
```powershell
$env:SBX_DEBUG = "1"
```

日志位置：`$env:USERPROFILE\.codex\.sandbox\sandbox.log`
