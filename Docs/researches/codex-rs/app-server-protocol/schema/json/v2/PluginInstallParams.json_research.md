# PluginInstallParams.json 研究文档

## 场景与职责

`PluginInstallParams.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述插件安装请求的参数结构。

该参数结构用于 `plugin/install` 方法，支持从指定的市场路径安装插件，并提供远程同步控制选项。

## 功能点目的

1. **插件安装**: 从本地或远程市场安装插件到 Codex 环境
2. **市场定位**: 通过 `marketplacePath` 指定插件来源
3. **远程同步控制**: 支持在安装前同步远程插件状态
4. **插件发现**: 结合 `PluginListResponse` 实现完整的插件管理流程

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "AbsolutePathBuf": {
      "description": "A path that is guaranteed to be absolute and normalized (though it is not guaranteed to be canonicalized or exist on the filesystem).\n\nIMPORTANT: When deserializing an `AbsolutePathBuf`, a base path must be set using [AbsolutePathBufGuard::new]. If no base path is set, the deserialization will fail unless the path being deserialized is already absolute.",
      "type": "string"
    }
  },
  "properties": {
    "forceRemoteSync": {
      "description": "When true, apply the remote plugin change before the local install flow.",
      "type": "boolean"
    },
    "marketplacePath": {
      "$ref": "#/definitions/AbsolutePathBuf"
    },
    "pluginName": {
      "type": "string"
    }
  },
  "required": ["marketplacePath", "pluginName"],
  "title": "PluginInstallParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `marketplacePath` | string | 是 | 插件市场的绝对路径，标识插件来源位置 |
| `pluginName` | string | 是 | 要安装的插件名称 |
| `forceRemoteSync` | boolean | 否 | 是否在本地安装前同步远程插件变更 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3360
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginInstallParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
    /// When true, apply the remote plugin change before the local install flow.
    #[serde(default)]
    pub force_remote_sync: bool,
}
```

### 方法映射

```rust
// common.rs 行 343-346
PluginInstall => "plugin/install" {
    params: v2::PluginInstallParams,
    response: v2::PluginInstallResponse,
}
```

### 路径类型说明

`AbsolutePathBuf` 是一个保证为绝对路径且已规范化的路径类型：
- 路径不一定是规范化的（canonicalized）
- 路径不一定存在于文件系统上
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard::new`）

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3360-3370)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PluginInstallParams.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 343-346)

### 调用方
- **客户端**: 通过 `plugin/install` 方法请求安装插件
- **UI 层**: 插件市场界面中的安装按钮

### 响应结构
- **对应响应**: `PluginInstallResponse` - 包含需要授权的应用列表和授权策略

### 依赖类型
- **AbsolutePathBuf**: `codex_utils_absolute_path::AbsolutePathBuf`

## 依赖与外部交互

### 上游依赖
1. **插件市场系统**: 管理插件的发现和元数据
2. **文件系统**: 读取插件包和配置文件
3. **远程同步**: 与远程插件状态同步（当 `forceRemoteSync` 为 true）

### 下游使用方
1. **插件安装器**: 执行实际的插件安装逻辑
2. **授权系统**: 处理插件所需的权限授权
3. **配置管理**: 更新插件配置状态

### 安装流程
1. 客户端调用 `plugin/install` 并传入 `PluginInstallParams`
2. 服务器验证插件市场和插件存在性
3. 如 `forceRemoteSync` 为 true，先同步远程状态
4. 执行本地安装流程
5. 返回 `PluginInstallResponse`，可能包含需要授权的应用列表

## 风险、边界与改进建议

### 潜在风险
1. **路径安全**: 需要验证 `marketplacePath` 不指向敏感系统目录
2. **插件冲突**: 同名插件可能在不同市场存在
3. **远程同步失败**: `forceRemoteSync` 可能因网络问题失败
4. **权限提升**: 插件安装可能需要额外的系统权限

### 边界情况
1. **市场不存在**: 指定的 `marketplacePath` 不存在时的错误处理
2. **插件不存在**: 指定市场中找不到对应插件名称
3. **已安装插件**: 重复安装同一插件的处理策略
4. **版本冲突**: 已安装版本与新版本不兼容

### 改进建议

#### 1. 添加版本指定
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "version": "1.2.3",
  "forceRemoteSync": true
}
```

#### 2. 添加安装选项
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "installOptions": {
    "skipDependencies": false,
    "forceReinstall": false,
    "dryRun": false
  }
}
```

#### 3. 添加来源验证
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "expectedChecksum": "sha256:abc123...",
  "signatureVerification": true
}
```

#### 4. 响应改进
当前 `PluginInstallResponse` 包含需要授权的应用列表，建议添加：
- 安装进度追踪 ID
- 预计安装时间
- 磁盘空间需求

### 最佳实践
1. **路径验证**: 始终验证 `marketplacePath` 的合法性
2. **用户确认**: 在安装需要授权的应用前获取用户确认
3. **错误处理**: 提供清晰的安装失败原因
4. **幂等性**: 支持重复调用，避免重复安装

### 相关 API
- `PluginInstallResponse` - 安装响应，包含授权需求
- `PluginListParams` / `PluginListResponse` - 插件列表查询
- `PluginReadParams` / `PluginReadResponse` - 插件详情读取
- `PluginUninstallParams` / `PluginUninstallResponse` - 插件卸载
