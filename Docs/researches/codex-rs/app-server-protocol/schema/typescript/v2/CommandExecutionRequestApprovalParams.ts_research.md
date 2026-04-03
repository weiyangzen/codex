# CommandExecutionRequestApprovalParams.ts 研究文档

## 场景与职责

`CommandExecutionRequestApprovalParams.ts` 定义了命令执行审批请求参数类型。当AI助手需要执行命令（如shell命令）时，向用户发送此请求以获取批准。这是Codex安全模型的核心组件，确保用户始终控制代码执行。

## 功能点目的

1. **执行审批**: 请求用户批准执行潜在危险的命令
2. **上下文提供**: 向用户展示命令详情和执行上下文
3. **决策选项**: 提供可用的决策选项供用户选择
4. **策略建议**: 提供策略修正建议简化未来类似请求
5. **技能元数据**: 支持技能脚本触发的审批场景

## 具体技术实现

### 数据结构

```typescript
export type CommandExecutionRequestApprovalParams = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  /**
   * Unique identifier for this specific approval callback.
   *
   * For regular shell/unified_exec approvals, this is null.
   *
   * For zsh-exec-bridge subcommand approvals, multiple callbacks can belong to
   * one parent `itemId`, so `approvalId` is a distinct opaque callback id
   * (a UUID) used to disambiguate routing.
   */
  approvalId?: string | null, 
  /**
   * Optional explanatory reason (e.g. request for network access).
   */
  reason?: string | null, 
  /**
   * Optional context for a managed-network approval prompt.
   */
  networkApprovalContext?: NetworkApprovalContext | null, 
  /**
   * The command to be executed.
   */
  command?: string | null, 
  /**
   * The command's working directory.
   */
  cwd?: string | null, 
  /**
   * Best-effort parsed command actions for friendly display.
   */
  commandActions?: Array<CommandAction> | null, 
  /**
   * Optional additional permissions requested for this command.
   */
  additionalPermissions?: AdditionalPermissionProfile | null, 
  /**
   * Optional skill metadata when the approval was triggered by a skill script.
   */
  skillMetadata?: CommandExecutionRequestApprovalSkillMetadata | null, 
  /**
   * Optional proposed execpolicy amendment to allow similar commands without prompting.
   */
  proposedExecpolicyAmendment?: ExecPolicyAmendment | null, 
  /**
   * Optional proposed network policy amendments (allow/deny host) for future requests.
   */
  proposedNetworkPolicyAmendments?: Array<NetworkPolicyAmendment> | null, 
  /**
   * Ordered list of decisions the client may present for this prompt.
   */
  availableDecisions?: Array<CommandExecutionApprovalDecision> | null, 
};
```

### 字段说明

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `threadId` | `string` | 必填 | 对话线程ID |
| `turnId` | `string` | 必填 | 对话轮次ID |
| `itemId` | `string` | 必填 | 消息项ID |
| `approvalId` | `string \| null` | 可选 | 审批回调唯一标识（zsh-exec-bridge场景） |
| `reason` | `string \| null` | 可选 | 审批原因说明 |
| `networkApprovalContext` | `NetworkApprovalContext \| null` | 可选 | 网络审批上下文 |
| `command` | `string \| null` | 可选 | 要执行的命令 |
| `cwd` | `string \| null` | 可选 | 工作目录 |
| `commandActions` | `CommandAction[] \| null` | 可选 | 解析后的命令动作 |
| `additionalPermissions` | `AdditionalPermissionProfile \| null` | 可选 | 额外权限请求 |
| `skillMetadata` | `CommandExecutionRequestApprovalSkillMetadata \| null` | 可选 | 技能脚本元数据 |
| `proposedExecpolicyAmendment` | `ExecPolicyAmendment \| null` | 可选 | 建议的执行策略修正 |
| `proposedNetworkPolicyAmendments` | `NetworkPolicyAmendment[] \| null` | 可选 | 建议的网络策略修正 |
| `availableDecisions` | `CommandExecutionApprovalDecision[] \| null` | 可选 | 可用决策列表 |

### 依赖类型

- `NetworkApprovalContext`: 网络审批上下文
- `CommandAction`: 命令动作解析
- `AdditionalPermissionProfile`: 额外权限配置
- `CommandExecutionRequestApprovalSkillMetadata`: 技能元数据
- `ExecPolicyAmendment`: 执行策略修正
- `NetworkPolicyAmendment`: 网络策略修正
- `CommandExecutionApprovalDecision`: 可用决策

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的命令执行审批模块

### 引用关系

**被引用方**:
- 审批请求处理器
- 审批UI组件

**引用**:
- `./NetworkApprovalContext`
- `./CommandAction`
- `./AdditionalPermissionProfile`
- `./CommandExecutionRequestApprovalSkillMetadata`
- `./ExecPolicyAmendment`
- `./NetworkPolicyAmendment`
- `./CommandExecutionApprovalDecision`

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecutionRequestApprovalParams.ts       # 本文件
├── CommandExecutionRequestApprovalResponse.ts     # 审批响应
├── CommandExecutionApprovalDecision.ts            # 决策类型
└── ...
```

## 依赖与外部交互

### 审批流程

```
AI决定执行命令
        ↓
构建审批请求参数
        ↓
发送审批请求通知
        ↓
显示审批UI
        ↓
用户审阅信息
        ↓
┌───────┬───────┬───────┐
↓       ↓       ↓       ↓
接受   拒绝   取消   策略修正
        ↓
发送审批响应
        ↓
执行或取消命令
```

### UI展示信息

```
┌─────────────────────────────────────┐
│ 命令执行请求                          │
├─────────────────────────────────────┤
│ 命令: npm install                    │
│ 目录: /project                       │
│                                     │
│ 操作:                               │
│   • 执行: npm install                │
│                                     │
│ 原因: 需要安装依赖                    │
│                                     │
│ [接受] [本次会话接受] [拒绝] [取消]   │
│                                     │
│ ☑ 记住此类型的命令                   │
└─────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **信息过载**: 字段过多可能导致UI复杂
2. **策略误导**: 自动建议的策略修正可能不安全
3. **权限升级**: additionalPermissions可能被滥用

### 边界情况

1. **空命令**: command为null时的处理
2. **无效决策**: availableDecisions包含无效选项
3. **过期请求**: 长时间未响应的审批请求

### 改进建议

1. **添加紧急程度**: 标识请求的紧急程度
   ```typescript
   export type CommandExecutionRequestApprovalParams = {
     // ...现有字段
     urgency?: 'low' | 'normal' | 'high';
   };
   ```

2. **添加超时**: 审批请求的有效期
   ```typescript
   export type CommandExecutionRequestApprovalParams = {
     // ...现有字段
     expiresAt?: number;  // 过期时间戳
   };
   ```

3. **添加风险评分**: 帮助用户理解风险
   ```typescript
   export type CommandExecutionRequestApprovalParams = {
     // ...现有字段
     riskScore?: number;  // 0-100
     riskFactors?: string[];
   };
   ```

4. **添加替代方案**: 提供不执行命令的替代选择
   ```typescript
   export type CommandExecutionRequestApprovalParams = {
     // ...现有字段
     alternatives?: Array<{
       description: string;
       action: string;
     }>;
   };
   ```

### 使用示例

```typescript
// 处理审批请求
function handleApprovalRequest(
  params: CommandExecutionRequestApprovalParams
): void {
  const {
    threadId,
    turnId,
    itemId,
    command,
    cwd,
    commandActions,
    reason,
    availableDecisions
  } = params;
  
  // 显示审批对话框
  showApprovalDialog({
    title: '命令执行请求',
    command: command || 'Unknown',
    directory: cwd || 'Current',
    actions: commandActions,
    reason: reason,
    decisions: availableDecisions || ['accept', 'decline', 'cancel'],
    onDecision: (decision) => {
      sendApprovalResponse(threadId, turnId, itemId, decision);
    }
  });
}

// 发送审批响应
async function sendApprovalResponse(
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
