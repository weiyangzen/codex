# ApprovalsReviewer.ts 研究文档

## 1. 场景与职责 (Usage Scenarios and Responsibilities)

### 场景
`ApprovalsReviewer` 是 Codex App Server Protocol v2 API 中的关键配置类型，用于控制审批请求的审查路由目标。它主要应用于以下安全敏感场景：

- **沙箱逃逸检测**：当代理尝试执行可能突破沙箱限制的操作时
- **网络访问拦截**：当代理尝试访问被阻止的网络资源时
- **MCP 审批提示**：当 Model Context Protocol 服务器需要用户确认时
- **ARC (Agent Risk Control) 升级**：当操作风险等级需要人工介入时
- **命令执行审批**：当执行潜在危险的系统命令时

### 职责
- 定义审批请求的路由目标（用户或 Guardian Subagent）
- 支持基于风险的自动化审批决策
- 作为配置系统的一部分，允许在 profile 级别或全局级别设置

## 2. 功能点目的 (Purpose of the Functionality)

### 核心功能
`ApprovalsReviewer` 提供了两种审批路由模式：

1. **用户审批 (`"user"`)**
   - 默认行为
   - 审批请求直接发送给终端用户
   - 用户通过 UI 界面进行手动确认或拒绝

2. **Guardian Subagent 审批 (`"guardian_subagent"`)**
   - 使用经过精心提示的子代理进行风险评估
   - 自动收集相关上下文信息
   - 应用基于风险的决策框架进行自动审批或拒绝
   - 减少用户打断，提高自动化程度

### 设计目标
- **安全性**：确保高风险操作得到适当审查
- **用户体验**：减少不必要的人工干预
- **可配置性**：允许根据场景选择不同的审批策略
- **自动化**：通过 AI 辅助的风险评估提高处理效率

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 类型定义
```typescript
/**
 * Configures who approval requests are routed to for review. Examples
 * include sandbox escapes, blocked network access, MCP approval prompts, and
 * ARC escalations. Defaults to `user`. `guardian_subagent` uses a carefully
 * prompted subagent to gather relevant context and apply a risk-based
 * decision framework before approving or denying the request.
 */
export type ApprovalsReviewer = "user" | "guardian_subagent";
```

### 技术特性
1. **字符串字面量联合类型**：使用 TypeScript 的联合类型确保类型安全
2. **详细 JSDoc 注释**：包含使用场景和默认值说明
3. **camelCase 序列化**：在 API 传输中使用 camelCase 格式

### Rust 源实现
在 Rust 代码中对应的定义为：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(rename_all = "snake_case", export_to = "v2/")]
/// Configures who approval requests are routed to for review. Examples
/// include sandbox escapes, blocked network access, MCP approval prompts, and
/// ARC escalations. Defaults to `user`. `guardian_subagent` uses a carefully
/// prompted subagent to gather relevant context and apply a risk-based
/// decision framework before approving or denying the request.
pub enum ApprovalsReviewer {
    User,
    GuardianSubagent,
}
```

### 核心协议映射
```rust
impl ApprovalsReviewer {
    pub fn to_core(self) -> CoreApprovalsReviewer {
        match self {
            ApprovalsReviewer::User => CoreApprovalsReviewer::User,
            ApprovalsReviewer::GuardianSubagent => CoreApprovalsReviewer::GuardianSubagent,
        }
    }
}

impl From<CoreApprovalsReviewer> for ApprovalsReviewer {
    fn from(value: CoreApprovalsReviewer) -> Self {
        match value {
            CoreApprovalsReviewer::User => ApprovalsReviewer::User,
            CoreApprovalsReviewer::GuardianSubagent => ApprovalsReviewer::GuardianSubagent,
        }
    }
}
```

### 代码生成
- 使用 `ts-rs` crate 从 Rust 枚举自动生成 TypeScript 类型
- 生成文件路径：`codex-rs/app-server-protocol/schema/typescript/v2/ApprovalsReviewer.ts`
- 保留 Rust 中的文档注释作为 TypeScript JSDoc

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 源文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 267-296) | Rust 源定义 `ApprovalsReviewer` 枚举及转换实现 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (line 16) | 导入 `CoreApprovalsReviewer` |

### 生成的 TypeScript 文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ApprovalsReviewer.ts` | 主类型定义文件 |
| `codex-rs/app-server-protocol/schema/typescript/v2/index.ts` | 模块导出索引 |

### JSON Schema
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | JSON Schema 定义 |

### 使用位置
- `Config.ts`: 作为全局默认 `approvals_reviewer` 字段
- `ProfileV2.ts`: 作为 profile 级别的 `approvals_reviewer` 字段
- 标记为实验性功能：`#[experimental("config/read.approvalsReviewer")]`

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 核心协议依赖
```rust
use codex_protocol::config_types::ApprovalsReviewer as CoreApprovalsReviewer;
```

### 被依赖方
- `Config.ts`: 全局配置中的 `approvals_reviewer` 字段
- `ProfileV2.ts`: Profile 配置中的 `approvals_reviewer` 字段
- `index.ts`: 统一导出模块

### 外部交互
1. **审批系统**：与 `AskForApproval` 配置协同工作
2. **Guardian Subagent**：当设置为 `"guardian_subagent"` 时，触发子代理风险评估流程
3. **用户界面**：当设置为 `"user"` 时，在客户端显示审批对话框

### 配置层级
```rust
pub struct Config {
    // ...
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    // ...
}

pub struct ProfileV2 {
    // ...
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    // ...
}
```

### API 使用场景
```typescript
// 示例：配置使用 Guardian Subagent 进行自动审批
const config: Config = {
  approvals_reviewer: "guardian_subagent",
  // ...
};

// 示例：配置使用用户审批（默认行为）
const config: Config = {
  approvals_reviewer: "user",
  // ...
};
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **Guardian Subagent 误判风险**
   - 风险：自动化风险评估可能产生误判，导致安全风险或用户体验问题
   - 缓解：提供审计日志，允许事后审查；设置置信度阈值

2. **实验性功能稳定性**
   - 风险：标记为实验性功能，API 可能在未来版本中变更
   - 缓解：客户端应做好向后兼容处理

3. **配置继承复杂性**
   - 风险：Profile 级别和全局级别的配置可能产生冲突
   - 缓解：明确配置优先级规则（profile > global > default）

### 边界情况

1. **未配置情况**：当 `approvals_reviewer` 为 `null` 或未设置时，默认使用 `"user"`
2. **无效值处理**：API 应拒绝非 `"user"` 或 `"guardian_subagent"` 的值
3. **运行时变更**：配置变更后的生效时机（立即生效 vs 下次操作时生效）

### 改进建议

1. **扩展审批模式**
   ```typescript
   export type ApprovalsReviewer = 
     | "user" 
     | "guardian_subagent"
     | "auto_allow_low_risk"  // 新增：低风险自动通过
     | "require_dual_approval"; // 新增：双重审批
   ```

2. **风险等级细分**
   ```typescript
   export type RiskBasedApprovalConfig = {
     low_risk: ApprovalsReviewer;
     medium_risk: ApprovalsReviewer;
     high_risk: ApprovalsReviewer;
   };
   ```

3. **审批历史追踪**
   - 添加审批决策的历史记录
   - 支持基于历史模式的智能推荐

4. ** Guardian Subagent 配置**
   ```typescript
   export type GuardianSubagentConfig = {
     enabled: boolean;
     confidence_threshold: number;
     audit_mode: boolean; // 记录但不自动执行
   };
   ```

5. **移除实验性标记**
   - 在功能稳定后移除 `#[experimental]` 标记
   - 更新文档和类型定义

### 测试建议

1. 测试 `"user"` 模式下的审批流程
2. 测试 `"guardian_subagent"` 模式下的自动决策
3. 测试配置继承和优先级
4. 测试无效值的错误处理
5. 测试运行时配置变更的行为
6. 测试 Guardian Subagent 的误判恢复机制
