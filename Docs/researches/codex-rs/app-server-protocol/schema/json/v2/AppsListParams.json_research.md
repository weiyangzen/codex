# AppsListParams Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`AppsListParams` 是 **EXPERIMENTAL** 状态的请求参数类型，用于 `app/list` 方法查询可用的 App/Connector 列表。

**使用场景：**
- 客户端初始化时加载应用市场
- 用户浏览可用应用时
- 刷新应用列表时
- 根据线程配置筛选可访问应用时

**职责：**
- 支持分页查询（cursor/limit）
- 支持按线程配置筛选
- 支持强制刷新缓存
- 提供灵活的应用列表查询能力

## 2. 功能点目的 (Purpose of the Functionality)

该参数类型的核心目的是实现应用列表的灵活查询：

1. **分页加载**: 支持大量应用的分页展示
2. **配置感知**: 根据线程配置评估应用可访问性
3. **缓存控制**: 支持强制刷新获取最新数据
4. **性能优化**: 避免一次性加载所有应用数据

**字段说明：**
- `cursor` (string | null): 分页游标，用于获取下一页
- `limit` (uint32 | null): 每页数量限制
- `threadId` (string | null): 可选线程 ID，用于评估应用可访问性
- `forceRefetch` (boolean): 是否强制刷新缓存

## 3. 具体技术实现 (Technical Implementation Details)

### 数据结构设计

```rust
// 定义位置: codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
/// EXPERIMENTAL - list available apps/connectors.
pub struct AppsListParams {
    /// Opaque pagination cursor returned by a previous call.
    #[ts(optional = nullable)]
    pub cursor: Option<String>,
    /// Optional page size; defaults to a reasonable server-side value.
    #[ts(optional = nullable)]
    pub limit: Option<u32>,
    /// Optional thread id used to evaluate app feature gating from that thread's config.
    #[ts(optional = nullable)]
    pub thread_id: Option<String>,
    /// When true, bypass app caches and fetch the latest data from sources.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub force_refetch: bool,
}
```

### 协议集成

在 `common.rs` 中注册为客户端请求：

```rust
client_request_definitions! {
    AppsList => "app/list" {
        params: v2::AppsListParams,
        response: v2::AppsListResponse,
    },
}
```

### 请求流程

1. 客户端构造 `AppsListParams`
2. 发送 `app/list` 请求到服务器
3. 服务器根据参数查询应用列表
4. 返回 `AppsListResponse` 包含应用数据和下一页游标

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 定义文件
- **主要定义**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs` (第 1929-1946 行)
- **协议注册**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs` (第 307-310 行)

### 相关类型
- `AppsListResponse`: 应用列表响应
- `AppInfo`: 应用信息类型

### 生成文件
- **JSON Schema**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/json/v2/AppsListParams.json`

### 相关通知
- `AppListUpdatedNotification`: 应用列表更新通知

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 内部依赖
- `#[experimental]` 宏标记实验性功能
- 标准 `Option` 类型用于可选字段
- `#[ts(optional = nullable)]` 用于 TypeScript 生成

### 外部交互
- **App 市场服务**: 查询应用列表
- **配置系统**: 根据 threadId 评估应用可访问性
- **缓存系统**: 处理 forceRefetch 的缓存刷新

### 相关配置
- `AppsConfig`: 应用配置
- 线程级别的配置可能影响应用可见性

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险点

1. **实验性状态**: API 可能不稳定
2. **缓存失效**: forceRefetch 可能导致性能问题
3. **权限泄漏**: threadId 可能暴露敏感配置信息

### 边界情况

1. **空游标**: 首次请求时 cursor 为 null
2. **超出范围**: limit 超过服务器最大值
3. **无效 threadId**: 线程不存在时的处理
4. **网络中断**: 分页请求中断后的恢复

### 改进建议

1. **添加筛选**: 支持按分类、开发者等筛选
2. **排序选项**: 支持按名称、更新时间排序
3. **搜索支持**: 添加关键词搜索参数
4. **批量获取**: 支持按 ID 列表批量获取
5. **稳定化**: 考虑从实验状态提升为稳定 API

### 测试建议

1. 测试分页逻辑的正确性
2. 测试 forceRefetch 的缓存刷新
3. 测试无效 threadId 的错误处理
4. 测试各种 limit 值的边界
5. 验证实验性标记的处理

### 客户端实现建议

1. 实现分页加载（无限滚动/分页器）
2. 本地缓存应用列表数据
3. 提供手动刷新按钮（使用 forceRefetch）
4. 处理空列表和无更多数据的场景
5. 展示实验性功能警告
