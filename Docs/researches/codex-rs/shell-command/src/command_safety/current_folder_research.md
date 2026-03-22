# codex-rs/shell-command/src/command_safety 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 模块定位

`command_safety` 模块是 Codex CLI 的**命令安全评估核心**，位于 `codex-shell-command` crate 中。它负责在命令执行前进行静态分析，判断命令是否：

1. **已知安全** (`is_known_safe_command`)：可自动批准执行，无需用户确认
2. **可能危险** (`command_might_be_dangerous`)：需要用户显式批准或拒绝

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **自动批准安全命令** | `ls`, `cat`, `git status` 等只读命令可自动执行 |
| **拦截危险命令** | `rm -rf`, `powershell Remove-Item -Force` 等需用户确认 |
| **沙箱策略配合** | 与 `SandboxPolicy` 协同，决定是否需要额外审批 |
| **跨平台支持** | Unix (bash/zsh) 和 Windows (PowerShell/CMD) 双平台 |

### 1.3 调用方上下文

```
┌─────────────────────────────────────────────────────────────┐
│                    调用方 (Callers)                          │
├─────────────────────────────────────────────────────────────┤
│ 1. core/src/exec_policy.rs                                  │
│    - render_decision_for_unmatched_command()                │
│    - 决策流程：Safe → Allow, Dangerous → Prompt/Forbidden   │
├─────────────────────────────────────────────────────────────┤
│ 2. core/src/tools/handlers/shell.rs                         │
│    - ShellHandler::is_mutating()                            │
│    - 判断命令是否为"mutating"（变异操作）                    │
├─────────────────────────────────────────────────────────────┤
│ 3. core/src/tools/handlers/unified_exec.rs                  │
│    - UnifiedExecHandler::is_mutating()                      │
│    - 统一执行框架的安全判断                                  │
├─────────────────────────────────────────────────────────────┤
│ 4. core/src/memories/usage.rs                               │
│    - emit_metric_for_tool_read()                            │
│    - 仅对安全命令收集内存使用指标                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 核心功能

#### 2.1.1 危险命令检测 (`is_dangerous_command`)

**目的**：识别可能导致数据丢失或系统破坏的命令

**检测范围**：
- **Unix**: `rm -f`, `rm -rf`, `sudo <dangerous>`
- **Windows PowerShell**: 
  - URL + ShellExecute 组合（`Start-Process https://...`）
  - 强制删除（`Remove-Item -Force`, `rm -Force`）
  - 浏览器/Explorer 启动 URL（`mshta`, `rundll32 url.dll`）
- **Windows CMD**: 
  - `del /f`, `erase /f`
  - `rd /s /q`, `rmdir /s /q`
  - `start https://...`

#### 2.1.2 安全命令白名单 (`is_safe_command`)

**目的**：识别只读、无副作用的标准工具命令

**白名单分类**：

| 类别 | 命令示例 |
|------|----------|
| 文件查看 | `cat`, `head`, `tail`, `less`, `more`, `bat` |
| 目录列表 | `ls`, `eza`, `exa`, `tree`, `du` |
| 文本处理 | `grep`, `rg`, `sed`（仅 `-n` 模式）, `awk`, `cut` |
| Git 只读 | `git status`, `git log`, `git diff`, `git show`, `git branch`（只读模式） |
| 系统信息 | `uname`, `whoami`, `pwd`, `id`, `which` |
| PowerShell | `Get-ChildItem`, `Get-Content`, `Select-String`, `Measure-Object` |

#### 2.1.3 Bash/Zsh 脚本解析支持

**目的**：处理 `bash -lc "..."` 和 `zsh -lc "..."` 形式的命令

**支持的操作符**：`&&`, `||`, `;`, `|`
**拒绝的构造**：重定向 (`>`, `<`), 子shell (`()`), 变量扩展 (`$VAR`), 命令替换 (`$(cmd)`)

### 2.2 安全哲学

```
保守原则 (Conservative Approach)
├── 默认拒绝：不确定的命令视为不安全
├── 白名单机制：只有明确识别的命令才自动批准
├── 平台特化：Windows 和 Unix 有独立的安全规则
└── 解析失败即拒绝：无法解析的脚本视为不安全
```

---

## 具体技术实现

### 3.1 模块结构

```
codex-rs/shell-command/src/command_safety/
├── mod.rs                          # 模块导出
├── is_dangerous_command.rs         # 危险命令检测 (161 lines)
├── is_safe_command.rs              # 安全命令白名单 (602 lines)
├── windows_dangerous_commands.rs   # Windows 危险命令 (755 lines)
├── windows_safe_commands.rs        # Windows 安全命令 (623 lines)
└── powershell_parser.ps1           # PowerShell AST 解析脚本 (201 lines)
```

### 3.2 关键数据结构

#### 3.2.1 命令表示

```rust
// 命令以 Vec<String> 形式表示，即 argv 格式
// 例如: ["git", "status", "--short"]

pub fn command_might_be_dangerous(command: &[String]) -> bool;
pub fn is_known_safe_command(command: &[String]) -> bool;
```

#### 3.2.2 PowerShell 解析结果 (Windows)

```rust
// windows_safe_commands.rs
struct ParsedPowershell {
    tokens: Vec<String>,
}

enum PowershellParseOutcome {
    Commands(Vec<Vec<String>>),  // 解析成功，返回命令序列
    Unsupported,                  // 包含不支持的构造
    Failed,                       // 解析失败
}

// 解析输出 JSON 结构
#[derive(Deserialize)]
struct PowershellParserOutput {
    status: String,              // "ok" | "unsupported" | "parse_failed" | "parse_errors"
    commands: Option<Vec<Vec<String>>>,
}
```

### 3.3 关键流程

#### 3.3.1 危险命令检测流程

```
command_might_be_dangerous(command)
│
├─→ Windows 平台检查 (windows_dangerous_commands.rs)
│   ├─→ is_dangerous_powershell()
│   │   ├─→ 解析 PowerShell 调用参数
│   │   ├─→ 检测 URL + ShellExecute 组合
│   │   ├─→ 检测强制删除 cmdlet
│   │   └─→ 检测浏览器/Explorer 启动
│   ├─→ is_dangerous_cmd()
│   │   ├─→ 解析 CMD 命令分隔符 (&, &&, |, ||)
│   │   ├─→ 检测 start + URL
│   │   ├─→ 检测 del/erase /f
│   │   └─→ 检测 rd/rmdir /s /q
│   └─→ is_direct_gui_launch()
│       └─→ 直接 GUI 程序 + URL
│
├─→ Unix 通用检查 (is_dangerous_command.rs)
│   ├─→ rm -f / rm -rf
│   ├─→ sudo <递归检查>
│   └─→ bash -lc 脚本递归解析
│
└─→ 返回: true (危险) / false (不确定)
```

#### 3.3.2 安全命令检测流程

```
is_known_safe_command(command)
│
├─→ zsh → bash 别名转换
│
├─→ Windows 安全命令检查
│   └─→ is_safe_command_windows()
│       ├─→ 必须是 PowerShell 调用
│       ├─→ 使用真实 PowerShell 进程解析 AST
│       └─→ 白名单匹配每个 pipeline 元素
│
├─→ Unix 安全命令检查 (is_safe_to_call_with_exec)
│   ├─→ 可执行名白名单匹配
│   ├─→ 命令特定参数检查
│   │   ├─→ base64: 拒绝 -o/--output
│   │   ├─→ find: 拒绝 -exec/-delete/-fprint
│   │   ├─→ rg: 拒绝 --pre/--hostname-bin/--search-zip
│   │   ├─→ git: 子命令白名单 + 全局选项检查
│   │   └─→ sed: 仅允许 -n <range>p 模式
│   └─→ bash -lc 脚本递归检查
│
└─→ 返回: true (已知安全) / false (不确定)
```

### 3.4 PowerShell AST 解析 (Windows 特有)

#### 3.4.1 技术方案

由于 PowerShell 语法复杂，模块采用**真实 PowerShell 进程**进行 AST 解析：

```rust
// windows_safe_commands.rs
fn parse_with_powershell_ast(executable: &str, script: &str) -> PowershellParseOutcome {
    // 1. 将脚本编码为 Base64 (UTF-16 LE)
    let encoded_script = encode_powershell_base64(script);
    
    // 2. 调用 PowerShell 执行解析脚本
    Command::new(executable)
        .args(["-NoLogo", "-NoProfile", "-NonInteractive", 
               "-EncodedCommand", encoded_parser_script])
        .env("CODEX_POWERSHELL_PAYLOAD", &encoded_script)
        .output()
}
```

#### 3.4.2 PowerShell 解析脚本逻辑

```powershell
# powershell_parser.ps1 核心逻辑

1. 从环境变量读取 Base64 编码的脚本
2. 使用 [System.Management.Automation.Language.Parser]::ParseInput() 解析 AST
3. 遍历 PipelineAst，提取命令元素
4. 拒绝以下构造：
   - 重定向 (Redirections)
   - 调用操作符 (&)
   - 子表达式 ($())
   - 数组展开 (@())
   - 动态表达式
5. 返回 JSON 格式的命令序列
```

#### 3.4.3 支持的 PowerShell 构造

| 构造 | 支持状态 | 说明 |
|------|----------|------|
| Pipeline | ✅ | `Get-ChildItem | Measure-Object` |
| 逻辑与 | ✅ pwsh 7+ | `cmd1 && cmd2` |
| 逻辑或 | ✅ pwsh 7+ | `cmd1 \|\| cmd2` |
| 括号分组 | ✅ | `(Get-Content file)` |
| 字符串参数 | ✅ | `'literal'` 和 `"expandable"` |
| 重定向 | ❌ | `>`, `>>`, `2>` 等 |
| 调用操作符 | ❌ | `& command` |
| 子表达式 | ❌ | `$(command)` |
| 数组展开 | ❌ | `@(command)` |

### 3.5 Bash 脚本解析 (Unix)

#### 3.5.1 Tree-sitter 解析

```rust
// bash.rs
pub fn try_parse_shell(shell_lc_arg: &str) -> Option<Tree> {
    let lang = BASH.into();
    let mut parser = Parser::new();
    parser.set_language(&lang).expect("load bash grammar");
    parser.parse(shell_lc_arg, None)
}
```

#### 3.5.2 允许的节点类型

```rust
const ALLOWED_KINDS: &[&str] = &[
    "program", "list", "pipeline",           // 顶层容器
    "command", "command_name",               // 命令
    "word", "string", "string_content",      // 单词和字符串
    "raw_string", "number", "concatenation", // 原始字符串和数字
];

const ALLOWED_PUNCT_TOKENS: &[&str] = &["&&", "||", ";", "|", "\"", "'"];
```

#### 3.5.3 拒绝的构造

- 重定向：`>`, `<`, `>>`
- 子shell：`(command)`
- 变量扩展：`$VAR`, `${VAR}`
- 命令替换：`$(cmd)`, `` `cmd` ``
- 后台执行：`&`
- 控制流：`if`, `for`, `while`, `case`

### 3.6 Git 命令特殊处理

#### 3.6.1 全局选项处理

Git 全局选项可能改变命令行为，需要特殊跳过：

```rust
// is_dangerous_command.rs
fn is_git_global_option_with_value(arg: &str) -> bool {
    matches!(arg, "-C" | "-c" | "--config-env" | "--exec-path" | 
                 "--git-dir" | "--namespace" | "--super-prefix" | "--work-tree")
}

pub(crate) fn find_git_subcommand<'a>(
    command: &'a [String],
    subcommands: &[&str],
) -> Option<(usize, &'a str)> {
    // 跳过全局选项，定位子命令
}
```

#### 3.6.2 安全子命令白名单

```rust
// is_safe_command.rs - Git 子命令检查
"status" | "log" | "diff" | "show" => {
    git_subcommand_args_are_read_only(subcommand_args)
}
"branch" => {
    git_subcommand_args_are_read_only(subcommand_args)
        && git_branch_is_read_only(subcommand_args)
}
```

#### 3.6.3 危险标志检查

```rust
const UNSAFE_GIT_FLAGS: &[&str] = &[
    "--output",      // 输出到文件
    "--ext-diff",    // 外部 diff 程序
    "--textconv",    // 文本转换
    "--exec",        // 执行命令
    "--paginate",    // 分页器
];

// 拒绝 -c / --config 全局配置覆盖
fn git_has_config_override_global_option(command: &[String]) -> bool {
    command.iter().any(|arg| {
        matches!(arg, "-c" | "--config-env") || arg.starts_with("-c") || arg.starts_with("--config-env=")
    })
}
```

---

## 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `is_dangerous_command.rs` | 161 | 危险命令检测入口，Unix 危险命令规则 |
| `is_safe_command.rs` | 602 | 安全命令白名单入口，Unix 安全命令规则，Git 特殊处理 |
| `windows_dangerous_commands.rs` | 755 | Windows 平台危险命令检测 |
| `windows_safe_commands.rs` | 623 | Windows 平台安全命令白名单，PowerShell AST 解析 |
| `powershell_parser.ps1` | 201 | PowerShell AST 解析脚本 |
| `mod.rs` | 3 | 模块导出 |

### 4.2 关键函数

#### 4.2.1 公共 API

```rust
// mod.rs 导出
pub use command_safety::is_dangerous_command::command_might_be_dangerous;
pub use command_safety::is_safe_command::is_known_safe_command;
```

#### 4.2.2 危险检测函数

| 函数 | 位置 | 说明 |
|------|------|------|
| `command_might_be_dangerous` | `is_dangerous_command.rs:7` | 主入口 |
| `is_dangerous_to_call_with_exec` | `is_dangerous_command.rs:130` | Unix 危险命令检查 |
| `is_dangerous_command_windows` | `windows_dangerous_commands.rs:8` | Windows 危险命令入口 |
| `is_dangerous_powershell` | `windows_dangerous_commands.rs:23` | PowerShell 危险检测 |
| `is_dangerous_cmd` | `windows_dangerous_commands.rs:93` | CMD 危险检测 |
| `is_direct_gui_launch` | `windows_dangerous_commands.rs:160` | GUI 启动检测 |

#### 4.2.3 安全检测函数

| 函数 | 位置 | 说明 |
|------|------|------|
| `is_known_safe_command` | `is_safe_command.rs:9` | 主入口 |
| `is_safe_to_call_with_exec` | `is_safe_command.rs:46` | Unix 安全命令检查 |
| `is_safe_command_windows` | `windows_safe_commands.rs:12` | Windows 安全命令入口 |
| `parse_powershell_invocation` | `windows_safe_commands.rs:35` | PowerShell 调用解析 |
| `parse_with_powershell_ast` | `windows_safe_commands.rs:127` | PowerShell AST 解析 |
| `is_safe_powershell_command` | `windows_safe_commands.rs:225` | PowerShell 命令白名单 |

#### 4.2.4 辅助函数

| 函数 | 位置 | 说明 |
|------|------|------|
| `executable_name_lookup_key` | `is_dangerous_command.rs:56` | 可执行文件名规范化（跨平台） |
| `find_git_subcommand` | `is_dangerous_command.rs:86` | Git 子命令定位 |
| `parse_shell_lc_plain_commands` | `bash.rs:115` | Bash/Zsh 脚本解析 |

### 4.3 测试覆盖

#### 4.3.1 测试分布

| 文件 | 测试数量 | 关键测试 |
|------|----------|----------|
| `is_dangerous_command.rs` | 2 | `rm_rf_is_dangerous`, `rm_f_is_dangerous` |
| `is_safe_command.rs` | 15+ | Git 分支变异、base64 输出、ripgrep 规则、bash -lc 序列 |
| `windows_dangerous_commands.rs` | 30+ | PowerShell 强制删除、CMD 链式命令、URL 启动 |
| `windows_safe_commands.rs` | 12+ | PowerShell 安全命令、管道、嵌套构造 |

#### 4.3.2 测试模式

```rust
// 典型测试模式
fn vec_str(items: &[&str]) -> Vec<String> {
    items.iter().map(std::string::ToString::to_string).collect()
}

#[test]
fn test_case() {
    assert!(command_might_be_dangerous(&vec_str(&["rm", "-rf", "/"])));
    assert!(is_known_safe_command(&vec_str(&["ls"])));
}
```

---

## 依赖与外部交互

### 5.1 Cargo 依赖

```toml
# codex-rs/shell-command/Cargo.toml
[dependencies]
base64 = { workspace = true }           # PowerShell 脚本编码
codex-protocol = { workspace = true }   # ParsedCommand 类型
codex-utils-absolute-path = { workspace = true }
once_cell = { workspace = true }        # 静态正则初始化
regex = { workspace = true }            # URL 检测
serde = { workspace = true }            # JSON 序列化
serde_json = { workspace = true }
shlex = { workspace = true }            # Shell 引号处理
tree-sitter = { workspace = true }      # Bash 解析
tree-sitter-bash = { workspace = true }
url = { workspace = true }              # URL 验证
which = { workspace = true }            # 可执行文件查找
```

### 5.2 内部模块依赖

```
codex-shell-command
├── lib.rs
│   ├── shell_detect.rs      # Shell 类型检测
│   ├── bash.rs              # Bash/Zsh 脚本解析
│   ├── powershell.rs        # PowerShell 命令提取
│   ├── parse_command.rs     # 命令解析（ParsedCommand）
│   └── command_safety/      # 安全评估模块
│       ├── is_dangerous_command.rs
│       ├── is_safe_command.rs
│       ├── windows_dangerous_commands.rs
│       └── windows_safe_commands.rs
```

### 5.3 外部调用方

```
codex-core
├── exec_policy.rs           # 执行策略决策
├── tools/handlers/
│   ├── shell.rs             # Shell 工具处理器
│   └── unified_exec.rs      # 统一执行处理器
└── memories/usage.rs        # 内存使用指标收集
```

### 5.4 Bazel 构建配置

```python
# codex-rs/shell-command/BUILD.bazel
codex_rust_crate(
    name = "shell-command",
    crate_name = "codex_shell_command",
    compile_data = ["src/command_safety/powershell_parser.ps1"],  # 嵌入编译产物
)
```

`powershell_parser.ps1` 通过 `include_str!` 宏嵌入到 Rust 二进制中：

```rust
// windows_safe_commands.rs
const POWERSHELL_PARSER_SCRIPT: &str = include_str!("powershell_parser.ps1");
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 解析边界

| 风险 | 说明 | 示例 |
|------|------|------|
| **Bash 解析不完整** | tree-sitter-bash 可能无法覆盖所有边缘语法 | 复杂嵌套结构 |
| **PowerShell 版本差异** | `&&`/`\|\|` 仅 pwsh 7+ 支持 | `pwsh -Command "cmd1 && cmd2"` |
| **编码问题** | PowerShell 脚本使用 UTF-16 LE Base64 编码 | 非 ASCII 字符处理 |
| **路径遍历** | 相对路径和符号链接可能绕过检查 | `../../dangerous` |

#### 6.1.2 安全绕过风险

```rust
// 潜在绕过示例（已防护）
// 1. Git 全局配置覆盖
// 已防护：git_has_config_override_global_option() 拒绝 -c/--config-env

// 2. 别名和函数
// 风险：用户可能在 shell 配置中定义危险别名
// 缓解：仅检查命令名，不展开别名

// 3. 环境变量注入
// 风险：LD_PRELOAD, PATH 污染
// 缓解：依赖外部沙箱机制
```

### 6.2 边界限制

#### 6.2.1 白名单限制

```rust
// 当前白名单仅包含基础工具
// 不支持的常见只读命令：
// - docker ps (需要 docker 白名单)
// - kubectl get (需要 k8s 白名单)
// - aws s3 ls (需要 AWS CLI 白名单)
// - 自定义脚本/工具
```

#### 6.2.2 平台差异

| 功能 | Unix | Windows |
|------|------|---------|
| 脚本解析 | tree-sitter-bash | PowerShell AST |
| 可执行名处理 | 区分大小写 | 不区分大小写，去扩展名 |
| 路径分隔符 | `/` | `\` 和 `/` |
| 登录 shell | `-lc` | `-Command` |

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强 Git 支持**
   ```rust
   // 建议：支持更多只读子命令
   "ls-files", "ls-tree", "ls-remote", "config" (仅读取)
   ```

2. **添加容器工具白名单**
   ```rust
   // 建议：只读容器命令
   "docker", "podman": ["ps", "images", "inspect", "logs", "top"]
   "kubectl": ["get", "describe", "logs", "top"]
   ```

3. **改进错误报告**
   ```rust
   // 当前：返回 bool
   // 建议：返回详细拒绝原因
   pub enum SafetyResult {
       Safe,
       Dangerous { reason: String, category: DangerCategory },
       Unknown { hint: String },
   }
   ```

#### 6.3.2 中期改进

1. **配置化白名单**
   ```toml
   # 建议：用户可配置白名单
   [safe_commands]
   allow = ["custom-tool --readonly", "my-script.sh"]
   deny = ["git", "push"]  # 覆盖默认
   ```

2. **动态行为分析**
   ```rust
   // 建议：结合静态分析和动态追踪
   // 使用 eBPF (Linux) / ETW (Windows) 监控实际系统调用
   ```

3. **机器学习辅助**
   ```rust
   // 建议：训练模型识别异常命令模式
   // 例如："rm -rf /" 的变体如 "rm -rf /*", "rm --no-preserve-root -rf /"
   ```

#### 6.3.3 长期架构

1. **统一的安全策略 DSL**
   ```rust
   // 建议：声明式安全规则
   rule! {
       command: "git",
       subcommand: ["status", "log", "diff"],
       allowed_flags: ["--short", "--oneline", "-n"],
       denied_flags: ["--output", "--exec"]
   }
   ```

2. **分层安全模型**
   ```
   Layer 1: 语法分析 (当前)
   Layer 2: 语义分析 (命令意图识别)
   Layer 3: 运行时沙箱 (Seatbelt, Landlock, Windows Sandbox)
   Layer 4: 系统调用过滤 (seccomp, eBPF)
   ```

### 6.4 测试建议

```rust
// 建议添加的测试用例

// 1. 模糊测试
#[test]
fn fuzz_command_parsing() {
    // 使用 arbitrary 生成随机命令序列
}

// 2. 跨平台一致性测试
#[test]
#[cfg(windows)]
fn windows_path_case_insensitive() {
    assert_eq!(
        is_known_safe_command(&["GIT.EXE", "status"]),
        is_known_safe_command(&["git.exe", "status"])
    );
}

// 3. 性能基准测试
#[bench]
fn bench_large_script_parsing(b: &mut Bencher) {
    let script = "ls && ".repeat(1000) + "pwd";
    b.iter(|| parse_shell_lc_plain_commands(&["bash", "-lc", &script]));
}
```

---

## 附录

### A. 文件引用汇总

| 路径 | 用途 |
|------|------|
| `codex-rs/shell-command/src/command_safety/mod.rs` | 模块导出 |
| `codex-rs/shell-command/src/command_safety/is_dangerous_command.rs` | 危险命令检测 |
| `codex-rs/shell-command/src/command_safety/is_safe_command.rs` | 安全命令白名单 |
| `codex-rs/shell-command/src/command_safety/windows_dangerous_commands.rs` | Windows 危险命令 |
| `codex-rs/shell-command/src/command_safety/windows_safe_commands.rs` | Windows 安全命令 |
| `codex-rs/shell-command/src/command_safety/powershell_parser.ps1` | PowerShell 解析脚本 |
| `codex-rs/shell-command/src/bash.rs` | Bash/Zsh 脚本解析 |
| `codex-rs/shell-command/src/powershell.rs` | PowerShell 命令提取 |
| `codex-rs/shell-command/src/shell_detect.rs` | Shell 类型检测 |
| `codex-rs/shell-command/src/parse_command.rs` | 命令解析 |
| `codex-rs/shell-command/src/lib.rs` | Crate 入口 |
| `codex-rs/shell-command/Cargo.toml` | 依赖配置 |
| `codex-rs/shell-command/BUILD.bazel` | Bazel 构建配置 |
| `codex-rs/core/src/exec_policy.rs` | 执行策略（调用方） |
| `codex-rs/core/src/tools/handlers/shell.rs` | Shell 处理器（调用方） |
| `codex-rs/core/src/tools/handlers/unified_exec.rs` | 统一执行处理器（调用方） |
| `codex-rs/core/src/memories/usage.rs` | 内存指标（调用方） |

### B. 关键常量

```rust
// 安全标志常量示例
const UNSAFE_FIND_OPTIONS: &[&str] = &[
    "-exec", "-execdir", "-ok", "-okdir",  // 执行命令
    "-delete",                              // 删除文件
    "-fls", "-fprint", "-fprint0", "-fprintf",  // 输出到文件
];

const UNSAFE_RIPGREP_OPTIONS_WITH_ARGS: &[&str] = &["--pre", "--hostname-bin"];
const UNSAFE_RIPGREP_OPTIONS_WITHOUT_ARGS: &[&str] = &["--search-zip", "-z"];

const UNSAFE_GIT_FLAGS: &[&str] = &["--output", "--ext-diff", "--textconv", "--exec", "--paginate"];
```

---

*文档生成时间: 2026-03-22*
*研究范围: codex-rs/shell-command/src/command_safety/*
