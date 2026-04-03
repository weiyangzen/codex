# CommandExecParams.ts 研究文档

## 场景与职责

`CommandExecParams.ts` 定义了 `command/exec` API 的请求参数类型，用于在服务器沙箱中执行独立命令（不创建线程或回合）。这是 Codex 提供的底层命令执行接口，支持从简单的同步命令到复杂的交互式 PTY 会话。

该类型是 Codex 命令执行系统的核心，为客户端提供了灵活的控制选项，包括流式 I/O、超时控制、环境变量设置和沙箱策略覆盖。

## 功能点目的

### 核心功能

1. **命令执行**：在服务器沙箱中执行任意命令
2. **流式 I/O**：支持实时 stdin/stdout/stderr 流传输
3. **PTY 支持**：支持伪终端模式运行交互式程序
4. **资源控制**：提供超时和输出大小限制
5. **环境配置**：支持工作目录和环境变量覆盖
6. **沙箱覆盖**：允许为单次命令指定自定义沙箱策略

### 类型定义

```typescript
import type { CommandExecTerminalSize } from "./CommandExecTerminalSize";
import type { SandboxPolicy } from "./SandboxPolicy";

/**
 * Run a standalone command (argv vector) in the server sandbox without
 * creating a thread or turn.
 *
 * The final `command/exec` response is deferred until the process exits and is
 * sent only after all `command/exec/outputDelta` notifications for that
 * connection have been emitted.
 */
export type CommandExecParams = { 
  /**
   * Command argv vector. Empty arrays are rejected.
   */
  command: Array<string>, 
  /**
   * Optional client-supplied, connection-scoped process id.
   */
  processId?: string | null, 
  /**
   * Enable PTY mode. This implies `streamStdin` and `streamStdoutStderr`.
   */
  tty?: boolean, 
  /**
   * Allow follow-up `command/exec/write` requests to write stdin bytes.
   */
  streamStdin?: boolean, 
  /**
   * Stream stdout/stderr via `command/exec/outputDelta` notifications.
   */
  streamStdoutStderr?: boolean, 
  /**
   * Optional per-stream stdout/stderr capture cap in bytes.
   */
  outputBytesCap?: number | null, 
  /**
   * Disable stdout/stderr capture truncation for this request.
   */
  disableOutputCap?: boolean, 
  /**
   * Disable the timeout entirely for this request.
   */
  disableTimeout?: boolean, 
  /**
   * Optional timeout in milliseconds.
   */
  timeoutMs?: number | null, 
  /**
   * Optional working directory. Defaults to the server cwd.
   */
  cwd?: string | null, 
  /**
   * Optional environment overrides merged into the server-computed environment.
   */
  env?: { [key in string]?: string | null } | null, 
  /**
   * Optional initial PTY size in character cells. Only valid when `tty` is true.
   */
  size?: CommandExecTerminalSize | null, 
  /**
   * Optional sandbox policy for this command.
   */
  sandboxPolicy?: SandboxPolicy | null, 
};
```

### 字段详细说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `command` | `string[]` | 是 | 命令参数向量，第一个元素是程序路径，空数组会被拒绝 |
| `processId` | `string \| null` | 否 | 客户端提供的进程标识符，用于关联后续操作（write/resize/terminate） |
| `tty` | `boolean` | 否 | 启用 PTY 模式，自动启用 `streamStdin` 和 `streamStdoutStderr` |
| `streamStdin` | `boolean` | 否 | 允许后续通过 `command/exec/write` 写入 stdin |
| `streamStdoutStderr` | `boolean` | 否 | 通过通知流式输出 stdout/stderr |
| `outputBytesCap` | `number \| null` | 否 | 每流输出上限（字节），不能与 `disableOutputCap` 同时使用 |
| `disableOutputCap` | `boolean` | 否 | 禁用输出上限，不能与 `outputBytesCap` 同时使用 |
| `disableTimeout` | `boolean` | 否 | 禁用超时，不能与 `timeoutMs` 同时使用 |
| `timeoutMs` | `number \| null` | 否 | 超时时间（毫秒），不能与 `disableTimeout` 同时使用 |
| `cwd` | `string \| null` | 否 | 工作目录，默认使用服务器当前目录 |
| `env` | `object` | 否 | 环境变量覆盖，null 值表示删除该变量 |
| `size` | `CommandExecTerminalSize` | 否 | 初始 PTY 大小（行×列），仅 PTY 模式有效 |
| `sandboxPolicy` | `SandboxPolicy` | 否 | 自定义沙箱策略，默认使用用户配置 |

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2280-2360)

```rust
/// Run a standalone command (argv vector) in the server sandbox without
/// creating a thread or turn.
///
/// The final `command/exec` response is deferred until the process exits and is
/// sent only after all `command/exec/outputDelta` notifications for that
/// connection have been emitted.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecParams {
    /// Command argv vector. Empty arrays are rejected.
    pub command: Vec<String>,
    /// Optional client-supplied, connection-scoped process id.
    #[ts(optional = nullable)]
    pub process_id: Option<String>,
    /// Enable PTY mode.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub tty: bool,
    /// Allow follow-up `command/exec/write` requests to write stdin bytes.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub stream_stdin: bool,
    /// Stream stdout/stderr via `command/exec/outputDelta` notifications.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub stream_stdout_stderr: bool,
    /// Optional per-stream stdout/stderr capture cap in bytes.
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub output_bytes_cap: Option<usize>,
    /// Disable stdout/stderr capture truncation for this request.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub disable_output_cap: bool,
    /// Disable the timeout entirely for this request.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub disable_timeout: bool,
    /// Optional timeout in milliseconds.
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub timeout_ms: Option<i64>,
    /// Optional working directory. Defaults to the server cwd.
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    /// Optional environment overrides merged into the server-computed environment.
    #[ts(optional = nullable)]
    pub env: Option<HashMap<String, Option<String>>>,
    /// Optional initial PTY size in character cells. Only valid when `tty` is true.
    #[ts(optional = nullable)]
    pub size: Option<CommandExecTerminalSize>,
    /// Optional sandbox policy for this command.
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>,
}
```

### 互斥字段验证

服务器应验证以下互斥组合：

```rust
// 伪代码
if output_bytes_cap.is_some() && disable_output_cap {
    return Err("Cannot combine outputBytesCap with disableOutputCap");
}
if timeout_ms.is_some() && disable_timeout {
    return Err("Cannot combine timeoutMs with disableTimeout");
}
```

## 关键代码路径与文件引用

### 依赖关系

```
CommandExecParams.ts
  ├── CommandExecTerminalSize.ts
  └── SandboxPolicy.ts
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `CommandExecTerminalSize.ts` | PTY 终端大小 |
| `SandboxPolicy.ts` | 沙箱策略定义 |
| `CommandExecResponse.ts` | 执行响应 |
| `CommandExecOutputDeltaNotification.ts` | 输出通知 |
| `CommandExecWriteParams.ts` | 写入 stdin |
| `CommandExecResizeParams.ts` | 调整 PTY 大小 |
| `CommandExecTerminateParams.ts` | 终止命令 |

### 使用模式

#### 模式 1：简单同步执行
```typescript
const params: CommandExecParams = {
  command: ["echo", "Hello World"],
};
// 响应包含完整的 stdout/stderr
```

#### 模式 2：流式输出
```typescript
const params: CommandExecParams = {
  command: ["long-running-process"],
  processId: "proc-123",
  streamStdoutStderr: true,
  outputBytesCap: 1024 * 1024,
};
// 接收 outputDelta 通知，最后接收响应
```

#### 模式 3：交互式 PTY
```typescript
const params: CommandExecParams = {
  command: ["bash"],
  processId: "bash-123",
  tty: true,
  size: { rows: 24, cols: 80 },
};
// 使用 write 发送输入，接收 outputDelta 输出
// 使用 resize 调整终端大小
```

## 依赖与外部交互

### 与 Thread/Turn 命令执行的区别

| 特性 | `command/exec` | Thread/Turn 执行 |
|------|----------------|------------------|
| 上下文 | 独立执行 | 在对话上下文中 |
| 审批 | 直接执行（需沙箱权限） | 可能需要用户审批 |
| 持久化 | 不持久化 | 记录在历史中 |
| 连接 | 连接断开则终止 | 可后台继续 |
| 适用场景 | 快速检查、交互式 shell | AI 驱动的任务执行 |

### 沙箱策略继承

`sandboxPolicy` 字段允许临时覆盖：

```typescript
// 使用默认策略
{ command: ["ls"] }

// 临时放宽网络访问
{ 
  command: ["curl", "https://example.com"],
  sandboxPolicy: {
    type: "workspaceWrite",
    networkAccess: true,
  }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **资源耗尽**：无限制的命令可能消耗大量资源
2. **安全风险**：自定义沙箱策略可能绕过安全限制
3. **连接依赖**：连接断开导致进程终止可能不符合预期
4. **竞态条件**：write/resize/terminate 可能在进程结束后到达

### 边界情况

1. **空命令数组**：服务器应拒绝并返回错误
2. **无效 processId**：后续操作使用无效 ID 应返回错误
3. **PTY 大小无效**：非 PTY 模式提供 size 应被忽略
4. **环境变量 null**：表示删除该变量，而非设置为空字符串

### 改进建议

1. **添加优先级**：
   ```typescript
   interface CommandExecParams {
     // ...
     priority?: "low" | "normal" | "high";
   }
   ```

2. **添加资源限制**：
   ```typescript
   interface CommandExecParams {
     // ...
     resourceLimits?: {
       maxMemoryMb?: number;
       maxCpuPercent?: number;
       maxFileDescriptors?: number;
     };
   }
   ```

3. **添加回调 URL**：
   ```typescript
   interface CommandExecParams {
     // ...
     callbackUrl?: string;  // 命令完成时通知
   }
   ```

4. **支持后台执行**：
   ```typescript
   interface CommandExecParams {
     // ...
     detach?: boolean;  // 连接断开继续执行
   }
   ```

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 向后兼容：是

### 最佳实践

1. **总是提供 processId**：如果使用流式功能
2. **设置合理的超时**：防止资源泄漏
3. **使用输出上限**：防止内存溢出
4. **验证互斥字段**：客户端应预先验证
