# ExperimentalFeature.ts 研究文档

## 场景与职责

`ExperimentalFeature.ts` 定义了实验性功能类型，用于表示单个实验性功能的元数据和状态。这是 Codex 功能开关（Feature Flag）系统的核心类型，支持功能的灰度发布、A/B 测试和逐步推广。

该类型在实验性功能管理、用户设置、功能发现等场景中发挥关键作用。

## 功能点目的

1. **功能元数据**: 提供功能的名称、描述、阶段等基本信息
2. **状态追踪**: 显示功能当前是否启用及默认状态
3. **用户界面**: 为实验性功能 UI 提供显示数据

## 具体技术实现

### 数据结构定义

```typescript
export type ExperimentalFeature = { 
  /**
   * Stable key used in config.toml and CLI flag toggles.
   */
  name: string, 
  /**
   * Lifecycle stage of this feature flag.
   */
  stage: ExperimentalFeatureStage, 
  /**
   * User-facing display name shown in the experimental features UI.
   * Null when this feature is not in beta.
   */
  displayName: string | null, 
  /**
   * Short summary describing what the feature does.
   * Null when this feature is not in beta.
   */
  description: string | null, 
  /**
   * Announcement copy shown to users when the feature is introduced.
   * Null when this feature is not in beta.
   */
  announcement: string | null, 
  /**
   * Whether this feature is currently enabled in the loaded config.
   */
  enabled: boolean, 
  /**
   * Whether this feature is enabled by default.
   */
  defaultEnabled: boolean, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 功能的唯一标识符，用于 `config.toml` 和 CLI 标志 |
| `stage` | `ExperimentalFeatureStage` | 功能生命周期阶段（beta、开发中、稳定等） |
| `displayName` | `string \| null` | 用户界面显示名称，非 beta 阶段为 null |
| `description` | `string \| null` | 功能描述，非 beta 阶段为 null |
| `announcement` | `string \| null` | 功能发布时的公告文案 |
| `enabled` | `boolean` | 当前配置中是否启用 |
| `defaultEnabled` | `boolean` | 默认是否启用 |

### 生命周期阶段

```typescript
export type ExperimentalFeatureStage = 
  | "beta"           // 可供用户测试和反馈
  | "underDevelopment" // 正在开发中，不适合广泛使用
  | "stable"         // 生产就绪
  | "deprecated"     // 已弃用，应避免使用
  | "removed";       // 仅保留向后兼容性
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1863-1884)

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

### 阶段枚举

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1847-1861)

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

### 列表响应

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1886-1894)

```rust
pub struct ExperimentalFeatureListResponse {
    pub data: Vec<ExperimentalFeature>,
    pub next_cursor: Option<String>,
}
```

### 列表参数

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1835-1845)

```rust
pub struct ExperimentalFeatureListParams {
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |
| `serde` | 序列化/反序列化 |

### 下游消费者

- **TUI 设置界面**: 显示实验性功能列表
- **配置系统**: 读取和写入功能开关状态
- **功能门控**: 根据功能状态启用/禁用功能

## 风险、边界与改进建议

### 已知风险

1. **阶段混淆**: `stable` 阶段仍标记为"实验性"，命名可能令人困惑
2. **UI 数据缺失**: 非 beta 阶段 `displayName` 和 `description` 为 null
3. **配置同步**: 功能状态可能在多个配置层中定义，需要正确合并

### 边界情况

1. **未知功能**: 客户端可能请求不存在的功能
2. **配置冲突**: 同一功能在不同配置层可能有不同设置
3. **版本差异**: 不同版本的客户端/服务器对功能的定义可能不同

### 改进建议

1. **重命名**: 考虑将 `stable` 重命名为 `generalAvailability` 或分离实验性和非实验性功能
2. **分类标签**: 增加功能分类（如 UI、性能、安全）
3. **依赖关系**: 支持功能之间的依赖关系
4. **用户反馈**: 集成用户反馈收集机制
5. **使用统计**: 收集功能使用统计数据
6. **强制启用**: 支持某些功能强制启用（不可禁用）

### 扩展示例

```typescript
export type ExperimentalFeature = { 
  name: string, 
  stage: ExperimentalFeatureStage,
  category: 'ui' | 'performance' | 'security' | 'integrations',
  displayName: string | null, 
  description: string | null, 
  announcement: string | null,
  enabled: boolean, 
  defaultEnabled: boolean,
  // 新增字段
  dependencies: string[],  // 依赖的其他功能
  requiresRestart: boolean,  // 修改后是否需要重启
  userConfigurable: boolean,  // 用户是否可配置
  rolloutPercentage: number | null,  // 灰度发布百分比
};
```
