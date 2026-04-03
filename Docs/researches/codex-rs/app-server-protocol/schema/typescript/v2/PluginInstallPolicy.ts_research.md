# PluginInstallPolicy.ts 调研文档

## 场景与职责

`PluginInstallPolicy` 是 Codex 应用服务器协议中用于定义插件安装策略的枚举类型。该类型主要用于以下场景：

1. **插件市场管理**：在插件市场中标识插件的安装可用性状态
2. **权限控制**：决定用户是否可以安装特定插件
3. **默认安装策略**：标识哪些插件应该被默认安装
4. **企业/组织策略**：支持管理员控制插件的分发和安装权限

该枚举在 `PluginSummary` 类型中被引用，用于描述每个插件的安装策略状态。

## 功能点目的

`PluginInstallPolicy` 定义了三种安装策略状态：

| 策略值 | 含义 | 使用场景 |
|--------|------|----------|
| `NOT_AVAILABLE` | 插件不可用 | 插件被禁用、下架或不符合当前环境要求 |
| `AVAILABLE` | 插件可用 | 用户可以选择安装该插件 |
| `INSTALLED_BY_DEFAULT` | 默认安装 | 插件应该被自动安装，无需用户手动操作 |

### 设计目的

1. **分层权限控制**：区分"完全不可用"、"可选安装"和"强制安装"三种级别
2. **企业场景支持**：允许组织设置必须安装的插件（如合规、安全相关插件）
3. **市场运营**：支持插件的灰度发布、限时试用等运营策略

## 具体技术实现

### TypeScript 定义

```typescript
export type PluginInstallPolicy = "NOT_AVAILABLE" | "AVAILABLE" | "INSTALLED_BY_DEFAULT";
```

### Rust 源码定义

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

### 序列化特性

- 使用 `#[serde(rename_all = "SCREAMING_SNAKE_CASE")]` 风格的大写下划线命名
- TypeScript 生成时使用相同的命名约定
- 支持 JSON Schema 生成用于验证

## 关键代码路径与文件引用

### 定义位置

- **Rust 源码**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3249-3259 行)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallPolicy.ts`

### 引用位置

1. **PluginSummary** (`v2.rs` 第 3275-3284 行)
   ```rust
   pub struct PluginSummary {
       // ...
       pub install_policy: PluginInstallPolicy,
       // ...
   }
   ```

2. **测试文件**
   - `codex-rs/app-server/tests/suite/v2/plugin_list.rs`：验证插件列表中的安装策略
   - `codex-rs/app-server/tests/suite/v2/plugin_install.rs`：验证安装流程中的策略检查

### 使用示例

```rust
// 在插件列表响应中使用
let plugin = PluginSummary {
    id: "plugin-id".to_string(),
    name: "plugin-name".to_string(),
    // ...
    install_policy: PluginInstallPolicy::Available,
    // ...
};
```

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `serde` | 序列化/反序列化支持 |
| `ts-rs` | TypeScript 类型生成 |
| `schemars` | JSON Schema 生成 |

### 外部交互

1. **插件市场 JSON 文件**
   - 在 `marketplace.json` 中通过 `policy.installation` 字段定义
   - 示例：
     ```json
     {
       "name": "demo-plugin",
       "policy": {
         "installation": "AVAILABLE"
       }
     }
     ```

2. **配置系统**
   - 与 `config.toml` 中的插件配置联动
   - 影响插件的 `installed` 和 `enabled` 状态

## 风险、边界与改进建议

### 潜在风险

1. **策略冲突**：`INSTALLED_BY_DEFAULT` 与用户在配置中显式禁用插件时可能产生冲突
2. **版本兼容性**：策略变更可能导致已安装插件的状态不一致
3. **权限绕过**：客户端需要严格验证 `NOT_AVAILABLE` 插件的安装请求

### 边界情况

| 场景 | 行为 |
|------|------|
| 策略为 `NOT_AVAILABLE` 但已安装 | 保持已安装状态，但显示为不可用 |
| 策略从 `AVAILABLE` 变为 `NOT_AVAILABLE` | 已安装的插件继续工作，新安装被阻止 |
| `INSTALLED_BY_DEFAULT` 但用户已卸载 | 需要定义重新安装策略 |

### 改进建议

1. **增加策略说明字段**
   ```rust
   pub struct PluginInstallPolicyInfo {
       pub policy: PluginInstallPolicy,
       pub reason: Option<String>, // 策略原因说明
       pub effective_until: Option<i64>, // 策略有效期
   }
   ```

2. **支持条件策略**
   - 基于用户角色、组织、地理位置等条件动态决定策略

3. **策略优先级**
   - 明确用户配置、组织策略、市场默认策略之间的优先级关系

4. **审计日志**
   - 记录策略变更历史，便于追踪插件可用性变化

5. **客户端缓存策略**
   - 定义策略的缓存时间，平衡实时性与性能
