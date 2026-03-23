# bubblewrap-shell.sh 研究文档

## 文件信息
- **路径**: `codex-rs/vendor/bubblewrap/demos/bubblewrap-shell.sh`
- **大小**: 1204 bytes
- **类型**: Bash 脚本演示示例

---

## 1. 场景与职责

### 1.1 使用场景

`bubblewrap-shell.sh` 是 Bubblewrap 项目官方提供的基础演示脚本，用于展示如何使用 `bwrap` 命令创建一个**最小化沙箱环境**，同时复用主机系统的二进制文件（`/usr` 目录）。该脚本演示了以下典型应用场景：

1. **开发/测试环境隔离**: 快速创建一个隔离的 shell 环境，用于测试软件而不影响主机系统
2. **安全研究**: 演示如何在保持主机二进制兼容性的同时，隔离关键系统目录（`/tmp`, `/home`, `/var`, `/run`, `/etc`）
3. **容器化学习**: 作为学习 Linux 命名空间（namespaces）和容器技术的入门示例

### 1.2 核心职责

该脚本的主要职责是：
- 展示 `bwrap` 命令的基本用法和常见参数组合
- 演示如何构建一个功能完整但受限的容器环境
- 提供可运行的沙箱 shell 示例，便于理解和扩展

---

## 2. 功能点目的

### 2.1 沙箱环境构建

脚本通过 `bwrap` 命令构建沙箱，实现以下目标：

| 功能 | 目的 |
|------|------|
| `--ro-bind /usr /usr` | 以只读方式挂载主机 `/usr`，复用系统二进制 |
| `--dir /tmp`, `--dir /var` | 创建独立的临时和变量目录，隔离主机数据 |
| `--proc /proc`, `--dev /dev` | 创建独立的 procfs 和 devfs，隔离进程和设备信息 |
| `--unshare-all` | 隔离所有命名空间（PID, NET, IPC, UTS, MNT, USER, CGROUP） |
| `--share-net` | 保留网络访问能力（与 `--unshare-all` 中的 NET 部分冲突时优先） |

### 2.2 文件系统布局

脚本构建的文件系统布局：

```
/                    # tmpfs 根目录（自动创建，退出时清理）
├── usr/             # 只读绑定自主机 /usr
├── lib -> usr/lib   # 符号链接，兼容传统路径
├── lib64 -> usr/lib64
├── bin -> usr/bin
├── sbin -> usr/sbin
├── tmp/             # 独立目录
├── var/             # 独立目录
│   └── tmp -> ../tmp
├── proc/            # 独立 procfs
├── dev/             # 独立 devfs
├── etc/             # 最小化配置
│   ├── resolv.conf  # 复用主机 DNS 配置
│   ├── passwd       # 动态生成的 stub 文件
│   └── group        # 动态生成的 stub 文件
└── run/user/$(id -u)/  # XDG 运行时目录
```

### 2.3 用户身份处理

脚本通过进程替换动态生成最小化的用户数据库文件：

```bash
11< <(getent passwd $UID 65534)   # 当前用户 + nobody
12< <(getent group $(id -g) 65534) # 当前组 + nogroup
```

这种方式避免了暴露主机完整的 `/etc/passwd` 和 `/etc/group`，减少信息泄露风险。

---

## 3. 具体技术实现

### 3.1 关键命令参数详解

```bash
bwrap \
    --ro-bind /usr /usr \           # 只读绑定挂载
    --dir /tmp \                    # 创建空目录
    --dir /var \                    # 创建空目录
    --symlink ../tmp var/tmp \      # 创建符号链接
    --proc /proc \                  # 挂载 procfs
    --dev /dev \                    # 挂载 devfs（最小设备集）
    --ro-bind /etc/resolv.conf /etc/resolv.conf \  # DNS 配置
    --symlink usr/lib /lib \        # FHS 兼容性链接
    --symlink usr/lib64 /lib64
    --symlink usr/bin /bin
    --symlink usr/sbin /sbin
    --chdir / \                     # 设置工作目录
    --unshare-all \                 # 隔离所有命名空间
    --share-net \                   # 但保留网络
    --die-with-parent \             # 父进程退出时终止容器
    --dir /run/user/$(id -u) \      # XDG 运行时目录
    --setenv XDG_RUNTIME_DIR ...    # 环境变量设置
    --setenv PS1 "bwrap-demo$ "     # 自定义提示符
    --file 11 /etc/passwd \         # 从 fd 读取内容写入文件
    --file 12 /etc/group
    /bin/sh                         # 执行的命令
```

### 3.2 文件描述符重定向技巧

脚本使用 Bash 的进程替换功能实现动态文件内容注入：

```bash
(exec bwrap ... \
    --file 11 /etc/passwd \
    --file 12 /etc/group \
    /bin/sh) \
    11< <(getent passwd $UID 65534) \
    12< <(getent group $(id -g) 65534)
```

**技术要点**：
- `exec` 替换当前进程，避免额外的 shell 层
- `11< <(...)` 使用进程替换创建匿名管道，将命令输出绑定到文件描述符 11
- `bwrap` 的 `--file FD PATH` 参数从指定 FD 读取内容，写入容器内的 PATH

### 3.3 安全机制

1. **`set -euo pipefail`**: 严格的错误处理模式
   - `-e`: 命令失败立即退出
   - `-u`: 使用未定义变量报错
   - `-o pipefail`: 管道中任一命令失败即整体失败

2. **`--die-with-parent`**: 确保容器生命周期与父进程绑定

3. **`--unshare-all`**: 最大程度隔离，但保留 `--share-net` 以满足基本网络需求

---

## 4. 关键代码路径与文件引用

### 4.1 本项目内引用

| 引用目标 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/vendor/bubblewrap/bubblewrap.c` | 被调用 | bwrap 主程序源码 |
| `codex-rs/vendor/bubblewrap/README.md` | 文档 | 提及此脚本作为示例 |

### 4.2 外部依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| `bwrap` | 二进制 | Bubblewrap 主程序 |
| `getent` | 系统命令 | 查询用户/组信息 |
| `id` | 系统命令 | 获取当前用户/组 ID |
| `/bin/sh` | 系统 shell | 容器内执行的命令 |

### 4.3 源码中相关实现

在 `bubblewrap.c` 中，相关参数的处理逻辑：

```c
// --ro-bind 处理
else if (strcmp (arg, "--ro-bind") == 0)
  {
    // 设置只读绑定挂载
  }

// --unshare-all 处理
else if (strcmp (arg, "--unshare-all") == 0)
  {
    // 设置所有 unshare 标志位
  }

// --file FD PATH 处理
else if (strcmp (arg, "--file") == 0)
  {
    // 从 FD 读取数据写入容器内文件
  }
```

---

## 5. 依赖与外部交互

### 5.1 系统要求

- Linux 内核（支持 namespaces）
- Bubblewrap 已安装（通常需要 setuid root 或 unprivileged user namespaces 支持）
- Bash 4.0+

### 5.2 运行时交互

```
┌─────────────────┐
│   Host System   │
│  ┌───────────┐  │
│  │   bash    │  │  ← 执行脚本
│  │  ┌─────┐  │  │
│  │  │bwrap│  │  │  ← 创建沙箱
│  │  │┌───┐│  │  │
│  │  ││sh ││  │  │  ← 容器内 shell
│  │  │└───┘│  │  │
│  │  └─────┘  │  │
│  └───────────┘  │
└─────────────────┘
```

### 5.3 与 Flatpak 的关系

此脚本是 Flatpak 底层技术的简化演示。Flatpak 实际使用更复杂的 `bwrap` 调用，包括：
- 更精细的文件系统绑定
- Seccomp 过滤器
- D-Bus 代理集成
- 额外的安全策略

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| `--share-net` | 保留网络访问，恶意代码可能联网 | 移除该参数以隔离网络 |
| `/etc/resolv.conf` | 暴露主机 DNS 配置 | 使用静态 DNS 或代理 |
| 设备访问 | `/dev` 包含部分主机设备 | 使用 `--dev-bind` 限制特定设备 |

### 6.2 边界限制

1. **无持久化存储**: 容器内所有修改在退出后丢失
2. **无图形支持**: 未配置 X11/Wayland 转发
3. **有限设备访问**: 无法访问 GPU 等专用硬件（除非额外配置）
4. **单用户模式**: 仅支持当前用户身份运行

### 6.3 改进建议

1. **添加 seccomp 过滤**:
   ```bash
   --seccomp 3 < syscall_filter.bpf
   ```

2. **网络隔离选项**（注释说明）:
   ```bash
   # 如需完全隔离，移除 --share-net
   # 如需选择性网络，使用 --unshare-net 配合代理
   ```

3. **资源限制**:
   ```bash
   # 可结合 systemd-nspawn 或 cgroup 限制资源使用
   ```

4. **目录共享扩展**:
   ```bash
   # 示例：安全地共享特定项目目录
   --ro-bind ~/projects/public /home/user/projects
   ```

### 6.4 生产环境注意事项

⚠️ **警告**: 此脚本仅用于演示目的，生产环境应：
- 使用更严格的 seccomp 策略
- 实施完整的文件系统访问控制
- 考虑使用 Flatpak 或 systemd-nspawn 等更成熟的容器方案
- 定期审查和更新安全策略

---

## 附录：相关 CVE 参考

- **CVE-2017-5226**: TIOCSTI 命令注入风险 → 使用 `--new-session` 缓解
- **CVE-2016-3135**: 用户命名空间漏洞 → Bubblewrap 通过限制权限缓解

---

*文档生成时间: 2026-03-23*
*基于 Bubblewrap 源码研究*
