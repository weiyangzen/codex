# Bubblewrap Demos 目录深度研究文档

## 目录信息

- **目标路径**: `codex-rs/vendor/bubblewrap/demos/`
- **父项目**: bubblewrap (bwrap) - 低权限 Linux 沙箱工具
- **在 codex-rs 中的角色**: 作为 vendored 依赖，被 `linux-sandbox` crate 用于构建时编译集成

---

## 1. 场景与职责

### 1.1 目录定位

`demos/` 目录是 bubblewrap 项目官方提供的**示例脚本集合**，用于演示如何使用 `bwrap` 命令行工具构建不同类型的沙箱环境。这些脚本既是学习材料，也是实际使用中的参考实现。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **教学演示** | 展示 bubblewrap 的核心功能和最佳实践 |
| **快速启动模板** | 为开发者提供可复用的沙箱配置模式 |
| **功能验证** | 演示高级特性如 seccomp、user namespace 等 |
| **集成参考** | 展示如何与外部工具（如 Flatpak）集成 |

### 1.3 在 codex-rs 项目中的上下文

在 codex-rs 项目中，bubblewrap 作为 **vendored 依赖** 存在：

- **构建时集成**: `linux-sandbox/build.rs` 在编译时将 bubblewrap C 源码编译为静态库
- **FFI 调用**: `linux-sandbox/src/vendored_bwrap.rs` 通过 FFI 调用 `bwrap_main` 函数
- **沙箱执行**: codex 使用 bubblewrap 作为 Linux 平台上的默认沙箱机制，为代码执行提供隔离环境

```
codex-rs/
├── vendor/bubblewrap/          # vendored bubblewrap 源码
│   ├── bubblewrap.c            # 主程序源码
│   ├── demos/                  # 本研究目标目录
│   └── ...
├── linux-sandbox/
│   ├── build.rs                # 编译 vendored bubblewrap
│   └── src/vendored_bwrap.rs   # FFI 封装层
└── ...
```

---

## 2. 功能点目的

### 2.1 文件清单与功能概览

| 文件 | 类型 | 功能目的 |
|------|------|----------|
| `bubblewrap-shell.sh` | Bash 脚本 | 演示基础沙箱环境，复用主机 `/usr` 但隔离 `/tmp`, `/home`, `/var` 等 |
| `flatpak-run.sh` | Bash 脚本 | 演示如何运行 Flatpak 应用，展示完整的桌面应用沙箱配置 |
| `flatpak.bpf` | 二进制数据 | seccomp BPF 规则文件，用于 `flatpak-run.sh` 的系统调用过滤 |
| `userns-block-fd.py` | Python 脚本 | 演示 `--userns-block-fd` 和 `--info-fd` 高级特性，展示外部 UID/GID 映射 |

### 2.2 各文件详细分析

#### 2.2.1 bubblewrap-shell.sh - 基础沙箱演示

**目的**: 创建一个最小但功能完整的交互式沙箱 shell 环境。

**核心特性**:
- 复用主机 `/usr` 目录（只读绑定挂载）
- 创建独立的 `/tmp`, `/var`, `/run` 目录
- 隔离 `/home` 目录（不共享，保护用户数据）
- 设置最小化的 `/etc/passwd` 和 `/etc/group`
- 使用 `--unshare-all` 创建所有可用的 namespace
- 保留网络访问 (`--share-net`)

**安全设计**:
```bash
# 不共享 /home 是故意设计的，防止沙箱内访问用户主目录
# 如需共享，应显式绑定特定子目录
```

#### 2.2.2 flatpak-run.sh - 桌面应用沙箱

**目的**: 演示如何为 Flatpak 应用构建生产级沙箱环境。

**核心特性**:
- 绑定 Flatpak 运行时和应用文件
- 完整的 D-Bus、X11、GPU (DRI) 支持
- 使用 seccomp BPF 进行系统调用过滤
- 精细的 XDG 目录配置（Cache/Config/Data 分离）
- 环境变量完整配置

**关键配置项**:
```bash
--ro-bind ~/.local/share/flatpak/runtime/... /usr  # 运行时
--ro-bind ~/.local/share/flatpak/app/... /app      # 应用文件
--dev-bind /dev/dri /dev/dri                       # GPU 访问
--bind /tmp/.X11-unix/X0 /tmp/.X11-unix/X99        # X11 显示
--seccomp 13                                       # seccomp 过滤
```

#### 2.2.3 flatpak.bpf - Seccomp 规则

**目的**: 为 Flatpak 应用提供系统调用过滤。

**技术细节**:
- 格式: 编译后的 cBPF (classic BPF) 程序
- 生成方式: 通常使用 `seccomp_export_bpf` 从 libseccomp 导出
- 作用: 限制沙箱内进程可使用的系统调用，减少攻击面

**内容分析** (通过 xxd 查看):
```
00000000: 2000 0000 0400 0000 1500 003e 3e00 00c0   ..........>>...
```
- 这是标准的 BPF 指令序列
- 包含加载、跳转、返回等操作码
- 具体规则需反汇编分析，但通常包括：
  - 允许基本文件操作
  - 允许内存管理调用
  - 禁止危险的系统调用（如 mount, pivot_root 等）

#### 2.2.4 userns-block-fd.py - 高级 UID/GID 映射

**目的**: 演示如何使用 `--userns-block-fd` 和 `--info-fd` 实现外部 UID/GID 映射。

**使用场景**:
- 当需要非特权用户创建用户命名空间时
- 当需要自定义 UID/GID 映射（而非默认的 0->当前用户）
- 当需要与 `newuidmap`/`newgidmap` 工具配合时

**工作流程**:
```
父进程                    子进程 (bwrap)
  |                          |
  |-- fork() --------------->|
  |                          |-- 创建 namespace
  |                          |-- 通过 --info-fd 发送 child-pid
  |<-- 接收 child-pid -------|
  |-- newuidmap $child_pid   |
  |-- newgidmap $child_pid   |
  |-- 写入 userns-block-fd ->|
  |                          |-- 继续执行
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 bubblewrap 执行流程

```
main()
├── 解析命令行参数
├── 验证参数组合（如 --userns-block-fd 需要 --unshare-user）
├── clone() / unshare() 创建 namespaces
├── 设置 UID/GID 映射
├── 挂载文件系统（按参数顺序执行）
├── 应用 seccomp 规则
├── 等待 block-fd（如果指定）
└── execve() 执行目标程序
```

#### 3.1.2 --userns-block-fd 实现机制

**源码位置**: `bubblewrap.c` 第 3206-3210 行

```c
if (opt_userns_block_fd != -1)
  {
    char b[1];
    (void) TEMP_FAILURE_RETRY (read (opt_userns_block_fd, b, 1));
    close (opt_userns_block_fd);
  }
```

**机制说明**:
1. bwrap 创建用户命名空间后，在设置 UID/GID 映射前暂停
2. 通过 `--info-fd` 将 child-pid 发送给父进程
3. 父进程（如 Python 脚本）调用 `newuidmap`/`newgidmap` 设置映射
4. 父进程向 `userns-block-fd` 写入数据，解除阻塞
5. bwrap 继续执行，此时 UID/GID 映射已完成

#### 3.1.3 --info-fd JSON 输出格式

**源码位置**: `bubblewrap.c` 第 3190-3196 行

```c
if (opt_info_fd != -1)
  {
    cleanup_free char *output = xasprintf ("{\n    \"child-pid\": %i", pid);
    dump_info (opt_info_fd, output, true);
    namespace_ids_write (opt_info_fd, false);
    dump_info (opt_info_fd, "\n}\n", true);
    close (opt_info_fd);
  }
```

**输出示例**:
```json
{
    "child-pid": 12345,
    "cgroup-namespace": 1234567890,
    "ipc-namespace": 1234567891,
    "mnt-namespace": 1234567892,
    "net-namespace": 1234567893,
    "pid-namespace": 1234567894,
    "uts-namespace": 1234567895
}
```

### 3.2 数据结构

#### 3.2.1 SetupOp - 挂载操作链表

```c
typedef enum {
  SETUP_BIND_MOUNT,
  SETUP_RO_BIND_MOUNT,
  SETUP_DEV_BIND_MOUNT,
  SETUP_OVERLAY_MOUNT,
  SETUP_TMP_OVERLAY_MOUNT,
  SETUP_RO_OVERLAY_MOUNT,
  SETUP_OVERLAY_SRC,
  SETUP_MOUNT_PROC,
  SETUP_MOUNT_DEV,
  SETUP_MOUNT_TMPFS,
  SETUP_MOUNT_MQUEUE,
  SETUP_MAKE_DIR,
  SETUP_MAKE_FILE,
  SETUP_MAKE_BIND_FILE,
  SETUP_MAKE_RO_BIND_FILE,
  SETUP_MAKE_SYMLINK,
  SETUP_REMOUNT_RO_NO_RECURSIVE,
  SETUP_SET_HOSTNAME,
  SETUP_CHMOD,
} SetupOpType;

typedef struct _SetupOp
{
  SetupOpType type;
  const char *source;
  const char *dest;
  int         fd;
  SetupOpFlag flags;
  int         perms;
  size_t      size;
  SetupOp    *next;
} SetupOp;
```

#### 3.2.2 NsInfo - 命名空间信息

```c
typedef struct _NsInfo NsInfo;

struct _NsInfo {
  const char *name;
  bool       *do_unshare;
  ino_t       id;
};

static NsInfo ns_infos[] = {
  {"cgroup", &opt_unshare_cgroup, 0},
  {"ipc",    &opt_unshare_ipc,    0},
  {"mnt",    NULL,                0},
  {"net",    &opt_unshare_net,    0},
  {"pid",    &opt_unshare_pid,    0},
  {"uts",    &opt_unshare_uts,    0},
  {NULL,     NULL,                0}
};
```

### 3.3 协议与接口

#### 3.3.1 命令行接口

| 选项 | 说明 |
|------|------|
| `--unshare-all` | 创建所有可用的 namespace |
| `--unshare-user` | 创建用户命名空间 |
| `--unshare-pid` | 创建 PID 命名空间 |
| `--unshare-net` | 创建网络命名空间 |
| `--bind SRC DEST` | 绑定挂载 |
| `--ro-bind SRC DEST` | 只读绑定挂载 |
| `--dev-bind SRC DEST` | 允许设备访问的绑定挂载 |
| `--proc /proc` | 挂载 proc 文件系统 |
| `--dev /dev` | 挂载 dev 文件系统（最小化设备集） |
| `--tmpfs /path` | 挂载 tmpfs |
| `--symlink SRC DEST` | 创建符号链接 |
| `--seccomp FD` | 从文件描述符加载 seccomp 规则 |
| `--userns-block-fd FD` | 阻塞等待 UID/GID 映射 |
| `--info-fd FD` | 输出沙箱信息 JSON |
| `--json-status-fd FD` | 输出状态信息（JSON Lines 格式） |

#### 3.3.2 特权分离机制

bubblewrap 使用 **特权分离** 设计：

1. **特权父进程**: 初始以特权运行（或 setuid root），执行需要特权的操作
2. **特权降级**: 完成特权操作后，立即丢弃所有 capabilities
3. **子进程**: 在沙箱内以非特权运行

**关键代码** (`bubblewrap.c` 第 3184-3185 行):
```c
/* We don't need any privileges in the launcher, drop them immediately. */
drop_privs (false, false);
```

---

## 4. 关键代码路径与文件引用

### 4.1 bubblewrap 核心源码

| 文件 | 功能 |
|------|------|
| `bubblewrap.c` | 主程序，包含命令解析、namespace 创建、挂载逻辑 |
| `bind-mount.c` | 绑定挂载相关工具函数 |
| `network.c` | 网络 namespace 设置 |
| `utils.c` | 通用工具函数 |

### 4.2 demos 目录文件引用关系

```
demos/
├── bubblewrap-shell.sh
│   └── 引用: bwrap (系统命令)
├── flatpak-run.sh
│   ├── 引用: bwrap (系统命令)
│   └── 引用: flatpak.bpf (seccomp 规则)
├── flatpak.bpf
│   └── 被引用: flatpak-run.sh
└── userns-block-fd.py
    └── 引用: bwrap (系统命令)
```

### 4.3 codex-rs 中的引用

| 文件 | 引用内容 |
|------|----------|
| `linux-sandbox/build.rs` | 编译 `vendor/bubblewrap/*.c` |
| `linux-sandbox/src/vendored_bwrap.rs` | FFI 调用 `bwrap_main` |
| `linux-sandbox/tests/suite/landlock.rs` | 测试 bubblewrap 集成 |

### 4.4 关键代码行号

| 功能 | 文件 | 行号 |
|------|------|------|
| `--userns-block-fd` 处理 | `bubblewrap.c` | 2346-2361, 2944-2947, 3206-3211 |
| `--info-fd` 处理 | `bubblewrap.c` | 2366-2381, 3190-3196 |
| `--json-status-fd` 处理 | `bubblewrap.c` | 2394-2401, 3198-3203 |
| seccomp 应用 | `bubblewrap.c` | 626, 283-297 |
| UID/GID 映射 | `bubblewrap.c` | 3164-3177, 3487-3489 |
| namespace 创建 | `bubblewrap.c` | 2870-3500+ |

---

## 5. 依赖与外部交互

### 5.1 系统依赖

| 依赖 | 用途 |
|------|------|
| Linux Kernel >= 3.10 | namespace、seccomp 支持 |
| libcap | POSIX capabilities 管理 |
| newuidmap/newgidmap | 外部 UID/GID 映射（可选） |
| Python 3 | 运行 `userns-block-fd.py` 演示 |

### 5.2 内核特性依赖

| 特性 | 配置选项 |
|------|----------|
| User Namespaces | CONFIG_USER_NS |
| PID Namespaces | CONFIG_PID_NS |
| Network Namespaces | CONFIG_NET_NS |
| IPC Namespaces | CONFIG_IPC_NS |
| UTS Namespaces | CONFIG_UTS_NS |
| Cgroup Namespaces | CONFIG_CGROUP_NS |
| Seccomp | CONFIG_SECCOMP, CONFIG_SECCOMP_FILTER |

### 5.3 与 Flatpak 的关系

- bubblewrap 最初从 Flatpak 的 `xdg-app-helper` 分离出来
- Flatpak 使用 bubblewrap 作为底层沙箱实现
- `flatpak-run.sh` 演示了如何手动复现 Flatpak 的沙箱配置

### 5.4 codex-rs 集成架构

```
┌─────────────────────────────────────────────────────────────┐
│                    codex-cli / codex-tui                     │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                   linux-sandbox crate                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           vendored_bwrap.rs (FFI 层)                  │   │
│  │  - exec_vendored_bwrap()                              │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           build.rs (编译脚本)                          │   │
│  │  - 编译 vendor/bubblewrap/*.c                         │   │
│  │  - 链接 libcap                                        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────┬───────────────────────────────┘
                              │ FFI 调用
┌─────────────────────────────▼───────────────────────────────┐
│              vendor/bubblewrap (vendored)                    │
│  - bubblewrap.c                                              │
│  - bind-mount.c                                              │
│  - network.c                                                 │
│  - utils.c                                                   │
│  - demos/ (本文档研究目标)                                    │
└─────────────────────────────┬───────────────────────────────┘
                              │ execve
┌─────────────────────────────▼───────────────────────────────┐
│                    沙箱内执行的命令                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 6.1.1 已知 CVE

| CVE | 描述 | 缓解措施 |
|-----|------|----------|
| CVE-2016-3135 | 用户命名空间本地提权 | bubblewrap 限制 iptables 控制 |
| CVE-2017-5226 | TIOCSTI ioctl 终端注入 | 使用 `--new-session` 或 seccomp 过滤 |

#### 6.1.2 配置相关风险

| 风险 | 说明 |
|------|------|
| 过度授权 | 绑定挂载过多目录会扩大攻击面 |
| 设备访问 | `--dev-bind` 允许访问设备节点，可能逃逸 |
| D-Bus 套接字 | 绑定 D-Bus 套接字可能允许通过 systemd 执行命令 |
| 不完整的 seccomp | 规则不完整可能导致系统调用逃逸 |

### 6.2 边界条件

#### 6.2.1 用户命名空间限制

- 某些发行版（如 CentOS/RHEL 7、Debian Jessie）默认禁用非特权用户命名空间
- 需要 `kernel.unprivileged_userns_clone=1` 或 setuid root 安装

#### 6.2.2 文件描述符限制

- `--userns-block-fd` 和 `--info-fd` 需要有效的文件描述符
- 文件描述符在 fork/exec 后需要正确继承

#### 6.2.3 挂载顺序依赖

- 挂载操作按命令行顺序执行
- 错误的顺序可能导致挂载失败或意外行为

### 6.3 改进建议

#### 6.3.1 针对 demos 目录

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 添加注释说明 | 高 | 为每个选项添加详细注释，解释其安全含义 |
| 添加错误处理 | 中 | 脚本应检查命令依赖（如 bwrap、newuidmap）是否存在 |
| 提供最小化示例 | 中 | 添加一个最小化的安全沙箱示例 |
| 添加 README | 高 | 说明每个演示的目的和使用方法 |

#### 6.3.2 针对 codex-rs 集成

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 版本锁定 | 高 | 记录 vendored bubblewrap 的版本号 |
| 安全审计 | 高 | 定期审查 bubblewrap 的安全公告 |
| 配置验证 | 中 | 在生成 bwrap 参数时进行安全检查 |
| 日志记录 | 中 | 记录沙箱创建和销毁事件 |

#### 6.3.3 针对 flatpak.bpf

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 源码化 | 高 | 提供生成此 BPF 的源代码（如 seccomp 策略文件） |
| 文档化 | 高 | 说明此 BPF 允许/禁止的系统调用 |
| 更新机制 | 中 | 建立 BPF 规则更新流程 |

### 6.4 测试建议

参考 `bubblewrap/tests/` 目录的测试策略：

```
tests/
├── test-run.sh           # 基础功能测试
├── test-specifying-userns.sh  # 用户命名空间测试
├── test-specifying-pidns.sh   # PID 命名空间测试
├── test-seccomp.py       # seccomp 规则测试
└── libtest.sh            # 测试工具库
```

codex-rs 中的相关测试：
- `linux-sandbox/tests/suite/landlock.rs` - 测试 bubblewrap 与 Landlock 的集成
- `linux-sandbox/tests/suite/managed_proxy.rs` - 测试代理功能

---

## 7. 总结

`codex-rs/vendor/bubblewrap/demos/` 目录包含 4 个文件，展示了 bubblewrap 的核心功能和高级特性：

1. **bubblewrap-shell.sh**: 基础沙箱，适合学习入门
2. **flatpak-run.sh**: 生产级桌面应用沙箱，配置最完整
3. **flatpak.bpf**: seccomp 规则示例，展示系统调用过滤
4. **userns-block-fd.py**: 高级特性演示，展示外部 UID/GID 映射

在 codex-rs 项目中，这些演示脚本作为参考，帮助理解 bubblewrap 的工作原理，而实际的沙箱功能通过 `linux-sandbox` crate 的 FFI 集成实现。

---

## 附录：参考链接

- [bubblewrap 官方仓库](https://github.com/containers/bubblewrap)
- [bubblewrap 文档 (bwrap.xml)](./bwrap.xml)
- [Flatpak 官方文档](https://docs.flatpak.org/)
- [Linux Namespaces 手册](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [Seccomp BPF 文档](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
