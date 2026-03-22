# Cargo.toml 研究文档

## 场景与职责

该文件定义了 `codex-connectors` crate 的元数据、依赖关系和构建设置。它是 Rust 生态系统的标准配置文件，同时支持 Cargo 和 Bazel 两种构建系统。该 crate 负责从 ChatGPT 目录 API 获取连接器（Connectors/Apps）信息，并提供缓存和合并功能。

## 功能点目的

### 1. 包元数据
```toml
[package]
name = "codex-connectors"
version.workspace = true
edition.workspace = true
license.workspace = true
```
- 使用 Workspace 继承机制，统一管理版本、Rust Edition 和许可证
- 保持与 Workspace 中其他 crate 的一致性

### 2. 代码质量检查
```toml
[lints]
workspace = true
```
- 继承 Workspace 级别的 Clippy 和 Rust lint 配置
- 确保代码风格和质量标准的一致性

### 3. 运行时依赖
```toml
[dependencies]
anyhow = { workspace = true }
codex-app-server-protocol = { workspace = true }
serde = { workspace = true, features = ["derive"] }
urlencoding = { workspace = true }
```

### 4. 开发依赖
```toml
[dev-dependencies]
pretty_assertions = { workspace = true }
tokio = { workspace = true, features = ["macros", "rt-multi-thread"] }
```

## 具体技术实现

### 依赖详解

#### `anyhow`
- **用途**: 简化错误处理，提供 `anyhow::Result<T>` 类型
- **使用场景**: `list_all_connectors_with_options` 等异步函数返回 `anyhow::Result<Vec<AppInfo>>`

#### `codex-app-server-protocol`
- **用途**: 提供应用服务器协议类型
- **关键类型**:
  - `AppInfo`: 连接器信息结构体，包含 id、name、description、logo_url 等字段
  - `AppBranding`: 品牌信息（category、developer、website 等）
  - `AppMetadata`: 应用元数据（categories、screenshots、version 等）
- **协议版本**: 对应 app-server-protocol v2 API

#### `serde`
- **用途**: JSON 序列化/反序列化
- **特性**: `derive` 启用派生宏（`#[derive(Deserialize)]`）
- **使用场景**: 解析 ChatGPT API 返回的 JSON 响应到 `DirectoryListResponse` 和 `DirectoryApp`

#### `urlencoding`
- **用途**: URL 参数编码
- **使用场景**: 对分页 token 进行 URL 编码（`urlencoding::encode(token)`）

### 开发依赖详解

#### `pretty_assertions`
- **用途**: 测试失败时提供美观的 diff 输出
- **使用场景**: 单元测试中的 `assert_eq!` 宏

#### `tokio`
- **用途**: 异步运行时
- **特性**: 
  - `macros`: 启用 `#[tokio::test]` 测试宏
  - `rt-multi-thread`: 多线程运行时
- **使用场景**: 异步测试函数

## 关键代码路径与文件引用

| 路径 | 说明 |
|------|------|
| `src/lib.rs` | 主库实现，包含连接器获取、缓存、合并逻辑 |
| `BUILD.bazel` | Bazel 构建配置 |
| `../app-server-protocol/src/protocol/v2.rs` | `AppInfo`, `AppBranding`, `AppMetadata` 定义 |
| `../Cargo.toml` | Workspace 根配置，定义共享依赖版本 |

## 依赖与外部交互

### 上游依赖（被调用）
- **ChatGPT API**: 通过 HTTP GET 请求获取连接器目录
  - `/connectors/directory/list?tier=categorized&external_logos=true`
  - `/connectors/directory/list_workspace?external_logos=true`

### 下游依赖（调用方）
- **`codex-core`**: 在 `core/src/connectors.rs` 中重新导出并扩展功能
  - `list_accessible_connectors_from_mcp_tools`: 从 MCP 工具获取可访问连接器
  - `merge_connectors`: 合并目录连接器和可访问连接器
  - `filter_disallowed_connectors`: 过滤不允许的连接器
  
- **`codex-chatgpt`**: 在 `chatgpt/src/connectors.rs` 中调用
  - `list_all_connectors_with_options`: 获取所有连接器
  - `cached_all_connectors`: 获取缓存的连接器

### 数据结构依赖

```rust
// DirectoryListResponse - API 响应结构
pub struct DirectoryListResponse {
    apps: Vec<DirectoryApp>,
    next_token: Option<String>,
}

// DirectoryApp - 目录应用原始数据
pub struct DirectoryApp {
    id: String,
    name: String,
    description: Option<String>,
    app_metadata: Option<AppMetadata>,
    branding: Option<AppBranding>,
    labels: Option<HashMap<String, String>>,
    logo_url: Option<String>,
    logo_url_dark: Option<String>,
    distribution_channel: Option<String>,
    visibility: Option<String>,
}
```

## 风险、边界与改进建议

### 风险

1. **API 变更风险**: `DirectoryListResponse` 和 `DirectoryApp` 结构与 ChatGPT API 紧密耦合，API 变更需要同步更新
2. **序列化兼容性**: 使用 `#[serde(alias = "...")]` 处理字段命名差异（如 `nextToken`），但新增字段可能导致兼容性问题
3. **缓存失效**: 全局静态缓存 `ALL_CONNECTORS_CACHE` 没有显式失效机制，仅依赖 TTL（3600秒）

### 边界

1. **单 Workspace 限制**: 依赖 Workspace 配置，不能独立构建
2. **Feature 标志缺失**: 没有使用 Cargo features 进行条件编译，所有功能始终启用
3. **平台兼容性**: `urlencoding` 和 `serde` 是跨平台的，但 HTTP 客户端由调用方提供（通过回调函数）

### 改进建议

1. **添加 Feature 标志**: 
   ```toml
   [features]
   default = []
   caching = []
   workspace-support = []
   ```
   允许调用方选择需要的功能

2. **版本兼容性**: 考虑使用 `serde_json::Value` 作为中间层，提供更宽松的 API 兼容性

3. **依赖优化**: 
   - `urlencoding` 可以用 `percent-encoding` 替代（如果其他 crate 已依赖）
   - 考虑将 `anyhow` 替换为 `thiserror` 以提供更结构化的错误类型

4. **测试增强**:
   ```toml
   [dev-dependencies]
   wiremock = { workspace = true }  # 用于模拟 HTTP API
   ```

5. **文档生成**:
   ```toml
   [package]
   documentation = "https://docs.rs/codex-connectors"
   repository = "https://github.com/openai/codex"
   ```

## 构建命令

```bash
# Cargo 构建
cargo build -p codex-connectors

# 运行测试
cargo test -p codex-connectors

# 检查依赖
cargo tree -p codex-connectors

# 发布检查（dry run）
cargo publish -p codex-connectors --dry-run
```

## 相关文件大小

- `Cargo.toml`: 451 bytes
- `src/lib.rs`: ~534 行
- `BUILD.bazel`: 123 bytes

该 crate 是一个轻量级工具 crate，专注于连接器数据的获取和缓存，业务逻辑主要在 `codex-core` 中实现。
