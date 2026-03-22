# Bubblewrap 深度研究文档

## 1. 场景与职责

### 1.1 项目定位

Bubblewrap 是一个轻量级的 Linux 沙箱工具，用于在非特权用户环境下创建安全的容器化执行环境。它是 Codex 项目在 Linux 平台上的核心沙箱组件，负责构建文件系统视图和进程隔离。

### 1.2 核心职责

1. **文件系统沙箱**: 通过 Linux 命名空间（namespace）和挂载（mount）操作，创建只读或受限的文件系统视图
2. **进程隔离**: 通过 PID、IPC、网络等命名空间实现进程级隔离
3. **权限控制**: 通过用户命名空间（user namespace）实现 UID/GID 映射，降低权限风险
4. **安全加固**: 集成 seccomp 过滤器、PR_SET_NO_NEW_PRIVS 等安全机制

### 1.3 在 Codex 项目中的角色

在 Codex 项目中，bubblewrap 被 `codex-linux-sandbox` crate 调用：

- **首选方案**: 优先使用系统 `/usr/bin/bwrap`，如不存在则回退到内置（vendored）版本
- **文件系统策略**: 根据 `FileSystemSandboxPolicy` 生成对应的 bwrap 命令行参数
- **网络隔离**: 支持 `--unshare-net` 实现网络命名空间隔离
- **默认配置**: `--ro-bind / /` 使文件系统默认只读，再通过 `--bind` 开放特定可写目录

## 2. 功能点目的

### 2.1 命名空间隔离

| 命名空间 | 选项 | 目的 |
|---------|------|------|
| Mount (CLONE_NEWNS) | 强制启用 | 创建独立的挂载点视图，实现文件系统隔离 |
| User (CLONE_NEWUSER) | `--unshare-user` | UID/GID 映射，让普通用户在沙箱内以 root 身份运行 |
| PID (CLONE_NEWPID) | `--unshare-pid` | 独立的进程 ID 空间，PID 1 由 bwrap 或用户程序担任 |
| Network (CLONE_NEWNET) | `--unshare-net` | 独立的网络栈，仅包含 loopback 接口 |
| IPC (CLONE_NEWIPC) | `--unshare-ipc` | 独立的 System V IPC 和 POSIX 消息队列 |
| UTS (CLONE_NEWUTS) | `--unshare-uts` | 独立的主机名和域名 |
| Cgroup (CLONE_NEWCGROUP) | `--unshare-cgroup` | 独立的 cgroup 视图 |

### 2.2 文件系统操作

| 操作类型 | 命令行选项 | 用途 |
|---------|-----------|------|
| 只读绑定挂载 | `--ro-bind src dest` | 将主机目录以只读方式映射到沙箱 |
| 可写绑定挂载 | `--bind src dest` | 将主机目录以可写方式映射到沙箱 |
| 设备绑定 | `--dev-bind src dest` | 允许访问设备文件的绑定挂载 |
| 临时文件系统 | `--tmpfs dest` | 创建空的 tmpfs 挂载点 |
| 创建目录 | `--dir dest` | 在沙箱内创建目录 |
| 创建符号链接 | `--symlink src dest` | 创建符号链接 |
| 重新挂载只读 | `--remount-ro dest` | 将已挂载目录重新设为只读 |
| Proc 文件系统 | `--proc dest` | 挂载新的 procfs |
| Dev 文件系统 | `--dev dest` | 挂载最小化的 devfs |

### 2.3 安全特性

1. **PR_SET_NO_NEW_PRIVS**: 禁止在 execve 后获取新特权，防止 setuid 二进制文件提升权限
2. **Seccomp 过滤器**: 通过 `--seccomp FD` 加载 BPF 程序限制系统调用
3. **能力（Capabilities）管理**: 精细控制进程能力集，默认丢弃非必要能力
4. **特权分离**: setuid 模式下，特权操作在独立进程中执行，非特权进程通过 socket 请求特权操作

## 3. 具体技术实现

### 3.1 关键数据结构

#### SetupOp（设置操作链表）

```c
// bubblewrap.c:150-162
typedef struct _SetupOp SetupOp;
struct _SetupOp
{
  SetupOpType type;      // 操作类型（绑定挂载、创建目录等）
  const char *source;    // 源路径
  const char *dest;      // 目标路径
  int         fd;        // 文件描述符（用于 --file 等）
  SetupOpFlag flags;     // 操作标志
  int         perms;     // 权限模式
  size_t      size;      // 大小（用于 tmpfs）
  SetupOp    *next;      // 链表下一个节点
};
```

#### PrivSepOp（特权分离操作）

```c
// bubblewrap.c:185-193
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

#### NsInfo（命名空间信息）

```c
// bubblewrap.c:102-108
typedef struct _NsInfo NsInfo;
struct _NsInfo {
  const char *name;      // 命名空间名称（"pid", "net" 等）
  bool       *do_unshare; // 是否取消共享的标志指针
  ino_t       id;        // 命名空间 inode ID（用于信息输出）
};
```

### 3.2 核心流程

#### 主流程（main 函数）

```
main()
├── 获取真实 UID/GID
├── acquire_privs()          # 获取必要的特权（setuid 模式）
├── prctl(PR_SET_NO_NEW_PRIVS, 1)  # 禁止新特权
├── read_overflowids()       # 读取溢出 UID/GID
├── parse_args()             # 解析命令行参数
├── 验证参数兼容性
├── 创建 eventfd 和 pipe
├── raw_clone()              # 创建新命名空间
│   └── 子进程进入沙箱
└── 父进程：
    ├── namespace_ids_read() # 读取子进程命名空间 ID
    ├── write_uid_gid_map()  # 设置 UID/GID 映射（setuid 模式）
    ├── drop_privs()         # 丢弃特权
    └── monitor_child()      # 监控子进程
```

#### 子进程设置流程

```
子进程（沙箱内）
├── 等待父进程设置 UID 映射
├── switch_to_user_with_privs()  # 切换用户但保留能力
├── loopback_setup()         # 设置 loopback 网络（如需要）
├── 挂载操作准备：
│   ├── mount(MS_SLAVE | MS_REC)  # 使挂载传播变为从属
│   └── mount(tmpfs on /tmp)      # 创建临时根
├── pivot_root()             # 切换根文件系统
│   └── 将旧根移动到 /oldroot
├── setup_newroot()          # 执行所有设置操作
│   ├── 遍历 SetupOp 链表
│   ├── 创建目录/文件/符号链接
│   ├── 执行绑定挂载
│   └── 请求特权操作（通过 socket）
├── 第二次 pivot_root()      # 将 /newroot 设为真正的根
├── umount(oldroot)          # 卸载旧根
├── 可选：创建第二层用户命名空间
├── drop_privs()             # 最终丢弃所有特权
├── seccomp_programs_apply() # 应用 seccomp 过滤器
└── execvp()                 # 执行目标程序
```

#### 特权分离流程（setuid 模式）

```
当 is_privileged 为 true 时：
├── socketpair()             # 创建特权分离通信通道
├── fork()
│   ├── 子进程（非特权）：
│   │   ├── drop_privs()     # 完全丢弃特权
│   │   ├── setup_newroot()  # 执行设置操作
│   │   │   └── 对于需要特权的操作，通过 socket 发送 PrivSepOp
│   │   └── exit(0)
│   └── 父进程（保留特权）：
│       ├── read_priv_sec_op()  # 读取子进程请求
│       ├── privileged_op(-1, ...)  # 执行特权操作
│       └── write() 回复子进程
└── 等待子进程完成
```

### 3.3 绑定挂载实现（bind-mount.c）

绑定挂载是 bubblewrap 的核心功能，其实现涉及复杂的挂载标志处理：

```c
// bind-mount.c:377-489
bind_mount_result
bind_mount (int           proc_fd,
            const char   *src,
            const char   *dest,
            bind_option_t options,
            char        **failing_path)
{
  // 1. 执行初始绑定挂载
  mount(src, dest, NULL, MS_SILENT | MS_BIND | (recursive ? MS_REC : 0), NULL)
  
  // 2. 解析目标路径的真实路径
  resolved_dest = realpath(dest, NULL)
  
  // 3. 通过 /proc/self/fd 获取内核使用的路径大小写
  dest_proc = xasprintf("/proc/self/fd/%d", dest_fd)
  kernel_case_combination = readlink_malloc(oldroot_dest_proc)
  
  // 4. 解析 /proc/self/mountinfo 获取挂载信息
  mount_tab = parse_mountinfo(proc_fd, kernel_case_combination)
  
  // 5. 重新挂载以应用标志（nodev, nosuid, ro）
  new_flags = current_flags | (devices ? 0 : MS_NODEV) | MS_NOSUID | (readonly ? MS_RDONLY : 0)
  mount("none", resolved_dest, NULL, MS_SILENT | MS_BIND | MS_REMOUNT | new_flags, NULL)
  
  // 6. 递归处理子挂载
  for (i = 1; mount_tab[i].mountpoint != NULL; i++)
    remount_submount_with_flags(...)
}
```

### 3.4 网络设置（network.c）

当使用 `--unshare-net` 时，bubblewrap 需要配置 loopback 接口：

```c
// network.c:136-199
void loopback_setup (void)
{
  // 创建 NETLINK_ROUTE socket
  rtnl_fd = socket(PF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE)
  bind(rtnl_fd, &src_addr, sizeof(src_addr))
  
  // 添加 loopback 地址 127.0.0.1
  header = rtnl_setup_request(buffer, RTM_NEWADDR, ...)
  addmsg = NLMSG_DATA(header)
  addmsg->ifa_family = AF_INET
  addmsg->ifa_prefixlen = 8
  ip_addr->s_addr = htonl(INADDR_LOOPBACK)
  rtnl_do_request(rtnl_fd, header)
  
  // 启用 loopback 接口
  header = rtnl_setup_request(buffer, RTM_NEWLINK, ...)
  infomsg = NLMSG_DATA(header)
  infomsg->ifi_flags = IFF_UP
  infomsg->ifi_change = IFF_UP
  rtnl_do_request(rtnl_fd, header)
}
```

### 3.5 协议与命令

#### 特权分离操作码

```c
// bubblewrap.c:173-183
enum {
  PRIV_SEP_OP_DONE,                    // 操作完成
  PRIV_SEP_OP_BIND_MOUNT,              // 绑定挂载
  PRIV_SEP_OP_OVERLAY_MOUNT,           // Overlay 挂载
  PRIV_SEP_OP_PROC_MOUNT,              // 挂载 procfs
  PRIV_SEP_OP_TMPFS_MOUNT,             // 挂载 tmpfs
  PRIV_SEP_OP_DEVPTS_MOUNT,            // 挂载 devpts
  PRIV_SEP_OP_MQUEUE_MOUNT,            // 挂载 mqueue
  PRIV_SEP_OP_REMOUNT_RO_NO_RECURSIVE, // 非递归重新挂载只读
  PRIV_SEP_OP_SET_HOSTNAME,            // 设置主机名
};
```

#### SetupOp 类型

```c
// bubblewrap.c:123-143
typedef enum {
  SETUP_BIND_MOUNT,              // --bind
  SETUP_RO_BIND_MOUNT,           // --ro-bind
  SETUP_DEV_BIND_MOUNT,          // --dev-bind
  SETUP_OVERLAY_MOUNT,           // --overlay
  SETUP_TMP_OVERLAY_MOUNT,       // --tmp-overlay
  SETUP_RO_OVERLAY_MOUNT,        // --ro-overlay
  SETUP_OVERLAY_SRC,             // --overlay-src
  SETUP_MOUNT_PROC,              // --proc
  SETUP_MOUNT_DEV,               // --dev
  SETUP_MOUNT_TMPFS,             // --tmpfs
  SETUP_MOUNT_MQUEUE,            // --mqueue
  SETUP_MAKE_DIR,                // --dir
  SETUP_MAKE_FILE,               // --file
  SETUP_MAKE_BIND_FILE,          // --bind-data
  SETUP_MAKE_RO_BIND_FILE,       // --ro-bind-data
  SETUP_MAKE_SYMLINK,            // --symlink
  SETUP_REMOUNT_RO_NO_RECURSIVE, // --remount-ro
  SETUP_SET_HOSTNAME,            // --hostname
  SETUP_CHMOD,                   // --chmod
} SetupOpType;
```

## 4. 关键代码路径与文件引用

### 4.1 核心源文件

| 文件 | 行数 | 职责 |
|-----|------|------|
| `bubblewrap.c` | ~3640 | 主程序逻辑、参数解析、命名空间管理、特权分离 |
| `bind-mount.c` | ~598 | 绑定挂载实现、mountinfo 解析、挂载标志处理 |
| `bind-mount.h` | ~54 | 绑定挂载接口定义 |
| `network.c` | ~199 | Loopback 网络接口配置 |
| `network.h` | ~22 | 网络配置接口定义 |
| `utils.c` | ~1000+ | 工具函数（字符串、文件操作、内存管理） |
| `utils.h` | ~217 | 工具函数接口定义 |

### 4.2 关键函数路径

#### 主流程函数

```
bubblewrap.c:
├── main() [line 2871-3641]
├── parse_args() [line 2776-2786]
├── parse_args_recurse() [line 2760-2774]
├── acquire_privs() [line 840-903]
├── drop_privs() [line 938-953]
├── monitor_child() [line 495-588]
├── do_init() [line 597-669]
├── setup_newroot() [line 1188-1592]
├── privileged_op() [line 1022-1182]
├── read_priv_sec_op() [line 1676-1712]
├── write_uid_gid_map() [line 955-1020]
├── switch_to_user_with_privs() [line 906-936]
└── seccomp_programs_apply() [line 282-300]
```

#### 绑定挂载函数

```
bind-mount.c:
├── bind_mount() [line 377-489]
├── parse_mountinfo() [line 229-375]
├── decode_mountoptions() [line 82-126]
├── die_with_bind_result() [line 552-598]
└── bind_mount_result_to_string() [line 496-550]
```

#### 工具函数

```
utils.c:
├── die/die_with_error/die_with_mount_error [line 69-109]
├── xmalloc/xcalloc/xrealloc/xstrdup [line 145-191]
├── strconcat/strconcat3/xasprintf [line 307-369]
├── fdwalk [line 371-425]
├── write_file_at/write_to_fd [line 427-476]
├── copy_file_data/copy_file [line 530-590]
├── load_file_data/load_file_at [line 594-661]
├── ensure_dir/ensure_file/mkdir_with_parents [line 674-750]
├── send_pid_on_socket/read_pid_from_socket/create_pid_socketpair [line 752-832]
├── get_oldroot_path/get_newroot_path [line 859-873]
├── raw_clone/pivot_root [line 875-897]
└── label_mount/label_exec/label_create_file [line 899-934]
```

### 4.3 Codex 集成路径

```
codex-rs/linux-sandbox/:
├── src/bwrap.rs           # Bubblewrap 参数构建逻辑
├── src/launcher.rs        # 系统 bwrap 与内置 bwrap 的启动器
├── src/vendored_bwrap.rs  # 内置 bwrap 的 FFI 接口
├── build.rs               # 编译时构建内置 bwrap
└── README.md              # 使用文档
```

## 5. 依赖与外部交互

### 5.1 系统依赖

| 依赖 | 用途 | 配置方式 |
|-----|------|---------|
| libcap | Linux 能力（capabilities）管理 | pkg-config |
| libselinux (可选) | SELinux 标签支持 | meson 选项 `-Dselinux=enabled` |
| libc | 标准 C 库和系统调用 | 系统默认 |

### 5.2 Linux 内核特性

| 特性 | 最低版本 | 说明 |
|-----|---------|------|
| User Namespaces | 3.8 | 非特权用户命名空间支持 |
| Mount Namespaces | 2.4.19 | 挂载命名空间 |
| PID Namespaces | 2.6.24 | PID 命名空间 |
| Network Namespaces | 2.6.24 | 网络命名空间 |
| Seccomp BPF | 3.5 | 系统调用过滤 |
| Seccomp Filter Mode | 3.17 | SECCOMP_MODE_FILTER |
| Ambient Capabilities | 4.3 | PR_CAP_AMBIENT |
| Cgroup Namespaces | 4.6 | CLONE_NEWCGROUP |

### 5.3 与 Codex 的交互

```
Codex Core
    │
    ▼
codex-linux-sandbox crate
    ├── 检查 /usr/bin/bwrap 是否存在
    │   ├── 存在 → exec_system_bwrap()
    │   └── 不存在 → exec_vendored_bwrap()
    │
    ├── bwrap.rs: create_bwrap_command_args()
    │   └── 根据 FileSystemSandboxPolicy 生成参数
    │       ├── --ro-bind / / (默认只读)
    │       ├── --bind <writable> <writable> (可写目录)
    │       ├── --unshare-user --unshare-pid (命名空间)
    │       └── --unshare-net (网络隔离)
    │
    └── launcher.rs: exec_bwrap()
        └── 执行 bwrap，最终 execve 到目标程序
```

### 5.4 测试依赖

| 测试文件 | 用途 |
|---------|------|
| `tests/test-run.sh` | 主要功能测试套件 |
| `tests/test-seccomp.py` | Seccomp 过滤器测试 |
| `tests/test-specifying-pidns.sh` | PID 命名空间指定测试 |
| `tests/test-specifying-userns.sh` | 用户命名空间指定测试 |
| `tests/libtest.sh` | 测试框架库 |
| `tests/libtest-core.sh` | 核心测试函数 |

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 6.1.1 Setuid 模式风险

- **风险**: 当以 setuid root 安装时，代码中的任何漏洞都可能导致本地权限提升
- **缓解**: 
  - 使用 `PR_SET_NO_NEW_PRIVS` 禁止新特权获取
  - 特权分离架构：非特权进程执行大部分逻辑，特权进程仅执行必要操作
  - 严格限制特权操作范围（仅影响子命名空间）
  - 文件系统访问始终以调用者 UID 进行（通过 `setfsuid`）

#### 6.1.2 TOCTOU 攻击

- **风险**: 路径解析和挂载操作之间可能存在竞争条件
- **缓解**:
  - 使用文件描述符（`O_PATH`）验证路径
  - 通过 `/proc/self/fd` 获取内核实际使用的路径大小写
  - 绑定挂载后比较 `fstat` 和 `lstat` 结果检测竞争

#### 6.1.3 命名空间逃逸

- **风险**: 通过 `/proc`、UNIX socket、D-Bus 等途径可能实现沙箱逃逸
- **缓解**:
  - 默认挂载新的 procfs（`--proc /proc`）
  - 覆盖敏感 proc 目录（`sys`, `sysrq-trigger`, `irq`, `bus`）
  - 文档明确说明需要外部工具（如 xdg-dbus-proxy）过滤 D-Bus

### 6.2 边界限制

#### 6.2.1 内核版本限制

```
必需:
- Linux 3.8+ (用户命名空间)
- CONFIG_USER_NS=y
- CONFIG_SECCOMP=y (用于 seccomp)

可选但推荐:
- Linux 4.3+ (Ambient capabilities)
- Linux 4.6+ (Cgroup 命名空间)
```

#### 6.2.2 发行版限制

某些发行版默认禁用非特权用户命名空间：
- Debian: `kernel.unprivileged_userns_clone=0`
- RHEL/CentOS 7: 内核模块参数 `user_namespace.enable=N`
- 需要 setuid 安装或显式启用

#### 6.2.3 嵌套限制

- 命名空间嵌套深度受 `/proc/sys/user/max_*_namespaces` 限制
- 挂载点数量受 `/proc/sys/fs/mount-max` 限制

### 6.3 已知问题

| 问题 | 描述 | 状态 |
|-----|------|------|
| CVE-2017-5226 | TIOCSTI 命令可能允许沙箱外命令执行 | 缓解: 使用 `--new-session` |
| 大小写敏感文件系统 | mountinfo 中的路径大小写可能与请求不同 | 已处理: 使用 readlink 获取内核路径 |
| Overlay 目录重叠 | Overlay 挂载源目录不能重叠 | 运行时检查并报错 |

### 6.4 改进建议

#### 6.4.1 代码层面

1. **增强错误处理**:
   - 当前某些错误仅输出到 stderr，建议增加结构化错误码
   - 改进 `bind_mount_result` 的细分，提供更精确的错误定位

2. **内存管理**:
   - 使用 `cleanup_free` 等 GCC 清理属性较好，但可考虑引入更现代的 RAII 模式
   - 大型缓冲区（如 `buffer[2048]`）可考虑动态分配

3. **测试覆盖**:
   - 增加对边界条件（如超长路径、特殊字符）的测试
   - 增加对竞争条件的压力测试

#### 6.4.2 架构层面

1. **Landlock 集成**:
   - Codex 已有 Landlock 支持，可考虑与 bubblewrap 更深度集成
   - Landlock 提供更细粒度的文件系统访问控制

2. **eBPF 增强**:
   - 考虑使用 eBPF LSM 钩子进行更细粒度的安全策略执行
   - 可替代部分 seccomp 功能，提供更灵活的过滤

3. **OCI 运行时兼容性**:
   - 考虑增加 OCI runtime-spec 兼容层
   - 便于与容器生态系统集成

#### 6.4.3 文档层面

1. **安全最佳实践**:
   - 更详细的威胁模型文档
   - 针对不同使用场景的安全配置指南

2. **故障排查**:
   - 常见错误和解决方案索引
   - 内核配置检查清单

### 6.5 维护建议

1. **定期同步上游**:
   - bubblewrap 上游活跃，应定期同步安全修复
   - 当前 vendored 版本为 0.11.0，需关注更新

2. **依赖监控**:
   - 监控 libcap 和内核 API 变化
   - 测试新内核版本的兼容性

3. **安全审计**:
   - 定期对特权分离代码进行安全审计
   - 使用静态分析工具（如 Coverity、CodeQL）扫描

---

*文档生成时间: 2026-03-22*
*研究对象版本: bubblewrap 0.11.0*
*Codex 集成路径: codex-rs/linux-sandbox/*
