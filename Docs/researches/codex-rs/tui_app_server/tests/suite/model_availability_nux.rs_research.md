# model_availability_nux.rs 研究文档

## 场景与职责

该文件包含针对 **模型可用性 NUX（New User Experience）** 功能的集成测试。NUX 是向用户展示模型新功能或变更的提示机制，该测试验证在会话恢复（resume）场景下，NUX 计数器不会被错误地重复消耗。

### 业务背景

- `model_availability_nux` 是配置文件中用于跟踪用户已查看特定模型 NUX 提示次数的计数器
- 当用户首次使用某个模型时，系统会显示 NUX 提示并增加计数
- **关键需求**: 在 resume 会话时，不应该再次消耗 NUX 计数（即不应该重复显示已看过的提示）

## 功能点目的

### 核心测试: `resume_startup_does_not_consume_model_availability_nux_count`

验证以下用户场景：

1. 用户首次启动 Codex，看到模型可用性 NUX 提示
2. 用户执行 `codex exec` 创建会话
3. 用户执行 `codex resume --last` 恢复会话
4. **断言**: 恢复会话后，`model_availability_nux` 计数器保持为 1（不增加）

### 测试覆盖点

- NUX 配置持久化到 `config.toml`
- 模型目录（catalog）自定义配置
- PTY 环境下的 TUI 启动和交互
- 会话恢复流程的完整性

## 具体技术实现

### 测试数据准备

```rust
// 1. 创建临时 CODEX_HOME 目录
let codex_home = tempdir()?;

// 2. 加载并修改模型目录
let source_catalog_path = codex_utils_cargo_bin::find_resource!("../core/models.json")?;
let mut source_catalog: JsonValue = serde_json::from_str(&source_catalog)?;

// 3. 为第一个模型添加 availability_nux 配置
first_model_object.insert(
    "availability_nux".to_string(),
    serde_json::json!({
        "message": "Model now available",
    }),
);
```

### 配置文件生成

```toml
model = "{model_slug}"
model_provider = "openai"
model_catalog_json = "{catalog_display}"

[projects."{repo_root_display}"]
trust_level = "trusted"

[tui.model_availability_nux]
"{model_slug}" = 1  # 预置计数为 1
```

### 执行流程

1. **创建初始会话** (`codex exec`):
   ```rust
   let exec_output = std::process::Command::new(&codex)
       .arg("exec")
       .arg("--skip-git-repo-check")
       .arg("-C")
       .arg(&repo_root)
       .arg("seed session for resume")
       .env("CODEX_HOME", codex_home.path())
       .env("OPENAI_API_KEY", "dummy")
       .env("CODEX_RS_SSE_FIXTURE", fixture_path)  // 使用 mock SSE 响应
       .env("OPENAI_BASE_URL", "http://unused.local")
       .output()
   ```

2. **恢复会话** (`codex resume --last`):
   ```rust
   let spawned = codex_utils_pty::spawn_pty_process(
       codex.to_string_lossy().as_ref(),
       &args,  // ["resume", "--last", "--no-alt-screen", ...]
       &repo_root,
       &env,
       &None,
       codex_utils_pty::TerminalSize::default(),
   ).await?;
   ```

3. **PTY 交互处理**:
   ```rust
   // 响应光标位置查询（CPR: ESC[6n）
   if chunk.windows(4).any(|window| window == b"\x1b[6n") {
       let _ = writer_tx.send(b"\x1b[1;1R".to_vec()).await;
   }
   ```

4. **中断处理**:
   ```rust
   // 2秒后发送 Ctrl+C (ASCII 3) 4次，间隔 500ms
   let interrupt_task = tokio::spawn(async move {
       sleep(Duration::from_secs(2)).await;
       for _ in 0..4 {
           let _ = interrupt_writer.send(vec![3]).await;
           sleep(Duration::from_millis(500)).await;
       }
   });
   ```

5. **验证计数器**:
   ```rust
   let config: toml::Value = toml::from_str(&config_contents)?;
   let shown_count = config
       .get("tui")
       .and_then(|tui| tui.get("model_availability_nux"))
       .and_then(|nux| nux.get(&model_slug))
       .and_then(toml::Value::as_integer)
       .context("missing tui.model_availability_nux count")?;
   
   assert_eq!(shown_count, 1);  // 关键断言：计数保持为 1
   ```

## 关键代码路径与文件引用

### 测试文件

| 文件 | 作用 |
|------|------|
| `tests/suite/model_availability_nux.rs` | 本测试文件 |
| `tests/test_backend.rs` | VT100Backend 定义（本测试间接使用） |
| `tests/all.rs` | 测试套件入口 |

### 被测代码

| 文件 | 相关功能 |
|------|----------|
| `src/lib.rs` | TUI 应用启动入口 |
| `src/app.rs` | 应用状态管理，可能包含 NUX 计数逻辑 |
| `src/onboarding/` | 新用户体验相关代码 |

### 依赖工具

| Crate/模块 | 用途 |
|------------|------|
| `codex_utils_pty` | PTY 进程生成和管理 |
| `codex_utils_cargo_bin` | 定位编译后的 `codex` 二进制文件和资源文件 |
| `../core/models.json` | 模型目录模板 |
| `../core/tests/cli_responses_fixture.sse` | Mock SSE 响应数据 |

## 依赖与外部交互

### 外部进程交互

1. **codex 二进制**: 测试需要预编译的 `codex` 可执行文件
   - 优先使用 `cargo_bin("codex")` 定位
   - 回退到 `codex-rs/target/debug/codex`

2. **SSE Fixture**: 使用 mock 的 SSE 响应避免真实网络请求
   ```rust
   env("CODEX_RS_SSE_FIXTURE", fixture_path)
   ```

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指向临时配置目录 |
| `OPENAI_API_KEY` | 使用 dummy 值避免真实认证 |
| `CODEX_RS_SSE_FIXTURE` | Mock SSE 响应文件路径 |
| `OPENAI_BASE_URL` | 指向无效地址，确保使用 fixture |

### 平台限制

```rust
// run_codex_cli() does not work on Windows due to PTY limitations.
if cfg!(windows) {
    return Ok(());
}
```

Windows 平台由于 PTY 限制，测试被完全跳过。

## 风险、边界与改进建议

### 当前风险

1. **测试不稳定性**: 测试被标记为潜在的 flaky 测试来源
   - PTY 交互的时序敏感性
   - 15 秒超时可能在高负载 CI 环境下不足

2. **平台覆盖缺失**: Windows 平台完全跳过测试，可能导致平台相关 bug 未被发现

3. **二进制依赖**: 测试依赖预编译的 `codex` 二进制，如果二进制不存在会静默跳过
   ```rust
   eprintln!("skipping integration test because codex binary is unavailable");
   return Ok(());
   ```

4. **硬编码超时**: 
   - 2 秒初始等待 + 4×500ms 中断发送
   - 15 秒总体超时
   - 在慢速 CI 环境或资源受限机器上可能失败

### 边界情况

1. **光标位置查询**: 测试需要正确响应 TUI 的光标位置查询（CPR）才能继续
2. **信号处理**: 使用 `Ctrl+C` (ASCII 3) 中断进程，依赖进程正确处理信号
3. **退出码验证**: 接受 `0`（正常退出）或 `130`（被信号 2/SIGINT 中断）

### 改进建议

1. **增加重试机制**: 对于 flaky 测试，考虑使用 `tokio::time::timeout` 配合指数退避重试

2. **Windows 支持**: 研究 Windows ConPTY 替代方案，或至少增加基于 pipe 的降级测试

3. **显式跳过原因**: 当测试被跳过时，使用 `#[ignore = "reason"]` 或 panic 提供明确信息
   ```rust
   if cfg!(windows) {
       panic!("Test skipped on Windows: PTY not supported");
   }
   ```

4. **参数化超时**: 从环境变量读取超时值，便于 CI 调整
   ```rust
   let timeout_secs = std::env::var("TEST_TIMEOUT_SECS")
       .ok()
       .and_then(|s| s.parse().ok())
       .unwrap_or(15);
   ```

5. **增强断言**: 除了计数器验证，还可以验证：
   - NUX 消息内容是否正确
   - 日志中是否包含预期的 NUX 显示记录
   - 会话元数据是否正确记录 NUX 状态

6. **代码复用**: 提取 PTY 测试的通用模式到共享的测试工具函数
   ```rust
   // 建议新增 tests/common/pty_test_helper.rs
   async fn spawn_codex_with_timeout(args: &[&str], timeout: Duration) -> Result<...>;
   async fn wait_for_pattern(output: &[u8], pattern: &[u8]) -> Result<()>;
   ```
