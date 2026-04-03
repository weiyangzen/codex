# CommandExecOutputDeltaNotification.ts 研究文档

## 场景与职责

`CommandExecOutputDeltaNotification.ts` 定义了命令执行输出增量通知的类型，用于 `command/exec/outputDelta` 通知消息。当客户端通过 `command/exec` 启动命令并启用流式输出时，服务器通过此通知类型实时推送 stdout/stderr 数据。

该类型是 Codex 实时命令执行系统的核心组件，支持 PTY 模式和流式 I/O 的交互式命令执行场景。

## 功能点目的

### 核心功能

1. **实时输出流**：将命令输出实时推送给客户端
2. **双通道支持**：区分 stdout 和 stderr 流
3. **Base64 编码**：支持二进制数据的安全传输
4. **流量控制**：通过 `capReached` 标记通知客户端输出被截断

### 类型定义

```typescript
import type { CommandExecOutputStream } from "./CommandExecOutputStream";

/**
 * Base64-encoded output chunk emitted for a streaming `command/exec` request.
 *
 * These notifications are connection-scoped. If the originating connection
 * closes, the server terminates the process.
 */
export type CommandExecOutputDeltaNotification = { 
  /**
   * Client-supplied, connection-scoped `processId` from the original
   * `command/exec` request.
   */
  processId: string, 
  /**
   * Output stream for this chunk.
   */
  stream: CommandExecOutputStream, 
  /**
   * Base64-encoded output bytes.
   */
  deltaBase64: string, 
  /**
   * `true` on the final streamed chunk for a stream when `outputBytesCap`
   * truncated later output on that stream.
   */
  capReached: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `processId` | `string` | 客户端提供的进程标识符，用于关联输出到特定命令 |
| `stream` | `CommandExecOutputStream` | 输出流类型（stdout 或 stderr） |
| `deltaBase64` | `string` | Base64 编码的输出数据块 |
| `capReached` | `boolean` | 是否因达到输出上限而截断 |

### 流类型枚举

```typescript
type CommandExecOutputStream = "stdout" | "stderr";
```

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 2436-2445)

```rust
/// Stream label for `command/exec/outputDelta` notifications.
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum CommandExecOutputStream {
    /// stdout stream. PTY mode multiplexes terminal output here.
    Stdout,
    /// stderr stream.
    Stderr,
}
```

通知类型定义（行 2447+ 附近，在 Thread/Turn 相关代码之后）：

```rust
// 在 v2.rs 的 Thread/Turn 部分之后定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecOutputDeltaNotification {
    /// Client-supplied, connection-scoped `processId` from the original
    /// `command/exec` request.
    pub process_id: String,
    /// Output stream for this chunk.
    pub stream: CommandExecOutputStream,
    /// Base64-encoded output bytes.
    pub delta_base64: String,
    /// `true` on the final streamed chunk for a stream when `outputBytesCap`
    /// truncated later output on that stream.
    pub cap_reached: bool,
}
```

### 流式输出机制

1. **启动命令**：
   ```typescript
   const params: CommandExecParams = {
     command: ["long-running-process"],
     processId: "proc-123",
     streamStdoutStderr: true,
     outputBytesCap: 1024 * 1024,  // 1MB 上限
   };
   ```

2. **接收输出**：
   ```typescript
   // 通知通过 WebSocket/SSE 推送
   interface CommandExecOutputDeltaNotification {
     processId: "proc-123";
     stream: "stdout";
     deltaBase64: "SGVsbG8gV29ybGQh";  // "Hello World!"
     capReached: false;
   }
   ```

3. **结束检测**：
   - 命令退出时发送最终响应 `CommandExecResponse`
   - 如果输出被截断，`capReached` 为 `true`

## 关键代码路径与文件引用

### 依赖关系

```
CommandExecOutputDeltaNotification.ts
  └── CommandExecOutputStream.ts
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `CommandExecOutputStream.ts` | 输出流类型枚举 |
| `CommandExecParams.ts` | 命令执行参数（启用流式输出） |
| `CommandExecResponse.ts` | 最终执行结果 |
| `CommandExecWriteParams.ts` | 向命令写入输入 |
| `CommandExecTerminateParams.ts` | 终止命令执行 |

### 完整流程

```
Client                              Server
  |                                    |
  |-- command/exec ------------------->|
  |   CommandExecParams                |
  |   (streamStdoutStderr: true)       |
  |<-- notification: outputDelta ------|
  |   (chunk 1)                        |
  |<-- notification: outputDelta ------|
  |   (chunk 2)                        |
  |<-- ... more chunks ...             |
  |<-- response: CommandExecResponse --|
  |   (exitCode, stdout, stderr)       |
```

## 依赖与外部交互

### 连接作用域

重要特性：**这些通知是连接作用域的**：

- 如果原始连接关闭，服务器会终止进程
- 客户端断线后重新连接不会继续接收输出
- 需要持久化执行的命令应使用 Thread/Turn 机制

### PTY 模式

当启用 `tty: true` 时：
- 所有终端输出多路复用到 `stdout` 流
- `stderr` 流可能不包含数据
- 支持交互式程序（如 vim、htop）

### 输出上限

`outputBytesCap` 和 `capReached` 的配合：

```typescript
// 场景：命令输出 10MB，上限为 1MB
const params: CommandExecParams = {
  outputBytesCap: 1024 * 1024,  // 1MB
};

// 服务器行为：
// 1. 发送多个通知，总计约 1MB 数据
// 2. 最后一个通知 capReached: true
// 3. 丢弃后续输出
// 4. 命令继续运行或根据策略终止
```

## 风险、边界与改进建议

### 潜在风险

1. **内存压力**：大量并发流式命令可能消耗大量内存
2. **网络拥塞**：高频小数据块通知可能导致网络拥塞
3. **Base64 开销**：编码增加约 33% 的数据传输量
4. **连接依赖**：连接断开导致进程终止可能不符合预期

### 边界情况

1. **空输出块**：
   - 某些程序可能产生空行输出
   - `deltaBase64` 可能为空字符串

2. **快速终止**：
   - 命令快速完成时可能没有输出通知
   - 直接返回 `CommandExecResponse`

3. **超大输出块**：
   - 单块输出可能超过网络帧大小
   - 需要服务器实现分片逻辑

4. **混合流**：
   - stdout 和 stderr 可能交错到达
   - 客户端需要正确重组

### 改进建议

1. **添加序列号**：
   ```typescript
   interface CommandExecOutputDeltaNotification {
     // ...
     sequenceNumber: number;  // 用于检测丢失和排序
   }
   ```

2. **支持压缩**：
   ```typescript
   interface CommandExecOutputDeltaNotification {
     // ...
     encoding: "base64" | "base64-gzip";  // 支持压缩
   }
   ```

3. **添加时间戳**：
   ```typescript
   interface CommandExecOutputDeltaNotification {
     // ...
     timestamp: number;  // 输出产生的时间戳
   }
   ```

4. **批量发送**：
   - 支持将多个小块合并为单个通知
   - 减少网络往返开销

5. **流量控制**：
   ```typescript
   interface CommandExecOutputDeltaNotification {
     // ...
     flowControl: {
       windowSize: number;  // 滑动窗口大小
       ackRequired: boolean;  // 是否需要确认
     };
   }
   ```

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定
- 向后兼容：是

### 性能建议

1. **客户端缓冲**：
   - 实现输出缓冲区减少渲染频率
   - 使用虚拟列表显示大量输出

2. **增量解码**：
   - 增量解码 Base64 数据
   - 避免重复解码已接收数据

3. **连接保活**：
   - 使用心跳保持连接
   - 避免长时间无输出导致超时
