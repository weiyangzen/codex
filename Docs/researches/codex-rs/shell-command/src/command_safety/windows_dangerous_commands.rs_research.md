# windows_dangerous_commands.rs 研究文档

## 场景与职责

`windows_dangerous_commands.rs` 是 Codex 项目中专门用于 Windows 平台的危险命令检测模块。该模块负责识别在 Windows 环境下可能导致安全风险的命令，特别是：

1. **URL 启动检测**：识别可能启动浏览器或打开外部 URL 的命令
2. **强制删除检测**：识别可能强制删除文件或目录的命令
3. **ShellExecute 检测**：识别使用 ShellExecute API 执行外部程序的模式
4. **PowerShell 危险模式**：检测 PowerShell 中的危险 cmdlet 和 COM 调用

该模块仅在 Windows 平台编译（`#[cfg(windows)]`），是 `is_dangerous_command.rs` 的 Windows 特定实现。

## 功能点目的

### 1. `is_dangerous_command_windows` - 主入口函数

接收命令参数列表，进行分层检测：

```rust
pub fn is_dangerous_command_windows(command: &[String]) -> bool {
    // 1. PowerShell 危险检测
    if is_dangerous_powershell(command) { return true; }
    
    // 2. CMD 危险检测
    if is_dangerous_cmd(command) { return true; }
    
    // 3. 直接 GUI 启动检测
    is_direct_gui_launch(command)
}
```

### 2. PowerShell 危险检测 (`is_dangerous_powershell`)

检测 PowerShell 脚本中的危险模式：

#### 2.1 URL + 启动组合检测

```rust
if has_url && tokens_lc.iter().any(|t| {
    matches!(t.as_str(), "start-process" | "start" | "saps" | "invoke-item" | "ii")
    || t.contains("start-process")
    || t.contains("invoke-item")
}) {
    return true;
}
```

**风险**：`Start-Process https://example.com` 可能打开恶意网站

#### 2.2 ShellExecute/COM 检测

```rust
if has_url && tokens_lc.iter().any(|t| {
    t.contains("shellexecute") || t.contains("shell.application")
}) {
    return true;
}
```

**风险**：通过 COM 对象执行外部程序

#### 2.3 遗留 ShellExecute 路径

```rust
// rundll32 url.dll,fileprotocolhandler
if first == "rundll32" 
    && tokens_lc.iter().any(|t| t.contains("url.dll,fileprotocolhandler"))
    && has_url {
    return true;
}

// mshta
if first == "mshta" && has_url { return true; }
```

#### 2.4 浏览器直接启动

```rust
if is_browser_executable(first) && has_url { return true; }
if matches!(first.as_str(), "explorer" | "explorer.exe") && has_url { return true; }
```

#### 2.5 强制删除检测

```rust
if has_force_delete_cmdlet(&tokens_lc) { return true; }
```

检测模式：
- `Remove-Item -Force`
- `ri -Force` (别名)
- `rm -Force` (别名)
- `del -Force`
- `erase -Force`

### 3. CMD 危险检测 (`is_dangerous_cmd`)

检测 CMD 命令中的危险模式：

#### 3.1 命令解析流程

```rust
fn is_dangerous_cmd(command: &[String]) -> bool {
    // 1. 验证是 cmd.exe
    // 2. 找到 /c 或 /r 标志
    // 3. 解析剩余参数为命令
    // 4. 分割命令操作符（&, &&, |, ||）
    // 5. 对每个命令段进行危险检测
}
```

#### 3.2 危险模式检测

| 模式 | 检测条件 | 风险 |
|------|----------|------|
| `start` + URL | `start https://...` | 打开恶意网站 |
| `del /f` | `del` 或 `erase` 带 `/f` | 强制删除文件 |
| `rd /s /q` | `rd` 或 `rmdir` 带 `/s` 和 `/q` | 静默递归删除目录 |

#### 3.3 命令操作符分割

```rust
fn split_embedded_cmd_operators(token: &str) -> Vec<String> {
    // 将 "echo hi&del" 分割为 ["echo hi", "&", "del"]
    // 处理 &, &&, |, ||
}
```

### 4. 直接 GUI 启动检测 (`is_direct_gui_launch`)

检测直接调用 GUI 程序并传入 URL 的情况：

```rust
fn is_direct_gui_launch(command: &[String]) -> bool {
    // explorer + URL
    // mshta + URL
    // rundll32 + url.dll + URL
    // 浏览器 + URL
}
```

### 5. URL 检测 (`looks_like_url`)

```rust
fn looks_like_url(token: &str) -> bool {
    // 1. 去除引号和括号
    // 2. 提取 http:// 或 https:// 开头的部分
    // 3. 使用 url crate 解析验证
    // 4. 检查 scheme 是 http 或 https
}
```

### 6. PowerShell 参数解析 (`parse_powershell_invocation`)

解析 PowerShell 命令行参数，提取脚本内容：

```rust
fn parse_powershell_invocation(args: &[String]) -> Option<ParsedPowershell> {
    // 处理 -Command, /command, -c 等标志
    // 处理 -Command:value 形式
    // 跳过 -NoLogo, -NoProfile 等无害标志
    // 返回解析后的 token 列表
}
```

### 7. 强制删除 cmdlet 检测 (`has_force_delete_cmdlet`)

复杂的分段检测逻辑：

```rust
fn has_force_delete_cmdlet(tokens: &[String]) -> bool {
    const DELETE_CMDLETS: &[&str] = &["remove-item", "ri", "rm", "del", "erase", "rd", "rmdir"];
    const SEG_SEPS: &[char] = &[';', '|', '&', '\n', '\r', '\t'];
    const SOFT_SEPS: &[char] = &['{', '}', '(', ')', '[', ']', ',', ';'];
    
    // 1. 按硬分隔符分割为命令段
    // 2. 在每个段内按软分隔符分割为原子
    // 3. 检测每个段是否同时包含删除 cmdlet 和 -Force 标志
}
```

## 具体技术实现

### URL 检测实现

```rust
fn looks_like_url(token: &str) -> bool {
    static RE: Lazy<Option<Regex>> =
        Lazy::new(|| Regex::new(r#"^[ "'\(\s]*([^\s"'\);]+)[\s;\)]*$"#).ok());
    
    // 提取 URL 部分
    let urlish = token
        .find("https://")
        .or_else(|| token.find("http://"))
        .map(|idx| &token[idx..])
        .unwrap_or(token);
    
    // 正则提取核心 URL
    let candidate = RE
        .as_ref()
        .and_then(|re| re.captures(urlish))
        .and_then(|caps| caps.get(1))
        .map(|m| m.as_str())
        .unwrap_or(urlish);
    
    // 解析验证
    let Ok(url) = Url::parse(candidate) else {
        return false;
    };
    matches!(url.scheme(), "http" | "https")
}
```

### CMD 操作符分割

```rust
fn split_embedded_cmd_operators(token: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut start = 0;
    let mut it = token.char_indices().peekable();
    
    while let Some((i, ch)) = it.next() {
        if ch == '&' || ch == '|' {
            if i > start {
                parts.push(token[start..i].to_string());
            }
            
            // 检测双操作符（&&, ||）
            let op_len = match it.peek() {
                Some(&(j, next)) if next == ch => {
                    it.next();
                    (j + next.len_utf8()) - i
                }
                _ => ch.len_utf8(),
            };
            
            parts.push(token[i..i + op_len].to_string());
            start = i + op_len;
        }
    }
    
    if start < token.len() {
        parts.push(token[start..].to_string());
    }
    
    parts.retain(|s| !s.trim().is_empty());
    parts
}
```

### 强制删除检测

```rust
fn has_force_delete_cmdlet(tokens: &[String]) -> bool {
    // 构建命令段
    let mut segments: Vec<Vec<String>> = vec![Vec::new()];
    for tok in tokens {
        // 按硬分隔符分割
        let mut cur = String::new();
        for ch in tok.chars() {
            if SEG_SEPS.contains(&ch) {
                // 保存当前段，开始新段
                let s = cur.trim();
                if let Some(msg) = segments.last_mut() && !s.is_empty() {
                    msg.push(s.to_string());
                }
                cur.clear();
                if let Some(last) = segments.last() && !last.is_empty() {
                    segments.push(Vec::new());
                }
            } else {
                cur.push(ch);
            }
        }
        // ...
    }
    
    // 在每个段内检测
    segments.into_iter().any(|seg| {
        let atoms = seg
            .iter()
            .flat_map(|t| t.split(|c| SOFT_SEPS.contains(&c)))
            .map(str::trim)
            .filter(|s| !s.is_empty());
        
        let mut has_delete = false;
        let mut has_force = false;
        
        for a in atoms {
            if DELETE_CMDLETS.iter().any(|cmd| a.eq_ignore_ascii_case(cmd)) {
                has_delete = true;
            }
            if a.eq_ignore_ascii_case("-force")
                || a.get(..7).is_some_and(|p| p.eq_ignore_ascii_case("-force:"))
            {
                has_force = true;
            }
        }
        
        has_delete && has_force
    })
}
```

## 关键代码路径与文件引用

### 模块依赖

```
windows_dangerous_commands.rs
├── is_dangerous_command_windows() [入口]
│   ├── is_dangerous_powershell()
│   │   ├── is_powershell_executable()
│   │   ├── parse_powershell_invocation()
│   │   │   └── shlex_split
│   │   ├── args_have_url()
│   │   │   └── looks_like_url()
│   │   │       └── Regex + url crate
│   │   └── has_force_delete_cmdlet()
│   ├── is_dangerous_cmd()
│   │   ├── executable_basename()
│   │   ├── shlex_split
│   │   ├── split_embedded_cmd_operators()
│   │   ├── args_have_url()
│   │   ├── has_force_flag_cmd()
│   │   ├── has_recursive_flag_cmd()
│   │   └── has_quiet_flag_cmd()
│   └── is_direct_gui_launch()
│       ├── executable_basename()
│       ├── args_have_url()
│       └── is_browser_executable()
└── 辅助函数
    ├── executable_basename()
    ├── is_powershell_executable()
    └── is_browser_executable()
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `once_cell::sync::Lazy` | 正则表达式延迟初始化 |
| `regex::Regex` | URL 提取正则 |
| `shlex::split` | 命令行分词 |
| `url::Url` | URL 解析验证 |
| `std::path::Path` | 路径处理 |

### 调用方

- `is_dangerous_command.rs`：通过 `#[cfg(windows)]` 条件编译导入

## 依赖与外部交互

### 导入依赖

```rust
use std::path::Path;
use once_cell::sync::Lazy;
use regex::Regex;
use shlex::split as shlex_split;
use url::Url;
```

### 条件编译

```rust
#[cfg(windows)]
#[path = "windows_dangerous_commands.rs"]
mod windows_dangerous_commands;
```

在 `is_dangerous_command.rs` 中：

```rust
#[cfg(windows)]
#[path = "windows_dangerous_commands.rs"]
mod windows_dangerous_commands;

pub fn command_might_be_dangerous(command: &[String]) -> bool {
    #[cfg(windows)]
    {
        if windows_dangerous_commands::is_dangerous_command_windows(command) {
            return true;
        }
    }
    // ...
}
```

## 风险、边界与改进建议

### 当前风险与边界

1. **URL 检测的准确性**
   - 使用正则表达式提取 URL 可能不准确
   - 某些合法字符串可能被误判为 URL
   - URL 编码和特殊字符处理可能有边界情况

2. **PowerShell 解析限制**
   - 使用简单的 shlex 分词，不是完整解析
   - 复杂的 PowerShell 语法可能绕过检测
   - 例如：脚本块、变量展开、命令替换

3. **CMD 解析的复杂性**
   - CMD 的解析规则复杂且有时不一致
   - `split_embedded_cmd_operators` 是尽力而为的实现
   - 某些边缘情况可能处理不正确

4. **大小写敏感问题**
   - 使用 `to_ascii_lowercase()` 进行大小写不敏感比较
   - 但某些情况下可能需要保留原始大小写

5. **浏览器检测列表**
   - 硬编码的浏览器列表可能不完整
   - 新浏览器或小众浏览器可能未被覆盖

### 测试覆盖分析

当前测试非常全面，覆盖：

**PowerShell 测试**：
- ✅ `Start-Process` + URL
- ✅ `Start-Process` 本地程序（不应标记）
- ✅ `Remove-Item -Force`
- ✅ `Remove-Item -Recurse -Force`
- ✅ `ri` 别名 + Force
- ✅ `Remove-Item` 不带 Force（不应标记）
- ✅ `rm` 别名 + Force
- ✅ 分号分隔的多命令
- ✅ 代码块内的删除
- ✅ 括号内的删除
- ✅ 逗号分隔的参数

**CMD 测试**：
- ✅ `start` + URL
- ✅ `del /f`
- ✅ `erase /f`
- ✅ `del` 不带 `/f`（不应标记）
- ✅ `rd /s /q`
- ✅ `rd` 不带 `/q`（不应标记）
- ✅ `rmdir /s /q`
- ✅ 链式命令（`&`, `&&`, `||`）
- ✅ 无空格链式（`echo hi&del /f file.txt`）
- ✅ 单字符串参数（`"del /f file.txt"`）

**直接启动测试**：
- ✅ `msedge.exe` + URL
- ✅ `explorer.exe` + 目录（不应标记）

### 改进建议

1. **增强 URL 检测**
   ```rust
   // 考虑使用更严格的 URL 验证
   fn looks_like_url(token: &str) -> bool {
       // 当前：简单正则提取
       // 建议：验证主机名、排除内网 IP 等
   }
   ```

2. **支持更多危险模式**
   ```rust
   // 建议添加：
   // - Invoke-WebRequest / curl 下载执行
   // - .NET 类型实例化
   // - WMI/CIM 调用
   ```

3. **改进 PowerShell 解析**
   - 考虑使用 PowerShell AST 解析（如 `powershell_parser.ps1`）
   - 但性能开销需要权衡

4. **浏览器列表更新机制**
   ```rust
   // 考虑从配置或外部源加载浏览器列表
   const BROWSER_EXECUTABLES: &[&str] = include!("browser_list.txt");
   ```

5. **更细粒度的删除检测**
   ```rust
   // 当前：检测 -Force 标志
   // 建议：也检测 -Recurse 和特定路径模式
   ```

6. **日志和审计**
   - 记录被标记的危险命令详情
   - 帮助用户理解为什么命令被阻止

### 安全边界情况

1. **PowerShell 编码绕过**
   ```powershell
   # 当前检测基于分词
   "Start-Process https://example.com"
   
   # 潜在的绕过（需要验证）
   "Start-Process 'https://example.com'"
   "Start-Process (\"https://example.com\")"
   ```

2. **CMD 转义绕过**
   ```cmd
   # 当前检测
   cmd /c "del /f file.txt"
   
   # 潜在的绕过（需要验证）
   cmd /c "del /f\"\" file.txt"
   ```

3. **URL 变体**
   ```powershell
   # 当前检测 http/https
   # 潜在的绕过：
   "ftp://example.com/malware.exe"
   "file://C:/Windows/System32/calc.exe"
   ```
