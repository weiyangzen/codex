# Bubblewrap ZSH 补全脚本研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 项目定位

Bubblewrap（bwrap）是一个**无特权（unprivileged）的低级沙箱工具**，由 Flatpak 项目维护，用于在 Linux 系统上创建安全的容器环境。该工具通过创建新的命名空间（namespaces）和受限的文件系统视图来实现进程隔离。

### 1.2 ZSH 补全脚本的职责

位于 `codex-rs/vendor/bubblewrap/completions/zsh/_bwrap` 的 ZSH 补全脚本承担以下核心职责：

| 职责 | 说明 |
|------|------|
| **命令行参数补全** | 为 `bwrap` 命令提供所有可用选项的自动补全 |
| **参数值类型提示** | 根据选项类型提供上下文相关的补全建议（如文件路径、数字、能力名等） |
| **状态机管理** | 处理 `--perms`/`--size` 等修饰符选项的后续选项补全逻辑 |
| **帮助信息展示** | 为每个选项提供描述性文本，提升用户体验 |

### 1.3 与 Bash 补全的对比

项目同时提供了 Bash 和 ZSH 两种补全脚本：

- **Bash 版本** (`completions/bash/bwrap`): 简单列出所有选项，使用 `compgen` 生成补全
- **ZSH 版本** (`completions/zsh/_bwrap`): 提供更精细的类型提示和状态管理，支持复杂的参数依赖关系

---

## 功能点目的

### 2.1 核心功能模块

ZSH 补全脚本 `_bwrap` 包含以下功能模块：

#### 2.1.1 基础参数补全

覆盖 bwrap 的 60+ 个命令行选项，包括：

- **命名空间相关**: `--unshare-user`, `--unshare-pid`, `--unshare-net`, `--unshare-all` 等
- **文件系统挂载**: `--bind`, `--ro-bind`, `--dev-bind`, `--tmpfs`, `--proc`, `--dev` 等
- **权限控制**: `--cap-add`, `--cap-drop`, `--perms`, `--chmod` 等
- **进程管理**: `--as-pid-1`, `--die-with-parent`, `--new-session` 等
- **文件描述符**: `--args`, `--seccomp`, `--info-fd`, `--block-fd` 等

#### 2.1.2 修饰符状态处理

脚本实现了三个状态数组来处理修饰符选项的后续补全：

```zsh
# 在 --perms 之后可用的选项
_bwrap_args_after_perms=(
    '--bind-data[...]:...'
    '--dir[...]:...'
    '--file[...]:...'
    '--ro-bind-data[...]:...'
    '--size[...]:...'
    '--tmpfs[...]:...'
)

# 在 --size 之后可用的选项
_bwrap_args_after_size=(
    '--perms[...]:...'
    '--tmpfs[...]:...'
)

# 在 --perms --size 之后可用的选项
_bwrap_args_after_perms_size=(
    '--tmpfs[...]:...'
)
```

#### 2.1.3 Linux 能力名补全

为 `--cap-add` 和 `--cap-drop` 选项提供完整的 Linux capability 列表：

```zsh
local all_caps=(
    CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID
    CAP_KILL CAP_SETGID CAP_SETUID CAP_SETPCAP CAP_LINUX_IMMUTABLE
    CAP_NET_BIND_SERVICE CAP_NET_BROADCAST CAP_NET_ADMIN CAP_NET_RAW
    # ... 共 38 个能力
)
```

### 2.2 设计目标

1. **准确性**: 确保补全建议与 bwrap 实际支持的选项完全一致
2. **上下文感知**: 根据已输入的选项动态调整后续补全建议
3. **类型安全**: 对需要特定类型参数（如文件描述符数字、八进制权限）的选项提供验证提示

---

## 具体技术实现

### 3.1 ZSH 补全系统基础

脚本使用 ZSH 的 `compdef` 和 `_arguments` 内置函数实现补全：

```zsh
#compdef bwrap

_bwrap() {
    _arguments -S $_bwrap_args
    case "$state" in
        after_perms)
            _values -S ' ' 'option' $_bwrap_args_after_perms
            ;;
        # ... 其他状态处理
    esac
}
```

**关键技术点**:
- `#compdef bwrap`: 声明此脚本为 `bwrap` 命令的补全处理器
- `_arguments -S`: 解析命令行参数，`-S` 允许选项和参数混合
- `$state`: ZSH 补全系统的状态变量，用于处理复杂的参数依赖

### 3.2 参数规范语法

每个选项的定义遵循 ZSH 补全语法：

```zsh
'--option-name[描述文本]:参数提示:补全动作'
```

示例解析：

```zsh
'--bind[Bind mount the host path SRC on DEST]:source:_files:destination:_files'
```
- `--bind`: 选项名
- `[Bind mount...]`: 帮助描述
- `:source`: 第一个参数（SRC）的提示
- `:_files`: 第一个参数的补全动作（文件路径）
- `:destination`: 第二个参数（DEST）的提示
- `:_files`: 第二个参数的补全动作（文件路径）

### 3.3 守卫表达式（Guard Expressions）

对于需要特定格式的参数，使用 `_guard` 进行验证：

```zsh
# 文件描述符参数（数字）
'--args[Parse NUL-separated args from FD]: :_guard "[0-9]#" "file descriptor"'

# 八进制权限参数
'--perms[Set permissions]: :_guard "[0-7]#" "permissions in octal"'
```

`_guard` 语法说明：
- `"[0-9]#"`: 正则表达式，匹配一个或多个数字
- `"file descriptor"`: 提示文本

### 3.4 状态机实现

脚本使用 `->state_name` 语法触发状态转换：

```zsh
_bwrap_args=(
    # ...
    '--perms[...]: :->after_perms'
    '--size[...]: :->after_size'
    # ...
)
```

当用户输入 `--perms` 后，补全系统会：
1. 检测到 `->after_perms` 状态标记
2. 设置 `$state` 变量为 `"after_perms"`
3. 在 `_bwrap()` 函数的 `case` 语句中匹配并执行相应逻辑

### 3.5 与 bwrap 选项的同步机制

脚本中的选项列表需要与 bwrap 源码保持一致。通过以下方式维护同步：

1. **注释约定**: 每个选项数组顶部都有注释 `Please sort alphabetically (in LC_ALL=C order) by option name`
2. **人工维护**: 当 bwrap 添加新选项时，需要手动更新补全脚本
3. **测试验证**: 通过实际使用测试补全功能

---

## 关键代码路径与文件引用

### 4.1 补全脚本文件

| 文件路径 | 行数 | 说明 |
|---------|------|------|
| `codex-rs/vendor/bubblewrap/completions/zsh/_bwrap` | 115 | ZSH 补全脚本主体 |
| `codex-rs/vendor/bubblewrap/completions/zsh/meson.build` | 7 | 构建配置，定义安装路径 |

### 4.2 相关源码文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/vendor/bubblewrap/bubblewrap.c` | bwrap 主程序，包含所有选项的解析逻辑（约 3000+ 行） |
| `codex-rs/vendor/bubblewrap/bwrap.xml` | DocBook 格式的手册页源码，包含选项文档 |
| `codex-rs/vendor/bubblewrap/completions/bash/bwrap` | Bash 补全脚本（80 行） |

### 4.3 关键代码片段

#### 4.3.1 bwrap 选项解析（bubblewrap.c）

```c
// 选项解析入口
static void
parse_args_recurse (int          *argcp,
                    const char ***argvp,
                    bool          in_file,
                    int          *total_parsed_argc_p)
{
    // ...
    else if (strcmp (arg, "--bind") == 0 ||
             strcmp (arg, "--bind-try") == 0)
    {
        if (argc < 3)
            die ("%s takes two arguments", arg);
        
        op = setup_op_new (SETUP_BIND_MOUNT);
        op->source = argv[1];
        op->dest = argv[2];
        // ...
    }
    // ...
}
```

#### 4.3.2 SetupOp 类型定义（bubblewrap.c）

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
```

### 4.4 构建系统集成

#### 4.4.1 顶层 meson.build

```meson
if not meson.is_subproject()
  subdir('completions')
endif
```

#### 4.4.2 completions/meson.build

```meson
if get_option('zsh_completion').enabled()
  subdir('zsh')
endif
```

#### 4.4.3 zsh/meson.build

```meson
zsh_completion_dir = get_option('zsh_completion_dir')

if zsh_completion_dir == ''
  zsh_completion_dir = get_option('datadir') / 'zsh' / 'site-functions'
endif

install_data('_bwrap', install_dir : zsh_completion_dir)
```

---

## 依赖与外部交互

### 5.1 运行时依赖

ZSH 补全脚本依赖以下组件：

| 依赖 | 说明 |
|------|------|
| ZSH | 需要 ZSH shell 环境 |
| `_files` | ZSH 标准补全函数，用于文件路径补全 |
| `_guard` | ZSH 标准补全函数，用于参数验证 |
| `_values` | ZSH 标准补全函数，用于值列表补全 |
| `_selinux_contexts` | ZSH 标准补全函数，用于 SELinux 上下文补全（可选） |
| `_parameters` | ZSH 标准补全函数，用于环境变量补全 |

### 5.2 构建依赖

| 依赖 | 说明 |
|------|------|
| Meson | 构建系统 |
| `zsh_completion` 选项 | meson_options.txt 中定义的 feature 选项 |
| `zsh_completion_dir` 选项 | 允许自定义安装路径 |

### 5.3 外部交互

补全脚本本身不直接与 bwrap 二进制交互，它是静态的声明式脚本。但为了保持功能正确性，需要：

1. **与 bwrap 版本同步**: 当 bwrap 添加/修改选项时，补全脚本需要相应更新
2. **与 ZSH 版本兼容**: 使用标准的 ZSH 补全 API，确保跨版本兼容

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 选项不同步风险

**风险描述**: bwrap 主程序添加新选项后，ZSH 补全脚本可能未及时更新，导致用户无法获得新选项的补全提示。

**影响**: 用户体验下降，新功能发现困难。

**缓解措施**: 
- 在 bwrap 发布流程中加入补全脚本更新检查
- 添加自动化测试验证选项一致性

#### 6.1.2 状态机复杂度

**风险描述**: `--perms` 和 `--size` 修饰符的状态机逻辑较为复杂，可能存在边界情况处理不当。

**当前实现**:
```zsh
case "$state" in
    after_perms)
        _values -S ' ' 'option' $_bwrap_args_after_perms
        ;;
    after_size)
        _values -S ' ' 'option' $_bwrap_args_after_size
        ;;
    after_perms_size)
        _values -S ' ' 'option' $_bwrap_args_after_perms_size
        ;;
esac
```

**潜在问题**: 如果用户输入 `--perms --size --perms`，状态机可能无法正确处理嵌套修饰符。

### 6.2 边界情况

#### 6.2.1 选项互斥性

部分 bwrap 选项存在互斥关系，但补全脚本未完全体现：

```zsh
# 源码中的互斥检查（bubblewrap.c）
if (opt_userns_fd != -1 && opt_unshare_user)
    die ("--userns not compatible --unshare-user");
```

补全脚本仅通过注释提示，未在补全层面阻止互斥选项的组合。

#### 6.2.2 特权模式限制

某些选项在 setuid 模式下不可用：

```c
// bubblewrap.c
if (is_privileged)
    die ("The --overlay-src option is not permitted in setuid mode");
```

补全脚本无法检测当前 bwrap 是否为 setuid 安装，因此会显示所有选项。

### 6.3 改进建议

#### 6.3.1 自动化同步

建议添加脚本自动从 bwrap 源码提取选项信息：

```bash
#!/bin/bash
# 从 bubblewrap.c 的 usage() 函数提取选项
# 自动生成补全脚本模板
```

#### 6.3.2 增强状态机

考虑使用更完善的状态管理，支持：
- 嵌套修饰符的正确处理
- 选项互斥的补全层面提示

#### 6.3.3 添加测试

建议添加补全功能的自动化测试：

```zsh
# 测试用例示例
_test_bwrap_completion() {
    # 测试基本选项补全
    compargs=(bwrap --bi<TAB>)
    # 期望: --bind, --bind-data, --bind-try 等
    
    # 测试 --perms 后续补全
    compargs=(bwrap --perms 0755 <TAB>)
    # 期望: --tmpfs, --dir, --file 等
}
```

#### 6.3.4 文档完善

在脚本头部添加更详细的维护说明：

```zsh
# _bwrap - ZSH completion script for bubblewrap
# 
# Maintenance notes:
# - Keep options sorted alphabetically (LC_ALL=C)
# - When adding new options, check bubblewrap.c for:
#   - Argument count and types
#   - Privilege mode restrictions
#   - Dependencies on other options
# - Test with: source _bwrap && compdef _bwrap bwrap
```

### 6.4 与 codex-rs 项目的关联

在 codex-rs 项目中，bubblewrap 作为 vendor 依赖被引入，主要用于：

1. **沙箱执行**: codex-rs 使用 bwrap 创建安全的代码执行环境
2. **命令构建**: TUI/CLI 组件构建 bwrap 命令行参数
3. **补全支持**: 为使用 zsh 的开发者提供 bwrap 命令补全

补全脚本的准确性直接影响开发者体验，特别是在手动调试沙箱命令时。

---

## 附录：选项对照表

| 选项类别 | 选项数量 | 示例 |
|---------|---------|------|
| 命名空间 | 10 | `--unshare-user`, `--unshare-pid`, `--unshare-net` |
| 挂载操作 | 14 | `--bind`, `--ro-bind`, `--tmpfs`, `--proc` |
| 文件操作 | 8 | `--file`, `--dir`, `--symlink`, `--chmod` |
| 权限控制 | 4 | `--cap-add`, `--cap-drop`, `--perms` |
| 进程管理 | 6 | `--as-pid-1`, `--die-with-parent`, `--new-session` |
| 文件描述符 | 8 | `--args`, `--seccomp`, `--info-fd` |
| 环境变量 | 3 | `--setenv`, `--unsetenv`, `--clearenv` |
| 其他 | 8 | `--help`, `--version`, `--hostname` |

**总计**: 60+ 个选项

---

*文档生成时间: 2026-03-22*
*基于 bubblewrap 版本: 0.11.0*
