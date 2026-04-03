# PluginUninstallParams 研究文档

## 场景与职责

`PluginUninstallParams` 是 Codex app-server-protocol v2 协议中 `plugin/uninstall` 方法的请求参数类型，用于指定要卸载的插件ID和控制卸载流程的选项。该类型是插件生命周期管理的关键组成部分，负责触发插件的卸载流程。

在 Codex 的插件生态中，`PluginUninstallParams` 用于：
1. **插件卸载**：指定要卸载的插件标识
2. **远程同步控制**：控制是否在本地卸载前先同步远程状态
3. **批量操作**：支持批量卸载多个插件（通过多次调用）

## 功能点目的

### 核心功能
- **目标标识**：通过 `pluginId` 指定要卸载的插件
- **远程同步**：通过 `forceRemoteSync` 控制远程同步行为
- **类型安全**：使用强类型确保参数正确性

### 设计意图
- **简单明确**：仅包含必要字段，降低使用复杂度
- **灵活控制**：提供 `forceRemoteSync` 选项处理复杂场景
- **与安装对称**：与 `PluginInstallParams` 设计保持一致

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`PluginUninstallParams.ts`）：
```typescript
export type PluginUninstallParams = { 
  pluginId: string, 
  /**
   * When true, apply the remote plugin change before the local uninstall flow.
   */
  forceRemoteSync?: boolean, 
};
```

**Rust 定义**（`v2.rs` 行 3379-3384）：
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

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pluginId` | `string` | 是 | 要卸载的插件唯一标识符 |
| `forceRemoteSync` | `boolean` | 否 | 是否在本地卸载前先应用远程插件变更，默认为 `false` |

### 序列化行为

`forceRemoteSync` 使用 `#[serde(default, skip_serializing_if = "std::ops::Not::not")]` 注解：
- 默认值为 `false`
- 当值为 `false` 时，序列化会跳过该字段
- 这减少了网络传输的数据量，同时保持向后兼容

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 3379-3384
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/PluginUninstallParams.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/PluginUninstallParams.json`

### 使用位置
- **ClientRequest 定义**：`common.rs` 行 347-349 - 注册为 RPC 方法参数
- **消息处理器**：`codex_message_processor.rs` 行 5853-5927 - 处理卸载请求
- **测试用例**：`tests/suite/v2/plugin_uninstall.rs` - 测试卸载功能

### 相关类型
- `PluginUninstallResponse`：对应的响应类型（行 3386-3389）
- `PluginInstallParams`：对应的安装参数（行 3360-3366）
- `PluginUninstallError`：核心层的卸载错误类型（`core/src/plugins/manager.rs` 行 1211）

### 处理流程

```
ClientRequest::PluginUninstall { params: PluginUninstallParams }
  ↓
codex_message_processor.rs::review_start() 行 728
  ↓
PluginUninstallParams { plugin_id, force_remote_sync }
  ↓
core::PluginManager::uninstall_plugin() 行 685
  ↓
PluginUninstallResponse {}
```

## 依赖与外部交互

### 依赖项
- `serde`：序列化/反序列化支持
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 上游依赖
- `PluginUninstallError`（核心层）：`core/src/plugins/manager.rs` 行 1211-1240

### 下游使用
- `ClientRequest`：作为 `plugin/uninstall` 方法的参数
- `PluginUninstallResponse`：形成请求-响应配对

### 协议集成
- RPC 方法名：`plugin/uninstall`（`common.rs` 行 347）
- 请求方向：Client → Server
- 响应类型：`PluginUninstallResponse`

## 风险、边界与改进建议

### 潜在风险
1. **误卸载**：错误的 `pluginId` 可能导致意外卸载重要插件
2. **依赖破坏**：卸载被其他插件依赖的插件可能导致功能失效
3. **远程同步冲突**：`forceRemoteSync` 可能引发状态不一致

### 边界情况
1. **不存在的插件**：`pluginId` 指向不存在的插件时的错误处理
2. **正在使用的插件**：卸载正在执行的插件的行为
3. **权限不足**：没有权限卸载系统级插件
4. **网络故障**：`forceRemoteSync: true` 时网络不可用

### 改进建议
1. **安全增强**：
   - 添加卸载确认机制（如需要额外的确认令牌）
   - 实现依赖检查，阻止卸载被依赖的插件
   - 添加卸载权限验证

2. **功能扩展**：
   - 支持批量卸载多个插件（`pluginIds: string[]`）
   - 添加 `keepData` 选项控制是否保留插件数据
   - 添加 `reason` 字段记录卸载原因

3. **错误处理改进**：
   - 细化错误类型（如 `PluginInUse`, `DependencyConflict`, `PermissionDenied`）
   - 添加重试机制处理临时失败

4. **审计日志**：
   - 记录卸载操作到审计日志
   - 支持撤销卸载操作

5. **用户体验**：
   - 添加卸载进度通知
   - 支持异步卸载大插件
