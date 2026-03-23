# bwrap.rs 深度研究文档

## 1. 场景与职责

### 1.1 模块定位
`bwrap.rs` 是 Codex Linux 沙箱的核心模块，负责基于 **Bubblewrap** (bwrap) 工具构建文件系统隔离层。它是 Linux 平台沙箱架构中的"外圈"防御机制，与 "内圈"的 seccomp/landlock 形成互补。

### 1.2 核心职责
- **文件系统视图构建**：通过 bubblewrap 的 mount 命名空间创建受限的文件系统视图
- **权限分层管理**：实现只读根目录 + 显式可写路径的安全模型
- **敏感路径保护**：确保 `.git`、`.codex` 等敏感子路径即使在可写父目录下也保持只读
- **网络命名空间控制**：支持网络隔离模式（完全访问/隔离/仅代理）
- **容器环境适配**：检测并适配受限容器环境（如 Docker、Kubernetes）

### 1.3 与 macOS Seatbelt 的语义对齐
模块注释明确指出其设计目标是对齐 macOS Seatbelt 沙箱的语义：
- 文件系统默认只读
- 显式可写根目录叠加
- 敏感子路径保持只读保护

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 使用场景 |
|--------|------|----------|
| `create_bwrap_command_args` | 主入口：根据策略生成 bwrap 参数 | 所有沙箱命令启动 |
| `create_bwrap_flags_full_filesystem` | 完整文件系统访问 + 网络隔离 | 完全磁盘写入权限场景 |
| `create_filesystem_args` | 构建复杂的文件系统挂载参数 | 受限文件系统策略 |
| `create_bwrap_flags` | 组合文件系统和命名空间参数 | 标准沙箱启动流程 |
| 符号链接攻击防护 | 防止通过符号链接绕过保护 | 敏感路径保护 |
| proc 挂载预检 | 检测容器环境 proc 挂载限制 | Docker/K8s 兼容性 |

### 2.2 网络模式策略

```rust
pub(crate) enum BwrapNetworkMode {
    FullAccess,  // 保持主机网络命名空间访问
    Isolated,    // 完全网络隔离（unshare net）
    ProxyOnly,   // 仅代理路由（unshare net + 代理桥接）
}
```

### 2.3 平台默认只读根目录

```rust
const LINUX_PLATFORM_DEFAULT_READ_ROOTS: &[&str] = &[
    "/bin", "/sbin", "/usr", "/etc",
    "/lib", "/lib64", "/nix/store",
    "/run/current-system/sw",
];
```

这些路径在 `include_platform_defaults` 启用时自动添加为只读，确保系统二进制文件和库可访问。

## 3. 具体技术实现

### 3.1 核心数据结构

#### BwrapOptions - 配置选项
```rust
pub(crate) struct BwrapOptions {
    pub mount_proc: bool,           // 是否挂载新的 /proc
    pub network_mode: BwrapNetworkMode,  // 网络隔离模式
}
```

#### BwrapArgs - 生成的参数
```rust
pub(crate) struct BwrapArgs {
    pub args: Vec<String>,          // bwrap 命令行参数
    pub preserved_files: Vec<File>, // 需要保持打开的文件描述符
}
```

### 3.2 挂载顺序算法

文件系统参数构建遵循严格的挂载顺序（代码注释详细说明）：

1. **基础挂载**：`--ro-bind / /`（完全读取）或 `--tmpfs /`（受限读取）
2. **设备树挂载**：`--dev /dev`（提供标准设备节点）
3. **不可读祖先遮罩**：在可写子路径之前遮罩不可读祖先
4. **可写根目录绑定**：`--bind <root> <root>`
5. **只读子路径重绑定**：`--ro-bind <subpath> <subpath>`
6. **嵌套不可读遮罩**：在可写根目录下的不可读路径遮罩
7. **独立不可读遮罩**：与其他路径无关的不可读路径遮罩

### 3.3 关键流程详解

#### 3.3.1 完整磁盘写入优化路径
```rust
fn create_bwrap_flags_full_filesystem(command: Vec<String>, options: BwrapOptions) -> BwrapArgs
```
当策略授予完全磁盘写入权限时，使用简化路径：
- `--bind / /` 绑定整个文件系统（可写）
- `--unshare-user`、`--unshare-pid` 用户和 PID 命名空间
- 条件性 `--unshare-net`（根据网络模式）
- 条件性 `--proc /proc`

#### 3.3.2 受限文件系统策略路径
```rust
fn create_filesystem_args(
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    cwd: &Path,
) -> Result<BwrapArgs>
```

处理复杂的文件系统权限策略：

**路径深度排序**：
```rust
sorted_writable_roots.sort_by_key(|writable_root| path_depth(writable_root.root.as_path()));
```
确保父目录在子目录之前处理。

**不可读祖先遮罩逻辑**：
```rust
let mut unreadable_ancestors_of_writable_roots: Vec<PathBuf> = unreadable_roots
    .iter()
    .filter(|path| {
        let unreadable_root = path.as_path();
        !allowed_write_paths.iter().any(|root| unreadable_root.starts_with(root))
            && allowed_write_paths.iter().any(|root| root.starts_with(unreadable_root))
    })
    .collect();
```
筛选出位于可写路径外部但包含可写路径的不可读祖先。

### 3.4 安全机制

#### 3.4.1 符号链接攻击防护
```rust
fn find_symlink_in_path(target_path: &Path, allowed_write_paths: &[PathBuf]) -> Option<PathBuf>
```
遍历路径的每个组件，检查是否为符号链接且位于可写路径内。如果发现此类符号链接，将使用 `/dev/null` 绑定覆盖它，防止被重定向。

#### 3.4.2 缺失路径组件防护
```rust
fn find_first_non_existent_component(target_path: &Path) -> Option<PathBuf>
```
找到路径中第一个不存在的组件，在其上绑定 `/dev/null`，防止沙盒内进程创建受保护的路径层次结构。

#### 3.4.3 目录遮罩与可写后代重建
```rust
fn append_unreadable_root_args(...)
```
对于需要遮罩的目录：
1. 使用 `--perms 111`（仅执行）或 `000`（无权限）创建 tmpfs
2. 重建可写后代目录结构（`--dir`）
3. 重新挂载为只读（`--remount-ro`）

对于需要遮罩的文件：
1. 使用 `--perms 000`
2. 使用 `--ro-bind-data <null_fd> <path>` 绑定空内容

### 3.5 工作目录规范化
```rust
fn normalize_command_cwd_for_bwrap(command_cwd: &Path) -> PathBuf
```
将工作目录规范化为物理路径（解析符号链接），防止沙盒内的符号链接别名在 mount 命名空间构建后失效。

## 4. 关键代码路径与文件引用

### 4.1 核心调用链

```
linux_run_main::run_main
  ├── create_bwrap_command_args (bwrap.rs:94)
  │   ├── 完全写入路径 → create_bwrap_flags_full_filesystem (bwrap.rs:121)
  │   └── 受限路径 → create_bwrap_flags (bwrap.rs:149)
  │       └── create_filesystem_args (bwrap.rs:209)
  │           ├── 处理可读根目录
  │           ├── 处理可写根目录（排序后）
  │           │   └── append_read_only_subpath_args (bwrap.rs:425)
  │           └── 处理不可读根目录
  │               └── append_unreadable_root_args (bwrap.rs:455)
  └── exec_bwrap (launcher.rs:19)
      ├── exec_system_bwrap (launcher.rs:38)
      └── exec_vendored_bwrap (vendored_bwrap.rs:46)
```

### 4.2 测试覆盖

单元测试位于 `bwrap.rs` 底部（行 598-1245），涵盖：

| 测试函数 | 测试目的 |
|----------|----------|
| `full_disk_write_full_network_returns_unwrapped_command` | 完全权限时跳过 bwrap |
| `full_disk_write_proxy_only_keeps_full_filesystem_but_unshares_network` | 网络隔离但文件系统完整 |
| `restricted_policy_chdirs_to_canonical_command_cwd` | 符号链接工作目录处理 |
| `ignores_missing_writable_roots` | 缺失路径容错 |
| `mounts_dev_before_writable_dev_binds` | /dev 挂载顺序 |
| `split_policy_reapplies_unreadable_carveouts_after_writable_binds` | 不可读遮罩顺序 |
| `split_policy_reenables_nested_writable_subpaths_after_read_only_parent` | 嵌套可写路径 |
| `split_policy_reenables_writable_subpaths_under_unreadable_parents` | 不可读父目录下的可写子路径 |
| `sandbox_blocks_git_and_codex_writes_inside_writable_root` | 敏感路径保护（集成测试） |

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `codex_core::error` | 错误类型定义 |
| `codex_protocol::protocol::FileSystemSandboxPolicy` | 文件系统策略协议 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径处理 |

### 5.2 外部系统依赖

| 依赖 | 用途 | 可选/必需 |
|------|------|-----------|
| `/usr/bin/bwrap` | 系统 bubblewrap | 首选，可选 |
| 内嵌 bwrap | 构建时编译的 bubblewrap | 系统不可用时回退 |
| libcap | Linux capabilities | 构建时必需 |

### 5.3 协议类型依赖

```rust
use codex_protocol::protocol::FileSystemSandboxPolicy;
use codex_protocol::protocol::FileSystemAccessMode;
use codex_protocol::protocol::FileSystemPath;
use codex_protocol::protocol::FileSystemSandboxEntry;
use codex_protocol::protocol::FileSystemSpecialPath;
use codex_protocol::protocol::ReadOnlyAccess;
use codex_protocol::protocol::SandboxPolicy;
```

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 容器环境限制
- **风险**：某些容器环境（如受限 Kubernetes Pod）禁止 `--proc /proc` 挂载
- **缓解**：`preflight_proc_mount_support` 预检机制，失败时回退到 `--no-proc`
- **代码位置**：`linux_run_main.rs:486-500`

#### 6.1.2 setuid 与 no_new_privs 冲突
- **风险**：bwrap 可能依赖 setuid 提升权限，但 seccomp 需要 `PR_SET_NO_NEW_PRIVS`
- **缓解**：采用两阶段执行：先 bwrap（可能使用 setuid），再在内阶段应用 seccomp

#### 6.1.3 符号链接竞争条件
- **风险**：TOCTOU（检查时间到使用时间）攻击
- **缓解**：`find_symlink_in_path` 在构建参数时检测符号链接，但无法完全消除竞争

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 缺失的可写根目录 | 静默跳过（允许跨平台配置） |
| 路径深度 > 系统限制 | 依赖 bubblewrap 处理 |
| 循环符号链接 | 依赖 `find_symlink_in_path` 检测 |
| 非 Linux 平台 | 编译时排除（`#[cfg(target_os = "linux")]`） |

### 6.3 改进建议

#### 6.3.1 性能优化
- **建议**：缓存文件系统策略到 bwrap 参数的转换结果
- **理由**：相同策略可能重复使用，避免重复计算路径深度和排序

#### 6.3.2 可观测性
- **建议**：添加结构化日志记录生成的 bwrap 参数
- **理由**：便于调试沙箱问题，当前仅通过 panic 暴露错误

#### 6.3.3 安全增强
- **建议**：实现路径规范化缓存，减少重复的系统调用
- **理由**：`canonicalize()` 是昂贵的系统调用

#### 6.3.4 测试覆盖
- **建议**：添加针对 NixOS 特殊路径的集成测试
- **理由**：`/nix/store` 和 `/run/current-system/sw` 是 NixOS 特有的平台默认路径

#### 6.3.5 错误处理
- **建议**：将 panic 转换为可恢复的错误类型
- **理由**：当前多处使用 `panic!`，不利于上层优雅降级

### 6.4 维护注意事项

1. **bubblewrap 版本兼容性**：内嵌 bwrap 需要定期同步上游安全更新
2. **Landlock 废弃路径**：代码注释表明 Landlock 是"legacy/backup"，但仍有代码路径依赖
3. **协议版本演进**：`FileSystemSandboxPolicy` 是较新的拆分策略，需要维护与旧版 `SandboxPolicy` 的兼容性
