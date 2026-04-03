# codex-rs/shell-command 深度研究文档

## 1. 场景与职责

### 1.1 定位
`codex-shell-command` 是 Codex 项目中负责**命令解析与安全检查**的核心基础库。它位于 Codex 工具链的最前端，承担着将用户输入的 shell 命令转换为结构化数据、并判断命令安全性的关键职责。

### 1.2 核心职责

| 职责领域 | 说明 |
|---------|------|
| **命令解析** | 将 shell 命令字符串解析为结构化的 `ParsedCommand`，支持 Read/ListFiles/Search/Unknown 四种类型 |
| **安全判定** | 提供 `is_known_safe_command()` 和 `command_might_be_dangerous()` 两个核心安全函数 |
| **跨平台支持** | 支持 Unix (bash/zsh) 和 Windows (PowerShell/CMD) 双平台 |
| **Shell 检测** | 识别不同类型的 shell（bash/zsh/pwsh/powershell/cmd） |

### 1.3 使用场景

1. **执行前安全检查**：在 Codex 执行任何 shell 命令前，调用安全函数判断是否需要用户确认
2. **命令摘要生成**：为 TUI 展示生成人类可读的命令摘要（如 "Read README.md"、"Search for 'TODO' in src"）
3. **策略决策支持**：为 `exec_policy` 模块提供命令结构化数据，用于规则匹配

---

## 2. 功能点目的

### 2.1 命令解析功能 (`parse_command`)

**目的**：将复杂的 shell 命令转换为标准化的结构化表示，便于后续处理和展示。

**支持的命令类型**：

| 类型 | 示例 | 说明 |
|-----|------|------|
| `Read` | `cat file.txt`, `head -n 50 file.txt` | 文件读取操作 |
| `ListFiles` | `ls`, `rg --files`, `find . -name '*.rs'` | 文件列表操作 |
| `Search` | `grep -R TODO src`, `rg pattern` | 文本搜索操作 |
| `Unknown` | `npm run build`, `python script.py` | 无法识别的命令 |

**特殊处理逻辑**：
- 支持 `bash -lc "..."` 和 `zsh -lc "..."` 形式的嵌套 shell 脚本解析
- 使用 tree-sitter-bash 进行 AST 级别的脚本解析
- 管道命令处理：识别并剥离 "small formatting commands"（如 `head`, `tail`, `awk`, `wc`）
- `cd` 命令追踪：在命令序列中跟踪目录变化，计算相对路径

### 2.2 安全判定功能

#### 2.2.1 安全命令判定 (`is_known_safe_command`)

**目的**：识别那些**已知只读**的命令，允许自动执行无需用户确认。

**安全命令白名单**（Unix）：
- 基础工具：`cat`, `ls`, `echo`, `pwd`, `head`, `tail`, `grep`, `wc`, `tr`, `cut`, `sort`, `uniq`
- 搜索工具：`rg`（带安全检查）, `ag`, `ack`, `pt`
- Git 操作：`git status`, `git log`, `git diff`, `git show`, `git branch`（只读模式）
- 文件列表：`eza`, `exa`, `tree`, `du`, `fd`, `find`（无危险选项时）
- 其他：`base64`（无输出选项时）, `sed -n <range>p`

**Windows 安全命令**：
- 仅允许 PowerShell 的特定只读 cmdlet
- 使用 PowerShell AST 解析器进行深度分析

#### 2.2.2 危险命令检测 (`command_might_be_dangerous`)

**目的**：识别可能导致数据丢失或系统损害的命令，强制要求用户确认。

**检测的危险模式**：

| 平台 | 危险模式 | 示例 |
|-----|---------|------|
| Unix | 强制删除 | `rm -rf /`, `rm -f file` |
| Windows | PowerShell 删除 | `Remove-Item -Force`, `rm -Force` |
| Windows | CMD 强制删除 | `del /f file`, `erase /f file` |
| Windows | 递归目录删除 | `rd /s /q dir`, `rmdir /s /q dir` |
| Windows | URL 启动 | `Start-Process https://...`, `explorer https://...` |
| Windows | 浏览器启动 | `chrome.exe https://...`, `mshta https://...` |

### 2.3 PowerShell 特殊处理

**目的**：Windows 平台使用 PowerShell 作为主要的 shell 环境，需要特殊的安全处理。

**实现方式**：
1. **AST 解析**：使用内嵌的 PowerShell 脚本 (`powershell_parser.ps1`) 调用 PowerShell 的 AST 解析器
2. **命令序列提取**：将 PowerShell 管道命令分解为独立的命令向量
3. **安全检查**：对每个命令进行白名单校验

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 ParsedCommand（定义于 codex-protocol）

```rust
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ParsedCommand {
    Read {
        cmd: String,        // 原始命令字符串
        name: String,       // 文件名（短格式）
        path: PathBuf,      // 文件路径
    },
    ListFiles {
        cmd: String,
        path: Option<String>,
    },
    Search {
        cmd: String,
        query: Option<String>,
        path: Option<String>,
    },
    Unknown {
        cmd: String,
    },
}
```

#### 3.1.2 ShellType（内部枚举）

```rust
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub(crate) enum ShellType {
    Zsh,
    Bash,
    PowerShell,
    Sh,
    Cmd,
}
```

### 3.2 关键流程

#### 3.2.1 命令解析流程

```
parse_command(command: &[String])
├── extract_bash_command() / extract_powershell_command()
│   └── 检测是否为 shell 包装命令
├── parse_shell_lc_commands() [如果是 bash/zsh -lc]
│   ├── try_parse_shell() [tree-sitter-bash 解析]
│   ├── try_parse_word_only_commands_sequence()
│   ├── drop_small_formatting_commands()
│   └── 为每个命令生成 ParsedCommand
├── parse_command_impl() [非 shell 包装命令]
│   ├── normalize_tokens() [处理 yes/no 前缀、bash -c]
│   ├── split_on_connectors() [按 &&/||/|/; 分割]
│   ├── 对每个命令段：
│   │   ├── cd 命令追踪当前目录
│   │   └── summarize_main_tokens() [生成 ParsedCommand]
│   └── simplify_once() [简化命令序列]
└── 去重并返回 ParsedCommand 列表
```

#### 3.2.2 安全判定流程

```
is_known_safe_command(command)
├── 将 zsh 映射为 bash（统一处理）
├── is_safe_command_windows() [Windows 平台]
│   └── try_parse_powershell_command_sequence()
│       └── parse_with_powershell_ast() [调用 PowerShell AST 解析]
└── is_safe_to_call_with_exec() [Unix/通用]
    ├── 基础命令白名单检查
    ├── 特定命令参数检查（base64, find, rg, git, sed）
    └── parse_shell_lc_plain_commands() [bash -lc 脚本检查]

command_might_be_dangerous(command)
├── is_dangerous_command_windows() [Windows]
│   ├── is_dangerous_powershell() [PowerShell 危险命令]
│   ├── is_dangerous_cmd() [CMD 危险命令]
│   └── is_direct_gui_launch() [直接 GUI 启动]
└── is_dangerous_to_call_with_exec() [Unix]
    ├── rm -f/-rf 检测
    └── sudo 递归检查
```

### 3.3 关键技术细节

#### 3.3.1 tree-sitter-bash 解析

**文件**：`src/bash.rs`

用于解析 `bash -lc "..."` 形式的脚本，提取其中的纯单词命令序列。

**允许的语法元素**：
- 命令连接符：`&&`, `||`, `;`, `|`
- 字符串：双引号、单引号
- 数字、单词、拼接（concatenation）

**拒绝的语法元素**：
- 括号、子 shell
- 重定向（`>`, `<`, `>>`）
- 命令替换（`$(...)`, `` `...` ``）
- 变量扩展（`$VAR`, `${VAR}`）
- 变量赋值前缀

#### 3.3.2 PowerShell AST 解析

**文件**：`src/command_safety/powershell_parser.ps1`

这是一个内嵌的 PowerShell 脚本，用于调用 PowerShell 的 `System.Management.Automation.Language.Parser` 进行 AST 解析。

**解析流程**：
1. 从环境变量 `CODEX_POWERSHELL_PAYLOAD` 读取 Base64 编码的脚本
2. 使用 PowerShell 的 Parser 解析为 AST
3. 遍历 AST，提取每个 Pipeline 的命令元素
4. 返回 JSON 格式的命令序列

**支持的 AST 节点**：
- `StringConstantExpressionAst`：字符串常量
- `ExpandableStringExpressionAst`：可扩展字符串（无嵌套表达式时）
- `ConstantExpressionAst`：常量表达式
- `CommandParameterAst`：命令参数

**拒绝的构造**：
- 重定向（Redirections）
- 调用操作符（InvocationOperator，如 `&`）
- 子表达式（Sub-expression，`$(...)`）
- 数组展开（`@(...)`）

#### 3.3.3 小格式化命令过滤

**文件**：`src/parse_command.rs` - `is_small_formatting_command()`

在管道命令中，某些命令仅用于格式化输出而不改变数据本质，这些命令会被过滤掉以突出主要命令。

**格式化命令列表**：
- `wc`, `tr`, `cut`, `sort`, `uniq`, `tee`, `column`
- `head`（无文件参数时）
- `tail`（无文件参数时）
- `sed`（非 `-n <range>p` 形式时）
- `awk`（无数据文件时）
- `xargs`（非变异命令时）

### 3.4 平台特定实现

#### 3.4.1 Windows 实现

**文件**：
- `src/command_safety/windows_dangerous_commands.rs`
- `src/command_safety/windows_safe_commands.rs`
- `src/powershell.rs`

**特点**：
- PowerShell 是 Windows 平台唯一被支持的安全 shell
- 使用 PowerShell 的 AST 解析器进行深度分析
- 对 CMD 命令进行严格限制
- 检测 URL 启动和强制删除操作

#### 3.4.2 Unix 实现

**文件**：
- `src/bash.rs`
- `src/command_safety/is_safe_command.rs`
- `src/command_safety/is_dangerous_command.rs`

**特点**：
- 使用 tree-sitter-bash 进行脚本解析
- 支持 bash/zsh/sh
- 详细的命令白名单机制

---

## 4. 关键代码路径与文件引用

### 4.1 模块结构

```
codex-rs/shell-command/
├── src/
│   ├── lib.rs                           # 模块入口，导出公共 API
│   ├── parse_command.rs                 # 命令解析主逻辑 (~2500 行)
│   ├── bash.rs                          # Bash 脚本解析（tree-sitter）
│   ├── powershell.rs                    # PowerShell 命令提取与处理
│   ├── shell_detect.rs                  # Shell 类型检测
│   └── command_safety/
│       ├── mod.rs                       # 安全模块入口
│       ├── is_safe_command.rs           # 安全命令判定 (~600 行)
│       ├── is_dangerous_command.rs      # 危险命令检测 (~160 行)
│       ├── windows_safe_commands.rs     # Windows 安全命令 (~620 行)
│       ├── windows_dangerous_commands.rs # Windows 危险命令 (~750 行)
│       └── powershell_parser.ps1        # PowerShell AST 解析脚本
├── Cargo.toml                           # 依赖配置
└── BUILD.bazel                          # Bazel 构建配置
```

### 4.2 公共 API

**文件**：`src/lib.rs`

```rust
pub mod bash;
pub mod command_safety;
pub mod parse_command;
pub mod powershell;

pub use command_safety::is_dangerous_command;
pub use command_safety::is_safe_command;
```

### 4.3 核心函数签名

```rust
// parse_command.rs
pub fn parse_command(command: &[String]) -> Vec<ParsedCommand>;
pub fn shlex_join(tokens: &[String]) -> String;
pub fn extract_shell_command(command: &[String]) -> Option<(&str, &str)>;

// bash.rs
pub fn try_parse_shell(shell_lc_arg: &str) -> Option<Tree>;
pub fn try_parse_word_only_commands_sequence(tree: &Tree, src: &str) -> Option<Vec<Vec<String>>>;
pub fn extract_bash_command(command: &[String]) -> Option<(&str, &str)>;

// powershell.rs
pub fn extract_powershell_command(command: &[String]) -> Option<(&str, &str)>;
pub fn prefix_powershell_script_with_utf8(command: &[String]) -> Vec<String>;

// command_safety/is_safe_command.rs
pub fn is_known_safe_command(command: &[String]) -> bool;

// command_safety/is_dangerous_command.rs
pub fn command_might_be_dangerous(command: &[String]) -> bool;
```

---

## 5. 依赖与外部交互

### 5.1 依赖 crate

| crate | 用途 |
|-------|------|
| `codex-protocol` | `ParsedCommand` 类型定义 |
| `codex-utils-absolute-path` | 绝对路径处理 |
| `tree-sitter` + `tree-sitter-bash` | Bash 脚本 AST 解析 |
| `shlex` | Shell 风格的字符串分割与连接 |
| `regex` | 正则表达式（URL 检测等） |
| `once_cell` | 静态初始化 |
| `serde` + `serde_json` | 序列化 |
| `base64` | PowerShell 脚本编码 |
| `url` | URL 解析 |
| `which` | 可执行文件查找 |

### 5.2 调用方 crate

| crate | 使用方式 |
|-------|---------|
| `codex-core` | `exec_policy.rs` 安全判定，`unified_exec.rs` 命令展示 |
| `codex-mcp-server` | 测试套件中的命令解析验证 |
| `codex-app-server` | `shlex_join` 用于命令字符串化 |
| `codex-tui` | 命令摘要展示 |

### 5.3 与 codex-protocol 的关系

`ParsedCommand` 类型定义在 `codex-protocol` crate 中，这是为了让其他 crate（如 `codex-app-server-protocol`）也能使用该类型而无需依赖 `codex-shell-command`。

**类型定义位置**：`codex-rs/protocol/src/parse_command.rs`

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 解析器限制

| 风险 | 说明 |
|-----|------|
| **Bash 解析不完整** | tree-sitter-bash 只解析 "word-only" 命令，复杂脚本会被拒绝 |
| **PowerShell 依赖运行时** | Windows 安全判定需要调用 PowerShell 进程，有性能开销 |
| **命令注入绕过** | 通过环境变量、别名等方式可能绕过安全检查 |

#### 6.1.2 安全边界

| 边界 | 说明 |
|-----|------|
| **白名单机制** | 只有明确列出的命令才被认为是安全的，新工具默认不安全 |
| **参数检查有限** | 某些命令只检查特定危险参数，可能遗漏其他危险用法 |
| **Git 配置绕过** | `-c core.pager=...` 等全局配置可执行任意命令，已被禁止 |

### 6.2 边界情况

1. **复杂管道命令**：`bash -lc "cmd1 | cmd2 | cmd3"` 中只有主要命令会被识别
2. **Here-document**：支持解析 `python3 <<'PY'...` 形式的单命令
3. **Windows 路径**：支持 `C:\\path\\to\\file` 格式的路径解析
4. **Unicode/UTF-8**：PowerShell 输出强制使用 UTF-8 编码

### 6.3 改进建议

#### 6.3.1 短期改进

1. **扩展命令白名单**
   - 添加更多常用的只读开发工具（如 `jq`, `yq`, `fd` 的更多用法）
   - 支持容器工具（`docker ps`, `kubectl get` 等只读命令）

2. **优化 PowerShell 性能**
   - 缓存 PowerShell 可执行文件路径查找结果
   - 考虑使用 PowerShell 的 .NET API 直接调用而非启动新进程

3. **改进错误信息**
   - 当命令被拒绝时，提供更具体的原因说明
   - 建议安全的替代命令

#### 6.3.2 中长期改进

1. **更智能的脚本分析**
   - 考虑使用更完整的 shell 解析器（如 shellcheck 的解析库）
   - 支持更多的 shell 方言（fish, nushell 等）

2. **机器学习辅助**
   - 基于历史数据训练命令安全性的预测模型
   - 识别常见开发工作流中的安全模式

3. **策略即代码**
   - 允许用户通过配置文件扩展安全命令白名单
   - 支持项目级别的 `.codex-safety` 配置文件

4. **审计与可观测性**
   - 记录所有安全判定的决策过程
   - 提供安全判定报告，帮助用户理解为什么某些命令需要确认

### 6.4 测试覆盖

当前测试覆盖情况良好，主要包括：

- **单元测试**：每个主要函数都有对应的测试用例
- **边界测试**：各种特殊参数组合、引号处理、管道命令
- **平台测试**：Windows 和 Unix 的特定测试（使用 `cfg!(windows)` 等条件编译）

**测试文件位置**：
- `src/parse_command.rs`：内联测试（~1200 行测试代码）
- `src/bash.rs`：内联测试（~300 行测试代码）
- `src/powershell.rs`：内联测试
- `src/command_safety/is_safe_command.rs`：内联测试
- `src/command_safety/windows_dangerous_commands.rs`：内联测试
- `src/command_safety/windows_safe_commands.rs`：Windows 特定测试

---

## 7. 总结

`codex-shell-command` 是 Codex 项目的安全守门员，通过精细的命令解析和严格的安全检查，在用户体验和系统安全之间取得平衡。其核心设计原则：

1. **默认拒绝**：未知命令默认不安全
2. **白名单机制**：只有明确验证的只读命令才自动通过
3. **深度解析**：使用 AST 级别的解析而非简单的字符串匹配
4. **跨平台**：针对 Unix 和 Windows 的不同 shell 环境提供专门支持

该模块的可靠性直接影响 Codex 的整体安全性，任何修改都需要经过严格的测试验证。
