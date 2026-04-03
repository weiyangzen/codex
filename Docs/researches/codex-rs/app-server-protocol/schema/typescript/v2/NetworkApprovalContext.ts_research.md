# NetworkApprovalContext.ts Research Document

## 场景与职责

`NetworkApprovalContext` 是 Codex App-Server Protocol v2 API 中用于描述网络访问审批请求的上下文信息的核心数据结构。它在用户需要批准或拒绝网络连接请求时，提供必要的上下文信息帮助用户做出明智的决策。

该类型在以下关键场景中被使用：

- **网络访问审批流程**：当沙箱中的代码尝试进行网络连接时，系统会创建 `NetworkApprovalContext` 来封装请求的详细信息
- **用户决策支持**：向用户展示目标主机和协议信息，帮助用户理解请求的上下文
- **安全审计**：记录网络访问请求的上下文，用于安全审计和合规性检查
- **策略匹配**：与网络策略规则进行匹配，确定是否需要用户审批

## 功能点目的

`NetworkApprovalContext` 的设计目的是提供简洁但完整的网络请求上下文：

1. **主机识别**：明确标识网络请求的目标主机（域名或 IP 地址）
2. **协议透明**：告知用户请求使用的网络协议类型
3. **审批决策支持**：为用户或自动化审批系统提供足够信息做出决策
4. **策略规则生成**：可作为创建网络策略修正（`NetworkPolicyAmendment`）的基础

### 与 NetworkPolicyAmendment 的关系

`NetworkApprovalContext` 提供请求的上下文信息，而 `NetworkPolicyAmendment` 用于持久化用户的审批决策。当用户批准某个主机的网络访问时，可以基于 `NetworkApprovalContext` 中的 `host` 创建相应的策略规则。

## 具体技术实现

### 数据结构定义

```typescript
// TypeScript 定义（由 ts-rs 自动生成）
import type { NetworkApprovalProtocol } from "./NetworkApprovalProtocol";

export type NetworkApprovalContext = { host: string, protocol: NetworkApprovalProtocol, };
```

```rust
// Rust 源定义（v2.rs）
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct NetworkApprovalContext {
    pub host: String,
    pub protocol: NetworkApprovalProtocol,
}
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `host` | `string` | 是 | 目标主机地址，可以是域名（如 `"api.openai.com"`）或 IP 地址（如 `"192.168.1.1"`） |
| `protocol` | `NetworkApprovalProtocol` | 是 | 请求使用的网络协议，如 HTTP、HTTPS、SOCKS5 等 |

### 序列化行为

- 使用 camelCase 命名规范序列化
- 在 JSON 中表现为扁平对象，便于前端处理和展示

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/NetworkApprovalContext.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs`（第 1016-1031 行）
- **核心协议定义**: `codex_protocol::approvals::NetworkApprovalContext`

### 转换实现

```rust
impl From<CoreNetworkApprovalContext> for NetworkApprovalContext {
    fn from(value: CoreNetworkApprovalContext) -> Self {
        Self {
            host: value.host,
            protocol: value.protocol.into(),
        }
    }
}
```

## 依赖与外部交互

### 依赖类型

| 类型 | 关系 | 说明 |
|---|---|---|
| `NetworkApprovalProtocol` | 字段类型 | 定义支持的网络协议枚举 |
| `CoreNetworkApprovalContext` | 源类型 | 核心协议层的审批上下文结构 |
| `NetworkPolicyAmendment` | 相关类型 | 基于审批上下文创建持久化策略规则 |
| `CommandExecutionApprovalDecision` | 使用者 | 审批决策枚举，包含网络策略修正选项 |

### 相关类型交互

```rust
// CommandExecutionApprovalDecision 中的使用
#[serde(rename_all = "camelCase")]
ApplyNetworkPolicyAmendment {
    network_policy_amendment: NetworkPolicyAmendment,
},
```

当用户选择 `ApplyNetworkPolicyAmendment` 决策时，系统会基于 `NetworkApprovalContext` 中的信息创建 `NetworkPolicyAmendment`。

## 风险、边界与改进建议

### 潜在风险

1. **主机信息伪造**：如果 `host` 字段来自不可信来源，可能存在伪造风险
2. **协议信息不完整**：当前仅支持有限的协议类型，可能无法覆盖所有网络访问场景
3. **缺乏端口信息**：不包含目标端口信息，可能无法区分同一主机的不同服务
4. **无请求路径**：对于 HTTP/HTTPS 请求，不包含 URL 路径信息

### 边界情况

1. **空主机字符串**：理论上 `host` 可以是空字符串，但实践中应该避免
2. **国际化域名**：应支持 Punycode 编码的国际化域名
3. **IPv6 地址**：应正确处理 IPv6 地址的格式（带方括号或不带）

### 改进建议

1. **增加端口信息**：
   ```rust
   pub struct NetworkApprovalContext {
       pub host: String,
       pub port: Option<u16>,  // 新增
       pub protocol: NetworkApprovalProtocol,
   }
   ```

2. **增加请求路径**（针对 HTTP/HTTPS）：
   ```rust
   pub path: Option<String>,  // 新增，如 "/api/v1/chat"
   ```

3. **增加请求方法**（针对 HTTP/HTTPS）：
   ```rust
   pub method: Option<String>,  // 新增，如 "GET", "POST"
   ```

4. **验证主机格式**：在创建时验证 `host` 是否为有效的域名或 IP 地址

5. **标准化处理**：对主机名进行标准化处理（如统一小写、去除尾随点）

### 安全建议

- 在展示给用户之前，对 `host` 进行 XSS 过滤
- 对于敏感主机，增加额外的确认步骤
- 记录所有审批上下文用于审计
- 考虑增加请求指纹（如哈希值）防止重放攻击

### 测试建议

- 测试各种主机格式（域名、IPv4、IPv6）
- 验证与 `NetworkApprovalProtocol` 的所有组合
- 测试序列化/反序列化的正确性
- 验证与核心协议类型的双向转换
- 测试国际化域名处理
