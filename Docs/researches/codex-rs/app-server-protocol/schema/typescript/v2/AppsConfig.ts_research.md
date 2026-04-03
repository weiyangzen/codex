# AppsConfig 类型研究文档

## 1. 场景与职责

### 使用场景
`AppsConfig` 是 Codex App-Server Protocol v2 中用于配置和管理外部应用（Apps/Connectors）的核心配置类型。它允许用户通过配置文件（如 `config.toml`）来精细控制各个应用的启用状态、工具权限和行为模式。

### 主要职责
- **应用配置管理**：为每个应用提供独立的配置命名空间
- **默认配置继承**：通过 `_default` 字段提供全局默认配置
- **工具权限控制**：管理应用内各个工具的启用状态和审批模式
- **安全策略配置**：控制破坏性操作和开放世界（open-world）功能的启用

### 使用示例
```toml
[apps]
_default = { enabled = true, destructive_enabled = false, open_world_enabled = false }

[apps.slack]
enabled = true
destructive_enabled = false
open_world_enabled = true
default_tools_approval_mode = "prompt"

[apps.slack.tools.send_message]
enabled = true
approval_mode = "auto"
```

---

## 2. 功能点目的

### 2.1 默认配置继承（`_default`）
- **目的**：为所有应用提供统一的默认行为基准
- **机制**：当特定应用未显式配置某个字段时，继承 `_default` 中的值
- **优势**：减少重复配置，便于统一管理

### 2.2 应用级配置（动态键）
- **目的**：为每个应用提供独立的配置空间
- **键名**：应用标识符（如 `"slack"`, `"github"` 等）
- **值类型**：包含完整应用配置的对象

### 2.3 工具配置嵌套（`tools`）
- **目的**：精细控制应用内各个工具的权限
- **支持**：启用/禁用、审批模式（auto/prompt/approve）

### 2.4 安全控制字段
| 字段 | 用途 |
|------|------|
| `enabled` | 应用总开关 |
| `destructive_enabled` | 允许破坏性操作（删除、修改） |
| `open_world_enabled` | 允许开放世界访问（网络、外部系统） |
| `default_tools_approval_mode` | 默认工具审批模式 |
| `default_tools_enabled` | 默认工具启用状态 |

---

## 3. 具体技术实现

### 3.1 TypeScript 类型定义
```typescript
export type AppsConfig = { 
    _default: AppsDefaultConfig | null, 
} & ({ 
    [key in string]?: { 
        enabled: boolean, 
        destructive_enabled: boolean | null, 
        open_world_enabled: boolean | null, 
        default_tools_approval_mode: AppToolApproval | null, 
        default_tools_enabled: boolean | null, 
        tools: AppToolsConfig | null, 
    } 
});
```

### 3.2 Rust 源类型定义
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct AppsConfig {
    #[serde(default, rename = "_default")]
    pub default: Option<AppsDefaultConfig>,
    #[serde(default, flatten)]
    pub apps: HashMap<String, AppConfig>,
}
```

### 3.3 关联类型
| 类型 | 文件 | 说明 |
|------|------|------|
| `AppsDefaultConfig` | `AppsDefaultConfig.ts` | 默认配置结构 |
| `AppToolApproval` | `AppToolApproval.ts` | 工具审批模式枚举 |
| `AppToolsConfig` | `AppToolsConfig.ts` | 工具配置映射 |
| `AppConfig` | v2.rs (内部) | 单个应用配置 |

### 3.4 序列化特性
- **命名规范**：Rust 使用 `snake_case`，TypeScript 保持 camelCase
- `_default` 字段**：Rust 中使用 `rename` 属性映射，避免与 Rust 关键字冲突
- **扁平化**：`apps` 字段使用 `flatten` 属性，在 JSON 中直接展开为动态键

---

## 4. 关键代码路径与文件引用

### 4.1 源文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| v2.rs | `codex-rs/app-server-protocol/src/protocol/v2.rs:674-679` | Rust 源类型定义 |

### 4.2 生成文件位置
| 文件 | 路径 | 说明 |
|------|------|------|
| AppsConfig.ts | `codex-rs/app-server-protocol/schema/typescript/v2/AppsConfig.ts` | TypeScript 类型定义 |
| JSON Schema | `codex-rs/app-server-protocol/schema/json/v2/AppsConfig.json` | JSON Schema 定义 |

### 4.3 使用位置
| 文件 | 路径 | 用途 |
|------|------|------|
| Config | `v2.rs:724` | 作为 Config 结构体的字段 |
| config.rs | `codex-rs/core/src/config/mod.rs` | 配置加载和合并 |
| config_loader | `codex-rs/core/src/config_loader/` | 配置文件解析 |

### 4.4 代码引用链
```
Config::apps (Option<AppsConfig>)
    ├── AppsConfig::_default (Option<AppsDefaultConfig>)
    └── AppsConfig::apps (HashMap<String, AppConfig>)
            ├── AppConfig::enabled
            ├── AppConfig::destructive_enabled
            ├── AppConfig::open_world_enabled
            ├── AppConfig::default_tools_approval_mode (Option<AppToolApproval>)
            ├── AppConfig::default_tools_enabled
            └── AppConfig::tools (Option<AppToolsConfig>)
                    └── HashMap<String, AppToolConfig>
                            ├── AppToolConfig::enabled
                            └── AppToolConfig::approval_mode
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖
```typescript
import type { AppToolApproval } from "./AppToolApproval";
import type { AppToolsConfig } from "./AppToolsConfig";
import type { AppsDefaultConfig } from "./AppsDefaultConfig";
```

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
| App List API | `app/list` | 应用列表与配置联动 |
| MCP Server | 内部调用 | 应用工具的执行控制 |
| TUI/CLI | 配置界面 | 用户配置交互 |

### 5.4 配置层级
```
MDM (最高优先级)
    ↓
System config.toml
    ↓
User config.toml (~/.codex/config.toml)
    ↓
Project .codex/config.toml
    ↓
Session flags (-c/--config)
    ↓
Legacy managed_config.toml
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：动态键的类型安全
- **问题**：TypeScript 中 `[key in string]?` 允许任意字符串键，但运行时可能传入无效的应用标识符
- **影响**：配置可能包含不存在的应用配置，导致静默失败
- **缓解**：在应用层进行应用标识符验证

#### 风险 2：null vs undefined 混淆
- **问题**：TypeScript 类型中字段可为 `null`，但某些场景下可能期望 `undefined`
- **影响**：可能导致类型检查通过但运行时行为异常
- **缓解**：统一使用 `null` 表示缺失，避免 `undefined`

#### 风险 3：配置冲突
- **问题**：多层配置合并时，`_default` 和具体应用配置可能产生意外覆盖
- **影响**：用户可能困惑于最终生效的配置
- **缓解**：提供配置溯源功能（`config/read` 返回层级信息）

### 6.2 边界情况

| 场景 | 行为 | 说明 |
|------|------|------|
| `_default` 为 `null` | 使用硬编码默认值 | 所有布尔字段默认为 `true` |
| 应用配置缺失字段 | 继承 `_default` 或系统默认 | 遵循配置层级规则 |
| 未知应用标识符 | 静默接受 | 需在应用层验证 |
| 空 `tools` 对象 | 表示无特殊工具配置 | 使用 `default_tools_*` 设置 |

### 6.3 改进建议

#### 建议 1：添加应用标识符校验
```rust
// 在配置加载时验证应用标识符
pub fn validate_app_id(id: &str) -> Result<(), ConfigError> {
    // 验证应用是否存在于注册表
}
```

#### 建议 2：增强类型安全性
```typescript
// 使用模板字面量类型限制应用标识符
export type KnownAppId = 'slack' | 'github' | 'jira' | ...;
export type AppsConfig = {
    _default: AppsDefaultConfig | null,
} & {
    [K in KnownAppId]?: AppConfig;
} & {
    [key: string]: AppConfig | undefined; // 允许扩展
};
```

#### 建议 3：配置变更通知
- 当前：配置变更需手动刷新
- 建议：添加配置变更事件通知机制，使客户端能实时感知配置更新

#### 建议 4：配置迁移工具
- 提供从旧版本配置格式自动迁移的工具
- 在配置加载时自动修复不兼容的字段

#### 建议 5：文档生成
- 基于类型定义自动生成配置文档
- 包含每个字段的详细说明和示例

### 6.4 实验性状态
- `AppsConfig` 目前标记为实验性功能（`#[experimental("config/read.apps")]`）
- API 可能在后续版本中发生变化
- 建议生产环境使用时关注版本更新说明
