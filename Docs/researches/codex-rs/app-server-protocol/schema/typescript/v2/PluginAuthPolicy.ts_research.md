# PluginAuthPolicy 研究文档

## 场景与职责

`PluginAuthPolicy` 是一个枚举类型，定义了插件的认证策略。它决定了插件在何时向用户请求认证（如 OAuth 登录）。

## 功能点目的

该类型的核心功能是：
1. **认证时机控制**: 定义插件何时需要用户认证
2. **用户体验优化**: 允许延迟认证到实际使用时，减少初始安装摩擦
3. **安全策略**: 支持不同的认证触发策略

## 具体技术实现

### 数据结构

```typescript
export type PluginAuthPolicy = "ON_INSTALL" | "ON_USE";
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub enum PluginAuthPolicy {
    #[serde(rename = "ON_INSTALL")]
    #[ts(rename = "ON_INSTALL")]
    OnInstall,
    #[serde(rename = "ON_USE")]
    #[ts(rename = "ON_USE")]
    OnUse,
}
```

### 枚举值详解

| 枚举值 | 说明 |
|-------|------|
| `ON_INSTALL` | 安装时认证：插件安装时立即请求用户认证 |
| `ON_USE` | 使用时认证：首次使用插件功能时才请求认证 |

### 序列化配置

使用大写蛇形命名（SCREAMING_SNAKE_CASE）进行序列化：
- `OnInstall` → `"ON_INSTALL"`
- `OnUse` → `"ON_USE"`

### 使用场景

该枚举主要用于 `PluginSummary` 和 `PluginInstallResponse` 类型：

```rust
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,
    pub installed: bool,
    pub enabled: bool,
    pub install_policy: PluginInstallPolicy,
    pub auth_policy: PluginAuthPolicy,  // <-- 这里
    pub interface: Option<PluginInterface>,
}

pub struct PluginInstallResponse {
    pub auth_policy: PluginAuthPolicy,  // <-- 这里
    pub apps_needing_auth: Vec<AppSummary>,
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 3261-3270 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginAuthPolicy.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 依赖类型
- `PluginSummary`: 使用该枚举描述插件的认证策略
- `PluginInstallResponse`: 返回插件的认证策略

### 协议集成
- 属于 App-Server Protocol v2 API
- 用于插件管理相关的 API 响应

### 插件系统集成
- 影响插件安装流程
- 决定何时触发 OAuth 或其他认证流程

## 风险、边界与改进建议

### 潜在风险
1. **认证失败**: `ON_INSTALL` 策略可能因用户拒绝认证而导致安装失败
2. **延迟发现问题**: `ON_USE` 策略可能导致用户在需要时才发现认证问题
3. **策略变更**: 插件更新时认证策略变更的处理

### 边界情况
1. **可选认证**: 某些插件可能认证是可选的，但当前枚举不支持
2. **多阶段认证**: 复杂插件可能需要多次认证
3. **认证过期**: 认证令牌过期后的重新认证策略

### 改进建议
1. 考虑添加 `OPTIONAL` 变体，表示认证是可选的
2. 添加 `PERIODIC` 变体，支持定期重新认证
3. 考虑添加 `NEVER` 变体，表示插件不需要认证
4. 支持按功能细分的认证策略（如某些功能需要认证，其他不需要）
5. 添加认证过期策略配置
