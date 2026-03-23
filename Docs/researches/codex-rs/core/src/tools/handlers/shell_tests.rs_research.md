# shell_tests.rs 研究文档

## 场景与职责

`shell_tests.rs` 是 `shell.rs` 的配套测试模块，负责验证 Shell 命令处理器的核心功能。该测试文件确保 ShellCommandHandler 生成的命令能够被安全命令检测系统正确识别，并验证登录 shell 配置、参数解析等关键行为。

## 功能点目的

### 1. 安全命令识别验证
测试 `ShellCommandHandler` 生成的命令是否能被 `is_known_safe_command()` 正确识别为安全命令。这是安全沙箱系统的关键防线，确保只有已知安全的命令才能绕过审批流程。

### 2. 登录 Shell 配置测试
验证显式登录标志的处理逻辑，包括：
- 允许登录 shell 时的行为
- 禁止登录 shell 时的错误处理
- 默认配置的回退行为

### 3. 执行参数生成验证
测试 `to_exec_params` 方法正确构建执行参数，包括命令解析、工作目录解析、环境变量设置、超时配置等。

## 具体技术实现

### 关键测试用例

#### `commands_generated_by_shell_command_handler_can_be_matched_by_is_known_safe_command`
```rust
// 测试逻辑：为不同 shell 类型生成命令，验证安全检测
let bash_shell = Shell { shell_type: ShellType::Bash, ... };
assert_safe(&bash_shell, "ls -la");

let zsh_shell = Shell { shell_type: ShellType::Zsh, ... };
assert_safe(&zsh_shell, "ls -la");

// PowerShell 条件测试（仅在可用时执行）
if let Some(path) = try_find_powershell_executable_blocking() {
    assert_safe(&powershell, "ls -Name");
}
```

**技术要点**：
- 使用 `Shell::derive_exec_args(command, use_login_shell)` 生成执行参数
- 验证 `is_known_safe_command()` 对生成参数的识别能力
- 同时测试登录 shell (`-lc`) 和非登录 shell (`-c`) 模式

#### `shell_command_handler_to_exec_params_uses_session_shell_and_turn_context`
```rust
// 构建测试参数
let params = ShellCommandToolCallParams {
    command: "echo hello".to_string(),
    workdir: Some("subdir".to_string()),
    login: None,
    timeout_ms: Some(1234),
    sandbox_permissions: Some(SandboxPermissions::RequireEscalated),
    justification: Some("because tests".to_string()),
    ...
};

// 验证生成的 ExecParams
let exec_params = ShellCommandHandler::to_exec_params(...);
assert_eq!(exec_params.command, expected_command);
assert_eq!(exec_params.cwd, expected_cwd);
assert_eq!(exec_params.env, expected_env);
```

**验证点**：
- 命令使用 session 的 user_shell 生成
- 工作目录通过 turn_context.resolve_path 解析
- 环境变量通过 create_env 创建
- 网络配置继承自 turn_context.network
- 沙箱权限和理由正确传递

#### `shell_command_handler_respects_explicit_login_flag`
```rust
// 测试显式登录标志
let login_command = ShellCommandHandler::base_command(&shell, "echo login shell", true);
assert_eq!(login_command, shell.derive_exec_args("echo login shell", true));

let non_login_command = ShellCommandHandler::base_command(&shell, "echo non login shell", false);
assert_eq!(non_login_command, shell.derive_exec_args("echo non login shell", false));
```

#### `shell_command_handler_rejects_login_when_disallowed`
```rust
let err = ShellCommandHandler::resolve_use_login_shell(Some(true), false)
    .expect_err("explicit login should be rejected");
// 验证错误消息包含 "login shell is disabled by config"
```

## 关键代码路径与文件引用

### 被测试的主要代码
- `codex-rs/core/src/tools/handlers/shell.rs` - ShellHandler 和 ShellCommandHandler 实现
- `codex-rs/core/src/shell.rs` - Shell 结构体和 derive_exec_args 方法
- `codex-rs/core/src/is_safe_command.rs` (通过 lib.rs 导出) - 安全命令检测

### 测试依赖
```rust
use crate::codex::make_session_and_context;  // 测试辅助函数
use crate::exec_env::create_env;             // 环境变量创建
use crate::is_safe_command::is_known_safe_command;  // 安全检测
use crate::powershell::try_find_powershell_executable_blocking;  // PowerShell 检测
use crate::sandboxing::SandboxPermissions;   // 沙箱权限类型
use crate::shell::Shell;                     // Shell 结构体
use crate::tools::handlers::ShellCommandHandler;  // 被测处理器
```

### 相关协议类型
- `codex_protocol::models::ShellCommandToolCallParams` - shell_command 工具参数

## 依赖与外部交互

### 外部系统依赖
1. **PowerShell 可执行文件** - 测试尝试检测系统上的 PowerShell/PowerShell Core
2. **Shell 环境** - 测试依赖 `/bin/bash`、`/bin/zsh` 等标准 shell 路径

### 内部模块交互
```
shell_tests.rs
    ├── shell.rs (被测代码)
    ├── shell.rs::ShellCommandHandler
    │   ├── to_exec_params() -> ExecParams
    │   ├── base_command() -> Vec<String>
│   └── resolve_use_login_shell() -> Result<bool>
├── shell.rs::Shell
│   └── derive_exec_args() -> Vec<String>
├── is_safe_command.rs
│   └── is_known_safe_command() -> bool
└── codex.rs::make_session_and_context() (测试辅助)
```

## 风险、边界与改进建议

### 潜在风险

1. **环境依赖性**
   - 测试假设 `/bin/bash` 和 `/bin/zsh` 存在
   - PowerShell 测试是条件执行的，可能跳过关键路径
   - 在 Windows 上行为可能不同

2. **测试覆盖盲区**
   - 未测试 Cmd shell 类型
   - 未测试复杂的命令注入场景
   - 未测试工作目录解析的错误边界

3. **并发安全**
   - `shell_snapshot` 使用 `watch::channel`，测试中创建空接收器
   - 实际并发场景下的行为未充分测试

### 边界情况

1. **登录 Shell 配置边界**
   ```rust
   // 当 allow_login_shell = false 时
   login: Some(true)  -> 错误
   login: Some(false) -> 允许
   login: None        -> 默认为 false
   ```

2. **命令安全检测边界**
   - 测试仅验证简单命令 (`ls -la`)
   - 复杂的管道、重定向未覆盖
   - 环境变量展开未测试

### 改进建议

1. **增强测试覆盖**
   ```rust
   // 建议添加：
   - 测试 Cmd shell 类型
   - 测试包含特殊字符的命令
   - 测试超长命令和参数
   - 测试工作目录不存在的情况
   ```

2. **减少环境依赖**
   ```rust
   // 使用 mock 或 stub 替代实际 shell 检测
   // 或者使用 cfg 条件编译分离平台特定测试
   ```

3. **安全场景扩展**
   ```rust
   // 添加危险命令检测测试
   #[test]
   fn shell_command_handler_detects_dangerous_commands() {
       // 验证危险命令被正确识别为不安全
   }
   ```

4. **性能测试**
   - 添加基准测试验证命令生成性能
   - 测试大量并发命令处理

### 维护注意事项

1. 当修改 `Shell::derive_exec_args` 时，必须同步更新此测试
2. 添加新的 shell 类型支持时，需要在此添加对应测试
3. 安全命令检测规则变更时，需要验证测试是否仍然有效
