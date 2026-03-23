# linux_run_main_tests.rs 研究文档

## 场景与职责

`linux_run_main_tests.rs` 是 `codex-linux-sandbox` crate 的集成测试模块，作为 `linux_run_main.rs` 的测试子模块被引入（通过 `#[path = "linux_run_main_tests.rs"]`）。该文件负责验证 Linux 沙箱核心逻辑的正确性，包括：

1. **bubblewrap 错误检测**：识别 `/proc` 挂载失败的特定错误模式
2. **命令行参数构建**：验证 bwrap 参数生成逻辑的正确性
3. **沙箱策略解析**：测试新旧策略格式的兼容性和冲突检测
4. **网络模式选择**：验证代理模式与网络隔离的优先级逻辑
5. **内部命令构建**：测试 seccomp 应用阶段的命令组装

## 功能点目的

### 1. proc 挂载失败检测 (`is_proc_mount_failure`)

检测 bubblewrap 在受限容器环境中挂载 `/proc` 失败的三种错误模式：
- `Invalid argument` - 参数无效
- `Operation not permitted` - 操作不被允许
- `Permission denied` - 权限被拒绝

**目的**：在预检阶段识别是否需要回退到 `--no-proc` 模式。

### 2. bwrap 参数构建验证

验证 `build_bwrap_argv` 函数生成的参数序列：
- `--argv0` 插入位置（必须在 `--` 分隔符之前）
- `--unshare-net` 在网络隔离/代理模式下的插入
- 基础参数如 `--new-session`, `--die-with-parent`, `--ro-bind` 等

### 3. 沙箱策略解析 (`resolve_sandbox_policies`)

测试策略解析的多种场景：
- 旧版策略（`SandboxPolicy`）自动派生分裂策略
- 分裂策略（`FileSystemSandboxPolicy` + `NetworkSandboxPolicy`）反向派生旧版策略
- 部分分裂策略的拒绝（只提供一个而不提供另一个）
- 策略语义不匹配检测
- 需要直接运行时执行的特殊策略（如 root 写权限 + 特定读权限）

### 4. 网络模式优先级

验证 `bwrap_network_mode` 的优先级逻辑：
- `allow_network_for_proxy=true` 时，即使网络策略为 `Enabled`，也强制使用 `ProxyOnly` 模式

### 5. 内部 seccomp 命令构建

验证 `build_inner_seccomp_command` 生成的命令结构：
- 包含 `--apply-seccomp-then-exec` 标志
- 序列化所有策略参数
- 代理模式下包含 `--proxy-route-spec`
- 非代理模式下不包含路由规范

### 6. 模式兼容性验证

- `--apply-seccomp-then-exec` 与 `--use-legacy-landlock` 互斥
- 旧版 Landlock 模式不支持需要直接运行时执行的策略

## 具体技术实现

### 测试结构

```rust
#[cfg(test)]
mod tests {
    // 使用 pretty_assertions 提供清晰的差异输出
    use pretty_assertions::assert_eq;
    
    // 测试函数命名规范：动作_条件_预期结果
    fn detects_proc_mount_invalid_argument_failure() { ... }
}
```

### 关键测试数据构造

**SandboxPolicy 构造**：
```rust
let sandbox_policy = SandboxPolicy::new_read_only_policy();
// 或
let sandbox_policy = SandboxPolicy::WorkspaceWrite {
    writable_roots: vec![...],
    read_only_access: ReadOnlyAccess::FullAccess,
    network_access: false,
    exclude_tmpdir_env_var: false,
    exclude_slash_tmp: false,
};
```

**FileSystemSandboxPolicy 构造**：
```rust
let policy = FileSystemSandboxPolicy::restricted(vec![
    FileSystemSandboxEntry {
        path: FileSystemPath::Special {
            value: FileSystemSpecialPath::CurrentWorkingDirectory,
        },
        access: FileSystemAccessMode::Write,
    },
    FileSystemSandboxEntry {
        path: FileSystemPath::Path { path: docs },
        access: FileSystemAccessMode::Read,
    },
]);
```

**BwrapOptions 构造**：
```rust
BwrapOptions {
    mount_proc: true,
    network_mode: BwrapNetworkMode::FullAccess, // 或 Isolated, ProxyOnly
}
```

### 断言模式

**向量包含检查**：
```rust
assert!(argv.contains(&"--unshare-net".to_string()));
```

**窗口匹配（成对参数）**：
```rust
assert!(
    args.windows(2)
        .any(|window| { window == ["--command-cwd", "/tmp/link"] })
);
```

**panic 预期测试**：
```rust
let result = std::panic::catch_unwind(|| {
    build_inner_seccomp_command(...)
});
assert!(result.is_err());
```

## 关键代码路径与文件引用

### 被测试的主实现文件

| 测试函数 | 被测试函数 | 定义位置 |
|---------|-----------|---------|
| `detects_proc_mount_*` | `is_proc_mount_failure` | `linux_run_main.rs:607-613` |
| `inserts_bwrap_argv0_*` | `build_bwrap_argv` | `linux_run_main.rs:452-484` |
| `inserts_unshare_net_*` | `build_bwrap_argv` | `linux_run_main.rs:452-484` |
| `proxy_only_mode_*` | `bwrap_network_mode` | `linux_run_main.rs:439-450` |
| `split_only_filesystem_policy_*` | `needs_direct_runtime_enforcement` | `codex-protocol` |
| `managed_proxy_*` | `build_preflight_bwrap_argv` | `linux_run_main.rs:502-519` |
| `managed_proxy_inner_command_*` | `build_inner_seccomp_command` | `linux_run_main.rs:615-683` |
| `inner_command_includes_*` | `build_inner_seccomp_command` | `linux_run_main.rs:615-683` |
| `resolve_sandbox_policies_*` | `resolve_sandbox_policies` | `linux_run_main.rs:273-346` |
| `apply_seccomp_then_exec_*` | `ensure_inner_stage_mode_is_valid` | `linux_run_main.rs:377-381` |
| `legacy_landlock_*` | `ensure_legacy_landlock_mode_supports_policy` | `linux_run_main.rs:383-397` |

### 依赖类型

```rust
// 协议类型
use codex_protocol::protocol::FileSystemSandboxPolicy;
use codex_protocol::protocol::NetworkSandboxPolicy;
use codex_protocol::protocol::ReadOnlyAccess;
use codex_protocol::protocol::SandboxPolicy;

// 工具类型
use codex_utils_absolute_path::AbsolutePathBuf;

// 测试工具
use pretty_assertions::assert_eq;
```

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_protocol` | 沙箱策略类型定义 |
| `codex_utils_absolute_path` | 绝对路径处理 |
| `pretty_assertions` | 测试断言美化 |
| `tempfile` | 临时目录创建（通过 dev-dependencies） |

### 文件系统交互

测试中使用 `tempfile::TempDir` 创建临时目录结构：
```rust
let temp_dir = tempfile::TempDir::new().expect("tempdir");
let docs = temp_dir.path().join("docs");
std::fs::create_dir_all(&docs).expect("create docs");
```

### 进程交互

- 使用 `std::panic::catch_unwind` 捕获预期 panic
- 使用 `std::process::id()` 获取当前 PID 用于测试数据

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖盲区**：
   - `run_bwrap_in_child_capture_stderr` 的 fork/exec 逻辑难以在单元测试中覆盖
   - `exec_bwrap` 和 `exec_or_panic` 的实际执行路径无法测试

2. **平台依赖**：
   - 部分测试依赖 `/usr/bin/true` 或 `/bin/true` 存在
   - 依赖真实文件系统路径（如 `/usr`）存在性检查

3. **临时目录竞争**：
   - `cleanup_stale_proxy_socket_dirs_in` 测试使用固定 PID 模式，可能存在并发问题

### 边界情况

1. **策略解析边界**：
   - 空策略列表的处理
   - 循环依赖检测（如 root 读写 + 子目录只读）
   - 符号链接路径的规范化

2. **参数构建边界**：
   - 超长参数列表的处理
   - 特殊字符在路径中的转义

### 改进建议

1. **增加集成测试**：
   - 添加需要实际 bubblewrap 执行的测试（标记为 `#[ignore]` 或单独测试套件）
   - 测试真实的 `/proc` 挂载失败回退场景

2. **增强错误场景覆盖**：
   - 测试 `resolve_sandbox_policies` 的所有错误变体
   - 测试 JSON 序列化失败的处理

3. **并发安全测试**：
   - 为 `cleanup_stale_proxy_socket_dirs_in` 添加并发压力测试
   - 测试多个代理路由同时创建的场景

4. **文档改进**：
   - 为复杂测试用例添加更多注释说明测试意图
   - 添加测试数据构造的辅助函数减少重复代码

5. **Mock 支持**：
   - 考虑引入 mock 框架测试与 bubblewrap 的交互
   - Mock `libc::fork` 和 `libc::execvp` 以测试错误路径
