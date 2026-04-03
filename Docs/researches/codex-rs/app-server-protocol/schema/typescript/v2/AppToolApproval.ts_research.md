# AppToolApproval 类型研究文档

## 1. 场景与职责

### 1.1 使用场景

`AppToolApproval` 是 Codex App-Server Protocol v2 中用于定义应用工具审批模式的枚举类型。它主要用于：

- **应用工具权限控制**：控制应用内各个工具的审批行为
- **安全策略配置**：定义工具调用的安全级别
- **用户交互控制**：决定工具调用时是否需要用户确认
- **自动化流程**：支持自动批准或提示批准的灵活配置

### 1.2 核心职责

- 定义工具调用的三种审批模式
- 作为 `AppToolConfig` 和 `AppToolsConfig` 的字段类型
- 支持应用级别的默认工具审批策略
- 支持工具级别的精细化审批控制

### 1.3 审批模式对比

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| `auto` | 自动批准，无需用户确认 | 可信应用、低风险操作 |
| `prompt` | 提示用户确认 | 中等风险、需要用户知情 |
| `approve` | 需要显式批准（可能包含 Guardian Subagent） | 高风险操作、安全敏感场景 |

---

## 2. 功能点目的

### 2.1 枚举值说明

| 值 | 含义 | 详细行为 |
|----|------|----------|
| `"auto"` | 自动模式 | 工具调用自动执行，不提示用户 |
| `"prompt"` | 提示模式 | 工具调用前显示确认对话框 |
| `"approve"` | 批准模式 | 需要显式批准，可能由用户或 Guardian Subagent 审批 |

### 2.2 设计意图

1. **安全分级**：三种模式对应不同的安全级别，从完全自动到严格审批
2. **灵活性**：支持全局默认和按工具覆盖的配置方式
3. **与 Guardian 集成**：`approve` 模式可与 `ApprovalsReviewer` 配合，支持 AI 辅助审批

### 2.3 配置层级

```
AppsConfig
  └── _default: AppsDefaultConfig
        └── default_tools_approval_mode: AppToolApproval
  └── apps: Record<string, AppConfig>
        └── default_tools_approval_mode: AppToolApproval
        └── tools: AppToolsConfig
              └── [toolName]: AppToolConfig
                    └── approval_mode: AppToolApproval
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义

```typescript
export type AppToolApproval = "auto" | "prompt" | "approve";
```

### 3.2 Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub enum AppToolApproval {
    Auto,
    Prompt,
    Approve,
}
```

### 3.3 序列化规则

- 使用 `#[serde(rename_all = "snake_case")]` 序列化为 `"auto"`、`"prompt"`、`"approve"`
- TypeScript 中使用字符串字面量联合类型
- 在 config.toml 中使用 snake_case 格式

### 3.4 配置示例

```toml
# config.toml
[apps.my_app]
enabled = true
default_tools_approval_mode = "prompt"

[apps.my_app.tools.file_read]
enabled = true
approval_mode = "auto"  # 覆盖默认值

[apps.my_app.tools.file_write]
enabled = true
approval_mode = "approve"  # 更严格的审批
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义（约第 621-628 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AppToolApproval.ts` | 生成的 TypeScript 类型 |

### 4.2 引用关系

```
AppToolApproval
  ├── AppToolConfig.approval_mode
  ├── AppConfig.default_tools_approval_mode
  └── AppsDefaultConfig.default_tools_approval_mode
```

### 4.3 相关类型

| 类型 | 关系 |
|------|------|
| `AppToolConfig` | 包含 `approval_mode: AppToolApproval \| null` |
| `AppToolsConfig` | 包含工具名称到 `AppToolConfig` 的映射 |
| `AppConfig` | 包含 `default_tools_approval_mode: AppToolApproval \| null` |
| `AppsDefaultConfig` | 包含 `default_tools_approval_mode: AppToolApproval` |

---

## 5. 依赖与外部交互

### 5.1 导入依赖

`AppToolApproval.ts` 无直接导入，是独立的枚举类型。

### 5.2 外部协议依赖

- **serde**：序列化/反序列化，使用 snake_case
- **schemars**：JSON Schema 生成
- **ts-rs**：TypeScript 类型生成

### 5.3 与 ApprovalsReviewer 的关系

```typescript
// 当 approval_mode 为 "approve" 时，由 ApprovalsReviewer 决定审批者
type ApprovalsReviewer = "user" | "guardian_subagent";

// 配置示例
interface ApprovalConfig {
  approval_mode: "approve";
  approvals_reviewer: ApprovalsReviewer;  // 谁来进行审批
}
```

### 5.4 客户端使用示例

```typescript
import type { AppToolApproval } from "./AppToolApproval";
import type { AppToolConfig } from "./AppToolsConfig";

// 审批模式常量
const ApprovalMode = {
  AUTO: 'auto',
  PROMPT: 'prompt',
  APPROVE: 'approve',
} as const satisfies Record<string, AppToolApproval>;

// 获取工具审批模式（带默认值）
function getToolApprovalMode(
  toolConfig: AppToolConfig | undefined,
  appDefault: AppToolApproval,
  globalDefault: AppToolApproval = 'prompt'
): AppToolApproval {
  return toolConfig?.approval_mode ?? appDefault ?? globalDefault;
}

// 检查是否需要用户确认
function requiresPrompt(mode: AppToolApproval): boolean {
  return mode === 'prompt' || mode === 'approve';
}

// 检查是否可以自动执行
function canAutoExecute(mode: AppToolApproval): boolean {
  return mode === 'auto';
}

// 执行工具前的审批检查
async function executeToolWithApproval(
  toolName: string,
  approvalMode: AppToolApproval,
  execute: () => Promise<void>
): Promise<void> {
  switch (approvalMode) {
    case 'auto':
      // 直接执行
      await execute();
      break;
      
    case 'prompt':
      // 显示确认对话框
      const confirmed = await showConfirmDialog(`Execute ${toolName}?`);
      if (confirmed) {
        await execute();
      }
      break;
      
    case 'approve':
      // 提交审批请求
      const approved = await submitApprovalRequest(toolName);
      if (approved) {
        await execute();
      }
      break;
  }
}

// UI 组件：审批模式选择器
function ApprovalModeSelector({
  value,
  onChange,
}: {
  value: AppToolApproval;
  onChange: (mode: AppToolApproval) => void;
}) {
  const options: { value: AppToolApproval; label: string; description: string }[] = [
    { 
      value: 'auto', 
      label: 'Auto', 
      description: 'Execute without confirmation' 
    },
    { 
      value: 'prompt', 
      label: 'Prompt', 
      description: 'Ask for confirmation before executing' 
    },
    { 
      value: 'approve', 
      label: 'Approve', 
      description: 'Require explicit approval' 
    },
  ];
  
  return (
    <select value={value} onChange={(e) => onChange(e.target.value as AppToolApproval)}>
      {options.map(opt => (
        <option key={opt.value} value={opt.value}>
          {opt.label} - {opt.description}
        </option>
      ))}
    </select>
  );
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **权限提升** | `auto` 模式可能被恶意利用 | 仅对可信应用启用 auto |
| **配置继承复杂** | 多层默认值可能导致意外行为 | 清晰的配置文档和验证 |
| **与 Guardian 冲突** | `approve` + `guardian_subagent` 可能延迟响应 | 设置超时和 fallback |

### 6.2 边界情况

1. **null 值处理**：`AppToolConfig.approval_mode` 可能为 null，表示使用默认值
2. **无效值**：服务端可能接受未知值，客户端应做好防护
3. **大小写敏感**：`"Auto"` 和 `"auto"` 不同

### 6.3 改进建议

1. **添加更多模式**：
   ```typescript
   type AppToolApproval = 
     | "auto"
     | "prompt"
     | "approve"
     | "deny"           // 明确拒绝
     | "review_once";   // 首次审批，后续自动
   ```

2. **条件审批**：
   ```typescript
   interface ConditionalApproval {
     mode: "conditional";
     rules: {
       condition: "high_risk" | "data_exfiltration" | "network_access";
       action: AppToolApproval;
     }[];
   }
   ```

3. **时间限制**：
   ```typescript
   interface TimeBoundApproval {
     mode: "approve";
     expiresAfterMinutes?: number;  // 审批有效期
   }
   ```

4. **审计日志集成**：
   ```typescript
   interface AuditConfig {
     mode: AppToolApproval;
     auditLog: boolean;  // 是否记录审计日志
   }
   ```

### 6.4 安全配置最佳实践

```typescript
// 安全配置检查
function validateSecurityConfig(
  appName: string,
  approvalMode: AppToolApproval,
  toolRiskLevel: 'low' | 'medium' | 'high'
): string[] {
  const warnings: string[] = [];
  
  if (approvalMode === 'auto' && toolRiskLevel === 'high') {
    warnings.push(
      `High-risk tool ${appName} is set to auto-approve. ` +
      `Consider using 'prompt' or 'approve' mode.`
    );
  }
  
  return warnings;
}

// 推荐配置
const recommendedConfig: Record<string, AppToolApproval> = {
  'file_read': 'auto',
  'file_write': 'prompt',
  'shell': 'approve',
  'network': 'approve',
};
```

### 6.5 与 ApprovalsReviewer 的协作

```typescript
// 完整的审批流程
async function handleToolExecution(
  toolName: string,
  config: {
    approvalMode: AppToolApproval;
    approvalsReviewer: ApprovalsReviewer;
  }
): Promise<boolean> {
  if (config.approvalMode === 'auto') {
    return true;
  }
  
  if (config.approvalMode === 'prompt') {
    return await showUserPrompt(toolName);
  }
  
  if (config.approvalMode === 'approve') {
    if (config.approvalsReviewer === 'guardian_subagent') {
      return await requestGuardianApproval(toolName);
    } else {
      return await showUserPrompt(toolName);
    }
  }
  
  return false;
}
```
