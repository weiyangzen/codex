# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Codex rollout 模块的入口和聚合模块，位于 `codex-rs/core/src/rollout/mod.rs`。它定义了模块的公共接口，组织并导出子模块的功能，是 rollout 系统的核心组织单元。

该模块的核心职责包括：
1. **模块组织**：声明并管理 rollout 子模块（`error`, `list`, `metadata`, `policy`, `recorder`, `session_index`, `truncation`）
2. **常量定义**：定义会话存储目录名称和交互式会话来源列表
3. **公共接口导出**：通过 `pub use` 语句暴露关键类型和函数给外部模块
4. **向后兼容**：通过 `#[deprecated]` 属性维护旧 API 名称的兼容性

## 功能点目的

### 1. 目录常量定义

**目的**：统一定义会话存储的目录结构

```rust
pub const SESSIONS_SUBDIR: &str = "sessions";
pub const ARCHIVED_SESSIONS_SUBDIR: &str = "archived_sessions";
```

**使用场景**：
- `sessions`：当前活跃会话的存储目录（按日期嵌套：`YYYY/MM/DD/`）
- `archived_sessions`：已归档会话的存储目录（扁平结构）

### 2. 交互式会话来源定义

**目的**：定义哪些会话来源被视为"交互式"，用于列表过滤

```rust
pub const INTERACTIVE_SESSION_SOURCES: &[SessionSource] =
    &[SessionSource::Cli, SessionSource::VSCode];
```

**使用场景**：
- 在列出会话时，默认只显示来自 CLI 和 VSCode 的交互式会话
- 过滤掉子代理（`SubAgent`）、执行模式（`Exec`）、MCP 等来源的会话

### 3. 子模块组织

**模块可见性设计**：

| 模块 | 可见性 | 说明 |
|-----|-------|------|
| `error` | `pub(crate)` | 错误处理，仅内部使用 |
| `list` | `pub` | 列表查询，对外公开 |
| `metadata` | `pub(crate)` | 元数据提取，仅内部使用 |
| `policy` | `pub(crate)` | 持久化策略，仅内部使用 |
| `recorder` | `pub` | 记录器，对外公开 |
| `session_index` | `pub(crate)` | 会话索引，仅内部使用 |
| `truncation` | `pub(crate)` | 截断处理，仅内部使用 |

### 4. 公共接口导出

**从协议 crate 重新导出**：
```rust
pub use codex_protocol::protocol::SessionMeta;
```

**内部模块导出**：
```rust
pub(crate) use error::map_session_init_error;
pub use list::find_archived_thread_path_by_id_str;
pub use list::find_thread_path_by_id_str;
pub use list::rollout_date_parts;
pub use recorder::RolloutRecorder;
pub use recorder::RolloutRecorderParams;
pub use session_index::append_thread_name;
pub use session_index::find_thread_name_by_id;
pub use session_index::find_thread_path_by_name_str;
```

### 5. 向后兼容

**目的**：在重命名 API 时保持旧代码兼容

```rust
#[deprecated(note = "use find_thread_path_by_id_str")]
pub use list::find_thread_path_by_id_str as find_conversation_path_by_id_str;

#[allow(dead_code)]
#[deprecated(note = "use ThreadItem")]
pub type ConversationItem = ThreadItem;

#[allow(dead_code)]
#[deprecated(note = "use ThreadsPage")]
pub type ConversationsPage = ThreadsPage;
```

**迁移路径**：
- `ConversationItem` → `ThreadItem`
- `ConversationsPage` → `ThreadsPage`
- `find_conversation_path_by_id_str` → `find_thread_path_by_id_str`

## 具体技术实现

### 模块声明模式

```rust
pub(crate) mod error;
pub mod list;
pub(crate) mod metadata;
pub(crate) mod policy;
pub mod recorder;
pub(crate) mod session_index;
pub(crate) mod truncation;
```

**可见性规则**：
- `pub`：完全公开，可被外部 crate 使用
- `pub(crate)`：仅当前 crate 内部可见
- 默认（无修饰符）：仅当前模块及其子模块可见

### 条件编译测试模块

```rust
#[cfg(test)]
pub mod tests;
```

**说明**：
- 仅在测试编译时包含 `tests` 模块
- `pub` 可见性允许其他模块的测试访问测试辅助函数

### 类型别名向后兼容

```rust
#[allow(dead_code)]
#[deprecated(note = "use ThreadItem")]
pub type ConversationItem = ThreadItem;
```

**技术细节**：
- `#[allow(dead_code)]`：抑制未使用警告，因为类型别名可能仅用于向后兼容
- `#[deprecated]`：编译时产生弃用警告，引导用户迁移

## 关键代码路径与文件引用

### 子模块文件映射

| 模块名 | 文件路径 | 功能 |
|-------|---------|------|
| `error` | `error.rs` | I/O 错误映射为用户友好提示 |
| `list` | `list.rs` | 会话列表、分页、查找 |
| `metadata` | `metadata.rs` | 元数据提取、状态回填 |
| `policy` | `policy.rs` | 持久化策略、事件过滤 |
| `recorder` | `recorder.rs` | Rollout 记录器、文件写入 |
| `session_index` | `session_index.rs` | 会话名称索引 |
| `truncation` | `truncation.rs` | 基于用户回合的截断 |
| `tests` | `tests.rs` | 模块级集成测试 |

### 外部依赖

| 依赖 | 来源 | 用途 |
|-----|------|------|
| `SessionSource` | `codex_protocol::protocol` | 会话来源枚举 |
| `SessionMeta` | `codex_protocol::protocol` | 会话元数据 |

### 调用方

通过 `pub use` 导出的符号被以下模块使用：

| 符号 | 调用方 |
|-----|-------|
| `RolloutRecorder` | `codex.rs`, `thread_manager.rs`, `agent/control.rs` |
| `RolloutRecorderParams` | `codex.rs`, `thread_manager.rs` |
| `find_thread_path_by_id_str` | `codex.rs`, `recorder.rs` |
| `find_archived_thread_path_by_id_str` | `recorder.rs` |
| `SessionMeta` | 多个模块 |
| `map_session_init_error` | `codex.rs`, `thread_manager.rs` |

## 依赖与外部交互

### 模块依赖图

```
rollout/mod.rs
    ├── error.rs (pub(crate))
    ├── list.rs (pub)
    │   └── 依赖: protocol, state, file_search, state_db
    ├── metadata.rs (pub(crate))
    │   └── 依赖: protocol, state, recorder, list
    ├── policy.rs (pub(crate))
    │   └── 依赖: protocol
    ├── recorder.rs (pub)
    │   └── 依赖: list, metadata, policy, state_db
    ├── session_index.rs (pub(crate))
    │   └── 依赖: protocol
    ├── truncation.rs (pub(crate))
    │   └── 依赖: protocol, event_mapping
    └── tests.rs (pub, cfg(test))
```

### 与 protocol crate 的关系

```rust
use codex_protocol::protocol::SessionSource;
pub use codex_protocol::protocol::SessionMeta;
```

**说明**：
- `SessionSource` 用于定义交互式会话来源常量
- `SessionMeta` 被重新导出，方便外部模块直接使用

## 风险、边界与改进建议

### 当前风险

1. **模块可见性不一致**：`list` 和 `recorder` 是 `pub`，但它们的内部实现细节可能泄露
2. **向后兼容负担**：弃用类型别名需要长期维护
3. **循环依赖风险**：`recorder` 依赖 `metadata`，`metadata` 依赖 `recorder` 的 `load_rollout_items`

### 边界情况

1. **模块初始化顺序**：Rust 模块初始化顺序由编译器决定，但通常按声明顺序
2. **条件编译**：`tests` 模块仅在测试时可用，生产代码不能依赖

### 改进建议

1. **模块可见性审查**：
   ```rust
   // 建议：考虑将 list 的内部实现细节设为 pub(crate)
   pub mod list {
       pub use self::public_fn::*;
       pub(crate) use self::internal::*;
   }
   ```

2. **API 版本管理**：
   ```rust
   // 建议：引入版本化模块
   pub mod v1 {
       pub use super::list::find_thread_path_by_id_str;
       #[deprecated]
       pub use super::list::find_thread_path_by_id_str as find_conversation_path_by_id_str;
   }
   pub mod v2 {
       pub use super::list::find_thread_path_by_id_str;
   }
   ```

3. **文档完善**：
   ```rust
   //! Rollout module: persistence and discovery of session rollout files.
   //!
   //! ## Module Overview
   //! - `list`: Thread listing and pagination
   //! - `recorder`: Rollout file recording
   //! - ...
   ```

4. **移除已弃用 API**：
   - 在主要版本升级时移除 `ConversationItem`、`ConversationsPage` 等弃用别名
   - 提供迁移脚本或自动化工具

5. **模块化测试**：
   ```rust
   // 建议：将测试拆分到各子模块
   #[cfg(test)]
   mod tests {
       mod list_tests;
       mod recorder_tests;
       // ...
   }
   ```

### 模块组织最佳实践

当前模块组织基本符合 Rust 惯例，但可以进一步优化：

1. **按功能分组**：
   ```rust
   // 读操作
   pub mod read {
       pub use list::get_threads;
       pub use list::find_thread_path_by_id_str;
   }
   
   // 写操作
   pub mod write {
       pub use recorder::RolloutRecorder;
   }
   ```

2. **内部实现隐藏**：
   ```rust
   // 使用 #[doc(hidden)] 隐藏内部实现
   #[doc(hidden)]
   pub(crate) mod internal {
       // 内部辅助函数
   }
   ```
