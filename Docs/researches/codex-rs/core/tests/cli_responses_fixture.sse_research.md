# cli_responses_fixture.sse 研究文档

## 场景与职责

`cli_responses_fixture.sse` 是一个 **SSE（Server-Sent Events）格式的测试固件文件**，用于模拟 OpenAI Responses API 的流式响应。该文件在 CLI（命令行界面）相关的集成测试中作为 Mock 服务器的响应数据源。

核心职责：
1. **提供标准化的 SSE 响应格式**：模拟真实的 Responses API 流式输出
2. **支持测试场景**：为 CLI 测试提供可预测的模型响应
3. **验证 SSE 解析逻辑**：确保客户端能正确解析各种事件类型

## 功能点目的

### SSE 事件结构

该固件文件包含三个 SSE 事件，模拟一个完整的响应周期：

```
event: response.created
data: {"type":"response.created","response":{"id":"resp1"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"fixture hello"}]}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp1","output":[]}}
```

### 事件序列说明

| 事件类型 | 目的 |
|---------|------|
| `response.created` | 表示响应创建成功，包含响应 ID |
| `response.output_item.done` | 表示输出项完成，包含助手的回复内容 |
| `response.completed` | 表示整个响应流程完成 |

### 使用场景

该固件主要用于：
1. **CLI 端到端测试**：验证命令行工具能正确处理流式响应
2. **SSE 解析测试**：验证事件流解析逻辑
3. **响应处理测试**：验证客户端对各种事件类型的处理

## 具体技术实现

### SSE 格式规范

SSE（Server-Sent Events）是一种服务器向客户端推送实时更新的标准：

```
event: <event_type>     # 事件类型
data: <json_payload>    # JSON 格式的数据负载
                        # 空行表示事件结束
```

### 数据结构

#### 1. response.created
```json
{
  "type": "response.created",
  "response": {
    "id": "resp1"
  }
}
```

#### 2. response.output_item.done
```json
{
  "type": "response.output_item.done",
  "item": {
    "type": "message",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": "fixture hello"
      }
    ]
  }
}
```

#### 3. response.completed
```json
{
  "type": "response.completed",
  "response": {
    "id": "resp1",
    "output": []
  }
}
```

### 代码引用

该固件文件在测试代码中的使用方式（参考 `core_test_support` 模块）：

```rust
// 通过 load_sse_fixture 函数加载
pub fn load_sse_fixture(path: impl AsRef<std::path::Path>) -> String {
    let events: Vec<serde_json::Value> =
        serde_json::from_reader(std::fs::File::open(path).expect("read fixture"))
            .expect("parse JSON fixture");
    events
        .into_iter()
        .map(|e| {
            let kind = e.get("type").and_then(|v| v.as_str()).expect("fixture event missing type");
            if e.as_object().map(|o| o.len() == 1).unwrap_or(false) {
                format!("event: {kind}\n\n")
            } else {
                format!("event: {kind}\ndata: {e}\n\n")
            }
        })
        .collect()
}
```

## 依赖与外部交互

### 消费方

| 组件 | 用途 |
|------|------|
| CLI 集成测试 | 模拟模型响应 |
| SSE 解析器测试 | 验证事件流解析 |
| Mock 服务器 | 作为响应体返回 |

### 相关代码

- `codex-rs/core/tests/common/lib.rs` - `load_sse_fixture` 函数
- `codex-rs/core/tests/common/responses.rs` - SSE 响应构建工具
- `codex-rs/codex-api/src/sse.rs` - SSE 流处理

## 风险、边界与改进建议

### 风险点

1. **格式兼容性**：如果 Responses API 的事件格式发生变化，固件需要同步更新
2. **事件完整性**：固件仅包含基本事件，可能无法覆盖所有边缘情况
3. **编码问题**：文件需要保持 UTF-8 编码，且行尾格式需符合 SSE 规范

### 边界条件

- 该固件模拟的是**简单文本响应**，不包含：
  - 工具调用（function_call）
  - 推理内容（reasoning）
  - 多轮对话上下文
  - 错误响应

### 改进建议

1. **扩展固件集**：创建更多固件文件覆盖不同场景：
   - `cli_responses_fixture_with_tool_call.sse` - 包含工具调用的响应
   - `cli_responses_fixture_with_error.sse` - 错误响应场景
   - `cli_responses_fixture_streaming.sse` - 分块流式响应

2. **文档化**：在文件头部添加注释说明固件的使用场景和更新流程

3. **版本控制**：如果 API 格式变化，考虑添加版本标识（如 `cli_responses_fixture_v2.sse`）

4. **自动生成**：考虑从实际 API 响应自动生成固件，确保与生产环境一致

---

**相关文件**：
- `codex-rs/core/tests/common/lib.rs` - 固件加载函数
- `codex-rs/codex-api/src/sse.rs` - SSE 流处理实现
- `codex-rs/protocol/src/models.rs` - 响应模型定义
