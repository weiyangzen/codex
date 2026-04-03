# ToolRequestUserInputAnswer 类型研究报告

## 场景与职责

`ToolRequestUserInputAnswer` 是一个 **EXPERIMENTAL** 类型，用于捕获用户对 `request_user_input` 工具调用的回答。它是交互式工具系统的一部分，允许 AI 在执行过程中向用户提问并获取结构化回答。

**核心使用场景：**

1. **交互式确认**：AI 需要用户确认某个操作（如"是否继续执行？"）
2. **参数收集**：AI 需要向用户收集执行所需的额外信息
3. **选择题交互**：用户从预定义选项中选择答案
4. **多问题回答**：一个工具调用可能包含多个问题，每个问题对应一个答案

**典型交互流程：**
```
AI 工具调用 -> request_user_input 
  -> 服务端发送 ServerRequest::ToolRequestUserInput 
  -> 客户端显示问题 UI
  -> 用户输入/选择答案
  -> 客户端构造 ToolRequestUserInputAnswer
  -> 客户端发送 ToolRequestUserInputResponse (包含 question_id -> answer 映射)
  -> AI 继续执行
```

## 功能点目的

该类型的设计目的包括：

1. **结构化回答**：将用户回答封装为结构化数据，便于 AI 解析
2. **多答案支持**：支持一个问题有多个答案（如多选场景）
3. **类型安全**：通过强类型确保回答格式的一致性
4. **工具链集成**：作为 `ToolRequestUserInputResponse` 的一部分，完成交互闭环

**与相关类型的关系：**

```
ToolRequestUserInputQuestion (问题定义)
  -> 用户回答 -> ToolRequestUserInputAnswer (单个答案)
    -> 聚合到 -> ToolRequestUserInputResponse.answers (question_id -> answer 映射)
```

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
/**
 * EXPERIMENTAL. Captures a user's answer to a request_user_input question.
 */
export type ToolRequestUserInputAnswer = { 
  answers: Array<string>, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Captures a user's answer to a request_user_input question.
pub struct ToolRequestUserInputAnswer {
    pub answers: Vec<String>,
}
```

### 类型映射

| Rust 类型 | TypeScript 类型 | 说明 |
|-----------|-----------------|------|
| `Vec<String>` | `Array<string>` | 使用 `#[ts(export_to = "v2/")]` 生成 |

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `answers` | `Vec<String>` / `Array<string>` | 用户提供的答案列表，支持单选和多选场景 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ToolRequestUserInputQuestion` | 问题定义 | 定义了问题的结构 |
| `ToolRequestUserInputOption` | 选项定义 | 预定义选项，用户可能选择这些选项作为答案 |
| `ToolRequestUserInputResponse` | 容器 | 包含 `answers: HashMap<String, ToolRequestUserInputAnswer>` |
| `ToolRequestUserInputParams` | 请求参数 | 服务端发送的问题参数 |

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5700-5707) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputAnswer.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/ToolRequestUserInputResponse.json` | 在响应 schema 中引用 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 ServerRequest 类型 |
| `codex-rs/app-server/src/outgoing_message.rs` | 处理 outgoing 消息 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 自定义事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 Codex 消息 |
| `codex-rs/app-server/tests/suite/v2/request_user_input.rs` | 集成测试 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 聊天组件处理用户输入 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | 应用服务器请求处理 |
| `codex-rs/tui_app_server/src/app/pending_interactive_replay.rs` | 待处理交互重放 |
| `codex-rs/exec/src/lib.rs` | 执行库 |

### 测试引用示例

```rust
// 来自 request_user_input.rs 测试
mcp.send_response(
    request_id,
    serde_json::json!({
        "answers": {
            "confirm_path": { "answers": ["yes"] }
        }
    }),
).await?;
```

## 依赖与外部交互

### 内部依赖

```
ToolRequestUserInputAnswer
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  ├── ts_rs (TS)
  └── ToolRequestUserInputResponse (作为 HashMap 值类型)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| 客户端 (TUI/CLI) | JSON-RPC 响应 | 构造并发送用户回答 |
| AI 模型 | 工具调用 | 发起 `request_user_input` 调用 |
| CodexMessageProcessor | 内部处理 | 处理回答并恢复 AI 执行 |

### 序列化示例

```json
// 单选回答
{
  "answers": ["option_a"]
}

// 多选回答
{
  "answers": ["option_a", "option_c"]
}

// 文本输入回答
{
  "answers": ["my custom input"]
}

// 在 ToolRequestUserInputResponse 中的使用
{
  "answers": {
    "question_1": { "answers": ["yes"] },
    "question_2": { "answers": ["option_a", "option_b"] }
  }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为 EXPERIMENTAL，未来可能大幅变更
2. **答案验证缺失**：服务端未对答案内容进行验证，可能收到无效答案
3. **空答案处理**：`answers` 数组为空时的语义不明确
4. **答案大小限制**：未限制单个答案或答案数组的大小，可能导致内存问题

### 边界情况

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| 空 answers 数组 | 允许 | 应定义语义（表示跳过？拒绝回答？） |
| 答案不在预定义选项中 | 允许 | 考虑添加验证模式 |
| 重复答案 | 允许 | 考虑去重或拒绝 |
| 超长答案字符串 | 无限制 | 应添加长度限制 |

### 改进建议

1. **添加验证**：实现答案验证逻辑：
   ```rust
   impl ToolRequestUserInputAnswer {
       pub fn validate(&self, question: &ToolRequestUserInputQuestion) -> Result<(), ValidationError> {
           if self.answers.is_empty() && !question.is_optional {
               return Err(ValidationError::EmptyAnswer);
           }
           // 验证答案是否在预定义选项中
           if let Some(options) = &question.options {
               for answer in &self.answers {
                   if !options.iter().any(|o| o.label == *answer) && !question.is_other {
                       return Err(ValidationError::InvalidOption);
                   }
               }
           }
           Ok(())
       }
   }
   ```

2. **添加元数据字段**：考虑添加时间戳和用户信息：
   ```rust
   pub struct ToolRequestUserInputAnswer {
       pub answers: Vec<String>,
       pub answered_at: i64,
       pub answer_source: AnswerSource, // User, Script, Default, etc.
   }
   ```

3. **支持更丰富的答案类型**：当前仅支持字符串数组，考虑支持：
   ```rust
   pub enum AnswerValue {
       Text(String),
       Number(f64),
       Boolean(bool),
       File { name: String, content: String },
   }
   ```

4. **添加大小限制**：在序列化层添加限制：
   ```rust
   #[serde(deserialize_with = "validate_answer_count")]
   pub answers: Vec<String>,
   ```

5. **文档增强**：添加更多使用示例：
   ```typescript
   /**
    * EXPERIMENTAL. Captures a user's answer to a request_user_input question.
    * 
    * @example
    * // Single choice
    * { answers: ["yes"] }
    * 
    * @example  
    * // Multiple choice
    * { answers: ["option_a", "option_b"] }
    * 
    * @example
    * // Free text input
    * { answers: ["My custom response"] }
    */
   ```

6. **考虑与 ToolRequestUserInputQuestion 的关联验证**：确保答案与问题类型匹配（如单选问题不应有多选答案）

### 实验性状态说明

该类型目前标记为 EXPERIMENTAL，意味着：
- API 可能在未来的版本中发生重大变更
- 不建议在生产关键路径中依赖此功能
- 需要持续的用户反馈来完善设计
- 文档和测试覆盖可能不完整
