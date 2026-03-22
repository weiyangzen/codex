# codex-rs/core/tests/suite 研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 目录定位

`codex-rs/core/tests/suite` 是 **Codex Core 库的集成测试套件**，负责验证 Codex 核心功能的端到端行为。该测试套件通过模拟 OpenAI Responses API 的服务器响应，测试 Codex 在各种场景下的正确性。

### 1.2 核心职责

| 职责领域 | 描述 |
|---------|------|
| **API 集成测试** | 验证 Codex 与 OpenAI Responses API 的交互逻辑 |
| **工具调用测试** | 测试各种工具（shell、file、apply_patch 等）的执行 |
| **状态管理测试** | 验证会话恢复、compact、undo/redo 等状态操作 |
| **沙箱安全测试** | 验证 seatbelt、landlock 等沙箱机制的正确性 |
| **多代理测试** | 测试子代理 spawn、通信、任务分配 |
| **网络与认证** | 测试 WebSocket、认证刷新、请求压缩等 |

### 1.3 测试架构特点

```
┌─────────────────────────────────────────────────────────────┐
│                    集成测试架构                              │
├─────────────────────────────────────────────────────────────┤
│  Test Module (suite/*.rs)                                   │
│       ↓                                                     │
│  core_test_support (tests/common/)                          │
│       ├── test_codex.rs    # TestCodexBuilder, TestCodex    │
│       ├── responses.rs     # Mock SSE responses             │
│       └── lib.rs           # wait_for_event, macros         │
│       ↓                                                     │
│  codex_core (src/)                                          │
│       ├── codex.rs         # CodexThread                    │
│       ├── client.rs        # ModelClient                    │
│       └── tools/           # Tool implementations           │
│       ↓                                                     │
│  wiremock::MockServer    # Simulated OpenAI API             │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 测试分类概览

该目录包含 **~90 个测试模块**，按功能分类如下：

#### 2.1.1 核心客户端测试 (`client.rs`)
- **目的**: 验证 Codex 客户端与模型 API 的基础交互
- **关键测试**:
  - `resume_includes_initial_messages_and_sends_prior_items` - 会话恢复时历史消息处理
  - `includes_conversation_id_and_model_headers_in_request` - 请求头验证
  - `chatgpt_auth_sends_correct_request` - ChatGPT 认证流程
  - `includes_user_instructions_message_in_request` - 用户指令注入

#### 2.1.2 工具测试 (`tools.rs`)
- **目的**: 验证各类工具调用的端到端行为
- **关键测试**:
  - `shell_escalated_permissions_rejected_then_ok` - 权限升级拒绝逻辑
  - `sandbox_denied_shell_returns_original_output` - 沙箱拒绝处理
  - `shell_timeout_includes_timeout_prefix_and_metadata` - 超时处理
  - `unified_exec_spec_toggle_end_to_end` - UnifiedExec 功能切换

#### 2.1.3 Compact 测试 (`compact.rs`, `compact_remote.rs`, `compact_resume_fork.rs`)
- **目的**: 验证上下文压缩功能
- **关键测试**:
  - `summarize_context_three_requests_and_instructions` - 手动 compact 流程
  - `multiple_auto_compact_per_task_runs_after_token_limit_hit` - 自动 compact
  - `manual_compact_uses_custom_prompt` - 自定义 compact prompt
  - `remote_pre_turn_compaction_restates_realtime_start` - 远程 compact

#### 2.1.4 会话恢复测试 (`resume.rs`)
- **目的**: 验证从 rollout 文件恢复会话
- **关键测试**:
  - `resume_replays_image_tool_outputs_with_detail` - 图像工具输出恢复
  - `resume_replays_legacy_js_repl_image_rollout_shapes` - 遗留格式兼容

#### 2.1.5 Agent 任务测试 (`agent_jobs.rs`)
- **目的**: 验证 CSV 批处理任务
- **关键测试**:
  - `spawn_agents_on_csv_runs_and_exports` - CSV 批处理执行
  - `spawn_agents_on_csv_dedupes_item_ids` - 重复 ID 去重
  - `spawn_agents_on_csv_stop_halts_future_items` - 停止信号处理

#### 2.1.6 Hooks 测试 (`hooks.rs`)
- **目的**: 验证 Codex Hooks 系统
- **关键测试**:
  - `stop_hook_can_block_multiple_times_in_same_turn` - Stop Hook 多次拦截
  - `session_start_hook_sees_materialized_transcript_path` - Session Start Hook
  - `blocked_user_prompt_submit_persists_additional_context` - UserPromptSubmit Hook

#### 2.1.7 技能系统测试 (`skills.rs`)
- **目的**: 验证 Skill 加载和注入
- **关键测试**:
  - `user_turn_includes_skill_instructions` - Skill 指令注入
  - `list_skills_includes_system_cache_entries` - 系统 Skill 缓存

#### 2.1.8 Shell 命令测试 (`shell_command.rs`)
- **目的**: 验证 shell_command 工具
- **关键测试**:
  - `shell_command_works` - 基础命令执行
  - `shell_command_times_out_with_timeout_ms` - 超时处理
  - `unicode_output` - Unicode 支持

### 2.2 平台特定测试

| 平台 | 测试文件 | 说明 |
|------|---------|------|
| macOS | `exec.rs`, `seatbelt.rs` | Seatbelt 沙箱测试 |
| Linux | `exec_policy.rs` | Landlock/seccomp 策略测试 |
| Non-Windows | `approvals.rs`, `hooks.rs` | 需要完整沙箱支持 |

---

## 具体技术实现

### 3.1 测试基础设施

#### 3.1.1 TestCodexBuilder 模式

```rust
// codex-rs/core/tests/common/test_codex.rs
pub struct TestCodexBuilder {
    config_mutators: Vec<Box<ConfigMutator>>,
    auth: CodexAuth,
    pre_build_hooks: Vec<Box<PreBuildHook>>,
    home: Option<Arc<TempDir>>,
    user_shell_override: Option<Shell>,
}
```

**关键方法**:
- `with_config()` - 修改 Config
- `with_model()` - 指定测试模型
- `with_pre_build_hook()` - 在构建前执行文件操作
- `build()` - 构建 TestCodex 实例
- `resume()` - 从 rollout 文件恢复会话

#### 3.1.2 Mock 服务器响应

```rust
// codex-rs/core/tests/common/responses.rs
pub fn sse(events: Vec<Value>) -> String {
    // 将 JSON 事件转换为 SSE 格式
    // event: response.output_item.done
    // data: {"type": "message", ...}
}

pub async fn mount_sse_once(server: &MockServer, body: String) -> ResponseMock {
    // 挂载一次性 SSE 响应
}

pub async fn mount_sse_sequence(server: &MockServer, bodies: Vec<String>) -> ResponseMock {
    // 挂载顺序响应序列
}
```

**常用事件构造器**:
- `ev_response_created(id)` - 响应创建事件
- `ev_completed(id)` - 响应完成事件
- `ev_assistant_message(id, text)` - 助手消息事件
- `ev_function_call(call_id, name, args)` - 函数调用事件
- `ev_reasoning_item(id, summary, raw)` - 推理事件

#### 3.1.3 事件等待机制

```rust
// codex-rs/core/tests/common/lib.rs
pub async fn wait_for_event<F>(
    codex: &CodexThread,
    predicate: F,
) -> EventMsg
where
    F: FnMut(&EventMsg) -> bool,
{
    // 轮询 Codex 事件流，直到匹配条件
}

pub async fn wait_for_event_match<T, F>(codex: &CodexThread, matcher: F) -> T
where
    F: Fn(&EventMsg) -> Option<T>,
{
    // 等待并返回匹配的事件数据
}
```

### 3.2 典型测试模式

#### 3.2.1 基础交互测试模式

```rust
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn example_test() -> Result<()> {
    skip_if_no_network!(Ok(()));

    // 1. 启动 Mock 服务器
    let server = start_mock_server().await;

    // 2. 挂载预期响应
    let mock = mount_sse_once(
        &server,
        sse(vec![
            ev_response_created("resp-1"),
            ev_function_call("call-1", "shell", &args),
            ev_completed("resp-1"),
        ]),
    ).await;

    // 3. 构建测试 Codex
    let mut builder = test_codex().with_model("gpt-5");
    let test = builder.build(&server).await?;

    // 4. 提交用户输入
    test.submit_turn("run command").await?;

    // 5. 验证请求
    let request = mock.single_request();
    let output = request.function_call_output_text("call-1");
    assert!(output.contains("expected"));

    Ok(())
}
```

#### 3.2.2 多轮对话测试模式

```rust
// 使用响应序列测试多轮对话
let request_log = mount_sse_sequence(&server, vec![
    sse(vec![ev_assistant_message("m1", "reply1"), ev_completed("r1")]),
    sse(vec![ev_assistant_message("m2", "reply2"), ev_completed("r2")]),
]).await;

// 执行多轮对话
test.submit_turn("turn 1").await?;
test.submit_turn("turn 2").await?;

// 验证所有请求
let requests = request_log.requests();
assert_eq!(requests.len(), 2);
```

#### 3.2.3 会话恢复测试模式

```rust
// 创建 rollout 文件
let rollout = vec![
    RolloutLine { timestamp, item: RolloutItem::SessionMeta(...) },
    RolloutLine { timestamp, item: RolloutItem::ResponseItem(...) },
];
// 写入文件...

// 从 rollout 恢复
let resumed = builder.resume(&server, home, rollout_path).await?;
resumed.submit_turn("continue").await?;
```

### 3.3 关键数据结构

#### 3.3.1 ResponsesRequest

```rust
// codex-rs/core/tests/common/responses.rs
#[derive(Debug, Clone)]
pub struct ResponsesRequest(wiremock::Request);

impl ResponsesRequest {
    pub fn body_json(&self) -> Value;           // 获取请求体 JSON
    pub fn input(&self) -> Vec<Value>;          // 获取 input 数组
    pub fn message_input_texts(&self, role: &str) -> Vec<String>;  // 提取消息文本
    pub fn function_call_output(&self, call_id: &str) -> Value;    // 获取函数输出
    pub fn header(&self, name: &str) -> Option<String>;            // 获取请求头
}
```

#### 3.3.2 ResponseMock

```rust
#[derive(Debug, Clone)]
pub struct ResponseMock {
    requests: Arc<Mutex<Vec<ResponsesRequest>>>,
}

impl ResponseMock {
    pub fn single_request(&self) -> ResponsesRequest;  // 获取唯一请求
    pub fn requests(&self) -> Vec<ResponsesRequest>;   // 获取所有请求
    pub fn last_request(&self) -> Option<ResponsesRequest>;
}
```

---

## 关键代码路径与文件引用

### 4.1 测试入口点

| 文件 | 作用 |
|------|------|
| `codex-rs/core/tests/all.rs` | 测试二进制入口，聚合 suite 模块 |
| `codex-rs/core/tests/suite/mod.rs` | 测试模块聚合，定义 CODEX_ALIASES_TEMP_DIR |
| `codex-rs/core/tests/responses_headers.rs` | 独立测试：验证 SubAgent Header |

### 4.2 测试支持库

| 文件 | 作用 |
|------|------|
| `codex-rs/core/tests/common/lib.rs` | 核心测试工具：wait_for_event, skip_if_no_network! |
| `codex-rs/core/tests/common/test_codex.rs` | TestCodexBuilder, TestCodex, TestCodexHarness |
| `codex-rs/core/tests/common/responses.rs` | SSE 响应构造、Mock 服务器、ResponseMock |
| `codex-rs/core/tests/common/streaming_sse.rs` | 流式 SSE 测试服务器 |
| `codex-rs/core/tests/common/context_snapshot.rs` | 上下文快照测试工具 |

### 4.3 核心被测代码

| 被测模块 | 对应测试文件 | 核心实现文件 |
|---------|-------------|-------------|
| CodexThread | `client.rs` | `codex-rs/core/src/codex.rs` |
| ModelClient | `client.rs` | `codex-rs/core/src/client.rs` |
| Compact | `compact.rs` | `codex-rs/core/src/compact.rs` |
| Tool Router | `tools.rs` | `codex-rs/core/src/tools/router.rs` |
| Shell Tool | `shell_command.rs` | `codex-rs/core/src/tools/handlers/shell.rs` |
| Agent Jobs | `agent_jobs.rs` | `codex-rs/core/src/tools/handlers/agent_jobs.rs` |
| Hooks | `hooks.rs` | `codex-rs/core/src/hook_runtime.rs` |
| Skills | `skills.rs` | `codex-rs/core/src/skills/` |

### 4.4 测试配置与条件编译

```rust
// codex-rs/core/tests/suite/mod.rs
#[cfg(not(target_os = "windows"))]
mod abort_tasks;
mod agent_jobs;
// ...
#[cfg(not(target_os = "windows"))]
mod request_permissions;
```

**平台条件**:
- `#[cfg(not(target_os = "windows"))]` - 需要 Unix 沙箱支持
- `#[cfg(target_os = "macos")]` - macOS Seatbelt 特有测试

---

## 依赖与外部交互

### 5.1 测试依赖图

```
codex-core (dev-dependencies)
    ├── core_test_support (workspace)
    │       ├── codex_core
    │       ├── wiremock
    │       ├── tokio
    │       └── tempfile
    ├── wiremock
    ├── tokio (rt-multi-thread)
    ├── tempfile
    ├── pretty_assertions
    ├── test-case
    └── zstd
```

### 5.2 外部系统交互

| 外部系统 | 交互方式 | 说明 |
|---------|---------|------|
| OpenAI API | wiremock::MockServer | 完全模拟，无真实网络请求 |
| 文件系统 | tempfile::TempDir | 每个测试隔离的临时目录 |
| 沙箱 (macOS) | /usr/bin/sandbox-exec | 真实 Seatbelt 沙箱测试 |
| 沙箱 (Linux) | codex-linux-sandbox | 真实 Landlock/seccomp 测试 |
| 网络 | skip_if_no_network! | 沙箱环境下跳过网络测试 |

### 5.3 环境变量控制

| 环境变量 | 用途 |
|---------|------|
| `CODEX_SANDBOX_NETWORK_DISABLED` | 禁用网络测试 |
| `CODEX_SANDBOX` | 标识沙箱类型 (seatbelt) |
| `INSTA_WORKSPACE_ROOT` | 快照测试工作区根目录 |
| `CODEX_HOME` | 测试隔离的 Codex 主目录 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台差异风险

```rust
// 问题：Windows 与 Unix 的 shell 行为差异
#[cfg(windows)]
const DEFAULT_SHELL_TIMEOUT_MS: i64 = 7_000;
#[cfg(not(windows))]
const DEFAULT_SHELL_TIMEOUT_MS: i64 = 2_000;
```

**风险**: 部分测试在 Windows 上被完全跳过，可能导致平台特定 bug 未被发现。

#### 6.1.2 时序敏感测试

```rust
// hooks.rs 中的流式测试
let (gate_completed_tx, gate_completed_rx) = oneshot::channel();
// ... 使用 gate 控制 SSE 流时序
```

**风险**: 依赖 sleep 和超时的测试可能在 CI 环境中不稳定。

#### 6.1.3 沙箱环境限制

```rust
#[ctor]
pub static CODEX_ALIASES_TEMP_DIR: TestCodexAliasesGuard = unsafe {
    // 在沙箱中运行时，某些测试必须跳过
};
```

**风险**: 当 `CODEX_SANDBOX=seatbelt` 时，大量测试被跳过，覆盖率下降。

### 6.2 边界情况

#### 6.2.1 Token 限制边界

```rust
// compact.rs
let token_count_used = 270_000;
let token_count_used_after_compaction = 80000;
```

**边界**: 自动 compact 触发阈值附近的精确行为。

#### 6.2.2 并发边界

```rust
// agent_jobs.rs
let args = json!({
    "max_concurrency": 1,  // 测试最小并发
});
```

#### 6.2.3 超时边界

```rust
// shell_command.rs
let timeout_ms = 50u64;  // 测试极短超时
```

### 6.3 改进建议

#### 6.3.1 测试组织优化

| 建议 | 优先级 | 说明 |
|------|--------|------|
| 按功能分目录 | 中 | 将 ~90 个测试文件按功能分组到子目录 |
| 提取通用模式 | 高 | 将重复的响应序列提取为 fixtures |
| 统一超时配置 | 中 | 集中管理测试超时，支持 CI 环境调整 |

#### 6.3.2 覆盖率提升

```rust
// 建议：增加错误路径测试
pub async fn mount_sse_error(server: &MockServer, error: ErrorResponse) -> ResponseMock {
    // 专门用于测试错误处理的 mock 辅助函数
}
```

#### 6.3.3 性能优化

```rust
// 建议：并行测试执行优化
// 当前：#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
// 优化：使用 cargo-nextest 实现进程级并行
```

#### 6.3.4 可维护性改进

| 建议 | 当前状态 | 改进方案 |
|------|---------|---------|
| 魔术字符串 | 分散在各测试 | 集中定义常量 (FIRST_REPLY, SUMMARY_TEXT) |
| 响应构造 | 内联 JSON | 使用类型安全的构造器 |
| 断言消息 | 简单 assert | 使用 pretty_assertions 提供清晰 diff |

### 6.4 技术债务

1. **遗留格式支持**: `resume_replays_legacy_js_repl_image_rollout_shapes` 等测试维护历史兼容性，需定期评估是否可移除。

2. **平台条件编译**: 大量 `#[cfg(not(target_os = "windows"))]` 导致 Windows 测试覆盖率不足，考虑使用条件编译抽象。

3. **测试数据管理**: 快照文件 (`snapshots/*.snap`) 与代码变更的同步需要手动维护。

---

## 附录：测试文件完整列表

### 核心功能测试
- `client.rs` - 客户端基础功能
- `client_websockets.rs` - WebSocket 连接
- `cli_stream.rs` - CLI 流式输出
- `tools.rs` - 工具调用综合测试

### 工具特定测试
- `shell_command.rs` - shell_command 工具
- `user_shell_cmd.rs` - 用户 shell 命令
- `read_file.rs` - 文件读取
- `list_dir.rs` - 目录列表
- `grep_files.rs` - 文件搜索
- `apply_patch_cli.rs` - 补丁应用
- `search_tool.rs` - 工具搜索

### 状态与持久化
- `resume.rs` - 会话恢复
- `compact.rs` - 上下文压缩
- `compact_remote.rs` - 远程压缩
- `compact_resume_fork.rs` - 压缩后恢复
- `undo.rs` - 撤销操作
- `turn_state.rs` - 回合状态

### 安全与沙箱
- `seatbelt.rs` - macOS Seatbelt
- `exec.rs` - 命令执行
- `exec_policy.rs` - 执行策略
- `approvals.rs` - 审批流程
- `request_permissions.rs` - 权限请求

### 多代理与任务
- `agent_jobs.rs` - Agent 批处理任务
- `hierarchical_agents.rs` - 层级代理
- `subagent_notifications.rs` - 子代理通知
- `spawn_agent_description.rs` - 代理描述

### 配置与扩展
- `skills.rs` - Skill 系统
- `hooks.rs` - Hook 系统
- `plugins.rs` - 插件系统
- `personality.rs` - 个性化配置
- `model_switching.rs` - 模型切换

### 网络与认证
- `auth_refresh.rs` - 认证刷新
- `websocket_fallback.rs` - WebSocket 降级
- `request_compression.rs` - 请求压缩
- `quota_exceeded.rs` - 配额超限

### 其他
- `sqlite_state.rs` - SQLite 状态存储
- `memories.rs` - 记忆系统
- `otel.rs` - OpenTelemetry 遥测
- `text_encoding_fix.rs` - 文本编码
