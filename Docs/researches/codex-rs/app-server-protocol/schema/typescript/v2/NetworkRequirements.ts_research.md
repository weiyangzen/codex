# NetworkRequirements 研究文档

## 场景与职责

`NetworkRequirements` 定义了网络访问的配置要求，用于企业环境或托管部署中强制执行网络策略。它允许管理员配置允许的网络端口、域名、代理设置等。

## 功能点目的

该类型的核心功能是：
1. **网络策略强制**: 定义允许的网络访问范围和限制
2. **代理配置**: 配置 HTTP/SOCKS 代理设置
3. **域名控制**: 明确允许或拒绝特定域名的访问
4. **Unix Socket 控制**: 管理 Unix 域套接字的访问权限

## 具体技术实现

### 数据结构

```typescript
export type NetworkRequirements = { 
  enabled: boolean | null, 
  httpPort: number | null, 
  socksPort: number | null, 
  allowUpstreamProxy: boolean | null, 
  dangerouslyAllowNonLoopbackProxy: boolean | null, 
  dangerouslyAllowAllUnixSockets: boolean | null, 
  allowedDomains: Array<string> | null, 
  deniedDomains: Array<string> | null, 
  allowUnixSockets: Array<string> | null, 
  allowLocalBinding: boolean | null 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct NetworkRequirements {
    pub enabled: Option<bool>,
    pub http_port: Option<u16>,
    pub socks_port: Option<u16>,
    pub allow_upstream_proxy: Option<bool>,
    pub dangerously_allow_non_loopback_proxy: Option<bool>,
    pub dangerously_allow_all_unix_sockets: Option<bool>,
    pub allowed_domains: Option<Vec<String>>,
    pub denied_domains: Option<Vec<String>>,
    pub allow_unix_sockets: Option<Vec<String>>,
    pub allow_local_binding: Option<bool>,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `enabled` | `boolean \| null` | 是否启用网络访问 |
| `httpPort` | `number \| null` | HTTP 代理端口 |
| `socksPort` | `number \| null` | SOCKS 代理端口 |
| `allowUpstreamProxy` | `boolean \| null` | 是否允许上游代理 |
| `dangerouslyAllowNonLoopbackProxy` | `boolean \| null` | 允许非回环代理（危险） |
| `dangerouslyAllowAllUnixSockets` | `boolean \| null` | 允许所有 Unix Socket（危险） |
| `allowedDomains` | `string[] \| null` | 允许的域名列表 |
| `deniedDomains` | `string[] \| null` | 拒绝的域名列表 |
| `allowUnixSockets` | `string[] \| null` | 允许的 Unix Socket 路径列表 |
| `allowLocalBinding` | `boolean \| null` | 是否允许本地端口绑定 |

### 使用场景

该类型用于 `ConfigRequirements` 中：

```rust
pub struct ConfigRequirements {
    pub allowed_approval_policies: Option<Vec<AskForApproval>>,
    pub allowed_sandbox_modes: Option<Vec<SandboxMode>>,
    pub allowed_web_search_modes: Option<Vec<WebSearchMode>>,
    pub feature_requirements: Option<BTreeMap<String, bool>>,
    pub enforce_residency: Option<ResidencyRequirement>,
    pub network: Option<NetworkRequirements>,  // <-- 这里
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 834-848 |
| `codex-rs/app-server-protocol/schema/typescript/v2/NetworkRequirements.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 依赖类型
- `ConfigRequirements`: 包含该类型作为网络配置部分

### 协议集成
- 属于 App-Server Protocol v2 API
- 用于 `configRequirements/read` 端点
- 标记为实验性功能: `configRequirements/read.network`

### 安全集成
- 与沙箱网络策略相关
- 影响 `SandboxPolicy` 中的网络访问控制

## 风险、边界与改进建议

### 安全风险
1. **危险选项**: `dangerouslyAllowNonLoopbackProxy` 和 `dangerouslyAllowAllUnixSockets` 明确标记为危险，可能绕过安全限制
2. **域名欺骗**: 简单的域名匹配可能无法防止某些欺骗攻击
3. **代理绕过**: 如果代理配置不当，可能导致流量绕过监控

### 边界情况
1. **通配符支持**: 当前域名列表不支持通配符（如 `*.example.com`）
2. **IP 地址**: 不清楚是否支持直接 IP 地址控制
3. **CIDR 表示法**: 不支持 IP 范围（如 `10.0.0.0/8`）

### 改进建议
1. 支持域名通配符匹配
2. 添加 IP 地址和 CIDR 范围支持
3. 添加端口级别的控制
4. 考虑添加 TLS 证书固定要求
5. 添加网络访问审计日志选项
6. 支持按协议类型（HTTP/HTTPS/SOCKS）的独立配置
