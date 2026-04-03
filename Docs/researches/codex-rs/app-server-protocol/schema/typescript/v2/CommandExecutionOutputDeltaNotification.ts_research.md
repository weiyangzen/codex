# CommandExecutionOutputDeltaNotification.ts 研究文档

## 场景与职责

`CommandExecutionOutputDeltaNotification.ts` 定义了命令执行输出增量通知类型（线程/对话上下文版本）。与`CommandExecOutputDeltaNotification`不同，此类型用于在对话线程中执行的命令，与特定的thread、turn和item关联。

## 功能点目的

1. **对话上下文输出**: 在thread/turn/item上下文中流式传输命令输出
2. **增量更新**: 支持增量式输出显示，减少延迟
3. **UI集成**: 与对话UI组件集成，在正确的消息位置显示输出

## 具体技术实现

### 数据结构

```typescript
export type CommandExecutionOutputDeltaNotification = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  delta: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `threadId` | `string` | 对话线程ID |
| `turnId` | `string` | 对话轮次ID |
| `itemId` | `string` | 消息项ID |
| `delta` | `string` | 输出增量内容 |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的对话执行模块

### 引用关系

**被引用方**:
- 对话消息渲染组件
- 命令输出处理器

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecutionOutputDeltaNotification.ts    # 本文件
├── CommandExecOutputDeltaNotification.ts         # 独立命令版本
└── ...
```

## 依赖与外部交互

### 与独立命令版本的区别

| 特性 | CommandExecOutputDeltaNotification | CommandExecutionOutputDeltaNotification |
|------|-----------------------------------|----------------------------------------|
| 上下文 | 独立执行（无thread） | 对话线程中 |
| 标识 | processId | threadId + turnId + itemId |
| 编码 | Base64 | 纯文本 |
| 用途 | 通用命令执行 | AI对话中的工具执行 |

### 使用场景

```
AI请求执行命令
        ↓
用户批准
        ↓
命令开始执行
        ↓
发送 CommandExecutionOutputDeltaNotification
        ↓
UI在对应item位置显示输出
        ↓
命令完成
        ↓
更新item状态
```

## 风险、边界与改进建议

### 潜在风险

1. **编码不一致**: 与独立版本使用不同编码（Base64 vs 纯文本）
2. **无流标识**: 不区分stdout/stderr
3. **无截断标记**: 无法得知输出是否被截断

### 改进建议

1. **统一编码**: 考虑统一使用Base64
   ```typescript
   export type CommandExecutionOutputDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     deltaBase64: string;  // 改为Base64
     stream: 'stdout' | 'stderr';  // 添加流标识
   };
   ```

2. **添加序列号**: 支持顺序验证
   ```typescript
   export type CommandExecutionOutputDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     delta: string;
     sequenceNumber: number;
   };
   ```

3. **添加完成标记**: 标识最后一块
   ```typescript
   export type CommandExecutionOutputDeltaNotification = { 
     threadId: string;
     turnId: string;
     itemId: string;
     delta: string;
     isFinal: boolean;
   };
   ```

### 使用示例

```typescript
// 处理对话命令输出
function handleExecutionOutput(
  notification: CommandExecutionOutputDeltaNotification
): void {
  const { threadId, turnId, itemId, delta } = notification;
  
  // 找到对应的UI组件
  const itemComponent = findItemComponent(threadId, turnId, itemId);
  
  // 追加输出
  itemComponent.appendOutput(delta);
}
```
