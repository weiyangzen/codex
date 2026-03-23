# exec_events.rs 研究文档

## 文件信息
- **路径**: `codex-rs/exec/src/exec_events.rs`
- **大小**: ~10,150 bytes
- **定位**: 定义 Codex Exec 的 JSONL 事件流数据结构

---

## 一、场景与职责

### 1.1 核心定位
`exec_events.rs` 是 Codex Exec 模块的**事件类型定义中心**，负责定义以 JSONL (JSON Lines) 格式输出到 stdout 的所有事件结构。它是 `--json` 模式下的核心数据契约层。

### 1.2 使用场景
1. **CLI 非交互式执行**: 用户运行 `codex-exec --json` 时，所有执行事件以 JSONL 格式输出
2. **程序化集成**: 下游工具/脚本解析 JSONL 流以获取执行进度和结果
3. **TypeScript 类型生成**: 通过 `ts-rs` crate 生成 TypeScript 类型定义，供前端使用

### 1.3 架构位置
```
┌─────────────────────────────────────────────────────────────┐
│                    codex-exec (CLI)                         │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────┐  │
│  │   cli.rs     │───▶│ event_processor_ │───▶│ exec_    │  │
│  │ (参数解析)    │    │ jsonl_output.rs  │    │ events.rs│  │
│  └──────────────┘    │ (事件转换/输出)   │    │ (类型定义)│  │
│                      └──────────────────┘    └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 ThreadEvent - 顶级事件枚举

定义了 Exec 模式下所有可能的事件类型，采用 `#[serde(tag = "type")]` 实现**内部标记序列化**：

| 事件变体 | Serde 标记 | 用途 |
|---------|-----------|------|
| `ThreadStarted` | `thread.started` | 会话开始，包含 thread_id |
| `TurnStarted` | `turn.started` | 新一轮对话开始 |
| `TurnCompleted` | `turn.completed` | 对话完成，包含 token 使用量 |
| `TurnFailed` | `turn.failed` | 对话失败 |
| `ItemStarted` | `item.started` | 某个工作项开始 |
| `ItemUpdated` | `item.updated` | 工作项状态更新 |
| `ItemCompleted` | `item.completed` | 工作项完成 |
| `Error` | `error` | 致命错误 |

### 2.2 ThreadItemDetails - 工作项详情

定义了 Agent 可能执行的**所有操作类型**：

```rust
pub enum ThreadItemDetails {
    AgentMessage(AgentMessageItem),      // Agent 文本回复
    Reasoning(ReasoningItem),            // 推理过程
    CommandExecution(CommandExecutionItem), // 命令执行
    FileChange(FileChangeItem),          // 文件变更
    McpToolCall(McpToolCallItem),        // MCP 工具调用
    CollabToolCall(CollabToolCallItem),  // 协作 Agent 工具
    WebSearch(WebSearchItem),            // 网络搜索
    TodoList(TodoListItem),              // 待办列表
    Error(ErrorItem),                    // 错误项
}
```

### 2.3 状态枚举设计

文件定义了多个状态枚举，采用 `#[serde(rename_all = "snake_case")]` 确保 JSON 输出风格一致：

- `CommandExecutionStatus`: InProgress → Completed/Failed/Declined
- `PatchApplyStatus`: InProgress → Completed/Failed
- `McpToolCallStatus`: InProgress → Completed/Failed
- `CollabToolCallStatus`: InProgress → Completed/Failed
- `CollabAgentStatus`: 协作 Agent 生命周期状态

---

## 三、具体技术实现

### 3.1 序列化设计

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, TS)]
#[serde(tag = "type")]  // 内部标记多态
pub enum ThreadEvent {
    #[serde(rename = "thread.started")]  // 自定义序列化名称
    ThreadStarted(ThreadStartedEvent),
    // ...
}
```

**关键技术选择**:
- `serde(tag = "type")`: 生成自描述的 JSON，便于下游解析
- `ts-rs::TS`: 自动生成 TypeScript 类型定义
- `#[serde(flatten)]`: 在 `ThreadItem` 中扁平化详情字段

### 3.2 MCP 工具结果设计

```rust
pub struct McpToolCallItemResult {
    // 使用 JsonValue 而非 rmcp::model::Content
    // 原因：保持 wire-shape，避免与 rmcp 深度耦合
    pub content: Vec<JsonValue>,
    pub structured_content: Option<JsonValue>,
}
```

**设计权衡**: 代码注释明确说明使用 `serde_json::Value` 而非 `rmcp::model::Content` 是为了：
1. 保持 schema/TS 友好性
2. 避免引入 rmcp 的 Rust 表示耦合

### 3.3 协作工具定义

```rust
pub enum CollabTool {
    SpawnAgent,   // 创建子 Agent
    SendInput,    // 向子 Agent 发送输入
    Wait,         // 等待子 Agent 完成
    CloseAgent,   // 关闭子 Agent
}
```

对应 `CollabToolCallItem` 结构体支持多接收者模式（`receiver_thread_ids: Vec<String>`）。

---

## 四、关键代码路径与文件引用

### 4.1 类型使用路径

```
exec_events.rs 定义类型
    │
    ▼
event_processor_with_jsonl_output.rs 消费/转换
    │
    ▼
stdout (JSONL 输出)
```

### 4.2 核心关联文件

| 文件 | 关系 | 说明 |
|-----|------|------|
| `event_processor_with_jsonl_output.rs` | 消费者 | 将 protocol 事件转换为 ThreadEvent |
| `event_processor_with_human_output.rs` | 平行实现 | 人类可读输出（不直接使用本文件类型） |
| `tests/event_processor_with_json_output.rs` | 测试 | 验证事件转换逻辑 |

### 4.3 外部协议依赖

```rust
use codex_protocol::models::WebSearchAction;  // 来自 protocol crate
```

`WebSearchAction` 定义在 `codex-protocol` 中，本文件仅引用不重新定义。

---

## 五、依赖与外部交互

### 5.1 Crate 依赖

```toml
[dependencies]
serde = { features = ["derive"] }
serde_json = {}
ts-rs = { features = ["uuid-impl", "serde-json-impl", "no-serde-warnings"] }
codex_protocol = { workspace = true }
```

### 5.2 跨模块依赖图

```
┌────────────────────────────────────────────────────────────┐
│                      exec_events.rs                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ serde       │  │ ts-rs       │  │ codex_protocol      │ │
│  │ (序列化)     │  │ (TS 生成)   │  │ (WebSearchAction)   │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   lib.rs      │   │ event_processor│   │    tests      │
│ (pub mod 导出)│   │ _with_jsonl_  │   │ (单元测试)     │
│               │   │ output.rs     │   │               │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 5.3 TypeScript 生成

通过 `ts-rs` 的 `#[derive(TS)]` 宏，在编译时生成 TypeScript 类型定义，供前端消费。

---

## 六、风险、边界与改进建议

### 6.1 当前风险

1. **类型版本漂移**: `ThreadEvent` 与 `codex-protocol` 中的事件类型需要手动同步
2. **扁平化限制**: `ThreadItem` 使用 `#[serde(flatten)]`，某些 JSON 解析器可能不支持
3. **MCP 内容抽象**: 使用 `JsonValue` 虽解耦但丢失了类型安全

### 6.2 边界情况

1. **空待办列表**: `TodoListItem` 允许空 `items` Vec，需消费者处理
2. **命令执行无退出码**: `CommandExecutionItem.exit_code` 为 `Option<i32>`，支持未完成状态
3. **WebSearch 初始空查询**: `handle_web_search_begin` 时 query 为空字符串，在 end 时填充

### 6.3 改进建议

| 优先级 | 建议 | 理由 |
|-------|------|------|
| 中 | 添加事件版本字段 | 便于未来 schema 演进 |
| 低 | 为 MCP 结果添加强类型 wrapper | 在不引入 rmcp 耦合的前提下提升类型安全 |
| 低 | 统一 Collab/非 Collab 工具表示 | 当前 `CollabToolCallItem` 与 `McpToolCallItem` 结构相似但独立 |

### 6.4 测试覆盖

测试集中在 `tests/event_processor_with_json_output.rs`，覆盖：
- 事件转换正确性
- ID 连续性（begin/end 使用相同 item_id）
- 错误状态传播
- 协作工具调用生命周期

**建议补充**: 边界测试（如 begin 无对应 end 的情况）。
