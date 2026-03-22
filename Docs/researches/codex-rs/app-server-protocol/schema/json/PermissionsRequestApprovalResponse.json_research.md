# PermissionsRequestApprovalResponse.json 研究文档

## 场景与职责

`PermissionsRequestApprovalResponse` 是 Codex App-Server 协议中用于**响应权限请求审批**的结构。当客户端收到 `item/permissions/requestApproval` 请求后，通过此结构返回用户的权限授权决策。

该类型属于 **Client → Server** 的响应流，是 `PermissionsRequestApproval` 请求的预期响应类型。

### 使用场景

1. **授予权限**：用户同意授予请求的权限
2. **部分授予**：用户只同意部分权限（通过 `GrantedPermissionProfile` 的子集）
3. **控制权限范围**：用户指定权限的有效范围（当前回合或整个会话）

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `permissions` | GrantedPermissionProfile | ✅ | 授予的权限配置 |
| `scope` | PermissionGrantScope | ❌ | 权限范围（默认：turn） |

### 权限范围（PermissionGrantScope）

| 值 | 描述 |
|------|------|
| `"turn"` | 权限仅对当前回合有效（默认） |
| `"session"` | 权限对整个会话有效 |

### 授予的权限配置（GrantedPermissionProfile）

```rust
pub struct GrantedPermissionProfile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub network: Option<AdditionalNetworkPermissions>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_system: Option<AdditionalFileSystemPermissions>,
}
```

注意：与 `RequestPermissionProfile` 不同，`GrantedPermissionProfile` 不包含 `macos` 字段。

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, Default, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct GrantedPermissionProfile {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub network: Option<AdditionalNetworkPermissions>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub file_system: Option<AdditionalFileSystemPermissions>,
}

v2_enum_from_core! {
    #[derive(Default)]
    pub enum PermissionGrantScope from CorePermissionGrantScope {
        #[default]
        Turn,
        Session
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PermissionsRequestApprovalResponse {
    pub permissions: GrantedPermissionProfile,
    #[serde(default)]
    pub scope: PermissionGrantScope,
}
```

### 默认值

```rust
// scope 默认为 Turn
let response = PermissionsRequestApprovalResponse {
    permissions: GrantedPermissionProfile::default(),
    scope: PermissionGrantScope::Turn,  // 默认值
};
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5624-5631） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | GrantedPermissionProfile 定义（行 1179-1189） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 761-764） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 权限响应处理 |
| `codex-rs/tui_app_server/src/chatwidget.rs` | 聊天组件构造响应 |

---

## 依赖与外部交互

### 依赖类型

```rust
use codex_protocol::request_permissions::PermissionGrantScope as CorePermissionGrantScope;
```

### 与 Core 类型的转换

```rust
impl From<GrantedPermissionProfile> for CorePermissionProfile {
    fn from(value: GrantedPermissionProfile) -> Self {
        Self {
            network: value.network.map(CoreNetworkPermissions::from),
            file_system: value.file_system.map(CoreFileSystemPermissions::from),
            macos: None,  // GrantedPermissionProfile 不包含 macos
        }
    }
}
```

### 与 RequestPermissionProfile 的区别

| 特性 | RequestPermissionProfile | GrantedPermissionProfile |
|------|-------------------------|-------------------------|
| macos 权限 | ✅ 支持 | ❌ 不支持 |
| 字段修饰 | 无 | `#[ts(optional)]` |
| 用途 | 请求权限 | 授予权限 |

---

## 风险、边界与改进建议

### 已知风险

1. **权限子集**：用户可以授予比请求更少的权限，服务器需要处理部分授权

2. **macOS 权限缺失**：`GrantedPermissionProfile` 不包含 macOS 权限，可能限制功能

3. **范围语义**：`session` 范围的具体语义（何时开始/结束）可能不明确

### 边界情况

1. **空权限**：`permissions` 的所有字段都为 null，表示拒绝所有权限
2. **超出请求范围**：授予的权限超出请求的权限（服务器应验证）
3. **范围降级**：请求 `session` 范围但只授予 `turn` 范围

### 改进建议

1. **明确拒绝**：添加显式的拒绝字段：
   ```rust
   pub struct PermissionsRequestApprovalResponse {
       pub permissions: GrantedPermissionProfile,
       pub scope: PermissionGrantScope,
       pub denied: Vec<String>,  // 被拒绝的权限路径列表
   }
   ```

2. **时间限制**：支持有时效的权限：
   ```rust
   pub enum PermissionGrantScope {
       Turn,
       Session,
       Duration(u64),  // 毫秒数
   }
   ```

3. **权限理由**：允许用户说明授权/拒绝的原因：
   ```rust
   pub struct PermissionsRequestApprovalResponse {
       pub permissions: GrantedPermissionProfile,
       pub scope: PermissionGrantScope,
       pub reason: Option<String>,
   }
   ```

4. **撤销机制**：支持后续撤销已授予的权限
