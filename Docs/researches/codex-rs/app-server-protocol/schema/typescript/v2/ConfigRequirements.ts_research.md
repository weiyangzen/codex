# ConfigRequirements.ts Research Document

## 场景与职责

`ConfigRequirements` 是 Codex App-Server V2 API 中用于定义配置约束和强制要求的核心类型。它主要用于企业环境或团队管理场景，允许管理员通过 `requirements.toml` 或 MDM (Mobile Device Management) 设置来限制用户可使用的配置选项。

该类型的典型使用场景包括：
- **企业合规管理**: 限制员工可使用的沙箱模式、审批策略等敏感配置
- **安全策略强制执行**: 确保所有用户遵循统一的安全标准
- **功能开关管理**: 控制哪些实验性功能可以被启用
- **数据驻留合规**: 强制要求数据存储在特定地理区域（如美国）

## 功能点目的

`ConfigRequirements` 的主要目的是提供一种机制，让管理员能够：

1. **限制审批策略**: 控制用户可以设置的自动审批级别，防止过度宽松的安全设置
2. **限制沙箱模式**: 防止用户禁用沙箱或启用危险的全访问模式
3. **限制网络搜索模式**: 控制用户可以使用哪些网络搜索配置
4. **强制功能要求**: 要求某些功能必须开启或关闭
5. **强制数据驻留**: 确保数据处理和存储符合地理合规要求

## 具体技术实现

### 数据结构定义

```typescript
import type { WebSearchMode } from "../WebSearchMode";
import type { AskForApproval } from "./AskForApproval";
import type { ResidencyRequirement } from "./ResidencyRequirement";
import type { SandboxMode } from "./SandboxMode";

export type ConfigRequirements = {
  allowedApprovalPolicies: Array<AskForApproval> | null,
  allowedSandboxModes: Array<SandboxMode> | null,
  allowedWebSearchModes: Array<WebSearchMode> | null,
  featureRequirements: { [key in string]?: boolean } | null,
  enforceResidency: ResidencyRequirement | null
};
```

### 关键字段说明

| 字段名 | 类型 | 说明 |
|--------|------|------|
| `allowedApprovalPolicies` | `Array<AskForApproval> \| null` | 允许使用的审批策略列表。如果为 `null`，表示不限制。可选值包括 `"untrusted"`、`"on-failure"`、`"on-request"`、granular 对象、`"never"` |
| `allowedSandboxModes` | `Array<SandboxMode> \| null` | 允许使用的沙箱模式列表。如果为 `null`，表示不限制。可选值为 `"read-only"`、`"workspace-write"`、`"danger-full-access"` |
| `allowedWebSearchModes` | `Array<WebSearchMode> \| null` | 允许使用的网络搜索模式列表。如果为 `null`，表示不限制。可选值为 `"disabled"`、`"cached"`、`"live"` |
| `featureRequirements` | `{ [key in string]?: boolean } \| null` | 功能要求映射表，键为功能名称，值为是否必须启用。用于强制开启或关闭特定功能 |
| `enforceResidency` | `ResidencyRequirement \| null` | 强制数据驻留要求。目前仅支持 `"us"`，用于确保数据存储在美国境内 |

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/ConfigRequirements.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 对应 Rust 结构体：`ConfigRequirements` (行 820-832)
  - 包含实验性 API 标记 `#[experimental(nested)]`

### 依赖类型

| 类型 | 文件路径 | 说明 |
|------|----------|------|
| `AskForApproval` | `v2/AskForApproval.ts` | 审批策略枚举 |
| `SandboxMode` | `v2/SandboxMode.ts` | 沙箱模式枚举 |
| `WebSearchMode` | `../WebSearchMode.ts` | 网络搜索模式枚举 |
| `ResidencyRequirement` | `v2/ResidencyRequirement.ts` | 数据驻留要求枚举 |

### 相关响应类型

| 类型 | 说明 |
|------|------|
| `ConfigRequirementsReadResponse` | 读取配置要求的响应包装器 |

## 依赖与外部交互

### 上游依赖

1. **ts-rs 生成**: 该文件由 Rust 的 `ts-rs` 库自动生成，不要手动修改
2. **核心协议类型**: 依赖 `codex_protocol::config_types` 中的相关类型

### 下游使用

1. **配置验证**: 在配置写入时验证用户设置是否符合要求
2. **UI 限制**: 客户端根据允许的值列表限制用户界面选项
3. **策略执行**: 服务端强制执行这些要求，拒绝不符合的 API 请求

### 配置层级

`ConfigRequirements` 通常来自以下高优先级配置源：
- MDM 管理配置 (precedence 0)
- 系统级配置 (precedence 10)

这些配置源优先级高于用户配置，确保企业策略无法被用户覆盖。

## 风险、边界与改进建议

### 潜在风险

1. **过度限制**: 如果 `allowedSandboxModes` 限制过于严格，可能导致某些合法工作流无法执行
2. **功能冲突**: `featureRequirements` 中的要求可能与用户的实际业务需求冲突
3. **版本兼容性**: 当新增审批策略或沙箱模式时，旧版客户端可能无法识别新的允许值

### 边界情况

1. **空数组 vs null**: 
   - `null` 表示"不限制"
   - 空数组 `[]` 理论上表示"禁止所有选项"，这可能导致系统无法正常工作
   
2. **Granular 审批策略**: 
   - `AskForApproval` 支持复杂的 granular 对象类型
   - 在 `allowedApprovalPolicies` 中包含 granular 配置需要特殊处理

3. **实验性功能**:
   - `allowedApprovalPolicies` 标记为实验性 API
   - 未来可能增加新的策略类型或修改现有类型

### 改进建议

1. **增加验证逻辑**: 在服务端增加对 `ConfigRequirements` 自身的验证，防止设置空数组等无效配置
2. **支持通配符**: 考虑支持 `"*"` 通配符明确表示"允许所有"
3. **分层要求**: 支持按用户组或项目设置不同的要求
4. **审计日志**: 记录要求变更历史，便于合规审计
5. **文档生成**: 自动生成受限制配置的用户友好说明

### 代码示例

```typescript
// 示例：企业安全策略配置
const enterpriseRequirements: ConfigRequirements = {
  // 只允许较严格的审批策略
  allowedApprovalPolicies: ["untrusted", "on-request"],
  
  // 禁止危险的全访问模式
  allowedSandboxModes: ["read-only", "workspace-write"],
  
  // 允许所有网络搜索模式
  allowedWebSearchModes: null,
  
  // 强制开启审计日志功能
  featureRequirements: {
    "audit_logging": true,
    "telemetry": true
  },
  
  // 强制数据驻留美国
  enforceResidency: "us"
};
```
