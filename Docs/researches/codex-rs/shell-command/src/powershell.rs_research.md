# powershell.rs 深度研究文档

## 场景与职责

`powershell.rs` 是 Codex 项目中专门处理 PowerShell 命令的模块，位于 `codex-rs/shell-command` crate 中。其主要职责包括：

1. **PowerShell 命令提取**：从 PowerShell 调用序列中提取脚本内容
2. **UTF-8 输出强制**：为 PowerShell 脚本添加 UTF-8 编码前缀，确保跨平台输出一致性
3. **可执行文件发现**：在 Windows 系统上查找 `pwsh.exe` 或 `powershell.exe`

该模块主要针对 Windows 平台，但部分功能（如命令提取）在跨平台场景下也适用。

## 功能点目的

### 1. PowerShell 命令提取 `extract_powershell_command`

解析形如以下的 PowerShell 调用：
```powershell
pwsh -NoProfile -Command "Get-ChildItem"
powershell.exe -c "Write-Host hi"
```

**提取逻辑**：
- 验证第一个参数是 PowerShell 可执行文件（通过 `detect_shell_type`）
- 扫描 `-Command` 或 `-c` 标志
- 支持其他常见标志：`-NoLogo`、`-NoProfile`、`-nologo`、`-noprofile`
- 返回 `(shell_name, script_body)` 元组

### 2. UTF-8 输出前缀注入 `prefix_powershell_script_with_utf8`

**问题背景**：
- Windows PowerShell 默认使用系统本地编码（如 GBK、Windows-1252）
- 这导致非 ASCII 字符（如中文、emoji）在输出时乱码

**解决方案**：
```rust
pub const UTF8_OUTPUT_PREFIX: &str = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;\n";
```

在脚本前注入该命令，强制 PowerShell 使用 UTF-8 编码输出。

**去重逻辑**：
- 检查脚本是否已以该前缀开头
- 避免重复添加前缀

### 3. PowerShell 可执行文件发现

支持两种 PowerShell 版本：

| 版本 | 可执行文件 | 特点 |
|-----|-----------|------|
| PowerShell Core | `pwsh.exe` | 跨平台，v6+，需单独安装 |
| Windows PowerShell | `powershell.exe` | Windows 内置，v5.1 及更早 |

**发现策略**：
1. 首先尝试 `pwsh.exe`（优先使用新版）
2. 通过 `cmd /C pwsh -NoProfile -Command $PSHOME` 获取安装路径
3. 回退到 PATH 查找
4. 最后尝试 `powershell.exe`

**可用性验证**：
```rust
fn is_powershellish_executable_available(path: &Path) -> bool {
    // 执行 "Write-Output ok" 测试命令
}
```

## 具体技术实现

### 核心常量

```rust
const POWERSHELL_FLAGS: &[&str] = &["-nologo", "-noprofile", "-command", "-c"];
pub const UTF8_OUTPUT_PREFIX: &str = "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;\n";
```

### 命令提取算法

```rust
pub fn extract_powershell_command(command: &[String]) -> Option<(&str, &str)> {
    // 1. 长度检查（至少3个参数：exe, flag, script）
    if command.len() < 3 { return None; }
    
    // 2. Shell 类型验证
    let shell = &command[0];
    if !matches!(detect_shell_type(&PathBuf::from(shell)), Some(ShellType::PowerShell)) {
        return None;
    }
    
    // 3. 扫描标志
    let mut i = 1;
    while i + 1 < command.len() {
        let flag = &command[i];
        // 只允许已知标志
        if !POWERSHELL_FLAGS.contains(&flag.to_ascii_lowercase().as_str()) {
            return None;
        }
        // 找到 -Command/-c，返回下一个参数作为脚本
        if flag.eq_ignore_ascii_case("-Command") || flag.eq_ignore_ascii_case("-c") {
            return Some((shell, &command[i + 1]));
        }
        i += 1;
    }
    None
}
```

### UTF-8 前缀注入

```rust
pub fn prefix_powershell_script_with_utf8(command: &[String]) -> Vec<String> {
    let Some((_, script)) = extract_powershell_command(command) else {
        return command.to_vec();  // 非 PowerShell 命令，原样返回
    };
    
    let trimmed = script.trim_start();
    let script = if trimmed.starts_with(UTF8_OUTPUT_PREFIX) {
        script.to_string()  // 已存在前缀，不重复添加
    } else {
        format!("{UTF8_OUTPUT_PREFIX}{script}")  // 添加前缀
    };
    
    // 重建命令数组：保留原参数，替换脚本部分
    let mut command: Vec<String> = command[..(command.len() - 1)]
        .iter()
        .map(ToString::to_string)
        .collect();
    command.push(script);
    command
}
```

### 可执行文件发现流程

```
try_find_pwsh_executable_blocking()
├── 尝试通过 cmd 获取 $PSHOME
│   └── cmd /C pwsh -NoProfile -Command $PSHOME
├── 如果成功，在 $PSHOME 下查找 pwsh.exe
│   └── 验证可执行性（is_powershellish_executable_available）
├── 回退：PATH 中查找 pwsh.exe（which::which）
└── 验证可执行性

try_find_powershell_executable_blocking()
└── 在 PATH 中查找 powershell.exe

try_find_powershellish_executable_blocking()（Windows only）
├── 先尝试 pwsh
└── 再尝试 powershell
```

## 关键代码路径与文件引用

### 主要函数位置

| 函数 | 行号 | 说明 |
|-----|------|------|
| `extract_powershell_command` | 41-69 | 核心提取函数 |
| `prefix_powershell_script_with_utf8` | 13-31 | UTF-8 前缀注入 |
| `try_find_pwsh_executable_blocking` | 99-123 | pwsh 发现 |
| `try_find_powershell_executable_blocking` | 85-87 | powershell 发现 |
| `try_find_powershellish_executable_blocking` | 76-82 | 综合发现（Windows）|
| `is_powershellish_executable_available` | 145-152 | 可用性验证 |

### 内部依赖

```rust
use crate::shell_detect::ShellType;
use crate::shell_detect::detect_shell_type;
use codex_utils_absolute_path::AbsolutePathBuf;
```

- `shell_detect.rs`: Shell 类型检测
- `codex_utils_absolute_path`: 绝对路径处理

### 测试覆盖

测试模块位于 line 154-204，覆盖：
- 基本命令提取
- 小写标志处理
- 完整路径 PowerShell
- `-NoProfile` + `-c` 别名组合

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `which` | 在 PATH 中查找可执行文件 |
| `codex_utils_absolute_path` | 绝对路径解析和验证 |

### 与 parse_command.rs 的交互

```rust
// parse_command.rs line 16-18
pub fn extract_shell_command(command: &[String]) -> Option<(&str, &str)> {
    extract_bash_command(command).or_else(|| extract_powershell_command(command))
}

// parse_command.rs line 1280-1284
if let Some((_, script)) = extract_powershell_command(command) {
    return vec![ParsedCommand::Unknown { cmd: script.to_string() }];
}
```

PowerShell 命令在 `parse_command.rs` 中被提取后，当前实现将其统一标记为 `Unknown` 类型（因为 PowerShell 脚本解析复杂度较高）。

### 调用方

通过 `extract_powershell_command` 被调用：
- `parse_command.rs`: 命令解析

通过 `prefix_powershell_script_with_utf8` 被调用：
- 可能在执行层使用（需确认具体调用点）

## 风险、边界与改进建议

### 已知风险

1. **PowerShell 脚本解析局限**
   - 当前不对 PowerShell 脚本内容进行深度解析
   - 所有 PowerShell 命令被归类为 `Unknown`，失去语义信息
   - 建议：未来可添加专门的 PowerShell 解析器（如使用 tree-sitter-powershell）

2. **UTF-8 前缀依赖系统配置**
   - `[Console]::OutputEncoding` 设置可能被后续脚本覆盖
   - 某些旧版 Windows PowerShell 可能不支持该命令

3. **可执行文件发现的不确定性**
   - `which` crate 在 Windows 上的行为可能与预期有差异
   - $PSHOME 方法依赖 pwsh 已在 PATH 中

### 边界情况

| 场景 | 处理方式 |
|-----|---------|
| 大小写混合标志 | 使用 `eq_ignore_ascii_case` 处理 |
| 未知标志 | 立即返回 None，拒绝解析 |
| 脚本为空字符串 | 正常返回（调用方处理）|
| pwsh 未安装 | 回退到 powershell.exe |
| 两者都未找到 | 返回 None |

### 改进建议

1. **功能扩展**
   - 支持 PowerShell 的 `-File` 参数（执行脚本文件）
   - 支持 `-EncodedCommand`（Base64 编码命令）
   - 添加 PowerShell Core 版本检测

2. **安全性增强**
   - 对提取的脚本进行基本的危险命令扫描
   - 考虑添加执行策略（Execution Policy）检查

3. **性能优化**
   - 缓存可执行文件查找结果
   - 避免重复验证 PowerShell 可用性

4. **跨平台改进**
   - Linux/macOS 上的 PowerShell Core 支持
   - 处理不同平台的 PATH 分隔符

5. **测试覆盖**
   - 添加 Windows 特有的集成测试
   - 测试各种 PowerShell 版本组合
   - 测试 UTF-8 前缀在复杂脚本中的行为

### 代码质量建议

1. `try_find_powershellish_executable_blocking` 被标记为 `#[allow(dead_code)]`，需确认是否实际使用
2. 错误处理较为简单，可考虑添加更详细的错误类型
3. 字符串比较使用 `to_ascii_lowercase()`，在热路径上可能有性能影响
