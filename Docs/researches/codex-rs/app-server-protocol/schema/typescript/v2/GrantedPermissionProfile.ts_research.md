# GrantedPermissionProfile.ts Research Document

## 场景与职责

`GrantedPermissionProfile` 类型定义了用户或系统授予的权限配置文件，用于控制 AI 助手在代码执行过程中的访问能力。该类型在以下核心场景中发挥作用：

1. **权限请求与授权**：当 AI 需要执行敏感操作（如网络访问、文件系统写入）时，系统会请求用户授权，并将授权结果封装在此类型中。

2. **权限范围界定**：明确界定 AI 在特定会话或操作中的权限边界，实现最小权限原则。

3. **权限持久化**：将授权决策持久化存储，支持跨会话的权限记忆和审计。

4. **动态权限调整**：支持在会话过程中动态调整已授予的权限。

## 功能点目的

`GrantedPermissionProfile` 的设计目的是：

- **安全控制**：为 AI 操作建立明确的安全边界，防止未授权访问
- **用户主权**：将敏感操作的最终决策权交还给用户
- **细粒度授权**：支持按权限类型（网络、文件系统）分别授权
- **灵活配置**：通过可选字段支持部分授权场景

所有字段均为可选（`?`），支持以下使用模式：
- 仅授予网络权限
- 仅授予文件系统权限
- 同时授予网络和文件系统权限
- 不授予任何权限（空对象）

## 具体技术实现

### 数据结构定义

```typescript
import type { AdditionalFileSystemPermissions } from "./AdditionalFileSystemPermissions";
import type { AdditionalNetworkPermissions } from "./AdditionalNetworkPermissions";

export type GrantedPermissionProfile = { 
  network?: AdditionalNetworkPermissions,   // 网络访问权限配置
  fileSystem?: AdditionalFileSystemPermissions  // 文件系统访问权限配置
};
```

### 关键字段说明

| 字段名 | 类型 | 可选性 | 说明 |
|--------|------|--------|------|
| `network` | `AdditionalNetworkPermissions` | 可选 (`?`) | 定义 AI 的网络访问权限。包含 `enabled` 布尔字段控制是否允许网络访问。省略表示不授予网络权限。 |
| `fileSystem` | `AdditionalFileSystemPermissions` | 可选 (`?`) | 定义 AI 的文件系统访问权限。包含 `read` 和 `write` 数组字段，分别指定可读写的路径列表。省略表示不授予文件系统权限。 |

### 嵌套类型详情

#### AdditionalNetworkPermissions
```typescript
export type AdditionalNetworkPermissions = { 
  enabled: boolean | null  // 是否启用网络访问
};
```

#### AdditionalFileSystemPermissions
```typescript
export type AdditionalFileSystemPermissions = { 
  read: Array<AbsolutePathBuf> | null,   // 允许读取的路径列表
  write: Array<AbsolutePathBuf> | null   // 允许写入的路径列表
};
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/GrantedPermissionProfile.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 1179-1199 行)

### Rust 实现细节

```rust
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

impl From<GrantedPermissionProfile> for CorePermissionProfile {
    fn from(value: GrantedPermissionProfile) -> Self {
        Self {
            network: value.network.map(CoreNetworkPermissions::from),
            file_system: value.file_system.map(CoreFileSystemPermissions::from),
            macos: None,  // macOS 特定权限在 v2 API 中暂不支持
        }
    }
}
```

### 使用位置

1. **PermissionsRequestApprovalResponse**（第 5627 行）：权限请求批准的响应体
   ```rust
   pub struct PermissionsRequestApprovalResponse {
       pub permissions: GrantedPermissionProfile,
       pub scope: PermissionGrantScope,
   }
   ```

## 依赖与外部交互

### 上游依赖

- `AdditionalNetworkPermissions`：网络权限的具体配置
- `AdditionalFileSystemPermissions`：文件系统权限的具体配置
- `AbsolutePathBuf`：文件系统路径的类型安全封装

### 下游消费者

- **核心协议层** (`CorePermissionProfile`)：v2 API 权限配置会转换为内部核心协议格式
- **权限管理器**：根据此配置控制 AI 的实际访问能力
- **审计系统**：记录授权决策用于合规审计

### 序列化行为

- 使用 `#[serde(default, skip_serializing_if = "Option::is_none")]` 确保省略的字段不会被序列化
- TypeScript 端使用 `#[ts(optional)]` 标记可选字段
- JSON 传输使用 camelCase 命名

## 风险、边界与改进建议

### 潜在风险

1. **权限扩散**：用户可能无意中授予过于宽泛的权限（如 `/` 目录的写权限）
2. **权限持久化风险**：持久化的权限可能在代码库结构变更后变得过时或危险
3. **路径遍历攻击**：如果路径验证不严格，可能存在路径遍历漏洞
4. **权限升级**：通过符号链接等手段可能实现权限升级

### 边界情况

1. **空权限对象**：`{}` 表示不授予任何额外权限，但基础权限可能仍然存在
2. **部分权限**：仅授予 `network` 或仅授予 `fileSystem` 的合法场景
3. **路径不存在**：授权时指定的路径可能在实际访问时已不存在
4. **相对路径**：`AbsolutePathBuf` 确保路径绝对化，但需验证转换逻辑
5. **跨平台路径**：Windows 和 Unix 路径格式的兼容性处理

### 改进建议

1. **权限模板**：预定义常用权限模板（如 "只读项目目录"、"完全访问"）
2. **权限时效**：添加权限有效期，支持临时授权
3. **路径验证**：增强路径验证，防止目录遍历攻击
4. **权限继承**：支持权限继承和覆盖机制
5. **可视化展示**：提供权限影响的直观可视化
6. **权限变更通知**：当权限配置变更时通知用户
7. **macOS 支持**：当前 `macos` 字段被硬编码为 `None`，应实现完整的 macOS 权限支持

### 安全最佳实践

1. **最小权限原则**：默认拒绝所有权限，按需逐步授予
2. **路径白名单**：严格限制可访问路径，避免通配符
3. **定期审计**：定期审查和清理已授予的权限
4. **敏感操作确认**：对于高风险操作（如删除、网络请求），即使已授权也应二次确认

### 兼容性注意事项

- 该类型与核心协议层的 `CorePermissionProfile` 存在映射关系
- `macos` 权限在 v2 API 中暂不支持，转换时设为 `None`
- 类型由 `ts-rs` 自动生成，手动修改会被覆盖
