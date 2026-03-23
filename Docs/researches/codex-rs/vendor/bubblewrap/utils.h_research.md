# utils.h 研究文档

## 文件信息

- **路径**: `codex-rs/vendor/bubblewrap/utils.h`
- **大小**: 6,435 bytes
- **所属项目**: bubblewrap (bwrap) - 沙箱容器工具
- **许可证**: LGPL-2.0-or-later
- **类型**: C 头文件（接口定义）

---

## 场景与职责

`utils.h` 是 bubblewrap 项目的核心工具库头文件，定义了 `utils.c` 中实现的所有公共接口。作为基础设施层的接口契约，它承担以下职责：

1. **接口契约**: 声明所有工具函数的原型、参数和返回值
2. **类型定义**: 定义 `StringBuilder` 等核心数据结构
3. **宏工具**: 提供调试宏、编译器属性宏、辅助宏
4. **编译器抽象**: 处理不同编译器/平台的差异（如 `TEMP_FAILURE_RETRY`）
5. **内存管理抽象**: 定义自动清理属性和指针窃取宏

该头文件被项目内所有 C 源文件包含，是 bubblewrap 代码库中最基础的依赖之一。

---

## 功能点目的

### 1. 调试与日志宏

```c
#if 0
#define debug(...) bwrap_log (LOG_DEBUG, __VA_ARGS__)
#else
#define debug(...)
#endif
```

**目的**: 提供条件编译的调试日志功能。默认关闭（`#if 0`），需要调试时改为 `#if 1` 重新编译。

### 2. 编译器属性宏

| 宏 | 目的 |
|----|------|
| `UNUSED` | 标记未使用参数，避免编译器警告 (`__attribute__((__unused__))`) |
| `N_ELEMENTS(arr)` | 计算数组元素个数 |

### 3. 系统调用重试宏

```c
#ifndef TEMP_FAILURE_RETRY
#define TEMP_FAILURE_RETRY(expression) \
  (__extension__ \
    ({ long int __result; \
       do __result = (long int) (expression); \
       while (__result == -1L && errno == EINTR); \
       __result; }))
#endif
```

**目的**: 自动重试被信号中断的系统调用。使用 GCC 扩展语句表达式，确保类型安全。

### 4. 管道端点常量

```c
#define PIPE_READ_END 0
#define PIPE_WRITE_END 1
```

**目的**: 提高管道操作代码的可读性，避免魔法数字。

### 5. 子收割者常量

```c
#ifndef PR_SET_CHILD_SUBREAPER
#define PR_SET_CHILD_SUBREAPER 36
#endif
```

**目的**: 为旧版本内核头文件提供 `PR_SET_CHILD_SUBREAPER` 的备用定义（Linux 3.4+ 引入）。

### 6. 日志与错误处理接口

```c
extern bool bwrap_level_prefix;  // 控制日志格式

void  bwrap_log (int severity, const char *format, ...) 
    __attribute__((format (printf, 2, 3)));

#define warn(...) bwrap_log (LOG_WARNING, __VA_ARGS__)

// 致命错误处理函数（noreturn）
void die_with_error (const char *format, ...) 
    __attribute__((__noreturn__)) __attribute__((format (printf, 1, 2)));
void die_with_mount_error (const char *format, ...) 
    __attribute__((__noreturn__)) __attribute__((format (printf, 1, 2)));
void die (const char *format, ...) 
    __attribute__((__noreturn__)) __attribute__((format (printf, 1, 2)));
void die_oom (void) __attribute__((__noreturn__));
void die_unless_label_valid (const char *label);
```

**设计要点**:
- `__attribute__((format (printf, ...)))`: 启用编译器格式字符串检查
- `__attribute__((__noreturn__))`: 告知编译器函数不返回，优化调用点代码

### 7. 进程控制接口

```c
void fork_intermediate_child (void);
```

**目的**: 创建中间子进程并退出父进程，用于 PID namespace 设置。

### 8. 内存管理接口

```c
void *xmalloc (size_t size);
void *xcalloc (size_t nmemb, size_t size);
void *xrealloc (void *ptr, size_t size);
char *xstrdup (const char *str);
void strfreev (char **str_array);
```

**约定**: 所有 `x` 前缀函数保证成功返回，失败时调用 `die_oom()` 终止程序。

### 9. 环境变量接口

```c
void xclearenv (void);
void xsetenv (const char *name, const char *value, int overwrite);
void xunsetenv (const char *name);
```

### 10. 字符串工具接口

```c
char *strconcat (const char *s1, const char *s2);
char *strconcat3 (const char *s1, const char *s2, const char *s3);
char *xasprintf (const char *format, ...) 
    __attribute__((format (printf, 1, 2)));
bool has_prefix (const char *str, const char *prefix);
```

### 11. 路径处理接口

```c
bool has_path_prefix (const char *str, const char *prefix);
bool path_equal (const char *path1, const char *path2);
char *get_oldroot_path (const char *path);
char *get_newroot_path (const char *path);
char *readlink_malloc (const char *pathname);
```

### 12. 文件描述符遍历接口

```c
int fdwalk (int proc_fd, 
            int (*cb)(void *data, int fd), 
            void *data);
```

**用途**: 遍历进程所有打开的文件描述符，执行回调函数。

### 13. 文件操作接口

```c
// 文件内容操作
char *load_file_data (int fd, size_t *size);
char *load_file_at (int dirfd, const char *path);
int write_file_at (int dirfd, const char *path, const char *content);
int write_to_fd (int fd, const char *content, ssize_t len);

// 文件复制
int copy_file_data (int sfd, int dfd);
int copy_file (const char *src_path, const char *dst_path, mode_t mode);

// 文件创建
int create_file (const char *path, mode_t mode, const char *content);
int ensure_file (const char *path, mode_t mode);
int ensure_dir (const char *path, mode_t mode);
int mkdir_with_parents (const char *pathname, mode_t mode, bool create_last);
int get_file_mode (const char *pathname);
```

### 14. 跨命名空间 PID 传递接口

```c
void create_pid_socketpair (int sockets[2]);
void send_pid_on_socket (int socket);
int read_pid_from_socket (int socket);
```

**核心机制**: 使用 `SCM_CREDENTIALS` 控制消息在 socket 上传递进程凭证，内核自动处理 namespace 转换。

### 15. 系统调用封装接口

```c
int raw_clone (unsigned long flags, void *child_stack);
int pivot_root (const char *new_root, const char *put_old);
```

**注意**: `raw_clone()` 直接调用系统调用，绕过 glibc 封装；`pivot_root()` 处理系统调用缺失的情况。

### 16. SELinux 标签接口

```c
char *label_mount (const char *opt, const char *mount_label);
int label_exec (const char *exec_label);
int label_create_file (const char *file_label);
```

### 17. 挂载错误处理

```c
const char *mount_strerror (int errsv);
```

**特殊处理**: 将 `ENOSPC` 错误解释为 "Limit exceeded" 并提供检查 `/proc/sys/fs/mount-max` 的提示。

### 18. 自动清理属性（RAII）

```c
// 清理函数
static inline void cleanup_freep (void *p);
static inline void cleanup_strvp (void *p);
static inline void cleanup_fdp (int *fdp);

// 属性宏
#define cleanup_free __attribute__((cleanup (cleanup_freep)))
#define cleanup_fd __attribute__((cleanup (cleanup_fdp)))
#define cleanup_strv __attribute__((cleanup (cleanup_strvp)))
```

**用法示例**:
```c
cleanup_free char *buffer = xmalloc(1024);
cleanup_fd int fd = open("file", O_RDONLY);
// 函数退出时自动释放 buffer 和关闭 fd
```

### 19. 指针窃取（所有权转移）

```c
static inline void * steal_pointer (void *pp);

// 类型安全包装
#define steal_pointer(pp) \
  (0 ? (*(pp)) : (steal_pointer) (pp))
```

**目的**: 将指针从变量中取出并置 NULL，实现所有权转移。宏中的 `0 ? (*(pp))` 用于类型检查。

### 20. 字符串构建器类型

```c
typedef struct _StringBuilder StringBuilder;

struct _StringBuilder {
  char * str;      // 缓冲区指针
  size_t size;     // 缓冲区总容量
  size_t offset;   // 当前写入位置（字符串长度）
};

// 操作函数
void strappend (StringBuilder *dest, const char *src);
void strappendf (StringBuilder *dest, const char *fmt, ...);
void strappend_escape_for_mount_options (StringBuilder *dest, const char *src);
```

**设计特点**: 动态扩容，始终保持 null-terminated，offset 指向 null 字节位置便于下次追加。

---

## 关键代码路径与文件引用

### 包含关系

```
utils.h
    ├── <assert.h>
    ├── <dirent.h>
    ├── <errno.h>
    ├── <fcntl.h>
    ├── <stdarg.h>
    ├── <stdbool.h>
    ├── <stdio.h>
    ├── <stdlib.h>
    ├── <string.h>
    ├── <syslog.h>
    ├── <unistd.h>
    ├── <sys/types.h>
    └── <sys/stat.h>
```

### 被包含关系

```
bubblewrap.c
bind-mount.c
network.c
utils.c
tests/test-utils.c
```

### 关键使用场景

1. **自动清理属性的使用** (`bubblewrap.c` 各处)
   ```c
   cleanup_free char *uid_map = xasprintf("%d %d 1\n", opt_sandbox_uid, real_uid);
   cleanup_fd int dir_fd = openat(AT_FDCWD, dir, O_RDONLY | O_NONBLOCK | O_DIRECTORY | O_CLOEXEC);
   ```

2. **StringBuilder 的使用** (`bind-mount.c` 构建挂载选项)
   ```c
   StringBuilder sb = {0};
   strappend_escape_for_mount_options(&sb, source);
   strappend(&sb, ",");
   strappend_escape_for_mount_options(&sb, dest);
   ```

3. **指针窃取的使用** (`utils.c` 内部)
   ```c
   cleanup_free char *data = xmalloc(len);
   // ... 填充数据 ...
   return steal_pointer(&data);  // 转移所有权给调用方
   ```

---

## 依赖与外部交互

### 标准库依赖

| 头文件 | 用途 |
|--------|------|
| `<assert.h>` | `assert()` 宏 |
| `<dirent.h>` | 目录遍历（`DIR`, `struct dirent`） |
| `<errno.h>` | 错误码定义 |
| `<fcntl.h>` | 文件控制选项（`O_RDONLY`, `O_CLOEXEC` 等） |
| `<stdarg.h>` | 可变参数列表 |
| `<stdbool.h>` | `bool`, `true`, `false` |
| `<stdio.h>` | 标准 I/O |
| `<stdlib.h>` | 内存分配、进程控制 |
| `<string.h>` | 字符串操作 |
| `<syslog.h>` | 日志级别常量（`LOG_ERR`, `LOG_WARNING` 等） |
| `<unistd.h>` | UNIX 标准函数 |
| `<sys/types.h>` | 系统类型定义 |
| `<sys/stat.h>` | 文件状态（`struct stat`, `mode_t` 等） |

### 编译器特性依赖

| 特性 | 用途 |
|------|------|
| `__attribute__((cleanup(...)))` | GCC/Clang 的变量清理属性 |
| `__attribute__((format(printf, ...)))` | 格式字符串检查 |
| `__attribute__((noreturn))` | 无返回函数标记 |
| `__extension__` | 允许 GCC 扩展语法 |
| `({ ... })` | GCC 语句表达式 |

### 平台兼容性

- **Linux 特有**: `pivot_root`, `raw_clone` 等系统调用封装
- **POSIX 兼容**: 大部分文件操作、进程控制
- **架构差异**: `raw_clone` 在 s390/cris 上参数顺序不同（在 `.c` 文件中处理）

---

## 风险、边界与改进建议

### 宏定义风险

1. **`TEMP_FAILURE_RETRY` 的副作用**
   ```c
   // 潜在问题：expression 被多次求值
   TEMP_FAILURE_RETRY(some_function_with_side_effect());
   ```
   **建议**: 文档中明确警告 expression 不应有副作用。

2. **`N_ELEMENTS` 的误用风险**
   ```c
   int *ptr = arr;
   N_ELEMENTS(ptr);  // 错误！计算的是指针大小而非数组
   ```
   **现状**: 这是 C 语言的固有限制，无法完全避免。

3. **`debug` 宏的条件编译**
   ```c
   // 当前实现需要手动修改源码切换
   #if 0  // 改为 1 启用调试
   ```
   **建议**: 考虑使用编译时定义（`-DDEBUG`）控制。

### 类型安全考虑

1. **`steal_pointer` 的类型擦除**
   ```c
   // 宏包装提供了类型检查，但底层仍是 void*
   #define steal_pointer(pp) (0 ? (*(pp)) : (steal_pointer) (pp))
   ```
   **注意**: 三元表达式 `0 ? (*(pp))` 永不执行，仅用于类型检查。

2. **`cleanup_freep` 的 void** 转换
   ```c
   static inline void cleanup_freep (void *p) {
     void **pp = (void **) p;  // 类型擦除
   ```
   **风险**: 如果传入非指针变量的地址，会导致未定义行为。

### 可移植性限制

1. **自动清理属性的编译器依赖**
   - 仅 GCC/Clang 支持 `__attribute__((cleanup(...)))`
   - MSVC 不支持，但 bubblewrap 是 Linux 专用工具

2. **`TEMP_FAILURE_RETRY` 的 GCC 扩展依赖**
   - 使用语句表达式 `({ ... })`，非标准 C
   - 使用 `__extension__` 抑制警告

### 接口设计建议

1. **添加 `cleanup_closep` 别名**
   ```c
   // 当前使用 cleanup_fd，但语义上是 close
   #define cleanup_close cleanup_fd
   ```

2. **StringBuilder 初始化宏**
   ```c
   // 建议添加
   #define STRING_BUILDER_INIT { NULL, 0, 0 }
   // 或
   #define STRING_BUILDER_INITIALIZER {0}
   ```

3. **错误码枚举**
   ```c
   // 建议为文件操作添加统一错误码
   typedef enum {
     BWRAP_OK = 0,
     BWRAP_ERROR_NOMEM,
     BWRAP_ERROR_IO,
     BWRAP_ERROR_INVALID,
   } BwrapError;
   ```

4. **函数文档注释**
   ```c
   /**
    * send_pid_on_socket: Send current process credentials over socket
    * @sockfd: Unix domain socket
    *
    * Sends pid/uid/gid via SCM_CREDENTIALS. The kernel translates
    * the pid to the receiver's pid namespace.
    *
    * Dies on error.
    */
   void send_pid_on_socket (int sockfd);
   ```

### 测试覆盖建议

当前 `test-utils.c` 已覆盖：
- `N_ELEMENTS`
- `strconcat` / `strconcat3`
- `has_prefix`
- `has_path_prefix`
- `StringBuilder`

**建议补充**:
- `path_equal` 的边界情况
- `readlink_malloc` 的错误处理
- `cleanup_*` 宏的功能验证
- `steal_pointer` 的所有权转移语义

---

## 相关文件引用

| 文件 | 关系 |
|------|------|
| `utils.c` | 实现文件，包含所有函数定义 |
| `bubblewrap.c` | 主要调用方 |
| `bind-mount.c` | 使用路径和字符串工具 |
| `network.c` | 使用日志和错误处理 |
| `tests/test-utils.c` | 单元测试 |
