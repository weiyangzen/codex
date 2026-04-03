# turn_steer.rs 研究文档

## 场景与职责

`turn_steer.rs` 是 Codex App Server V2 API 的集成测试文件，专注于测试 **Turn Steer（回合引导）** 功能。该功能允许在对话回合进行中向 AI 发送额外的引导输入，用于实时纠正方向或提供补充信息。

### 核心测试场景

1. **活跃回合验证**：验证 steer 操作需要活跃的回合
2. **输入大小限制**：验证 steer 输入的字符数上限
3. **回合 ID 匹配**：验证 steer 操作返回正确的活跃回合 ID

### 平台限制

```rust
#![cfg(unix)]
```

该测试文件仅在 Unix 平台运行，因为依赖 shell 命令执行来保持回合活跃状态。

---

## 功能点目的

### Turn Steer 功能

Turn Steer 是 Codex 的实时交互增强机制：

- **实时纠正**：用户可以在 AI 思考过程中发送纠正信息
- **补充上下文**：在回合进行中提供额外的文件或信息
- **方向调整**：改变 AI 的处理方向或策略

### 关键业务规则

1. Steer 操作需要指定 `expected_turn_id`，如果不匹配当前活跃回合会失败
2. Steer 输入有最大字符数限制（`MAX_USER_INPUT_TEXT_CHARS`）
3. Steer 操作成功后返回当前活跃回合的 ID
4. Steer 只能在回合处于 `InProgress` 状态时执行

### 错误处理

| 错误码 | 场景 | 说明 |
|--------|------|------|
| `-32600` | 无效请求 | 回合不存在或已完成 |
| `INVALID_PARAMS_ERROR_CODE` | 参数无效 | 输入超过最大长度 |

---

## 具体技术实现

### 数据结构

#### TurnSteerParams
```rust
pub struct TurnSteerParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    /// 必需：活跃回合 ID 前置条件
    pub expected_turn_id: String,
}
```

#### TurnSteerResponse
```rust
pub struct TurnSteerResponse {
    pub turn_id: String,  // 当前活跃回合 ID
}
```

#### 输入限制常量
```rust
// codex-rs/protocol/src/user_input.rs
pub const MAX_USER_INPUT_TEXT_CHARS: usize = 100_000;
```

### 测试用例 1: 活跃回合验证

```rust
async fn turn_steer_requires_active_turn() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录
2. 创建 Mock Server（无响应序列）
3. 启动 MCP 进程并初始化
4. 创建线程（thread/start）
5. 发送 turn/steer 请求
   └── 使用不存在的 turn_id: "turn-does-not-exist"
6. 验证收到错误响应
7. 验证错误码为 -32600（无效请求）
```

**关键验证点**:
- 对不存在的回合发送 steer 请求返回错误
- 错误码符合 JSON-RPC 规范

### 测试用例 2: 输入大小限制

```rust
async fn turn_steer_rejects_oversized_text_input() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录和工作目录
2. 创建 Mock Server，配置返回长耗时命令（sleep 10s）
3. 启动 MCP 进程
4. 创建线程
5. 启动回合（turn/start），触发长耗时命令
6. 等待 turn/started 通知
7. 构造超大输入："x".repeat(MAX_USER_INPUT_TEXT_CHARS + 1)
8. 发送 turn/steer 请求，携带超大输入
9. 验证收到错误响应
10. 验证错误码为 INVALID_PARAMS_ERROR_CODE
11. 验证错误消息包含最大长度信息
12. 验证错误数据包含：
    - input_error_code: INPUT_TOO_LARGE_ERROR_CODE
    - max_chars: MAX_USER_INPUT_TEXT_CHARS
    - actual_chars: 超大输入的字符数
13. 调用 interrupt_turn_and_wait_for_aborted 清理
```

**关键验证点**:
- 超大输入被拒绝
- 错误信息包含结构化数据
- 客户端可以根据错误数据调整输入

### 测试用例 3: 回合 ID 匹配

```rust
async fn turn_steer_returns_active_turn_id() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录和工作目录
2. 创建 Mock Server，配置返回长耗时命令（sleep 10s）
3. 启动 MCP 进程
4. 创建线程
5. 启动回合（turn/start），获取 turn_id
6. 等待 turn/started 通知
7. 发送 turn/steer 请求
   └── expected_turn_id: 步骤5获取的 turn_id
8. 验证响应成功
9. 验证响应中的 turn_id 与请求的一致
10. 调用 interrupt_turn_and_wait_for_aborted 清理
```

**关键验证点**:
- Steer 操作成功返回当前活跃回合 ID
- 回合 ID 一致性验证

---

## 关键代码路径与文件引用

### 测试文件
- **位置**: `codex-rs/app-server/tests/suite/v2/turn_steer.rs`
- **行数**: 288 行
- **平台限制**: `#[cfg(unix)]`

### 协议定义
- **位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **相关结构**:
  - `TurnSteerParams` (行 3944-3950)
  - `TurnSteerResponse` (行 3952-3957)

### 错误码定义
- **位置**: `codex-rs/app-server/src/lib.rs`（或类似位置）
- **相关常量**:
  - `INPUT_TOO_LARGE_ERROR_CODE`
  - `INVALID_PARAMS_ERROR_CODE` (-32602)

### 输入限制
- **位置**: `codex-rs/protocol/src/user_input.rs`
- **常量**: `MAX_USER_INPUT_TEXT_CHARS = 100_000`

### 测试支持库
- **位置**: `codex-rs/app-server/tests/common/mcp_process.rs`
- **方法**: `send_turn_steer_request` (行 680-687)
- **方法**: `interrupt_turn_and_wait_for_aborted` (行 632-678)

### 服务器错误码
- **位置**: `codex-rs/app-server/src/lib.rs`（推测）
- **导入**: `INPUT_TOO_LARGE_ERROR_CODE`, `INVALID_PARAMS_ERROR_CODE`

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 测试超时控制 |
| `codex_protocol::user_input::MAX_USER_INPUT_TEXT_CHARS` | 输入大小限制常量 |

### 内部模块依赖

```
turn_steer.rs
├── app_test_support::McpProcess
├── app_test_support::create_mock_responses_server_sequence
├── app_test_support::create_mock_responses_server_sequence_unchecked
├── app_test_support::create_shell_command_sse_response
├── app_test_support::to_response
├── codex_app_server::INPUT_TOO_LARGE_ERROR_CODE
├── codex_app_server::INVALID_PARAMS_ERROR_CODE
├── codex_app_server_protocol::JSONRPCError
├── codex_app_server_protocol::JSONRPCNotification
├── codex_app_server_protocol::JSONRPCResponse
├── codex_app_server_protocol::TurnSteerParams
├── codex_app_server_protocol::TurnSteerResponse
├── codex_app_server_protocol::TurnStartParams
├── codex_app_server_protocol::TurnStartResponse
├── codex_protocol::user_input::MAX_USER_INPUT_TEXT_CHARS
└── tempfile::TempDir
```

### 平台适配

```rust
#[cfg(target_os = "windows")]
let shell_command = vec![
    "powershell".to_string(),
    "-Command".to_string(),
    "Start-Sleep -Seconds 10".to_string(),
];
#[cfg(not(target_os = "windows"))]
let shell_command = vec!["sleep".to_string(), "10".to_string()];
```

虽然代码包含 Windows 适配，但整个文件被 `#![cfg(unix)]` 限制。

---

## 风险、边界与改进建议

### 潜在风险

1. **字符数计算差异**
   - 测试使用 `chars().count()` 计算字符数
   - 实际服务器可能使用字节数或其他计算方式
   - **缓解**: 确保客户端和服务器使用相同的计数方法

2. **竞态条件**
   - 测试依赖 `turn/started` 通知来确认回合已开始
   - 在快速执行环境，回合可能在 steer 前已完成
   - **缓解**: 使用长耗时命令保持回合活跃

3. **平台限制**
   - 测试仅在 Unix 运行，Windows 行为未覆盖
   - **缓解**: 考虑移除平台限制或添加 Windows 特定测试

4. **超时设置**
   - `DEFAULT_READ_TIMEOUT = 10 秒` 可能不足以覆盖慢速环境
   - 长耗时命令使用 10 秒 sleep，加上启动时间可能接近超时

### 边界情况

1. **空输入**: 测试未覆盖空输入或空数组的处理
2. **多输入项**: 测试未覆盖 `input` 数组包含多个 `UserInput` 的场景
3. **快速完成**: 测试未覆盖回合在 steer 发送前已完成的场景
4. **并发 steer**: 测试未覆盖多个 steer 请求同时发送的场景

### 改进建议

1. **增加边界测试**
   ```rust
   // 建议添加：空输入测试
   async fn turn_steer_with_empty_input_returns_error() -> Result<()>
   
   // 建议添加：多输入项测试
   async fn turn_steer_with_multiple_inputs_succeeds() -> Result<()>
   
   // 建议添加：恰好达到限制长度
   async fn turn_steer_at_max_length_succeeds() -> Result<()>
   ```

2. **增强稳定性**
   - 使用更长持续时间的命令（如 30 秒）确保测试稳定性
   - 或实现事件驱动的回合状态等待

3. **增加性能测试**
   ```rust
   // 建议添加：steer 响应时间测试
   async fn turn_steer_response_time_under_threshold() -> Result<()>
   ```

4. **移除平台限制**
   - 测试逻辑本身不依赖 Unix 特定功能
   - 可以移除 `#![cfg(unix)]` 限制，在 Windows 也运行

5. **增加并发测试**
   ```rust
   // 建议添加：并发 steer 测试
   async fn concurrent_steer_requests_handled_correctly() -> Result<()>
   ```

### 相关测试文件

- `turn_start.rs`: 回合启动测试
- `turn_interrupt.rs`: 回合中断测试
- `thread_unsubscribe.rs`: 包含回合中断时的 steer 相关行为

### 错误码参考

| 常量 | 值 | 用途 |
|------|-----|------|
| `INVALID_PARAMS_ERROR_CODE` | -32602 | JSON-RPC 标准无效参数错误 |
| `INPUT_TOO_LARGE_ERROR_CODE` | 自定义 | 输入超过最大长度 |

错误响应结构示例：
```json
{
  "error": {
    "code": -32602,
    "message": "Input exceeds the maximum length of 100000 characters.",
    "data": {
      "input_error_code": "INPUT_TOO_LARGE",
      "max_chars": 100000,
      "actual_chars": 100001
    }
  }
}
```
