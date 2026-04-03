# PluginInstallResponse.json 研究文档

## 场景与职责

`PluginInstallResponse.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述插件安装响应的结构。

该响应结构用于 `plugin/install` 方法的返回，包含安装后需要授权的应用列表和授权策略信息，支持客户端处理插件安装后的权限配置流程。

## 功能点目的

1. **授权需求通知**: 告知客户端哪些应用需要用户授权
2. **授权策略控制**: 指定授权的时机策略（安装时 vs 使用时）
3. **安装结果反馈**: 确认插件安装操作已完成
4. **后续流程引导**: 指导客户端完成必要的授权步骤

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "AppSummary": {
      "description": "EXPERIMENTAL - app metadata summary for plugin responses.",
      "properties": {
        "description": { "type": ["string", "null"] },
        "id": { "type": "string" },
        "installUrl": { "type": ["string", "null"] },
        "name": { "type": "string" }
      },
      "required": ["id", "name"],
      "type": "object"
    },
    "PluginAuthPolicy": {
      "enum": ["ON_INSTALL", "ON_USE"],
      "type": "string"
    }
  },
  "properties": {
    "appsNeedingAuth": {
      "items": { "$ref": "#/definitions/AppSummary" },
      "type": "array"
    },
    "authPolicy": {
      "$ref": "#/definitions/PluginAuthPolicy"
    }
  },
  "required": ["appsNeedingAuth", "authPolicy"],
  "title": "PluginInstallResponse",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `appsNeedingAuth` | array | 是 | 需要授权的应用列表，每个应用包含 id、name、description、installUrl |
| `authPolicy` | string | 是 | 授权策略，`ON_INSTALL`（安装时）或 `ON_USE`（使用时） |

### 子类型定义

#### AppSummary
- **id**: 应用唯一标识符
- **name**: 应用显示名称
- **description**: 应用描述（可选）
- **installUrl**: 应用安装/授权 URL（可选）

#### PluginAuthPolicy
- **ON_INSTALL**: 在安装时完成授权
- **ON_USE**: 在首次使用时完成授权

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3371
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallResponse {
    pub apps_needing_auth: Vec<AppSummary>,
    pub auth_policy: PluginAuthPolicy,
}

// AppSummary 定义 (行 1929-1946)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct AppSummary {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub install_url: Option<String>,
}

// PluginAuthPolicy 枚举
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
#[ts(export_to = "v2/")]
pub enum PluginAuthPolicy {
    OnInstall,
    OnUse,
}
```

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3371-3378)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PluginInstallResponse.json`
- **AppSummary**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1929-1946)
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 343-346)

### 调用方
- **方法**: `PluginInstall` (`plugin/install`)
- **请求参数**: `PluginInstallParams`

### 使用场景
1. 插件安装后立即需要授权（`ON_INSTALL`）
2. 插件安装后延迟授权（`ON_USE`）
3. 多应用插件需要批量授权

## 依赖与外部交互

### 上游依赖
1. **插件安装器**: 执行实际的插件安装逻辑
2. **应用授权系统**: 管理应用与插件的授权关系
3. **OAuth/SSO 服务**: 处理第三方应用授权

### 下游使用方
1. **客户端 UI**: 展示需要授权的应用列表
2. **授权流程**: 引导用户完成应用授权
3. **插件管理器**: 跟踪授权状态

### 授权流程

#### ON_INSTALL 策略
1. 服务器返回 `PluginInstallResponse`，`authPolicy` 为 `ON_INSTALL`
2. 客户端展示 `appsNeedingAuth` 列表
3. 用户完成所有应用授权
4. 插件完全激活

#### ON_USE 策略
1. 服务器返回 `PluginInstallResponse`，`authPolicy` 为 `ON_USE`
2. 客户端记录需要授权的应用
3. 插件部分激活，功能受限
4. 首次使用相关功能时触发授权流程

## 风险、边界与改进建议

### 潜在风险
1. **授权失败**: 用户可能拒绝或无法完成应用授权
2. **URL 安全**: `installUrl` 可能指向恶意网站
3. **策略混淆**: 用户可能不理解 `ON_INSTALL` 和 `ON_USE` 的区别
4. **授权过期**: 应用授权可能有时效性，需要重新授权

### 边界情况
1. **空授权列表**: `appsNeedingAuth` 为空数组表示无需额外授权
2. **重复应用**: 同一应用可能在多个插件中出现
3. **授权中断**: 授权流程可能在中途被取消
4. **策略变更**: 插件更新可能改变授权策略

### 改进建议

#### 1. 添加安装状态
```json
{
  "appsNeedingAuth": [...],
  "authPolicy": "ON_INSTALL",
  "installStatus": "pending_auth",
  "installId": "uuid-for-tracking"
}
```

#### 2. 添加授权进度
```json
{
  "appsNeedingAuth": [
    {
      "id": "app1",
      "name": "App One",
      "authStatus": "completed",
      "completedAt": 1712345678
    },
    {
      "id": "app2", 
      "name": "App Two",
      "authStatus": "pending"
    }
  ],
  "authPolicy": "ON_INSTALL"
}
```

#### 3. 添加重试机制
```json
{
  "appsNeedingAuth": [...],
  "authPolicy": "ON_INSTALL",
  "retryInfo": {
    "maxRetries": 3,
    "retryDelayMs": 5000
  }
}
```

#### 4. 添加授权说明
```json
{
  "appsNeedingAuth": [
    {
      "id": "app1",
      "name": "App One",
      "description": "...",
      "installUrl": "...",
      "requestedPermissions": ["read:profile", "write:data"],
      "permissionExplanation": "This app needs access to your profile to personalize the experience."
    }
  ],
  "authPolicy": "ON_INSTALL",
  "authInstructions": "Please authorize the following apps to complete the plugin installation."
}
```

### 最佳实践
1. **清晰说明**: 向用户清晰解释为什么需要授权每个应用
2. **渐进授权**: 对于多应用插件，考虑分批请求授权
3. **取消处理**: 提供取消授权流程的选项和后果说明
4. **状态持久化**: 记录授权状态，支持断点续传

### 相关 API
- `PluginInstallParams` - 插件安装请求
- `PluginListResponse` - 插件列表（包含已安装插件的授权状态）
- `AppSummary` - 应用摘要信息
- `AppsListResponse` - 应用列表（包含详细的授权信息）
