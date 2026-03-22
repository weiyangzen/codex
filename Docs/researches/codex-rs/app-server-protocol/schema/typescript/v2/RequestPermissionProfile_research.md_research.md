# RequestPermissionProfile 研究文档

## 场景与职责

`RequestPermissionProfile` 是 Codex App Server Protocol v2 中用于定义请求权限配置的结构体。它允许在运行时动态请求额外的权限，如网络访问权限和文件系统访问权限。

该类型在权限请求流程中扮演核心角色，当 Codex 需要超出当前沙箱策略的权限时，通过此类型向用户展示权限请求，并收集用户的授权决定。

## 功能点目的

1. **动态权限请求**：支持在运行时请求额外权限
2. **权限分类**：区分网络权限和文件系统权限
3. **用户授权**：收集用户对权限请求的决定
4. **策略扩展**：允许临时或永久扩展当前沙箱策略

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[serde(deny_unknown_fields)]
#[ts(export_to = "v2/")]
pub struct RequestPermissionProfile {
    pub network: Option<AdditionalNetworkPermissions>,
    pub file_system: Option<AdditionalFileSystemPermissions>,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/RequestPermissionProfile.ts)
export type RequestPermissionProfile = { 
    network: AdditionalNetworkPermissions | null, 
    fileSystem: AdditionalFileSystemPermissions | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `network` | `Option<AdditionalNetworkPermissions>` | 额外的网络权限请求 |
| `file_system` | `Option<AdditionalFileSystemPermissions>` | 额外的文件系统权限请求 |

### 子类型定义

```rust
// 网络权限
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalNetworkPermissions {
    pub enabled: Option<bool>,
}

// 文件系统权限
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalFileSystemPermissions {
    pub read: Option<Vec<AbsolutePathBuf>>,
    pub write: Option<Vec<AbsolutePathBuf>>,
}
```

### 核心协议类型映射

```rust
// 与 codex_protocol 类型的转换
impl From<CoreRequestPermissionProfile> for RequestPermissionProfile {
    fn from(value: CoreRequestPermissionProfile) -> Self {
        Self {
            network: value.network.map(AdditionalNetworkPermissions::from),
            file_system: value.file_system.map(AdditionalFileSystemPermissions::from),
        }
    }
}

impl From<RequestPermissionProfile> for CoreRequestPermissionProfile {
    fn from(value: RequestPermissionProfile) -> Self {
        Self {
            network: value.network.map(CoreNetworkPermissions::from),
            file_system: value.file_system.map(CoreFileSystemPermissions::from),
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 1123-1148)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/RequestPermissionProfile.ts`

### 相关类型
- `AdditionalNetworkPermissions`: 网络权限子类型
- `AdditionalFileSystemPermissions`: 文件系统权限子类型
- `AdditionalPermissionProfile`: 扩展版本，包含 macOS 权限
- `GrantedPermissionProfile`: 已授权权限配置
- `PermissionsRequestApprovalParams`: 权限请求参数

### 使用场景
- `CommandExecutionRequestApprovalParams.additional_permissions`: 命令执行时的额外权限请求
- `PermissionsRequestApprovalParams`: 独立的权限请求

## 依赖与外部交互

### 内部依赖
- `AdditionalNetworkPermissions`: 网络权限定义
- `AdditionalFileSystemPermissions`: 文件系统权限定义
- `codex_protocol::request_permissions::RequestPermissionProfile`: 核心协议类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**权限请求示例**:
```json
{
    "jsonrpc": "2.0",
    "method": "item/commandExecution/requestApproval",
    "params": {
        "threadId": "thread-123",
        "turnId": "turn-456",
        "itemId": "item-789",
        "command": "curl https://api.example.com",
        "additionalPermissions": {
            "network": {
                "enabled": true
            },
            "fileSystem": null
        }
    }
}
```

**权限响应示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "decision": "accept"
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **简单网络权限**：网络权限只有 `enabled` 布尔值，无法指定特定域名
2. **无时间限制**：权限授予后没有过期时间
3. **无范围限制**：无法限制权限的使用次数或范围

### 边界情况
1. **空权限请求**：`network` 和 `file_system` 都为 `None` 的情况
2. **权限冲突**：请求的权限与当前策略冲突
3. **部分授权**：用户可能只授权部分请求的权限

### 改进建议

1. **细化网络权限**：
   ```rust
   pub struct AdditionalNetworkPermissions {
       pub enabled: Option<bool>,
       pub allowed_domains: Option<Vec<String>>,  // 新增
       pub denied_domains: Option<Vec<String>>,   // 新增
   }
   ```

2. **添加时间限制**：
   ```rust
   pub struct RequestPermissionProfile {
       pub network: Option<AdditionalNetworkPermissions>,
       pub file_system: Option<AdditionalFileSystemPermissions>,
       pub expires_after_seconds: Option<u64>,  // 新增
   }
   ```

3. **添加使用限制**：
   ```rust
   pub struct RequestPermissionProfile {
       // ...
       pub max_uses: Option<u32>,  // 新增
   }
   ```

4. **支持更多权限类型**：
   - 环境变量访问
   - 系统调用权限
   - 外部程序执行权限

### 兼容性注意
- 使用 `#[serde(deny_unknown_fields)]` 确保严格模式，拒绝未知字段
- 使用 `Option<T>` 确保可选字段的灵活性
- 与核心协议类型的双向转换确保数据一致性

### 安全考虑
- 权限请求应明确展示给用户
- 避免自动授权敏感权限
- 记录权限授予历史
