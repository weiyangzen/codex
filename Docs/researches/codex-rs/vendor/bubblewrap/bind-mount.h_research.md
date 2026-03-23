# bind-mount.h 研究文档

## 场景与职责

`bind-mount.h` 是 bubblewrap 项目中绑定挂载模块的公共头文件，定义了 `bind-mount.c` 对外暴露的接口、数据类型和常量。作为模块的 API 契约，该头文件是模块间交互的基础，确保调用者正确使用绑定挂载功能。

## 功能点目的

1. **接口契约**：明确定义模块对外提供的功能
2. **类型安全**：提供强类型的选项和结果枚举
3. **编译时检查**：通过头文件包含确保函数签名匹配
4. **文档化**：通过代码结构自文档化接口用法

## 具体技术实现

### 1. 头文件保护

```c
#pragma once
```

使用现代编译器支持的 `#pragma once` 替代传统的 include guard：
- **优势**：简洁，避免宏命名冲突
- **兼容性**：GCC、Clang、MSVC 均支持
- **注意**：非标准 C，但在实际项目中广泛支持

### 2. 依赖包含

```c
#include "utils.h"
```

`utils.h` 提供了模块所需的通用工具：
- 内存管理函数（`xmalloc`, `xstrdup` 等）
- 路径处理函数（`has_path_prefix`, `path_equal` 等）
- 文件操作函数（`load_file_at`, `readlink_malloc` 等）
- 错误处理宏和类型

### 3. 绑定选项枚举（bind_option_t）

```c
typedef enum {
  BIND_READONLY = (1 << 0),   // 0x01
  BIND_DEVICES = (1 << 2),    // 0x04
  BIND_RECURSIVE = (1 << 3),  // 0x08
} bind_option_t;
```

#### 设计分析

| 标志 | 值 | 含义 | 内核对应 |
|------|-----|------|---------|
| `BIND_READONLY` | 1 << 0 (0x01) | 只读挂载 | `MS_RDONLY` |
| `BIND_DEVICES` | 1 << 2 (0x04) | 允许设备访问 | 无 `MS_NODEV` |
| `BIND_RECURSIVE` | 1 << 3 (0x08) | 递归挂载 | `MS_REC` |

#### 位掩码设计

- 使用位运算允许选项组合：
  ```c
  bind_option_t opts = BIND_READONLY | BIND_RECURSIVE;
  ```

- **注意**：`BIND_DEVICES` 使用位 2（跳过位 1），可能是历史遗留或预留

- **标志检查**（在 `bind-mount.c` 中）：
  ```c
  bool readonly = (options & BIND_READONLY) != 0;
  bool devices = (options & BIND_DEVICES) != 0;
  bool recursive = (options & BIND_RECURSIVE) != 0;
  ```

#### 与内核标志的映射

```
BIND_READONLY  →  MS_RDONLY (挂载时应用)
BIND_DEVICES   →  0 (默认 MS_NODEV，此标志禁用)
BIND_RECURSIVE →  MS_REC (初始挂载时使用)
```

### 4. 挂载结果枚举（bind_mount_result）

```c
typedef enum
{
  BIND_MOUNT_SUCCESS = 0,
  BIND_MOUNT_ERROR_MOUNT,
  BIND_MOUNT_ERROR_REALPATH_DEST,
  BIND_MOUNT_ERROR_REOPEN_DEST,
  BIND_MOUNT_ERROR_READLINK_DEST_PROC_FD,
  BIND_MOUNT_ERROR_FIND_DEST_MOUNT,
  BIND_MOUNT_ERROR_REMOUNT_DEST,
  BIND_MOUNT_ERROR_REMOUNT_SUBMOUNT,
} bind_mount_result;
```

#### 错误码设计

| 错误码 | 场景 | 典型 errno |
|--------|------|-----------|
| `SUCCESS` | 操作成功 | - |
| `ERROR_MOUNT` | 初始挂载失败 | EPERM, ENOENT, ENOTDIR |
| `ERROR_REALPATH_DEST` | 解析目标路径失败 | ENOENT, EACCES, ELOOP |
| `ERROR_REOPEN_DEST` | 重新打开目标失败 | EACCES, ENOENT |
| `ERROR_READLINK_DEST_PROC_FD` | 读取 /proc/self/fd 失败 | - |
| `ERROR_FIND_DEST_MOUNT` | 在 mountinfo 中找不到目标 | EINVAL |
| `ERROR_REMOUNT_DEST` | 重新挂载目标失败 | EPERM, EBUSY |
| `ERROR_REMOUNT_SUBMOUNT` | 重新挂载子挂载失败 | EACCES, EPERM |

#### 设计优点

1. **精确错误定位**：每个错误码对应具体操作
2. **0 表示成功**：符合 C 语言惯例
3. **可扩展性**：可添加新错误码而不破坏 ABI

### 5. 函数声明

#### bind_mount() - 主挂载函数

```c
bind_mount_result bind_mount (int           proc_fd,
                              const char   *src,
                              const char   *dest,
                              bind_option_t options,
                              char        **failing_path);
```

##### 参数分析

| 参数 | 类型 | 说明 |
|------|------|------|
| `proc_fd` | `int` | /proc 文件系统的文件描述符（用于读取 mountinfo） |
| `src` | `const char*` | 源路径（可为 NULL，表示仅重新挂载） |
| `dest` | `const char*` | 目标路径（必须非 NULL） |
| `options` | `bind_option_t` | 挂载选项（位掩码） |
| `failing_path` | `char**` | 输出参数，失败时设置出错路径（可为 NULL） |

##### 调用模式

```c
// 1. 完整绑定挂载（带递归和只读）
char *failing_path = NULL;
result = bind_mount(proc_fd, "/host/path", "/sandbox/path",
                    BIND_RECURSIVE | BIND_READONLY, 
                    &failing_path);

// 2. 仅重新挂载为只读（src=NULL）
result = bind_mount(proc_fd, NULL, "/sandbox/path",
                    BIND_READONLY, 
                    &failing_path);

// 3. 忽略具体失败路径
result = bind_mount(proc_fd, src, dest, options, NULL);
```

#### die_with_bind_result() - 错误处理辅助

```c
void die_with_bind_result (bind_mount_result res,
                           int               saved_errno,
                           const char       *failing_path,
                           const char       *format,
                           ...)
  __attribute__((__noreturn__))
  __attribute__((format (printf, 4, 5)));
```

##### 属性说明

| 属性 | 含义 |
|------|------|
| `__noreturn__` | 函数不返回（调用 exit） |
| `format (printf, 4, 5)` | 第 4 个参数是格式字符串，第 5 个起是参数 |

##### 使用场景

用于在特权分离（privilege separation）上下文中报告致命错误：

```c
bind_mount_result result = bind_mount(...);
if (result != BIND_MOUNT_SUCCESS) {
    die_with_bind_result(result, errno, failing_path,
                         "Can't bind mount %s on %s", src, dest);
}
```

## 关键代码路径与文件引用

### 包含关系

```
bind-mount.h
    └── utils.h
        ├── 标准头文件 (<assert.h>, <errno.h>, ...)
        └── 项目工具函数声明

被包含方：
    ├── bind-mount.c (实现)
    └── bubblewrap.c (调用者)
```

### 调用链

```
bubblewrap.c
    #include "bind-mount.h"
    
    privileged_op() {
        bind_mount_result bind_result;
        char *failing_path = NULL;
        
        case PRIV_SEP_OP_REMOUNT_RO_NO_RECURSIVE:
            bind_result = bind_mount(proc_fd, NULL, arg2, 
                                     BIND_READONLY, &failing_path);
            if (bind_result != BIND_MOUNT_SUCCESS)
                die_with_bind_result(bind_result, errno, failing_path, ...);
            
        case PRIV_SEP_OP_BIND_MOUNT:
            bind_result = bind_mount(proc_fd, arg1, arg2,
                                     BIND_RECURSIVE | flags, &failing_path);
            if (bind_result != BIND_MOUNT_SUCCESS)
                die_with_bind_result(bind_result, errno, failing_path, ...);
    }
```

## 依赖与外部交互

### 编译时依赖

- **C 编译器**：支持 `#pragma once` 和 `__attribute__`
- **utils.h**：提供底层工具函数

### 运行时依赖

- **Linux 内核**：提供 mount 系统调用和 mountinfo 接口
- **libc**：提供标准 C 库函数

### ABI 稳定性

当前设计考虑了 ABI 稳定性：
- 枚举值从 0 开始顺序分配
- 新选项使用新的位
- 新错误码添加到枚举末尾

## 风险、边界与改进建议

### 风险

1. **API 误用风险**
   ```c
   // 危险：未检查返回值
   bind_mount(proc_fd, src, dest, options, NULL);
   
   // 危险：failing_path 未释放（内存泄漏）
   char *path;
   bind_mount(..., &path);  // path 被设置但未释放
   ```

2. **选项组合风险**
   ```c
   // 逻辑矛盾：递归但只读？
   BIND_RECURSIVE | BIND_READONLY
   // 实际上支持，但语义可能令人困惑
   ```

3. **NULL 指针风险**
   - `dest` 必须非 NULL，但头文件未明确文档化
   - `failing_path` 可为 NULL，但调用者可能误解

### 边界

1. **线程安全**：未明确保证线程安全（依赖全局状态如 `bwrap_level_prefix`）
2. **信号安全**：使用 `TEMP_FAILURE_RETRY` 处理 `EINTR`，但非完全信号安全
3. **内存分配**：内部使用 `xmalloc`（失败时退出），无内存限制

### 改进建议

1. **添加文档注释**
   ```c
   /**
    * Perform a bind mount with specified security options.
    *
    * @param proc_fd File descriptor for /proc (for reading mountinfo)
    * @param src Source path, or NULL to remount only
    * @param dest Destination path (must not be NULL)
    * @param options Bitmask of bind_option_t flags
    * @param failing_path Output: path that caused failure (may be NULL)
    * @return BIND_MOUNT_SUCCESS on success, error code otherwise
    * 
    * Note: If failing_path is set, caller must free it with free()
    */
   bind_mount_result bind_mount(int proc_fd, const char *src, 
                                const char *dest, bind_option_t options,
                                char **failing_path);
   ```

2. **添加选项验证**
   ```c
   // 在 bind_mount 实现中添加
   #define BIND_ALL_OPTIONS (BIND_READONLY | BIND_DEVICES | BIND_RECURSIVE)
   assert((options & ~BIND_ALL_OPTIONS) == 0);  // 检测未知选项
   ```

3. **考虑添加 flags 字符串版本**
   ```c
   // 便于调试和日志
   const char *bind_option_to_string(bind_option_t options);
   // 返回 "readonly,recursive" 等
   ```

4. **改进错误码**
   ```c
   // 添加更多上下文
   BIND_MOUNT_ERROR_MOUNT_SRC,      // 源路径问题
   BIND_MOUNT_ERROR_MOUNT_DEST,     // 目标路径问题
   BIND_MOUNT_ERROR_NAMESPACE,      // 命名空间相关问题
   ```

5. **考虑 const 正确性**
   ```c
   // 如果 failing_path 不应被修改，考虑：
   const char **failing_path  // 但这样调用者无法释放...
   ```

6. **版本控制**
   ```c
   // 添加 API 版本宏
   #define BIND_MOUNT_API_VERSION 1
   ```

## 与项目整体的关系

### 模块架构

```
bind-mount 模块
├── bind-mount.h (本文件) - 接口定义
├── bind-mount.c - 实现
└── 调用者
    ├── bubblewrap.c - 主程序
    └── [潜在的测试代码]
```

### 接口设计哲学

bubblewrap 整体采用**显式、最小化**的接口设计：
- 少量精心设计的函数
- 明确的错误码而非魔术数字
- 位掩码选项支持组合
- 输出参数用于详细错误信息

这种设计反映了项目的安全敏感性质：
- 减少 API 误用机会
- 清晰的错误处理路径
- 便于安全审计

## 相关资源

- [C Header File Best Practices](https://en.wikipedia.org/wiki/Header_file)
- [GCC Function Attributes](https://gcc.gnu.org/onlinedocs/gcc/Function-Attributes.html)
- [Linux Kernel Coding Style](https://www.kernel.org/doc/html/latest/process/coding-style.html)
- [Semantic Versioning for C APIs](https://semver.org/)
