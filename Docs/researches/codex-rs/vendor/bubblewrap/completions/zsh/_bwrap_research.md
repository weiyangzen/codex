# Zsh Completion Script for Bubblewrap (`_bwrap`)

## 场景与职责

`_bwrap` 是 Bubblewrap 沙箱工具的 Zsh 命令补全脚本，位于 `codex-rs/vendor/bubblewrap/completions/zsh/_bwrap`。该文件为 Zsh 用户提供交互式的命令行参数补全功能，帮助用户快速、准确地构建复杂的沙箱命令。

### 核心职责
1. **参数补全**：为 `bwrap` 命令的所有选项（options）提供智能补全
2. **上下文感知**：根据当前输入的选项，动态调整后续可用选项（如 `--perms` 后允许 `--size`）
3. **值验证**：对特定参数类型（如文件描述符、权限八进制数、能力名）提供格式验证和补全
4. **文件路径补全**：对涉及路径的选项（如 `--bind`, `--tmpfs`）提供文件系统补全

### 在项目中的位置
- 上游项目：[containers/bubblewrap](https://github.com/containers/bubblewrap)
- 本地路径：`codex-rs/vendor/bubblewrap/completions/zsh/_bwrap`
- 安装目标：`/usr/share/zsh/site-functions/_bwrap`（默认可配置）

---

## 功能点目的

### 1. 选项分类与组织

脚本将 `bwrap` 的众多选项按功能逻辑分组，便于维护和补全逻辑实现：

| 选项数组 | 包含选项 | 触发条件 |
|---------|---------|---------|
| `_bwrap_args` | 所有主要选项 | 默认补全 |
| `_bwrap_args_after_perms` | `--size`, `--bind-data`, `--file` 等 | 在 `--perms` 后可用 |
| `_bwrap_args_after_size` | `--perms`, `--tmpfs` | 在 `--size` 后可用 |
| `_bwrap_args_after_perms_size` | `--tmpfs` | 在 `--perms --size` 或 `--size --perms` 后可用 |

### 2. 参数类型智能补全

| 选项类型 | 补全行为 | 实现方式 |
|---------|---------|---------|
| 文件路径 (`--bind`, `--ro-bind` 等) | 文件/目录补全 | `_files` 辅助函数 |
| 目录路径 (`--tmpfs`, `--proc`, `--dev`) | 仅目录补全 | `_files -/` |
| 文件描述符 (`--seccomp`, `--args` 等) | 数字验证 | `_guard "[0-9]#" "description"` |
| 权限八进制 (`--perms`, `--chmod`) | 八进制数字验证 | `_guard "[0-7]#" "permissions in octal"` |
| SELinux 标签 (`--exec-label`, `--file-label`) | SELinux 上下文补全 | `_selinux_contexts` |
| Linux 能力 (`--cap-add`, `--cap-drop`) | 预定义能力名列表 | 硬编码 `all_caps` 数组 |

### 3. 能力名补全

脚本硬编码了 Linux 内核支持的所有能力（capabilities）：

```zsh
local all_caps=(
    CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID
    CAP_KILL CAP_SETGID CAP_SETUID CAP_SETPCAP CAP_LINUX_IMMUTABLE
    CAP_NET_BIND_SERVICE CAP_NET_BROADCAST CAP_NET_ADMIN CAP_NET_RAW
    CAP_IPC_LOCK CAP_IPC_OWNER CAP_SYS_MODULE CAP_SYS_RAWIO CAP_SYS_CHROOT
    CAP_SYS_PTRACE CAP_SYS_PACCT CAP_SYS_ADMIN CAP_SYS_BOOT CAP_SYS_NICE
    CAP_SYS_RESOURCE CAP_SYS_TIME CAP_SYS_TTY_CONFIG CAP_MKNOD CAP_LEASE
    CAP_AUDIT_WRITE CAP_AUDIT_CONTROL CAP_SETFCAP CAP_MAC_OVERRIDE
    CAP_MAC_ADMIN CAP_SYSLOG CAP_WAKE_ALARM CAP_BLOCK_SUSPEND CAP_AUDIT_READ
)
```

> 注：注释中提供了从内核头文件提取能力名的命令：
> `grep -E '#define\sCAP_\w+\s+[0-9]+' /usr/include/linux/capability.h`

---

## 具体技术实现

### 1. Zsh 补全系统基础

```zsh
#compdef bwrap
```
- 文件首行的 `#compdef` 指令告诉 Zsh 该文件为 `bwrap` 命令提供补全
- 文件必须位于 `$fpath` 中的某个目录才能被 Zsh 加载

### 2. 核心补全函数 `_bwrap()`

```zsh
_bwrap() {
    _arguments -S $_bwrap_args
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
        caps)
            _values 'caps' $all_caps
            ;;
    esac
}
```

**关键技术点：**
- `_arguments -S`：解析命令行选项，`-S` 允许选项和参数之间有空格
- `->state`：当选项需要特殊处理时，设置 `$state` 变量并跳转到 case 语句
- `_values`：从预定义列表中提供补全值

### 3. 选项定义语法

每个选项定义遵循格式：
```
'--option-name[description]:placeholder:action'
```

**示例解析：**
```zsh
'--bind[Bind mount the host path SRC on DEST]:source:_files:destination:_files'
```
- `--bind`：选项名
- `Bind mount...`：帮助描述（按 `LC_ALL=C` 字母顺序排序）
- `source`：第一个参数的占位符描述
- `_files`：第一个参数的补全动作（文件补全）
- `destination`：第二个参数的占位符描述
- `_files`：第二个参数的补全动作

**条件依赖选项：**
```zsh
'(--clearenv)--unsetenv[Unset an environment variable]:...'
```
- `(--clearenv)`：表示该选项与 `--clearenv` 有互斥或依赖关系

### 4. 状态机处理流程

```
用户输入 --perms <octal>
         ↓
    _arguments 解析，设置 state="after_perms"
         ↓
    case "$state" in
        after_perms)
            _values ... $_bwrap_args_after_perms
            ;;
    esac
         ↓
    提供 --size, --bind-data, --file 等后续选项补全
```

---

## 关键代码路径与文件引用

### 本文件内部结构

```
_bwrap (115 lines)
├── 行 1      #compdef bwrap
├── 行 3-6    _bwrap_args_after_perms_size 定义
├── 行 8-16   _bwrap_args_after_perms 定义
├── 行 18-22  _bwrap_args_after_size 定义
├── 行 24-83  _bwrap_args 主选项数组定义
├── 行 85-115 _bwrap() 补全函数实现
│   ├── 行 86 _arguments 调用
│   └── 行 87-114 state case 处理
```

### 相关文件引用

| 文件路径 | 关系 | 说明 |
|---------|------|------|
| `codex-rs/vendor/bubblewrap/bwrap.xml` | 文档源 | DocBook 格式的 man 页源文件，定义了所有选项的正式文档 |
| `codex-rs/vendor/bubblewrap/bubblewrap.c` | 实现源 | bwrap 主程序，包含选项解析逻辑 |
| `codex-rs/vendor/bubblewrap/completions/bash/bwrap` | 平行实现 | Bash 补全脚本，功能类似但实现方式不同 |
| `codex-rs/vendor/bubblewrap/completions/zsh/meson.build` | 构建配置 | 定义安装逻辑 |
| `codex-rs/vendor/bubblewrap/completions/meson.build` | 父构建配置 | 条件编译控制 |
| `codex-rs/vendor/bubblewrap/meson_options.txt` | 构建选项 | 定义 `zsh_completion` 和 `zsh_completion_dir` 选项 |

### 与 Bash 补全脚本的对比

| 特性 | Zsh (`_bwrap`) | Bash (`bwrap`) |
|------|---------------|----------------|
| 实现复杂度 | 高（状态机、类型验证） | 低（简单字符串列表） |
| 路径补全 | 原生 `_files` 支持 | 依赖 `_init_completion` |
| 动态选项 | 支持（`--perms` 后选项变化） | 不支持（静态列表） |
| 能力名补全 | 完整列表 | 无 |
| SELinux 支持 | `_selinux_contexts` | 无 |

---

## 依赖与外部交互

### 1. Zsh 内置/标准补全函数

| 函数 | 来源 | 用途 |
|------|------|------|
| `_arguments` | Zsh 标准补全库 | 解析 GNU 风格长选项 |
| `_values` | Zsh 标准补全库 | 从列表提供补全值 |
| `_guard` | Zsh 标准补全库 | 验证输入格式（正则匹配） |
| `_files` | Zsh 标准补全库 | 文件路径补全 |
| `_selinux_contexts` | Zsh 标准补全库 | SELinux 上下文补全 |
| `_parameters` | Zsh 标准补全库 | 参数/变量补全（用于 `--setenv`） |

### 2. 构建系统依赖

```meson
# meson_options.txt
option('zsh_completion', type: 'feature', value: 'enabled')
option('zsh_completion_dir', type: 'string', value: '')
```

安装路径优先级：
1. 用户指定的 `zsh_completion_dir`
2. 默认路径：`${datadir}/zsh/site-functions`

### 3. 运行时依赖

- **Zsh 版本**：需要支持 `_arguments` 和状态机功能的现代 Zsh（通常 5.0+）
- **SELinux 支持**：`_selinux_contexts` 仅在启用了 SELinux 补全支持的 Zsh 安装中可用

---

## 风险、边界与改进建议

### 1. 已知风险

#### 选项同步风险
- **问题**：`bwrap` 主程序新增选项后，补全脚本可能未及时更新
- **影响**：用户无法补全新选项，或补全已废弃选项
- **缓解**：上游维护者在 `release-checklist.md` 中应包含补全脚本更新检查

#### 能力名硬编码
- **问题**：`all_caps` 数组硬编码在脚本中，内核新增能力时需要手动更新
- **当前列表**：基于较旧内核版本，缺少如 `CAP_PERFMON`, `CAP_BPF`, `CAP_CHECKPOINT_RESTORE` 等新能力（Linux 5.8+）
- **建议**：添加注释说明如何更新，或考虑动态提取

#### 选项互斥关系不完整
- **问题**：脚本仅标记了部分互斥关系（如 `--clearenv` 与 `--unsetenv`）
- **遗漏**：如 `--unshare-user` 与 `--userns` 的互斥关系未在补全中强制限制

### 2. 边界情况

#### 复合选项顺序
- `--perms` 和 `--size` 可以任意顺序组合，脚本通过 `after_perms_size` 状态正确处理
- 但三个及以上修饰选项的组合（如 `--perms --size --another`）未定义

#### 文件描述符验证
- 使用 `_guard "[0-9]#"` 仅验证输入为数字，不验证 FD 是否实际存在
- 这是设计选择（FD 可能在运行时动态创建）

#### 长选项与短选项
- `bwrap` 实际上**没有**短选项（如 `-h`），脚本正确反映了这一点
- 用户输入 `-` 时不会触发补全

### 3. 改进建议

#### 短期改进

1. **更新能力列表**
   ```zsh
   # 添加 Linux 5.8+ 新增能力
   CAP_PERFMON CAP_BPF CAP_CHECKPOINT_RESTORE
   ```

2. **添加更多互斥关系标记**
   ```zsh
   '(--userns --userns2)--unshare-user[...]'
   '(--unshare-user)--userns[...]'
   ```

3. **改进 `--setenv` 补全**
   - 当前仅补全变量名，可改进为 `VAR=value` 格式支持

#### 中期改进

1. **动态选项生成**
   - 考虑从 `bwrap --help` 输出自动生成补全脚本
   - 或添加测试用例验证选项同步

2. **上下文感知增强**
   - `--bind` 后根据第一个参数自动过滤第二个参数的补全类型
   - 检测已使用的互斥选项并禁用冲突选项

3. **文档集成**
   - 在补全提示中显示更详细的选项说明（从 bwrap.xml 提取）

#### 长期考虑

1. **与上游同步机制**
   - 建议 bubblewrap 项目添加 CI 检查，确保补全脚本与主程序选项同步
   
2. **多版本支持**
   - 考虑根据 `bwrap --version` 输出调整可用选项

### 4. 测试建议

```zsh
# 手动测试命令
source completions/zsh/_bwrap
compdef _bwrap bwrap

# 测试场景
bwrap --<TAB>          # 应显示所有选项
bwrap --perms 700 --<TAB>  # 应显示 after_perms 选项
bwrap --cap-add <TAB>  # 应显示能力名列表
bwrap --bind /etc/<TAB> # 应提供文件补全
```

---

## 附录：选项覆盖对照表

| bwrap 选项 | 补全脚本支持 | 补全类型 | 备注 |
|-----------|-------------|---------|------|
| `--help`, `--version` | ✅ | 布尔 | - |
| `--args` | ✅ | FD 数字 | - |
| `--argv0` | ✅ | 字符串 | - |
| `--as-pid-1` | ✅ | 布尔 | - |
| `--bind`, `--bind-try` | ✅ | 路径:路径 | - |
| `--block-fd` | ✅ | FD 数字 | - |
| `--cap-add`, `--cap-drop` | ✅ | 能力名 | 硬编码列表 |
| `--chdir` | ✅ | 目录 | - |
| `--chmod` | ✅ | 八进制:路径 | - |
| `--clearenv` | ✅ | 布尔 | - |
| `--dev-bind`, `--dev-bind-try` | ✅ | 路径:路径 | - |
| `--dev` | ✅ | 目录 | - |
| `--die-with-parent` | ✅ | 布尔 | - |
| `--disable-userns` | ✅ | 布尔 | - |
| `--exec-label`, `--file-label` | ✅ | SELinux 标签 | - |
| `--gid`, `--uid` | ✅ | 数字 | - |
| `--hostname` | ✅ | 字符串 | - |
| `--info-fd`, `--json-status-fd` | ✅ | FD 数字 | - |
| `--lock-file` | ✅ | 路径 | - |
| `--mqueue` | ✅ | 目录 | - |
| `--new-session` | ✅ | 布尔 | - |
| `--perms` | ✅ | 八进制 | 触发状态机 |
| `--proc` | ✅ | 目录 | - |
| `--remount-ro` | ✅ | 路径 | - |
| `--ro-bind`, `--ro-bind-try` | ✅ | 路径:路径 | - |
| `--seccomp`, `--add-seccomp-fd` | ✅ | FD 数字 | - |
| `--setenv` | ✅ | 变量名:值 | - |
| `--size` | ✅ | 数字 | 触发状态机 |
| `--symlink` | ✅ | 路径:路径 | - |
| `--sync-fd` | ✅ | FD 数字 | - |
| `--unsetenv` | ✅ | 变量名 | 依赖 `--clearenv` |
| `--unshare-*` | ✅ | 布尔 | 多个选项 |
| `--userns`, `--userns2` | ✅ | 字符串 | - |
| `--userns-block-fd` | ✅ | FD 数字 | - |
| `--tmpfs` | ✅ | 目录 | 受 `--perms`/`--size` 影响 |

> 注：`--overlay`, `--overlay-src`, `--tmp-overlay`, `--ro-overlay` 等 overlay 相关选项在补全脚本中**未实现**，但在 Bash 补全脚本中有定义。这可能是 Zsh 补全脚本的遗漏。
