# PermissionsRequestApprovalParams 研究文档

## 场景与职责

`PermissionsRequestApprovalParams` 定义了请求额外权限批准的参数类型。当 Agent 需要超出当前沙箱策略允许的权限时（如访问特定文件或网络），使用此类型向用户请求批准。

## 功能点目的

该类型的核心功能是：
1. **权限升级请求**: 允许 Agent 在运行时请求额外权限
2. **上下文关联**: 将权限请求与特定的线程、回合和项目关联
3. **理由说明**: 提供请求权限的原因说明
4. **结构化权限**: 使用 `RequestPermissionProfile` 定义请求的权限范围

## 具体技术实现

### 数据结构

```typescript
export type PermissionsRequestApprovalParams = { 
  threadId: string, 
  turnId: string, 
  itemId: string, 
  reason: string | null, 
  permissions: RequestPermissionProfile 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PermissionsRequestApprovalParams {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,
    pub reason: Option<String>,
    pub permissions: RequestPermissionProfile,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `threadId` | `string` | 关联的线程 ID |
| `turnId` | `string` | 关联的回合 ID |
| `itemId` | `string` | 关联的项目 ID |
| `reason` | `string \| null` | 请求权限的原因说明 |
| `permissions` | `RequestPermissionProfile` | 请求的权限配置 |

### 关联类型

`RequestPermissionProfile` 定义了请求的权限范围：

```rust
pub struct RequestPermissionProfile {
    pub network: Option<AdditionalNetworkPermissions>,
    pub file_system: Option<AdditionalFileSystemPermissions>,
}
```

### 使用场景

这是一个服务器向客户端发送的请求类型：

```rust
server_request_definitions! {
    PermissionsRequestApproval => "item/permissions/requestApproval" {
        params: v2::PermissionsRequestApprovalParams,
        response: v2::PermissionsRequestApprovalResponse,
    },
}
```

### 响应类型

```rust
pub struct PermissionsRequestApprovalResponse {
    pub permissions: GrantedPermissionProfile,
    pub scope: PermissionGrantScope,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PermissionsRequestApprovalParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器请求定义，行 760-764 |

## 依赖与外部交互

### 依赖类型
- `RequestPermissionProfile`: 请求的权限配置
- `GrantedPermissionProfile`: 响应中返回的已授权权限
- `PermissionGrantScope`: 权限授权范围

### 协议集成
- 属于 App-Server Protocol v2 API
- 是服务器向客户端发送的请求（Server Request）
- 方法名: `item/permissions/requestApproval`

### 安全集成
- 与沙箱权限系统相关
- 影响 `SandboxPolicy` 的有效权限

## 风险、边界与改进建议

### 潜在风险
1. **权限提升攻击**: 恶意 Agent 可能尝试请求过多权限
2. **社会工程学**: `reason` 字段可能被用于误导用户
3. **权限持久化**: 需要明确授权的权限是临时的还是持久的

### 边界情况
1. **部分授权**: 用户可能只批准部分请求的权限
2. **超时处理**: 用户长时间不响应的处理机制
3. **并发请求**: 多个并发权限请求的处理

### 改进建议
1. 添加 `requestedAt` 时间戳字段
2. 添加 `timeoutSeconds` 字段指定请求超时时间
3. 考虑添加 `riskLevel` 字段帮助用户理解风险
4. 支持权限模板引用，简化常见权限请求
5. 添加 `denyReason` 字段用于用户拒绝时提供原因
