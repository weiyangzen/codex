# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 `codex-rs/hooks/src/events/` 模块的入口文件，负责声明和组织三个核心事件处理子模块：

- `session_start` - 会话启动事件处理
- `stop` - 停止事件处理  
- `user_prompt_submit` - 用户提示提交事件处理

同时暴露 `common` 模块作为内部共享工具（`pub(crate)` 可见性）。

## 功能点目的

该模块采用 Rust 标准模块组织模式：

1. **模块声明**：使用 `mod` 关键字声明子模块，对应同目录下的 `.rs` 文件
2. **可见性控制**：
   - `mod common` - 仅 crate 内部可见，作为共享工具
   - `pub mod session_start` - 公开，供外部调用 SessionStart 相关类型和函数
   - `pub mod stop` - 公开，供外部调用 Stop 相关类型和函数
   - `pub mod user_prompt_submit` - 公开，供外部调用 UserPromptSubmit 相关类型和函数

## 具体技术实现

### 模块结构

```rust
// events/mod.rs
mod common;                           // 内部共享工具
pub mod session_start;                // 公开：会话启动事件
pub mod stop;                         // 公开：停止事件
pub mod user_prompt_submit;           // 公开：用户提示提交事件
```

### 外部访问路径

```rust
// 外部代码通过以下路径访问
use codex_hooks::events::session_start::{SessionStartRequest, SessionStartOutcome, SessionStartSource};
use codex_hooks::events::stop::{StopRequest, StopOutcome};
use codex_hooks::events::user_prompt_submit::{UserPromptSubmitRequest, UserPromptSubmitOutcome};
```

## 关键代码路径与文件引用

### 模块文件映射

| 模块声明 | 文件路径 | 说明 |
|----------|----------|------|
| `mod common` | `events/common.rs` | 共享工具函数 |
| `pub mod session_start` | `events/session_start.rs` | 会话启动事件处理 |
| `pub mod stop` | `events/stop.rs` | 停止事件处理 |
| `pub mod user_prompt_submit` | `events/user_prompt_submit.rs` | 用户提示提交事件处理 |

### 被引用关系

| 引用者 | 文件路径 | 说明 |
|--------|----------|------|
| `lib.rs` | `hooks/src/lib.rs` | `pub mod events` 引入整个事件模块 |
| `engine/mod.rs` | `engine/mod.rs` | 通过 `crate::events` 使用事件类型 |

## 依赖与外部交互

### 模块层级图

```
codex-hooks crate
├── lib.rs
│   └── pub mod events
│       └── events/mod.rs (本文件)
│           ├── mod common
│           │   └── common.rs
│           ├── pub mod session_start
│           │   └── session_start.rs
│           ├── pub mod stop
│           │   └── stop.rs
│           └── pub mod user_prompt_submit
│               └── user_prompt_submit.rs
```

### 与 engine 模块的交互

```
engine/mod.rs (ClaudeHooksEngine)
    │
    ├── preview_session_start() ───────► events::session_start::preview()
    ├── run_session_start() ───────────► events::session_start::run()
    ├── preview_user_prompt_submit() ──► events::user_prompt_submit::preview()
    ├── run_user_prompt_submit() ──────► events::user_prompt_submit::run()
    ├── preview_stop() ────────────────► events::stop::preview()
    └── run_stop() ────────────────────► events::stop::run()
```

## 风险、边界与改进建议

### 当前设计特点

1. **简洁性**：仅 4 行代码完成模块组织，符合 Rust 惯例
2. **清晰边界**：`common` 内部可见，三个事件模块公开
3. **对称结构**：三个事件模块遵循相同的 `preview`/`run` 模式

### 潜在改进

1. **文档注释**
   - 建议添加模块级文档注释说明各事件触发时机：
   ```rust
   //! Event handling for Claude Hooks protocol
   //! 
   //! - SessionStart: Triggered when a new session begins
   //! - UserPromptSubmit: Triggered when user submits a prompt
   //! - Stop: Triggered after assistant response generation
   ```

2. **未来扩展**
   - 如需添加新事件类型（如 `ToolUse`），只需在此添加一行 `pub mod`
   - 考虑使用 `#[cfg(feature = ...)]` 条件编译支持可选事件

3. **可见性审查**
   - 当前 `common` 为 `pub(crate)`，确保外部 crate 无法直接访问
   - 如果未来有自定义 hook 需求，可能需要重新评估可见性
