# ToolRequestUserInputQuestion 类型研究报告

## 场景与职责

`ToolRequestUserInputQuestion` 是一个 **EXPERIMENTAL** 类型，用于定义 `request_user_input` 工具中的单个问题。它包含了向用户展示问题所需的所有信息，包括问题文本、选项、以及控制问题行为的标志。

**核心使用场景：**

1. **确认对话框**：需要用户确认某个操作（如删除文件、执行命令）
2. **信息收集**：向用户询问特定信息（如 API 密钥、配置参数）
3. **选择题**：用户从预定义选项中选择
4. **多步骤表单**：多个问题组合成完整的表单
5. **敏感信息输入**：密码、密钥等需要保密输入的场景

**典型使用场景：**
```
AI: "I need to perform a potentially dangerous operation."
  Question: {
    header: "Security Confirmation",
    question: "This will delete 3 files. Do you want to proceed?",
    options: [
      { label: "yes", description: "Delete the files" },
      { label: "no", description: "Cancel the operation" }
    ],
    isSecret: false,
    isOther: false
  }
```

## 功能点目的

该类型的设计目的包括：

1. **完整问题定义**：包含标题、问题文本、选项等所有必要信息
2. **灵活输入支持**：支持预定义选项（单选/多选）和自由文本输入
3. **安全输入**：通过 `isSecret` 支持密码等敏感信息输入
4. **扩展输入支持**：通过 `isOther` 支持"其他"选项，允许用户自定义输入
5. **唯一标识**：通过 `id` 字段支持多问题场景下的答案映射

**字段设计意图：**

| 字段 | 目的 |
|------|------|
| `id` | 唯一标识，用于答案映射和问题引用 |
| `header` | 简短标题，用于 UI 标题栏或分组 |
| `question` | 具体问题文本，向用户说明需要什么 |
| `isOther` | 是否允许"其他"选项，支持自由输入 |
| `isSecret` | 是否为敏感信息，控制输入框类型 |
| `options` | 预定义选项列表，`null` 表示自由文本输入 |

## 具体技术实现

### 数据结构定义

**TypeScript 定义（生成代码）：**
```typescript
/**
 * EXPERIMENTAL. Represents one request_user_input question and its required options.
 */
export type ToolRequestUserInputQuestion = { 
  id: string, 
  header: string, 
  question: string, 
  isOther: boolean, 
  isSecret: boolean, 
  options: Array<ToolRequestUserInputOption> | null, 
};
```

**Rust 源定义：**
```rust
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
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `id` | `String` | - | 问题的唯一标识符，用于答案映射 |
| `header` | `String` | - | 问题标题，简短描述 |
| `question` | `String` | - | 具体问题文本 |
| `isOther` | `bool` | `false` | 是否允许"其他"选项（自由输入） |
| `isSecret` | `bool` | `false` | 是否为敏感信息（密码输入） |
| `options` | `Option<Vec<ToolRequestUserInputOption>>` | `None` | 预定义选项，`None` 表示自由文本 |

### 关联类型

| 类型 | 关系 | 说明 |
|------|------|------|
| `ToolRequestUserInputOption` | 子元素 | 定义选项的结构 |
| `ToolRequestUserInputParams` | 父容器 | 包含 `questions: Vec<ToolRequestUserInputQuestion>` |
| `ToolRequestUserInputAnswer` | 对应答案 | 用户对此问题的回答 |

### 输入模式组合

| options | isOther | isSecret | 输入模式 |
|---------|---------|----------|----------|
| `Some([...])` | `false` | `false` | 单选/多选，必须从选项中选择 |
| `Some([...])` | `true` | `false` | 单选/多选 + "其他"，可自定义输入 |
| `None` | `false` | `false` | 自由文本输入 |
| `None` | `false` | `true` | 密码/敏感信息输入 |
| `Some([...])` | `false` | `true` | 从选项中选择密码（不推荐） |

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5674-5687) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputQuestion.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 5697) | 作为 `ToolRequestUserInputParams` 的字段类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ToolRequestUserInputParams.ts` | 导入并作为字段类型使用 |
| `codex-rs/app-server/tests/suite/v2/request_user_input.rs` | 集成测试 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 渲染问题 |
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | 适配器处理 |

### 序列化示例

**选择题模式：**
```json
{
  "id": "action_choice",
  "header": "Choose Action",
  "question": "What would you like to do?",
  "isOther": false,
  "isSecret": false,
  "options": [
    { "label": "run", "description": "Run the command" },
    { "label": "skip", "description": "Skip this step" }
  ]
}
```

**带"其他"选项的选择题：**
```json
{
  "id": "reason",
  "header": "Reason",
  "question": "Why do you want to skip?",
  "isOther": true,
  "isSecret": false,
  "options": [
    { "label": "not_needed", "description": "This step is not needed" },
    { "label": "already_done", "description": "I already did this" }
  ]
}
```

**自由文本输入：**
```json
{
  "id": "feedback",
  "header": "Feedback",
  "question": "Please provide your feedback:",
  "isOther": false,
  "isSecret": false,
  "options": null
}
```

**敏感信息输入：**
```json
{
  "id": "api_key",
  "header": "API Key",
  "question": "Please enter your API key:",
  "isOther": false,
  "isSecret": true,
  "options": null
}
```

## 依赖与外部交互

### 内部依赖

```
ToolRequestUserInputQuestion
  ├── ToolRequestUserInputOption
  ├── serde (Serialize, Deserialize)
  ├── schemars (JsonSchema)
  └── ts_rs (TS)
```

### 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| AI 模型 | 生成 | 构造问题内容 |
| 客户端 UI | 渲染 | 根据字段渲染不同的输入组件 |
| 用户 | 交互 | 根据问题类型提供输入 |

### UI 渲染建议

```typescript
function renderQuestion(question: ToolRequestUserInputQuestion) {
  // 根据 isSecret 选择输入框类型
  const InputComponent = question.isSecret ? PasswordInput : TextInput;
  
  // 根据 options 选择渲染方式
  if (question.options) {
    return (
      <div>
        <h3>{question.header}</h3>
        <p>{question.question}</p>
        <RadioGroup options={question.options} />
        {question.isOther && <InputComponent placeholder="Other..." />}
      </div>
    );
  } else {
    return (
      <div>
        <h3>{question.header}</h3>
        <p>{question.question}</p>
        <InputComponent />
      </div>
    );
  }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为 EXPERIMENTAL，未来可能变更
2. **空字符串字段**：`id`、`header`、`question` 可能为空，导致 UI 问题
3. **options 和 isOther 冲突**：当 `options` 为 `null` 时，`isOther` 无意义
4. **id 冲突**：同一请求中的多个问题可能有相同 id
5. **isSecret 和 options 组合**：从选项中选择敏感信息可能不安全

### 边界情况

| 场景 | 当前行为 | 潜在问题 |
|------|----------|----------|
| 空 id | 允许 | 答案无法映射 |
| 空 header | 允许 | UI 显示问题 |
| 空 question | 允许 | 用户不知道要输入什么 |
| options 为空数组 | 允许 | 无选项可展示 |
| isOther=true, options=null | 允许 | isOther 无意义 |

### 改进建议

1. **添加验证方法**：
   ```rust
   impl ToolRequestUserInputQuestion {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.id.is_empty() {
               return Err(ValidationError::EmptyId);
           }
           if self.header.is_empty() {
               return Err(ValidationError::EmptyHeader);
           }
           if self.question.is_empty() {
               return Err(ValidationError::EmptyQuestion);
           }
           
           // 验证 options 和 isOther 的组合
           if self.options.is_none() && self.is_other {
               tracing::warn!("isOther is true but options is null, isOther has no effect");
           }
           
           // 验证 options 非空
           if let Some(options) = &self.options {
               if options.is_empty() {
                   return Err(ValidationError::EmptyOptions);
               }
               // 验证选项
               for option in options {
                   option.validate()?;
               }
           }
           
           Ok(())
       }
   }
   ```

2. **添加输入验证规则**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub validation: Option<InputValidation>,
   }
   
   pub struct InputValidation {
       pub min_length: Option<u32>,
       pub max_length: Option<u32>,
       pub pattern: Option<String>, // 正则表达式
       pub required: bool,
   }
   ```

3. **支持默认值**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub default_value: Option<String>,
   }
   ```

4. **支持占位符文本**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub placeholder: Option<String>,
   }
   ```

5. **支持多行输入**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(default)]
       pub multiline: bool,
       #[serde(skip_serializing_if = "Option::is_none")]
       pub rows: Option<u32>,
   }
   ```

6. **添加帮助文本**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub help_text: Option<String>,
   }
   ```

7. **支持条件显示**：
   ```rust
   pub struct ToolRequestUserInputQuestion {
       // ... 现有字段
       #[serde(skip_serializing_if = "Option::is_none")]
       pub show_if: Option<Condition>, // 基于其他问题答案的条件
   }
   ```

### 安全考虑

1. **isSecret 字段**：
   - 客户端应使用密码输入框（隐藏输入）
   - 答案在日志中应被脱敏处理
   - 考虑添加自动过期机制

2. **输入验证**：
   - 服务端应对所有输入进行验证
   - 防止命令注入、XSS 等攻击
   - 敏感信息不应在错误消息中暴露

### 实验性状态说明

作为实验性 API，建议：
- 在实际使用中进行充分测试
- 收集不同客户端实现的反馈
- 关注 API 变更通知
- 准备向后兼容的适配层
- 考虑与现有表单库（如 React Hook Form、Formik）的集成
