# seatbelt.rs 研究文档

## 场景与职责

`seatbelt.rs` 是 Codex Core 的 macOS 特定测试文件，专注于验证 **macOS Seatbelt 沙盒机制**。Seatbelt 是 macOS 的内置沙盒系统（`sandbox-exec`），Codex 使用它来限制子进程的权限：

- **文件系统访问控制**：限制可读写路径
- **网络访问控制**：限制网络连接
- **Git 仓库保护**：防止意外修改 `.git` 目录
- **平台特定行为**：验证 macOS 特有的沙盒行为

本测试仅适用于 macOS（`#![cfg(target_os = "macos")]`）。

## 功能点目的

### 1. 父目录可写时的 Git 目录访问 (`if_parent_of_repo_is_writable_then_dot_git_folder_is_writable`)
验证当工作区根是 Git 仓库父目录时的行为：
- 配置 `WorkspaceWrite` 策略，可写根为仓库父目录
- 验证仓库外文件可写
- 验证仓库内文件可写
- **验证 `.git` 目录可写**（因为父目录可写，无法单独限制）

### 2. Git 仓库根可写时的保护 (`if_git_repo_is_writable_root_then_dot_git_folder_is_read_only`)
验证当工作区根是 Git 仓库根时的 `.git` 保护：
- 配置 `WorkspaceWrite` 策略，可写根为仓库根
- 验证仓库外文件不可写
- 验证仓库内文件可写
- **验证 `.git` 目录不可写**（自动保护）

### 3. 完全访问模式 (`danger_full_access_allows_all_writes`)
验证 `DangerFullAccess` 策略允许所有写入：
- 任何地方（包括 `.git`）都可写
- 用于用户明确信任的场景

### 4. 只读模式 (`read_only_forbids_all_writes`)
验证 `ReadOnly` 策略禁止所有写入：
- 任何地方都不可写
- 用于安全审查场景

### 5. OpenPTY 支持 (`openpty_works_under_seatbelt`)
验证伪终端（PTY）在沙盒中正常工作：
- 使用 Python 测试 `os.openpty()`
- 验证主/从设备读写
- 确保交互式 shell 工具可用

### 6. Java Home 检测 (`java_home_finds_runtime_under_seatbelt`)
验证 `/usr/libexec/java_home` 在沙盒中正常工作：
- 需要读取系统 Java 配置
- 验证沙盒不破坏系统工具执行

## 具体技术实现

### 关键数据结构

```rust
// 测试场景结构
struct TestScenario {
    repo_parent: PathBuf,           // 仓库父目录
    file_outside_repo: PathBuf,     // 仓库外文件
    repo_root: PathBuf,             // 仓库根
    file_in_repo_root: PathBuf,     // 仓库内文件
    file_in_dot_git_dir: PathBuf,   // .git 目录内文件
}

// 测试期望
struct TestExpectations {
    file_outside_repo_is_writable: bool,
    file_in_repo_root_is_writable: bool,
    file_in_dot_git_dir_is_writable: bool,
}
```

### Seatbelt 策略生成

```rust
// 来自 codex_core::seatbelt
create_seatbelt_command_args_for_policies_with_extensions(
    command: Vec<String>,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_policy_cwd: &Path,
    enforce_managed_network: bool,
    network: Option<&NetworkProxy>,
    extensions: Option<&MacOsSeatbeltProfileExtensions>,
) -> Vec<String>
```

### 沙盒策略片段

```rust
// 基础策略（seatbelt_base_policy.sbpl）
// - 允许基本系统调用
// - 允许标准库路径读取

// 文件写入策略
"(allow file-write* (subpath (param \"WRITABLE_ROOT_0\")))"

// 带排除的路径策略
"(require-all (subpath (param \"WRITABLE_ROOT_0\")) (require-not (subpath (param \"WRITABLE_ROOT_0_RO_0\"))))"

// 网络策略
"(allow network-outbound (remote ip \"localhost:8080\"))"
```

### 测试执行流程

```rust
async fn touch(path: &Path, policy: &SandboxPolicy) -> bool {
    let mut child = spawn_command_under_seatbelt(
        vec!["/usr/bin/touch".to_string(), path.to_string_lossy().to_string()],
        command_cwd,
        policy,
        sandbox_cwd.as_path(),
        StdioPolicy::RedirectForShellTool,
        None,
        HashMap::new(),
    ).await.expect("should be able to spawn command under seatbelt");
    
    child.wait().await.expect("...").success()
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::seatbelt::spawn_command_under_seatbelt` | Seatbelt 进程启动 |
| `codex_core::spawn::StdioPolicy` | 标准输入输出策略 |
| `codex_protocol::protocol::SandboxPolicy` | 沙盒策略定义 |

### 外部依赖

| 组件 | 用途 |
|------|------|
| `/usr/bin/sandbox-exec` | macOS 沙盒可执行文件 |
| `/usr/bin/touch` | 文件写入测试 |
| `python3` | PTY 测试 |
| `/usr/libexec/java_home` | Java 检测测试 |

### 沙盒策略文件

```
codex-rs/core/src/
├── seatbelt_base_policy.sbpl          # 基础策略
├── seatbelt_network_policy.sbpl       # 网络策略
└── restricted_read_only_platform_defaults.sbpl  # 只读默认策略
```

## 风险、边界与改进建议

### 当前风险

1. **平台限制**：仅测试 macOS，Linux/Windows 使用不同沙盒机制
2. **环境依赖**：需要 `python3` 和 `java_home`，测试可能因环境缺失被跳过
3. **嵌套沙盒**：当 `CODEX_SANDBOX=seatbelt` 时，测试会跳过（无法嵌套沙盒）

### 边界情况

1. **符号链接**：未测试通过符号链接访问受保护路径
2. **硬链接**：未测试硬链接绕过路径检查
3. **资源限制**：未测试 CPU/内存限制
4. **时间精度**：文件修改时间检测的精度问题

### 改进建议

1. **测试扩展**：
   - 添加对 `com.apple.security` 扩展属性的测试
   - 测试沙盒内的进程间通信（IPC）
   - 测试沙盒内的文件锁定行为

2. **性能优化**：
   - 缓存编译后的沙盒策略
   - 并行执行独立的沙盒测试

3. **安全增强**：
   - 添加对 `sandbox-exec` 被篡改的检测
   - 测试策略注入攻击防护

4. **跨平台统一**：
   - 考虑使用抽象层统一 macOS Seatbelt、Linux Landlock/seccomp、Windows 沙盒的测试
   - 共享测试场景定义，平台特定实现

5. **可观测性**：
   - 记录沙盒违规尝试
   - 监控沙盒启动时间

### 相关文件引用

- `codex-rs/core/src/seatbelt.rs` - Seatbelt 实现
- `codex-rs/core/src/seatbelt_permissions.rs` - 权限扩展
- `codex-rs/core/src/seatbelt_tests.rs` - 单元测试
- `codex-rs/core/src/sandboxing/mod.rs` - 跨平台沙盒抽象
- `codex-rs/core/src/landlock.rs` - Linux Landlock 实现
