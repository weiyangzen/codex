# CommandExecTerminateParams.ts 研究文档

## 场景与职责

`CommandExecTerminateParams.ts` 定义了终止正在运行的命令执行会话的请求参数类型。当用户需要强制停止长时间运行的命令或交互式会话时，使用此类型发送终止请求。

## 功能点目的

1. **进程终止**: 强制结束正在运行的命令进程
2. **会话清理**: 清理相关的资源和状态
3. **用户控制**: 允许用户中断不想要的操作
4. **超时处理**: 支持超时后的强制终止

## 具体技术实现

### 数据结构

```typescript
/**
 * Terminate a running `command/exec` session.
 */
export type CommandExecTerminateParams = { 
  /**
   * Client-supplied, connection-scoped `processId` from the original
   * `command/exec` request.
   */
  processId: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `processId` | `string` | 要终止的进程ID，来自原始`command/exec`请求 |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行模块

### 引用关系

**被引用方**:
- `command/exec/terminate` RPC处理代码
- 进程管理器

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecTerminateParams.ts       # 本文件
├── CommandExecTerminateResponse.ts     # 终止响应
├── CommandExecParams.ts                # 初始执行参数
└── ...
```

## 依赖与外部交互

### 终止流程

```
用户触发终止
        ↓
构建 CommandExecTerminateParams
        ↓
发送 command/exec/terminate RPC
        ↓
服务器查找进程
        ↓
┌───────┴───────┐
↓               ↓
找到进程      未找到
↓               ↓
发送 SIGTERM   返回错误
等待优雅退出
        ↓
超时?
        ↓
是 → 发送 SIGKILL
        ↓
进程终止
        ↓
返回响应
```

### 信号序列

```
终止请求
    ↓
SIGTERM (优雅终止)
    ↓
等待 (默认5秒)
    ↓
┌───┴───┐
↓       ↓
退出    仍在运行
    ↓
SIGKILL (强制终止)
```

## 风险、边界与改进建议

### 潜在风险

1. **数据丢失**: 强制终止可能导致未保存数据丢失
2. **资源泄漏**: 子进程可能未被正确终止
3. **僵尸进程**: 终止后未正确回收可能产生僵尸进程
4. **竞态条件**: 进程可能在终止请求到达时刚好退出

### 边界情况

1. **已退出进程**: 终止已退出的进程应返回错误
2. **僵尸进程**: 无法终止已经是僵尸的进程
3. **权限问题**: 某些进程可能需要更高权限才能终止
4. **孤儿进程**: 终止父进程后子进程可能成为孤儿

### 改进建议

1. **添加终止原因**: 用于日志和审计
   ```typescript
   export type CommandExecTerminateParams = { 
     processId: string;
     reason?: 'userRequest' | 'timeout' | 'cleanup';
   };
   ```

2. **添加信号选择**: 允许指定终止信号
   ```typescript
   export type CommandExecTerminateParams = { 
     processId: string;
     signal?: 'SIGTERM' | 'SIGKILL' | 'SIGINT';
     gracefulTimeoutMs?: number;
   };
   ```

3. **添加级联选项**: 控制是否终止子进程
   ```typescript
   export type CommandExecTerminateParams = { 
     processId: string;
     includeChildren?: boolean;  // 默认true
   };
   ```

4. **添加等待确认**: 确保进程确实已终止
   ```typescript
   export type CommandExecTerminateResponse = {
     success: boolean;
     processState: 'terminated' | 'notFound' | 'zombie';
     exitCode?: number;
   };
   ```

### 使用示例

```typescript
// 终止特定进程
async function terminateProcess(processId: string): Promise<void> {
  const params: CommandExecTerminateParams = { processId };
  
  try {
    await rpc.call('command/exec/terminate', params);
    console.log('Process terminated successfully');
  } catch (error) {
    console.error('Failed to terminate process:', error);
  }
}

// 带超时的执行
async function executeWithTimeout(
  params: CommandExecParams, 
  timeoutMs: number
): Promise<CommandExecResponse> {
  const processId = params.processId!;
  
  const timeoutId = setTimeout(() => {
    const terminateParams: CommandExecTerminateParams = { processId };
    rpc.call('command/exec/terminate', terminateParams);
  }, timeoutMs);
  
  try {
    const response = await rpc.call('command/exec', params);
    clearTimeout(timeoutId);
    return response;
  } catch (error) {
    clearTimeout(timeoutId);
    throw error;
  }
}

// 取消按钮处理
function setupCancelButton(processId: string): void {
  const cancelButton = document.getElementById('cancel');
  cancelButton?.addEventListener('click', () => {
    const params: CommandExecTerminateParams = { processId };
    rpc.call('command/exec/terminate', params);
  });
}
```
