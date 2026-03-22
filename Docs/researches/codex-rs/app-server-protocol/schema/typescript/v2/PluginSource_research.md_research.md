# PluginSource 研究文档

## 场景与职责

`PluginSource` 是 Codex App Server Protocol v2 中用于定义插件来源的枚举类型。它负责标识插件的物理位置或获取方式，是插件管理系统的基础组件之一。

在 Codex 的插件生态中，插件可以来自不同的来源，目前主要支持本地文件系统路径。该类型用于插件安装、卸载、查询等操作中，标识插件的来源位置。

## 功能点目的

1. **插件来源标识**：明确插件的物理位置或获取方式
2. **类型安全**：使用 Rust 枚举和 TypeScript 联合类型确保来源类型的正确性
3. **序列化支持**：支持 JSON 序列化/反序列化，用于客户端-服务器通信
4. **类型生成**：通过 `ts-rs` 自动生成 TypeScript 类型定义

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum PluginSource {
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Local { path: AbsolutePathBuf },
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/PluginSource.ts)
export type PluginSource = { "type": "local", path: AbsolutePathBuf, };
```

### 关键特性

1. **Tagged Union 模式**：使用 `type` 字段作为 discriminant，支持未来扩展其他来源类型
2. **AbsolutePathBuf**：使用绝对路径类型确保路径的确定性
3. **camelCase 命名**：遵循 TypeScript/JavaScript 命名规范

### 生成流程

1. Rust 代码中使用 `#[derive(TS)]` 宏标记
2. 运行 `cargo test` 或 `just write-app-server-schema` 触发类型导出
3. 生成 TypeScript 文件到 `schema/typescript/v2/` 目录

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 3336-3340)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginSource.ts`

### 相关类型
- `PluginSummary`: 包含 `PluginSource` 作为字段
- `PluginDetail`: 插件详情，包含来源信息
- `AbsolutePathBuf`: 路径类型定义在 `codex-utils-absolute-path` crate

### 使用场景
- 插件安装 (`PluginInstallParams`)
- 插件列表查询 (`PluginListResponse`)
- 插件详情查询 (`PluginReadResponse`)

## 依赖与外部交互

### 内部依赖
- `codex_utils_absolute_path::AbsolutePathBuf`: 绝对路径类型
- `serde`: 序列化/反序列化
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互
- 客户端通过 JSON-RPC 发送插件相关请求时包含此类型
- 服务器返回插件信息时包含来源字段

## 风险、边界与改进建议

### 当前限制
1. **单一来源类型**：目前仅支持 `Local` 来源，未来可能需要支持远程 URL、Git 仓库等
2. **路径验证**：类型本身不验证路径是否存在或可访问
3. **跨平台路径**：需要确保 Windows/Unix 路径格式的正确处理

### 扩展建议
1. 考虑添加 `Remote` 变体支持远程插件
2. 考虑添加 `Git` 变体支持 Git 仓库来源
3. 添加路径存在性验证的辅助方法

### 兼容性注意
- 使用 tagged union 模式确保向后兼容
- 新增来源类型时，旧客户端应能安全忽略不识别的变体
