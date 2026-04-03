# ExternalAgentConfigImportParams 研究文档

## 1. 场景与职责

### 1.1 使用场景

`ExternalAgentConfigImportParams` 是 Codex App-Server Protocol v2 API 中用于**导入外部 Agent 配置**的请求参数结构体。它接收用户选择的迁移项列表，并执行实际的配置迁移操作。

主要应用场景包括：

1. **用户确认迁移**：在检测到可迁移配置后，用户通过 UI 选择需要导入的项目，调用此接口执行导入
2. **批量配置同步**：一次性导入多个仓库或全局配置
3. **自动化迁移脚本**：在 CI/CD 或初始化脚本中自动迁移配置

### 1.2 职责范围

该结构体的核心职责是：
- 接收用户选择的迁移项列表
- 传递迁移项的完整信息（类型、描述、工作目录）给 Core 层执行
- 作为 `externalAgentConfig/import` RPC 方法的输入参数

---

## 2. 功能点目的

### 2.1 设计目标

| 目标 | 说明 |
|------|------|
| **精确控制** | 用户可以选择性地导入检测到的部分或全部配置 |
| **幂等性** | 重复导入相同配置不会导致错误或数据损坏 |
| **可追溯性** | 通过 `description` 字段记录迁移操作的意图 |
| **类型安全** | 复用 `ExternalAgentConfigMigrationItem` 类型，确保 Detect 和 Import 之间的数据一致性 |

### 2.2 与 Detect 的关系

```
Detect (检测)          Import (导入)
    ↓                       ↓
返回可迁移项列表  →  用户选择 →  执行迁移
    ↓                       ↓
ExternalAgentConfigDetectResponse
    ↓
ExternalAgentConfigMigrationItem[]
    ↓
ExternalAgentConfigImportParams.migrationItems
```

---

## 3. 具体技术实现

### 3.1 数据结构定义

**JSON Schema 定义** (`codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigImportParams.json`):

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
    "migrationItems": {
      "items": {
        "$ref": "#/definitions/ExternalAgentConfigMigrationItem"
      },
      "type": "array"
    }
  },
  "required": ["migrationItems"],
  "title": "ExternalAgentConfigImportParams",
  "type": "object"
}
```

**Rust 结构体定义** (`codex-rs/app-server-protocol/src/protocol/v2.rs` 第 912-917 行):

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ExternalAgentConfigImportParams {
    pub migration_items: Vec<ExternalAgentConfigMigrationItem>,
}
```

### 3.2 字段详解

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| `migrationItems` | `ExternalAgentConfigMigrationItem[]` | 是 | 要导入的迁移项列表 |

### 3.3 嵌套类型

`ExternalAgentConfigMigrationItem` 与 DetectResponse 中使用的类型完全一致：

```rust
pub struct ExternalAgentConfigMigrationItem {
    pub item_type: ExternalAgentConfigMigrationItemType,
    pub description: String,
    pub cwd: Option<PathBuf>,
}
```

| 字段名 | 类型 | 必需 | 说明 |
|--------|------|------|------|
| `itemType` | `ExternalAgentConfigMigrationItemType` | 是 | 迁移项类型 |
| `description` | `string` | 是 | 迁移描述（仅用于日志/展示） |
| `cwd` | `string \| null` | 否 | 工作目录，决定迁移范围 |

### 3.4 协议集成

在 `common.rs` 中注册为 RPC 方法参数 (`client_request_definitions!` 宏):

```rust
ExternalAgentConfigImport => "externalAgentConfig/import" {
    params: v2::ExternalAgentConfigImportParams,
    response: v2::ExternalAgentConfigImportResponse,
},
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 作用 |
|----------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ExternalAgentConfigImportParams.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` (912-917行) | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` (485-488行) | RPC 方法注册 |
| `codex-rs/app-server/src/external_agent_config_api.rs` (65-97行) | API 实现，参数处理 |
| `codex-rs/core/src/external_agent_config.rs` (76-108行) | Core 层导入逻辑 |

### 4.2 TypeScript 类型定义

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ExternalAgentConfigImportParams.ts` | TypeScript 类型定义 |

### 4.3 调用流程

```
Client Request
    ↓
externalAgentConfig/import RPC
    ↓
ExternalAgentConfigImportParams (反序列化)
    ↓
ExternalAgentConfigApi::import() (app-server)
    ↓
类型转换: Protocol 类型 → Core 类型
    ↓
ExternalAgentConfigService::import() (core)
    ↓
按类型分发到具体导入逻辑
    ├─ import_config()      (CONFIG)
    ├─ import_skills()      (SKILLS)
    ├─ import_agents_md()   (AGENTS_MD)
    └─ (空实现)             (MCP_SERVER_CONFIG)
```

### 4.4 类型转换代码

在 `external_agent_config_api.rs` 中的转换逻辑：

```rust
self.migration_service
    .import(
        params
            .migration_items
            .into_iter()
            .map(|migration_item| CoreMigrationItem {
                item_type: match migration_item.item_type {
                    ExternalAgentConfigMigrationItemType::Config => CoreMigrationItemType::Config,
                    ExternalAgentConfigMigrationItemType::Skills => CoreMigrationItemType::Skills,
                    ExternalAgentConfigMigrationItemType::AgentsMd => CoreMigrationItemType::AgentsMd,
                    ExternalAgentConfigMigrationItemType::McpServerConfig => CoreMigrationItemType::McpServerConfig,
                },
                description: migration_item.description,
                cwd: migration_item.cwd,
            })
            .collect(),
    )
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 依赖项 | 说明 |
|--------|------|
| `serde` | 序列化/反序列化 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |
| `ExternalAgentConfigMigrationItem` | 嵌套类型，定义在 v2.rs |

### 5.2 关联类型

- `ExternalAgentConfigDetectResponse`: 输出相同的 `ExternalAgentConfigMigrationItem` 类型
- `ExternalAgentConfigImportResponse`: 对应的响应类型（空对象）

### 5.3 导入行为详情

#### CONFIG 类型导入 (`import_config`)

1. 解析 `cwd` 确定源和目标路径
2. 读取源 `settings.json` 文件
3. 调用 `build_config_from_external()` 转换为 TOML 格式
4. 合并到目标 `config.toml`（保留现有配置，只添加缺失项）
5. 写入文件

#### SKILLS 类型导入 (`import_skills`)

1. 解析 `cwd` 确定源和目标技能目录
2. 遍历源目录下的所有子目录
3. 复制不存在的技能目录到目标位置
4. 对 `SKILL.md` 文件进行内容重写（替换 "Claude" 为 "Codex"）
5. 返回复制的技能数量

#### AGENTS_MD 类型导入 (`import_agents_md`)

1. 解析 `cwd` 确定源和目标 AGENTS.md 路径
2. 检查源文件是否存在且非空
3. 检查目标文件是否缺失或为空
4. 复制文件并执行内容重写

#### MCP_SERVER_CONFIG 类型

当前为空实现，不执行任何操作。

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 说明 | 缓解措施 |
|--------|------|----------|
| **部分失败** | 批量导入时部分项失败，当前返回整体错误 | 建议添加细粒度的错误报告 |
| **数据覆盖** | 虽然设计为合并而非覆盖，但仍可能意外修改配置 | 建议添加备份机制 |
| **并发导入** | 多线程同时导入可能导致文件竞争 | 建议添加文件锁或队列机制 |
| **MCP_SERVER_CONFIG 空实现** | 用户可能误以为该类型已支持 | 建议返回明确的未支持错误 |

### 6.2 边界情况

1. **空 `migrationItems`**: 不执行任何操作，返回成功
2. **重复导入**: 由于采用合并策略，重复导入不会导致数据丢失
3. **源文件不存在**: 静默跳过（返回 Ok）
4. **目标文件已存在且有冲突内容**: 保留现有内容，只添加缺失的配置项
5. **无效 `cwd`**: 跳过该项（对于非空 `cwd`）或按全局处理（对于 `None`）

### 6.3 改进建议

1. **添加导入预览模式**: 在执行实际导入前返回将要执行的操作
   ```rust
   pub struct ExternalAgentConfigImportParams {
       pub migration_items: Vec<ExternalAgentConfigMigrationItem>,
       pub dry_run: bool, // 新增：预览模式
   }
   
   pub struct ExternalAgentConfigImportResponse {
       pub applied: Vec<AppliedMigration>,
       pub skipped: Vec<SkippedMigration>,
       pub errors: Vec<MigrationError>,
   }
   ```

2. **支持强制覆盖**: 允许用户选择覆盖策略
   ```rust
   pub enum ImportStrategy {
       Merge,    // 默认：合并，保留现有配置
       Replace,  // 替换：完全覆盖
       Skip,     // 跳过：如果目标存在则跳过
   }
   
   pub struct ExternalAgentConfigMigrationItem {
       // ... 现有字段
       pub strategy: ImportStrategy,
   }
   ```

3. **添加事务支持**: 确保批量导入的原子性
   ```rust
   pub struct ExternalAgentConfigImportParams {
       pub migration_items: Vec<ExternalAgentConfigMigrationItem>,
       pub atomic: bool, // 如果为 true，任一失败则全部回滚
   }
   ```

4. **支持回滚**: 记录导入操作以便撤销
   ```rust
   pub struct ExternalAgentConfigImportResponse {
       // ... 现有字段
       pub rollback_token: String, // 用于后续回滚操作
   }
   ```

5. **增强错误报告**: 提供详细的错误信息
   ```rust
   pub struct MigrationError {
       pub item: ExternalAgentConfigMigrationItem,
       pub error_code: String,
       pub error_message: String,
       pub suggestion: Option<String>,
   }
   ```

6. **支持进度回调**: 对于大量迁移项，提供进度通知
   ```rust
   pub struct ExternalAgentConfigImportParams {
       pub migration_items: Vec<ExternalAgentConfigMigrationItem>,
       pub enable_progress: bool, // 启用进度通知
   }
   // 发送 ServerNotification: ExternalAgentConfigImportProgress
   ```
