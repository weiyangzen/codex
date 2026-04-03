# PluginReadParams 研究文档

## 1. 场景与职责

`PluginReadParams` 是读取单个插件详情的请求参数类型，用于指定要查看的插件所在的市场和插件名称。

**使用场景：**
- 插件详情页面：用户点击插件卡片查看详细信息
- 插件安装前确认：获取插件的完整信息供用户确认
- 插件管理：查看已安装插件的详细信息

## 2. 功能点目的

该类型的核心目的是：

1. **定位特定插件**：通过市场路径和插件名称唯一标识一个插件
2. **支持跨市场查询**：允许从任意市场获取插件详情
3. **简化查询接口**：仅需两个参数即可获取完整插件信息

## 3. 具体技术实现

### TypeScript 定义
```typescript
import type { AbsolutePathBuf } from "../common/AbsolutePathBuf.js";

export type PluginReadParams = {
  marketplacePath: AbsolutePathBuf;
  pluginName: string;
};
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
}
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `marketplacePath` | `AbsolutePathBuf` | 插件所在市场的文件系统路径 |
| `pluginName` | `string` | 插件的名称标识 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行3122-3125

**关联的响应类型：**
- `PluginReadResponse`：对应的读取响应（行3127-3132）

**API方法：**
- `plugin/read`：使用此参数的RPC方法

## 5. 依赖与外部交互

**导入依赖：**
- `AbsolutePathBuf`：绝对路径类型，用于市场路径

**使用场景：**
- 插件详情查询API
- 与 `PluginReadResponse` 配对使用

## 6. 风险、边界与改进建议

### 潜在风险
1. **路径遍历攻击**：marketplacePath可能包含恶意路径
2. **插件不存在**：指定的插件可能在市场中不存在
3. **权限问题**：用户可能没有访问该市场的权限

### 边界情况
- 市场路径不存在：返回错误
- 插件名称不存在于市场：返回错误
- 市场路径有效但插件已删除：返回错误

### 改进建议
1. **添加路径验证**：确保marketplacePath指向有效的市场目录
2. **使用插件ID**：除了名称，考虑支持使用唯一ID定位插件
3. **添加版本参数**：支持获取特定版本的插件详情
4. **添加缓存控制**：支持客户端缓存控制头
5. **错误细化**：区分"市场不存在"和"插件不存在"的错误
