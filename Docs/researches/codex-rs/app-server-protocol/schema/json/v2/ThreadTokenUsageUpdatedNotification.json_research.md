# ThreadTokenUsageUpdatedNotification.json 研究文档

## 场景与职责

`ThreadTokenUsageUpdatedNotification` 是 Codex App-Server Protocol v2 中的服务器通知类型，用于向客户端实时报告 Token 使用量统计信息。这是成本控制和用量监控的核心机制，帮助用户了解 API 调用成本和模型上下文窗口使用情况。

典型使用场景：
- 每次模型调用完成后更新 Token 使用统计
- 客户端实时显示当前会话的累计 Token 消耗
- 监控模型上下文窗口剩余容量
- 成本估算和用量限制预警

## 功能点目的

该通知的主要目的是：
1. **成本透明**：让用户了解每次交互的 Token 消耗情况
2. **上下文管理**：监控上下文窗口使用率，避免超出限制
3. **用量统计**：累计统计整个 Thread 的 Token 使用量
4. **性能优化**：帮助用户理解哪些操作消耗较多 Token

### TokenUsage 数据结构

| 字段 | 类型 | 描述 |
|------|------|------|
| `total` | TokenUsageBreakdown | 整个 Thread 的累计 Token 使用 |
| `last` | TokenUsageBreakdown | 最近一次调用的 Token 使用 |
| `modelContextWindow` | integer \| null | 模型上下文窗口大小 |

### TokenUsageBreakdown 详细字段

| 字段 | 类型 | 描述 |
|------|------|------|
| `totalTokens` | integer | 总 Token 数 |
| `inputTokens` | integer | 输入 Token 数 |
| `cachedInputTokens` | integer | 缓存命中的输入 Token 数 |
| `outputTokens` | integer | 输出 Token 数 |
| `reasoningOutputTokens` | integer | 推理阶段的输出 Token 数 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "threadId": { "type": "string" },
    "tokenUsage": { "$ref": "#/definitions/ThreadTokenUsage" },
    "turnId": { "type": "string" }
  },
  "required": ["threadId", "tokenUsage", "turnId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`（行 3525-3549）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadTokenUsageUpdatedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub token_usage: ThreadTokenUsage,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadTokenUsage {
    pub total: TokenUsageBreakdown,
    pub last: TokenUsageBreakdown,
    #[ts(type = "number | null")]
    pub model_context_window: Option<i64>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TokenUsageBreakdown {
    #[ts(type = "number")]
    pub total_tokens: i64,
    #[ts(type = "number")]
    pub input_tokens: i64,
    #[ts(type = "number")]
    pub cached_input_tokens: i64,
    #[ts(type = "number")]
    pub output_tokens: i64,
    #[ts(type = "number")]
    pub reasoning_output_tokens: i64,
}
```

### 从核心类型转换

```rust
impl From<CoreTokenUsageInfo> for ThreadTokenUsage {
    fn from(value: CoreTokenUsageInfo) -> Self {
        Self {
            total: value.total_token_usage.into(),
            last: value.last_token_usage.into(),
            model_context_window: value.model_context_window,
        }
    }
}

impl From<CoreTokenUsage> for TokenUsageBreakdown {
    fn from(value: CoreTokenUsage) -> Self {
        Self {
            total_tokens: value.total_tokens,
            input_tokens: value.input_tokens,
            cached_input_tokens: value.cached_input_tokens,
            output_tokens: value.output_tokens,
            reasoning_output_tokens: value.reasoning_output_tokens,
        }
    }
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中：

```rust
server_notification_definitions! {
    ThreadTokenUsageUpdated => "thread/tokenUsage/updated" (v2::ThreadTokenUsageUpdatedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadTokenUsageUpdatedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 3525-3566） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 884） |

### 服务端发送代码

位于 `codex-rs/app-server/src/bespoke_event_handling.rs`：
- 处理来自核心 Codex 引擎的 Token 使用事件
- 转换为 v2 协议格式后发送给客户端

位于 `codex-rs/tui_app_server/src/app.rs`：
- TUI 应用服务器接收并处理 Token 使用通知
- 更新 UI 显示 Token 统计信息

## 依赖与外部交互

### 上游依赖

1. **codex_protocol::protocol::TokenUsageInfo**: 核心 Token 使用信息类型
2. **codex_protocol::protocol::TokenUsage**: 核心 Token 使用统计类型

### 下游消费者

1. **tui_app_server**: TUI 应用服务器显示 Token 统计
2. **VSCode 扩展**: 在编辑器界面显示 Token 使用情况
3. **CLI 工具**: 命令行界面显示 Token 统计

### 相关类型

- `CoreTokenUsageInfo`: 核心库中的 Token 使用信息
- `CoreTokenUsage`: 核心库中的 Token 使用统计

## 风险、边界与改进建议

### 潜在风险

1. **精度丢失**：Token 计数使用 `i64`，理论上足够大，但极端情况下可能溢出
2. **缓存统计不准确**：`cachedInputTokens` 依赖模型提供商的准确报告
3. **并发更新**：多个 Turn 同时完成时，通知顺序可能影响客户端显示的准确性

### 边界情况

1. **modelContextWindow 为 null**：某些模型或配置下可能无法获取上下文窗口大小
2. **reasoningOutputTokens 为 0**：非推理模型或不支持推理输出的场景
3. **Turn 中断**：Turn 被中断时，Token 统计可能不完整

### 改进建议

1. **添加时间戳**：记录 Token 使用统计的生成时间
2. **预估成本**：基于 Token 使用量计算预估成本
3. **用量限制预警**：当接近用量限制时发送警告通知
4. **历史趋势**：支持查询 Token 使用的历史趋势数据
5. **模型切换处理**：模型切换时重置或调整统计口径

### 性能考虑

- Token 统计通知在每次模型调用后发送，频率适中
- 数据结构紧凑，网络开销小
- 客户端可以聚合多个通知以减少 UI 更新频率
