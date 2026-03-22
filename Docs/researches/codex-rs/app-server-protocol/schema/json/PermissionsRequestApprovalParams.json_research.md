# PermissionsRequestApprovalParams.json 研究文档

## 场景与职责

`PermissionsRequestApprovalParams` 是 Codex App-Server 协议中用于**权限请求审批**的参数结构。当 AI Agent 需要额外的权限（如文件系统访问、网络访问）时，服务器通过此结构向客户端发送审批请求。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `item/permissions/requestApproval`。

### 使用场景

1. **文件系统权限**：请求额外的文件读取/写入权限
2. **网络权限**：请求网络访问权限
3. **会话级权限**：为整个会话请求权限，而非单次操作

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `itemId` | string | ✅ | 审批项唯一标识 |
| `threadId` | string | ✅ | 所属线程标识 |
| `turnId` | string | ✅ | 所属回合标识 |
| `permissions` | RequestPermissionProfile | ✅ | 请求的权限配置 |
| `reason` | string \| null | ❌ | 可选解释原因 |

### 权限配置（RequestPermissionProfile）

```rust
pub struct RequestPermissionProfile {
    pub file_system: Option<AdditionalFileSystemPermissions>,
    pub network: Option<AdditionalNetworkPermissions>,
}
```

### 文件系统权限

```rust
pub struct AdditionalFileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}
```

### 网络权限

```rust
pub struct AdditionalNetworkPermissions {
    pub enabled: Option<bool>,
}
```

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct RequestPermissionProfile {
    pub network: Option<AdditionalNetworkPermissions>,
    pub file_system: Option<AdditionalFileSystemPermissions>,
}

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

### ServerRequest 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    PermissionsRequestApproval => "item/permissions/requestApproval" {
        params: v2::PermissionsRequestApprovalParams,
        response: v2::PermissionsRequestApprovalResponse,
    },
}
```

### 与 Core 类型的转换

```rust
impl From<CoreRequestPermissionProfile> for RequestPermissionProfile {
    fn from(value: CoreRequestPermissionProfile) -> Self {
        Self {
            network: value.network.map(AdditionalNetworkPermissions::from),
            file_system: value.file_system.map(AdditionalFileSystemPermissions::from),
        }
    }
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5607-5613） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | RequestPermissionProfile 定义（行 1123-1130） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 761-764） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 服务器端权限请求处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | TUI 权限审批 UI |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | 应用服务器请求处理 |

---

## 依赖与外部交互

### 依赖类型

```rust
use codex_utils_absolute_path::AbsolutePathBuf;
use codex_protocol::request_permissions::RequestPermissionProfile as CoreRequestPermissionProfile;
```

### 路径安全

`AdditionalFileSystemPermissions` 使用 `AbsolutePathBuf` 确保路径是绝对路径。相对路径在反序列化时会失败。

### 与 CommandExecutionRequestApprovalParams 的区别

`CommandExecutionRequestApprovalParams` 包含 `AdditionalPermissionProfile`，比 `RequestPermissionProfile` 多了 `macos` 字段（macOS 特定权限）。权限请求审批专注于文件系统和网络权限。

---

## 风险、边界与改进建议

### 已知风险

1. **路径验证**：虽然使用 `AbsolutePathBuf`，但不验证路径是否存在或可访问

2. **权限粒度**：网络权限只有 `enabled` 布尔值，粒度较粗

3. **权限持久化**：响应中的 `scope` 字段控制权限范围（turn/session），但实现可能复杂

### 边界情况

1. **空权限**：`permissions` 的所有字段都为 null
2. **重叠权限**：请求的权限可能与已有权限重叠
3. **无效路径**：路径格式正确但指向不存在的文件/目录

### 改进建议

1. **细化网络权限**：支持按域名/端口控制网络访问：
   ```rust
   pub struct NetworkPermissions {
       pub enabled: Option<bool>,
       pub allowed_hosts: Option<Vec<String>>,  // 域名白名单
       pub allowed_ports: Option<Vec<u16>>,     // 端口白名单
   }
   ```

2. **权限预览**：在请求中添加当前权限状态的对比：
   ```rust
   pub struct PermissionsRequestApprovalParams {
       // ... 现有字段
       pub current_permissions: RequestPermissionProfile,
       pub requested_permissions: RequestPermissionProfile,
   }
   ```

3. **权限模板**：支持预定义的权限模板：
   ```rust
   pub enum PermissionTemplate {
       ReadOnly,
       ReadWrite,
       NetworkOnly,
       FullAccess,
   }
   ```

4. **审计日志**：记录权限请求和授权历史
