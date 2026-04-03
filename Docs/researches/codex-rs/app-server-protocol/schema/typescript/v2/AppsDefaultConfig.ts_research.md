# AppsDefaultConfig 类型研究文档

## 1. 场景与职责

### 使用场景
`AppsDefaultConfig` 是 Codex App-Server Protocol v2 中用于定义应用（Apps/Connectors）全局默认配置的基础类型。它作为 `AppsConfig` 结构中的 `_default` 字段，为所有未显式配置的应用提供统一的默认行为基准。

### 主要职责
- **全局默认配置**：为所有应用提供统一的初始配置值
- **配置继承基础**：作为应用级配置的继承源，减少重复配置
- **安全基线设置**：定义应用功能的默认安全策略（启用/禁用状态）
- **简化配置管理**：用户只需在 `_default` 中配置一次，所有应用自动继承

### 使用示例
```toml
# config.toml
[apps]
# 设置全局默认值
_default = { enabled = true, destructive_enabled = false, open_world_enabled = false }

# 特定应用可以覆盖默认值
[apps.slack]
enabled = true  # 继承 _default 的其他值

[apps.github]
enabled = true
destructive_enabled = true  # 覆盖默认值
```

---

## 2. 功能点目的

### 2.1 应用启用控制（`enabled`）
- **目的**：控制应用是否可用
- **默认值**：`true`（在 Rust 中通过 `default_enabled()` 函数设置）
- **行为**：当为 `false` 时，应用完全禁用，其所有工具不可用

### 2.2 破坏性操作控制（`destructive_enabled`）
- **目的**：控制应用是否可以执行破坏性操作
- **破坏性操作定义**：删除文件、修改数据、发送消息等不可逆操作
- **默认值**：`true`（在 Rust 中设置）
- **安全意义**：即使应用启用，也可以单独限制其破坏性能力

### 2.3 开放世界访问控制（`open_world_enabled`）
- **目的**：控制应用是否可以访问外部系统（网络、第三方 API）
- **默认值**：`true`
- **安全意义**：限制应用的数据外泄风险，适用于敏感环境

### 2.4 配置继承机制
```
AppsDefaultConfig (全局默认值)
    ↓ 继承
AppConfig (特定应用配置，可覆盖)
    ↓ 继承 + 合并
AppToolConfig (特定工具配置，可覆盖)
```

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
export type AppsDefaultConfig = { 
    enabled: boolean, 
    destructive_enabled: boolean, 
    open_world_enabled: boolean, 
};
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct AppsDefaultConfig {
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default = "default_enabled")]
    pub destructive_enabled: bool,
    #[serde(default = "default_enabled")]
    pub open_world_enabled: bool,
}

const fn default_enabled() -> bool {
    true
}
```

### 3.3 序列化特性
| 特性 | 说明 |
|------|------|
| `rename_all = "snake_case"` | 字段使用蛇形命名法（Rust 端） |
| `default = "default_enabled"` | 字段默认值为 `true` |
| 无 `Option` 包装 | 所有字段都是必填的布尔值 |

### 3.4 默认值策略
```rust
// 所有布尔字段默认启用
const fn default_enabled() -> bool {
    true
}
```

这意味着：
- 如果配置文件中省略某个字段，该功能默认启用
- 采用"默认开放，显式关闭"的安全策略
- 用户必须显式设置为 `false` 来禁用功能

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:633-640` | Rust 源类型定义 |
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:681-683` | 默认函数定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| AppsDefaultConfig.ts | `codex-rs/app-server-protocol/schema/typescript/v2/AppsDefaultConfig.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/AppsDefaultConfig.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| AppsConfig | `v2.rs:676` | 作为 `AppsConfig` 的 `_default` 字段 |
| AppConfig | `v2.rs:661-669` | 特定应用配置，字段与 `AppsDefaultConfig` 对应 |

### 4.4 代码引用链
```
Config
    └── apps: Option<AppsConfig>
            └── _default: Option<AppsDefaultConfig>
                    ├── enabled: bool (default: true)
                    ├── destructive_enabled: bool (default: true)
                    └── open_world_enabled: bool (default: true)
```

### 4.5 配置继承流程
```rust
// 伪代码：配置解析时的默认值处理
impl AppConfig {
    pub fn resolve(&self, defaults: &AppsDefaultConfig) -> ResolvedConfig {
        ResolvedConfig {
            enabled: self.enabled.unwrap_or(defaults.enabled),
            destructive_enabled: self.destructive_enabled.unwrap_or(defaults.destructive_enabled),
            open_world_enabled: self.open_world_enabled.unwrap_or(defaults.open_world_enabled),
        }
    }
}
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
`AppsDefaultConfig` 是一个基础类型，不依赖其他自定义类型。

### 5.2 上游依赖
| 依赖 | 来源 | 用途 |
|------|------|------|
| `ts-rs` | Rust crate | 生成 TypeScript 类型 |
| `schemars` | Rust crate | 生成 JSON Schema |
| `serde` | Rust crate | 序列化/反序列化 |

### 5.3 外部交互
| 交互方 | 交互方式 | 说明 |
|--------|----------|------|
| Config API | `config/read`, `config/write` | 配置的读写操作 |
| AppsConfig | 嵌套使用 | 作为 `_default` 字段类型 |
| 配置加载器 | 默认值应用 | 在配置解析时提供默认值 |

### 5.4 配置合并逻辑
```
配置层级（高优先级到低优先级）：
1. 特定应用显式配置
2. _default 配置
3. 硬编码默认值（全部为 true）
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：默认全开的安全隐患
- **问题**：所有字段默认值为 `true`，可能导致用户无意中启用危险功能
- **影响**：新用户可能不了解配置含义，默认开放所有权限
- **缓解**：
  - 提供配置向导，引导用户理解每个选项
  - 在文档中明确标注安全风险
  - 考虑在敏感环境中使用更保守的默认值

#### 风险 2：布尔值缺乏语义
- **问题**：简单的布尔值无法表达复杂的条件逻辑（如"仅对特定应用启用"）
- **影响**：配置灵活性受限
- **缓解**：未来可考虑支持条件表达式或规则引擎

#### 风险 3：与 AppConfig 的字段重复
- **问题**：`AppsDefaultConfig` 和 `AppConfig` 有相似的字段，但类型不同（`bool` vs `Option<bool>`）
- **影响**：代码重复，维护成本增加
- **缓解**：考虑使用宏或泛型减少重复代码

### 6.2 边界情况

| 场景 | 行为 | 说明 |
|------|------|------|
| `_default` 完全省略 | 所有字段使用硬编码默认值 `true` | 相当于 `_default = { enabled = true, ... }` |
| `_default` 部分省略 | 省略的字段使用默认值 `true` | Serde 的 `default` 属性处理 |
| `_default` 显式设置为 `null` | 所有应用使用各自的默认值或系统默认 | 等同于无全局默认 |
| 与特定应用配置冲突 | 特定应用配置优先 | 遵循配置层级规则 |

### 6.3 改进建议

#### 建议 1：考虑更保守的默认策略
```rust
// 当前实现
const fn default_enabled() -> bool { true }

// 建议：考虑更保守的默认
const fn default_destructive_enabled() -> bool { false }
const fn default_open_world_enabled() -> bool { false }
```

#### 建议 2：添加配置验证
```rust
impl AppsDefaultConfig {
    pub fn validate(&self) -> Result<(), ConfigError> {
        // 验证配置组合的合理性
        if !self.enabled && self.destructive_enabled {
            warn!("应用已禁用但 destructive_enabled 为 true，此设置将被忽略");
        }
        Ok(())
    }
}
```

#### 建议 3：增强文档和注释
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct AppsDefaultConfig {
    /// 是否默认启用所有应用。
    /// 当为 false 时，除非特定应用显式启用，否则所有应用被禁用。
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    
    /// 是否默认允许应用执行破坏性操作（删除、修改等）。
    /// 建议在生产环境中设置为 false。
    #[serde(default = "default_enabled")]
    pub destructive_enabled: bool,
    
    /// 是否默认允许应用访问外部网络和服务。
    /// 在隔离环境中建议设置为 false。
    #[serde(default = "default_enabled")]
    pub open_world_enabled: bool,
}
```

#### 建议 4：支持配置模板
```toml
# 建议支持命名模板
[apps.templates.secure]
enabled = true
destructive_enabled = false
open_world_enabled = false

[apps.templates.permissive]
enabled = true
destructive_enabled = true
open_world_enabled = true

# 应用模板
[apps.slack]
template = "secure"
```

#### 建议 5：运行时配置变更通知
- 当前：配置变更需要重启或手动刷新
- 建议：支持配置热重载，变更时通知相关组件

### 6.4 相关类型对比

| 类型 | 字段类型 | 用途 |
|------|----------|------|
| `AppsDefaultConfig` | `bool` | 全局默认值，必填 |
| `AppConfig` | `Option<bool>` | 特定应用配置，可选覆盖 |

这种设计允许：
1. `AppsDefaultConfig` 提供确定性的默认值
2. `AppConfig` 可以区分"未设置"和"显式设置为 false"
3. 配置合并逻辑清晰明确
