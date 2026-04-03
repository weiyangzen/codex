# CommandExecutionRequestApprovalResponse.ts 研究文档

## 场景与职责

`CommandExecutionRequestApprovalResponse.ts` 定义了命令执行审批响应类型。用户在审阅命令执行请求后，使用此类型发送决策回服务器。

## 功能点目的

1. **决策传递**: 将用户的审批决策传递给服务器
2. **执行控制**: 根据决策决定是否执行命令
3. **策略应用**: 传递包含策略修正的复杂决策

## 具体技术实现

### 数据结构

```typescript
export type CommandExecutionRequestApprovalResponse = { 
  decision: CommandExecutionApprovalDecision, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `decision` | `CommandExecutionApprovalDecision` | 用户的审批决策 |

### 依赖类型

- `CommandExecutionApprovalDecision`: 决策类型，包含多种决策变体

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行审批模块

### 引用关系

**被引用方**:
- 审批响应处理器

**引用**:
- `./CommandExecutionApprovalDecision` - 决策类型

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecutionRequestApprovalResponse.ts       # 本文件
├── CommandExecutionRequestApprovalParams.ts         # 审批请求
├── CommandExecutionApprovalDecision.ts              # 决策类型
└── ...
```

## 依赖与外部交互

### 响应流程

```
用户做出决策
        ↓
构建审批响应
        ↓
发送响应到服务器
        ↓
服务器处理决策
        ↓
┌───────┬───────┬───────┐
↓       ↓       ↓       ↓
接受   拒绝   取消   策略修正
        ↓
执行或取消
```

## 风险、边界与改进建议

### 潜在风险

1. **决策篡改**: 响应可能被拦截和修改
2. **重放攻击**: 响应可能被重放
3. **时序问题**: 响应可能在请求过期后到达

### 改进建议

1. **添加时间戳**: 防止重放攻击
   ```typescript
   export type CommandExecutionRequestApprovalResponse = {
     decision: CommandExecutionApprovalDecision;
     timestamp: number;
   };
   ```

2. **添加请求引用**: 明确关联到请求
   ```typescript
   export type CommandExecutionRequestApprovalResponse = {
     decision: CommandExecutionApprovalDecision;
     requestId: string;  // 对应请求的ID
   };
   ```

3. **添加用户身份**: 明确决策者
   ```typescript
   export type CommandExecutionRequestApprovalResponse = {
     decision: CommandExecutionApprovalDecision;
     userId?: string;
   };
   ```

### 使用示例

```typescript
// 发送接受决策
const acceptResponse: CommandExecutionRequestApprovalResponse = {
  decision: 'accept'
};

// 发送带策略修正的决策
const policyResponse: CommandExecutionRequestApprovalResponse = {
  decision: {
    acceptWithExecpolicyAmendment: {
      execpolicy_amendment: ['allow:write:/tmp']
    }
  }
};

// 发送响应
async function sendApprovalResponse(
  threadId: string,
  turnId: string,
  itemId: string,
  response: CommandExecutionRequestApprovalResponse
): Promise<void> {
  await rpc.call('commandExecution/requestApproval/response', {
    threadId,
    turnId,
    itemId,
    ...response
  });
}
```
