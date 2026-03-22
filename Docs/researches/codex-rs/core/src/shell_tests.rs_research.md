# shell_tests.rs 深度研究文档

## 场景与职责

`shell_tests.rs` 是 Codex 核心模块中 `shell.rs` 的配套测试文件，位于 `codex-rs/core/src/` 目录下。其主要职责是验证 Shell 检测、路径解析和命令执行参数生成的正确性。

该测试文件覆盖以下关键方面：
1. **Shell 路径检测** - 验证各类型 Shell 的自动发现
2. **回退逻辑** - 验证当首选 Shell 不可用时正确回退
3. **命令执行** - 验证生成的命令参数能正确执行
4. **参数生成** - 验证 `derive_exec_args` 的输出格式
5. **平台适配** - 验证不同操作系统下的行为差异

## 功能点目的

### 1. Shell 检测测试
验证 `get_shell` 函数能正确找到系统中安装的 Shell：
- Zsh（macOS 默认）
- Bash（Linux 常见）
- Sh（POSIX 兼容）
- PowerShell（Windows 和跨平台）
- Cmd（Windows）

### 2. 回退逻辑测试
验证当用户默认 Shell 不受支持时（如 Fish），系统能正确回退到支持的 Shell。

### 3. 命令执行测试
验证生成的 Shell 命令参数能实际执行并产生预期输出。

### 4. 参数格式测试
验证 `derive_exec_args` 为不同 Shell 生成正确的参数格式，包括登录 Shell 和非登录 Shell 的区别。

### 5. 默认 Shell 测试
验证 `default_user_shell` 根据平台选择正确的默认 Shell。

## 具体技术实现

### 关键测试用例

#### 1. Zsh 检测测试 (macOS)
```rust
#[test]
#[cfg(target_os = "macos")]
fn detects_zsh() {
    let zsh_shell = get_shell(ShellType::Zsh, None).unwrap();
    let shell_path = zsh_shell.shell_path;
    assert_eq!(shell_path, std::path::Path::new("/bin/zsh"));
}
```

验证在 macOS 上能正确找到 `/bin/zsh`。

#### 2. Fish 回退测试 (macOS)
```rust
#[test]
#[cfg(target_os = "macos")]
fn fish_fallback_to_zsh() {
    let zsh_shell = default_user_shell_from_path(Some(PathBuf::from("/bin/fish")));
    let shell_path = zsh_shell.shell_path;
    assert_eq!(shell_path, std::path::Path::new("/bin/zsh"));
}
```

验证当用户默认 Shell 是 Fish（不支持）时，回退到 Zsh。

**回退链（macOS）：**
```
用户默认 Shell（如果不支持）
→ Zsh
→ Bash
→ Sh（终极回退）
```

**回退链（Linux）：**
```
用户默认 Shell（如果不支持）
→ Bash
→ Zsh
→ Sh（终极回退）
```

#### 3. Bash 检测测试
```rust
#[test]
fn detects_bash() {
    let bash_shell = get_shell(ShellType::Bash, None).unwrap();
    let shell_path = bash_shell.shell_path;
    assert!(
        shell_path.file_name().and_then(|name| name.to_str()) == Some("bash"),
        "shell path: {shell_path:?}",
    );
}
```

验证能找到 Bash，路径可能因系统而异（`/bin/bash`、`/usr/bin/bash` 等）。

#### 4. Sh 检测测试
```rust
#[test]
fn detects_sh() {
    let sh_shell = get_shell(ShellType::Sh, None).unwrap();
    let shell_path = sh_shell.shell_path;
    assert!(
        shell_path.file_name().and_then(|name| name.to_str()) == Some("sh"),
        "shell path: {shell_path:?}",
    );
}
```

#### 5. Shell 执行测试
```rust
#[test]
fn can_run_on_shell_test() {
    let cmd = "echo \"Works\"";
    if cfg!(windows) {
        assert!(shell_works(
            get_shell(ShellType::PowerShell, None),
            "Out-String 'Works'",
            true,
        ));
        assert!(shell_works(get_shell(ShellType::Cmd, None), cmd, true));
        assert!(shell_works(Some(ultimate_fallback_shell()), cmd, true));
    } else {
        assert!(shell_works(Some(ultimate_fallback_shell()), cmd, true));
        assert!(shell_works(get_shell(ShellType::Zsh, None), cmd, false));
        assert!(shell_works(get_shell(ShellType::Bash, None), cmd, true));
        assert!(shell_works(get_shell(ShellType::Sh, None), cmd, true));
    }
}

fn shell_works(shell: Option<Shell>, command: &str, required: bool) -> bool {
    if let Some(shell) = shell {
        let args = shell.derive_exec_args(command, false);
        let output = Command::new(args[0].clone())
            .args(&args[1..])
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(String::from_utf8_lossy(&output.stdout).contains("Works"));
        true
    } else {
        !required
    }
}
```

验证各 Shell 能实际执行命令：
- Windows：PowerShell、Cmd、终极回退
- Unix：终极回退、Zsh、Bash、Sh

**注意：** Zsh 测试标记为 `false`（非必需），可能因为某些环境 Zsh 未安装。

#### 6. 参数生成测试
```rust
#[test]
fn derive_exec_args() {
    // Bash 测试
    let test_bash_shell = Shell {
        shell_type: ShellType::Bash,
        shell_path: PathBuf::from("/bin/bash"),
        shell_snapshot: empty_shell_snapshot_receiver(),
    };
    assert_eq!(
        test_bash_shell.derive_exec_args("echo hello", false),
        vec!["/bin/bash", "-c", "echo hello"]
    );
    assert_eq!(
        test_bash_shell.derive_exec_args("echo hello", true),
        vec!["/bin/bash", "-lc", "echo hello"]
    );
    
    // Zsh 测试
    let test_zsh_shell = Shell {
        shell_type: ShellType::Zsh,
        shell_path: PathBuf::from("/bin/zsh"),
        shell_snapshot: empty_shell_snapshot_receiver(),
    };
    assert_eq!(
        test_zsh_shell.derive_exec_args("echo hello", false),
        vec!["/bin/zsh", "-c", "echo hello"]
    );
    assert_eq!(
        test_zsh_shell.derive_exec_args("echo hello", true),
        vec!["/bin/zsh", "-lc", "echo hello"]
    );
    
    // PowerShell 测试
    let test_powershell_shell = Shell {
        shell_type: ShellType::PowerShell,
        shell_path: PathBuf::from("pwsh.exe"),
        shell_snapshot: empty_shell_snapshot_receiver(),
    };
    assert_eq!(
        test_powershell_shell.derive_exec_args("echo hello", false),
        vec!["pwsh.exe", "-NoProfile", "-Command", "echo hello"]
    );
    assert_eq!(
        test_powershell_shell.derive_exec_args("echo hello", true),
        vec!["pwsh.exe", "-Command", "echo hello"]
    );
}
```

验证 `derive_exec_args` 的输出格式：

| Shell | 非登录 | 登录 |
|-------|--------|------|
| Bash/Zsh/Sh | `-c` | `-lc` |
| PowerShell | `-NoProfile -Command` | `-Command` |
| Cmd | `/c` | N/A |

#### 7. 当前 Shell 检测测试
```rust
#[tokio::test]
async fn test_current_shell_detects_zsh() {
    let shell = Command::new("sh")
        .arg("-c")
        .arg("echo $SHELL")
        .output()
        .unwrap();
    
    let shell_path = String::from_utf8_lossy(&shell.stdout).trim().to_string();
    if shell_path.ends_with("/zsh") {
        assert_eq!(
            default_user_shell(),
            Shell {
                shell_type: ShellType::Zsh,
                shell_path: PathBuf::from(shell_path),
                shell_snapshot: empty_shell_snapshot_receiver(),
            }
        );
    }
}
```

验证 `default_user_shell` 能正确检测当前用户的默认 Shell（通过 `$SHELL` 环境变量）。

#### 8. Windows PowerShell 测试
```rust
#[tokio::test]
async fn detects_powershell_as_default() {
    if !cfg!(windows) {
        return;
    }
    
    let powershell_shell = default_user_shell();
    let shell_path = powershell_shell.shell_path;
    
    assert!(shell_path.ends_with("pwsh.exe") || shell_path.ends_with("powershell.exe"));
}

#[test]
fn finds_powershell() {
    if !cfg!(windows) {
        return;
    }
    
    let powershell_shell = get_shell(ShellType::PowerShell, None).unwrap();
    let shell_path = powershell_shell.shell_path;
    
    assert!(shell_path.ends_with("pwsh.exe") || shell_path.ends_with("powershell.exe"));
}
```

验证 Windows 平台上 PowerShell 的检测：
- 支持 `pwsh`（PowerShell Core）和 `powershell`（Windows PowerShell）
- 默认 Shell 为 PowerShell

## 关键代码路径与文件引用

### 测试依赖图

```
shell_tests.rs
├── shell.rs (被测试模块)
│   ├── get_shell()
│   ├── default_user_shell()
│   ├── default_user_shell_from_path()
│   ├── derive_exec_args()
│   ├── ultimate_fallback_shell()
│   └── empty_shell_snapshot_receiver()
├── shell_detect.rs
│   └── detect_shell_type()
└── std::process::Command
    └── output()
```

### 测试组织结构

```rust
#[cfg(test)]
#[cfg(unix)]
#[path = "shell_tests.rs"]
mod tests;
```

测试作为 `shell.rs` 的子模块，仅在 Unix 平台编译。

**注意：** 虽然测试模块标记为 `#[cfg(unix)]`，但内部测试用例也使用了 `#[cfg(target_os = "macos")]` 和 `#[cfg(windows)]` 进行更细粒度的平台控制。

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `std::process::Command` | 执行 Shell 命令验证 |
| `tokio` | 异步测试运行时 |

### 系统依赖

| 组件 | 用途 |
|------|------|
| `/bin/zsh` | Zsh 检测和执行测试（macOS） |
| `/bin/bash` | Bash 检测和执行测试 |
| `/bin/sh` | Sh 检测和执行测试 |
| `pwsh.exe` / `powershell.exe` | PowerShell 测试（Windows） |
| `cmd.exe` | Cmd 测试（Windows） |

## 风险、边界与改进建议

### 已知风险

1. **平台条件编译复杂**
   - 模块级别 `#[cfg(unix)]`
   - 测试级别 `#[cfg(target_os = "macos")]` 和 `#[cfg(windows)]`
   - 代码级别 `if cfg!(windows)`
   - 可能导致某些平台测试被意外跳过

2. **系统依赖**
   - 测试依赖特定路径的 Shell（`/bin/zsh` 等）
   - 在不同发行版或配置上可能失败

3. **环境敏感**
   - `test_current_shell_detects_zsh` 依赖 `$SHELL` 环境变量
   - 在 CI 环境可能不准确

### 边界情况

1. **可选测试**
   ```rust
   assert!(shell_works(get_shell(ShellType::Zsh, None), cmd, false));
   ```
   Zsh 测试标记为 `false`（非必需），允许 Zsh 未安装时跳过。

2. **路径灵活性**
   ```rust
   assert!(
       shell_path.file_name().and_then(|name| name.to_str()) == Some("bash"),
       "shell path: {shell_path:?}",
   );
   ```
   仅验证文件名而非完整路径，适应不同系统布局。

3. **PowerShell 变体**
   ```rust
   assert!(shell_path.ends_with("pwsh.exe") || shell_path.ends_with("powershell.exe"));
   ```
   接受两种 PowerShell 可执行文件。

### 改进建议

1. **测试稳定性**
   - 使用 `which` 或 `command -v` 动态查找 Shell 路径
   - 添加 Shell 存在性检查，不存在时跳过而非失败

2. **覆盖率提升**
   - 添加 `get_shell_by_model_provided_path` 测试
   - 添加显式路径优先级测试（提供路径 vs 自动发现）
   - 添加 `get_user_shell_path` 的直接测试

3. **平台一致性**
   - 统一使用 `#[cfg]` 属性或 `cfg!` 宏，避免混合
   - 考虑使用 `target_family` 替代特定 OS

4. **错误消息**
   - 添加更多上下文到断言消息
   - 失败时输出系统 Shell 配置信息

5. **模拟测试**
   - 使用模拟文件系统测试路径解析逻辑
   - 减少对真实系统 Shell 的依赖

### 测试最佳实践

1. **条件编译清晰**
   ```rust
   #[test]
   #[cfg(target_os = "macos")]
   fn macos_specific_test() { ... }
   ```

2. **运行时平台检查**
   ```rust
   if !cfg!(windows) {
       return;
   }
   ```

3. **辅助函数复用**
   ```rust
   fn shell_works(shell: Option<Shell>, command: &str, required: bool) -> bool { ... }
   ```
   统一的测试逻辑，支持必需和可选测试。
