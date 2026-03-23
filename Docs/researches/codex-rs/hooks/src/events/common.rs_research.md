# common.rs 研究文档

## 场景与职责

`common.rs` 是 Codex Hooks 事件处理模块的共享工具库，为 `session_start`、`stop` 和 `user_prompt_submit` 三个事件处理模块提供通用辅助函数。该模块位于事件处理流程的下游，主要负责：

1. **文本处理**：合并多段文本、清理空字符串
2. **上下文管理**：收集和展平来自多个 hook 的附加上下文
3. **错误处理**：为序列化失败场景生成统一的 hook 完成事件

## 功能点目的

### 1. `join_text_chunks` - 文本块合并

将多个字符串段落用 `"\n\n"` 连接成单个字符串，用于聚合多个 hook 的阻塞原因或继续提示。

**使用场景**：
- `stop.rs` 中合并多个 hook 的 `block_reason` 和 `continuation_prompt`
- 当多个 hook 同时触发阻塞决策时，整合所有原因信息

### 2. `trimmed_non_empty` - 非空字符串提取

去除字符串首尾空白后，仅当结果非空时返回 `Some(trimmed)`，否则返回 `None`。

**使用场景**：
- 验证 hook 返回的 `reason` 字段是否有效
- 过滤掉仅包含空白字符的 stderr 输出

### 3. `append_additional_context` - 添加上下文条目

将附加上下文同时添加到：
- `entries`: Hook 输出条目列表（用于 UI 展示）
- `additional_contexts_for_model`: 模型上下文列表（用于传递给 LLM）

**使用场景**：
- `session_start.rs` 和 `user_prompt_submit.rs` 处理 hook 返回的 `additionalContext`
- 确保上下文既展示给用户，又传递给模型

### 4. `flatten_additional_contexts` - 展平上下文集合

将多个上下文字符串切片迭代器展平为单个 `Vec<String>`，用于聚合多个 handler 的结果。

**使用场景**：
- 在事件处理结束时，收集所有匹配 handler 产生的附加上下文

### 5. `serialization_failure_hook_events` - 序列化失败事件生成

当输入 JSON 序列化失败时，为所有匹配的 handlers 生成失败状态的 `HookCompletedEvent`。

**关键设计**：
- 保持与正常执行相同的 handler 覆盖范围
- 统一错误信息格式
- 设置零持续时间（`duration_ms: 0`）和相同起止时间

## 具体技术实现

### 数据结构依赖

```rust
// 来自 codex_protocol::protocol
HookCompletedEvent {
    turn_id: Option<String>,
    run: HookRunSummary,
}

HookRunSummary {
    id: String,
    event_name: HookEventName,
    handler_type: HookHandlerType,
    execution_mode: HookExecutionMode,
    scope: HookScope,
    source_path: PathBuf,
    display_order: i64,
    status: HookRunStatus,  // Running | Completed | Failed | Stopped | Blocked
    status_message: Option<String>,
    started_at: i64,
    completed_at: Option<i64>,
    duration_ms: Option<i64>,
    entries: Vec<HookOutputEntry>,
}

HookOutputEntry {
    kind: HookOutputEntryKind,  // Warning | Stop | Feedback | Context | Error
    text: String,
}
```

### 关键流程

```
序列化失败处理流程:
┌─────────────────┐
│ 序列化失败       │
└────────┬────────┘
         ▼
┌─────────────────────────────┐
│ serialization_failure_hook_events │
│ - 遍历所有 matched handlers  │
│ - 调用 dispatcher::running_summary │
│ - 修改 status 为 Failed     │
│ - 添加 Error 类型 entry     │
└────────┬────────────────────┘
         ▼
┌─────────────────┐
│ 返回失败事件列表 │
└─────────────────┘
```

## 关键代码路径与文件引用

### 内部依赖

| 函数 | 依赖模块 | 说明 |
|------|----------|------|
| `serialization_failure_hook_events` | `crate::engine::dispatcher` | 调用 `running_summary` 生成基础事件结构 |

### 被调用方

| 调用者 | 文件路径 | 调用场景 |
|--------|----------|----------|
| `session_start::run` | `events/session_start.rs:103` | SessionStartCommandInput 序列化失败 |
| `stop::run` | `events/stop.rs:92` | StopCommandInput 序列化失败 |
| `user_prompt_submit::run` | `events/user_prompt_submit.rs:91` | UserPromptSubmitCommandInput 序列化失败 |

### 外部协议类型

- `codex_protocol::protocol::HookCompletedEvent`
- `codex_protocol::protocol::HookOutputEntry`
- `codex_protocol::protocol::HookOutputEntryKind`
- `codex_protocol::protocol::HookRunStatus`

## 依赖与外部交互

### 模块依赖图

```
common.rs
├── codex_protocol::protocol::*  (协议类型)
└── crate::engine::dispatcher    (事件生成)
    └── running_summary()
```

### 与事件处理模块的关系

```
┌─────────────────────────────────────────┐
│           events/ 模块                   │
│  ┌─────────────┐ ┌─────────┐ ┌────────┐ │
│  │session_start│ │  stop   │ │user_   │ │
│  │             │ │         │ │prompt  │ │
│  └──────┬──────┘ └────┬────┘ └───┬────┘ │
│         └─────────────┼──────────┘       │
│                       ▼                  │
│              ┌─────────────┐             │
│              │  common.rs  │             │
│              │ (共享工具)   │             │
│              └─────────────┘             │
└─────────────────────────────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **零持续时间语义**
   - `serialization_failure_hook_events` 中设置 `duration_ms: 0`
   - 这可能与真实执行的 hook 区分不明显，建议设为 `None` 或负数标记

2. **错误信息单一**
   - 所有 handlers 收到相同的错误信息副本
   - 无法区分是哪个 handler 的配置导致问题（实际上都是同一输入序列化失败）

### 边界情况

1. **空 chunks 处理**
   ```rust
   // join_text_chunks 对空 vec 返回 None，符合预期
   join_text_chunks(vec![]) -> None
   ```

2. **空白字符串处理**
   ```rust
   // trimmed_non_empty 对纯空白返回 None
   trimmed_non_empty("   \n\t  ") -> None
   ```

### 改进建议

1. **添加日志记录**
   - 序列化失败时应记录详细错误，便于调试配置问题

2. **考虑使用宏**
   - `serialization_failure_hook_events` 模式在三处重复，可考虑宏简化

3. **类型安全增强**
   - `flatten_additional_contexts` 接受 `&'a [String]` 迭代器，可考虑更具体的类型包装

4. **文档完善**
   - 建议为每个函数添加使用示例，特别是 `append_additional_context` 的双列表操作
