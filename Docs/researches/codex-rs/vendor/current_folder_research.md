# codex-rs/vendor 目录深度研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/vendor` 目录是 Codex CLI 项目的第三方依赖源码托管目录，专门用于存放经过筛选和验证的外部 C/C++ 库源码。当前该目录仅包含 **bubblewrap** 一个项目，这是一个由 Flatpak 团队开发的 Linux 沙箱工具。

### 1.2 核心职责

该目录承担以下关键职责：

1. **构建时沙箱能力提供**：为 `codex-linux-sandbox` crate 提供编译时集成的 bubblewrap 能力，使得 Codex CLI 在 Linux 平台上无需依赖系统安装的 bubblewrap 即可执行沙箱隔离。

2. **供应链安全**：通过源码级 vendoring，避免对外部系统包的运行时依赖，减少供应链攻击面。

3. **跨平台构建一致性**：确保在不同 Linux 发行版上都能获得一致的沙箱行为，不受系统 bubblewrap 版本差异影响。

4. **降级安全网**：当系统未安装 `/usr/bin/bwrap` 时，自动回退到 vendored 版本，保证功能可用性。

### 1.3 使用场景

| 场景 | 行为 |
|------|------|
| 系统有 `/usr/bin/bwrap` | 优先使用系统版本，通过 `execv` 执行 |
| 系统无 bubblewrap | 调用 vendored 版本，通过 FFI 调用 `bwrap_main` |
| 容器/受限环境 | 完全自包含，无需额外安装依赖 |
| 开发/调试 | 可通过 `CODEX_BWRAP_SOURCE_DIR` 环境变量指向自定义 bubblewrap 源码 |

---

## 2. 功能点目的

### 2.1 Bubblewrap 功能概述

Bubblewrap 是一个轻量级的 Linux 沙箱工具，通过 Linux 内核命名空间（namespaces）和权限控制机制实现进程隔离。其核心设计目标是：

- **非特权用户可用**：通过 setuid 或 user namespaces 实现非 root 用户创建沙箱
- **最小权限原则**：仅保留必要的 capabilities（CAP_SYS_ADMIN, CAP_SYS_CHROOT 等）
- **可组合性**：通过命令行参数灵活配置沙箱策略

### 2.2 Codex 使用的关键功能

| 功能 | 命令行参数 | 目的 |
|------|-----------|------|
| 用户命名空间隔离 | `--unshare-user` | 创建独立的 UID/GID 映射，防止特权提升 |
| PID 命名空间隔离 | `--unshare-pid` | 隔离进程视图，防止进程枚举 |
| 网络命名空间隔离 | `--unshare-net` | 隔离网络栈，配合代理实现受控网络访问 |
| 挂载命名空间隔离 | `--unshare-all` | 创建独立的文件系统视图 |
| 只读根文件系统 | `--ro-bind / /` | 默认只读，保护系统文件 |
| 可写目录绑定 | `--bind <src> <dest>` | 开放特定目录的写权限 |
| 临时文件系统 | `--tmpfs <path>` | 创建内存中的临时目录 |
| 设备节点挂载 | `--dev <path>` | 提供标准设备节点（/dev/null, /dev/urandom 等） |
| 进程生命周期绑定 | `--die-with-parent` | 父进程退出时自动终止沙箱 |
| 新会话创建 | `--new-session` | 防止 TIOCSTI 攻击（CVE-2017-5226） |
| Seccomp 过滤 | `--seccomp <fd>` | 系统调用过滤 |

### 2.3 安全增强机制

1. **PR_SET_NO_NEW_PRIVS**：禁止在 execve 后获取新特权，防止 setuid 二进制逃逸
2. **Capabilities 管理**：精细控制 CAP_SYS_ADMIN、CAP_SETUID 等能力的获取和丢弃
3. **双重 pivot_root**：通过两次 pivot_root 操作确保旧根文件系统完全不可访问
4. **特权分离（PrivSep）**：在 setuid 模式下，特权操作通过 socket 通信委托给特权进程执行

---

## 3. 具体技术实现

### 3.1 源码文件结构

```
codex-rs/vendor/bubblewrap/
├── bubblewrap.c      # 主程序入口，约 3641 行，包含命名空间创建、权限管理、主逻辑
├── bind-mount.c      # 绑定挂载实现，约 598 行，处理递归挂载和挂载标志传播
├── bind-mount.h      # 绑定挂载头文件，定义 bind_option_t 和错误码枚举
├── network.c         # 网络配置实现，约 199 行，设置 loopback 接口
├── network.h         # 网络配置头文件
├── utils.c           # 工具函数，约 1000+ 行，包含内存管理、文件操作、字符串处理
├── utils.h           # 工具函数头文件，定义 StringBuilder 和 cleanup 宏
├── config.h          # 构建时生成的配置文件（由 build.rs 生成）
├── demos/            # 示例脚本
│   ├── bubblewrap-shell.sh  # 基础沙箱 shell 示例
│   ├── flatpak-run.sh       # Flatpak 风格运行示例
│   ├── flatpak.bpf          # Seccomp BPF 示例
│   └── userns-block-fd.py   # 用户命名空间阻塞示例
├── tests/            # 测试套件
│   ├── test-run.sh          # 主测试脚本
│   ├── test-seccomp.py      # Seccomp 测试
│   ├── libtest.sh           # 测试库
│   └── try-syscall.c        # 系统调用测试工具
└── meson.build       # Meson 构建配置（上游原生构建系统）
```

### 3.2 关键数据结构

#### 3.2.1 SetupOp（设置操作）

```c
// bubblewrap.c 第 150-162 行
typedef struct _SetupOp SetupOp;
struct _SetupOp
{
  SetupOpType type;      // 操作类型（绑定挂载、创建目录等）
  const char *source;    // 源路径
  const char *dest;      // 目标路径
  int         fd;        // 文件描述符（用于 --bind-fd 等）
  SetupOpFlag flags;     // 操作标志
  int         perms;     // 权限模式
  size_t      size;      // 大小参数（用于 tmpfs）
  SetupOp    *next;      // 链表指针
};
```

SetupOp 类型枚举（第 123-143 行）：
- `SETUP_BIND_MOUNT` / `SETUP_RO_BIND_MOUNT` / `SETUP_DEV_BIND_MOUNT`：绑定挂载变体
- `SETUP_OVERLAY_MOUNT` / `SETUP_TMP_OVERLAY_MOUNT` / `SETUP_RO_OVERLAY_MOUNT`：OverlayFS 挂载
- `SETUP_MOUNT_PROC` / `SETUP_MOUNT_DEV` / `SETUP_MOUNT_TMPFS` / `SETUP_MOUNT_MQUEUE`：特殊文件系统
- `SETUP_MAKE_DIR` / `SETUP_MAKE_FILE` / `SETUP_MAKE_SYMLINK`：文件系统创建操作
- `SETUP_REMOUNT_RO_NO_RECURSIVE`：非递归重新挂载为只读

#### 3.2.2 NsInfo（命名空间信息）

```c
// bubblewrap.c 第 102-121 行
typedef struct _NsInfo NsInfo;
struct _NsInfo {
  const char *name;      // 命名空间名称（cgroup, ipc, mnt, net, pid, uts）
  bool       *do_unshare; // 是否取消共享的标志指针
  ino_t       id;        // 命名空间 inode ID（用于信息报告）
};
```

#### 3.2.3 PrivSepOp（特权分离操作）

```c
// bubblewrap.c 第 185-193 行
typedef struct
{
  uint32_t op;           // 操作码
  uint32_t flags;        // 标志
  uint32_t perms;        // 权限
  size_t   size_arg;     // 大小参数
  uint32_t arg1_offset;  // 参数1在缓冲区中的偏移
  uint32_t arg2_offset;  // 参数2在缓冲区中的偏移
} PrivSepOp;
```

### 3.3 关键执行流程

#### 3.3.1 主执行流程（bubblewrap.c main 函数）

```
main()
├── 参数解析 (parse_args)
│   └── 解析 --bind, --ro-bind, --tmpfs, --unshare-* 等选项
│   └── 构建 SetupOp 链表
├── 权限获取 (acquire_privs)
│   └── 检测 setuid 模式
│   └── 设置 fsuid 为真实用户
│   └── 保留必要 capabilities
├── 命名空间创建 (raw_clone)
│   └── CLONE_NEWNS | CLONE_NEWUSER | CLONE_NEWPID | CLONE_NEWNET | ...
├── 父进程流程
│   ├── 写入 UID/GID 映射 (write_uid_gid_map)
│   ├── 丢弃特权 (drop_privs)
│   └── 监控子进程 (monitor_child)
└── 子进程流程
    ├── 等待父进程信号 (child_wait_fd)
    ├── 切换到用户权限 (switch_to_user_with_privs)
    ├── 设置 loopback 网络 (loopback_setup)
    ├── 设置新根文件系统 (setup_newroot)
    │   ├── 创建 tmpfs 作为新根
    │   ├── pivot_root 切换根
    │   └── 执行 SetupOp 链表中的挂载操作
    ├── 第二次 pivot_root（清理 oldroot）
    ├── 可选的第二层用户命名空间
    ├── 丢弃所有 capabilities
    ├── 创建 PID 1 初始化进程 (do_init)
    │   └── 等待子进程并收割僵尸进程
    └── 执行目标程序 (execvp)
```

#### 3.3.2 特权分离流程（setuid 模式）

```
setup_newroot (unprivileged child)
├── 通过 socket 发送 PrivSepOp 请求
└── 等待特权进程执行操作

privileged_op (privileged parent)
├── 接收 PrivSepOp 请求
├── 验证操作安全性
└── 执行挂载等特权操作
```

### 3.4 Rust 集成实现

#### 3.4.1 构建时编译（build.rs）

```rust
// linux-sandbox/build.rs
fn try_build_vendored_bwrap() -> Result<(), String> {
    // 1. 解析 bubblewrap 源码目录
    let src_dir = resolve_bwrap_source_dir(&manifest_dir)?;
    
    // 2. 探测 libcap 依赖
    let libcap = pkg_config::Config::new().probe("libcap")?;
    
    // 3. 生成 config.h
    std::fs::write(&config_h, r#"#pragma once
#define PACKAGE_STRING "bubblewrap built at codex build-time"
"#)?;
    
    // 4. 编译 C 源码
    let mut build = cc::Build::new();
    build
        .file(src_dir.join("bubblewrap.c"))
        .file(src_dir.join("bind-mount.c"))
        .file(src_dir.join("network.c"))
        .file(src_dir.join("utils.c"))
        .define("main", Some("bwrap_main"))  // 重命名 main 函数
        .compile("build_time_bwrap");
}
```

#### 3.4.2 FFI 调用（vendored_bwrap.rs）

```rust
// linux-sandbox/src/vendored_bwrap.rs
unsafe extern "C" {
    fn bwrap_main(argc: libc::c_int, argv: *const *const c_char) -> libc::c_int;
}

pub(crate) fn exec_vendored_bwrap(argv: Vec<String>, preserved_files: Vec<File>) -> ! {
    let exit_code = run_vendored_bwrap_main(&argv, &preserved_files);
    std::process::exit(exit_code);
}
```

#### 3.4.3 启动器选择（launcher.rs）

```rust
// linux-sandbox/src/launcher.rs
enum BubblewrapLauncher {
    System(AbsolutePathBuf),  // /usr/bin/bwrap
    Vendored,                 // 内嵌版本
}

pub(crate) fn exec_bwrap(argv: Vec<String>, preserved_files: Vec<File>) -> ! {
    match preferred_bwrap_launcher() {
        BubblewrapLauncher::System(program) => exec_system_bwrap(&program, argv, preserved_files),
        BubblewrapLauncher::Vendored => exec_vendored_bwrap(argv, preserved_files),
    }
}
```

### 3.5 命令行参数生成（bwrap.rs）

Codex 根据 `FileSystemSandboxPolicy` 生成 bubblewrap 参数：

```rust
// linux-sandbox/src/bwrap.rs
fn create_bwrap_flags(...) -> Result<BwrapArgs> {
    let mut args = Vec::new();
    
    // 基础安全选项
    args.push("--new-session".to_string());
    args.push("--die-with-parent".to_string());
    
    // 文件系统策略
    if file_system_sandbox_policy.has_full_disk_read_access() {
        args.extend(["--ro-bind", "/", "/"]);
    } else {
        args.extend(["--tmpfs", "/"]);
        // 添加可读的根目录...
    }
    
    // 命名空间隔离
    args.push("--unshare-user".to_string());
    args.push("--unshare-pid".to_string());
    if options.network_mode.should_unshare_network() {
        args.push("--unshare-net".to_string());
    }
    
    // 挂载 /proc
    if options.mount_proc {
        args.extend(["--proc", "/proc"]);
    }
    
    // 可写目录
    for writable_root in writable_roots {
        args.extend(["--bind", path, path]);
    }
    
    // 保护子路径（只读）
    for subpath in read_only_subpaths {
        args.extend(["--ro-bind", path, path]);
    }
    
    Ok(BwrapArgs { args, preserved_files })
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心代码文件

| 文件 | 行数 | 关键功能 |
|------|------|----------|
| `bubblewrap.c` | ~3641 | 主程序逻辑、命名空间管理、权限控制、进程监控 |
| `bind-mount.c` | ~598 | 绑定挂载实现、挂载标志传播、mountinfo 解析 |
| `utils.c` | ~1000+ | 内存管理、文件操作、字符串处理、socket 通信 |
| `network.c` | ~199 | Loopback 接口配置（RTNETLINK） |

### 4.2 关键函数引用

#### 4.2.1 bubblewrap.c

| 函数 | 行号 | 功能 |
|------|------|------|
| `main` | 2871-3641 | 程序入口，协调整个沙箱创建流程 |
| `acquire_privs` | 840-903 | 获取必要的特权（setuid 模式） |
| `setup_newroot` | 1188-1592 | 设置新的根文件系统 |
| `privileged_op` | 1022-1182 | 特权操作执行（挂载等） |
| `write_uid_gid_map` | 955-1020 | 写入 UID/GID 映射 |
| `monitor_child` | 495-588 | 监控子进程状态 |
| `do_init` | 597-669 | PID 1 初始化进程 |
| `raw_clone` | 876-886 | 封装 clone 系统调用 |

#### 4.2.2 bind-mount.c

| 函数 | 行号 | 功能 |
|------|------|------|
| `bind_mount` | 377-489 | 执行绑定挂载并传播挂载标志 |
| `parse_mountinfo` | 229-375 | 解析 /proc/self/mountinfo |
| `die_with_bind_result` | 552-597 | 绑定挂载错误处理 |

#### 4.2.3 network.c

| 函数 | 行号 | 功能 |
|------|------|------|
| `loopback_setup` | 136-199 | 配置 127.0.0.1 和启用 lo 接口 |
| `rtnl_do_request` | 101-112 | 执行 RTNETLINK 请求 |

### 4.3 Rust 集成代码路径

| 文件 | 功能 |
|------|------|
| `codex-rs/linux-sandbox/build.rs` | 编译时构建 vendored bubblewrap |
| `codex-rs/linux-sandbox/src/vendored_bwrap.rs` | FFI 接口和 vendored 启动 |
| `codex-rs/linux-sandbox/src/launcher.rs` | 系统/vendored 启动器选择 |
| `codex-rs/linux-sandbox/src/bwrap.rs` | 参数生成和文件系统策略映射 |
| `codex-rs/linux-sandbox/BUILD.bazel` | Bazel 构建配置 |
| `codex-rs/vendor/BUILD.bazel` | Vendor 目录 Bazel 配置 |

---

## 5. 依赖与外部交互

### 5.1 编译依赖

| 依赖 | 用途 | 检测方式 |
|------|------|----------|
| libcap | Linux capabilities 支持 | pkg-config |
| cc crate | C 代码编译 | Cargo 依赖 |
| pkg-config crate | 系统库检测 | Cargo 依赖 |

### 5.2 运行时依赖

| 依赖 | 说明 |
|------|------|
| Linux 内核 3.8+ | 用户命名空间支持（CLONE_NEWUSER） |
| /proc 文件系统 | mountinfo、namespace 信息读取 |
| /dev/null | 用于屏蔽不可读路径 |

### 5.3 与 Codex 其他组件的交互

```
┌─────────────────────────────────────────────────────────────┐
│                     Codex CLI                               │
├─────────────────────────────────────────────────────────────┤
│  codex-exec / codex-tui / codex-app-server                  │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────┐     ┌─────────────────────────────┐   │
│  │  core crate     │────▶│  FileSystemSandboxPolicy    │   │
│  └─────────────────┘     └─────────────────────────────┘   │
│                                     │                       │
│                                     ▼                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         codex-linux-sandbox crate                    │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ bwrap.rs    │  │ launcher.rs │  │ vendored_   │  │   │
│  │  │ (参数生成)   │─▶│ (启动器选择) │─▶│ bwrap.rs    │  │   │
│  │  └─────────────┘  └─────────────┘  │ (FFI 调用)   │  │   │
│  │                                     └─────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  vendored bubblewrap (codex-rs/vendor/bubblewrap)   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ bubblewrap.c│  │ bind-mount.c│  │ network.c   │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Linux Kernel (namespaces, capabilities, seccomp)   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 配置接口

| 配置项 | 类型 | 说明 |
|--------|------|------|
| `CODEX_BWRAP_SOURCE_DIR` | 环境变量 | 自定义 bubblewrap 源码路径 |
| `features.use_legacy_landlock` | 配置 | 强制使用旧版 Landlock 沙箱 |
| `--no-proc` | CLI 参数 | 跳过 /proc 挂载（容器环境） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| CVE-2017-5226 (TIOCSTI) | 终端注入攻击 | `--new-session` 默认启用 |
| setuid 攻击面 | 历史版本曾出现 setuid 提权漏洞 | 优先使用 user namespaces，setuid 代码路径最小化 |
| mount 传播 | 挂载事件可能泄漏到父命名空间 | 使用 `MS_SLAVE | MS_REC` 隔离 |
| procfs 信息泄漏 | /proc 可能暴露宿主机信息 | 挂载新的 procfs，限制敏感文件访问 |

#### 6.1.2 兼容性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 内核版本不支持 | 旧内核可能缺少 user namespaces | 检测并回退到 setuid 模式或报错 |
| 容器嵌套限制 | Docker 等容器可能禁止嵌套命名空间 | 检测 `/proc/sys/user/max_user_namespaces` |
| SELinux 冲突 | 可能与新根文件系统标签冲突 | 支持 `--exec-label` 和 `--file-label` |

### 6.2 边界条件

#### 6.2.1 路径处理边界

```rust
// bwrap.rs 中的路径深度排序
fn path_depth(path: &Path) -> usize {
    path.components().count()
}
```

- 挂载顺序依赖路径深度，确保父目录先于子目录处理
- 符号链接检测防止路径遍历攻击
- 不存在的路径组件通过 `/dev/null` 绑定阻止创建

#### 6.2.2 命名空间嵌套深度

- 内核限制 `/proc/sys/user/max_user_namespaces`
- 嵌套过深返回 `ENOSPC`
- Codex 最多使用两层用户命名空间（devpts 需求场景）

#### 6.2.3 参数数量限制

```c
// bubblewrap.c 第 1779 行
static const int32_t MAX_ARGS = 9000;
```

- 防止参数注入攻击
- 通过 `--args FD` 支持从文件读取参数绕过限制

### 6.3 改进建议

#### 6.3.1 安全增强

1. **Landlock 叠加**：在 bubblewrap 之外叠加 Landlock LSM，提供额外的文件系统访问控制层
2. **Seccomp 策略细化**：当前使用基础网络过滤，可扩展为完整的系统调用白名单
3. **完整性校验**：对 vendored bubblewrap 源码进行哈希校验，防止篡改

#### 6.3.2 功能增强

1. **idmapped 挂载**：利用内核 5.12+ 的 idmapped mounts 简化 UID/GID 映射
2. **cgroups v2 支持**：添加资源限制（CPU、内存）支持
3. **性能优化**：缓存 mountinfo 解析结果，减少重复读取

#### 6.3.3 可维护性改进

1. **版本追踪**：在 config.h 中嵌入 bubblewrap 上游版本号
2. **自动化同步**：建立脚本定期同步上游 bubblewrap 更新
3. **测试覆盖**：扩展集成测试，覆盖更多边界场景（如嵌套命名空间、各种挂载组合）

#### 6.3.4 监控与可观测性

1. **结构化日志**：当前使用 stderr 输出，可添加 JSON 格式日志选项
2. **指标导出**：暴露沙箱创建耗时、失败率等指标
3. **审计日志**：记录所有特权操作（挂载、权限变更）

### 6.4 上游同步策略

当前 vendored 版本与上游差异：
- 移除了 meson 构建系统依赖
- 添加了 `config.h` 生成逻辑
- 重命名 `main` 为 `bwrap_main` 以支持 FFI

建议建立以下同步流程：
1. 跟踪上游 releases（https://github.com/containers/bubblewrap/releases）
2. 安全补丁优先同步
3. 功能更新评估后同步
4. 维护 `VENDOR_BUBBLEWRAP_VERSION` 文件记录当前版本

---

## 附录：参考链接

- [Bubblewrap 上游仓库](https://github.com/containers/bubblewrap)
- [Bubblewrap 文档](https://github.com/containers/bubblewrap/blob/main/README.md)
- [Linux Namespaces 手册](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [Linux Capabilities 手册](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [Flatpak 沙箱设计](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
