# PluginInstallPolicy 研究文档

## 1. 场景与职责

`PluginInstallPolicy` 是一个枚举类型，定义了插件在系统中的安装策略状态。它用于插件市场系统中，表示插件对当前用户的可用性和安装状态。

**使用场景：**
- 插件市场列表展示：向用户显示插件的安装选项
- 插件详情页面：指示用户可以对插件执行的操作
- 插件安装流程：决定插件是否可以被安装
- 默认插件管理：标识哪些插件是系统预装的

## 2. 功能点目的

该枚举的核心目的是标准化插件的安装策略，使客户端能够：

1. **区分插件可用性**：明确插件是否可供安装
2. **管理默认插件**：标识系统预装的插件
3. **控制用户交互**：根据策略决定UI中显示的按钮和操作

**三个策略级别：**
- `NOT_AVAILABLE`：插件不可用，用户无法安装
- `AVAILABLE`：插件可用，用户可以手动安装
- `INSTALLED_BY_DEFAULT`：插件默认已安装，通常是系统核心功能

## 3. 具体技术实现

### TypeScript 定义
```typescript
export type PluginInstallPolicy = "NOT_AVAILABLE" | "AVAILABLE" | "INSTALLED_BY_DEFAULT";
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub enum PluginInstallPolicy {
    #[serde(rename = "NOT_AVAILABLE")]
    #[ts(rename = "NOT_AVAILABLE")]
    NotAvailable,
    #[serde(rename = "AVAILABLE")]
    #[ts(rename = "AVAILABLE")]
    Available,
    #[serde(rename = "INSTALLED_BY_DEFAULT")]
    #[ts(rename = "INSTALLED_BY_DEFAULT")]
    InstalledByDefault,
}
```

### 关键特性
- 使用 `#[derive(Copy)]` 实现轻量级复制语义
- 使用 `#[derive(PartialEq, Eq)]` 支持相等性比较
- 序列化/反序列化使用大写下划线命名（SCREAMING_SNAKE_CASE）

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3247-3259

**使用位置：**
- `PluginSummary` 结构体中的 `install_policy` 字段（行3281）
- 插件市场列表和详情API的响应数据

**相关类型：**
- `PluginSummary`：包含此策略的插件摘要信息
- `PluginAuthPolicy`：关联的认证策略枚举

## 5. 依赖与外部交互

**无外部依赖**

这是一个独立的枚举类型，不依赖其他类型。但它是以下类型的组成部分：
- `PluginSummary.install_policy`

## 6. 风险、边界与改进建议

### 潜在风险
1. **策略冲突**：`INSTALLED_BY_DEFAULT` 与 `installed: false` 的组合可能产生逻辑矛盾
2. **状态转换**：缺乏明确的状态转换规则（如从 AVAILABLE 到 INSTALLED_BY_DEFAULT）

### 边界情况
- 当 `install_policy` 为 `NOT_AVAILABLE` 时，`installed` 字段应该始终为 `false`
- `INSTALLED_BY_DEFAULT` 的插件理论上不应该被卸载

### 改进建议
1. **添加验证逻辑**：在服务器端验证策略与安装状态的一致性
2. **考虑添加更多状态**：如 `PENDING_INSTALL`、`INSTALLING` 等中间状态
3. **文档化策略规则**：明确每种策略对应的用户操作权限
