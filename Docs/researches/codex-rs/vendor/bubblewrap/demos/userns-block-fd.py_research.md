# userns-block-fd.py 研究文档

## 文件信息
- **路径**: `codex-rs/vendor/bubblewrap/demos/userns-block-fd.py`
- **大小**: 969 bytes
- **类型**: Python 3 演示脚本

---

## 1. 场景与职责

### 1.1 使用场景

`userns-block-fd.py` 是一个**高级演示脚本**，展示了如何使用 Bubblewrap 的 `--userns-block-fd` 和 `--info-fd` 参数实现**外部用户命名空间配置**。这是解决非特权用户命名空间（unprivileged user namespaces）映射问题的关键技术。

典型应用场景：

1. **非特权容器启动**: 在没有 `newuidmap`/`newgidmap` setuid 辅助程序的环境中启动容器
2. **自定义 UID/GID 映射**: 实现非标准的用户/组 ID 映射策略
3. **嵌套命名空间**: 在已有用户命名空间内创建新的命名空间
4. **安全研究**: 理解用户命名空间的内部工作机制

### 1.2 核心职责

该脚本演示了以下关键机制：

1. **进程协调**: 父进程和子进程通过管道进行同步
2. **UID/GID 映射**: 使用 `newuidmap`/`newgidmap` 配置用户命名空间映射
3. **阻塞等待**: 利用 `--userns-block-fd` 确保映射完成后再继续执行
4. **信息传递**: 通过 `--info-fd` 获取容器进程信息

### 1.3 解决的问题

在 Linux 中，非特权用户创建用户命名空间时，默认的 UID/GID 映射是：

```
# /proc/PID/uid_map
0          1000          1
# 容器内 UID 0 映射到主机 UID 1000，范围 1
```

这意味着容器内的 "root" 实际上是主机的普通用户。通过 `newuidmap`，可以配置更灵活的映射：

```
0 1000 1        # 容器 root = 主机用户
1 100000 65536  # 容器其他用户 = 主机子 UID 范围
```

---

## 2. 功能点目的

### 2.1 用户命名空间映射流程

```
┌─────────────────────────────────────────────────────────────┐
│                        主进程 (Python)                        │
│  ┌─────────────────┐         ┌─────────────────────────┐    │
│  │   父进程         │         │       子进程             │    │
│  │                 │         │  ┌─────────────────┐    │    │
│  │  1. 创建管道     │         │  │   bwrap         │    │    │
│  │     pipe_info   │◄────────│  │  ┌───────────┐  │    │    │
│  │     userns_block│────────►│  │  │  容器进程  │  │    │    │
│  │                 │         │  │  │           │  │    │    │
│  │  2. fork()      │         │  │  │  阻塞等待  │  │    │    │
│  │     ├───────────┼────────►│  │  │  userns_  │  │    │    │
│  │     │           │         │  │  │  block_fd │  │    │    │
│  │  3. 等待 info   │         │  │  └─────┬─────┘  │    │    │
│  │     通过管道    │◄────────│  │        │        │    │    │
│  │                 │         │  │  写入 child-pid │    │    │
│  │  4. 配置映射    │         │  │        │        │    │    │
│  │     newuidmap   │         │  │  继续执行...    │    │    │
│  │     newgidmap   │────────►│  │  （映射已配置） │    │    │
│  │                 │         │  └─────────────────┘    │    │
│  │  5. 解除阻塞    │────────►│                         │    │
│  │     写入管道    │         │                         │    │
│  └─────────────────┘         └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 关键组件

| 组件 | 类型 | 用途 |
|------|------|------|
| `pipe_info` | 管道 (os.pipe) | 子进程向父进程传递容器 PID |
| `userns_block` | 管道 (os.pipe) | 父进程控制子进程继续执行 |
| `--info-fd` | bwrap 参数 | 子进程通过此 FD 输出信息 |
| `--userns-block-fd` | bwrap 参数 | 子进程阻塞读取此 FD |
| `newuidmap` | 系统命令 | 配置 UID 映射 |
| `newgidmap` | 系统命令 | 配置 GID 映射 |

---

## 3. 具体技术实现

### 3.1 代码流程分析

```python
#!/usr/bin/env python3
import os, select, subprocess, sys, json

# 1. 创建两个管道
pipe_info = os.pipe()      # 用于传递子进程信息
userns_block = os.pipe()   # 用于阻塞/同步

# 2. fork 创建子进程
pid = os.fork()

if pid != 0:
    # ========== 父进程 ==========
    # 关闭不需要的端
    os.close(pipe_info[1])      # 关闭 info 管道的写端
    os.close(userns_block[0])   # 关闭 block 管道的读端
    
    # 等待子进程通过 pipe_info 发送数据
    select.select([pipe_info[0]], [], [])
    
    # 读取 JSON 格式的子进程信息
    data = json.load(os.fdopen(pipe_info[0]))
    child_pid = str(data['child-pid'])
    
    # 配置 UID/GID 映射
    # 格式: newuidmap <pid> <container_uid> <host_uid> <count>
    subprocess.call(["newuidmap", child_pid, "0", str(os.getuid()), "1"])
    subprocess.call(["newgidmap", child_pid, "0", str(os.getgid()), "1"])
    
    # 解除子进程的阻塞
    os.write(userns_block[1], b'1')
    
else:
    # ========== 子进程 ==========
    # 关闭不需要的端
    os.close(pipe_info[0])
    os.close(userns_block[1])
    
    # 设置 FD 为可继承（传递给 bwrap）
    os.set_inheritable(pipe_info[1], True)
    os.set_inheritable(userns_block[0], True)
    
    # 构建 bwrap 命令
    args = ["bwrap",
            "bwrap",                          # 程序名（execlp 需要）
            "--unshare-all",                  # 隔离所有命名空间
            "--unshare-user",                 # 创建新的用户命名空间
            "--userns-block-fd", "%i" % userns_block[0],  # 阻塞 FD
            "--info-fd", "%i" % pipe_info[1], # 信息输出 FD
            "--bind", "/", "/",              # 绑定根文件系统
            "cat", "/proc/self/uid_map"]      # 验证映射
    
    # 执行 bwrap
    os.execlp(*args)
```

### 3.2 关键技术点

#### 3.2.1 管道继承

```python
os.set_inheritable(pipe_info[1], True)
os.set_inheritable(userns_block[0], True)
```

**必要性**: 
- 默认情况下，Python 创建的管道 FD 在 `exec()` 后关闭（`O_CLOEXEC`）
- `set_inheritable(True)` 确保 FD 在 `execlp()` 后保持打开
- 这样 `bwrap` 才能使用这些 FD

#### 3.2.2 阻塞机制

```bash
--userns-block-fd FD
```

在 `bubblewrap.c` 中的实现：

```c
if (opt_userns_block_fd != -1)
  {
    char b[1];
    // 阻塞读取，直到父进程写入数据
    (void) TEMP_FAILURE_RETRY (read (opt_userns_block_fd, b, 1));
    close (opt_userns_block_fd);
  }
```

**时机**: 
- 在创建用户命名空间后
- 在尝试任何需要权限的操作前
- 确保 UID/GID 映射已正确配置

#### 3.2.3 信息传递格式

`--info-fd` 输出的 JSON 格式：

```json
{
    "child-pid": 12345,
    "user-namespace": 4026531837,
    "pid-namespace": 4026531836,
    "mnt-namespace": 4026531840
}
```

在 `bubblewrap.c` 中的生成：

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

### 3.3 UID/GID 映射详解

#### 3.3.1 映射文件格式

`/proc/PID/uid_map` 和 `/proc/PID/gid_map` 的格式：

```
<container_uid> <host_uid> <count>
```

示例：
```
0 1000 1        # 容器 UID 0 映射到主机 UID 1000，1 个用户
1 100000 65536  # 容器 UID 1-65536 映射到主机 100000-165535
```

#### 3.3.2 newuidmap 命令

```bash
newuidmap <pid> <container_uid_start> <host_uid_start> <count> [...]
```

脚本中的使用：
```python
subprocess.call(["newuidmap", child_pid, "0", str(os.getuid()), "1"])
# 等价于: newuidmap <child_pid> 0 <current_uid> 1
# 含义: 容器 UID 0 = 主机当前用户 UID
```

#### 3.3.3 权限要求

`newuidmap`/`newgidmap` 需要：
1. `/etc/subuid` 和 `/etc/subgid` 中配置的子 ID 范围
2. 或者以 root 权限运行

示例 `/etc/subuid`：
```
username:100000:65536
# 用户名:起始UID:数量
```

---

## 4. 关键代码路径与文件引用

### 4.1 本项目内引用

| 引用目标 | 关系 | 说明 |
|---------|------|------|
| `bubblewrap.c` | 被调用 | bwrap 主程序 |
| `bubblewrap-shell.sh` | 相关示例 | 基础沙箱演示 |
| `flatpak-run.sh` | 相关示例 | 完整应用沙箱 |

### 4.2 Bubblewrap 源码相关

#### 4.2.1 参数解析

```c
// bubblewrap.c:2346-2364
else if (strcmp (arg, "--userns-block-fd") == 0)
  {
    int the_fd;
    char *endptr;
    
    if (argc < 2)
      die ("--userns-block-fd takes an argument");
    
    if (opt_userns_block_fd != -1)
      warn_only_last_option ("--userns-block-fd");
    
    the_fd = strtol (argv[1], &endptr, 10);
    if (argv[1][0] == 0 || endptr[0] != 0 || the_fd < 0)
      die ("Invalid fd: %s", argv[1]);
    
    opt_userns_block_fd = the_fd;
    argc -= 1;
  }
```

#### 4.2.2 验证逻辑

```c
// bubblewrap.c:2943-2947
if (opt_userns_block_fd != -1 && !opt_unshare_user)
  die ("--userns-block-fd requires --unshare-user");

if (opt_userns_block_fd != -1 && opt_info_fd == -1)
  die ("--userns-block-fd requires --info-fd");
```

#### 4.2.3 阻塞实现

```c
// bubblewrap.c:3206-3211
if (opt_userns_block_fd != -1)
  {
    char b[1];
    (void) TEMP_FAILURE_RETRY (read (opt_userns_block_fd, b, 1));
    close (opt_userns_block_fd);
  }
```

### 4.3 外部依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| `bwrap` | 二进制 | Bubblewrap 主程序 |
| `newuidmap` | setuid 二进制 | 配置 UID 映射 |
| `newgidmap` | setuid 二进制 | 配置 GID 映射 |
| `cat` | 系统命令 | 验证映射结果 |

---

## 5. 依赖与外部交互

### 5.1 系统要求

- Linux 内核 3.8+（用户命名空间支持）
- `CONFIG_USER_NS` 内核编译选项
- `newuidmap`/`newgidmap` 工具（shadow-utils 包）
- `/etc/subuid` 和 `/etc/subgid` 配置

### 5.2 运行时序图

```
时间 ──────────────────────────────────────────────────────────────►

[Python 父进程]        [Python 子进程]           [bwrap/容器]
      │                       │                       │
      │─── os.fork() ────────►│                       │
      │                       │─── os.execlp() ──────►│
      │                       │                       │
      │◄── 子进程启动 ────────│                       │
      │                       │                       │
      │─── select() 等待 ◄────│                       │
      │                       │                       │
      │                       │                       │─── 创建用户命名空间
      │                       │                       │
      │                       │                       │─── 阻塞 read(userns_block_fd)
      │                       │                       │
      │                       │─── 写入 child-pid ───►│
      │                       │    到 info-fd         │
      │                       │                       │
      │◄── 读取 child-pid ────│                       │
      │                       │                       │
      │─── newuidmap() ───────┼──────────────────────►│
      │─── newgidmap() ───────┼──────────────────────►│
      │    (配置映射)          │                       │
      │                       │                       │
      │─── 写入 userns_block ─┼──────────────────────►│
      │                       │                       │
      │                       │                       │─── 解除阻塞，继续执行
      │                       │                       │
      │                       │                       │─── cat /proc/self/uid_map
      │                       │                       │
      │◄── 输出验证结果 ────────────────────────────────│
```

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 竞态条件 | PID 重用可能导致映射错误进程 | 使用 pidfd 或快速操作 |
| 映射配置错误 | 错误的 UID 映射可能导致权限提升 | 验证映射后再解除阻塞 |
| 子 ID 耗尽 | 大量容器可能耗尽 subuid 范围 | 合理规划 ID 范围 |
| 信息泄露 | `--info-fd` 可能泄露敏感信息 | 限制 FD 访问权限 |

### 6.2 边界限制

1. **需要 newuidmap**: 在没有 shadow-utils 的系统上无法运行
2. **需要 subuid 配置**: 用户必须在 `/etc/subuid` 中有配置
3. **单线程**: 脚本使用 `fork()`，在 Python 多线程环境下可能有问题
4. **错误处理简单**: 使用 `subprocess.call()` 而非 `check_call()`

### 6.3 改进建议

#### 6.3.1 错误处理增强

```python
import subprocess

def setup_id_maps(child_pid):
    """配置 UID/GID 映射，带错误处理"""
    try:
        subprocess.run(
            ["newuidmap", child_pid, "0", str(os.getuid()), "1"],
            check=True,
            capture_output=True,
            text=True
        )
        subprocess.run(
            ["newgidmap", child_pid, "0", str(os.getgid()), "1"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError as e:
        print(f"Failed to setup ID maps: {e.stderr}", file=sys.stderr)
        # 通知子进程失败
        os.write(userns_block[1], b'0')  # 发送失败信号
        sys.exit(1)
```

#### 6.3.2 使用 pidfd（Linux 5.3+）

```python
import os

# 使用 pidfd 避免 PID 重用
pidfd = os.pidfd_open(pid)
# 后续操作使用 pidfd 而非 PID
```

#### 6.3.3 支持多 UID 映射

```python
def setup_complex_maps(child_pid, uid_ranges, gid_ranges):
    """配置复杂的 UID/GID 映射
    
    uid_ranges: [(container_start, host_start, count), ...]
    """
    uid_args = ["newuidmap", child_pid]
    for c_start, h_start, count in uid_ranges:
        uid_args.extend([str(c_start), str(h_start), str(count)])
    
    subprocess.run(uid_args, check=True)
```

#### 6.3.4 异步/协程版本

```python
import asyncio

async def run_container():
    """使用 asyncio 的异步版本"""
    # 使用 asyncio 的进程管理
    # 更好的并发控制和错误处理
    pass
```

### 6.4 生产环境建议

⚠️ **警告**: 此脚本是教育性演示，生产环境应：

1. **使用成熟的容器运行时**: 如 systemd-nspawn、LXC、Podman
2. **验证所有输入**: 严格验证从子进程接收的数据
3. **限制权限**: 使用 capabilities 而非 root
4. **审计日志**: 记录所有 ID 映射操作
5. **监控资源**: 防止 fork 炸弹等资源耗尽攻击

---

## 附录：与 Flatpak 的关系

Flatpak 实际使用类似的机制，但更复杂：

| 特性 | 此脚本 | Flatpak |
|------|--------|---------|
| 进程管理 | Python fork | 自定义 C 代码 |
| ID 映射 | 简单 1:1 | 支持多范围映射 |
| 错误处理 | 基本 | 完整错误恢复 |
| 安全验证 | 无 | 完整验证链 |
| 性能 | 一般 | 优化 |

Flatpak 的实现在 `common/flatpak-run.c` 中，使用类似的 `--userns-block-fd` 机制。

---

*文档生成时间: 2026-03-23*
*基于 Bubblewrap 源码和 Linux 用户命名空间研究*
