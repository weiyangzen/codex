# stop.command.output.schema.json 研究文档

## 场景与职责

`stop.command.output.schema.json` 是 Codex Hooks 系统中 **Stop** 事件的命令输出 JSON Schema 定义文件。它定义了外部钩子命令在处理停止事件后，向 Codex 返回的输出数据结构。

Stop 输出 Schema 的独特之处在于其支持 **Block 决策** 机制：钩子可以决定阻止停止操作，并要求用户提供继续操作的提示。这是 Stop 事件特有的功能，用于实现"确认停止"或"保存工作"等场景。

## 功能点目的

### 核心功能
1. **流程控制**: 通过 `continue` 字段允许钩子中断停止流程
2. **阻止停止**: 通过 `decision: "block"` 阻止用户停止操作
3. **阻止原因**: 通过 `reason` 字段提供阻止停止的说明
4. **继续提示**: 阻止时向用户显示的反馈信息
5. **通用输出**: 支持系统消息、输出抑制等通用功能

### Block 决策机制

Stop 事件独有的 Block 功能允许钩子：
- 拦截用户的停止请求
- 要求用户确认（如"有未保存的更改，确定要停止吗？"）
- 提供替代操作（如"请先保存文件"）

## 具体技术实现

### 数据结构定义

```json
{
  "definitions": {
    "BlockDecisionWire": {
      "enum": ["block"],
      "type": "string"
    }
  },
  "properties": {
    "continue": { "default": true, "type": "boolean" },
    "decision": {
      "allOf": [{ "$ref": "#/definitions/BlockDecisionWire" }],
      "default": null
    },
    "reason": {
      "default": null,
      "description": "Claude requires `reason` when `decision` is `block`; we enforce that semantic rule during output parsing rather than in the JSON schema.",
      "type": "string"
    },
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
#[schemars(rename = "stop.command.output")]
pub(crate) struct StopCommandOutputWire {
    #[serde(flatten)]
    pub universal: HookUniversalOutputWire,
    #[serde(default)]
    pub decision: Option<BlockDecisionWire>,
    /// Claude requires `reason` when `decision` is `block`; we enforce that
    /// semantic rule during output parsing rather than in the JSON schema.
    #[serde(default)]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
pub(crate) enum BlockDecisionWire {
    #[serde(rename = "block")]
    Block,
}
```

### 关键流程

1. **输出解析** (`codex-rs/hooks/src/engine/output_parser.rs` 第 73-91 行):
   ```rust
   pub(crate) fn parse_stop(stdout: &str) -> Option<StopOutput> {
       let wire: StopCommandOutputWire = parse_json(stdout)?;
       let should_block = matches!(wire.decision, Some(BlockDecisionWire::Block));
       let invalid_block_reason = if should_block
           && match wire.reason.as_deref() {
               Some(reason) => reason.trim().is_empty(),
               None => true,
           } {
           Some(invalid_block_message("Stop"))
       } else {
           None
       };
       Some(StopOutput {
           universal: UniversalOutput::from(wire.universal),
           should_block: should_block && invalid_block_reason.is_none(),
           reason: wire.reason,
           invalid_block_reason,
       })
   }
   ```

2. **结果处理** (`codex-rs/hooks/src/events/stop.rs` 第 122-253 行):
   - 解析 `decision` 和 `reason`
   - 验证 block 决策必须有非空 reason
   - 处理 `continue: false`（优先级高于 block）
   - 处理退出码 2 的特殊语义（stderr 作为阻止原因）

3. **退出码语义**:
   | 退出码 | 含义 |
   |--------|------|
   | 0 | 正常执行，解析 stdout JSON |
   | 2 | 阻止停止，stderr 内容作为阻止原因 |
   | 其他 | 执行失败 |

4. **决策优先级**:
   ```
   continue: false > decision: block > 正常完成
   ```
   如果同时设置 `continue: false` 和 `decision: "block"`，`continue: false` 优先。

### 结果聚合

Stop 事件支持多个钩子，结果通过 `aggregate_results()` 聚合 (`stop.rs` 第 255-290 行):

```rust
fn aggregate_results<'a>(
    results: impl IntoIterator<Item = &'a StopHandlerData>,
) -> StopHandlerData {
    let should_stop = results.iter().any(|result| result.should_stop);
    let stop_reason = results.iter().find_map(|result| result.stop_reason.clone());
    // 只有当 should_stop 为 false 时才考虑 block
    let should_block = !should_stop && results.iter().any(|result| result.should_block);
    // block_reason 和 continuation_prompt 合并多个钩子的原因
    ...
}
```

## 关键代码路径与文件引用

### Schema 生成
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/schema.rs` (118-131行) | `StopCommandOutputWire` 结构体 |
| `codex-rs/hooks/src/schema.rs` (133-137行) | `BlockDecisionWire` 枚举 |

### 输出解析
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/engine/output_parser.rs` (73-91行) | `parse_stop()` 函数 |
| `codex-rs/hooks/src/engine/output_parser.rs` (24-30行) | `StopOutput` 结构体 |

### 事件处理
| 文件 | 职责 |
|------|------|
| `codex-rs/hooks/src/events/stop.rs` (122-253行) | `parse_completed()` 结果处理 |
| `codex-rs/hooks/src/events/stop.rs` (255-290行) | `aggregate_results()` 结果聚合 |

### 测试覆盖
| 文件 | 测试内容 |
|------|----------|
| `codex-rs/hooks/src/events/stop.rs` (319-342行) | `block_decision_with_reason_sets_continuation_prompt` |
| `codex-rs/hooks/src/events/stop.rs` (344-361行) | `block_decision_without_reason_is_invalid` |
| `codex-rs/hooks/src/events/stop.rs` (363-386行) | `continue_false_overrides_block_decision` |
| `codex-rs/hooks/src/events/stop.rs` (388-407行) | `exit_code_two_uses_stderr_feedback_only` |
| `codex-rs/hooks/src/events/stop.rs` (409-424行) | `exit_code_two_without_stderr_does_not_block` |
| `codex-rs/hooks/src/events/stop.rs` (465-493行) | `aggregate_results_concatenates_blocking_reasons` |

## 依赖与外部交互

### 上游依赖
1. **HookUniversalOutputWire**: 通用输出字段（通过 `#[serde(flatten)]` 嵌入）
2. **schemars**: Schema 生成
3. **serde**: 序列化/反序列化

### 下游消费者
1. **外部钩子命令**: 返回 Block 决策以阻止停止
2. **ClaudeHooksEngine**: 解析输出并决定是否阻止停止

### 与 UserPromptSubmit 输出的区别

| 特性 | Stop | UserPromptSubmit |
|------|------|------------------|
| Block 决策 | ✅ 支持 | ✅ 支持 |
| 退出码 2 | ✅ 阻止停止 | ✅ 阻止提交 |
| continue 优先 | ✅ continue > block | ✅ continue > block |
| hookSpecificOutput | ❌ 无 | ✅ 有 |

Stop 输出更简洁，没有 `hookSpecificOutput`，因为它不需要注入额外上下文。

## 风险、边界与改进建议

### 当前风险

1. **reason 验证在解析时而非 Schema 中**:
   - Schema 允许 `decision: "block"` 而不提供 `reason`
   - 实际验证在 `parse_stop()` 中进行
   - 风险: 不符合 Schema 的验证模式，可能导致混淆

2. **空 reason 处理不一致**:
   - 仅 trim 后检查是否为空
   - 纯空白字符的 reason 被视为无效
   - 但 Schema 层面无此限制

3. **多个 Block 决策的合并**:
   - 多个钩子都返回 block 时，原因用 `\n\n` 连接
   - 可能产生过长的 continuation_prompt

### 边界情况

1. **Block + Stop 同时触发**:
   - 一个钩子返回 `continue: false`
   - 另一个钩子返回 `decision: "block"`
   - 结果: Stop 优先，Block 被忽略

2. **退出码 2 + JSON 输出**:
   - 退出码 2 时，stdout 中的 JSON 被完全忽略
   - 仅使用 stderr 内容

3. **超长 reason**:
   - 无长度限制，可能导致 UI 显示问题

### 改进建议

1. **Schema 内嵌验证**:
   ```json
   {
     "if": {
       "properties": { "decision": { "const": "block" } }
     },
     "then": {
       "required": ["reason"],
       "properties": {
         "reason": { "minLength": 1 }
       }
     }
   }
   ```

2. **添加 reason 长度限制**:
   ```rust
   const MAX_BLOCK_REASON_LENGTH: usize = 500;
   ```

3. **结构化 Block 原因**:
   ```json
   {
     "decision": "block",
     "reason": {
       "title": "未保存的更改",
       "message": "您有 3 个未保存的文件",
       "actions": ["保存并退出", "不保存退出", "取消"]
     }
   }
   ```

4. **添加 block 优先级**:
   ```rust
   pub priority: Option<u8>, // 高优先级 block 优先显示
   ```

5. **退出码 2 的 JSON 支持**:
   ```rust
   // 允许退出码 2 时仍解析 stdout JSON
   if exit_code == Some(2) {
       if let Some(parsed) = parse_stop(&run_result.stdout) {
           // 使用 JSON 中的 reason，而非 stderr
       } else {
           // 回退到 stderr
       }
   }
   ```

### 测试覆盖分析

| 测试场景 | 覆盖状态 | 说明 |
|----------|----------|------|
| Block 有 reason | ✅ | block_decision_with_reason_sets_continuation_prompt |
| Block 无 reason | ✅ | block_decision_without_reason_is_invalid |
| continue 覆盖 block | ✅ | continue_false_overrides_block_decision |
| 退出码 2 | ✅ | exit_code_two_uses_stderr_feedback_only |
| 退出码 2 无 stderr | ✅ | exit_code_two_without_stderr_does_not_block |
| 多钩子 Block 合并 | ✅ | aggregate_results_concatenates_blocking_reasons |
| 空白 reason | ✅ | block_decision_with_blank_reason_fails_instead_of_blocking |
| 超长 reason | ❌ | 未覆盖 |
| 特殊字符 reason | ❌ | 未覆盖 |

测试覆盖较全面，但缺少边界值和特殊字符测试。
