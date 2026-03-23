# session-start.command.output.schema.json 研究文档

## 场景与职责

`session-start.command.output.schema.json` 是 Codex Hooks 系统中 **SessionStart** 事件的命令输出 JSON Schema 定义文件。它定义了外部钩子命令执行完成后，向 Codex 返回的输出数据结构。

与输入 Schema 不同，输出 Schema 采用更宽松的设计：大部分字段有默认值，且仅 `hookSpecificOutput.hookEventName` 是必需的。这种设计允许钩子以简单方式返回结果（纯文本或最小 JSON）。

## 功能点目的

### 核心功能
1. **钩子响应标准化**: 定义钩子可以返回的控制指令和数据
2. **流程控制**: 通过 `continue` 字段允许钩子中断会话启动流程
3. **上下文注入**: 通过 `additionalContext` 向模型注入额外上下文信息
4. **用户通知**: 通过 `systemMessage` 向用户显示警告或信息
5. **输出抑制**: 通过 `suppressOutput` 控制钩子输出的显示

### Schema 设计特点
- **宽松默认值**: `continue` 默认为 `true`，`suppressOutput` 默认为 `false`
- **可选字段为主**: 只有 `hookEventName` 是必需的
- **嵌套结构**: 使用 `hookSpecificOutput` 包装特定于事件的输出

## 具体技术实现

### 数据结构定义

```json
{
  "properties": {
    "continue": { "default": true, "type": "boolean" },
    "hookSpecificOutput": {
      "allOf": [{ "$ref": "#/definitions/SessionStartHookSpecificOutputWire" }],
      "default": null
    },
    "stopReason": { "default": null, "type": "string" },
    "suppressOutput": { "default": false, "type": "boolean" },
    "systemMessage": { "default": null, "type": "string" }
  }
}

// 嵌套定义
"SessionStartHookSpecificOutputWire": {
  "properties": {
    "additionalContext": { "default": null, "type": "string" },
    "hookEventName": { "$ref": "#/definitions/HookEventNameWire" }
  },
  "required": ["hookEventName"]
}

"HookEventNameWire": {
  "enum": ["SessionStart", "UserPromptSubmit", "Stop"],
  "type": "string"
}
```

### 输出解析流程

1. **解析入口** (`codex-rs/hooks/src/engine/output_parser.rs`):
   ```rust
   pub(crate) fn parse_session_start(stdout: &str) -> Option<SessionStartOutput> {
       let wire: SessionStartCommandOutputWire = parse_json(stdout)?;
       let additional_context = wire
           .hook_specific_output
           .and_then(|output| output.additional_context);
       Some(SessionStartOutput {
           universal: UniversalOutput::from(wire.universal),
           additional_context,
       })
   }
   ```

2. **结果处理** (`codex-rs/hooks/src/events/session_start.rs`):
   - 解析 `systemMessage` 并记录为 Warning 类型条目
   - 提取 `additionalContext` 注入到模型上下文
   - 检查 `continue` 字段，若为 `false` 则停止会话启动
   - 处理 `stopReason` 作为停止原因说明

3. **降级处理策略**:
   - 空输出: 静默忽略
   - 纯文本输出: 视为 `additionalContext` 注入模型
   - 无效 JSON: 标记为 Failed 状态
   - 有效 JSON: 按 Schema 解析并处理

### 输出处理状态机

```
┌─────────────────┐
│   Hook 执行完成  │
└────────┬────────┘
         ▼
┌─────────────────┐     ┌─────────────────┐
│  stdout 为空？   │──Yes──►│   静默忽略      │
└────────┬────────┘     └─────────────────┘
         │ No
         ▼
┌─────────────────┐     ┌─────────────────┐
│  是有效 JSON？   │──No───►│ 纯文本作为上下文 │
└────────┬────────┘     └─────────────────┘
         │ Yes
         ▼
┌─────────────────┐
│ 按 Schema 解析   │
└────────┬────────┘
         ▼
┌─────────────────┐     ┌─────────────────┐
│ continue=false? │──Yes──►│ 停止会话启动    │
└────────┬────────┘     └─────────────────┘
         │ No
         ▼
┌─────────────────┐
│ 提取并注入上下文 │
└─────────────────┘
```

## 关键代码路径与文件引用

### Schema 生成
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` (77-93行) | `SessionStartCommandOutputWire` 结构体定义 |
| `codex-rs/hooks/src/schema.rs` (85-92行) | `SessionStartHookSpecificOutputWire` 嵌套结构 |
| `codex-rs/hooks/src/schema.rs` (50-62行) | `HookUniversalOutputWire` 通用输出结构 |

### 输出解析
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/output_parser.rs` (38-47行) | `parse_session_start()` 解析函数 |
| `codex-rs/hooks/src/events/session_start.rs` (139-235行) | `parse_completed()` 结果处理逻辑 |

### 测试覆盖
| 文件 | 测试内容 |
|------|----------|
| `codex-rs/hooks/src/events/session_start.rs` (261-321行) | `plain_stdout_becomes_model_context` 纯文本测试 |
| `codex-rs/hooks/src/events/session_start.rs` (287-321行) | `continue_false_preserves_context_for_later_turns` 停止流程测试 |
| `codex-rs/hooks/src/events/session_start.rs` (323-351行) | `invalid_json_like_stdout_fails_instead_of_becoming_model_context` 错误处理测试 |

## 依赖与外部交互

### 上游依赖
1. **schemars**: Schema 生成
2. **serde**: 反序列化配置
   - `#[serde(flatten)]`: 展平通用输出字段
   - `#[serde(default)]`: 提供默认值
   - `#[serde(deny_unknown_fields)]`: 拒绝未知字段

### 下游消费者
1. **外部钩子命令**: 按此 Schema 格式返回 JSON
2. **ClaudeHooksEngine**: 解析输出并影响会话启动流程

### 与输入 Schema 的关系
```
session-start.command.input.schema.json
    ↓ (触发)
External Hook Command
    ↓ (返回符合)
session-start.command.output.schema.json
    ↓ (解析为)
SessionStartOutput (Rust 结构)
    ↓ (影响)
SessionStartOutcome (流程决策)
```

### 通用输出复用
`HookUniversalOutputWire` 被多个输出 Schema 复用：
- `session-start.command.output.schema.json`
- `user-prompt-submit.command.output.schema.json`
- `stop.command.output.schema.json`

## 风险、边界与改进建议

### 当前风险

1. **additionalProperties: false 的严格性**:
   - 虽然 Schema 禁止额外属性，但解析代码使用 `serde(deny_unknown_fields)` 也会拒绝未知字段
   - 风险: 向后兼容性差，新增字段会导致旧钩子失败

2. **纯文本与 JSON 的歧义**:
   - 以 `{` 或 `[` 开头的纯文本会被误判为 JSON 尝试解析
   - 位置: `events/session_start.rs` 第 190-195 行
   - 示例: 钩子输出 `{note: remember to check this}`（非标准 JSON）会被视为错误

3. **空字符串处理不一致**:
   - `additionalContext` 为空字符串时仍会被注入模型上下文
   - 建议: 添加 `trim().is_empty()` 检查

### 边界情况

1. **超大输出**: 无输出大小限制，可能导致内存问题
2. **多字节字符**: JSON 解析使用 UTF-8，但未验证外部钩子输出编码
3. **并发执行**: 多个 SessionStart 钩子并发执行，输出按声明顺序聚合

### 改进建议

1. **向后兼容设计**:
   ```rust
   // 建议: 移除 deny_unknown_fields 或添加版本字段
   #[serde(deny_unknown_fields)]  // 当前严格模式
   // 改为:
   #[serde(default)]  // 忽略未知字段
   ```

2. **纯文本标记**:
   ```json
   {
     "_format": "text",
     "content": "{this is not json}"
   }
   ```
   或支持显式内容类型声明

3. **输出大小限制**:
   ```rust
   const MAX_HOOK_OUTPUT_SIZE: usize = 1024 * 1024; // 1MB
   ```

4. **增强验证**:
   ```rust
   // 对 additionalContext 进行空值检查
   if let Some(context) = additional_context {
       if !context.trim().is_empty() {
           additional_contexts_for_model.push(context);
       }
   }
   ```

5. **Schema 文档化**:
   ```json
   "additionalContext": {
     "type": "string",
     "description": "Additional context to inject into the model's prompt. Will be visible to the AI but not the user directly."
   }
   ```

6. **测试增强**:
   - 添加大输出压力测试
   - 添加编码边界测试（UTF-8/ASCII 混合）
   - 添加并发执行顺序验证测试

### 相关测试用例分析

| 测试名称 | 验证场景 | 代码位置 |
|----------|----------|----------|
| `plain_stdout_becomes_model_context` | 纯文本输出正确解析为上下文 | session_start.rs:261 |
| `continue_false_preserves_context_for_later_turns` | continue=false 时仍保留上下文 | session_start.rs:287 |
| `invalid_json_like_stdout_fails_instead_of_becoming_model_context` | 类 JSON 无效输出正确处理为错误 | session_start.rs:323 |

这些测试展示了三种输出处理路径，覆盖了主要的使用场景。
