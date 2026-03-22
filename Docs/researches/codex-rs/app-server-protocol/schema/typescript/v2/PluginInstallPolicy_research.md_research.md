# PluginInstallPolicy 深度研究文档

## 1. 场景与职责

### 1.1 核心定位

`PluginInstallPolicy` 是 Codex 插件市场系统的核心枚举类型，定义了插件对当前用户的**可用性和安装策略**。它位于应用服务器协议层（app-server-protocol），是连接核心插件管理逻辑与客户端 UI 展示的关键桥梁。

### 1.2 使用场景

| 场景 | 职责描述 |
|------|----------|
| **插件市场列表展示** | `plugin/list` API 返回插件列表时，通过 `install_policy` 字段告知客户端每个插件的安装权限 |
| **插件详情页面** | `plugin/read` API 在 `PluginDetail.summary.install_policy` 中提供单个插件的策略信息 |
| **插件安装流程控制** | 服务端在 `resolve_marketplace_plugin()` 中根据策略决定是否允许安装请求继续执行 |
| **默认插件管理** | 标识系统预装的核心功能插件，这类插件通常不允许卸载 |
| **UI 交互决策** | 客户端根据策略决定显示"安装"、"已安装"或"不可用"等不同的按钮状态 |

### 1.3 策略语义

```
NOT_AVAILABLE        →  插件对用户不可见或不可安装（如区域限制、产品版本限制）
AVAILABLE            →  插件可供用户手动安装（默认状态）
INSTALLED_BY_DEFAULT →  插件默认已安装，通常是系统核心功能（如官方 curated 插件）
```

---

## 2. 功能点目的

### 2.1 设计目标

1. **标准化插件可用性表达**：统一服务端和客户端对插件安装权限的理解
2. **支持分级发布策略**：允许插件按用户群体、产品版本、地域等维度进行灰度发布
3. **区分系统插件与用户插件**：明确标识不可卸载的系统核心插件
4. **简化客户端逻辑**：客户端仅需根据枚举值渲染对应 UI，无需理解复杂业务规则

### 2.2 与相关字段的协作

`PluginInstallPolicy` 与 `PluginSummary` 中的其他字段共同构成完整的插件状态描述：

```rust
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,
    pub installed: bool,           // 实际安装状态
    pub enabled: bool,             // 是否启用
    pub install_policy: PluginInstallPolicy,  // 安装策略（本研究对象）
    pub auth_policy: PluginAuthPolicy,        // 认证策略（关联）
    pub interface: Option<PluginInterface>,   // 展示信息
}
```

**关键组合逻辑：**
- `install_policy: NOT_AVAILABLE` → `installed` 应该始终为 `false`
- `install_policy: INSTALLED_BY_DEFAULT` → `installed` 通常为 `true`，且理论上不可卸载
- `install_policy: AVAILABLE` + `installed: false` → 显示"安装"按钮
- `install_policy: AVAILABLE` + `installed: true` → 显示"已安装"或"卸载"按钮

---

## 3. 具体技术实现

### 3.1 类型定义

#### Rust 源实现（协议层）

**文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3247-3259)

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

**关键特性：**
- `Copy` trait：轻量级值类型，可随意复制无需 Clone
- `PartialEq + Eq`：支持相等性比较，便于测试和条件判断
- `JsonSchema`：自动生成 JSON Schema 文档
- `TS` (ts-rs)：自动生成 TypeScript 类型定义

#### TypeScript 生成定义

**文件**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallPolicy.ts`

```typescript
export type PluginInstallPolicy = "NOT_AVAILABLE" | "AVAILABLE" | "INSTALLED_BY_DEFAULT";
```

#### JSON Schema 定义

**文件**: `codex-rs/app-server-protocol/schema/json/v2/PluginListResponse.json` (行 26-33)

```json
"PluginInstallPolicy": {
  "enum": ["NOT_AVAILABLE", "AVAILABLE", "INSTALLED_BY_DEFAULT"],
  "type": "string"
}
```

### 3.2 核心层映射

**文件**: `codex-rs/core/src/plugins/marketplace.rs` (行 64-91)

核心层定义了对应的 `MarketplacePluginInstallPolicy` 枚举，并通过 `From` trait 实现与协议层的转换：

```rust
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
pub enum MarketplacePluginInstallPolicy {
    #[serde(rename = "NOT_AVAILABLE")]
    NotAvailable,
    #[default]
    #[serde(rename = "AVAILABLE")]
    Available,
    #[serde(rename = "INSTALLED_BY_DEFAULT")]
    InstalledByDefault,
}

// 自动派生 Default 使 AVAILABLE 成为默认值

impl From<MarketplacePluginInstallPolicy> for PluginInstallPolicy {
    fn from(value: MarketplacePluginInstallPolicy) -> Self {
        match value {
            MarketplacePluginInstallPolicy::NotAvailable => Self::NotAvailable,
            MarketplacePluginInstallPolicy::Available => Self::Available,
            MarketplacePluginInstallPolicy::InstalledByDefault => Self::InstalledByDefault,
        }
    }
}
```

### 3.3 策略执行逻辑

#### 安装前检查

**文件**: `codex-rs/core/src/plugins/marketplace.rs` (行 146-186)

```rust
pub fn resolve_marketplace_plugin(
    marketplace_path: &AbsolutePathBuf,
    plugin_name: &str,
) -> Result<ResolvedMarketplacePlugin, MarketplaceError> {
    // ... 查找插件逻辑 ...
    
    let install_policy = policy.installation;
    if install_policy == MarketplacePluginInstallPolicy::NotAvailable {
        return Err(MarketplaceError::PluginNotAvailable {
            plugin_name: name,
            marketplace_name,
        });
    }
    
    // ... 继续安装流程 ...
}
```

**关键行为**：当 `install_policy` 为 `NOT_AVAILABLE` 时，服务端会返回 `PluginNotAvailable` 错误，阻止安装流程继续。

#### 错误分类处理

**文件**: `codex-rs/core/src/plugins/manager.rs` (行 1196-1208)

```rust
impl PluginInstallError {
    pub fn is_invalid_request(&self) -> bool {
        matches!(
            self,
            Self::Marketplace(
                MarketplaceError::MarketplaceNotFound { .. }
                    | MarketplaceError::InvalidMarketplaceFile { .. }
                    | MarketplaceError::PluginNotFound { .. }
                    | MarketplaceError::PluginNotAvailable { .. }  // ← 策略拒绝归类为无效请求
                    | MarketplaceError::InvalidPlugin(_)
            ) | Self::Store(PluginStoreError::Invalid(_))
        )
    }
}
```

`PluginNotAvailable` 被归类为 `is_invalid_request()`，这意味着客户端会收到 `-32600 Invalid request` JSON-RPC 错误，而非服务器内部错误。

### 3.4 数据流向

```
marketplace.json (磁盘)
    ↓ 反序列化
RawMarketplaceManifestPluginPolicy::installation: MarketplacePluginInstallPolicy
    ↓ 加载到内存
MarketplacePluginPolicy::installation
    ↓ 转换 (From trait)
PluginSummary::install_policy: PluginInstallPolicy
    ↓ 序列化 (JSON-RPC 响应)
客户端收到的 "installPolicy": "AVAILABLE" | "NOT_AVAILABLE" | "INSTALLED_BY_DEFAULT"
```

### 3.5 marketplace.json 配置示例

```json
{
  "name": "codex-curated",
  "plugins": [
    {
      "name": "demo-plugin",
      "source": {
        "source": "local",
        "path": "./plugins/demo-plugin"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      }
    },
    {
      "name": "core-plugin",
      "source": {
        "source": "local",
        "path": "./plugins/core"
      },
      "policy": {
        "installation": "INSTALLED_BY_DEFAULT",
        "authentication": "ON_USE"
      }
    }
  ]
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 类型定义

| 文件路径 | 行号 | 说明 |
|----------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3247-3259 | `PluginInstallPolicy` 枚举定义 |
| `codex-rs/core/src/plugins/marketplace.rs` | 64-72 | `MarketplacePluginInstallPolicy` 核心层定义 |
| `codex-rs/core/src/plugins/marketplace.rs` | 83-91 | `From<MarketplacePluginInstallPolicy>` 转换实现 |

### 4.2 使用位置

| 文件路径 | 行号 | 使用场景 |
|----------|------|----------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3281 | `PluginSummary` 结构体字段定义 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 5531 | `plugin/list` 响应构造时转换策略值 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 5643 | `plugin/read` 响应构造时转换策略值 |
| `codex-rs/core/src/plugins/marketplace.rs` | 171 | `resolve_marketplace_plugin()` 策略检查 |
| `codex-rs/core/src/plugins/marketplace.rs` | 222 | `load_marketplace()` 加载策略到内存 |

### 4.3 测试覆盖

| 文件路径 | 行号 | 测试内容 |
|----------|------|----------|
| `codex-rs/app-server/tests/suite/v2/plugin_list.rs` | 11, 261, 273, 288, 483 | 验证列表返回的策略值 |
| `codex-rs/app-server/tests/suite/v2/plugin_read.rs` | 8, 146 | 验证详情返回的策略值 |
| `codex-rs/core/src/plugins/manager_tests.rs` | 977, 993, 1178, 1281, 1310, 1392 | 核心层策略加载测试 |
| `codex-rs/core/src/plugins/marketplace_tests.rs` | 149, 161, 182, 194, 270, 287, 357, 514, 581, 655 | 市场层策略解析测试 |

### 4.4 生成文件

| 文件路径 | 说明 |
|----------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallPolicy.ts` | TypeScript 类型定义（自动生成） |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginSummary.ts` | 引用该类型的结构体定义 |
| `codex-rs/app-server-protocol/schema/json/v2/PluginListResponse.json` | JSON Schema 定义（行 26-33） |
| `codex-rs/app-server-protocol/schema/json/v2/PluginReadResponse.json` | JSON Schema 定义（行 89-96） |
| `codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.v2.schemas.json` | 完整协议 Schema（行 6018-6025） |

---

## 5. 依赖与外部交互

### 5.1 直接依赖

```
PluginInstallPolicy
├── serde (Serialize, Deserialize)  ← 序列化支持
├── schemars (JsonSchema)           ← JSON Schema 生成
├── ts-rs (TS)                      ← TypeScript 类型生成
└── PartialEq, Eq, Copy, Clone, Debug  ← 标准 trait
```

### 5.2 被依赖关系

```
PluginInstallPolicy
├── PluginSummary::install_policy              ← 被包含结构体
├── PluginDetail::summary::install_policy      ← 被嵌套包含
├── PluginListResponse::marketplaces[].plugins[].install_policy  ← API 响应
├── PluginReadResponse::plugin.summary.install_policy            ← API 响应
└── MarketplaceError::PluginNotAvailable       ← 策略拒绝错误类型
```

### 5.3 协议集成

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 343-346)

```rust
PluginInstall => "plugin/install" {
    params: v2::PluginInstallParams,
    response: v2::PluginInstallResponse,  // 注意：响应中不包含策略，但安装流程会检查策略
}
```

### 5.4 核心层到协议层的转换链

```
MarketplacePluginInstallPolicy (core)
    ↓ From trait
PluginInstallPolicy (app-server-protocol)
    ↓ ts-rs 宏
"AVAILABLE" | "NOT_AVAILABLE" | "INSTALLED_BY_DEFAULT" (TypeScript/JSON)
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 风险 1：策略与状态不一致

**问题**：`install_policy: INSTALLED_BY_DEFAULT` 与 `installed: false` 的组合在逻辑上矛盾，但当前系统允许这种数据存在。

**影响**：客户端可能困惑于"默认安装但未安装"的状态，导致 UI 展示异常。

**代码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3275-3284)

#### 风险 2：NOT_AVAILABLE 插件仍可见

**问题**：`NOT_AVAILABLE` 仅阻止安装操作，但插件仍会在列表 API 中返回给客户端。

**影响**：客户端需要额外过滤逻辑来隐藏这些插件，增加了客户端复杂度。

#### 风险 3：缺乏中间状态

**问题**：当前策略是静态的，没有 `INSTALLING`、`PENDING_APPROVAL` 等中间状态。

**影响**：长时间安装操作中，客户端无法展示准确的进度状态。

### 6.2 边界情况

| 场景 | 当前行为 | 建议 |
|------|----------|------|
| `NOT_AVAILABLE` + `installed: true` | 技术上可能（手动安装后策略变更） | 应在服务端验证时警告 |
| `INSTALLED_BY_DEFAULT` + 用户卸载 | 未明确定义行为 | 应禁止卸载或降级为 `AVAILABLE` |
| 策略字段缺失 | 默认 `AVAILABLE`（通过 `#[default]`） | 行为符合预期 |
| 未知策略值 | 反序列化失败，返回错误 | 需要错误处理 |

### 6.3 改进建议

#### 建议 1：添加服务端验证

在 `PluginSummary` 构造时添加一致性验证：

```rust
impl PluginSummary {
    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.install_policy == PluginInstallPolicy::NotAvailable && self.installed {
            return Err(ValidationError::InconsistentState(
                "NOT_AVAILABLE plugin cannot be installed"
            ));
        }
        Ok(())
    }
}
```

#### 建议 2：扩展策略语义

考虑添加更细粒度的策略：

```rust
pub enum PluginInstallPolicy {
    NotAvailable,           // 完全不可见
    VisibleButNotInstallable { reason: String },  // 可见但不可安装（带原因）
    Available,              // 可安装
    PreInstalled,           // 预装但可卸载
    InstalledByDefault,     // 预装且不可卸载
}
```

#### 建议 3：客户端策略过滤

在 `plugin/list` 服务端实现中添加可选过滤参数：

```rust
pub struct PluginListParams {
    pub cwds: Option<Vec<AbsolutePathBuf>>,
    pub force_remote_sync: bool,
    #[serde(default)]
    pub include_not_available: bool,  // 默认 false，隐藏 NOT_AVAILABLE 插件
}
```

#### 建议 4：策略变更通知

当插件策略从 `AVAILABLE` 变更为 `NOT_AVAILABLE` 时，已安装实例的处理策略需要明确：
- 选项 A：自动卸载（风险高）
- 选项 B：保持安装但禁止新安装（当前隐式行为）
- 选项 C：添加 `DEPRECATED` 状态，提示用户即将移除

### 6.4 测试建议

当前测试主要验证策略值的正确传递，建议补充：

1. **边界测试**：`NOT_AVAILABLE` 插件的安装请求被拒绝
2. **一致性测试**：策略与安装状态的组合验证
3. **序列化测试**：未知策略值的错误处理
4. **性能测试**：大量插件的策略转换效率

---

## 附录：相关类型速查

```rust
// 协议层（app-server-protocol）
PluginInstallPolicy          // 本研究对象
PluginAuthPolicy            // 关联：认证策略
PluginSummary               // 包含 install_policy
PluginDetail                // 包含 PluginSummary
PluginMarketplaceEntry      // 包含 PluginSummary 列表

// 核心层（core）
MarketplacePluginInstallPolicy      // 核心层对应枚举
MarketplacePluginPolicy             // 包含 installation 策略
MarketplaceError::PluginNotAvailable // 策略拒绝错误
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/app-server-protocol/src/protocol/v2.rs (行 3247-3259)*
