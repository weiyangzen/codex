# PluginUninstallParams 研究文档

## 场景与职责

`PluginUninstallParams` 是 Codex App Server Protocol v2 中用于插件卸载功能的请求参数类型。该类型定义了客户端向服务器发起插件卸载请求时所需提供的参数结构。

**核心使用场景：**
- 用户通过 CLI 或 TUI 界面主动卸载已安装的插件/Skill
- 系统在执行插件管理操作时传递卸载参数
- 支持本地插件卸载与远程插件同步的协调操作

**职责定位：**
- 作为 `plugin/uninstall` RPC 方法的请求参数类型
- 标识待卸载的插件（通过 `pluginId`）
- 控制卸载流程的行为（通过 `forceRemoteSync` 标志）

## 功能点目的

### 1. 插件标识（pluginId）
- **目的**：唯一标识需要卸载的插件
- **类型**：`string`（必填）
- **说明**：对应插件的唯一标识符，通常是插件的名称或 ID

### 2. 远程同步控制（forceRemoteSync）
- **目的**：控制卸载流程中远程同步的行为
- **类型**：`boolean`（可选，默认为 `false`）
- **说明**：
  - 当设置为 `true` 时，会先应用远程插件变更，再执行本地卸载流程
  - 用于确保本地卸载与远程状态的同步一致性
  - 在分布式或多设备场景下特别有用

### 3. 序列化行为
- 使用 `#[serde(default, skip_serializing_if = "std::ops::Not::not")]` 属性
- 当 `force_remote_sync` 为 `false` 时，该字段不会被序列化到 JSON
- 符合 API v2 的设计规范：布尔值默认为 `false` 时省略序列化

## 具体技术实现

### Rust 源码定义

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

### TypeScript 生成代码

```typescript
export type PluginUninstallParams = { 
    pluginId: string, 
    /**
     * When true, apply the remote plugin change before the local uninstall flow.
     */
    forceRemoteSync?: boolean, 
};
```

### 关键属性说明

| 属性名 | Rust 字段名 | TypeScript 属性名 | 类型 | 必填 | 默认值 | 说明 |
|--------|-------------|-------------------|------|------|--------|------|
| 插件ID | `plugin_id` | `pluginId` | `string` | 是 | - | 待卸载插件的唯一标识 |
| 强制远程同步 | `force_remote_sync` | `forceRemoteSync` | `boolean` | 否 | `false` | 是否先同步远程变更 |

### 序列化特性

1. **命名规范**：Rust 使用 `snake_case`，JSON/TypeScript 使用 `camelCase`
2. **ts-rs 导出**：通过 `#[ts(export_to = "v2/")]` 自动生成 TypeScript 类型定义
3. **JSON Schema**：通过 `#[derive(JsonSchema)]` 支持 JSON Schema 生成

## 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行号：3379-3384

### RPC 方法注册
- **文件**：`codex-rs/app-server-protocol/src/protocol/common.rs`
  - 行号：347-349
  - 方法名：`PluginUninstall`
  - 路径：`"plugin/uninstall"`

```rust
PluginUninstall => "plugin/uninstall" {
    params: v2::PluginUninstallParams,
    response: v2::PluginUninstallResponse,
}
```

### 生成的 TypeScript 文件
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/PluginUninstallParams.ts`

### 测试引用
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行号：7725, 7736（测试序列化场景）

### 相关类型
- `PluginUninstallResponse`：卸载操作的响应类型（空对象）
- `PluginInstallParams` / `PluginInstallResponse`：对应的安装操作类型

## 依赖与外部交互

### 内部依赖

| 依赖项 | 类型 | 说明 |
|--------|------|------|
| `serde` | 序列化库 | 提供 `Serialize`/`Deserialize` derive 宏 |
| `schemars` | JSON Schema | 提供 `JsonSchema` derive 宏 |
| `ts-rs` | TypeScript 生成 | 提供 `TS` derive 宏，自动生成 TS 类型 |

### 协议交互

```
Client -> Server: plugin/uninstall
  {
    "pluginId": "skill-name",
    "forceRemoteSync": true  // 可选
  }

Server -> Client: PluginUninstallResponse
  {}  // 空对象表示成功
```

### 与 Core 协议的关系
- 该类型是 App Server Protocol v2 的专属类型
- 在内部实现中可能会映射到 `codex_protocol` crate 中的相关类型
- 通过 `PluginUninstallResponse` 的空对象设计，体现了 v2 API 的简洁性原则

## 风险、边界与改进建议

### 潜在风险

1. **插件ID格式不一致**
   - 风险：不同来源的插件可能使用不同格式的 ID（如名称 vs UUID）
   - 缓解：确保插件注册和卸载使用一致的标识方案

2. **远程同步失败**
   - 风险：`forceRemoteSync=true` 时，远程同步失败可能导致本地卸载也被阻塞
   - 缓解：需要明确的错误处理和回滚机制

3. **并发卸载**
   - 风险：多个客户端同时卸载同一插件可能导致竞态条件
   - 缓解：服务器端需要实现适当的锁机制

### 边界情况

| 场景 | 行为 |
|------|------|
| `pluginId` 不存在 | 应返回明确的错误信息 |
| `pluginId` 为空字符串 | 应在验证阶段拒绝 |
| 插件正在使用中 | 需要决定是强制卸载还是拒绝 |
| 网络不可达且 `forceRemoteSync=true` | 需要超时和错误处理 |

### 改进建议

1. **添加验证注解**
   ```rust
   // 建议添加验证以确保 plugin_id 非空
   #[serde(validate = "::validators::string_non_empty")]
   pub plugin_id: String,
   ```

2. **考虑添加卸载原因字段**
   - 用于审计和分析用户卸载插件的原因
   - 可选字段，不影响现有功能

3. **增强错误响应**
   - 当前 `PluginUninstallResponse` 是空对象
   - 建议添加可选的 `message` 字段用于传递警告信息

4. **添加幂等性支持**
   - 考虑添加 `idempotent` 标志或请求 ID
   - 防止重复提交导致的意外行为

5. **文档完善**
   - 明确 `pluginId` 的格式要求（名称、UUID 等）
   - 详细说明 `forceRemoteSync` 的具体行为和失败场景

---

*文档生成时间：2026-03-22*
*基于版本：codex-rs/app-server-protocol 最新主分支*
