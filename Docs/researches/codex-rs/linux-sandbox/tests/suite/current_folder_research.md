# codex-rs/linux-sandbox/tests/suite 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 目录定位

`codex-rs/linux-sandbox/tests/suite/` 是 Codex 项目 Linux 沙箱模块的**集成测试套件目录**，负责验证 Linux 平台下沙箱隔离机制的正确性和安全性。

### 核心职责

1. **文件系统隔离测试**：验证 bubblewrap (bwrap) 和 Landlock 实现的文件系统沙箱策略是否正确执行
2. **网络隔离测试**：验证 seccomp 过滤器是否正确阻断网络访问
3. **托管代理模式测试**：验证 managed proxy 模式下的网络路由和隔离行为
4. **安全边界测试**：验证敏感路径（如 `.git`, `.codex`）的写保护
5. **超时与错误处理测试**：验证沙箱命令的超时控制和错误传播

### 测试架构

```
codex-rs/linux-sandbox/tests/
├── all.rs          # 测试入口，聚合 suite 模块
└── suite/
    ├── mod.rs      # 测试模块聚合器
    ├── landlock.rs # 文件系统与网络隔离测试（约766行）
    └── managed_proxy.rs # 托管代理模式测试（约312行）
```

### 运行环境要求

- **平台限制**：仅 Linux (`#![cfg(target_os = "linux")]`)
- **架构适配**：针对 x86_64 和 aarch64 设置不同超时参数
- **CI 适配**：GitHub CI 的 arm64 测试需要更长超时（5秒 vs 200毫秒）

---

## 功能点目的

### 1. 文件系统访问控制测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `test_root_read` | 验证可读取根目录 `/bin` |
| `test_root_write` | 验证**禁止**写入根目录（应 panic） |
| `test_writable_root` | 验证可写入显式声明的可写目录 |
| `test_dev_null_write` | 验证 `/dev/null` 可写（设备节点处理） |
| `bwrap_populates_minimal_dev_nodes` | 验证 bwrap 创建标准设备节点 |
| `bwrap_preserves_writable_dev_shm_bind_mount` | 验证 `/dev/shm` 可写绑定挂载 |
| `sandbox_ignores_missing_writable_roots_under_bwrap` | 验证缺失的可写根被优雅忽略 |

### 2. 安全加固测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `test_no_new_privs_is_enabled` | 验证 `PR_SET_NO_NEW_PRIVS` 已启用 |
| `test_timeout` | 验证命令超时机制（应 panic） |
| `sandbox_blocks_git_and_codex_writes_inside_writable_root` | 验证 `.git` 和 `.codex` 目录写保护 |
| `sandbox_blocks_codex_symlink_replacement_attack` | 验证符号链接替换攻击防护 |

### 3. 网络隔离测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `sandbox_blocks_curl` | 阻断 curl 网络访问 |
| `sandbox_blocks_wget` | 阻断 wget 网络访问 |
| `sandbox_blocks_ping` | 阻断 ICMP (ping) |
| `sandbox_blocks_nc` | 阻断 netcat 连接 |
| `sandbox_blocks_ssh` | 阻断 SSH 连接 |
| `sandbox_blocks_getent` | 阻断 DNS 查询 |
| `sandbox_blocks_dev_tcp_redirection` | 阻断 bash `/dev/tcp` 技巧 |

### 4. 细粒度策略测试 (`landlock.rs`)

| 测试函数 | 目的 |
|---------|------|
| `sandbox_blocks_explicit_split_policy_carveouts_under_bwrap` | 验证显式拒绝条目生效 |
| `sandbox_reenables_writable_subpaths_under_unreadable_parents` | 验证嵌套可写子路径可重新启用 |
| `sandbox_blocks_root_read_carveouts_under_bwrap` | 验证根目录读权限可细化拒绝 |

### 5. 托管代理模式测试 (`managed_proxy.rs`)

| 测试函数 | 目的 |
|---------|------|
| `managed_proxy_mode_fails_closed_without_proxy_env` | 无代理环境变量时失败关闭 |
| `managed_proxy_mode_routes_through_bridge_and_blocks_direct_egress` | 验证代理桥路由和直接出口阻断 |
| `managed_proxy_mode_denies_af_unix_creation_for_user_command` | 验证用户命令禁止创建 AF_UNIX socket |

---

## 具体技术实现

### 1. 测试执行流程

#### 1.1 核心测试辅助函数

```rust
// landlock.rs: 运行命令并返回输出
async fn run_cmd_result_with_writable_roots(
    cmd: &[&str],
    writable_roots: &[PathBuf],
    timeout_ms: u64,
    use_legacy_landlock: bool,
    network_access: bool,
) -> Result<ExecToolCallOutput>
```

**流程**：
1. 构建 `SandboxPolicy::WorkspaceWrite` 策略
2. 转换为 `FileSystemSandboxPolicy` 和 `NetworkSandboxPolicy`
3. 调用 `process_exec_tool_call()` 执行命令
4. 返回执行结果（stdout, stderr, exit_code）

#### 1.2 托管代理测试辅助函数

```rust
// managed_proxy.rs: 直接运行 Linux 沙箱
async fn run_linux_sandbox_direct(
    command: &[&str],
    sandbox_policy: &SandboxPolicy,
    allow_network_for_proxy: bool,
    env: HashMap<String, String>,
    timeout_ms: u64,
) -> Output
```

**流程**：
1. 序列化沙箱策略为 JSON
2. 构建 `codex-linux-sandbox` 命令行参数
3. 使用 `tokio::process::Command` 执行
4. 返回原始进程输出

### 2. 超时配置策略

```rust
// 架构自适应超时配置
#[cfg(not(target_arch = "aarch64"))]
const SHORT_TIMEOUT_MS: u64 = 200;
#[cfg(target_arch = "aarch64")]
const SHORT_TIMEOUT_MS: u64 = 5_000;

#[cfg(not(target_arch = "aarch64"))]
const LONG_TIMEOUT_MS: u64 = 1_000;
#[cfg(target_arch = "aarch64")]
const LONG_TIMEOUT_MS: u64 = 5_000;

#[cfg(not(target_arch = "aarch64"))]
const NETWORK_TIMEOUT_MS: u64 = 2_000;
#[cfg(target_arch = "aarch64")]
const NETWORK_TIMEOUT_MS: u64 = 10_000;
```

### 3. 测试跳过逻辑

#### 3.1 Bubblewrap 可用性检测

```rust
async fn should_skip_bwrap_tests() -> bool {
    match run_cmd_result_with_writable_roots(...).await {
        Ok(output) => is_bwrap_unavailable_output(&output),
        Err(CodexErr::Sandbox(SandboxErr::Denied { output, .. })) => {
            is_bwrap_unavailable_output(&output)
        }
        Err(CodexErr::Sandbox(SandboxErr::Timeout { .. })) => true,
        Err(err) => panic!("..."),
    }
}
```

检测特征：
- 包含 `"build-time bubblewrap is not available in this build."`
- 或包含 `"Can't mount proc on /newroot/proc"` 配合权限错误

#### 3.2 托管代理权限检测

```rust
const MANAGED_PROXY_PERMISSION_ERR_SNIPPETS: &[&str] = &[
    "loopback: Failed RTM_NEWADDR",
    "loopback: Failed RTM_NEWLINK",
    "setting up uid map: Permission denied",
    "No permissions to create a new namespace",
    "error isolating Linux network namespace for proxy mode",
];
```

### 4. 网络阻断验证策略

```rust
async fn assert_network_blocked(cmd: &[&str]) {
    // 1. 使用 ReadOnly 策略执行命令
    // 2. 验证退出码非零（或 SandboxErr::Denied）
    // 3. 如果 exit_code == 0，则 panic 报告沙箱被突破
}
```

### 5. 代理环境变量处理

```rust
const PROXY_ENV_KEYS: &[&str] = &[
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "FTP_PROXY",
    "YARN_HTTP_PROXY", "YARN_HTTPS_PROXY",
    "NPM_CONFIG_HTTP_PROXY", "NPM_CONFIG_HTTPS_PROXY", "NPM_CONFIG_PROXY",
    "BUNDLE_HTTP_PROXY", "BUNDLE_HTTPS_PROXY",
    "PIP_PROXY",
    "DOCKER_HTTP_PROXY", "DOCKER_HTTPS_PROXY",
];

fn strip_proxy_env(env: &mut HashMap<String, String>) {
    for key in PROXY_ENV_KEYS {
        env.remove(*key);
        env.remove(key.to_ascii_lowercase().as_str());
    }
}
```

---

## 关键代码路径与文件引用

### 1. 测试文件结构

```
codex-rs/linux-sandbox/tests/suite/
├── mod.rs                 # 3行：模块聚合
│   └── 导出 landlock, managed_proxy
├── landlock.rs            # 766行：主要测试集
│   ├── 超时配置 (28-41行)
│   ├── 辅助函数 (45-187行)
│   ├── 文件系统测试 (189-337行)
│   ├── 安全加固测试 (339-356行)
│   ├── 超时测试 (358-362行)
│   ├── 网络阻断测试 (364-447行)
│   └── 细粒度策略测试 (449-766行)
└── managed_proxy.rs       # 312行：代理模式测试
    ├── 常量定义 (18-43行)
    ├── 辅助函数 (45-159行)
    └── 测试用例 (161-312行)
```

### 2. 被测代码路径

| 被测组件 | 文件路径 | 关键函数/结构 |
|---------|---------|-------------|
| Bubblewrap 参数构建 | `src/bwrap.rs` | `create_bwrap_command_args()`, `create_filesystem_args()` |
| Seccomp 过滤器 | `src/landlock.rs` | `install_network_seccomp_filter_on_current_thread()` |
| Landlock 规则 | `src/landlock.rs` | `install_filesystem_landlock_rules_on_current_thread()` |
| 主执行流程 | `src/linux_run_main.rs` | `run_main()`, `LandlockCommand` |
| 代理路由 | `src/proxy_routing.rs` | `prepare_host_proxy_route_spec()`, `activate_proxy_routes_in_netns()` |
| 启动器 | `src/launcher.rs` | `exec_bwrap()` |
| 内嵌 bwrap | `src/vendored_bwrap.rs` | `exec_vendored_bwrap()` |

### 3. 外部依赖调用

```rust
// 来自 codex-core 的执行引擎
use codex_core::exec::process_exec_tool_call;
use codex_core::exec::ExecParams;
use codex_core::exec_env::create_env;
use codex_core::config::types::ShellEnvironmentPolicy;
use codex_core::sandboxing::SandboxPermissions;

// 来自 codex-protocol 的策略类型
use codex_protocol::permissions::FileSystemSandboxPolicy;
use codex_protocol::permissions::NetworkSandboxPolicy;
use codex_protocol::permissions::FileSystemSandboxEntry;
use codex_protocol::permissions::FileSystemAccessMode;
use codex_protocol::protocol::SandboxPolicy;
use codex_protocol::protocol::ReadOnlyAccess;

// 来自 codex-utils-absolute-path
use codex_utils_absolute_path::AbsolutePathBuf;
```

### 4. 关键数据结构

#### 4.1 沙箱策略转换链

```
SandboxPolicy (legacy)
    ↓
FileSystemSandboxPolicy (split)
    ↓
BwrapArgs (bubblewrap 命令行参数)
```

#### 4.2 测试用例中的策略构造示例

```rust
// 工作区写入策略
let sandbox_policy = SandboxPolicy::WorkspaceWrite {
    writable_roots: vec![...],
    read_only_access: Default::default(),
    network_access: false,
    exclude_tmpdir_env_var: true,
    exclude_slash_tmp: true,
};

// 细粒度受限策略
let file_system_sandbox_policy = FileSystemSandboxPolicy::restricted(vec![
    FileSystemSandboxEntry {
        path: FileSystemPath::Special { value: FileSystemSpecialPath::Minimal },
        access: FileSystemAccessMode::Read,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path { path: ... },
        access: FileSystemAccessMode::Write,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path { path: ... },
        access: FileSystemAccessMode::None,  // 显式拒绝
    },
]);
```

---

## 依赖与外部交互

### 1. 直接依赖（Cargo.toml）

```toml
[target.'cfg(target_os = "linux")'.dependencies]
clap = { workspace = true, features = ["derive"] }
codex-core = { workspace = true }
codex-protocol = { workspace = true }
codex-utils-absolute-path = { workspace = true }
landlock = { workspace = true }
libc = { workspace = true }
seccompiler = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
url = { workspace = true }

[target.'cfg(target_os = "linux")'.dev-dependencies]
pretty_assertions = { workspace = true }
tempfile = { workspace = true }
tokio = { workspace = true, features = [...] }
```

### 2. 外部系统依赖

| 依赖 | 用途 | 检测/回退策略 |
|-----|------|-------------|
| `/usr/bin/bwrap` | 系统 bubblewrap | 不存在时使用内嵌版本 |
| `libcap` | Linux capabilities | 编译时通过 pkg-config 检测 |
| `python3` | 托管代理测试 | 运行时检测，缺失则跳过 |
| `/dev/shm` | 共享内存设备 | 运行时检测，缺失则跳过 |

### 3. 环境变量交互

| 变量 | 用途 |
|-----|------|
| `CARGO_BIN_EXE_codex-linux-sandbox` | 测试时定位沙箱可执行文件 |
| `TMPDIR` | 临时目录解析 |
| `CODEX_HOME` | 代理 socket 目录父路径 |
| `HTTP_PROXY` / `HTTPS_PROXY` 等 | 托管代理模式配置 |

### 4. 内核特性依赖

- **Landlock**: LSM (Linux Security Modules) 支持
- **seccomp**: 系统调用过滤
- **User Namespaces**: `--unshare-user`
- **PID Namespaces**: `--unshare-pid`
- **Network Namespaces**: `--unshare-net`
- **PR_SET_NO_NEW_PRIVS**: 禁止提升权限

---

## 风险、边界与改进建议

### 1. 已知风险

#### 1.1 测试环境依赖风险

| 风险 | 描述 | 缓解措施 |
|-----|------|---------|
| bwrap 不可用 | CI 环境可能缺少 bubblewrap | `should_skip_bwrap_tests()` 自动跳过 |
| 命名空间权限不足 | 容器环境可能禁止创建新命名空间 | 检测权限错误并跳过 |
| 架构差异 | arm64 测试需要更长超时 | 条件编译设置不同超时 |
| /proc 挂载失败 | 某些容器禁止挂载新 proc | `--no-proc` 回退 |

#### 1.2 测试覆盖边界

```rust
// 当前测试未覆盖的场景：
// 1. 非 Linux 平台（条件编译排除）
// 2. 复杂的嵌套策略组合（部分覆盖）
// 3. 大文件/高并发 I/O 压力测试
// 4. 长时间运行的沙箱进程稳定性
// 5. 多线程程序在沙箱中的行为
```

### 2. 代码质量观察

#### 2.1 优点

- **架构自适应**：通过条件编译支持 x86_64 和 aarch64
- **优雅降级**：自动检测环境限制并跳过不适用的测试
- **清晰的错误分类**：区分 `SandboxErr::Denied` 和 `SandboxErr::Timeout`
- **辅助函数复用**：`run_cmd_result_with_writable_roots` 等函数减少重复代码

#### 2.2 潜在改进点

| 位置 | 问题 | 建议 |
|-----|------|------|
| `landlock.rs:26-41` | 超时常量为模块级，不可配置 | 考虑环境变量覆盖 |
| `landlock.rs:143-152` | `is_bwrap_unavailable_output` 使用字符串匹配 | 考虑使用结构化错误码 |
| `managed_proxy.rs:275-285` | python3 检测在测试函数内 | 提取为共享辅助函数 |
| 多处 | `#[expect(clippy::unwrap_used)]` 较多 | 考虑使用 `?` 或更安全的模式 |

### 3. 安全测试建议

#### 3.1 建议新增测试

```rust
// 1. TOCTOU (Time-of-check-time-of-use) 测试
// 验证在路径检查和实际访问之间替换文件的处理

// 2. 符号链接遍历测试
// 验证对 ../../../etc/passwd 等路径的防护

// 3. 文件描述符泄漏测试
// 验证沙箱进程不会泄漏敏感 fd

// 4. 竞争条件测试
// 验证并发创建/删除路径时的行为

// 5. 资源耗尽测试
// 验证对大量小文件/深目录结构的处理
```

#### 3.2 建议增强的监控

```rust
// 当前测试仅验证 exit_code，建议增加：
// - 系统调用追踪验证（strace 集成）
// - 实际的文件系统访问审计
// - 网络包捕获验证
```

### 4. 维护性建议

1. **文档化测试矩阵**：明确列出每个测试的环境要求（内核版本、capabilities、文件系统类型）

2. **性能基准**：记录测试执行时间基准，便于检测性能退化

3. **日志增强**：在测试失败时输出更多诊断信息（当前仅输出 stdout/stderr）

4. **参数化测试**：使用 `rstest` 或类似框架减少重复代码

5. **快照测试**：对复杂的 bwrap 参数生成使用 insta 快照验证

### 5. 与上游依赖的兼容性风险

| 依赖 | 风险 | 监控建议 |
|-----|------|---------|
| bubblewrap | API 变化可能影响参数生成 | 跟踪 bwrap 发布说明 |
| landlock crate | ABI 版本变化 | 测试多内核版本 |
| seccompiler | BPF 生成变化 | 验证生成的过滤器 |
| libc | 系统调用号变化 | CI 覆盖多架构 |

---

## 附录：关键代码片段

### A.1 测试入口 (`tests/all.rs`)

```rust
// Single integration test binary that aggregates all test modules.
// The submodules live in `tests/suite/`.
mod suite;
```

### A.2 模块聚合 (`tests/suite/mod.rs`)

```rust
// Aggregates all former standalone integration tests as modules.
mod landlock;
mod managed_proxy;
```

### A.3 典型测试模式

```rust
#[tokio::test]
async fn test_example() {
    if should_skip_bwrap_tests().await {
        eprintln!("skipping bwrap test: ...");
        return;
    }
    
    let output = run_cmd_result_with_writable_roots(
        &["command", "arg"],
        &[writable_root],
        TIMEOUT_MS,
        false,  // use_legacy_landlock
        true,   // network_access
    ).await.expect("...");
    
    assert_eq!(output.exit_code, 0);
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/linux-sandbox/tests/suite/*
