# Bubblewrap CI 目录深度研究报告

## 目录

- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/vendor/bubblewrap/ci/` 是 **Bubblewrap** 项目的持续集成（CI）脚本目录，位于 Codex 项目的 Rust 代码库中作为 vendored 依赖。Bubblewrap 是一个低级别的 Linux 沙箱工具，Codex 使用它来实现 Linux 平台上的文件系统隔离。

### 1.2 核心职责

该目录包含两个核心脚本，分别承担以下职责：

| 脚本 | 职责 |
|------|------|
| `builddeps.sh` | 在 CI 环境中安装构建 Bubblewrap 所需的系统依赖（编译器、库、工具链） |
| `enable-userns.sh` | 在 CI 环境中启用 Linux 用户命名空间（user namespaces）支持 |

### 1.3 在 Codex 项目中的角色

在 Codex 项目中，Bubblewrap 被用作 **Linux 沙箱的核心组件**：

1. **构建时嵌入**：通过 `linux-sandbox/build.rs` 将 Bubblewrap 的 C 源码编译为静态库，嵌入到 Rust 二进制中
2. **运行时回退**：当系统 `/usr/bin/bwrap` 不可用时，使用内嵌的 vendored bubblewrap
3. **文件系统隔离**：提供 `--ro-bind`、`--bind`、`--tmpfs` 等 mount 命名空间隔离能力

---

## 功能点目的

### 2.1 builddeps.sh - 构建依赖安装

**目的**：在 CI 环境（GitHub Actions）中自动安装构建 Bubblewrap 所需的所有系统依赖。

**支持的发行版**：
- Debian/Ubuntu（通过 `apt-get`）
- RHEL/CentOS/Fedora（通过 `yum`）

**安装的关键依赖**：

| 类别 | 依赖包 | 用途 |
|------|--------|------|
| 编译工具 | `build-essential` / `gcc` | C 编译器 |
| 构建系统 | `meson`, `libtool` | 构建系统 |
| 文档工具 | `docbook-xml`, `docbook-xsl`, `xsltproc` | 生成 man 页 |
| 功能库 | `libcap-dev` / `libcap-devel` | POSIX capabilities 支持 |
| 安全功能 | `libselinux1-dev` / `pkgconfig(libselinux)` | SELinux 支持 |
| 可选编译器 | `clang` | 替代 GCC 的编译器（通过 `--clang` 选项启用） |

### 2.2 enable-userns.sh - 用户命名空间启用

**目的**：在 CI 环境中启用 Linux 用户命名空间（user namespaces），这是 Bubblewrap 非特权运行的关键内核特性。

**技术背景**：
- 某些 Linux 发行版（如 Ubuntu）默认禁用非特权用户命名空间
- AppArmor 可能限制用户命名空间的创建
- 该脚本通过 sysctl 配置解除限制

**执行的操作**：
```bash
# 设置内核参数，禁用 AppArmor 对非特权用户命名空间的限制
echo "kernel.apparmor_restrict_unprivileged_userns = 0" > /etc/sysctl.d/99-userns.conf
sysctl --system
```

---

## 具体技术实现

### 3.1 builddeps.sh 实现细节

#### 3.1.1 命令行参数解析

```bash
# 支持的选项
--clang    # 额外安装 clang 编译器
--help     # 显示帮助信息
```

使用 `getopt` 进行标准 POSIX 参数解析：

```bash
getopt_temp="help,clang"
getopt_temp="$(getopt -o '' --long "${getopt_temp}" -n "$0" -- "$@")"
eval set -- "$getopt_temp"
```

#### 3.1.2 发行版检测逻辑

```bash
if dpkg-vendor --derives-from Debian; then
    # Debian/Ubuntu 分支
    apt-get -y update
    apt-get -q -y install ...
elif command -v yum; then
    # RHEL/CentOS/Fedora 分支
    yum -y install ...
else
    echo "Unknown distribution" >&2
    exit 1
fi
```

#### 3.1.3 关键设计模式

- **`${NULL+}` 技巧**：在包列表末尾使用 `${NULL+}` 防止 shell 单词分割问题，允许在列表末尾安全地添加注释或换行
- **严格错误处理**：`set -eux -o pipefail` 确保任何命令失败立即退出，并打印执行的命令

### 3.2 enable-userns.sh 实现细节

#### 3.2.1 内核参数配置

```bash
echo "kernel.apparmor_restrict_unprivileged_userns = 0" > /etc/sysctl.d/99-userns.conf
```

- 写入 `/etc/sysctl.d/99-userns.conf` 持久化配置
- 使用 `99-` 前缀确保配置在其他 sysctl 配置之后加载（高优先级）

#### 3.2.2 配置生效

```bash
sysctl --system
```

- 重新加载所有 sysctl 配置文件
- 立即应用新的内核参数，无需重启

### 3.3 与 GitHub Actions 的集成

在 `.github/workflows/check.yml` 中的使用：

```yaml
jobs:
  meson:
    steps:
    - name: Install build-dependencies
      run: sudo ./ci/builddeps.sh
    - name: Enable user namespaces
      run: sudo ./ci/enable-userns.sh
      
  clang:
    steps:
    - name: Install build-dependencies
      run: sudo ./ci/builddeps.sh --clang
```

---

## 关键代码路径与文件引用

### 4.1 本目录文件

| 文件 | 行数 | 用途 |
|------|------|------|
| `builddeps.sh` | 107 | 构建依赖安装脚本 |
| `enable-userns.sh` | 6 | 用户命名空间启用脚本 |

### 4.2 上游 Bubblewrap 核心文件

| 文件 | 用途 |
|------|------|
| `bubblewrap.c` | 主程序入口，命令行解析，命名空间管理，特权分离 |
| `bind-mount.c` | 绑定挂载操作实现 |
| `network.c` | 网络命名空间配置 |
| `utils.c` | 工具函数 |
| `meson.build` | Meson 构建配置 |
| `meson_options.txt` | 构建选项定义 |

### 4.3 Codex 集成相关文件

| 文件 | 用途 |
|------|------|
| `codex-rs/linux-sandbox/build.rs` | 编译 vendored bubblewrap 为 Rust 可调用库 |
| `codex-rs/linux-sandbox/src/bwrap.rs` | Bubblewrap 参数构建和调用封装 |
| `codex-rs/linux-sandbox/src/vendored_bwrap.rs` | 内嵌 bubblewrap 的 FFI 调用接口 |
| `codex-rs/linux-sandbox/src/linux_run_main.rs` | Linux 沙箱主逻辑，协调 bubblewrap 和 seccomp |

### 4.4 测试相关文件

| 文件 | 用途 |
|------|------|
| `tests/test-run.sh` | 主测试脚本（TAP 格式输出） |
| `tests/libtest.sh` | 测试库函数 |
| `tests/libtest-core.sh` | 核心测试工具 |
| `tests/test-seccomp.py` | Seccomp 过滤器测试 |

---

## 依赖与外部交互

### 5.1 系统依赖

#### 5.1.1 构建时依赖

| 依赖 | 版本要求 | 说明 |
|------|----------|------|
| meson | >= 0.49.0 | 构建系统 |
| libcap | 任意 | POSIX capabilities |
| libselinux | >= 2.1.9 | 可选 SELinux 支持 |
| docbook-xsl | 任意 | 可选 man 页生成 |

#### 5.1.2 运行时依赖

| 依赖 | 说明 |
|------|------|
| Linux Kernel | 需要支持用户命名空间（CONFIG_USER_NS） |
| /proc | 需要挂载 procfs 用于命名空间信息 |

### 5.2 与 Codex 的集成依赖

```
Codex Linux Sandbox
├── 优先使用: /usr/bin/bwrap (系统安装)
├── 回退使用: vendored bubblewrap (内嵌编译)
│   └── 编译来源: codex-rs/vendor/bubblewrap/
├── 配合: seccomp-bpf (系统调用过滤)
└── 配合: PR_SET_NO_NEW_PRIVS (禁止提升特权)
```

### 5.3 CI 环境交互

```
GitHub Actions Runner (Ubuntu)
├── 执行: ci/builddeps.sh
│   └── 安装: gcc, meson, libcap-dev, etc.
├── 执行: ci/enable-userns.sh
│   └── 配置: kernel.apparmor_restrict_unprivileged_userns = 0
├── 执行: meson _build
├── 执行: meson test -C _build
└── 执行: meson dist -C _build
```

---

## 风险、边界与改进建议

### 6.1 当前风险

#### 6.1.1 发行版支持局限

**风险**：`builddeps.sh` 仅支持 Debian 和 RHEL 系发行版。

```bash
# 当前代码
if dpkg-vendor --derives-from Debian; then
    ...
elif command -v yum; then
    ...
else
    echo "Unknown distribution" >&2
    exit 1
fi
```

**影响**：在 Arch Linux、Alpine Linux、openSUSE 等发行版上无法自动安装依赖。

#### 6.1.2 用户命名空间安全风险

**风险**：`enable-userns.sh` 禁用了 AppArmor 对用户命名空间的限制。

```bash
echo "kernel.apparmor_restrict_unprivileged_userns = 0" > /etc/sysctl.d/99-userns.conf
```

**影响**：在 CI 环境中这是必要的，但在生产环境可能降低系统安全边界。

#### 6.1.3 硬编码路径依赖

**风险**：脚本假设特定的系统路径和工具位置。

| 硬编码项 | 风险 |
|----------|------|
| `/etc/sysctl.d/99-userns.conf` | 某些容器环境可能不支持 sysctl 持久化配置 |
| `dpkg-vendor` | 仅在 Debian 系发行版可用 |
| `yum` | RHEL 8+ 默认使用 `dnf` |

### 6.2 边界条件

#### 6.2.1 容器内运行限制

- 在 Docker 容器中运行时，需要 `--privileged` 或特定 capabilities 才能启用用户命名空间
- 某些 CI 环境（如某些 Kubernetes 集群）可能禁止修改 sysctl

#### 6.2.2 内核版本要求

- 用户命名空间需要 Linux 3.8+
- 某些命名空间特性（如 cgroup 命名空间）需要更新的内核版本

### 6.3 改进建议

#### 6.3.1 扩展发行版支持

```bash
# 建议增加对更多发行版的支持
elif command -v pacman; then
    # Arch Linux
    pacman -S --noconfirm base-devel meson libcap
elif command -v apk; then
    # Alpine Linux
    apk add build-base meson libcap-dev
elif command -v zypper; then
    # openSUSE
    zypper install -y gcc meson libcap-devel
```

#### 6.3.2 增加前置检查

```bash
# 建议：在修改 sysctl 前检查当前值
if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" = "1" ]; then
    echo "Enabling user namespaces..."
    echo "kernel.apparmor_restrict_unprivileged_userns = 0" > /etc/sysctl.d/99-userns.conf
    sysctl --system
else
    echo "User namespaces already enabled or not restricted"
fi
```

#### 6.3.3 增加错误恢复机制

```bash
# 建议：在关键操作后验证结果
sysctl --system
if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns)" != "0" ]; then
    echo "Failed to enable user namespaces" >&2
    exit 1
fi
```

#### 6.3.4 文档改进

- 在脚本头部增加更详细的使用说明
- 记录每个依赖的具体用途
- 添加故障排除指南

### 6.4 安全建议

1. **最小权限原则**：CI 脚本应以最小权限运行，仅在必要时使用 `sudo`
2. **配置审计**：定期审计 sysctl 配置，确保不降低生产环境安全
3. **依赖验证**：考虑添加依赖包的签名验证或哈希校验
4. **隔离性**：在 CI 环境中确保不同构建之间的隔离，防止沙箱逃逸影响其他构建

---

## 附录：相关链接

- [Bubblewrap 上游仓库](https://github.com/containers/bubblewrap)
- [Linux 用户命名空间文档](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [Codex Linux Sandbox README](/home/sansha/Github/codex/codex-rs/linux-sandbox/README.md)
