# Bubblewrap Tests 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/vendor/bubblewrap/tests` 是 bubblewrap（bwrap）沙箱工具的测试套件目录。bubblewrap 是一个用于构建无特权容器/沙箱环境的底层工具，被 Flatpak、rpm-ostree 等容器工具使用。该测试目录位于 codex-rs 项目的 vendor 目录中，作为依赖项被引入。

### 1.2 核心职责

该测试目录承担以下关键职责：

1. **功能验证**：验证 bubblewrap 的核心沙箱功能，包括命名空间隔离、挂载操作、权限控制等
2. **安全测试**：测试 seccomp 过滤器、capabilities、用户命名空间等安全机制
3. **集成测试**：验证与外部系统（如 FUSE、SELinux）的交互
4. **回归测试**：防止已修复问题的再次出现（如 CVE-2019-10063）
5. **跨平台兼容**：支持不同内核版本和发行版的兼容性测试

### 1.3 在 codex-rs 项目中的角色

在 codex-rs 项目中，bubblewrap 作为 Linux 沙箱后端被使用：

- `codex-rs/linux-sandbox` 模块依赖 bubblewrap 提供底层沙箱能力
- 测试文件 `landlock.rs` 和 `managed_proxy.rs` 中检测 bubblewrap 可用性并执行相关测试
- 当 bubblewrap 不可用时，测试会被跳过（`should_skip_bwrap_tests()`）

---

## 2. 功能点目的

### 2.1 测试文件功能矩阵

| 测试文件 | 类型 | 主要测试目的 |
|---------|------|-------------|
| `test-run.sh` | Shell | 核心功能集成测试，覆盖挂载、命名空间、权限、环境变量等 |
| `test-seccomp.py` | Python | seccomp 过滤器测试，包括白名单、黑名单、堆叠过滤器 |
| `test-specifying-pidns.sh` | Shell | PID 命名空间指定功能测试 |
| `test-specifying-userns.sh` | Shell | 用户命名空间指定功能测试 |
| `test-utils.c` | C | 单元测试工具函数（字符串处理、路径操作等） |
| `try-syscall.c` | C | 系统调用测试辅助程序，用于 seccomp 测试 |
| `libtest.sh` | Shell | 测试框架库，提供测试基础设施 |
| `libtest-core.sh` | Shell | 核心测试断言库（来自 ostree 项目） |

### 2.2 详细功能点分析

#### 2.2.1 test-run.sh - 核心功能测试

**测试覆盖范围：**

1. **基础功能测试**
   - `--help` 输出验证
   - FUSE 目录绑定挂载（`--bind`）
   - `/proc` 挂载（`--proc`）
   - 网络隔离（`--unshare-net`）

2. **安全权限测试**
   - 不可读文件访问控制（`/etc/shadow`）
   - 符号链接绑定目标（CVE 修复验证）
   - 设备文件创建（`/dev` 下的标准设备）

3. **命名空间测试**
   - `--as-pid-1`：以 PID 1 运行
   - `--info-fd` 和 `--json-status-fd`：状态信息输出
   - 命名空间 ID 信息验证

4. **Capabilities 测试**
   - 非 root 用户 capabilities 检查
   - `--cap-add` 和 `--cap-drop` 功能

5. **进程生命周期测试**
   - `--die-with-parent`：父进程退出时子进程终止
   - 文件锁机制测试

6. **参数解析测试**
   - `--args` 从文件描述符读取参数
   - `--` 分隔符处理

7. **挂载功能测试**
   - 目录绑定挂载（`--bind`）
   - 只读绑定挂载（`--ro-bind`）
   - 设备绑定挂载（`--dev-bind`）
   - tmpfs 挂载（`--tmpfs`）及大小限制（`--size`）
   - Overlay 文件系统（`--overlay`, `--tmp-overlay`, `--ro-overlay`）

8. **权限和所有权测试**
   - `--perms` 权限设置
   - `--chmod` 权限修改
   - 挂载点自动创建的权限验证

9. **环境操作测试**
   - `--setenv` 设置环境变量
   - `--unsetenv` 取消设置环境变量
   - `--clearenv` 清空环境变量
   - `--argv0` 设置程序名

#### 2.2.2 test-seccomp.py - Seccomp 安全测试

**测试目标：** 验证 seccomp BPF 过滤器的正确应用

**测试场景：**

1. **无 seccomp 测试** (`test_no_seccomp`)
   - 验证系统调用在无过滤器时的行为
   - 测试 syscall: chmod, chroot, clone3, ioctl, listen, prctl

2. **白名单测试** (`test_seccomp_allowlist`)
   - 使用 systemd 的 @default、@basic-io、@filesystem-io 系统调用集
   - 验证允许列表外的系统调用被阻止（返回 ENOSYS）
   - 验证允许列表内的系统调用正常执行

3. **黑名单测试** (`test_seccomp_denylist`)
   - 显式阻止特定系统调用（chmod, chroot, prctl, ioctl TIOCSTI）
   - 验证被阻止的系统调用返回 ECONNREFUSED

4. **堆叠过滤器测试** (`test_seccomp_stacked`)
   - 测试多个 seccomp 过滤器的组合效果
   - 验证过滤器添加顺序对结果的影响

5. **无效输入测试** (`test_seccomp_invalid`)
   - 无效文件描述符处理
   - `--seccomp` 与 `--add-seccomp-fd` 互斥验证
   - 无效 seccomp 数据格式处理

**关键系统调用测试集：**
```python
TRY_SYSCALLS = [
    'chmod',
    'chroot', 
    'clone3',
    'ioctl TIOCNOTTY',
    'ioctl TIOCSTI CVE-2019-10063',  # CVE 回归测试
    'ioctl TIOCSTI',
    'listen',
    'prctl',
]
```

#### 2.2.3 test-specifying-pidns.sh - PID 命名空间测试

**测试目的：** 验证 `--pidns` 选项允许加入现有 PID 命名空间

**测试流程：**
1. 创建第一个沙箱，使用 `--unshare-user --unshare-pid`，获取其 PID 命名空间
2. 创建第二个沙箱，使用 `--userns` 和 `--pidns` 加入第一个沙箱的命名空间
3. 验证两个进程在相同的 PID 命名空间中

**关键命令：**
```bash
$RUN --info-fd 42 --unshare-user --unshare-pid sh -c 'readlink /proc/self/ns/pid > sandbox-pidns; cat < donepipe' 42>info.json
$RUN --userns 11 --pidns 12 readlink /proc/self/ns/pid > sandbox2-pidns 11< /proc/$SANDBOX1PID/ns/user 12< /proc/$SANDBOX1PID/ns/pid
```

#### 2.2.4 test-specifying-userns.sh - 用户命名空间测试

**测试目的：** 验证 `--userns` 选项允许加入现有用户命名空间

**测试流程：**
1. 创建第一个沙箱，使用 `--unshare-user`，获取其用户命名空间
2. 创建第二个沙箱，使用 `--userns` 加入第一个沙箱的用户命名空间
3. 验证两个进程在相同的用户命名空间中

#### 2.2.5 test-utils.c - 单元测试

**测试目标：** 测试 `utils.c` 中的辅助函数

**测试函数：**

| 测试函数 | 测试目标 |
|---------|---------|
| `test_n_elements` | `N_ELEMENTS` 宏计算数组元素数量 |
| `test_strconcat` | `strconcat` 字符串连接 |
| `test_strconcat3` | `strconcat3` 三字符串连接 |
| `test_has_prefix` | `has_prefix` 前缀检查 |
| `test_has_path_prefix` | `has_path_prefix` 路径前缀检查 |
| `test_string_builder` | `StringBuilder` 动态字符串构建 |

**路径前缀测试用例：**
```c
{ "/run/host/usr", "/run/host", true },
{ "/run/host/usr", "/run/host/", true },
{ "/run/hostage", "/run/host", false },  // 边界情况
{ "////run///host////usr", "//run//host", true },  // 多斜杠处理
```

#### 2.2.6 try-syscall.c - 系统调用测试辅助

**用途：** 被 `test-seccomp.py` 调用，执行具体的系统调用并返回 errno

**支持的系统调用：**
- `chmod` - 测试文件权限修改
- `chroot` - 测试根目录切换
- `clone3` - 测试新进程创建（Linux 5.3+）
- `ioctl TIOCNOTTY` - 测试终端控制
- `ioctl TIOCSTI` - 测试终端输入注入（CVE-2019-10063 相关）
- `listen` - 测试网络监听
- `prctl` - 测试进程控制

**安全设计：** 使用无效指针（`WRONG_POINTER = (char *) 1`）或无效文件描述符（`-1`）使系统调用安全失败，避免副作用。

---

## 3. 具体技术实现

### 3.1 测试框架架构

#### 3.1.1 TAP 协议支持

测试使用 [TAP (Test Anything Protocol)](https://testanything.org/) 输出格式：

```
ok 1 - Help works
ok 2 - can mount /proc with 
ok 3 - can unshare network, create new /dev with 
...
1..N
```

**辅助函数：**
```bash
ok () {
    test_count=$((test_count + 1))
    echo ok $test_count "$@"
}
ok_skip () {
    ok "# SKIP" "$@"
}
done_testing () {
    echo "1..$test_count"
}
```

#### 3.1.2 测试库分层

```
libtest-core.sh (来自 ostree 项目)
    ↓ 提供基础断言
libtest.sh (bubblewrap 特定)
    ↓ 提供 bubblewrap 测试基础设施
测试脚本 (test-*.sh, test-*.py)
    ↓ 调用 BWRAP 执行测试
bubblewrap 可执行文件
```

### 3.2 关键数据结构

#### 3.2.1 SetupOp 结构体（bubblewrap.c）

```c
typedef struct _SetupOp SetupOp;
struct _SetupOp {
  SetupOpType type;      // 操作类型（绑定挂载、创建目录等）
  const char *source;    // 源路径
  const char *dest;      // 目标路径
  int         fd;        // 文件描述符
  SetupOpFlag flags;     // 标志位
  int         perms;     // 权限模式
  size_t      size;      // 大小（用于 tmpfs）
  SetupOp    *next;      // 链表指针
};
```

**SetupOpType 枚举：**
```c
typedef enum {
  SETUP_BIND_MOUNT,           // --bind
  SETUP_RO_BIND_MOUNT,        // --ro-bind
  SETUP_DEV_BIND_MOUNT,       // --dev-bind
  SETUP_OVERLAY_MOUNT,        // --overlay
  SETUP_TMP_OVERLAY_MOUNT,    // --tmp-overlay
  SETUP_RO_OVERLAY_MOUNT,     // --ro-overlay
  SETUP_OVERLAY_SRC,          // --overlay-src
  SETUP_MOUNT_PROC,           // --proc
  SETUP_MOUNT_DEV,            // --dev
  SETUP_MOUNT_TMPFS,          // --tmpfs
  SETUP_MOUNT_MQUEUE,         // --mqueue
  SETUP_MAKE_DIR,             // --dir
  SETUP_MAKE_FILE,            // --file
  SETUP_MAKE_BIND_FILE,       // --bind-data
  SETUP_MAKE_RO_BIND_FILE,    // --ro-bind-data
  SETUP_MAKE_SYMLINK,         // --symlink
  SETUP_REMOUNT_RO_NO_RECURSIVE,
  SETUP_SET_HOSTNAME,         // --hostname
  SETUP_CHMOD,                // --chmod
} SetupOpType;
```

#### 3.2.2 NsInfo 结构体（命名空间信息）

```c
typedef struct _NsInfo NsInfo;
struct _NsInfo {
  const char *name;      // 命名空间名称
  bool       *do_unshare; // 是否取消共享
  ino_t       id;        // 命名空间 ID
};

static NsInfo ns_infos[] = {
  {"cgroup", &opt_unshare_cgroup, 0},
  {"ipc",    &opt_unshare_ipc,    0},
  {"mnt",    NULL,                0},  // 总是取消共享
  {"net",    &opt_unshare_net,    0},
  {"pid",    &opt_unshare_pid,    0},
  {"uts",    &opt_unshare_uts,    0},
  {NULL,     NULL,                0}
};
```

### 3.3 关键流程

#### 3.3.1 沙箱启动流程

```
1. 解析命令行参数 → 填充 SetupOp 链表
2. 检查权限（setuid 或 capabilities）
3. 创建新的 mount 命名空间（总是执行）
4. 根据需要创建其他命名空间（user, pid, net, ipc, uts, cgroup）
5. 设置 seccomp 过滤器（如果指定）
6. 执行挂载操作（SetupOp 链表）
7. pivot_root 切换到新根文件系统
8. 执行目标程序
```

#### 3.3.2 权限分离机制

bubblewrap 使用权限分离（privilege separation）来安全执行挂载操作：

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

特权操作通过 socket 发送给保留 capabilities 的父进程执行。

### 3.4 Seccomp 实现细节

#### 3.4.1 系统调用集合定义

```python
# 来自 systemd 的 @default 集合
DEFAULT_SET = {'brk', 'clock_gettime', 'execve', 'exit', 'futex', ...}

# 来自 systemd 的 @basic-io 集合  
BASIC_IO_SET = {'close', 'read', 'write', 'lseek', ...}

# 来自 systemd 的 @filesystem-io 集合
FILESYSTEM_SET = {'open', 'stat', 'access', 'chmod', 'chdir', ...}

# 合并允许列表
ALLOWED = DEFAULT_SET | BASIC_IO_SET | FILESYSTEM_SET | {'arch_prctl', 'ioctl', ...}
```

#### 3.4.2 Seccomp 过滤器堆叠

```python
# 白名单过滤器（默认拒绝）
allowlist = seccomp.SyscallFilter(seccomp.ERRNO(errno.ENOSYS))
for syscall in ALLOWED:
    allowlist.add_rule(seccomp.ALLOW, syscall)

# 黑名单过滤器（默认允许）
denylist = seccomp.SyscallFilter(seccomp.ALLOW)
denylist.add_rule(seccomp.ERRNO(errno.ECONNREFUSED), 'chmod')
```

---

## 4. 关键代码路径与文件引用

### 4.1 测试到被测代码的映射

| 测试文件 | 被测代码 | 关键函数/功能 |
|---------|---------|--------------|
| `test-run.sh` | `bubblewrap.c` | 主程序逻辑、参数解析、沙箱设置 |
| `test-run.sh` | `bind-mount.c` | `bind_mount()`, `die_with_bind_result()` |
| `test-run.sh` | `utils.c` | `has_path_prefix()`, `path_equal()` |
| `test-seccomp.py` | `bubblewrap.c` | seccomp 过滤器加载逻辑 |
| `test-specifying-*.sh` | `bubblewrap.c` | 命名空间加入逻辑 |
| `test-utils.c` | `utils.c` | 字符串和路径工具函数 |
| `try-syscall.c` | N/A | 测试辅助程序 |

### 4.2 核心文件路径

```
codex-rs/vendor/bubblewrap/
├── bubblewrap.c          # 主程序（约 116KB）
├── bind-mount.c          # 绑定挂载实现
├── bind-mount.h          # 绑定挂载头文件
├── network.c             # 网络设置（loopback）
├── network.h             # 网络头文件
├── utils.c               # 工具函数（约 21KB）
├── utils.h               # 工具头文件
├── tests/
│   ├── test-run.sh       # 主测试脚本（约 28KB，692行）
│   ├── test-seccomp.py   # seccomp 测试（约 19KB，635行）
│   ├── test-specifying-pidns.sh
│   ├── test-specifying-userns.sh
│   ├── test-utils.c      # 单元测试
│   ├── try-syscall.c     # 系统调用测试辅助
│   ├── libtest.sh        # 测试框架
│   ├── libtest-core.sh   # 核心断言库
│   └── meson.build       # 构建配置
└── meson.build           # 主构建配置
```

### 4.3 关键代码片段

#### 4.3.1 绑定挂载实现（bind-mount.c）

```c
bind_mount_result bind_mount (int           proc_fd,
                              const char   *src,
                              const char   *dest,
                              bind_option_t options,
                              char        **failing_path);
```

**错误码枚举：**
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

#### 4.3.2 路径前缀检查（utils.c）

```c
bool has_path_prefix (const char *str, const char *prefix) {
  while (true) {
    // 跳过连续斜杠
    while (*str == '/') str++;
    while (*prefix == '/') prefix++;
    
    // 前缀结束，匹配成功
    if (*prefix == 0) return true;
    
    // 比较路径元素
    while (*prefix != 0 && *prefix != '/') {
      if (*str != *prefix) return false;
      str++;
      prefix++;
    }
    
    // 确保是完整路径元素匹配
    if (*str != '/' && *str != 0) return false;
  }
}
```

#### 4.3.3 测试断言实现（libtest-core.sh）

```bash
assert_file_has_content () {
    fpath=$1
    shift
    for re in "$@"; do
        if ! grep -q -e "$re" "$fpath"; then
            _fatal_print_file "$fpath" "File '$fpath' doesn't match regexp '$re'"
        fi
    done
}

assert_files_equal() {
    if ! cmp "$1" "$2"; then
        _fatal_print_files "$1" "$2" "File '$1' and '$2' is not equal"
    fi
}
```

---

## 5. 依赖与外部交互

### 5.1 构建依赖

| 依赖 | 用途 | 必需 |
|-----|------|------|
| meson >= 0.49.0 | 构建系统 | 是 |
| libcap | Linux capabilities | 是 |
| libselinux >= 2.1.9 | SELinux 标签支持 | 可选 |
| bash | 测试脚本执行 | 是 |
| python3 | seccomp 测试 | 是 |
| python3-seccomp | seccomp Python 绑定 | 是（用于 seccomp 测试）|

### 5.2 运行时依赖

| 依赖 | 用途 |
|-----|------|
| Linux kernel >= 3.18 | 用户命名空间支持（推荐）|
| setuid root 或 CAP_SYS_ADMIN | 特权操作 |
| FUSE（可选）| FUSE 挂载测试 |
| strace（可选）| 故障注入测试 |

### 5.3 外部系统集成

#### 5.3.1 与 codex-rs 的集成

```rust
// codex-rs/linux-sandbox/tests/suite/landlock.rs
const BWRAP_UNAVAILABLE_ERR: &str = "build-time bubblewrap is not available in this build.";

async fn should_skip_bwrap_tests() -> bool {
    // 检测 bubblewrap 是否可用
    is_bwrap_unavailable_output(&output)
}

#[tokio::test]
async fn bwrap_populates_minimal_dev_nodes() {
    if should_skip_bwrap_tests().await {
        eprintln!("skipping bwrap test: bwrap sandbox prerequisites are unavailable");
        return;
    }
    // 执行 bubblewrap 相关测试
}
```

#### 5.3.2 与 Flatpak 的关系

bubblewrap 最初从 Flatpak 项目分离出来，作为独立的沙箱工具：
- Flatpak 使用 bubblewrap 创建应用沙箱
- `use-as-subproject/` 目录包含 Flatpak 风格的子项目使用示例
- `program_prefix` 选项支持 Flatpak 的命名空间隔离

### 5.4 测试环境变量

| 变量 | 说明 |
|-----|------|
| `BWRAP` | bubblewrap 可执行文件路径 |
| `G_TEST_SRCDIR` | 测试源代码目录 |
| `G_TEST_BUILDDIR` | 测试构建目录 |
| `BWRAP_MUST_WORK` | 如果设置，bubblewrap 必须正常工作 |
| `TEST_SKIP_CLEANUP` | 跳过测试清理（用于调试）|
| `FUSE_DIR` | FUSE 挂载点（自动检测）|

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

1. **CVE-2017-5226**：TIOCSTI ioctl 可导致沙箱逃逸
   - 缓解：使用 `--new-session` 或 seccomp 过滤器阻止 TIOCSTI
   - 测试：`test-seccomp.py` 包含 `ioctl TIOCSTI` 测试

2. **CVE-2019-10063**：64位参数掩码绕过 seccomp 过滤
   - 缓解：更新 seccomp 规则使用掩码匹配
   - 测试：`test-seccomp.py` 包含 `ioctl TIOCSTI CVE-2019-10063` 测试

3. **setuid 攻击面**：当用户命名空间不可用时使用 setuid
   - 缓解：最小化 setuid 代码，使用权限分离
   - 测试：`bwrap_is_suid` 检测和条件跳过

#### 6.1.2 测试限制

1. **内核版本依赖**：某些功能需要特定内核版本
   - unprivileged overlayfs（Linux 5.11+）
   - clone3（Linux 5.3+）

2. **权限要求**：部分测试需要 root 或特定 capabilities
   - setuid 模式测试
   - capabilities 操作测试

3. **环境依赖**：
   - FUSE 测试需要可用的 FUSE 挂载点
   - SELinux 测试需要 SELinux 启用

### 6.2 边界条件

#### 6.2.1 已处理的边界

1. **路径处理**：
   - 多斜杠规范化（`////run///host` → `/run/host`）
   - 空路径元素处理
   - 符号链接边界（`/run/hostage` 不匹配 `/run/host`）

2. **大小限制**：
   - tmpfs 大小上限：`SIZE_MAX / 2`
   - 零大小拒绝（`--size 0` 无效）
   - 溢出检测（`2^64` 被拒绝）

3. **权限边界**：
   - 挂载点自动创建权限（默认 755）
   - 父目录权限继承规则
   - setuid 与非 setuid 模式差异

#### 6.2.2 潜在边界问题

1. **长路径**：测试未覆盖超过 `PATH_MAX` 的路径
2. **特殊字符**：overlay 路径转义测试覆盖 `:,\` 但不覆盖所有特殊字符
3. **资源耗尽**：大文件描述符编号、大量挂载点等压力测试缺失

### 6.3 改进建议

#### 6.3.1 测试覆盖改进

1. **增加模糊测试**：
   ```python
   # 建议：使用 hypothesis 进行属性测试
   from hypothesis import given, strategies as st
   
   @given(st.text())
   def test_path_prefix_properties(path):
       # 验证路径处理属性
   ```

2. **增加并发测试**：
   - 多个 bubblewrap 实例同时运行
   - 命名空间竞争条件测试

3. **增加压力测试**：
   - 大量挂载点（1000+）
   - 深层目录结构（100+ 层）
   - 大参数文件（`--args` 从超大文件读取）

#### 6.3.2 代码质量改进

1. **静态分析集成**：
   - 集成 Coverity、CodeQL 扫描
   - 添加更多编译器警告（已在 meson.build 中启用多项）

2. **测试框架现代化**：
   - 从 TAP 迁移到更现代的测试框架（如 CMocka）
   - 增加测试覆盖率报告（gcov/lcov）

3. **文档改进**：
   - 增加架构文档（当前仅有 README）
   - 增加威胁模型文档
   - 增加贡献者安全指南

#### 6.3.3 功能增强建议

1. **Landlock 支持**：
   - Linux 5.13+ 引入 Landlock LSM
   - 可作为 seccomp 的补充，提供更细粒度的文件系统访问控制

2. **ID 映射增强**：
   - 支持更复杂的 UID/GID 映射
   - 支持 subuid/subgid 范围映射

3. ** cgroup v2 支持增强**：
   - 更完整的 cgroup 资源限制
   - 集成 systemd 资源控制

### 6.4 维护建议

1. **定期同步上游**：
   - bubblewrap 上游活跃开发中
   - 关注安全公告及时更新

2. **CI/CD 改进**：
   - 在多种发行版上测试（Alpine、Debian、Fedora 等）
   - 测试不同内核版本
   - 自动化安全扫描

3. **依赖管理**：
   - 当前使用 vendor 方式嵌入
   - 考虑使用系统包管理器提供的 bubblewrap（如果版本足够新）

---

## 附录：文件清单

### 测试目录文件

```
codex-rs/vendor/bubblewrap/tests/
├── libtest-core.sh              # 核心断言库（190行）
├── libtest.sh                   # 测试框架（115行）
├── meson.build                  # 测试构建配置（72行）
├── test-run.sh                  # 主测试脚本（692行）
├── test-seccomp.py              # seccomp 测试（635行）
├── test-specifying-pidns.sh     # PID 命名空间测试（28行）
├── test-specifying-userns.sh    # 用户命名空间测试（28行）
├── test-utils.c                 # 单元测试（247行）
├── try-syscall.c                # 系统调用辅助（180行）
└── use-as-subproject/           # 子项目使用示例
    ├── assert-correct-rpath.py  # RPATH 验证脚本
    ├── config.h                 # 配置文件
    ├── dummy-config.h.in        # 配置模板
    ├── meson.build              # 子项目构建配置
    └── README                   # 说明文档
```

### 被测代码文件

```
codex-rs/vendor/bubblewrap/
├── bubblewrap.c      # 主程序（约 3500行）
├── bind-mount.c      # 绑定挂载（约 450行）
├── bind-mount.h      # 绑定挂载头文件
├── network.c         # 网络设置（约 200行）
├── network.h         # 网络头文件
├── utils.c           # 工具函数（约 800行）
└── utils.h           # 工具头文件
```

---

*文档生成时间：2026-03-22*
*基于 bubblewrap 版本：0.11.0*
