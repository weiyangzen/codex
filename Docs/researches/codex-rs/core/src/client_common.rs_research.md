# client_common.rs 研究文档

## 文件信息
- **路径**: `codex-rs/core/src/client_common.rs`
- **大小**: ~11,634 bytes
- **所属模块**: `codex-core`

---

## 一、场景与职责

`client_common.rs` 是 `client.rs` 的配套模块，负责定义 API 请求/响应的共享数据结构和工具类型。它作为客户端层与协议层之间的桥梁，提供：

1. **Prompt 结构**: 封装单次模型调用的完整上下文（输入、工具、指令等）
2. **响应流抽象**: `ResponseStream` 类型，将底层 API 流适配为 Rust Stream trait
3. **工具规范**: `ToolSpec` 枚举，定义 OpenAI Responses API 支持的所有工具类型
4. **Shell 输出重序列化**: 将结构化 Shell 输出转换为人类可读格式

### 架构定位
```
┌─────────────────────────────────────────────────────────────┐
│                    API Client Layer                         │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐         ┌─────────────────────────────┐  │
│  │  client.rs    │◄───────▶│    client_common.rs         │  │
│  │  (通信逻辑)    │         │  (数据结构 & 工具定义)        │  │
│  └───────────────┘         └─────────────────────────────┘  │
│           ▲                            │                    │
│           │                            ▼                    │
│  ┌───────────────┐         ┌─────────────────────────────┐  │
│  │  codex_api    │◄───────▶│  codex_protocol             │  │
│  │  (API 客户端)  │         │  (协议类型定义)              │  │
│  └───────────────┘         └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、功能点目的

### 2.1 Prompt 结构

**目的**: 封装单次模型调用的所有输入参数

**字段说明**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `input` | `Vec<ResponseItem>` | 对话历史输入项 |
| `tools` | `Vec<ToolSpec>` | 可用工具列表（包含 MCP 外部工具） |
| `parallel_tool_calls` | `bool` | 是否允许并行工具调用 |
| `base_instructions` | `BaseInstructions` | 基础系统指令 |
| `personality` | `Option<Personality>` | 模型个性配置 |
| `output_schema` | `Option<Value>` | 输出 JSON Schema（结构化输出） |

**核心方法**:
```rust
impl Prompt {
    /// 获取格式化后的输入，处理 Shell 输出重序列化
    pub(crate) fn get_formatted_input(&self) -> Vec<ResponseItem>;
}
```

### 2.2 Shell 输出重序列化

**目的**: 将 JSON 格式的 Shell 输出转换为更易读的结构化文本格式

**触发条件**: 当工具列表中包含名为 `apply_patch` 的 Freeform 工具时

**转换示例**:
```json
// 原始输出
{"output":"hello","metadata":{"exit_code":0,"duration_seconds":0.5}}

// 转换后
Exit code: 0
Wall time: 0.5 seconds
Output:
hello
```

**处理流程**:
1. 扫描 `tools` 列表，检查是否包含 `apply_patch` Freeform 工具
2. 遍历 `input` 中的所有 `ResponseItem`
3. 识别 Shell 调用和输出项（通过 `call_id` 关联）
4. 解析 JSON 输出，提取 `exit_code`、`duration_seconds` 和 `output`
5. 重新格式化为结构化文本

### 2.3 ToolSpec 枚举

**目的**: 定义所有支持的工具类型，可直接序列化为 OpenAI Responses API 的 Tool 格式

**工具类型**:
| 变体 | 序列化类型 | 说明 |
|------|-----------|------|
| `Function` | `function` | 标准函数工具 |
| `ToolSearch` | `tool_search` | 工具搜索 |
| `LocalShell` | `local_shell` | 本地 Shell 执行 |
| `ImageGeneration` | `image_generation` | 图像生成 |
| `WebSearch` | `web_search` | 网络搜索 |
| `Freeform` | `custom` | 自定义/自由格式工具 |

### 2.4 ResponseStream

**目的**: 将 `tokio::sync::mpsc` 通道适配为 `futures::Stream`

```rust
pub struct ResponseStream {
    pub(crate) rx_event: mpsc::Receiver<Result<ResponseEvent>>,
}

impl Stream for ResponseStream {
    type Item = Result<ResponseEvent>;
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) 
        -> Poll<Option<Self::Item>>;
}
```

---

## 三、具体技术实现

### 3.1 关键数据结构

#### Prompt
```rust
#[derive(Default, Debug, Clone)]
pub struct Prompt {
    pub input: Vec<ResponseItem>,
    pub(crate) tools: Vec<ToolSpec>,
    pub(crate) parallel_tool_calls: bool,
    pub base_instructions: BaseInstructions,
    pub personality: Option<Personality>,
    pub output_schema: Option<Value>,
}
```

#### ToolSpec 枚举
```rust
#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "type")]
pub(crate) enum ToolSpec {
    #[serde(rename = "function")]
    Function(ResponsesApiTool),
    
    #[serde(rename = "tool_search")]
    ToolSearch {
        execution: String,
        description: String,
        parameters: JsonSchema,
    },
    
    #[serde(rename = "local_shell")]
    LocalShell {},
    
    #[serde(rename = "image_generation")]
    ImageGeneration { output_format: String },
    
    #[serde(rename = "web_search")]
    WebSearch {
        #[serde(skip_serializing_if = "Option::is_none")]
        external_web_access: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none")]
        filters: Option<ResponsesApiWebSearchFilters>,
        #[serde(skip_serializing_if = "Option::is_none")]
        user_location: Option<ResponsesApiWebSearchUserLocation>,
        #[serde(skip_serializing_if = "Option::is_none")]
        search_context_size: Option<WebSearchContextSize>,
        #[serde(skip_serializing_if = "Option::is_none")]
        search_content_types: Option<Vec<String>>,
    },
    
    #[serde(rename = "custom")]
    Freeform(FreeformTool),
}
```

#### ResponsesApiTool
```rust
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ResponsesApiTool {
    pub(crate) name: String,
    pub(crate) description: String,
    pub(crate) strict: bool,  // TODO: 需要验证逻辑
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) defer_loading: Option<bool>,
    pub(crate) parameters: JsonSchema,
    #[serde(skip)]  // 输出模式不发送到 API
    pub(crate) output_schema: Option<Value>,
}
```

#### FreeformTool
```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FreeformTool {
    pub(crate) name: String,
    pub(crate) description: String,
    pub(crate) format: FreeformToolFormat,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FreeformToolFormat {
    pub(crate) r#type: String,
    pub(crate) syntax: String,
    pub(crate) definition: String,
}
```

### 3.2 Shell 输出重序列化实现

#### 核心函数
```rust
fn reserialize_shell_outputs(items: &mut [ResponseItem]) {
    let mut shell_call_ids: HashSet<String> = HashSet::new();

    items.iter_mut().for_each(|item| match item {
        // 第一遍：收集所有 Shell 调用的 call_id
        ResponseItem::LocalShellCall { call_id, id, .. } => {
            if let Some(identifier) = call_id.clone().or_else(|| id.clone()) {
                shell_call_ids.insert(identifier);
            }
        }
        ResponseItem::CustomToolCall { call_id, name, .. } if name == "apply_patch" => {
            shell_call_ids.insert(call_id.clone());
        }
        ResponseItem::FunctionCall { name, call_id, .. } 
            if is_shell_tool_name(name) || name == "apply_patch" => {
            shell_call_ids.insert(call_id.clone());
        }
        
        // 第二遍：处理输出项
        ResponseItem::FunctionCallOutput { call_id, output, .. }
        | ResponseItem::CustomToolCallOutput { call_id, output, .. } => {
            if shell_call_ids.remove(call_id)
                && let Some(structured) = output
                    .text_content()
                    .and_then(parse_structured_shell_output)
            {
                output.body = FunctionCallOutputBody::Text(structured);
            }
        }
        _ => {}
    })
}
```

#### 解析结构化输出
```rust
#[derive(Deserialize)]
struct ExecOutputJson {
    output: String,
    metadata: ExecOutputMetadataJson,
}

#[derive(Deserialize)]
struct ExecOutputMetadataJson {
    exit_code: i32,
    duration_seconds: f32,
}

fn parse_structured_shell_output(raw: &str) -> Option<String> {
    let parsed: ExecOutputJson = serde_json::from_str(raw).ok()?;
    Some(build_structured_output(&parsed))
}

fn build_structured_output(parsed: &ExecOutputJson) -> String {
    let mut sections = Vec::new();
    sections.push(format!("Exit code: {}", parsed.metadata.exit_code));
    sections.push(format!(
        "Wall time: {} seconds",
        parsed.metadata.duration_seconds
    ));

    let mut output = parsed.output.clone();
    if let Some((stripped, total_lines)) = strip_total_output_header(&parsed.output) {
        sections.push(format!("Total output lines: {total_lines}"));
        output = stripped.to_string();
    }

    sections.push("Output:".to_string());
    sections.push(output);

    sections.join("\n")
}
```

### 3.3 常量定义

```rust
/// Review thread system prompt. Edit `core/src/review_prompt.md` to customize.
pub const REVIEW_PROMPT: &str = include_str!("../review_prompt.md");

// Review 相关模板
pub const REVIEW_EXIT_SUCCESS_TMPL: &str = include_str!("../templates/review/exit_success.xml");
pub const REVIEW_EXIT_INTERRUPTED_TMPL: &str = 
    include_str!("../templates/review/exit_interrupted.xml");
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 依赖文件/模块 | 用途 |
|--------------|------|
| `tools/spec.rs` | `JsonSchema` 类型定义 |
| `config/types.rs` | `Personality` 配置类型 |
| `codex_protocol::models` | `BaseInstructions`, `ResponseItem`, `FunctionCallOutputBody` |
| `codex_protocol::config_types` | `WebSearchContextSize`, `WebSearchFilters` 等 |

### 4.2 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_api::common` | `ResponseEvent` 重导出 |
| `futures` | `Stream` trait 实现 |
| `serde` | 序列化/反序列化 |
| `serde_json` | JSON Value 类型 |
| `tokio::sync::mpsc` | 异步通道 |

### 4.3 关键代码路径

**Prompt 格式化路径**:
```
Prompt::get_formatted_input()
  → 检查是否包含 apply_patch Freeform 工具
  → reserialize_shell_outputs(&mut input)
    → 第一遍扫描收集 shell_call_ids
    → 第二遍处理输出项
      → parse_structured_shell_output()
        → build_structured_output()
```

**ToolSpec 序列化路径**:
```
ToolSpec → serde::Serialize 
  → 根据变体类型序列化为不同 JSON 结构
  → 使用 #[serde(tag = "type")] 实现多态序列化
```

**ResponseStream 消费路径**:
```
client.stream() → ResponseStream
  → Stream::poll_next()
    → mpsc::Receiver::poll_recv()
      → 从通道接收 Result<ResponseEvent>
```

---

## 五、依赖与外部交互

### 5.1 与 tools/spec.rs 的交互

```rust
use crate::tools::spec::JsonSchema;

// ResponsesApiTool 使用 JsonSchema 定义参数
pub struct ResponsesApiTool {
    pub(crate) parameters: JsonSchema,
    ...
}
```

### 5.2 与 codex_protocol 的交互

```rust
use codex_protocol::models::BaseInstructions;
use codex_protocol::models::FunctionCallOutputBody;
use codex_protocol::models::ResponseItem;
use codex_protocol::config_types::WebSearchContextSize;

// Prompt 结构体依赖协议层类型
pub struct Prompt {
    pub input: Vec<ResponseItem>,
    pub base_instructions: BaseInstructions,
    ...
}
```

### 5.3 与 codex_api 的交互

```rust
pub use codex_api::common::ResponseEvent;
// ResponseEvent 从 API 层重导出，用于 ResponseStream
```

---

## 六、风险、边界与改进建议

### 6.1 潜在风险

#### 1. Shell 输出重序列化的条件判断
**风险**: 仅当存在 `apply_patch` Freeform 工具时才触发重序列化，可能遗漏其他需要类似处理的场景
```rust
let is_freeform_apply_patch_tool_present = self.tools.iter().any(|tool| match tool {
    ToolSpec::Freeform(f) => f.name == "apply_patch",
    _ => false,
});
```
**建议**: 考虑将重序列化逻辑扩展到所有 Shell 相关工具，或提供配置选项

#### 2. JSON 解析失败静默处理
**风险**: `parse_structured_shell_output` 使用 `ok()` 忽略解析错误，可能导致输出未按预期转换而不被察觉
```rust
fn parse_structured_shell_output(raw: &str) -> Option<String> {
    let parsed: ExecOutputJson = serde_json::from_str(raw).ok()?;  // 静默失败
    ...
}
```

#### 3. ToolSpec 的 strict 字段验证缺失
**风险**: 代码注释明确标注了 TODO，但目前没有验证逻辑
```rust
/// TODO: Validation. When strict is set to true, the JSON schema,
/// `required` and `additional_properties` must be present...
pub(crate) strict: bool,
```

### 6.2 边界条件

| 边界条件 | 处理策略 |
|----------|----------|
| 空 tools 列表 | 正常处理，无工具可用 |
| 非 JSON 格式的 Shell 输出 | `parse_structured_shell_output` 返回 `None`，保持原样 |
| 缺少 metadata 字段 | 解析失败，保持原样 |
| call_id 不匹配 | 输出项不被处理，保持原样 |
| 重复的 call_id | 仅第一次匹配有效（`remove` 操作） |

### 6.3 改进建议

#### 1. Shell 输出重序列化增强
```rust
// 当前：仅处理 apply_patch
// 建议：可配置的工具名列表，或基于输出格式自动检测
pub struct ShellOutputConfig {
    tool_names: Vec<String>,
    auto_detect_json: bool,
}
```

#### 2. 添加重序列化调试日志
```rust
fn reserialize_shell_outputs(items: &mut [ResponseItem]) {
    trace!("Starting shell output reserialization for {} items", items.len());
    // ... 处理逻辑
    if shell_call_ids.is_empty() {
        trace!("No shell calls found for reserialization");
    }
}
```

#### 3. ToolSpec 验证实现
```rust
impl ResponsesApiTool {
    pub fn validate(&self) -> Result<(), ToolValidationError> {
        if self.strict {
            // 验证 required 和 additional_properties 存在
            // 验证 properties 中所有字段都在 required 中
        }
        Ok(())
    }
}
```

#### 4. Prompt 构建器模式
```rust
// 当前直接使用结构体字段
// 建议：提供 Builder 模式简化构造
let prompt = Prompt::builder()
    .input(items)
    .tool(ToolSpec::Function(...))
    .parallel_tool_calls(true)
    .build()?;
```

### 6.4 测试覆盖

现有测试在 `client_common_tests.rs` 中覆盖：
- `serializes_text_verbosity_when_set`: 文本详细程度序列化
- `serializes_text_schema_with_strict_format`: JSON Schema 序列化
- `omits_text_when_not_set`: 空值省略
- `serializes_flex_service_tier_when_set`: ServiceTier 序列化
- `reserializes_shell_outputs_for_function_and_custom_tool_calls`: Shell 输出重序列化
- `tool_search_output_namespace_serializes_with_deferred_child_tools`: 命名空间工具序列化

建议增加：
- `Prompt::get_formatted_input` 的完整流程测试
- 各种 `ToolSpec` 变体的序列化/反序列化测试
- 边界条件测试（空输入、无效 JSON 等）
