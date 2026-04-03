# RawResponseItemCompletedNotification.json 研究文档

## 场景与职责

`RawResponseItemCompletedNotification` 是 Codex App-Server Protocol v2 API 中的服务器通知类型，用于向客户端传递原始的 Responses API 项目完成事件。这是一个内部专用通知（Internal-only），主要用于 Codex Cloud 等内部服务，暴露底层的 OpenAI Responses API 原始数据结构。

## 功能点目的

1. **原始事件透传**: 将底层的 Responses API 项目事件原样透传给需要原始数据的消费者
2. **Codex Cloud 支持**: 为 Codex Cloud 服务提供完整的响应项数据
3. **调试与审计**: 支持详细的 API 调用审计和调试分析
4. **数据完整性**: 保留完整的响应项元数据，包括内部字段

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct RawResponseItemCompletedNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item: ResponseItem,
}
```

### 核心类型定义

**ResponseItem** - Tagged Union（Discriminated Union）:

| 类型 | 说明 |
|------|------|
| `message` | 消息响应项（用户/助手消息） |
| `reasoning` | 推理响应项（思维链内容） |
| `local_shell_call` | 本地 Shell 调用项 |
| `function_call` | 函数调用项 |
| `tool_search_call` | 工具搜索调用项 |
| `function_call_output` | 函数调用输出项 |
| `custom_tool_call` | 自定义工具调用项 |
| `custom_tool_call_output` | 自定义工具调用输出项 |
| `tool_search_output` | 工具搜索输出项 |
| `web_search_call` | Web 搜索调用项 |
| `image_generation_call` | 图像生成调用项 |
| `ghost_snapshot` | Ghost 提交快照项 |
| `compaction` | 上下文压缩项 |
| `other` | 其他类型项 |

### ContentItem 类型

**InputTextContentItem**:
- `type`: "input_text"
- `text`: string

**InputImageContentItem**:
- `type`: "input_image"
- `image_url`: string

**OutputTextContentItem**:
- `type`: "output_text"
- `text`: string

### FunctionCallOutputContentItem 类型

支持工具调用输出的内容项，是 ContentItem 的子集：
- `input_text`: 文本输入
- `input_image`: 图片输入（带可选的 `detail` 字段：auto/low/high/original）

### LocalShellAction 类型

**ExecLocalShellAction**:
- `type`: "exec"
- `command`: string[] - 命令参数数组
- `env`: Record<string, string> | null - 环境变量
- `timeout_ms`: integer | null - 超时（毫秒）
- `user`: string | null - 执行用户
- `working_directory`: string | null - 工作目录

### ReasoningItem 类型

**ReasoningResponseItem**:
- `type`: "reasoning"
- `content`: ReasoningItemContent[] | null - 推理内容
- `encrypted_content`: string | null - 加密内容
- `summary`: ReasoningItemReasoningSummary[] - 推理摘要

**ReasoningItemContent**:
- `reasoning_text`: 推理文本
- `text`: 普通文本

**ReasoningItemReasoningSummary**:
- `summary_text`: 摘要文本

### GhostCommit 类型

- `id`: string - Ghost 提交 ID
- `parent`: string | null - 父提交
- `preexisting_untracked_dirs`: string[] - 预先存在的未跟踪目录
- `preexisting_untracked_files`: string[] - 预先存在的未跟踪文件

### ResponsesApiWebSearchAction 类型

- `search`: 搜索操作（queries: string[] | null, query: string | null）
- `open_page`: 打开页面（url: string | null）
- `find_in_page`: 页面内查找（pattern: string | null, url: string | null）
- `other`: 其他操作

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `RawResponseItemCompletedNotification`: 第 4823 行附近

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_server_notification_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ServerNotification 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 896 行
```rust
/// This event is internal-only. Used by Codex Cloud.
RawResponseItemCompleted => "rawResponseItem/completed" (v2::RawResponseItemCompletedNotification),
```

### 核心依赖类型
- `ResponseItem`: 定义在 `codex_protocol::models::ResponseItem`
- `MessagePhase`: 定义在 `codex_protocol::models::MessagePhase`
- `LocalShellStatus`: 定义在 `codex_protocol::protocol`

## 依赖与外部交互

### 内部依赖
1. **codex_protocol**: 核心协议类型（ResponseItem, MessagePhase 等）
2. **schemars**: JSON Schema 生成
3. **ts_rs**: TypeScript 类型生成
4. **serde**: 序列化/反序列化

### 外部交互
1. **OpenAI Responses API**: 原始数据来源
2. **Codex Cloud**: 主要消费者
3. **审计系统**: 可能用于 API 调用审计

### 数据流
```
OpenAI Responses API -> Codex Core -> ResponseItem -> 
RawResponseItemCompletedNotification -> Client (Codex Cloud)
```

## 风险、边界与改进建议

### 风险点
1. **内部 API 暴露**: 该通知标记为 internal-only，但 schema 中暴露了大量内部细节
2. **数据量大**: ResponseItem 可能包含大量内容（如长文本、多图片），影响传输性能
3. **Schema 复杂性**: 921 行的 JSON Schema，包含大量嵌套和联合类型，验证成本高
4. **版本耦合**: 与 OpenAI Responses API 结构紧密耦合，API 变更会影响兼容性

### 边界情况
1. **加密内容**: `encrypted_content` 字段可能包含无法解析的加密数据
2. **大内容处理**: 单个 ResponseItem 可能非常大（如长推理链）
3. **类型扩展**: 新的 ResponseItem 类型需要更新 union 定义
4. **Ghost 提交**: Ghost 快照包含大量文件路径信息

### 改进建议
1. **访问控制**: 添加权限检查，确保只有授权客户端能订阅此通知
2. **数据裁剪**: 提供字段选择机制，允许客户端只订阅需要的字段
3. **压缩传输**: 对大内容启用压缩（如 gzip）
4. **分页支持**: 对包含数组的项支持分页或流式传输
5. **Schema 拆分**: 将庞大的 ResponseItem 定义拆分为独立文件
6. **版本控制**: 添加 `api_version` 字段跟踪 Responses API 版本
7. **速率限制**: 对高频通知实施速率限制，防止客户端过载
