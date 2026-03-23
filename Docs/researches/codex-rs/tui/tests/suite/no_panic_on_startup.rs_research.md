# no_panic_on_startup.rs 研究文档

## 场景与职责

`codex-rs/tui/tests/suite/no_panic_on_startup.rs` 是一个回归测试，针对 GitHub Issue #8803 验证 Codex CLI 在启动时遇到错误配置时的优雅降级行为。

**问题背景**: 当 `rules` 应该是一个目录但被错误地创建为文件时，旧版本代码会在启动时 panic。该测试确保当前版本能够优雅地处理此类错误，向用户显示清晰的错误信息而非崩溃。

## 功能点目的

1. **回归测试**: 防止 Issue #8803 的 panic 问题重新引入
2. **错误处理验证**: 确保配置错误导致受控退出而非 panic
3. **用户体验**: 验证错误消息的可读性和准确性

## 具体技术实现

### 测试架构

```
┌─────────────────────────────────────────────────────────────┐
│  Test: malformed_rules_should_not_panic                     │
├─────────────────────────────────────────────────────────────┤
│  1. 创建临时目录作为 CODEX_HOME                              │
│  2. 在 CODEX_HOME 下创建文件（而非目录）名为 "rules"          │
│  3. 创建最小化 config.toml 配置                              │
│  4. 通过 PTY 启动 codex CLI                                  │
│  5. 等待进程退出（预期非零退出码）                            │
│  6. 验证输出包含预期错误信息                                  │
└─────────────────────────────────────────────────────────────┘
```

### 关键代码解析

#### 1. 错误配置准备
```rust
let tmp = tempfile::tempdir()?;
let codex_home = tmp.path();

// 故意创建文件而非目录，模拟错误配置
std::fs::write(
    codex_home.join("rules"),
    "rules should be a directory not a file",
)?;
```

#### 2. 最小化配置
```rust
let config_contents = format!(
    r#"
# Pick a local provider so the CLI doesn't prompt for OpenAI auth in this test.
model_provider = "ollama"

[projects]
"{cwd}" = {{ trust_level = "trusted" }}
"#,
    cwd = cwd.display()
);
```

使用 `ollama` 作为模型提供方，避免测试需要 OpenAI API 认证。

#### 3. PTY 进程启动与监控
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

#### 4. 终端交互处理
```rust
let exit_code_result = timeout(Duration::from_secs(10), async {
    loop {
        select! {
            result = output_rx.recv() => match result {
                Ok(chunk) => {
                    // 响应光标位置查询，避免 TUI 阻塞
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

#### 5. 断言验证
```rust
let CodexCliOutput { exit_code, output } = run_codex_cli(codex_home, cwd).await?;

// 验证非零退出码
assert_ne!(0, exit_code, "Codex CLI should exit nonzero.");

// 验证错误消息内容
assert!(
    output.contains("ERROR: Failed to initialize codex:"),
    "expected startup error in output, got: {output}"
);
assert!(
    output.contains("failed to read rules files"),
    "expected rules read error in output, got: {output}"
);
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件 | 相关功能 |
|------|----------|
| `codex-rs/core/src/config_loader.rs` | 配置加载和 rules 目录读取 |
| `codex-rs/core/src/exec_policy.rs` | rules 文件解析逻辑 |
| `codex-rs/tui/src/lib.rs` | TUI 启动错误处理 |

### 依赖工具库
| 库 | 用途 |
|----|------|
| `codex_utils_cargo_bin` | 定位 codex 二进制文件 |
| `codex_utils_pty` | PTY 进程管理 |
| `tempfile` | 临时目录创建 |
| `tokio::time::timeout` | 测试超时控制 |

### 数据结构
```rust
struct CodexCliOutput {
    exit_code: i32,
    output: String,
}
```

## 依赖与外部交互

### 环境变量
| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指向临时测试目录 |

### 测试标记
```rust
#[tokio::test]
#[ignore = "TODO(mbolin): flaky"]  // 当前被标记为不稳定
async fn malformed_rules_should_not_panic() -> anyhow::Result<()> {
```

### 平台限制
```rust
// run_codex_cli() does not work on Windows due to PTY limitations.
if cfg!(windows) {
    return Ok(());
}
```

### 已知问题
- 测试被标记为 `#[ignore]`，原因是存在 flaky 行为
- 注释提到使用临时目录作为 cwd 会导致测试挂起

## 风险、边界与改进建议

### 风险
1. **被忽略**: 测试当前被 `#[ignore]` 标记，不会自动运行
2. **Flaky 行为**: 存在时序相关的稳定性问题
3. **PTY 依赖**: 测试复杂度较高，依赖外部 PTY 库

### 边界条件
- 仅测试 `rules` 文件（而非目录）这一种错误配置
- 使用 `ollama` 提供方避免网络依赖
- 10 秒超时可能不足以覆盖慢速环境

### 改进建议
1. **去忽略化**: 修复 flaky 问题后移除 `#[ignore]` 标记
2. **根因修复**: 调查临时目录作为 cwd 导致挂起的原因
3. **扩展覆盖**: 添加其他配置错误的测试（如无效 TOML、权限问题等）
4. **日志增强**: 失败时捕获并输出更多诊断信息
5. **单元测试补充**: 考虑在配置加载层添加单元测试减少端到端测试依赖
