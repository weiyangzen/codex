# PluginInstallResponse 研究文档

## 场景与职责

`PluginInstallResponse` 是 app-server v2 API 中 ClientRequest 的 `plugin/install` 方法的响应类型。它返回插件安装操作的结果，包括认证策略信息和需要授权的应用列表。

该类型是 Codex 插件管理系统的核心组成部分，用于处理从插件市场安装插件后的状态反馈。

## 功能点目的

### 核心功能
1. **返回认证策略**：告知客户端该插件的认证时机（安装时或使用时的）
2. **标识需授权应用**：列出插件中包含的需要用户授权才能使用的应用
3. **支持延迟认证**：允许用户先安装插件，后续再处理应用授权

### 使用场景
- 用户从插件市场安装新插件
- 安装后需要立即进行 OAuth 或其他认证流程
- 安装后需要用户审查并授权插件包含的应用

## 具体技术实现

### 数据结构定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs (lines 3368-3374)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallResponse {
    /// 插件的认证策略
    pub auth_policy: PluginAuthPolicy,
    /// 需要授权的应用列表
    pub apps_needing_auth: Vec<AppSummary>,
}
```

### 认证策略枚举

```rust
// PluginAuthPolicy (lines 3261-3270)
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[ts(export_to = "v2/")]
pub enum PluginAuthPolicy {
    #[serde(rename = "ON_INSTALL")]
    #[ts(rename = "ON_INSTALL")]
    OnInstall,           // 安装时认证
    #[serde(rename = "ON_USE")]
    #[ts(rename = "ON_USE")]
    OnUse,               // 使用时认证
}
```

### 应用摘要结构

```rust
// AppSummary (lines 2027-2047)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AppSummary {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub icon_url: Option<String>,
    pub enabled: bool,
    pub linked: bool,
    pub auth_status: AppAuthStatus,
    pub branding: Option<AppBranding>,
}
```

### 生成的 TypeScript 类型

```typescript
// schema/typescript/v2/PluginInstallResponse.ts
import type { AppSummary } from "./AppSummary";
import type { PluginAuthPolicy } from "./PluginAuthPolicy";

export type PluginInstallResponse = { 
    authPolicy: PluginAuthPolicy, 
    appsNeedingAuth: Array<AppSummary>, 
};
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行 3368-3374：`PluginInstallResponse` 结构体
  - 行 3261-3270：`PluginAuthPolicy` 枚举

### 协议注册
```rust
// codex-rs/app-server-protocol/src/protocol/common.rs (lines 343-346)
client_request_definitions! {
    PluginInstall => "plugin/install" {
        params: v2::PluginInstallParams,
        response: v2::PluginInstallResponse,
    },
}
```

### 请求参数
```rust
// PluginInstallParams (lines 3357-3367)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
    /// 安装前同步远程插件状态
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 相关类型定义
| 类型 | 文件 | 行号 | 说明 |
|------|------|------|------|
| `PluginInstallParams` | v2.rs | 3357-3367 | 对应的请求参数 |
| `PluginAuthPolicy` | v2.rs | 3261-3270 | 认证策略枚举 |
| `AppSummary` | v2.rs | 2027-2047 | 应用摘要 |
| `AppAuthStatus` | v2.rs | 2048-2069 | 应用认证状态 |
| `PluginUninstallResponse` | v2.rs | 3386-3389 | 卸载响应（空结构） |

### 生成的 TypeScript 文件
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallResponse.ts`
- `codex-rs/app-server-protocol/schema/typescript/v2/PluginAuthPolicy.ts`（依赖）
- `codex-rs/app-server-protocol/schema/typescript/v2/AppSummary.ts`（依赖）

## 依赖与外部交互

### 内部依赖
1. **ts-rs**：TypeScript 类型导出
2. **schemars**：JSON Schema 生成
3. **serde**：驼峰命名序列化

### 插件安装流程
```
Client
    ↓
PluginInstallParams { marketplace_path, plugin_name, force_remote_sync }
    ↓
POST plugin/install
    ↓
Server 处理：
    1. 验证 marketplace_path 和 plugin_name
    2. 如 force_remote_sync=true，同步远程状态
    3. 执行安装流程
    4. 确定 auth_policy
    5. 识别 apps_needing_auth
    ↓
PluginInstallResponse { auth_policy, apps_needing_auth }
    ↓
Client 根据响应：
    - 如 auth_policy=OnInstall 且 apps_needing_auth 非空，提示授权
    - 如 auth_policy=OnUse，延迟到使用时再授权
```

### 认证策略对比
| 策略 | 说明 | 适用场景 |
|------|------|----------|
| `OnInstall` | 安装时要求完成所有认证 | 安全敏感、企业环境 |
| `OnUse` | 首次使用时再认证 | 用户体验优先、快速试用 |

## 风险、边界与改进建议

### 潜在风险
1. **空应用列表**：`apps_needing_auth` 为空时，客户端不应显示授权提示
2. **策略冲突**：`auth_policy=OnInstall` 但 `apps_needing_auth` 为空，可能表示配置不一致
3. **部分授权失败**：多个应用需要授权时，部分失败的处理策略

### 边界情况
1. **重复安装**：已安装插件的重复安装请求应返回错误还是幂等成功？
2. **依赖缺失**：插件依赖的其他插件未安装时的错误信息
3. **版本冲突**：已安装不同版本插件时的处理

### 改进建议
1. **添加安装状态**：
   ```rust
   pub struct PluginInstallResponse {
       pub auth_policy: PluginAuthPolicy,
       pub apps_needing_auth: Vec<AppSummary>,
       pub status: InstallStatus,  // 新增：NewInstalled / Updated / AlreadyInstalled
       pub installed_version: String,  // 新增
   }
   ```

2. **添加错误详情**：
   ```rust
   pub struct PluginInstallResponse {
       // ... 现有字段
       pub warnings: Vec<InstallWarning>,  // 非致命警告
   }
   ```

3. **支持部分成功**：当部分应用授权失败时，允许插件部分启用

### 测试覆盖
建议测试场景：
1. 正常安装（OnInstall 策略，有需要授权的应用）
2. 正常安装（OnUse 策略，无需要授权的应用）
3. 重复安装处理
4. 远程同步失败处理
5. 依赖缺失错误

### API 稳定性
- 此类型属于稳定 API（无 `#[experimental]` 标记）
- 作为 ClientRequest 的响应类型，变更会影响客户端
- 建议通过添加可选字段来扩展

### 与 PluginUninstallResponse 的对比
```rust
// PluginUninstallResponse 是空结构体
pub struct PluginUninstallResponse {}
```
卸载操作相对简单，无需返回额外信息，而安装需要处理认证策略的复杂性。
