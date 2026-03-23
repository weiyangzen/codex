# windows_safe_commands.rs 研究文档

## 场景与职责

`windows_safe_commands.rs` 是 Codex 项目中专门用于 Windows 平台的命令安全白名单模块。与 `windows_dangerous_commands.rs` 形成互补，该模块负责：

1. **PowerShell 安全命令识别**：识别已知安全的 PowerShell cmdlet 和参数组合
2. **命令序列解析**：解析 PowerShell 管道和逻辑操作符连接的命令序列
3. **只读操作验证**：确保命令不会修改文件系统或执行外部程序
4. **Git 安全检测**：在 PowerShell 环境中验证 Git 命令的安全性

该模块是 Windows 平台自动批准机制的核心组件，当命令被判定为安全时，用户无需手动确认。

## 功能点目的

### 1. `is_safe_command_windows` - 主入口函数

接收命令参数列表，返回布尔值表示是否安全：

```rust
pub fn is_safe_command_windows(command: &[String]) -> bool {
    if let Some(commands) = try_parse_powershell_command_sequence(command) {
        commands
            .iter()
            .all(|cmd| is_safe_powershell_command(cmd.as_slice()))
    } else {
        // 目前只允许 PowerShell 调用
        false
    }
}
```

**设计决策**：Windows 平台目前只允许 PowerShell 调用，其他所有命令默认不安全。

### 2. PowerShell 命令序列解析

#### 2.1 入口函数 (`try_parse_powershell_command_sequence`)

```rust
fn try_parse_powershell_command_sequence(command: &[String]) -> Option<Vec<Vec<String>>> {
    let (exe, rest) = command.split_first()?;
    if is_powershell_executable(exe) {
        parse_powershell_invocation(exe, rest)
    } else {
        None
    }
}
```

#### 2.2 调用解析 (`parse_powershell_invocation`)

解析 PowerShell 命令行参数：

```rust
fn parse_powershell_invocation(executable: &str, args: &[String]) -> Option<Vec<Vec<String>>> {
    // 处理各种参数形式：
    // - -Command <script>
    // - -c <script>
    // - -Command:<script>
    // - 直接命令序列（无 -Command）
    
    // 拒绝的参数：
    // - -EncodedCommand, -ec（编码命令，不透明）
    // - -File（脚本文件，不可控）
    // - -WindowStyle（可能隐藏窗口）
    // - -ExecutionPolicy（可能绕过限制）
    // - -WorkingDirectory（可能改变上下文）
}
```

#### 2.3 脚本解析 (`parse_powershell_script`)

使用内嵌的 PowerShell 解析器脚本：

```rust
fn parse_powershell_script(executable: &str, script: &str) -> Option<Vec<Vec<String>>> {
    if let PowershellParseOutcome::Commands(commands) =
        parse_with_powershell_ast(executable, script)
    {
        Some(commands)
    } else {
        None
    }
}
```

### 3. PowerShell AST 解析

#### 3.1 解析流程 (`parse_with_powershell_ast`)

```rust
fn parse_with_powershell_ast(executable: &str, script: &str) -> PowershellParseOutcome {
    // 1. 将用户脚本编码为 Base64 UTF-16 LE
    let encoded_script = encode_powershell_base64(script);
    
    // 2. 获取编码后的解析器脚本（内嵌 powershell_parser.ps1）
    let encoded_parser_script = encoded_parser_script();
    
    // 3. 启动 PowerShell 进程执行解析
    match Command::new(executable)
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-EncodedCommand",
            encoded_parser_script,
        ])
        .env("CODEX_POWERSHELL_PAYLOAD", &encoded_script)
        .output()
    {
        // 解析 JSON 输出
    }
}
```

#### 3.2 编码实现

PowerShell 使用 UTF-16 LE 编码：

```rust
fn encode_powershell_base64(script: &str) -> String {
    let mut utf16 = Vec::with_capacity(script.len() * 2);
    for unit in script.encode_utf16() {
        utf16.extend_from_slice(&unit.to_le_bytes());
    }
    BASE64_STANDARD.encode(utf16)
}
```

### 4. 安全命令白名单 (`is_safe_powershell_command`)

#### 4.1 嵌套不安全 cmdlet 检测

首先检查命令参数中是否嵌套了不安全的 cmdlet：

```rust
for w in words.iter() {
    let inner = w
        .trim_matches(|c| c == '(' || c == ')')
        .trim_start_matches('-')
        .to_ascii_lowercase();
    if matches!(
        inner.as_str(),
        "set-content" | "add-content" | "out-file" | "new-item" |
        "remove-item" | "move-item" | "copy-item" | "rename-item" |
        "start-process" | "stop-process"
    ) {
        return false;
    }
}
```

#### 4.2 安全命令白名单

| 命令/别名 | 说明 |
|-----------|------|
| `echo`, `write-output`, `write-host` | 输出（无重定向） |
| `dir`, `ls`, `get-childitem`, `gci` | 列出目录内容 |
| `cat`, `type`, `gc`, `get-content` | 读取文件内容 |
| `select-string`, `sls`, `findstr` | 文本搜索 |
| `measure-object`, `measure` | 统计对象属性 |
| `get-location`, `gl`, `pwd` | 获取当前目录 |
| `test-path`, `tp` | 测试路径存在 |
| `resolve-path`, `rvpa` | 解析路径 |
| `select-object`, `select` | 选择对象属性 |
| `get-item` | 获取项信息 |
| `git` | 版本控制（只读子命令） |
| `rg` | ripgrep 搜索 |

#### 4.3 显式禁止的 cmdlet

即使不在嵌套检测中，这些 cmdlet 也被显式禁止：

```rust
"set-content" | "add-content" | "out-file" | "new-item" | "remove-item" |
"move-item" | "copy-item" | "rename-item" | "start-process" | "stop-process" => false
```

### 5. Ripgrep 安全检测 (`is_safe_ripgrep`)

```rust
fn is_safe_ripgrep(words: &[String]) -> bool {
    const UNSAFE_RIPGREP_OPTIONS_WITH_ARGS: &[&str] = &["--pre", "--hostname-bin"];
    const UNSAFE_RIPGREP_OPTIONS_WITHOUT_ARGS: &[&str] = &["--search-zip", "-z"];
    
    !words.iter().skip(1).any(|arg| {
        let arg_lc = arg.to_ascii_lowercase();
        UNSAFE_RIPGREP_OPTIONS_WITHOUT_ARGS.contains(&arg_lc.as_str())
            || UNSAFE_RIPGREP_OPTIONS_WITH_ARGS
                .iter()
                .any(|opt| arg_lc == *opt || arg_lc.starts_with(&format!("{opt}=")))
    })
}
```

### 6. Git 安全检测 (`is_safe_git_command`)

```rust
fn is_safe_git_command(words: &[String]) -> bool {
    const SAFE_SUBCOMMANDS: &[&str] = &["status", "log", "show", "diff", "cat-file"];
    
    // 1. 跳过全局选项（-c, --config, --git-dir, --work-tree）
    // 2. 检查子命令是否在白名单
    // 3. 确保有子命令（纯 "git" 不安全）
}
```

## 具体技术实现

### 参数引用处理

```rust
fn quote_argument(arg: &str) -> String {
    if arg.is_empty() {
        return "''".to_string();
    }
    
    if arg.chars().all(|ch| !ch.is_whitespace()) {
        return arg.to_string();
    }
    
    // PowerShell 单引号转义：' -> ''
    format!("'{}'", arg.replace('\'', "''"))
}
```

### 参数连接

```rust
fn join_arguments_as_script(args: &[String]) -> String {
    let mut words = Vec::with_capacity(args.len());
    if let Some((first, rest)) = args.split_first() {
        words.push(first.clone());
        for arg in rest {
            words.push(quote_argument(arg));
        }
    }
    words.join(" ")
}
```

### 解析结果处理

```rust
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PowershellParserOutput {
    status: String,
    commands: Option<Vec<Vec<String>>>,
}

impl PowershellParserOutput {
    fn into_outcome(self) -> PowershellParseOutcome {
        match self.status.as_str() {
            "ok" => self
                .commands
                .filter(|commands| {
                    !commands.is_empty()
                        && commands
                            .iter()
                            .all(|cmd| !cmd.is_empty() && cmd.iter().all(|word| !word.is_empty()))
                })
                .map(PowershellParseOutcome::Commands)
                .unwrap_or(PowershellParseOutcome::Unsupported),
            "unsupported" => PowershellParseOutcome::Unsupported,
            _ => PowershellParseOutcome::Failed,
        }
    }
}
```

## 关键代码路径与文件引用

### 模块依赖图

```
windows_safe_commands.rs
├── is_safe_command_windows() [入口]
│   └── try_parse_powershell_command_sequence()
│       ├── is_powershell_executable()
│       └── parse_powershell_invocation()
│           ├── parse_powershell_script()
│           │   └── parse_with_powershell_ast()
│           │       ├── encode_powershell_base64()
│           │       ├── encoded_parser_script()
│           │       │   └── POWERSHELL_PARSER_SCRIPT
│           │       │       └── powershell_parser.ps1
│           │       └── Command::new(executable).output()
│           │           └── JSON 解析
│           │               └── PowershellParserOutput::into_outcome()
│           └── join_arguments_as_script()
│               └── quote_argument()
└── is_safe_powershell_command()
    ├── 嵌套不安全 cmdlet 检测
    └── 命令白名单匹配
        ├── is_safe_ripgrep()
        └── is_safe_git_command()
```

### 跨文件依赖

| 依赖文件 | 用途 |
|----------|------|
| `powershell_parser.ps1` | 内嵌 PowerShell 解析脚本 |

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `base64` | Base64 编码 |
| `serde::Deserialize` | JSON 解析 |
| `std::process::Command` | 执行 PowerShell |
| `std::sync::LazyLock` | 延迟初始化编码后的解析器脚本 |

## 依赖与外部交互

### 内嵌资源

```rust
const POWERSHELL_PARSER_SCRIPT: &str = include_str!("powershell_parser.ps1");

fn encoded_parser_script() -> &'static str {
    static ENCODED: LazyLock<String> =
        LazyLock::new(|| encode_powershell_base64(POWERSHELL_PARSER_SCRIPT));
    &ENCODED
}
```

### PowerShell 进程调用

```rust
Command::new(executable)
    .args([
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-EncodedCommand",
        encoded_parser_script,
    ])
    .env("CODEX_POWERSHELL_PAYLOAD", &encoded_script)
    .output()
```

**安全标志**：
- `-NoLogo`：不显示版权信息
- `-NoProfile`：不加载用户配置文件
- `-NonInteractive`：非交互模式

### 环境变量

- `CODEX_POWERSHELL_PAYLOAD`：传递给解析器的用户脚本（Base64 编码）

## 风险、边界与改进建议

### 当前风险与边界

1. **PowerShell 进程开销**
   - 每次解析都需要启动 PowerShell 进程
   - 可能影响性能（虽然命令解析通常不频繁）
   - 没有缓存机制

2. **解析器依赖性**
   - 依赖目标系统的 PowerShell 可用性
   - PowerShell 7 (pwsh) 和 Windows PowerShell 5.1 可能有行为差异
   - 某些系统可能禁用了 PowerShell

3. **白名单方法的局限性**
   - 只能识别明确列入白名单的命令
   - 新命令或自定义函数默认不安全
   - 可能过度保守

4. **嵌套检测的边界**
   ```powershell
   # 当前检测
   Write-Output (Remove-Item foo)  # 被检测
   
   # 潜在的绕过（需要验证）
   Write-Output $(Remove-Item foo)
   & { Remove-Item foo }
   ```

5. **Git 安全检测的简化**
   - 只检查子命令名称，不深入参数
   - 某些 Git 命令的参数可能危险（如 `git show --output`）

### 测试覆盖分析

当前测试非常全面：

**基础功能测试**：
- ✅ 识别安全的 PowerShell 包装器
- ✅ 接受全路径 PowerShell 调用
- ✅ pwsh 和 powershell.exe 都支持

**管道和 Git 测试**：
- ✅ 只读管道（`rg | Measure-Object | Select-Object`）
- ✅ Git 状态查询
- ✅ Git cat-file
- ✅ 括号表达式（`(Get-Content foo.rs -Raw)`）

**副作用拒绝测试**：
- ✅ `Remove-Item`
- ✅ `rg --pre`（外部命令）
- ✅ `Set-Content`
- ✅ 重定向（`>`, `2>`, `| Out-File`）
- ✅ 调用操作符（`&`）
- ✅ 链式安全+不安全命令
- ✅ 嵌套不安全 cmdlet
- ✅ 数组子表达式（`@()`）
- ✅ 逻辑操作符（`&&`）- 被 AST 解析器拒绝
- ✅ 子表达式（`$()`）
- ✅ 空字符串

**参数测试**：
- ✅ 常量表达式参数（单引号、双引号）
- ✅ 拒绝动态参数（变量）

**版本差异测试**：
- ✅ 使用调用的 PowerShell 变体进行解析

### 改进建议

1. **缓存解析结果**
   ```rust
   // 建议：使用 LRU 缓存
   static PARSE_CACHE: LazyLock<Mutex<LruCache<String, Option<Vec<Vec<String>>>>>> = ...;
   ```

2. **支持更多只读命令**
   ```rust
   // 建议添加：
   "compare-object" | "diff" => true,  // 比较对象
   "group-object" | "group" => true,   // 分组
   "sort-object" | "sort" => true,     // 排序
   "where-object" | "where" | "?" => true,  // 过滤
   "foreach-object" | "foreach" | "%" => true,  // 迭代（只读时）
   ```

3. **增强 Git 检测**
   ```rust
   // 建议：检查 Git 参数
   fn is_safe_git_command(words: &[String]) -> bool {
       // 当前：只检查子命令
       // 建议：也检查 --output 等危险标志
   }
   ```

4. **异步解析**
   ```rust
   // 建议：支持异步解析，避免阻塞
   async fn parse_powershell_script_async(...) -> ...
   ```

5. **详细拒绝原因**
   ```rust
   // 建议：返回拒绝原因，帮助用户理解
   pub enum SafetyResult {
       Safe,
       Unsafe { reason: String, command: String },
       ParseFailed { error: String },
   }
   ```

6. **PowerShell 版本检测**
   ```rust
   // 建议：检测并使用最佳可用的 PowerShell
   fn find_best_powershell() -> Option<PathBuf> {
       // 优先 pwsh，回退到 powershell
   }
   ```

### 安全边界情况

1. **别名绕过**
   ```powershell
   # 当前白名单包含别名
   # 但用户可能定义新的别名覆盖 cmdlet
   Set-Alias -Name cat -Value Remove-Item
   cat foo.txt  # 实际上是删除！
   ```
   
   **缓解**：使用 `powershell_parser.ps1` 解析后的实际命令名，而不是原始输入。

2. **函数覆盖**
   ```powershell
   # 用户可能定义同名函数
   function Get-Content { Remove-Item $args }
   Get-Content foo.txt  # 实际上是删除！
   ```
   
   **缓解**：`-NoProfile` 标志不加载用户配置文件，但函数仍可能在当前会话定义。

3. **Provider 路径**
   ```powershell
   # PowerShell 支持多种 provider
   Get-Content Registry::HKLM\Software\Key
   Get-Content Env:\PATH
   ```
   
   **当前**：只检查命令名，不检查路径。
   **风险**：某些 provider 可能有副作用。

4. **动态模块加载**
   ```powershell
   Import-Module SomeModule
   Safe-LookingCmdlet  # 实际可能有副作用
   ```
   
   **当前**：只检查命令名，不检查模块来源。
