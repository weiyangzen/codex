# session_prefix.rs 深度研究文档

## 场景与职责

`session_prefix.rs` 是 Codex 核心模块中的一个轻量级工具模块，位于 `codex-rs/core/src/` 目录下。其主要职责是格式化与子代理（subagent）相关的会话状态标记消息，这些标记存储在用户角色的消息中，但并非用户意图本身。

该模块解决的核心问题是：在复杂的代理协作场景中，需要一种机制来向模型传递子代理的状态变化通知（如启动、完成、失败等），同时确保这些系统消息与用户输入明确区分。

## 功能点目的

### 1. 子代理通知消息格式化
将子代理的状态变化（`AgentStatus`）格式化为结构化的 JSON 消息，并包装在特定的 XML 风格标签中，便于后续解析和识别。

### 2. 子代理上下文行格式化
生成简洁的子代理标识行，用于在会话上下文中列出活跃的子代理，支持可选的昵称显示。

## 具体技术实现

### 核心函数

#### `format_subagent_notification_message`
```rust
pub(crate) fn format_subagent_notification_message(agent_id: &str, status: &AgentStatus) -> String {
    let payload_json = serde_json::json!({
        "agent_id": agent_id,
        "status": status,
    })
    .to_string();
    SUBAGENT_NOTIFICATION_FRAGMENT.wrap(payload_json)
}
```

**功能流程：**
1. 构造包含 `agent_id` 和 `status` 的 JSON 对象
2. 将 JSON 序列化为字符串
3. 使用 `SUBAGENT_NOTIFICATION_FRAGMENT` 包装，添加 XML 风格标签

**输出示例：**
```
<subagent_notification>
{"agent_id":"agent-123","status":"completed"}
</subagent_notification>
```

#### `format_subagent_context_line`
```rust
pub(crate) fn format_subagent_context_line(agent_id: &str, agent_nickname: Option<&str>) -> String {
    match agent_nickname.filter(|nickname| !nickname.is_empty()) {
        Some(agent_nickname) => format!("- {agent_id}: {agent_nickname}"),
        None => format!("- {agent_id}"),
    }
}
```

**功能流程：**
1. 检查是否提供了非空的昵称
2. 如果有昵称，格式化为 `- {agent_id}: {agent_nickname}`
3. 如果没有昵称，仅格式化为 `- {agent_id}`

**输出示例：**
- 有昵称：`- agent-123: code-reviewer`
- 无昵称：`- agent-123`

### 依赖的类型定义

#### `AgentStatus`
来自 `codex_protocol::protocol::AgentStatus`，表示子代理的状态，可能包括：
- 运行中（Running）
- 已完成（Completed）
- 失败（Failed）
- 等等

#### `SUBAGENT_NOTIFICATION_FRAGMENT`
来自 `contextual_user_message` 模块，是一个 `ContextualUserFragmentDefinition` 类型的常量，定义了：
- 开始标记：`<subagent_notification>`
- 结束标记：`</subagent_notification>`
- `wrap` 方法：将内容包装在标签之间

## 关键代码路径与文件引用

### 模块依赖图

```
session_prefix.rs
├── contextual_user_message.rs
│   └── SUBAGENT_NOTIFICATION_FRAGMENT
│       ├── start_marker: "<subagent_notification>"
│       ├── end_marker: "</subagent_notification>"
│       └── wrap()
└── codex_protocol::protocol::AgentStatus
```

### 调用方分析

该模块的函数主要在以下场景被调用：
1. **子代理生命周期管理** - 当子代理状态变化时，生成通知消息插入到会话历史中
2. **上下文构建** - 在构建模型输入时，列出当前活跃的子代理

### 相关文件

| 文件 | 关系 |
|------|------|
| `contextual_user_message.rs` | 提供消息片段定义和包装功能 |
| `codex.rs` | 可能调用这些函数管理子代理会话 |
| `agent/` 目录下的模块 | 子代理实现，触发状态通知 |

## 依赖与外部交互

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `serde_json` | JSON 序列化 |
| `codex_protocol` | `AgentStatus` 类型定义 |

### 内部模块依赖

| 模块 | 用途 |
|------|------|
| `contextual_user_message` | `SUBAGENT_NOTIFICATION_FRAGMENT` 常量 |

## 风险、边界与改进建议

### 已知限制

1. **功能单一**
   - 模块仅包含两个简单的格式化函数
   - 职责范围非常狭窄，但符合单一职责原则

2. **无错误处理**
   - 函数不涉及 IO 或复杂计算，不会返回错误
   - `AgentStatus` 的序列化由 `serde_json` 处理，假设总是成功

3. **格式硬编码**
   - XML 风格的标签格式在 `contextual_user_message` 中定义
   - 列表项格式（`- ` 前缀）在此模块硬编码

### 边界情况

1. **空字符串昵称处理**
   ```rust
   agent_nickname.filter(|nickname| !nickname.is_empty())
   ```
   使用 `filter` 确保空字符串被视为无昵称，避免输出 `- agent-123: ` 这样的不完整行。

2. **JSON 序列化**
   - `AgentStatus` 必须实现 `Serialize` trait
   - 序列化结果不应包含换行符，以确保单消息格式

### 改进建议

1. **文档增强**
   - 添加更多使用示例
   - 说明 `AgentStatus` 的具体变体

2. **格式可配置**
   - 考虑将列表项前缀（`- `）提取为常量，便于统一修改
   - 支持其他格式选项（如编号列表）

3. **测试覆盖**
   - 当前文件无内联测试
   - 建议添加单元测试验证输出格式

4. **国际化考虑**
   - 当前格式为英文硬编码
   - 如果未来需要多语言支持，考虑将格式模板化

### 代码质量

- **简洁性**：代码非常简洁，易于理解
- **函数式风格**：使用 `filter` 和 `match` 处理可选值，符合 Rust 惯用法
- **零开销**：无堆分配（除 `serde_json::json!` 宏外），性能开销极小
