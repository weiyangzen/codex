# ExperimentalFeatureListResponse.json 研究文档

## 场景与职责

`ExperimentalFeatureListResponse.json` 是 Codex app-server-protocol v2 API 的 JSON Schema 文件，定义了获取实验性功能列表的响应数据结构。该文件位于 `codex-rs/app-server-protocol/schema/json/v2/` 目录下，与 `ExperimentalFeatureListParams.json` 配对使用，构成完整的分页查询 API。

**使用场景**：
- 服务器响应客户端的实验性功能列表请求
- 提供功能标志（Feature Flags）的完整元数据
- 支持功能生命周期管理（从开发到弃用）
- 客户端根据响应数据渲染实验性功能管理界面

**核心职责**：
- 定义实验性功能的数据结构（`ExperimentalFeature`）
- 定义功能生命周期阶段（`ExperimentalFeatureStage`）
- 支持分页响应（`data` 数组和 `nextCursor`）
- 提供功能启用状态和默认状态信息

## 功能点目的

### 1. 实验性功能数据结构

#### 1.1 ExperimentalFeature

```json
{
  "name": "feature-key",
  "stage": "beta",
  "displayName": "用户可见名称",
  "description": "功能描述",
  "announcement": "发布公告文案",
  "enabled": true,
  "defaultEnabled": false
}
```

**字段说明**：

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 稳定键名，用于 config.toml 和 CLI 标志 |
| `stage` | ExperimentalFeatureStage | 是 | 功能生命周期阶段 |
| `displayName` | string\|null | 否 | 用户界面显示名称（beta 阶段必需） |
| `description` | string\|null | 否 | 功能简短描述（beta 阶段必需） |
| `announcement` | string\|null | 否 | 发布公告文案（beta 阶段必需） |
| `enabled` | boolean | 是 | 当前配置中是否启用 |
| `defaultEnabled` | boolean | 是 | 默认是否启用 |

#### 1.2 功能生命周期阶段（ExperimentalFeatureStage）

```json
{
  "stage": {
    "oneOf": [
      { "enum": ["beta"], "description": "Feature is available for user testing and feedback." },
      { "enum": ["underDevelopment"], "description": "Feature is still being built and not ready for broad use." },
      { "enum": ["stable"], "description": "Feature is production-ready." },
      { "enum": ["deprecated"], "description": "Feature is deprecated and should be avoided." },
      { "enum": ["removed"], "description": "Feature flag is retained only for backwards compatibility." }
    ]
  }
}
```

**阶段说明**：

| 阶段 | 英文 | 说明 |
|------|------|------|
| 内测 | `beta` | 可供用户测试和反馈 |
| 开发中 | `underDevelopment` | 仍在开发中，不适合广泛使用 |
| 稳定 | `stable` | 生产就绪 |
| 已弃用 | `deprecated` | 已弃用，应避免使用 |
| 已移除 | `removed` | 仅保留标志以兼容旧版本 |

### 2. 响应结构设计

#### 2.1 分页响应

```json
{
  "data": [...],
  "nextCursor": "opaque-cursor-string"
}
```

**设计目的**：
- `data`: 当前页的实验性功能数组
- `nextCursor`: 下一页游标，null 表示没有更多数据
- 与 `ExperimentalFeatureListParams` 的 `cursor` 和 `limit` 配对使用

#### 2.2 阶段相关字段的可空性

注意到 `displayName`、`description`、`announcement` 在 schema 中定义为可为 null，且描述中注明 "Null when this feature is not in beta"。这体现了以下设计决策：

- **beta 阶段**：需要提供完整的用户-facing 信息
- **其他阶段**：可能不需要展示信息（如开发中、已弃用）

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ExperimentalFeature": {
      "properties": {
        "announcement": { "type": ["string", "null"] },
        "defaultEnabled": { "type": "boolean" },
        "description": { "type": ["string", "null"] },
        "displayName": { "type": ["string", "null"] },
        "enabled": { "type": "boolean" },
        "name": { "type": "string" },
        "stage": { "$ref": "#/definitions/ExperimentalFeatureStage" }
      },
      "required": ["defaultEnabled", "enabled", "name", "stage"],
      "type": "object"
    },
    "ExperimentalFeatureStage": {
      "oneOf": [
        { "enum": ["beta"], "type": "string" },
        { "enum": ["underDevelopment"], "type": "string" },
        { "enum": ["stable"], "type": "string" },
        { "enum": ["deprecated"], "type": "string" },
        { "enum": ["removed"], "type": "string" }
      ]
    }
  },
  "properties": {
    "data": {
      "items": { "$ref": "#/definitions/ExperimentalFeature" },
      "type": "array"
    },
    "nextCursor": { "type": ["string", "null"] }
  },
  "required": ["data"],
  "type": "object"
}
```

### Rust 数据结构

#### ExperimentalFeatureStage 枚举

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ExperimentalFeatureStage {
    /// Feature is available for user testing and feedback.
    Beta,
    /// Feature is still being built and not ready for broad use.
    UnderDevelopment,
    /// Feature is production-ready.
    Stable,
    /// Feature is deprecated and should be avoided.
    Deprecated,
    /// Feature flag is retained only for backwards compatibility.
    Removed,
}
```

#### ExperimentalFeature 结构体

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExperimentalFeature {
    /// Stable key used in config.toml and CLI flag toggles.
    pub name: String,
    /// Lifecycle stage of this feature flag.
    pub stage: ExperimentalFeatureStage,
    /// User-facing display name shown in the experimental features UI.
    /// Null when this feature is not in beta.
    pub display_name: Option<String>,
    /// Short summary describing what the feature does.
    /// Null when this feature is not in beta.
    pub description: Option<String>,
    /// Announcement copy shown to users when the feature is introduced.
    /// Null when this feature is not in beta.
    pub announcement: Option<String>,
    /// Whether this feature is currently enabled in the loaded config.
    pub enabled: bool,
    /// Whether this feature is enabled by default.
    pub default_enabled: bool,
}
```

#### ExperimentalFeatureListResponse 结构体

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExperimentalFeatureListResponse {
    pub data: Vec<ExperimentalFeature>,
    /// Opaque cursor to pass to the next call to continue after the last item.
    /// If None, there are no more items to return.
    pub next_cursor: Option<String>,
}
```

### 序列化行为

```rust
// 序列化示例
let feature = ExperimentalFeature {
    name: "granular-approval".to_string(),
    stage: ExperimentalFeatureStage::Beta,
    display_name: Some("Granular Approval".to_string()),
    description: Some("Fine-grained approval controls".to_string()),
    announcement: Some("New: Granular approval is now in beta!".to_string()),
    enabled: true,
    default_enabled: false,
};

// JSON 输出
{
  "name": "granular-approval",
  "stage": "beta",
  "displayName": "Granular Approval",
  "description": "Fine-grained approval controls",
  "announcement": "New: Granular approval is now in beta!",
  "enabled": true,
  "defaultEnabled": false
}
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ExperimentalFeatureListResponse.json` | JSON Schema 定义（本文件） |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 数据结构定义（第 1847-1894 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求/响应注册 |

### 代码位置详情

```rust
// v2.rs 中的定义位置
pub enum ExperimentalFeatureStage { ... }          // 第 1850-1861 行
pub struct ExperimentalFeature { ... }             // 第 1866-1884 行
pub struct ExperimentalFeatureListResponse { ... } // 第 1889-1894 行
```

### API 注册

在 `common.rs` 中：

```rust
ExperimentalFeatureList => "experimentalFeature/list" {
    params: v2::ExperimentalFeatureListParams,
    response: v2::ExperimentalFeatureListResponse,
}
```

### 与实验性 API 属性的关系

该 API 本身不是实验性的（没有 `#[experimental(...)]` 属性），但返回的数据描述了其他实验性功能的状态。这与 `#[experimental(...)]` 属性系统形成互补：

```rust
// 示例：其他结构体上的实验性标记
#[experimental("askForApproval.granular")]
Granular { ... },

#[experimental("config/read.approvalsReviewer")]
pub approvals_reviewer: Option<ApprovalsReviewer>,
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `serde` | 序列化和反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 外部交互

**完整的请求-响应流程**：

```json
// 客户端请求
{
  "method": "experimentalFeature/list",
  "id": 1,
  "params": {
    "cursor": null,
    "limit": 10
  }
}

// 服务器响应
{
  "id": 1,
  "result": {
    "data": [
      {
        "name": "askForApproval.granular",
        "stage": "beta",
        "displayName": "Granular Approval",
        "description": "Fine-grained control over approval prompts",
        "announcement": "Granular approval is now available for testing",
        "enabled": true,
        "defaultEnabled": false
      },
      {
        "name": "thread/realtime",
        "stage": "underDevelopment",
        "displayName": null,
        "description": null,
        "announcement": null,
        "enabled": false,
        "defaultEnabled": false
      }
    ],
    "nextCursor": "eyJsYXN0X2lkIjogMn0="
  }
}
```

### 与配置系统的集成

实验性功能的启用状态通常来自配置系统：

```toml
# config.toml 示例
[experimental]
askForApproval.granular = true
thread.realtime = false
```

服务器需要：
1. 解析配置确定 `enabled` 值
2. 维护功能定义确定 `default_enabled` 值
3. 根据代码中的属性确定 `stage` 值

## 风险、边界与改进建议

### 潜在风险

1. **阶段信息不一致**
   - `stage` 字段与实际的 `#[experimental(...)]` 属性可能不同步
   - 需要确保代码中的属性与 API 返回的阶段一致

2. **可空字段的语义**
   - `displayName`、`description`、`announcement` 在 beta 阶段应该非 null
   - 但 schema 允许它们为 null，可能导致 UI 显示问题
   - 建议添加验证逻辑

3. **布尔字段的歧义**
   - `enabled` 和 `defaultEnabled` 可能让客户端困惑
   - 需要清晰的文档说明两者的区别

4. **分页数据一致性**
   - 如果功能列表在分页查询间发生变化，可能导致数据不一致
   - 游标应包含版本信息或快照 ID

### 边界情况

1. **空列表**
   ```json
   { "data": [], "nextCursor": null }
   ```
   - 表示没有实验性功能
   - 或所有功能都不符合过滤条件

2. **单页完整数据**
   ```json
   { "data": [...], "nextCursor": null }
   ```
   - 所有数据在一页内返回
   - 客户端不应再发起请求

3. **开发中功能的展示**
   - `displayName`、`description`、`announcement` 为 null
   - UI 需要处理这种情况（如显示 `name` 作为后备）

4. **已移除功能的处理**
   - 保留在列表中以兼容旧配置
   - 但应明确标记为 `removed`
   - 客户端可能需要特殊处理（如禁用启用开关）

### 改进建议

1. **添加版本信息**
   ```rust
   pub struct ExperimentalFeature {
       // ... 现有字段 ...
       pub introduced_in_version: Option<String>,
       pub deprecated_in_version: Option<String>,
   }
   ```

2. **添加分类标签**
   ```rust
   pub tags: Vec<String>,  // ["ui", "security", "performance"]
   ```

3. **添加依赖关系**
   ```rust
   pub requires: Vec<String>,  // 依赖的其他功能名称
   pub conflicts_with: Vec<String>,
   ```

4. **增强阶段转换信息**
   ```rust
   pub stage_changed_at: Option<i64>,  // 时间戳
   pub stage_change_notes: Option<String>,
   ```

5. **添加统计信息**
   ```rust
   pub struct ExperimentalFeatureListResponse {
       pub data: Vec<ExperimentalFeature>,
       pub next_cursor: Option<String>,
       pub total_count: u64,
       pub by_stage: HashMap<ExperimentalFeatureStage, u64>,
   }
   ```

6. **改进可空字段验证**
   ```rust
   impl ExperimentalFeature {
       pub fn validate(&self) -> Result<(), ValidationError> {
           if self.stage == ExperimentalFeatureStage::Beta {
               if self.display_name.is_none() {
                   return Err(ValidationError::MissingDisplayName);
               }
               // ...
           }
           Ok(())
       }
   }
   ```

7. **添加文档链接**
   ```rust
   pub documentation_url: Option<String>,
   pub feedback_url: Option<String>,  // beta 阶段收集反馈
   ```

8. **支持功能配置 Schema**
   ```rust
   pub config_schema: Option<JsonValue>,  // 功能特定的配置选项
   ```

### 使用示例

```rust
// 服务器端：构建响应
fn list_experimental_features(
    params: ExperimentalFeatureListParams,
) -> ExperimentalFeatureListResponse {
    let all_features = vec![
        ExperimentalFeature {
            name: "askForApproval.granular".to_string(),
            stage: ExperimentalFeatureStage::Beta,
            display_name: Some("Granular Approval".to_string()),
            description: Some("Fine-grained approval controls".to_string()),
            announcement: Some("Now in beta!".to_string()),
            enabled: true,
            default_enabled: false,
        },
        // ...
    ];
    
    // 分页逻辑...
    ExperimentalFeatureListResponse {
        data: all_features,
        next_cursor: None,
    }
}
```

```typescript
// 客户端：处理响应
interface ExperimentalFeature {
    name: string;
    stage: 'beta' | 'underDevelopment' | 'stable' | 'deprecated' | 'removed';
    displayName: string | null;
    description: string | null;
    announcement: string | null;
    enabled: boolean;
    defaultEnabled: boolean;
}

function renderFeature(feature: ExperimentalFeature): React.ReactNode {
    const displayName = feature.displayName ?? feature.name;
    const isConfigurable = feature.stage !== 'removed';
    
    return (
        <div className={`feature-${feature.stage}`}>
            <h3>{displayName}</h3>
            {feature.description && <p>{feature.description}</p>}
            {feature.announcement && <div className="announcement">{feature.announcement}</div>}
            <Toggle 
                checked={feature.enabled}
                disabled={!isConfigurable}
                defaultChecked={feature.defaultEnabled}
            />
        </div>
    );
}
```

### 与实验性 API 系统的集成

该响应结构与 `#[experimental(...)]` 属性系统的关系：

```rust
// 1. 代码中标记实验性
#[experimental("askForApproval.granular")]
Granular { ... }

// 2. API 返回该功能的元数据
{
    "name": "askForApproval.granular",
    "stage": "beta",  // 根据属性推断或配置
    // ...
}

// 3. 客户端根据 stage 决定是否显示/启用
```

建议建立自动化机制，确保：
- 代码中的 `#[experimental(...)]` 属性与 API 返回的 `stage` 一致
- 当功能从 beta 转为 stable 时，同步更新所有相关定义
