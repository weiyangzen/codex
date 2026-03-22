# PluginUninstallResponse 研究文档

## 场景与职责

`PluginUninstallResponse` 是 Codex App Server Protocol v2 中插件卸载操作的响应类型。它是一个空对象类型（Empty Object），表示卸载操作的成功确认。

该类型的设计遵循 JSON-RPC 2.0 协议的惯例，成功响应返回空对象表示操作已完成，具体的错误信息通过 JSON-RPC 的 error 字段传递。

## 功能点目的

1. **操作确认**：表示插件卸载请求已成功处理
2. **协议一致性**：符合 JSON-RPC 2.0 响应格式要求
3. **类型安全**：提供明确的类型定义，便于客户端处理响应

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallResponse {}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/PluginUninstallResponse.ts)
export type PluginUninstallResponse = Record<string, never>;
```

### 类型说明

- **Rust**: 使用空结构体 `{}` 表示
- **TypeScript**: 使用 `Record<string, never>` 表示空对象类型
  - `Record<string, never>` 是 TypeScript 中表示"空对象"的惯用方式
  - 它表示一个对象，其属性键为 `string`，但属性值的类型为 `never`（即不可能有任何属性）

### 对比相关类型

| 类型 | Rust 定义 | TypeScript 定义 |
|------|-----------|-----------------|
| `PluginUninstallResponse` | `struct PluginUninstallResponse {}` | `Record<string, never>` |
| `PluginInstallResponse` | 包含多个字段的结构体 | 包含字段的对象类型 |
| `TurnInterruptResponse` | `struct TurnInterruptResponse {}` | `Record<string, never>` |

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3386-3389)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginUninstallResponse.ts`

### 相关类型
- `PluginUninstallParams`: 对应的请求参数类型
- `PluginInstallResponse`: 安装响应（对比参考）

### 使用场景
- 服务器处理 `plugin/uninstall` 请求后返回此响应
- 客户端接收并解析 JSON-RPC 响应

## 依赖与外部交互

### 内部依赖
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**成功响应示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {}
}
```

**错误响应示例**:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "error": {
        "code": -32600,
        "message": "Plugin not found: my-plugin"
    }
}
```

## 风险、边界与改进建议

### 当前限制
1. **无详细信息**：响应不包含卸载结果的详细信息（如删除了哪些文件）
2. **无状态反馈**：无法区分"已卸载"和"原本就不存在"的情况
3. **无部分成功**：无法表示部分成功的情况（如某些文件删除失败）

### 设计考量

#### 为什么选择空对象？
1. **简洁性**：卸载操作通常是原子性的，要么成功要么失败
2. **一致性**：与 JSON-RPC 2.0 协议中其他空响应保持一致
3. **扩展性**：未来可以添加字段而不破坏向后兼容

#### 与 `PluginInstallResponse` 的对比
- 安装操作需要返回 `auth_policy` 和 `apps_needing_auth` 等信息
- 卸载操作相对简单，不需要额外信息

### 改进建议

1. **添加状态字段**：
   ```rust
   pub struct PluginUninstallResponse {
       pub uninstalled: bool,  // true = 已卸载, false = 原本不存在
   }
   ```

2. **添加详情字段**：
   ```rust
   pub struct PluginUninstallResponse {
       pub removed_files: Vec<PathBuf>,
       pub removed_configs: Vec<String>,
   }
   ```

3. **保持现状**：
   - 如果需要详细信息，可以通过后续的 `plugin/read` 或 `plugin/list` 查询
   - 保持简单，避免过度设计

### 兼容性注意
- 空对象响应在 JSON 中表示为 `{}`
- TypeScript 中使用 `Record<string, never>` 确保类型安全
- 未来添加字段时，应使用 `Option<T>` 确保向后兼容
