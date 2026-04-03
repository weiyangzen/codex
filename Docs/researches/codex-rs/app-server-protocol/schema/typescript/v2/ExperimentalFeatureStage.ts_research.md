# ExperimentalFeatureStage.ts 研究文档

## 场景与职责

`ExperimentalFeatureStage.ts` 定义了实验性功能的生命周期阶段枚举，用于表示功能从开发到退役的完整生命周期。这是功能开关系统的核心枚举，决定了功能在 UI 中的展示方式和可用性。

该类型在功能管理、UI 渲染、权限控制等场景中发挥关键作用。

## 功能点目的

1. **生命周期管理**: 标识功能所处的开发阶段
2. **UI 适配**: 根据阶段决定如何展示功能信息
3. **访问控制**: 限制某些阶段的功能访问

## 具体技术实现

### 数据结构定义

```typescript
export type ExperimentalFeatureStage = 
  | "beta" 
  | "underDevelopment" 
  | "stable" 
  | "deprecated" 
  | "removed";
```

### 阶段说明

| 阶段 | 值 | 说明 |
|------|------|------|
| Beta | `"beta"` | 可供用户测试和反馈的阶段 |
| 开发中 | `"underDevelopment"` | 正在积极开发，不适合广泛使用 |
| 稳定 | `"stable"` | 生产就绪，功能完整 |
| 已弃用 | `"deprecated"` | 已弃用，应避免使用 |
| 已移除 | `"removed"` | 仅保留向后兼容性 |

### 使用示例

```typescript
// 根据阶段渲染不同 UI
function renderFeature(feature: ExperimentalFeature) {
  switch (feature.stage) {
    case 'beta':
      return <BetaBadge feature={feature} />;
    case 'underDevelopment':
      return <DevBadge feature={feature} />;
    case 'stable':
      return <FeatureToggle feature={feature} />;
    case 'deprecated':
      return <DeprecatedWarning feature={feature} />;
    case 'removed':
      return null; // 不显示已移除的功能
  }
}
```

## 关键代码路径与文件引用

### Rust 源码定义

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1847-1861)

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
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

### 使用场景

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1863-1884)

```rust
pub struct ExperimentalFeature {
    pub name: String,
    pub stage: ExperimentalFeatureStage,  // 使用阶段枚举
    pub display_name: Option<String>,
    pub description: Option<String>,
    pub announcement: Option<String>,
    pub enabled: bool,
    pub default_enabled: bool,
}
```

## 依赖与外部交互

### 上游依赖

| 依赖 | 说明 |
|------|------|
| `serde` | 序列化/反序列化（camelCase 命名） |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 下游消费者

- **UI 渲染**: 根据阶段显示不同的标签和样式
- **功能过滤**: 某些界面可能只显示特定阶段的功能
- **权限检查**: 开发中阶段的功能可能限制访问

## 风险、边界与改进建议

### 已知风险

1. **命名混淆**: `"stable"` 阶段仍属于"实验性功能"，概念上有些矛盾
2. **阶段转换**: 阶段转换规则不明确
3. **UI 数据缺失**: 非 beta 阶段 `displayName` 和 `description` 为 null

### 边界情况

1. **未知阶段**: 未来可能增加新阶段，客户端需要处理未知值
2. **阶段回退**: 功能可能从 stable 回退到 underDevelopment
3. **快速迭代**: 阶段可能频繁变化

### 改进建议

1. **重命名**: 考虑将 `"stable"` 改为 `"generalAvailability"` 或 `"production"`
2. **时间线**: 增加每个阶段的进入时间
3. **自动转换**: 定义阶段自动转换规则（如 beta 30 天后自动转 stable）
4. **通知机制**: 阶段变化时通知客户端
5. **阶段权限**: 明确各阶段的访问权限规则

### 扩展示例

```typescript
export type ExperimentalFeatureStage = 
  | { type: "beta"; startedAt: string; feedbackUrl: string }
  | { type: "underDevelopment"; estimatedRelease: string | null }
  | { type: "stable"; releasedAt: string }
  | { type: "deprecated"; replacement: string | null; removalDate: string }
  | { type: "removed"; removedAt: string };
```
