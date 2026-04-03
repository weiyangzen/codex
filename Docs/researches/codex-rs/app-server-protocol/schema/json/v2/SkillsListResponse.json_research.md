# SkillsListResponse.json 研究文档

## 场景与职责

`SkillsListResponse` 是 App-Server Protocol v2 中用于返回技能列表的响应结构。它提供了按工作目录组织的技能信息，包括技能元数据、依赖关系、错误信息等。

该响应支持复杂的技能生态系统，包括用户技能、仓库技能和系统技能。

## 功能点目的

1. **技能展示**: 展示来自多个来源的可用技能
2. **依赖管理**: 显示技能的依赖关系（特别是工具依赖）
3. **错误报告**: 报告技能加载过程中的错误
4. **界面渲染**: 提供技能界面信息用于 UI 展示

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "SkillDependencies": {
      "properties": {
        "tools": { "items": { "$ref": "#/definitions/SkillToolDependency" }, "type": "array" }
      },
      "required": ["tools"],
      "type": "object"
    },
    "SkillErrorInfo": {
      "properties": {
        "message": { "type": "string" },
        "path": { "type": "string" }
      },
      "required": ["message", "path"],
      "type": "object"
    },
    "SkillInterface": {
      "properties": {
        "brandColor": { "type": ["string", "null"] },
        "defaultPrompt": { "type": ["string", "null"] },
        "displayName": { "type": ["string", "null"] },
        "iconLarge": { "type": ["string", "null"] },
        "iconSmall": { "type": ["string", "null"] },
        "shortDescription": { "type": ["string", "null"] }
      },
      "type": "object"
    },
    "SkillMetadata": {
      "properties": {
        "dependencies": { "anyOf": [{ "$ref": "#/definitions/SkillDependencies" }, { "type": "null" }] },
        "description": { "type": "string" },
        "enabled": { "type": "boolean" },
        "interface": { "anyOf": [{ "$ref": "#/definitions/SkillInterface" }, { "type": "null" }] },
        "name": { "type": "string" },
        "path": { "type": "string" },
        "scope": { "$ref": "#/definitions/SkillScope" },
        "shortDescription": { "description": "Legacy short_description from SKILL.md...", "type": ["string", "null"] }
      },
      "required": ["description", "enabled", "name", "path", "scope"],
      "type": "object"
    },
    "SkillScope": {
      "enum": ["user", "repo", "system", "admin"],
      "type": "string"
    },
    "SkillToolDependency": {
      "properties": {
        "command": { "type": ["string", "null"] },
        "description": { "type": ["string", "null"] },
        "transport": { "type": ["string", "null"] },
        "type": { "type": "string" },
        "url": { "type": ["string", "null"] },
        "value": { "type": "string" }
      },
      "required": ["type", "value"],
      "type": "object"
    },
    "SkillsListEntry": {
      "properties": {
        "cwd": { "type": "string" },
        "errors": { "items": { "$ref": "#/definitions/SkillErrorInfo" }, "type": "array" },
        "skills": { "items": { "$ref": "#/definitions/SkillMetadata" }, "type": "array" }
      },
      "required": ["cwd", "errors", "skills"],
      "type": "object"
    }
  },
  "properties": {
    "data": { "items": { "$ref": "#/definitions/SkillsListEntry" }, "type": "array" }
  },
  "required": ["data"],
  "title": "SkillsListResponse",
  "type": "object"
}
```

### 字段说明

#### 根级别字段

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `data` | SkillsListEntry[] | 是 | 按工作目录组织的技能列表 |

#### SkillsListEntry 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `cwd` | string | 工作目录 |
| `skills` | SkillMetadata[] | 该目录下的技能列表 |
| `errors` | SkillErrorInfo[] | 技能加载错误列表 |

#### SkillMetadata 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 技能名称 |
| `path` | string | 技能路径 |
| `description` | string | 技能描述 |
| `enabled` | boolean | 是否启用 |
| `scope` | SkillScope | 技能作用域 |
| `interface` | SkillInterface | 技能界面信息 |
| `dependencies` | SkillDependencies | 技能依赖 |
| `shortDescription` | string \| null | 简短描述（来自 SKILL.md） |

#### SkillScope 枚举

| 值 | 说明 |
|----|------|
| `user` | 用户级技能 |
| `repo` | 仓库级技能 |
| `system` | 系统级技能 |
| `admin` | 管理员配置的技能 |

### 关联的 RPC 方法

- **方法**: `skills/list`
- **请求参数**: `SkillsListParams`

## 关键代码路径与文件引用

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListResponse {
    pub data: Vec<SkillsListEntry>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillsListEntry {
    pub cwd: String,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct SkillMetadata {
    pub name: String,
    pub path: String,
    pub description: String,
    pub enabled: bool,
    pub scope: SkillScope,
    pub interface: Option<SkillInterface>,
    pub dependencies: Option<SkillDependencies>,
    pub short_description: Option<String>,
}
```

### 相关文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 请求处理实现 |
| `codex-rs/app-server/tests/suite/v2/skills_list.rs` | 测试文件 |
| `codex-rs/tui_app_server/src/app.rs` | TUI 应用中的使用 |

## 依赖与外部交互

### 上游依赖

1. **技能管理器**: `codex_core::skills::SkillsManager`
2. **SKILL.md/SKILL.json 解析**: 技能元数据解析
3. **文件系统扫描**: 技能目录扫描

### 下游交互

1. **技能列表 UI**: 客户端渲染技能列表
2. **技能详情**: 用户查看技能详情和依赖

### 协议版本

- **版本**: v2
- **稳定性**: 稳定 API (非实验性)

## 风险、边界与改进建议

### 风险点

1. **响应体大小**: 大量技能时响应体可能很大
2. **敏感信息**: `path` 字段可能包含敏感路径信息
3. **依赖循环**: 技能依赖可能存在循环

### 边界情况

1. **空列表**: 没有可用技能时返回空数组
2. **加载错误**: 部分技能加载失败时的处理
3. **重复技能**: 不同作用域中同名技能的处理

### 改进建议

1. **添加分页**: 建议添加分页支持
2. **添加排序**: 建议添加排序选项
3. **添加分组**: 建议按作用域分组展示
4. **添加统计**: 建议添加技能使用统计

### 测试覆盖

相关测试文件：`codex-rs/app-server/tests/suite/v2/skills_list.rs`

建议测试场景：
- 多工作目录技能列表
- 技能加载错误处理
- 技能依赖展示
