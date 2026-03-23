# hooks.rs 深度研究文档

## 场景与职责

`hooks.rs` 是 Codex 核心测试套件中验证 **Hooks（生命周期钩子）** 系统的综合测试文件。Hooks 是 Codex 的扩展机制，允许在关键生命周期点执行自定义逻辑。

测试覆盖的钩子类型：
1. **Stop Hook**：在模型生成响应后执行，可决定是否继续生成
2. **SessionStart Hook**：会话开始时执行，用于初始化
3. **UserPromptSubmit Hook**：用户提交提示时执行，可拦截或修改提示

这些测试确保 Hooks 系统能够：
- 多次拦截和继续对话
- 在恢复会话时保持状态
- 正确处理被阻止的提示队列

## 功能点目的

### 1. Stop Hook（停止钩子）
- **触发时机**：模型生成响应后
- **能力**：
  - 阻止响应（`decision: "block"`）
  - 添加继续提示（`systemMessage`）
  - 在同一会话中多次触发

### 2. SessionStart Hook（会话开始钩子）
- **触发时机**：新会话初始化时
- **能力**：
  - 访问会话元数据（如 `transcript_path`）
  - 执行初始化逻辑

### 3. UserPromptSubmit Hook（用户提示提交钩子）
- **触发时机**：用户提交新提示时
- **能力**：
  - 阻止提示（`decision: "block"`）
  - 添加上下文（`additionalContext`）
  - 记录提示历史

## 具体技术实现

### Hook 配置格式

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "command",
        "command": "python3 /path/to/stop_hook.py",
        "statusMessage": "running stop hook"
      }]
    }],
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "python3 /path/to/prompt_hook.py",
        "statusMessage": "running user prompt submit hook"
      }]
    }],
    "SessionStart": [{
      "hooks": [{
        "type": "command",
        "command": "python3 /path/to/session_hook.py",
        "statusMessage": "running session start hook"
      }]
    }]
  }
}
```

### Hook 运行时 (hook_runtime.rs)

```rust
pub(crate) struct HookRuntimeOutcome {
    pub should_stop: bool,
    pub additional_contexts: Vec<String>,
}

pub(crate) enum PendingInputHookDisposition {
    Accepted(Box<PendingInputRecord>),
    Blocked { additional_contexts: Vec<String> },
}

// 运行 SessionStart Hooks
pub(crate) async fn run_pending_session_start_hooks(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
) -> bool {
    let request = codex_hooks::SessionStartRequest {
        session_id: sess.conversation_id,
        cwd: turn_context.cwd.clone(),
        transcript_path: sess.hook_transcript_path().await,
        model: turn_context.model_info.slug.clone(),
        permission_mode: hook_permission_mode(turn_context),
        source: session_start_source,
    };
    
    let outcome = run_context_injecting_hook(...).await;
    outcome.record_additional_contexts(sess, turn_context).await
}

// 运行 UserPromptSubmit Hooks
pub(crate) async fn run_user_prompt_submit_hooks(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    prompt: String,
) -> HookRuntimeOutcome {
    let request = UserPromptSubmitRequest {
        session_id: sess.conversation_id,
        turn_id: turn_context.sub_id.clone(),
        cwd: turn_context.cwd.clone(),
        transcript_path: sess.hook_transcript_path().await,
        model: turn_context.model_info.slug.clone(),
        permission_mode: hook_permission_mode(turn_context),
        prompt,
    };
    ...
}
```

### Stop Hook 处理流程

```rust
// 1. Hook 输入格式
{
  "turn_id": "...",
  "stop_hook_active": false,  // 首次为 false，后续为 true
  "response": {...}
}

// 2. Hook 输出格式（阻止）
{
  "decision": "block",
  "reason": "需要修改"
}

// 3. Hook 输出格式（继续）
{
  "systemMessage": "继续提示内容"
}
```

### 测试中的 Stop Hook 脚本

```python
import json
from pathlib import Path
import sys

log_path = Path(r"{log_path}")
block_prompts = {prompts_json}

payload = json.load(sys.stdin)
existing = [...]  # 读取已有日志

with log_path.open("a") as handle:
    handle.write(json.dumps(payload) + "\n")

invocation_index = len(existing)
if invocation_index < len(block_prompts):
    print(json.dumps({"decision": "block", "reason": block_prompts[invocation_index]}))
else:
    print(json.dumps({"systemMessage": f"stop hook pass {invocation_index + 1} complete"}))
```

### 被阻止提示的处理

```rust
pub(crate) async fn inspect_pending_input(
    sess: &Arc<Session>,
    turn_context: &Arc<TurnContext>,
    pending_input_item: ResponseInputItem,
) -> PendingInputHookDisposition {
    let response_item = ResponseItem::from(pending_input_item);
    if let Some(TurnItem::UserMessage(user_message)) = parse_turn_item(&response_item) {
        let outcome = run_user_prompt_submit_hooks(sess, turn_context, user_message.message()).await;
        if outcome.should_stop {
            // 阻止提示，但保存上下文供后续使用
            PendingInputHookDisposition::Blocked {
                additional_contexts: outcome.additional_contexts,
            }
        } else {
            PendingInputHookDisposition::Accepted(Box::new(PendingInputRecord::UserMessage {
                content: user_message.content,
                response_item,
                additional_contexts: outcome.additional_contexts,
            }))
        }
    } else {
        PendingInputHookDisposition::Accepted(...)
    }
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/core/tests/suite/hooks.rs` - 本测试文件

### 核心实现
- `codex-rs/core/src/hook_runtime.rs` - Hook 运行时
  - `run_pending_session_start_hooks`
  - `run_user_prompt_submit_hooks`
  - `inspect_pending_input`
  - `record_pending_input`

- `codex-rs/codex-hooks/src/` - Hook 引擎（独立 crate）
  - `SessionStartRequest` / `SessionStartOutcome`
  - `UserPromptSubmitRequest` / `UserPromptSubmitOutcome`
  - Hook 执行器

### 特性标志
- `codex-rs/core/src/features.rs`
  - `Feature::CodexHooks` - 控制 Hooks 功能启用

### 协议类型
- `codex-rs/protocol/src/protocol.rs`
  - `HookStartedEvent`
  - `HookCompletedEvent`
  - `HookRunSummary`

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `codex_hooks` | Hook 引擎 |
| `codex_core::hook_runtime` | Hook 运行时集成 |
| `codex_core::features` | 特性标志 |
| `core_test_support` | 测试基础设施 |

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `python3` | Hook 脚本执行（测试中）|

### 测试基础设施
```rust
// 写 Hook 配置
fn write_stop_hook(home: &Path, block_prompts: &[&str]) -> Result<()> {
    let script_path = home.join("stop_hook.py");
    let log_path = home.join("stop_hook_log.jsonl");
    // 生成 Python 脚本...
    let hooks = serde_json::json!({
        "hooks": {
            "Stop": [{
                "hooks": [{
                    "type": "command",
                    "command": format!("python3 {}", script_path.display()),
                    "statusMessage": "running stop hook",
                }]
            }]
        }
    });
    fs::write(home.join("hooks.json"), hooks.to_string())?;
    Ok(())
}
```

### 特性启用
```rust
let mut builder = test_codex()
    .with_pre_build_hook(|home| {
        write_stop_hook(home, &[FIRST_CONTINUATION_PROMPT, SECOND_CONTINUATION_PROMPT])
            .expect("...");
    })
    .with_config(|config| {
        config.features.enable(Feature::CodexHooks).expect("...");
    });
```

## 风险、边界与改进建议

### 已知风险

1. **Hook 执行超时**
   - 风险：Hook 脚本可能长时间运行或死锁
   - 缓解：应有超时机制（测试中未显式验证）

2. **Hook 链累积**
   - 风险：多次阻止后，继续提示累积可能超出上下文窗口
   - 现状：测试验证 3 次阻止后成功

3. **并发安全**
   - 风险：Hook 日志文件并发写入
   - 现状：测试使用顺序执行避免

### 边界情况

1. **空 Hook 输出**
   - 处理：应视为通过

2. **无效 JSON 输出**
   - 处理：应视为错误并记录

3. **Hook 脚本不存在**
   - 处理：应报告执行错误

4. **被阻止提示的上下文**
   - 验证：`additional_contexts` 应在后续提示中可见
   - 测试：`blocked_user_prompt_submit_persists_additional_context_for_next_turn`

5. **队列中被阻止的提示**
   - 场景：提示 A（接受）→ 提示 B（阻止）→ 提示 C（接受）
   - 验证：B 不应出现在最终请求中
   - 测试：`blocked_queued_prompt_does_not_strand_earlier_accepted_prompt`

### 改进建议

1. **Hook 类型扩展**
   - 添加 PreToolCall / PostToolCall Hooks
   - 添加 PreCompact / PostCompact Hooks

2. **性能优化**
   - Hook 结果缓存
   - 并行执行独立 Hooks

3. **安全性**
   - Hook 脚本签名验证
   - 沙箱化 Hook 执行

4. **调试支持**
   - Hook 执行追踪
   - Hook 性能分析

5. **测试增强**
   - 添加 Hook 超时测试
   - 添加并发 Hook 测试
   - 添加 Hook 错误恢复测试

6. **配置简化**
   - 提供声明式 Hook 配置
   - 内置常用 Hook 模板
