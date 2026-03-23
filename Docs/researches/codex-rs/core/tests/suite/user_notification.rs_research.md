# user_notification.rs 研究文档

## 场景与职责

`user_notification.rs` 是 Codex 核心测试套件中专门测试**用户通知系统**的集成测试文件。该测试文件验证当 Agent 完成一轮对话（turn）时，系统能够通过配置的外部命令（notify script）向用户发送通知。

该测试文件位于 `codex-rs/core/tests/suite/user_notification.rs`，代码量约 80 行，包含 1 个核心测试用例。该测试仅在非 Windows 平台运行（使用 `#![cfg(not(target_os = "windows"))]` 条件编译）。

### 核心职责

1. **验证用户通知功能**：当 Agent 完成一轮对话后，执行配置的 notify 脚本
2. **验证通知负载格式**：确保通知包含正确的 JSON 负载（类型、输入消息、助手回复等）
3. **测试外部命令集成**：验证 notify 配置能够正确调用外部 shell 脚本

---

## 功能点目的

### 测试用例概览

| 测试函数 | 目的 |
|---------|------|
| `summarize_context_three_requests_and_instructions` | 验证用户通知在 Agent 完成 turn 时正确触发，并包含正确的上下文信息 |

### 详细功能说明

#### 测试场景

**测试目标**：验证当 Agent 完成一轮对话后，配置的 notify 脚本被调用，并接收正确的 JSON 负载。

**测试步骤**：
1. 启动 Mock SSE 服务器
2. 创建临时目录和 notify 脚本（`notify.sh`）
3. 配置 notify 脚本路径到 Codex 配置
4. 提交用户输入并等待 turn 完成
5. 等待 notify 脚本写入输出文件
6. 验证输出文件中的 JSON 负载内容

**notify 脚本功能**：
```bash
#!/bin/bash
set -e
payload_path="$(dirname "${0}")/notify.txt"
tmp_path="${payload_path}.tmp"
echo -n "${@: -1}" > "${tmp_path}"
mv "${tmp_path}" "${payload_path}"
```

该脚本接收 notify 参数，将最后一个参数（JSON 负载）写入 `notify.txt` 文件。

**验证点**：
- 通知类型为 `"agent-turn-complete"`
- `input-messages` 包含用户输入 `["hello world"]`
- `last-assistant-message` 包含助手回复 `"Done"`

---

## 具体技术实现

### 关键代码流程

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn summarize_context_three_requests_and_instructions() -> anyhow::Result<()> {
    // 1. 网络检查
    skip_if_no_network!(Ok(()));
    
    // 2. 启动 Mock 服务器
    let server = start_mock_server().await;
    let sse1 = sse(vec![ev_assistant_message("m1", "Done"), ev_completed("r1")]);
    responses::mount_sse_once(&server, sse1).await;
    
    // 3. 创建 notify 目录和脚本
    let notify_dir = TempDir::new()?;
    let notify_script = notify_dir.path().join("notify.sh");
    std::fs::write(&notify_script, r#"#!/bin/bash
set -e
payload_path="$(dirname "${0}")/notify.txt"
tmp_path="${payload_path}.tmp"
echo -n "${@: -1}" > "${tmp_path}"
mv "${tmp_path}" "${payload_path}""#)?;
    std::fs::set_permissions(&notify_script, std::fs::Permissions::from_mode(0o755))?;
    let notify_file = notify_dir.path().join("notify.txt");
    let notify_script_str = notify_script.to_str().unwrap().to_string();
    
    // 4. 配置 Codex 使用 notify 脚本
    let TestCodex { codex, .. } = test_codex()
        .with_config(move |cfg| cfg.notify = Some(vec![notify_script_str]))
        .build(&server)
        .await?;
    
    // 5. 提交用户输入
    codex.submit(Op::UserInput {
        items: vec![UserInput::Text {
            text: "hello world".into(),
            text_elements: Vec::new(),
        }],
        final_output_json_schema: None,
    }).await?;
    wait_for_event(&codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
    
    // 6. 等待 notify 文件写入
    fs_wait::wait_for_path_exists(&notify_file, Duration::from_secs(5)).await?;
    let notify_payload_raw = tokio::fs::read_to_string(&notify_file).await?;
    let payload: Value = serde_json::from_str(&notify_payload_raw)?;
    
    // 7. 验证通知内容
    assert_eq!(payload["type"], json!("agent-turn-complete"));
    assert_eq!(payload["input-messages"], json!(["hello world"]));
    assert_eq!(payload["last-assistant-message"], json!("Done"));
    
    Ok(())
}
```

### 通知负载格式

通知系统发送的 JSON 负载格式如下：

```json
{
    "type": "agent-turn-complete",
    "thread-id": "<线程ID>",
    "turn-id": "<回合ID>",
    "cwd": "/当前/工作/目录",
    "client": "codex-tui",
    "input-messages": ["用户输入消息1", "用户输入消息2"],
    "last-assistant-message": "助手最后一条回复"
}
```

### notify 配置

notify 配置是 Codex 配置中的可选字段：

```rust
// codex-rs/core/src/config/mod.rs
pub struct Config {
    // ...
    /// Optional external command to spawn for end-user notifications.
    pub notify: Option<Vec<String>>,
    // ...
}
```

配置示例（config.toml）：
```toml
notify = ["notify-send", "Codex"]
```

这会配置 Codex 在 turn 完成时执行：
```bash
notify-send Codex '{"type":"agent-turn-complete",...}'
```

---

## 关键代码路径与文件引用

### 被测代码路径

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/hooks/src/user_notification.rs` | 用户通知负载定义和序列化 |
| `codex-rs/hooks/src/legacy_notify.rs` | 传统 notify 钩子实现 |
| `codex-rs/hooks/src/lib.rs` | Hooks 模块导出 |
| `codex-rs/core/src/codex.rs` | Session 实现，调用 notify 钩子 |
| `codex-rs/core/src/config/mod.rs` | Config 定义，包含 notify 字段 |

### Hooks 系统架构

#### Hooks 配置

```rust
// codex-rs/core/src/codex.rs
let hooks = Hooks::new(HooksConfig {
    legacy_notify_argv: config.notify.clone(),  // 从配置读取 notify 命令
    feature_enabled: config.features.enabled(Feature::CodexHooks),
    config_layer_stack: Some(config.config_layer_stack.clone()),
    hook_shell_program,
    hook_shell_argv,
});
```

#### UserNotification 结构

```rust
// codex-rs/hooks/src/user_notification.rs
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum UserNotification {
    #[serde(rename_all = "kebab-case")]
    AgentTurnComplete {
        thread_id: String,
        turn_id: String,
        cwd: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        client: Option<String>,
        input_messages: Vec<String>,
        last_assistant_message: Option<String>,
    },
}
```

#### notify_hook 函数

```rust
// codex-rs/hooks/src/user_notification.rs
pub fn notify_hook(argv: Vec<String>) -> Hook {
    let argv = Arc::new(argv);
    Hook {
        name: "legacy_notify".to_string(),
        func: Arc::new(move |payload: &HookPayload| {
            let argv = Arc::clone(&argv);
            Box::pin(async move {
                let mut command = match command_from_argv(&argv) {
                    Some(command) => command,
                    None => return HookResult::Success,
                };
                // 序列化负载并作为参数附加
                if let Ok(notify_payload) = legacy_notify_json(payload) {
                    command.arg(notify_payload);
                }
                // 后台执行，忽略输出
                command
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null());
                match command.spawn() {
                    Ok(_) => HookResult::Success,
                    Err(err) => HookResult::FailedContinue(err.into()),
                }
            })
        }),
    }
}
```

### 事件触发流程

1. **Turn 完成**：当 `TurnComplete` 事件发生时
2. **Hooks 触发**：Codex 调用 `Hooks::trigger_after_agent`
3. **负载构建**：构建 `HookPayload` 包含 turn 信息
4. **notify 执行**：如果配置了 `notify`，执行 `notify_hook`
5. **命令执行**：fork 子进程执行 notify 命令，附加 JSON 负载

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `tempfile::TempDir` | 创建临时目录存放 notify 脚本 |
| `serde_json::Value` | 解析 notify 输出的 JSON 负载 |
| `std::os::unix::fs::PermissionsExt` | 设置脚本可执行权限（Unix） |

### 内部依赖

| 模块 | 用途 |
|-----|------|
| `codex_protocol::protocol::*` | 协议事件类型（EventMsg, Op） |
| `codex_protocol::user_input::UserInput` | 用户输入类型 |
| `core_test_support::*` | 测试支持库 |

### 平台限制

```rust
#![cfg(not(target_os = "windows"))]
```

该测试明确排除 Windows 平台，原因：
1. 使用 Unix 特定的文件权限设置 (`PermissionsExt`)
2. notify 脚本使用 Bash（Windows 需要不同实现）

---

## 风险、边界与改进建议

### 已知风险

1. **平台限制**：测试仅在 Unix 平台运行，Windows 用户通知功能缺乏测试覆盖
2. **脚本依赖**：测试依赖 Bash 脚本，在最小化环境（如某些容器）可能失败
3. **时序敏感性**：使用 `fs_wait::wait_for_path_exists` 等待文件写入，依赖文件系统通知
4. **并发问题**：notify 脚本使用临时文件 + 原子重命名，但在高并发场景可能有问题

### 边界情况

1. **空输入消息**：未测试用户发送空消息时的通知行为
2. **多轮对话**：仅测试单轮对话，未验证多轮对话中每轮都触发通知
3. **通知失败**：未测试 notify 命令执行失败时的错误处理
4. **特殊字符**：未测试用户输入包含特殊字符（引号、换行等）时的 JSON 转义
5. **长消息**：未测试超长消息时的通知截断行为

### 改进建议

1. **增加 Windows 支持**：
   ```rust
   #[cfg(target_os = "windows")]
   async fn summarize_context_three_requests_and_instructions_windows() {
       // 使用 PowerShell 脚本或 Windows 通知 API
   }
   ```

2. **增加错误处理测试**：
   ```rust
   async fn handles_notify_command_failure() {
       // 配置一个会失败的 notify 命令，验证系统不崩溃
   }
   ```

3. **增加特殊字符测试**：
   ```rust
   async fn handles_special_characters_in_notification() {
       // 测试输入包含引号、换行、Unicode 等字符
   }
   ```

4. **增加多轮对话测试**：
   ```rust
   async fn notifies_on_each_turn_in_multi_turn_conversation() {
       // 验证多轮对话中每轮都触发通知
   }
   ```

5. **改进脚本健壮性**：
   - 添加超时机制防止脚本挂起
   - 添加重试机制处理临时失败

6. **增加通知配置测试**：
   ```rust
   async fn respects_notify_configuration_changes() {
       // 测试运行时修改 notify 配置
   }
   ```

### 相关配置项

```toml
# config.toml 示例
notify = ["notify-send", "Codex"]  # Linux 桌面通知
# 或
notify = ["osascript", "-e", "display notification \"Codex Done\""]  # macOS
# 或自定义脚本
notify = ["/path/to/custom-notify.sh"]
```

### 测试执行建议

```bash
# 运行用户通知测试（非 Windows 平台）
cargo test -p codex-core summarize_context_three_requests_and_instructions

# 运行所有用户通知相关测试
cargo test -p codex-core user_notification
```

### 与 CodexHooks 特性的关系

用户通知系统与 `CodexHooks` 特性相关但独立：

- **传统 notify**：通过 `config.notify` 配置，始终启用（如果配置）
- **CodexHooks**：通过 `Feature::CodexHooks` 启用，支持更复杂的钩子系统

测试中使用的是传统 notify 机制，不依赖 `CodexHooks` 特性标志。
