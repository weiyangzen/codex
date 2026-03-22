# WindowsSandboxSetupStartResponse.json 研究文档

## 场景与职责

`WindowsSandboxSetupStartResponse` 是 Codex App-Server Protocol v2 中 `windowsSandbox/setupStart` RPC 方法的响应结构。它在客户端请求启动 Windows 沙箱设置后返回，确认设置操作已启动。

**核心职责：**
- 确认沙箱设置操作已成功启动
- 提供简单的布尔状态指示
- 作为异步流程的起点确认

## 功能点目的

### 1. 启动确认
`started` 字段确认：
- 服务器已接受设置请求
- 后台设置流程已启动
- 客户端应等待后续 `windowsSandbox/setupCompleted` 通知

### 2. 轻量级响应
响应设计极简：
- 仅包含布尔值 `started`
- 不等待实际设置完成
- 快速响应，避免阻塞客户端

### 3. 异步流程起点
响应与通知的配合：
- 响应表示"已开始"
- 通知表示"已完成（成功或失败）"
- 客户端通过两者了解完整流程

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartResponse {
    pub started: bool,
}
```

### 响应语义

| started 值 | 含义 | 客户端行为 |
|------------|------|-----------|
| `true` | 设置已启动 | 等待 `setupCompleted` 通知 |
| `false` | 设置未启动（理论上不应出现） | 检查错误响应或重试 |

### 关键流程

1. **接收请求**：服务器接收 `windowsSandbox/setupStart` 请求
2. **验证参数**：检查 `mode` 和 `cwd`（如果是相对路径会失败）
3. **启动设置**：在后台启动沙箱初始化
4. **返回响应**：返回 `WindowsSandboxSetupStartResponse { started: true }`
5. **异步完成**：设置完成后发送 `windowsSandbox/setupCompleted` 通知

### 响应示例

**成功启动：**
```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "result": {
    "started": true
  }
}
```

**参数错误（如相对路径）：**
```json
{
  "jsonrpc": "2.0",
  "id": 123,
  "error": {
    "code": -32600,
    "message": "Invalid request"
  }
}
```

## 关键代码路径与文件引用

### 定义位置
- `WindowsSandboxSetupStartResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4997`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:425-428`
  ```rust
  WindowsSandboxSetupStart => "windowsSandbox/setupStart" {
      params: v2::WindowsSandboxSetupStartParams,
      response: v2::WindowsSandboxSetupStartResponse,
  },
  ```

### 测试覆盖
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs:36-49`
  ```rust
  let request_id = mcp
      .send_windows_sandbox_setup_start_request(WindowsSandboxSetupStartParams {
          mode: WindowsSandboxSetupMode::Unelevated,
          cwd: None,
      })
      .await?;
  let response: JSONRPCResponse = timeout(
      DEFAULT_READ_TIMEOUT,
      mcp.read_stream_until_response_message(RequestId::Integer(request_id)),
  ).await??;
  let start_payload: WindowsSandboxSetupStartResponse = to_response(response)?;
  assert!(start_payload.started);
  ```

### 相关类型
- `WindowsSandboxSetupStartParams`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4988`
- `WindowsSandboxSetupCompletedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:5004`

## 依赖与外部交互

### 上游依赖
- 无特殊依赖，仅使用标准 `bool` 类型

### 下游消费
- Windows 客户端确认设置已启动
- 客户端开始等待 `setupCompleted` 通知

### 协议集成
- 作为 JSON-RPC 2.0 响应的 `result` 字段
- 请求方法: `windowsSandbox/setupStart`
- 请求参数: `WindowsSandboxSetupStartParams`
- 后续通知: `windowsSandbox/setupCompleted`

### 平台限制
- 仅在 Windows 平台有效
- 非 Windows 平台可能返回未实现错误

## 风险、边界与改进建议

### 已知风险

1. **信息有限**
   - 仅返回布尔值，无其他上下文
   - 客户端无法从响应中了解设置预计耗时

2. **false 值未使用**
   - 当前设计似乎总是返回 `true` 或错误
   - `started: false` 的场景不明确

3. **竞态条件**
   - 响应返回后，设置可能立即失败
   - 客户端可能在收到通知前尝试使用沙箱

### 边界情况

1. **重复请求**
   - 当前实现未明确处理重复启动请求
   - 可能的行为：返回 `true`、返回错误或重置沙箱

2. **快速完成**
   - 如果设置非常快，通知可能在响应前到达
   - 客户端需要处理这种时序

3. **服务器重启**
   - 如果服务器在设置过程中重启，客户端可能收不到通知
   - 需要超时和重试机制

### 改进建议

1. **响应增强**
   - 添加 `setup_id` 用于追踪具体设置操作
   - 添加 `estimated_duration_ms` 提供预计耗时

2. **状态查询**
   - 添加 `windowsSandbox/setupStatus` 查询接口
   - 允许客户端在错过通知时查询状态

3. **进度通知**
   - 添加 `windowsSandbox/setupProgress` 通知
   - 对于长时间设置提供更好的用户体验

4. **错误细化**
   - 考虑在响应中添加警告信息（非致命问题）
   - 如 "设置已启动但某些功能可能不可用"

5. **幂等性设计**
   - 明确重复请求的行为
   - 考虑添加 `idempotent_key` 支持

6. **取消支持**
   - 返回 `setup_id` 后支持取消操作
   - 添加 `windowsSandbox/setupCancel` 方法
