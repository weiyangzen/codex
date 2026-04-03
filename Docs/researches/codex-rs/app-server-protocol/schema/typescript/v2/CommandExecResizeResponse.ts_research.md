# CommandExecResizeResponse.ts 研究文档

## 场景与职责

`CommandExecResizeResponse.ts` 定义了调整PTY会话大小操作的响应类型。作为`command/exec/resize`RPC的返回类型，它表示终端尺寸调整操作的成功确认。

## 功能点目的

1. **操作确认**: 确认终端尺寸调整请求已被成功处理
2. **空响应优化**: 使用空对象类型表示无需额外数据的成功响应
3. **协议一致性**: 保持请求-响应模式的完整性

## 具体技术实现

### 数据结构

```typescript
/**
 * Empty success response for `command/exec/resize`.
 */
export type CommandExecResizeResponse = Record<string, never>;
```

### 说明

- 使用`Record<string, never>`表示一个空对象类型
- 不包含任何字段，仅表示操作成功
- 与TypeScript的`{}`类型不同，它禁止任何属性

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行模块

### 引用关系

**被引用方**:
- `command/exec/resize` RPC响应处理

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecResizeResponse.ts       # 本文件
├── CommandExecResizeParams.ts         # 对应请求参数
└── ...
```

## 依赖与外部交互

### 响应流程

```
发送 CommandExecResizeParams
        ↓
服务器处理
        ↓
┌───────┴───────┐
↓               ↓
成功          失败
↓               ↓
{}           错误响应
(本类型)      (异常)
```

## 风险、边界与改进建议

### 潜在问题

1. **无反馈信息**: 无法得知实际应用的尺寸
2. **错误处理**: 错误通过异常而非响应传递
3. **异步确认**: 尺寸调整的实际效果可能有延迟

### 改进建议

1. **添加确认信息**: 返回调整后的尺寸
   ```typescript
   export type CommandExecResizeResponse = {
     appliedSize: CommandExecTerminalSize;
   };
   ```

2. **添加状态码**: 支持更细粒度的结果
   ```typescript
   export type CommandExecResizeResponse = {
     status: 'applied' | 'ignored' | 'deferred';
     message?: string;
   };
   ```

3. **添加时间戳**: 用于调试和同步
   ```typescript
   export type CommandExecResizeResponse = {
     processedAt: number;  // Unix时间戳
   };
   ```

### 使用示例

```typescript
async function resizePty(
  processId: string, 
  size: CommandExecTerminalSize
): Promise<void> {
  const params: CommandExecResizeParams = { processId, size };
  
  // 空响应表示成功
  const response: CommandExecResizeResponse = await rpc.call(
    'command/exec/resize', 
    params
  );
  
  // 无需处理响应数据
  console.log('PTY resized successfully');
}
```
