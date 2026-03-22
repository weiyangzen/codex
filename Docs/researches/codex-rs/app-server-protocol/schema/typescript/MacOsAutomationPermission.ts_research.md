# MacOsAutomationPermission Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`MacOsAutomationPermission` 是 Codex 中用于控制 macOS 自动化权限的枚举类型。它定义了应用可以自动化控制其他 macOS 应用的权限级别，是 macOS Seatbelt 沙盒配置的一部分。

主要使用场景：
- **权限配置**：在配置文件中指定自动化权限级别
- **沙盒策略**：作为 `MacOsSeatbeltProfileExtensions` 的一部分
- **安全控制**：限制应用控制其他应用的能力
- **用户授权**：请求用户授权控制特定应用

## 2. 功能点目的 (Purpose of This Type)

- **权限分级**：提供从完全禁止到完全允许的权限级别
- **细粒度控制**：支持指定允许控制的具体应用 Bundle ID
- **安全默认**：默认无权限，需要显式授权
- **配置灵活**：支持多种配置方式（字符串、数组、对象）

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构

```typescript
// TypeScript 定义（由 ts-rs 生成）
export type MacOsAutomationPermission = 
  | "none" 
  | "all" 
  | { "bundle_ids": Array<string> };
```

```rust
// Rust 定义
#[derive(Debug, Clone, PartialEq, Eq, Default, Hash, Serialize, Deserialize, JsonSchema, TS)]
#[serde(rename_all = "snake_case", try_from = "MacOsAutomationPermissionDe")]
pub enum MacOsAutomationPermission {
    #[default]
    None,
    All,
    BundleIds(Vec<String>),
}

// 反序列化辅助枚举
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum MacOsAutomationPermissionDe {
    Mode(String),
    BundleIds(Vec<String>),
    BundleIdsObject { bundle_ids: Vec<String> },
}

impl TryFrom<MacOsAutomationPermissionDe> for MacOsAutomationPermission {
    type Error = String;

    /// Accepts one of:
    /// - `"none"` or `"all"`
    /// - a plain list of bundle IDs, e.g. `["com.apple.Notes"]`
    /// - an object with bundle IDs, e.g. `{"bundle_ids": ["com.apple.Notes"]}`
    fn try_from(value: MacOsAutomationPermissionDe) -> Result<Self, Self::Error> {
        // ...
    }
}
```

### 变体说明

| 变体 | TypeScript 表示 | 说明 |
|-----|----------------|------|
| `None` | `"none"` | 禁止所有自动化操作（默认） |
| `All` | `"all"` | 允许自动化控制所有应用 |
| `BundleIds` | `{ bundle_ids: string[] }` | 仅允许控制指定 Bundle ID 的应用 |

### 支持的配置格式

```json
// 字符串模式
"none"
"all"

// 数组模式（简写）
["com.apple.Notes", "com.apple.Mail"]

// 对象模式（完整）
{ "bundle_ids": ["com.apple.Notes", "com.apple.Mail"] }
```

### 使用位置

```rust
// 在 MacOsSeatbeltProfileExtensions 中使用
#[derive(Debug, Clone, PartialEq, Eq, Default, Hash, Serialize, Deserialize, JsonSchema, TS)]
#[serde(default)]
pub struct MacOsSeatbeltProfileExtensions {
    #[serde(alias = "preferences")]
    pub macos_preferences: MacOsPreferencesPermission,
    #[serde(alias = "automations")]
    pub macos_automation: MacOsAutomationPermission,
    #[serde(alias = "launch_services")]
    pub macos_launch_services: bool,
    #[serde(alias = "accessibility")]
    pub macos_accessibility: bool,
    #[serde(alias = "calendar")]
    pub macos_calendar: bool,
    #[serde(alias = "reminders")]
    pub macos_reminders: bool,
    #[serde(alias = "contacts")]
    pub macos_contacts: MacOsContactsPermission,
}

// 在 PermissionProfile 中使用
pub struct PermissionProfile {
    pub network: Option<NetworkPermissions>,
    pub file_system: Option<FileSystemPermissions>,
    pub macos: Option<MacOsSeatbeltProfileExtensions>,
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

| 文件路径 | 说明 |
|---------|------|
| `/codex-rs/protocol/src/models.rs` (lines 136-191) | Rust 枚举定义和反序列化实现 |
| `/codex-rs/app-server-protocol/schema/typescript/MacOsAutomationPermission.ts` | TypeScript 类型定义（生成） |

### 相关类型

- `MacOsSeatbeltProfileExtensions`：包含自动化权限的扩展配置
- `MacOsPreferencesPermission`：偏好设置权限
- `MacOsContactsPermission`：通讯录权限
- `PermissionProfile`：权限配置文件

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 依赖项

- `serde`：序列化/反序列化，使用自定义 `try_from` 反序列化
- `ts_rs::TS`：TypeScript 类型生成
- `schemars::JsonSchema`：JSON Schema 生成

### 反序列化逻辑

```rust
impl TryFrom<MacOsAutomationPermissionDe> for MacOsAutomationPermission {
    type Error = String;

    fn try_from(value: MacOsAutomationPermissionDe) -> Result<Self, Self::Error> {
        let permission = match value {
            MacOsAutomationPermissionDe::Mode(value) => {
                let normalized = value.trim().to_ascii_lowercase();
                if normalized == "all" {
                    MacOsAutomationPermission::All
                } else if normalized == "none" {
                    MacOsAutomationPermission::None
                } else {
                    return Err(format!(
                        "invalid macOS automation permission: {value}; expected none, all, or bundle ids"
                    ));
                }
            }
            MacOsAutomationPermissionDe::BundleIds(bundle_ids)
            | MacOsAutomationPermissionDe::BundleIdsObject { bundle_ids } => {
                let bundle_ids = bundle_ids
                    .into_iter()
                    .map(|bundle_id| bundle_id.trim().to_string())
                    .filter(|bundle_id| !bundle_id.is_empty())
                    .collect::<Vec<String>>();
                if bundle_ids.is_empty() {
                    MacOsAutomationPermission::None
                } else {
                    MacOsAutomationPermission::BundleIds(bundle_ids)
                }
            }
        };

        Ok(permission)
    }
}
```

### 配置示例

```json
{
  "macos": {
    "macos_automation": {
      "bundle_ids": ["com.apple.Notes", "com.apple.Mail"]
    }
  }
}
```

或使用别名：
```json
{
  "macos": {
    "automations": ["com.apple.Notes"]
  }
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **安全风险**：`All` 权限允许控制任何应用，包括系统应用
2. **用户体验**：需要用户手动在系统设置中授权
3. **Bundle ID 验证**：不验证 Bundle ID 是否有效
4. **大小写敏感**：Bundle ID 通常区分大小写

### 改进建议

1. **添加验证方法**：
   ```rust
   impl MacOsAutomationPermission {
       pub fn validate_bundle_ids(&self) -> Result<(), ValidationError> {
           // 验证 Bundle ID 格式（反向域名格式）
       }
       
       pub fn is_allowed(&self, bundle_id: &str) -> bool {
           match self {
               Self::None => false,
               Self::All => true,
               Self::BundleIds(allowed) => allowed.contains(bundle_id),
           }
       }
   }
   ```

2. **添加常用 Bundle ID 常量**：
   ```rust
   pub const NOTES: &str = "com.apple.Notes";
   pub const MAIL: &str = "com.apple.Mail";
   pub const SAFARI: &str = "com.apple.Safari";
   ```

3. **添加权限描述**：
   ```rust
   pub fn description(&self) -> &'static str {
       match self {
           Self::None => "No automation access",
           Self::All => "Full automation access to all applications",
           Self::BundleIds(_) => "Automation access to specific applications",
       }
   }
   ```

4. **考虑添加通配符支持**：
   ```rust
   BundleIds(vec!["com.apple.*".to_string()])  // 允许所有 Apple 应用
   ```

### 测试建议

- 测试各种配置格式的反序列化
- 测试大小写不敏感的 "none" 和 "all"
- 测试空 Bundle ID 列表的处理
- 测试重复的 Bundle ID
- 验证与 Seatbelt 配置文件的集成

### 安全最佳实践

- 默认使用 `None`，遵循最小权限原则
- 仅在必要时使用 `All`
- 优先使用具体的 Bundle ID 列表
- 向用户明确说明授权的影响
- 在 UI 中提供清晰的权限说明
