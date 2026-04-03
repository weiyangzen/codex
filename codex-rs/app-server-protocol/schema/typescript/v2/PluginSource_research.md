# PluginSource 研究文档

## 1. 场景与职责

`PluginSource` 是插件来源的联合类型（discriminated union），用于标识插件的来源位置和获取方式。目前支持本地文件系统路径作为来源。

**使用场景：**
- 插件安装来源追踪：记录插件从何处安装
- 插件更新检查：根据来源确定如何检查更新
- 插件迁移：在不同环境间迁移插件时保持来源信息

## 2. 功能点目的

该类型的核心目的是：

1. **标识插件来源**：明确插件是从何处加载的
2. **支持扩展**：为未来添加更多来源类型（如远程URL、Git仓库等）预留结构
3. **类型安全**：使用tagged union确保类型安全

## 3. 具体技术实现

### TypeScript 定义
```typescript
import type { AbsolutePathBuf } from "../common/AbsolutePathBuf.js";

export type PluginSource = {
  type: "local";
  path: AbsolutePathBuf;
};
```

### Rust 源实现
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

### 关键特性
- 使用 `#[serde(tag = "type")]` 实现tagged union序列化
- 使用 `rename_all = "camelCase"` 确保字段命名风格一致
- 当前仅支持 `Local` 变体，包含 `path` 字段

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `"local"` | 来源类型标识，当前仅支持 "local" |
| `path` | `AbsolutePathBuf` | 本地文件系统路径 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3332-3340

**使用位置：**
- `PluginSummary.source`：插件摘要中的来源信息（行3278）

## 5. 依赖与外部交互

**导入依赖：**
- `AbsolutePathBuf`：绝对路径类型，用于本地路径

**使用场景：**
- `PluginSummary` 的组成部分
- 插件来源追踪和管理

## 6. 风险、边界与改进建议

### 潜在风险
1. **路径失效**：本地路径可能在插件安装后被移动或删除
2. **跨平台问题**：路径格式在不同操作系统间可能不兼容
3. **安全风险**：路径可能指向敏感目录

### 边界情况
- 路径指向的目录不存在：需要优雅处理
- 路径是相对路径：应该转换为绝对路径存储
- 网络路径：当前不支持UNC路径或网络共享

### 改进建议
1. **添加更多来源类型**：
   - `Remote`：从远程URL下载
   - `Git`：从Git仓库克隆
   - `Registry`：从插件注册表安装
   - `Builtin`：内置插件
2. **添加来源验证**：验证来源路径/URL的有效性
3. **添加版本信息**：记录来源的具体版本（如Git commit hash）
4. **添加校验和**：验证插件完整性
5. **支持路径变量**：允许使用环境变量或特殊标记（如 `$HOME`）
