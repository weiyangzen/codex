# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-hooks` crate 的库入口文件，负责模块组织和公共 API 导出。作为钩子系统的门面（facade），它统一暴露了遗留通知机制和新的 Claude Hooks 引擎的所有公共类型和函数。

该 crate 在 Codex 架构中承担以下角色：
- **钩子执行引擎**：管理 `AfterAgent` 和 `AfterToolUse` 两类事件的钩子分发
- **Claude Hooks 兼容层**：实现与 Claude CLI 兼容的 hooks.json 配置系统
- **遗留通知兼容**：维护向后兼容的 `notify` 配置支持

## 功能点目的

### 1. 模块组织

| 模块 | 可见性 | 用途 |
|------|--------|------|
| `engine` | `pub(crate)` | Claude Hooks 引擎核心（命令执行、配置发现、输出解析） |
| `events` | `pub` | 事件处理子模块（session_start, stop, user_prompt_submit） |
| `legacy_notify` | `pub` (模块私有) | 遗留通知机制实现 |
| `registry` | `pub` (模块私有) | 钩子注册表管理 |
| `schema` | `pub` (模块私有) | JSON Schema 定义和生成 |
| `types` | `pub` (模块私有) | 核心类型定义 |

### 2. 公共 API 导出

#### 事件类型（来自 events 模块）
- `SessionStartOutcome` / `SessionStartRequest` / `SessionStartSource`
- `StopOutcome` / `StopRequest`
- `UserPromptSubmitOutcome` / `UserPromptSubmitRequest`

#### 遗留通知（来自 legacy_notify 模块）
- `legacy_notify_json`: 生成遗留通知 JSON 负载
- `notify_hook`: 创建遗留通知钩子

#### 注册表（来自 registry 模块）
- `Hooks`: 钩子注册表主结构体
- `HooksConfig`: 钩子配置结构体
- `command_from_argv`: 命令行解析工具

#### 模式生成（来自 schema 模块）
- `write_schema_fixtures`: 写入 JSON Schema 文件

#### 核心类型（来自 types 模块）
- `Hook`: 单个钩子结构体
- `HookEvent` / `HookEventAfterAgent` / `HookEventAfterToolUse`: 事件类型
- `HookPayload`: 钩子执行时的负载数据
- `HookResponse`: 钩子执行响应
- `HookResult`: 钩子执行结果（Success/FailedContinue/FailedAbort）
- `HookToolInput` / `HookToolInputLocalShell` / `HookToolKind`: 工具输入相关类型

## 具体技术实现

### 模块结构图

```
codex-hooks (lib.rs)
│
├─> engine/ (Claude Hooks 引擎)
│   ├─> command_runner.rs    # 命令执行
│   ├─> config.rs            # 配置解析
│   ├─> discovery.rs         # 钩子发现
│   ├─> dispatcher.rs        # 钩子调度
│   ├─> mod.rs               # 引擎主模块
│   ├─> output_parser.rs     # 输出解析
│   └─> schema_loader.rs     # Schema 加载
│
├─> events/ (事件处理)
│   ├─> common.rs            # 共享工具函数
│   ├─> mod.rs               # 事件模块入口
│   ├─> session_start.rs     # SessionStart 事件
│   ├─> stop.rs              # Stop 事件
│   └─> user_prompt_submit.rs # UserPromptSubmit 事件
│
├─> legacy_notify.rs         # 遗留通知机制
├─> registry.rs              # 钩子注册表
├─> schema.rs                # JSON Schema 定义
└─> types.rs                 # 核心类型定义
```

### 导出策略

```rust
// 引擎模块：crate 内部可见
mod engine;

// 事件模块：公共可见，但子模块选择性公开
pub mod events;
mod legacy_notify;
mod registry;
mod schema;
mod types;

// 选择性重导出
pub use events::session_start::SessionStartOutcome;
pub use events::session_start::SessionStartRequest;
// ... (共 20+ 个公共导出)
```

### 设计决策

1. **模块可见性分层**
   - `engine` 为 `pub(crate)`：引擎实现细节不对外暴露
   - `events` 为 `pub`：允许外部直接访问事件子模块
   - 具体实现模块为私有：通过 `pub use` 控制 API 表面

2. **类型导出粒度**
   - 每个具体类型单独导出，而非 `pub use types::*`
   - 明确控制公共 API 的稳定性

## 关键代码路径与文件引用

### 当前文件结构

| 行号 | 内容 | 说明 |
|------|------|------|
| 1-6 | `mod` 声明 | 模块组织 |
| 8-30 | `pub use` 导出 | 公共 API 暴露 |

### 模块文件映射

| 模块名 | 文件路径 | 行数（约） |
|--------|----------|-----------|
| `engine` | `engine/mod.rs` + 6 子文件 | ~800 |
| `events` | `events/mod.rs` + 4 子文件 | ~1400 |
| `legacy_notify` | `legacy_notify.rs` | ~145 |
| `registry` | `registry.rs` | ~137 |
| `schema` | `schema.rs` | ~437 |
| `types` | `types.rs` | ~290 |

### 外部调用方

| 调用方 | 路径 | 使用内容 |
|--------|------|----------|
| `core/src/codex.rs` | `codex-rs/core/src/codex.rs` | `Hooks`, `HooksConfig`, `HookPayload`, `HookEvent`, `HookResult` |
| `core/src/codex_tests.rs` | `codex-rs/core/src/codex_tests.rs` | `Hooks`, `HooksConfig` |

## 依赖与外部交互

### Cargo.toml 依赖

```toml
[dependencies]
anyhow = { workspace = true }
chrono = { workspace = true, features = ["serde"] }
codex-config = { workspace = true }
codex-protocol = { workspace = true }
futures = { workspace = true, features = ["alloc"] }
regex = { workspace = true }
schemars = { workspace = true }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
tokio = { workspace = true, features = ["io-util", "process", "time"] }
```

### 依赖关系图

```
codex-hooks
  ├─> codex-config      # 配置层栈访问
  ├─> codex-protocol    # ThreadId, 协议类型
  ├─> chrono            # 时间序列化
  ├─> serde/serde_json  # 序列化
  ├─> schemars          # JSON Schema 生成
  ├─> tokio             # 异步进程执行
  ├─> regex             # 钩子匹配
  └─> futures           # 异步 trait
```

### 被依赖关系

```
codex-core
  └─> codex-hooks       # 钩子系统集成
```

## 风险、边界与改进建议

### 架构风险

1. **API 表面过大**
   - 当前导出 20+ 个公共类型
   - 缺乏版本控制机制（如 `v1`/`v2` 模块）
   - 建议：考虑使用 `#[doc(hidden)]` 隐藏内部类型，或引入模块版本

2. **模块耦合**
   - `events` 模块直接依赖 `engine` 内部实现
   - 测试时需要模拟整个引擎
   - 建议：引入 trait 抽象，便于单元测试

3. **可见性不一致**
   - `events` 为 `pub` 但 `legacy_notify` 等为私有
   - 新开发者可能困惑于访问模式
   - 建议：统一模块可见性策略，添加架构文档

### 维护建议

1. **文档完善**
   - 添加 crate-level 文档（`//!`）
   - 为每个公共类型添加使用示例
   - 提供架构概览图

2. **API 稳定性**
   - 标记实验性 API（`#[doc(alias = "unstable")]`）
   - 考虑使用 `semver` 自动化检查
   - 添加变更日志（CHANGELOG）

3. **测试策略**
   - 当前测试分散在各模块
   - 建议添加集成测试目录 `tests/`
   - 测试钩子端到端执行流程

### 演进方向

| 阶段 | 目标 | 行动 |
|------|------|------|
| 短期 | 稳定 API | 隐藏内部类型，完善文档 |
| 中期 | 性能优化 | 钩子并行执行，缓存配置 |
| 长期 | 功能扩展 | 支持更多事件类型，WebAssembly 钩子 |

### 代码统计

```
codex-rs/hooks/src/
├── lib.rs              ~30 行
├── types.rs           ~290 行
├── registry.rs        ~137 行
├── legacy_notify.rs   ~145 行
├── schema.rs          ~437 行
├── engine/            ~800 行
└── events/           ~1400 行
---------------------------
总计                  ~3200 行
```

该 crate 属于中等规模，但承担了关键的钩子系统职责，建议保持模块边界清晰，避免功能膨胀。
