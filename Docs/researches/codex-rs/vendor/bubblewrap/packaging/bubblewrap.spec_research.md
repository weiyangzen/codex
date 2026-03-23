# bubblewrap.spec 深度研究文档

## 1. 场景与职责

### 1.1 文件定位

`bubblewrap.spec` 位于 `codex-rs/vendor/bubblewrap/packaging/` 目录，是一个 **RPM 打包规范文件**，用于构建 bubblewrap 的 RPM 软件包。该文件是 OpenAI Codex 项目中 vendored（内嵌）的 bubblewrap 沙箱工具的一部分。

### 1.2 核心职责

该 spec 文件定义了如何将 bubblewrap 源代码构建、打包成 RPM 格式，主要服务于以下场景：

1. **Linux 发行版集成**：为 RHEL/CentOS/Fedora 等 RPM 系发行版提供标准化的软件包构建流程
2. **Codex 项目的沙箱依赖**：作为 `codex-rs/linux-sandbox` crate 的底层沙箱实现基础
3. **非特权容器执行**：在无法使用 Docker/rootless 容器的环境中提供轻量级沙箱能力

### 1.3 与 Codex 项目的关系

```
codex-rs/
├── linux-sandbox/          # Rust 封装层
│   ├── src/bwrap.rs        # bubblewrap 参数构建逻辑
│   ├── src/vendored_bwrap.rs # FFI 调用层
│   └── build.rs            # 编译时嵌入 bwrap C 代码
├── vendor/
│   └── bubblewrap/         # 内嵌的 bubblewrap 源码
│       ├── bubblewrap.c    # 主程序 (~3600 行)
│       ├── bind-mount.c    # 绑定挂载实现
│       ├── network.c       # 网络命名空间配置
│       ├── utils.c         # 工具函数
│       └── packaging/
│           └── bubblewrap.spec  # <-- 本研究对象
```

bubblewrap 在 Codex 中的角色是 **Linux 沙箱执行引擎**，负责：
- 创建隔离的文件系统视图（只读根目录 + 可写白名单）
- 设置命名空间隔离（PID、Network、User、IPC、UTS）
- 在 exec 前构建沙箱环境，然后执行用户命令

---

## 2. 功能点目的

### 2.1 RPM 包元数据定义

| 字段 | 值 | 说明 |
|------|-----|------|
| `Name` | `bubblewrap` | 软件包名称 |
| `Version` | `0` | 版本号（开发版本） |
| `Release` | `1%{?dist}` | 发布号，含发行版标签 |
| `License` | `LGPLv2+` | GNU 宽通用公共许可证 v2 或更高 |
| `URL` | `https://github.com/projectatomic/bubblewrap` | 上游项目地址 |
| `Source0` | GitHub archive | 从特定 commit 获取源码 |

**关键设计**：
- 使用固定的 commit hash (`66d12bb23b04e201c5846e325f0b10930ed802f8`) 而非动态 tag，确保构建可复现
- `shortcommit0` 宏提取前 7 位作为版本标识

### 2.2 构建依赖 (BuildRequires)

```spec
BuildRequires: git
BuildRequires: autoconf automake libtool
BuildRequires: libcap-devel
BuildRequires: pkgconfig(libselinux)
BuildRequires: libxslt
BuildRequires: docbook-style-xsl
```

| 依赖 | 用途 |
|------|------|
| `git` | `%autosetup -Sgit` 需要 git 进行源码解压 |
| `autoconf/automake/libtool` | 运行 `autogen.sh` 生成 configure 脚本 |
| `libcap-devel` | Linux capabilities 支持（CAP_SYS_ADMIN 等）|
| `libselinux` | SELinux 标签支持（可选）|
| `libxslt` + `docbook-style-xsl` | 生成 man 手册页 |

### 2.3 构建配置

```spec
%build
env NOCONFIGURE=1 ./autogen.sh
%configure --disable-silent-rules --with-priv-mode=none
make %{?_smp_mflags}
```

**关键选项**：`--with-priv-mode=none`
- 禁用 setuid 安装模式
- 现代 Linux 使用 user namespaces 而非 setuid 来实现非特权沙箱
- 符合 Codex 项目的安全模型（依赖 user ns，不依赖 setuid 二进制文件）

### 2.4 安装与文件列表

```spec
%files
%license COPYING
%doc README.md
%{_datadir}/bash-completion/completions/bwrap
%if (0%{?rhel} != 0 && 0%{?rhel} <= 7)
%attr(4755,root,root) %{_bindir}/bwrap
%else
%{_bindir}/bwrap
%endif
%{_mandir}/man1/*
```

**条件逻辑**：
- RHEL 7 及更早版本：设置 setuid 位 (`4755`)，因为内核不支持非特权 user namespaces
- RHEL 8+/现代发行版：普通权限 (`755`)，依赖内核 user namespace 支持

---

## 3. 具体技术实现

### 3.1 bubblewrap 核心架构

#### 3.1.1 进程模型

```
Parent Process (bwrap 主进程)
    │
    ├── clone() ──► Child Process (PID 1 in new namespace)
    │                   │
    │                   ├── setup_newroot() ──► 构建文件系统视图
    │                   │   ├── pivot_root() 到 tmpfs
    │                   │   ├── 执行 bind mount 操作
    │                   │   └── 应用 seccomp 过滤器
    │                   │
    │                   └── fork() ──► Grandchild (实际用户命令)
    │                           │
    │                           └── execvp() 用户指定的 COMMAND
    │
    └── monitor_child() ──► 等待子进程退出，传播 exit status
```

#### 3.1.2 关键数据结构

**SetupOp** (`bubblewrap.c:152-162`)：
```c
typedef struct _SetupOp
{
  SetupOpType type;      // 操作类型（bind mount、tmpfs、symlink 等）
  const char *source;    // 源路径
  const char *dest;      // 目标路径
  int         fd;        // 文件描述符（用于 --file、--bind-fd 等）
  SetupOpFlag flags;     // 标志位（ALLOW_NOTEXIST 等）
  int         perms;     // 权限模式
  size_t      size;      // tmpfs 大小
  SetupOp    *next;      // 链表指针
} SetupOp;
```

**SetupOpType 枚举** (`bubblewrap.c:123-143`)：
```c
typedef enum {
  SETUP_BIND_MOUNT,           // --bind
  SETUP_RO_BIND_MOUNT,        // --ro-bind
  SETUP_DEV_BIND_MOUNT,       // --dev-bind
  SETUP_OVERLAY_MOUNT,        // --overlay
  SETUP_TMP_OVERLAY_MOUNT,    // --tmp-overlay
  SETUP_RO_OVERLAY_MOUNT,     // --ro-overlay
  SETUP_MOUNT_PROC,           // --proc
  SETUP_MOUNT_DEV,            // --dev
  SETUP_MOUNT_TMPFS,          // --tmpfs
  SETUP_MAKE_DIR,             // --dir
  SETUP_MAKE_FILE,            // --file
  SETUP_MAKE_SYMLINK,         // --symlink
  // ... 更多类型
} SetupOpType;
```

**NsInfo** (`bubblewrap.c:104-121`)：
```c
typedef struct _NsInfo NsInfo;
struct _NsInfo {
  const char *name;    // 命名空间名称（"pid", "net", "ipc" 等）
  bool       *do_unshare;  // 是否取消共享的标志指针
  ino_t       id;      // 命名空间 inode ID（用于信息输出）
};

static NsInfo ns_infos[] = {
  {"cgroup", &opt_unshare_cgroup, 0},
  {"ipc",    &opt_unshare_ipc,    0},
  {"mnt",    NULL,                0},  // mount ns 总是创建
  {"net",    &opt_unshare_net,    0},
  {"pid",    &opt_unshare_pid,    0},
  {"uts",    &opt_unshare_uts,    0},
  {NULL,     NULL,                0}
};
```

### 3.2 命名空间创建流程

```c
// bubblewrap.c:3072-3099
clone_flags = SIGCHLD | CLONE_NEWNS;  // 总是创建新的 mount namespace
if (opt_unshare_user)
  clone_flags |= CLONE_NEWUSER;
if (opt_unshare_pid && opt_pidns_fd == -1)
  clone_flags |= CLONE_NEWPID;
if (opt_unshare_net)
  clone_flags |= CLONE_NEWNET;
if (opt_unshare_ipc)
  clone_flags |= CLONE_NEWIPC;
if (opt_unshare_uts)
  clone_flags |= CLONE_NEWUTS;
if (opt_unshare_cgroup)
  clone_flags |= CLONE_NEWCGROUP;

pid = raw_clone(clone_flags, NULL);
```

### 3.3 文件系统构建流程

#### 3.3.1 pivot_root 舞蹈

```c
// 1. 在 /tmp 创建 tmpfs 作为新的根
mount("tmpfs", base_path, "tmpfs", MS_NODEV | MS_NOSUID, NULL);

// 2. 创建 newroot 和 oldroot 目录
mkdir("newroot", 0755);
mkdir("oldroot", 0755);

// 3. 第一次 pivot_root
pivot_root(base_path, "oldroot");

// 4. 在 newroot 内构建文件系统
setup_newroot();  // 执行所有 SETUP_* 操作

// 5. 第二次 pivot_root（进入 newroot，卸载 oldroot）
pivot_root(".", ".");
umount2(".", MNT_DETACH);
```

#### 3.3.2 特权分离模式

当 bwrap 以 setuid 运行时，使用特权分离：

```c
// bubblewrap.c:3358-3402
if (is_privileged) {
  // 创建 socket pair 用于特权/非特权进程通信
  socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, privsep_sockets);
  
  child = fork();
  if (child == 0) {
    // 非特权子进程：执行 setup_newroot()，但需要特权操作时通过 socket 请求
    drop_privs(false, true);
    setup_newroot(opt_unshare_pid, privsep_sockets[1]);
    exit(0);
  } else {
    // 特权父进程：执行实际的特权 mount 操作
    do {
      op = read_priv_sec_op(unpriv_socket, buffer, sizeof(buffer), ...);
      privileged_op(-1, op, flags, perms, size_arg, arg1, arg2);
    } while (op != PRIV_SEP_OP_DONE);
  }
}
```

**PrivSepOp 操作码** (`bubblewrap.c:173-183`)：
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

### 3.4 网络命名空间配置

`network.c` 实现独立的网络命名空间初始化：

```c
void loopback_setup(void) {
  // 1. 创建 NETLINK_ROUTE socket
  rtnl_fd = socket(PF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
  
  // 2. 配置 lo 接口的 IP 地址（127.0.0.1/8）
  header = rtnl_setup_request(buffer, RTM_NEWADDR, ...);
  addmsg = NLMSG_DATA(header);
  addmsg->ifa_family = AF_INET;
  addmsg->ifa_prefixlen = 8;
  ip_addr->s_addr = htonl(INADDR_LOOPBACK);
  rtnl_do_request(rtnl_fd, header);
  
  // 3. 启用 lo 接口（IFF_UP）
  header = rtnl_setup_request(buffer, RTM_NEWLINK, ...);
  infomsg = NLMSG_DATA(header);
  infomsg->ifi_flags = IFF_UP;
  infomsg->ifi_change = IFF_UP;
  rtnl_do_request(rtnl_fd, header);
}
```

### 3.5 绑定挂载实现

`bind-mount.c` 处理复杂的绑定挂载逻辑：

```c
bind_mount_result bind_mount(int proc_fd,
                             const char *src,
                             const char *dest,
                             bind_option_t options,
                             char **failing_path) {
  // 1. 执行初始 bind mount
  mount(src, dest, NULL, MS_SILENT | MS_BIND | (recursive ? MS_REC : 0), NULL);
  
  // 2. 解析目标路径的 realpath
  resolved_dest = realpath(dest, NULL);
  
  // 3. 通过 /proc/self/fd 获取内核使用的路径大小写
  dest_proc = xasprintf("/proc/self/fd/%d", dest_fd);
  kernel_case_combination = readlink_malloc(oldroot_dest_proc);
  
  // 4. 解析 mountinfo 获取当前挂载选项
  mount_tab = parse_mountinfo(proc_fd, kernel_case_combination);
  
  // 5. 应用新的挂载标志（readonly、nodev、nosuid）
  new_flags = current_flags | (devices ? 0 : MS_NODEV) | MS_NOSUID | (readonly ? MS_RDONLY : 0);
  mount("none", resolved_dest, NULL, MS_SILENT | MS_BIND | MS_REMOUNT | new_flags, NULL);
  
  // 6. 递归处理子挂载（如果是递归 bind）
  for (i = 1; mount_tab[i].mountpoint != NULL; i++) {
    // 对每个子挂载应用相同的标志
  }
}
```

### 3.6 Codex 项目中的 Rust 封装

`codex-rs/linux-sandbox/src/bwrap.rs` 构建 bubblewrap 命令行参数：

```rust
fn create_bwrap_flags(...) -> Result<BwrapArgs> {
    let mut args = Vec::new();
    
    // 安全基础选项
    args.push("--new-session".to_string());      // 创建新终端会话
    args.push("--die-with-parent".to_string());  // 父进程死亡时杀死子进程
    
    // 命名空间隔离
    args.push("--unshare-user".to_string());     // 用户命名空间
    args.push("--unshare-pid".to_string());      // PID 命名空间
    if options.network_mode.should_unshare_network() {
        args.push("--unshare-net".to_string());  // 网络命名空间
    }
    
    // 文件系统配置
    if file_system_sandbox_policy.has_full_disk_read_access() {
        args.extend(["--ro-bind", "/", "/"]);
    } else {
        args.extend(["--tmpfs", "/"]);
        // 添加特定的只读绑定
        for root in readable_roots {
            args.extend(["--ro-bind", &root, &root]);
        }
    }
    
    // 可写根目录
    for writable_root in writable_roots {
        args.extend(["--bind", &writable_root, &writable_root]);
    }
    
    args.push("--".to_string());
    args.extend(command);
    
    Ok(BwrapArgs { args, preserved_files })
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 bubblewrap 源码结构

| 文件 | 行数 | 职责 |
|------|------|------|
| `bubblewrap.c` | ~3600 | 主程序：参数解析、命名空间创建、进程管理、特权分离 |
| `bind-mount.c` | ~600 | 绑定挂载实现，mountinfo 解析，挂载标志处理 |
| `network.c` | ~200 | 网络命名空间配置，loopback 接口设置 |
| `utils.c` | ~1000 | 工具函数：内存管理、文件操作、字符串处理、SELinux 支持 |
| `utils.h` | ~220 | 头文件，数据结构定义，内联函数 |
| `bind-mount.h` | ~54 | 绑定挂载接口定义 |
| `network.h` | ~22 | 网络配置接口定义 |

### 4.2 关键函数路径

**初始化流程**：
```
main() [bubblewrap.c:2871]
  ├── acquire_privs() [bubblewrap.c:841]     # 获取/检查特权
  ├── parse_args() [bubblewrap.c:2776]       # 解析命令行参数
  ├── read_overflowids() [bubblewrap.c:2789] # 读取 overflow UID/GID
  ├── raw_clone() [bubblewrap.c:3130]        # 创建命名空间
  └── (child process)
      ├── setup_newroot() [bubblewrap.c:1188]  # 构建文件系统
      │   └── privileged_op() [bubblewrap.c:1022]  # 特权操作
      └── execvp() [bubblewrap.c:3626]         # 执行用户命令
```

**文件系统构建**：
```
setup_newroot() [bubblewrap.c:1188]
  ├── resolve_symlinks_in_ops() [bubblewrap.c:1614]  # 解析符号链接
  ├── mount(MS_SLAVE|MS_REC)  # 设置挂载传播
  ├── mount(tmpfs)            # 创建新根
  ├── pivot_root()            # 切换根目录
  └── for each SetupOp:
      ├── SETUP_BIND_MOUNT → privileged_op(PRIV_SEP_OP_BIND_MOUNT)
      ├── SETUP_MOUNT_PROC → privileged_op(PRIV_SEP_OP_PROC_MOUNT)
      ├── SETUP_MOUNT_DEV  → privileged_op(PRIV_SEP_OP_TMPFS_MOUNT) + 创建设备节点
      └── ...
```

### 4.3 Codex 调用链

```
codex-cli 或 codex-tui
  └── linux-sandbox::exec_vendored_bwrap()
      └── vendored_bwrap::exec_vendored_bwrap()
          └── bwrap_main(argc, argv) [FFI 调用 C 代码]
              └── bubblewrap.c:main()
```

**构建时嵌入** (`linux-sandbox/build.rs`)：
```rust
// 将 bubblewrap C 源码编译为静态库
cc::Build::new()
    .file(src_dir.join("bubblewrap.c"))
    .file(src_dir.join("bind-mount.c"))
    .file(src_dir.join("network.c"))
    .file(src_dir.join("utils.c"))
    .define("main", Some("bwrap_main"))  // 重命名 main 以便 FFI 调用
    .compile("build_time_bwrap");
```

---

## 5. 依赖与外部交互

### 5.1 编译时依赖

| 依赖 | 用途 | 在 Codex 中的处理 |
|------|------|------------------|
| `libcap` | Linux capabilities | `pkg_config` 探测，`-idirafter` 添加头文件路径 |
| `libselinux` | SELinux 标签支持（可选）| 通过 `pkgconfig(libselinux)` 检测 |
| `meson` | 原生构建系统（上游使用）| Codex 使用 `cc` crate 直接编译，绕过 meson |
| `autotools` | spec 文件中的构建方式 | Codex 不使用 |

### 5.2 运行时依赖

| 依赖 | 说明 |
|------|------|
| Linux 3.8+ | 用户命名空间支持（非 setuid 模式）|
| `/proc` | 挂载信息读取、PID 信息 |
| `/dev/null` | 用于屏蔽不可读文件的 bind mount 目标 |

### 5.3 内核接口

**系统调用**：
- `clone()` / `unshare()` - 创建/切换命名空间
- `pivot_root()` - 切换根文件系统
- `mount()` / `umount2()` - 挂载操作
- `setns()` - 加入现有命名空间
- `prctl(PR_SET_NO_NEW_PRIVS)` - 禁止提升特权
- `prctl(PR_SET_PDEATHSIG)` - 父进程死亡信号
- `seccomp()` - 系统调用过滤

**procfs 接口**：
- `/proc/self/mountinfo` - 挂载信息解析
- `/proc/self/ns/*` - 命名空间信息
- `/proc/sys/kernel/overflowuid` - 溢出 UID
- `/proc/sys/user/max_user_namespaces` - 用户命名空间限制

### 5.4 与 Codex 其他组件的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex Application                         │
│  (cli / tui / tui_app_server)                               │
└───────────────────────┬─────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────────┐
│              linux-sandbox (Rust crate)                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ bwrap.rs    │  │ landlock.rs │  │ vendored_bwrap.rs   │  │
│  │ (参数构建)   │  │ (额外限制)   │  │ (FFI 调用)          │  │
│  └──────┬──────┘  └─────────────┘  └──────────┬──────────┘  │
└─────────┼─────────────────────────────────────┼─────────────┘
          │                                     │
          │    ┌──────────────────────────────┐ │
          └───►│   bubblewrap (C binary)      │◄┘
               │   - 命名空间隔离              │
               │   - 文件系统沙箱              │
               │   - seccomp 过滤器            │
               └──────────────┬───────────────┘
                              │
               ┌──────────────▼───────────────┐
               │    Sandboxed Process         │
               │    (用户命令执行)             │
               └──────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 6.1.1 setuid 模式风险

**问题**：spec 文件中 RHEL 7 的条件分支设置 setuid 位：
```spec
%if (0%{?rhel} != 0 && 0%{?rhel} <= 7)
%attr(4755,root,root) %{_bindir}/bwrap
```

**风险**：
- setuid root 二进制文件是潜在的安全隐患
- 历史上 bubblewrap 曾修复多个 setuid 相关漏洞（CVE-2016-3135 等）
- 需要严格审计代码路径

**缓解**：
- Codex 项目使用 `--with-priv-mode=none` 构建，禁用 setuid 支持
- 依赖现代内核的 user namespace 功能

#### 6.1.2 User Namespace 限制

**问题**：某些发行版（如 Debian）默认禁用非特权 user namespace：
```bash
# Debian 需要手动启用
sysctl kernel.unprivileged_userns_clone=1
```

**影响**：bwrap 会报错并退出，Codex 沙箱无法启动。

### 6.2 边界情况

#### 6.2.1 嵌套沙箱

bubblewrap 支持嵌套运行，但有以下限制：
- 嵌套层数受 `/proc/sys/user/max_*_namespaces` 限制
- 文件系统视图需要小心设计以避免冲突

**Codex 处理** (`bwrap.rs:142-148`)：
```rust
// 递归调用时使用 /proc/self/exe 而不是外部 bwrap 路径
$BWRAP_RECURSE -- /proc/self/exe --unshare-all ...
```

#### 6.2.2 符号链接处理

**风险**：TOCTOU（Time-of-check to time-of-use）攻击

**缓解措施** (`bwrap.rs:533-565`)：
```rust
fn find_symlink_in_path(...) -> Option<PathBuf> {
    // 检测路径中的符号链接，防止在可写目录中的保护路径被替换
}
```

#### 6.2.3 大参数列表

bubblewrap 有硬编码的参数数量限制 (`MAX_ARGS = 9000`)，防止恶意输入导致内存耗尽。

### 6.3 改进建议

#### 6.3.1 针对 spec 文件的改进

1. **版本管理**：
   - 当前使用固定 commit hash，建议跟踪上游版本标签
   - 添加 `%changelog` 段记录打包历史

2. **条件编译优化**：
   ```spec
   # 建议添加对 user namespace 支持的检测
   %if 0%{?fedora} >= 23 || 0%{?rhel} >= 8
   # 现代发行版，不需要 setuid
   %else
   # 旧版本，需要 setuid 或禁用功能
   %endif
   ```

3. **测试集成**：
   ```spec
   %check
   make check
   ```

#### 6.3.2 针对 Codex 集成的改进

1. **错误处理增强**：
   - 当前 bwrap 启动失败时错误信息可能不够清晰
   - 建议捕获并解析 bwrap 的错误输出，提供用户友好的提示

2. **性能优化**：
   - 对于大量文件系统规则，考虑批量处理或缓存 mount 操作
   - 评估使用 overlayfs 替代多层 bind mount 的性能

3. **安全加固**：
   ```rust
   // 考虑添加更多 seccomp 过滤器
   --seccomp 参数加载预编译的 BPF 程序
   ```

4. **可观测性**：
   - 利用 `--info-fd` 和 `--json-status-fd` 获取沙箱运行时信息
   - 集成到 Codex 的日志系统中

#### 6.3.3 上游 bubblewrap 建议

1. **Landlock 集成**：
   - 当前 bubblewrap 使用传统的 mount-based 沙箱
   - 考虑集成 Linux Landlock LSM 提供更细粒度的文件系统访问控制

2. **cgroups v2 支持**：
   - 增强资源限制能力（CPU、内存、IO）

3. **seccomp 用户通知**：
   - 使用 `SECCOMP_FILTER_FLAG_NEW_LISTENER` 实现更灵活的系统调用拦截

### 6.4 已知问题与限制

| 问题 | 影响 | 状态 |
|------|------|------|
| Overlayfs 需要 kernel 4.0+ | 旧内核无法使用 `--overlay` | 文档已说明 |
| `--size` 在 setuid 模式下禁用 | 无法限制 tmpfs 大小 | 安全设计 |
| Case-insensitive 文件系统 | mountinfo 路径大小写问题 | 已处理 (`bind-mount.c:417-436`) |
| FUSE 文件系统 | bind mount 可能失败 | 测试覆盖 (`test-run.sh:30-35`) |

---

## 7. 总结

`bubblewrap.spec` 是 Codex 项目中 vendored bubblewrap 的 RPM 打包规范，定义了如何在 RPM 系发行版中构建和分发 bubblewrap。该 spec 文件体现了以下关键设计决策：

1. **安全优先**：默认使用 `--with-priv-mode=none`，依赖 user namespace 而非 setuid
2. **向后兼容**：对 RHEL 7 等旧系统保留 setuid 支持
3. **可复现构建**：使用固定 commit hash 而非动态标签

bubblewrap 本身是一个轻量级、专注的沙箱工具，通过 Linux 命名空间和精心设计的特权分离机制，为 Codex 提供了可靠的 Linux 沙箱执行环境。其 C 代码经过广泛审计，被 Flatpak 等成熟项目采用，安全性有充分保障。

在 Codex 项目中，bubblewrap 通过 `linux-sandbox` crate 的 Rust 封装与上层应用集成，实现了与 macOS Seatbelt 沙箱类似的语义：默认只读、显式可写白名单、敏感路径保护。
