# ToolRequestUserInputParams 类型研究报告

## 场景与职责

`ToolRequestUserInputParams` 是一个 **EXPERIMENTAL** 类型，作为服务端向客户端发送 `request_user_input` 工具请求时的参数载体。它包含了向用户展示交互式问题所需的所有上下文信息。

**核心使用场景：**

1. **AI 执行中断**：当 AI 需要用户输入才能继续执行时，发送此请求
2. **多问题批量提问**：一次请求中包含多个相关问题，减少往返次数
3. **上下文关联**：通过 `threadId`、`turnId`、`itemId` 将问题与特定执行上下文关联
4. **交互式工作流**：支持复杂的用户确认和参数收集工作流

**典型交互流程：**
```
AI 执行中遇到需要用户输入的情况
  -> CodexMessageProcessor 构造 ToolRequestUserInputParams
  -> 通过 ServerRequest::ToolRequestUserInput 发送给客户端
  -> 客户端解析参数并渲染 UI
  -> 用户回答问题
  -> 客户端构造 ToolRequestUserInputResponse 返回
  -> AI 继续执行
```

## 功能点目的

该类型的设计目的包括：

1. **上下文传递**：确保客户端知道问题属于哪个线程、回合和项目
2. **批量提问**：支持一次请求多个问题，提高交互效率
3. **类型安全**：强类型确保参数结构的正确性
4. **UI 无关性**：纯数据结构，可被任何客户端渲染

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `threadId` | 标识问题所属的线程，用于路由回答 |
| `turnId` | 标识问题所属的回合，用于状态管理 |
| `itemId` | 标识问题所属的工具调用项目 |
| `questions` | 问题列表，每个问题包含展示和回答所需的信息 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
/**
 * EXPERIMENTAL. Params sent with a request_user_input event.
 */
export type ToolRequestUserInputParams = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  questions: Array<ToolRequestUserInputQuestion>, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Params sent with a request_user_input event.
pub struct ToolRequestUserInputParams {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub questions: Vec<ToolRequestUserInputQuestion>,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | `String` / `string` | 是 | 问题所属的线程 ID |
| `turnId` | `String` / `string` | 是 | 问题所属的回合 ID |
| `itemId` | `String` / `string` | 是 | 问题所属的工具调用项目 ID |
| `questions` | `Vec<ToolRequestUserInputQuestion>` / `Array<ToolRequestUserInputQuestion>` | 是 | 问题列表 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ToolRequestUserInputQuestion` | 子元素 | 定义单个问题的结构 |
| `ToolRequestUserInputOption` | 孙子元素 | 定义问题的选项 |
| `ToolRequestUserInputAnswer` | 对应答案 | 用户回答的结构 |
| `ToolRequestUserInputResponse` | 响应类型 | 客户端返回的响应 |
| `ServerRequest` | 容器 | 作为 `ToolRequestUserInput` 变体的参数 |

### 类型层次

```
ToolRequestUserInputParams
  ├── threadId: String
  ├── turnId: String
  ├── itemId: String
  └── questions: Vec<ToolRequestUserInputQuestion>
        └── ToolRequestUserInputQuestion
              ├── id: String
              ├── header: String
              ├── question: String
              ├── isOther: bool
              ├── isSecret: bool
              └── options: Option<Vec<ToolRequestUserInputOption>>
                    └── ToolRequestUserInputOption
                          ├── label: String
                          └── description: String
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5689-5698) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputParams.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/ToolRequestUserInputParams.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 ServerRequest 类型 |
| `codex-rs/app-server/src/outgoing_message.rs` | 构造 outgoing 消息 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 自定义事件处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理并发送请求 |
| `codex-rs/app-server/tests/suite/v2/request_user_input.rs` | 集成测试验证参数传递 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 处理请求参数 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | 应用服务器请求处理 |
| `codex-rs/tui_app_server/src/app/pending_interactive_replay.rs` | 待处理交互重放 |
| `codex-rs/exec/src/lib.rs` | 执行库 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库 |

### 测试引用示例

```rust
// 来自 request_user_input.rs 测试
let ServerRequest::ToolRequestUserInput { request_id, params } = server_req else {
    panic!("expected ToolRequestUserInput request");
};

assert_eq!(params.thread_id, thread.id);
assert_eq!(params.turn_id, turn.id);
assert_eq!(params.item_id, "call1");
assert_eq!(params.questions.len(), 1);
```

## 依赖与外部交互

### 内部依赖

```
ToolRequestUserInputParams
  ├── ToolRequestUserInputQuestion
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| AI 模型 | 触发 | 模型调用 `request_user_input` 工具 |
| CodexMessageProcessor | 构造 | 将工具调用转换为请求参数 |
| 客户端 (TUI/CLI) | JSON-RPC 请求 | 接收并处理请求 |
| Thread/Turn 管理 | 关联 | 通过 ID 关联到具体执行上下文 |

### 序列化示例

```json
{
  "threadId": "thread_abc123",
  "turnId": "turn_def456",
  "itemId": "call_ghi789",
  "questions": [
    {
      "id": "confirm_deletion",
      "header": "Confirm File Deletion",
      "question": "Are you sure you want to delete file.txt?",
      "isOther": false,
      "isSecret": false,
      "options": [
        {
          "label": "yes",
          "description": "Delete the file permanently"
        },
        {
          "label": "no",
          "description": "Keep the file"
        }
      ]
    }
  ]
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为 EXPERIMENTAL，未来可能大幅变更
2. **ID 有效性**：不验证 `threadId`、`turnId`、`itemId` 是否真实存在
3. **questions 为空**：空问题列表的语义不明确
4. **循环引用风险**：如果 AI 反复请求输入，可能导致交互循环
5. **超时处理**：未定义用户无响应时的超时行为

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 空 questions 数组 | 允许 | 无问题可展示，用户困惑 |
| 无效 threadId | 未验证 | 回答可能无法正确路由 |
| 重复 question id | 允许 | 答案映射可能冲突 |
| 超长问题列表 | 无限制 | UI 渲染性能问题 |

### 改进建议

1. **添加验证方法**：
   ```rust
   impl ToolRequestUserInputParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.questions.is_empty() {
               return Err(ValidationError::NoQuestions);
           }
           
           // 验证 question id 唯一性
           let mut ids = HashSet::new();
           for question in &self.questions {
               if !ids.insert(&question.id) {
                   return Err(ValidationError::DuplicateQuestionId);
               }
               question.validate()?;
           }
           
           Ok(())
       }
   }
   ```

2. **添加超时字段**：
   ```rust
   pub struct ToolRequestUserInputParams {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       #[ts(type = "number", optional = nullable)]
       pub timeout_seconds: Option<u32>,
   }
   ```

3. **添加优先级/紧急度**：
   ```rust
   pub enum InputPriority {
       Low,
       Normal,
       High,
       Blocking, // 必须回答才能继续
   }
   
   pub struct ToolRequestUserInputParams {
       // ... 现有字段
       #[serde(default)]
       pub priority: InputPriority,
   }
   ```

4. **支持条件问题**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub depends_on: Option<String>, // 依赖的其他问题 id
       #[serde(skip_serializing_if = "Option::is_none")]
       pub show_when: Option<Condition>, // 显示条件
   }
   ```

5. **添加元数据**：
   ```rust
   pub struct ToolRequestUserInputParams {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub metadata: Option<HashMap<String, String>>,
   }
   ```

6. **支持进度信息**：
   ```rust
   pub struct ToolRequestUserInputParams {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub progress: Option<InputProgress>,
   }
   
   pub struct InputProgress {
       pub current_step: u32,
       pub total_steps: u32,
       pub step_description: String,
   }
   ```

7. **添加取消令牌**：
   ```rust
   pub struct ToolRequestUserInputParams {
       // ... 现有字段
       pub cancellation_token: String, // 用于取消此输入请求
   }
   ```

### 安全考虑

1. **isSecret 字段使用**：当 `isSecret` 为 true 时，客户端应使用密码输入框
2. **输入验证**：服务端应对用户回答进行验证，防止注入攻击
3. **超时处理**：建议实现超时机制，防止无限等待

### 实验性状态说明

作为实验性 API，建议：
- 在实际使用中进行充分测试
- 收集客户端实现的反馈
- 关注 API 变更通知
- 准备向后兼容的适配层
