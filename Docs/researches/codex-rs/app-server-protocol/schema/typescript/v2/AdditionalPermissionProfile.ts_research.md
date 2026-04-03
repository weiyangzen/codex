# AdditionalPermissionProfile.ts 研究文档

## 1. 场景与职责

`AdditionalPermissionProfile` 是**额外的权限配置组合类型**，用于在标准沙箱策略之外，为 Agent 授予额外的跨维度权限。它是文件系统、网络和 macOS 平台权限的统一容器。

### 使用场景
- **权限请求**: 当 Agent 需要超出默认沙箱的权限时，向用户发起权限请求
- **动态权限扩展**: 在会话期间根据任务需求动态申请额外权限
- **权限配置持久化**: 保存用户授权的额外权限配置
- **跨平台权限管理**: 统一处理不同平台的权限需求

### 职责
- 组合网络权限配置（`network`）
- 组合文件系统权限配置（`fileSystem`）
- 组合 macOS 平台权限配置（`macos`）
- 作为权限请求、审批和授予的统一数据结构

---

## 2. 功能点目的

### 2.1 统一权限配置容器

```typescript
export type AdditionalPermissionProfile = { 
  network: AdditionalNetworkPermissions | null,      // 网络权限
  fileSystem: AdditionalFileSystemPermissions | null, // 文件系统权限
  macos: AdditionalMacOsPermissions | null,          // macOS 平台权限
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `network` | `AdditionalNetworkPermissions \| null` | 额外的网络访问权限 |
| `fileSystem` | `AdditionalFileSystemPermissions \| null` | 额外的文件读写权限 |
| `macos` | `AdditionalMacOsPermissions \| null` | macOS 平台特定权限 |

### 2.3 设计意图

1. **模块化设计**: 每个权限维度独立，可以单独请求或授予
2. **平台抽象**: macOS 特定权限与其他权限分离，便于跨平台实现
3. **可选配置**: 使用 `null` 表示不请求/不授予该维度的额外权限
4. **统一接口**: 为权限请求和审批提供一致的接口

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AdditionalPermissionProfile {
  network: AdditionalNetworkPermissions | null;
  fileSystem: AdditionalFileSystemPermissions | null;
  macos: AdditionalMacOsPermissions | null;
}
```

### 3.2 依赖类型

**AdditionalNetworkPermissions**:
```typescript
export type AdditionalNetworkPermissions = { 
  enabled: boolean | null,
};
```

**AdditionalFileSystemPermissions**:
```typescript
export type AdditionalFileSystemPermissions = { 
  read: Array<AbsolutePathBuf> | null,
  write: Array<AbsolutePathBuf> | null,
};
```

**AdditionalMacOsPermissions**:
```typescript
export type AdditionalMacOsPermissions = { 
  preferences: MacOsPreferencesPermission,
  automations: MacOsAutomationPermission,
  launchServices: boolean,
  accessibility: boolean,
  calendar: boolean,
  reminders: boolean,
  contacts: MacOsContactsPermission,
};
```

### 3.3 Rust 源类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalPermissionProfile {
    pub network: Option<AdditionalNetworkPermissions>,
    pub file_system: Option<AdditionalFileSystemPermissions>,
    pub macos: Option<AdditionalMacOsPermissions>,
}

// 与 CorePermissionProfile 的转换
impl From<CorePermissionProfile> for AdditionalPermissionProfile {
    fn from(value: CorePermissionProfile) -> Self {
        Self {
            network: value.network.map(AdditionalNetworkPermissions::from),
            file_system: value.file_system.map(AdditionalFileSystemPermissions::from),
            macos: value.macos.map(AdditionalMacOsPermissions::from),
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（约第 1150-1177 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AdditionalPermissionProfile.ts` | 生成的 TypeScript 类型 |

### 4.2 类型依赖图

```
AdditionalPermissionProfile.ts
  ├── AdditionalFileSystemPermissions.ts
  │   └── AbsolutePathBuf.ts (../AbsolutePathBuf)
  ├── AdditionalMacOsPermissions.ts
  │   ├── MacOsAutomationPermission.ts (../MacOsAutomationPermission)
  │   ├── MacOsContactsPermission.ts (../MacOsContactsPermission)
  │   └── MacOsPreferencesPermission.ts (../MacOsPreferencesPermission)
  └── AdditionalNetworkPermissions.ts
```

### 4.3 使用位置

| 类型 | 用途 |
|------|------|
| `RequestPermissionProfile` | 权限请求的配置（不包含 macOS） |
| `PermissionsRequestApprovalParams` | 权限请求审批参数 |
| `SandboxPolicy` | 沙箱策略的权限扩展部分 |

### 4.4 权限请求流程

```
┌─────────────────────────────────────────────────────────────┐
│                    Permission Request Flow                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │   Agent     │───►│  Detects need for extra permissions │ │
│  │  Operation  │    │  (network/file/macos)               │ │
│  └─────────────┘    └─────────────────┬───────────────────┘ │
│                                       │                     │
│                                       ▼                     │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │    User     │◄───│  Build AdditionalPermissionProfile  │ │
│  │   Prompt    │    │  with requested permissions         │ │
│  └──────┬──────┘    └─────────────────────────────────────┘ │
│         │                                                   │
│         │ Approve/Deny                                      │
│         ▼                                                   │
│  ┌─────────────┐    ┌─────────────────────────────────────┐ │
│  │   Granted   │───►│  Apply to Sandbox Policy            │ │
│  │  Permission │    │  (Update Seatbelt/seccomp/etc.)     │ │
│  └─────────────┘    └─────────────────────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { AdditionalFileSystemPermissions } from "./AdditionalFileSystemPermissions";
import type { AdditionalMacOsPermissions } from "./AdditionalMacOsPermissions";
import type { AdditionalNetworkPermissions } from "./AdditionalNetworkPermissions";
```

### 5.2 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                    Permission System                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │         AdditionalPermissionProfile                  │  │
│   │  ┌─────────────┐ ┌─────────────┐ ┌────────────────┐ │  │
│   │  │   Network   │ │ File System │ │     macOS      │ │  │
│   │  │  (enabled)  │ │(read/write) │ │(prefs/auto/   │ │  │
│   │  │             │ │             │ │ calendar/etc.) │ │  │
│   │  └──────┬──────┘ └──────┬──────┘ └───────┬────────┘ │  │
│   └─────────┼───────────────┼────────────────┼──────────┘  │
│             │               │                │             │
│             ▼               ▼                ▼             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              Platform Sandbox Layer                  │  │
│   │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │  │
│   │  │Seatbelt │  │Landlock │  │seccomp  │  │Windows │ │  │
│   │  │ (macOS) │  │(Linux)  │  │(Linux)  │  │Sandbox │ │  │
│   │  └─────────┘  └─────────┘  └─────────┘  └────────┘ │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 序列化示例

**完整权限请求:**
```json
{
  "network": {
    "enabled": true
  },
  "fileSystem": {
    "read": ["/home/user/documents"],
    "write": ["/home/user/workspace"]
  },
  "macos": {
    "preferences": "read",
    "automations": "whitelist",
    "launchServices": true,
    "accessibility": false,
    "calendar": false,
    "reminders": false,
    "contacts": "none"
  }
}
```

**仅网络权限:**
```json
{
  "network": {
    "enabled": true
  },
  "fileSystem": null,
  "macos": null
}
```

**无额外权限:**
```json
{
  "network": null,
  "fileSystem": null,
  "macos": null
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 权限扩散 | 用户可能过度授权 | UI 明确展示每个权限的具体影响 |
| 平台差异 | macOS 权限在其他平台无意义 | 客户端根据平台过滤显示 |
| 权限持久化 | 授权后难以追踪和撤销 | 提供权限管理界面 |
| 组合复杂性 | 三个维度的组合可能产生意外行为 | 充分测试各种组合 |

### 6.2 边界情况

1. **部分授权**: 用户可能只同意部分权限请求
2. **权限降级**: 已授权权限被后续操作限制
3. **平台不支持**: 某些权限在特定平台不可用
4. **空配置**: 所有字段为 `null` 表示无额外权限

### 6.3 改进建议

1. **添加时间限制**: 支持临时权限授权
   ```typescript
   export type AdditionalPermissionProfile = { 
     network: AdditionalNetworkPermissions | null;
     fileSystem: AdditionalFileSystemPermissions | null;
     macos: AdditionalMacOsPermissions | null;
     expiresAt?: number;  // 权限过期时间
   };
   ```

2. **权限理由**: 说明为什么需要这些权限
   ```typescript
   reason?: string;  // 用户友好的权限申请理由
   ```

3. **权限来源**: 追踪权限的来源
   ```typescript
   source?: {
     type: "user" | "policy" | "default";
     timestamp: number;
   };
   ```

4. **细粒度撤销**: 支持单独撤销某个维度的权限
   ```typescript
   // 添加撤销方法
   revokePermission(dimension: "network" | "fileSystem" | "macos"): void;
   ```

5. **权限模板**: 预定义的常用权限组合
   ```typescript
   export const PERMISSION_TEMPLATES = {
     webDevelopment: { /* ... */ },
     dataAnalysis: { /* ... */ },
     systemAdmin: { /* ... */ },
   };
   ```

### 6.4 与相关类型的关系

| 类型 | 关系 | 区别 |
|------|------|------|
| `RequestPermissionProfile` | 相似 | 不包含 macOS 权限，用于请求阶段 |
| `GrantedPermissionProfile` | 子集 | 仅包含网络和文件系统，用于已授予的权限 |
| `SandboxPolicy` | 使用 | 将 AdditionalPermissionProfile 应用到沙箱策略 |

### 6.5 测试建议

- 各种权限组合的序列化/反序列化
- 部分授权场景的处理
- 权限应用到沙箱的正确性
- 跨平台兼容性（macOS vs Linux vs Windows）
- 权限过期和撤销
- 大量权限条目的性能
