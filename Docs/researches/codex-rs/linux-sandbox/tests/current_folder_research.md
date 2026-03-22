# codex-rs/linux-sandbox/tests 深度研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/linux-sandbox/tests/` 是 Codex 项目 Linux 沙箱组件的**集成测试套件**，负责验证 `codex-linux-sandbox` 二进制文件的核心沙箱功能。该测试目录与主代码目录 `codex-rs/linux-sandbox/src/` 形成测试-被测关系。

### 1.2 核心职责

该测试套件承担以下验证职责：

1. **文件系统隔离验证**：验证 bubblewrap (bwrap) 和 Landlock 实现的文件系统沙箱策略，包括只读/读写权限控制、敏感目录保护（如 `.git`、`.codex`）
2. **网络隔离验证**：验证 seccomp 过滤器对网络系统调用的拦截能力，包括 socket 创建、连接、DNS 解析等
3. **托管代理模式验证**：验证 `--allow-network-for-proxy` 模式下的网络代理路由功能
4. **安全策略边界验证**：验证 `no_new_privs`、seccomp、namespace 隔离等安全机制的正确启用
5. **跨架构兼容性**：针对 x86_64 和 aarch64 架构设置不同的超时阈值

### 1.3 测试架构

```
codex-rs/linux-sandbox/tests/
├── all.rs                 # 测试入口，聚合所有测试模块
└── suite/
    ├── mod.rs             # 测试模块聚合
    ├── landlock.rs        # 文件系统+网络沙箱测试（766行）
    └── managed_proxy.rs   # 托管代理模式测试（312行）
```

测试采用 Rust 集成测试模式，通过 `cargo test -p codex-linux-sandbox` 执行。

---

## 2. 功能点目的

### 2.1 文件系统沙箱测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `test_root_read` | 验证根目录 `/` 的读取权限在默认策略下可用 |
| `test_root_write` | 验证对根目录的写入被禁止（`#[should_panic]`） |
| `test_dev_null_write` | 验证 `/dev/null` 写入权限（bwrap 特殊处理） |
| `test_writable_root` | 验证显式指定的可写目录允许写入 |
| `sandbox_ignores_missing_writable_roots_under_bwrap` | 验证不存在的可写根目录被静默跳过 |
| `sandbox_blocks_git_and_codex_writes_inside_writable_root` | 验证 `.git` 和 `.codex` 子目录在可写根内仍被保护 |
| `sandbox_blocks_codex_symlink_replacement_attack` | 验证符号链接替换攻击被阻止 |
| `sandbox_blocks_explicit_split_policy_carveouts_under_bwrap` | 验证细粒度 split policy 的拒绝规则生效 |
| `sandbox_reenables_writable_subpaths_under_unreadable_parents` | 验证嵌套策略：不可读父目录下的可写子目录仍可用 |
| `sandbox_blocks_root_read_carveouts_under_bwrap` | 验证根目录读取权限的细粒度剥离 |
| `bwrap_populates_minimal_dev_nodes` | 验证 bwrap 创建最小设备节点集 |
| `bwrap_preserves_writable_dev_shm_bind_mount` | 验证 `/dev/shm` 可写绑定挂载 |

### 2.2 网络安全测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `sandbox_blocks_curl` | 验证 curl 网络访问被阻止 |
| `sandbox_blocks_wget` | 验证 wget 网络访问被阻止 |
| `sandbox_blocks_ping` | 验证 ICMP (raw socket) 被阻止 |
| `sandbox_blocks_nc` | 验证 netcat TCP 连接被阻止 |
| `sandbox_blocks_ssh` | 验证 SSH 连接被阻止 |
| `sandbox_blocks_getent` | 验证 DNS 解析 (getent) 被阻止 |
| `sandbox_blocks_dev_tcp_redirection` | 验证 bash `/dev/tcp` 重定向被阻止 |

### 2.3 托管代理模式测试 (`managed_proxy.rs`)

| 测试函数 | 目的 |
|---------|------|
| `managed_proxy_mode_fails_closed_without_proxy_env` | 验证无代理环境变量时失败关闭 |
| `managed_proxy_mode_routes_through_bridge_and_blocks_direct_egress` | 验证流量经代理桥路由且阻止直接出口 |
| `managed_proxy_mode_denies_af_unix_creation_for_user_command` | 验证用户命令无法创建 AF_UNIX socket |

### 2.4 安全机制测试

| 测试函数 | 目的 |
|---------|------|
| `test_no_new_privs_is_enabled` | 验证 `PR_SET_NO_NEW_PRIVS` 已启用 |
| `test_timeout` | 验证命令超时机制（`#[should_panic]`） |

---

## 3. 具体技术实现

### 3.1 测试基础设施

#### 3.1.1 超时配置（架构感知）

```rust
// codex-rs/linux-sandbox/tests/suite/landlock.rs:28-41
#[cfg(not(target_arch = "aarch64"))]
const SHORT_TIMEOUT_MS: u64 = 200;
#[cfg(target_arch = "aarch64")]
const SHORT_TIMEOUT_MS: u64 = 5_000;

#[cfg(not(target_arch = "aarch64"))]
const LONG_TIMEOUT_MS: u64 = 1_000;
#[cfg(target_arch = "aarch64")]
const LONG_TIMEOUT_MS: u64 = 5_000;
```

**设计原因**：GitHub CI 的 ARM64 运行器性能较低，需要更长超时。

#### 3.1.2 测试辅助函数

```rust
// 核心测试执行器
async fn run_cmd_result_with_writable_roots(
    cmd: &[&str],
    writable_roots: &[PathBuf],
    timeout_ms: u64,
    use_legacy_landlock: bool,
    network_access: bool,
) -> Result<ExecToolCallOutput>

// 策略化测试执行器
async fn run_cmd_result_with_policies(
    cmd: &[&str],
    sandbox_policy: SandboxPolicy,
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    timeout_ms: u64,
    use_legacy_landlock: bool,
) -> Result<ExecToolCallOutput>
```

### 3.2 被测系统架构

#### 3.2.1 双层执行模型

```
┌─────────────────────────────────────────────────────────────┐
│  Outer Stage (bubblewrap)                                   │
│  ├── --new-session      (新会话)                            │
│  ├── --die-with-parent  (父进程死亡时退出)                   │
│  ├── --unshare-user     (用户命名空间)                       │
│  ├── --unshare-pid      (PID 命名空间)                       │
│  ├── --unshare-net      (网络命名空间，可选)                  │
│  ├── --proc /proc       (新 proc 挂载)                      │
│  └── 文件系统绑定挂载策略                                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Inner Stage (codex-linux-sandbox --apply-seccomp-then-exec)│
│  ├── PR_SET_NO_NEW_PRIVS                                    │
│  ├── seccomp 网络过滤器                                      │
│  └── execvp 用户命令                                         │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2.2 文件系统策略转换

```rust
// SandboxPolicy (legacy) ──► FileSystemSandboxPolicy (split)
//                              └── NetworkSandboxPolicy (split)

// 示例：WorkspaceWrite 策略
SandboxPolicy::WorkspaceWrite {
    writable_roots: vec!["/workspace"],
    read_only_access: FullAccess,
    network_access: false,
    exclude_tmpdir_env_var: true,
    exclude_slash_tmp: true,
}
```

#### 3.2.3 seccomp 网络过滤器

```rust
// codex-rs/linux-sandbox/src/landlock.rs:164-264
fn install_network_seccomp_filter_on_current_thread(mode: NetworkSeccompMode) {
    let mut rules: BTreeMap<i64, Vec<SeccompRule>> = BTreeMap::new();
    
    // 基础拒绝规则
    deny_syscall(&mut rules, libc::SYS_ptrace);
    deny_syscall(&mut rules, libc::SYS_io_uring_setup);
    
    match mode {
        NetworkSeccompMode::Restricted => {
            // 完全网络隔离：拒绝 connect/accept/bind/listen 等
            deny_syscall(&mut rules, libc::SYS_connect);
            deny_syscall(&mut rules, libc::SYS_accept);
            // socket: 仅允许 AF_UNIX
            let unix_only_rule = SeccompRule::new(vec![SeccompCondition::new(
                0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_UNIX as u64,
            )?])?;
            rules.insert(libc::SYS_socket, vec![unix_only_rule]);
        }
        NetworkSeccompMode::ProxyRouted => {
            // 代理模式：仅允许 AF_INET/AF_INET6，拒绝 AF_UNIX
            let deny_non_ip_socket = SeccompRule::new(vec![
                SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET as u64)?,
                SeccompCondition::new(0, SeccompCmpArgLen::Dword, SeccompCmpOp::Ne, libc::AF_INET6 as u64)?,
            ])?;
            rules.insert(libc::SYS_socket, vec![deny_non_ip_socket]);
        }
    }
    
    let filter = SeccompFilter::new(
        rules,
        SeccompAction::Allow,                     // 默认允许
        SeccompAction::Errno(libc::EPERM as u32), // 匹配时返回 EPERM
        TargetArch::x86_64, // 或 aarch64
    )?;
    apply_filter(&filter.try_into()?)?;
}
```

### 3.3 托管代理模式实现

#### 3.3.1 代理路由架构

```
┌─────────────────┐     HTTP_PROXY=http://127.0.0.1:<port>
│  Sandboxed App  │◄──────────────────────────────────────┐
└────────┬────────┘                                       │
         │                                                │
         │  TCP 127.0.0.1:<port>                          │
         ▼                                                │
┌─────────────────┐     Unix Domain Socket                │
│  Local Bridge   │◄───────────────────────────────────┐  │
│  (in netns)     │                                    │  │
└────────┬────────┘                                    │  │
         │                                             │  │
         │ UDS                                         │  │
         ▼                                             │  │
┌─────────────────┐     TCP                             │  │
│  Host Bridge    │─────────────────────────────────────┘  │
│  (on host)      │     ◄── 实际代理服务器 (127.0.0.1:8080)  │
└─────────────────┘                                        │
         ▲                                                 │
         │                                                 │
         └─────────────────────────────────────────────────┘
              从环境变量 HTTP_PROXY 解析的端点
```

#### 3.3.2 代理环境变量列表

```rust
// codex-rs/linux-sandbox/src/proxy_routing.rs:26-41
const PROXY_ENV_KEYS: &[&str] = &[
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "FTP_PROXY",
    "YARN_HTTP_PROXY", "YARN_HTTPS_PROXY",
    "NPM_CONFIG_HTTP_PROXY", "NPM_CONFIG_HTTPS_PROXY", "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY", "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY", "DOCKER_HTTPS_PROXY",
];
```

### 3.4 关键数据结构

#### 3.4.1 沙箱策略类型

```rust
// codex-protocol 定义
pub enum SandboxPolicy {
    DangerFullAccess,
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    WorkspaceWrite { writable_roots: Vec<AbsolutePathBuf>, ... },
}

pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,  // Unrestricted | Restricted | ExternalSandbox
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub struct FileSystemSandboxEntry {
    pub path: FileSystemPath,         // Path | Special
    pub access: FileSystemAccessMode, // Read | Write | None
}
```

#### 3.4.2 Bubblewrap 参数构建

```rust
// codex-rs/linux-sandbox/src/bwrap.rs:82-85
pub(crate) struct BwrapArgs {
    pub args: Vec<String>,           // bwrap 命令行参数
    pub preserved_files: Vec<File>,  // 需要保持打开的文件描述符
}

pub(crate) struct BwrapOptions {
    pub mount_proc: bool,            // 是否挂载 /proc
    pub network_mode: BwrapNetworkMode,  // FullAccess | Isolated | ProxyOnly
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试调用链

```
test function (landlock.rs)
    └── run_cmd_result_with_writable_roots()
        └── process_exec_tool_call()  [codex-rs/core/src/exec.rs:183]
            └── build_exec_request()
                └── 根据平台选择沙箱类型
                    └── SandboxType::LinuxSeccomp
                        └── 调用 codex-linux-sandbox 二进制
```

### 4.2 沙箱二进制执行流程

```
main() [src/main.rs]
    └── run_main() [src/lib.rs]
        └── linux_run_main::run_main() [src/linux_run_main.rs:99]
            ├── resolve_sandbox_policies()  [line 273-346]
            │   └── 处理 legacy/split 策略转换
            ├── Outer Stage:
            │   └── run_bwrap_with_proc_fallback() [line 399-437]
            │       └── exec_bwrap() [src/launcher.rs:19]
            │           ├── exec_system_bwrap()  [优先]
            │           └── exec_vendored_bwrap() [src/vendored_bwrap.rs]
            └── Inner Stage:
                └── apply_sandbox_policy_to_current_thread() [src/landlock.rs:42]
                    ├── set_no_new_privs()
                    └── install_network_seccomp_filter_on_current_thread()
```

### 4.3 关键文件映射

| 功能领域 | 文件路径 | 说明 |
|---------|---------|------|
| 测试入口 | `tests/all.rs` | 集成测试聚合入口 |
| 文件系统测试 | `tests/suite/landlock.rs` | 主要测试文件（766行） |
| 代理测试 | `tests/suite/managed_proxy.rs` | 代理模式测试（312行） |
| 主逻辑 | `src/linux_run_main.rs` | 沙箱主执行逻辑（709行） |
| bwrap 参数 | `src/bwrap.rs` | Bubblewrap 参数构建 |
| seccomp/Landlock | `src/landlock.rs` | 进程内沙箱原语 |
| 代理路由 | `src/proxy_routing.rs` | 托管代理模式实现 |
| 启动器 | `src/launcher.rs` | bwrap 执行器选择 |
| 内嵌 bwrap | `src/vendored_bwrap.rs` | 编译时 bwrap 集成 |
| 构建脚本 | `build.rs` | 编译时 bwrap 编译 |
| 单元测试 | `src/linux_run_main_tests.rs` | 主逻辑单元测试 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

#### 5.1.1 系统依赖

| 依赖 | 用途 | 检测/回退 |
|-----|------|----------|
| `/usr/bin/bwrap` | 系统 bubblewrap | 不存在时使用内嵌版本 |
| `libcap` | Linux capabilities | 编译时通过 pkg-config 检测 |
| `/dev/shm` | 共享内存设备 | 测试时动态检测存在性 |
| `python3` | AF_UNIX 测试 | 测试时动态检测 |

#### 5.1.2 Rust 依赖

```toml
# Cargo.toml 关键依赖
[target.'cfg(target_os = "linux")'.dependencies]
landlock = { workspace = true }      # 文件系统沙箱（legacy）
seccompiler = { workspace = true }   # seccomp BPF 编译
libc = { workspace = true }          # 系统调用
clap = { workspace = true }          # CLI 解析

[target.'cfg(target_os = "linux")'.dev-dependencies]
tokio = { workspace = true }         # 异步运行时
tempfile = { workspace = true }      # 临时文件/目录
pretty_assertions = { workspace = true }
```

### 5.2 跨 crate 依赖

```
codex-linux-sandbox
    ├── codex-core                   # ExecParams, process_exec_tool_call
    ├── codex-protocol               # SandboxPolicy, FileSystemSandboxPolicy
    └── codex-utils-absolute-path    # AbsolutePathBuf
```

### 5.3 编译时集成

```rust
// build.rs: 编译时 bubblewrap 集成
fn try_build_vendored_bwrap() -> Result<(), String> {
    let libcap = pkg_config::Config::new().probe("libcap")?;
    
    cc::Build::new()
        .file(src_dir.join("bubblewrap.c"))
        .file(src_dir.join("bind-mount.c"))
        .file(src_dir.join("network.c"))
        .file(src_dir.join("utils.c"))
        .define("main", Some("bwrap_main"))  // 重命名 main 为 bwrap_main
        .compile("build_time_bwrap");
}
```

### 5.4 测试跳过条件

```rust
// 条件跳过检测
async fn should_skip_bwrap_tests() -> bool {
    // 检测 bwrap 是否可用
    // 检测错误输出是否包含 "build-time bubblewrap is not available"
}

async fn managed_proxy_skip_reason() -> Option<String> {
    // 检测命名空间权限
    // 检测错误是否包含 "No permissions to create a new namespace"
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试环境依赖风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| bwrap 不可用 | CI 环境可能缺少 bubblewrap | `should_skip_bwrap_tests()` 自动跳过 |
| 命名空间权限不足 | 容器环境可能禁止 unshare | `managed_proxy_skip_reason()` 检测 |
| /proc 挂载失败 | 受限容器可能禁止 --proc | `preflight_proc_mount_support()` 回退到 --no-proc |
| 架构性能差异 | ARM64 CI 运行器较慢 | 架构特定的超时配置 |

#### 6.1.2 安全边界风险

```rust
// 风险：测试本身在沙箱中运行，可能无法测试完整功能
// AGENTS.md 明确说明：
// "You operate in a sandbox where `CODEX_SANDBOX_NETWORK_DISABLED=1` will be set"
// "checks for `CODEX_SANDBOX=seatbelt` are also often used to early exit out of tests"
```

#### 6.1.3 竞态条件风险

```rust
// proxy_routing.rs:375-401
// cleanup worker 通过 fork + 轮询 PID 存活状态来清理
// 可能存在 PID 复用风险（虽然概率极低）
fn spawn_proxy_socket_dir_cleanup_worker(...) {
    let pid = unsafe { libc::fork() };
    // ... 子进程轮询 bridge_pid 存活状态
}
```

### 6.2 边界情况

#### 6.2.1 文件系统策略边界

```rust
// 边界：符号链接处理
fn find_symlink_in_path(target_path: &Path, allowed_write_paths: &[PathBuf]) -> Option<PathBuf> {
    // 遍历路径组件，检测是否在可写路径内存在符号链接
    // 防止攻击：.codex -> ./decoy
}

// 边界：不存在的路径处理
fn find_first_non_existent_component(target_path: &Path) -> Option<PathBuf> {
    // 对首个不存在的组件挂载 /dev/null
    // 防止攻击者创建受保护路径层次结构
}
```

#### 6.2.2 网络策略边界

```rust
// 边界：recvfrom 被允许（为了 cargo clippy 等工具）
// 注意：这允许部分网络接收功能
deny_syscall(&mut rules, libc::SYS_sendto);
// deny_syscall(&mut rules, libc::SYS_recvfrom);  // 被注释掉
```

### 6.3 改进建议

#### 6.3.1 测试覆盖率

1. **添加更多网络工具测试**：目前测试覆盖 curl/wget/nc/ssh，可添加 `telnet`、`ftp`、`scp` 等
2. **添加文件系统竞争测试**：多进程同时访问沙箱边界路径
3. **添加大文件/目录测试**：验证沙箱在大规模文件操作下的性能

#### 6.3.2 代码改进

```rust
// 建议：统一错误处理
// 当前代码中多处使用 panic! 处理错误，建议改为返回 Result
// 例如：exec_or_panic() 可考虑返回 Result 供调用方处理

// 建议：减少 unsafe 代码块
// 当前 fork/pipe/ioctl 等调用包裹在 unsafe 中
// 可考虑封装为更安全的抽象
```

#### 6.3.3 可观测性

```rust
// 建议：添加结构化日志
// 当前使用 eprintln! 输出跳过原因，建议使用 tracing  crate
// 便于在 CI 中收集和分析测试结果
```

#### 6.3.4 配置灵活性

```rust
// 建议：环境变量覆盖超时值
// 当前超时值硬编码，建议支持：
// CODEX_SANDBOX_TEST_TIMEOUT_SHORT_MS
// CODEX_SANDBOX_TEST_TIMEOUT_LONG_MS
```

### 6.4 维护注意事项

1. **bwrap 版本兼容性**：内嵌 bubblewrap 源码需定期同步上游安全更新
2. **seccomp 规则更新**：新内核可能添加新网络相关系统调用，需同步更新过滤器
3. **架构支持**：新增架构时需更新 `seccompiler::TargetArch` 匹配
4. **Landlock ABI 演进**：`landlock::ABI::V5` 需跟踪上游更新

---

## 7. 总结

`codex-rs/linux-sandbox/tests` 是一个设计完善的集成测试套件，通过双层沙箱架构（bubblewrap + seccomp）验证 Linux 平台的文件系统和网络安全隔离。测试覆盖了主要的安全边界，具备良好的架构感知超时配置和环境适应能力。主要技术亮点包括：

1. **分层安全策略**：legacy/split 策略兼容，支持细粒度权限控制
2. **托管代理模式**：创新的网络隔离+代理路由方案
3. **健壮的错误处理**：全面的测试跳过条件检测
4. **跨架构支持**：x86_64 和 aarch64 的差异化处理

该测试套件是保障 Codex Linux 沙箱安全性的关键防线，建议持续维护并扩展覆盖边界情况。
