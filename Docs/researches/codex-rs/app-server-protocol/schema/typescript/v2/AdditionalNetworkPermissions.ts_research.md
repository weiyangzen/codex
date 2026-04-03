# AdditionalNetworkPermissions.ts 研究文档

## 1. 场景与职责

`AdditionalNetworkPermissions` 定义了**额外的网络权限配置**，用于控制 Agent 的网络访问能力。这是沙箱安全模型中的关键组成部分，决定了 Agent 是否可以访问外部网络资源。

### 使用场景
- **网络请求授权**: 当 Agent 需要访问外部 API 或下载资源时请求网络权限
- **离线模式**: 完全禁用网络访问以确保数据安全
- **受限网络**: 仅允许访问特定域名或 IP 范围
- **代理配置**: 控制代理服务器访问权限

### 职责
- 定义网络访问的启用/禁用状态（`enabled`）
- 作为网络权限请求和授予的数据载体
- 支持细粒度的网络访问控制

---

## 2. 功能点目的

### 2.1 网络访问控制

```typescript
export type AdditionalNetworkPermissions = { 
  enabled: boolean | null,  // 网络访问是否启用
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `enabled` | `boolean \| null` | `true` 允许网络访问，`false` 禁止，`null` 使用默认值 |

### 2.3 设计意图

1. **简单明确**: 使用布尔值表示网络访问的基本开关
2. **可空设计**: `null` 允许使用系统或配置默认值
3. **扩展预留**: 当前简单设计为未来更细粒度的网络控制预留空间

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AdditionalNetworkPermissions {
  enabled: boolean | null;
}
```

### 3.2 Rust 源类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalNetworkPermissions {
    pub enabled: Option<bool>,
}

// 与 CoreNetworkPermissions 的转换
impl From<CoreNetworkPermissions> for AdditionalNetworkPermissions {
    fn from(value: CoreNetworkPermissions) -> Self {
        Self {
            enabled: value.enabled,
        }
    }
}

impl From<AdditionalNetworkPermissions> for CoreNetworkPermissions {
    fn from(value: AdditionalNetworkPermissions) -> Self {
        Self {
            enabled: value.enabled,
        }
    }
}
```

### 3.3 在权限系统中的位置

```
PermissionProfile
  ├── network: NetworkPermissions  ← AdditionalNetworkPermissions 映射自此
  ├── file_system: FileSystemPermissions
  └── macos: MacOsPermissions
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（约第 1100-1121 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AdditionalNetworkPermissions.ts` | 生成的 TypeScript 类型 |

### 4.2 类型依赖

此类型无外部类型依赖。

### 4.3 使用位置

| 类型 | 用途 |
|------|------|
| `RequestPermissionProfile` | 权限请求时的网络部分 |
| `AdditionalPermissionProfile` | 完整的额外权限配置 |
| `PermissionsRequestApprovalParams` | 权限请求审批参数 |
| `NetworkRequirements` | 配置要求中的网络限制 |

### 4.4 网络权限流程

```
┌─────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────────┐
│  Agent  │───►│  Network    │───►│  User   │───►│   Grant     │
│ Request │    │  Blocked    │    │ Prompt  │    │  Permission │
│         │    │  (Sandbox)  │    │         │    │             │
└─────────┘    └─────────────┘    └─────────┘    └──────┬──────┘
                                                        │
                                                        ▼
┌─────────┐    ┌─────────────┐    ┌─────────┐    ┌─────────────┐
│ Execute │◄───│  Update     │◄───│  Server │◄───│ Additional  │
│  Action │    │  Sandbox    │    │  Notify │    │  Network    │
│         │    │  Policy     │    │         │    │ Permissions │
└─────────┘    └─────────────┘    └─────────┘    └─────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                      Network Layer                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  HTTP/HTTPS │  │   SOCKS5    │  │   Unix Domain       │ │
│  │  Requests   │  │   Proxy     │  │   Sockets           │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          ▼                                 │
│         ┌─────────────────────────────────┐                │
│         │  Network Policy Enforcement     │                │
│         │  (Sandbox + Firewall Rules)     │                │
│         └─────────────────────────────────┘                │
│                          │                                 │
│                          ▼                                 │
│         ┌─────────────────────────────────┐                │
│         │ AdditionalNetworkPermissions    │                │
│         │ (enabled: true/false/null)      │                │
│         └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 序列化示例

**启用网络:**
```json
{
  "enabled": true
}
```

**禁用网络:**
```json
{
  "enabled": false
}
```

**使用默认:**
```json
{
  "enabled": null
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 过度简化 | 仅布尔值无法表达复杂的网络策略 | 结合 `NetworkRequirements` 实现细粒度控制 |
| DNS 泄露 | 即使 `enabled: false` 仍可能解析 DNS | 沙箱层拦截 DNS 查询 |
| 本地网络 | 无法区分外网和本地网络访问 | 使用 `NetworkRequirements` 的 `allow_local_binding` |
| 代理绕过 | 恶意代码可能尝试绕过代理 | 强制所有流量通过配置的代理 |

### 6.2 边界情况

1. **部分网络**: 某些沙箱实现可能允许特定白名单域名
2. **本地回环**: `localhost` / `127.0.0.1` 的访问策略
3. **Unix Socket**: 本地 Unix 域套接字的访问控制
4. **ICMP**: ping 等 ICMP 流量的处理

### 6.3 改进建议

1. **细粒度控制**: 添加域名/IP 白名单
   ```typescript
   export type AdditionalNetworkPermissions = { 
     enabled: boolean | null;
     allowlist?: {
       domains: string[];     // 如 ["api.openai.com", "*.github.com"]
       ips: string[];         // CIDR 表示法
       ports: number[];       // 允许的端口
     };
   };
   ```

2. **出站代理**: 强制使用代理服务器
   ```typescript
   proxy?: {
     http?: string;     // http://proxy:8080
     https?: string;    // https://proxy:8080
     socks5?: string;   // socks5://proxy:1080
   };
   ```

3. **流量限制**: 添加带宽和请求频率限制
   ```typescript
   limits?: {
     maxBandwidthBps?: number;      // 最大带宽
     maxRequestsPerMinute?: number; // 请求频率
     maxConcurrentConnections?: number;
   };
   ```

4. **DNS 控制**: 自定义 DNS 解析
   ```typescript
   dns?: {
     servers: string[];      // 自定义 DNS 服务器
     blockLists: string[];   // DNS 阻止列表
   };
   ```

5. **审计日志**: 记录网络访问
   ```typescript
   audit?: {
     logAllRequests: boolean;
     logFailedRequests: boolean;
   };
   ```

### 6.4 与 NetworkRequirements 的关系

当前 `AdditionalNetworkPermissions` 是简化的运行时权限，而 `NetworkRequirements` 提供了更详细的配置：

```typescript
// NetworkRequirements.ts - 更详细的配置
export type NetworkRequirements = {
  enabled?: boolean;
  httpPort?: number;
  socksPort?: number;
  allowUpstreamProxy?: boolean;
  dangerouslyAllowNonLoopbackProxy?: boolean;
  allowedDomains?: string[];
  deniedDomains?: string[];
  // ...
};
```

**建议**: 考虑合并或明确分层这两个类型的职责。

### 6.5 测试建议

- 网络启用/禁用的实际效果
- DNS 查询的拦截
- 本地回环地址的处理
- 代理服务器的正确使用
- 并发网络请求的限制
- 大文件下载的带宽限制
