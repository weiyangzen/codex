# no_panic_on_startup.rs 研究文档

## 场景与职责

该文件包含针对 Codex TUI 启动时配置错误处理的回归测试。具体测试场景是当 `rules` 配置项应该是一个目录，但实际为一个普通文件时，应用应该优雅地报告错误而不是 panic。

### 业务背景

- Codex 使用 `rules` 目录存储项目特定的执行策略和规则文件
- 用户可能误将 `rules` 创建为普通文件（例如直接写入了规则内容而不是创建目录）
- **原始问题**: GitHub Issue #8803 报告在此场景下应用会 panic
- **修复目标**: 应用应该检测到此配置错误并输出清晰的错误信息，然后以非零状态退出

## 功能点目的

### 核心测试: `malformed_rules_should_not_panic`

验证以下场景的错误处理：

1. 用户在 `CODEX_HOME` 中创建名为 `rules` 的文件（而非目录）
2. 启动 Codex TUI
3. **断言**: 
   - 应用不应该 panic
   - 应该以非零退出码退出
   - 错误输出应该包含 `"ERROR: Failed to initialize codex:"`
   - 错误输出应该包含 `"failed to read rules files"`

### 测试覆盖点

- 配置加载阶段的错误检测
- 文件系统类型检查（文件 vs 目录）
- 错误消息的友好性和准确性
- 进程退出状态码的正确性

## 具体技术实现

### 测试数据准备

```rust
// 1. 创建临时目录作为 CODEX_HOME
let tmp = tempfile::tempdir()?;
let codex_home = tmp.path();

// 2. 创建错误的 rules 配置（文件而非目录）
std::fs::write(
    codex_home.join("rules"),
    "rules should be a directory not a file",
)?;
```

### 配置文件生成

```rust
let cwd = std::env::current_dir()?;
let config_contents = format!(
    r#"
# Pick a local provider so the CLI doesn't prompt for OpenAI auth in this test.
model_provider = "ollama"

[projects]
"{cwd}" = {{ trust_level = "trusted" }}
"#,
    cwd = cwd.display()
);
std::fs::write(codex_home.join("config.toml"), config_contents)?;
```

**设计决策**: 使用 `ollama` 作为模型提供者，避免在测试期间弹出 OpenAI 认证提示。

### 辅助函数: `run_codex_cli`

```rust
async fn run_codex_cli(
    codex_home: impl AsRef<Path>,
    cwd: impl AsRef<Path>,
) -> anyhow::Result<CodexCliOutput> {
    let codex_cli = codex_utils_cargo_bin::cargo_bin("codex")?;
    let mut env = HashMap::new();
    env.insert("CODEX_HOME".to_string(), codex_home.as_ref().display().to_string());

    let args = vec!["-c".to_string(), "analytics.enabled=false".to_string()];
    let spawned = codex_utils_pty::spawn_pty_process(
        codex_cli.to_string_lossy().as_ref(),
        &args,
        cwd.as_ref(),
        &env,
        &None,
        codex_utils_pty::TerminalSize::default(),
    ).await?;
    // ...
}
```

### PTY 交互处理

```rust
let exit_code_result = timeout(Duration::from_secs(10), async {
    loop {
        select! {
            result = output_rx.recv() => match result {
                Ok(chunk) => {
                    // 响应光标位置查询（CPR: ESC[6n）
                    if chunk.windows(4).any(|window| window == b"\x1b[6n") {
                        let _ = writer_tx.send(b"\x1b[1;1R".to_vec()).await;
                    }
                    output.extend_from_slice(&chunk);
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break exit_rx.await,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
            },
            result = &mut exit_rx => break result,
        }
    }
}).await;
```

### 断言验证

```rust
let CodexCliOutput { exit_code, output } = run_codex_cli(codex_home, cwd).await?;

// 1. 验证非零退出码
assert_ne!(0, exit_code, "Codex CLI should exit nonzero.");

// 2. 验证错误消息包含初始化失败提示
assert!(
    output.contains("ERROR: Failed to initialize codex:"),
    "expected startup error in output, got: {output}"
);

// 3. 验证错误消息包含具体的 rules 读取错误
assert!(
    output.contains("failed to read rules files"),
    "expected rules read error in output, got: {output}"
);
```

## 关键代码路径与文件引用

### 测试文件

| 文件 | 作用 |
|------|------|
| `tests/suite/no_panic_on_startup.rs` | 本测试文件 |
| `tests/all.rs` | 测试套件入口 |

### 被测代码

| 文件 | 相关功能 |
|------|----------|
| `src/lib.rs` | TUI 应用启动入口，配置加载 |
| `codex_core::config_loader` | 配置加载和验证逻辑 |
| `codex_core::execpolicy` | 规则文件读取逻辑 |

### 依赖工具

| Crate/模块 | 用途 |
|------------|------|
| `codex_utils_pty` | PTY 进程生成和管理 |
| `codex_utils_cargo_bin` | 定位编译后的 `codex` 二进制文件 |

## 依赖与外部交互

### 外部进程交互

**codex 二进制**: 测试需要预编译的 `codex` 可执行文件
- 通过 `codex_utils_cargo_bin::cargo_bin("codex")` 定位
- 如果二进制不存在，测试会失败（不像 `model_availability_nux` 那样静默跳过）

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指向临时配置目录，包含错误的 `rules` 文件 |

### 平台限制

```rust
// run_codex_cli() does not work on Windows due to PTY limitations.
if cfg!(windows) {
    return Ok(());
}
```

Windows 平台由于 PTY 限制，测试被完全跳过。

### 忽略标记

```rust
#[tokio::test]
#[ignore = "TODO(mbolin): flaky"]
async fn malformed_rules_should_not_panic() -> anyhow::Result<()> {
```

测试当前被标记为 `#[ignore]`，原因标注为 "flaky"。这表明测试存在不稳定性问题，需要进一步调查。

## 风险、边界与改进建议

### 当前风险

1. **测试被忽略**: 由于 flaky 问题，测试当前不参与 CI 运行，可能导致回归风险
   
2. **Flaky 根因不明**: 注释仅说明 "TODO(mbolin): flaky"，但没有详细说明什么情况下会失败

3. **CWD 限制**: 注释提到使用临时目录作为 CWD 会导致测试挂起，因此使用当前目录
   ```rust
   // TODO(mbolin): Figure out why using a temp dir as the cwd causes this
   // test to hang.
   let cwd = std::env::current_dir()?;
   ```
   这可能导致测试副作用（如创建临时文件到当前目录）

4. **平台覆盖缺失**: Windows 平台完全跳过测试

### 边界情况

1. **超时处理**: 10 秒超时后调用 `session.terminate()`，但 terminate 的清理可能不完整
2. **输出竞争**: 使用 `try_recv()` 排空退出后可能剩余的输出，但可能丢失部分输出
3. **光标位置查询**: 如果 TUI 多次查询光标位置，测试都能正确响应

### 改进建议

1. **解决 Flaky 问题**: 
   - 增加详细的日志记录，捕获失败时的状态
   - 考虑增加重试机制
   - 分析超时是否为主要失败原因

2. **移除忽略标记**: 修复 flaky 问题后，移除 `#[ignore]` 让测试参与 CI

3. **调查 CWD 问题**: 
   - 研究为什么临时目录作为 CWD 会导致挂起
   - 可能需要修复产品代码或测试代码

4. **增强错误验证**: 当前仅验证错误消息字符串，可以进一步增强：
   ```rust
   // 建议：验证错误类型或错误码
   assert!(output.contains("ConfigError::RulesNotDirectory") || 
           output.contains("E002"));  // 假设有错误码
   ```

5. **增加更多边界测试**:
   - `rules` 目录存在但不可读
   - `rules` 目录存在但包含无效文件
   - `rules` 为符号链接指向文件

6. **Windows 支持**: 研究使用 pipe 模式而非 PTY 模式进行测试，绕过 Windows PTY 限制
   ```rust
   #[cfg(windows)]
   async fn run_codex_cli(...) -> ... {
       // 使用 spawn_pipe_process 替代 spawn_pty_process
   }
   ```

7. **资源清理**: 确保测试即使在失败情况下也能正确清理临时文件
   ```rust
   // 使用 scopeguard 或自定义 Drop 确保清理
   let _guard = scopeguard::guard((), |_| {
       let _ = std::fs::remove_dir_all(&tmp);
   });
   ```
