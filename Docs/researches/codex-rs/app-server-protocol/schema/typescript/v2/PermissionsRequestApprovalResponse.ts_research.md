# PermissionsRequestApprovalResponse 研究文档

## 场景与职责

`PermissionsRequestApprovalResponse` 是用户对权限请求批准的响应类型。当服务器发送 `PermissionsRequestApproval` 请求后，客户端使用此类型返回用户的决定。

## 功能点目的

该类型的核心功能是：
1. **权限授权反馈**: 返回用户实际授予的权限范围
2. **授权范围界定**: 明确权限是仅本次有效还是会话级别有效
3. **部分授权支持**: 允许用户只批准部分请求的权限

## 具体技术实现

### 数据结构

```typescript
export type PermissionsRequestApprovalResponse = { 
  permissions: GrantedPermissionProfile, 
  scope: PermissionGrantScope 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PermissionsRequestApprovalResponse {
    pub permissions: GrantedPermissionProfile,
    pub scope: PermissionGrantScope,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `permissions` | `GrantedPermissionProfile` | 用户实际授予的权限 |
| `scope` | `PermissionGrantScope` | 权限授权的范围 |

### 关联类型

#### GrantedPermissionProfile

```rust
pub struct GrantedPermissionProfile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub network: Option<AdditionalNetworkPermissions>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub file_system: Option<AdditionalFileSystemPermissions>,
}
```

注意：`GrantedPermissionProfile` 不包含 macOS 权限字段，只包含网络文件系统权限。

#### PermissionGrantScope

```rust
pub enum PermissionGrantScope {
    #[default]
    Turn,      // 仅当前回合有效
    Session,   // 整个会话有效
}
```

### 使用场景

这是对 `PermissionsRequestApproval` 服务器请求的响应：

```rust
server_request_definitions! {
    PermissionsRequestApproval => "item/permissions/requestApproval" {
        params: v2::PermissionsRequestApprovalParams,
        response: v2::PermissionsRequestApprovalResponse,
    },
}
```

### 转换方法

```rust
impl From<GrantedPermissionProfile> for CorePermissionProfile {
    fn from(value: GrantedPermissionProfile) -> Self {
        Self {
            network: value.network.map(CoreNetworkPermissions::from),
            file_system: value.file_system.map(CoreFileSystemPermissions::from),
            macos: None,  // GrantedPermissionProfile 不包含 macOS 权限
        }
    }
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PermissionsRequestApprovalResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器请求定义 |

## 依赖与外部交互

### 依赖类型
- `GrantedPermissionProfile`: 已授权的权限配置
- `PermissionGrantScope`: 权限授权范围枚举
- `CorePermissionProfile`: 核心权限配置类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 是客户端对服务器请求的响应
- 方法名: `item/permissions/requestApproval`

### 安全集成
- 授权结果影响沙箱的有效权限
- `Session` 级别的授权会被缓存

## 风险、边界与改进建议

### 潜在风险
1. **权限降级**: 用户可能授予比请求更少的权限，Agent 需要妥善处理
2. **范围误解**: 用户可能不理解 `Turn` 和 `Session` 的区别
3. **权限缓存**: `Session` 级别的授权需要安全的缓存机制

### 边界情况
1. **空权限**: 用户可能拒绝所有权限，返回空 `GrantedPermissionProfile`
2. **权限扩展**: 用户可能授予比请求更多的权限（虽然不太可能）
3. **范围冲突**: 如果之前的授权是 `Session` 级别，新的 `Turn` 级别授权如何处理

### 改进建议
1. 添加 `deniedReason` 字段，当权限被拒绝时说明原因
2. 添加 `expiresAt` 字段支持临时授权
3. 考虑添加 `Persistent` 范围，将授权持久化到配置文件中
4. 支持权限条件的表达（如"只允许访问此特定文件"）
