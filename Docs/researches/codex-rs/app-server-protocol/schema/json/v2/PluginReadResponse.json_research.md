# PluginReadResponse.json 研究文档

## 场景与职责

`PluginReadResponse` 是 Codex App-Server Protocol v2 API 中 `plugin/read` 方法的响应结构，用于返回指定插件的详细信息。该响应在客户端查询特定插件详情时返回，包含插件的完整元数据、关联应用、技能列表、MCP 服务器等信息。

## 功能点目的

1. **插件详情查询响应**: 作为 `plugin/read` RPC 方法的响应体，提供单个插件的完整信息
2. **插件生态整合**: 展示插件与 App、Skill、MCP Server 的关联关系
3. **插件状态管理**: 包含插件的安装状态、启用状态、认证策略等运行时信息
4. **市场集成**: 支持插件市场相关字段（marketplaceName, marketplacePath）

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct PluginReadResponse {
    pub plugin: PluginDetail,
}
```

### 核心类型定义

**PluginDetail** - 插件详细信息:
- `summary`: PluginSummary - 插件基础摘要信息
- `description`: Option<String> - 插件详细描述
- `marketplace_name`: String - 市场名称
- `marketplace_path`: AbsolutePathBuf - 市场路径（绝对路径）
- `apps`: Vec<AppSummary> - 关联的应用列表
- `mcp_servers`: Vec<String> - 关联的 MCP 服务器名称列表
- `skills`: Vec<SkillSummary> - 关联的技能列表

**PluginSummary** - 插件摘要:
- `id`: String - 插件唯一标识
- `name`: String - 插件名称
- `source`: PluginSource - 插件来源（目前仅支持 LocalPluginSource）
- `installed`: bool - 是否已安装
- `enabled`: bool - 是否启用
- `install_policy`: PluginInstallPolicy - 安装策略（NOT_AVAILABLE/AVAILABLE/INSTALLED_BY_DEFAULT）
- `auth_policy`: PluginAuthPolicy - 认证策略（ON_INSTALL/ON_USE）
- `interface`: Option<PluginInterface> - 插件界面配置

**PluginInterface** - 插件界面配置:
- `display_name`: Option<String> - 显示名称
- `developer_name`: Option<String> - 开发者名称
- `short_description`: Option<String> - 简短描述
- `long_description`: Option<String> - 详细描述
- `category`: Option<String> - 分类
- `brand_color`: Option<String> - 品牌色
- `logo`: Option<AbsolutePathBuf> - Logo 路径
- `composer_icon`: Option<AbsolutePathBuf> - Composer 图标路径
- `screenshots`: Vec<AbsolutePathBuf> - 截图路径列表
- `capabilities`: Vec<String> - 能力列表
- `default_prompt`: Option<Vec<String>> - 默认提示词（最多3条，每条最多128字符）
- `website_url`: Option<String> - 网站 URL
- `privacy_policy_url`: Option<String> - 隐私政策 URL
- `terms_of_service_url`: Option<String> - 服务条款 URL

**SkillSummary** - 技能摘要:
- `name`: String - 技能名称
- `description`: String - 技能描述
- `path`: String - 技能路径
- `short_description`: Option<String> - 简短描述
- `interface`: Option<SkillInterface> - 技能界面配置

**AppSummary** - 应用摘要（实验性）:
- `id`: String - 应用 ID
- `name`: String - 应用名称
- `description`: Option<String> - 应用描述
- `install_url`: Option<String> - 安装 URL

### 枚举类型

**PluginInstallPolicy**:
- `NOT_AVAILABLE` - 不可安装
- `AVAILABLE` - 可安装
- `INSTALLED_BY_DEFAULT` - 默认已安装

**PluginAuthPolicy**:
- `ON_INSTALL` - 安装时认证
- `ON_USE` - 使用时认证

**PluginSource** - Tagged Union:
- `LocalPluginSource` - 本地插件源
  - `type`: "local"
  - `path`: AbsolutePathBuf - 本地路径

## 关键代码路径与文件引用

### 源文件位置
- **Rust 结构定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `PluginReadResponse`: 第 3130 行附近
  - `PluginDetail`: 第 3100 行附近
  - `PluginSummary`: 第 3040 行附近
  - `PluginInterface`: 第 3055 行附近
  - `SkillSummary`: 第 3080 行附近
  - `AppSummary`: 第 2030 行附近

### Schema 生成
- **生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`
- **生成函数**: `write_schema_fixtures_with_options()` 调用 `export_client_response_schemas()`
- **导出宏**: `client_request_definitions!` 在 `common.rs` 中定义

### 使用位置
- **ClientRequest 定义**: `codex-rs/app-server-protocol/src/protocol/common.rs` 第 303-306 行
```rust
PluginRead => "plugin/read" {
    params: v2::PluginReadParams,
    response: v2::PluginReadResponse,
}
```

## 依赖与外部交互

### 内部依赖
1. **codex_protocol**: 核心协议类型（PluginMetadata, SkillMetadata 等）
2. **codex_utils_absolute_path**: AbsolutePathBuf 类型用于路径处理
3. **schemars**: JSON Schema 生成
4. **ts_rs**: TypeScript 类型生成
5. **serde**: 序列化/反序列化

### 外部交互
1. **插件市场**: 通过 `marketplace_name` 和 `marketplace_path` 与插件市场交互
2. **MCP 服务器**: `mcp_servers` 字段关联 MCP 服务器配置
3. **App 系统**: `apps` 字段关联应用元数据
4. **Skill 系统**: `skills` 字段关联技能元数据

### 相关类型映射
- `PluginDetail` 从 `codex_protocol::plugins::PluginMetadata` 转换而来
- `PluginSummary` 从 `codex_protocol::plugins::PluginSummary` 转换而来
- `SkillSummary` 从 `codex_protocol::protocol::SkillMetadata` 转换而来

## 风险、边界与改进建议

### 风险点
1. **AbsolutePathBuf 序列化**: 路径类型在反序列化时需要设置 base path，否则可能失败
2. **实验性 API**: `AppSummary` 标记为 EXPERIMENTAL，未来可能变更
3. **PluginSource 扩展**: 目前仅支持本地源，未来添加远程源时需要变更 oneOf 结构

### 边界情况
1. **空插件**: `PluginDetail` 的所有字段都是 required，但 `description`, `interface` 等可为 null
2. **技能列表**: `skills` 数组可能为空
3. **MCP 服务器**: `mcp_servers` 数组可能为空
4. **路径处理**: `AbsolutePathBuf` 要求绝对路径，相对路径会导致反序列化失败

### 改进建议
1. **缓存优化**: 插件详情查询结果可考虑缓存，减少重复 I/O
2. **增量更新**: 支持插件元数据的增量更新通知机制
3. **错误细化**: 当前响应不包含错误详情，建议添加 `error` 字段用于失败场景
4. **版本控制**: 建议添加 `version` 字段支持插件版本管理
5. **权限细化**: `auth_policy` 可考虑细化为更灵活的权限模型
