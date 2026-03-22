# codex-rs/shell-command/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-shell-command` crate 是 Codex 项目的**命令解析与安全检测基础设施层**，位于 `codex-rs/shell-command/` 目录。该 crate 被多个上层组件依赖：

- **codex-core**: 执行策略判断、Shell 工具处理
- **codex-protocol**: 协议层命令解析数据类型定义
- **codex-mcp-server**: MCP 服务器执行审批
- **codex-tui/tui_app_server**: 终端 UI 的命令展示与审批

### 1.2 核心职责

1. **命令解析 (Command Parsing)**: 将模型生成的 shell 命令解析为结构化的 `ParsedCommand`，支持人类可读的命令摘要
2. **安全检测 (Safety Checking)**: 
   - 识别"已知安全"命令（可自动执行）
   - 识别"危险命令"（需要用户审批）
3. **跨平台支持**: 
   - Unix/Linux/macOS: Bash/Zsh/Sh
   - Windows: PowerShell (pwsh/powershell.exe)、CMD

### 1.3 使用场景

| 场景 | 说明 |
|------|------|
| 自动审批 | `ls`、`git status`、`rg --files` 等只读命令可自动通过 |
| 人工审批 | `rm -rf`、`powershell -Command "Remove-Item"` 等危险命令需用户确认 |
| 命令摘要 | 将复杂命令（如 `bash -lc "cd foo && cat bar.txt"`）解析为 `Read { path: "foo/bar.txt" }` |
| 沙箱策略 | 为执行策略层提供命令分类信息，辅助决策 |

---

## 2. 功能点目的

### 2.1 命令解析功能 (parse_command.rs)

**目的**: 将原始命令字符串（通常是 `Vec<String>` 格式的 argv）转换为结构化的 `ParsedCommand`，用于：
- UI 展示命令摘要
- 提取命令操作类型（读文件、搜索、列目录）
- 提取关键参数（文件路径、搜索查询）

**支持的命令类型**:

| ParsedCommand 变体 | 典型命令示例 | 用途 |
|-------------------|-------------|------|
| `Read` | `cat file.txt`, `head -n 50 file`, `sed -n '1,10p' file` | 文件读取操作 |
| `ListFiles` | `ls`, `rg --files`, `find . -type f`, `tree` | 文件列表操作 |
| `Search` | `rg pattern src`, `grep -R TODO .`, `fd main src` | 文本/文件搜索 |
| `Unknown` | `npm run build`, `python script.py` | 无法识别的命令 |

### 2.2 安全命令检测 (command_safety/is_safe_command.rs)

**目的**: 识别不需要用户审批的"只读"命令。

**判定维度**:
- 命令白名单：`cat`, `ls`, `grep`, `rg`, `git status`, `head`, `tail` 等
- 参数检查：排除危险参数（如 `find -exec`, `rg --pre`, `git -c` 配置覆盖）
- 复合命令支持：`bash -lc "cmd1 && cmd2"` 中所有子命令都安全才通过

### 2.3 危险命令检测 (command_safety/is_dangerous_command.rs)

**目的**: 主动识别高风险操作，强制人工审批。

**检测范围**:
- Unix: `rm -rf`, `rm -f`
- Windows PowerShell: `Remove-Item -Force`, `Start-Process https://...`, ShellExecute
- Windows CMD: `del /f`, `rmdir /s /q`, `start https://...`

### 2.4 Windows 专用安全模块

**windows_safe_commands.rs**: PowerShell 安全命令解析
- 使用内嵌的 PowerShell 脚本 (`powershell_parser.ps1`) 进行 AST 解析
- 支持管道链、命令序列的递归解析
- 严格限制：禁止重定向、变量扩展、子表达式

**windows_dangerous_commands.rs**: Windows 危险命令检测
- URL 检测：防止通过浏览器或 ShellExecute 打开恶意链接
- 强制删除检测：`Remove-Item -Force`, `del /f`, `rmdir /s /q`
- 正则表达式 + URL 解析双重验证

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 ParsedCommand (protocol/src/parse_command.rs)

```rust
#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ParsedCommand {
    Read {
        cmd: String,
        name: String,
        path: PathBuf,
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

#### 3.1.2 ShellType (shell_detect.rs)

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

### 3.2 核心算法流程

#### 3.2.1 命令解析主流程 (parse_command.rs)

```
parse_command(command: &[String]) -> Vec<ParsedCommand>
  ├── parse_shell_lc_commands()          // 尝试解析 bash/zsh -lc 脚本
  │     ├── extract_bash_command()       // 提取 shell 和 script
  │     ├── try_parse_shell()            // tree-sitter 解析
  │     ├── try_parse_word_only_commands_sequence()  // AST 遍历
  │     └── summarize_main_tokens()      // 转换为 ParsedCommand
  ├── extract_powershell_command()       // PowerShell 提取
  └── parse_command_impl()               // 普通命令解析
        ├── normalize_tokens()           // 标准化（去除 yes/no 前缀等）
        ├── split_on_connectors()        // 按 &&/||/|/; 分割
        └── summarize_main_tokens()      // 逐个解析
```

#### 3.2.2 Bash 脚本解析 (bash.rs)

使用 **tree-sitter-bash** 进行语法解析：

```rust
pub fn try_parse_shell(shell_lc_arg: &str) -> Option<Tree> {
    let lang = BASH.into();
    let mut parser = Parser::new();
    parser.set_language(&lang).expect("load bash grammar");
    parser.parse(shell_lc_arg, None)
}
```

AST 节点类型白名单 (`ALLOWED_KINDS`):
- 容器: `program`, `list`, `pipeline`
- 命令: `command`, `command_name`, `word`, `string`, `raw_string`, `number`
- 连接: `concatenation`

允许的标点符号: `&&`, `||`, `;`, `|`, `"`, `"`

**拒绝的构造**:
- 括号/子 shell: `(ls)`
- 重定向: `ls > out.txt`
- 变量替换: `$HOME`, `"${USER}"`
- 命令替换: `$(pwd)`, `` `pwd` ``
- 后台执行: `echo hi &`

#### 3.2.3 PowerShell 安全解析 (windows_safe_commands.rs)

**解析流程**:

```
is_safe_command_windows(command)
  ├── try_parse_powershell_command_sequence()  // 识别 PowerShell 可执行文件
  ├── parse_powershell_invocation()            // 解析参数，提取 -Command 脚本
  ├── parse_with_powershell_ast()              // 调用 PowerShell 进程解析 AST
  │     └── 执行 powershell_parser.ps1         // 内嵌 PowerShell 脚本
  └── is_safe_powershell_command()             // 白名单验证
```

**powershell_parser.ps1 逻辑**:
1. 从环境变量 `CODEX_POWERSHELL_PAYLOAD` 读取 Base64 编码的脚本
2. 使用 `[System.Management.Automation.Language.Parser]::ParseInput()` 解析 AST
3. 遍历 `EndBlock.Statements`，提取每个 Pipeline 元素
4. 转换命令元素为字符串数组，返回 JSON 格式：`{ status: "ok", commands: [...] }`

**安全命令白名单** (PowerShell):
- 输出: `echo`, `Write-Output`, `Write-Host`
- 文件列表: `dir`, `ls`, `Get-ChildItem`, `gci`
- 文件读取: `cat`, `type`, `gc`, `Get-Content`
- 搜索: `Select-String`, `sls`, `findstr`
- 测量: `Measure-Object`, `measure`
- 路径: `Get-Location`, `gl`, `pwd`, `Test-Path`, `Resolve-Path`
- 选择: `Select-Object`, `select`
- Git: `git status`, `git log`, `git diff`, `git show`, `git cat-file`
- Ripgrep: `rg` (排除 `--pre`, `--hostname-bin`, `--search-zip`)

**拒绝的构造**:
- 重定向: `>`, `2>`, `| Out-File`
- 变量扩展: `$foo`, `"foo $bar"`
- 子表达式: `$(...)`, `@(...)`
- 调用操作符: `&`
- 危险 cmdlet: `Set-Content`, `Remove-Item`, `Start-Process`, `New-Item`

### 3.3 安全检测算法

#### 3.3.1 已知安全命令检测 (is_safe_command.rs)

```rust
pub fn is_known_safe_command(command: &[String]) -> bool {
    // 1. 尝试解析 bash -lc 脚本中的多个命令
    if let Some(all_commands) = parse_shell_lc_plain_commands(&command)
        && all_commands.iter().all(|cmd| is_safe_to_call_with_exec(cmd)) {
        return true;
    }
    // 2. 单命令检测
    is_safe_to_call_with_exec(&command)
}
```

**命令特定检测逻辑**:

| 命令 | 安全条件 |
|------|---------|
| `base64` | 不包含 `-o`, `--output` |
| `find` | 不包含 `-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`, `-fls`, `-fprint`, `-fprint0`, `-fprintf` |
| `rg` | 不包含 `--pre`, `--hostname-bin`, `--search-zip`, `-z` |
| `git` | 子命令为 `status`/`log`/`diff`/`show`/`branch`，且无 `--output`, `--ext-diff`, `--config-env` |
| `sed` | 格式为 `sed -n <number>p` 或 `sed -n <start>,<end>p` |

#### 3.3.2 危险命令检测 (is_dangerous_command.rs)

```rust
pub fn command_might_be_dangerous(command: &[String]) -> bool {
    // Windows 特定检测
    #[cfg(windows)] {
        if windows_dangerous_commands::is_dangerous_command_windows(command) {
            return true;
        }
    }
    // Unix 基础检测
    if is_dangerous_to_call_with_exec(command) {
        return true;
    }
    // 递归检测 bash -lc 脚本
    if let Some(all_commands) = parse_shell_lc_plain_commands(command)
        && all_commands.iter().any(|cmd| is_dangerous_to_call_with_exec(cmd)) {
        return true;
    }
    false
}
```

**Unix 危险模式**:
- `rm -f ...`, `rm -rf ...`
- `sudo <cmd>`: 递归检测 `<cmd>`

**Windows 危险模式** (windows_dangerous_commands.rs):

```rust
// URL 启动检测
has_url && (
    tokens.contains("start-process") ||
    tokens.contains("invoke-item") ||
    tokens.contains("shellexecute") ||
    tokens.contains("shell.application") ||
    first == "rundll32" && contains("url.dll,fileprotocolhandler") ||
    first == "mshta" ||
    is_browser_executable(first)
)

// 强制删除检测
has_force_delete_cmdlet(tokens): 
    DELETE_CMDLETS.iter().any(|cmd| token == cmd) && 
    tokens.contains("-force")
```

### 3.4 关键工具函数

#### 3.4.1 命令提取

```rust
// 从 bash -lc 或 bash -c 提取脚本
pub fn extract_bash_command(command: &[String]) -> Option<(&str, &str)>

// 从 PowerShell -Command/-c 提取脚本  
pub fn extract_powershell_command(command: &[String]) -> Option<(&str, &str)>
```

#### 3.4.2 路径处理

```rust
// 缩短路径用于显示，排除 build/dist/node_modules/src
fn short_display_path(path: &str) -> String

// 处理 cd 命令，计算有效路径
fn cd_target(args: &[String]) -> Option<String>
fn join_paths(base: &str, dir: &str) -> String
```

#### 3.4.3 参数处理

```rust
// 跳过带值的标志，处理 -- 结束标志
fn skip_flag_values<'a>(args: &'a [String], flags_with_vals: &[&str]) -> Vec<&'a String>

// 提取位置参数（非标志参数）
fn positional_operands<'a>(args: &'a [String], flags_with_vals: &[&str]) -> Vec<&'a String>
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/shell-command/
├── Cargo.toml                          # 依赖声明
├── BUILD.bazel                         # Bazel 构建配置
└── src/
    ├── lib.rs                          # 模块导出
    ├── parse_command.rs                # 命令解析主逻辑 (~2000 lines)
    ├── bash.rs                         # Bash/Zsh 解析 (~590 lines)
    ├── powershell.rs                   # PowerShell 提取与查找 (~204 lines)
    ├── shell_detect.rs                 # Shell 类型检测 (~32 lines)
    └── command_safety/
        ├── mod.rs                      # 模块组织
        ├── is_safe_command.rs          # 安全命令检测 (~602 lines)
        ├── is_dangerous_command.rs     # 危险命令检测 (~161 lines)
        ├── windows_safe_commands.rs    # Windows 安全解析 (~623 lines)
        ├── windows_dangerous_commands.rs  # Windows 危险检测 (~755 lines)
        └── powershell_parser.ps1       # PowerShell AST 解析脚本 (~201 lines)
```

### 4.2 关键代码引用

#### 4.2.1 命令解析入口

**文件**: `src/parse_command.rs:30-48`

```rust
pub fn parse_command(command: &[String]) -> Vec<ParsedCommand> {
    // Parse and then collapse consecutive duplicate commands to avoid redundant summaries.
    let parsed = parse_command_impl(command);
    let mut deduped: Vec<ParsedCommand> = Vec::with_capacity(parsed.len());
    for cmd in parsed.into_iter() {
        if deduped.last().is_some_and(|prev| prev == &cmd) {
            continue;
        }
        deduped.push(cmd);
    }
    if deduped.iter().any(|cmd| matches!(cmd, ParsedCommand::Unknown { .. })) {
        vec![single_unknown_for_command(command)]
    } else {
        deduped
    }
}
```

#### 4.2.2 Bash AST 解析

**文件**: `src/bash.rs:29-95`

```rust
pub fn try_parse_word_only_commands_sequence(tree: &Tree, src: &str) -> Option<Vec<Vec<String>>> {
    if tree.root_node().has_error() {
        return None;
    }

    const ALLOWED_KINDS: &[&str] = &[
        "program", "list", "pipeline",
        "command", "command_name", "word", "string", "string_content",
        "raw_string", "number", "concatenation",
    ];
    const ALLOWED_PUNCT_TOKENS: &[&str] = &["&&", "||", ";", "|", "\"", "'"];
    
    // 遍历 AST，验证节点类型，提取命令...
}
```

#### 4.2.3 PowerShell 安全检测

**文件**: `src/command_safety/windows_safe_commands.rs:127-152`

```rust
fn parse_with_powershell_ast(executable: &str, script: &str) -> PowershellParseOutcome {
    let encoded_script = encode_powershell_base64(script);
    let encoded_parser_script = encoded_parser_script();
    match Command::new(executable)
        .args(["-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded_parser_script])
        .env("CODEX_POWERSHELL_PAYLOAD", &encoded_script)
        .output()
    {
        Ok(output) if output.status.success() => {
            // 解析 JSON 结果...
        }
        _ => PowershellParseOutcome::Failed,
    }
}
```

#### 4.2.4 危险命令检测

**文件**: `src/command_safety/is_dangerous_command.rs:130-142`

```rust
fn is_dangerous_to_call_with_exec(command: &[String]) -> bool {
    let cmd0 = command.first().map(String::as_str);
    match cmd0 {
        Some("rm") => matches!(command.get(1).map(String::as_str), Some("-f" | "-rf")),
        Some("sudo") => is_dangerous_to_call_with_exec(&command[1..]),
        _ => false,
    }
}
```

### 4.3 测试覆盖

**单元测试分布**:

| 文件 | 测试数量 | 主要测试内容 |
|------|---------|-------------|
| `parse_command.rs` | ~80+ | 各类命令解析场景 |
| `bash.rs` | ~25 | AST 解析、字符串提取、拒绝危险构造 |
| `powershell.rs` | ~4 | 命令提取、标志解析 |
| `is_safe_command.rs` | ~20 | 安全命令识别、危险参数排除 |
| `is_dangerous_command.rs` | ~2 | rm 危险模式 |
| `windows_dangerous_commands.rs` | ~35 | URL 检测、强制删除、链式命令 |
| `windows_safe_commands.rs` | ~12 | PowerShell 安全解析 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖 (Cargo.toml)

```toml
[dependencies]
base64 = { workspace = true }                    # PowerShell 脚本编码
codex-protocol = { workspace = true }            # ParsedCommand 定义
codex-utils-absolute-path = { workspace = true } # 绝对路径处理
once_cell = { workspace = true }                 # 静态正则表达式
regex = { workspace = true }                     # URL 检测
serde = { workspace = true }                     # 序列化
serde_json = { workspace = true }                # JSON 解析
shlex = { workspace = true }                     # Shell 词法分析
tree-sitter = { workspace = true }               # Bash 语法解析
tree-sitter-bash = { workspace = true }          # Bash 语法定义
url = { workspace = true }                       # URL 验证
which = { workspace = true }                     # 可执行文件查找
```

### 5.2 调用方依赖

#### 5.2.1 codex-core

**文件**: `codex-rs/core/src/tools/handlers/shell.rs:13,167-176`

```rust
use crate::is_safe_command::is_known_safe_command;

async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
    match &invocation.payload {
        ToolPayload::Function { arguments } => {
            serde_json::from_str::<ShellToolCallParams>(arguments)
                .map(|params| !is_known_safe_command(&params.command))
                .unwrap_or(true)
        }
        ToolPayload::LocalShell { params } => !is_known_safe_command(&params.command),
        _ => true,
    }
}
```

**文件**: `codex-rs/core/src/exec_policy.rs:10-11`

```rust
use crate::is_dangerous_command::command_might_be_dangerous;
use crate::is_safe_command::is_known_safe_command;
```

#### 5.2.2 codex-protocol

**文件**: `codex-rs/protocol/src/protocol.rs:44`

```rust
use crate::parse_command::ParsedCommand;
```

**文件**: `codex-rs/protocol/src/approvals.rs:7,195`

```rust
use crate::parse_command::ParsedCommand;
pub struct ExecApprovalRequestEvent {
    pub parsed_cmd: Vec<ParsedCommand>,
}
```

#### 5.2.3 codex-mcp-server

**文件**: `codex-rs/mcp-server/src/exec_approval.rs:6,38`

```rust
use codex_protocol::parse_command::ParsedCommand;
pub struct ExecApprovalElicitRequestParams {
    pub codex_parsed_cmd: Vec<ParsedCommand>,
}
```

### 5.3 数据流

```
模型生成命令
    │
    ▼
┌─────────────────┐
│  parse_command  │ ──► ParsedCommand[] (用于 UI 展示)
│  (shell-command)│
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ is_safe_command │ ──► bool (是否自动审批)
│  (shell-command)│
└─────────────────┘
    │
    ▼
┌─────────────────┐
│is_dangerous_cmd │ ──► bool (是否强制审批)
│  (shell-command)│
└─────────────────┘
    │
    ▼
执行策略层 (exec_policy.rs)
    │
    ▼
用户审批 / 自动执行
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 解析器绕过风险

**风险**: Bash 解析器使用白名单机制，攻击者可能通过未覆盖的语法构造绕过安全检测。

**示例**:
```bash
# 当前会被拒绝（变量替换）
bash -lc 'echo $HOME'

# 但以下可能绕过（如果扩展名检查不严格）
bash -lc 'eval "echo \$HOME"'
```

**缓解**: 保守策略——任何无法解析的构造都视为 `Unknown`，最终落入人工审批流程。

#### 6.1.2 PowerShell 解析依赖外部进程

**风险**: `parse_with_powershell_ast()` 需要启动 PowerShell 进程，可能：
- 性能开销（每次解析都启动新进程）
- 依赖 PowerShell 可用性
- 环境变量注入风险（`CODEX_POWERSHELL_PAYLOAD`）

**缓解**: 仅在 Windows 平台启用，且解析失败时保守地返回 `Failed`。

#### 6.1.3 URL 检测的误报/漏报

**风险**: `looks_like_url()` 使用正则表达式 + URL 解析，可能：
- 漏报：非标准 URL 格式（如 `hxxp://evil.com`）
- 误报：路径中包含 `http://` 的合法文件路径

**代码位置**: `src/command_safety/windows_dangerous_commands.rs:312-335`

### 6.2 边界限制

#### 6.2.1 命令解析边界

| 限制 | 说明 |
|------|------|
| 仅支持词法分析 | 不执行命令，无法解析变量值 |
| 无别名展开 | `alias ll='ls -la'` 无法识别 |
| 无路径解析 | `cat $(find . -name file)` 无法追踪 |
| 仅支持特定 shell | Bash/Zsh/PowerShell，不支持 Fish、Nu 等 |

#### 6.2.2 安全检测边界

- **时间侧信道**: 不检测命令执行时间（如 `sleep 10000`）
- **资源消耗**: 不检测 CPU/内存密集型命令（如 `fork bomb`）
- **网络操作**: 不检测纯网络命令（如 `curl https://...` 在 Unix 上）

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强 Git 安全检测**
   - 当前仅支持 `status`, `log`, `diff`, `show`, `branch`
   - 建议增加 `stash list`, `remote -v`, `config --list` 等只读命令

2. **优化 PowerShell 解析性能**
   - 考虑使用 PowerShell 的 COM 接口或 .NET 托管 API，避免进程启动开销
   - 或者缓存 PowerShell 进程（类似 REPL 模式）

3. **改进错误信息**
   - 当前解析失败时仅返回 `Unknown`，建议增加失败原因分类
   - 帮助用户理解为何命令需要审批

#### 6.3.2 中期改进

1. **引入命令指纹机制**
   - 对常见安全命令模式预计算哈希，加速匹配
   - 建立命令行为数据库，支持更精细的分类

2. **增强复合命令分析**
   - 当前 `bash -lc "cmd1 && cmd2"` 要求所有子命令安全
   - 可改进为识别"安全前缀"，如 `cd foo && rm -rf bar` 中 `cd foo` 是安全的

3. **支持更多 Shell**
   - Fish、Nushell、Elvish 等现代 shell 的解析支持

#### 6.3.3 长期改进

1. **基于 ML 的命令分类**
   - 使用历史审批数据训练分类器
   - 结合命令语义和上下文进行风险评估

2. **动态沙箱建议**
   - 根据命令特征自动推荐沙箱策略
   - 如检测到文件写入时建议启用写保护沙箱

3. **跨平台统一抽象**
   - 当前 Unix/Windows 实现分离，可抽象统一的"命令执行意图"层
   - 将平台特定逻辑下沉到适配器层

### 6.4 测试建议

1. **模糊测试**: 对 `parse_command` 和 AST 解析器进行 fuzzing
2. **对抗测试**: 专门测试绕过安全检测的攻击模式
3. **性能基准**: 建立 PowerShell 解析的性能基准，防止回归

---

## 7. 总结

`codex-shell-command` crate 是 Codex 项目安全执行体系的核心组件，通过**命令解析**和**安全检测**两大能力，实现了：

1. **用户体验优化**: 自动审批常见只读命令，减少用户干扰
2. **安全防护**: 识别危险操作，强制人工确认
3. **跨平台支持**: Unix 和 Windows 平台的差异化安全策略

其技术实现结合了**静态分析**（tree-sitter AST 解析）、**模式匹配**（正则 + 白名单）和**外部工具**（PowerShell AST），在保证安全性的同时兼顾了实用性。

未来的改进方向应聚焦于**性能优化**、**覆盖扩展**和**智能化分类**，以应对日益复杂的命令执行场景。
