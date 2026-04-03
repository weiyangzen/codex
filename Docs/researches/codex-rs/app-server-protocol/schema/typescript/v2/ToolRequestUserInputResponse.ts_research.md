# ToolRequestUserInputResponse 类型研究报告

## 场景与职责

`ToolRequestUserInputResponse` 是一个 **EXPERIMENTAL** 类型，作为客户端对 `request_user_input` 工具请求的响应。它将用户的回答按问题 ID 组织成映射表，完成交互式输入的闭环。

**核心使用场景：**

1. **回答提交**：用户完成问题回答后，客户端构造此响应返回给服务端
2. **批量回答**：一次响应可以包含多个问题的答案
3. **答案映射**：通过 question ID 到 answer 的映射，确保答案与问题正确对应
4. **交互恢复**：服务端收到响应后恢复 AI 执行流程

**典型交互流程：**
```
服务端发送 ToolRequestUserInputParams (含 questions)
  -> 客户端渲染 UI 并收集用户输入
  -> 客户端构造 ToolRequestUserInputResponse
       { answers: { "question_id": { answers: ["user_answer"] } } }
  -> 客户端发送响应
  -> 服务端解析答案并恢复 AI 执行
  -> AI 根据用户输入继续处理
```

## 功能点目的

该类型的设计目的包括：

1. **结构化回答**：将用户回答组织为结构化的映射表，便于服务端解析
2. **多问题支持**：支持一次响应多个问题的答案
3. **类型安全**：强类型确保响应格式的正确性
4. **灵活答案**：每个问题可以有多个答案（支持多选场景）

**数据结构意图：**

| 字段 | 目的 |
|------|------|
| `answers` | 问题 ID 到答案的映射，支持批量回答 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
/**
 * EXPERIMENTAL. Response payload mapping question ids to answers.
 */
export type ToolRequestUserInputResponse = { 
  answers: { [key in string]?: ToolRequestUserInputAnswer }, 
};
```

**Rust 源定义：**
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Response payload mapping question ids to answers.
pub struct ToolRequestUserInputResponse {
    pub answers: HashMap<String, ToolRequestUserInputAnswer>,
}
```

### 类型映射

| Rust 类型 | TypeScript 类型 | 说明 |
|-----------|-----------------|------|
| `HashMap<String, ToolRequestUserInputAnswer>` | `{ [key in string]?: ToolRequestUserInputAnswer }` | 可选键的映射表 |

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `answers` | `HashMap<String, ToolRequestUserInputAnswer>` / `Record<string, ToolRequestUserInputAnswer>` | 问题 ID 到答案的映射 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ToolRequestUserInputAnswer` | 值类型 | 单个问题的答案结构 |
| `ToolRequestUserInputParams` | 对应请求 | 包含问题定义 |
| `ToolRequestUserInputQuestion` | 问题定义 | 其 `id` 字段作为映射的键 |

### 数据流

```
ToolRequestUserInputParams.questions
  -> 用户交互
    -> ToolRequestUserInputResponse.answers
      -> HashMap<question.id, ToolRequestUserInputAnswer>
        -> AI 恢复执行
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5708-5714) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputResponse.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/ToolRequestUserInputResponse.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 ServerRequest 的响应类型 |
| `codex-rs/app-server/tests/suite/v2/request_user_input.rs` | 集成测试构造响应 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 构造并发送响应 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | 应用服务器请求处理 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库 |

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

### 序列化示例

**单问题回答：**
```json
{
  "answers": {
    "confirm_deletion": {
      "answers": ["yes"]
    }
  }
}
```

**多问题回答：**
```json
{
  "answers": {
    "action_choice": {
      "answers": ["run_tests"]
    },
    "verbosity_level": {
      "answers": ["detailed"]
    }
  }
}
```

**多选回答：**
```json
{
  "answers": {
    "features_to_enable": {
      "answers": ["auto_save", "lint_on_save", "format_on_save"]
    }
  }
}
```

**带"其他"选项的回答：**
```json
{
  "answers": {
    "reason": {
      "answers": ["other: I have a custom reason"]
    }
  }
}
```

## 依赖与外部交互

### 内部依赖

```
ToolRequestUserInputResponse
  ├── ToolRequestUserInputAnswer
  ├── HashMap (std::collections)
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| 客户端 (TUI/CLI) | JSON-RPC 响应 | 构造并发送响应 |
| 服务端 | 接收解析 | 解析答案并恢复 AI 执行 |
| AI 模型 | 消费 | 根据用户回答继续处理 |

### 响应构造示例

```typescript
function constructResponse(
  questions: ToolRequestUserInputQuestion[],
  userInputs: Map<string, string[]>
): ToolRequestUserInputResponse {
  const answers: Record<string, ToolRequestUserInputAnswer> = {};
  
  for (const question of questions) {
    const userAnswer = userInputs.get(question.id);
    if (userAnswer) {
      answers[question.id] = { answers: userAnswer };
    }
  }
  
  return { answers };
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为 EXPERIMENTAL，未来可能变更
2. **答案缺失**：客户端可能未回答所有问题，导致 answers 映射不完整
3. **无效 question ID**：映射中可能包含请求中不存在的问题 ID
4. **答案格式错误**：答案格式可能与问题类型不匹配
5. **空 answers 映射**：用户可能未回答任何问题

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 空 answers | 允许 | AI 可能无法继续执行 |
| 部分回答 | 允许 | 未回答的问题如何处理？ |
| 额外 question ID | 允许 | 服务端可能忽略或报错 |
| 空答案数组 | 允许 | 语义不明确 |

### 改进建议

1. **添加验证方法**：
   ```rust
   impl ToolRequestUserInputResponse {
       pub fn validate(&self, expected_questions: &[ToolRequestUserInputQuestion]) -> Result<(), ValidationError> {
           // 检查是否有未回答的问题
           for question in expected_questions {
               if !self.answers.contains_key(&question.id) && question.is_required() {
                   return Err(ValidationError::MissingAnswer(question.id.clone()));
               }
           }
           
           // 检查是否有意外的 question ID
           let expected_ids: HashSet<_> = expected_questions.iter().map(|q| &q.id).collect();
           for id in self.answers.keys() {
               if !expected_ids.contains(id) {
                   return Err(ValidationError::UnexpectedQuestionId(id.clone()));
               }
           }
           
           // 验证每个答案
           for (id, answer) in &self.answers {
               let question = expected_questions.iter().find(|q| q.id == *id)
                   .ok_or_else(|| ValidationError::QuestionNotFound(id.clone()))?;
               answer.validate(question)?;
           }
           
           Ok(())
       }
   }
   ```

2. **添加完成状态**：
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       #[serde(default)]
       pub completion_status: CompletionStatus,
   }
   
   pub enum CompletionStatus {
       Complete,      // 所有问题已回答
       Partial,       // 部分回答（用户选择跳过某些问题）
       Cancelled,     // 用户取消交互
       TimedOut,      // 超时
   }
   ```

3. **支持答案元数据**：
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub metadata: Option<ResponseMetadata>,
   }
   
   pub struct ResponseMetadata {
       pub submitted_at: i64,
       pub client_version: String,
   }
   ```

4. **支持部分回答说明**：
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub skipped_questions: Option<Vec<String>>, // 用户跳过的 question IDs
       #[serde(skip_serializing_if = "Option::is_none")]
       pub skip_reason: Option<String>,
   }
   ```

5. **添加签名/验证**：
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub signature: Option<String>, // 防止篡改
   }
   ```

### 与请求参数的对应关系

```rust
// 验证响应与请求的对应关系
pub fn validate_response_against_request(
    response: &ToolRequestUserInputResponse,
    request: &ToolRequestUserInputParams,
) -> Result<(), ValidationError> {
    let request_ids: HashSet<_> = request.questions.iter().map(|q| &q.id).collect();
    
    // 检查所有请求的问题都有答案（除非是可选的）
    for question in &request.questions {
        if !response.answers.contains_key(&question.id) {
            // 检查问题是否为可选
            if !question.is_optional() {
                return Err(ValidationError::RequiredQuestionNotAnswered(question.id.clone()));
            }
        }
    }
    
    // 检查响应中的问题 ID 都在请求中
    for id in response.answers.keys() {
        if !request_ids.contains(id) {
            return Err(ValidationError::UnknownQuestionId(id.clone()));
        }
    }
    
    Ok(())
}
```

### 实验性状态说明

作为实验性 API，建议：
- 在实际使用中进行充分测试
- 实现健壮的验证逻辑
- 准备处理各种边界情况
- 关注 API 变更通知
- 考虑添加遥测以收集使用情况数据
