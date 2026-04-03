# AppToolsConfig.ts 研究文档

## 场景与职责

`AppToolsConfig.ts` 定义了 Codex 应用中工具配置的类型结构，用于管理应用（App）中各个工具的启用状态和审批模式。这是 App-Server Protocol v2 API 的一部分，支持对工具进行细粒度的权限控制。

该类型主要用于：
- 配置特定应用工具的启用/禁用状态
- 设置工具执行时的审批策略（自动、提示、批准）
- 在 `AppsConfig` 中作为 `tools` 字段的类型

## 功能点目的

### 核心功能

1. **工具配置映射**：提供一个从工具名称到工具配置的映射表
2. **启用状态控制**：每个工具可以独立设置启用或禁用
3. **审批模式配置**：支持为每个工具配置不同的审批策略

### 类型定义

```typescript
export type AppToolsConfig = { 
  [key in string]?: { 
    enabled: boolean | null, 
    approval_mode: AppToolApproval | null, 
  } 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `enabled` | `boolean \| null` | 工具是否启用，null 表示使用默认值 |
| `approval_mode` | `AppToolApproval \| null` | 工具的审批模式，null 表示使用默认值 |

### AppToolApproval 枚举值

- `auto`：自动执行，无需审批
- `prompt`：需要用户提示确认
- `approve`：需要明确批准

## 具体技术实现

### 代码生成来源

该 TypeScript 类型由 Rust 代码通过 `ts-rs` 自动生成：

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct AppToolsConfig {
    #[serde(default, flatten)]
    pub tools: HashMap<String, AppToolConfig>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct AppToolConfig {
    pub enabled: Option<bool>,
    pub approval_mode: Option<AppToolApproval>,
}
```

### 序列化规则

- Rust 使用 `snake_case` 命名规范
- TypeScript 使用 `camelCase` 命名规范（通过 serde 转换）
- 使用 `#[serde(flatten)]` 将嵌套结构展平为字典

## 关键代码路径与文件引用

### 生成文件

| 文件 | 说明 |
|------|------|
| `AppToolsConfig.ts` | 工具配置映射类型 |
| `AppToolApproval.ts` | 审批模式枚举 |
| `AppToolConfig.ts` | 单个工具配置（内联类型展开后） |

### 依赖关系

```
AppToolsConfig.ts
  └── AppToolApproval.ts
```

### 上游依赖

- `AppConfig.ts`：在应用配置中使用 `tools` 字段
- `AppsConfig.ts`：在默认配置中使用

## 依赖与外部交互

### 协议集成

该类型是 App-Server Protocol v2 的一部分，用于：
- `config/read` 响应：返回当前配置的工具设置
- `config/write` 请求：更新工具配置
- `apps/list` 响应：显示应用的可用工具及其配置

### 配置层级

工具配置遵循 Codex 的配置层级系统：
1. MDM 层（最低优先级）
2. System 层
3. User 层
4. Project 层
5. SessionFlags 层（最高优先级）

## 风险、边界与改进建议

### 潜在风险

1. **空值处理**：`enabled` 和 `approval_mode` 都可能为 null，客户端需要正确处理默认值
2. **键名冲突**：作为扁平化的字典结构，工具名称需要唯一
3. **类型安全**：TypeScript 的索引签名允许任意字符串键，可能导致无效的工具名称

### 边界情况

1. **空配置**：当没有配置任何工具时，对象为空 `{}`
2. **部分配置**：某些工具可能只配置了 `enabled` 而未配置 `approval_mode`
3. **无效工具名**：配置中可能包含服务器不认识的工具名称

### 改进建议

1. **文档化工具列表**：建议维护一个受支持工具的枚举或常量列表
2. **验证增强**：在服务器端增加对工具名称的验证
3. **默认值明确化**：考虑在 API 文档中明确每个字段的默认值
4. **类型收窄**：考虑使用更具体的工具名称联合类型而非任意字符串

### 版本兼容性

- 当前版本：v2
- 稳定性：稳定（非实验性 API）
- 变更历史：从 v1 的 `Tools` 类型演进而来，增加了更细粒度的控制
