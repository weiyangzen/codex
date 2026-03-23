# bind-mount.c 研究文档

## 场景与职责

`bind-mount.c` 是 bubblewrap 项目中负责**绑定挂载（bind mount）**操作的核心模块。绑定挂载是 Linux 沙箱技术的基石，用于将宿主机的文件系统部分映射到沙箱中，同时应用只读、设备限制等安全策略。

该模块处理以下关键场景：
1. 沙箱文件系统构建时的目录映射
2. 递归挂载的权限传播
3. 大小写不敏感文件系统的兼容性处理
4. 挂载标志的精确控制（只读、noexec、nodev 等）

## 功能点目的

### 核心功能

1. **安全绑定挂载**：执行带安全标志的绑定挂载操作
2. **递归挂载处理**：处理子挂载的权限传播
3. **挂载信息解析**：解析 `/proc/self/mountinfo` 获取挂载状态
4. **错误处理**：提供详细的错误诊断和报告

### 安全目标

- 确保挂载操作在指定的安全约束下进行
- 防止通过挂载操作逃逸沙箱
- 正确处理 case-insensitive 文件系统的边缘情况

## 具体技术实现

### 1. 数据结构与类型定义

#### 绑定挂载选项（bind_option_t）
```c
typedef enum {
  BIND_READONLY = (1 << 0),   // 只读挂载
  BIND_DEVICES = (1 << 2),    // 允许设备访问
  BIND_RECURSIVE = (1 << 3),  // 递归挂载
} bind_option_t;
```

#### 挂载结果枚举（bind_mount_result）
```c
typedef enum {
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

详细的错误码设计便于调用者精确诊断问题。

#### 挂载信息结构
```c
typedef struct MountInfo MountInfo;
struct MountInfo {
  char *mountpoint;        // 挂载点路径
  unsigned long options;   // 挂载标志（MS_RDONLY, MS_NODEV 等）
};

typedef MountInfo *MountTab;  // 以 NULL 结尾的数组
```

#### 挂载信息行结构（解析用）
```c
typedef struct MountInfoLine MountInfoLine;
struct MountInfoLine {
  const char *mountpoint;
  const char *options;
  bool covered;            // 是否被父挂载覆盖
  int id;                  // 挂载 ID
  int parent_id;           // 父挂载 ID
  MountInfoLine *first_child;
  MountInfoLine *next_sibling;
};
```

使用树结构表示挂载层次关系，便于处理嵌套挂载。

### 2. 核心函数实现

#### bind_mount() - 主挂载函数

```c
bind_mount_result
bind_mount (int           proc_fd,
            const char   *src,
            const char   *dest,
            bind_option_t options,
            char        **failing_path)
```

**执行流程**：

```
1. 执行初始绑定挂载（如果 src 不为 NULL）
   mount(src, dest, NULL, MS_SILENT | MS_BIND | MS_REC?, NULL)
   
2. 解析目标路径的真实路径
   realpath(dest) → resolved_dest
   
3. 重新打开目标文件（获取 fd）
   open(resolved_dest, O_PATH | O_CLOEXEC) → dest_fd
   
4. 处理大小写不敏感文件系统
   readlink(/proc/self/fd/N) → kernel_case_combination
   
5. 解析挂载信息表
   parse_mountinfo(proc_fd, kernel_case_combination) → mount_tab
   
6. 重新挂载应用安全标志
   mount("none", resolved_dest, NULL, MS_BIND | MS_REMOUNT | new_flags, NULL)
   
7. 递归处理子挂载（如果 BIND_RECURSIVE）
   遍历 mount_tab[1..]，对每个子挂载重新挂载
```

**大小写不敏感处理详解**：

```c
/* If we are in a case-insensitive filesystem, mountinfo might contain a
 * different case combination of the path we requested to mount.
 * This is due to the fact that the kernel, as of the beginning of 2021,
 * populates mountinfo with whatever case combination first appeared in the
 * dcache; kernel developers plan to change this in future so that it
 * reflects the on-disk encoding instead.
 */
dest_proc = xasprintf ("/proc/self/fd/%d", dest_fd);
oldroot_dest_proc = get_oldroot_path (dest_proc);
kernel_case_combination = readlink_malloc (oldroot_dest_proc);
```

这是针对 Windows 子系统（WSL）或 macOS 等大小写不敏感文件系统的兼容性处理。

#### parse_mountinfo() - 挂载信息解析

```c
static MountTab
parse_mountinfo (int  proc_fd,
                 const char *root_mount)
```

**解析流程**：

1. **读取 mountinfo 文件**
   ```c
   mountinfo = load_file_at (proc_fd, "self/mountinfo");
   ```

2. **解析每行数据**
   mountinfo 格式示例：
   ```
   36 35 98:0 /mnt1 /mnt2 rw,noatime master:1 - ext3 /dev/root rw,errors=continue
   (1) (2) (3) (4)   (5)      (6)      (7)   (8) (9)   (10)         (11)
   
   (1) mount ID
   (2) parent ID
   (3) major:minor
   (4) root
   (5) mount point
   (6) mount options
   (7) optional fields
   (8) separator
   (9) filesystem type
   (10) mount source
   (11) super options
   ```

3. **构建挂载树**
   ```c
   for (i = 0; i < n_lines; i++)
   {
     // 建立父子关系
     MountInfoLine *parent = by_id[this->parent_id];
     // 处理覆盖关系
     if (has_path_prefix (this->mountpoint, sibling->mountpoint))
       sibling->covered = true;
   }
   ```

4. **收集可见挂载**
   从 root_mount 开始，收集未被覆盖的挂载点

#### decode_mountoptions() - 挂载选项解码

```c
static unsigned long
decode_mountoptions (const char *options)
```

将字符串选项（如 "rw,noatime"）转换为内核标志位：

```c
static const struct {
  int   flag;
  const char *name;
} flags_data[] = {
  { 0, "rw" },
  { MS_RDONLY, "ro" },
  { MS_NOSUID, "nosuid" },
  { MS_NODEV, "nodev" },
  { MS_NOEXEC, "noexec" },
  { MS_NOATIME, "noatime" },
  { MS_NODIRATIME, "nodiratime" },
  { MS_RELATIME, "relatime" },
  { 0, NULL }
};
```

### 3. 错误处理与报告

#### bind_mount_result_to_string()

将错误码转换为人类可读的描述：

```c
static char *
bind_mount_result_to_string (bind_mount_result res,
                             const char *failing_path,
                             bool *want_errno_p)
```

**错误分类**：
- 挂载相关错误：使用 `mount_strerror()`（处理内核特定错误码）
- 系统调用错误：使用标准 `strerror()`

#### die_with_bind_result()

格式化并输出错误信息，然后退出：

```c
void
die_with_bind_result (bind_mount_result res,
                      int               saved_errno,
                      const char       *failing_path,
                      const char       *format,
                      ...)
```

支持 `--level-prefix` 选项，生成 systemd 兼容的日志格式。

### 4. 辅助函数

#### unescape_inline() - 路径转义解码

mountinfo 中的路径使用八进制转义（如 `\040` 表示空格）：

```c
static char *
unescape_inline (char *escaped)
{
  // \040 → ' '
  *unescaped++ =
    ((escaped[1] - '0') << 6) |
    ((escaped[2] - '0') << 3) |
    ((escaped[3] - '0') << 0);
}
```

#### skip_token() 和 match_token()

mountinfo 解析的辅助函数，用于字段分割和匹配。

## 关键代码路径与文件引用

### 文件依赖关系

```
bind-mount.c
    ├── bind-mount.h (接口定义)
    ├── utils.h (工具函数)
    │   ├── xmalloc, xstrdup (内存管理)
    │   ├── has_path_prefix (路径比较)
    │   ├── path_equal (路径相等)
    │   ├── load_file_at (文件读取)
    │   ├── get_oldroot_path (路径转换)
    │   └── readlink_malloc (符号链接读取)
    └── config.h (编译配置)

被调用方：
    └── bubblewrap.c (主程序)
        └── privileged_op() (特权操作)
```

### 调用链

```
bubblewrap.c:privileged_op()
    └── PRIV_SEP_OP_BIND_MOUNT
        └── bind_mount()
            ├── mount() [初始绑定]
            ├── realpath() [路径解析]
            ├── parse_mountinfo() [挂载信息解析]
            │   ├── load_file_at() [读取 /proc/self/mountinfo]
            │   ├── unescape_inline() [路径解码]
            │   └── decode_mountoptions() [选项解码]
            └── mount() [重新挂载应用标志]

bubblewrap.c:privileged_op()
    └── PRIV_SEP_OP_REMOUNT_RO_NO_RECURSIVE
        └── bind_mount() [src=NULL, BIND_READONLY]
```

## 依赖与外部交互

### 系统调用

| 系统调用 | 用途 | 错误处理 |
|---------|------|---------|
| `mount()` | 执行挂载操作 | 检查返回值，设置 errno |
| `realpath()` | 解析符号链接 | NULL 检查 |
| `open()` | 获取文件描述符 | 返回错误码 |
| `readlink()` | 读取符号链接目标 | 分配内存存储结果 |

### 内核接口

- **`/proc/self/mountinfo`**：读取当前命名空间的挂载信息
- **mount flags**：`MS_BIND`, `MS_REC`, `MS_REMOUNT`, `MS_RDONLY`, `MS_NOSUID`, `MS_NODEV`, `MS_SILENT`

### 外部函数依赖（来自 utils.c）

| 函数 | 用途 |
|------|------|
| `load_file_at()` | 从 /proc 读取 mountinfo |
| `has_path_prefix()` | 检查路径前缀关系 |
| `path_equal()` | 比较路径（大小写不敏感） |
| `get_oldroot_path()` | 转换路径到 oldroot 视角 |
| `readlink_malloc()` | 读取符号链接 |
| `xmalloc`, `xcalloc`, `xstrdup` | 内存分配（失败时退出） |
| `xasprintf()` | 格式化字符串分配 |

## 风险、边界与改进建议

### 安全风险

1. **符号链接攻击**
   - **风险**：攻击者可能通过符号链接操纵挂载目标
   - **缓解**：使用 `realpath()` 解析真实路径，`O_PATH` 重新打开

2. **TOCTOU（Time-of-check to time-of-use）**
   - **风险**：路径检查和挂载操作之间文件系统可能变化
   - **缓解**：通过文件描述符操作，减少竞态窗口

3. **挂载信息竞争**
   - **风险**：读取 mountinfo 和实际挂载之间状态可能变化
   - **缓解**：操作在私有命名空间进行，减少外部干扰

4. **递归挂载性能**
   - **风险**：大量子挂载时性能下降
   - **现状**：线性遍历，每次重新挂载都可能触发内核操作

### 边界情况

1. **大小写不敏感文件系统**
   - 已实现特殊处理，但依赖内核行为（dcache 缓存）
   - 未来内核可能改变行为

2. **挂载点不可访问**
   - 递归处理时忽略 `EACCES` 错误
   - 注释说明："如果无法读取挂载点，则无法重新挂载，但应该是安全的"

3. **内存限制**
   - mountinfo 解析使用 `xcalloc`，大系统可能消耗较多内存
   - 无显式内存限制检查

### 改进建议

1. **添加单元测试**
   ```c
   // 测试用例建议
   - 基本绑定挂载
   - 递归挂载标志传播
   - 大小写不敏感路径处理
   - 错误路径覆盖
   ```

2. **性能优化**
   ```c
   // 当前：逐个重新挂载子挂载
   for (i = 1; mount_tab[i].mountpoint != NULL; i++)
     mount(...)
   
   // 优化：批量处理或使用 mount_setattr（Linux 5.12+）
   ```

3. **增强日志**
   ```c
   // 添加调试日志
   debug("bind_mount: src=%s dest=%s options=%x\n", src, dest, options);
   ```

4. **改进错误信息**
   ```c
   // 当前错误信息较简略
   // 建议添加更多上下文：
   "Can't remount %s readonly: mount flags 0x%lx, current flags 0x%lx"
   ```

5. **文档化挂载传播行为**
   ```c
   /* Note: This does not apply the flags to mounts which are later
    * propagated into this namespace.
    */
   // 应在文档中更详细说明此限制
   ```

6. **处理新的挂载 API**
   ```c
   // Linux 5.2+ 引入 open_tree, move_mount
   // Linux 5.12+ 引入 mount_setattr
   // 这些新 API 可能提供更安全的挂载操作
   ```

## 与项目整体的关系

### 在沙箱构建中的位置

```
沙箱构建流程
├── 创建新命名空间 (CLONE_NEWNS)
├── 挂载 tmpfs 作为新根
├── bind-mount.c:bind_mount() ← 本模块
│   ├── 绑定 /usr (只读)
│   ├── 绑定 /lib (只读)
│   └── 绑定其他必要目录
├── 挂载 proc, dev, tmpfs
└── pivot_root 切换根目录
```

### 安全架构

```
安全层
├── bubblewrap (setuid)
│   └── bind-mount.c (本文件) - 文件系统隔离
├── Linux 内核
│   ├── namespaces (mnt, pid, net, ...)
│   └── seccomp (可选)
└── 调用者 (Flatpak 等)
    └── 定义安全策略
```

## 相关资源

- [Linux mount(2) man page](https://man7.org/linux/man-pages/man2/mount.2.html)
- [proc(5) mountinfo](https://man7.org/linux/man-pages/man5/proc.5.html)
- [Linux kernel mount implementation](https://github.com/torvalds/linux/tree/master/fs)
- [Flatpak sandbox documentation](https://docs.flatpak.org/en/latest/sandbox-permissions.html)
