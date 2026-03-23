# bubblewrap.c 深度研究文档

## 1. 场景与职责

### 1.1 项目定位

`bubblewrap.c` 是 [Bubblewrap](https://github.com/containers/bubblewrap) 项目的核心源代码文件，是一个用于在 Linux 系统上创建轻量级沙箱环境的底层工具。在 Codex 项目中，它被作为 vendored 依赖集成到 `codex-rs/linux-sandbox` crate 中，用于为 Linux 平台提供安全的文件系统隔离和进程沙箱功能。

### 1.2 核心职责

1. **命名空间隔离**：创建新的 Linux 命名空间（user、pid、net、ipc、uts、cgroup、mount），实现进程、网络、主机名等资源的隔离
2. **文件系统沙箱**：通过 bind mount、overlayfs、tmpfs 等机制构建受限的文件系统视图
3. **权限管理**：处理 UID/GID 映射、capabilities 的升降级，实现最小权限原则
4. **特权分离**：在 setuid 模式下，通过父子进程通信实现特权操作的安全委托
5. **进程生命周期管理**：作为 PID 1 的 init 进程或监控进程管理沙箱内进程的生命周期

### 1.3 使用场景

- **Codex CLI**: 在 Linux 上执行不受信任的代码时创建隔离环境
- **Flatpak**: 桌面应用的沙箱运行环境
- **容器运行时**: 作为底层工具构建容器文件系统
- **CI/CD 环境**: 安全地运行构建和测试任务

---

## 2. 功能点目的

### 2.1 命名空间管理

| 命名空间 | 选项 | 目的 |
|---------|------|------|
| User (CLONE_NEWUSER) | `--unshare-user` | 隔离用户/组 ID，允许非特权用户拥有 root 权限的视图 |
| PID (CLONE_NEWPID) | `--unshare-pid` | 隔离进程 ID 空间，沙箱内 PID 1 可管理僵尸进程 |
| Network (CLONE_NEWNET) | `--unshare-net` | 隔离网络设备，仅保留 loopback |
| IPC (CLONE_NEWIPC) | `--unshare-ipc` | 隔离 System V IPC 和 POSIX 消息队列 |
| UTS (CLONE_NEWUTS) | `--unshare-uts` | 隔离主机名和域名 |
| Cgroup (CLONE_NEWCGROUP) | `--unshare-cgroup` | 隔离 cgroup 视图 |
| Mount (CLONE_NEWNS) | 始终启用 | 隔离挂载点，构建独立的文件系统视图 |

### 2.2 文件系统操作

| 操作类型 | 命令行选项 | 用途 |
|---------|-----------|------|
| 只读绑定挂载 | `--ro-bind` | 将主机目录以只读方式暴露到沙箱 |
| 读写绑定挂载 | `--bind` | 将主机目录以读写方式暴露到沙箱 |
| 设备绑定挂载 | `--dev-bind` | 允许访问设备文件的绑定挂载 |
| 临时覆盖层 | `--tmp-overlay` | 在 tmpfs 上创建可写的 overlayfs |
| 只读覆盖层 | `--ro-overlay` | 创建只读的 overlayfs 视图 |
| 创建 tmpfs | `--tmpfs` | 在指定路径挂载临时文件系统 |
| 创建目录 | `--dir` | 在沙箱内创建目录 |
| 创建文件 | `--file` | 从文件描述符复制内容创建文件 |
| 创建符号链接 | `--symlink` | 创建符号链接 |

### 2.3 安全机制

| 机制 | 目的 |
|------|------|
| `PR_SET_NO_NEW_PRIVS` | 禁止进程通过 execve 获得新特权（防止 setuid 逃逸） |
| Seccomp-BPF | 通过系统调用过滤限制可执行的 syscall |
| Capabilities 管理 | 精确控制进程的 Linux capabilities，最小化权限 |
| UID/GID 映射 | 将外部 UID/GID 映射到沙箱内的不同值 |
| Pivot Root | 改变根文件系统，彻底隔离主机文件系统 |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 SetupOp - 文件系统操作队列

```c
typedef struct _SetupOp SetupOp;
struct _SetupOp
{
  SetupOpType type;      // 操作类型（绑定挂载、创建目录等）
  const char *source;    // 源路径
  const char *dest;      // 目标路径
  int         fd;        // 文件描述符（用于 --file 等）
  SetupOpFlag flags;     // 操作标志
  int         perms;     // 权限模式
  size_t      size;      // 大小参数（用于 tmpfs）
  SetupOp    *next;      // 链表指针
};
```

**用途**：在参数解析阶段收集所有文件系统操作，在沙箱设置阶段按顺序执行。

#### 3.1.2 NsInfo - 命名空间信息

```c
typedef struct _NsInfo NsInfo;
struct _NsInfo {
  const char *name;      // 命名空间名称（如 "pid", "net"）
  bool       *do_unshare; // 是否取消共享的标志指针
  ino_t       id;        // 命名空间的 inode ID（用于标识）
};
```

**用途**：跟踪哪些命名空间被创建，以及它们的标识符。

#### 3.1.3 PrivSepOp - 特权分离操作

```c
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

**用途**：在 setuid 模式下，非特权子进程通过 socket 向特权父进程请求执行特权操作。

### 3.2 关键流程

#### 3.2.1 主流程概览

```
main()
├── 获取真实 UID/GID
├── acquire_privs()           # 获取/管理特权
├── parse_args()              # 解析命令行参数
├── 验证参数兼容性
├── raw_clone()               # 创建新命名空间
│   └── 子进程进入沙箱
└── 父进程：
    ├── namespace_ids_read()  # 读取命名空间 ID
    ├── write_uid_gid_map()   # 设置 UID/GID 映射
    ├── drop_privs()          # 丢弃特权
    └── monitor_child()       # 监控子进程
```

#### 3.2.2 沙箱初始化流程（子进程）

```
子进程入口
├── 等待父进程设置 UID/GID 映射
├── switch_to_user_with_privs()  # 切换到目标用户但保留 capabilities
├── loopback_setup()             # 如果隔离网络，设置 loopback
├── resolve_symlinks_in_ops()    # 解析符号链接
├── 设置挂载传播（MS_SLAVE | MS_REC）
├── 在 /tmp 创建 tmpfs 作为新根
├── pivot_root()                 # 切换到新根
├── setup_newroot()              # 执行所有文件系统操作
│   └── 遍历 SetupOp 链表执行操作
├── 第二次 pivot_root()          # 清理 oldroot
├── 可能的第二层用户命名空间
├── drop_privs()                 # 最终丢弃 capabilities
└── execvp()                     # 执行目标程序
```

#### 3.2.3 特权分离流程（setuid 模式）

```
当 is_privileged = true 时：
├── socketpair() 创建特权分离 socket
├── fork() 创建子进程
│   └── 子进程（非特权）：
│       ├── drop_privs(false, true)  # 完全降权
│       ├── setup_newroot()          # 构建操作列表
│       └── 通过 socket 发送 PrivSepOp 请求
└── 父进程（特权）：
    └── 循环读取 PrivSepOp 并执行特权操作
        ├── PRIV_SEP_OP_BIND_MOUNT
        ├── PRIV_SEP_OP_PROC_MOUNT
        ├── PRIV_SEP_OP_TMPFS_MOUNT
        └── ...
```

### 3.3 关键技术细节

#### 3.3.1 UID/GID 映射

```c
static void write_uid_gid_map (uid_t sandbox_uid,
                               uid_t parent_uid,
                               uid_t sandbox_gid,
                               uid_t parent_gid,
                               pid_t pid,
                               bool  deny_groups,
                               bool  map_root)
```

**功能**：写入 `/proc/[pid]/uid_map` 和 `/proc/[pid]/gid_map`，建立命名空间内外 UID/GID 的映射关系。

**示例映射**（map_root=true, parent_uid=1000, sandbox_uid=1000）：
```
uid_map: "0 65534 1\n1000 1000 1\n"
gid_map: "0 65534 1\n1000 1000 1\n"
```
这表示：
- 沙箱内 UID 0 映射到外部 overflow_uid (65534)
- 沙箱内 UID 1000 映射到外部 UID 1000

#### 3.3.2 Pivot Root 操作

Bubblewrap 使用两次 pivot_root 来完全隔离文件系统：

**第一次 pivot_root**:
```c
pivot_root("/tmp", "oldroot");
```
将新创建的 tmpfs 作为根，原根移动到 `/oldroot`。

**第二次 pivot_root**:
```c
pivot_root(".", ".");  // /newroot 成为新根
umount2(".", MNT_DETACH);  // 卸载 oldroot
```
将 `/newroot`（在 tmpfs 中构建的沙箱根）提升为真正的根。

#### 3.3.3 Bind Mount 安全处理

```c
bind_mount_result bind_mount (int           proc_fd,
                              const char   *src,
                              const char   *dest,
                              bind_option_t options,
                              char        **failing_path)
```

**安全措施**：
1. 使用 `MS_REC` 进行递归绑定，防止通过非递归绑定访问被覆盖的挂载点
2. 重新打开目标路径获取 fd，通过 `/proc/self/fd/N` 读取实际挂载点
3. 解析 `/proc/self/mountinfo` 获取准确的挂载信息
4. 使用 `MS_REMOUNT` 应用只读、nosuid、nodev 等标志

#### 3.3.4 Seccomp 程序加载

```c
typedef struct _SeccompProgram SeccompProgram;
struct _SeccompProgram
{
  struct sock_fprog  program;  // BPF 程序
  SeccompProgram    *next;
};

static void seccomp_programs_apply (void)
{
  for (program = seccomp_programs; program != NULL; program = program->next)
    prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program->program);
}
```

**特点**：
- 支持加载多个 seccomp 程序（通过 `--add-seccomp-fd`）
- 在 `do_init()` 或最终 exec 前应用
- 与 `PR_SET_NO_NEW_PRIVS` 配合使用

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/vendor/bubblewrap/
├── bubblewrap.c      # 主程序（3641 行）- 参数解析、命名空间管理、主流程
├── bind-mount.c      # 绑定挂载实现（598 行）- mountinfo 解析、安全挂载
├── bind-mount.h      # 绑定挂载头文件
├── network.c         # 网络设置（199 行）- loopback 配置
├── network.h         # 网络头文件
├── utils.c           # 工具函数（1080 行）- 字符串、文件操作、内存管理
├── utils.h           # 工具头文件
└── config.h          # 构建时生成的配置
```

### 4.2 关键代码路径

#### 4.2.1 参数解析路径

```
bubblewrap.c:2871 main()
  └── bubblewrap.c:2934 parse_args()
      └── bubblewrap.c:1761 parse_args_recurse()
          ├── 处理 --unshare-* 选项（行 1887-1918）
          ├── 处理 --bind/--ro-bind/--dev-bind（行 1956-2000）
          ├── 处理 --overlay/--tmp-overlay/--ro-overlay（行 2025-2094）
          ├── 处理 --proc/--dev/--tmpfs（行 2095-2172）
          └── 处理 --seccomp/--add-seccomp-fd（行 2406-2449）
```

#### 4.2.2 沙箱设置路径

```
bubblewrap.c:3130 raw_clone() 创建子进程
  └── 子进程：
      ├── bubblewrap.c:3275 switch_to_user_with_privs()
      ├── bubblewrap.c:3310 mount(MS_SLAVE | MS_REC) 设置挂载传播
      ├── bubblewrap.c:3314 mount(tmpfs) 创建新根
      ├── bubblewrap.c:3352 pivot_root() 第一次切换根
      ├── bubblewrap.c:3404/3358 setup_newroot() 执行文件系统操作
      │   └── 遍历 ops 链表执行 SETUP_* 操作
      ├── bubblewrap.c:3439 pivot_root() 第二次切换根
      └── bubblewrap.c:3502 drop_privs() 最终降权
```

#### 4.2.3 特权分离路径（setuid 模式）

```
bubblewrap.c:3358 进入 setuid 分支
  ├── bubblewrap.c:3363 socketpair() 创建通信 socket
  ├── bubblewrap.c:3366 fork() 创建子进程
  │   └── 子进程（bubblewrap.c:3370-3376）：
  │       ├── drop_privs(false, true) 完全降权
  │       └── setup_newroot(opt_unshare_pid, privsep_sockets[1])
  │           └── 通过 privileged_op() 发送请求
  └── 父进程（bubblewrap.c:3378-3401）：
      └── 循环 read_priv_sec_op() + privileged_op(-1, ...) 执行特权操作
```

#### 4.2.4 监控进程路径

```
bubblewrap.c:3190 monitor_child(event_fd, pid, setup_finished_pipe[0])
  ├── bubblewrap.c:521 fdwalk() 关闭多余文件描述符
  ├── bubblewrap.c:526 signalfd() 创建信号 fd
  ├── bubblewrap.c:540 poll() 等待事件
  │   ├── 读取 event_fd 获取子进程退出码
  │   └── 读取 signal_fd 处理 SIGCHLD
  └── bubblewrap.c:578 propagate_exit_status() 返回子进程状态
```

### 4.3 Codex 集成路径

```
codex-rs/linux-sandbox/
├── src/
│   ├── bwrap.rs           # Bubblewrap 参数构建（Rust 封装）
│   ├── launcher.rs        # 启动器（系统 bwrap 或 vendored）
│   ├── vendored_bwrap.rs  # 内嵌 bwrap 的 FFI 调用
│   └── lib.rs             # 库入口
├── build.rs               # 编译时构建 bubblewrap.c
└── README.md              # 使用文档
```

**构建时集成**（`build.rs` 行 61-78）：
```rust
let mut build = cc::Build::new();
build
    .file(src_dir.join("bubblewrap.c"))
    .file(src_dir.join("bind-mount.c"))
    .file(src_dir.join("network.c"))
    .file(src_dir.join("utils.c"))
    .define("main", Some("bwrap_main"));  // 重命名 main 为 bwrap_main
```

---

## 5. 依赖与外部交互

### 5.1 系统依赖

| 依赖 | 用途 | 检测方式 |
|------|------|---------|
| libcap | Linux capabilities 操作 | pkg-config |
| Linux Kernel 3.8+ | User namespaces 支持 | 运行时检测 |
| /proc | 进程信息、mountinfo | 必需 |
| /sys | 内核参数（如 max_user_namespaces） | 可选功能检测 |

### 5.2 内核接口

#### 5.2.1 系统调用封装

```c
// utils.c:876-897
int raw_clone (unsigned long flags, void *child_stack)
{
  return (int) syscall (__NR_clone, flags, child_stack);
}

int pivot_root (const char * new_root, const char * put_old)
{
  return syscall (__NR_pivot_root, new_root, put_old);
}
```

#### 5.2.2 prctl 操作

```c
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);     // 禁止获得新特权
prctl(PR_SET_PDEATHSIG, SIGKILL, ...);      // 父进程死亡时发送信号
prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_RAISE, ...);  // 设置 ambient capabilities
prctl(PR_CAPBSET_DROP, ...);                // 从 bounding set 删除 capability
prctl(PR_SET_KEEPCAPS, 1, ...);             // 切换 UID 时保留 capabilities
prctl(PR_SET_DUMPABLE, 1, ...);             // 设置可 dump（用于 /proc/self 所有权）
```

### 5.3 与 Codex 的交互

#### 5.3.1 调用链

```
Codex CLI (Rust)
└── linux-sandbox::run_main()
    └── create_bwrap_command_args()  [bwrap.rs:94]
        └── 构建 bubblewrap 参数列表
            └── launcher::exec_bwrap()  [launcher.rs:19]
                ├── 优先尝试 /usr/bin/bwrap
                └── 回退到 vendored_bwrap::exec_vendored_bwrap()
                    └── bwrap_main(argc, argv)  [bubblewrap.c:2871]
```

#### 5.3.2 典型参数生成

Codex 生成的典型 bubblewrap 参数（来自 `bwrap.rs`）：

```
--new-session
--die-with-parent
--ro-bind / /
--dev /dev
--bind <writable_root> <writable_root>
--ro-bind <protected_subpath> <protected_subpath>
--unshare-user
--unshare-pid
--unshare-net  (如果网络隔离)
--proc /proc
--chdir <cwd>
--
<command> <args...>
```

### 5.4 外部工具交互

| 工具/文件 | 交互方式 | 用途 |
|----------|---------|------|
| /proc/self/mountinfo | 读取 | 解析当前挂载状态 |
| /proc/[pid]/ns/* | 读取 | 获取命名空间 ID |
| /proc/[pid]/uid_map | 写入 | 设置 UID 映射 |
| /proc/[pid]/gid_map | 写入 | 设置 GID 映射 |
| /proc/[pid]/setgroups | 写入 | 禁用 setgroups |
| /proc/sys/user/max_user_namespaces | 读取/写入 | 检测/限制用户命名空间 |

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 6.1.1 setuid 模式风险

**风险描述**：当 bubblewrap 以 setuid root 安装时，任何本地用户都可以使用它。虽然代码经过安全审计，但 setuid 程序本质上是高价值攻击目标。

**缓解措施**：
- 优先使用非特权用户命名空间（`--unshare-user`）
- 使用 `PR_SET_NO_NEW_PRIVS` 防止特权提升
- 最小化保留的 capabilities（仅 CAP_SYS_ADMIN, CAP_SYS_CHROOT 等）

**Codex 处理方式**：Codex 默认使用 `--unshare-user`，优先依赖非特权用户命名空间而非 setuid。

#### 6.1.2 TIOCSTI 攻击 (CVE-2017-5226)

**风险描述**：如果沙箱内进程可以访问外部终端，可能通过 `TIOCSTI` ioctl 向终端注入命令。

**缓解措施**：
- 使用 `--new-session` 创建新的终端会话（默认启用）
- 或使用 seccomp 过滤 `TIOCSTI`

**代码实现**（bubblewrap.c:3543-3545）：
```c
if (opt_new_session && setsid () == (pid_t) -1)
  die_with_error ("setsid");
```

#### 6.1.3 符号链接竞态条件

**风险描述**：在处理路径时，攻击者可能通过符号链接竞态条件（TOCTOU）访问未授权文件。

**缓解措施**：
- 使用文件描述符（`--bind-fd`）而非路径
- 在 `bind_mount()` 中通过 `/proc/self/fd/N` 验证实际挂载的目标
- 使用 `O_PATH` 和 `fstat()` 进行验证

### 6.2 边界条件

#### 6.2.1 内核版本兼容性

| 功能 | 最低内核版本 | 检测方式 |
|------|------------|---------|
| User namespaces | 3.8 | 检测 `/proc/self/ns/user` |
| PID namespaces | 2.6.24 | 始终可用 |
| Network namespaces | 2.6.24 | 始终可用 |
| Cgroup namespaces | 4.6 | 检测 `/proc/self/ns/cgroup` |
| Seccomp-BPF | 3.5 | 运行时检测 |
| Ambient capabilities | 4.3 | 运行时检测（EINVAL） |

#### 6.2.2 资源限制

```c
#define MAX_TMPFS_BYTES ((size_t) (SIZE_MAX >> 1))  // 地址空间的一半
static const int32_t MAX_ARGS = 9000;               // 参数数量限制
```

#### 6.2.3 嵌套限制

- 用户命名空间嵌套深度受 `/proc/sys/user/max_user_namespaces` 限制
- 挂载命名空间嵌套可能导致 `ENOSPC`（mount-max 限制，默认 100000）

### 6.3 已知限制

1. **Overlayfs 限制**：`--overlay` 系列选项在 setuid 模式下被禁用（行 2027-2040）
2. **Size 限制**：`--size` 选项在 setuid 模式下被禁用（行 2684-2685）
3. **设备访问**：`--dev` 创建的 minimal /dev 只包含标准设备（null, zero, full, random, urandom, tty）
4. **信号处理**：某些信号（如 SIGSTOP）可能导致监控进程和沙箱进程状态不一致

### 6.4 改进建议

#### 6.4.1 安全增强

1. **Landlock 集成**：考虑集成 Linux Landlock LSM 进行更细粒度的文件系统访问控制（Codex 已在 `landlock.rs` 中实现部分支持）

2. **Seccomp 策略改进**：
   - 提供预定义的 seccomp 策略配置文件
   - 支持更细粒度的 syscall 参数过滤

3. **审计日志**：增加可选的审计日志记录沙箱创建、文件系统操作等安全相关事件

#### 6.4.2 功能增强

1. **cgroups v2 支持**：添加对 cgroups v2 的资源限制支持（CPU、内存、IO）

2. **ID 映射改进**：支持更灵活的 UID/GID 映射配置，如多范围映射

3. **性能优化**：
   - 减少 mountinfo 解析的开销（缓存或增量更新）
   - 优化大规模绑定挂载场景

#### 6.4.3 可维护性改进

1. **模块化**：将 `bubblewrap.c`（3641 行）拆分为更小的模块：
   - `namespace.c` - 命名空间管理
   - `mount.c` - 挂载操作
   - `privilege.c` - 特权管理

2. **测试覆盖**：增加单元测试，特别是边界条件测试：
   - 嵌套命名空间测试
   - 资源耗尽测试
   - 竞态条件测试

3. **文档完善**：
   - 详细的内部架构文档
   - 安全模型说明
   - 性能基准测试

#### 6.4.4 Codex 特定建议

1. **版本追踪**：建立 vendored bubblewrap 版本与上游的同步机制
2. **补丁管理**：如有本地修改，使用 quilt/patch 系统管理
3. **安全更新**：建立安全公告监控，及时更新 vendored 版本

---

## 7. 总结

`bubblewrap.c` 是一个经过良好设计和安全审计的 Linux 沙箱工具。在 Codex 项目中，它作为文件系统隔离的核心组件，通过命名空间、挂载操作和权限管理构建安全的执行环境。

**核心优势**：
- 轻量级，无守护进程
- 支持 setuid 和非特权两种模式
- 细粒度的文件系统控制
- 活跃的安全维护

**使用建议**：
- 优先使用非特权用户命名空间（`--unshare-user`）
- 始终使用 `--new-session` 防止 TIOCSTI 攻击
- 仔细审查 bind mount 的源路径，避免敏感信息泄露
- 定期更新 vendored 版本以获取安全修复

---

*文档生成时间：2026-03-23*
*基于 bubblewrap.c 版本：上游 commit 未明确，位于 codex-rs/vendor/bubblewrap/*
