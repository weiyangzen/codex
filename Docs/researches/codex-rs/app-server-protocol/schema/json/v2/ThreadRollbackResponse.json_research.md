# ThreadRollbackResponse.json 研究文档

## 场景与职责

`ThreadRollbackResponse` 是 Codex App Server Protocol v2 中 `thread/rollback` 方法的响应结构，用于向客户端返回线程回滚操作后的完整状态。该响应对客户端更新 UI 状态、同步本地缓存至关重要。

该响应包含回滚后的线程完整信息，包括：
- 线程元数据（ID、名称、状态等）
- 回滚后的回合历史（turns）
- 当前线程配置信息

**重要特性**: 响应中的 `ThreadItem` 是 lossy 的，不保留所有代理交互细节（如命令执行详情），这与 `thread/resume` 的行为一致。

## 功能点目的

### 核心功能
- **状态确认**: 向客户端确认回滚操作已成功完成
- **状态同步**: 提供回滚后的完整线程状态，供客户端更新 UI
- **历史可见性**: 返回回滚后的回合列表，让用户了解当前历史状态

### 使用场景
1. 客户端发起回滚请求后，根据响应更新对话界面
2. TUI 应用根据响应重置输入缓冲区和待处理状态
3. 多客户端场景下，通过通知机制广播回滚事件

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRollbackResponse {
    /// 回滚后的线程状态，包含 turns 数组
    ///
    /// ThreadItem 是 lossy 的，不保留所有代理交互细节
    /// （如命令执行详情），这与 thread/resume 行为一致
    pub thread: Thread,
}
```

### JSON Schema 结构

ThreadRollbackResponse.json 是一个复杂的嵌套结构，包含以下主要定义：

#### 核心类型定义
- **Thread**: 线程元数据（id, name, status, turns 等）
- **Turn**: 对话回合（id, status, items, error）
- **ThreadItem**: 多种类型的线程项（UserMessage, AgentMessage, CommandExecution 等）

#### 错误类型
- **TurnError**: 回合失败时的错误信息
- **CodexErrorInfo**: Codex 特定的错误码（contextWindowExceeded, usageLimitExceeded 等）

#### 状态枚举
- **ThreadStatus**: notLoaded, idle, active, systemError
- **TurnStatus**: completed, interrupted, failed, inProgress
- **CommandExecutionStatus**: inProgress, completed, failed, declined

### 关键流程

1. **事件处理**: `bespoke_event_handling.rs` 监听 `ThreadRollback` 事件
2. **线程重建**: 从截断后的 rollout 文件重建 Thread 对象
3. **响应构造**: 包装 Thread 到 ThreadRollbackResponse
4. **响应发送**: 通过 WebSocket/SSE 发送给请求客户端
5. **通知广播**: 向其他连接的客户端广播线程状态变更

### TUI 应用集成

在 `tui_app_server` 中，回滚响应的处理：

```rust
// app.rs
fn apply_thread_rollback(&mut self, response: &ThreadRollbackResponse) {
    self.turns = response.thread.turns.clone();
    self.buffer.clear();
    self.pending_interactive_replay = PendingInteractiveReplayState::default();
    self.active_turn_id = None;
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadRollbackResponse 结构体定义
- `codex-rs/app-server-protocol/schema/json/v2/ThreadRollbackResponse.json`: JSON Schema 定义

### 服务端实现
- `codex-rs/app-server/src/bespoke_event_handling.rs`:
  - 处理 ThreadRollback 事件，构造响应
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_rollback()` 发起回滚操作

### 客户端实现
- `codex-rs/tui_app_server/src/app.rs`:
  - `apply_thread_rollback()` 应用回滚到本地状态
- `codex-rs/tui_app_server/src/app_server_session.rs`:
  - `thread_rollback()` 发起请求并处理响应

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_rollback.rs`:
  - 验证响应结构和线程状态

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRollbackResponse.ts`

## 依赖与外部交互

### 内部依赖
- **Thread**: 线程完整状态表示
- **Turn**: 回合数据结构
- **ThreadItem**: 多种类型的对话项

### 嵌套类型详解

#### Thread 结构
```rust
pub struct Thread {
    pub id: String,
    pub name: Option<String>,
    pub status: ThreadStatus,
    pub turns: Vec<Turn>,
    pub cwd: String,
    pub model_provider: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub preview: String,
    pub ephemeral: bool,
    pub git_info: Option<GitInfo>,
    pub source: SessionSource,
    pub cli_version: String,
    pub path: Option<String>,
}
```

#### Turn 结构
```rust
pub struct Turn {
    pub id: String,
    pub status: TurnStatus,
    pub items: Vec<ThreadItem>,
    pub error: Option<TurnError>,
}
```

#### ThreadItem 变体
- **UserMessage**: 用户输入消息
- **AgentMessage**: 代理回复消息
- **CommandExecution**: 命令执行记录
- **FileChange**: 文件变更记录
- **McpToolCall**: MCP 工具调用
- **WebSearch**: 网页搜索记录
- **Reasoning**: 推理过程记录
- **CollabAgentToolCall**: 协作代理工具调用

## 风险、边界与改进建议

### 已知风险

1. **Lossy 历史**: 命令执行详情等部分信息在响应中丢失
2. **大历史负载**: 长对话历史可能导致响应体过大
3. **序列化开销**: 复杂的嵌套结构增加序列化/反序列化成本

### 边界情况

1. **空线程回滚**: 回滚所有回合后，turns 数组为空
2. **失败回合**: 包含 error 字段的 Turn 需要特殊处理
3. **并发修改**: 响应生成期间线程状态可能再次变化

### 改进建议

1. **分页历史**: 对于长历史，考虑分页返回 turns
2. **增量更新**: 仅返回变更的部分，而非完整 Thread
3. **压缩选项**: 大响应考虑 Gzip 压缩
4. **选择性字段**: 允许客户端指定需要的字段子集

### 兼容性考虑
- `name` 字段在未设置时必须序列化为 `null` 而非省略
- 新添加的 ThreadItem 类型需要保持向后兼容
