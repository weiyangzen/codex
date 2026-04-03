# ModelUpgradeInfo.ts 调研文档

## 场景与职责

`ModelUpgradeInfo` 是 Codex App Server Protocol v2 API 中用于表示模型升级信息的数据结构。它提供了关于模型升级的详细信息，包括升级说明、迁移指南和相关链接。

主要使用场景包括：
- 模型弃用通知：告知用户当前模型将被升级
- 迁移指导：提供详细的迁移说明和文档链接
- 升级推荐：在模型列表中展示可用的升级选项

## 功能点目的

该类型的核心目的是提供标准化的模型升级信息：

1. **升级标识**：通过 `model` 字段标识推荐升级到的目标模型
2. **用户文案**：通过 `upgradeCopy` 提供用户友好的升级说明
3. **文档支持**：通过 `modelLink` 和 `migrationMarkdown` 提供详细文档

TypeScript 定义：
```typescript
export type ModelUpgradeInfo = { 
    model: string, 
    upgradeCopy: string | null, 
    modelLink: string | null, 
    migrationMarkdown: string | null 
}
```

## 具体技术实现

### Rust 端实现

在 `codex-rs/app-server-protocol/src/protocol/v2.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ModelUpgradeInfo {
    pub model: String,
    pub upgrade_copy: Option<String>,
    pub model_link: Option<String>,
    pub migration_markdown: Option<String>,
}
```

### 核心协议层定义

在 `codex-rs/protocol/src/openai_models.rs` 中定义核心结构：

```rust
#[derive(Debug, Clone, Deserialize, Serialize, TS, JsonSchema, PartialEq)]
pub struct ModelUpgrade {
    pub id: String,
    pub reasoning_effort_mapping: Option<HashMap<ReasoningEffort, ReasoningEffort>>,
    pub migration_config_key: String,
    pub model_link: Option<String>,
    pub upgrade_copy: Option<String>,
    pub migration_markdown: Option<String>,
}
```

### 使用位置

在 `Model` 结构中作为可选字段：

```rust
pub struct Model {
    pub id: String,
    pub model: String,
    pub upgrade: Option<String>,
    pub upgrade_info: Option<ModelUpgradeInfo>,  // <-- 使用位置
    pub availability_nux: Option<ModelAvailabilityNux>,
    // ...
}
```

## 关键代码路径与文件引用

### 定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 协议定义，第 1769-1777 行 |
| `codex-rs/protocol/src/openai_models.rs` | 核心协议模型定义（ModelUpgrade），第 102-110 行 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ModelUpgradeInfo.ts` | 生成的 TypeScript 类型定义 |

### 引用文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/Model.ts` | Model 类型中引用（upgradeInfo 字段） |

### 类型关系

```
ModelUpgradeInfo
    └── Model (作为可选字段 upgrade_info)
        └── ModelListResponse (作为 data 数组元素)
```

## 依赖与外部交互

### 内部依赖

1. **序列化框架**：`serde` 使用 `rename_all = "camelCase"`
2. **TypeScript 生成**：`ts-rs` crate
3. **JSON Schema 生成**：`schemars` crate

### 外部交互

- **模型配置**：从模型配置中读取升级信息
- **客户端 UI**：展示升级提示和迁移指南
- **文档系统**：`modelLink` 和 `migrationMarkdown` 指向外部资源

### 升级信息展示流程

```
+---------------+     +-------------------+     +-------------------+
| 模型配置       |     | model/list API    |     | 客户端 UI          |
|               |     |                   |     |                   |
+-------+-------+     +---------+---------+     +---------+---------+
        |                       |                         |
        | ModelUpgradeInfo      |                         |
        |---------------------->|                         |
        |                       |                         |
        |                       | 包含在 Model 响应中      |
        |                       |------------------------>|
        |                       |                         |
        |                       |                         | 展示升级提示
        |                       |                         | 渲染 Markdown
        |                       |                         |
```

## 风险、边界与改进建议

### 潜在风险

1. **链接失效**：`modelLink` 和 `migrationMarkdown` 指向的外部资源可能失效
   - 建议：定期验证链接有效性，提供备用方案

2. **Markdown 安全**：`migrationMarkdown` 可能包含恶意内容
   - 建议：客户端应使用安全的 Markdown 渲染器，过滤危险标签

3. **信息不完整**：所有字段均为可选，可能导致信息不完整
   - 建议：定义必填字段的最小集

4. **多语言支持**：当前不支持国际化
   - 建议：添加本地化键值或多语言字段

### 边界情况

1. **空值处理**：所有字段为 `null` 时的展示逻辑
2. **长文本**：`upgradeCopy` 或 `migrationMarkdown` 过长时的 UI 处理
3. **模型不存在**：`model` 字段指向的模型可能不存在或已弃用

### 改进建议

1. **添加时间信息**：
   ```rust
   pub struct ModelUpgradeInfo {
       pub model: String,
       pub upgrade_copy: Option<String>,
       pub model_link: Option<String>,
       pub migration_markdown: Option<String>,
       pub effective_date: Option<i64>,  // 升级生效日期
       pub deprecation_date: Option<i64>, // 当前模型弃用日期
   }
   ```

2. **支持多种升级路径**：
   ```rust
   pub alternatives: Option<Vec<ModelUpgradeAlternative>>,  // 多个升级选项
   ```

3. **添加优先级**：
   ```rust
   pub priority: Option<UpgradePriority>,  // recommended, optional, required
   ```

4. **支持内联资源**：
   ```rust
   pub migration_html: Option<String>,  // 预渲染的 HTML
   ```

5. **添加验证**：
   - 验证 `model` 字段格式
   - 验证 URL 格式
   - 限制 Markdown 内容大小

6. **测试增强**：
   - 测试序列化/反序列化
   - 验证可选字段处理
   - 测试 Markdown 渲染安全
