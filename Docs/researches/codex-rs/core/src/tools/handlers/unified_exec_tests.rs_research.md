# unified_exec_tests.rs 研究文档

## 场景与职责

`unified_exec_tests.rs` 是 `unified_exec.rs` 的配套测试模块，负责验证统一执行工具处理器的核心功能。测试覆盖命令构建、shell 选择、登录 shell 配置、ZshFork 模式以及相对路径权限解析等关键场景，确保命令执行在各种配置下的正确性。

## 功能点目的

### 1. 命令构建验证
验证 `get_command` 函数根据不同输入参数正确构建命令行，包括默认 shell 使用、显式 shell 指定、登录 shell 标志处理等。

### 2. Shell 类型支持
测试对各种 shell 类型的支持：
- 默认用户 shell
- 显式指定的 Bash
- PowerShell（Windows）
- Cmd（Windows）

### 3. 特殊模式测试
验证 ZshFork 模式的命令构建逻辑，该模式用于特定的 Unix 沙箱场景。

### 4. 权限路径解析
测试相对路径在 `additional_permissions` 中的正确解析，确保相对于工作目录的路径被正确转换为绝对路径。

## 具体技术实现

### 核心测试用例

#### `test_get_command_uses_default_shell_when_unspecified`

验证未指定 shell 时使用默认 shell：

```rust
#[test]
fn test_get_command_uses_default_shell_when_unspecified() -> anyhow::Result<()> {
    let json = r#"{"cmd": "echo hello"}"#;
    let args: ExecCommandArgs = parse_arguments(json)?;

    // 验证 shell 字段为 None
    assert!(args.shell.is_none());

    // 使用默认 shell 构建命令
    let command = get_command(
        &args,
        Arc::new(default_user_shell()),
        &UnifiedExecShellMode::Direct,
        true,  // allow_login_shell
    )?;

    // 验证命令结构：["/bin/zsh", "-lc", "echo hello"] 或类似
    assert_eq!(command.len(), 3);
    assert_eq!(command[2], "echo hello");
    Ok(())
}
```

#### `test_get_command_respects_explicit_bash_shell`

验证显式指定 Bash shell：

```rust
#[test]
fn test_get_command_respects_explicit_bash_shell() -> anyhow::Result<()> {
    let json = r#"{"cmd": "echo hello", "shell": "/bin/bash"}"#;
    let args: ExecCommandArgs = parse_arguments(json)?;

    assert_eq!(args.shell.as_deref(), Some("/bin/bash"));

    let command = get_command(&args, Arc::new(default_user_shell()), &UnifiedExecShellMode::Direct, true)?;

    assert_eq!(command.last(), Some(&"echo hello".to_string()));
    // PowerShell 特殊检查
    if command.iter().any(|arg| arg.eq_ignore_ascii_case("-Command")) {
        assert!(command.contains(&"-NoProfile".to_string()));
    }
    Ok(())
}
```

#### `test_get_command_respects_explicit_powershell_shell`

验证 PowerShell shell 指定：

```rust
#[test]
fn test_get_command_respects_explicit_powershell_shell() -> anyhow::Result<()> {
    let json = r#"{"cmd": "echo hello", "shell": "powershell"}"#;
    let args: ExecCommandArgs = parse_arguments(json)?;

    assert_eq!(args.shell.as_deref(), Some("powershell"));

    let command = get_command(&args, Arc::new(default_user_shell()), &UnifiedExecShellMode::Direct, true)?;

    assert_eq!(command[2], "echo hello");
    Ok(())
}
```

#### `test_get_command_rejects_explicit_login_when_disallowed`

验证登录 shell 配置限制：

```rust
#[test]
fn test_get_command_rejects_explicit_login_when_disallowed() -> anyhow::Result<()> {
    let json = r#"{"cmd": "echo hello", "login": true}"#;
    let args: ExecCommandArgs = parse_arguments(json)?;

    // allow_login_shell = false
    let err = get_command(&args, Arc::new(default_user_shell()), &UnifiedExecShellMode::Direct, false)
        .expect_err("explicit login should be rejected");

    assert!(err.contains("login shell is disabled by config"));
    Ok(())
}
```

#### `test_get_command_ignores_explicit_shell_in_zsh_fork_mode`

验证 ZshFork 模式忽略显式 shell：

```rust
#[test]
fn test_get_command_ignores_explicit_shell_in_zsh_fork_mode() -> anyhow::Result<()> {
    let json = r#"{"cmd": "echo hello", "shell": "/bin/bash"}"#;  // 显式指定 bash
    let args: ExecCommandArgs = parse_arguments(json)?;

    // 构建 ZshFork 配置
    let shell_zsh_path = AbsolutePathBuf::from_absolute_path(if cfg!(windows) {
        r"C:\opt\codex\zsh"
    } else {
        "/opt/codex/zsh"
    })?;
    let shell_mode = UnifiedExecShellMode::ZshFork(ZshForkConfig {
        shell_zsh_path: shell_zsh_path.clone(),
        main_execve_wrapper_exe: AbsolutePathBuf::from_absolute_path(...)?,
    });

    let command = get_command(&args, Arc::new(default_user_shell()), &shell_mode, true)?;

    // 验证使用 ZshFork 配置，忽略 shell: "/bin/bash"
    assert_eq!(command, vec![
        shell_zsh_path.to_string_lossy().to_string(),
        "-lc".to_string(),  // 登录 shell
        "echo hello".to_string()
    ]);
    Ok(())
}
```

#### `exec_command_args_resolve_relative_additional_permissions_against_workdir`

验证相对权限路径解析：

```rust
#[test]
fn exec_command_args_resolve_relative_additional_permissions_against_workdir() -> anyhow::Result<()> {
    let cwd = tempdir()?;
    let workdir = cwd.path().join("nested");
    fs::create_dir_all(&workdir)?;
    let expected_write = workdir.join("relative-write.txt");

    let json = r#"{
        "cmd": "echo hello",
        "workdir": "nested",
        "additional_permissions": {
            "file_system": {
                "write": ["./relative-write.txt"]
            }
        }
    }"#;

    // 解析基础路径（考虑 workdir）
    let base_path = resolve_workdir_base_path(json, cwd.path())?;
    let args: ExecCommandArgs = parse_arguments_with_base_path(json, base_path.as_path())?;

    // 验证相对路径被解析为绝对路径
    assert_eq!(
        args.additional_permissions,
        Some(PermissionProfile {
            file_system: Some(FileSystemPermissions {
                read: None,
                write: Some(vec![AbsolutePathBuf::try_from(expected_write)?]),
            }),
            ..Default::default()
        })
    );
    Ok(())
}
```

## 关键代码路径与文件引用

### 被测试代码
- `codex-rs/core/src/tools/handlers/unified_exec.rs`
  - `get_command()` 函数
  - `ExecCommandArgs` 结构

### 依赖类型
```rust
use super::*;  // 导入 unified_exec.rs 的所有内容
use crate::shell::default_user_shell;
use crate::tools::handlers::{parse_arguments_with_base_path, resolve_workdir_base_path};
use crate::tools::spec::ZshForkConfig;
use codex_protocol::models::{FileSystemPermissions, PermissionProfile};
use codex_utils_absolute_path::AbsolutePathBuf;
use pretty_assertions::assert_eq;
use std::fs;
use std::sync::Arc;
use tempfile::tempdir;
```

### 相关文件
- `codex-rs/core/src/shell.rs` - `default_user_shell()` 和 `Shell` 类型
- `codex-rs/core/src/tools/spec.rs` - `UnifiedExecShellMode` 和 `ZshForkConfig`
- `codex-rs/core/src/tools/handlers/mod.rs` - `parse_arguments_with_base_path` 和 `resolve_workdir_base_path`

## 依赖与外部交互

### 测试数据流
```
测试用例
    │
    ├──> test_get_command_uses_default_shell_when_unspecified
    │       ├── JSON: {"cmd": "echo hello"}
    │       ├── parse_arguments() -> ExecCommandArgs
    │       ├── get_command() with UnifiedExecShellMode::Direct
    │       └── 验证命令结构 [shell, flag, cmd]
    │
    ├──> test_get_command_respects_explicit_*_shell
    │       ├── JSON: {"cmd": "...", "shell": "..."}
    │       ├── get_command()
    │       └── 验证 shell 参数被使用
    │
    ├──> test_get_command_rejects_explicit_login_when_disallowed
    │       ├── JSON: {"cmd": "...", "login": true}
    │       ├── get_command() with allow_login_shell=false
    │       └── 验证错误消息
    │
    ├──> test_get_command_ignores_explicit_shell_in_zsh_fork_mode
    │       ├── JSON: {"cmd": "...", "shell": "/bin/bash"}
    │       ├── UnifiedExecShellMode::ZshFork(config)
    │       ├── get_command()
    │       └── 验证使用 zsh 路径，忽略 shell 参数
    │
    └──> exec_command_args_resolve_relative_additional_permissions_against_workdir
            ├── 创建临时目录结构
            ├── JSON with workdir and relative path
            ├── resolve_workdir_base_path()
            ├── parse_arguments_with_base_path()
            └── 验证绝对路径解析
```

### 平台差异处理
```rust
// ZshFork 路径根据平台变化
let shell_zsh_path = AbsolutePathBuf::from_absolute_path(if cfg!(windows) {
    r"C:\opt\codex\zsh"
} else {
    "/opt/codex/zsh"
})?;
```

## 风险、边界与改进建议

### 潜在风险

1. **环境依赖性**
   ```rust
   Arc::new(default_user_shell())
   ```
   - 测试依赖系统默认 shell
   - 不同环境可能导致测试行为不一致

2. **平台特定代码覆盖不足**
   ```rust
   #[cfg(windows)]
   // Windows 特定测试有限
   ```
   - PowerShell/Cmd 测试仅在 Windows 有效
   - 跨平台一致性未充分验证

3. **硬编码路径**
   ```rust
   r"C:\opt\codex\zsh"
   "/opt/codex/zsh"
   ```
   - 测试使用假设路径
   - 实际部署路径可能不同

4. **权限测试不完整**
   - 仅测试文件系统写权限
   - 网络权限、macOS 权限未测试

### 边界情况

1. **空命令**
   ```rust
   // 未测试 cmd: "" 的情况
   ```

2. **特殊字符**
   ```rust
   // 未测试包含引号、转义字符的命令
   {"cmd": "echo \"hello world\""}
   ```

3. **超长命令**
   - 未测试命令长度限制

4. **工作目录不存在**
   ```rust
   "workdir": "nonexistent"
   // 行为未定义
   ```

5. **权限路径遍历**
   ```rust
   "write": ["../../../etc/passwd"]
   // 未测试路径遍历防护
   ```

### 改进建议

1. **Mock Shell 环境**
   ```rust
   // 使用 mock 替代实际 shell
   struct MockShell {
       expected_cmd: String,
   }
   
   impl Shell for MockShell {
       fn derive_exec_args(&self, cmd: &str, _login: bool) -> Vec<String> {
           vec!["mock".to_string(), "-c".to_string(), cmd.to_string()]
       }
   }
   ```

2. **参数化测试**
   ```rust
   #[rstest]
   #[case("bash", ShellType::Bash)]
   #[case("zsh", ShellType::Zsh)]
   #[case("powershell", ShellType::PowerShell)]
   fn test_shell_types(#[case] shell_name: &str, #[case] expected: ShellType) {
       // 测试各种 shell 类型
   }
   ```

3. **错误场景测试**
   ```rust
   #[test]
   fn test_invalid_shell_path() {
       let json = r#"{"cmd": "echo hello", "shell": "/nonexistent/shell"}"#;
       // 验证错误处理
   }
   ```

4. **并发安全测试**
   ```rust
   #[tokio::test]
   async fn test_concurrent_command_execution() {
       // 验证并发执行的正确性
   }
   ```

5. **权限边界测试**
   ```rust
   #[test]
   fn test_permission_path_traversal_protection() {
       let json = r#"{
           "cmd": "echo hello",
           "additional_permissions": {
               "file_system": {
                   "write": ["../../../etc/passwd"]
               }
           }
       }"#;
       // 验证路径被规范化或拒绝
   }
   ```

6. **使用快照测试**
   ```rust
   #[test]
   fn test_command_structure_matches_snapshot() {
       let command = get_command(...).unwrap();
       insta::assert_debug_snapshot!(command);
   }
   ```

### 测试覆盖缺口

当前未覆盖的场景：
1. `write_stdin` 参数解析
2. `max_output_tokens` 处理
3. `justification` 字段传递
4. `prefix_rule` 处理
5. 超时处理
6. 网络权限配置

建议添加：
```rust
#[test]
fn test_write_stdin_args_parsing() { ... }

#[test]
fn test_max_output_tokens_propagation() { ... }

#[test]
fn test_network_permissions_in_additional_permissions() { ... }
```

### 维护注意事项

1. 当 `ExecCommandArgs` 结构变更时，需要同步更新测试
2. `UnifiedExecShellMode` 新增模式时需要添加对应测试
3. 权限模型变更时需要更新权限解析测试
4. 考虑使用 `insta` 快照测试简化复杂结构的验证
