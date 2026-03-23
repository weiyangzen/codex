# tool_parallelism.rs 研究文档

## 场景与职责

`tool_parallelism.rs` 是 Codex Core 的集成测试套件，专注于验证工具并行执行能力。该测试确保多个工具调用能够在同一对话轮次中并行执行，提高整体响应效率，并验证工具结果的正确分组和排序。

### 核心职责
1. **读文件工具并行**：验证 `read_file` 工具并行执行
2. **Shell 工具并行**：验证 `shell_command` 工具并行执行
3. **混合工具并行**：验证不同类型工具混合并行执行
4. **工具结果分组**：验证工具调用和输出在请求中的正确分组
5. **流延迟场景**：验证工具在 `response.completed` 延迟时仍正确启动

## 功能点目的

### 1. 读文件工具并行 (`read_file_tools_run_in_parallel`)
- **目的**：验证 `test_sync_tool` 工具并行执行
- **验证点**：
  - 使用 barrier 同步机制确保两个工具真正并行
  - 总执行时间小于 1.6 秒（串行执行需要 ~600ms）
  - 预热回合确保 JIT 编译不影响测量

### 2. Shell 工具并行 (`shell_tools_run_in_parallel`)
- **目的**：验证 `shell_command` 工具并行执行
- **验证点**：
  - 两个 `sleep 0.25` 命令并行执行
  - 总时间小于 1.6 秒
  - 使用非登录 shell 避免启动开销

### 3. 混合工具并行 (`mixed_parallel_tools_run_in_parallel`)
- **目的**：验证 `test_sync_tool` 和 `shell_command` 混合并行执行
- **验证点**：
  - 不同类型工具同时执行
  - 总时间小于 1.6 秒

### 4. 工具结果分组 (`tool_results_grouped`)
- **目的**：验证工具调用和输出在请求中的正确顺序
- **验证点**：
  - 所有 `function_call` 在 `function_call_output` 之前
  - 输出顺序与调用顺序一致（按 `call_id` 匹配）
  - 3 个调用对应 3 个输出

### 5. 流延迟启动 (`shell_tools_start_before_response_completed_when_stream_delayed`)
- **目的**：验证工具在 SSE 流延迟完成时仍正确启动
- **验证点**：
  - 4 个 shell 命令在 `response.completed` 之前启动
  - 使用 Perl 记录时间戳验证启动时间
  - 所有命令在流完成前已执行

## 具体技术实现

### 测试辅助函数
```rust
async fn run_turn(test: &TestCodex, prompt: &str) -> anyhow::Result<()> {
    let session_model = test.session_configured.model.clone();
    test.codex.submit(Op::UserTurn { ... }).await?;
    wait_for_event(&test.codex, |ev| matches!(ev, EventMsg::TurnComplete(_))).await;
    Ok(())
}

async fn run_turn_and_measure(test: &TestCodex, prompt: &str) -> anyhow::Result<Duration> {
    let start = Instant::now();
    run_turn(test, prompt).await?;
    Ok(start.elapsed())
}

fn assert_parallel_duration(actual: Duration) {
    assert!(
        actual < Duration::from_millis(1_600),
        "expected parallel execution to finish quickly, got {actual:?}"
    );
}
```

### Barrier 同步机制
```rust
let parallel_args = json!({
    "sleep_after_ms": 300,
    "barrier": {
        "id": "parallel-test-sync",
        "participants": 2,
        "timeout_ms": 1_000,
    }
});
```

### 读文件工具并行测试
```rust
let warmup_args = json!({
    "sleep_after_ms": 10,
    "barrier": { "id": "parallel-test-sync-warmup", "participants": 2, "timeout_ms": 1_000 }
});
let parallel_args = json!({
    "sleep_after_ms": 300,
    "barrier": { "id": "parallel-test-sync", "participants": 2, "timeout_ms": 1_000 }
});

// 预热回合
mount_sse_sequence(&server, vec![warmup_first, warmup_second, ...]).await;
run_turn(&test, "warm up parallel tool").await?;

// 实际测试
let duration = run_turn_and_measure(&test, "exercise sync tool").await?;
assert_parallel_duration(duration);
```

### Shell 工具并行测试
```rust
let shell_args = json!({
    "command": "sleep 0.25",
    "login": false, // 避免用户特定的 shell 启动开销
    "timeout_ms": 1_000,
});

let first_response = sse(vec![
    json!({"type": "response.created", "response": {"id": "resp-1"}}),
    ev_function_call("call-1", "shell_command", &args_one),
    ev_function_call("call-2", "shell_command", &args_two),
    ev_completed("resp-1"),
]);
```

### 工具结果分组测试
```rust
let input = tool_output_request.single_request().input();

// 查找所有 function_call
let function_calls = input.iter().enumerate()
    .filter(|(_, item)| item.get("type").and_then(Value::as_str) == Some("function_call"))
    .collect::<Vec<_>>();

// 查找所有 function_call_output
let function_call_outputs = input.iter().enumerate()
    .filter(|(_, item)| item.get("type").and_then(Value::as_str) == Some("function_call_output"))
    .collect::<Vec<_>>();

// 验证顺序：所有调用在输出之前
for (index, _) in &function_calls {
    for (output_index, _) in &function_call_outputs {
        assert!(*index < *output_index, "all function calls must come before outputs");
    }
}

// 验证 call_id 匹配
for (call, output) in function_calls.iter().zip(function_call_outputs.iter()) {
    assert_eq!(
        call.1.get("call_id").and_then(Value::as_str),
        output.1.get("call_id").and_then(Value::as_str)
    );
}
```

### 流延迟启动测试
```rust
// 使用 gate 控制流的分块发送
let (first_gate_tx, first_gate_rx) = oneshot::channel();
let (completion_gate_tx, completion_gate_rx) = oneshot::channel();
let (follow_up_gate_tx, follow_up_gate_rx) = oneshot::channel();

let (streaming_server, completion_receivers) = start_streaming_sse_server(vec![
    vec![
        StreamingSseChunk { gate: Some(first_gate_rx), body: first_chunk },
        StreamingSseChunk { gate: Some(completion_gate_rx), body: second_chunk },
    ],
    vec![StreamingSseChunk { gate: Some(follow_up_gate_rx), body: follow_up }],
]).await;

// 发送 gate 信号，但延迟 completion
let _ = first_gate_tx.send(());
let _ = follow_up_gate_tx.send(());

// 验证命令在 completion 之前已执行
let timestamps = tokio::time::timeout(Duration::from_secs(5), async {
    loop {
        let contents = fs::read_to_string(output_path)?;
        let timestamps: Vec<i64> = contents.lines()
            .map(|line| line.trim().parse::<i64>())
            .collect::<Result<_, _>>()?;
        if timestamps.len() == 4 {
            return Ok(timestamps);
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}).await??;

// 发送 completion 信号
let _ = completion_gate_tx.send(());
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/tool_executor.rs` | 工具执行器，管理并行执行 |
| `codex-rs/core/src/tools/mod.rs` | 工具注册和调度 |
| `codex-rs/core/src/tools/handlers/read_file.rs` | `test_sync_tool` 实现 |
| `codex-rs/core/src/tools/handlers/shell.rs` | `shell_command` 实现 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/streaming_sse.rs` | `start_streaming_sse_server` 和 `StreamingSseChunk` |
| `codex-rs/core/tests/common/responses.rs` | SSE 事件构造器 |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 测试辅助 |

### 关键类型引用
```rust
// core_test_support::streaming_sse
pub struct StreamingSseChunk {
    pub gate: Option<oneshot::Receiver<()>>, // 控制发送时机的信号
    pub body: String,
}

// tokio::sync
pub struct oneshot::Receiver<T>;
pub struct oneshot::Sender<T>;

// serde_json::Value
pub enum Value {
    Object(Map<String, Value>),
    Array(Vec<Value>),
    String(String),
    ...
}
```

## 依赖与外部交互

### 外部依赖
1. **tokio**: 异步运行时（`multi_thread` flavor）
2. **serde_json**: JSON 处理
3. **wiremock**: HTTP Mock（部分测试使用）

### 内部依赖
1. **codex_core**: 核心库
2. **codex_protocol**: 协议定义
3. **core_test_support**: 测试支持库

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- 非 Windows 平台（`#![cfg(not(target_os = "windows"))]`）
- Perl（流延迟测试使用 `Time::HiRes`）

## 风险、边界与改进建议

### 已知风险
1. **时序敏感**：时间断言（< 1.6s）在慢速 CI 环境可能失败
2. **平台限制**：排除 Windows，可能遗漏平台特定问题
3. **外部依赖**：流延迟测试依赖 Perl 和 `Time::HiRes`

### 边界情况
1. **资源竞争**：未测试大量并发工具调用的资源限制
2. **部分失败**：未测试部分工具失败时的并行处理
3. **取消场景**：未测试工具执行中途取消的场景

### 改进建议
1. **自适应超时**：根据 CI 环境动态调整时间断言
2. **资源限制测试**：添加大量并发工具调用的压力测试
3. **失败场景**：添加部分工具失败的并行处理测试
4. **取消测试**：添加工具执行取消的测试
5. **Windows 支持**：调查并添加 Windows 平台支持

### 潜在缺陷
1. **硬编码阈值**：1.6 秒阈值可能不适用于所有环境
2. **无预热控制**：依赖单次预热回合，可能不充分
3. **有限的重试**：未测试工具重试对并行性的影响

### 相关测试
- `tools.rs`: 工具功能和权限测试
- `tool_harness.rs`: 工具事件和输出测试
- `abort_tasks.rs`: 任务取消测试
