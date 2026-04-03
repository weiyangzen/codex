# v2/index.ts Research

## 场景与职责

`v2/index.ts` 是 Codex App Server Protocol v2 API 的 TypeScript 类型主入口文件（barrel export）。它集中导出所有 v2 协议的 TypeScript 类型定义，为客户端开发者提供统一的类型导入接口。

**使用场景：**
- TypeScript 客户端需要导入 v2 协议类型
- IDE 自动补全和类型检查
- 构建时类型验证
- 文档生成工具消费类型定义

**核心职责：**
1. **统一入口**：作为 v2 协议类型的单一导入点
2. **模块组织**：按功能域组织类型导出
3. **版本隔离**：与 v1 协议类型完全隔离
4. **生成代码托管**：托管 `ts-rs` 工具生成的类型定义

## 功能点目的

该文件的设计目的是解决大型协议的类型管理问题：

1. **简化导入**：
   ```typescript
   // 而不是这样：
   import type { Thread } from "./Thread";
   import type { Turn } from "./Turn";
   
   // 可以这样做：
   import type { Thread, Turn } from "./v2";
   ```

2. **版本管理**：
   - v2 协议是活跃的 API 开发版本
   - 所有新功能都添加到 v2
   - v1 保持向后兼容，不再扩展

3. **代码生成集成**：
   - 文件内容由 `ts-rs` 从 Rust 源码自动生成
   - 确保 TypeScript 类型与 Rust 类型严格同步
   - 减少手动维护工作量和错误

## 具体技术实现

### 文件结构

```typescript
// GENERATED CODE! DO NOT MODIFY BY HAND!

export type { Account } from "./Account";
export type { AccountLoginCompletedNotification } from "./AccountLoginCompletedNotification";
// ... 330+ 类型导出
export type { WriteStatus } from "./WriteStatus";
```

### 模块组织

文件按功能域组织导出，主要类别包括：

#### 1. 账户相关 (Account)
- `Account`, `AccountLoginCompletedNotification`
- `AccountRateLimitsUpdatedNotification`, `AccountUpdatedNotification`
- `GetAccountParams`, `GetAccountResponse`, `GetAccountRateLimitsResponse`
- `LoginAccountParams`, `LoginAccountResponse`, `LogoutAccountResponse`
- `CancelLoginAccountParams`, `CancelLoginAccountResponse`

#### 2. 应用相关 (App)
- `AppBranding`, `AppInfo`, `AppListUpdatedNotification`
- `AppMetadata`, `AppReview`, `AppScreenshot`, `AppSummary`
- `AppToolApproval`, `AppToolsConfig`, `AppsConfig`, `AppsDefaultConfig`
- `AppsListParams`, `AppsListResponse`

#### 3. 命令执行 (Command)
- `CommandAction`, `CommandExecOutputDeltaNotification`
- `CommandExecOutputStream`, `CommandExecParams`, `CommandExecResponse`
- `CommandExecResizeParams`, `CommandExecResizeResponse`
- `CommandExecTerminalSize`, `CommandExecTerminateParams`, `CommandExecTerminateResponse`
- `CommandExecWriteParams`, `CommandExecWriteResponse`
- `CommandExecutionApprovalDecision`, `CommandExecutionOutputDeltaNotification`
- `CommandExecutionRequestApprovalParams`, `CommandExecutionRequestApprovalResponse`
- `CommandExecutionRequestApprovalSkillMetadata`, `CommandExecutionSource`, `CommandExecutionStatus`

#### 4. 配置管理 (Config)
- `Config`, `ConfigBatchWriteParams`, `ConfigEdit`, `ConfigLayer`
- `ConfigLayerMetadata`, `ConfigLayerSource`, `ConfigReadParams`, `ConfigReadResponse`
- `ConfigRequirements`, `ConfigRequirementsReadResponse`, `ConfigValueWriteParams`
- `ConfigWarningNotification`, `ConfigWriteResponse`, `MergeStrategy`, `WriteStatus`
- `OverriddenMetadata`

#### 5. 文件系统 (File System)
- `FsCopyParams`, `FsCopyResponse`, `FsCreateDirectoryParams`, `FsCreateDirectoryResponse`
- `FsGetMetadataParams`, `FsGetMetadataResponse`, `FsReadDirectoryEntry`
- `FsReadDirectoryParams`, `FsReadDirectoryResponse`, `FsReadFileParams`, `FsReadFileResponse`
- `FsRemoveParams`, `FsRemoveResponse`, `FsWriteFileParams`, `FsWriteFileResponse`
- `FileChangeApprovalDecision`, `FileChangeOutputDeltaNotification`
- `FileChangeRequestApprovalParams`, `FileChangeRequestApprovalResponse`, `FileUpdateChange`

#### 6. Hook 系统
- `HookCompletedNotification`, `HookEventName`, `HookExecutionMode`
- `HookHandlerType`, `HookOutputEntry`, `HookOutputEntryKind`, `HookRunStatus`
- `HookRunSummary`, `HookScope`, `HookStartedNotification`

#### 7. MCP (Model Context Protocol)
- `ListMcpServerStatusParams`, `ListMcpServerStatusResponse`, `McpAuthStatus`
- `McpElicitationArrayType`, `McpElicitationBooleanSchema`, `McpElicitationBooleanType`
- `McpElicitationConstOption`, `McpElicitationEnumSchema`, `McpElicitationLegacyTitledEnumSchema`
- `McpElicitationMultiSelectEnumSchema`, `McpElicitationNumberSchema`, `McpElicitationNumberType`
- `McpElicitationObjectType`, `McpElicitationPrimitiveSchema`, `McpElicitationSchema`
- `McpElicitationSingleSelectEnumSchema`, `McpElicitationStringFormat`, `McpElicitationStringSchema`
- `McpElicitationStringType`, `McpElicitationTitledEnumItems`, `McpElicitationTitledMultiSelectEnumSchema`
- `McpElicitationTitledSingleSelectEnumSchema`, `McpElicitationUntitledEnumItems`
- `McpElicitationUntitledMultiSelectEnumSchema`, `McpElicitationUntitledSingleSelectEnumSchema`
- `McpServerElicitationAction`, `McpServerElicitationRequestParams`, `McpServerElicitationRequestResponse`
- `McpServerOauthLoginCompletedNotification`, `McpServerOauthLoginParams`, `McpServerOauthLoginResponse`
- `McpServerRefreshResponse`, `McpServerStatus`, `McpToolCallError`, `McpToolCallProgressNotification`
- `McpToolCallResult`, `McpToolCallStatus`

#### 8. 模型相关 (Model)
- `Model`, `ModelAvailabilityNux`, `ModelListParams`, `ModelListResponse`
- `ModelRerouteReason`, `ModelReroutedNotification`, `ModelUpgradeInfo`, `ReasoningEffortOption`

#### 9. 权限管理 (Permission)
- `PermissionGrantScope`, `PermissionsRequestApprovalParams`, `PermissionsRequestApprovalResponse`
- `RequestPermissionProfile`, `GrantedPermissionProfile`, `AdditionalPermissionProfile`
- `AdditionalFileSystemPermissions`, `AdditionalMacOsPermissions`, `AdditionalNetworkPermissions`
- `SandboxMode`, `SandboxPolicy`, `SandboxWorkspaceWrite`, `ReadOnlyAccess`, `NetworkAccess`
- `NetworkApprovalContext`, `NetworkApprovalProtocol`, `NetworkPolicyAmendment`, `NetworkPolicyRuleAction`
- `NetworkRequirements`, `ExecPolicyAmendment`

#### 10. 插件系统 (Plugin)
- `PluginAuthPolicy`, `PluginDetail`, `PluginInstallParams`, `PluginInstallPolicy`
- `PluginInstallResponse`, `PluginInterface`, `PluginListParams`, `PluginListResponse`
- `PluginMarketplaceEntry`, `PluginReadParams`, `PluginReadResponse`, `PluginSource`
- `PluginSummary`, `PluginUninstallParams`, `PluginUninstallResponse`, `MarketplaceInterface`

#### 11. Skill 系统
- `SkillDependencies`, `SkillErrorInfo`, `SkillInterface`, `SkillMetadata`
- `SkillScope`, `SkillSummary`, `SkillToolDependency`, `SkillsChangedNotification`
- `SkillsConfigWriteParams`, `SkillsConfigWriteResponse`, `SkillsListEntry`
- `SkillsListExtraRootsForCwd`, `SkillsListParams`, `SkillsListResponse`

#### 12. Thread/Turn/Item 核心类型
- `Thread`, `ThreadActiveFlag`, `ThreadArchiveParams`, `ThreadArchiveResponse`
- `ThreadArchivedNotification`, `ThreadClosedNotification`, `ThreadCompactStartParams`, `ThreadCompactStartResponse`
- `ThreadForkParams`, `ThreadForkResponse`, `ThreadItem`, `ThreadListParams`, `ThreadListResponse`
- `ThreadLoadedListParams`, `ThreadLoadedListResponse`, `ThreadMetadataGitInfoUpdateParams`
- `ThreadMetadataUpdateParams`, `ThreadMetadataUpdateResponse`, `ThreadNameUpdatedNotification`
- `ThreadReadParams`, `ThreadReadResponse`, `ThreadRealtimeAudioChunk`, `ThreadRealtimeClosedNotification`
- `ThreadRealtimeErrorNotification`, `ThreadRealtimeItemAddedNotification`, `ThreadRealtimeOutputAudioDeltaNotification`
- `ThreadRealtimeStartedNotification`, `ThreadResumeParams`, `ThreadResumeResponse`
- `ThreadRollbackParams`, `ThreadRollbackResponse`, `ThreadSetNameParams`, `ThreadSetNameResponse`
- `ThreadShellCommandParams`, `ThreadShellCommandResponse`, `ThreadSortKey`, `ThreadSourceKind`
- `ThreadStartParams`, `ThreadStartResponse`, `ThreadStartedNotification`, `ThreadStatus`
- `ThreadStatusChangedNotification`, `ThreadTokenUsage`, `ThreadTokenUsageUpdatedNotification`
- `ThreadUnarchiveParams`, `ThreadUnarchiveResponse`, `ThreadUnarchivedNotification`
- `ThreadUnsubscribeParams`, `ThreadUnsubscribeResponse`, `ThreadUnsubscribeStatus`

- `Turn`, `TurnCompletedNotification`, `TurnDiffUpdatedNotification`, `TurnError`
- `TurnInterruptParams`, `TurnInterruptResponse`, `TurnPlanStep`, `TurnPlanStepStatus`
- `TurnPlanUpdatedNotification`, `TurnStartParams`, `TurnStartResponse`, `TurnStartedNotification`
- `TurnStatus`, `TurnSteerParams`, `TurnSteerResponse`

- `ItemCompletedNotification`, `ItemGuardianApprovalReviewCompletedNotification`
- `ItemGuardianApprovalReviewStartedNotification`, `ItemStartedNotification`

#### 13. Windows 平台特定
- `WindowsSandboxSetupCompletedNotification`, `WindowsSandboxSetupMode`
- `WindowsSandboxSetupStartParams`, `WindowsSandboxSetupStartResponse`
- `WindowsWorldWritableWarningNotification`

#### 14. 其他工具类型
- `ApprovalsReviewer`, `AskForApproval`, `ByteRange`, `ChatgptAuthTokensRefreshParams`
- `ChatgptAuthTokensRefreshReason`, `ChatgptAuthTokensRefreshResponse`, `CodexErrorInfo`
- `CollabAgentState`, `CollabAgentStatus`, `CollabAgentTool`, `CollabAgentToolCallStatus`
- `CollaborationModeMask`, `ContextCompactedNotification`, `CreditsSnapshot`
- `DeprecationNoticeNotification`, `DynamicToolCallOutputContentItem`, `DynamicToolCallParams`
- `DynamicToolCallResponse`, `DynamicToolCallStatus`, `DynamicToolSpec`, `ErrorNotification`
- `ExperimentalFeature`, `ExperimentalFeatureListParams`, `ExperimentalFeatureListResponse`
- `ExperimentalFeatureStage`, `ExternalAgentConfigDetectParams`, `ExternalAgentConfigDetectResponse`
- `ExternalAgentConfigImportParams`, `ExternalAgentConfigImportResponse`, `ExternalAgentConfigMigrationItem`
- `ExternalAgentConfigMigrationItemType`, `FeedbackUploadParams`, `FeedbackUploadResponse`
- `GitInfo`, `GuardianApprovalReview`, `GuardianApprovalReviewStatus`, `GuardianRiskLevel`
- `MemoryCitation`, `MemoryCitationEntry`, `OverriddenMetadata`, `PatchApplyStatus`, `PatchChangeKind`
- `PlanDeltaNotification`, `ProfileV2`, `RateLimitSnapshot`, `RateLimitWindow`
- `RawResponseItemCompletedNotification`, `ReasoningSummaryPartAddedNotification`
- `ReasoningSummaryTextDeltaNotification`, `ReasoningTextDeltaNotification`, `ResidencyRequirement`
- `ReviewDelivery`, `ReviewStartParams`, `ReviewStartResponse`, `ReviewTarget`, `ServerRequestResolvedNotification`
- `SessionSource`, `TerminalInteractionNotification`, `TextElement`, `TextPosition`, `TextRange`
- `TokenUsageBreakdown`, `ToolRequestUserInputAnswer`, `ToolRequestUserInputOption`, `ToolRequestUserInputParams`
- `ToolRequestUserInputQuestion`, `ToolRequestUserInputResponse`, `ToolsV2`, `UserInput`, `WebSearchAction`

### 生成机制

文件由 `ts-rs` crate 自动生成：

1. Rust 源码中的 `#[ts(export_to = "v2/")]` 属性标记要导出的类型
2. 构建时 `ts-rs` 生成对应的 `.ts` 文件
3. 同时生成 `index.ts` 汇总所有导出

示例 Rust 定义：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Thread {
    pub id: String,
    // ...
}
```

## 关键代码路径与文件引用

### 生成源文件
- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 所有 v2 协议类型的 Rust 定义
  - 包含 330+ 个类型定义

### 生成目标文件
- `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`
  - 本文件，barrel export
- `codex-rs/app-server-protocol/schema/typescript/v2/*.ts`
  - 单个类型定义文件（330+ 个）

### 父级导出
- `codex-rs/app-server-protocol/schema/typescript/index.ts`
  - 可能存在的更高级别 barrel export

### 消费者
- `codex-rs/app-server-protocol/schema/typescript/ServerNotification.ts`
  - 导入 v2 通知类型
- `codex-rs/codex-cli` (TypeScript CLI)
  - 客户端类型消费
- 外部 TypeScript 项目
  - 通过 npm 包消费类型

### 相关配置文件
- `codex-rs/app-server-protocol/Cargo.toml`
  - `ts-rs` 依赖配置
- `codex-rs/app-server-protocol/build.rs` (如存在)
  - 自定义生成逻辑

## 依赖与外部交互

### 生成依赖

| 工具/库 | 用途 |
|---------|------|
| `ts-rs` | Rust 到 TypeScript 的类型生成 |
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |

### 运行时依赖

生成的 TypeScript 文件依赖：
- 其他生成的类型（相对路径导入）
- 基础类型（如 `JsonValue`, `AbsolutePathBuf`）

### 导入模式

```typescript
// 从 v2 模块导入
import type { Thread, Turn, WriteStatus } from "./v2";

// 或从特定文件导入（不推荐）
import type { Thread } from "./v2/Thread";
```

### 版本策略

- **v2**: 活跃开发版本，所有新 API 添加到这里
- **v1**: 维护模式，保持向后兼容
- **未来 v3**: 当需要破坏性变更时创建

## 风险、边界与改进建议

### 已知风险

1. **文件大小**：
   - 330+ 个导出使文件较大
   - 可能影响某些构建工具的性能
   - 建议：考虑按子模块拆分（如 `v2/config`, `v2/thread`）

2. **生成代码管理**：
   - 文件是自动生成的，但提交到版本控制
   - 可能产生不必要的合并冲突
   - 建议：在 CI 中验证生成代码是否最新

3. **循环依赖风险**：
   - 复杂类型之间可能存在循环引用
   - TypeScript 的 `type` 导入可以缓解，但需要小心

### 边界情况

1. **类型名称冲突**：
   - 所有类型在 v2 命名空间内必须唯一
   - 当前命名约定（前缀）避免了冲突

2. **跨版本兼容性**：
   - v2 类型的变更可能影响客户端
   - 需要遵循语义化版本控制

3. **平台特定类型**：
   - Windows 特定类型在非 Windows 平台无用
   - 但类型定义仍然导出

### 改进建议

1. **模块化组织**：
   ```typescript
   // 建议的结构
   export * from "./account";
   export * from "./config";
   export * from "./thread";
   // ...
   ```

2. **文档生成**：
   - 集成 TypeDoc 生成 API 文档
   - 从 Rust 文档注释同步

3. **类型验证**：
   - 添加 CI 检查确保生成代码最新
   - 验证 TypeScript 类型与 JSON Schema 的一致性

4. **版本标记**：
   - 为实验性类型添加标记
   - 帮助客户端识别不稳定 API

5. **树摇优化**：
   - 确保支持 tree-shaking
   - 避免未使用类型的打包

### 维护建议

1. **生成流程**：
   ```bash
   # 建议的生成命令
   cd codex-rs/app-server-protocol
   cargo build --features export-typescript
   ```

2. **验证流程**：
   ```bash
   # 验证生成代码是否最新
   cargo test --test typescript_generation
   ```

3. **发布流程**：
   - 类型变更应触发 minor 版本更新
   - 破坏性变更需要 major 版本更新
