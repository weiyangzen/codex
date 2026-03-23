# flatpak.bpf 研究文档

## 文件信息
- **路径**: `codex-rs/vendor/bubblewrap/demos/flatpak.bpf`
- **大小**: 744 bytes
- **类型**: 二进制 BPF（Berkeley Packet Filter）字节码

---

## 1. 场景与职责

### 1.1 使用场景

`flatpak.bpf` 是一个**预编译的 Seccomp BPF（Berkeley Packet Filter）程序**，用于在 Flatpak 应用沙箱中实施系统调用过滤。该文件被 `flatpak-run.sh` 脚本加载，通过 `bwrap` 的 `--seccomp` 参数应用到容器进程。

### 1.2 核心职责

1. **系统调用过滤**: 限制容器内进程可执行的系统调用集合
2. **安全策略实施**: 阻止潜在危险的系统调用，减少攻击面
3. **兼容性保证**: 允许正常应用运行所需的系统调用，同时阻止特权操作

### 1.3 在沙箱中的位置

```
┌─────────────────────────────────────────┐
│           应用进程 (org.gnome.Weather)   │
│  ┌─────────────────────────────────┐    │
│  │      Seccomp BPF Filter         │    │ ← flatpak.bpf
│  │  ┌─────────────────────────┐    │    │
│  │  │    允许的 syscalls      │    │    │
│  │  │    - read/write         │    │    │
│  │  │    - mmap/munmap        │    │    │
│  │  │    - futex              │    │    │
│  │  │    - ...                │    │    │
│  │  └─────────────────────────┘    │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │    阻止的 syscalls      │    │    │
│  │  │    - mount/umount       │    │    │
│  │  │    - pivot_root         │    │    │
│  │  │    - ptrace             │    │    │
│  │  │    - ...                │    │    │
│  │  └─────────────────────────┘    │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 Seccomp 模式

Linux Seccomp 提供两种主要模式：

| 模式 | 说明 | 用途 |
|------|------|------|
| **SECCOMP_MODE_STRICT** | 只允许 read/write/exit/sigreturn | 极度受限，极少使用 |
| **SECCOMP_MODE_FILTER** | 使用 BPF 程序过滤系统调用 | 灵活精细控制 |

`flatpak.bpf` 使用 **SECCOMP_MODE_FILTER** 模式，提供精细的系统调用控制。

### 2.2 BPF 程序结构

Seccomp BPF 程序的基本结构：

```c
struct sock_filter {
    __u16 code;   // 操作码
    __u8  jt;     // 真跳转偏移
    __u8  jf;     // 假跳转偏移
    __u32 k;      // 立即数/参数
};
```

### 2.3 典型过滤策略

Flatpak 的 Seccomp 策略通常遵循**白名单**模式：

1. **默认拒绝**: 未明确允许的系统调用返回 `EPERM`（操作不允许）
2. **架构特定**: 针对 x86_64 架构的系统调用号
3. **参数检查**: 某些系统调用根据参数值决定是否允许

---

## 3. 具体技术实现

### 3.1 文件格式分析

通过 `xxd` 分析文件结构：

```
00000000: 2000 0000 0400 0000 1500 003e 3e00 00c0   ..........>>...
```

**头结构解析**（Linux `struct sock_fprog`）：

```c
struct sock_fprog {
    unsigned short len;    // BPF 指令数量
    struct sock_filter *filter;  // 指令数组指针
};
```

从字节序看（小端）：
- `20 00` = 0x0020 = 32 条指令（或相关计数）
- 后续是 BPF 指令数组

### 3.2 BPF 指令解码

BPF 指令格式（64位系统）：

```
┌────────┬────┬────┬────────────┐
│  code  │ jt │ jf │     k      │
│ 16 bit │8bit│8bit│   32 bit   │
└────────┴────┴────┴────────────┘
```

常见操作码：

| 操作码 | 含义 | 用途 |
|--------|------|------|
| `0x00` | LD | 加载数据 |
| `0x05` | JMP | 跳转 |
| `0x06` | RET | 返回（允许/拒绝） |
| `0x15` | JEQ | 等于则跳转 |
| `0x20` | LD W ABS | 从绝对偏移加载字 |

### 3.3 系统调用号映射

x86_64 架构常用系统调用号（部分）：

| 系统调用 | 编号（十六进制） | 编号（十进制） |
|---------|----------------|---------------|
| read | 0 | 0 |
| write | 1 | 1 |
| open | 2 | 2 |
| close | 3 | 3 |
| stat | 4 | 4 |
| fstat | 5 | 5 |
| mmap | 9 | 9 |
| mprotect | 10 | 10 |
| munmap | 11 | 11 |
| brk | 12 | 12 |
| rt_sigaction | 13 | 13 |
| rt_sigprocmask | 14 | 14 |
| ioctl | 16 | 16 |
| pread64 | 17 | 17 |
| pwrite64 | 18 | 18 |
| readv | 19 | 19 |
| writev | 20 | 20 |
| access | 21 | 21 |
| pipe | 22 | 22 |
| select | 23 | 23 |
| sched_yield | 24 | 24 |
| mremap | 25 | 25 |
| msync | 26 | 26 |
| mincore | 27 | 27 |
| madvise | 28 | 28 |
| shmget | 29 | 29 |
| shmat | 30 | 30 |
| shmctl | 31 | 31 |
| dup | 32 | 32 |
| dup2 | 33 | 33 |
| pause | 34 | 34 |
| nanosleep | 35 | 35 |
| getitimer | 36 | 36 |
| alarm | 37 | 37 |
| setitimer | 38 | 38 |
| getpid | 39 | 39 |
| sendfile | 40 | 40 |
| socket | 41 | 41 |
| connect | 42 | 42 |
| accept | 43 | 43 |
| sendto | 44 | 44 |
| recvfrom | 45 | 45 |
| sendmsg | 46 | 46 |
| recvmsg | 47 | 47 |
| shutdown | 48 | 48 |
| bind | 49 | 49 |
| listen | 50 | 50 |
| getsockname | 51 | 51 |
| getpeername | 52 | 52 |
| socketpair | 53 | 53 |
| setsockopt | 54 | 54 |
| getsockopt | 55 | 55 |
| clone | 56 | 56 |
| fork | 57 | 57 |
| vfork | 58 | 58 |
| execve | 59 | 59 |
| exit | 60 | 60 |
| wait4 | 61 | 61 |
| kill | 62 | 62 |
| uname | 63 | 63 |
| semget | 64 | 64 |
| semop | 65 | 65 |
| semctl | 66 | 66 |
| shmdt | 67 | 67 |
| msgget | 68 | 68 |
| msgsnd | 69 | 69 |
| msgrcv | 70 | 70 |
| msgctl | 71 | 71 |
| fcntl | 72 | 72 |
| flock | 73 | 73 |
| fsync | 74 | 74 |
| fdatasync | 75 | 75 |
| truncate | 76 | 76 |
| ftruncate | 77 | 77 |
| getdents | 78 | 78 |
| getcwd | 79 | 79 |
| chdir | 80 | 80 |
| fchdir | 81 | 81 |
| rename | 82 | 82 |
| mkdir | 83 | 83 |
| rmdir | 84 | 84 |
| creat | 85 | 85 |
| link | 86 | 86 |
| unlink | 87 | 87 |
| symlink | 88 | 88 |
| readlink | 89 | 89 |
| chmod | 90 | 90 |
| fchmod | 91 | 91 |
| chown | 92 | 92 |
| fchown | 93 | 93 |
| lchown | 94 | 94 |
| umask | 95 | 95 |
| gettimeofday | 96 | 96 |
| getrlimit | 97 | 97 |
| getrusage | 98 | 98 |
| sysinfo | 99 | 99 |
| times | 100 | 100 |
| ptrace | 101 | 101 |
| getuid | 102 | 102 |
| syslog | 103 | 103 |
| getgid | 104 | 104 |
| setuid | 105 | 105 |
| setgid | 106 | 106 |
| geteuid | 107 | 107 |
| getegid | 108 | 108 |
| setpgid | 109 | 109 |
| getppid | 110 | 110 |
| getpgrp | 111 | 111 |
| setsid | 112 | 112 |
| setreuid | 113 | 113 |
| setregid | 114 | 114 |
| getgroups | 115 | 115 |
| setgroups | 116 | 116 |
| setresuid | 117 | 117 |
| getresuid | 118 | 118 |
| setresgid | 119 | 119 |
| getresgid | 120 | 120 |
| getpgid | 121 | 121 |
| setfsuid | 122 | 122 |
| setfsgid | 123 | 123 |
| getsid | 124 | 124 |
| capget | 125 | 125 |
| capset | 126 | 126 |
| rt_sigpending | 127 | 127 |
| rt_sigtimedwait | 128 | 128 |
| rt_sigqueueinfo | 129 | 129 |
| rt_sigsuspend | 130 | 130 |
| sigaltstack | 131 | 131 |
| utime | 132 | 132 |
| mknod | 133 | 133 |
| uselib | 134 | 134 |
| personality | 135 | 135 |
| ustat | 136 | 136 |
| statfs | 137 | 137 |
| fstatfs | 138 | 138 |
| sysfs | 139 | 139 |
| getpriority | 140 | 140 |
| setpriority | 141 | 141 |
| sched_setparam | 142 | 142 |
| sched_getparam | 143 | 143 |
| sched_setscheduler | 144 | 144 |
| sched_getscheduler | 145 | 145 |
| sched_get_priority_max | 146 | 146 |
| sched_get_priority_min | 147 | 147 |
| sched_rr_get_interval | 148 | 148 |
| mlock | 149 | 149 |
| munlock | 150 | 150 |
| mlockall | 151 | 151 |
| munlockall | 152 | 152 |
| vhangup | 153 | 153 |
| modify_ldt | 154 | 154 |
| pivot_root | 155 | 155 |
| _sysctl | 156 | 156 |
| prctl | 157 | 157 |
| arch_prctl | 158 | 158 |
| adjtimex | 159 | 159 |
| setrlimit | 160 | 160 |
| chroot | 161 | 161 |
| sync | 162 | 162 |
| acct | 163 | 163 |
| settimeofday | 164 | 164 |
| mount | 165 | 165 |
| umount2 | 166 | 166 |
| swapon | 167 | 167 |
| swapoff | 168 | 168 |
| reboot | 169 | 169 |
| sethostname | 170 | 170 |
| setdomainname | 171 | 171 |
| iopl | 172 | 172 |
| ioperm | 173 | 173 |
| create_module | 174 | 174 |
| init_module | 175 | 175 |
| delete_module | 176 | 176 |
| get_kernel_syms | 177 | 177 |
| query_module | 178 | 178 |
| quotactl | 179 | 179 |
| nfsservctl | 180 | 180 |
| getpmsg | 181 | 181 |
| putpmsg | 182 | 182 |
| afs_syscall | 183 | 183 |
| tuxcall | 184 | 184 |
| security | 185 | 185 |
| gettid | 186 | 186 |
| readahead | 187 | 187 |
| setxattr | 188 | 188 |
| lsetxattr | 189 | 189 |
| fsetxattr | 190 | 190 |
| getxattr | 191 | 191 |
| lgetxattr | 192 | 192 |
| fgetxattr | 193 | 193 |
| listxattr | 194 | 194 |
| llistxattr | 195 | 195 |
| flistxattr | 196 | 196 |
| removexattr | 197 | 197 |
| lremovexattr | 198 | 198 |
| fremovexattr | 199 | 199 |
| tkill | 200 | 200 |
| time | 201 | 201 |
| futex | 202 | 202 |
| sched_setaffinity | 203 | 203 |
| sched_getaffinity | 204 | 204 |
| set_thread_area | 205 | 205 |
| io_setup | 206 | 206 |
| io_destroy | 207 | 207 |
| io_getevents | 208 | 208 |
| io_submit | 209 | 209 |
| io_cancel | 210 | 210 |
| get_thread_area | 211 | 211 |
| lookup_dcookie | 212 | 212 |
| epoll_create | 213 | 213 |
| epoll_ctl_old | 214 | 214 |
| epoll_wait_old | 215 | 215 |
| remap_file_pages | 216 | 216 |
| getdents64 | 217 | 217 |
| set_tid_address | 218 | 218 |
| restart_syscall | 219 | 219 |
| semtimedop | 220 | 220 |
| fadvise64 | 221 | 221 |
| timer_create | 222 | 222 |
| timer_settime | 223 | 223 |
| timer_gettime | 224 | 224 |
| timer_getoverrun | 225 | 225 |
| timer_delete | 226 | 226 |
| clock_settime | 227 | 227 |
| clock_gettime | 228 | 228 |
| clock_getres | 229 | 229 |
| clock_nanosleep | 230 | 230 |
| exit_group | 231 | 231 |
| epoll_wait | 232 | 232 |
| epoll_ctl | 233 | 233 |
| tgkill | 234 | 234 |
| utimes | 235 | 235 |
| vserver | 236 | 236 |
| mbind | 237 | 237 |
| set_mempolicy | 238 | 238 |
| get_mempolicy | 239 | 239 |
| mq_open | 240 | 240 |
| mq_unlink | 241 | 241 |
| mq_timedsend | 242 | 242 |
| mq_timedreceive | 243 | 243 |
| mq_notify | 244 | 244 |
| mq_getsetattr | 245 | 245 |
| kexec_load | 246 | 246 |
| waitid | 247 | 247 |
| add_key | 248 | 248 |
| request_key | 249 | 249 |
| keyctl | 250 | 250 |
| ioprio_set | 251 | 251 |
| ioprio_get | 252 | 252 |
| inotify_init | 253 | 253 |
| inotify_add_watch | 254 | 254 |
| inotify_rm_watch | 255 | 255 |
| migrate_pages | 256 | 256 |
| openat | 257 | 257 |
| mkdirat | 258 | 258 |
| mknodat | 259 | 259 |
| fchownat | 260 | 260 |
| futimesat | 261 | 261 |
| newfstatat | 262 | 262 |
| unlinkat | 263 | 263 |
| renameat | 264 | 264 |
| linkat | 265 | 265 |
| symlinkat | 266 | 266 |
| readlinkat | 267 | 267 |
| fchmodat | 268 | 268 |
| faccessat | 269 | 269 |
| pselect6 | 270 | 270 |
| ppoll | 271 | 271 |
| unshare | 272 | 272 |
| set_robust_list | 273 | 273 |
| get_robust_list | 274 | 274 |
| splice | 275 | 275 |
| tee | 276 | 276 |
| sync_file_range | 277 | 277 |
| vmsplice | 278 | 278 |
| move_pages | 279 | 279 |
| utimensat | 280 | 280 |
| epoll_pwait | 281 | 281 |
| signalfd | 282 | 282 |
| timerfd_create | 283 | 283 |
| eventfd | 284 | 284 |
| fallocate | 285 | 285 |
| timerfd_settime | 286 | 286 |
| timerfd_gettime | 287 | 287 |
| accept4 | 288 | 288 |
| signalfd4 | 289 | 289 |
| eventfd2 | 290 | 290 |
| epoll_create1 | 291 | 291 |
| dup3 | 292 | 292 |
| pipe2 | 293 | 293 |
| inotify_init1 | 294 | 294 |
| preadv | 295 | 295 |
| pwritev | 296 | 296 |
| rt_tgsigqueueinfo | 297 | 297 |
| perf_event_open | 298 | 298 |
| recvmmsg | 299 | 299 |
| fanotify_init | 300 | 300 |
| fanotify_mark | 301 | 301 |
| prlimit64 | 302 | 302 |
| name_to_handle_at | 303 | 303 |
| open_by_handle_at | 304 | 304 |
| clock_adjtime | 305 | 305 |
| syncfs | 306 | 306 |
| sendmmsg | 307 | 307 |
| setns | 308 | 308 |
| getcpu | 309 | 309 |
| process_vm_readv | 310 | 310 |
| process_vm_writev | 311 | 311 |
| kcmp | 312 | 312 |
| finit_module | 313 | 313 |
| sched_setattr | 314 | 314 |
| sched_getattr | 315 | 315 |
| renameat2 | 316 | 316 |
| seccomp | 317 | 317 |
| getrandom | 318 | 318 |
| memfd_create | 319 | 319 |
| kexec_file_load | 320 | 320 |
| bpf | 321 | 321 |
| stub_execveat | 322 | 322 |
| userfaultfd | 323 | 323 |
| membarrier | 324 | 324 |
| mlock2 | 325 | 325 |
| copy_file_range | 326 | 326 |
| preadv2 | 327 | 327 |
| pwritev2 | 328 | 328 |
| pkey_mprotect | 329 | 329 |
| pkey_alloc | 330 | 330 |
| pkey_free | 331 | 331 |
| statx | 332 | 332 |
| io_pgetevents | 333 | 333 |
| rseq | 334 | 334 |
| pidfd_send_signal | 424 | 424 |
| io_uring_setup | 425 | 425 |
| io_uring_enter | 426 | 426 |
| io_uring_register | 427 | 427 |
| open_tree | 428 | 428 |
| move_mount | 429 | 429 |
| fsopen | 430 | 430 |
| fsconfig | 431 | 431 |
| fsmount | 432 | 432 |
| fspick | 433 | 433 |
| pidfd_open | 434 | 434 |
| clone3 | 435 | 435 |
| close_range | 436 | 436 |
| openat2 | 437 | 437 |
| pidfd_getfd | 438 | 438 |
| faccessat2 | 439 | 439 |
| process_madvise | 440 | 440 |
| epoll_pwait2 | 441 | 441 |
| mount_setattr | 442 | 442 |
| quotactl_fd | 443 | 443 |
| landlock_create_ruleset | 444 | 444 |
| landlock_add_rule | 445 | 445 |
| landlock_restrict_self | 446 | 446 |
| memfd_secret | 447 | 447 |
| process_mrelease | 448 | 448 |
| futex_waitv | 449 | 449 |
| set_mempolicy_home_node | 450 | 450 |

### 3.4 字节码分析

从 `xxd` 输出分析关键指令：

```
00000000: 2000 0000 0400 0000 1500 003e 3e00 00c0
```

解析（小端序）：
- `2000` = 0x0020 = 32（可能是指令数或版本）
- `0000 0400` = 后续结构
- `1500` = BPF_JEQ（比较相等跳转）
- `003e` = 跳转偏移
- `3e00 00c0` = 立即数/参数

### 3.5 加载机制

在 `flatpak-run.sh` 中的使用：

```bash
--seccomp 13 \
... \
13< `dirname $0`/flatpak.bpf
```

加载流程：
1. Bash 将 `flatpak.bpf` 文件打开为文件描述符 13
2. `bwrap` 的 `--seccomp 13` 参数指定从 FD 13 读取 BPF 程序
3. `bwrap` 内部调用 `seccomp_program_new()` 读取并验证 BPF 数据
4. 在子进程启动前调用 `seccomp_programs_apply()` 应用过滤器

---

## 4. 关键代码路径与文件引用

### 4.1 本项目内引用

| 引用目标 | 关系 | 说明 |
|---------|------|------|
| `flatpak-run.sh` | 调用方 | 加载此 BPF 文件 |
| `bubblewrap.c` | 处理程序 | 实现 Seccomp 加载逻辑 |

### 4.2 Bubblewrap 源码相关

在 `bubblewrap.c` 中的处理：

```c
// Seccomp 程序链表
DEFINE_LINKED_LIST (SeccompProgram, seccomp_program)

// 从 FD 创建新的 Seccomp 程序
static void
seccomp_program_new (int *fd)
{
  SeccompProgram *self = _seccomp_program_append_new ();
  
  // 读取 BPF 数据...
  if (read (*fd, ... ) < 0)
    die_with_error ("Can't read seccomp data");
    
  // 验证数据对齐
  if (bytes_read % 8 != 0)
    die ("Invalid seccomp data, must be multiple of 8");
}

// 应用所有 Seccomp 程序
static void
seccomp_programs_apply (void)
{
  SeccompProgram *program;
  
  for (program = seccomp_programs; program != NULL; program = program->next)
    {
      // 使用 prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ...)
      // 或 seccomp() 系统调用应用过滤器
    }
}
```

### 4.3 生成工具

此 BPF 文件通常由以下工具生成：

1. **libseccomp**: 高级 Seccomp 库
   ```c
   scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ERRNO(EPERM));
   seccomp_rule_add(ctx, SCMP_ACT_ALLOW, SCMP_SYS(read), 0);
   // ... 添加更多规则
   seccomp_export_bpf(ctx, fd);
   ```

2. **Flatpak 的 seccomp 生成器**: Flatpak 源码中的 `common/flatpak-seccomp.c`

---

## 5. 依赖与外部交互

### 5.1 系统依赖

| 依赖 | 说明 |
|------|------|
| Linux 3.5+ | Seccomp BPF 支持需要内核 3.5 或更高版本 |
| `CONFIG_SECCOMP_FILTER` | 内核编译选项 |
| `CONFIG_SECCOMP` | 基础 Seccomp 支持 |

### 5.2 运行时交互

```
┌─────────────────────────────────────────┐
│              应用进程                    │
│  ┌─────────────────────────────────┐    │
│  │         用户代码                 │    │
│  │    syscall(SYS_read, ...)       │    │
│  └─────────────┬───────────────────┘    │
│                │                        │
│  ┌─────────────▼───────────────────┐    │
│  │      Linux 内核 Seccomp         │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │   BPF 虚拟机执行         │    │    │
│  │  │   flatpak.bpf 程序       │    │    │
│  │  │                         │    │    │
│  │  │   LD [syscall_nr]       │    │    │
│  │  │   JEQ read, allow       │    │    │
│  │  │   JEQ write, allow      │    │    │
│  │  │   ...                   │    │    │
│  │  │   RET DENY              │    │    │
│  │  └─────────────────────────┘    │    │
│  └─────────────┬───────────────────┘    │
│                │                        │
│         允许/拒绝                        │
│                │                        │
│  ┌─────────────▼───────────────────┐    │
│  │      实际系统调用处理           │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| BPF 程序错误 | 错误的 BPF 可能允许危险系统调用 | 使用 libseccomp 等成熟库生成 |
| TOCTOU 攻击 | 加载 BPF 和执行之间的时间窗口 | 在子进程启动前立即应用 |
| 架构差异 | 不同架构系统调用号不同 | 为每个架构生成特定 BPF |
| 新系统调用 | 新内核可能添加危险调用 | 定期更新 BPF 策略 |

### 6.2 边界限制

1. **静态策略**: 预编译 BPF 无法根据运行时条件动态调整
2. **参数检查限制**: 复杂的参数检查可能导致 BPF 程序过大
3. **性能开销**: 每个系统调用都需经过 BPF 虚拟机
4. **调试困难**: 二进制 BPF 难以人工审查

### 6.3 改进建议

#### 6.3.1 生成可审查的源码

```bash
# 使用 libseccomp 生成带注释的 BPF
seccomp-export-bpf --commented -o flatpak.bpf

# 或使用 seccomp-bpf 编译器
bpf_asm -c flatpak.seccomp > flatpak.bpf
```

#### 6.3.2 动态策略

```c
// 使用 seccomp_notify 实现动态策略
seccomp_rule_add(ctx, SCMP_ACT_NOTIFY, SCMP_SYS(open), 0);
// 用户空间代理决定是否允许
```

#### 6.3.3 多层过滤

```bash
# 基础过滤（严格）
--seccomp 10 < base.bpf
# 应用特定过滤（宽松）
--seccomp 11 < app-specific.bpf
```

#### 6.3.4 审计和日志

```c
// 使用 SCMP_ACT_TRACE 记录被阻止的调用
seccomp_rule_add(ctx, SCMP_ACT_TRACE(0), SCMP_SYS(ptrace), 0);
```

### 6.4 验证工具

```bash
# 使用 bpftool 验证 BPF 程序
bpftool prog dump xlated id <id>

# 使用 libseccomp 工具分析
scmp_bpf_disasm flatpak.bpf

# 内核验证
strace -e seccomp ./flatpak-run.sh
```

---

## 附录：相关 CVE

| CVE | 说明 | 与 Seccomp 关系 |
|-----|------|----------------|
| CVE-2016-3135 | 用户命名空间漏洞 | Seccomp 可限制相关调用 |
| CVE-2017-5226 | TIOCSTI 终端注入 | 需配合 Seccomp 或 `--new-session` |
| CVE-2019-5736 | runc 容器逃逸 | 强调 Seccomp 策略更新的重要性 |

---

*文档生成时间: 2026-03-23*
*基于 BPF 字节码分析和 Bubblewrap 源码研究*
