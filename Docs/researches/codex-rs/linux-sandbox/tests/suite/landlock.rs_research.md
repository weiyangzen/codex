# Linux Sandbox Landlock 测试套件研究文档

## 场景与职责

`landlock.rs` 是 Codex Linux Sandbox 的核心集成测试文件，负责验证 Linux 平台上的沙箱隔离机制。该测试套件主要覆盖以下场景：

1. **文件系统访问控制**：验证基于 Landlock 和 Bubblewrap (bwrap) 的文件系统隔离策略
2. **网络访问控制**：验证 seccomp 网络沙箱的有效性
3. **权限边界测试**：确保敏感目录（如 `.git`、`.codex`）在可写根目录下仍保持只读
4. **超时与错误处理**：验证命令执行超时机制和沙箱拒绝行为的正确性

该文件是 Linux 沙箱安全机制的最后一道防线，确保 AI 代理在执行 shell 命令时不会越权访问或修改系统。

## 功能点目的

### 1. 文件系统沙箱测试
- **只读根目录访问** (`test_root_read`)：验证沙箱内可以读取系统目录（如 `/bin`）
- **写保护验证** (`test_root_write`)：验证尝试写入非授权路径会失败
- **可写根目录** (`test_writable_root`)：验证在明确指定的可写目录中可以创建文件
- **敏感目录保护** (`sandbox_blocks_git_and_codex_writes_inside_writable_root`)：确保 `.git` 和 `.codex` 目录即使在可写根目录下也保持只读

### 2. Bubblewrap 集成测试
- **最小化 dev 节点** (`bwrap_populates_minimal_dev_nodes`)：验证 `/dev/null`、`/dev/urandom` 等关键设备节点可用
- **dev/shm 绑定挂载** (`bwrap_preserves_writable_dev_shm_bind_mount`)：验证共享内存可写
- **缺失可写根目录处理** (`sandbox_ignores_missing_writable_roots_under_bwrap`)：优雅处理不存在的路径

### 3. 网络安全测试
- **网络工具阻断** (`sandbox_blocks_curl`, `sandbox_blocks_wget`, `sandbox_blocks_ping`, `sandbox_blocks_nc`)：验证常用网络工具被 seccomp 阻断
- **SSH 阻断** (`sandbox_blocks_ssh`)：验证 SSH 连接被阻止
- **DNS 查询阻断** (`sandbox_blocks_getent`)：验证 DNS 解析被限制
- **/dev/tcp 重定向阻断** (`sandbox_blocks_dev_tcp_redirection`)：验证 bash 内置网络功能被阻断

### 4. 高级策略测试
- **显式策略分割** (`sandbox_blocks_explicit_split_policy_carveouts_under_bwrap`)：测试细粒度文件系统策略
- **嵌套可写子路径** (`sandbox_reenables_writable_subpaths_under_unreadable_parents`)：验证在不可读父目录下的可写子目录
- **符号链接攻击防护** (`sandbox_blocks_codex_symlink_replacement_attack`)：防止通过符号链接绕过保护

## 具体技术实现

### 关键数据结构

```rust
// 超时配置（区分架构）
#[cfg(not(target_arch = "aarch64"))]
const SHORT_TIMEOUT_MS: u64 = 200;
#[cfg(target_arch = "aarch64")]
const SHORT_TIMEOUT_MS: u64 = 5_000;  // ARM64 需要更长超时

// Bubblewrap 不可用错误标识
const BWRAP_UNAVAILABLE_ERR: &str = "build-time bubblewrap is not available in this build.";
```

### 核心测试辅助函数

#### `run_cmd_result_with_writable_roots`
构建带可写根目录的沙箱命令执行环境：

```rust
async fn run_cmd_result_with_writable_roots(
    cmd: &[&str],
    writable_roots: &[PathBuf],
    timeout_ms: u64,
    use_legacy_landlock: bool,
    network_access: bool,
) -> Result<ExecToolCallOutput>
```

流程：
1. 创建 `SandboxPolicy::WorkspaceWrite` 策略
2. 转换为 `FileSystemSandboxPolicy` 和 `NetworkSandboxPolicy`
3. 调用 `process_exec_tool_call` 执行命令

#### `run_cmd_result_with_policies`
完整的策略控制执行函数：

```rust
async fn run_cmd_result_with_policies(
    cmd: &[&str],
    sandbox_policy: SandboxPolicy,
    file_system_sandbox_policy: FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    timeout_ms: u64,
    use_legacy_landlock: bool,
) -> Result<ExecToolCallOutput>
```

关键参数：
- `sandbox_cwd`: 沙箱工作目录
- `codex_linux_sandbox_exe`: 沙箱辅助程序路径（通过 `CARGO_BIN_EXE_codex-linux-sandbox` 获取）
- `use_legacy_landlock`: 是否使用旧版 Landlock（默认使用 Bubblewrap）

#### `should_skip_bwrap_tests`
检测当前环境是否支持 Bubblewrap：

```rust
async fn should_skip_bwrap_tests() -> bool {
    match run_cmd_result_with_writable_roots(
        &["bash", "-lc", "true"],
        &[],
        NETWORK_TIMEOUT_MS,
        false,
        true,
    ).await {
        Ok(output) => is_bwrap_unavailable_output(&output),
        Err(CodexErr::Sandbox(SandboxErr::Denied { output, .. })) => {
            is_bwrap_unavailable_output(&output)
        }
        Err(CodexErr::Sandbox(SandboxErr::Timeout { .. })) => true,
        Err(err) => panic!("bwrap availability probe failed unexpectedly: {err:?}"),
    }
}
```

### 网络阻断验证机制

`assert_network_blocked` 函数实现网络沙箱测试：

```rust
async fn assert_network_blocked(cmd: &[&str]) {
    // 1. 构建只读策略（无网络访问）
    let sandbox_policy = SandboxPolicy::new_read_only_policy();
    
    // 2. 通过 process_exec_tool_call 执行命令
    let result = process_exec_tool_call(
        params,
        &sandbox_policy,
        &FileSystemSandboxPolicy::from(&sandbox_policy),
        NetworkSandboxPolicy::from(&sandbox_policy),
        sandbox_cwd.as_path(),
        &codex_linux_sandbox_exe,
        false,  // use_legacy_landlock
        None,
    ).await;
    
    // 3. 验证命令非成功退出（exit code != 0）
    if output.exit_code == 0 {
        panic!("Network sandbox FAILED - {cmd:?} exited 0");
    }
}
```

### 策略分割测试实现

测试显式文件系统策略（绕过传统策略桥接）：

```rust
let file_system_sandbox_policy = FileSystemSandboxPolicy::restricted(vec![
    FileSystemSandboxEntry {
        path: FileSystemPath::Special {
            value: FileSystemSpecialPath::Minimal,
        },
        access: FileSystemAccessMode::Read,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path {
            path: AbsolutePathBuf::try_from(sandbox_helper_dir.as_path())
                .expect("absolute helper dir"),
        },
        access: FileSystemAccessMode::Read,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path {
            path: AbsolutePathBuf::try_from(tmpdir.path()).expect("absolute tempdir"),
        },
        access: FileSystemAccessMode::Write,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path {
            path: AbsolutePathBuf::try_from(blocked.as_path()).expect("absolute blocked dir"),
        },
        access: FileSystemAccessMode::None,  // 明确拒绝访问
    },
]);
```

## 关键代码路径与文件引用

### 测试调用链

```
landlock.rs test function
    ↓
run_cmd_result_with_writable_roots / run_cmd_result_with_policies
    ↓
process_exec_tool_call (codex-rs/core/src/exec.rs:183)
    ↓
build_exec_request (codex-rs/core/src/exec.rs:209)
    ↓
SandboxManager::transform (codex-rs/core/src/sandboxing/mod.rs)
    ↓
[Linux] spawn_child_async (codex-rs/core/src/spawn.rs)
    ↓
codex-linux-sandbox 二进制 (codex-rs/linux-sandbox/src/main.rs)
    ↓
run_main (codex-rs/linux-sandbox/src/linux_run_main.rs:99)
    ↓
[bwrap 路径] create_bwrap_command_args → exec_bwrap
    ↓
apply_sandbox_policy_to_current_thread (codex-rs/linux-sandbox/src/landlock.rs:42)
    ↓
install_network_seccomp_filter_on_current_thread
```

### 相关文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/linux-sandbox/tests/suite/landlock.rs` | 本测试文件 |
| `codex-rs/linux-sandbox/src/linux_run_main.rs` | 沙箱主入口，协调 bwrap 和 seccomp |
| `codex-rs/linux-sandbox/src/bwrap.rs` | Bubblewrap 命令行构建 |
| `codex-rs/linux-sandbox/src/landlock.rs` | Landlock/seccomp 策略应用 |
| `codex-rs/linux-sandbox/src/launcher.rs` | bwrap 执行器（系统/vendored） |
| `codex-rs/core/src/exec.rs` | 核心执行逻辑，process_exec_tool_call |
| `codex-rs/protocol/src/permissions.rs` | FileSystemSandboxPolicy 定义 |
| `codex-rs/protocol/src/protocol.rs` | SandboxPolicy 定义 |

## 依赖与外部交互

### 外部依赖

1. **Bubblewrap (bwrap)**：用户空间文件系统沙箱
   - 系统路径：`/usr/bin/bwrap`
   - 内嵌路径：通过 `CARGO_BIN_EXE_codex-linux-sandbox` 关联的 vendored bwrap

2. **Landlock (内核特性)**：Linux 5.13+ 的文件系统访问控制
   - 当前作为 legacy 备用方案

3. **seccomp**：系统调用过滤
   - 通过 `seccompiler` crate 生成 BPF 程序
   - 阻断网络相关 syscall

### 环境变量

- `CARGO_BIN_EXE_codex-linux-sandbox`：测试时由 Cargo 设置，指向沙箱二进制
- `TMPDIR`：临时目录路径（可能被包含在可写根目录中）

### 测试前置条件

```rust
// 跳过测试的条件检测
if should_skip_bwrap_tests().await {
    eprintln!("skipping bwrap test: bwrap sandbox prerequisites are unavailable");
    return;
}

if !std::path::Path::new("/dev/shm").exists() {
    eprintln!("skipping bwrap test: /dev/shm is unavailable in this environment");
    return;
}
```

## 风险、边界与改进建议

### 已知风险

1. **架构差异**：ARM64 (aarch64) 测试需要更长的超时（5秒 vs 200毫秒），可能导致 CI 不稳定
2. **环境依赖**：Bubblewrap 在某些容器环境中不可用（如缺少 CAP_SYS_ADMIN）
3. **测试跳过逻辑**：`should_skip_bwrap_tests` 可能因超时误判为不支持 bwrap

### 边界情况

1. **/proc 挂载失败**：某些容器环境拒绝 `--proc /proc`，代码已处理回退逻辑
2. **符号链接攻击**：测试 `sandbox_blocks_codex_symlink_replacement_attack` 验证防护，但依赖文件系统状态
3. **并发执行**：多个测试同时创建临时目录，使用 `tempfile` crate 确保隔离

### 改进建议

1. **增强诊断信息**：
   - 当前 `should_skip_bwrap_tests` 在超时后直接跳过，建议区分"真正不支持"和"超时"
   - 添加更多环境信息输出（内核版本、bwrap 版本等）

2. **测试覆盖率**：
   - 增加对 `FileSystemSpecialPath::ProjectRoots` 的测试
   - 测试更复杂的嵌套策略场景（三层及以上目录层级）

3. **性能优化**：
   - `should_skip_bwrap_tests` 在每个 bwrap 测试前都执行，考虑使用 `lazy_static` 或 `once_cell` 缓存结果
   - ARM64 的超时值可以基于实际运行数据动态调整

4. **错误处理**：
   - `expect_denied` 函数使用 `panic!`，建议改用更结构化的错误断言
   - 网络测试中的 `dbg!` 输出应改为结构化日志

5. **代码组织**：
   - 测试文件已接近 800 行，考虑按功能（文件系统、网络、边界情况）拆分为子模块
   - 共享的辅助函数可以提取到 `tests/common/mod.rs`

### 安全注意事项

1. **测试本身运行在沙箱中**：测试通过 `process_exec_tool_call` 启动沙箱进程，不会直接影响宿主系统
2. **临时文件清理**：使用 `tempfile::tempdir()` 和 `NamedTempFile`，确保测试后清理
3. **命令注入风险**：测试中使用 `format!` 构建命令，但输入来自测试内部生成，风险可控
