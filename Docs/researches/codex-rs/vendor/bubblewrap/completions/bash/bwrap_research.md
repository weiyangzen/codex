# bwrap - Bash 自动补全脚本研究文档

## 场景与职责

`bwrap` 是 Bubblewrap 项目的 Bash 自动补全脚本，位于 `codex-rs/vendor/bubblewrap/completions/bash/bwrap`。Bubblewrap 是一个轻量级的沙箱工具，用于在 Linux 上创建非特权容器环境。该脚本为 `bwrap` 命令提供交互式命令行补全功能，帮助用户快速输入复杂的沙箱配置选项。

### 核心职责

1. **命令行参数补全**：为 `bwrap` 的所有命令行选项提供 Tab 键自动补全
2. **选项分类管理**：将选项分为布尔选项（无参数）和带参数选项两类
3. **提升用户体验**：减少用户记忆大量复杂选项的负担，降低输入错误

## 功能点目的

### 1. 布尔选项补全

布尔选项是不需要额外参数的开关选项，例如：
- `--as-pid-1`：不安装 PID=1 的 reaper 进程
- `--clearenv`：清除所有环境变量
- `--unshare-all`：解离所有支持的命名空间
- `--help`, `--version`：帮助和版本信息

### 2. 带参数选项补全

带参数选项需要额外的值，例如：
- `--bind SRC DEST`：绑定挂载主机路径
- `--uid UID`：设置沙箱中的用户 ID
- `--gid GID`：设置沙箱中的组 ID
- `--hostname NAME`：设置沙箱主机名
- `--setenv VAR VALUE`：设置环境变量

### 3. 选项分类策略

脚本将所有选项分为两个集合：
- `boolean_options`：纯开关选项
- `options_with_args`：包含布尔选项和所有带参数选项（用于完整补全）

## 具体技术实现

### 关键数据结构

```bash
# 布尔选项列表（按 LC_ALL=C 排序）
local boolean_options="
    --as-pid-1
    --assert-userns-disabled
    --clearenv
    ...
"

# 带参数选项列表（包含所有选项）
local options_with_args="
    $boolean_optons  # 注意：这里有拼写错误 'optons'
    --add-seccomp-fd
    --args
    --argv0
    ...
"
```

### 核心补全逻辑

```bash
if [[ "$cur" == -* ]]; then
    COMPREPLY=( $( compgen -W "$boolean_options $options_with_args" -- "$cur" ) )
fi
```

**逻辑说明**：
1. 检查当前输入 `$cur` 是否以 `-` 开头
2. 如果是，使用 `compgen -W` 从选项列表中生成匹配项
3. 将结果赋值给 `COMPREPLY` 数组，Bash 使用它显示补全建议

### Bash Completion 框架集成

```bash
# 初始化补全系统
_init_completion || return

# 注册补全函数
complete -F _bwrap bwrap
```

**依赖的 Bash 内置和工具**：
- `_init_completion`：bash-completion 包提供的初始化函数
- `compgen`：Bash 内置命令，生成补全匹配
- `complete -F`：将函数注册为命令的补全处理器

### 变量说明

| 变量 | 来源 | 用途 |
|------|------|------|
| `cur` | `_init_completion` | 当前正在输入的词 |
| `prev` | `_init_completion` | 前一个词 |
| `words` | `_init_completion` | 命令行所有词数组 |
| `cword` | `_init_completion` | 当前词的索引 |
| `COMPREPLY` | 输出 | 补全建议数组 |

## 关键代码路径与文件引用

### 文件位置

```
codex-rs/vendor/bubblewrap/completions/bash/
├── bwrap              # 本文件（Bash 补全脚本）
└── meson.build        # Meson 构建配置
```

### 构建系统集成

`meson.build` 控制补全脚本的安装：

```meson
# 检测 bash-completion 安装位置
bash_completion_dir = get_option('bash_completion_dir')

# 如果未指定，尝试从 pkg-config 获取
if bash_completion.found()
    bash_completion_dir = bash_completion.get_variable(
        pkgconfig: 'completionsdir',
        ...
    )
endif

# 默认安装路径
if bash_completion_dir == ''
    bash_completion_dir = get_option('datadir') / 'bash-completion' / 'completions'
endif

# 安装补全脚本
install_data('bwrap', install_dir : bash_completion_dir)
```

### 上游引用

- 主项目：`codex-rs/vendor/bubblewrap/bubblewrap.c`（bwrap 主程序）
- 手册页：`codex-rs/vendor/bubblewrap/bwrap.xml`（DocBook 格式）
- 构建配置：`codex-rs/vendor/bubblewrap/meson.build`
- 选项定义：`codex-rs/vendor/bubblewrap/meson_options.txt`

## 依赖与外部交互

### 运行时依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| bash-completion | 可选 | 提供 `_init_completion` 函数 |
| Bash | 必需 | 脚本执行环境 |

### 构建时依赖

| 依赖 | 类型 | 说明 |
|------|------|------|
| bash-completion (>=2.0) | 可选 | 用于检测 completionsdir |
| meson (>=0.49.0) | 必需 | 构建系统 |

### 与其他补全脚本的对比

项目同时提供 Zsh 补全脚本（`completions/zsh/_bwrap`），功能更强大：
- Zsh 版本支持参数级别的补全（如 `--cap-add` 后补全能力名）
- Zsh 版本支持状态机（state machine）处理复杂选项序列
- Bash 版本仅支持简单的选项名补全

## 风险、边界与改进建议

### 已知问题

1. **拼写错误**：第 32 行 `$boolean_optons` 应为 `$boolean_options`
   - 影响：带参数选项列表实际上未包含布尔选项（虽然最终补全合并了两个列表，所以功能上没问题）
   - 修复建议：修正拼写错误

2. **补全粒度有限**：
   - 不区分哪些选项需要文件路径参数
   - 不区分哪些选项需要数字参数
   - 不支持选项的参数值补全（如 `--cap-add` 后的能力名）

3. **排序维护**：注释要求保持 LC_ALL=C 顺序，但人工维护容易出错

### 边界情况

1. **bash-completion 未安装**：`_init_completion` 函数不存在时脚本会失败
2. **旧版本 Bash**：某些语法可能在极旧版本 Bash 上不兼容
3. **自定义前缀**：当使用 `program_prefix` 选项构建时，补全脚本名需要相应调整

### 改进建议

1. **修复拼写错误**：
   ```bash
   local options_with_args="
       $boolean_options  # 修正拼写
       ...
   "
   ```

2. **增强补全粒度**：参考 Zsh 版本，为常用选项添加参数补全：
   ```bash
   case "$prev" in
       --cap-add|--cap-drop)
           COMPREPLY=( $( compgen -W "CAP_CHOWN CAP_KILL ..." -- "$cur" ) )
           return
           ;;
       --uid|--gid)
           # 不提供补全，但可验证输入是否为数字
           ;;
   esac
   ```

3. **自动化维护**：
   - 从 `bubblewrap.c` 或 `bwrap.xml` 自动生成选项列表
   - 在 CI 中验证选项列表与主程序同步

4. **兼容性改进**：
   ```bash
   # 添加对 _init_completion 的兼容性检查
   if ! type _init_completion &>/dev/null; then
       # 回退到基本补全逻辑
       cur="${COMP_WORDS[COMP_CWORD]}"
       prev="${COMP_WORDS[COMP_CWORD-1]}"
   fi
   ```

5. **与主程序同步**：
   - 当前选项列表基于 bubblewrap 0.11.0
   - 需要定期与 `bubblewrap.c` 中的选项定义同步
   - 建议添加版本检查注释

### 安全考虑

- 补全脚本本身不执行特权操作
- 仅影响交互式 shell 体验
- 不会影响沙箱的安全性
