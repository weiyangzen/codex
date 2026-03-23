# Research: codex-rs/linux-sandbox/tests/all.rs

## 1. 场景与职责

### 1.1 文件定位

`codex-rs/linux-sandbox/tests/all.rs` 是 **Linux Sandbox 集成测试的入口文件**，采用 Rust 的 "single integration test binary" 模式设计。该文件本身仅包含 3 行代码，实际测试逻辑分布在 `tests/suite/` 子模块中。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **测试聚合** | 作为统一的测试入口，聚合 `suite/landlock.rs` 和 `suite/managed_proxy.rs` 两个测试子模块 |
| **CI/CD 集成** | 通过 `cargo test -p codex-linux-sandbox` 执行，验证 Linux 沙箱功能的正确性 |
| **架构验证** | 测试覆盖 bubblewrap 沙箱、seccomp 网络过滤、Landlock 文件系统限制、托管代理模式等核心功能 |

### 1.3 测试范围

```
all.rs (入口)
├── suite/mod.rs      (子模块声明)
├── suite/landlock.rs (文件系统 + 网络沙箱测试)
└── suite/managed_proxy.rs (托管代理网络模式测试)
```

---

## 2. 功能点目的

### 2.1 测试分类概览

#### 2.1.1 文件系统沙箱测试 (landlock.rs)

| 测试函数 | 目的 |
|---------|------|
| `test_root_read` | 验证沙箱内可以读取根目录 `/bin` |
| `test_root_write` | **负面测试**：验证沙箱内无法写入未授权路径（应 panic） |
| `test_dev_null_write` | 验证 `/dev/null` 可写（bwrap 最小设备节点） |
| `bwrap_populates_minimal_dev_nodes` | 验证 bwrap 正确创建标准设备节点（null/zero/full/random/urandom/tty） |
| `bwrap_preserves_writable_dev_shm_bind_mount` | 验证 `/dev/shm` 绑定挂载保持可写 |
| `test_writable_root` | 验证显式声明的可写根目录可正常写入 |
| `sandbox_ignores_missing_writable_roots_under_bwrap` | 验证缺失的可写根目录被优雅忽略 |
| `test_no_new_privs_is_enabled` | 验证 `PR_SET_NO_NEW_PRIVS` 已启用 |
| `test_timeout` | 验证命令超时机制正常工作 |
| `sandbox_blocks_git_and_codex_writes_inside_writable_root` | 验证 `.git` 和 `.codex` 子目录在可写根内仍只读 |
| `sandbox_blocks_codex_symlink_replacement_attack` | 验证符号链接替换攻击被阻止 |
| `sandbox_blocks_explicit_split_policy_carveouts_under_bwrap` | 验证显式拒绝策略在 bwrap 下生效 |
| `sandbox_reenables_writable_subpaths_under_unreadable_parents` | 验证嵌套可写子路径在不可读父目录下重新启用 |
| `sandbox_blocks_root_read_carveouts_under_bwrap` | 验证根目录读取权限的精细控制 |

#### 2.1.2 网络沙箱测试 (landlock.rs)

| 测试函数 | 目的 |
|---------|------|
| `sandbox_blocks_curl` | 验证 curl 网络访问被阻止 |
| `sandbox_blocks_wget` | 验证 wget 网络访问被阻止 |
| `sandbox_blocks_ping` | 验证 ICMP ping 被阻止 |
| `sandbox_blocks_nc` | 验证 netcat 连接被阻止 |
| `sandbox_blocks_ssh` | 验证 SSH 连接被阻止 |
| `sandbox_blocks_getent` | 验证 getent 网络查询被阻止 |
| `sandbox_blocks_dev_tcp_redirection` | 验证 bash `/dev/tcp` 重定向被阻止 |

#### 2.1.3 托管代理模式测试 (managed_proxy.rs)

| 测试函数 | 目的 |
|---------|------|
| `managed_proxy_mode_fails_closed_without_proxy_env` | 验证无代理环境变量时托管代理模式失败关闭 |
| `managed_proxy_mode_routes_through_bridge_and_blocks_direct_egress` | 验证流量通过代理桥路由且阻止直接出口 |
| `managed_proxy_mode_denies_af_unix_creation_for_user_command` | 验证用户命令无法创建 AF_UNIX 套接字 |

### 2.2 测试设计哲学

1. **分层防御验证**：测试覆盖从内核级（seccomp）、系统调用级（Landlock）到容器级（bubblewrap）的多层沙箱机制
2. **负面测试为主**：大量测试验证"什么不能做"，确保沙箱的拒绝策略可靠
3. **环境自适应**：通过 `should_skip_bwrap_tests()` 检测环境能力，在受限 CI 环境中优雅降级

---

## 3. 具体技术实现

### 3.1 测试执行流程

```rust
// all.rs -> suite/mod.rs -> suite/landlock.rs / suite/managed_proxy.rs

// 典型测试执行链：
test_writable_root
  └── run_cmd
      └── run_cmd_output
          └── run_cmd_result_with_writable_roots
              └── run_cmd_result_with_policies
                  └── process_exec_tool_call  // codex-core/src/exec.rs
                      └── build_exec_request
                          └── SandboxManager::transform
                              └── execute_env
```

### 3.2 关键测试辅助函数

#### 3.2.1 命令执行封装 (landlock.rs)

```rust
// 行 71-141: 核心测试执行函数
async fn run_cmd_result_with_policies(
    cmd: &[&str],
    sandbox_policy: SandboxPolicy,
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    timeout_ms: u64,
    use_legacy_landlock: bool,
) -> Result<ExecToolCallOutput> {
    let params = ExecParams {
        command: cmd.iter().copied().map(str::to_owned).collect(),
        cwd,
        expiration: timeout_ms.into(),
        env: create_env_from_core_vars(),
        network: None,
        sandbox_permissions: SandboxPermissions::UseDefault,
        // ...
    };
    let sandbox_program = env!("CARGO_BIN_EXE_codex-linux-sandbox");
    
    process_exec_tool_call(
        params,
        &sandbox_policy,
        &file_system_sandbox_policy,
        network_sandbox_policy,
        sandbox_cwd.as_path(),
        &codex_linux_sandbox_exe,
        use_legacy_landlock,
        None,
    ).await
}
```

#### 3.2.2 环境变量准备

```rust
// 行 45-48: 创建测试环境变量
fn create_env_from_core_vars() -> HashMap<String, String> {
    let policy = ShellEnvironmentPolicy::default();
    create_env(&policy, None)
}
```

#### 3.2.3 bwrap 可用性检测

```rust
// 行 154-173: 检测 bwrap 是否可用
async fn should_skip_bwrap_tests() -> bool {
    match run_cmd_result_with_writable_roots(&["bash", "-lc", "true"], &[], NETWORK_TIMEOUT_MS, false, true).await {
        Ok(output) => is_bwrap_unavailable_output(&output),
        Err(CodexErr::Sandbox(SandboxErr::Denied { output, .. })) => {
            is_bwrap_unavailable_output(&output)
        }
        Err(CodexErr::Sandbox(SandboxErr::Timeout { .. })) => true,
        Err(err) => panic!("bwrap availability probe failed unexpectedly: {err:?}"),
    }
}
```

### 3.3 托管代理测试架构

```rust
// managed_proxy.rs 行 115-159: 直接调用沙箱二进制
async fn run_linux_sandbox_direct(
    command: &[&str],
    sandbox_policy: &SandboxPolicy,
    allow_network_for_proxy: bool,
    env: HashMap<String, String>,
    timeout_ms: u64,
) -> Output {
    let policy_json = serde_json::to_string(sandbox_policy).unwrap();
    
    let mut args = vec![
        "--sandbox-policy-cwd".to_string(),
        cwd.to_string_lossy().to_string(),
        "--sandbox-policy".to_string(),
        policy_json,
    ];
    if allow_network_for_proxy {
        args.push("--allow-network-for-proxy".to_string());
    }
    args.push("--".to_string());
    args.extend(command.iter().map(|entry| (*entry).to_string()));

    let mut cmd = Command::new(env!("CARGO_BIN_EXE_codex-linux-sandbox"));
    cmd.args(args)
        .env_clear()
        .envs(env)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    // ...
}
```

### 3.4 超时配置策略

```rust
// 行 28-41: 架构相关的超时配置
#[cfg(not(target_arch = "aarch64"))]
const SHORT_TIMEOUT_MS: u64 = 200;
#[cfg(target_arch = "aarch64")]
const SHORT_TIMEOUT_MS: u64 = 5_000;  // ARM64 CI 需要更长超时

#[cfg(not(target_arch = "aarch64"))]
const LONG_TIMEOUT_MS: u64 = 1_000;
#[cfg(target_arch = "aarch64")]
const LONG_TIMEOUT_MS: u64 = 5_000;

#[cfg(not(target_arch = "aarch64"))]
const NETWORK_TIMEOUT_MS: u64 = 2_000;
#[cfg(target_arch = "aarch64")]
const NETWORK_TIMEOUT_MS: u64 = 10_000;
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试依赖链

```
codex-rs/linux-sandbox/tests/all.rs
├── codex-rs/linux-sandbox/tests/suite/mod.rs
│   ├── codex-rs/linux-sandbox/tests/suite/landlock.rs
│   └── codex-rs/linux-sandbox/tests/suite/managed_proxy.rs
│
└── 被测代码 (通过 process_exec_tool_call 调用):
    ├── codex-rs/core/src/exec.rs
    │   ├── build_exec_request()
    │   └── execute_exec_request()
    │
    ├── codex-rs/core/src/sandboxing/mod.rs
    │   └── SandboxManager::transform()
    │
    └── codex-rs/linux-sandbox/src/ (实际沙箱实现)
        ├── lib.rs                    (库入口)
        ├── main.rs                   (二进制入口)
        ├── linux_run_main.rs         (CLI 解析 + 执行流程)
        ├── bwrap.rs                  (bubblewrap 参数构建)
        ├── launcher.rs               (bwrap 启动器)
        ├── landlock.rs               (Landlock/seccomp 限制)
        ├── proxy_routing.rs          (托管代理路由)
        └── vendored_bwrap.rs         (内嵌 bwrap 编译)
```

### 4.2 关键数据结构

#### 4.2.1 沙箱策略 (protocol/src/protocol.rs)

```rust
pub enum SandboxPolicy {
    DangerFullAccess,
    ExternalSandbox { network_access: NetworkAccess },
    ReadOnly { access: ReadOnlyAccess, network_access: bool },
    WorkspaceWrite {
        writable_roots: Vec<AbsolutePathBuf>,
        read_only_access: ReadOnlyAccess,
        network_access: bool,
        exclude_tmpdir_env_var: bool,
        exclude_slash_tmp: bool,
    },
}
```

#### 4.2.2 文件系统沙箱策略 (protocol/src/permissions.rs)

```rust
pub struct FileSystemSandboxPolicy {
    pub kind: FileSystemSandboxKind,  // Restricted/Unrestricted/ExternalSandbox
    pub entries: Vec<FileSystemSandboxEntry>,
}

pub struct FileSystemSandboxEntry {
    pub path: FileSystemPath,         // Path 或 Special
    pub access: FileSystemAccessMode, // Read/Write/None
}
```

### 4.3 沙箱执行流程 (linux_run_main.rs)

```rust
// 行 99-220: 主执行流程
pub fn run_main() -> ! {
    // 1. 解析 CLI 参数
    let LandlockCommand { ... } = LandlockCommand::parse();
    
    // 2. 解析沙箱策略
    let EffectiveSandboxPolicies { ... } = resolve_sandbox_policies(...);
    
    // 3. 内层阶段：应用 seccomp 后执行
    if apply_seccomp_then_exec {
        if allow_network_for_proxy {
            activate_proxy_routes_in_netns(spec);
        }
        apply_sandbox_policy_to_current_thread(...);
        exec_or_panic(command);
    }
    
    // 4. 全磁盘写访问快捷路径
    if file_system_sandbox_policy.has_full_disk_write_access() && !allow_network_for_proxy {
        apply_sandbox_policy_to_current_thread(...);
        exec_or_panic(command);
    }
    
    // 5. 外层阶段：bubblewrap + 重新进入
    if !use_legacy_landlock {
        let proxy_route_spec = if allow_network_for_proxy {
            Some(prepare_host_proxy_route_spec())
        } else { None };
        
        let inner = build_inner_seccomp_command(...);
        run_bwrap_with_proc_fallback(...);
    }
    
    // 6. 遗留路径：纯 Landlock
    apply_sandbox_policy_to_current_thread(..., /*apply_landlock_fs*/ true, ...);
    exec_or_panic(command);
}
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 来源 |
|------|------|------|
| **bubblewrap (bwrap)** | 文件系统命名空间隔离 | 系统 `/usr/bin/bwrap` 或内嵌编译 |
| **libcap** | Linux capabilities 支持 | 系统 pkg-config |
| **seccomp** | 系统调用过滤 | `seccompiler` crate |
| **Landlock** | 文件系统访问控制 | `landlock` crate (LTS 版本) |
| **libc** | 底层系统调用 | `libc` crate |

### 5.2 内部 crate 依赖

```toml
# Cargo.toml 依赖
codex-core        # ExecParams, process_exec_tool_call
codex-protocol    # SandboxPolicy, FileSystemSandboxPolicy, NetworkSandboxPolicy
codex-utils-absolute-path  # AbsolutePathBuf
```

### 5.3 测试工具依赖

```toml
# dev-dependencies
pretty_assertions  # 测试断言美化
tempfile           # 临时文件/目录
tokio              # 异步运行时
```

### 5.4 环境变量交互

| 变量 | 用途 |
|------|------|
| `CARGO_BIN_EXE_codex-linux-sandbox` | 测试时定位沙箱二进制 |
| `CODEX_BWRAP_SOURCE_DIR` | 自定义 bubblewrap 源码路径 |
| `TMPDIR` | 临时目录（可能被沙箱排除） |
| `HTTP_PROXY`/`HTTPS_PROXY` | 托管代理模式测试 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试环境依赖风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **bwrap 不可用** | CI 环境可能缺少 bubblewrap | `should_skip_bwrap_tests()` 检测并跳过 |
| **权限不足** | 容器环境可能缺少 `CAP_SYS_ADMIN` | 检测特定错误信息并跳过 |
| **架构差异** | ARM64 测试需要更长超时 | 条件编译配置不同超时 |
| **网络命名空间** | 托管代理需要内核命名空间权限 | `managed_proxy_skip_reason()` 检测 |

#### 6.1.2 测试覆盖边界

```rust
// 行 43: bwrap 不可用错误提示
const BWRAP_UNAVAILABLE_ERR: &str = "build-time bubblewrap is not available in this build.";

// 行 20-26: 托管代理权限错误片段
const MANAGED_PROXY_PERMISSION_ERR_SNIPPETS: &[&str] = &[
    "loopback: Failed RTM_NEWADDR",
    "loopback: Failed RTM_NEWLINK",
    "setting up uid map: Permission denied",
    "No permissions to create a new namespace",
    "error isolating Linux network namespace for proxy mode",
];
```

### 6.2 代码边界与限制

#### 6.2.1 沙箱策略转换限制

```rust
// linux_run_main.rs 行 383-397
fn ensure_legacy_landlock_mode_supports_policy(...) {
    if use_legacy_landlock
        && file_system_sandbox_policy.needs_direct_runtime_enforcement(...) {
        panic!("split sandbox policies requiring direct runtime enforcement are incompatible with --use-legacy-landlock");
    }
}
```

#### 6.2.2 网络沙箱模式

```rust
// landlock.rs 行 89-93
enum NetworkSeccompMode {
    Restricted,    // 完全禁止网络
    ProxyRouted,   // 仅允许代理路由
}
```

### 6.3 改进建议

#### 6.3.1 测试层面

1. **增加并发测试覆盖**
   - 当前测试多为串行执行，建议增加并发写入同一可写根目录的测试

2. **增加资源限制测试**
   - 测试内存限制（cgroups）
   - 测试 CPU 时间限制

3. **改进错误诊断**
   ```rust
   // 建议：在测试失败时输出更详细的沙箱状态
   dbg!(&output.stderr.text);
   dbg!(&output.stdout.text);
   dbg!(&output.exit_code);
   ```

#### 6.3.2 架构层面

1. **统一超时策略**
   - 当前超时分散在多处（SHORT_TIMEOUT_MS, LONG_TIMEOUT_MS, NETWORK_TIMEOUT_MS）
   - 建议采用分层超时配置结构

2. **增强可观测性**
   - 在沙箱执行关键路径增加 tracing span
   - 导出沙箱策略转换的详细日志

3. **改进测试隔离**
   - 使用 `tempfile::tempdir()` 确保测试间完全隔离
   - 当前已部分使用，可全面推广

#### 6.3.3 安全加固

1. **符号链接竞争防护**
   - 当前 `find_symlink_in_path` 在测试中被验证
   - 建议增加 TOCTOU（Time-of-check-time-of-use）防护

2. **环境变量清理**
   - `managed_proxy.rs` 中 `strip_proxy_env` 已清理代理变量
   - 建议统一清理所有可能泄露敏感信息的环境变量

### 6.4 相关文件清单

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/linux-sandbox/tests/all.rs` | 测试入口 |
| `codex-rs/linux-sandbox/tests/suite/mod.rs` | 子模块声明 |
| `codex-rs/linux-sandbox/tests/suite/landlock.rs` | 文件系统/网络沙箱测试 |
| `codex-rs/linux-sandbox/tests/suite/managed_proxy.rs` | 托管代理模式测试 |
| `codex-rs/linux-sandbox/src/lib.rs` | 库入口 |
| `codex-rs/linux-sandbox/src/linux_run_main.rs` | 主执行逻辑 |
| `codex-rs/linux-sandbox/src/bwrap.rs` | bubblewrap 参数构建 |
| `codex-rs/linux-sandbox/src/landlock.rs` | seccomp/Landlock 限制 |
| `codex-rs/linux-sandbox/src/proxy_routing.rs` | 代理路由实现 |
| `codex-rs/linux-sandbox/src/launcher.rs` | bwrap 启动器 |
| `codex-rs/linux-sandbox/src/vendored_bwrap.rs` | 内嵌 bwrap FFI |
| `codex-rs/linux-sandbox/build.rs` | 构建时编译 bwrap |
| `codex-rs/protocol/src/permissions.rs` | 沙箱策略定义 |
| `codex-rs/core/src/exec.rs` | 执行请求处理 |

---

## 7. 总结

`codex-rs/linux-sandbox/tests/all.rs` 是 OpenAI Codex Linux 沙箱子系统的核心测试入口，通过聚合 `landlock.rs` 和 `managed_proxy.rs` 两个测试模块，实现了对以下功能的全面验证：

1. **多层沙箱机制**：bubblewrap 容器 + seccomp 系统调用过滤 + Landlock 文件系统限制
2. **网络隔离**：完全禁止、托管代理两种模式
3. **文件系统访问控制**：可读/可写/不可读路径的精细控制
4. **安全边界**：符号链接攻击防护、敏感目录保护（.git/.codex）

测试设计充分考虑了 CI/CD 环境的多样性，通过运行时检测优雅处理 bwrap 不可用、权限不足等情况，确保测试套件在各种环境下都能提供可靠的验证结果。
