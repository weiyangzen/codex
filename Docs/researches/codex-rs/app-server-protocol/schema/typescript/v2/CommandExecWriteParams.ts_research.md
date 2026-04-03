# CommandExecWriteParams.ts 研究文档

## 场景与职责

`CommandExecWriteParams.ts` 定义了向正在运行的命令执行会话写入数据（stdin）的请求参数类型。用于向交互式进程发送输入，支持写入数据、关闭stdin或两者同时进行。

## 功能点目的

1. **交互式输入**: 向交互式命令（如shell、REPL）发送输入
2. **数据流传输**: 支持向进程传输大量数据
3. **流控制**: 支持关闭stdin表示输入结束
4. **PTY交互**: 支持PTY模式下的终端输入

## 具体技术实现

### 数据结构

```typescript
/**
 * Write stdin bytes to a running `command/exec` session, close stdin, or
 * both.
 */
export type CommandExecWriteParams = { 
  /**
   * Client-supplied, connection-scoped `processId` from the original
   * `command/exec` request.
   */
  processId: string, 
  /**
   * Optional base64-encoded stdin bytes to write.
   */
  deltaBase64?: string | null, 
  /**
   * Close stdin after writing `deltaBase64`, if present.
   */
  closeStdin?: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `processId` | `string` | 必填 | 目标进程的ID |
| `deltaBase64` | `string \| null` | 可选 | Base64编码的输入数据 |
| `closeStdin` | `boolean` | 可选 | 是否关闭stdin |

### 使用模式

| 场景 | deltaBase64 | closeStdin |
|------|-------------|------------|
| 发送输入 | 有数据 | false/undefined |
| 结束输入 | null/undefined | true |
| 最后输入 | 有数据 | true |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行模块

### 引用关系

**被引用方**:
- `command/exec/write` RPC处理代码
- 交互式终端组件

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecWriteParams.ts       # 本文件
├── CommandExecWriteResponse.ts     # 写入响应
├── CommandExecParams.ts            # 初始执行参数
└── ...
```

## 依赖与外部交互

### 写入流程

```
用户输入
      ↓
编码为Base64
      ↓
构建 CommandExecWriteParams
      ↓
发送 command/exec/write RPC
      ↓
服务器解码并写入stdin
      ↓
进程接收输入
```

### 交互式会话

```
启动交互式shell
        ↓
显示提示符
        ↓
用户输入 "ls"
        ↓
CommandExecWriteParams
  { processId, deltaBase64: "bHM=", closeStdin: false }
        ↓
shell执行命令
        ↓
返回输出
        ↓
显示结果
        ↓
等待下一次输入
```

### 批量数据传输

```
发送大数据块1
        ↓
发送大数据块2
        ↓
...
        ↓
发送最后一块 + closeStdin: true
        ↓
进程处理完整数据
```

## 风险、边界与改进建议

### 潜在风险

1. **编码开销**: Base64编码增加33%的数据量
2. **缓冲区溢出**: 快速写入可能超过进程读取速度
3. **竞态条件**: 进程可能在写入前退出
4. **编码错误**: 无效的Base64数据会导致错误

### 边界情况

1. **空写入**: `deltaBase64: ""` 是有效的（空写入）
2. **仅关闭**: 可以只关闭stdin而不写入数据
3. **已关闭**: 向已关闭的stdin写入应返回错误
4. **非交互进程**: 向非流式进程写入可能无效

### 改进建议

1. **添加偏移量**: 支持断点续传
   ```typescript
   export type CommandExecWriteParams = { 
     processId: string;
     deltaBase64?: string | null;
     closeStdin?: boolean;
     offset?: number;  // 数据流中的偏移量
   };
   ```

2. **添加编码选项**: 支持不同编码
   ```typescript
   export type CommandExecWriteParams = { 
     processId: string;
     deltaBase64?: string | null;
     closeStdin?: boolean;
     encoding?: 'base64' | 'utf8' | 'binary';  // 默认base64
   };
   ```

3. **添加控制字符**: 支持发送特殊控制序列
   ```typescript
   export type CommandExecWriteParams = { 
     processId: string;
     deltaBase64?: string | null;
     closeStdin?: boolean;
     controlChar?: 'SIGINT' | 'SIGQUIT' | 'EOF';  // 控制字符
   };
   ```

4. **添加写入确认**: 返回实际写入的字节数
   ```typescript
   export type CommandExecWriteResponse = {
     bytesWritten: number;
     stdinClosed: boolean;
   };
   ```

### 使用示例

```typescript
// 发送简单输入
async function sendInput(processId: string, text: string): Promise<void> {
  const params: CommandExecWriteParams = {
    processId,
    deltaBase64: btoa(text)
  };
  
  await rpc.call('command/exec/write', params);
}

// 发送命令并执行
async function executeCommand(
  processId: string, 
  command: string
): Promise<void> {
  const params: CommandExecWriteParams = {
    processId,
    deltaBase64: btoa(command + '\n'),  // 添加换行
    closeStdin: false
  };
  
  await rpc.call('command/exec/write', params);
}

// 结束输入
async function endInput(processId: string): Promise<void> {
  const params: CommandExecWriteParams = {
    processId,
    closeStdin: true
  };
  
  await rpc.call('command/exec/write', params);
}

// 发送文件内容
async function sendFile(processId: string, content: string): Promise<void> {
  const chunkSize = 4096;
  
  for (let i = 0; i < content.length; i += chunkSize) {
    const chunk = content.slice(i, i + chunkSize);
    const isLast = i + chunkSize >= content.length;
    
    const params: CommandExecWriteParams = {
      processId,
      deltaBase64: btoa(chunk),
      closeStdin: isLast
    };
    
    await rpc.call('command/exec/write', params);
  }
}

// 发送Ctrl+C
async function sendInterrupt(processId: string): Promise<void> {
  const params: CommandExecWriteParams = {
    processId,
    deltaBase64: btoa('\x03')  // Ctrl+C = ASCII 3
  };
  
  await rpc.call('command/exec/write', params);
}
```
