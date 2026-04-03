# PluginUninstallResponse 研究文档

## 1. 场景与职责

`PluginUninstallResponse` 是卸载插件操作的响应类型，表示卸载操作已成功完成。这是一个空响应类型，不包含额外数据。

**使用场景：**
- 确认插件卸载成功
- 完成卸载流程的响应

## 2. 功能点目的

该类型的核心目的是：

1. **确认操作成功**：向客户端表明卸载操作已完成
2. **保持API一致性**：与其他响应类型保持统一的结构
3. **为未来扩展预留空间**：空结构允许后续添加字段而不破坏兼容性

## 3. 具体技术实现

### TypeScript 定义
```typescript
export type PluginUninstallResponse = Record<string, never>;
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallResponse {}
```

### 关键特性
- TypeScript中使用 `Record<string, never>` 表示空对象类型
- Rust中使用空结构体 `{}`
- 序列化为空JSON对象 `{}`

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3386-3389

**关联的请求类型：**
- `PluginUninstallParams`：对应的卸载请求参数（行3376-3384）

**API方法：**
- `plugin/uninstall`：返回此响应的RPC方法

## 5. 依赖与外部交互

**无外部依赖**

**使用场景：**
- 插件卸载API的响应
- 与 `PluginUninstallParams` 配对使用

## 6. 风险、边界与改进建议

### 潜在风险
1. **信息不足**：空响应不提供卸载的具体信息（如释放的空间、删除的文件数）
2. **状态不明确**：无法区分"已卸载"和"原本就没有安装"

### 边界情况
- 插件原本未安装：操作可能仍被视为成功（幂等性）
- 部分卸载：某些文件无法删除，但响应仍为成功

### 改进建议
1. **添加卸载详情**：
   - 删除的文件/目录列表
   - 释放的磁盘空间
   - 卸载时间戳
2. **添加状态信息**：
   - 明确告知插件是否原本已安装
   - 告知是否有残留文件
3. **添加警告信息**：
   - 如果有依赖此插件的其他插件，给出警告
   - 如果有数据被删除，给出提示
4. **支持软删除**：添加 `soft` 选项，允许保留数据以便恢复
