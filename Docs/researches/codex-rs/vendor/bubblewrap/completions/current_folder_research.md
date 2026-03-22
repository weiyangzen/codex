# Bubblewrap Completions 目录研究文档

## 1. 场景与职责

### 1.1 目录定位

`codex-rs/vendor/bubblewrap/completions` 是 bubblewrap 项目（bwrap）的 shell 自动补全脚本目录，位于 codex-rs 的 vendor 依赖中。该目录包含 Bash 和 Zsh 两种 shell 的补全定义文件，用于在用户输入 `bwrap` 命令时提供交互式的选项补全支持。

### 1.2 核心职责

- **命令行选项补全**：为 `bwrap` 命令的所有命令行选项（`--bind`, `--ro-bind`, `--unshare-*` 等）提供自动补全
- **参数类型提示**：区分布尔选项（无参数）和需要参数的选项
- **上下文感知补全**：Zsh 补全脚本支持根据已输入的选项动态调整后续补全行为（如 `--perms` 后接特定选项）
- **安装集成**：通过 meson 构建系统在安装 bwrap 时同步安装补全脚本到系统标准位置

### 1.3 使用场景

1. **开发/运维人员**：在命令行中使用 bwrap 构建沙箱环境时，通过 Tab 键快速补全复杂选项
2. **Codex 沙箱执行**：codex-linux-sandbox 内部调用 bwrap 时，虽然由程序自动构建参数，但补全脚本仍对调试和手动测试有用
3. **系统集成**：作为 bubblewrap 软件包的一部分，随系统包管理器分发到用户环境

---

## 2. 功能点目的

### 2.1 Bash 补全 (`bash/bwrap`)

| 功能 | 目的 |
|------|------|
| `boolean_options` | 定义无需参数的布尔标志选项（如 `--help`, `--unshare-all`） |
| `options_with_args` | 定义需要参数的选项（如 `--bind SRC DEST`, `--uid UID`） |
| `compgen -W` | 生成补全候选列表，支持前缀匹配 |
| `_init_completion` | 初始化 bash-completion 框架，解析当前命令行状态 |

**关键设计**：
- 选项列表按 `LC_ALL=C` 字母顺序排序，便于维护时查重
- 使用 `compgen -W` 将选项列表与当前输入 `$cur` 进行前缀匹配
- 仅对以 `-` 开头的输入提供补全（`if [[ "$cur" == -* ]]`）

### 2.2 Zsh 补全 (`zsh/_bwrap`)

| 功能 | 目的 |
|------|------|
| `_bwrap_args` | 主选项数组，定义所有选项及其参数描述 |
| `_bwrap_args_after_perms` | `--perms` 后可跟随的选项子集 |
| `_bwrap_args_after_size` | `--size` 后可跟随的选项子集 |
| `_bwrap_args_after_perms_size` | `--perms --size` 组合后可跟随的选项 |
| `_values -S ' '` | 在特定上下文中提供受限的选项补全 |
| `caps` 状态处理 | 为 `--cap-add`/`--cap-drop` 提供 Linux capability 列表 |

**高级特性**：
- **参数描述**：每个选项都带有 `[description]` 说明，在补全时显示帮助文本
- **参数类型验证**：使用 `_guard` 限制参数格式（如 `[0-9]#` 表示数字）
- **文件路径补全**：使用 `_files` 提供路径补全（如 `--bind` 的 SRC/DEST）
- **状态机**：通过 `->state` 语法实现上下文相关的补全（如 `--perms` 后只显示特定选项）
- **互斥选项**：使用 `(option)` 语法标记互斥选项（如 `(--clearenv)--unsetenv`）

### 2.3 Meson 构建集成

| 文件 | 功能 |
|------|------|
| `meson.build` | 条件编译入口，根据 `bash_completion`/`zsh_completion` 选项决定是否包含子目录 |
| `bash/meson.build` | 检测系统 bash-completion 安装位置并安装补全脚本 |
| `zsh/meson.build` | 安装 zsh 补全脚本到标准 site-functions 目录 |

---

## 3. 具体技术实现

### 3.1 Bash 补全实现细节

```bash
# 初始化补全框架
_init_completion || return

# 定义布尔选项（按 LC_ALL=C 排序）
local boolean_options="
    --as-pid-1
    --assert-userns-disabled
    ...
"

# 定义带参数选项（包含布尔选项作为子集）
local options_with_args="
    $boolean_options
    --add-seccomp-fd
    --args
    ...
"

# 仅对以 - 开头的输入提供补全
if [[ "$cur" == -* ]]; then
    COMPREPLY=( $( compgen -W "$boolean_options $options_with_args" -- "$cur" ) )
fi
```

**注意**：代码中存在一个拼写错误 `$boolean_optons`（应为 `$boolean_options`），但由于 `options_with_args` 实际使用时与 `boolean_options` 合并，该错误不影响功能。

### 3.2 Zsh 补全实现细节

#### 3.2.1 状态机设计

Zsh 补全使用 `_arguments` 的 `-S` 选项和状态标记实现上下文感知：

```zsh
_bwrap_args=(
    '*::arguments:_normal'  # 捕获所有剩余参数
    
    # 标准选项定义
    '--bind[description]:source:_files:destination:_files'
    '--perms[Set permissions]: :_guard "[0-7]#" "permissions in octal": :->after_perms'
    
    # 状态标记 ->after_perms 触发状态机切换
)

_bwrap() {
    _arguments -S $_bwrap_args
    case "$state" in
        after_perms)
            _values -S ' ' 'option' $_bwrap_args_after_perms
            ;;
        ...
    esac
}
```

#### 3.2.2 Capability 补全

```zsh
caps)
    local all_caps=(
        CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH ...
    )
    _values 'caps' $all_caps
    ;;
```

Capability 列表硬编码自 `/usr/include/linux/capability.h`，包含 38 个标准 Linux capabilities。

#### 3.2.3 选项分组逻辑

| 上下文 | 可用选项 | 说明 |
|--------|----------|------|
| 默认 | 所有 `_bwrap_args` 中的选项 | 完整选项集 |
| after_perms | `--bind-data`, `--dir`, `--file`, `--ro-bind-data`, `--size`, `--tmpfs` | 需要权限设置的选项 |
| after_size | `--perms`, `--tmpfs` | 需要大小设置的选项 |
| after_perms_size | `--tmpfs` | 同时需要权限和大小的选项 |

### 3.3 构建系统安装逻辑

#### Bash 补全安装 (`bash/meson.build`)

```meson
# 1. 检查用户是否指定了自定义目录
bash_completion_dir = get_option('bash_completion_dir')

# 2. 尝试从 pkg-config 获取系统标准路径
if bash_completion_dir == ''
  bash_completion = dependency('bash-completion', version : '>=2.0', required : false)
  if bash_completion.found()
    bash_completion_dir = bash_completion.get_variable(
      pkgconfig: 'completionsdir',
      ...
    )
  endif
endif

# 3. 回退到默认路径
if bash_completion_dir == ''
  bash_completion_dir = get_option('datadir') / 'bash-completion' / 'completions'
endif

# 4. 安装
install_data('bwrap', install_dir : bash_completion_dir)
```

#### Zsh 补全安装 (`zsh/meson.build`)

```meson
zsh_completion_dir = get_option('zsh_completion_dir')

if zsh_completion_dir == ''
  zsh_completion_dir = get_option('datadir') / 'zsh' / 'site-functions'
endif

install_data('_bwrap', install_dir : zsh_completion_dir)
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/vendor/bubblewrap/completions/
├── meson.build              # 条件子目录包含
├── bash/
│   ├── meson.build          # bash-completion 检测与安装逻辑
│   └── bwrap                # Bash 补全脚本（80行）
└── zsh/
    ├── meson.build          # zsh 补全安装逻辑
    └── _bwrap               # Zsh 补全脚本（115行）
```

### 4.2 关键代码引用

#### 4.2.1 Bash 补全脚本 (`bash/bwrap`)

| 行号 | 代码 | 说明 |
|------|------|------|
| 1 | `# shellcheck shell=bash` | ShellCheck 指令 |
| 6-8 | `_bwrap() { local cur prev words cword; _init_completion ...` | 补全函数框架 |
| 11-28 | `local boolean_options=...` | 布尔选项列表 |
| 31-70 | `local options_with_args=...` | 带参数选项列表 |
| 72-74 | `if [[ "$cur" == -* ]]; then COMPREPLY=...` | 补全逻辑 |
| 78 | `complete -F _bwrap bwrap` | 注册补全函数 |

#### 4.2.2 Zsh 补全脚本 (`zsh/_bwrap`)

| 行号 | 代码 | 说明 |
|------|------|------|
| 1 | `#compdef bwrap` | Zsh 补全定义指令 |
| 3-6 | `_bwrap_args_after_perms_size=...` | 权限+大小上下文选项 |
| 8-16 | `_bwrap_args_after_perms=...` | 权限上下文选项 |
| 18-22 | `_bwrap_args_after_size=...` | 大小上下文选项 |
| 24-83 | `_bwrap_args=(...)` | 主选项数组 |
| 85-115 | `_bwrap() { _arguments ... }` | 补全主函数 |
| 100-112 | `caps)` | Capability 补全逻辑 |

#### 4.2.3 Meson 构建文件

| 文件 | 关键代码 | 说明 |
|------|----------|------|
| `meson.build` | `if get_option('bash_completion').enabled()` | 条件包含 |
| `bash/meson.build` | `bash_completion = dependency('bash-completion', ...)` | 依赖检测 |
| `bash/meson.build` | `install_data('bwrap', install_dir : bash_completion_dir)` | 安装 |
| `zsh/meson.build` | `install_data('_bwrap', install_dir : zsh_completion_dir)` | 安装 |

### 4.3 与 bubblewrap 主程序的选项对应

补全脚本中的选项与 `bubblewrap.c` 中的命令行解析严格对应：

```c
// bubblewrap.c 中的选项解析（约 1788-2600 行）
if (strcmp (arg, "--help") == 0)
else if (strcmp (arg, "--version") == 0)
else if (strcmp (arg, "--args") == 0)
else if (strcmp (arg, "--bind") == 0 || strcmp(arg, "--bind-try") == 0)
...
```

补全脚本需要与主程序的选项保持同步，当 bubblewrap 新增选项时，补全脚本也需要更新。

---

## 5. 依赖与外部交互

### 5.1 构建时依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| meson | 构建系统 | 处理条件安装逻辑 |
| bash-completion (pkg-config) | 系统包 | 检测标准补全目录 |
| zsh | 系统包 | 目标 shell（仅运行时） |

### 5.2 运行时依赖

| 依赖 | 说明 |
|------|------|
| bash-completion >= 2.0 | Bash 补全需要加载框架（`/_init_completion`） |
| zsh + compinit | Zsh 补全需要启用补全系统 |
| bwrap | 被补全的目标命令 |

### 5.3 与 Codex 项目的交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex CLI (Node.js)                       │
├─────────────────────────────────────────────────────────────┤
│              codex-linux-sandbox (Rust)                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  bwrap.rs (参数构建)                                 │   │
│  │  - create_bwrap_command_args()                       │   │
│  │  - create_bwrap_flags()                              │   │
│  │  - create_filesystem_args()                          │   │
│  └─────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│              launcher.rs (执行层)                           │
│  - 优先使用 /usr/bin/bwrap                                  │
│  - 回退到 vendored_bwrap.rs (内嵌 C 代码)                    │
├─────────────────────────────────────────────────────────────┤
│         vendor/bubblewrap/completions/ (本目录)              │
│  - 仅用于开发和调试，Codex 运行时自动构建 bwrap 参数          │
└─────────────────────────────────────────────────────────────┘
```

### 5.4 上游项目关系

- **上游仓库**: https://github.com/containers/bubblewrap
- **Codex 中的位置**: `codex-rs/vendor/bubblewrap/`（作为 git subtree/submodule 或手动同步）
- **版本**: 当前 vendor 版本为 0.11.0（从 `meson.build` 读取）

---

## 6. 风险、边界与改进建议

### 6.1 已知问题

#### 6.1.1 Bash 补全脚本中的拼写错误

```bash
# bash/bwrap 第 32 行
local options_with_args="
    $boolean_optons  # <-- 应为 $boolean_options
    ...
"
```

**影响**: 低。`options_with_args` 实际使用时与 `boolean_options` 合并，该变量引用错误不影响功能。

#### 6.1.2 选项同步延迟

补全脚本中的选项列表是手动维护的，当 bubblewrap 主程序新增选项时，补全脚本可能滞后更新。

**当前缺失的选项**（对比 bubblewrap.c）：
- `--bind-fd` / `--ro-bind-fd`（Zsh 有，Bash 无）
- `--share-net`（Bash 无）
- `--level-prefix`（两者均无）

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 旧版 bash-completion | `< 2.0` 版本可能不支持某些特性，但基本功能可用 |
| 无 pkg-config | 使用默认路径安装，可能不符合发行版规范 |
| 用户自定义前缀 | 支持 `bash_completion_dir` 和 `zsh_completion_dir` 选项覆盖 |
| 子项目构建 | `meson.is_subproject()` 为真时仍安装补全（除非显式禁用） |

### 6.3 安全考虑

- 补全脚本本身不执行特权操作，仅提供文本补全
- 不涉及沙箱安全策略的定义（这些在 `bwrap.rs` 中处理）
- 不处理用户输入的验证（由 bubblewrap 主程序处理）

### 6.4 改进建议

#### 6.4.1 短期改进

1. **修复拼写错误**
   ```bash
   # bash/bwrap 第 32 行
   $boolean_optons → $boolean_options
   ```

2. **同步缺失选项**
   - 添加 `--bind-fd`, `--ro-bind-fd`, `--share-net`, `--level-prefix` 到 Bash 补全
   - 添加 `--level-prefix` 到 Zsh 补全

3. **添加注释说明**
   - 在选项列表顶部添加注释，指向 bubblewrap.c 中对应选项的定义位置
   - 添加维护说明，提示更新时需要同步检查

#### 6.4.2 中期改进

1. **自动生成补全脚本**
   - 从 bubblewrap.c 的选项定义自动生成补全脚本
   - 可通过解析 `usage()` 函数或添加结构化元数据实现

2. **Fish shell 支持**
   - 添加 `completions/fish/bwrap.fish` 以支持 Fish 用户

3. **选项分类**
   - 在 Bash 补全中增加选项分组（如命名空间选项、挂载选项、环境选项）

#### 6.4.3 长期改进

1. **动态补全**
   - 为 `--args FD` 支持从文件描述符读取参数并补全
   - 为 `--userns FD` 等选项提供可用的命名空间列表（如果可行）

2. **集成测试**
   - 添加测试验证补全脚本与主程序选项的同步性
   - 在 CI 中检查选项覆盖率

### 6.5 Codex 项目特定建议

由于 Codex 使用 vendored bubblewrap，建议：

1. **文档化版本同步流程**
   - 记录当前 vendor 的 bubblewrap 版本
   - 建立升级检查清单，包含补全脚本同步验证

2. **考虑移除补全脚本**
   - 如果 Codex 仅通过程序调用 bwrap（非交互式），可考虑不安装补全脚本
   - 在 `meson.build` 中设置 `-Dbash_completion=disabled -Dzsh_completion=disabled`

3. **监控上游更新**
   - 关注 bubblewrap 发布说明中的 CLI 变更
   - 在升级 vendor 时同步更新补全脚本

---

## 附录：选项对照表

### Bash 补全选项覆盖

| 选项 | Bash | Zsh | bubblewrap.c |
|------|------|-----|--------------|
| --help | ✓ | ✓ | ✓ |
| --version | ✓ | ✓ | ✓ |
| --args | ✓ | ✓ | ✓ |
| --argv0 | ✓ | ✓ | ✓ |
| --bind | ✓ | ✓ | ✓ |
| --bind-try | - | ✓ | ✓ |
| --bind-fd | - | ✓ | ✓ |
| --ro-bind-fd | - | ✓ | ✓ |
| --unshare-all | ✓ | ✓ | ✓ |
| --share-net | - | - | ✓ |
| --level-prefix | - | - | ✓ |
| ... | ... | ... | ... |

（完整对照需逐项检查，建议作为维护任务执行）
