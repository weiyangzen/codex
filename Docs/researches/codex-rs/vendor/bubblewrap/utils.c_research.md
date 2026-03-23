# utils.c 研究文档

## 文件信息

- **路径**: `codex-rs/vendor/bubblewrap/utils.c`
- **大小**: 21,527 bytes
- **所属项目**: bubblewrap (bwrap) - 沙箱容器工具
- **许可证**: LGPL-2.0-or-later

---

## 场景与职责

`utils.c` 是 bubblewrap 项目的核心工具函数库，提供了沙箱容器运行过程中所需的基础工具函数。该文件在整个 bubblewrap 架构中扮演着"基础设施层"的角色，为上层业务逻辑提供：

1. **错误处理与日志记录**: 统一的错误报告机制和日志输出
2. **内存管理**: 安全的内存分配封装，确保 OOM 时优雅退出
3. **文件系统操作**: 文件读写、目录创建、路径处理等
4. **进程间通信**: Socket 传递 PID/凭证的跨命名空间机制
5. **系统调用封装**: 对 Linux 特定系统调用（如 `pivot_root`, `clone`）的封装
6. **SELinux 支持**: 安全标签相关的辅助函数

该文件被 `bubblewrap.c`（主程序）、`bind-mount.c`（挂载操作）、`network.c`（网络设置）以及测试代码广泛依赖。

---

## 功能点目的

### 1. 日志与错误处理系统

| 函数 | 目的 |
|------|------|
| `bwrap_log()` / `bwrap_logv()` | 统一的日志输出，支持 severity 前缀 |
| `die()` | 无 errno 的致命错误退出 |
| `die_with_error()` | 带 errno 描述的致命错误退出 |
| `die_with_mount_error()` | 专门处理 mount 错误，提供友好提示 |
| `die_oom()` | 内存耗尽时的专用退出 |
| `die_unless_label_valid()` | SELinux 标签验证失败时退出 |

**关键设计**: `bwrap_level_prefix` 全局变量控制是否在日志前添加 `<severity>` 前缀，用于 systemd 日志级别标记。

### 2. 安全内存分配器

| 函数 | 目的 |
|------|------|
| `xmalloc()` | malloc 封装，失败时调用 `die_oom()` |
| `xcalloc()` | calloc 封装，确保零初始化 |
| `xrealloc()` | realloc 封装，禁止 size=0 |
| `xstrdup()` | strdup 封装 |
| `strfreev()` | 字符串数组释放 |

**设计原则**: 所有 `x` 前缀函数保证成功返回，失败时立即终止程序，避免调用方处理 NULL 检查。

### 3. 路径处理函数

| 函数 | 目的 |
|------|------|
| `has_path_prefix()` | 检查路径前缀（处理多斜杠情况） |
| `path_equal()` | 路径相等比较（规范化斜杠） |
| `has_prefix()` | 简单字符串前缀检查 |
| `get_oldroot_path()` | 生成 `/oldroot/` 前缀路径 |
| `get_newroot_path()` | 生成 `/newroot/` 前缀路径 |

**关键算法**: `has_path_prefix()` 特别处理了连续斜杠的情况，例如 `/run/host` 匹配 `////run///host////usr`。

### 4. 文件系统操作

| 函数 | 目的 |
|------|------|
| `fdwalk()` | 遍历进程所有打开的文件描述符 |
| `write_to_fd()` | 可靠地将数据写入 fd（处理 EINTR 和短写） |
| `write_file_at()` | 在指定目录 fd 下写入文件 |
| `create_file()` | 创建文件并写入内容 |
| `ensure_file()` | 确保文件存在（非目录/非链接） |
| `ensure_dir()` | 确保目录存在 |
| `mkdir_with_parents()` | 递归创建目录（类似 `mkdir -p`） |
| `copy_file_data()` | 在两个 fd 间复制数据 |
| `copy_file()` | 复制整个文件 |
| `load_file_data()` | 从 fd 加载文件内容到内存 |
| `load_file_at()` | 从指定目录加载文件 |
| `get_file_mode()` | 获取文件类型模式 |

### 5. 跨命名空间 PID 传递

| 函数 | 目的 |
|------|------|
| `send_pid_on_socket()` | 通过 socket 发送当前进程的 ucred（含 PID） |
| `create_pid_socketpair()` | 创建用于 PID 传递的 socket pair |
| `read_pid_from_socket()` | 从 socket 读取 PID（内核自动转换命名空间） |

**技术原理**: 利用 `SCM_CREDENTIALS` 控制消息，让内核自动填充和转换进程凭证。当进程跨越 PID namespace 时，接收方看到的 PID 是其在自身 namespace 中的视角。

### 6. 系统调用封装

| 函数 | 目的 |
|------|------|
| `raw_clone()` | 直接调用 `clone()` 系统调用（处理 s390/cris 架构差异） |
| `pivot_root()` | 封装 `pivot_root` 系统调用（处理缺失情况） |

### 7. SELinux 支持

| 函数 | 目的 |
|------|------|
| `label_mount()` | 为挂载选项添加 SELinux 上下文 |
| `label_create_file()` | 设置文件创建时的 SELinux 标签 |
| `label_exec()` | 设置执行时的 SELinux 标签 |

**条件编译**: 所有 SELinux 功能通过 `#ifdef HAVE_SELINUX` 控制。

### 8. 字符串构建器 (StringBuilder)

| 函数 | 目的 |
|------|------|
| `strappend()` | 追加字符串 |
| `strappendf()` | 追加格式化字符串 |
| `strappend_escape_for_mount_options()` | 追加并转义挂载选项（转义 `\`, `,`, `:`） |
| `xadd()` / `xmul()` | 安全的 size_t 加法/乘法（溢出检查） |

**应用场景**: 动态构建 overlayfs 挂载选项字符串时需要转义特殊字符。

### 9. 环境变量操作

| 函数 | 目的 |
|------|------|
| `xclearenv()` | 清空所有环境变量 |
| `xsetenv()` | 设置环境变量 |
| `xunsetenv()` | 取消设置环境变量 |

### 10. 字符串工具

| 函数 | 目的 |
|------|------|
| `strconcat()` / `strconcat3()` | 连接 2-3 个字符串 |
| `xasprintf()` | 安全的 asprintf 封装 |
| `readlink_malloc()` | 读取符号链接目标（自动扩容） |

---

## 具体技术实现

### 关键流程 1: PID 跨命名空间传递

```c
// 发送方（子进程在子 PID namespace 中）
void send_pid_on_socket (int sockfd) {
    struct ucred cred;
    cred.pid = getpid();  // 在子 namespace 中的 PID（通常是 1）
    cred.uid = geteuid();
    cred.gid = getegid();
    // 通过 SCM_CREDENTIALS 发送，内核验证并传递
}

// 接收方（父进程在父 PID namespace 中）
int read_pid_from_socket (int sockfd) {
    // 接收到的 cred.pid 是父 namespace 视角下的子进程 PID
    // 内核自动完成了 namespace 转换
}
```

**应用场景**: bubblewrap 使用此机制在创建 PID namespace 后，让父进程获取子进程在父 namespace 中的真实 PID。

### 关键流程 2: 安全的文件描述符遍历

```c
int fdwalk (int proc_fd, int (*cb)(void *data, int fd), void *data) {
    // 优先使用 /proc/self/fd 目录遍历（更高效）
    // 回退到遍历 0 到 sysconf(_SC_OPEN_MAX)
}
```

**用途**: 在 `execve()` 前关闭所有非必要的文件描述符，防止文件描述符泄漏到沙箱内。

### 关键流程 3: 路径前缀匹配算法

```c
bool has_path_prefix (const char *str, const char *prefix) {
    // 1. 跳过所有前导斜杠
    // 2. 逐路径元素比较
    // 3. 确保匹配到完整路径元素（而非子字符串）
    // 例如: /a/prefix 匹配 /a/prefix/foo，但不匹配 /a/prefixfoo
}
```

### 关键数据结构

```c
// 字符串构建器
struct _StringBuilder {
    char * str;      // 缓冲区
    size_t size;     // 总容量
    size_t offset;   // 当前写入位置（也是字符串长度）
};

// 自动清理属性（GCC 扩展）
#define cleanup_free __attribute__((cleanup (cleanup_freep)))
#define cleanup_fd __attribute__((cleanup (cleanup_fdp)))
#define cleanup_strv __attribute__((cleanup (cleanup_strvp)))

// 指针窃取（所有权转移）
static inline void * steal_pointer (void *pp) {
    void **ptr = (void **) pp;
    void *ref = *ptr;
    *ptr = NULL;
    return ref;
}
```

---

## 关键代码路径与文件引用

### 调用关系图

```
bubblewrap.c (主程序)
    ├── utils.h/c (本文件)
    │   ├── 日志: bwrap_log, die_with_error
    │   ├── 内存: xmalloc, xcalloc, xstrdup
    │   ├── 路径: has_path_prefix, get_oldroot_path
    │   ├── 文件: write_file_at, load_file_at, mkdir_with_parents
    │   ├── IPC: send_pid_on_socket, read_pid_from_socket
    │   └── 系统调用: raw_clone, pivot_root
    ├── bind-mount.c
    │   └── 使用 utils 的路径处理和文件操作
    └── network.c
        └── 使用 utils 的日志和错误处理
```

### 核心代码路径

1. **PID namespace 创建与同步** (`bubblewrap.c:3130-3243`)
   - 调用 `raw_clone()` 创建新 namespace
   - 子进程通过 `send_pid_on_socket()` 发送 PID
   - 父进程通过 `read_pid_from_socket()` 获取子进程 PID

2. **pivot_root 操作** (`bubblewrap.c:3352-3446`)
   - 使用 `pivot_root()` 系统调用切换根文件系统
   - 配合 `get_oldroot_path()` / `get_newroot_path()` 管理路径

3. **UID/GID 映射设置** (`bubblewrap.c:996-1012`)
   - 使用 `write_file_at()` 写入 `/proc/[pid]/uid_map` 和 `gid_map`
   - 写入 `/proc/[pid]/setgroups` 控制组权限

4. **文件描述符清理** (`bubblewrap.c:521, 3581`)
   - 使用 `fdwalk()` 遍历并关闭多余 fd

---

## 依赖与外部交互

### 头文件依赖

```c
#include "config.h"           // 编译时配置（HAVE_SELINUX 等）
#include "utils.h"            // 自身头文件
#include <limits.h>           // PATH_MAX, SIZE_MAX
#include <stdint.h>           // 固定宽度整数类型
#include <sys/syscall.h>      // 系统调用号
#include <sys/socket.h>       // socket, SCM_CREDENTIALS
#include <sys/param.h>        // MAX()
#ifdef HAVE_SELINUX
#include <selinux/selinux.h>  // SELinux API
#endif
```

### 外部库

| 库 | 用途 |
|----|------|
| libc | 标准 C 库函数 |
| libselinux (可选) | SELinux 标签管理 |

### 系统调用

| 系统调用 | 用途 |
|----------|------|
| `clone` | 创建新进程和 namespace |
| `pivot_root` | 切换根文件系统 |
| `setenv`/`unsetenv`/`clearenv` | 环境变量操作 |
| `sendmsg`/`recvmsg` | Socket 传递凭证 |
| `openat`/`mkdir`/`stat` | 文件系统操作 |

### 宏定义依赖

- `TEMP_FAILURE_RETRY`: 自动重试被信号中断的系统调用
- `HAVE_SELINUX`: 是否启用 SELinux 支持
- `HAVE_SELINUX_2_3`: libselinux 版本 >= 2.3（const-correct API）

---

## 风险、边界与改进建议

### 已知风险

1. **内存分配失败处理**
   - 当前实现直接调用 `exit(1)`，无法进行资源清理
   - 在沙箱初始化过程中，部分资源可能已分配但未释放

2. **路径处理边界情况**
   - `has_path_prefix()` 对空字符串的处理：`""` 是任何路径的前缀
   - 极长路径（接近 PATH_MAX）可能导致截断风险

3. **SELinux 兼容性**
   - libselinux < 2.3 的 const-correct 问题通过宏定义处理，但可能有遗漏
   - 某些系统上 SELinux 可能处于启用状态但无法设置标签

4. **系统调用失败**
   - `pivot_root()` 在某些系统上可能未实现（返回 ENOSYS）
   - `raw_clone()` 在 s390/cris 架构上的参数顺序特殊处理

### 边界条件

| 场景 | 行为 |
|------|------|
| `xrealloc(ptr, 0)` | 触发 assert 失败 |
| `xstrdup(NULL)` | 触发 assert 失败 |
| `write_to_fd()` 遇到短写 | 设置 errno=ENOSPC 并返回 -1 |
| `load_file_data()` 文件 > SSIZE_MAX/2 | 返回 EFBIG 错误 |
| `readlink_malloc()` 链接目标极长 | 自动扩容直到 SIZE_MAX/2 |

### 改进建议

1. **错误处理增强**
   ```c
   // 建议添加错误回调机制，允许调用方在退出前清理资源
   typedef void (*bwrap_cleanup_handler_t)(void);
   void bwrap_set_cleanup_handler(bwrap_cleanup_handler_t handler);
   ```

2. **路径处理优化**
   - 考虑使用 `realpath()` 或类似机制规范化路径后再比较
   - 添加对相对路径的支持（当前主要处理绝对路径）

3. **内存分配统计**
   - 在调试模式下添加内存分配统计，帮助检测泄漏

4. **SELinux 错误信息**
   - 当前 `die_unless_label_valid()` 直接退出，建议提供更详细的 SELinux 状态诊断

5. **StringBuilder 改进**
   - 当前 `strappend()` 使用 `strncpy`，可以优化为 `memcpy`（已知长度）
   - 添加 `strreset()` 函数用于重置构建器而不释放内存

6. **测试覆盖**
   - `test-utils.c` 已覆盖大部分字符串和路径函数
   - 建议添加对 `fdwalk()`、`send_pid_on_socket()` 等系统级函数的测试

### 安全注意事项

1. **TOCTOU 风险**: `ensure_file()` 和 `ensure_dir()` 存在检查-使用竞争条件，但在 bubblewrap 的使用场景（单线程、受控环境）中风险较低。

2. **符号链接遍历**: `readlink_malloc()` 正确处理了长链接目标，但调用方需要注意循环链接的可能性。

3. **整数溢出**: `xadd()` 和 `xmul()` 提供了溢出检查，但仅在 GCC >= 5 时使用内置函数，旧版本使用手动检查。

---

## 相关文件引用

| 文件 | 关系 |
|------|------|
| `utils.h` | 头文件，声明所有接口 |
| `bubblewrap.c` | 主要调用方，使用几乎所有功能 |
| `bind-mount.c` | 使用路径处理和文件操作 |
| `network.c` | 使用日志和错误处理 |
| `tests/test-utils.c` | 单元测试 |
| `config.h` (生成) | 编译时配置 |
| `meson.build` | 构建配置，定义 HAVE_SELINUX 等 |
