# ToolRequestUserInputParams.json 深入研究

## 场景与职责

`ToolRequestUserInputParams.json` 是 Codex App Server Protocol 的实验性组件，定义了**服务器向客户端请求用户输入**的参数结构。该类型用于支持交互式工具调用场景，允许 AI 工具在执行过程中向用户提出问题并获取答案。

### 核心使用场景

1. **交互式工具调用**：当 AI 工具需要用户确认或补充信息时
2. **多步骤表单收集**：支持一次性收集多个相关问题的答案
3. **选择性选项**：提供预定义选项供用户选择（单选/多选）
4. **敏感信息输入**：支持标记为 secret 的输入字段（如密码、API 密钥）

### 在协议中的位置

```
ServerRequest
└── ToolRequestUserInput (method: "item/tool/requestUserInput")
    └── params: ToolRequestUserInputParams ← 本文件定义
        └── questions: ToolRequestUserInputQuestion[]
            └── options: ToolRequestUserInputOption[]
```

## 功能点目的

### 1. 问题定义结构（ToolRequestUserInputQuestion）

每个问题包含以下属性：

| 字段 | 类型 | 必填 | 默认值 | 用途 |
|------|------|------|--------|------|
| `id` | string | 是 | - | 问题唯一标识，用于映射答案 |
| `header` | string | 是 | - | 问题标题/分类 |
| `question` | string | 是 | - | 具体问题内容 |
| `options` | Option[] | 否 | null | 预定义选项列表 |
| `isOther` | boolean | 否 | false | 是否允许"其他"自由输入 |
| `isSecret` | boolean | 否 | false | 是否为敏感信息（密码等） |

### 2. 选项定义（ToolRequestUserInputOption）

```json
{
  "label": "选项显示标签",
  "description": "选项详细描述"
}
```

选项设计采用标签+描述的模式，支持丰富的 UI 展示。

### 3. 请求上下文关联

```json
{
  "threadId": "会话标识",
  "turnId": "当前 turn 标识", 
  "itemId": "工具调用项标识",
  "questions": [...]
}
```

通过 `threadId` + `turnId` + `itemId` 三重标识精确定位请求上下文。

## 具体技术实现

### 1. Rust 类型定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs

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

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Represents one request_user_input question and its required options.
pub struct ToolRequestUserInputQuestion {
    pub id: String,
    pub header: String,
    pub question: String,
    #[serde(default)]
    pub is_other: bool,
    #[serde(default)]
    pub is_secret: bool,
    pub options: Option<Vec<ToolRequestUserInputOption>>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL. Defines a single selectable option for request_user_input.
pub struct ToolRequestUserInputOption {
    pub label: String,
    pub description: String,
}
```

### 2. JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ToolRequestUserInputOption": { ... },
    "ToolRequestUserInputQuestion": { ... }
  },
  "properties": {
    "itemId": { "type": "string" },
    "questions": {
      "items": { "$ref": "#/definitions/ToolRequestUserInputQuestion" },
      "type": "array"
    },
    "threadId": { "type": "string" },
    "turnId": { "type": "string" }
  },
  "required": ["itemId", "questions", "threadId", "turnId"]
}
```

### 3. 序列化约定

- **命名风格**：Rust 使用 `snake_case`，JSON/TypeScript 使用 `camelCase`
- **布尔默认值**：`isOther` 和 `isSecret` 默认值为 `false`
- **可选字段**：`options` 为可空数组

### 4. 生成流程

```
Rust 类型定义 (v2.rs)
    ↓ derive(JsonSchema)
schemars schema 生成
    ↓ write_json_schema()
ToolRequestUserInputParams.json
    ↓ generate_ts()
TypeScript 类型定义 (v2/ToolRequestUserInputParams.ts)
```

## 关键代码路径与文件引用

### 源头定义
| 文件 | 行号 | 内容 |
|------|------|------|
| `src/protocol/v2.rs` | 5668-5698 | `ToolRequestUserInputOption`, `ToolRequestUserInputQuestion`, `ToolRequestUserInputParams` 定义 |

### 引用位置
| 文件 | 用途 |
|------|------|
| `src/protocol/common.rs` | `server_request_definitions!` 宏中引用为请求参数类型 |
| `schema/json/ServerRequest.json` | 内联包含本 schema 的定义 |

### 生成输出
| 文件 | 职责 |
|------|------|
| `schema/json/ToolRequestUserInputParams.json` | 本文件 |
| `schema/typescript/v2/ToolRequestUserInputParams.ts` | TypeScript 类型 |
| `schema/typescript/v2/ToolRequestUserInputQuestion.ts` | 问题类型 |
| `schema/typescript/v2/ToolRequestUserInputOption.ts` | 选项类型 |

### 相关测试
| 文件 | 测试内容 |
|------|----------|
| `tests/schema_fixtures.rs` | Schema fixture 一致性验证 |

## 依赖与外部交互

### 上游依赖（被调用方）

1. **工具调用系统**
   - 当 AI 模型调用需要用户输入的工具时触发
   - 通过 `ToolRequestUserInput` ServerRequest 发送给客户端

2. **线程/回合管理**
   - 依赖 `threadId` 和 `turnId` 进行请求路由
   - 与 `ThreadActiveFlag::WaitingOnUserInput` 状态关联

### 下游依赖（调用方）

1. **客户端 UI 实现**
   - CLI：需要实现交互式提示
   - TUI：需要渲染表单界面
   - VS Code：需要展示 WebView 表单

2. **响应类型**
   - 客户端回复使用 `ToolRequestUserInputResponse`
   - 答案映射通过 `question.id` 关联

### 协议交互流程

```
┌─────────┐                    ┌─────────┐
│ Server  │ ──ToolRequestUserInput──> │ Client  │
│         │    (ToolRequestUserInputParams) │         │
│         │ <──────Response─────── │         │
│         │    (ToolRequestUserInputResponse) │         │
└─────────┘                    └─────────┘
```

## 风险、边界与改进建议

### 当前风险

1. **实验性状态**
   - 标记为 `EXPERIMENTAL`，API 可能不兼容变更
   - 生产环境使用存在风险

2. **功能局限**
   - 仅支持选项选择，不支持自由文本输入（除非 `isOther`）
   - 不支持输入验证规则（regex、min/max 等）
   - 不支持条件逻辑（如选择 A 才显示 B）

3. **安全问题**
   - `isSecret` 仅标记语义，实际加密传输需额外实现
   - 敏感信息可能出现在日志中

### 边界情况

1. **空选项列表**
   - `options: null` 时，客户端应如何处理？
   - 当前设计暗示必须有选项，但 schema 允许 null

2. **问题 ID 冲突**
   - 同一请求中 `questions` 数组内的 `id` 必须唯一
   - 重复 ID 会导致答案映射歧义

3. **超长问题列表**
   - 未限制 `questions` 数组长度
   - 大量问题可能导致客户端性能问题

### 改进建议

1. **增强输入类型支持**
   ```rust
   // 建议添加更多输入类型
   pub enum InputType {
       Select,      // 单选
       MultiSelect, // 多选
       Text,        // 自由文本
       Number,      // 数字
       Confirm,     // 是/否确认
   }
   ```

2. **添加验证规则**
   ```json
   {
     "validation": {
       "required": true,
       "minLength": 3,
       "maxLength": 100,
       "pattern": "^[a-zA-Z]+$"
     }
   }
   ```

3. **支持条件显示**
   ```json
   {
     "showWhen": {
       "questionId": "previous_question",
       "equals": "specific_value"
     }
   }
   ```

4. **国际化支持**
   - 添加 `i18n` 字段支持多语言
   - 或支持通过 key 查找翻译

5. **稳定化路径**
   - 收集更多使用反馈
   - 定义明确的稳定化标准
   - 考虑与 MCP Elicitation 的整合

6. **安全增强**
   - 为 `isSecret` 字段定义明确的处理规范
   - 禁止敏感信息进入日志
   - 考虑端到端加密
