# CommandExecutionApprovalDecision.ts 研究文档

## 场景与职责

`CommandExecutionApprovalDecision.ts` 定义了命令执行审批决策类型，表示用户对命令执行请求的可能决策选项。这是命令执行安全审批流程的核心类型，支持多种决策变体，包括简单的接受/拒绝以及带策略修正的决策。

## 功能点目的

1. **审批决策建模**: 定义用户可以对命令执行请求做出的所有决策
2. **策略修正**: 支持通过决策修改执行策略（如放宽沙箱限制）
3. **网络策略**: 支持通过决策添加网络访问规则
4. **会话记忆**: 支持"本次会话接受"等记忆选项

## 具体技术实现

### 数据结构

```typescript
export type CommandExecutionApprovalDecision = 
  | "accept" 
  | "acceptForSession" 
  | { "acceptWithExecpolicyAmendment": { execpolicy_amendment: ExecPolicyAmendment } } 
  | { "applyNetworkPolicyAmendment": { network_policy_amendment: NetworkPolicyAmendment } } 
  | "decline" 
  | "cancel";
```

### 变体说明

| 决策 | 类型 | 说明 |
|------|------|------|
| `"accept"` | 字符串 | 接受本次执行 |
| `"acceptForSession"` | 字符串 | 接受本次执行，并在本次会话中记住此决定 |
| `acceptWithExecpolicyAmendment` | 对象 | 接受并添加执行策略修正 |
| `applyNetworkPolicyAmendment` | 对象 | 应用网络策略修正 |
| `"decline"` | 字符串 | 拒绝执行 |
| `"cancel"` | 字符串 | 取消审批流程 |

### 依赖类型

- `ExecPolicyAmendment`: 执行策略修正类型
- `NetworkPolicyAmendment`: 网络策略修正类型

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行审批模块

### 引用关系

**被引用方**:
- `CommandExecutionRequestApprovalResponse.ts` - 作为响应的`decision`字段
- `CommandExecutionRequestApprovalParams.ts` - 作为`availableDecisions`的元素

**引用**:
- `./ExecPolicyAmendment` - 执行策略修正
- `./NetworkPolicyAmendment` - 网络策略修正

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecutionApprovalDecision.ts       # 本文件
├── CommandExecutionRequestApprovalResponse.ts # 使用此类型
├── CommandExecutionRequestApprovalParams.ts   # 使用此类型
├── ExecPolicyAmendment.ts                     # 执行策略修正
├── NetworkPolicyAmendment.ts                  # 网络策略修正
└── ...
```

## 依赖与外部交互

### 决策流程

```
收到审批请求
        ↓
显示命令详情
        ↓
用户选择决策
        ↓
┌───────┬───────┬───────┬───────┬───────┐
↓       ↓       ↓       ↓       ↓       ↓
accept  accept  accept  apply   decline cancel
        For     With    Network
        Session Policy  Policy
        ↓       ↓       ↓
    执行命令  执行+    执行+
    记住决策  策略修正 网络规则
```

### 策略修正示例

```typescript
// 接受并放宽执行策略
const decision: CommandExecutionApprovalDecision = {
  acceptWithExecpolicyAmendment: {
    execpolicy_amendment: [
      "allow:read:/tmp",
      "allow:write:/tmp"
    ]
  }
};

// 接受并添加网络规则
const decision: CommandExecutionApprovalDecision = {
  applyNetworkPolicyAmendment: {
    network_policy_amendment: {
      host: "api.example.com",
      action: "allow"
    }
  }
};
```

## 风险、边界与改进建议

### 潜在风险

1. **策略升级**: `acceptWithExecpolicyAmendment`可能被滥用提升权限
2. **网络暴露**: `applyNetworkPolicyAmendment`可能意外开放网络访问
3. **记忆持久性**: `acceptForSession`的范围可能不明确

### 边界情况

1. **无效修正**: 服务器可能拒绝无效的策略修正
2. **冲突规则**: 多个修正可能产生冲突
3. **过期策略**: 会话结束后策略修正应失效

### 改进建议

1. **添加理由**: 要求为策略修正提供理由
   ```typescript
   export type CommandExecutionApprovalDecision = 
     | ...
     | { "acceptWithExecpolicyAmendment": { 
         execpolicy_amendment: ExecPolicyAmendment;
         reason?: string;  // 新增
       } } 
     | ...;
   ```

2. **时间限制**: 为策略修正添加有效期
   ```typescript
   export type CommandExecutionApprovalDecision = 
     | ...
     | { "acceptWithExecpolicyAmendment": { 
         execpolicy_amendment: ExecPolicyAmendment;
         expiresAt?: number;  // 新增：过期时间戳
       } } 
     | ...;
   ```

3. **撤销支持**: 支持撤销之前的决策
   ```typescript
   export type CommandExecutionApprovalDecision = 
     | ...
     | "revokeSessionAcceptance";  // 新增
   ```

4. **条件接受**: 支持带条件的接受
   ```typescript
   export type CommandExecutionApprovalDecision = 
     | ...
     | { "acceptWithConditions": {
         maxExecutionTimeMs: number;
         maxOutputBytes: number;
       }}
     | ...;
   ```

### 使用示例

```typescript
// 简单接受
const acceptDecision: CommandExecutionApprovalDecision = "accept";

// 会话记忆
const sessionDecision: CommandExecutionApprovalDecision = "acceptForSession";

// 拒绝
const declineDecision: CommandExecutionApprovalDecision = "decline";

// 带执行策略修正
const policyDecision: CommandExecutionApprovalDecision = {
  acceptWithExecpolicyAmendment: {
    execpolicy_amendment: ["allow:write:/project/build"]
  }
};

// 带网络策略
const networkDecision: CommandExecutionApprovalDecision = {
  applyNetworkPolicyAmendment: {
    network_policy_amendment: {
      host: "npm.registry.org",
      action: "allow"
    }
  }
};

// 发送审批响应
async function sendApproval(
  threadId: string,
  turnId: string,
  itemId: string,
  decision: CommandExecutionApprovalDecision
): Promise<void> {
  const response: CommandExecutionRequestApprovalResponse = { decision };
  await rpc.call('commandExecution/requestApproval/response', {
    threadId,
    turnId,
    itemId,
    ...response
  });
}
```
