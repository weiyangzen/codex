# dynamic.rs 深度研究文档

## 场景与职责

`dynamic.rs` 实现了 Codex 的 **动态工具处理器（Dynamic Tool Handler）**，用于处理运行时动态注册的工具调用。动态工具允许在会话过程中动态添加自定义工具，而无需预先在工具配置中定义。

**核心使用场景：**
1. **MCP 工具调用** - 通过 Model Context Protocol 动态发现的工具
2. **运行时工具注册** - 会话中动态添加的自定义工具
3. **插件系统** - 支持第三方工具插件
4. **交互式工具发现** - 用户或模型在对话中引入的新工具

## 功能点目的

### 1. 动态工具调用转发
- 接收动态工具调用请求
- 将请求转发给外部工具提供者
- 收集并返回工具执行结果

### 2. 异步响应处理
- 使用 oneshot channel 等待外部响应
- 支持超时和取消机制
- 处理响应超时或取消场景

### 3. 事件发射
- 发射 `DynamicToolCallRequest` 事件
- 发射 `DynamicToolCallResponse` 事件
- 支持调用时长记录

### 4. 结果转换
- 将外部响应转换为内部 `FunctionCallOutputContentItem`
- 支持成功/失败状态传递

## 具体技术实现

### 关键数据结构

```rust
pub struct DynamicToolHandler;

// 动态工具调用请求（来自 codex_protocol）
pub struct DynamicToolCallRequest {
    pub call_id: String,
    pub turn_id: String,
    pub tool: String,
    pub arguments: Value,
}

// 动态工具响应（来自 codex_protocol）
pub struct DynamicToolResponse {
    pub content_items: Vec<FunctionCallOutputContentItem>,
    pub success: bool,
}

// 动态工具调用响应事件
pub struct DynamicToolCallResponseEvent {
    pub call_id: String,
    pub turn_id: String,
    pub tool: String,
    pub arguments: Value,
    pub content_items: Vec<FunctionCallOutputContentItem>,
    pub success: bool,
    pub error: Option<String>,
    pub duration: Duration,
}

// 内部挂起的动态工具调用
// 存储在 session.active_turn.turn_state 中
pub struct PendingDynamicTool {
    pub call_id: String,
    pub response_tx: oneshot::Sender<DynamicToolResponse>,
}
```

### 关键流程

#### 1. Handler 入口 (`DynamicToolHandler::handle`)

```rust
async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
    // 1. 提取参数
    let arguments = match payload {
        ToolPayload::Function { arguments } => arguments,
        _ => error,
    };

    // 2. 解析为 JSON Value
    let args: Value = parse_arguments(&arguments)?;

    // 3. 请求动态工具执行
    let response = request_dynamic_tool(&session, turn.as_ref(), call_id, tool_name, args)
        .await
        .ok_or_else(|| {
            FunctionCallError::RespondToModel(
                "dynamic tool call was cancelled before receiving a response".to_string(),
            )
        })?;

    // 4. 转换响应
    let DynamicToolResponse { content_items, success } = response;
    let body = content_items
        .into_iter()
        .map(FunctionCallOutputContentItem::from)
        .collect::<Vec<_>>();

    // 5. 返回结果
    Ok(FunctionToolOutput::from_content(body, Some(success)))
}
```

#### 2. 动态工具请求流程 (`request_dynamic_tool`)

```rust
async fn request_dynamic_tool(
    session: &Session,
    turn_context: &TurnContext,
    call_id: String,
    tool: String,
    arguments: Value,
) -> Option<DynamicToolResponse> {
    let turn_id = turn_context.sub_id.clone();
    let (tx_response, rx_response) = oneshot::channel();
    let event_id = call_id.clone();

    // 1. 注册挂起的调用
    let prev_entry = {
        let mut active = session.active_turn.lock().await;
        match active.as_mut() {
            Some(at) => {
                let mut ts = at.turn_state.lock().await;
                ts.insert_pending_dynamic_tool(call_id.clone(), tx_response)
            }
            None => None,
        }
    };
    if prev_entry.is_some() {
        warn!("Overwriting existing pending dynamic tool call for call_id: {event_id}");
    }

    // 2. 记录开始时间
    let started_at = Instant::now();

    // 3. 发送请求事件
    let event = EventMsg::DynamicToolCallRequest(DynamicToolCallRequest {
        call_id: call_id.clone(),
        turn_id: turn_id.clone(),
        tool: tool.clone(),
        arguments: arguments.clone(),
    });
    session.send_event(turn_context, event).await;

    // 4. 等待响应
    let response = rx_response.await.ok();

    // 5. 发送响应事件
    let response_event = match &response {
        Some(response) => EventMsg::DynamicToolCallResponse(DynamicToolCallResponseEvent {
            call_id,
            turn_id,
            tool,
            arguments,
            content_items: response.content_items.clone(),
            success: response.success,
            error: None,
            duration: started_at.elapsed(),
        }),
        None => EventMsg::DynamicToolCallResponse(DynamicToolCallResponseEvent {
            call_id,
            turn_id,
            tool,
            arguments,
            content_items: Vec::new(),
            success: false,
            error: Some("dynamic tool call was cancelled before receiving a response".to_string()),
            duration: started_at.elapsed(),
        }),
    };
    session.send_event(turn_context, response_event).await;

    response
}
```

### 状态管理

动态工具调用的挂起状态存储在会话的活跃回合状态中：

```rust
// 在 session.active_turn.turn_state 中
pub struct TurnState {
    pending_dynamic_tools: HashMap<String, PendingDynamicTool>,
}

impl TurnState {
    pub fn insert_pending_dynamic_tool(
        &mut self,
        call_id: String,
        response_tx: oneshot::Sender<DynamicToolResponse>,
    ) -> Option<PendingDynamicTool> {
        self.pending_dynamic_tools.insert(
            call_id.clone(),
            PendingDynamicTool { call_id, response_tx },
        )
    }

    pub fn remove_pending_dynamic_tool(&mut self, call_id: &str) -> Option<PendingDynamicTool> {
        self.pending_dynamic_tools.remove(call_id)
    }
}
```

### 外部响应处理

外部组件（如 MCP 管理器）通过以下方式响应动态工具调用：

```rust
// 外部组件接收 DynamicToolCallRequest 事件后执行工具
// 然后通过 oneshot channel 发送响应
let response = DynamicToolResponse {
    content_items: vec![FunctionCallOutputContentItem::InputText { text: result }],
    success: true,
};
pending_tool.response_tx.send(response).ok();
```

## 关键代码路径与文件引用

### 当前文件内关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `DynamicToolHandler::handle` | 35-72 | 主处理入口 |
| `DynamicToolHandler::is_mutating` | 31-33 | 标记为可变操作 |
| `request_dynamic_tool` | 75-134 | 动态工具请求处理 |

### 外部依赖

| 模块/文件 | 用途 |
|-----------|------|
| `codex_protocol::dynamic_tools::DynamicToolCallRequest` | 请求协议定义 |
| `codex_protocol::dynamic_tools::DynamicToolResponse` | 响应协议定义 |
| `codex_protocol::protocol::DynamicToolCallResponseEvent` | 响应事件定义 |
| `Session::active_turn` | 挂起调用状态存储 |
| `TurnState::insert_pending_dynamic_tool` | 注册挂起调用 |

## 依赖与外部交互

### 与会话状态交互

```rust
// 注册挂起调用
let mut active = session.active_turn.lock().await;
match active.as_mut() {
    Some(at) => {
        let mut ts = at.turn_state.lock().await;
        ts.insert_pending_dynamic_tool(call_id.clone(), tx_response)
    }
    None => None,
}
```

### 与事件系统交互

```rust
// 发送请求事件
let event = EventMsg::DynamicToolCallRequest(DynamicToolCallRequest {
    call_id: call_id.clone(),
    turn_id: turn_id.clone(),
    tool: tool.clone(),
    arguments: arguments.clone(),
});
session.send_event(turn_context, event).await;

// 发送响应事件
let response_event = EventMsg::DynamicToolCallResponse(DynamicToolCallResponseEvent { ... });
session.send_event(turn_context, response_event).await;
```

### 与 MCP 系统集成

动态工具处理器是 MCP 工具调用的核心通道：

```
模型调用 dynamic tool
    ↓
DynamicToolHandler::handle
    ↓
request_dynamic_tool
    ↓
发送 DynamicToolCallRequest 事件
    ↓
McpConnectionManager 接收事件
    ↓
调用 MCP 服务器工具
    ↓
通过 oneshot channel 返回结果
    ↓
发送 DynamicToolCallResponse 事件
    ↓
返回 FunctionToolOutput
```

## 风险、边界与改进建议

### 已知风险

1. **内存泄漏风险**
   - 挂起的动态工具调用在 `pending_dynamic_tools` 中存储
   - 如外部组件未响应，可能长期占用内存
   - 建议：添加超时清理机制

2. **重复 call_id**
   - 相同 call_id 的调用会覆盖之前的挂起状态
   - 可能导致前一个调用的响应丢失
   - 建议：添加重复检测和错误处理

3. **会话状态依赖**
   - 依赖 `session.active_turn` 存在
   - 如会话结束，挂起调用无法处理
   - 建议：添加会话生命周期检查

### 边界情况

1. **无活跃回合**
   - `session.active_turn` 为 None
   - 调用 `insert_pending_dynamic_tool` 返回 None
   - 工具调用无法完成

2. **响应通道关闭**
   - `rx_response.await` 返回 Err
   - 视为取消，发送错误响应事件

3. **重复 call_id**
   - 覆盖之前的挂起状态
   - 记录警告日志

### 改进建议

1. **超时机制**
   ```rust
   // 添加超时处理
   let response = tokio::time::timeout(Duration::from_secs(60), rx_response).await.ok()?;
   ```

2. **重复检测**
   ```rust
   // 检测到重复 call_id 时返回错误
   if prev_entry.is_some() {
       return Err(FunctionCallError::RespondToModel(
           "duplicate dynamic tool call id".to_string(),
       ));
   }
   ```

3. **状态清理**
   ```rust
   // 定期清理超时的挂起调用
   async fn cleanup_pending_tools(&self) {
       // 实现清理逻辑
   }
   ```

4. **可观测性**
   - 添加挂起调用数量指标
   - 记录调用等待时间
   - 添加调用成功率统计

5. **测试覆盖**
   - 当前文件无独立测试文件
   - 建议添加：
     - 正常调用流程测试
     - 超时场景测试
     - 取消场景测试
     - 重复 call_id 测试
