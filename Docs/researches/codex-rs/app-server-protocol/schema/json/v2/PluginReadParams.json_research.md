# PluginReadParams.json 研究文档

## 场景与职责

`PluginReadParams.json` 是 Codex 应用服务器协议 v2 的 JSON Schema 定义文件，用于描述插件详情读取请求的参数结构。

该参数结构用于 `plugin/read` 方法，支持从指定的市场路径读取特定插件的详细信息，使客户端能够获取插件的完整元数据。

## 功能点目的

1. **插件详情获取**: 获取特定插件的完整元数据和配置信息
2. **市场定位**: 通过 `marketplacePath` 指定插件来源市场
3. **插件识别**: 通过 `pluginName` 指定要读取的插件
4. **安装前预览**: 支持在安装前查看插件详细信息

## 具体技术实现

### 数据结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "definitions": {
    "AbsolutePathBuf": {
      "description": "A path that is guaranteed to be absolute and normalized (though it is not guaranteed to be canonicalized or exist on the filesystem).\n\nIMPORTANT: When deserializing an `AbsolutePathBuf`, a base path must be set using [AbsolutePathBufGuard::new]. If no base path is set, the deserialization will fail unless the path being deserialized is already absolute.",
      "type": "string"
    }
  },
  "properties": {
    "marketplacePath": {
      "$ref": "#/definitions/AbsolutePathBuf"
    },
    "pluginName": {
      "type": "string"
    }
  },
  "required": ["marketplacePath", "pluginName"],
  "title": "PluginReadParams",
  "type": "object"
}
```

### 字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `marketplacePath` | string | 是 | 插件市场的绝对路径，标识插件来源位置 |
| `pluginName` | string | 是 | 要读取的插件名称 |

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs:3122
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
}
```

### 方法映射

```rust
// common.rs 行 303-306
PluginRead => "plugin/read" {
    params: v2::PluginReadParams,
    response: v2::PluginReadResponse,
}
```

### 路径类型说明

`AbsolutePathBuf` 是一个保证为绝对路径且已规范化的路径类型：
- 路径不一定是规范化的（canonicalized）
- 路径不一定存在于文件系统上
- 反序列化时需要设置基础路径（通过 `AbsolutePathBufGuard::new`）

## 关键代码路径与文件引用

### 协议定义
- **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3122-3128)
- **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/PluginReadParams.json`
- **方法注册**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 303-306)

### 调用方
- **客户端**: 通过 `plugin/read` 方法请求插件详情
- **UI 层**: 插件详情页面、安装确认对话框

### 响应结构
- **对应响应**: `PluginReadResponse` - 包含插件的完整详细信息

### 依赖类型
- **AbsolutePathBuf**: `codex_utils_absolute_path::AbsolutePathBuf`

## 依赖与外部交互

### 上游依赖
1. **插件市场系统**: 管理插件的发现和元数据
2. **文件系统**: 读取插件包和配置文件
3. **插件元数据解析器**: 解析插件配置和界面信息

### 下游使用方
1. **插件详情 UI**: 展示插件的完整信息
2. **安装确认**: 在安装前展示插件详情供用户确认
3. **配置编辑器**: 编辑插件配置

### 读取流程
1. 客户端调用 `plugin/read` 并传入 `PluginReadParams`
2. 服务器验证插件市场路径存在性
3. 服务器在市场路径下查找指定名称的插件
4. 解析插件元数据和配置
5. 返回 `PluginReadResponse`

## 风险、边界与改进建议

### 潜在风险
1. **路径安全**: 需要验证 `marketplacePath` 不指向敏感系统目录
2. **信息泄露**: 插件详情可能包含敏感配置信息
3. **路径不存在**: 指定的市场路径可能不存在
4. **插件不存在**: 指定市场中可能找不到对应插件

### 边界情况
1. **市场不存在**: 指定的 `marketplacePath` 不存在时的错误处理
2. **插件不存在**: 指定市场中找不到对应插件名称
3. **配置损坏**: 插件配置文件损坏或格式错误
4. **权限不足**: 无法读取插件目录或文件

### 改进建议

#### 1. 添加版本指定
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "version": "1.2.3"
}
```

#### 2. 添加读取选项
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "include": {
    "readme": true,
    "changelog": true,
    "config": true
  }
}
```

#### 3. 添加缓存控制
```json
{
  "marketplacePath": "/path/to/marketplace",
  "pluginName": "my-plugin",
  "cache": {
    "forceRefresh": false,
    "ifModifiedSince": 1712345678
  }
}
```

#### 4. 支持通过 ID 读取
```json
{
  "pluginId": "plugin-uuid-or-unique-id"
}
```

或者支持多种查询方式：
```json
{
  "query": {
    "type": "byPath",
    "marketplacePath": "/path/to/marketplace",
    "pluginName": "my-plugin"
  }
}
```

### 最佳实践
1. **路径验证**: 始终验证 `marketplacePath` 的合法性
2. **错误处理**: 提供清晰的错误信息，区分市场不存在和插件不存在
3. **缓存利用**: 客户端应缓存插件详情，减少重复请求
4. **权限检查**: 确保调用者有权限读取指定路径

### 相关 API
- `PluginReadResponse` - 插件详情响应
- `PluginListParams` / `PluginListResponse` - 插件列表查询
- `PluginInstallParams` / `PluginInstallResponse` - 插件安装
- `PluginSummary` - 插件摘要信息（列表中使用的简化版本）

### 与 PluginListResponse 的关系

`PluginReadParams` + `PluginReadResponse` 提供比 `PluginListResponse` 更详细的插件信息：

| 信息类型 | PluginListResponse | PluginReadResponse |
|---------|-------------------|-------------------|
| 基本信息 | ✓ | ✓ |
| 界面元数据 | ✓（简化） | ✓（完整） |
| 配置文件 | ✗ | ✓ |
| 依赖信息 | ✗ | ✓ |
| 权限要求 | ✗ | ✓ |
| 使用示例 | ✗ | ✓ |

客户端通常先调用 `plugin/list` 获取插件列表，然后根据用户选择调用 `plugin/read` 获取详细信息。
