# PluginSource 研究文档

## 场景与职责

`PluginSource` 是一个标签联合（Tagged Union）类型，定义了插件的来源信息。当前只支持本地路径来源，但设计为可扩展以支持其他来源类型（如远程 URL、Git 仓库等）。

## 功能点目的

该类型的核心功能是：
1. **来源追踪**: 记录插件的安装来源
2. **可扩展设计**: 支持未来添加更多来源类型
3. **本地开发支持**: 支持从本地路径加载插件

## 具体技术实现

### 数据结构

```typescript
export type PluginSource = { 
  "type": "local", 
  path: AbsolutePathBuf 
};
```

### Rust 源码定义

```rust
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

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `type` | `"local"` | 来源类型标识，固定为 `"local"` |
| `path` | `AbsolutePathBuf` | 插件的本地文件系统路径 |

### 序列化配置

- 使用 `#[serde(tag = "type")]` 实现标签联合序列化
- `type` 字段作为鉴别器（discriminator）
- 使用 camelCase 命名约定

### 使用场景

该类型主要用于 `PluginSummary`：

```rust
pub struct PluginSummary {
    pub id: String,
    pub name: String,
    pub source: PluginSource,  // <-- 这里
    pub installed: bool,
    pub enabled: bool,
    pub install_policy: PluginInstallPolicy,
    pub auth_policy: PluginAuthPolicy,
    pub interface: Option<PluginInterface>,
}
```

### 序列化示例

```json
{
  "type": "local",
  "path": "/home/user/.codex/plugins/my-plugin"
}
```

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 3332-3340 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginSource.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 依赖类型
- `AbsolutePathBuf`: 绝对路径类型
- `PluginSummary`: 使用该类型作为字段

### 协议集成
- 属于 App-Server Protocol v2 API
- 作为 `PluginSummary` 的一部分返回

### 插件系统集成
- 标识插件的物理位置
- 用于插件的加载和更新

## 风险、边界与改进建议

### 潜在风险
1. **路径安全**: `path` 是绝对路径，需要确保安全性
2. **路径有效性**: 路径可能在返回后变得无效
3. **跨平台**: 路径格式在不同操作系统上可能不同

### 边界情况
1. **单一来源**: 当前只支持本地路径，限制了插件分发方式
2. **路径移动**: 插件被移动后路径失效
3. **符号链接**: 路径可能是符号链接

### 改进建议
1. **添加远程来源**: 
   ```rust
   Remote { url: String, checksum: Option<String> }
   ```
2. **添加 Git 来源**:
   ```rust
   Git { repository: String, branch: Option<String>, commit: Option<String> }
   ```
3. **添加市场来源**:
   ```rust
   Marketplace { marketplace_id: String, plugin_id: String, version: String }
   ```
4. 添加 `installedAt` 字段记录安装时间
5. 添加 `installedBy` 字段记录安装者（对于多用户系统）
6. 考虑添加 `signature` 字段用于验证插件签名
