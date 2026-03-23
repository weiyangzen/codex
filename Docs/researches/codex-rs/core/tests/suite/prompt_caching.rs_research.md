# prompt_caching.rs 研究文档

## 场景与职责

`prompt_caching.rs` 是 Codex Core 的集成测试套件，专门测试 **Prompt Caching（提示缓存）** 功能。该功能通过维护稳定的 `prompt_cache_key` 和可重用的消息前缀来优化 API 调用，减少重复传输不变的上下文信息，从而降低延迟和成本。

提示缓存是 Codex 性能优化的核心机制，它确保：
- 多轮对话中不变的系统指令和用户指令只发送一次
- 上下文切换（如 model override、policy change）时缓存 key 保持稳定
- 工具列表和指令在多轮之间保持一致

## 功能点目的

### 1. 工具一致性验证
验证多轮对话中工具列表保持一致，不会因轮次变化而产生差异。

### 2. GPT-5 的 apply_patch 指令处理
针对 GPT-5 模型（不支持 apply_patch 工具），验证系统正确追加 apply_patch 指令到基础指令中。

### 3. 前缀缓存一致性
验证多轮对话中，缓存的前缀消息（permissions + contextual user message）被正确重用。

### 4. 上下文覆盖与缓存稳定性
验证通过 `Op::OverrideTurnContext` 修改上下文（如 sandbox policy、model）时：
- `prompt_cache_key` 保持不变
- 前缀消息被重用
- 变更通过增量消息（settings update）通知模型

### 5. 每轮覆盖与缓存
验证通过 `Op::UserTurn` 的每轮参数（per-turn overrides）修改上下文时，同样保持缓存 key 稳定。

### 6. 无变化优化
验证当连续两轮使用完全相同的参数时，不发送冗余的环境上下文更新。

### 7. 首次覆盖的环境上下文
验证在首次对话前发送 `OverrideTurnContext` 时，环境上下文被正确生成。

## 具体技术实现

### 关键数据结构

```rust
// 请求体结构（简化）
{
    "model": "gpt-5.1-codex-max",
    "prompt_cache_key": "stable-key-across-turns",
    "instructions": "...",
    "tools": [...],
    "input": [
        // 0: permissions message (developer role)
        {"role": "developer", "content": [...]},
        // 1: contextual user message (user role)
        {"role": "user", "content": [
            {"type": "input_text", "text": "user instructions"},
            {"type": "input_text", "text": "<environment_context>...</environment_context>"}
        ]},
        // 2+: user messages
        {"type": "message", "role": "user", "content": [...]}
    ]
}
```

### 环境上下文结构

```xml
<environment_context>
  <cwd>/current/working/directory</cwd>
  <shell>zsh</shell>
  <current_date>2026-03-23</current_date>
  <timezone>Asia/Shanghai</timezone>
</environment_context>
```

### 核心测试模式

#### 1. 工具一致性测试

```rust
async fn prompt_tools_are_consistent_across_requests() {
    // 设置：启用 CollaborationModes，配置 user_instructions
    // 第一轮：发送 "hello 1"
    // 第二轮：发送 "hello 2"
    // 验证：
    // - 两轮请求的 tools 列表完全相同
    // - 两轮请求的 instructions 完全相同
}
```

#### 2. 缓存前缀重用测试

```rust
async fn prefixes_context_and_instructions_once_and_consistently_across_requests() {
    // 第一轮请求后获取 input 数组
    let input1 = body1["input"].as_array();
    assert_eq!(input1.len(), 3); // permissions + contextual user + user msg
    
    // 第二轮请求的 input 前缀应与第一轮相同
    let input2 = body2["input"].as_array();
    assert_eq!(&input2[..input1.len()], input1.as_slice());
}
```

#### 3. 覆盖与缓存稳定性测试

```rust
async fn overrides_turn_context_but_keeps_cached_prefix_and_key_constant() {
    // 第一轮：标准对话
    // 发送 OverrideTurnContext { approval_policy: Never, sandbox_policy: ..., effort: High }
    // 第二轮：标准对话
    
    // 验证 prompt_cache_key 相同
    assert_eq!(body1["prompt_cache_key"], body2["prompt_cache_key"]);
    
    // 验证第二轮包含更新的 permissions message
    let expected_permissions_msg_2 = body2["input"][body1_input.len()].clone();
    assert_ne!(expected_permissions_msg_2, expected_permissions_msg);
    
    // 验证前缀重用
    let mut expected_body2 = body1_input.to_vec();
    expected_body2.push(expected_permissions_msg_2);
    expected_body2.push(expected_user_message_2);
    assert_eq!(body2["input"], serde_json::Value::Array(expected_body2));
}
```

### 辅助函数

```rust
// 构建文本用户输入
fn text_user_input(text: String) -> serde_json::Value {
    serde_json::json!({
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": text }]
    })
}

// 验证环境上下文
fn assert_default_env_context(text: &str, cwd: &str, shell: &Shell) {
    assert!(text.starts_with(ENVIRONMENT_CONTEXT_OPEN_TAG));
    assert!(text.contains(&format!("<cwd>{cwd}</cwd>")));
    assert!(text.contains(&format!("<shell>{shell_name}</shell>")));
    assert!(text.contains("<current_date>") && text.contains("</current_date>"));
    assert!(text.contains("<timezone>") && text.contains("</timezone>"));
}

// 验证工具名称列表
fn assert_tool_names(body: &serde_json::Value, expected_names: &[&str]) {
    let actual_names: Vec<String> = body["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t.get("name").or_else(|| t.get("type"))
            .and_then(|v| v.as_str())
            .unwrap()
            .to_string())
        .collect();
    assert_eq!(actual_names, expected_names);
}

// 换行符规范化（处理 Windows/Unix 差异）
fn normalize_newlines(text: &str) -> String {
    text.replace("\r\n", "\n")
}
```

## 依赖与外部交互

### 功能标志

```rust
Feature::CollaborationModes  // 启用协作模式（大部分测试需要）
Feature::ApplyPatchFreeform  // 控制 apply_patch 工具包含
```

### 核心模块依赖

| 模块 | 用途 |
|-----|------|
| `codex_core::shell::default_user_shell` | 获取默认 shell 信息 |
| `codex_protocol::protocol::ENVIRONMENT_CONTEXT_OPEN_TAG` | 环境上下文标签常量 |
| `codex_protocol::protocol::Op::UserInput` / `Op::UserTurn` / `Op::OverrideTurnContext` | 操作类型 |
| `codex_apply_patch::APPLY_PATCH_TOOL_INSTRUCTIONS` | apply_patch 指令常量 |

### 测试工具链

```rust
// Mock SSE 响应
use core_test_support::responses::{
    mount_sse_once, mount_sse_sequence,
    sse, ev_response_created, ev_completed,
    start_mock_server
};

// 测试 Codex 构建器
use core_test_support::test_codex::{test_codex, TestCodex};

// 事件等待
use core_test_support::wait_for_event;
```

### 关键常量

```rust
// 来自 codex_protocol::protocol
ENVIRONMENT_CONTEXT_OPEN_TAG = "<environment_context>"
ENVIRONMENT_CONTEXT_CLOSE_TAG = "</environment_context>"
```

## 风险、边界与改进建议

### 已知边界

1. **平台差异**: 工具列表在 Windows 和非 Windows 平台不同：
   - Windows: `["shell_command"]`
   - 其他: `["exec_command", "write_stdin"]`

2. **模型特定行为**: GPT-5 系列模型不包含 apply_patch 工具，需要特殊处理指令追加。

3. **测试线程数**: 不同测试使用不同 `worker_threads`（2 或 4），这可能影响并发行为测试的稳定性。

### 缓存失效场景

当前测试覆盖的缓存失效/更新场景：
- ✅ Model 切换
- ✅ Approval policy 变更
- ✅ Sandbox policy 变更
- ✅ Reasoning effort 变更
- ✅ CWD 变更

未覆盖的场景：
- ❌ 工具列表变更（动态工具加载）
- ❌ User instructions 变更
- ❌ 系统时间/时区变更

### 改进建议

1. **缓存命中率指标**: 添加测试验证缓存命中统计正确上报。

2. **大负载测试**: 添加测试验证大上下文下的缓存性能和稳定性。

3. **并发覆盖测试**: 添加测试验证多轮同时提交时的缓存一致性。

4. **缓存失效粒度**: 考虑更细粒度的缓存失效策略，避免全量前缀重建。

5. **可视化调试**: 添加调试模式输出缓存 key 和消息结构的详细对比。

### 相关文件引用

- 测试文件: `codex-rs/core/tests/suite/prompt_caching.rs` (1030 行)
- 客户端实现: `codex-rs/core/src/client.rs`
- 客户端公共代码: `codex-rs/core/src/client_common.rs`
- 协议常量: `codex-rs/protocol/src/protocol.rs` (第 82-87 行)
- apply_patch 指令: `codex-rs/apply_patch/src/lib.rs`
