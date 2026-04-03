# request_user_input.rs 研究文档

## 场景与职责

本文件是 Codex App Server v2 API 的集成测试套件的一部分，专门测试**用户输入请求工具** (`request_user_input`) 的完整流程。该工具允许 AI 在执行关键操作前，以结构化方式向用户提问并获取确认或选择。

测试场景覆盖：
1. **用户输入请求完整流程** - 从 AI 发起提问到用户回答的端到端测试
2. **协作模式集成** - 验证在 Plan 模式下用户输入请求的行为
3. **结构化问答** - 测试复杂问题结构（多选项、确认等）

## 功能点目的

### 1. 用户输入请求工作流
当 AI 需要用户确认或选择时：
1. AI 调用 `request_user_input` 工具，传入问题列表
2. 服务器向客户端发送 `ToolRequestUserInput` 服务器请求
3. 客户端展示交互式 UI（确认框、单选、多选等）
4. 用户回答后，客户端发送响应
5. AI 继续执行，使用用户输入

### 2. 问题结构
- **ID**: 问题唯一标识
- **Header**: 标题
- **Question**: 问题描述
- **Options**: 选项列表（含标签和描述）

### 3. 协作模式支持
测试特别验证了在 Plan 协作模式下：
- 使用 `CollaborationMode` 配置
- 指定 `ModeKind::Plan` 和推理配置
- 用户输入请求在计划执行流程中的集成

## 具体技术实现

### 关键流程

```
测试用例: request_user_input_round_trip
1. 创建 mock Responses API 服务器
   - 配置返回 request_user_input 工具调用
   - 配置返回最终助手消息
2. 初始化 MCP 连接
3. 启动线程 (thread/start)
4. 开始回合 (turn/start) 触发 AI 响应
   - 配置协作模式为 Plan
   - 配置推理努力程度为 Medium
5. 接收 ServerRequest::ToolRequestUserInput
6. 验证请求参数 (thread_id, turn_id, item_id, questions)
7. 发送用户回答响应
8. 等待 serverRequest/resolved 通知
9. 等待 turn/completed 通知
```

### 核心数据结构

```rust
// AI 发起的用户输入请求参数
request_user_input 工具参数:
{
    "questions": [{
        "id": "confirm_path",
        "header": "Confirm",
        "question": "Proceed with the plan?",
        "options": [{
            "label": "Yes (Recommended)",
            "description": "Continue the current plan."
        }, {
            "label": "No",
            "description": "Stop and revisit the approach."
        }]
    }]
}

// 服务器请求
ServerRequest::ToolRequestUserInput {
    request_id: String,
    params: ToolRequestUserInputParams {
        thread_id: String,
        turn_id: String,
        item_id: String,
        questions: Vec<Question>,
    },
}

// 客户端响应
{
    "answers": {
        "confirm_path": {
            "answers": ["yes"]
        }
    }
}
```

### 协作模式配置

```rust
CollaborationMode {
    mode: ModeKind::Plan,
    settings: Settings {
        model: "mock-model".to_string(),
        reasoning_effort: Some(ReasoningEffort::Medium),
        developer_instructions: None,
    },
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/request_user_input.rs` - 本测试文件

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `read_stream_until_request_message()` - 读取服务器请求
  - `send_response()` - 发送客户端响应

- `codex-rs/app-server/tests/common/responses.rs`
  - `create_request_user_input_sse_response()` - 构造用户输入请求 SSE 响应
  - `create_final_assistant_message_sse_response()` - 构造最终消息 SSE 响应

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/common.rs`
  - `ToolRequestUserInput => "tool/requestUserInput"` (服务器请求)
  - `ServerRequestResolved => "serverRequest/resolved"` (通知)

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `ToolRequestUserInputParams`
  - `Question` 结构
  - `CollaborationMode`
  - `ModeKind` (Plan/Act/Auto)
  - `ReasoningEffort`

### 核心实现
- `codex-rs/core/src/tools/request_user_input.rs` - 用户输入请求工具实现
- `codex-rs/app-server/src/codex_message_processor.rs` - 服务器请求处理

## 依赖与外部交互

### 直接依赖
| 依赖 | 用途 |
|-----|------|
| `app_test_support` | 测试辅助函数 |
| `tokio::time::timeout` | 异步超时控制 |
| `serde_json` | JSON 序列化 |
| `codex_protocol::config_types` | 协作模式类型 |
| `codex_protocol::openai_models` | 推理努力程度 |

### SSE 响应构造
```rust
pub fn create_request_user_input_sse_response(call_id: &str) -> anyhow::Result<String> {
    let tool_call_arguments = serde_json::to_string(&json!({
        "questions": [{
            "id": "confirm_path",
            "header": "Confirm",
            "question": "Proceed with the plan?",
            "options": [...]
        }]
    }))?;
    
    Ok(responses::sse(vec![
        responses::ev_response_created("resp-1"),
        responses::ev_function_call(call_id, "request_user_input", &tool_call_arguments),
        responses::ev_completed("resp-1"),
    ]))
}
```

### 配置要求
```toml
approval_policy = "untrusted"
model_provider = "mock_provider"
```

## 风险、边界与改进建议

### 当前风险

1. **单一问答类型**
   - 仅测试了单选确认问题
   - 未测试多选、文本输入、数值输入等
   - 建议: 扩展问题类型覆盖

2. **协作模式单一**
   - 仅测试了 Plan 模式
   - 未测试 Act/Auto 模式下的行为差异
   - 建议: 添加多模式测试

3. **错误处理未覆盖**
   - 未测试无效回答格式
   - 未测试用户取消操作
   - 建议: 添加错误场景测试

### 边界情况

1. **空问题列表**
   - 未测试空 questions 数组的行为
   - 建议: 添加边界测试

2. **超长问题**
   - 未测试超长问题描述的处理
   - 建议: 添加大负载测试

3. **多问题并发**
   - 未测试一次请求多个问题的场景
   - 建议: 添加多问题测试

4. **超时处理**
   - 未测试用户长时间不响应
   - 建议: 添加超时测试

### 改进建议

1. **扩展测试覆盖**
   ```rust
   // 建议添加:
   - async fn request_user_input_multiple_questions()  // 多问题
   - async fn request_user_input_text_input()  // 文本输入
   - async fn request_user_input_cancelled()  // 取消操作
   - async fn request_user_input_invalid_response()  // 无效响应
   - async fn request_user_input_act_mode()  // Act 模式
   ```

2. **UI 集成测试**
   - 验证问题渲染格式
   - 测试选项展示顺序

3. **国际化测试**
   - 测试非 ASCII 字符的问题
   - 测试 RTL 语言支持

### 相关测试文件
- `codex-rs/app-server/tests/suite/v2/request_permissions.rs` - 类似的权限请求测试
- `codex-rs/app-server/tests/suite/v2/plan_item.rs` - Plan 模式相关测试
