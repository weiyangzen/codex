# Bubblewrap Bash Completion 研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 项目定位
`codex-rs/vendor/bubblewrap/` 是 [bubblewrap](https://github.com/containers/bubblewrap) 项目的完整源码嵌入（vendor），这是一个由 Linux 容器社区维护的**非特权沙箱工具**。Bubblewrap 的核心使命是：

> 为未授权用户提供安全的容器化执行环境，通过创建新的 Linux 命名空间（namespaces）实现进程隔离。

### Bash Completion 的职责
位于 `completions/bash/bwrap` 的脚本承担以下职责：

| 职责维度 | 说明 |
|---------|------|
| **交互增强** | 为 `bwrap` 命令提供 Tab 键自动补全，降低命令行使用门槛 |
| **选项发现** | 帮助用户发现 60+ 个命令行选项，无需记忆完整参数名 |
| **输入校验** | 通过补全限制减少无效输入（如布尔选项与带参选项的区分） |
| **一致性维护** | 与上游 bubblewrap 版本保持选项同步（当前版本 0.11.0） |

### 使用场景
1. **开发调试**：开发者快速构建沙箱环境测试应用
2. **系统集成**：Flatpak、rpm-ostree 等工具链底层调用 bwrap
3. **安全研究**：安全工程师构造受限执行环境

---

## 功能点目的

### 核心功能：命令行选项补全

Bash completion 脚本的核心功能是**根据当前输入上下文，提供合法的选项补全建议**：

```bash
# 用户输入
$ bwrap --un<TAB>

# 补全结果
$ bwrap --unshare-
--unshare-all       --unshare-net       --unshare-user-try
--unshare-cgroup    --unshare-pid       --unshare-uts
--unshare-cgroup-try --unshare-user
```

### 选项分类策略

脚本将选项分为两类，采用不同的补全策略：

| 分类 | 定义 | 示例 | 补全行为 |
|-----|------|------|---------|
| `boolean_options` | 无参数开关选项 | `--help`, `--unshare-pid` | 直接补全选项名 |
| `options_with_args` | 需要后续参数 | `--bind SRC DEST`, `--uid UID` | 补全选项名，参数由用户手动输入 |

### 与 Zsh Completion 的对比

项目同时提供 Zsh 补全（`completions/zsh/_bwrap`），其功能更为精细：

- **Zsh 版**：支持参数类型提示（如文件路径、数字范围）、选项依赖关系（如 `--unshare-user` 与 `--userns` 互斥）
- **Bash 版**：轻量级实现，仅提供选项名补全，不处理参数值补全

---

## 具体技术实现

### 3.1 脚本结构

```bash
# shellcheck shell=bash
# ^ 声明使用 shellcheck 进行静态分析，指定 bash 方言

_bwrap() {
    local cur prev words cword
    _init_completion || return  # 初始化补全环境变量
    
    # 选项定义...
    
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $( compgen -W "$boolean_options $options_with_args" -- "$cur" ) )
    fi
    return 0
}

complete -F _bwrap bwrap  # 注册补全函数
```

### 3.2 关键变量解析

#### `cur` - 当前正在输入的词
由 `_init_completion` 设置，表示光标所在位置的当前词。例如：
- 输入 `bwrap --un<TAB>` 时，`cur="--un"`

#### `boolean_options` - 布尔选项列表

```bash
local boolean_options="
    --as-pid-1
    --assert-userns-disabled
    --clearenv
    --disable-userns
    --help
    --new-session
    --unshare-all
    --unshare-cgroup
    --unshare-cgroup-try
    --unshare-ipc
    --unshare-net
    --unshare-pid
    --unshare-user
    --unshare-user-try
    --unshare-uts
    --version
"
```

**设计规范**：
- 按 `LC_ALL=C` 字典序排序（即 ASCII 顺序）
- 包含 17 个无参数选项
- 涵盖命名空间控制、环境控制、帮助信息三大类

#### `options_with_args` - 带参选项列表

```bash
local options_with_args="
    $boolean_optons          # 注意：这里有拼写错误！应为 $boolean_options
    --add-seccomp-fd
    --args
    --argv0
    --bind
    --bind-data
    --block-fd
    --cap-add
    --cap-drop
    --chdir
    --chmod
    --dev
    --dev-bind
    --die-with-parent
    --dir
    --exec-label
    --file
    --file-label
    --gid
    --hostname
    --info-fd
    --lock-file
    --overlay
    --overlay-src
    --perms
    --proc
    --remount-ro
    --ro-bind
    --ro-overlay
    --seccomp
    --setenv
    --size
    --symlink
    --sync-fd
    --tmp-overlay
    --uid
    --unsetenv
    --userns-block-fd
"
```

**关键发现**：存在拼写错误 `$boolean_optons`（缺少字母 'i'），这导致布尔选项未被正确包含在 `options_with_args` 中。

### 3.3 补全逻辑流程

```
用户按 TAB
    │
    ▼
_bwrap() 被调用
    │
    ├── _init_completion 设置 cur, prev, words, cword
    │
    ├── 检查 cur 是否以 "-" 开头
    │       │
    │       ├── 是 ──► compgen -W 生成补全列表
    │       │              │
    │       │              ▼
    │       │         匹配 $cur 前缀的选项
    │       │              │
    │       │              ▼
    │       │         存入 COMPREPLY 数组
    │       │
    │       └── 否 ──► 无补全（返回 0）
    │
    ▼
 Bash 显示补全建议
```

### 3.4 与 Bubblewrap 主程序的选项映射

通过对比 `bubblewrap.c` 中的选项定义与 bash completion 脚本：

**C 源码中定义的全部选项**（65 个）：
```
--add-seccomp-fd, --args, --argv0, --as-pid-1, --assert-userns-disabled,
--bind, --bind-data, --bind-fd, --bind-try, --block-fd, --cap-add, --cap-drop,
--chdir, --chmod, --clearenv, --dev, --dev-bind, --dev-bind-try, --die-with-parent,
--dir, --disable-userns, --exec-label, --file, --file-label, --gid, --help,
--hostname, --info-fd, --json-status-fd, --level-prefix, --lock-file, --mqueue,
--new-session, --overlay, --overlay-src, --perms, --pidns, --proc, --remount-ro,
--ro-bind, --ro-bind-data, --ro-bind-fd, --ro-bind-try, --ro-overlay, --seccomp,
--setenv, --share, --share-net, --size, --symlink, --sync-fd, --tmpfs,
--tmp-overlay, --try, --uid, --unsetenv, --unshare, --unshare-all,
--unshare-cgroup, --unshare-cgroup-try, --unshare-ipc, --unshare-net,
--unshare-pid, --unshare-user, --unshare-user-try, --unshare-uts,
--userns, --userns2, --userns-block-fd, --version
```

**Bash Completion 中缺失的选项**（16 个）：
| 缺失选项 | C 源码中用途 | 影响评估 |
|---------|-------------|---------|
| `--bind-fd` | 通过文件描述符绑定目录 | 高（常用功能） |
| `--bind-try` | 条件绑定（源不存在时忽略） | 高 |
| `--dev-bind-try` | 条件设备绑定 | 中 |
| `--json-status-fd` | JSON 格式状态输出 | 中 |
| `--level-prefix` | 日志级别前缀（v0.11.0 新增） | 高（新版本功能） |
| `--mqueue` | 挂载 mqueue 文件系统 | 低 |
| `--pidns` | 使用现有 PID 命名空间 | 中 |
| `--ro-bind-data` | 只读绑定数据 | 中 |
| `--ro-bind-fd` | 只读绑定文件描述符 | 中 |
| `--ro-bind-try` | 条件只读绑定 | 中 |
| `--share-net` | 保留网络命名空间 | 中 |
| `--tmpfs` | 挂载 tmpfs | 高（常用功能） |
| `--userns` | 使用现有用户命名空间 | 中 |
| `--userns2` | 切换到指定用户命名空间 | 低 |

**注意**：`--share`, `--try`, `--unshare` 是 C 源码中的匹配残留（如 `strcmp(arg, "--bind-try")` 会匹配到 `--try` 子串），并非独立选项。

---

## 关键代码路径与文件引用

### 4.1 文件组织结构

```
codex-rs/vendor/bubblewrap/completions/
├── meson.build              # 条件编译入口
├── bash/
│   ├── bwrap                # bash completion 脚本（本研究对象）
│   └── meson.build          # bash 安装配置
└── zsh/
    ├── _bwrap               # zsh completion 脚本
    └── meson.build          # zsh 安装配置
```

### 4.2 构建系统集成

#### 顶层 meson.build（节选）
```meson
if not meson.is_subproject()
  subdir('completions')  # 仅在非子项目构建时安装补全
endif
```

#### completions/meson.build
```meson
if get_option('bash_completion').enabled()
  subdir('bash')  # 条件：bash_completion 选项为 enabled
endif
```

#### completions/bash/meson.build（完整）
```meson
bash_completion_dir = get_option('bash_completion_dir')

if bash_completion_dir == ''
  # 尝试通过 pkg-config 获取系统 bash-completion 目录
  bash_completion = dependency(
    'bash-completion',
    version : '>=2.0',
    required : false,
  )
  
  if bash_completion.found()
    # 使用 pkg-config 获取 completionsdir 变量
    if meson.version().version_compare('>=0.51.0')
      bash_completion_dir = bash_completion.get_variable(
        default_value: '',
        pkgconfig: 'completionsdir',
        pkgconfig_define: [
          'datadir', get_option('prefix') / get_option('datadir'),
        ],
      )
    else
      bash_completion_dir = bash_completion.get_pkgconfig_variable(
        'completionsdir',
        default: '',
        define_variable: [
          'datadir', get_option('prefix') / get_option('datadir'),
        ],
      )
    endif
  endif
endif

# 回退到默认路径
if bash_completion_dir == ''
  bash_completion_dir = get_option('datadir') / 'bash-completion' / 'completions'
endif

install_data('bwrap', install_dir : bash_completion_dir)
```

### 4.3 与主程序的关联

| 关联文件 | 关联方式 | 说明 |
|---------|---------|------|
| `bubblewrap.c` | 逻辑同步 | 选项定义需与 C 源码中的 `parse_args_recurse()` 保持一致 |
| `bwrap.xml` | 文档同步 | DocBook 格式的 man 页面，定义选项语义 |
| `meson_options.txt` | 构建配置 | 定义 `bash_completion` 和 `bash_completion_dir` 选项 |

### 4.4 关键代码行引用

**Bash Completion 脚本**：
- 第 1 行：`# shellcheck shell=bash` - 静态分析指令
- 第 6-7 行：`local cur prev words cword` - 补全标准变量
- 第 8 行：`_init_completion || return` - 初始化调用
- 第 11-28 行：`boolean_options` 定义
- 第 30-70 行：`options_with_args` 定义
- 第 32 行：`$boolean_optons` - **拼写错误位置**
- 第 72-74 行：补全逻辑核心
- 第 78 行：`complete -F _bwrap bwrap` - 补全注册

**Bubblewrap C 源码**：
- 第 303-378 行：`usage()` 函数 - 选项帮助文本
- 第 1761-2783 行：`parse_args_recurse()` - 选项解析实现
- 第 1788 行：`strcmp (arg, "--help")` - 选项匹配模式

---

## 依赖与外部交互

### 5.1 运行时依赖

| 依赖项 | 类型 | 说明 |
|-------|------|------|
| Bash | 必需 | 版本要求：支持 `compgen` 和 `complete` 内置命令 |
| bash-completion | 可选 | 提供 `_init_completion` 辅助函数；脚本可在无此库时优雅降级 |

### 5.2 构建时依赖

| 依赖项 | 用途 |
|-------|------|
| Meson ≥ 0.49.0 | 构建系统 |
| bash-completion ≥ 2.0 | pkg-config 查询安装路径 |
| pkg-config | 获取系统补全目录 |

### 5.3 版本兼容性说明

根据 `NEWS.md`（v0.11.0）：
> For users of bash-completion, bash-completion ≥ 2.10 is recommended.
> With older bash-completion, bubblewrap might install completions
> outside its `${prefix}` unless overridden with `-Dbash_completion_dir=…`.

**解读**：
- 旧版本 bash-completion（< 2.10）的 pkg-config 可能返回系统级目录（如 `/usr/share/bash-completion/completions`）
- 即使使用 `--prefix` 指定自定义安装路径，补全脚本仍可能被安装到系统目录
- **解决方案**：显式指定 `-Dbash_completion_dir=/custom/path`

### 5.4 外部交互接口

```
┌─────────────────┐
│   Bash Shell    │
│  (用户按 TAB)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  complete -F    │
│  _bwrap bwrap   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   _bwrap()      │
│  补全函数       │
│                 │
│  1. _init_completion  │
│  2. compgen -W        │
│  3. 输出到 COMPREPLY  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  用户看到补全   │
│    建议列表     │
└─────────────────┘
```

---

## 风险、边界与改进建议

### 6.1 已知问题

#### 问题 1：拼写错误导致选项遗漏
**位置**：`completions/bash/bwrap` 第 32 行
```bash
local options_with_args="
    $boolean_optons    # 错误：应为 $boolean_options
    ...
"
```
**影响**：`boolean_options` 中的 17 个选项未被包含在 `options_with_args` 中，但由于 `boolean_options` 单独在 `compgen` 中被使用，实际补全功能不受影响。这是一个**代码质量**问题而非功能缺陷。

**修复建议**：
```bash
local options_with_args="
    $boolean_options
    ...
"
```

#### 问题 2：选项同步滞后
**现状**：Bash completion 缺少 16 个有效选项（见第 3.4 节）

**高风险缺失**：
- `--tmpfs`：常用功能，用于挂载临时文件系统
- `--bind-fd`, `--bind-try`：文件描述符绑定相关
- `--level-prefix`：v0.11.0 新增功能

**修复建议**：
1. 建立选项同步检查脚本（CI 阶段）
2. 将选项列表提取到共享配置文件（YAML/JSON），生成 bash/zsh/C 代码

#### 问题 3：无参数值补全
**现状**：Bash 版本仅补全选项名，不补全参数值

**对比 Zsh 版本**：
```zsh
'--bind[Bind mount SRC on DEST]:source:_files:destination:_files'
# ^ 提供文件路径补全
```

**改进建议**：
- 对于路径参数（`--bind`, `--chdir`, `--proc` 等），使用 `_files` 提供文件补全
- 对于数字参数（`--uid`, `--gid`, `--size` 等），使用正则守卫

### 6.2 边界条件

| 边界场景 | 行为 | 说明 |
|---------|------|------|
| `cur` 为空字符串 | 无补全 | 用户未输入任何内容时按 TAB |
| `cur` 以单 `-` 开头 | 补全长选项 | 如 `-` 补全为 `--help` 等 |
| `cur` 以 `--` 开头 | 正常补全 | 标准用法 |
| 无匹配选项 | 无补全 | `COMPREPLY` 为空数组 |
| 多个匹配 | 显示列表 | Bash 默认行为 |

### 6.3 安全考虑

1. **命令注入风险**：无，脚本不执行用户输入
2. **路径遍历风险**：无，脚本不处理文件系统操作
3. **信息泄露风险**：低，补全列表仅暴露公开选项

### 6.4 改进建议优先级

| 优先级 | 建议 | 工作量 | 收益 |
|-------|------|-------|------|
| P0 | 修复 `$boolean_optons` 拼写错误 | 1 行 | 代码质量 |
| P1 | 同步缺失的 16 个选项 | 约 20 行 | 功能完整 |
| P2 | 添加路径参数补全 | 中等 | 用户体验 |
| P3 | CI 选项同步检查 | 脚本开发 | 维护性 |
| P4 | 统一 bash/zsh 选项源 | 架构改动 | 长期维护 |

### 6.5 测试建议

当前项目测试集（`tests/`）未包含 completion 测试，建议添加：

```bash
# tests/test-completion.sh（建议新增）
#!/bin/bash
source completions/bash/bwrap

# 测试选项存在性
assert_contains "$(complete -p bwrap)" "_bwrap"

# 测试补全输出
COMP_WORDS=(bwrap --un)
COMP_CWORD=1
cur="--un" _bwrap
assert_contains "${COMPREPLY[*]}" "--unshare-pid"
```

---

## 附录：选项对照表

### 完整选项清单（Bubblewrap 0.11.0）

| 选项 | 类型 | Bash 支持 | Zsh 支持 | C 源码支持 |
|-----|------|----------|----------|-----------|
| `--add-seccomp-fd FD` | 带参 | ✅ | ✅ | ✅ |
| `--args FD` | 带参 | ✅ | ✅ | ✅ |
| `--argv0 VALUE` | 带参 | ✅ | ✅ | ✅ |
| `--as-pid-1` | 布尔 | ✅ | ✅ | ✅ |
| `--assert-userns-disabled` | 布尔 | ✅ | ✅ | ✅ |
| `--bind SRC DEST` | 带参 | ✅ | ✅ | ✅ |
| `--bind-data FD DEST` | 带参 | ✅ | ✅ | ✅ |
| `--bind-fd FD DEST` | 带参 | ❌ | ✅ | ✅ |
| `--bind-try SRC DEST` | 带参 | ❌ | ✅ | ✅ |
| `--block-fd FD` | 带参 | ✅ | ✅ | ✅ |
| `--cap-add CAP` | 带参 | ✅ | ✅ | ✅ |
| `--cap-drop CAP` | 带参 | ✅ | ✅ | ✅ |
| `--chdir DIR` | 带参 | ✅ | ✅ | ✅ |
| `--chmod OCTAL PATH` | 带参 | ✅ | ✅ | ✅ |
| `--clearenv` | 布尔 | ✅ | ✅ | ✅ |
| `--dev DEST` | 带参 | ✅ | ✅ | ✅ |
| `--dev-bind SRC DEST` | 带参 | ✅ | ✅ | ✅ |
| `--dev-bind-try SRC DEST` | 带参 | ❌ | ✅ | ✅ |
| `--die-with-parent` | 布尔 | ✅ | ✅ | ✅ |
| `--dir DEST` | 带参 | ✅ | ✅ | ✅ |
| `--disable-userns` | 布尔 | ✅ | ✅ | ✅ |
| `--exec-label LABEL` | 带参 | ✅ | ✅ | ✅ |
| `--file FD DEST` | 带参 | ✅ | ✅ | ✅ |
| `--file-label LABEL` | 带参 | ✅ | ✅ | ✅ |
| `--gid GID` | 带参 | ✅ | ✅ | ✅ |
| `--help` | 布尔 | ✅ | ✅ | ✅ |
| `--hostname NAME` | 带参 | ✅ | ✅ | ✅ |
| `--info-fd FD` | 带参 | ✅ | ✅ | ✅ |
| `--json-status-fd FD` | 带参 | ❌ | ✅ | ✅ |
| `--level-prefix` | 布尔 | ❌ | ✅ | ✅ |
| `--lock-file DEST` | 带参 | ✅ | ✅ | ✅ |
| `--mqueue DEST` | 带参 | ❌ | ✅ | ✅ |
| `--new-session` | 布尔 | ✅ | ✅ | ✅ |
| `--overlay RWSRC WORKDIR DEST` | 带参 | ✅ | ✅ | ✅ |
| `--overlay-src SRC` | 带参 | ✅ | ✅ | ✅ |
| `--perms OCTAL` | 带参 | ✅ | ✅ | ✅ |
| `--pidns FD` | 带参 | ❌ | ✅ | ✅ |
| `--proc DEST` | 带参 | ✅ | ✅ | ✅ |
| `--remount-ro DEST` | 带参 | ✅ | ✅ | ✅ |
| `--ro-bind SRC DEST` | 带参 | ✅ | ✅ | ✅ |
| `--ro-bind-data FD DEST` | 带参 | ❌ | ✅ | ✅ |
| `--ro-bind-fd FD DEST` | 带参 | ❌ | ✅ | ✅ |
| `--ro-bind-try SRC DEST` | 带参 | ❌ | ✅ | ✅ |
| `--ro-overlay DEST` | 带参 | ✅ | ✅ | ✅ |
| `--seccomp FD` | 带参 | ✅ | ✅ | ✅ |
| `--setenv VAR VALUE` | 带参 | ✅ | ✅ | ✅ |
| `--share-net` | 布尔 | ❌ | ✅ | ✅ |
| `--size BYTES` | 带参 | ✅ | ✅ | ✅ |
| `--symlink SRC DEST` | 带参 | ✅ | ✅ | ✅ |
| `--sync-fd FD` | 带参 | ✅ | ✅ | ✅ |
| `--tmpfs DEST` | 带参 | ❌ | ✅ | ✅ |
| `--tmp-overlay DEST` | 带参 | ✅ | ✅ | ✅ |
| `--uid UID` | 带参 | ✅ | ✅ | ✅ |
| `--unsetenv VAR` | 带参 | ✅ | ✅ | ✅ |
| `--unshare-all` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-cgroup` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-cgroup-try` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-ipc` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-net` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-pid` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-user` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-user-try` | 布尔 | ✅ | ✅ | ✅ |
| `--unshare-uts` | 布尔 | ✅ | ✅ | ✅ |
| `--userns FD` | 带参 | ❌ | ✅ | ✅ |
| `--userns2 FD` | 带参 | ❌ | ✅ | ✅ |
| `--userns-block-fd FD` | 带参 | ✅ | ✅ | ✅ |
| `--version` | 布尔 | ✅ | ✅ | ✅ |

**统计**：
- 总计选项：~65 个
- Bash 支持：~52 个（80%）
- Bash 缺失：13 个（主要为新功能或较少用选项）

---

*文档生成时间：2026-03-22*
*基于 Bubblewrap 版本：0.11.0*
