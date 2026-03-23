# subagent_notifications.rs 研究文档

## 场景与职责

`subagent_notifications.rs` 是 Codex Core 的集成测试套件，专注于验证多智能体协作（Collab）功能中的子代理通知机制。该测试确保当父代理生成子代理时，相关的通知和上下文能够正确传递，包括模型配置继承、角色覆盖和上下文分叉等复杂场景。

### 核心职责
1. **子代理通知传递**：验证子代理完成通知能够正确传递给父代理
2. **上下文分叉**：验证子代理能够继承父代理的对话历史
3. **配置继承与覆盖**：验证模型和推理努力配置的继承和角色覆盖逻辑
4. **工具描述生成**：验证角色锁定设置能够在工具描述中正确体现

## 功能点目的

### 1. 子代理通知无等待 (`subagent_notification_is_included_without_wait`)
- **目的**：验证即使父代理不等待子代理完成，子代理通知仍能被包含在后续请求中
- **验证点**：
  - 子代理被生成
  - 父代理立即继续（不等待）
  - 下一轮对话包含 `<subagent_notification>`

### 2. 上下文分叉 (`spawned_child_receives_forked_parent_context`)
- **目的**：验证子代理通过 `fork_context: true` 能够继承父代理的完整对话历史
- **验证点**：
  - 父代理的对话历史包含在子代理的初始请求中
  - 子代理收到 `FORKED_SPAWN_AGENT_OUTPUT_MESSAGE` 提示
  - `function_call_output` 包含预期的内容和成功标志

### 3. 配置继承（无角色）(`spawn_agent_requested_model_and_reasoning_override_inherited_settings_without_role`)
- **目的**：验证子代理可以覆盖继承的模型和推理努力设置
- **验证点**：
  - 父代理配置：`INHERITED_MODEL` + `INHERITED_REASONING_EFFORT`
  - 子代理请求覆盖：`REQUESTED_MODEL` + `REQUESTED_REASONING_EFFORT`
  - 子代理最终配置使用请求的覆盖值

### 4. 角色配置覆盖 (`spawn_agent_role_overrides_requested_model_and_reasoning_settings`)
- **目的**：验证角色配置优先于请求中的模型和推理努力设置
- **验证点**：
  - 定义自定义角色配置（`ROLE_MODEL` + `ROLE_REASONING_EFFORT`）
  - 子代理请求同时指定角色和不同的模型/推理努力
  - 最终配置使用角色定义的值，而非请求中的值

### 5. 角色锁定描述 (`spawn_agent_tool_description_mentions_role_locked_settings`)
- **目的**：验证角色锁定的设置会在 `spawn_agent` 工具的 `agent_type` 参数描述中体现
- **验证点**：
  - 工具描述包含角色名称和描述
  - 描述中包含锁定的模型和推理努力设置
  - 提示用户这些设置无法更改

## 具体技术实现

### 常量定义
```rust
const SPAWN_CALL_ID: &str = "spawn-call-1";
const FORKED_SPAWN_AGENT_OUTPUT_MESSAGE: &str = "You are the newly spawned agent...";
const TURN_0_FORK_PROMPT: &str = "seed fork context";
const TURN_1_PROMPT: &str = "spawn a child and continue";
const TURN_2_NO_WAIT_PROMPT: &str = "follow up without wait";
const CHILD_PROMPT: &str = "child: do work";
const INHERITED_MODEL: &str = "gpt-5.2-codex";
const INHERITED_REASONING_EFFORT: ReasoningEffort = ReasoningEffort::XHigh;
const REQUESTED_MODEL: &str = "gpt-5.1";
const REQUESTED_REASONING_EFFORT: ReasoningEffort = ReasoningEffort::Low;
const ROLE_MODEL: &str = "gpt-5.1-codex-max";
const ROLE_REASONING_EFFORT: ReasoningEffort = ReasoningEffort::High;
```

### 核心辅助函数

#### 请求体内容检测
```rust
fn body_contains(req: &wiremock::Request, text: &str) -> bool {
    let is_zstd = req.headers.get("content-encoding")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value.split(',')
                .any(|entry| entry.trim().eq_ignore_ascii_case("zstd"))
        });
    let bytes = if is_zstd {
        zstd::stream::decode_all(std::io::Cursor::new(&req.body)).ok()
    } else {
        Some(req.body.clone())
    };
    bytes.and_then(|body| String::from_utf8(body).ok())
        .is_some_and(|body| body.contains(text))
}
```

#### 子代理通知检测
```rust
fn has_subagent_notification(req: &ResponsesRequest) -> bool {
    req.message_input_texts("user")
        .iter()
        .any(|text| text.contains("<subagent_notification>"))
}
```

#### 工具参数描述提取
```rust
fn tool_parameter_description(
    req: &ResponsesRequest,
    tool_name: &str,
    parameter_name: &str,
) -> Option<String> {
    req.body_json()
        .get("tools")
        .and_then(serde_json::Value::as_array)
        .and_then(|tools| {
            tools.iter().find_map(|tool| {
                if tool.get("name").and_then(serde_json::Value::as_str) == Some(tool_name) {
                    tool.get("parameters")
                        .and_then(|p| p.get("properties"))
                        .and_then(|p| p.get(parameter_name))
                        .and_then(|p| p.get("description"))
                        .and_then(serde_json::Value::as_str)
                        .map(str::to_owned)
                } else {
                    None
                }
            })
        })
}
```

#### 角色块提取
```rust
fn role_block(description: &str, role_name: &str) -> Option<String> {
    let role_header = format!("{role_name}: {{");
    let mut lines = description.lines().skip_while(|line| *line != role_header);
    let first_line = lines.next()?;
    let mut block = vec![first_line];
    for line in lines {
        if line.ends_with(": {") {
            break;
        }
        block.push(line);
    }
    Some(block.join("\n"))
}
```

### 测试设置流程

#### 带子代理的回合设置
```rust
async fn setup_turn_one_with_spawned_child(
    server: &MockServer,
    child_response_delay: Option<Duration>,
) -> Result<(TestCodex, String)> {
    // 1. 挂载父代理响应（包含 spawn_agent 调用）
    mount_sse_once_match(
        server,
        |req| body_contains(req, TURN_1_PROMPT),
        sse(vec![
            ev_response_created("resp-turn1-1"),
            ev_function_call(SPAWN_CALL_ID, "spawn_agent", &spawn_args),
            ev_completed("resp-turn1-1"),
        ]),
    ).await;

    // 2. 挂载子代理响应
    let child_sse = sse(vec![
        ev_response_created("resp-child-1"),
        ev_assistant_message("msg-child-1", "child done"),
        ev_completed("resp-child-1"),
    ]);
    // ... 挂载逻辑

    // 3. 挂载父代理后续响应
    let _turn1_followup = mount_sse_once_match(...).await;

    // 4. 启用 Collab 功能并构建测试
    let mut builder = test_codex().with_config(|config| {
        config.features.enable(Feature::Collab).expect(...);
        config.model = Some(INHERITED_MODEL.to_string());
        config.model_reasoning_effort = Some(INHERITED_REASONING_EFFORT);
    });
    let test = builder.build(server).await?;
    
    // 5. 提交回合并等待子代理创建
    test.submit_turn(TURN_1_PROMPT).await?;
    let spawned_id = wait_for_spawned_thread_id(&test).await?;
    
    Ok((test, spawned_id))
}
```

### 配置快照捕获
```rust
async fn spawn_child_and_capture_snapshot(
    server: &MockServer,
    spawn_args: serde_json::Value,
    configure_test: impl FnOnce(TestCodexBuilder) -> TestCodexBuilder,
) -> Result<ThreadConfigSnapshot> {
    let (test, spawned_id) = setup_turn_one_with_custom_spawned_child(
        server, spawn_args, None, false, configure_test
    ).await?;
    let thread_id = ThreadId::from_string(&spawned_id)?;
    Ok(test.thread_manager.get_thread(thread_id).await?.config_snapshot().await)
}
```

## 关键代码路径与文件引用

### 被测代码路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/src/features.rs` | `Feature::Collab` 多智能体协作功能标志 |
| `codex-rs/core/src/thread_manager.rs` | 线程管理器，处理子代理创建 |
| `codex-rs/core/src/tools/handlers/spawn_agent.rs` | `spawn_agent` 工具实现 |
| `codex-rs/core/src/config/role.rs` | 角色配置定义 |
| `codex-rs/protocol/src/openai_models.rs` | `ReasoningEffort` 枚举 |

### 测试依赖路径
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/core/tests/common/responses.rs` | SSE 事件构造器和 `ResponsesRequest` |
| `codex-rs/core/tests/common/test_codex.rs` | `TestCodex` 和 `TestCodexBuilder` |
| `codex-rs/core/tests/common/lib.rs` | `wait_for_event` 和 `skip_if_no_network!` |

### 关键类型引用
```rust
// codex_core
pub struct ThreadConfigSnapshot {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    ...
}

pub struct AgentRoleConfig {
    pub description: Option<String>,
    pub config_file: Option<PathBuf>,
    pub nickname_candidates: Option<Vec<String>>,
}

// codex_protocol
pub enum ReasoningEffort {
    Low,
    Medium,
    High,
    XHigh,
}
```

## 依赖与外部交互

### 外部依赖
1. **wiremock**: HTTP Mock 服务器
2. **tokio**: 异步运行时
3. **serde_json**: JSON 处理
4. **zstd**: 请求体解压缩（用于检测压缩后的内容）

### 内部依赖
1. **codex_core**: 核心库
2. **codex_protocol**: 协议定义
3. **core_test_support**: 测试支持库

### 环境要求
- 网络访问（通过 `skip_if_no_network!` 宏在沙箱中跳过）
- `Feature::Collab` 功能必须启用

## 风险、边界与改进建议

### 已知风险
1. **复杂设置逻辑**：测试设置涉及多个 Mock 响应，维护成本高
2. **时序依赖**：`wait_for_spawned_thread_id` 使用固定超时，可能因系统负载失败
3. **字符串匹配脆弱性**：`body_contains` 依赖 JSON 序列化格式，可能因格式改变失败

### 边界情况
1. **并发子代理**：测试未覆盖同时生成多个子代理的场景
2. **嵌套子代理**：测试未覆盖子代理再生成子代理的场景
3. **角色循环依赖**：测试未覆盖角色配置相互引用的场景

### 改进建议
1. **测试辅助宏**：提取通用的子代理测试设置到宏或函数
2. **参数化测试**：使用参数化测试覆盖不同的配置组合
3. **快照测试**：对工具描述使用快照测试，便于审查变更
4. **并发测试**：添加并发生成子代理的测试
5. **错误场景**：添加子代理生成失败的错误处理测试

### 潜在缺陷
1. **硬编码超时**：`wait_for_spawned_thread_id` 使用 2 秒硬编码超时
2. **无清理验证**：未验证子代理线程在测试结束后被正确清理
3. **无网络失败测试**：未测试子代理网络请求失败的处理
