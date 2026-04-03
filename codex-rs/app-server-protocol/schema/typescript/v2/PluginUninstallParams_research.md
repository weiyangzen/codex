# PluginUninstallParams 研究文档

## 1. 场景与职责

`PluginUninstallParams` 是卸载插件的请求参数类型，用于指定要卸载的插件ID和控制卸载流程的选项。

**使用场景：**
- 用户从插件管理界面卸载插件
- 系统清理不再需要的插件
- 插件更新前的卸载准备

## 2. 功能点目的

该类型的核心目的是：

1. **标识目标插件**：通过插件ID指定要卸载的插件
2. **控制同步行为**：决定是否先与远程服务器同步状态
3. **支持强制卸载**：处理各种边界情况

## 3. 具体技术实现

### TypeScript 定义
```typescript
export type PluginUninstallParams = {
  pluginId: string;
  forceRemoteSync: boolean;
};
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginUninstallParams {
    pub plugin_id: String,
    /// When true, apply the remote plugin change before the local uninstall flow.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_remote_sync: bool,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `pluginId` | `string` | 要卸载的插件的唯一标识符 |
| `forceRemoteSync` | `boolean` | 为true时，在本地卸载前先与远程服务器同步状态 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3376-3384

**关联的响应类型：**
- `PluginUninstallResponse`：对应的卸载响应（行3386-3389）

**API方法：**
- `plugin/uninstall`：使用此参数的RPC方法

## 5. 依赖与外部交互

**无外部类型依赖**

**使用场景：**
- 插件卸载API
- 与 `PluginUninstallResponse` 配对使用

## 6. 风险、边界与改进建议

### 潜在风险
1. **误卸载**：错误的pluginId可能导致卸载错误的插件
2. **依赖破坏**：卸载被其他插件依赖的插件可能导致功能异常
3. **数据丢失**：插件相关的用户数据可能在卸载时被删除

### 边界情况
- 插件不存在：返回错误
- 插件未安装：可能是重复卸载请求
- 远程同步失败：本地卸载可能已完成但远程状态未更新
- 系统插件：默认安装的插件可能不允许卸载

### 改进建议
1. **添加依赖检查**：卸载前检查是否有其他插件依赖此插件
2. **添加确认机制**：要求客户端提供确认令牌，防止误操作
3. **添加保留数据选项**：允许用户选择是否保留插件数据
4. **添加批量卸载**：支持一次卸载多个插件
5. **添加回滚机制**：卸载失败时能够恢复原状
6. **添加卸载原因**：收集用户卸载原因用于改进
