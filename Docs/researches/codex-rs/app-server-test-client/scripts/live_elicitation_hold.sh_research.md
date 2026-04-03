# live_elicitation_hold.sh 研究文档

## 场景与职责

`live_elicitation_hold.sh` 是 Codex 应用服务器测试客户端的辅助脚本，专门用于测试**带外请求暂停 (out-of-band elicitation pause)** 机制。该机制允许外部辅助脚本在执行期间暂停线程的超时计时，防止因等待用户批准或其他外部交互而导致命令被意外终止。

### 核心场景

1. **测试 elicitation timeout pause 功能**：验证当外部脚本需要长时间执行（如15秒）时，是否能正确暂停统一执行超时（unified exec timeout，默认10秒），避免命令被提前终止
2. **模拟真实世界的批准流程**：在自动化测试中模拟需要用户交互的场景，如 OAuth 登录、MCP 服务器请求批准等
3. **端到端集成测试**：作为 `live-elicitation-timeout-pause` 命令的默认辅助脚本，验证整个流程的正确性

### 职责边界

- **不负责**：实际执行业务逻辑或用户交互
- **负责**：通过调用 `thread-increment-elicitation` 和 `thread-decrement-elicitation` API，在指定时间段内保持 elicitation 暂停状态

---

## 功能点目的

### 1. 暂停超时计时

当脚本启动时，通过调用 `thread-increment-elicitation` 增加线程的带外请求计数器。当计数器 > 0 时，统一执行层会暂停超时计时，允许长时间运行的外部操作完成。

### 2. 恢复超时计时

脚本结束时（正常完成或被信号中断），通过调用 `thread-decrement-elicitation` 减少计数器。当计数器归零时，超时计时恢复正常。

### 3. 信号安全清理

通过 `trap` 机制确保即使在脚本被中断（SIGINT、SIGTERM、SIGHUP）时，也能正确恢复计数器，避免资源泄漏。

---

## 具体技术实现

### 关键流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        脚本执行流程                              │
├─────────────────────────────────────────────────────────────────┤
│ 1. 验证必需环境变量                                              │
│    - APP_SERVER_URL: app-server WebSocket 地址                  │
│    - APP_SERVER_TEST_CLIENT_BIN: 测试客户端二进制路径            │
│    - CODEX_THREAD_ID: 目标线程 ID                               │
│                                                                 │
│ 2. 设置信号处理 (trap cleanup EXIT INT TERM HUP)                │
│                                                                 │
│ 3. 增加 elicitation 计数器                                      │
│    $APP_SERVER_TEST_CLIENT_BIN thread-increment-elicitation     │
│                                                                 │
│ 4. 休眠指定时间 (默认15秒，可通过 ELICITATION_HOLD_SECONDS 配置) │
│                                                                 │
│ 5. 减少 elicitation 计数器                                      │
│    $APP_SERVER_TEST_CLIENT_BIN thread-decrement-elicitation     │
│                                                                 │
│ 6. 清理并退出                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 数据结构

#### 环境变量

| 变量名 | 必需 | 默认值 | 说明 |
|--------|------|--------|------|
| `APP_SERVER_URL` | 是 | - | app-server WebSocket URL |
| `APP_SERVER_TEST_CLIENT_BIN` | 是 | - | 测试客户端可执行文件路径 |
| `CODEX_THREAD_ID` | 是 | - | 目标线程 ID |
| `ELICITATION_HOLD_SECONDS` | 否 | 15 | 暂停持续时间（秒） |

#### 内部状态变量

```bash
incremented=0  # 标记是否已成功增加计数器，用于 cleanup 判断
```

### 协议与命令

#### 使用的 JSON-RPC 方法

脚本通过调用 `codex-app-server-test-client` 二进制文件执行以下 API：

1. **`thread/increment_elicitation`**
   - 请求：`{ "threadId": "<thread_id>" }`
   - 响应：`{ "count": <u64>, "paused": <bool> }`
   - 作用：增加带外请求计数器，暂停超时计时

2. **`thread/decrement_elicitation`**
   - 请求：`{ "threadId": "<thread_id>" }`
   - 响应：`{ "count": <u64>, "paused": <bool> }`
   - 作用：减少带外请求计数器，当 count=0 时恢复超时计时

#### 信号处理

```bash
trap cleanup EXIT INT TERM HUP

# cleanup 函数逻辑：
# 如果 incremented=1（已成功增加计数器），则执行 decrement
# 忽略失败（|| true），确保清理不会导致脚本以错误状态退出
```

---

## 关键代码路径与文件引用

### 脚本本身

**文件**: `codex-rs/app-server-test-client/scripts/live_elicitation_hold.sh`

```bash
#!/bin/sh
set -eu

# 环境变量验证函数
require_env() { ... }

# 清理函数
cleanup() {
  if [ "$incremented" -eq 1 ]; then
    "$APP_SERVER_TEST_CLIENT_BIN" --url "$APP_SERVER_URL" \
      thread-decrement-elicitation "$thread_id" >/dev/null 2>&1 || true
  fi
}

# 主流程
trap cleanup EXIT INT TERM HUP
echo "[elicitation-hold] increment thread=$thread_id"
"$APP_SERVER_TEST_CLIENT_BIN" thread-increment-elicitation "$thread_id"
sleep "$hold_seconds"
echo "[elicitation-hold] decrement thread=$thread_id"
"$APP_SERVER_TEST_CLIENT_BIN" thread-decrement-elicitation "$thread_id"
```

### 调用方：测试客户端

**文件**: `codex-rs/app-server-test-client/src/lib.rs`

#### `live_elicitation_timeout_pause` 函数（行 1165-1319）

这是脚本的主要调用方，执行以下步骤：

1. **构建命令**：将脚本路径和环境变量组合成 shell 命令
2. **构造提示词**：指示模型使用 `exec_command` 工具执行该命令
3. **验证结果**：检查脚本输出中是否包含 `[elicitation-hold] done` 标记

#### `thread_increment_elicitation` 函数（行 1137-1149）

```rust
fn thread_increment_elicitation(url: &str, thread_id: String) -> Result<()> {
    let endpoint = Endpoint::ConnectWs(url.to_string());
    let mut client = CodexClient::connect(&endpoint, &[])?;
    let response = client.thread_increment_elicitation(
        ThreadIncrementElicitationParams { thread_id }
    )?;
    println!("< thread/increment_elicitation response: {response:?}");
    Ok(())
}
```

### 协议定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

#### 请求/响应结构（行 2742-2779）

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadIncrementElicitationParams {
    pub thread_id: String,
}

pub struct ThreadIncrementElicitationResponse {
    pub count: u64,
    pub paused: bool,
}

pub struct ThreadDecrementElicitationParams {
    pub thread_id: String,
}

pub struct ThreadDecrementElicitationResponse {
    pub count: u64,
    pub paused: bool,
}
```

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`

#### 客户端请求枚举（行 237-253）

```rust
#[experimental("thread/increment_elicitation")]
ThreadIncrementElicitation => "thread/increment_elicitation" {
    params: v2::ThreadIncrementElicitationParams,
    response: v2::ThreadIncrementElicitationResponse,
},

#[experimental("thread/decrement_elicitation")]
ThreadDecrementElicitation => "thread/decrement_elicitation" {
    params: v2::ThreadDecrementElicitationParams,
    response: v2::ThreadDecrementElicitationResponse,
},
```

### 服务端实现

**文件**: `codex-rs/app-server/src/codex_message_processor.rs`

#### `thread_increment_elicitation` 处理器（行 2217-2250）

```rust
async fn thread_increment_elicitation(
    &self,
    request_id: ConnectionRequestId,
    params: ThreadIncrementElicitationParams,
) {
    let (_, thread) = match self.load_thread(&params.thread_id).await { ... };
    
    match thread.increment_out_of_band_elicitation_count().await {
        Ok(count) => {
            self.outgoing
                .send_response(
                    request_id,
                    ThreadIncrementElicitationResponse {
                        count,
                        paused: count > 0,
                    },
                )
                .await;
        }
        Err(err) => { ... }
    }
}
```

### 核心层实现

**文件**: `codex-rs/core/src/codex_thread.rs`

#### 计数器管理（行 166-199）

```rust
pub struct CodexThread {
    pub(crate) codex: Codex,
    rollout_path: Option<PathBuf>,
    out_of_band_elicitation_count: Mutex<u64>,
    _watch_registration: WatchRegistration,
}

pub async fn increment_out_of_band_elicitation_count(&self) -> CodexResult<u64> {
    let mut guard = self.out_of_band_elicitation_count.lock().await;
    let was_zero = *guard == 0;
    *guard = guard.checked_add(1).ok_or_else(|| {
        CodexErr::Fatal("out-of-band elicitation count overflowed".to_string())
    })?;

    if was_zero {
        self.codex
            .session
            .set_out_of_band_elicitation_pause_state(true);
    }
    Ok(*guard)
}

pub async fn decrement_out_of_band_elicitation_count(&self) -> CodexResult<u64> {
    let mut guard = self.out_of_band_elicitation_count.lock().await;
    if *guard == 0 {
        return Err(CodexErr::InvalidRequest(
            "out-of-band elicitation count is already zero".to_string(),
        ));
    }
    *guard -= 1;
    let now_zero = *guard == 0;
    if now_zero {
        self.codex
            .session
            .set_out_of_band_elicitation_pause_state(false);
    }
    Ok(*guard)
}
```

### 统一执行层暂停机制

**文件**: `codex-rs/core/src/unified_exec/process_manager.rs`

#### 截止时间延长逻辑（行 734-758）

```rust
async fn extend_deadlines_while_paused(
    pause_state: &mut Option<watch::Receiver<bool>>,
    deadline: &mut Instant,
    post_exit_deadline: &mut Option<Instant>,
) {
    let Some(receiver) = pause_state.as_mut() else { return; };
    if !*receiver.borrow() { return; }

    let paused_at = Instant::now();
    while *receiver.borrow() {
        if receiver.changed().await.is_err() { break; }
    }

    let paused_for = paused_at.elapsed();
    *deadline += paused_for;
    if let Some(post_exit_deadline) = post_exit_deadline.as_mut() {
        *post_exit_deadline += paused_for;
    }
}
```

---

## 依赖与外部交互

### 直接依赖

| 组件 | 类型 | 说明 |
|------|------|------|
| `codex-app-server-test-client` | 二进制 | 提供 `thread-increment-elicitation` 和 `thread-decrement-elicitation` 命令 |
| `app-server` | 服务 | 通过 WebSocket 提供 JSON-RPC API |
| POSIX shell | 运行时 | 脚本使用 `/bin/sh`，依赖 `trap`、`sleep` 等标准命令 |

### 外部交互流程

```
┌─────────────────────┐     ┌──────────────────────────┐     ┌─────────────────┐
│ live_elicitation_   │────▶│ codex-app-server-test-   │────▶│   app-server    │
│     hold.sh         │     │        client            │     │  (WebSocket)    │
└─────────────────────┘     └──────────────────────────┘     └─────────────────┘
         │                              │                              │
         │  1. thread-increment-         │  2. thread/increment_        │
         │     elicitation <thread_id>   │     elicitation JSON-RPC     │
         │──────────────────────────────▶│─────────────────────────────▶│
         │                              │  3. Response {count, paused} │
         │  4. OK / Error               │◀─────────────────────────────│
         │◀─────────────────────────────│                              │
         │  5. sleep 15s (local)        │                              │
         │                              │                              │
         │  6. thread-decrement-        │  7. thread/decrement_        │
         │     elicitation <thread_id>  │     elicitation JSON-RPC     │
         │──────────────────────────────▶│─────────────────────────────▶│
         │                              │  8. Response {count, paused} │
         │  9. OK / Error               │◀─────────────────────────────│
         │◀─────────────────────────────│                              │
```

### 核心层依赖链

```
app-server
    └── codex_message_processor::thread_{increment,decrement}_elicitation
            └── CodexThread::increment_out_of_band_elicitation_count()
                    ├── out_of_band_elicitation_count (Mutex<u64>)
                    └── Session::set_out_of_band_elicitation_pause_state()
                            └── unified_exec::ProcessManager
                                    └── collect_output_until_deadline()
                                            └── extend_deadlines_while_paused()
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 计数器泄漏风险

**风险描述**：如果脚本在调用 `increment` 后被强制终止（SIGKILL，无法捕获），`decrement` 可能无法执行，导致计数器永久非零，该线程的超时计时将永远暂停。

**缓解措施**：
- 使用 `trap` 捕获常见信号（INT、TERM、HUP）
- 测试客户端在测试结束后会尝试强制 `decrement` 作为清理

**代码参考**（`lib.rs` 行 1300-1309）：
```rust
match client.thread_decrement_elicitation(ThreadDecrementElicitationParams {
    thread_id: thread_id.clone(),
}) {
    Ok(response) => { ... }
    Err(err) => {
        eprintln!("[cleanup] thread/decrement_elicitation ignored: {err:#}");
    }
}
```

#### 2. 计数器溢出风险

**风险描述**：虽然使用了 `checked_add`，但如果调用方异常地反复调用 `increment`，可能导致 `u64` 溢出。

**缓解措施**：核心层已实现溢出检查（`codex_thread.rs` 行 169-171）

#### 3. 环境变量缺失

**风险描述**：必需环境变量缺失时，脚本会以状态码 1 退出，但错误信息可能不够详细。

### 边界条件

| 场景 | 行为 |
|------|------|
| `ELICITATION_HOLD_SECONDS=0` | 立即执行 decrement，几乎无暂停效果 |
| `ELICITATION_HOLD_SECONDS` 未设置 | 使用默认值 15 秒 |
| 线程不存在 | `thread-increment-elicitation` 命令返回错误，脚本以状态码 1 退出 |
| 计数器已为 0 时调用 decrement | 服务端返回错误，`cleanup` 中的 `|| true` 确保脚本不因此失败 |
| 多次信号中断 | `trap` 设置确保 cleanup 只执行一次（通过 `incremented` 变量控制） |

### 改进建议

#### 1. 增加健康检查

在 `increment` 后增加一个验证步骤，确认暂停状态已生效：

```bash
if ! "$APP_SERVER_TEST_CLIENT_BIN" --url "$APP_SERVER_URL" \
    thread-check-elicitation "$thread_id" | grep -q '"paused":true'; then
    echo "[elicitation-hold] failed to pause timeout" >&2
    exit 1
fi
```

#### 2. 支持超时配置

当前 `hold_seconds` 只控制 `sleep` 时间，但 `increment`/`decrement` API 调用本身也可能超时。建议增加：

```bash
API_TIMEOUT="${ELICITATION_API_TIMEOUT:-5}"
timeout "$API_TIMEOUT" "$APP_SERVER_TEST_CLIENT_BIN" ...
```

#### 3. 日志增强

当前日志仅输出到 stdout，建议增加结构化日志或日志级别控制：

```bash
LOG_LEVEL="${ELICITATION_LOG_LEVEL:-info}"
log() {
    local level="$1"
    shift
    if [ "$level" = "error" ] || [ "$LOG_LEVEL" != "quiet" ]; then
        echo "[elicitation-hold][$level] $*" >&2
    fi
}
```

#### 4. 幂等性改进

当前 `cleanup` 函数依赖 `incremented` 变量，但如果脚本在 `increment` 和设置 `incremented=1` 之间被中断，可能导致状态不一致。

#### 5. 跨平台支持

当前脚本使用 POSIX shell，但 Windows 环境下可能无法运行。`live_elicitation_timeout_pause` 函数已明确检查并拒绝 Windows。建议提供 PowerShell 版本的脚本以支持 Windows 原生测试。

#### 6. 并发安全文档

虽然核心层的计数器使用 `Mutex<u64>` 保护，但脚本本身不处理并发调用场景。如果同一脚本的多个实例同时操作同一线程，计数器可能无法正确反映预期的暂停/恢复语义。建议在文档中明确：

> 同一脚本的多实例并发执行在同一线程上可能导致计数器状态不一致。如需并发暂停，请确保调用方协调。

---

## 相关测试

### 单元测试

**文件**: `codex-rs/core/src/unified_exec/mod_tests.rs`

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn unified_exec_pause_blocks_yield_timeout() -> anyhow::Result<()> {
    let (session, turn) = test_session_and_turn().await;
    session.set_out_of_band_elicitation_pause_state(true);

    let paused_session = Arc::clone(&session);
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(2)).await;
        paused_session.set_out_of_band_elicitation_pause_state(false);
    });

    let started = tokio::time::Instant::now();
    let response = exec_command(&session, &turn, "sleep 1 && echo done", 250).await?;

    assert!(
        started.elapsed() >= Duration::from_secs(2),
        "pause should block the unified exec yield timeout"
    );
    Ok(())
}
```

### 集成测试

**文件**: `codex-rs/app-server-test-client/src/lib.rs` 中的 `live_elicitation_timeout_pause` 函数

该函数作为端到端测试，验证：
1. 脚本输出包含 `[elicitation-hold] done` 标记
2. 命令执行状态为 `Completed`
3. Turn 状态为 `Completed`
4. 执行时间至少为 `hold_seconds - 1` 秒（证明暂停生效）

---

## 总结

`live_elicitation_hold.sh` 是一个专门用于测试 Codex 带外请求暂停机制的辅助脚本。它通过简单的 `increment` → `sleep` → `decrement` 流程，验证核心层的超时暂停功能是否正常工作。虽然脚本本身逻辑简单，但它依赖于复杂的跨层机制（协议层 → 应用服务器 → 核心层 → 统一执行层），是验证端到端 elicitation 暂停功能的关键组件。
