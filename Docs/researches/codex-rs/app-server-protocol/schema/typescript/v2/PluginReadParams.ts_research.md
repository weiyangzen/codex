# PluginReadParams 研究文档

## 场景与职责

`PluginReadParams` 定义了读取插件详情的请求参数类型。当客户端需要获取特定插件的完整信息时使用此类型指定要读取的插件。

## 功能点目的

该类型的核心功能是：
1. **精确定位插件**: 通过市场路径和插件名称唯一标识插件
2. **支持详情查看**: 获取插件的完整信息，包括技能、应用和 MCP 服务器
3. **安装前检查**: 允许用户在安装前查看插件详情

## 具体技术实现

### 数据结构

```typescript
export type PluginReadParams = { 
  marketplacePath: AbsolutePathBuf, 
  pluginName: string 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
}
```

### 字段详解

| 字段 | 类型 | 说明 |
|-----|------|------|
| `marketplacePath` | `AbsolutePathBuf` | 插件所在市场的文件系统路径 |
| `pluginName` | `string` | 要读取的插件名称 |

### 使用场景

作为 `plugin/read` API 的请求参数：

```rust
client_request_definitions! {
    PluginRead => "plugin/read" {
        params: v2::PluginReadParams,
        response: v2::PluginReadResponse,
    },
}
```

### 响应类型

```rust
pub struct PluginReadResponse {
    pub plugin: PluginDetail,
}
```

其中 `PluginDetail` 包含：
- 市场名称和路径
- 插件摘要信息
- 详细描述
- 包含的技能列表
- 关联的应用列表
- MCP 服务器列表

### 典型使用流程

1. 调用 `plugin/list` 获取可用插件列表
2. 用户选择感兴趣的插件
3. 使用 `PluginReadParams` 调用 `plugin/read` 获取详情
4. 展示 `PluginDetail` 中的详细信息给用户

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 3119-3125 |
| `codex-rs/app-server-protocol/schema/typescript/v2/PluginReadParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义，行 303-306 |

## 依赖与外部交互

### 依赖类型
- `AbsolutePathBuf`: 绝对路径类型
- `PluginReadResponse`: 对应的响应类型
- `PluginDetail`: 响应中包含的插件详情类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 是客户端向服务器发送的请求
- 方法名: `plugin/read`

### 插件系统集成
- 从文件系统读取插件的完整元数据
- 解析插件的 SKILL.md、SKILL.json 等文件

## 风险、边界与改进建议

### 潜在风险
1. **路径安全**: `marketplacePath` 是绝对路径，需要验证防止路径遍历
2. **插件不存在**: 指定的插件可能不存在于指定市场
3. **权限问题**: 可能没有权限读取某些插件

### 边界情况
1. **大小写敏感**: 插件名称的大小写处理
2. **特殊字符**: 插件名称包含特殊字符的处理
3. **并发修改**: 读取期间插件可能被修改或删除

### 改进建议
1. 添加 `version` 字段支持读取特定版本
2. 添加 `includeReadme` 选项控制是否包含完整 README
3. 添加 `locale` 字段支持本地化内容
4. 考虑使用插件 ID 替代名称，更稳定可靠
5. 添加 `includeChangelog` 选项控制是否包含更新日志
