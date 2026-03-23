# shell_command.rs 研究文档

## 场景与职责

`shell_command.rs` 是 Codex Core 的测试文件，专注于验证 **`shell_command` 工具的执行功能**。`shell_command` 是 Codex 的核心工具之一，允许 AI 模型执行用户 shell 命令。本测试确保：

- 基本命令执行和输出捕获
- 登录 shell（`--login`）选项支持
- 超时机制
- Unicode 和多行输出处理
- 跨平台兼容性（Windows/Unix）

## 功能点目的

### 1. 基本命令执行 (`shell_command_works`)
验证简单的 `echo` 命令执行：
- 命令：`echo 'hello, world'`
- 验证退出码 0
- 验证输出内容匹配

### 2. 登录 Shell 选项 (`output_with_login`, `output_without_login`)
验证 `login` 参数控制是否使用登录 shell：
- `login: true`：使用登录 shell（加载 `.bash_profile` 等）
- `login: false`：使用非登录 shell
- `login: null`：使用默认配置

### 3. 多行输出 (`multi_line_output_with_login`)
验证多行命令输出正确处理：
- 命令：`echo 'first line\nsecond line'`
- 验证换行符正确传递

### 4. 管道输出 (`pipe_output_with_login`, `pipe_output_without_login`)
验证管道命令执行：
- 命令：`echo 'hello, world' | cat`
- 跳过 Windows（管道语法差异）

### 5. 超时机制 (`shell_command_times_out_with_timeout_ms`)
验证命令超时处理：
- 命令：`sleep 5`（Unix）或 `timeout /t 5`（Windows）
- 超时：200ms
- 验证退出码 124（Unix）或相应的超时退出码
- 验证输出包含 "command timed out"

### 6. Unicode 支持 (`unicode_output`, `unicode_output_with_newlines`)
验证 Unicode 字符正确处理：
- 测试字符串：`naïve_café`
- 启用 `Feature::PowershellUtf8` 功能
- 验证 UTF-8 编码正确

## 具体技术实现

### 关键数据结构

```rust
// ShellCommandToolCallParams（来自 codex_protocol）
pub struct ShellCommandToolCallParams {
    pub command: String,           // 要执行的命令
    pub timeout_ms: i64,           // 超时时间（毫秒）
    pub login: Option<bool>,       // 是否使用登录 shell
    pub workdir: Option<PathBuf>,  // 工作目录
    pub sandbox_permissions: Option<SandboxPermissions>,
    pub justification: Option<String>,
}

// ExecParams（内部使用）
pub struct ExecParams {
    pub command: Vec<String>,      // 解析后的命令参数
    pub cwd: PathBuf,              // 工作目录
    pub expiration: Expiration,    // 超时配置
    pub env: HashMap<String, String>, // 环境变量
    pub network: Option<NetworkProxy>, // 网络代理
    pub sandbox_permissions: SandboxPermissions,
    // ... 其他字段
}
```

### 命令执行流程

```
模型调用 shell_command
  └─ ShellCommandHandler::handle()
       ├─ 解析参数 (ShellCommandToolCallParams)
       ├─ 解析登录 shell 选项
       │    └─ resolve_use_login_shell()
       ├─ 构建命令
       │    └─ base_command() // 使用用户 shell 解析命令
       ├─ 创建 ExecParams
       ├─ 拦截 apply_patch（如果命令包含）
       ├─ 创建 ToolOrchestrator
       └─ 执行
            └─ ShellRuntime::execute()
                 ├─ 启动进程（可能经过沙盒）
                 ├─ 捕获输出
                 └─ 等待完成或超时
```

### 登录 Shell 解析

```rust
fn resolve_use_login_shell(
    login: Option<bool>,
    allow_login_shell: bool,
) -> Result<bool, FunctionCallError> {
    if !allow_login_shell && login == Some(true) {
        return Err(FunctionCallError::RespondToModel(
            "login shell is disabled by config; omit `login` or set it to false.".to_string(),
        ));
    }
    Ok(login.unwrap_or(allow_login_shell))
}
```

### 输出验证

```rust
fn assert_shell_command_output(output: &str, expected: &str) -> Result<()> {
    let normalized_output = output
        .replace("\r\n", "\n")  // Windows 换行符标准化
        .replace('\r', "\n")
        .trim_end_matches('\n')
        .to_string();

    let expected_pattern = format!(
        r"(?s)^Exit code: 0\nWall time: [0-9]+(?:\.[0-9]+)? seconds\nOutput:\n{}\n?$",
        expected
    );

    assert_regex_match(&expected_pattern, &normalized_output);
    Ok(())
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::tools::handlers::shell::ShellCommandHandler` | 工具处理器 |
| `codex_core::tools::runtimes::shell::ShellRuntime` | Shell 运行时 |
| `codex_core::exec::ExecParams` | 执行参数 |
| `codex_core::shell::Shell` | 用户 shell 抽象 |

### 外部依赖

| 组件 | 用途 |
|------|------|
| 系统 shell（bash/zsh） | 命令执行 |
| `echo`, `cat`, `sleep` | 测试命令 |

### 测试基础设施

```rust
// 测试辅助函数
fn shell_responses(call_id: &str, command: &str, login: Option<bool>) -> Vec<String>

async fn shell_command_harness_with(
    configure: impl FnOnce(TestCodexBuilder) -> TestCodexBuilder,
) -> Result<TestCodexHarness>

async fn mount_shell_responses(
    harness: &TestCodexHarness,
    call_id: &str,
    command: &str,
    login: Option<bool>,
)
```

## 风险、边界与改进建议

### 当前风险

1. **平台差异**：Windows 和 Unix 的 shell 语法、命令可用性不同
2. **环境依赖**：测试依赖系统命令（`echo`, `sleep`）的存在
3. **时序敏感**：超时测试可能因系统负载产生 flaky 结果

### 边界情况

1. **命令注入**：未测试恶意命令的防护
2. **大输出**：未测试大量输出（>1MB）的处理
3. **特殊字符**：未测试包含控制字符的命令
4. **环境变量**：未测试包含特殊字符的环境变量值

### 改进建议

1. **测试扩展**：
   - 添加对复杂 shell 语法的测试（子 shell、命令替换）
   - 测试环境变量传递和隔离
   - 测试工作目录切换
   - 添加对信号处理（SIGINT, SIGTERM）的测试

2. **性能优化**：
   - 使用 Mock shell 替代真实 shell，加速测试
   - 并行执行独立的命令测试

3. **安全增强**：
   - 测试命令注入防护
   - 测试敏感信息（如密码）在输出中的过滤
   - 测试对危险命令（`rm -rf /`）的拦截

4. **可观测性**：
   - 记录命令执行时间和资源使用
   - 监控超时频率和原因

5. **跨平台统一**：
   - 使用 Rust 实现的跨平台 shell 替代系统 shell
   - 统一 Windows 和 Unix 的测试用例

### 相关文件引用

- `codex-rs/core/src/tools/handlers/shell.rs` - Shell 工具处理器
- `codex-rs/core/src/tools/handlers/shell_tests.rs` - 单元测试
- `codex-rs/core/src/tools/runtimes/shell.rs` - Shell 运行时
- `codex-rs/core/src/exec.rs` - 执行引擎
- `codex-rs/core/src/shell.rs` - 用户 shell 管理
