# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-cloud-tasks-client` crate 的库入口文件，负责模块组织和公共 API 导出。它采用条件编译（feature flags）来支持两种后端实现：在线 HTTP 客户端和离线 Mock 客户端。

主要使用场景：
- 作为 `codex-cloud-tasks` crate 的依赖，提供云任务客户端功能
- 支持 TUI/CLI 应用在在线模式和测试模式之间切换
- 为单元测试提供 Mock 实现，避免真实网络调用

## 功能点目的

### 1. 模块组织

```rust
mod api;  // 核心 API 定义（trait + 数据类型）

#[cfg(feature = "mock")]
mod mock;  // Mock 实现（仅 mock feature 启用时编译）

#[cfg(feature = "online")]
mod http;  // HTTP 实现（仅 online feature 启用时编译）
```

### 2. 公共 API 导出

从 `api` 模块重新导出所有公共类型：

```rust
pub use api::ApplyOutcome;
pub use api::ApplyStatus;
pub use api::AttemptStatus;
pub use api::CloudBackend;      // 核心 trait
pub use api::CloudTaskError;    // 错误类型
pub use api::CreatedTask;
pub use api::DiffSummary;
pub use api::Result;            // Result<T, CloudTaskError>
pub use api::TaskId;
pub use api::TaskListPage;
pub use api::TaskStatus;
pub use api::TaskSummary;
pub use api::TaskText;
pub use api::TurnAttempt;
```

### 3. 条件编译导出

```rust
#[cfg(feature = "mock")]
pub use mock::MockClient;       // 测试用 Mock 客户端

#[cfg(feature = "online")]
pub use http::HttpClient;       // 真实 HTTP 客户端
```

## 具体技术实现

### Feature 配置

在 `Cargo.toml` 中定义：

```toml
[features]
default = ["online"]      # 默认启用在线模式
online = ["dep:codex-backend-client"]  # 依赖 backend-client
mock = []                  # 无额外依赖
```

### 架构设计

```
┌─────────────────────────────────────┐
│        cloud-tasks-client           │
│           (lib.rs)                  │
├─────────────────────────────────────┤
│  api.rs (trait + types)             │
│  ├── CloudBackend trait             │
│  ├── TaskSummary, TaskId, etc.      │
│  └── CloudTaskError                 │
├─────────────────────────────────────┤
│  http.rs (online feature)           │
│  └── HttpClient implements          │
│      CloudBackend                   │
├─────────────────────────────────────┤
│  mock.rs (mock feature)             │
│  └── MockClient implements          │
│      CloudBackend                   │
└─────────────────────────────────────┘
```

### 注释说明

文件末尾的注释：
```rust
// Reusable apply engine now lives in the shared crate `codex-git`.
```

说明补丁应用逻辑已从本 crate 迁移到独立的 `codex-git` crate，实现了代码复用。

## 关键代码路径与文件引用

```
codex-rs/cloud-tasks-client/src/lib.rs
├── 模块声明 (lines 1-2)
│   └── mod api;
├── 公共类型导出 (lines 3-16)
│   ├── 从 api 模块导出所有核心类型
├── Mock 模块条件编译 (lines 18-19)
│   └── #[cfg(feature = "mock")] mod mock;
├── HTTP 模块条件编译 (lines 21-22)
│   └── #[cfg(feature = "online")] mod http;
├── MockClient 条件导出 (lines 24-25)
│   └── #[cfg(feature = "mock")] pub use mock::MockClient;
├── HttpClient 条件导出 (lines 27-28)
│   └── #[cfg(feature = "online")] pub use http::HttpClient;
└── 注释 (line 30)
    └── codex-git 迁移说明
```

### 依赖文件

| 文件 | 用途 |
|------|------|
| `api.rs` | 核心 trait 和数据类型定义 |
| `http.rs` | HTTP 客户端实现（online feature） |
| `mock.rs` | Mock 客户端实现（mock feature） |

### 调用方

| crate | 用途 |
|-------|------|
| `codex-cloud-tasks` | TUI/CLI 应用，使用 `HttpClient` 或 `MockClient` |

## 依赖与外部交互

### Cargo.toml 配置

```toml
[package]
name = "codex-cloud-tasks-client"

[lib]
name = "codex_cloud_tasks_client"  # 下划线命名（Rust 惯例）

[features]
default = ["online"]
online = ["dep:codex-backend-client"]
mock = []

[dependencies]
codex-backend-client = { path = "../backend-client", optional = true }
codex-git = { workspace = true }
```

### 外部依赖

| crate | 用途 |
|-------|------|
| `codex-backend-client` | HTTP 客户端底层实现（online feature） |
| `codex-git` | Git 补丁应用 |

## 风险、边界与改进建议

### 当前风险

1. **Feature 冲突**: `mock` 和 `online` 可以同时启用，可能导致代码膨胀
2. **默认 feature 依赖**: `default = ["online"]` 意味着纯测试使用方需要显式禁用
   ```toml
   codex-cloud-tasks-client = { default-features = false, features = ["mock"] }
   ```

### 边界情况

1. **无 feature 启用**: 如果两个 feature 都禁用，crate 只能使用类型定义，无可用客户端
2. **编译时错误**: 如果 `online` 启用但 `codex-backend-client` 编译失败，整个 crate 不可用

### 改进建议

1. **互斥 feature 检查**（编译时）：
   ```rust
   #[cfg(all(feature = "mock", feature = "online"))]
   compile_warning!("Both mock and online features are enabled. Consider using only one.");
   ```

2. **添加 `offline` feature alias**：
   ```toml
   [features]
   offline = ["mock"]  # 更语义化的别名
   ```

3. **文档完善**：为每个公共类型添加 rustdoc
   ```rust
   /// Unique identifier for a cloud task.
   pub use api::TaskId;
   ```

4. **重新导出优化**：考虑按功能模块组织导出
   ```rust
   pub mod types {
       pub use crate::api::{TaskId, TaskStatus, TaskSummary, ...};
   }
   pub mod client {
       pub use crate::api::CloudBackend;
       #[cfg(feature = "online")]
       pub use crate::http::HttpClient;
       #[cfg(feature = "mock")]
       pub use crate::mock::MockClient;
   }
   ```

5. **版本兼容性**：考虑添加 `serde` feature gate，使类型可选地支持序列化
   ```toml
   [features]
   serde = ["dep:serde", "chrono/serde"]
   ```
