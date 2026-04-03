# PluginReadParams 研究文档

## 场景与职责

`PluginReadParams` 是读取单个插件详情的请求参数类型。它通过指定市场路径和插件名称，精确标识需要查询的插件，返回完整的插件详细信息。

该类型用于用户查看插件详情、安装前预览、或管理已安装插件时的数据获取。

## 功能点目的

1. **精确定位**: 通过 `marketplacePath` 和 `pluginName` 唯一标识插件
2. **详情获取**: 获取比列表视图更丰富的插件信息
3. **安装准备**: 在安装前查看插件的完整信息
4. **管理支持**: 支持已安装插件的详情查看

## 具体技术实现

### 数据结构

```typescript
export type PluginReadParams = { 
  marketplacePath: AbsolutePathBuf, 
  pluginName: string, 
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| `marketplacePath` | `AbsolutePathBuf` | 插件所在市场的配置文件路径 |
| `pluginName` | `string` | 插件的名称（在市场内的唯一标识） |

### 响应类型

对应的响应类型为 `PluginReadResponse`：

```typescript
export type PluginReadResponse = { 
  plugin: PluginDetail, 
};

type PluginDetail = {
  marketplaceName: string,
  marketplacePath: AbsolutePathBuf,
  summary: PluginSummary,
  description: string | null,
  skills: SkillSummary[],
  apps: AppSummary[],
  mcpServers: string[],
};
```

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 从 Rust 源代码生成。

对应的 Rust 定义：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadParams {
    pub marketplace_path: AbsolutePathBuf,
    pub plugin_name: String,
}
```

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/PluginReadParams.ts`
- **依赖类型**: `AbsolutePathBuf.ts`
- **响应类型**: `PluginReadResponse.ts`
- **索引**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行号约 3122-3125)
- **响应定义**: 同一文件 (行号约 3127-3132)

### 协议注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册：
```rust
client_request_definitions! {
    // ...
    PluginRead => "plugin/read" {
        params: v2::PluginReadParams,
        response: v2::PluginReadResponse,
    },
    // ...
}
```

### 核心使用位置

1. **App Server 消息处理**
   - 文件: `codex-rs/app-server/src/codex_message_processor.rs`
   - 导入: `use codex_app_server_protocol::PluginReadParams;`

2. **测试套件**
   - 文件: `codex-rs/app-server/tests/suite/v2/plugin_read.rs`
   - 文件: `codex-rs/app-server/tests/common/mcp_process.rs`

## 依赖与外部交互

### 查询流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        插件详情查询流程                                  │
└─────────────────────────────────────────────────────────────────────────┘

  Client                      App Server                   Plugin System
    │                             │                            │
    │  1. plugin/read             │                            │
    │     {                       │                            │
    │       marketplacePath,      │                            │
    │       pluginName            │                            │
    │     }                       │                            │
    │────────────────────────────▶│                            │
    │                             │                            │
    │                             │  2. 读取市场配置             │
    │                             │     定位插件                │
    │                             │                            │
    │                             │  3. 加载插件详情             │
    │                             │     - manifest              │
    │                             │     - skills                │
    │                             │     - apps                  │
    │                             │     - mcpServers            │
    │                             │                            │
    │  4. { plugin: PluginDetail }│                            │
    │◀────────────────────────────│                            │
    │                             │                            │
```

### 参数来源

通常从 `PluginListResponse` 中的数据构造：

```typescript
// 从列表响应中获取参数
const listResponse: PluginListResponse = await pluginList(params);

for (const marketplace of listResponse.marketplaces) {
  for (const plugin of marketplace.plugins) {
    // 构造详情查询参数
    const readParams: PluginReadParams = {
      marketplacePath: marketplace.path,
      pluginName: plugin.name,
    };
    
    const detail = await pluginRead(readParams);
    // 展示详情...
  }
}
```

## 风险、边界与改进建议

### 已知风险

1. **路径失效**: `marketplacePath` 指向的文件不存在
   - 风险: 查询失败
   - 缓解: 返回明确的错误信息

2. **插件不存在**: `pluginName` 在市场内找不到
   - 风险: 404 错误
   - 缓解: 返回友好的错误提示

3. **权限问题**: 无权限读取市场文件或插件目录
   - 风险: 访问被拒绝
   - 缓解: 检查权限并返回适当错误

### 边界情况

1. **大小写敏感**: `pluginName` 是否区分大小写
   - 建议: 实现不区分大小写的匹配

2. **特殊字符**: `pluginName` 包含特殊字符
   - 需要正确的 URL 编码/解码

3. **并发修改**: 查询过程中市场文件被修改
   - 可能返回不一致的数据

### 改进建议

1. **支持插件 ID**:
   ```typescript
   pluginId?: string;  // 全局唯一 ID，替代 marketplacePath + pluginName
   ```

2. **添加版本指定**:
   ```typescript
   version?: string;  // 查询特定版本
   ```

3. **支持缓存控制**:
   ```typescript
   cacheControl?: "no-cache" | "max-age-seconds";
   ```

4. **添加字段选择**:
   ```typescript
   fields?: ("description" | "skills" | "apps" | "mcpServers")[];
   ```

### 测试建议

1. **单元测试**:
   - 参数序列化/反序列化

2. **集成测试**:
   - 正常查询流程
   - 插件不存在
   - 路径不存在

3. **边界测试**:
   - 特殊字符名称
   - 空名称
   - 超长名称

### UI/UX 建议

1. **加载状态**: 显示详情加载进度
2. **错误处理**: 清晰的错误提示和重试按钮
3. **缓存优化**: 已查看的插件详情本地缓存
