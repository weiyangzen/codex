# PluginUninstallResponse.json 研究文档

## 场景与职责

`PluginUninstallResponse` 是 Codex App-Server Protocol v2 API 中 `plugin/uninstall` 方法的响应结构。这是一个空响应体（Empty Response），仅表示插件卸载操作已成功完成，不携带额外的返回数据。

## 功能点目的

1. **操作确认**: 确认 `plugin/uninstall` 请求已成功处理
2. **简洁契约**: 使用空对象表示成功，符合 RESTful 设计原则
3. **未来扩展**: 保留结构以便未来添加可选的返回字段

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallResponse {}
```

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "PluginUninstallResponse",
  "type": "object"
}
```

### 特点
- **无字段**: 响应体不包含任何字段
- **空对象**: JSON 表示为 `{}`
- **成功语义**: HTTP/RPC 层面的成功状态 + 空对象 = 操作成功

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `PluginUninstallResponse`: 第 3389 行附近

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallResponse {}
```

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `export_client_response_schemas()` 在 `common.rs` 中定义

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

### 关联请求类型
- `PluginUninstallParams`: 对应的请求参数
  - `plugin_id`: 要卸载的插件 ID
  - `force_remote_sync`: 是否先同步远程变更

### 错误处理
虽然响应体为空，但错误通过以下方式传递：
1. **RPC 错误响应**: JSON-RPC 错误对象包含错误码和消息
2. **HTTP 状态码**: 对于 HTTP 传输，使用 4xx/5xx 状态码

## 风险、边界与改进建议

### 风险点
1. **信息不足**: 空响应无法提供卸载操作的详细信息（如删除了哪些文件）
2. **状态确认**: 客户端需要额外查询确认插件确实已被卸载
3. **部分失败**: 如果卸载部分失败（如某些文件删除失败），无法从响应中得知

### 边界情况
1. **重复卸载**: 对同一插件多次调用卸载，空响应无法区分首次和重复
2. **并发卸载**: 多个客户端同时卸载同一插件，响应无法反映实际执行者

### 改进建议
1. **添加卸载详情**:
   ```rust
   pub struct PluginUninstallResponse {
       pub uninstalled_at: i64,           // 卸载时间戳
       pub removed_files: Vec<String>,    // 删除的文件列表
       pub removed_size_bytes: u64,       // 释放的存储空间
   }
   ```

2. **添加状态字段**:
   ```rust
   pub struct PluginUninstallResponse {
       pub status: UninstallStatus,       // success | already_uninstalled | partial
       pub message: Option<String>,       // 可选的状态说明
   }
   ```

3. **保留元数据选项**:
   ```rust
   pub struct PluginUninstallResponse {
       pub metadata_preserved: bool,      // 是否保留了配置数据以便重新安装
       pub preserve_token: Option<String>, // 恢复令牌（如支持恢复）
   }
   ```

4. **与其他空响应统一**: 考虑为所有空响应定义统一的成功标记类型：
   ```rust
   pub type PluginUninstallResponse = EmptySuccessResponse;
   ```
