# PluginUninstallParams.json 研究文档

## 场景与职责

`PluginUninstallParams` 是 Codex App-Server Protocol v2 API 中 `plugin/uninstall` 方法的请求参数结构，用于指定要卸载的插件及卸载选项。该参数在客户端请求卸载插件时发送，支持强制远程同步选项以处理分布式场景。

## 功能点目的

1. **插件卸载请求**: 作为 `plugin/uninstall` RPC 方法的参数，发起插件卸载操作
2. **远程同步控制**: 支持 `forceRemoteSync` 选项，在本地卸载前应用远程插件变更
3. **插件生命周期管理**: 完成插件从 installed 到 uninstalled 状态的转换

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallParams {
    pub plugin_id: String,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pluginId` | string | 是 | 要卸载的插件唯一标识符 |
| `forceRemoteSync` | boolean | 否 | 为 true 时，在本地卸载流程前先应用远程插件变更 |

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "forceRemoteSync": {
      "description": "When true, apply the remote plugin change before the local uninstall flow.",
      "type": "boolean"
    },
    "pluginId": {
      "type": "string"
    }
  },
  "required": ["pluginId"],
  "title": "PluginUninstallParams",
  "type": "object"
}
```

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `PluginUninstallParams`: 第 3379 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallParams {
    pub plugin_id: String,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_client_param_schemas()` 在 `common.rs` 中定义

### 使用位置
- **ClientRequest 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 347-350 行
```rust
PluginUninstall => "plugin/uninstall" {
    params: v2::PluginUninstallParams,
    response: v2::PluginUninstallResponse,
}
```

## 依赖与外部交互

### 内部依赖
1. **schemars**: JSON Schema 生成
2. **ts_rs**: TypeScript 类型生成
3. **serde**: 序列化/反序列化

### 外部交互
1. **插件系统**: 与插件管理器交互执行卸载操作
2. **文件系统**: 删除插件相关文件和目录
3. **配置存储**: 更新插件安装状态配置
4. **远程同步**（当 forceRemoteSync=true）: 与远程插件仓库同步状态

### 关联响应类型
- `PluginUninstallResponse`: 空响应体，表示操作成功

## 风险、边界与改进建议

### 风险点
1. **数据丢失**: 卸载操作不可逆，插件相关数据可能被删除
2. **依赖破坏**: 卸载插件可能影响依赖该插件的 Apps 或 Skills
3. **并发冲突**: 多客户端同时操作同一插件可能导致状态不一致
4. **远程同步失败**: `forceRemoteSync` 依赖网络，可能超时或失败

### 边界情况
1. **插件不存在**: 请求不存在的 pluginId 时应返回明确错误
2. **插件未安装**: 对未安装的插件调用卸载应返回特定状态
3. **权限不足**: 系统级插件可能需要特殊权限才能卸载
4. **正在使用**: 插件正在被使用时卸载可能导致运行时错误

### 改进建议
1. **依赖检查**: 卸载前检查是否有 Apps/Skills 依赖该插件
2. **软删除**: 考虑先标记为待卸载，确认无依赖后再真正删除
3. **备份机制**: 支持卸载前备份插件配置和数据
4. **异步处理**: 卸载操作可能耗时，考虑改为异步模式并返回任务 ID
5. **回滚支持**: 卸载失败时支持回滚到之前状态
6. **批量卸载**: 支持一次请求卸载多个插件
