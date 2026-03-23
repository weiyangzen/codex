# user_input.rs 深度研究文档

## 1. 场景与职责

`user_input.rs` 是 Codex 协议层中负责**用户输入表示**的核心模块。它定义了用户与 AI 交互的所有输入类型，包括文本、图片、技能选择、提及等，是整个 Codex 系统输入层的基石。

### 核心场景

1. **文本输入**：用户输入的普通文本消息
2. **图片输入**：用户上传的图片（URL、本地路径、Base64）
3. **技能选择**：用户选择特定的 Skill 文件
4. **提及（Mention）**：用户显式提及某个应用或插件
5. **富文本元素**：文本中的特殊标记（如图片占位符）

### 职责边界

- 定义所有用户输入类型的枚举（`UserInput`）
- 支持富文本元素（`TextElement`）的标记和范围管理
- 提供字节范围（`ByteRange`）的精确文本定位
- 限制用户输入大小（`MAX_USER_INPUT_TEXT_CHARS`）
- 与 `models.rs` 中的 `ResponseInputItem` 形成输入-输出闭环

---

## 2. 功能点目的

### 2.1 MAX_USER_INPUT_TEXT_CHARS - 输入大小限制

```rust
pub const MAX_USER_INPUT_TEXT_CHARS: usize = 1 << 20;  // 1,048,576 字符
```

**设计意图**：
- 防止单个用户消息占用过大上下文窗口
- 保守设置，平衡用户体验和系统稳定性
- 约 1MB 文本，足够大多数场景使用

### 2.2 UserInput 枚举

```rust
#[non_exhaustive]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum UserInput {
    Text {
        text: String,
        text_elements: Vec<TextElement>,  // 富文本元素
    },
    Image { image_url: String },  // Base64 data URI
    LocalImage { path: PathBuf },  // 本地图片路径
    Skill { name: String, path: PathBuf },  // Skill 选择
    Mention { name: String, path: String },  // 显式提及
}
```

**变体详解**：

| 变体 | 用途 | 典型场景 |
|------|------|----------|
| `Text` | 普通文本输入 | 用户打字消息 |
| `Image` | 预编码图片 | 粘贴图片、截图 |
| `LocalImage` | 本地图片路径 | 拖拽图片到窗口 |
| `Skill` | Skill 选择 | 选择 `.codex/skills/` 下的技能 |
| `Mention` | 显式提及 | `@某个应用` 或 `@某个插件` |

**`#[non_exhaustive]` 作用**：
- 防止外部 crate 穷尽匹配，允许未来添加新变体而不破坏兼容性

### 2.3 TextElement - 富文本元素

```rust
pub struct TextElement {
    pub byte_range: ByteRange,           // 字节范围
    placeholder: Option<String>,         // 占位符文本
}
```

**设计目的**：
- 在纯文本中标记特殊元素（如图片占位符）
- 不修改原始文本，保持数据纯净
- 支持跨历史和恢复的持久化

**使用示例**：
```rust
// 文本: "Check this image: [Image #1] and this: [Image #2]"
// text_elements 标记 [Image #1] 和 [Image #2] 的范围
TextElement {
    byte_range: ByteRange { start: 18, end: 28 },  // "[Image #1]"
    placeholder: Some("[Image #1]".to_string()),
}
```

### 2.4 ByteRange - 字节范围

```rust
pub struct ByteRange {
    pub start: usize,  // 包含
    pub end: usize,    // 不包含
}
```

**设计选择**：
- 使用字节偏移而非字符偏移：与 Rust 字符串内部表示一致
- 标准 Range 语义：`start` 包含，`end` 不包含
- 实现 `From<std::ops::Range<usize>>` 便于转换

### 2.5 TextElement 方法

```rust
impl TextElement {
    pub fn new(byte_range: ByteRange, placeholder: Option<String>) -> Self;
    
    pub fn map_range<F>(&self, map: F) -> Self
    where
        F: FnOnce(ByteRange) -> ByteRange;
    
    pub fn set_placeholder(&mut self, placeholder: Option<String>);
    
    #[doc(hidden)]
    pub fn _placeholder_for_conversion_only(&self) -> Option<&str>;
    
    pub fn placeholder<'a>(&'a self, text: &'a str) -> Option<&'a str>;
}
```

**方法详解**：

| 方法 | 用途 |
|------|------|
| `new` | 构造函数 |
| `map_range` | 范围重映射（文本编辑后更新位置） |
| `set_placeholder` | 设置占位符 |
| `_placeholder_for_conversion_only` | 内部转换使用（doc hidden） |
| `placeholder` | 获取占位符，回退到文本切片 |

---

## 3. 具体技术实现

### 3.1 数据结构关系图

```
MAX_USER_INPUT_TEXT_CHARS: usize = 1_048_576

UserInput (枚举，non_exhaustive)
    ├── Text
    │   ├── text: String
    │   └── text_elements: Vec<TextElement>
    ├── Image
    │   └── image_url: String (Base64 data URI)
    ├── LocalImage
    │   └── path: PathBuf
    ├── Skill
    │   ├── name: String
    │   └── path: PathBuf
    └── Mention
        ├── name: String
        └── path: String

TextElement
    ├── byte_range: ByteRange
    └── placeholder: Option<String>

ByteRange
    ├── start: usize (inclusive)
    └── end: usize (exclusive)
    └── From<std::ops::Range<usize>>
```

### 3.2 序列化配置

```rust
#[serde(tag = "type", rename_all = "snake_case")]
pub enum UserInput {
    Text {
        text: String,
        #[serde(default)]
        text_elements: Vec<TextElement>,
    },
    // ...
}
```

**序列化示例**：
```json
{
    "type": "text",
    "text": "Check this image: [Image #1]",
    "text_elements": [
        {
            "byte_range": {"start": 18, "end": 28},
            "placeholder": "[Image #1]"
        }
    ]
}
```

### 3.3 TextElement 的 placeholder 逻辑

```rust
pub fn placeholder<'a>(&'a self, text: &'a str) -> Option<&'a str> {
    self.placeholder
        .as_deref()
        .or_else(|| text.get(self.byte_range.start..self.byte_range.end))
}
```

**优先级**：
1. 使用显式设置的 `placeholder` 字段
2. 回退到文本中 `byte_range` 指定的切片

**使用场景**：
- 当原始文本可用时，优先使用 `placeholder(text)`
- 当进行类型转换时，使用 `_placeholder_for_conversion_only()`

### 3.4 范围重映射

```rust
pub fn map_range<F>(&self, map: F) -> Self
where
    F: FnOnce(ByteRange) -> ByteRange,
{
    Self {
        byte_range: map(self.byte_range),
        placeholder: self.placeholder.clone(),
    }
}
```

**用途**：
- 文本编辑后更新元素位置
- 复制元素到新文本上下文

---

## 4. 关键代码路径与文件引用

### 4.1 定义位置

```
codex-rs/protocol/src/user_input.rs (109 lines)
```

### 4.2 核心使用路径

```
1. 用户输入提交
   └── codex-rs/protocol/src/protocol.rs
       └── Op::UserInput { items: Vec<UserInput>, ... }
       └── Op::UserTurn { items: Vec<UserInput>, ... }

2. 输入处理
   └── codex-rs/core/src/codex.rs
       └── 解析 UserInput，转换为模型输入

3. 图片处理
   └── codex-rs/protocol/src/models.rs
       └── local_image_content_items_with_label_number()
           └── 将 LocalImage 转换为 Image (Base64)

4. Skill 处理
   └── codex-rs/core/src/skills/
       └── 解析 Skill 变体，加载 SKILL.md

5. Mention 处理
   └── codex-rs/core/src/mentions.rs
       └── 解析 Mention 变体，解析 connector/plugin 路径

6. TUI 输入
   └── codex-rs/tui/src/
       └── 用户输入转换为 UserInput::Text
       └── 图片拖拽转换为 UserInput::LocalImage

7. App Server 协议
   └── codex-rs/app-server-protocol/src/protocol/
       ├── v2.rs - CoreUserInput 导入
       └── common.rs - 请求处理
```

### 4.3 转换流程

```
UserInput::LocalImage { path }
    └── codex-rs/protocol/src/models.rs
        └── local_image_content_items_with_label_number()
            ├── 读取文件 bytes
            ├── load_for_prompt_bytes() - 图片处理
            └── 转换为 ResponseInputItem::Message
                └── ContentItem::InputImage { image_url: data_url }

UserInput::Skill { name, path }
    └── codex-rs/core/src/skills/
        └── 加载 SKILL.md
            └── 注入到系统提示词

UserInput::Mention { name, path }
    └── codex-rs/core/src/mentions.rs
        ├── app://<connector-id> → 应用提及
        └── plugin://<plugin-name>@<marketplace> → 插件提及
```

### 4.4 App Server Protocol 集成

```
codex-rs/app-server-protocol/src/protocol/v2.rs
├── CoreUserInput 导入
├── CoreByteRange 导入
├── CoreTextElement 导入
└── UserInput.ts 生成

codex-rs/app-server-protocol/schema/typescript/v2/UserInput.ts
└── TypeScript 类型定义
```

### 4.5 测试覆盖

```
codex-rs/core/tests/suite/
├── skills.rs - Skill 输入测试
├── plugins.rs - Mention 输入测试
└── view_image.rs - 图片输入测试

codex-rs/protocol/src/models.rs
└── local_image_content_items_with_label_number() 测试
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖模块 | 用途 |
|----------|------|
| `std::path::PathBuf` | 本地路径表示 |
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 5.2 外部使用者

| 使用者 | 用途 |
|--------|------|
| `codex-core` | 输入处理和转换 |
| `codex-app-server` | 输入 API 暴露 |
| `codex-tui` | 用户输入捕获 |
| `codex-exec` | 执行模式输入 |
| `codex-mcp-server` | MCP 工具输入 |

### 5.3 协议集成

```rust
// protocol.rs 中的 Op 定义
pub enum Op {
    UserInput {
        items: Vec<UserInput>,
        final_output_json_schema: Option<Value>,
    },
    UserTurn {
        items: Vec<UserInput>,
        cwd: PathBuf,
        approval_policy: AskForApproval,
        sandbox_policy: SandboxPolicy,
        model: String,
        // ...
    },
    // ...
}
```

### 5.4 与 ResponseInputItem 的关系

```rust
// models.rs
pub enum ResponseInputItem {
    Message { role: String, content: Vec<ContentItem> },
    FunctionCallOutput { call_id: String, output: ... },
    // ...
}

// UserInput 转换为 ResponseInputItem::Message
impl From<UserInput> for ResponseInputItem {
    fn from(input: UserInput) -> Self {
        match input {
            UserInput::Text { text, .. } => ResponseInputItem::Message { ... },
            UserInput::Image { image_url } => ResponseInputItem::Message { ... },
            // ...
        }
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

1. **字节范围与 UTF-8**
   - 风险：`ByteRange` 使用字节偏移，可能切割多字节 UTF-8 字符
   - 缓解：`placeholder()` 方法使用 `text.get()`，自动处理无效范围

2. **图片大小限制**
   - 风险：`MAX_USER_INPUT_TEXT_CHARS` 仅限制文本，不限制图片
   - 建议：添加图片大小独立限制

3. **路径安全**
   - 风险：`LocalImage` 和 `Skill` 包含 `PathBuf`，可能包含恶意路径
   - 缓解：Core 层进行路径验证和沙箱检查

4. **non_exhaustive 兼容性**
   - 风险：外部 crate 无法穷尽匹配，需要 `_ =>` 分支
   - 缓解：这是设计意图，强制前向兼容

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 文本超过 1MB | 被截断或拒绝（取决于调用方） |
| `text_elements` 为空 | 正常处理，视为纯文本 |
| `ByteRange` 越界 | `placeholder()` 返回 `None` |
| `placeholder` 为 `None` | 回退到文本切片 |
| 无效图片路径 | 转换为错误占位符文本 |

### 6.3 改进建议

1. **添加输入验证**
   ```rust
   impl UserInput {
       pub fn validate(&self) -> Result<(), ValidationError> {
           match self {
               UserInput::Text { text, .. } => {
                   if text.len() > MAX_USER_INPUT_TEXT_CHARS {
                       return Err(ValidationError::TooLong);
                   }
               }
               UserInput::LocalImage { path } => {
                   if !path.exists() {
                       return Err(ValidationError::FileNotFound);
                   }
               }
               // ...
           }
           Ok(())
       }
   }
   ```

2. **支持更多输入类型**
   ```rust
   pub enum UserInput {
       // ...
       Audio { audio_url: String },  // 语音输入
       File { path: PathBuf, mime: String },  // 通用文件
       Location { lat: f64, lng: f64 },  // 位置信息
   }
   ```

3. **增强 TextElement**
   ```rust
   pub struct TextElement {
       pub byte_range: ByteRange,
       pub placeholder: Option<String>,
       pub element_type: TextElementType,  // 新增
       pub metadata: Option<Value>,  // 新增
   }
   
   pub enum TextElementType {
       ImagePlaceholder,
       Mention,
       CodeBlock,
       Custom(String),
   }
   ```

4. **添加输入历史**
   ```rust
   pub struct UserInputWithMetadata {
       pub input: UserInput,
       pub timestamp: i64,
       pub source: InputSource,  // Keyboard, Paste, DragDrop, etc.
   }
   ```

5. **支持输入模板**
   ```rust
   pub struct UserInputTemplate {
       pub template: String,
       pub variables: HashMap<String, UserInput>,
   }
   ```

### 6.4 测试建议

1. **边界测试**
   - 1MB 边界文本
   - 空文本
   - 仅包含 emoji 的文本

2. **编码测试**
   - 多字节 UTF-8 字符的范围标记
   - 不同编码的图片路径

3. **转换测试**
   - UserInput → ResponseInputItem round-trip
   - LocalImage → Image (Base64) 转换

4. **序列化测试**
   - JSON 序列化/反序列化
   - TypeScript 类型兼容性

---

## 7. 附录：代码统计

| 指标 | 数值 |
|------|------|
| 文件行数 | 109 |
| 枚举数量 | 1 |
| 结构体数量 | 2 |
| impl 块数量 | 2 |
| 常量定义 | 1 |

---

## 8. 相关文档

- `codex-rs/protocol/src/models.rs` - ResponseInputItem 定义和转换
- `codex-rs/protocol/src/protocol.rs` - Op 定义
- `codex-rs/core/src/mentions.rs` - Mention 处理
- `codex-rs/core/src/skills/` - Skill 处理
- `codex-rs/app-server-protocol/schema/typescript/v2/UserInput.ts` - TypeScript 类型
