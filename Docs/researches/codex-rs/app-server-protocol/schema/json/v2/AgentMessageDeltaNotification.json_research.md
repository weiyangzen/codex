# AgentMessageDeltaNotification Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AgentMessageDeltaNotification` 是服务器向客户端发送的流式通知，用于实时传递 AI Agent 生成的消息内容增量。

**使用场景：**
- AI 生成回复时的实时流式输出
- 长文本生成过程中的渐进式展示
- 打字机效果的实现基础
- 实时协作场景中的内容同步

**职责：**
- 提供消息内容的增量更新（delta）
- 标识消息所属的线程和轮次
- 支持多条消息（items）的并行流式传输
- 实现低延迟的实时内容推送

## 2. 功能点目的 (Purpose of the Functionality)

该通知的核心目的是实现 AI 回复的流式传输：

1. **实时反馈**: 用户无需等待完整回复即可看到内容
2. **渐进式渲染**: 支持打字机效果的 UI 展示
3. **性能优化**: 减少首字节时间（TTFB），提升用户体验
4. **上下文关联**: 通过 threadId/turnId/itemId 精确定位消息位置

**字段说明：**
- `threadId` (string, required): 所属线程 ID
- `turnId` (string, required): 所属轮次 ID
- `itemId` (string, required): 消息项 ID
- `delta` (string, required): 内容增量（UTF-8 文本）

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AgentMessageDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,
}
```

### 协议集成

在 `common.rs` 中注册：

```rust
server_notification_definitions! {
    AgentMessageDelta => "item/agentMessage/delta" (v2::AgentMessageDeltaNotification),
}
```

### 流式传输流程

1. 客户端发送 `turn/start` 启动一轮对话
2. 服务器开始生成 AI 回复
3. 每生成一段内容，发送 `AgentMessageDeltaNotification`
4. 客户端累积 delta 内容并实时展示
5. 生成完成后发送 `ItemCompletedNotification`

### 与 Responses API 的关系

该通知对应 OpenAI Responses API 的流式输出，将 SSE 事件转换为 App-Server 协议通知。

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs`
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs`

### 相关类型
- `TurnStartParams/Response`: 启动轮次
- `ItemStartedNotification`: 消息项开始
- `ItemCompletedNotification`: 消息项完成
- `TurnCompletedNotification`: 轮次完成

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AgentMessageDeltaNotification.json`

### 核心协议模块
- Thread/Turn/Item 生命周期管理
- 与 OpenAI Responses API 的集成层

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `codex_protocol::items::AgentMessageContent`: 消息内容核心类型
- `codex_protocol::items::TurnItem`: 轮次项类型
- Thread/Turn/Item 管理系统

### 外部交互
- **OpenAI Responses API**: 获取 AI 生成的流式输出
- **客户端 UI**: 通过 WebSocket/SSE 推送增量内容
- **Token 计数**: 同步更新 token 使用量

### 相关配置
- `model`: 影响生成速度和内容
- `model_reasoning_effort`: 影响推理过程展示
- `model_verbosity`: 影响输出长度

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **乱序到达**: 网络问题可能导致 delta 乱序
2. **丢失增量**: 连接中断可能导致部分内容丢失
3. **编码问题**: 多字节 UTF-8 字符可能被截断
4. **累积延迟**: 大量小增量可能导致渲染卡顿

### 边界情况

1. **空 delta**: 某些情况下可能发送空字符串
2. **超长内容**: 极长回复的内存和性能考虑
3. **多 item 并发**: 同一轮次多个消息的并行处理
4. **中断恢复**: 连接中断后的状态恢复

### 改进建议

1. **添加序号**: 建议添加 `sequence` 字段用于排序和丢包检测
2. **批量发送**: 小增量可合并发送减少网络开销
3. **压缩传输**: 大量文本可考虑压缩
4. **心跳机制**: 长时间无输出时发送心跳保持连接
5. **断点续传**: 支持从指定位置恢复流式传输

### 测试建议

1. 测试各种长度的内容生成
2. 测试多字节字符（中文、emoji）的正确性
3. 测试网络中断和重连场景
4. 测试高并发消息处理
5. 验证累积内容的完整性

### 客户端实现建议

1. 使用缓冲区累积 delta 内容
2. 实现平滑的打字机效果（控制渲染频率）
3. 处理乱序到达的 delta（如有序号）
4. 提供暂停/继续流式展示的功能
5. 实现内容复制时需使用累积后的完整内容

### 性能优化

1. 使用 `requestAnimationFrame` 控制渲染频率
2. 虚拟滚动处理超长内容
3. 节流/防抖处理高频更新
4. Web Worker 处理内容解析（如 Markdown）
