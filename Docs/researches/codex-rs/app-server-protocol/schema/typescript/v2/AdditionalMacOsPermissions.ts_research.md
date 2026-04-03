# AdditionalMacOsPermissions.ts 研究文档

## 1. 场景与职责

`AdditionalMacOsPermissions` 定义了 **macOS 平台特有的额外权限配置**，用于控制 Agent 在 macOS 系统上的特殊功能访问权限。这些权限涉及系统级功能，需要用户显式授权。

### 使用场景
- **自动化权限**: 控制 Agent 是否可以控制其他 macOS 应用程序（AppleScript、Accessibility）
- **隐私数据访问**: 访问日历、提醒事项、通讯录等敏感数据
- **系统偏好设置**: 修改系统偏好设置
- **启动服务**: 访问 LaunchServices 注册的应用程序信息

### 职责
- 定义 macOS 偏好设置权限级别
- 定义自动化权限级别（控制其他应用）
- 定义启动服务访问权限
- 定义辅助功能（Accessibility）权限
- 定义日历、提醒事项、通讯录访问权限

---

## 2. 功能点目的

### 2.1 macOS 平台权限控制

```typescript
export type AdditionalMacOsPermissions = { 
  preferences: MacOsPreferencesPermission,     // 系统偏好设置权限
  automations: MacOsAutomationPermission,      // 自动化权限（控制其他应用）
  launchServices: boolean,                     // LaunchServices 访问
  accessibility: boolean,                      // 辅助功能权限
  calendar: boolean,                           // 日历访问
  reminders: boolean,                          // 提醒事项访问
  contacts: MacOsContactsPermission,           // 通讯录权限
};
```

### 2.2 字段语义

| 字段 | 类型 | 说明 |
|------|------|------|
| `preferences` | `MacOsPreferencesPermission` | 系统偏好设置读写级别：`"none"`, `"read"`, `"write"` |
| `automations` | `MacOsAutomationPermission` | 自动化控制级别：`"none"`, `"whitelist"`, `"all"` |
| `launchServices` | `boolean` | 是否允许访问 LaunchServices |
| `accessibility` | `boolean` | 是否允许使用 Accessibility API |
| `calendar` | `boolean` | 是否允许访问日历 |
| `reminders` | `boolean` | 是否允许访问提醒事项 |
| `contacts` | `MacOsContactsPermission` | 通讯录访问级别：`"none"`, `"read"` |

### 2.3 设计意图

1. **平台特定**: 专门针对 macOS 的安全和隐私模型设计
2. **分层权限**: 不同功能使用不同的权限级别（布尔值或枚举）
3. **用户控制**: 所有权限都需要用户显式授权，符合 macOS 隐私规范

---

## 3. 具体技术实现

### 3.1 数据结构

```typescript
interface AdditionalMacOsPermissions {
  preferences: "none" | "read" | "write";
  automations: "none" | "whitelist" | "all";
  launchServices: boolean;
  accessibility: boolean;
  calendar: boolean;
  reminders: boolean;
  contacts: "none" | "read";
}
```

### 3.2 依赖类型

**MacOsPreferencesPermission**:
```typescript
export type MacOsPreferencesPermission = "none" | "read" | "write";
```

**MacOsAutomationPermission**:
```typescript
export type MacOsAutomationPermission = "none" | "whitelist" | "all";
```

**MacOsContactsPermission**:
```typescript
export type MacOsContactsPermission = "none" | "read";
```

### 3.3 Rust 源类型

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AdditionalMacOsPermissions {
    pub preferences: CoreMacOsPreferencesPermission,
    pub automations: CoreMacOsAutomationPermission,
    pub launch_services: bool,
    pub accessibility: bool,
    pub calendar: bool,
    pub reminders: bool,
    pub contacts: CoreMacOsContactsPermission,
}

// 与 CoreMacOsSeatbeltProfileExtensions 的转换
impl From<CoreMacOsSeatbeltProfileExtensions> for AdditionalMacOsPermissions {
    fn from(value: CoreMacOsSeatbeltProfileExtensions) -> Self {
        Self {
            preferences: value.macos_preferences,
            automations: value.macos_automation,
            launch_services: value.macos_launch_services,
            accessibility: value.macos_accessibility,
            calendar: value.macos_calendar,
            reminders: value.macos_reminders,
            contacts: value.macos_contacts,
        }
    }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（约第 1059-1098 行） |
| `codex-rs/app-server-protocol/schema/typescript/v2/AdditionalMacOsPermissions.ts` | 生成的 TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/typescript/MacOsPreferencesPermission.ts` | 偏好设置权限枚举 |
| `codex-rs/app-server-protocol/schema/typescript/MacOsAutomationPermission.ts` | 自动化权限枚举 |
| `codex-rs/app-server-protocol/schema/typescript/MacOsContactsPermission.ts` | 通讯录权限枚举 |

### 4.2 类型依赖图

```
AdditionalMacOsPermissions.ts
  ├── MacOsAutomationPermission.ts (../MacOsAutomationPermission)
  ├── MacOsContactsPermission.ts (../MacOsContactsPermission)
  └── MacOsPreferencesPermission.ts (../MacOsPreferencesPermission)
```

### 4.3 使用位置

| 类型 | 用途 |
|------|------|
| `AdditionalPermissionProfile` | 完整额外权限配置的 macOS 部分 |
| `SandboxPolicy` | macOS 沙箱策略扩展 |

### 4.4 macOS 权限系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS Security Layer                     │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │  TCC (Transparency,        │  │  Seatbelt Sandbox   │ │
│  │   Consent, Control)        │  │  (Profile Extensions)│ │
│  │   - Privacy Database       │  │                     │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
│         └────────────────┼────────────────────┘            │
│                          ▼                                 │
│         ┌─────────────────────────────────┐                │
│         │ AdditionalMacOsPermissions      │                │
│         │ (Protocol Layer Definition)     │                │
│         └─────────────────────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. 依赖与外部交互

### 5.1 类型依赖

```typescript
import type { MacOsAutomationPermission } from "../MacOsAutomationPermission";
import type { MacOsContactsPermission } from "../MacOsContactsPermission";
import type { MacOsPreferencesPermission } from "../MacOsPreferencesPermission";
```

### 5.2 外部系统交互

```
┌─────────────────────────────────────────────────────────────┐
│                      User Interaction                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ System      │  │ Application │  │ Agent Request       │ │
│  │ Preferences │  │ Prompt      │  │ (via Protocol)      │ │
│  │ Dialogs     │  │             │  │                     │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                    │            │
└─────────┼────────────────┼────────────────────┼────────────┘
          │                │                    │
          ▼                ▼                    ▼
┌─────────────────────────────────────────────────────────────┐
│                    Codex App-Server                          │
│         ┌─────────────────────────────────┐                  │
│         │ AdditionalMacOsPermissions      │                  │
│         │ (Permission Definition)         │                  │
│         └─────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Seatbelt Profile                          │
│         (Sandbox Extension Configuration)                    │
└─────────────────────────────────────────────────────────────┘
```

### 5.3 序列化示例

**最小权限:**
```json
{
  "preferences": "none",
  "automations": "none",
  "launchServices": false,
  "accessibility": false,
  "calendar": false,
  "reminders": false,
  "contacts": "none"
}
```

**完整权限:**
```json
{
  "preferences": "write",
  "automations": "all",
  "launchServices": true,
  "accessibility": true,
  "calendar": true,
  "reminders": true,
  "contacts": "read"
}
```

**典型开发场景:**
```json
{
  "preferences": "read",
  "automations": "whitelist",
  "launchServices": true,
  "accessibility": false,
  "calendar": false,
  "reminders": false,
  "contacts": "none"
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| TCC 提示疲劳 | 频繁请求权限导致用户习惯性允许 | 批量请求权限，清晰说明用途 |
| 权限持久化 | macOS 记住用户选择后难以撤销 | 提供权限管理指引 |
| 自动化滥用 | `automations: "all"` 可控制任意应用 | 默认使用 `"whitelist"`，明确列出目标应用 |
| 隐私泄露 | `contacts: "read"` 可获取全部联系人 | 最小化权限范围，及时清理 |

### 6.2 边界情况

1. **权限降级**: 用户撤销已授权权限后的行为
2. **TCC 数据库损坏**: 系统级权限数据库异常的处理
3. **企业 MDM**: 受管设备上的权限限制
4. **沙箱冲突**: Seatbelt 与 TCC 权限的交集和冲突

### 6.3 改进建议

1. **添加应用白名单**: 细化自动化权限的目标应用
   ```typescript
   automations: {
     level: "whitelist";
     allowedApps: string[];  // Bundle IDs
   } | {
     level: "none" | "all";
   };
   ```

2. **权限有效期**: 支持临时授权
   ```typescript
   expiresAt?: number;  // Unix timestamp
   ```

3. **权限使用审计**: 记录敏感权限的使用
   ```typescript
   audit?: {
     logAccess: boolean;
     notifyUser: boolean;
   };
   ```

4. **权限预检**: 在请求前检查当前授权状态
   ```typescript
   // 添加新的查询方法
   checkMacOsPermissions(): Promise<AdditionalMacOsPermissions>;
   ```

5. **分组权限**: 按功能场景分组请求
   ```typescript
   export type MacOsPermissionGroup = 
     | "productivity"  // calendar + reminders
     | "communication" // contacts
     | "system"        // preferences + accessibility
     | "automation";   // automations + launchServices
   ```

### 6.4 测试建议

- 各种权限组合的序列化/反序列化
- TCC 权限被拒绝时的优雅降级
- 权限变更后的实时响应
- 沙箱策略的正确生成
- 与 macOS 版本兼容性（不同版本的 TCC 行为）
- 企业环境（MDM 托管）下的权限管理
