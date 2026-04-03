# CommandExecutionRequestApprovalSkillMetadata.ts 研究文档

## 场景与职责

`CommandExecutionRequestApprovalSkillMetadata.ts` 定义了当命令执行审批由技能脚本触发时的元数据类型。这允许系统区分普通AI触发的命令和特定技能触发的命令，并提供技能相关的上下文信息。

## 功能点目的

1. **技能识别**: 标识触发命令的技能
2. **上下文提供**: 提供技能相关的路径信息
3. **审计追踪**: 支持技能执行的安全审计
4. **UI展示**: 在审批UI中显示技能来源

## 具体技术实现

### 数据结构

```typescript
export type CommandExecutionRequestApprovalSkillMetadata = { 
  pathToSkillsMd: string, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `pathToSkillsMd` | `string` | 技能SKILL.md文件的路径 |

## 关键代码路径与文件引用

### 生成源

- `codex-rs/app-server-protocol/src/protocol/v2.rs` 中的技能执行模块

### 引用关系

**被引用方**:
- `CommandExecutionRequestApprovalParams.ts` - 作为`skillMetadata`字段类型

**引用**: 无

### 相关文件

```
codex-rs/app-server-protocol/schema/typescript/v2/
├── CommandExecutionRequestApprovalSkillMetadata.ts    # 本文件
├── CommandExecutionRequestApprovalParams.ts           # 使用此类型
└── ...
```

## 依赖与外部交互

### 使用场景

```
技能脚本执行
        ↓
需要执行命令
        ↓
触发审批请求
        ↓
包含 skillMetadata
        ↓
UI显示技能来源
        ↓
用户了解上下文
        ↓
做出决策
```

### UI展示示例

```
┌─────────────────────────────────────┐
│ 命令执行请求                          │
├─────────────────────────────────────┤
│ 来源: 技能脚本                        │
│ 技能: /skills/deploy/SKILL.md        │
│                                     │
│ 命令: ./deploy.sh production         │
│                                     │
│ [接受] [拒绝]                        │
└─────────────────────────────────────┘
```

## 风险、边界与改进建议

### 潜在风险

1. **路径伪造**: 恶意技能可能伪造路径
2. **信息不足**: 仅有路径可能不足以完全识别技能
3. **路径变更**: 技能移动后路径失效

### 改进建议

1. **添加技能ID**: 使用唯一标识符
   ```typescript
   export type CommandExecutionRequestApprovalSkillMetadata = {
     pathToSkillsMd: string;
     skillId: string;        // 唯一技能ID
     skillVersion: string;   // 技能版本
   };
   ```

2. **添加技能名称**: 提供人类可读的名称
   ```typescript
   export type CommandExecutionRequestApprovalSkillMetadata = {
     pathToSkillsMd: string;
     skillName: string;      // 显示名称
   };
   ```

3. **添加执行上下文**: 提供更多执行信息
   ```typescript
   export type CommandExecutionRequestApprovalSkillMetadata = {
     pathToSkillsMd: string;
     executionContext?: {
       triggeredBy: 'user' | 'auto' | 'hook';
       triggerReason?: string;
     };
   };
   ```

### 使用示例

```typescript
// 在审批UI中显示技能信息
function renderSkillMetadata(
  metadata: CommandExecutionRequestApprovalSkillMetadata | null
): string {
  if (!metadata) {
    return '来源: AI助手';
  }
  
  return `来源: 技能脚本\n路径: ${metadata.pathToSkillsMd}`;
}
```
