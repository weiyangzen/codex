# WindowsSandboxSetupCompletedNotification.ts Research Document

## 场景与职责

`WindowsSandboxSetupCompletedNotification` 是 App-Server Protocol v2 中的服务器端通知类型，用于通知客户端 Windows 沙盒环境的设置完成状态。该类型在以下场景中发挥关键作用：

1. **Windows 沙盒初始化**: 通知客户端 Windows 沙盒环境的设置已完成（成功或失败）
2. **权限提升流程**: 在需要管理员权限的沙盒设置完成后通知客户端
3. **NUX（新用户体验）流程**: 支持 Windows 沙盒功能的引导设置流程
4. **错误处理**: 当沙盒设置失败时，向客户端传递错误信息
5. **状态同步**: 确保客户端了解当前沙盒环境的准备状态

## 功能点目的

该通知类型的核心目的是：

- **异步完成通知**: 沙盒设置是异步操作，通过通知告知客户端完成状态
- **结果传递**: 传递设置是否成功以及失败原因
- **模式确认**: 确认设置的沙盒模式（提升权限或非提升权限）
- **用户体验**: 支持 UI 显示设置进度和结果
- **流程控制**: 客户端可以基于通知决定后续操作（如开始执行命令）

## 具体技术实现

### TypeScript 类型定义

```typescript
export type WindowsSandboxSetupCompletedNotification = { 
  mode: WindowsSandboxSetupMode, 
  success: boolean, 
  error: string | null, 
};
```

### Rust 源类型定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct WindowsSandboxSetupCompletedNotification {
    pub mode: WindowsSandboxSetupMode,
    pub success: bool,
    pub error: Option<String>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `mode` | `WindowsSandboxSetupMode` | 沙盒设置模式（`"elevated"` 或 `"unelevated"`） |
| `success` | `boolean` | 设置是否成功 |
| `error` | `string \| null` | 失败时的错误信息，成功时为 null |

### 状态组合

| `success` | `error` | 含义 |
|----------|---------|------|
| `true` | `null` | 设置成功完成 |
| `false` | `"具体错误信息"` | 设置失败，附带错误原因 |

### WindowsSandboxSetupMode

```typescript
export type WindowsSandboxSetupMode = "elevated" | "unelevated";
```

- **`elevated`**: 提升权限模式，需要管理员权限，提供更完整的沙盒环境
- **`unelevated`**: 非提升权限模式，使用受限令牌，权限更严格

### 设置流程

```
客户端发送: WindowsSandboxSetupStartParams
                    │
                    ▼
服务器开始异步设置
                    │
                    ├── 设置进行中 ──→ 客户端可显示进度
                    │
                    ▼
服务器发送: WindowsSandboxSetupCompletedNotification
                    │
                    ├── success: true → 客户端可以继续执行命令
                    └── success: false → 客户端显示错误，提供重试选项
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 5001-5008) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/WindowsSandboxSetupCompletedNotification.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/WindowsSandboxSetupCompletedNotification.json` | JSON Schema 定义 |

### 使用位置

| 文件路径 | 用途 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 注册为服务器通知变体 |
| `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts` | 包含在服务器通知联合类型中 |
| `codex-rs/core/src/windows_sandbox.rs` | Windows 沙盒核心逻辑 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 发送设置完成通知 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 应用服务器处理通知 |
| `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs` | 集成测试 |

### 相关类型

| 类型 | 说明 |
|-----|------|
| `WindowsSandboxSetupStartParams` | 启动沙盒设置的请求参数 |
| `WindowsSandboxSetupStartResponse` | 启动请求的响应 |
| `WindowsSandboxSetupMode` | 沙盒模式枚举 |

## 依赖与外部交互

### 内部依赖

- **`WindowsSandboxSetupMode`**: 沙盒设置模式枚举
- **`WindowsSandboxSetupStartParams`**: 对应的启动参数
- **`WindowsSandboxLevel`**: 核心层的沙盒级别定义

### 协议依赖

- 属于 **Server Notification** 类别（服务器 → 客户端单向通知）
- 通过 WebSocket 或 SSE 传输
- 与 `WindowsSandboxSetupStartParams`/`WindowsSandboxSetupStartResponse` 形成完整的请求-通知流程

### Windows 系统交互

```rust
// 伪代码示意
pub async fn setup_windows_sandbox(mode: WindowsSandboxSetupMode) -> Result<(), SandboxError> {
    match mode {
        Elevated => {
            // 请求管理员权限
            // 配置 AppContainer 或类似机制
            // 设置文件系统重定向
        }
        Unelevated => {
            // 使用受限令牌
            // 配置基础沙盒策略
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **权限提升失败**: `elevated` 模式下用户可能拒绝 UAC 提示
2. **系统兼容性**: 某些 Windows 版本或配置可能不支持沙盒功能
3. **资源泄漏**: 沙盒设置失败可能导致资源未正确清理
4. **通知丢失**: 网络问题可能导致客户端收不到完成通知

### 边界情况

1. **重复通知**: 同一设置的多次完成通知（应幂等处理）
2. **超时无响应**: 设置操作长时间未完成，客户端需要超时处理
3. **部分成功**: 某些设置步骤成功，某些失败（当前设计为二元成功/失败）
4. **模式不匹配**: 请求的模式与实际设置的模式不一致

### 改进建议

1. **添加进度通知**: 除了完成通知，添加进度更新通知：
   ```typescript
   export type WindowsSandboxSetupProgressNotification = {
     mode: WindowsSandboxSetupMode,
     stage: "initializing" | "configuring" | "verifying",
     progress: number, // 0-100
   };
   ```

2. **详细错误分类**: 将错误分类为可恢复和不可恢复：
   ```typescript
   export type WindowsSandboxSetupCompletedNotification = {
     mode: WindowsSandboxSetupMode,
     success: boolean,
     error: {
       code: "PERMISSION_DENIED" | "UNSUPPORTED_OS" | "RESOURCE_UNAVAILABLE" | "TIMEOUT" | "UNKNOWN",
       message: string,
       recoverable: boolean,
     } | null,
   };
   ```

3. **添加时间戳**: 记录设置耗时：
   ```typescript
   export type WindowsSandboxSetupCompletedNotification = {
     mode: WindowsSandboxSetupMode,
     success: boolean,
     error: string | null,
     durationMs: number, // 设置耗时
     completedAt: number, // Unix timestamp
   };
   ```

4. **回退机制**: 当 `elevated` 失败时，自动尝试 `unelevated`：
   ```rust
   pub async fn setup_with_fallback(requested_mode: WindowsSandboxSetupMode) {
       if let Err(e) = setup(requested_mode).await {
           if requested_mode == Elevated {
               log::warn!("Elevated setup failed, trying unelevated: {}", e);
               setup(Unelevated).await
           } else {
               Err(e)
           }
       }
   }
   ```

5. **健康检查**: 添加设置后的健康检查：
   ```typescript
   export type WindowsSandboxSetupCompletedNotification = {
     mode: WindowsSandboxSetupSetupMode,
     success: boolean,
     error: string | null,
     healthCheck: {
       filesystemAccess: boolean,
       networkAccess: boolean,
       processIsolation: boolean,
     } | null,
   };
   ```

### 测试覆盖

- 集成测试: `codex-rs/app-server/tests/suite/v2/windows_sandbox_setup.rs`
- 建议添加：
  - 权限被拒绝场景测试
  - 超时处理测试
  - 网络分区恢复测试
  - 不同 Windows 版本兼容性测试
  - 资源清理验证测试
