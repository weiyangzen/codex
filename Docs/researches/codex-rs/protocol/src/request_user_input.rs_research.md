# request_user_input.rs 深度研究文档

## 1. 场景与职责

`request_user_input.rs` 是 Codex 协议层中负责**交互式用户输入**的核心模块。它定义了 AI Agent 在执行任务过程中，向用户发起结构化问答的完整数据结构和交互协议。

### 核心场景

1. **计划确认**：AI 制定计划后，向用户展示选项并等待确认
2. **参数收集**：需要用户输入特定参数（如文件名、选择项等）
3. **分支决策**：在多个执行路径中，由用户选择具体方案
4. **敏感操作确认**：执行破坏性操作前的二次确认

### 职责边界

- 定义交互式问答的数据结构（Question/Option/Args/Response/Event）
- 支持多种问题类型（单选、多选、自由输入等）
- 提供问题元数据（header、description、secret 标记等）
- 与 `protocol.rs` 中的 `Op::UserInputAnswer` 形成请求-响应闭环

---

## 2. 功能点目的

### 2.1 RequestUserInputQuestionOption - 选项定义

```rust
pub struct RequestUserInputQuestionOption {
    pub label: String,        // 选项标签（简短）
    pub description: String,  // 选项描述（详细）
}
```

**设计意图**：
- `label`：UI 中直接显示的简短文本（如 "Yes (Recommended)"）
- `description`：鼠标悬停或展开时显示的详细说明

### 2.2 RequestUserInputQuestion - 问题定义

```rust
pub struct RequestUserInputQuestion {
    pub id: String,                    // 问题唯一标识
    pub header: String,                // 问题标题/分类
    pub question: String,              // 具体问题文本
    #[serde(rename = "isOther", default)]
    pub is_other: bool,                // 是否允许"其他"选项
    #[serde(rename = "isSecret", default)]
    pub is_secret: bool,               // 是否敏感（密码等）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<RequestUserInputQuestionOption>>,  // 预设选项
}
```

**关键字段解析**：

| 字段 | 用途 | 序列化 |
|------|------|--------|
| `id` | 答案映射的键 | 原样 |
| `header` | UI 分组显示 | 原样 |
| `question` | 核心问题文本 | 原样 |
| `is_other` | 允许自由输入 | camelCase (`isOther`) |
| `is_secret` | 密码输入框 | camelCase (`isSecret`) |
| `options` | 预设选项列表 | 省略空值 |

### 2.3 RequestUserInputArgs - 工具调用参数

```rust
pub struct RequestUserInputArgs {
    pub questions: Vec<RequestUserInputQuestion>,  // 问题列表（1-3个）
}
```

**约束**：
- 最多支持 3 个问题（由工具描述强制执行）
- 每个问题必须有非空选项（`is_other` 除外）

### 2.4 RequestUserInputAnswer - 用户答案

```rust
pub struct RequestUserInputAnswer {
    pub answers: Vec<String>,  // 答案列表（支持多选）
}
```

**设计特点**：
- 使用 `Vec<String>` 支持多选场景
- 单选时列表长度为 1
- 自由输入时内容为自定义文本

### 2.5 RequestUserInputResponse - 响应结构

```rust
pub struct RequestUserInputResponse {
    pub answers: HashMap<String, RequestUserInputAnswer>,  // question_id → answers
}
```

**映射关系**：
- Key：`RequestUserInputQuestion.id`
- Value：该问题的所有答案

### 2.6 RequestUserInputEvent - 事件通知

```rust
pub struct RequestUserInputEvent {
    pub call_id: String,     // Responses API 调用 ID
    #[serde(default)]
    pub turn_id: String,     // 所属回合 ID（向后兼容）
    pub questions: Vec<RequestUserInputQuestion>,
}
```

---

## 3. 具体技术实现

### 3.1 数据结构关系图

```
RequestUserInputQuestionOption
    ├── label: String
    └── description: String

RequestUserInputQuestion
    ├── id: String
    ├── header: String
    ├── question: String
    ├── is_other: bool (序列化为 isOther)
    ├── is_secret: bool (序列化为 isSecret)
    └── options: Option<Vec<RequestUserInputQuestionOption>>

RequestUserInputArgs
    └── questions: Vec<RequestUserInputQuestion>

RequestUserInputAnswer
    └── answers: Vec<String>

RequestUserInputResponse
    └── answers: HashMap<String, RequestUserInputAnswer>

RequestUserInputEvent
    ├── call_id: String
    ├── turn_id: String
    └── questions: Vec<RequestUserInputQuestion>
```

### 3.2 序列化配置详解

```rust
// 问题结构体的字段重命名
#[serde(rename = "isOther", default)]
pub is_other: bool,

#[serde(rename = "isSecret", default)]
pub is_secret: bool,
```

**配置解析**：
- `rename`：将 Rust 的 snake_case 映射为 JSON 的 camelCase
- `default`：字段缺失时使用默认值（`false`）

```rust
// 选项字段的省略策略
#[serde(skip_serializing_if = "Option::is_none")]
pub options: Option<Vec<RequestUserInputQuestionOption>>,
```

**作用**：当 `options` 为 `None` 时，序列化结果中不包含该字段。

### 3.3 多平台类型生成

```rust
// 所有类型都派生 TS trait
#[derive(..., TS)]
```

生成的 TypeScript 类型位于：
```
codex-rs/app-server-protocol/schema/typescript/v2/
├── ToolRequestUserInputQuestion.ts
├── ToolRequestUserInputParams.ts
├── ToolRequestUserInputResponse.ts
└── ToolRequestUserInputAnswer.ts
```

---

## 4. 关键代码路径与文件引用

### 4.1 定义位置

```
codex-rs/protocol/src/request_user_input.rs (55 lines)
```

### 4.2 核心调用路径

```
1. 模型调用 request_user_input 工具
   └── codex-rs/core/src/tools/handlers/request_user_input.rs
       └── RequestUserInputHandler::handle()
           ├── 检查模式可用性: request_user_input_is_available()
           ├── 解析参数: RequestUserInputArgs
           ├── 验证选项非空
           ├── 设置 is_other = true（强制允许自由输入）
           └── 发送请求: session.request_user_input()
               └── 生成: RequestUserInputEvent

2. 事件传播到客户端
   └── codex-rs/protocol/src/protocol.rs
       └── EventMsg::RequestUserInput(RequestUserInputEvent)

3. 客户端处理（TUI）
   ├── codex-rs/tui/src/bottom_pane/request_user_input/mod.rs
   ├── codex-rs/tui/src/bottom_pane/request_user_input/layout.rs
   ├── codex-rs/tui/src/bottom_pane/request_user_input/render.rs
   └── codex-rs/tui/src/chatwidget/interrupts.rs

4. 用户响应
   └── Op::UserInputAnswer
       └── 包含: RequestUserInputResponse
```

### 4.3 模式限制

```rust
// codex-rs/core/src/tools/handlers/request_user_input.rs
fn request_user_input_is_available(mode: ModeKind, default_mode_request_user_input: bool) -> bool {
    mode.allows_request_user_input()
        || (default_mode_request_user_input && mode == ModeKind::Default)
}
```

**可用模式**：
- `Plan` 模式：始终可用
- `Default` 模式：需要启用 `DefaultModeRequestUserInput` feature
- `Execute`/`PairProgramming` 模式：不可用

### 4.4 测试覆盖

```
codex-rs/core/tests/suite/request_user_input.rs (323 lines)
├── request_user_input_round_trip_resolves_pending
├── request_user_input_rejected_in_execute_mode_alias
├── request_user_input_rejected_in_default_mode_by_default
├── request_user_input_round_trip_in_default_mode_with_feature
└── request_user_input_rejected_in_pair_mode_alias

codex-rs/app-server/tests/suite/v2/request_user_input.rs
└── App Server v2 API 测试
```

### 4.5 App Server Protocol 集成

```
codex-rs/app-server-protocol/src/protocol/v2.rs
└── ToolRequestUserInputParams / ToolRequestUserInputResponse 定义

codex-rs/app-server-protocol/src/protocol/common.rs
└── 客户端请求处理
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `std::collections::HashMap` | 答案映射存储 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 5.2 外部使用者

| 使用者 | 用途 |
|--------|------|
| `codex-core` | 工具处理实现 |
| `codex-app-server` | 事件转发和 API 暴露 |
| `codex-tui` | UI 渲染和用户交互 |
| `codex-tui_app_server` | 请求处理 |

### 5.3 协议集成

```rust
// protocol.rs 中的事件定义
pub enum EventMsg {
    // ...
    RequestUserInput(RequestUserInputEvent),
    // ...
}

// Op 中的响应定义
pub enum Op {
    // ...
    UserInputAnswer {
        id: String,
        response: RequestUserInputResponse,
    },
    // ...
}
```

### 5.4 导出宏

```rust
// protocol.rs 中的导出
pub use crate::request_user_input::RequestUserInputEvent;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

1. **模式可用性混淆**
   - 风险：用户在不同模式下看到不同的工具可用性
   - 缓解：工具描述明确说明可用模式

2. **is_other 强制启用**
   - 风险：所有问题都允许自由输入，可能不符合预期
   - 代码：`question.is_other = true;`（强制设置）
   - 建议：评估是否应该保留模型原始设置

3. **选项验证不足**
   - 风险：空选项列表可能导致 UI 渲染问题
   - 现状：handler 中检查 `missing_options`

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| `questions` 为空 | 工具返回错误 |
| `options` 为空且 `is_other` 为 false | 工具返回错误 |
| 问题数量 > 3 | 工具描述限制，实际未强制检查 |
| 用户取消输入 | 返回 `None`，工具返回错误消息 |
| 模式不支持 | 返回错误：`request_user_input is unavailable in X mode` |

### 6.3 改进建议

1. **支持更多问题类型**
   ```rust
   pub enum QuestionType {
       SingleChoice,   // 单选
       MultipleChoice, // 多选
       TextInput,      // 文本输入
       NumberInput,    // 数字输入
       Confirm,        // 是/否确认
   }
   ```

2. **添加验证规则**
   ```rust
   pub struct RequestUserInputQuestion {
       // ...
       pub validation: Option<ValidationRule>,  // 新增
   }
   
   pub enum ValidationRule {
       MinLength(usize),
       MaxLength(usize),
       Pattern(String),  // 正则表达式
       Required,
   }
   ```

3. **支持条件问题**
   ```rust
   pub struct RequestUserInputQuestion {
       // ...
       pub depends_on: Option<String>,  // 依赖的问题 id
       pub show_when: Option<Condition>, // 显示条件
   }
   ```

4. **改进错误处理**
   - 当前：取消时返回通用错误
   - 建议：区分用户取消、超时、网络错误等情况

5. **支持问题分组**
   ```rust
   pub struct QuestionGroup {
       pub header: String,
       pub questions: Vec<RequestUserInputQuestion>,
   }
   ```

### 6.4 测试建议

1. 添加并发请求测试
2. 测试超长问题/选项文本的渲染
3. 测试特殊字符（Unicode、HTML 标签等）的处理
4. 测试会话恢复后的输入状态
5. 测试网络断开时的超时行为

---

## 7. 附录：代码统计

| 指标 | 数值 |
|------|------|
| 文件行数 | 55 |
| 结构体数量 | 5 |
| 派生宏使用 | 全部使用 `#[derive(...)]` |
| 测试用例（相关）| 5+ |

---

## 8. 相关文档

- `codex-rs/protocol/src/protocol.rs` - 事件和 Op 定义
- `codex-rs/core/src/tools/handlers/request_user_input.rs` - 工具处理实现
- `codex-rs/tui/src/bottom_pane/request_user_input/` - TUI 渲染实现
- `codex-rs/app-server-protocol/src/protocol/v2.rs` - App Server v2 协议
