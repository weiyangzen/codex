# shell_detect.rs 深度研究文档

## 场景与职责

`shell_detect.rs` 是 Codex 项目中负责 Shell 类型检测的最小模块，位于 `codex-rs/shell-command` crate 中。其核心职责是：

1. **Shell 类型识别**：根据可执行文件路径或名称识别 Shell 类型
2. **跨平台支持**：支持 Windows 和 Unix-like 系统的常见 Shell
3. **为上层模块提供类型标记**：`ShellType` 枚举用于指导后续解析策略

该模块是整个 shell-command crate 的基础依赖，被 `bash.rs`、`powershell.rs` 和 `parse_command.rs` 广泛调用。

## 功能点目的

### 1. Shell 类型枚举 `ShellType`

定义支持的 Shell 类型：

```rust
pub(crate) enum ShellType {
    Zsh,        // Z Shell
    Bash,       // Bourne Again Shell
    PowerShell, // Windows PowerShell / PowerShell Core
    Sh,         // Bourne Shell
    Cmd,        // Windows Command Prompt
}
```

**设计考量**：
- 使用 `#[derive(Debug, PartialEq, Eq, Clone, Copy)]`，便于比较和复制
- 标记为 `pub(crate)`，限制在 crate 内部使用

### 2. Shell 检测函数 `detect_shell_type`

**输入**：可执行文件路径（`&PathBuf`）
**输出**：`Option<ShellType>`

**检测规则**（按优先级）：

| 输入 | 识别结果 |
|-----|---------|
| `"zsh"` | `Some(ShellType::Zsh)` |
| `"sh"` | `Some(ShellType::Sh)` |
| `"cmd"` | `Some(ShellType::Cmd)` |
| `"bash"` | `Some(ShellType::Bash)` |
| `"pwsh"` | `Some(ShellType::PowerShell)` |
| `"powershell"` | `Some(ShellType::PowerShell)` |
| 其他 | 递归检测文件名（不含扩展名）|

**递归检测逻辑**：
- 提取路径的文件名（`file_stem`）
- 如果文件名与原始路径不同，递归检测文件名
- 用于处理带扩展名的路径，如 `/usr/bin/bash.exe` → `bash`

## 具体技术实现

### 完整代码分析

```rust
use std::path::Path;
use std::path::PathBuf;

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub(crate) enum ShellType {
    Zsh,
    Bash,
    PowerShell,
    Sh,
    Cmd,
}

pub(crate) fn detect_shell_type(shell_path: &PathBuf) -> Option<ShellType> {
    match shell_path.as_os_str().to_str() {
        // 直接匹配基本名称
        Some("zsh") => Some(ShellType::Zsh),
        Some("sh") => Some(ShellType::Sh),
        Some("cmd") => Some(ShellType::Cmd),
        Some("bash") => Some(ShellType::Bash),
        Some("pwsh") => Some(ShellType::PowerShell),
        Some("powershell") => Some(ShellType::PowerShell),
        _ => {
            // 递归检测：提取文件名（不含扩展名）后重试
            let shell_name = shell_path.file_stem();
            if let Some(shell_name) = shell_name {
                let shell_name_path = Path::new(shell_name);
                if shell_name_path != Path::new(shell_path) {
                    return detect_shell_type(&shell_name_path.to_path_buf());
                }
            }
            None
        }
    }
}
```

### 递归检测示例

| 输入路径 | 递归步骤 | 最终结果 |
|---------|---------|---------|
| `/usr/bin/bash` | 直接匹配 "bash" | `Some(Bash)` |
| `bash.exe` | 提取 stem "bash" → 匹配 | `Some(Bash)` |
| `/bin/zsh` | 直接匹配 "zsh" | `Some(Zsh)` |
| `pwsh.exe` | 提取 stem "pwsh" → 匹配 | `Some(PowerShell)` |
| `C:\Windows\System32\cmd.exe` | 提取 stem "cmd" → 匹配 | `Some(Cmd)` |
| `python` | 无匹配，stem 与原始相同 | `None` |
| `node.js` | 提取 stem "node" → 无匹配 | `None` |

### 终止条件

递归检测的终止条件：
```rust
if shell_name_path != Path::new(shell_path) {
    return detect_shell_type(&shell_name_path.to_path_buf());
}
```

- 当 `file_stem()` 返回的名称与原始路径相同时停止递归
- 避免无限递归（如路径本身就是单个无扩展名的名称）

## 关键代码路径与文件引用

### 文件位置

- **文件路径**: `codex-rs/shell-command/src/shell_detect.rs`
- **总行数**: 32 行（含空行和注释）
- **枚举定义**: line 4-11
- **检测函数**: line 13-32

### 内部使用方

| 使用方 | 文件路径 | 用途 |
|-------|---------|------|
| `extract_bash_command` | `bash.rs:103` | 验证是否为 Bash/Zsh/Sh |
| `extract_powershell_command` | `powershell.rs:47-50` | 验证是否为 PowerShell |

### 使用示例

```rust
// bash.rs
if !matches!(
    detect_shell_type(&PathBuf::from(shell)),
    Some(ShellType::Zsh) | Some(ShellType::Bash) | Some(ShellType::Sh)
) {
    return None;
}

// powershell.rs
if !matches!(
    detect_shell_type(&PathBuf::from(shell)),
    Some(ShellType::PowerShell)
) {
    return None;
}
```

## 依赖与外部交互

### 标准库依赖

```rust
use std::path::Path;
use std::path::PathBuf;
```

仅依赖 Rust 标准库的 `std::path` 模块，无外部 crate 依赖。

### 模块可见性

- `ShellType` 和 `detect_shell_type` 均为 `pub(crate)`
- 仅在 `shell-command` crate 内部可见
- 不对外暴露（不在 `lib.rs` 的 `pub use` 中）

### 与系统 Shell 的对应关系

| ShellType | 典型路径（Linux） | 典型路径（Windows） |
|-----------|------------------|-------------------|
| `Zsh` | `/bin/zsh`, `/usr/bin/zsh` | WSL: `/bin/zsh` |
| `Bash` | `/bin/bash`, `/usr/bin/bash` | Git Bash: `C:\Program Files\Git\bin\bash.exe` |
| `Sh` | `/bin/sh` | WSL: `/bin/sh` |
| `PowerShell` | `/usr/bin/pwsh`（如果安装） | `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| `Cmd` | N/A | `C:\Windows\System32\cmd.exe` |

## 风险、边界与改进建议

### 已知风险

1. **检测范围有限**
   - 仅支持 5 种常见 Shell
   - 不支持其他流行 Shell（如 `fish`、`dash`、`ksh`、`tcsh`）
   - 不支持通过符号链接调用的 Shell（如 `/bin/sh` 指向 `dash`）

2. **大小写敏感**
   - 字符串匹配区分大小写
   - `PowerShell` 或 `POWERSHELL` 不会被识别
   - Windows 上路径通常不区分大小写，可能导致漏检

3. **路径解析依赖**
   - 依赖 `PathBuf::as_os_str().to_str()` 成功转换
   - 非 UTF-8 路径可能导致检测失败

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|-----|---------|---------|
| `"/usr/bin/zsh"` | 识别为 Zsh | ✅ 正确 |
| `"zsh.exe"` | 识别为 Zsh | ✅ 正确 |
| `"/bin/sh"` | 识别为 Sh | ⚠️ 实际可能是 dash 的符号链接 |
| `"fish"` | 返回 None | ❌ 不支持 fish shell |
| `""`（空路径） | 返回 None | ✅ 合理 |
| `"/path/to/custom/bash"` | 识别为 Bash | ✅ 通过 stem 检测 |
| `"powershell.exe"` | 识别为 PowerShell | ✅ 正确 |
| `"pwsh-preview"` | 返回 None | ⚠️ 预览版不支持 |

### 改进建议

1. **扩展 Shell 支持**
   ```rust
   pub(crate) enum ShellType {
       // 现有类型...
       Fish,  // Friendly Interactive Shell
       Dash,  // Debian Almquist Shell
       Ksh,   // Korn Shell
       Tcsh,  // TENEX C Shell
   }
   ```

2. **大小写不敏感匹配**
   ```rust
   Some(s) if s.eq_ignore_ascii_case("powershell") => Some(ShellType::PowerShell),
   ```

3. **符号链接追踪**
   ```rust
   // 使用 std::fs::canonicalize 或 read_link 追踪符号链接
   if let Ok(real_path) = std::fs::canonicalize(shell_path) {
       return detect_shell_type(&real_path);
   }
   ```

4. **更灵活的匹配**
   - 支持前缀匹配（如 `pwsh-preview` → `PowerShell`）
   - 支持常见别名（如 `posh` → `PowerShell`）

5. **错误处理增强**
   - 返回 `Result<ShellType, ShellDetectError>` 替代 `Option`
   - 提供详细的检测失败原因

6. **缓存机制**
   - 使用 `once_cell::Lazy` 或 `std::sync::OnceLock` 缓存检测结果
   - 避免重复解析相同路径

### 测试建议

当前模块无测试代码，建议添加：

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_basic_shells() {
        assert_eq!(detect_shell_type(&PathBuf::from("bash")), Some(ShellType::Bash));
        assert_eq!(detect_shell_type(&PathBuf::from("zsh")), Some(ShellType::Zsh));
        assert_eq!(detect_shell_type(&PathBuf::from("pwsh")), Some(ShellType::PowerShell));
    }

    #[test]
    fn detects_with_extension() {
        assert_eq!(detect_shell_type(&PathBuf::from("bash.exe")), Some(ShellType::Bash));
        assert_eq!(detect_shell_type(&PathBuf::from("powershell.exe")), Some(ShellType::PowerShell));
    }

    #[test]
    fn detects_full_path() {
        assert_eq!(
            detect_shell_type(&PathBuf::from("/usr/bin/bash")),
            Some(ShellType::Bash)
        );
    }

    #[test]
    fn returns_none_for_unknown() {
        assert_eq!(detect_shell_type(&PathBuf::from("python")), None);
        assert_eq!(detect_shell_type(&PathBuf::from("node")), None);
    }

    #[test]
    fn case_sensitivity() {
        // 当前实现行为（大小写敏感）
        assert_eq!(detect_shell_type(&PathBuf::from("Bash")), None);
        assert_eq!(detect_shell_type(&PathBuf::from("POWERSHELL")), None);
    }
}
```

### 架构考量

该模块虽小，但在架构上承担重要角色：

1. **单一职责**：只做 Shell 类型检测，不涉及解析逻辑
2. **不可变性**：纯函数，无副作用，便于测试和缓存
3. **平台抽象**：统一接口屏蔽 Windows/Unix 差异

未来如需支持更多 Shell 类型，建议：
- 保持向后兼容（现有枚举变体不变）
- 考虑使用特征（trait）替代枚举，支持用户扩展
- 或添加 `Other(String)` 变体捕获未知 Shell
