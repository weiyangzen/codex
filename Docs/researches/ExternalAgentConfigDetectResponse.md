# ExternalAgentConfigDetectResponse 研究文档

## 1. 场景与职责

### 1.1 使用场景

`ExternalAgentConfigDetectResponse` 是 Codex App-Server Protocol v2 API 中 `externalAgentConfig/detect` RPC 方法的响应结构体。它用于返回在指定范围内检测到的可迁移配置项列表。

主要应用场景包括：

1. **迁移向导 UI**: 客户端展示检测到的可迁移配置，让用户选择需要导入的项目
2. **批量迁移准备**: 为后续的 `externalAgentConfig/import` 调用提供参数
3. **配置同步检查**: 检测当前工作区是否存在外部 Agent 的遗留配置

### 1.2 职责范围

该结构体的核心职责是：
- 封装检测到的所有可迁移配置项
- 提供每个迁移项的详细描述（类型、说明、位置）
- 支持区分仓库级（repo-scoped）和全局（home-scoped）迁移项

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| **完整信息展示** | 每个迁移项包含类型、描述、工作目录，便于用户理解 |
| **精准定位** | 通过 `cwd` 字段区分仓库级和全局配置 |
| **类型安全** | 使用枚举定义迁移项类型，避免魔法字符串 |
| **可扩展性** | 结构体设计支持未来添加更多迁移项类型 |

### 2.2 迁移项类型说明

| 类型 | 源文件/目录 | 目标文件/目录 | 说明 |
|------|-------------|---------------|------|
| `AGENTS_MD` | `CLAUDE.md` 或 `.claude/CLAUDE.md` | `AGENTS.md` | Agent 指令文档 |
| `CONFIG` | `.claude/settings.json` | `.codex/config.toml` | Agent 配置 |
| `SKILLS` | `.claude/skills/` | `.agents/skills/` | 技能目录 |
| `MCP_SERVER_CONFIG` | (预留) | (预留) | MCP 服务器配置 |

---

## 3. 具体技术实现

### 3.1 数据结构定义

**JSON Schema 定义** (`codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigDetectResponse.json`):

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "ExternalAgentConfigMigrationItem": {
      "properties": {
        "cwd": {
          "description": "Null or empty means home-scoped migration; non-empty means repo-scoped migration.",
          "type": ["string", "null"]
        },
        "description": {
          "type": "string"
        },
        "itemType": {
          "$ref": "#/definitions/ExternalAgentConfigMigrationItemType"
        }
      },
      "required": ["description", "itemType"],
      "type": "object"
    },
    "ExternalAgentConfigMigrationItemType": {
      "enum": ["AGENTS_MD", "CONFIG", "SKILLS", "MCP_SERVER_CONFIG"],
      "type": "string"
    }
  },
  "properties": {
    "items": {
      "items": {
        "$ref": "#/definitions/ExternalAgentConfigMigrationItem"
      },
      "type": "array"
    }
  },
  "required": ["items"],
  "title": "ExternalAgentConfigDetectResponse",
  "type": "object"
}
```

**Rust 结构体定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs`):

```rust
// 第 866-881 行：迁移项类型枚举
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Hash, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub enum ExternalAgentConfigMigrationItemType {
    #[serde(rename = "AGENTS_MD")]
    #[ts(rename = "AGENTS_MD")]
    AgentsMd,
    #[serde(rename = "CONFIG")]
    #[ts(rename = "CONFIG")]
    Config,
    #[serde(rename = "SKILLS")]
    #[ts(rename = "SKILLS")]
    Skills,
    #[serde(rename = "MCP_SERVER_CONFIG")]
    #[ts(rename = "MCP_SERVER_CONFIG")]
    McpServerConfig,
}

// 第 883-891 行：迁移项结构体
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExternalAgentConfigMigrationItem {
    pub item_type: ExternalAgentConfigMigrationItemType,
    pub description: String,
    /// Null or empty means home-scoped migration; non-empty means repo-scoped migration.
    pub cwd: Option<PathBuf>,
}

// 第 893-898 行：响应结构体
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExternalAgentConfigDetectResponse {
    pub items: Vec<ExternalAgentConfigMigrationItem>,
}
```

### 3.2 字段详解

#### ExternalAgentConfigDetectResponse

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| `items` | `ExternalAgentConfigMigrationItem[]` | 是 | 检测到的迁移项列表 |

#### ExternalAgentConfigMigrationItem

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| `itemType` | `ExternalAgentConfigMigrationItemType` | 是 | 迁移项类型 |
| `description` | `string` | 是 | 人类可读的迁移描述 |
| `cwd` | `string \| null` | 否 | 工作目录，`null` 表示全局配置 |

#### ExternalAgentConfigMigrationItemType 枚举值

| 枚举值 | 说明 |
|--------|------|
| `AGENTS_MD` | AGENTS.md 文档迁移 |
| `CONFIG` | 配置文件迁移 |
| `SKILLS` | 技能目录迁移 |
| `MCP_SERVER_CONFIG` | MCP 服务器配置（预留） |

### 3.3 序列化行为

- 所有字段使用 camelCase 命名规范
- `ExternalAgentConfigMigrationItemType` 使用大写下划线命名（如 `AGENTS_MD`）
- `cwd` 为 `Option<PathBuf>`，序列化后为 `string` 或 `null`

### 3.4 描述生成逻辑

描述字符串在 Core 层生成，格式如下：

```rust
// CONFIG 类型
format!("Migrate {} into {}", source_settings.display(), target_config.display())
// 示例: "Migrate /home/user/.claude/settings.json into /home/user/.codex/config.toml"

// SKILLS 类型
format!("Copy skill folders from {} to {}", source_skills.display(), target_skills.display())
// 示例: "Copy skill folders from /project/.claude/skills to /project/.agents/skills"

// AGENTS_MD 类型
format!("Import {} to {}", source_agents_md.display(), target_agents_md.display())
// 示例: "Import /project/CLAUDE.md to /project/AGENTS.md"
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigDetectResponse.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (866-898行) | Rust 类型定义（枚举、迁移项、响应） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (481-484行) | RPC 响应类型注册 |
| `codex-rs/app-server/src/external_agent_config_api.rs` (28-63行) | API 实现，响应构建 |
| `codex-rs/core/src/external_agent_config.rs` (27-32, 110-218行) | Core 层迁移项生成逻辑 |

### 4.2 TypeScript 类型定义

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ExternalAgentConfigDetectResponse.ts` | 响应类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ExternalAgentConfigMigrationItem.ts` | 迁移项类型 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ExternalAgentConfigMigrationItemType.ts` | 迁移项类型枚举 |

### 4.3 数据流

```
Core 层检测逻辑 (external_agent_config.rs)
    ↓
CoreMigrationItem (Core 类型)
    ↓
ExternalAgentConfigApi::detect() (app-server)
    ↓
类型转换: CoreMigrationItemType → ExternalAgentConfigMigrationItemType
    ↓
ExternalAgentConfigMigrationItem (Protocol 类型)
    ↓
ExternalAgentConfigDetectResponse
    ↓
JSON 序列化 → 客户端
```

### 4.4 类型转换代码

在 `external_agent_config_api.rs` 中的转换逻辑：

```rust
ExternalAgentConfigMigrationItem {
    item_type: match migration_item.item_type {
        CoreMigrationItemType::Config => ExternalAgentConfigMigrationItemType::Config,
        CoreMigrationItemType::Skills => ExternalAgentConfigMigrationItemType::Skills,
        CoreMigrationItemType::AgentsMd => ExternalAgentConfigMigrationItemType::AgentsMd,
        CoreMigrationItemType::McpServerConfig => ExternalAgentConfigMigrationItemType::McpServerConfig,
    },
    description: migration_item.description,
    cwd: migration_item.cwd,
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |
| `std::path::PathBuf` | 路径表示 |

### 5.2 关联类型

- `ExternalAgentConfigImportParams`: 使用相同的 `ExternalAgentConfigMigrationItem` 类型作为输入
- `ExternalAgentConfigMigrationItem` 在 Detect 和 Import 之间共享

### 5.3 客户端使用流程

```typescript
// 1. 调用检测接口
const response = await client.request('externalAgentConfig/detect', {
    includeHome: true,
    cwds: ['/path/to/project']
});

// 2. 展示检测到的项目
for (const item of response.items) {
    console.log(`${item.itemType}: ${item.description}`);
}

// 3. 用户选择后调用导入
await client.request('externalAgentConfig/import', {
    migrationItems: selectedItems
});
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 说明 | 缓解措施 |
|--------|------|----------|
| **MCP_SERVER_CONFIG 未实现** | 该类型在 Core 层检测逻辑中为空实现，可能导致用户困惑 | 建议隐藏未实现的类型，或添加文档说明 |
| **描述字符串过长** | 路径可能很长，导致描述难以阅读 | 考虑使用相对路径或添加路径截断 |
| **重复检测** | 同一仓库多次检测可能返回重复项 | 客户端需要去重，或服务端添加缓存 |

### 6.2 边界情况

1. **空结果**: `items` 为空数组表示未检测到任何可迁移配置
2. **重复 cwd**: 多个迁移项可能具有相同的 `cwd`（如同一仓库有 CONFIG 和 SKILLS）
3. **cwd 为 null**: 表示全局（home-scoped）迁移项
4. **cwd 为空字符串**: 与 `null` 语义相同，表示全局迁移

### 6.3 改进建议

1. **添加迁移状态字段**: 让用户知道某项是否已迁移
   ```rust
   pub struct ExternalAgentConfigMigrationItem {
       // ... 现有字段
       pub status: MigrationStatus, // New, AlreadyMigrated, PartiallyMigrated
   }
   ```

2. **添加冲突检测**: 检测目标位置是否已存在文件
   ```rust
   pub struct ExternalAgentConfigMigrationItem {
       // ... 现有字段
       pub conflicts: Vec<ConflictInfo>,
   }
   ```

3. **支持批量操作元数据**: 添加建议的批量操作分组
   ```rust
   pub struct ExternalAgentConfigDetectResponse {
       pub items: Vec<ExternalAgentConfigMigrationItem>,
       pub groups: Vec<MigrationGroup>, // 按 cwd 分组
   }
   ```

4. **添加迁移预览**: 返回更详细的迁移内容预览
   ```rust
   pub struct ExternalAgentConfigMigrationItem {
       // ... 现有字段
       pub preview: Option<MigrationPreview>, // 配置内容预览
   }
   ```

5. **国际化支持**: 描述字符串当前为英文，建议添加 i18n 支持
   ```rust
   pub description_key: String, // 用于查找翻译的 key
   pub description_params: HashMap<String, String>, // 模板参数
   ```
