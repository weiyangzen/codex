# user-prompt-submit.command.output.schema.json 研究文档

## 场景与职责

`user-prompt-submit.command.output.schema.json` 是 Codex Hooks 系统中 **UserPromptSubmit** 事件的命令输出 JSON Schema 定义文件。它定义了外部钩子命令在处理用户提示提交后，向 Codex 返回的输出数据结构。

UserPromptSubmit 输出 Schema 是最复杂的输出 Schema，它同时支持：
1. **Block 决策**（阻止提示提交）
2. **上下文注入**（向模型添加额外信息）
3. **流程控制**（停止处理）

这使得它成为实现输入过滤、提示增强和安全检查的核心机制。

## 功能点目的

### 核心功能
1. **阻止提交**: 通过 `decision: "block"` 阻止用户提示到达模型
2. **阻止原因**: 通过 `reason` 说明为什么阻止
3. **上下文注入**: 通过 `additionalContext` 向模型添加背景信息
4. **流程控制**: 通过 `continue` 完全停止处理流程
5. **系统消息**: 向用户显示警告或信息

### 与 Stop 输出的区别

| 特性 | UserPromptSubmit Output | Stop Output |
|------|------------------------|-------------|
| Block 决策 | ✅ | ✅ |
| 上下文注入 | ✅ `additionalContext` | ❌ |
| hookSpecificOutput | ✅ | ❌ |
| 用途 | 输入审查+增强 | 停止确认 |

## 具体技术实现

### 数据结构定义

```json
{
  "definitions": {
    "BlockDecisionWire": { "enum": ["block"], "type": "string" },
    "HookEventNameWire": {
      "enum": ["SessionStart", "UserPromptSubmit", "Stop"],
      "type": "string"
    },
    "UserPromptSubmitHookSpecificOutputWire": {
      "properties": {
        "additionalContext": { "default": null, "type": "string" },
        "hookEventName": { "$ref": "#/definitions/HookEventNameWire" }
      },
      "required": ["hookEventName"]
    }
  },
  "properties": {
    "continue": { "default": true, "type": "boolean" },
    "decision": {
      "allOf": [{ "$ref": "#/definitions/BlockDecisionWire" }],
      "default": null
    },
    "hookSpecificOutput": {
      "allOf": [{ "$ref": "#/definitions/UserPromptSubmitHookSpecificOutputWire" }],
      "default": null
    },
    "reason": { "default": null, "type": "string" },
    "stopReason": { "default": null, "type": "string" },
    "suppressOutput": { "default": false, "type": "boolean" },
    "systemMessage": { "default": null, "type": "string" }
  }
}
```

### Rust 结构体定义

```rust
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[schemars(rename = "user-prompt-submit.command.output")]
pub(crate) struct UserPromptSubmitCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub hook_specific_output: Option<UserPromptSubmitHookSpecificOutputWire>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
pub(crate) struct UserPromptSubmitHookSpecificOutputWire {
    pub hook_event_name: HookEventNameWire,
    #[serde(default)]
    pub additional_context: Option<String>,
}
```

### 关键流程

1. **输出解析** (`codex-rs/hooks/src/engine/output_parser.rs` 第 49-71 行):
   ```rust
   pub(crate) fn parse_user_prompt_submit(stdout: &str) -> Option<UserPromptSubmitOutput> {
       let wire: UserPromptSubmitCommandOutputWire = parse_json(stdout)?;
       let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
       let invalid_block_reason = if should_block
           && match wire.reason.as_deref() {
               Some(reason) => reason.trim().is_empty(),
               None => true,
           } {
           Some(invalid_block_message("UserPromptSubmit"))
       } else {
           None
       };
       let additional_context = wire
           .hook_specific_output
           .and_then(|output| output.additional_context);
       Some(UserPromptSubmitOutput {
           universal: UniversalOutput::from(wire.universal),
           should_block: should_block && invalid_block_reason.is_none(),
           reason: wire.reason,
           invalid_block_reason,
           additional_context,
       })
   }
   ```

2. **结果处理** (`codex-rs/hooks/src/events/user_prompt_submit.rs` 第 127-258 行):
   - 解析 `decision` 和 `reason`
   - 验证 block 决策必须有非空 reason
   - 提取 `additionalContext` 注入模型上下文
   - 处理 `continue: false`（优先级最高）
   - 处理退出码 2（stderr 作为阻止原因）

3. **上下文注入逻辑**:
   ```rust
   if parsed.invalid_block_reason.is_none()
       && let Some(additional_context) = parsed.additional_context
   {
       common::append_additional_context(
           &mut entries,
           &mut additional_contexts_for_model,
           additional_context,
       );
   }
   ```
   注意：如果存在 `invalid_block_reason`，上下文不会被注入。

4. **决策优先级**:
   ```
   continue: false > decision: block > additionalContext 注入 > 正常完成
   ```

### 退出码语义

| 退出码 | 处理方式 |
|--------|----------|
| 0 | 解析 stdout JSON，处理 block/context |
| 2 | 阻止提交，stderr 内容作为阻止原因 |
| 其他 | 执行失败 |

## 关键代码路径与文件引用

### Schema 生成
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` (94-107行) | `UserPromptSubmitCommandOutputWire` 结构体 |
| `codex-rs/hooks/src/schema.rs` (109-116行) | `UserPromptSubmitHookSpecificOutputWire` 结构体 |

### 输出解析
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/output_parser.rs` (49-71行) | `parse_user_prompt_submit()` 函数 |
| `codex-rs/hooks/src/engine/output_parser.rs` (15-22行) | `UserPromptSubmitOutput` 结构体 |

### 事件处理
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (127-258行) | `parse_completed()` 结果处理 |
| `codex-rs/hooks/src/events/common.rs` (26-36行) | `append_additional_context()` 上下文追加 |

### 测试覆盖
| 文件 | 测试内容 |
|------|----------|
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (284-318行) | `continue_false_preserves_context_for_later_turns` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (320-354行) | `claude_block_decision_blocks_processing` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (356-385行) | `claude_block_decision_requires_reason` |
| `codex-rs/hooks/src/events/user_prompt_submit.rs` (387-411行) | `exit_code_two_blocks_processing` |

## 依赖与外部交互

### 上游依赖
1. **HookUniversalOutputWire**: 通用输出字段
2. **BlockDecisionWire**: Block 决策枚举（与 Stop 共享）
3. **HookEventNameWire**: 事件名枚举（共享定义）
4. **schemars**: Schema 生成

### 下游消费者
1. **外部钩子命令**: 返回 Block 决策或上下文
2. **ClaudeHooksEngine**: 解析输出并决定是否阻止/增强提示

### 与 SessionStart 输出的对比

| 特性 | UserPromptSubmit | SessionStart |
|------|------------------|--------------|
| Block 决策 | ✅ | ❌ |
| 上下文注入 | ✅ | ✅ |
| hookSpecificOutput | ✅ | ✅ |
| reason 字段 | ✅ (block 用) | ❌ |
| 退出码 2 | ✅ (block) | ❌ |

UserPromptSubmit 输出是最全面的，结合了 Block 和上下文注入能力。

## 风险、边界与改进建议

### 当前风险

1. **Block 与 Context 的冲突**:
   - 如果钩子同时返回 `decision: "block"` 和 `additionalContext`
   - 当前逻辑：block 失败时（无 reason）不会注入上下文
   - 但 block 成功时，上下文仍会被注入（在 `continue: true` 时）
   - 风险: 被阻止的提示的上下文可能仍会影响后续处理

2. **additionalContext 大小无限制**:
   - 钩子可以返回任意大小的上下文
   - 风险: 大上下文增加 token 消耗和传输开销

3. **多个钩子的上下文合并**:
   - 多个钩子返回上下文时，按声明顺序合并
   - 无去重机制，可能重复注入相似上下文

4. **reason 和 additionalContext 的混淆**:
   - `reason` 用于 block 时向用户解释
   - `additionalContext` 用于向模型注入信息
   - 钩子开发者可能混淆两者用途

### 边界情况

1. **Block + Context 同时返回**:
   ```json
   {
     "decision": "block",
     "reason": "敏感内容",
     "hookSpecificOutput": {
       "hookEventName": "UserPromptSubmit",
       "additionalContext": "这是敏感内容的说明"
     }
   }
   ```
   当前行为：阻止提交，但上下文仍被注入（如果 continue 为 true）

2. **空 additionalContext**:
   - 空字符串仍会被注入
   - 浪费 token 和处理资源

3. **退出码 2 + JSON 输出**:
   - 退出码 2 时，stdout 中的 JSON 被忽略
   - 即使 JSON 中包含 `additionalContext` 也不会被使用

### 改进建议

1. **Block 时禁用 Context 注入**:
   ```rust
   if parsed.should_block {
       // 阻止提交时，不注入上下文
       // 或者添加标记区分被阻止的上下文
   }
   ```

2. **添加 Context 大小限制**:
   ```rust
   const MAX_CONTEXT_LENGTH: usize = 10000;
   if additional_context.len() > MAX_CONTEXT_LENGTH {
       warn!("Hook returned oversized context, truncating");
       additional_context.truncate(MAX_CONTEXT_LENGTH);
   }
   ```

3. **Context 去重**:
   ```rust
   // 使用 HashSet 去重相似上下文
   let mut seen_contexts: HashSet<u64> = HashSet::new(); // 存储哈希值
   ```

4. **字段文档增强**:
   ```json
   "reason": {
     "type": "string",
     "description": "Human-readable explanation shown to the user when the prompt is blocked. Required when decision is 'block'."
   },
   "additionalContext": {
     "type": "string",
     "description": "Additional context injected into the model's prompt. Visible to AI but not directly to user. Ignored if the prompt is blocked."
   }
   ```

5. **结构化 Context**:
   ```json
   {
     "hookSpecificOutput": {
       "hookEventName": "UserPromptSubmit",
       "additionalContext": {
         "text": "上下文内容",
         "priority": "high",
         "category": "security_check",
         "ttl": 1
       }
     }
   }
   ```

6. **添加 Metrics**:
   ```rust
   // 记录钩子决策统计
   metrics::counter!("hooks.user_prompt_submit.blocked").increment();
   metrics::histogram!("hooks.user_prompt_submit.context_length").record(context_len);
   ```

### 测试覆盖分析

| 测试场景 | 覆盖状态 | 说明 |
|----------|----------|------|
| continue=false + context | ✅ | continue_false_preserves_context_for_later_turns |
| Block 决策 | ✅ | claude_block_decision_blocks_processing |
| Block 无 reason | ✅ | claude_block_decision_requires_reason |
| 退出码 2 | ✅ | exit_code_two_blocks_processing |
| Block + Context 组合 | ⚠️ | 部分覆盖 |
| 空 Context | ❌ | 未明确测试 |
| 大 Context | ❌ | 未覆盖 |
| 多钩子 Context 合并 | ❌ | 未明确测试 |

建议添加针对组合场景和边界值的测试用例。
