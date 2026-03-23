# powershell_parser.ps1 研究文档

## 场景与职责

`powershell_parser.ps1` 是一个 PowerShell 脚本，被嵌入到 Rust 代码中（通过 `include_str!`），用于在运行时解析 PowerShell 命令。该脚本的主要职责是：

1. **AST 解析**：使用 PowerShell 的原生解析器（`System.Management.Automation.Language.Parser`）将脚本解析为 AST
2. **命令提取**：从 AST 中提取命令序列，转换为 Rust 可处理的格式
3. **安全检查前置**：在解析阶段就拒绝不安全的构造

该脚本被 `windows_safe_commands.rs` 使用，是 Windows 平台命令安全检测的关键组件。

## 功能点目的

### 1. 脚本解析流程

```powershell
# 1. 从环境变量获取 Base64 编码的脚本
$payload = $env:CODEX_POWERSHELL_PAYLOAD

# 2. 解码为 Unicode 字符串
[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($payload))

# 3. 使用 PowerShell 解析器生成 AST
[System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
```

### 2. 命令提取

将 PowerShell AST 转换为命令序列的 JSON 表示：

```json
{
  "status": "ok",
  "commands": [
    ["Get-ChildItem", "-Path", "."],
    ["Measure-Object"]
  ]
}
```

### 3. 安全构造限制

脚本只接受以下安全构造：
- 简单命令（`CommandAst`）
- 管道（`|`）
- 逻辑操作符（`&&`, `||`）
- 字符串常量（单引号、双引号）
- 数字常量

**拒绝的构造**：
- 重定向（`>`, `>>`, `<`）
- 调用操作符（`&`）
- 子表达式（`$()`）
- 数组子表达式（`@()`）
- 变量
- 脚本块

## 具体技术实现

### 核心函数

#### `Convert-CommandElement`

将 AST 命令元素转换为字符串数组：

```powershell
function Convert-CommandElement {
    param($element)

    # 字符串常量
    if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return @($element.Value)
    }

    # 可扩展字符串（但拒绝包含嵌套表达式）
    if ($element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        if ($element.NestedExpressions.Count -gt 0) {
            return $null  # 拒绝变量插值
        }
        return @($element.Value)
    }

    # 常量表达式
    if ($element -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return @($element.Value.ToString())
    }

    # 命令参数
    if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
        if ($element.Argument -eq $null) {
            return @('-' + $element.ParameterName)
        }
        # ... 处理带值的参数
    }

    return $null  # 拒绝其他类型
}
```

#### `Convert-PipelineElement`

转换管道元素：

```powershell
function Convert-PipelineElement {
    param($element)

    # 命令
    if ($element -is [System.Management.Automation.Language.CommandAst]) {
        # 拒绝重定向
        if ($element.Redirections.Count -gt 0) {
            return $null
        }
        # 拒绝调用操作符
        if ($element.InvocationOperator -ne $null) {
            return $null
        }
        # ... 转换命令元素
    }

    # 命令表达式（处理括号表达式）
    if ($element -is [System.Management.Automation.Language.CommandExpressionAst]) {
        # 拒绝重定向
        if ($element.Redirections.Count -gt 0) {
            return $null
        }
        # 递归处理括号表达式
        if ($element.Expression -is [System.Management.Automation.Language.ParenExpressionAst]) {
            # ...
        }
    }

    return $null
}
```

#### `Add-CommandsFromPipelineBase`

递归处理管道链：

```powershell
function Add-CommandsFromPipelineBase {
    param($pipeline, $commands)

    # 普通管道
    if ($pipeline -is [System.Management.Automation.Language.PipelineAst]) {
        return Add-CommandsFromPipelineAst $pipeline $commands
    }

    # 管道链（&&, ||）
    if ($pipeline -is [System.Management.Automation.Language.PipelineChainAst]) {
        return Add-CommandsFromPipelineChain $pipeline $commands
    }

    return $false
}
```

### 输出格式

脚本输出 JSON 格式的结果：

```powershell
$result = if ($commands -eq $null) {
    @{ status = 'unsupported' }
} else {
    @{ status = 'ok'; commands = $commands }
}

,$result | ConvertTo-Json -Depth 3
```

**状态码**：
- `ok`：成功解析，返回命令序列
- `unsupported`：包含不支持的构造
- `parse_failed`：解析失败（Base64 解码或解析错误）
- `parse_errors`：解析有错误

## 关键代码路径与文件引用

### 调用链

```
windows_safe_commands.rs
├── parse_with_powershell_ast()
│   ├── encode_powershell_base64()          # UTF-16 LE Base64 编码
│   ├── encoded_parser_script()             # 获取编码后的解析器脚本
│   │   └── POWERSHELL_PARSER_SCRIPT        # include_str!("powershell_parser.ps1")
│   └── Command::new(executable)
│       ├── -NoLogo -NoProfile -NonInteractive -EncodedCommand <parser_script>
│       └── env: CODEX_POWERSHELL_PAYLOAD=<user_script>
└── PowershellParserOutput::into_outcome()
    └── 解析 JSON 输出
```

### 在 Rust 中的使用

```rust
// windows_safe_commands.rs
const POWERSHELL_PARSER_SCRIPT: &str = include_str!("powershell_parser.ps1");

fn parse_with_powershell_ast(executable: &str, script: &str) -> PowershellParseOutcome {
    let encoded_script = encode_powershell_base64(script);
    let encoded_parser_script = encoded_parser_script();
    
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
        // ... 处理输出
    }
}
```

## 依赖与外部交互

### PowerShell API 依赖

| API | 用途 |
|-----|------|
| `System.Management.Automation.Language.Parser::ParseInput` | PowerShell 脚本解析 |
| `System.Text.Encoding::Unicode` | UTF-16 LE 编码 |
| `System.Convert::FromBase64String` | Base64 解码 |
| `ConvertTo-Json` | JSON 序列化 |

### 环境变量

- `CODEX_POWERSHELL_PAYLOAD`：输入的 Base64 编码脚本

### 编码细节

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

## 风险、边界与改进建议

### 当前风险与边界

1. **解析器依赖性**
   - 依赖目标系统的 PowerShell 解析器
   - 不同 PowerShell 版本可能有行为差异
   - PowerShell 7 (pwsh) 和 Windows PowerShell 5.1 的 AST 可能略有不同

2. **编码复杂性**
   - 需要 UTF-16 LE Base64 编码
   - 增加了调用复杂性和性能开销

3. **进程创建开销**
   - 每次解析都需要启动 PowerShell 进程
   - 可能影响性能（虽然命令解析通常不频繁）

4. **错误处理限制**
   - 解析失败时只返回简单状态码
   - 没有详细的错误信息传递给用户

5. **安全构造的保守性**
   - 为了安全，拒绝了许多合法的 PowerShell 构造
   - 可能影响用户体验（某些安全命令被拒绝）

### 测试覆盖

该脚本本身没有直接的单元测试，测试通过 `windows_safe_commands.rs` 的测试间接覆盖：

- ✅ 简单命令解析
- ✅ 管道解析
- ✅ 逻辑操作符解析
- ✅ 字符串参数
- ✅ 拒绝重定向
- ✅ 拒绝调用操作符
- ✅ 拒绝变量
- ✅ 拒绝子表达式

### 改进建议

1. **缓存解析结果**
   ```rust
   // 建议：使用 LRU 缓存解析结果
   static PARSE_CACHE: LazyLock<Mutex<LruCache<String, PowershellParseOutcome>>> = ...;
   ```

2. **详细错误信息**
   ```powershell
   # 当前
   @{ status = 'unsupported' }
   
   # 建议
   @{ status = 'unsupported'; reason = 'redirection_not_allowed'; line = 1 }
   ```

3. **版本兼容性检查**
   ```powershell
   # 添加版本检测
   $psVersion = $PSVersionTable.PSVersion
   if ($psVersion.Major -lt 5) {
       @{ status = 'version_unsupported'; min_required = '5.0' }
   }
   ```

4. **性能优化**
   - 考虑使用 PowerShell 的持久化进程（类似 Language Server）
   - 减少进程启动开销

5. **更细粒度的安全控制**
   ```powershell
   # 当前：完全拒绝重定向
   if ($element.Redirections.Count -gt 0) { return $null }
   
   # 建议：区分输入/输出重定向
   foreach ($redir in $element.Redirections) {
       if ($redir -is [System.Management.Automation.Language.FileRedirectionAst]) {
           if ($redir.FromStream -eq 'Output' -and -not $redir.Appending) {
               # 输出重定向到文件是危险的
               return $null
           }
       }
   }
   ```

6. **支持更多安全构造**
   - 考虑允许某些安全的变量（如 `$PSVersionTable`）
   - 考虑允许某些安全的脚本块

### 安全考虑

1. **输入验证**
   - 脚本对输入进行 Base64 解码，可能受到畸形输入攻击
   - 需要确保解码失败时优雅处理

2. **环境隔离**
   - 使用 `-NoProfile` 和 `-NonInteractive` 减少环境干扰
   - 但解析器仍然可以访问某些系统信息

3. **拒绝服务**
   - 恶意构造的脚本可能导致解析器挂起或消耗大量资源
   - 考虑添加超时机制
