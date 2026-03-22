# ToolRequestUserInputResponse.json 深入研究

## 场景与职责

`ToolRequestUserInputResponse.json` 定义了客户端对 `ToolRequestUserInput` 服务器请求的响应格式。它是 Codex App Server Protocol 中交互式工具调用流程的**响应端契约**，负责将用户的答案从客户端传回服务器。

### 核心职责

1. **答案传递**：将用户对问题的回答传递给服务器
2. **多问题支持**：支持一次性回答多个问题
3. **多选支持**：单个问题支持多个答案（多选场景）
4. **答案映射**：通过问题 ID 建立答案与问题的关联

### 使用场景

```
用户触发工具调用
    ↓
服务器发送 ToolRequestUserInput (含 questions)
    ↓
客户端展示交互式表单
    ↓
用户填写/选择答案
    ↓
客户端发送 ToolRequestUserInputResponse (含 answers) ← 本文件定义
    ↓
服务器继续工具执行
```

## 功能点目的

### 1. 响应结构（ToolRequestUserInputResponse）

```json
{
  "answers": {
    "question_id_1": { "answers": ["选项A", "选项B"] },
    "question_id_2": { "answers": ["自由文本输入"] }
  }
}
```

- `answers`：以问题 ID 为键的映射表
- 支持每个问题多个答案（多选场景）
- 答案为字符串数组，保持灵活性

### 2. 答案结构（ToolRequestUserInputAnswer）

```json
{
  "answers": ["string"]
}
```

设计选择：
- 使用数组而非单值，天然支持多选
- 字符串类型保持简单，复杂数据可序列化为 JSON 字符串
- 与 `ToolRequestUserInputOption.label` 对应

### 3. 与请求类型的对应关系

| 请求字段 | 响应字段 | 对应关系 |
|---------|---------|---------|
| `ToolRequestUserInputQuestion.id` | `answers` 的键 | 通过 ID 关联 |
| `ToolRequestUserInputOption.label` | `ToolRequestUserInputAnswer.answers[]` | 值对应 |
| `ToolRequestUserInputQuestion.isOther` | 自定义答案 | 当选择"其他"时 |
| `ToolRequestUserInputQuestion.isSecret` | 加密传输 | 需额外实现 |

## 具体技术实现

### 1. Rust 类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Captures a user's answer to a request_user_input question.
pub struct ToolRequestUserInputAnswer {
    pub answers: Vec<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Response payload mapping question ids to answers.
pub struct ToolRequestUserInputResponse {
    pub answers: HashMap<String, ToolRequestUserInputAnswer>,
}
```

### 2. JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ToolRequestUserInputAnswer": {
      "description": "EXPERIMENTAL. Captures a user's answer to a request_user_input question.",
      "properties": {
        "answers": {
          "items": { "type": "string" },
          "type": "array"
        }
      },
      "required": ["answers"],
      "type": "object"
    }
  },
  "description": "EXPERIMENTAL. Response payload mapping question ids to answers.",
  "properties": {
    "answers": {
      "additionalProperties": {
        "$ref": "#/definitions/ToolRequestUserInputAnswer"
      },
      "type": "object"
    }
  },
  "required": ["answers"],
  "title": "ToolRequestUserInputResponse",
  "type": "object"
}
```

### 3. 关键设计决策

#### 为什么使用 HashMap 而非数组？

```rust
// 实际实现
pub answers: HashMap<String, ToolRequestUserInputAnswer>

// 对比：如果使用数组
pub answers: Vec<ToolRequestUserInputAnswerWithId>
```

选择 HashMap 的原因：
1. **O(1) 查找**：服务器按问题 ID 检索答案更快
2. **天然去重**：键的唯一性保证每个问题只有一个答案对象
3. **JSON 友好**：序列化为对象比数组更紧凑

#### 为什么答案使用 Vec<String>？

```rust
pub answers: Vec<String>  // 而非 String
```

原因：
1. **支持多选**：单个问题可选择多个选项
2. **统一接口**：单选时退化为单元素数组
3. **未来扩展**：可轻松支持排序、优先级等

### 4. 序列化示例

```rust
// Rust 对象
let response = ToolRequestUserInputResponse {
    answers: [
        ("q1".to_string(), ToolRequestUserInputAnswer {
            answers: vec!["Option A".to_string()]
        }),
        ("q2".to_string(), ToolRequestUserInputAnswer {
            answers: vec!["Custom input".to_string()]
        }),
    ].into_iter().collect()
};

// JSON 输出
{
  "answers": {
    "q1": { "answers": ["Option A"] },
    "q2": { "answers": ["Custom input"] }
  }
}
```

## 关键代码路径与文件引用

### 源头定义
| 文件 | 行号 | 内容 |
|------|------|------|
| `src/protocol/v2.rs` | 5700-5714 | `ToolRequestUserInputAnswer` 和 `ToolRequestUserInputResponse` 定义 |

### 在 ServerRequest 中的引用
| 文件 | 内容 |
|------|------|
| `src/protocol/common.rs` | `server_request_definitions!` 宏中定义 `ToolRequestUserInput` 请求的响应类型 |

```rust
server_request_definitions! {
    ToolRequestUserInput => "item/tool/requestUserInput" {
        params: v2::ToolRequestUserInputParams,
        response: v2::ToolRequestUserInputResponse,  // ← 本类型
    },
    // ...
}
```

### 生成输出
| 文件 | 职责 |
|------|------|
| `schema/json/ToolRequestUserInputResponse.json` | 本文件 |
| `schema/typescript/v2/ToolRequestUserInputResponse.ts` | TypeScript 类型定义 |
| `schema/typescript/v2/ToolRequestUserInputAnswer.ts` | 答案子类型 |

### 相关文件
| 文件 | 关系 |
|------|------|
| `ToolRequestUserInputParams.json` | 对应的请求参数 schema |
| `ServerRequest.json` | 包含本类型的内联定义 |

## 依赖与外部交互

### 协议流程中的位置

```
┌─────────────────────────────────────────────────────────────┐
│                     完整交互流程                              │
├─────────────────────────────────────────────────────────────┤
│  1. ServerRequest::ToolRequestUserInput                      │
│     └── params: ToolRequestUserInputParams                   │
│         └── questions: [Question { id: "q1", ... }]          │
│                           ↓                                  │
│  2. 客户端展示表单，用户交互                                  │
│                           ↓                                  │
│  3. 客户端构造 ToolRequestUserInputResponse                  │
│     └── answers: {"q1": Answer { answers: ["value"] }}       │
│                           ↓                                  │
│  4. 服务器接收响应，继续执行                                  │
└─────────────────────────────────────────────────────────────┘
```

### 与请求类型的数据流

```
ToolRequestUserInputParams.questions[].id 
    → 作为键 → ToolRequestUserInputResponse.answers 的键

ToolRequestUserInputOption.label (请求中)
    ← 对应 → ToolRequestUserInputAnswer.answers[] (响应中)
```

### 客户端实现要求

1. **ID 匹配**：必须使用请求中的 `question.id` 作为响应键
2. **答案格式**：
   - 单选：`answers: ["selected_label"]`
   - 多选：`answers: ["label1", "label2"]`
   - 其他输入：`answers: ["custom_text"]`
3. **完整性**：建议回答所有问题，但协议未强制要求

## 风险、边界与改进建议

### 当前风险

1. **实验性状态**
   - 与请求类型同为 EXPERIMENTAL
   - API 变更时需同步更新客户端

2. **验证缺失**
   - Schema 不验证答案是否对应有效问题 ID
   - 不验证答案值是否在预定义选项中
   - 不验证必填问题是否已回答

3. **类型安全**
   - 答案统一使用字符串，类型信息丢失
   - 数字、布尔值需字符串化，可能引入解析错误

### 边界情况

1. **空答案对象**
   ```json
   { "answers": {} }
   ```
   - 用户拒绝回答任何问题的场景
   - 服务器需有默认处理逻辑

2. **未知问题 ID**
   ```json
   { "answers": { "unknown_id": { "answers": ["value"] } } }
   ```
   - 客户端发送了请求中不存在的问题答案
   - 服务器应忽略或报错

3. **空答案数组**
   ```json
   { "answers": { "q1": { "answers": [] } } }
   ```
   - 语义不明确：是未回答还是回答为空？
   - 建议协议明确禁止或定义语义

4. **重复答案**
   ```json
   { "answers": { "q1": { "answers": ["A", "A", "B"] } } }
   ```
   - 多选场景可能出现重复
   - 服务器需决定去重策略

### 改进建议

1. **添加元数据字段**
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       pub metadata: Option<ResponseMetadata>,  // 新增
   }
   
   pub struct ResponseMetadata {
       pub completed: bool,      // 是否完成所有问题
       pub skipped: Vec<String>, // 跳过的问题 ID
       pub timestamp: i64,       // 响应时间戳
   }
   ```

2. **支持答案类型标记**
   ```rust
   pub struct ToolRequestUserInputAnswer {
       pub answers: Vec<Answer>,
   }
   
   pub struct Answer {
       pub value: String,
       pub answer_type: AnswerType,  // Select | Other | Skip
   }
   ```

3. **添加验证错误报告**
   ```rust
   pub struct ToolRequestUserInputResponse {
       pub answers: HashMap<String, ToolRequestUserInputAnswer>,
       pub validation_errors: Option<Vec<ValidationError>>,
   }
   ```

4. **稳定化建议**
   - 收集实际使用数据
   - 定义最小可行功能集
   - 考虑与 MCP Elicitation 响应格式的兼容性
   - 制定明确的版本迁移策略

5. **安全增强**
   - 为 `isSecret` 问题的答案定义加密传输机制
   - 添加答案签名防止篡改
   - 限制答案长度防止 DoS
