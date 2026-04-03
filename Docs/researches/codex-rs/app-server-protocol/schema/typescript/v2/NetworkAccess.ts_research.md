# NetworkAccess.ts Research Document

## 场景与职责

`NetworkAccess` 是 Codex App-Server Protocol v2 API 中用于定义沙箱网络访问级别的核心枚举类型。它主要用于控制外部沙箱（External Sandbox）环境中的网络访问权限，是安全策略配置的关键组成部分。

该类型在以下场景中被使用：
- **沙箱策略配置**：在 `SandboxPolicy` 类型中作为 `ExternalSandbox` 变体的 `network_access` 字段类型
- **网络安全控制**：决定沙箱环境是否允许网络连接，防止未授权的网络访问
- **权限管理**：与用户审批流程集成，确保敏感网络操作需要显式授权

## 功能点目的

`NetworkAccess` 枚举的设计目的是提供简单但有效的网络访问控制机制：

1. **二元访问控制**：通过两个明确的变体（`restricted` 和 `enabled`）简化网络权限管理
2. **安全优先**：默认采用 `restricted` 模式，遵循最小权限原则
3. **与沙箱策略集成**：作为 `ExternalSandbox` 沙箱策略的一部分，控制外部沙箱的网络能力

### 与 CoreNetworkAccess 的关系

该类型是 `codex_protocol::protocol::NetworkAccess`（核心协议层）的 v2 API 封装，通过 `v2_enum_from_core!` 宏自动生成转换逻辑，确保类型安全的同时保持与核心协议的兼容性。

## 具体技术实现

### 数据结构定义

```typescript
// TypeScript 定义（由 ts-rs 自动生成）
export type NetworkAccess = "restricted" | "enabled";
```

```rust
// Rust 源定义（v2.rs）
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum NetworkAccess {
    #[default]
    Restricted,
    Enabled,
}
```

### 关键字段说明

| 值 | 说明 | 使用场景 |
|---|---|---|
| `"restricted"` | 网络访问被限制（默认值） | 安全敏感环境，防止沙箱内代码进行网络通信 |
| `"enabled"` | 网络访问被启用 | 需要网络连接的场景，如调用外部 API、下载依赖等 |

### 序列化行为

- 使用 camelCase 命名规范序列化
- `Restricted` → `"restricted"`
- `Enabled` → `"enabled"`

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/NetworkAccess.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`（第 1215-1222 行）
- **核心协议定义**: `codex_protocol::protocol::NetworkAccess`

### 使用位置

```rust
// SandboxPolicy::ExternalSandbox 中的使用
#[serde(rename_all = "camelCase")]
#[ts(rename_all = "camelCase")]
ExternalSandbox {
    #[serde(default)]
    network_access: NetworkAccess,
},
```

## 依赖与外部交互

### 依赖类型

| 类型 | 关系 | 说明 |
|---|---|---|
| `CoreNetworkAccess` | 源类型 | 核心协议层的网络访问枚举 |
| `SandboxPolicy` | 使用者 | 沙箱策略枚举，包含 NetworkAccess 作为字段 |

### 转换实现

```rust
// 从核心类型转换
impl From<CoreNetworkAccess> for NetworkAccess {
    fn from(value: CoreNetworkAccess) -> Self {
        match value {
            CoreNetworkAccess::Restricted => NetworkAccess::Restricted,
            CoreNetworkAccess::Enabled => NetworkAccess::Enabled,
        }
    }
}

// 转换为核心类型
impl NetworkAccess {
    pub fn to_core(self) -> CoreNetworkAccess {
        match self {
            NetworkAccess::Restricted => CoreNetworkAccess::Restricted,
            NetworkAccess::Enabled => CoreNetworkAccess::Enabled,
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **过度宽松配置**：如果错误地将 `enabled` 设为默认值，可能导致沙箱逃逸或数据泄露风险
2. **无细粒度控制**：该类型仅提供开/关两种状态，无法对特定域名、端口或协议进行限制
3. **与 NetworkRequirements 的混淆**：`NetworkAccess` 控制沙箱网络能力，而 `NetworkRequirements` 控制代理网络配置，两者用途不同但名称相似

### 边界情况

1. **默认值行为**：Rust 实现中 `#[default]` 标记在 `Restricted` 上，确保未显式配置时网络访问被限制
2. **序列化兼容性**：使用 camelCase 确保与 TypeScript/JavaScript 生态系统的命名约定一致
3. **与 ReadOnlyAccess 的区别**：`ReadOnlyAccess` 也有 `network_access` 字段，但那是布尔类型，与此枚举不同

### 改进建议

1. **增加中间状态**：考虑增加 `"limited"` 状态，允许配置白名单/黑名单模式
2. **文档增强**：在 API 文档中明确区分 `NetworkAccess` 和 `NetworkRequirements` 的用途
3. **审计日志**：建议在网络访问状态变更时记录审计日志，便于安全追踪
4. **与 NetworkPolicy 集成**：考虑与 `NetworkPolicyAmendment` 和 `NetworkPolicyRuleAction` 更紧密集成，提供更灵活的网络策略管理

### 测试建议

- 验证默认值为 `restricted`
- 测试序列化/反序列化的正确性
- 确保与 `SandboxPolicy` 的集成正常工作
- 验证与核心协议类型的双向转换
