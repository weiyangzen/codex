# flatpak-run.sh 研究文档

## 文件信息
- **路径**: `codex-rs/vendor/bubblewrap/demos/flatpak-run.sh`
- **大小**: 2642 bytes
- **类型**: Bash 脚本演示示例

---

## 1. 场景与职责

### 1.1 使用场景

`flatpak-run.sh` 是一个**高级演示脚本**，展示了如何使用纯 `bwrap` 命令（不依赖 Flatpak 工具链）手动运行 Flatpak 格式的应用程序。该脚本模拟了 Flatpak 运行时的核心行为，适用于：

1. **理解 Flatpak 内部机制**: 展示 Flatpak 如何使用 Bubblewrap 构建应用沙箱
2. **调试 Flatpak 应用**: 当 Flatpak 工具链出现问题时，手动构建运行环境
3. **自定义容器运行时**: 基于 Flatpak 应用包构建自定义运行环境
4. **安全研究**: 分析 Flatpak 沙箱的安全边界和配置策略

### 1.2 前置条件

脚本头部注释明确说明了运行前需要执行的准备工作：

```bash
# 添加 GNOME Nightly 仓库
flatpak --user remote-add --gpg-key=nightly.gpg gnome-nightly http://sdk.gnome.org/nightly/repo/
# 安装运行时和应用程序
flatpak --user install gnome-nightly org.gnome.Platform
flatpak --user install gnome-nightly org.gnome.Weather
```

### 1.3 核心职责

- 演示 Flatpak 应用沙箱的完整构建过程
- 展示运行时（Runtime）和应用（App）的分离挂载
- 实现 X11 图形转发、D-Bus 配置、GPU 访问等桌面集成
- 提供 Seccomp 过滤器集成示例

---

## 2. 功能点目的

### 2.1 沙箱架构

脚本构建了典型的 Flatpak 双层沙箱架构：

```
┌─────────────────────────────────────────┐
│           Host System                   │
│  ┌─────────────────────────────────┐    │
│  │      Flatpak Sandbox            │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │   org.gnome.Platform    │    │    │  ← 运行时层
│  │  │   (挂载到 /usr)          │    │    │
│  │  └─────────────────────────┘    │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │   org.gnome.Weather     │    │    │  ← 应用层
│  │  │   (挂载到 /app)          │    │    │
│  │  └─────────────────────────┘    │    │
│  │  ┌─────────────────────────┐    │    │
│  │  │   持久化数据目录         │    │    │  ← 数据层
│  │  │   (~/.var/app/...)      │    │    │
│  │  └─────────────────────────┘    │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

### 2.2 功能模块

| 模块 | 参数/配置 | 目的 |
|------|----------|------|
| **运行时挂载** | `--ro-bind ~/.local/share/flatpak/runtime/... /usr` | 提供基础库和依赖 |
| **应用挂载** | `--ro-bind ~/.local/share/flatpak/app/... /app` | 提供应用二进制 |
| **引用锁定** | `--lock-file /usr/.ref`, `--lock-file /app/.ref` | 防止运行时/应用被卸载 |
| **持久化存储** | `--bind ~/.var/app/org.gnome.Weather ...` | 应用数据持久化 |
| **图形输出** | `--bind /tmp/.X11-unix/X0 /tmp/.X11-unix/X99` | X11 转发 |
| **GPU 访问** | `--dev-bind /dev/dri /dev/dri` | 直接渲染设备 |
| **D-Bus/配置** | `--bind ~/.config/dconf ...` | 桌面配置共享 |
| **Seccomp** | `--seccomp 13 < flatpak.bpf` | 系统调用过滤 |

### 2.3 环境变量配置

脚本设置了 Flatpak 应用所需的完整环境：

```bash
XDG_RUNTIME_DIR="/run/user/$(id -u)"    # XDG 运行时目录
DISPLAY=:99                               # X11 显示（映射到主机 :0）
GI_TYPELIB_PATH=/app/lib/girepository-1.0 # GObject 类型库
GST_PLUGIN_PATH=/app/lib/gstreamer-1.0   # GStreamer 插件
LD_LIBRARY_PATH=/app/lib:/usr/lib/GL     # 库搜索路径
PATH=/app/bin:/usr/bin                    # 可执行文件搜索路径
XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg    # 配置目录
XDG_DATA_DIRS=/app/share:/usr/share      # 数据目录
XDG_CACHE_HOME=~/.var/app/.../cache      # 缓存目录
XDG_CONFIG_HOME=~/.var/app/.../config    # 配置主目录
XDG_DATA_HOME=~/.var/app/.../data        # 数据主目录
```

---

## 3. 具体技术实现

### 3.1 运行时与应用分离

```bash
# 运行时（基础系统）- 只读挂载到 /usr
--ro-bind ~/.local/share/flatpak/runtime/org.gnome.Platform/x86_64/master/active/files /usr \
--lock-file /usr/.ref \

# 应用程序 - 只读挂载到 /app
--ro-bind ~/.local/share/flatpak/app/org.gnome.Weather/x86_64/master/active/files/ /app \
--lock-file /app/.ref \
```

**技术要点**：
- `--lock-file` 创建文件锁，防止 Flatpak 在应用运行时卸载运行时或应用
- 运行时和应用分离允许不同应用共享同一运行时，节省空间

### 3.2 文件系统布局

```
/                           # tmpfs 根
├── usr/                    # GNOME Platform 运行时
│   ├── bin/, lib/, share/  # 基础系统文件
│   └── etc/ -> /usr/etc    # 配置目录（符号链接）
├── app/                    # GNOME Weather 应用
│   ├── bin/                # 应用可执行文件
│   ├── lib/                # 应用库
│   └── share/              # 应用数据
├── tmp/ -> /var/tmp        # 临时目录
├── var/                    # 变量目录
│   ├── tmp/                # 临时文件
│   └── run/ -> /run        # 运行时链接
├── run/                    # 运行时目录
│   └── user/$(id -u)/      # 用户运行时
│       └── flatpak-info    # Flatpak 元数据
├── sys/                    # sysfs（部分只读挂载）
│   ├── block/, bus/, class/
│   ├── dev/, devices/
├── dev/                    # devfs
│   └── dri/                # GPU 设备
└── etc/ -> usr/etc         # 配置链接
```

### 3.3 X11 转发实现

```bash
--bind /tmp/.X11-unix/X0 /tmp/.X11-unix/X99
--setenv DISPLAY :99
```

**安全考虑**：
- 使用 `:99` 而非 `:0` 避免直接暴露主机显示
- 通过绑定挂载将主机 X0 映射到容器内 X99
- 注意：X11 协议本身不安全，现代 Flatpak 更倾向使用 Wayland + XWayland

### 3.4 Seccomp 集成

```bash
--seccomp 13 \
... \
13< `dirname $0`/flatpak.bpf
```

从文件描述符 13 加载预编译的 BPF 字节码，限制容器内可执行的系统调用。

### 3.5 元数据注入

```bash
--file 10 /run/user/`id -u`/flatpak-info
10<<EOF
[Application]
name=org.gnome.Weather
runtime=runtime/org.gnome.Platform/x86_64/master
EOF
```

创建 `flatpak-info` 文件，供应用检测自身运行环境（如判断是否运行在 Flatpak 中）。

---

## 4. 关键代码路径与文件引用

### 4.1 本项目内引用

| 引用目标 | 关系 | 说明 |
|---------|------|------|
| `flatpak.bpf` | 依赖 | Seccomp BPF 过滤器字节码 |
| `bubblewrap.c` | 被调用 | bwrap 主程序源码 |
| `README.md` | 文档 | 项目说明 |

### 4.2 外部依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| Flatpak 运行时 | 数据 | `org.gnome.Platform` |
| Flatpak 应用 | 数据 | `org.gnome.Weather` |
| X11 服务器 | 系统服务 | 图形显示 |
| DRI 设备 | 硬件 | GPU 加速 |
| D-Bus | 系统服务 | 桌面集成 |

### 4.3 主机路径依赖

```
~/.local/share/flatpak/runtime/...    # Flatpak 运行时存储
~/.local/share/flatpak/app/...        # Flatpak 应用存储
~/.var/app/org.gnome.Weather/...      # 应用持久化数据
~/.config/dconf                       # DConf 配置
/run/user/$(id -u)/dconf              # 运行时 DConf
/tmp/.X11-unix/X0                     # X11 套接字
/etc/machine-id                       # 机器标识
/etc/resolv.conf                      # DNS 配置
/dev/dri/                             # GPU 设备
/sys/                                 # 系统信息
```

---

## 5. 依赖与外部交互

### 5.1 架构交互图

```
┌─────────────────────────────────────────────────────────┐
│                      Host System                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ X11 Server  │  │   D-Bus     │  │  Flatpak Store  │  │
│  │   :0        │  │   Session   │  │  (OSTree repo)  │  │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────┘  │
│         │                │                              │
│  ┌──────┴────────────────┴─────────────────────────┐    │
│  │              bwrap (Sandbox)                    │    │
│  │  ┌─────────────────────────────────────────┐    │    │
│  │  │         org.gnome.Weather               │    │    │
│  │  │    ┌─────────┐    ┌─────────────┐       │    │    │
│  │  │    │   GTK   │<--->│   GStreamer │       │    │    │
│  │  │    └────┬────┘    └─────────────┘       │    │    │
│  │  │         │                               │    │    │
│  │  │    ┌────┴────┐    ┌─────────────┐       │    │    │
│  │  │    │  X11    │--->│   /dev/dri  │       │    │    │
│  │  │    │ Client  │    │   (GPU)     │       │    │    │
│  │  │    └─────────┘    └─────────────┘       │    │    │
│  │  └─────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 5.2 命名空间使用

脚本仅使用 `--unshare-pid`，相比 `bubblewrap-shell.sh` 的 `--unshare-all` 更保守：

```bash
--unshare-pid  # 仅隔离 PID 命名空间
```

这意味着：
- 与主机共享网络命名空间（`--share-net` 隐式）
- 与主机共享 IPC 命名空间
- 与主机共享 UTS 命名空间
- 与主机共享挂载命名空间（但 bwrap 总是创建新的 mount namespace）

**注意**：bwrap 始终创建新的 mount namespace，这是其核心功能。

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

| 风险 | 严重程度 | 说明 |
|------|---------|------|
| X11 套接字绑定 | **高** | X11 协议不安全，应用可监听所有输入 |
| 共享网络 | 中 | 应用可直接访问网络 |
| D-Bus 访问 | 中 | 通过 DConf 可能访问系统服务 |
| GPU 设备直通 | 中 | `/dev/dri` 直通可能暴露 GPU 内存 |
| 部分 sysfs 暴露 | 低 | 只读挂载部分 sys 目录 |

### 6.2 已知限制

1. **硬编码路径**: 脚本使用 `~/.local/share/flatpak`，可能不适用于所有安装方式
2. **架构硬编码**: `x86_64` 架构写死
3. **版本硬编码**: `master` 分支版本
4. **单应用**: 仅适用于 `org.gnome.Weather`
5. **无 Wayland 支持**: 仅支持 X11

### 6.3 改进建议

#### 6.3.1 安全性增强

```bash
# 1. 添加 --new-session 防止 TIOCSTI 攻击
--new-session \

# 2. 使用 Wayland 替代 X11（如果应用支持）
--ro-bind "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" \
--setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY" \

# 3. 添加更多 seccomp 限制
# 参考 flatpak-bpf 生成更严格的过滤器

# 4. 使用 xdg-dbus-proxy 过滤 D-Bus 访问
# --ro-bind "$XDG_RUNTIME_DIR/bus" "$XDG_RUNTIME_DIR/bus"
```

#### 6.3.2 通用性改进

```bash
#!/usr/bin/env bash
# 通用 Flatpak 应用启动器

APP_ID="${1:-org.gnome.Weather}"
RUNTIME="${2:-org.gnome.Platform}"
ARCH="${3:-$(uname -m)}"

# 动态解析路径
APP_PATH="$HOME/.local/share/flatpak/app/$APP_ID/$ARCH/master/active/files"
RUNTIME_PATH="$HOME/.local/share/flatpak/runtime/$RUNTIME/$ARCH/master/active/files"

# 验证路径存在
if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: App $APP_ID not found"
    exit 1
fi
```

#### 6.3.3 调试支持

```bash
# 添加调试输出
DEBUG=1
if [[ "$DEBUG" == "1" ]]; then
    echo "App Path: $APP_PATH"
    echo "Runtime Path: $RUNTIME_PATH"
    BWRAP="bwrap --debug"
else
    BWRAP="bwrap"
fi
```

### 6.4 生产环境建议

⚠️ **重要**: 此脚本是教育性演示，生产环境应：

1. **使用官方 Flatpak 工具链**:
   ```bash
   flatpak run org.gnome.Weather
   ```

2. **启用完整沙箱**:
   - 使用 `--unshare-all` 并选择性 `--share-net`
   - 使用 xdg-dbus-proxy 过滤 D-Bus
   - 使用 PulseAudio/PipeWire 代理而非直接访问

3. **定期更新**:
   - 保持运行时和应用更新
   - 更新 seccomp 过滤器以匹配新内核

4. **监控和审计**:
   - 记录沙箱逃逸尝试
   - 监控异常系统调用

---

## 附录：与真实 Flatpak 的差异

| 特性 | 此脚本 | 真实 Flatpak |
|------|--------|-------------|
| 沙箱构建 | 手动 bwrap | 自动生成 |
| 门户(Portals) | 不支持 | 完整支持 |
| 更新机制 | 无 | OSTree 增量更新 |
| D-Bus 过滤 | 无 | xdg-dbus-proxy |
| 文件选择器 | 无 | 门户提供 |
| 打印支持 | 无 | 门户提供 |
| 沙箱逃逸检测 | 无 | 有 |

---

*文档生成时间: 2026-03-23*
*基于 Bubblewrap 源码和 Flatpak 架构研究*
