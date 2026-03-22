# ThreadShellCommandResponse.json 研究文档

## 场景与职责

`ThreadShellCommandResponse` 是 Codex App Server Protocol v2 中 `thread/shellCommand` 方法的响应结构。这是一个极简的响应类型，仅用于确认 shell 命令已成功启动执行。

该响应的设计特点：
- **异步确认**: 仅表示命令已提交执行，不等待完成
- **空负载**: 不包含命令输出，输出通过通知流式发送
- **即时返回**: 避免长时间阻塞等待命令完成

## 功能点目的

### 核心功能
- **启动确认**: 向客户端确认 shell 命令已成功启动
- **异步架构**: 支持长时间运行的命令不阻塞请求通道
- **协议完整性**: 满足 JSON-RPC 请求-响应模式要求

### 设计哲学
采用空响应 + 通知的设计原因：
1. **非阻塞**: 命令可能长时间运行，不应阻塞 JSON-RPC 通道
2. **流式输出**: 命令输出通过 `CommandExecutionOutputDelta` 通知实时推送
3. **状态追踪**: 客户端通过 `ItemStartedNotification` 和 `ItemCompletedNotification` 跟踪执行状态

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadShellCommandResponse {}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ThreadShellCommandResponse",
  "type": "object"
}
```

### 响应流程

1. **命令提交**: `Op::RunUserShellCommand` 成功提交到线程执行器
2. **即时响应**: 返回空的 `ThreadShellCommandResponse`
3. **异步执行**: 命令在后台执行
4. **状态通知**: 通过以下通知推送执行状态和输出：
   - `ItemStartedNotification`: 命令开始
   - `CommandExecutionOutputDeltaNotification`: 输出增量
   - `ItemCompletedNotification`: 命令完成

### 典型响应示例

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "result": {}
}
```

### 完整交互流程

```
Client                                          Server
  |                                               |
  |--- thread/shellCommand {command} ----------->|
  |                                               |
  |<-- ThreadShellCommandResponse {} -------------|
  |                                               |
  |<-- item/started (CommandExecution) -----------|
  |                                               |
  |<-- item/commandExecution/outputDelta (chunk1) |
  |<-- item/commandExecution/outputDelta (chunk2) |
  |<-- item/commandExecution/outputDelta (chunk3) |
  |                                               |
  |<-- item/completed (CommandExecution) ---------|
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadShellCommandResponse 结构体定义
- `codex-rs/app-server-protocol/schema/json/v2/ThreadShellCommandResponse.json`: JSON Schema 定义

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_shell_command()` 方法发送响应 (line 3020-3023)

### 客户端处理
- `codex-rs/tui_app_server/src/app_server_session.rs`:
  - 调用 shell 命令并处理响应和通知

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs`:
  - 验证响应接收和后续通知流程

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadShellCommandResponse.ts`:
  ```typescript
  export type ThreadShellCommandResponse = {};
  ```

## 依赖与外部交互

### 关联通知类型

客户端需要监听以下通知获取完整执行信息：

#### ItemStartedNotification
```rust
pub struct ItemStartedNotification {
    pub turn_id: String,
    pub item: ThreadItem,  // CommandExecution 变体
}
```

#### CommandExecutionOutputDeltaNotification
```rust
pub struct CommandExecutionOutputDeltaNotification {
    pub turn_id: String,
    pub item_id: String,
    pub delta: String,  // base64 编码的输出块
}
```

#### ItemCompletedNotification
```rust
pub struct ItemCompletedNotification {
    pub turn_id: String,
    pub item: ThreadItem,  // 包含最终状态、退出码、聚合输出
}
```

### 错误响应
操作失败时返回 JSON-RPC Error：
- **无效请求错误** (-32600): 空命令、无效线程 ID
- **内部错误** (-32603): 命令启动失败

### CommandExecution ThreadItem

```rust
pub struct CommandExecution {
    pub id: String,
    pub command: String,
    pub cwd: String,
    pub status: CommandExecutionStatus,
    pub source: CommandExecutionSource,  // UserShell
    pub aggregated_output: Option<String>,
    pub exit_code: Option<i32>,
    pub duration_ms: Option<i64>,
    pub process_id: Option<String>,
}
```

## 风险、边界与改进建议

### 已知限制

1. **无同步确认**: 响应返回时命令可能尚未实际开始执行
2. **无进程 ID**: 响应中不包含进程 ID，客户端无法直接终止命令
3. **无预估时间**: 无法预估长时间运行命令的完成时间

### 边界情况

1. **命令启动失败**: 虽然响应已发送，但命令可能因权限等原因启动失败
2. **快速完成**: 短命令可能在响应发送前已完成
3. **通知丢失**: 网络问题可能导致客户端错过状态通知

### 改进建议

1. **返回执行 ID**: 添加唯一的命令执行 ID 便于追踪
2. **启动确认**: 考虑添加命令实际启动的确认机制
3. **取消令牌**: 提供取消令牌用于终止命令
4. **进度预估**: 对于已知类型的命令，提供进度预估

### 兼容性
- 空对象响应对所有 JSON-RPC 客户端兼容
- 未来可安全添加可选字段，保持向后兼容

### 调试建议
- 客户端应实现通知超时检测，识别可能的命令启动失败
- 记录所有通知接收时间，帮助诊断问题
- 考虑实现命令执行状态的重同步机制
