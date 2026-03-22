# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-app-server-protocol` crate 的根模块文件，作为整个应用服务器协议库的入口点。该 crate 负责定义 Codex 应用服务器与客户端之间的通信协议，包括：

1. **协议类型导出**：导出所有客户端请求、服务器请求、通知类型及其参数/响应类型
2. **JSON-RPC 基础结构**：提供轻量级 JSON-RPC 消息格式定义
3. **Schema 生成支持**：支持生成 TypeScript 类型定义和 JSON Schema 用于客户端集成
4. **实验性 API 管理**：提供实验性 API 的标记和管理机制

该 crate 是 Codex 应用服务器架构的核心组件，被 `app-server`、`tui`、`tui_app_server` 等多个组件依赖。

## 功能点目的

### 1. 模块组织与重导出

文件通过模块化设计组织代码：
- `experimental_api`：实验性 API 标记 trait 和宏支持
- `export`：TypeScript/JSON Schema 生成逻辑
- `jsonrpc_lite`：轻量级 JSON-RPC 类型定义
- `protocol`：核心协议定义（common、v1、v2、thread_history）
- `schema_fixtures`：Schema 测试固件管理

### 2. 协议版本管理

支持两个主要协议版本：
- **v1**：旧版 API（如 `GetConversationSummary`、`GitDiffToRemote` 等），保持向后兼容
- **v2**：新版 API（如 `thread/start`、`turn/start` 等），当前主要开发方向

### 3. 类型导出策略

使用 `pub use` 重导出所有公共类型，使外部使用者可以通过单一入口访问：
- 请求类型：`ClientRequest`、`ServerRequest`
- 通知类型：`ClientNotification`、`ServerNotification`
- 参数/响应类型：如 `ThreadStartParams`、`ConfigReadResponse` 等

## 具体技术实现

### 关键数据结构

```rust
// 模块声明
mod experimental_api;
mod export;
mod jsonrpc_lite;
mod protocol;
mod schema_fixtures;
```

### 导出模式

文件采用"显式枚举导出"模式，为每个公共类型提供独立导出：

```rust
pub use protocol::v1::ApplyPatchApprovalParams;
pub use protocol::v1::ApplyPatchApprovalResponse;
// ... 更多 v1 类型

pub use protocol::v2::*;  // v2 使用通配符导出
```

### Schema 固件功能

```rust
pub use schema_fixtures::SchemaFixtureOptions;
pub use schema_fixtures::read_schema_fixture_subtree;
pub use schema_fixtures::read_schema_fixture_tree;
pub use schema_fixtures::write_schema_fixtures;
pub use schema_fixtures::write_schema_fixtures_with_options;
```

## 关键代码路径与文件引用

### 直接依赖模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `experimental_api` | `src/experimental_api.rs` | 实验性 API 标记系统 |
| `export` | `src/export.rs` | TypeScript/JSON Schema 生成 |
| `jsonrpc_lite` | `src/jsonrpc_lite.rs` | JSON-RPC 基础类型 |
| `protocol` | `src/protocol/` | 协议定义子模块 |
| `schema_fixtures` | `src/schema_fixtures.rs` | Schema 测试固件 |

### 协议子模块结构

```
src/protocol/
├── mod.rs          # 子模块入口
├── common.rs       # 共享类型（ClientRequest/ServerRequest 定义）
├── v1.rs           # v1 API 类型
├── v2.rs           # v2 API 类型（主要开发方向）
├── thread_history.rs # 线程历史构建
├── mappers.rs      # 类型映射
└── serde_helpers.rs # 序列化辅助
```

### 调用方分析

通过代码搜索，主要调用方包括：
- `codex-rs/app-server`：应用服务器实现
- `codex-rs/tui`：终端用户界面
- `codex-rs/tui_app_server`：TUI 应用服务器

## 依赖与外部交互

### 内部依赖

```toml
[dependencies]
codex-protocol = { workspace = true }
codex-experimental-api-macros = { workspace = true }
codex-utils-absolute-path = { workspace = true }
```

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型生成 |
| `serde` | 序列化/反序列化 |
| `strum_macros` | 枚举工具宏 |
| `inventory` | 实验性字段注册 |

### Schema 输出

生成的 Schema 文件位于：
- `schema/typescript/`：TypeScript 类型定义
- `schema/json/`：JSON Schema 定义

## 风险、边界与改进建议

### 当前风险

1. **版本兼容性**：v1 和 v2 API 并存，维护成本较高
2. **实验性 API 管理**：实验性标记分散在多个文件中，可能遗漏
3. **导出膨胀**：大量使用 `pub use` 可能导致公共 API 表面过大

### 边界情况

1. **Schema 生成平台差异**：Windows 和 Unix 的换行符差异已在 `schema_fixtures.rs` 中处理
2. **JSON 数组排序**：跨平台 Schema 比较时需要规范化数组顺序

### 改进建议

1. **模块化导出**：考虑按功能模块组织导出，而非单一平面导出
2. **版本弃用计划**：制定 v1 API 的弃用时间表
3. **文档生成**：考虑添加自动化 API 文档生成
4. **类型安全**：考虑使用 newtype 模式增强类型安全

### 维护注意事项

- 修改协议类型后需运行 `just write-app-server-schema` 更新 Schema 固件
- 新增实验性 API 需使用 `#[experimental("reason")]` 标记
- 保持 Rust 和 TypeScript 命名一致性（camelCase）
