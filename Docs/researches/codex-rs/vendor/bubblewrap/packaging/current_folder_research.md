# Bubblewrap Packaging 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/vendor/bubblewrap/packaging` 是 OpenAI Codex 项目中 vendored bubblewrap 子项目的打包配置目录。该目录仅包含一个文件 `bubblewrap.spec`，用于定义 RPM 包的构建规范。

### 1.2 核心职责

- **RPM 包构建规范**：为 Fedora/RHEL/CentOS 等基于 RPM 的 Linux 发行版提供软件包构建指令
- **特权模式配置**：定义 bubblewrap 的 setuid 安装模式，确保在没有用户命名空间支持的系统上也能运行沙箱
- **系统集成**：配置 bash-completion、man 手册页和文档的安装位置

### 1.3 在 Codex 项目中的角色

Codex CLI 在 Linux 平台使用 bubblewrap 作为其默认的文件系统沙箱实现：

1. **系统级优先**：Codex 优先使用系统安装的 `/usr/bin/bwrap`
2. **vendored 回退**：当系统 bwrap 不可用时，编译并使用 vendored 版本
3. **安全隔离**：通过 bubblewrap 创建只读根文件系统、用户命名空间隔离和可选的网络命名空间隔离

---

## 2. 功能点目的

### 2.1 bubblewrap.spec 文件分析

```spec
%global commit0 66d12bb23b04e201c5846e325f0b10930ed802f8
%global shortcommit0 %(c=%{commit0}; echo ${c:0:7})
```

**目的**：使用特定 Git commit 而非版本标签进行构建，确保构建的可重现性。

### 2.2 关键构建配置

```spec
%build
env NOCONFIGURE=1 ./autogen.sh
%configure --disable-silent-rules --with-priv-mode=none
```

| 配置项 | 值 | 目的 |
|--------|-----|------|
| `NOCONFIGURE=1` | 环境变量 | 阻止 autogen.sh 自动运行 configure |
| `--disable-silent-rules` | 配置选项 | 启用详细构建输出，便于调试 |
| `--with-priv-mode=none` | 配置选项 | **关键**：禁用 setuid 特权模式，依赖用户命名空间 |

**注意**：`--with-priv-mode=none` 的选择反映了现代 Linux 发行版对用户命名空间的支持已经成熟，不再需要在构建时强制 setuid。

### 2.3 文件权限处理

```spec
%if (0%{?rhel} != 0 && 0%{?rhel} <= 7)
%attr(4755,root,root) %{_bindir}/bwrap
%else
%{_bindir}/bwrap
%endif
```

**条件逻辑**：
- **RHEL 7 及更早版本**：设置 setuid 位 (4755)，因为内核不支持非特权用户命名空间
- **RHEL 8+ / 现代发行版**：普通权限 (755)，依赖内核的用户命名空间功能

---

## 3. 具体技术实现

### 3.1 Bubblewrap 核心架构

#### 3.1.1 命名空间隔离

Bubblewrap 使用 Linux 命名空间实现隔离（定义在 `bubblewrap.c`）：

```c
static bool opt_unshare_user = false;   // CLONE_NEWUSER - 用户命名空间
static bool opt_unshare_pid = false;    // CLONE_NEWPID - PID 命名空间
static bool opt_unshare_ipc = false;    // CLONE_NEWIPC - IPC 命名空间
static bool opt_unshare_net = false;    // CLONE_NEWNET - 网络命名空间
static bool opt_unshare_uts = false;    // CLONE_NEWUTS - UTS (主机名) 命名空间
static bool opt_unshare_cgroup = false; // CLONE_NEWCGROUP - cgroup 命名空间
```

#### 3.1.2 设置操作类型

```c
typedef enum {
  SETUP_BIND_MOUNT,              // --bind
  SETUP_RO_BIND_MOUNT,           // --ro-bind
  SETUP_DEV_BIND_MOUNT,          // --dev-bind
  SETUP_OVERLAY_MOUNT,           // --overlay
  SETUP_TMP_OVERLAY_MOUNT,       // --tmp-overlay
  SETUP_RO_OVERLAY_MOUNT,        // --ro-overlay
  SETUP_MOUNT_PROC,              // --proc
  SETUP_MOUNT_DEV,               // --dev
  SETUP_MOUNT_TMPFS,             // --tmpfs
  SETUP_MAKE_DIR,                // --dir
  SETUP_MAKE_FILE,               // --file
  SETUP_MAKE_SYMLINK,            // --symlink
  SETUP_SET_HOSTNAME,            // --hostname
  SETUP_CHMOD,                   // --chmod
} SetupOpType;
```

### 3.2 特权分离机制

当 bubblewrap 以 setuid 模式运行时，使用特权分离（privilege separation）架构：

```c
enum {
  PRIV_SEP_OP_DONE,
  PRIV_SEP_OP_BIND_MOUNT,
  PRIV_SEP_OP_OVERLAY_MOUNT,
  PRIV_SEP_OP_PROC_MOUNT,
  PRIV_SEP_OP_TMPFS_MOUNT,
  PRIV_SEP_OP_DEVPTS_MOUNT,
  PRIV_SEP_OP_MQUEUE_MOUNT,
  PRIV_SEP_OP_REMOUNT_RO_NO_RECURSIVE,
  PRIV_SEP_OP_SET_HOSTNAME,
};
```

**工作流程**：
1. 主进程 fork 出特权辅助进程
2. 非特权进程通过 Unix socket 发送操作请求
3. 特权进程执行需要 CAP_SYS_ADMIN 的 mount 操作
4. 操作完成后，特权进程退出

### 3.3 根文件系统设置流程

```c
// bubblewrap.c: main() 中的关键步骤

// 1. 创建新的 mount 命名空间
clone_flags = SIGCHLD | CLONE_NEWNS;

// 2. 在 /tmp 创建 tmpfs 作为新根
mount ("tmpfs", base_path, "tmpfs", MS_NODEV | MS_NOSUID, NULL);

// 3. 创建 newroot 和 oldroot 目录
mkdir ("newroot", 0755);
mkdir ("oldroot", 0755);

// 4. 第一次 pivot_root - 将 tmpfs 设为根
pivot_root (base_path, "oldroot");

// 5. 执行所有设置操作（bind mount、overlay 等）
setup_newroot ();

// 6. 第二次 pivot_root - 切换到最终的 newroot
pivot_root (".", ".");
umount2 (".", MNT_DETACH);
```

### 3.4 Codex 的 Bubblewrap 集成

#### 3.4.1 参数构建（`bwrap.rs`）

Codex 根据 `FileSystemSandboxPolicy` 构建 bubblewrap 参数：

```rust
fn create_bwrap_flags(...) -> Result<BwrapArgs> {
    let mut args = Vec::new();
    
    // 安全基础
    args.push("--new-session".to_string());
    args.push("--die-with-parent".to_string());
    
    // 命名空间隔离
    args.push("--unshare-user".to_string());
    args.push("--unshare-pid".to_string());
    
    if options.network_mode.should_unshare_network() {
        args.push("--unshare-net".to_string());
    }
    
    // 文件系统设置
    if file_system_sandbox_policy.has_full_disk_read_access() {
        args.extend(["--ro-bind", "/", "/"]);
    } else {
        args.extend(["--tmpfs", "/"]);
        // 添加特定的只读绑定
    }
    
    args.push("--dev".to_string());
    args.push("/dev".to_string());
    
    // 可写根目录
    for writable_root in writable_roots {
        args.extend(["--bind", root, root]);
    }
}
```

#### 3.4.2 启动器选择（`launcher.rs`）

```rust
const SYSTEM_BWRAP_PATH: &str = "/usr/bin/bwrap";

enum BubblewrapLauncher {
    System(AbsolutePathBuf),  // 使用系统 bwrap
    Vendored,                  // 使用内嵌的 vendored 版本
}

fn preferred_bwrap_launcher() -> BubblewrapLauncher {
    if !Path::new(SYSTEM_BWRAP_PATH).is_file() {
        return BubblewrapLauncher::Vendored;
    }
    // ... 返回 System
}
```

#### 3.4.3 Vendored 构建（`build.rs`）

```rust
fn try_build_vendored_bwrap() -> Result<(), String> {
    let mut build = cc::Build::new();
    build
        .file(src_dir.join("bubblewrap.c"))
        .file(src_dir.join("bind-mount.c"))
        .file(src_dir.join("network.c"))
        .file(src_dir.join("utils.c"))
        .define("main", Some("bwrap_main"));  // 重命名 main 以便 FFI 调用
    
    build.compile("build_time_bwrap");
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 描述 |
|------|------|------|
| `bubblewrap.spec` | 48 | RPM 包构建规范 |

### 4.2 上游 Bubblewrap 源文件

| 文件 | 行数 | 核心功能 |
|------|------|----------|
| `bubblewrap.c` | 3641 | 主程序逻辑、命名空间管理、设置操作执行 |
| `bind-mount.c` | ~500 | 挂载信息解析、mount 选项处理 |
| `network.c` | 199 | 网络命名空间中的 loopback 设备设置 |
| `utils.c` | ~700 | 工具函数、内存管理、文件操作、SELinux 支持 |
| `meson.build` | 171 | Meson 构建配置 |

### 4.3 Codex 集成文件

| 文件 | 描述 |
|------|------|
| `codex-rs/linux-sandbox/src/bwrap.rs` | Bubblewrap 参数构建逻辑 |
| `codex-rs/linux-sandbox/src/launcher.rs` | 系统/vendored bwrap 选择 |
| `codex-rs/linux-sandbox/src/vendored_bwrap.rs` | Vendored bwrap FFI 调用 |
| `codex-rs/linux-sandbox/build.rs` | 构建时编译 vendored bwrap |
| `codex-rs/vendor/BUILD.bazel` | Bazel 构建的源文件组定义 |

### 4.4 关键代码路径

#### 4.4.1 Bubblewrap 启动流程

```
bubblewrap.c:main()
  ├── acquire_privs()           # 获取特权 (setuid 模式)
  ├── parse_args()              # 解析命令行参数
  ├── raw_clone()               # 创建新命名空间
  ├── setup_newroot()           # 设置新根文件系统
  │   ├── SETUP_MOUNT_DEV       # 挂载 /dev
  │   ├── SETUP_RO_BIND_MOUNT   # 只读绑定挂载
  │   ├── SETUP_BIND_MOUNT      # 可写绑定挂载
  │   └── ...
  ├── pivot_root()              # 切换根文件系统
  └── execvp()                  # 执行目标程序
```

#### 4.4.2 Codex 调用路径

```
linux_run_main::run_main()
  ├── create_bwrap_command_args()  # bwrap.rs
  │   └── create_bwrap_flags()
  │       └── create_filesystem_args()
  ├── exec_bwrap()                 # launcher.rs
  │   ├── exec_system_bwrap()      # 优先路径
  │   └── exec_vendored_bwrap()    # 回退路径
  │       └── bwrap_main()         # FFI 调用 vendored C 代码
```

---

## 5. 依赖与外部交互

### 5.1 构建依赖（来自 spec 文件）

| 依赖 | 用途 |
|------|------|
| `git` | 源码版本控制 |
| `autoconf` / `automake` / `libtool` | 构建系统 |
| `libcap-devel` | POSIX capabilities 支持 |
| `libselinux` | SELinux 标签支持 |
| `libxslt` / `docbook-style-xsl` | man 手册页生成 |

### 5.2 运行时依赖

| 依赖 | 说明 |
|------|------|
| Linux 内核 >= 3.8 | 用户命名空间支持（推荐）|
| libcap | 用于 capabilities 管理 |
| libselinux (可选) | 用于 SELinux 标签 |

### 5.3 内核特性要求

```c
// 必需
CLONE_NEWNS      // mount 命名空间
CLONE_NEWPID     // PID 命名空间（可选但推荐）

// 可选但推荐
CLONE_NEWUSER    // 用户命名空间（现代发行版）
CLONE_NEWNET     // 网络命名空间
CLONE_NEWIPC     // IPC 命名空间
CLONE_NEWUTS     // UTS 命名空间
CLONE_NEWCGROUP  // cgroup 命名空间（较新内核）
```

### 5.4 与 Codex 其他组件的交互

```
┌─────────────────────────────────────────────────────────────┐
│                      Codex CLI                              │
└──────────────────────┬──────────────────────────────────────┘
                       │ FileSystemSandboxPolicy
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              codex-linux-sandbox                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   bwrap.rs   │  │ launcher.rs  │  │ vendored_bwrap.rs│  │
│  │ (参数构建)    │  │ (启动器选择)  │  │ (FFI 调用)       │  │
│  └──────────────┘  └──────┬───────┘  └──────────────────┘  │
└───────────────────────────┼─────────────────────────────────┘
                            │
           ┌────────────────┴────────────────┐
           ▼                                 ▼
┌──────────────────────┐          ┌──────────────────────┐
│   /usr/bin/bwrap     │          │   vendored bwrap     │
│   (系统安装)          │          │   (内嵌编译)          │
└──────────────────────┘          └──────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 6.1.1 Setuid 模式风险

虽然 `bubblewrap.spec` 中 `--with-priv-mode=none` 禁用了 setuid，但在 RHEL 7 上仍可能通过 `%attr(4755,root,root)` 设置 setuid 位。

**风险**：
- Setuid 二进制文件是特权升级攻击的高价值目标
- 历史上 bubblewrap 曾修复过多个 setuid 相关的安全漏洞（如 CVE-2017-5226）

**缓解**：
- 现代发行版应优先使用用户命名空间而非 setuid
- Codex 的 vendored 版本不启用 setuid

#### 6.1.2 TIOCSTI 攻击

```c
// CVE-2017-5226 修复
if (opt_new_session &&
    setsid () == (pid_t) -1)
  die_with_error ("setsid");
```

`--new-session` 选项创建新的终端会话，防止通过 TIOCSTI ioctl 向父 shell 注入命令。

### 6.2 功能边界

#### 6.2.1 不支持的平台

- **非 Linux 系统**：Bubblewrap 依赖 Linux 特有的命名空间机制
- **旧内核**（< 3.8）：缺乏用户命名空间支持
- **禁用用户命名空间的内核**：如某些 Debian/Ubuntu 配置

#### 6.2.2 嵌套沙箱限制

```c
if (opt_disable_userns || opt_assert_userns_disabled)
  {
    /* Verify that we can't make a new userns again */
    res = unshare (CLONE_NEWUSER);
    if (res == 0)
      die ("creation of new user namespaces was not disabled as requested");
  }
```

`--disable-userns` 可防止沙箱内进一步创建用户命名空间，但这也限制了嵌套沙箱的能力。

### 6.3 已知问题

#### 6.3.1 FUSE 文件系统访问

在 `--unshare-user` 模式下，FUSE 文件系统可能无法正常工作，因为内核要求访问 FUSE 挂载的 UID 与挂载时的 UID 匹配。

#### 6.3.2 /proc 挂载限制

某些容器环境（如 Docker 默认配置）禁止 `--proc /proc`，Codex 提供了 `--no-proc` 选项作为回退。

### 6.4 改进建议

#### 6.4.1 短期改进

1. **更新 spec 文件中的 commit**：
   ```spec
   %global commit0 66d12bb23b04e201c5846e325f0b10930ed802f8
   ```
   当前使用的是 2023 年的版本，建议更新到最新稳定版。

2. **添加版本标签支持**：
   当前 spec 文件使用 commit hash，建议同时支持版本标签以便追踪。

#### 6.4.2 中期改进

1. **Landlock LSM 集成**：
   Codex 已有 Landlock 支持（`landlock.rs`），但当前默认使用 bubblewrap。考虑在支持 Landlock 的系统上优先使用原生 LSM，减少依赖外部二进制文件。

2. **seccomp 策略增强**：
   当前 Codex 使用基本的 seccomp 网络过滤。可以扩展为更细粒度的系统调用过滤，与 bubblewrap 的文件系统隔离形成纵深防御。

#### 6.4.3 长期改进

1. **用户命名空间检测**：
   ```rust
   // 在 launcher.rs 中添加运行时检测
   fn check_userns_support() -> bool {
       // 尝试 unshare(CLONE_NEWUSER)
       // 返回是否支持
   }
   ```
   在启动时检测用户命名空间支持，提供更有针对性的错误信息。

2. **OCI 运行时兼容**：
   考虑支持 OCI 运行时规范，使 Codex 沙箱可以与 containerd、cri-o 等容器运行时互操作。

### 6.5 监控与调试

#### 6.5.1 调试标志

Bubblewrap 支持 `PR_SET_DUMPABLE` 和 info fd 输出：

```c
if (opt_info_fd != -1)
  {
    cleanup_free char *output = xasprintf ("{\n    \"child-pid\": %i", pid);
    dump_info (opt_info_fd, output, true);
    namespace_ids_write (opt_info_fd, false);
  }
```

#### 6.5.2 日志记录

Codex 可以通过 `--level-prefix` 选项启用分级日志：

```c
if (bwrap_level_prefix)
  fprintf (stderr, "<%d>", severity);
```

---

## 7. 附录

### 7.1 参考链接

- [Bubblewrap 上游仓库](https://github.com/containers/bubblewrap)
- [Bubblewrap 官方文档](https://github.com/containers/bubblewrap/blob/main/README.md)
- [Linux 用户命名空间文档](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Codex Linux Sandbox README](/home/sansha/Github/codex/codex-rs/linux-sandbox/README.md)

### 7.2 相关 CVE

| CVE | 描述 | 修复版本 |
|-----|------|----------|
| CVE-2017-5226 | TIOCSTI 终端注入 | 0.1.2 |
| CVE-2016-3135 | 用户命名空间权限绕过 | N/A (内核修复) |

### 7.3 术语表

| 术语 | 解释 |
|------|------|
| Setuid | 设置用户 ID 位，允许程序以文件所有者权限运行 |
| Namespace | Linux 内核提供的资源隔离机制 |
| Pivot_root | 切换进程的根文件系统，比 chroot 更安全 |
| Privilege separation | 将特权操作与非特权代码分离的安全设计 |
| Seccomp | Linux 安全计算模式，限制进程可调用的系统调用 |
| Landlock | Linux 5.13+ 引入的非特权沙箱 LSM |
