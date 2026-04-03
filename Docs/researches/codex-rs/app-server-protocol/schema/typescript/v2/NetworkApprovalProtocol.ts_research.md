# NetworkApprovalProtocol 研究文档

## 场景与职责

`NetworkApprovalProtocol` 是一个枚举类型，定义了网络访问请求批准流程中支持的网络协议类型。它用于在执行网络相关的沙箱操作时，标识请求访问的网络协议。

## 功能点目的

该类型的核心功能是：
1. **协议标识**: 明确标识网络请求使用的传输层协议
2. **安全策略**: 支持基于协议类型的细粒度网络访问控制
3. **代理支持**: 支持 HTTP、HTTPS 以及 SOCKS5 代理协议

## 具体技术实现

### 数据结构

```typescript
export type NetworkApprovalProtocol = "http" | "https" | "socks5Tcp" | "socks5Udp";
```

### Rust 源码定义

```rust
v2_enum_from_core! {
    pub enum NetworkApprovalProtocol from CoreNetworkApprovalProtocol {
        Http,
        Https,
        Socks5Tcp,
        Socks5Udp
    }
}
```

### 枚举值详解

| 枚举值 | 说明 |
|-------|------|
| `http` | HTTP 协议，用于普通的 HTTP 请求 |
| `https` | HTTPS 协议，用于加密的 HTTP 请求 |
| `socks5Tcp` | SOCKS5 TCP 协议，用于 TCP 流量的 SOCKS5 代理 |
| `socks5Udp` | SOCKS5 UDP 协议，用于 UDP 流量的 SOCKS5 代理 |

### 序列化配置

```rust
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
```

序列化时使用 camelCase 格式，例如：`socks5Tcp`。

### 与 Core 类型的映射

```rust
impl NetworkApprovalProtocol {
    pub fn to_core(self) -> CoreNetworkApprovalProtocol {
        match self {
            NetworkApprovalProtocol::Http => CoreNetworkApprovalProtocol::Http,
            NetworkApprovalProtocol::Https => CoreNetworkApprovalProtocol::Https,
            NetworkApprovalProtocol::Socks5Tcp => CoreNetworkApprovalProtocol::Socks5Tcp,
            NetworkApprovalProtocol::Socks5Udp => CoreNetworkApprovalProtocol::Socks5Udp,
        }
    }
}
```

### 使用场景

该枚举主要用于 `NetworkApprovalContext` 类型中：

```rust
pub struct NetworkApprovalContext {
    pub host: String,
    pub protocol: NetworkApprovalProtocol,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 1007-1014 |
| `codex-rs/app-server-protocol/schema/typescript/v2/NetworkApprovalProtocol.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 依赖类型
- `CoreNetworkApprovalProtocol`: 来自 codex_protocol 的核心枚举类型
- `NetworkApprovalContext`: 使用该枚举作为字段类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 用于网络访问审批流程

### 沙箱集成
- 与沙箱网络策略 (`SandboxPolicy`) 相关
- 用于 `NetworkPolicyAmendment` 中的网络规则配置

## 风险、边界与改进建议

### 潜在风险
1. **协议混淆**: HTTP 和 HTTPS 是不同的安全级别，需要正确区分
2. **SOCKS5 支持**: 并非所有环境都支持 SOCKS5 代理

### 边界情况
1. **未知协议**: 如果遇到未列出的协议，可能需要扩展枚举
2. **协议版本**: 当前不区分 HTTP/1.1 和 HTTP/2

### 改进建议
1. 考虑添加 `ftp` 或 `ftps` 支持
2. 可以添加 `ws` 和 `wss` (WebSocket) 支持
3. 考虑添加协议版本信息（如 HTTP/2、HTTP/3）
