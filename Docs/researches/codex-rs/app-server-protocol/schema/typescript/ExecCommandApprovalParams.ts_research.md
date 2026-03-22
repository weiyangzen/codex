# ExecCommandApprovalParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ExecCommandApprovalParams` 是 Codex 应用服务器协议中用于**命令执行审批请求**的参数类型。当 Agent 需要执行一个 shell 命令时，如果该命令需要用户审批（基于 `AskForApproval` 策略），服务器会向客户端发送一个审批请求，携带此参数结构。

**典型使用场景：**
- Agent 执行 `shell` 或 `container.exec` 工具调用时
- 命令匹配了 execpolicy 的 `prompt` 规则
- Skill 脚本执行需要审批时
- 命令需要额外的权限（如沙箱逃逸或网络访问）

**职责：**
- 提供命令执行的完整上下文信息
- 允许客户端关联相关的开始/结束事件（通过 `callId`）
- 支持子命令审批（通过 `approvalId`）
- 提供命令解析信息（`parsedCmd`）帮助客户端理解命令意图

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **审批上下文传递**：向客户端提供足够的信息以做出明智的审批决策
2. **事件关联**：通过 `callId` 关联 `ExecCommandBeginEvent` 和 `ExecCommandEndEvent`
3. **子命令支持**：通过 `approvalId` 支持 execve 拦截场景下的子命令审批
4. **命令解析**：通过 `parsedCmd` 提供结构化的命令分析，帮助 UI 展示命令意图

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type ExecCommandApprovalParams = { 
  conversationId: ThreadId, 
  /**
   * Use to correlate this with [codex_protocol::protocol::ExecCommandBeginEvent]
   * and [codex_protocol::protocol::ExecCommandEndEvent].
   */
  callId: string, 
  /**
   * Identifier for this specific approval callback.
   */
  approvalId: string | null, 
  command: Array<string>, 
  cwd: string, 
  reason: string | null, 
  parsedCmd: Array<ParsedCommand>, 
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ExecCommandApprovalParams {
    pub conversation_id: ThreadId,
    /// Use to correlate this with [codex_protocol::protocol::ExecCommandBeginEvent]
    /// and [codex_protocol::protocol::ExecCommandEndEvent].
    pub call_id: String,
    /// Identifier for this specific approval callback.
    pub approval_id: Option<String>,
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub reason: Option<String>,
    pub parsed_cmd: Vec<ParsedCommand>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `conversationId` | `ThreadId` | 关联的对话/线程 ID |
| `callId` | `string` | 命令调用的唯一标识，用于关联生命周期事件 |
| `approvalId` | `string \| null` | 子命令审批的唯一标识（execve 拦截场景） |
| `command` | `string[]` | 命令参数数组（argv 格式） |
| `cwd` | `string` | 命令执行的工作目录 |
| `reason` | `string \| null` | 可选的审批原因说明 |
| `parsedCmd` | `ParsedCommand[]` | 命令解析结果数组 |

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ExecCommandApprovalParams.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 143-156)

### 相关事件类型
- `ExecCommandBeginEvent` - 命令开始执行事件
- `ExecCommandEndEvent` - 命令执行结束事件
- `ExecApprovalRequestEvent` - 审批请求事件（protocol crate）

### 使用位置
- `ServerRequest::ExecCommandApproval` - 服务器向客户端发送的审批请求
- 定义在 `common.rs` 的 `server_request_definitions!` 宏中

### 依赖类型
- `ThreadId` - 线程/对话标识符
- `ParsedCommand` - 解析后的命令结构

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖类型
```typescript
import type { ParsedCommand } from "./ParsedCommand";
import type { ThreadId } from "./ThreadId";
```

### 响应类型
客户端使用 `ExecCommandApprovalResponse` 回复审批决策：
```typescript
export type ExecCommandApprovalResponse = { 
  decision: ReviewDecision, 
};
```

### 协议集成
- 属于 **v1 API**（已标记为 DEPRECATED，推荐使用 v2 的 `CommandExecutionRequestApproval`）
- 通过 JSON-RPC 协议传输
- 使用 camelCase 序列化

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：该类型属于 v1 API，已被标记为 DEPRECATED，新代码应使用 v2 API
   - v2 替代：`CommandExecutionRequestApprovalParams`

2. **approvalId 为空**：当 `approvalId` 为 `null` 时，表示审批针对主命令本身（`call_id`）

3. **parsedCmd 解析限制**：`ParsedCommand` 的解析是"尽力而为"（best effort），可能无法识别所有命令类型

4. **命令数组格式**：`command` 是 argv 格式的数组，第一个元素是可执行文件路径

### 改进建议

1. **迁移到 v2 API**：新客户端应实现 v2 的 `CommandExecutionRequestApproval` 替代此类型

2. **增强命令解析**：考虑扩展 `ParsedCommand` 的类型覆盖范围

3. **添加安全元数据**：可考虑添加命令的风险评估信息（如 Guardian 风险评分）

4. **统一审批体验**：v1 和 v2 的审批流程存在差异，建议客户端统一处理逻辑

### 测试建议
- 验证 `callId` 与生命周期事件的正确关联
- 测试子命令审批场景（`approvalId` 非空）
- 验证 `parsedCmd` 对各种命令格式的解析
