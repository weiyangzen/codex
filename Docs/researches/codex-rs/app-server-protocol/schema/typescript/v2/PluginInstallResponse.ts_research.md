# PluginInstallResponse.ts 调研文档

## 场景与职责

`PluginInstallResponse` 是 Codex 应用服务器协议中用于响应插件安装请求的类型。该类型主要用于以下场景：

1. **插件安装结果反馈**：向客户端返回插件安装的详细结果
2. **授权策略通知**：告知客户端该插件的认证策略（安装时认证 vs 使用时认证）
3. **依赖应用提示**：列出需要用户授权才能使用的关联应用/连接器
4. **安装后引导**：帮助客户端引导用户完成必要的授权流程

该类型作为 `plugin/install` RPC 方法的响应体，是插件安装流程的核心组成部分。

## 功能点目的

`PluginInstallResponse` 包含两个核心字段：

| 字段 | 类型 | 用途 |
|------|------|------|
| `authPolicy` | `PluginAuthPolicy` | 插件的认证策略，决定何时需要用户授权 |
| `appsNeedingAuth` | `AppSummary[]` | 需要授权的应用列表，用于引导用户完成授权 |

### 设计目的

1. **延迟授权支持**：某些插件可能不需要在安装时立即授权，而是在实际使用时才需要
2. **依赖透明化**：让用户清楚了解插件依赖哪些应用/服务
3. **安装流程优化**：允许插件先安装，后续再按需完成授权
4. **用户体验一致性**：统一的响应格式便于客户端实现标准化的安装后引导

### 认证策略说明

- `ON_INSTALL`：安装时即需要完成授权
- `ON_USE`：首次使用时才需要授权

## 具体技术实现

### TypeScript 定义

```typescript
import type { AppSummary } from "./AppSummary";
import type { PluginAuthPolicy } from "./PluginAuthPolicy";

export type PluginInstallResponse = { 
    authPolicy: PluginAuthPolicy, 
    appsNeedingAuth: Array<AppSummary>, 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallResponse {
    pub auth_policy: PluginAuthPolicy,
    pub apps_needing_auth: Vec<AppSummary>,
}
```

### 关联类型

1. **PluginAuthPolicy** (`v2.rs` 第 3263-3270 行)
   ```rust
   pub enum PluginAuthPolicy {
       #[serde(rename = "ON_INSTALL")]
       OnInstall,
       #[serde(rename = "ON_USE")]
       OnUse,
   }
   ```

2. **AppSummary** (`v2.rs` 第 2026-2046 行)
   ```rust
   pub struct AppSummary {
       pub id: String,
       pub name: String,
       pub description: Option<String>,
       pub install_url: Option<String>,
   }
   ```

## 关键代码路径与文件引用

### 定义位置

- **Rust 源码**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 3371-3374 行)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginInstallResponse.ts`

### RPC 方法注册

在 `common.rs` 中注册为 `plugin/install` 方法的响应类型：

```rust
PluginInstall => "plugin/install" {
    params: v2::PluginInstallParams,
    response: v2::PluginInstallResponse,
}
```

### 测试覆盖

- **文件**: `codex-rs/app-server/tests/suite/v2/plugin_install.rs`
- **关键测试用例**:
  - `plugin_install_returns_apps_needing_auth`：验证返回需要授权的应用列表
  - `plugin_install_filters_disallowed_apps_needing_auth`：验证过滤不允许的应用
  - `plugin_install_force_remote_sync_enables_remote_plugin_before_local_install`：验证远程同步场景

### 使用示例

```rust
// 安装插件后返回响应
let response = PluginInstallResponse {
    auth_policy: PluginAuthPolicy::OnInstall,
    apps_needing_auth: vec![
        AppSummary {
            id: "gmail".to_string(),
            name: "Gmail".to_string(),
            description: Some("Google Mail integration".to_string()),
            install_url: Some("https://chatgpt.com/apps/gmail/gmail".to_string()),
        }
    ],
};
```

## 依赖与外部交互

### 内部依赖

| 依赖项 | 用途 |
|--------|------|
| `PluginAuthPolicy` | 定义认证策略枚举 |
| `AppSummary` | 定义应用摘要信息 |
| `serde` | 序列化/反序列化 |
| `ts-rs` | TypeScript 类型生成 |

### 外部交互

1. **应用/连接器服务**
   - 通过 MCP (Model Context Protocol) 服务器获取应用信息
   - 检查应用的可访问性和授权状态

2. **插件清单解析**
   - 从 `.app.json` 文件读取插件依赖的应用列表
   - 示例：
     ```json
     {
       "apps": {
         "gmail": { "id": "gmail" },
         "calendar": { "id": "calendar" }
       }
     }
     ```

3. **授权服务**
   - 查询用户对各应用的授权状态
   - 过滤已授权的应用，仅返回需要授权的应用

## 风险、边界与改进建议

### 潜在风险

1. **授权状态时效性**：`appsNeedingAuth` 返回的是安装时刻的快照，用户授权状态可能随后发生变化
2. **应用服务不可用**：如果应用目录服务不可用，可能无法准确判断需要授权的应用
3. **循环依赖**：插件 A 依赖应用 B，应用 B 又依赖插件 A 的场景需要处理

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 无依赖应用 | `appsNeedingAuth` 返回空数组 |
| 所有应用已授权 | `appsNeedingAuth` 返回空数组 |
| 应用服务不可用 | 根据实现可能返回空数组或错误 |
| 插件无 interface 定义 | 默认使用 `ON_INSTALL` 策略 |

### 改进建议

1. **增加安装状态字段**
   ```rust
   pub struct PluginInstallResponse {
       pub auth_policy: PluginAuthPolicy,
       pub apps_needing_auth: Vec<AppSummary>,
       pub install_status: InstallStatus, // 新增：安装成功/部分成功/失败
       pub message: Option<String>, // 新增：人类可读的状态说明
   }
   ```

2. **支持渐进式授权**
   ```rust
   pub struct AppAuthInfo {
       pub app: AppSummary,
       pub auth_url: String,
       pub is_required: bool, // 是否必须授权才能使用插件
       pub can_skip: bool, // 是否允许跳过
   }
   ```

3. **增加重试机制**
   - 当应用服务暂时不可用时，提供重试选项
   - 返回 `Retry-After` 头信息

4. **授权状态订阅**
   - 支持客户端订阅授权状态变化
   - 当用户完成授权后主动推送通知

5. **批量安装支持**
   - 支持一次安装多个插件
   - 合并返回所有需要授权的应用（去重）

6. **授权引导优化**
   ```rust
   pub struct AppSummary {
       // 现有字段...
       pub auth_flow_type: AuthFlowType, // OAuth, API Key, etc.
       pub estimated_auth_time_seconds: Option<u32>, // 预估授权耗时
       pub help_url: Option<String>, // 授权帮助文档
   }
   ```
