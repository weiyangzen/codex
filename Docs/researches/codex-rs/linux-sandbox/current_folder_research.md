# codex-rs/linux-sandbox 研究文档

## 概述

`codex-linux-sandbox` 是 Codex CLI 在 Linux 平台上的沙箱隔离实现 crate。它提供了一个独立的可执行文件，用于在 Linux 系统上执行命令时提供文件系统和网络隔离。该 crate 同时作为库（lib）和可执行文件（bin）发布，支持多种沙箱策略配置。

---

## 场景与职责

### 核心职责

1. **文件系统隔离**：通过 bubblewrap (bwrap) 创建只读或受限的文件系统视图
2. **网络隔离**：通过 seccomp 和 Linux 命名空间限制网络访问
3. **进程隔离**：通过 PID 命名空间和用户命名空间隔离进程
4. **托管代理模式**：支持受控的网络代理路由，允许特定代理流量通过

### 使用场景

- **安全执行用户命令**：防止恶意代码访问敏感文件或网络
- **受限网络环境**：在隔离网络环境下运行工具，同时允许通过代理访问特定端点
- **CI/CD 集成**：在持续集成环境中安全地执行构建和测试命令
- **多租户环境**：在同一主机上隔离不同用户的执行环境

### 架构定位

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex CLI / Core                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           sandboxing/mod.rs (SandboxManager)        │   │
│  │  - 策略转换和权限合并                                │   │
│  │  - 平台沙箱选择 (LinuxSeccomp / MacosSeatbelt)     │   │
│  └────────────────────┬────────────────────────────────┘   │
│                       │                                      │
│                       ▼                                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │     landlock.rs (create_linux_sandbox_command_args) │   │
│  │  - 构建沙箱命令行参数                                │   │
│  └────────────────────┬────────────────────────────────┘   │
└───────────────────────┼─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-linux-sandbox (本 crate)                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │   main.rs → lib.rs → linux_run_main::run_main()    │   │
│  └────────────────────┬────────────────────────────────┘   │
│                       │                                      │
│         ┌─────────────┼─────────────┐                       │
│         ▼             ▼             ▼                       │
│    ┌─────────┐   ┌─────────┐   ┌──────────┐                │
│    │  bwrap  │   │landlock │   │  proxy   │                │
│    │  .rs    │   │  .rs    │   │_routing  │                │
│    └────┬────┘   └────┬────┘   └────┬─────┘                │
│         │             │             │                       │
│         ▼             ▼             ▼                       │
│    ┌─────────┐   ┌─────────┐   ┌──────────┐                │
│    │launcher │   │ seccomp │   │ TCP/UDS  │                │
│    │  .rs    │   │ filter  │   │  bridge  │                │
│    └────┬────┘   └─────────┘   └──────────┘                │
│         │                                                   │
│         ▼                                                   │
│    ┌─────────────┐                                          │
│    │vendored_bwrap│ (可选内嵌 bubblewrap)                  │
│    └─────────────┘                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 双层执行模型

```rust
// linux_run_main.rs
pub fn run_main() -> ! {
    // 第一阶段：外部 bubblewrap 包装（如果需要文件系统隔离）
    if !use_legacy_landlock && needs_filesystem_sandbox {
        // 构建内层命令（带 --apply-seccomp-then-exec）
        let inner = build_inner_seccomp_command(...);
        // 执行 bubblewrap
        run_bwrap_with_proc_fallback(...);
    }
    
    // 第二阶段：内层 seccomp 应用（在 bwrap 内部或直执行）
    if apply_seccomp_then_exec {
        apply_sandbox_policy_to_current_thread(...);
        exec_or_panic(command);
    }
    
    // 遗留路径：纯 Landlock 模式
    apply_sandbox_policy_to_current_thread(..., apply_landlock_fs=true);
    exec_or_panic(command);
}
```

**目的**：
- bubblewrap 需要某些特权（如 CAP_SYS_ADMIN）来创建命名空间
- seccomp 需要在 `no_new_privs` 之后应用，这会阻止 setuid
- 分离两个阶段可以兼顾两者需求

### 2. 策略解析与合并

```rust
// 支持三种策略输入方式
enum ResolveSandboxPoliciesError { ... }

fn resolve_sandbox_policies(
    sandbox_policy_cwd: &Path,
    sandbox_policy: Option<SandboxPolicy>,           // 遗留策略
    file_system_sandbox_policy: Option<FileSystemSandboxPolicy>,  // 新文件系统策略
    network_sandbox_policy: Option<NetworkSandboxPolicy>,         // 新网络策略
) -> Result<EffectiveSandboxPolicies, ResolveSandboxPoliciesError>
```

**目的**：
- 向后兼容：支持旧的 `SandboxPolicy` 配置
- 向前扩展：支持新的分离策略（文件系统/网络独立配置）
- 策略验证：确保遗留策略和分离策略语义一致

### 3. Bubblewrap 参数构建

```rust
// bwrap.rs
pub(crate) fn create_bwrap_command_args(
    command: Vec<String>,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    sandbox_policy_cwd: &Path,
    command_cwd: &Path,
    options: BwrapOptions,
) -> Result<BwrapArgs>
```

**挂载顺序**（关键安全属性）：
1. `--ro-bind / /` - 只读根文件系统
2. `--dev /dev` - 最小设备树（null, zero, full, random, urandom, tty）
3. 不可读祖先目录掩码（保护可写根目录的父目录）
4. `--bind <root> <root>` - 重新绑定可写根目录
5. `--ro-bind <subpath>` - 在可写根内应用只读保护（如 `.git`, `.codex`）
6. 嵌套不可读目录掩码

### 4. Seccomp 网络过滤

```rust
// landlock.rs
fn install_network_seccomp_filter_on_current_thread(
    mode: NetworkSeccompMode,
) -> Result<(), SandboxErr>
```

**两种模式**：

| 模式 | 描述 | 允许的系统调用 |
|------|------|---------------|
| `Restricted` | 完全网络隔离 | 仅 AF_UNIX socket |
| `ProxyRouted` | 代理路由模式 | AF_INET/AF_INET6 socket，禁止 AF_UNIX |

**被阻止的系统调用**：
- `connect`, `accept`, `accept4`, `bind`, `listen`
- `getpeername`, `getsockname`, `shutdown`
- `sendto`, `sendmmsg`, `recvmmsg`
- `getsockopt`, `setsockopt`
- `ptrace`, `io_uring_setup/enter/register`

### 5. 托管代理路由（Managed Proxy）

```rust
// proxy_routing.rs
pub(crate) fn prepare_host_proxy_route_spec() -> io::Result<String>;
pub(crate) fn activate_proxy_routes_in_netns(spec: &str) -> io::Result<()>;
```

**架构**：

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│   User Command  │◄───────►│  Local Bridge   │◄───────►│  Host Bridge    │
│   (in netns)    │  TCP    │  (localhost)    │  UDS    │  (outside)      │
└─────────────────┘         └─────────────────┘         └────────┬────────┘
                                                                  │
                                                                  ▼
                                                           ┌──────────────┐
                                                           │ Proxy Server │
                                                           │ (loopback)   │
                                                           └──────────────┘
```

**目的**：
- 允许沙箱内命令通过特定代理访问网络
- 阻止直接网络访问（通过 `--unshare-net` + seccomp）
- 阻止 AF_UNIX socket 创建（防止绕过代理）

---

## 具体技术实现

### 关键数据结构

#### 1. CLI 参数结构（LandlockCommand）

```rust
#[derive(Debug, Parser)]
pub struct LandlockCommand {
    #[arg(long = "sandbox-policy-cwd")]
    pub sandbox_policy_cwd: PathBuf,
    
    #[arg(long = "command-cwd", hide = true)]
    pub command_cwd: Option<PathBuf>,
    
    #[arg(long = "sandbox-policy", hide = true)]
    pub sandbox_policy: Option<SandboxPolicy>,
    
    #[arg(long = "file-system-sandbox-policy", hide = true)]
    pub file_system_sandbox_policy: Option<FileSystemSandboxPolicy>,
    
    #[arg(long = "network-sandbox-policy", hide = true)]
    pub network_sandbox_policy: Option<NetworkSandboxPolicy>,
    
    #[arg(long = "use-legacy-landlock", hide = true)]
    pub use_legacy_landlock: bool,
    
    #[arg(long = "apply-seccomp-then-exec", hide = true)]
    pub apply_seccomp_then_exec: bool,
    
    #[arg(long = "allow-network-for-proxy", hide = true)]
    pub allow_network_for_proxy: bool,
    
    #[arg(long = "proxy-route-spec", hide = true)]
    pub proxy_route_spec: Option<String>,
    
    #[arg(long = "no-proc", default_value_t = false)]
    pub no_proc: bool,
    
    #[arg(trailing_var_arg = true)]
    pub command: Vec<String>,
}
```

#### 2. Bubblewrap 网络模式

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum BwrapNetworkMode {
    #[default]
    FullAccess,    // 保持主机网络命名空间访问
    Isolated,      // 移除主机网络命名空间访问
    ProxyOnly,     // 代理专用模式（unshare net + 代理桥）
}
```

#### 3. 代理路由规范

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct ProxyRouteSpec {
    routes: Vec<ProxyRouteEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct ProxyRouteEntry {
    env_key: String,    // 如 "HTTP_PROXY"
    uds_path: PathBuf,  // Unix Domain Socket 路径
}
```

### 关键流程

#### 1. 主执行流程

```
run_main()
    │
    ├──► 解析 CLI 参数 (LandlockCommand)
    │
    ├──► resolve_sandbox_policies() - 解析/验证策略
    │
    ├──► 检查 apply_seccomp_then_exec 标志
    │    │
    │    ├──► true: 内层阶段
    │    │    ├──► 激活代理路由（如果需要）
    │    │    ├──► apply_sandbox_policy_to_current_thread()
    │    │    │    ├──► set_no_new_privs()
    │    │    │    └──► install_network_seccomp_filter_on_current_thread()
    │    │    └──► exec_or_panic() - 执行用户命令
    │    │
    │    └──► false: 外层阶段
    │         ├──► 检查是否需要 bwrap（非完全磁盘写入）
    │         │    │
    │         │    ├──► 不需要: 直接应用 seccomp 并执行
    │         │    │
    │         │    └──► 需要: 构建 bwrap 命令
    │         │         ├──► preflight_proc_mount_support() - 测试 /proc 挂载
    │         │         ├──► build_inner_seccomp_command() - 构建内层命令
    │         │         └──► run_bwrap_with_proc_fallback() - 执行 bwrap
    │         │              └──► exec_bwrap() - 系统或内嵌 bwrap
    │         │
    │         └──► 遗留路径（use_legacy_landlock）
    │              └──► apply_sandbox_policy_to_current_thread() + Landlock
```

#### 2. Bubblewrap 参数构建流程

```
create_bwrap_command_args()
    │
    ├──► 完全磁盘写入 + 完全网络访问？
    │    └──► 返回原始命令（无沙箱开销）
    │
    └──► create_bwrap_flags()
         │
         ├──► create_filesystem_args() - 构建文件系统参数
         │    ├──► 完全读取访问？
         │    │    ├──► true: --ro-bind / /
         │    │    └──► false: --tmpfs / + 特定 --ro-bind
         │    ├──► --dev /dev
         │    ├──► 处理不可读祖先（掩码）
         │    ├──► 绑定可写根目录
         │    ├──► 应用只读子路径保护
         │    └──► 处理嵌套不可读目录
         │
         ├──► --unshare-user, --unshare-pid
         ├──► 网络隔离？--unshare-net
         └──► --proc /proc（除非 --no-proc）
```

#### 3. 代理路由建立流程

```
prepare_host_proxy_route_spec() [在父命名空间执行]
    │
    ├──► plan_proxy_routes() - 从环境变量解析代理配置
    │    └──► parse_loopback_proxy_endpoint() - 只接受回环地址
    │
    ├──► create_proxy_socket_dir() - 创建 UDS 目录（0700 权限）
    │
    ├──► spawn_host_bridge() [每个唯一端点]
    │    └──► run_host_bridge() - UDS 监听，转发到 TCP
    │
    ├──► spawn_proxy_socket_dir_cleanup_worker() - 清理工作进程
    │
    └──► 返回 ProxyRouteSpec JSON

activate_proxy_routes_in_netns(spec) [在子命名空间执行]
    │
    ├──► 解析 ProxyRouteSpec
    │
    ├──► spawn_local_bridge() [每个 UDS 路径]
    │    └──► run_local_bridge() - TCP 监听（localhost），转发到 UDS
    │
    └──► rewrite_proxy_env_value() - 重写环境变量指向本地端口
```

### 安全机制详解

#### 1. 符号链接攻击防护

```rust
fn find_symlink_in_path(target_path: &Path, allowed_write_paths: &[PathBuf]) -> Option<PathBuf> {
    // 遍历路径的每个组件
    for component in target_path.components() {
        // ...
        if metadata.file_type().is_symlink()
            && is_within_allowed_write_paths(&current, allowed_write_paths)
        {
            return Some(current);  // 发现可写根内的符号链接
        }
    }
    None
}

// 在 append_read_only_subpath_args 中：
if let Some(symlink_path) = find_symlink_in_path(subpath, allowed_write_paths) {
    args.push("--ro-bind".to_string());
    args.push("/dev/null".to_string());  // 用 /dev/null 覆盖符号链接
    args.push(path_to_string(&symlink_path));
    return;
}
```

**目的**：防止攻击者通过替换 `.codex` 或 `.git` 符号链接来绕过只读保护。

#### 2. 缺失路径组件防护

```rust
fn find_first_non_existent_component(target_path: &Path) -> Option<PathBuf> {
    // 遍历路径，找到第一个不存在的组件
    for component in target_path.components() {
        // ...
        if !current.exists() {
            return Some(current);
        }
    }
    None
}

// 用 /dev/null 绑定到第一个缺失组件，防止创建保护路径
```

#### 3. /proc 挂载预检

```rust
fn preflight_proc_mount_support(...) -> bool {
    // 在子进程中运行测试 bwrap 命令
    let stderr = run_bwrap_in_child_capture_stderr(preflight_argv);
    // 检查是否包含 "Can't mount proc" 错误
    !is_proc_mount_failure(stderr.as_str())
}
```

**目的**：某些容器环境（如 Docker）可能禁止挂载 proc，预检允许优雅降级到 `--no-proc`。

---

## 关键代码路径与文件引用

### 源文件结构

```
codex-rs/linux-sandbox/
├── Cargo.toml              # crate 配置，定义 bin 和 lib
├── build.rs                # 构建脚本，编译内嵌 bubblewrap
├── config.h                # bubblewrap 构建配置
├── README.md               # 使用文档和行为说明
├── BUILD.bazel             # Bazel 构建配置
│
├── src/
│   ├── main.rs             # 可执行文件入口（简单委托）
│   ├── lib.rs              # 库入口，条件编译 Linux 模块
│   ├── linux_run_main.rs   # 主逻辑实现（~700行）
│   ├── linux_run_main_tests.rs  # 单元测试
│   ├── bwrap.rs            # bubblewrap 参数构建（~1000行）
│   ├── landlock.rs         # seccomp/Landlock 应用（~325行）
│   ├── launcher.rs         # bwrap 启动器（系统/内嵌）
│   ├── proxy_routing.rs    # 代理路由实现（~800行）
│   └── vendored_bwrap.rs   # 内嵌 bwrap FFI 接口
│
└── tests/
    ├── all.rs              # 测试聚合入口
    └── suite/
        ├── mod.rs          # 测试模块声明
        ├── landlock.rs     # 沙箱功能集成测试（~766行）
        └── managed_proxy.rs # 代理模式集成测试（~312行）
```

### 关键代码路径

| 功能 | 文件 | 函数/结构 |
|------|------|----------|
| 主入口 | `src/main.rs` | `main()` |
| 库入口 | `src/lib.rs` | `run_main()` |
| 策略解析 | `src/linux_run_main.rs` | `LandlockCommand`, `resolve_sandbox_policies()` |
| bwrap 参数 | `src/bwrap.rs` | `create_bwrap_command_args()`, `create_filesystem_args()` |
| seccomp 过滤 | `src/landlock.rs` | `install_network_seccomp_filter_on_current_thread()` |
| bwrap 启动 | `src/launcher.rs` | `exec_bwrap()`, `preferred_bwrap_launcher()` |
| 代理路由 | `src/proxy_routing.rs` | `prepare_host_proxy_route_spec()`, `activate_proxy_routes_in_netns()` |
| 内嵌 bwrap | `src/vendored_bwrap.rs` | `exec_vendored_bwrap()` |
| 构建脚本 | `build.rs` | `try_build_vendored_bwrap()` |

### 外部依赖

| crate | 用途 |
|-------|------|
| `clap` | CLI 参数解析 |
| `codex-core` | 错误类型和工具 |
| `codex-protocol` | 沙箱策略协议定义 |
| `landlock` | Landlock LSM 绑定（遗留模式） |
| `seccompiler` | seccomp BPF 编译 |
| `libc` | 系统调用 |
| `serde`/`serde_json` | 策略序列化 |
| `url` | 代理 URL 解析 |

---

## 依赖与外部交互

### 调用方（上游）

1. **codex-core/src/sandboxing/mod.rs**
   - `SandboxManager::transform()` 创建 `ExecRequest`
   - 调用 `create_linux_sandbox_command_args_for_policies()` 构建参数

2. **codex-core/src/landlock.rs**
   - `spawn_command_under_linux_sandbox()` 异步启动沙箱命令
   - `create_linux_sandbox_command_args_for_policies()` 构建命令行

3. **codex-exec CLI**
   - 通过 `arg0` 检测（`codex-linux-sandbox`）委托执行

### 被调用方（下游）

1. **系统 bubblewrap** (`/usr/bin/bwrap`)
   - 优先使用系统安装版本
   - 需要 setuid root 或 CAP_SYS_ADMIN

2. **内嵌 bubblewrap** (`vendored_bwrap`)
   - 当系统 bwrap 不可用时回退
   - 通过 `build.rs` 编译，C 源码在 `codex-rs/vendor/bubblewrap`

3. **Linux 内核**
   - `prctl(PR_SET_NO_NEW_PRIVS)` - 阻止特权提升
   - `seccomp` - 系统调用过滤
   - `unshare` - 命名空间隔离（通过 bwrap）
   - `Landlock` LSM - 文件系统访问控制（遗留模式）

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_BWRAP_SOURCE_DIR` | 自定义 bubblewrap 源码路径 |
| `CODEX_HOME` | 代理 socket 目录父路径 |
| `TMPDIR` | 临时目录（用于代理 socket） |
| `HTTP_PROXY`/`HTTPS_PROXY`/... | 代理配置（托管代理模式） |

---

## 风险、边界与改进建议

### 已知风险

#### 1. 容器环境兼容性

**问题**：在 Docker 等容器中，`--proc /proc` 挂载可能失败。

**缓解**：`preflight_proc_mount_support()` 检测并自动降级到 `--no-proc`。

**残余风险**：某些容器配置可能仍然阻止 bwrap 正常工作。

#### 2. 架构支持限制

**问题**：seccomp 过滤器仅支持 x86_64 和 aarch64。

```rust
if cfg!(target_arch = "x86_64") {
    TargetArch::x86_64
} else if cfg!(target_arch = "aarch64") {
    TargetArch::aarch64
} else {
    unimplemented!("unsupported architecture for seccomp filter");
}
```

**影响**：其他架构无法使用网络隔离功能。

#### 3. 代理路由竞争条件

**问题**：代理 socket 目录清理依赖 PID 检测（`is_pid_alive`），在 PID 命名空间嵌套场景中可能误判。

#### 4. 遗留 Landlock 模式限制

**问题**：
- 不支持受限读取策略（`Restricted` read-only）
- 不支持嵌套策略（如可写根内的只读子路径）

**代码体现**：
```rust
if !sandbox_policy.has_full_disk_read_access() {
    return Err(CodexErr::UnsupportedOperation(
        "Restricted read-only access is not supported by the legacy Linux Landlock filesystem backend."
            .to_string(),
    ));
}
```

### 边界条件

| 边界 | 行为 |
|------|------|
| 完全磁盘写入 + 完全网络 | 跳过 bwrap，直接执行（无沙箱开销） |
| 完全磁盘写入 + 网络隔离 | 仅使用 bwrap 进行网络命名空间隔离 |
| 缺失可写根目录 | 静默跳过（允许跨平台配置） |
| 符号链接在可写根内 | 用 `/dev/null` 覆盖，阻止替换攻击 |
| 保护路径不存在 | 绑定 `/dev/null` 到第一个缺失组件 |
| 代理环境变量指向非回环 | 忽略（仅支持 localhost/127.0.0.1/::1） |

### 改进建议

#### 1. 增强容器检测

```rust
// 建议添加
fn detect_container_environment() -> ContainerType {
    if Path::new("/.dockerenv").exists() {
        return ContainerType::Docker;
    }
    if std::fs::read_to_string("/proc/1/cgroup")
        .map(|c| c.contains("containerd") || c.contains("kubepods"))
        .unwrap_or(false) 
    {
        return ContainerType::Kubernetes;
    }
    ContainerType::None
}
```

#### 2. 支持更多架构

添加对 `riscv64`, `arm`, `ppc64le` 等架构的 seccomp 支持。

#### 3. 代理路由改进

- 支持非回环代理（通过配置白名单）
- 添加代理健康检查
- 支持 SOCKS 代理的 UDP 关联

#### 4. 可观测性增强

```rust
// 建议添加结构化日志
#[derive(Debug, Serialize)]
struct SandboxEvent {
    timestamp: u64,
    event_type: SandboxEventType,
    policy: SandboxPolicy,
    command: Vec<String>,
    result: SandboxResult,
}
```

#### 5. 策略验证工具

提供独立命令验证沙箱策略效果：

```bash
codex-linux-sandbox --dry-run --file-system-sandbox-policy='...' -- echo test
# 输出：将应用的 bwrap 参数和 seccomp 规则
```

#### 6. 测试覆盖

- 添加更多边界条件测试（如非常长路径、特殊字符）
- 添加性能基准测试（bwrap 启动开销）
- 添加模糊测试（策略解析）

---

## 参考文档

- [Bubblewrap 官方文档](https://github.com/containers/bubblewrap)
- [Linux Landlock LSM](https://docs.kernel.org/userspace-api/landlock.html)
- [Linux seccomp](https://www.kernel.org/doc/Documentation/prctl/seccomp_filter.txt)
- `codex-rs/linux-sandbox/README.md` - 详细行为说明
- `codex-rs/protocol/src/permissions.rs` - 策略协议定义
