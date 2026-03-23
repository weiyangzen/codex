# README.md 研究文档

## 场景与职责

`README.md` 是 bubblewrap 项目的主要文档入口，面向潜在用户、贡献者和安全审计人员。它全面介绍了项目的背景、设计理念、安全模型、使用方法和相关项目对比。

## 功能点目的

1. **项目介绍**：解释 bubblewrap 是什么及其解决的问题
2. **安全说明**：详细阐述安全模型和限制
3. **使用指导**：提供基本使用示例和安装说明
4. **项目对比**：与类似工具进行差异化比较
5. **生态定位**：说明在容器生态系统中的位置

## 具体技术实现

### 文档结构

```markdown
Bubblewrap
==========

1. 背景与问题陈述
2. User namespaces 技术背景
3. System security（系统安全）
4. Sandbox security（沙箱安全）
5. Users（用户/采用者）
6. Installation（安装）
7. Usage（使用）
8. Sandboxing（沙箱技术细节）
9. Limitations（限制）
10. 相关项目对比
11. 项目命名由来
```

### 核心概念解析

#### 1. 问题背景

bubblewrap 解决的核心问题：
```markdown
Many container runtime tools like `systemd-nspawn`, `docker`,
etc. focus on providing infrastructure for system administrators...
These tools are not suitable to give to unprivileged users, because it
is trivial to turn such access into a fully privileged root shell
on the host.
```

**关键洞察**：传统容器工具需要 root 权限，不适合普通用户使用。

#### 2. User Namespaces 与 bubblewrap 的关系

```markdown
Bubblewrap could be viewed as setuid implementation of a *subset* of
user namespaces.
```

| 特性 | User Namespaces | bubblewrap |
|------|----------------|------------|
| 实现方式 | 内核特性 | setuid 二进制 |
| 权限要求 | 内核支持 | 安装时 setuid |
| 功能范围 | 完整 | 子集（更安全） |
| 可用性 | 部分发行版禁用 | 始终可用 |

**CVE-2016-3135 案例**：
- 问题：user namespaces 引入的本地 root 漏洞
- bubblewrap 对策：不提供 iptables 控制（漏洞相关功能）

#### 3. 安全模型

**系统安全（System Security）**
```markdown
The maintainers of this tool believe that it does not, even when used
in combination with typical software installed on that distribution,
allow privilege escalation.
```

关键安全机制：
- `PR_SET_NO_NEW_PRIVS`：禁止获取新特权（防止 setuid 二进制逃逸）

**沙箱安全（Sandbox Security）**
```markdown
Whatever program constructs the command-line arguments for bubblewrap
(often a larger framework like Flatpak...) is responsible for defining
its own security model
```

重要原则：bubblewrap 是**工具包**而非**现成沙箱**，安全边界由调用者定义。

#### 4. 技术实现机制

**命名空间支持**

| 命名空间 | 标志 | 功能 |
|---------|------|------|
| User | `CLONE_NEWUSER` | 隐藏 uid/gid |
| IPC | `CLONE_NEWIPC` | 隔离 SystemV IPC |
| PID | `CLONE_NEWPID` | 进程隔离 + pid1 处理 |
| Network | `CLONE_NEWNET` | 网络隔离 |
| UTS | `CLONE_NEWUTS` | 主机名隔离 |

**PID 1 问题处理**
```markdown
bubblewrap will run a trivial pid1 inside your container to handle
the requirements of reaping children in the sandbox.
```

解决 Docker pid 1 僵尸进程问题。

#### 5. 使用示例

**基础示例**
```bash
bwrap \
    --ro-bind /usr /usr \
    --symlink usr/lib64 /lib64 \
    --proc /proc \
    --dev /dev \
    --unshare-pid \
    --new-session \
    bash
```

**关键选项说明**
- `--ro-bind`：只读绑定挂载
- `--symlink`：创建符号链接
- `--proc`：挂载 proc 文件系统
- `--dev`：挂载设备文件系统
- `--unshare-pid`：创建 PID 命名空间
- `--new-session`：创建新会话（防止 TIOCSTI 攻击）

#### 6. 安全限制

**CVE-2017-5226 防护**
```markdown
If you are not filtering out `TIOCSTI` commands using seccomp filters,
argument `--new-session` is needed to protect against out-of-sandbox
command execution
```

**其他限制**
- 绑定 D-Bus 套接字可能导致权限提升（可通过 systemd 执行命令）
- 浏览器内部沙箱可能与 bubblewrap 冲突

### 项目对比分析

#### Firejail vs bubblewrap

| 方面 | Firejail | bubblewrap |
|------|---------|-----------|
| 设计哲学 | 大而全（包含桌面功能） | 小而精（核心沙箱） |
| 代码量 | 较大 | 较小（更易审计） |
| PulseAudio | 内置支持 | 由调用者处理 |
| 路径白名单 | 是 | 否（使用能力机制） |

**关键观点**：小 setuid 程序更易审计，桌面功能应放在非特权层。

#### runc vs bubblewrap

| 方面 | runc | bubblewrap |
|------|------|-----------|
| 目标用户 | root | 普通用户 |
| setuid | 不支持 | 支持 |
| OCI 兼容 | 是 | 否 |
| rootless | 支持 | 原生支持 |

## 关键代码路径与文件引用

- **文件位置**: `codex-rs/vendor/bubblewrap/README.md`
- **关联文件**:
  - `SECURITY.md` - 详细安全政策
  - `demos/bubblewrap-shell.sh` - 完整演示脚本
  - `bwrap.xml` - 手册页源文件

## 依赖与外部交互

### 采用者生态

```
Flatpak ──────┐
rpm-ostree ───┼──► bubblewrap
bwrap-oci ────┘
     │
     ▼
Kubernetes/OpenShift (期望支持)
```

### 技术依赖

- Linux 内核（命名空间、seccomp 支持）
- setuid 权限（或 user namespaces）
- meson（构建时）

## 风险、边界与改进建议

### 风险

1. **安全误解风险**
   - 用户可能误认为 bubblewrap 本身是完整沙箱
   - 实际安全边界由命令行参数决定

2. **TIOCSTI 风险**
   - 不使用 `--new-session` 且未过滤 `TIOCSTI` 存在安全漏洞

3. **setuid 风险**
   - 尽管代码力求精简，setuid 程序仍存在潜在风险

### 边界

- 不提供现成安全策略
- 不了解桌面环境细节（PulseAudio、D-Bus 等）
- 需要调用者（如 Flatpak）构建合适的安全模型

### 改进建议

1. **添加架构图**
   ```
   添加命名空间创建流程图、权限分离架构图
   ```

2. **扩展使用示例**
   - 更多实际场景示例
   - 与 Flatpak、Docker 的集成示例

3. **安全最佳实践**
   ```markdown
   ## Security Best Practices
   
   1. Always use `--new-session` unless you have specific reasons
   2. Filter TIOCSTI via seccomp when possible
   3. Use xdg-dbus-proxy for D-Bus access control
   4. Avoid binding sensitive host directories
   ```

4. **故障排除指南**
   - 常见错误及解决方案
   - 调试技巧（如 `--level-prefix` 使用）

5. **性能考虑**
   - 启动时间优化
   - 内存开销说明

6. **多语言支持**
   - 考虑添加其他语言版本

## 与项目整体的关系

### 文档体系

```
文档层级
├── README.md (本文件) - 入门和概览
├── SECURITY.md - 安全政策和漏洞报告
├── NEWS.md - 版本变更
├── demos/ - 示例脚本
├── bwrap.xml - 详细手册页
└── https://github.com/containers/bubblewrap - 完整文档
```

### 项目定位

bubblewrap 在 Linux 容器生态中的位置：

```
┌─────────────────────────────────────────┐
│           应用层 (Flatpak 等)            │
├─────────────────────────────────────────┤
│         bubblewrap (沙箱执行)            │ ← 本工具
├─────────────────────────────────────────┤
│    Linux 内核 (namespaces, seccomp)     │
└─────────────────────────────────────────┘
```

## 相关资源

- [项目主页](https://github.com/containers/bubblewrap)
- [Flatpak](https://www.flatpak.org)
- [Linux Namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [CVE-2017-5226](https://github.com/containers/bubblewrap/issues/142)
- [Docker pid 1 problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
