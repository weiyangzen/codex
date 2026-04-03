# CommandExecResponse.ts 研究文档

## 场景与职责

`CommandExecResponse.ts` 定义了命令执行操作的最终响应类型。当命令执行完成后，服务器返回此响应包含退出码和捕获的输出内容。注意：如果启用了流式输出，stdout/stderr字段将为空（因为已通过通知发送）。

## 功能点目的

1. **执行结果返回**: 提供命令执行的最终状态
2. **退出码传递**: 传递子进程的退出码
3. **输出收集**: 在缓冲模式下返回完整的stdout/stderr
4. **流式协调**: 与`CommandExecOutputDeltaNotification`协调，避免重复数据

## 具体技术实现

### 数据结构

```typescript
/**
 * Final buffered result for `command/exec`.
 */
export type CommandExecResponse = { 
  /**
   * Process exit code.
   */
  exitCode: number, 
  /**
   * Buffered stdout capture.
   *
   * Empty when stdout was streamed via `command/exec/outputDelta`.
   */
  stdout: string, 
  /**
   * Buffered stderr capture.
   *
   * Empty when stderr was streamed via `command/exec/outputDelta`.
   */
  stderr: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `exitCode` | `number` | 进程退出码，0通常表示成功 |
| `stdout` | `string` | 标准输出内容，流式模式下为空 |
| `stderr` | `string` | 标准错误内容，流式模式下为空 |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行模块

### 引用关系

**被引用方**:
- `command/exec` RPC响应处理
- 命令执行结果处理器

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecResponse.ts               # 本文件
├── CommandExecParams.ts                 # 执行参数
├── CommandExecOutputDeltaNotification.ts # 流式输出通知
└── ...
```

## 依赖与外部交互

### 响应流程

```
发送 CommandExecParams
        ↓
命令执行中...
        ↓
┌───────┴───────┐
↓               ↓
缓冲模式      流式模式
↓               ↓
累积输出      发送 notifications
        ↓
命令完成
        ↓
返回 CommandExecResponse
        ↓
┌───────┴───────┐
↓               ↓
exitCode      exitCode
stdout        "" (空)
stderr        "" (空)
```

### 输出数据流

| 模式 | stdout来源 | stderr来源 |
|------|-----------|-----------|
| 缓冲模式 | `CommandExecResponse.stdout` | `CommandExecResponse.stderr` |
| 流式模式 | `CommandExecOutputDeltaNotification` | `CommandExecOutputDeltaNotification` |

## 风险、边界与改进建议

### 潜在风险

1. **数据丢失**: 流式模式下客户端必须确保接收所有通知
2. **编码问题**: 输出字符串的编码需要正确处理
3. **大输出**: 非常大的输出可能导致内存问题
4. **空字符串歧义**: 空stdout可能是无输出或流式模式

### 边界情况

1. **信号终止**: 被信号终止的进程可能有特殊退出码
2. **超时终止**: 超时后终止的进程退出码可能非零
3. **输出截断**: 达到`outputBytesCap`时输出可能被截断

### 改进建议

1. **添加执行时间**: 记录命令执行耗时
   ```typescript
   export type CommandExecResponse = {
     exitCode: number;
     stdout: string;
     stderr: string;
     durationMs: number;  // 新增：执行耗时
   };
   ```

2. **添加输出统计**: 提供输出元数据
   ```typescript
   export type CommandExecResponse = {
     exitCode: number;
     stdout: string;
     stderr: string;
     stdoutBytes: number;  // 实际字节数
     stderrBytes: number;
     truncated: boolean;   // 是否被截断
   };
   ```

3. **区分输出模式**: 明确标识数据来源
   ```typescript
   export type CommandExecResponse = {
     exitCode: number;
     stdout: string;
     stderr: string;
     outputMode: 'buffered' | 'streamed';  // 新增
   };
   ```

4. **添加进程信息**: 提供更多执行上下文
   ```typescript
   export type CommandExecResponse = {
     exitCode: number;
     stdout: string;
     stderr: string;
     pid: number;          // 进程ID
     command: string[];    // 实际执行的命令
   };
   ```

### 使用示例

```typescript
async function executeCommand(params: CommandExecParams): Promise<void> {
  const response: CommandExecResponse = await rpc.call('command/exec', params);
  
  // 检查退出码
  if (response.exitCode !== 0) {
    console.error(`Command failed with exit code ${response.exitCode}`);
    console.error('stderr:', response.stderr);
    throw new Error(`Command failed: ${response.stderr}`);
  }
  
  // 处理输出
  console.log('stdout:', response.stdout);
  
  return response.stdout;
}

// 处理流式+最终响应
async function executeStreaming(params: CommandExecParams): Promise<void> {
  const outputChunks: string[] = [];
  
  // 订阅通知
  rpc.onNotification('command/exec/outputDelta', (notification) => {
    const text = base64Decode(notification.deltaBase64);
    outputChunks.push(text);
    process.stdout.write(text);
  });
  
  // 执行命令
  const response: CommandExecResponse = await rpc.call('command/exec', {
    ...params,
    streamStdoutStderr: true
  });
  
  // 流式模式下response.stdout/stderr为空
  console.log('Exit code:', response.exitCode);
  console.log('Total output:', outputChunks.join(''));
}
```
