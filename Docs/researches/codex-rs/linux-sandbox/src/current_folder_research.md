# codex-rs/linux-sandbox/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-rs/linux-sandbox/src` 是 Codex CLI 在 Linux 平台上的**沙箱隔离核心实现**，负责为 AI 代理执行的外部命令提供安全的运行环境。该模块作为独立的二进制 crate (`codex-linux-sandbox`) 和库 (`codex_linux_sandbox`) 双重形态存在：

- **独立二进制**: 可直接作为 `codex-linux-sandbox` 命令行工具运行
- **库集成**: 通过 `lib.rs` 暴露 `run_main()` 供 `codex-exec` 等主程序通过 arg0 技巧调用

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **文件系统隔离** | 通过 bubblewrap (bwrap) 构建只读或受限的文件系统视图 |
| **网络隔离** | 通过 Linux namespace (`--unshare-net`) 和 seccomp BPF 过滤实现网络沙箱 |
| **权限降级** | 启用 `PR_SET_NO_NEW_PRIVS` 防止特权提升 |
| **代理路由** | 支持托管代理模式，将网络流量通过 UDS->TCP 桥接路由到指定代理 |
| **向后兼容** | 保留 Landlock 作为传统回退方案 |

### 1.3 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                     Linux Sandbox Pipeline                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │   Stage 1   │ -> │   Stage 2   │ -> │    User Command     │  │
│  │  (Outer)    │    │  (Inner)    │    │                     │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
│         │                  │                                    │
│    bubblewrap        seccomp + no_new_privs                     │
│    filesystem        network filter                             │
│    namespace                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 双阶段沙箱执行模型

| 阶段 | 文件 | 关键函数 | 目的 |
|-----|------|---------|------|
| **Outer Stage** | `linux_run_main.rs` | `run_bwrap_with_proc_fallback()` | 使用 bubblewrap 构建文件系统视图，创建隔离的 namespace |
| **Inner Stage** | `linux_run_main.rs` | `apply_seccomp_then_exec` 分支 | 在已隔离的环境中应用 seccomp 和 no_new_privs，然后 exec 用户命令 |

**设计 rationale**: bubblewrap 可能需要 setuid 权限来创建 namespace，而 seccomp 需要 `no_new_privs`。分离执行允许先完成需要特权的 namespace 创建，再应用限制性的 seccomp。

### 2.2 文件系统策略层级

```rust
// From: linux_run_main.rs:222-227
struct EffectiveSandboxPolicies {
    sandbox_policy: SandboxPolicy,           // 传统策略（向后兼容）
    file_system_sandbox_policy: FileSystemSandboxPolicy,  // 新拆分策略
    network_sandbox_policy: NetworkSandboxPolicy,         // 新拆分策略
}
```

策略解析支持三种输入模式：
1. **纯传统策略**: 仅提供 `SandboxPolicy`，自动派生拆分策略
2. **纯拆分策略**: 仅提供 `FileSystemSandboxPolicy` + `NetworkSandboxPolicy`，自动派生传统策略
3. **混合模式**: 同时提供，验证语义一致性

### 2.3 网络沙箱模式

| 模式 | 实现机制 | 适用场景 |
|-----|---------|---------|
| `FullAccess` | 无限制 | 完全信任模式 |
| `Isolated` | `--unshare-net` + seccomp 阻断所有网络 syscall | 完全隔离 |
| `ProxyOnly` | `--unshare-net` + UDS/TCP 桥接 + seccomp 限制 AF_UNIX | 仅允许通过代理访问网络 |

### 2.4 托管代理路由 (Managed Proxy)

当启用 `--allow-network-for-proxy` 时：

```
┌─────────────────────────────────────────────────────────────┐
│                    Proxy Routing Architecture                │
├─────────────────────────────────────────────────────────────┤
│  Sandbox内部                    Sandbox外部                  │
│  ┌──────────┐                 ┌──────────┐                  │
│  │ User Cmd │ --TCP->127.0.0.1 │ Local    │ --UDS-> ┌─────┐ │
│  │          │    (local_port) │ Bridge   │         │Host │ │
│  └──────────┘                 └──────────┘         │Bridge│ │
│                                                      └──┬──┘ │
│  ┌──────────────────────────────────────────────────────┘    │
│  v                                                            │
│ ┌──────────────┐    ┌─────────────────┐                      │
│ │ Proxy Socket │ --> │ Original Proxy  │                      │
│ │ (UDS)        │     │ (TCP loopback)  │                      │
│ └──────────────┘     └─────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

关键代码路径: `proxy_routing.rs`
- `prepare_host_proxy_route_spec()`: 外部准备阶段，创建 UDS 监听和桥接进程
- `activate_proxy_routes_in_netns()`: 内部激活阶段，重写环境变量，建立本地 TCP 监听

---

## 3. 具体技术实现

### 3.1 Bubblewrap 参数构建 (`bwrap.rs`)

#### 核心数据结构

```rust
// From: bwrap.rs:40-58
pub(crate) struct BwrapOptions {
    pub mount_proc: bool,           // 是否挂载 /proc
    pub network_mode: BwrapNetworkMode,
}

pub(crate) struct BwrapArgs {
    pub args: Vec<String>,          // bwrap 命令行参数
    pub preserved_files: Vec<File>, // 需要保持打开的文件描述符
}
```

#### 文件系统挂载顺序

```rust
// From: bwrap.rs:209-389 (create_filesystem_args)
// 挂载顺序至关重要：
// 1. 基础只读绑定 (--ro-bind / / 或 --tmpfs / + 选择性 --ro-bind)
// 2. 设备树 (--dev /dev)
// 3. 可写根目录祖先的不可读掩码
// 4. 可写根目录绑定 (--bind <root> <root>)
// 5. 可写根下的只读子路径 (--ro-bind)
// 6. 可写根下的嵌套不可读 carveouts
// 7. 独立不可读根目录
```

#### 路径深度排序

```rust
// From: bwrap.rs:294
sorted_writable_roots.sort_by_key(|writable_root| path_depth(writable_root.root.as_path()));
```

通过按路径深度排序确保父目录先于子目录处理，保证嵌套策略正确应用。

### 3.2 Seccomp BPF 过滤 (`landlock.rs`)

#### 网络沙箱 syscall 拦截

```rust
// From: landlock.rs:168-264 (install_network_seccomp_filter_on_current_thread)
// 两种模式：

// Restricted 模式 - 完全网络隔离
NetworkSeccompMode::Restricted => {
    deny_syscall(&mut rules, libc::SYS_connect);
    deny_syscall(&mut rules, libc::SYS_accept);
    // ... 阻断所有网络相关 syscall
    // 允许 AF_UNIX (本地 socket)
    let unix_only_rule = SeccompRule::new(vec![SeccompCondition::new(
        0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_UNIX as u64,
    )?])?;
    rules.insert(libc::SYS_socket, vec![unix_only_rule.clone()]);
}

// ProxyRouted 模式 - 仅允许 IP socket
NetworkSeccompMode::ProxyRouted => {
    // 阻断 AF_UNIX，仅允许 AF_INET/AF_INET6
    let deny_non_ip_socket = SeccompRule::new(vec![
        SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET as u64)?,
        SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET6 as u64)?,
    ])?;
}
```

#### Landlock 传统文件系统沙箱

```rust
// From: landlock.rs:136-162 (install_filesystem_landlock_rules_on_current_thread)
// 当前作为 legacy fallback 保留
fn install_filesystem_landlock_rules_on_current_thread(writable_roots: Vec<AbsolutePathBuf>) 
    -> Result<()> {
    let abi = ABI::V5;
    let access_rw = AccessFs::from_all(abi);
    let access_ro = AccessFs::from_read(abi);
    
    let mut ruleset = Ruleset::default()
        .set_compatibility(CompatLevel::BestEffort)
        .handle_access(access_rw)?
        .create()?
        .add_rules(landlock::path_beneath_rules(&["/"], access_ro))?  // 全局只读
        .add_rules(landlock::path_beneath_rules(&["/dev/null"], access_rw))?;
    // ... 添加可写根目录规则
}
```

### 3.3 代理路由实现 (`proxy_routing.rs`)

#### 环境变量解析

支持 13 种代理环境变量：

```rust
// From: proxy_routing.rs:26-41
const PROXY_ENV_KEYS: &[&str] = &[
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "FTP_PROXY",
    "YARN_HTTP_PROXY", "YARN_HTTPS_PROXY",
    "NPM_CONFIG_HTTP_PROXY", "NPM_CONFIG_HTTPS_PROXY", "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY", "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY", "DOCKER_HTTPS_PROXY",
];
```

#### 桥接进程生命周期管理

```rust
// From: proxy_routing.rs:375-401
fn spawn_proxy_socket_dir_cleanup_worker(socket_dir: PathBuf, host_bridge_pids: Vec<libc::pid_t>) 
    -> io::Result<()> {
    let pid = unsafe { libc::fork() };
    if pid == 0 {
        // 子进程：监控桥接进程
        loop {
            if host_bridge_pids.iter().all(|pid| !is_pid_alive_raw(*pid)) {
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let _ = cleanup_proxy_socket_dir(socket_dir.as_path());
        unsafe { libc::_exit(0) };
    }
    Ok(())
}
```

### 3.4 启动器 (`launcher.rs`)

#### Bubblewrap 来源选择

```rust
// From: launcher.rs:11-36
const SYSTEM_BWRAP_PATH: &str = "/usr/bin/bwrap";

enum BubblewrapLauncher {
    System(AbsolutePathBuf),  // 优先使用系统 bwrap
    Vendored,                  // 回退到内置 bwrap
}

fn preferred_bwrap_launcher() -> BubblewrapLauncher {
    if !Path::new(SYSTEM_BWRAP_PATH).is_file() {
        return BubblewrapLauncher::Vendored;
    }
    // ... 使用系统 bwrap
}
```

#### 文件描述符继承处理

```rust
// From: launcher.rs:73-97
fn make_files_inheritable(files: &[File]) {
    for file in files {
        clear_cloexec(file.as_raw_fd());
    }
}

fn clear_cloexec(fd: libc::c_int) {
    let flags = unsafe { libc::fcntl(fd, libc::F_GETFD) };
    let cleared_flags = flags & !libc::FD_CLOEXEC;
    if cleared_flags == flags { return; }
    unsafe { libc::fcntl(fd, libc::F_SETFD, cleared_flags) };
}
```

### 3.5 内置 Bubblewrap (`vendored_bwrap.rs`)

通过 build.rs 在编译时将 bubblewrap C 源码编译进二进制：

```rust
// From: vendored_bwrap.rs:31-49
pub(crate) fn run_vendored_bwrap_main(argv: &[String], _preserved_files: &[File]) -> libc::c_int {
    let cstrings = argv_to_cstrings(argv);
    let mut argv_ptrs: Vec<*const c_char> = cstrings.iter()
        .map(|arg| arg.as_ptr())
        .collect();
    argv_ptrs.push(std::ptr::null());
    
    // 调用 FFI 到 C 编译的 bwrap_main
    unsafe { bwrap_main(cstrings.len() as libc::c_int, argv_ptrs.as_ptr()) }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 入口点调用链

```
main.rs:main()
    └── lib.rs:run_main()
            └── linux_run_main.rs:run_main()
                    ├── 策略解析: resolve_sandbox_policies()
                    ├── 内层阶段: apply_seccomp_then_exec 分支
                    │       ├── proxy_routing.rs:activate_proxy_routes_in_netns() (可选)
                    │       ├── landlock.rs:apply_sandbox_policy_to_current_thread()
                    │       └── exec_or_panic()
                    └── 外层阶段: run_bwrap_with_proc_fallback()
                            ├── bwrap.rs:create_bwrap_command_args()
                            ├── launcher.rs:exec_bwrap()
                            │       ├── exec_system_bwrap() 或 
                            │       └── vendored_bwrap.rs:exec_vendored_bwrap()
                            └── 递归调用自身 (inner seccomp stage)
```

### 4.2 文件职责矩阵

| 文件 | 行数 | 核心职责 | 测试覆盖 |
|-----|------|---------|---------|
| `lib.rs` | 27 | 模块聚合，条件编译入口 | - |
| `main.rs` | 6 | 二进制入口，委托给 lib | - |
| `linux_run_main.rs` | 709 | CLI 解析、策略协调、两阶段执行编排 | `linux_run_main_tests.rs` |
| `bwrap.rs` | 1245 | Bubblewrap 参数构建、文件系统策略映射 | 内联 tests (598-1245行) |
| `landlock.rs` | 325 | Seccomp BPF、Landlock 传统支持 | 内联 tests (266-325行) |
| `launcher.rs` | 134 | bwrap 执行、系统/vendored 选择、fd 处理 | 内联 tests (99-134行) |
| `vendored_bwrap.rs` | 78 | FFI 封装内置 bubblewrap | - |
| `proxy_routing.rs` | 796 | 托管代理路由、UDS/TCP 桥接 | 内联 tests (647-796行) |
| `linux_run_main_tests.rs` | 441 | 集成测试 | - |

### 4.3 关键数据结构定义位置

```rust
// 策略类型 (来自 codex-protocol crate，在 linux_run_main.rs 使用)
codex_protocol::protocol::SandboxPolicy
codex_protocol::protocol::FileSystemSandboxPolicy  
codex_protocol::protocol::NetworkSandboxPolicy

// 内部类型
linux_run_main.rs:222  EffectiveSandboxPolicies
linux_run_main.rs:229  ResolveSandboxPoliciesError
bwrap.rs:40           BwrapOptions
bwrap.rs:51           BwrapNetworkMode
bwrap.rs:82           BwrapArgs
landlock.rs:89        NetworkSeccompMode
proxy_routing.rs:47   ProxyRouteSpec
proxy_routing.rs:52   ProxyRouteEntry
```

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖关系

```
codex-linux-sandbox
├── codex-core (workspace)      # 错误类型、工具支持
├── codex-protocol (workspace)  # 策略协议定义
├── codex-utils-absolute-path   # 路径规范化
├── landlock                    # Landlock LSM 绑定
├── seccompiler                 # Seccomp BPF 编译
├── libc                        # 系统调用
├── clap                        # CLI 解析
├── serde/serde_json            # 策略序列化
└── url                         # 代理 URL 解析
```

### 5.2 外部系统依赖

| 依赖 | 用途 | 回退方案 |
|-----|------|---------|
| `/usr/bin/bwrap` | 首选 bubblewrap 实现 | 内置 vendored bwrap |
| `libcap` (pkg-config) | 编译时检测 capabilities 支持 | 编译失败 |
| Linux Kernel 5.13+ | Landlock ABI v5 | 使用 bubblewrap 替代 |
| Linux Namespace 支持 | 网络/用户/PID 隔离 | 降级到无沙箱 |

### 5.3 调用方与被调用方

#### 调用方 (谁使用这个 crate)

```
codex-exec/src/main.rs
    └── arg0_dispatch_or_else() 检测 arg0 == "codex-linux-sandbox"
            └── codex_linux_sandbox::run_main()

codex-core/src/landlock.rs
    └── spawn_command_under_linux_sandbox()  # 异步 spawn

codex-core/src/sandboxing/mod.rs
    └── SandboxManager::transform()  # 生成 ExecRequest
```

#### 被调用方 (这个 crate 调用谁)

```
系统调用:
- libc::execvp()          # 执行最终命令
- libc::fork()            # 创建子进程
- libc::prctl()           # no_new_privs, deathsig
- libc::pipe2()           # 进程间通信
- libc::waitpid()         # 等待子进程
- libc::socket/ioctl      # 网络配置 (proxy_routing)

外部程序:
- /usr/bin/bwrap (优先)   # 系统 bubblewrap
- 内置 bwrap_main()       # 编译时嵌入的 bubblewrap
```

### 5.4 构建时依赖

```rust
// build.rs:43-81
try_build_vendored_bwrap() {
    // 1. 检测 libcap via pkg-config
    // 2. 编译 bubblewrap C 源码 (bubblewrap.c, bind-mount.c, network.c, utils.c)
    // 3. 定义 main -> bwrap_main 以便 FFI 调用
    // 4. 设置 cfg(vendored_bwrap_available)
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险点

#### 6.1.1 容器环境兼容性

```rust
// From: linux_run_main.rs:486-500
fn preflight_proc_mount_support(...) -> bool {
    // 预检 /proc 挂载能力，某些容器环境会拒绝
    // 失败时自动降级到 --no-proc
}
```

**风险**: 在 Docker/Kubernetes 等受限容器中，namespace 创建可能失败。
**缓解**: 预检机制 + 自动降级。

#### 6.1.2 Seccomp 架构依赖

```rust
// From: landlock.rs:250-256
if cfg!(target_arch = "x86_64") {
    TargetArch::x86_64
} else if cfg!(target_arch = "aarch64") {
    TargetArch::aarch64
} else {
    unimplemented!("unsupported architecture for seccomp filter");
}
```

**风险**: 仅支持 x86_64 和 aarch64，其他架构会 panic。

#### 6.1.3 代理路由竞态条件

```rust
// From: proxy_routing.rs:375-401
// cleanup worker 通过轮询 (100ms 间隔) 检测桥接进程死亡
// 存在短暂窗口期，socket 文件可能残留
```

### 6.2 边界条件

| 边界场景 | 处理策略 |
|---------|---------|
| 缺失的可写根目录 | 静默跳过 (`bwrap.rs:216-220`) |
| 符号链接攻击 | 挂载 `/dev/null` 到 symlink 路径 (`bwrap.rs:533-565`) |
| 不存在的保护路径 | 挂载到第一个缺失的组件 (`bwrap.rs:567-596`) |
| 嵌套策略冲突 | 按路径深度排序，窄策略优先 (`bwrap.rs:294`) |
| 空代理环境变量 | fail-closed，拒绝执行 (`proxy_routing.rs:74-80`) |

### 6.3 改进建议

#### 6.3.1 架构支持扩展

```rust
// 建议：添加 riscv64 支持
#[cfg(target_arch = "riscv64")]
TargetArch::riscv64
```

#### 6.3.2 错误信息增强

当前错误信息较为底层：
```
"error applying Linux sandbox restrictions: ..."
```

建议添加用户友好的错误分类：
- "沙箱需要内核 namespace 支持，但在当前环境中不可用"
- "代理路由需要 CAP_NET_ADMIN 能力"

#### 6.3.3 性能优化

```rust
// proxy_routing.rs:386-394
// 当前使用 100ms 轮询监控桥接进程
// 建议改用 signalfd 或 pidfd 实现事件驱动
```

#### 6.3.4 测试覆盖

当前测试主要依赖集成测试 (`tests/suite/`)。建议添加：
- 单元测试覆盖策略解析逻辑 (`resolve_sandbox_policies`)
- Mock 测试 seccomp 规则生成
- 模糊测试 bwrap 参数构建

#### 6.3.5 安全加固

1. ** Landlock 降级检测**: 当 Landlock 实际未生效时 (RulesetStatus::NotEnforced)，当前返回错误，但可考虑添加审计日志。

2. ** Seccomp 审计**: 当前允许 `recvfrom` syscall (注释说明为了 cargo clippy 等工具)，需定期评估此例外。

3. ** 代理路由隔离**: 考虑使用单独的网络 namespace 而非仅依赖 seccomp 限制 AF_UNIX。

### 6.4 配置建议

```toml
# 用户配置示例 (codex/config.toml)
[sandbox]
# 强制使用传统 Landlock (不推荐，仅用于调试)
use_legacy_landlock = false

# 禁用 /proc 挂载 (用于受限容器)
no_proc = false

# 启用托管代理模式
allow_network_for_proxy = true
```

---

## 7. 附录：关键代码片段索引

### 7.1 策略解析核心

```rust
// linux_run_main.rs:273-346
fn resolve_sandbox_policies(...) -> Result<EffectiveSandboxPolicies, ResolveSandboxPoliciesError>
```

### 7.2 Seccomp 规则构建

```rust
// landlock.rs:168-264
fn install_network_seccomp_filter_on_current_thread(mode: NetworkSeccompMode) 
    -> std::result::Result<(), SandboxErr>
```

### 7.3 bwrap 参数构建入口

```rust
// bwrap.rs:94-119
pub(crate) fn create_bwrap_command_args(
    command: Vec<String>,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    sandbox_policy_cwd: &Path,
    command_cwd: &Path,
    options: BwrapOptions,
) -> Result<BwrapArgs>
```

### 7.4 代理路由准备

```rust
// proxy_routing.rs:70-119
pub(crate) fn prepare_host_proxy_route_spec() -> io::Result<String>
```

---

*文档生成时间: 2026-03-22*
*基于 commit: 当前工作目录*
