# WindowsSandboxSetupStartResponse.ts Research Document

## 场景与职责

`WindowsSandboxSetupStartResponse` 是 App-Server Protocol v2 中的服务器响应类型，用于确认 `windowsSandbox/setup` 请求的接收状态。该类型在以下场景中发挥关键作用：

1. **异步操作确认**: 确认沙盒设置请求已被接受并开始异步处理
2. **流程控制**: 告知客户端是否可以继续等待完成通知或需要采取其他行动
3. **错误早期发现**: 在设置开始前发现参数错误或其他可快速检测的问题
4. **资源管理**: 指示系统是否有足够资源启动新的沙盒设置流程
5. **用户体验**: 支持客户端显示"设置中"状态，提供操作反馈

## 功能点目的

该响应类型的核心目的是：

- **请求确认**: 明确告知客户端请求是否被接受
- **状态同步**: 建立客户端对设置流程已启动的认知
- **协议完整性**: 完成 `windowsSandbox/setup` 请求-响应循环
- **错误边界**: 区分同步错误（立即返回）和异步错误（通过通知返回）
- **调试支持**: 提供可用于日志记录和故障排查的状态信息

## 具体技术实现

### TypeScript 类型定义

```typescript
export type WindowsSandboxSetupStartResponse = { 
  started: boolean, 
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupStartResponse {
    pub started: bool,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `started` | `boolean` | 沙盒设置是否已成功启动 |

### 响应语义

| `started` 值 | 含义 | 后续操作 |
|-------------|------|---------|
| `true` | 设置流程已成功启动 | 客户端应等待 `WindowsSandboxSetupCompletedNotification` |
| `false` | 设置流程未能启动 | 客户端应检查错误响应或重试 |

### 响应流程

```
客户端发送: WindowsSandboxSetupStartParams
                    │
                    ▼
服务器同步验证:
    ├── 参数格式检查
    ├── 权限检查
    ├── 资源可用性检查
    └── 并发冲突检查
                    │
                    ├── 验证失败 → 返回 JSON-RPC Error
                    │
                    └── 验证通过
                          │
                          ▼
                    启动异步设置任务
                          │
                          ▼
                    返回 WindowsSandboxSetupStartResponse
                          │
                          ├── started: true → 客户端等待完成通知
                          └── started: false → 客户端处理失败
```

### 与完成通知的关系

```
WindowsSandboxSetupStartResponse          WindowsSandboxSetupCompletedNotification
        │                                              │
        ├── started: true ─────────────────────────────┤
        │                         异步设置完成          │
        │                         success: true/false   │
        │                                              │
        └── started: false                             │
            (不会发送完成通知)                          │
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4994-4999) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WindowsSandboxSetupStartResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupStartResponse.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为 `windowsSandbox/setup` 方法的响应类型 |
| `codex-rs/app-server-protocol/schema/json/ClientRequest.json` | 在客户端请求 schema 中引用响应类型 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 构造并返回设置启动响应 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 处理设置启动响应 |
| `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs` | 测试中验证响应内容 |

### 请求-响应映射

在 `common.rs` 中注册：

```rust
client_request_definitions! {
    // ...
    WindowsSandboxSetupStart => "windowsSandbox/setup" {
        params: WindowsSandboxSetupStartParams,
        response: WindowsSandboxSetupStartResponse,
    },
    // ...
}
```

## 依赖与外部交互

### 内部依赖

- **`WindowsSandboxSetupStartParams`**: 对应的请求参数类型
- **`WindowsSandboxSetupCompletedNotification`**: 后续的完成通知类型

### 协议依赖

- 属于 **Client Response** 类别（服务器 → 客户端）
- 对应 RPC 方法: `windowsSandbox/setup`
- 与 `WindowsSandboxSetupCompletedNotification` 形成完整的异步操作反馈

### 错误处理对比

| 场景 | 响应类型 | 说明 |
|-----|---------|------|
| 参数无效 | JSON-RPC Error | code: -32602, 同步返回 |
| 权限不足 | JSON-RPC Error | code: -32000, 同步返回 |
| 资源不足 | `WindowsSandboxSetupStartResponse { started: false }` | 或 JSON-RPC Error |
| 设置已进行中 | `WindowsSandboxSetupStartResponse { started: false }` | 或返回当前状态 |
| 设置成功启动 | `WindowsSandboxSetupStartResponse { started: true }` | 后续通过通知返回结果 |
| 设置启动后失败 | `WindowsSandboxSetupCompletedNotification { success: false }` | 异步通知 |

## 风险、边界与改进建议

### 潜在风险

1. **响应歧义**: `started: false` 的原因不明确，客户端难以决定后续操作
2. **竞态条件**: 在响应发送和通知发送之间，客户端状态可能发生变化
3. **通知丢失**: 如果 `started: true` 但完成通知丢失，客户端可能无限等待
4. **重复启动**: 客户端可能基于模糊响应重复发送启动请求

### 边界情况

1. **快速完成**: 设置可能在响应发送前就已经完成
2. **部分启动**: 设置流程部分启动后失败（`started: true` 但后续出错）
3. **客户端断开**: 客户端在收到响应后断开连接，错过完成通知
4. **服务器重启**: 服务器在设置进行中重启，客户端状态不一致

### 改进建议

1. **添加原因字段**: 明确 `started: false` 的原因：
   ```typescript
   export type WindowsSandboxSetupStartResponse = {
     started: boolean,
     reason?: {
       code: "ALREADY_IN_PROGRESS" | "INSUFFICIENT_RESOURCES" | 
             "PERMISSION_DENIED" | "UNSUPPORTED_PLATFORM",
       message: string,
     },
   };
   ```

2. **添加操作 ID**: 用于关联响应和后续通知：
   ```typescript
   export type WindowsSandboxSetupStartResponse = {
     started: boolean,
     operationId: string, // 用于关联完成通知
   };
   
   export type WindowsSandboxSetupCompletedNotification = {
     operationId: string, // 与响应中的 ID 匹配
     mode: WindowsSandboxSetupMode,
     success: boolean,
     error: string | null,
   };
   ```

3. **预计时间**: 提供预计完成时间，帮助客户端实现超时逻辑：
   ```typescript
   export type WindowsSandboxSetupStartResponse = {
     started: boolean,
     estimatedDurationMs: number, // 预计完成时间
   };
   ```

4. **状态查询**: 支持查询当前设置状态：
   ```typescript
   // 新增请求类型
   export type WindowsSandboxSetupStatusParams = {};
   
   export type WindowsSandboxSetupStatusResponse = {
     isSettingUp: boolean,
     currentMode?: WindowsSandboxSetupMode,
     progress?: number, // 0-100
   };
   ```

5. **幂等性支持**: 添加幂等键支持重复请求：
   ```typescript
   export type WindowsSandboxSetupStartParams = {
     mode: WindowsSandboxSetupMode,
     cwd?: AbsolutePathBuf | null,
     idempotencyKey?: string, // 幂等键
   };
   
   export type WindowsSandboxSetupStartResponse = {
     started: boolean,
     idempotencyKey: string, // 回显幂等键
   };
   ```

6. **乐观响应**: 对于已知会快速完成的场景，考虑直接返回结果：
   ```typescript
   export type WindowsSandboxSetupStartResponse = {
     started: boolean,
     completed?: WindowsSandboxSetupCompletedNotification, // 如果已完成
   };
   ```

### 测试覆盖

- 集成测试: `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
- 建议添加：
  - `started: false` 的各种原因测试
  - 响应和通知的关联性测试
  - 客户端断开和重连场景测试
  - 服务器重启后的状态恢复测试
  - 幂等性测试（重复请求处理）
  - 超时处理测试
