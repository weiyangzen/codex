# linux_run_main.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`linux_run_main.rs` 是 Codex Linux 沙箱的**核心协调器**，负责整个沙箱启动流程的编排。它实现了两阶段执行模型（外阶段 bubblewrap + 内阶段 seccomp），并处理各种策略组合和兼容性场景。

### 1.2 核心职责
- **参数解析**：解析命令行参数（使用 `clap`）
- **策略解析与验证**：处理新旧策略格式的兼容
- **两阶段执行编排**：外阶段（bwrap）+ 内阶段（seccomp）
- **代理路由管理**：托管代理模式的网络桥接设置
- **容器环境适配**：proc 挂载预检和回退

### 1.3 执行流程概览

```
┌─────────────────────────────────────────────────────────────────────┐
│                      两阶段执行模型                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐    exec    ┌─────────────────┐                │
│  │   外阶段 (Host) │ ─────────► │  内阶段 (Bwrap) │                │
│  │                 │            │                 │                │
│  │  • 解析参数      │            │  • 应用 seccomp │                │
│  │  • 准备代理路由  │            │  • 设置代理桥接  │                │
│  │  • 启动 bwrap   │            │  • exec 用户命令 │                │
│  │                 │            │                 │                │
│  │  [可能有 setuid] │           │  [NO_NEW_PRIVS] │                │
│  └─────────────────┘            └─────────────────┘                │
│                                                                     │
│  分离原因：bwrap 可能需要 setuid 提升权限，而 seccomp 需要           │
│           PR_SET_NO_NEW_PRIVS，两者互斥                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 关键代码位置 |
|--------|------|--------------|
| `LandlockCommand` | CLI 参数定义 | 行 21-90 |
| `run_main` | 主入口函数 | 行 99-219 |
| `resolve_sandbox_policies` | 策略解析与兼容 | 行 273-346 |
| `run_bwrap_with_proc_fallback` | 带回退的 bwrap 执行 | 行 399-437 |
| `build_inner_seccomp_command` | 内阶段命令构建 | 行 627-683 |
| `preflight_proc_mount_support` | proc 挂载预检 | 行 486-500 |
| `apply_seccomp_then_exec` 分支 | 内阶段逻辑 | 行 138-159 |

### 2.2 CLI 参数设计

```rust
pub struct LandlockCommand {
    #[arg(long = "sandbox-policy-cwd")]
    pub sandbox_policy_cwd: PathBuf,          // 策略基准目录
    
    #[arg(long = "command-cwd", hide = true)]
    pub command_cwd: Option<PathBuf>,         // 命令工作目录
    
    #[arg(long = "sandbox-policy", hide = true)]
    pub sandbox_policy: Option<SandboxPolicy>, // 遗留策略
    
    #[arg(long = "file-system-sandbox-policy", hide = true)]
    pub file_system_sandbox_policy: Option<FileSystemSandboxPolicy>, // 新文件系统策略
    
    #[arg(long = "network-sandbox-policy", hide = true)]
    pub network_sandbox_policy: Option<NetworkSandboxPolicy>, // 新网络策略
    
    #[arg(long = "use-legacy-landlock", hide = true)]
    pub use_legacy_landlock: bool,            // 使用遗留 Landlock
    
    #[arg(long = "apply-seccomp-then-exec", hide = true)]
    pub apply_seccomp_then_exec: bool,        // 内阶段模式标志
    
    #[arg(long = "allow-network-for-proxy", hide = true)]
    pub allow_network_for_proxy: bool,        // 代理网络模式
    
    #[arg(long = "proxy-route-spec", hide = true)]
    pub proxy_route_spec: Option<String>,     // 代理路由规格
    
    #[arg(long = "no-proc", default_value_t = false)]
    pub no_proc: bool,                        // 跳过 proc 挂载
    
    #[arg(trailing_var_arg = true)]
    pub command: Vec<String>,                 // 用户命令
}
```

### 2.3 策略兼容性矩阵

支持三种策略输入组合：

| 输入组合 | 处理方式 | 使用场景 |
|----------|----------|----------|
| 仅 `sandbox_policy` | 派生拆分策略 | 旧版客户端 |
| 仅拆分策略 | 派生遗留策略 | 新版客户端 |
| 两者都提供 | 验证一致性 | 过渡期兼容 |

## 3. 具体技术实现

### 3.1 核心数据结构

#### EffectiveSandboxPolicies - 解析后的有效策略
```rust
struct EffectiveSandboxPolicies {
    sandbox_policy: SandboxPolicy,                    // 遗留策略（兼容用）
    file_system_sandbox_policy: FileSystemSandboxPolicy, // 文件系统策略
    network_sandbox_policy: NetworkSandboxPolicy,     // 网络策略
}
```

#### ResolveSandboxPoliciesError - 策略解析错误
```rust
enum ResolveSandboxPoliciesError {
    PartialSplitPolicies,                    // 部分拆分策略
    SplitPoliciesRequireDirectRuntimeEnforcement(String),
    FailedToDeriveLegacyPolicy(String),
    MismatchedLegacyPolicy { provided: SandboxPolicy, derived: SandboxPolicy },
    MissingConfiguration,
}
```

#### InnerSeccompCommandArgs - 内阶段命令参数
```rust
struct InnerSeccompCommandArgs<'a> {
    sandbox_policy_cwd: &'a Path,
    command_cwd: Option<&'a Path>,
    sandbox_policy: &'a SandboxPolicy,
    file_system_sandbox_policy: &'a FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    allow_network_for_proxy: bool,
    proxy_route_spec: Option<String>,
    command: Vec<String>,
}
```

### 3.2 主执行流程

```rust
pub fn run_main() -> ! {
    // 1. 解析参数
    let LandlockCommand { ... } = LandlockCommand::parse();
    
    // 2. 验证模式兼容性
    ensure_inner_stage_mode_is_valid(apply_seccomp_then_exec, use_legacy_landlock);
    
    // 3. 解析策略
    let EffectiveSandboxPolicies { ... } = resolve_sandbox_policies(...)
        .unwrap_or_else(|err| panic!("{err}"));
    
    // 4. 验证遗留模式支持
    ensure_legacy_landlock_mode_supports_policy(...);
    
    // 5. 分支处理
    if apply_seccomp_then_exec {
        // 内阶段：应用 seccomp 后执行
        inner_stage_execution(...);
    } else if file_system_sandbox_policy.has_full_disk_write_access() && !allow_network_for_proxy {
        // 快速路径：完全访问，无需 bwrap
        direct_execution(...);
    } else if !use_legacy_landlock {
        // 外阶段：启动 bwrap，进入内阶段
        outer_stage_execution(...);
    } else {
        // 遗留路径：仅 Landlock
        legacy_execution(...);
    }
}
```

### 3.3 策略解析逻辑

```rust
fn resolve_sandbox_policies(
    sandbox_policy_cwd: &Path,
    sandbox_policy: Option<SandboxPolicy>,
    file_system_sandbox_policy: Option<FileSystemSandboxPolicy>,
    network_sandbox_policy: Option<NetworkSandboxPolicy>,
) -> Result<EffectiveSandboxPolicies, ResolveSandboxPoliciesError>
```

**解析流程**：

1. **检查拆分策略完整性**：
```rust
let split_policies = match (file_system_sandbox_policy, network_sandbox_policy) {
    (Some(fs), Some(net)) => Some((fs, net)),
    (None, None) => None,
    _ => return Err(ResolveSandboxPoliciesError::PartialSplitPolicies),
};
```

2. **处理四种输入组合**：
```rust
match (sandbox_policy, split_policies) {
    // 两者都提供：验证一致性
    (Some(legacy), Some((fs, net))) => {
        if needs_direct_runtime_enforcement(...) {
            return Ok(EffectiveSandboxPolicies { ... });
        }
        let derived = fs.to_legacy_sandbox_policy(net, sandbox_policy_cwd)?;
        if !legacy_sandbox_policies_match_semantics(&legacy, &derived, sandbox_policy_cwd) {
            return Err(ResolveSandboxPoliciesError::MismatchedLegacyPolicy { ... });
        }
        Ok(EffectiveSandboxPolicies { ... })
    }
    // 仅遗留策略：派生拆分策略
    (Some(legacy), None) => Ok(EffectiveSandboxPolicies {
        file_system_sandbox_policy: FileSystemSandboxPolicy::from_legacy_sandbox_policy(&legacy, ...),
        network_sandbox_policy: NetworkSandboxPolicy::from(&legacy),
        sandbox_policy: legacy,
    }),
    // 仅拆分策略：派生遗留策略
    (None, Some((fs, net))) => {
        let legacy = fs.to_legacy_sandbox_policy(net, sandbox_policy_cwd)?;
        Ok(EffectiveSandboxPolicies { ... })
    }
    // 都无：错误
    (None, None) => Err(ResolveSandboxPoliciesError::MissingConfiguration),
}
```

### 3.4 外阶段执行

```rust
fn run_bwrap_with_proc_fallback(
    sandbox_policy_cwd: &Path,
    command_cwd: Option<&Path>,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    inner: Vec<String>,
    mount_proc: bool,
    allow_network_for_proxy: bool,
) -> !
```

**执行流程**：

1. **确定网络模式**：
```rust
fn bwrap_network_mode(
    network_sandbox_policy: NetworkSandboxPolicy,
    allow_network_for_proxy: bool,
) -> BwrapNetworkMode {
    if allow_network_for_proxy {
        BwrapNetworkMode::ProxyOnly
    } else if network_sandbox_policy.is_enabled() {
        BwrapNetworkMode::FullAccess
    } else {
        BwrapNetworkMode::Isolated
    }
}
```

2. **预检 proc 挂载**：
```rust
if mount_proc && !preflight_proc_mount_support(...) {
    mount_proc = false;  // 静默回退
}
```

3. **构建并执行 bwrap**：
```rust
let options = BwrapOptions { mount_proc, network_mode };
let bwrap_args = build_bwrap_argv(inner, file_system_sandbox_policy, ..., options);
exec_bwrap(bwrap_args.args, bwrap_args.preserved_files);
```

### 3.5 proc 挂载预检

```rust
fn preflight_proc_mount_support(...) -> bool {
    let preflight_argv = build_preflight_bwrap_argv(...);
    let stderr = run_bwrap_in_child_capture_stderr(preflight_argv);
    !is_proc_mount_failure(stderr.as_str())
}
```

**预检实现**：

```rust
fn run_bwrap_in_child_capture_stderr(bwrap_args: BwrapArgs) -> String {
    const MAX_PREFLIGHT_STDERR_BYTES: u64 = 64 * 1024;
    
    // 创建管道
    let mut pipe_fds = [0; 2];
    unsafe { libc::pipe2(pipe_fds.as_mut_ptr(), libc::O_CLOEXEC) };
    
    // fork 子进程
    let pid = unsafe { libc::fork() };
    
    if pid == 0 {
        // 子进程：重定向 stderr，执行 bwrap
        unsafe {
            libc::dup2(write_fd, libc::STDERR_FILENO);
            exec_bwrap(bwrap_args.args, bwrap_args.preserved_files);
        }
    }
    
    // 父进程：读取 stderr，等待子进程
    // ...
}
```

**错误检测**：
```rust
fn is_proc_mount_failure(stderr: &str) -> bool {
    stderr.contains("Can't mount proc")
        && stderr.contains("/newroot/proc")
        && (stderr.contains("Invalid argument")
            || stderr.contains("Operation not permitted")
            || stderr.contains("Permission denied"))
}
```

### 3.6 内阶段命令构建

```rust
fn build_inner_seccomp_command(args: InnerSeccompCommandArgs<'_>) -> Vec<String>
```

**构建逻辑**：

1. **获取当前可执行文件路径**：
```rust
let current_exe = std::env::current_exe()
    .unwrap_or_else(|err| panic!("failed to resolve current executable path: {err}"));
```

2. **序列化策略**：
```rust
let policy_json = serde_json::to_string(sandbox_policy)
    .unwrap_or_else(|err| panic!("failed to serialize sandbox policy: {err}"));
// ... 文件系统和网络策略
```

3. **构建命令行**：
```rust
let mut inner = vec![
    current_exe.to_string_lossy().to_string(),
    "--sandbox-policy-cwd".to_string(),
    sandbox_policy_cwd.to_string_lossy().to_string(),
];
// ... 添加其他参数
inner.push("--apply-seccomp-then-exec".to_string());
if allow_network_for_proxy {
    inner.push("--allow-network-for-proxy".to_string());
    inner.push("--proxy-route-spec".to_string());
    inner.push(proxy_route_spec.unwrap());
}
inner.push("--".to_string());
inner.extend(command);
```

### 3.7 内阶段执行

```rust
// 在 apply_seccomp_then_exec 分支中
if apply_seccomp_then_exec {
    if allow_network_for_proxy {
        // 激活代理路由
        let spec = proxy_route_spec.expect("managed proxy mode requires --proxy-route-spec");
        if let Err(err) = activate_proxy_routes_in_netns(spec) {
            panic!("error activating Linux proxy routing bridge: {err}");
        }
    }
    
    // 应用沙箱策略
    let proxy_routing_active = allow_network_for_proxy;
    if let Err(e) = apply_sandbox_policy_to_current_thread(
        &sandbox_policy,
        network_sandbox_policy,
        &sandbox_policy_cwd,
        /*apply_landlock_fs*/ false,
        allow_network_for_proxy,
        proxy_routing_active,
    ) {
        panic!("error applying Linux sandbox restrictions: {e:?}");
    }
    
    // 执行用户命令
    exec_or_panic(command);
}
```

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
main.rs::main
    └── lib.rs::run_main
        └── linux_run_main::run_main
            ├── LandlockCommand::parse() [clap]
            ├── ensure_inner_stage_mode_is_valid
            ├── resolve_sandbox_policies
            │   ├── file_system_sandbox_policy.needs_direct_runtime_enforcement
            │   ├── file_system_sandbox_policy.to_legacy_sandbox_policy
            │   └── legacy_sandbox_policies_match_semantics
            ├── ensure_legacy_landlock_mode_supports_policy
            └── 分支执行
                ├── apply_seccomp_then_exec 分支（内阶段）
                │   ├── activate_proxy_routes_in_netns (proxy_routing.rs)
                │   ├── apply_sandbox_policy_to_current_thread (landlock.rs)
                │   └── exec_or_panic
                ├── 完全访问路径
                │   └── apply_sandbox_policy_to_current_thread
                └── 外阶段路径
                    ├── prepare_host_proxy_route_spec (proxy_routing.rs)
                    ├── build_inner_seccomp_command
                    ├── run_bwrap_with_proc_fallback
                    │   ├── preflight_proc_mount_support
                    │   │   └── run_bwrap_in_child_capture_stderr
                    │   ├── build_bwrap_argv
                    │   │   └── create_bwrap_command_args (bwrap.rs)
                    │   └── exec_bwrap (launcher.rs)
                    └── 遗留路径
                        └── apply_sandbox_policy_to_current_thread
```

### 4.2 测试覆盖

单元测试位于 `linux_run_main_tests.rs`：

| 测试函数 | 测试目的 |
|----------|----------|
| `detects_proc_mount_invalid_argument_failure` | proc 挂载错误检测 |
| `inserts_bwrap_argv0_before_command_separator` | argv0 插入位置 |
| `inserts_unshare_net_when_network_isolation_requested` | 网络隔离标志 |
| `proxy_only_mode_takes_precedence_over_full_network_policy` | 代理模式优先级 |
| `resolve_sandbox_policies_derives_split_policies_from_legacy_policy` | 策略派生 |
| `resolve_sandbox_policies_rejects_partial_split_policies` | 部分策略拒绝 |
| `resolve_sandbox_policies_rejects_mismatched_legacy_and_split_inputs` | 不匹配拒绝 |

## 5. 依赖与外部交互

### 5.1 外部 crate 依赖

| crate | 用途 |
|-------|------|
| `clap` | 命令行参数解析 |
| `serde_json` | 策略序列化 |

### 5.2 内部模块依赖

| 模块 | 用途 |
|------|------|
| `bwrap` | 生成 bwrap 参数 |
| `landlock` | 应用 seccomp/landlock 策略 |
| `launcher` | 执行 bwrap |
| `proxy_routing` | 代理路由管理 |

### 5.3 协议类型依赖

```rust
use codex_protocol::protocol::FileSystemSandboxPolicy;
use codex_protocol::protocol::NetworkSandboxPolicy;
use codex_protocol::protocol::SandboxPolicy;
```

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 策略不匹配风险
- **风险**：遗留策略与拆分策略语义不一致
- **缓解**：`resolve_sandbox_policies` 中的验证逻辑
- **潜在问题**：复杂的策略组合可能绕过验证

#### 6.1.2 proc 挂载预检开销
- **风险**：每次启动都 fork 子进程进行预检
- **影响**：增加启动延迟（约 10-50ms）
- **建议**：考虑缓存预检结果（按环境指纹）

#### 6.1.3 panic 使用
- **风险**：多处使用 `panic!` 处理错误
- **影响**：无法优雅降级
- **代码位置**：策略解析、命令构建等

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 空命令 | `panic!("No command specified to execute.")` |
| 不兼容模式 | `panic!("--apply-seccomp-then-exec is incompatible with --use-legacy-landlock")` |
| proc 挂载失败 | 静默回退到 `--no-proc` |
| 代理路由失败 | panic |
| 策略序列化失败 | panic |

### 6.3 改进建议

#### 6.3.1 错误处理改进
- **建议**：引入结构化错误类型，替代 panic
- **实现**：定义 `SandboxSetupError` 枚举
- **价值**：支持上层优雅降级和错误报告

#### 6.3.2 预检缓存
- **建议**：缓存 proc 挂载预检结果
- **实现**：基于 `/proc/self/cgroup` 等环境指纹
- **价值**：减少启动延迟

#### 6.3.3 日志增强
- **建议**：添加结构化日志记录关键决策点
- **位置**：策略选择、模式回退、代理路由激活
- **价值**：便于生产环境调试

#### 6.3.4 配置验证
- **建议**：添加配置验证模式（dry-run）
- **实现**：`--validate-config` 标志
- **价值**：提前发现配置错误

#### 6.3.5 测试覆盖
- **建议**：添加更多集成测试
- **场景**：容器环境、代理模式、策略组合
- **当前**：单元测试较完善，集成测试有限

### 6.4 维护注意事项

1. **策略演进**：拆分策略是较新的设计，需要维护与遗留策略的兼容性
2. **两阶段模型复杂性**：理解外阶段/内阶段的分离对故障排查很重要
3. **代理路由**：`proxy_routing.rs` 是一个复杂的子系统，修改需谨慎
4. **容器兼容性**：定期测试在 Docker、Kubernetes 等环境中的行为
