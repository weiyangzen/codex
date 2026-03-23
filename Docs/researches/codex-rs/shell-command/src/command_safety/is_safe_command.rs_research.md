# is_safe_command.rs 研究文档

## 场景与职责

`is_safe_command.rs` 是 Codex 项目中命令安全检测模块的核心组件，与 `is_dangerous_command.rs` 形成互补的安全评估体系。该模块的主要职责是：

1. **安全命令白名单**：维护一个已知安全的命令列表，允许自动批准执行
2. **细粒度参数检查**：对特定命令的参数进行深度检查，识别潜在风险
3. **跨平台安全策略**：提供 Windows 和 Unix-like 系统的安全命令评估
4. **嵌套脚本安全评估**：解析 `bash -lc` 和 PowerShell 脚本中的命令序列

该模块是 TUI 自动批准机制的关键决策组件，当命令被判定为"已知安全"时，用户无需手动确认即可执行。

## 功能点目的

### 1. `is_known_safe_command` - 主入口函数

接收命令参数列表，返回布尔值表示命令是否已知安全。

**处理流程**：
1. **Shell 别名转换**：将 `zsh` 转换为 `bash` 进行统一处理
2. **Windows 安全检测**：调用 `is_safe_command_windows`
3. **直接安全检测**：调用 `is_safe_to_call_with_exec`
4. **嵌套脚本解析**：解析 `bash -lc` 脚本，验证所有子命令都安全

### 2. `is_safe_to_call_with_exec` - 核心安全评估

对单个命令进行详细的安全评估，支持多种命令类型：

#### 2.1 基础安全命令白名单

```rust
"cat" | "cd" | "cut" | "echo" | "expr" | "false" | "grep" | "head" | "id" |
"ls" | "nl" | "paste" | "pwd" | "rev" | "seq" | "stat" | "tail" | "tr" |
"true" | "uname" | "uniq" | "wc" | "which" | "whoami"
```

#### 2.2 Linux 特定命令

- `numfmt`：数字格式化
- `tac`：反向输出文件

#### 2.3 参数敏感命令

| 命令 | 安全条件 | 风险参数 |
|------|----------|----------|
| `base64` | 不包含输出选项 | `-o`, `--output` |
| `find` | 不包含执行/删除选项 | `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fls`, `-fprint`, `-fprint0`, `-fprintf` |
| `rg` (ripgrep) | 不包含外部命令选项 | `--pre`, `--hostname-bin`, `--search-zip`, `-z` |
| `git` | 只读子命令 + 无危险标志 | 见下文详细分析 |
| `sed` | 特定模式 `-n {N|M,N}p` | 其他所有模式 |

#### 2.4 Git 命令安全评估

**安全检查层级**：

1. **配置覆盖检测**：
   ```rust
   fn git_has_config_override_global_option(command: &[String]) -> bool {
       command.iter().map(String::as_str).any(|arg| {
           matches!(arg, "-c" | "--config-env")
               || (arg.starts_with("-c") && arg.len() > 2)
               || arg.starts_with("--config-env=")
       })
   }
   ```
   
   **安全风险**：`-c core.pager=cat` 等配置覆盖可能执行任意命令

2. **安全子命令白名单**：`status`, `log`, `diff`, `show`, `branch`

3. **子命令参数检查**：
   - `git branch` 只读检测：`--list`, `-l`, `--show-current`, `-a`, `--all`, `-r`, `--remotes`, `-v`, `-vv`, `--verbose`, `--format=`
   - 通用不安全标志：`--output`, `--ext-diff`, `--textconv`, `--exec`, `--paginate`

#### 2.5 Sed 安全模式

仅允许 `-n` 标志后跟行号选择模式（如 `1,5p`）：

```rust
fn is_valid_sed_n_arg(arg: Option<&str>) -> bool {
    // 匹配 /^(d+,)?d+p$/
    // 有效: "10", "1,5"
    // 无效: "xp", "1,2,3"
}
```

### 3. 嵌套脚本支持

通过 `parse_shell_lc_plain_commands` 解析 `bash -lc` 脚本：

```rust
if let Some(all_commands) = parse_shell_lc_plain_commands(&command)
    && !all_commands.is_empty()
    && all_commands
        .iter()
        .all(|cmd| is_safe_to_call_with_exec(cmd))
{
    return true;
}
```

**支持的操作符**：`&&`, `||`, `;`, `|`

## 具体技术实现

### Git 子命令查找

复用 `is_dangerous_command.rs` 中的 `find_git_subcommand`：

```rust
let Some((subcommand_idx, subcommand)) =
    find_git_subcommand(command, &["status", "log", "diff", "show", "branch"])
else {
    return false;
};
```

### Git Branch 只读检测

```rust
fn git_branch_is_read_only(branch_args: &[String]) -> bool {
    if branch_args.is_empty() {
        return true; // `git branch` 列出分支
    }

    let mut saw_read_only_flag = false;
    for arg in branch_args.iter().map(String::as_str) {
        match arg {
            "--list" | "-l" | "--show-current" | "-a" | "--all" | "-r" | "--remotes" | "-v" | "-vv" | "--verbose" => {
                saw_read_only_flag = true;
            }
            _ if arg.starts_with("--format=") => {
                saw_read_only_flag = true;
            }
            _ => return false, // 任何其他参数都可能是危险的
        }
    }
    saw_read_only_flag
}
```

### Find 命令安全检查

```rust
const UNSAFE_FIND_OPTIONS: &[&str] = &[
    // 执行任意命令
    "-exec", "-execdir", "-ok", "-okdir",
    // 删除文件
    "-delete",
    // 写入文件
    "-fls", "-fprint", "-fprint0", "-fprintf",
];

!command.iter().any(|arg| UNSAFE_FIND_OPTIONS.contains(&arg.as_str()))
```

### Ripgrep 安全检查

```rust
const UNSAFE_RIPGREP_OPTIONS_WITH_ARGS: &[&str] = &["--pre", "--hostname-bin"];
const UNSAFE_RIPGREP_OPTIONS_WITHOUT_ARGS: &[&str] = &["--search-zip", "-z"];
```

## 关键代码路径与文件引用

### 模块依赖图

```
is_safe_command.rs
├── is_known_safe_command() [入口]
│   ├── is_safe_command_windows() [Windows安全检测]
│   │   └── windows_safe_commands.rs
│   ├── is_safe_to_call_with_exec() [核心安全评估]
│   │   ├── executable_name_lookup_key()
│   │   ├── base64 参数检查
│   │   ├── find 参数检查
│   │   ├── rg 参数检查
│   │   ├── git 安全评估
│   │   │   ├── git_has_config_override_global_option()
│   │   │   ├── find_git_subcommand() [from is_dangerous_command]
│   │   │   ├── git_subcommand_args_are_read_only()
│   │   │   └── git_branch_is_read_only()
│   │   └── sed 模式检查
│   │       └── is_valid_sed_n_arg()
│   └── parse_shell_lc_plain_commands() [嵌套脚本]
│       └── is_safe_to_call_with_exec() [递归]
└── find_git_subcommand() [导入]
    └── is_dangerous_command.rs
```

### 跨文件依赖

| 依赖文件 | 导入内容 | 用途 |
|----------|----------|------|
| `bash.rs` | `parse_shell_lc_plain_commands` | 解析嵌套脚本 |
| `is_dangerous_command.rs` | `find_git_subcommand`, `executable_name_lookup_key` | Git 命令解析 |
| `windows_safe_commands.rs` | `is_safe_command_windows` | Windows 安全检测 |

## 依赖与外部交互

### 导入依赖

```rust
use crate::bash::parse_shell_lc_plain_commands;
use crate::command_safety::is_dangerous_command::executable_name_lookup_key;
use crate::command_safety::is_dangerous_command::find_git_subcommand;
use crate::command_safety::windows_safe_commands::is_safe_command_windows;
```

### 平台特定代码

- Linux 特定：`numfmt`, `tac` 命令支持
- Windows 特定：通过 `windows_safe_commands.rs` 处理

## 风险、边界与改进建议

### 当前风险与边界

1. **白名单方法的局限性**
   - 只能识别明确列入白名单的命令
   - 新命令或非常用命令默认不安全
   - 可能过度保守，影响用户体验

2. **参数解析的复杂性**
   - 各命令的参数检查逻辑分散，难以维护
   - 某些命令的复杂参数组合可能绕过检查
   - 例如：`git log --output=/tmp/x` 被检测，但 `--output /tmp/x` 呢？

3. **Git 安全评估的边界情况**
   - `git branch` 的只读检测依赖明确的标志
   - 分支名可能与标志冲突（虽然罕见）
   - 某些 Git 配置可能影响命令行为

4. **嵌套脚本解析限制**
   - 依赖 tree-sitter 的解析能力
   - 复杂 shell 结构被拒绝
   - 引号处理可能有边界情况

5. **平台差异**
   - Windows 和非 Windows 的安全策略不同
   - PowerShell 和 CMD 的复杂性

### 测试覆盖分析

当前测试覆盖：
- ✅ 基础安全命令（ls, cat, grep 等）
- ✅ Git 子命令和全局选项
- ✅ Git branch 变异标志检测
- ✅ Base64 输出选项
- ✅ Find 不安全选项
- ✅ Ripgrep 不安全选项
- ✅ Sed 模式验证
- ✅ bash -lc 安全示例
- ✅ bash -lc 不安全示例（操作符、重定向、子 shell）
- ✅ zsh 别名支持
- ✅ Windows 全路径调用

### 改进建议

1. **统一安全评估框架**
   ```rust
   // 建议：定义统一的安全评估 trait
   trait CommandSafetyChecker {
       fn check(&self, command: &[String]) -> SafetyResult;
   }
   
   enum SafetyResult {
       Safe,
       Unsafe { reason: String },
       Unknown,
   }
   ```

2. **增强 Git 安全检测**
   - 添加更多只读子命令（`ls-files`, `ls-tree`, `show-ref` 等）
   - 检测 `git config` 的写入操作
   - 考虑 `git worktree` 的安全性

3. **扩展安全命令列表**
   - 添加 `file`, `stat`, `readlink` 等只读命令
   - 考虑容器/虚拟化命令（`docker ps`, `kubectl get` 等）

4. **改进参数解析**
   - 使用更结构化的参数解析（如 clap 的解析器）
   - 统一处理 `--flag=value` 和 `--flag value` 形式

5. **安全日志和审计**
   - 记录安全评估决策原因
   - 提供用户可理解的安全评估解释

6. **与危险命令检测的整合**
   - 当前 `is_safe_command` 和 `is_dangerous_command` 是独立判断
   - 考虑定义明确的安全状态机：
     ```
     Unknown -> SafetyAnalysis -> Safe / Unsafe / NeedsReview
     ```

### 潜在安全边界情况

1. **Git 配置覆盖绕过**
   ```bash
   # 当前检测
   git -c core.pager=cat status  # 被检测为不安全
   
   # 潜在的绕过（需要验证）
   git --config-env=VAR status   # 是否被正确检测？
   ```

2. **Find 命令的复杂参数**
   ```bash
   # 当前检测基于简单字符串匹配
   find . -name "*.txt" -exec rm {} \;  # 被检测
   
   # 潜在的边界
   find . -name "*.txt" -execdir /bin/rm {} \;  # 是否被检测？
   ```

3. **Sed 模式绕过**
   ```bash
   # 只允许 -n 模式
   sed -n '1,5p' file  # 安全
   
   # 其他模式
   sed 's/foo/bar/' file  # 不安全（修改输出）
   sed -i 's/foo/bar/' file  # 不安全（原地修改）
   ```
