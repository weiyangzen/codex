# mod.rs (engine) 深度研究文档

## 场景与职责

`mod.rs` 是 Codex Hooks 引擎的**核心模块入口与协调器**，负责定义引擎的公共接口、核心数据结构，并协调各子模块（discovery、dispatcher、command_runner 等）的协作。它是 Hooks 系统的"门面"，承担着以下关键职责：

1. **模块组织**：声明并导出 engine 子模块
2. **核心数据结构定义**：`CommandShell`、`ConfiguredHandler`、`ClaudeHooksEngine`
3. **引擎生命周期管理**：创建、初始化、执行
4. **事件处理接口**：为三种事件类型（SessionStart、UserPromptSubmit、Stop）提供统一的预览和执行接口

该模块实现了**外观模式**（Facade Pattern），将复杂的子系统（discovery + dispatcher + command_runner）封装为简洁的 API。

## 功能点目的

### 1. 模块组织

```rust
pub(crate) mod command_runner;
pub(crate) mod config;
pub(crate) mod discovery;
pub(crate) mod dispatcher;
pub(crate) mod output_parser;
pub(crate) mod schema_loader;
```

**模块职责划分**：
| 模块 | 职责 |
|-----|------|
| `command_runner` | 子进程执行 |
| `config` | 配置结构定义 |
| `discovery` | 配置发现与加载 |
| `dispatcher` | Handler 调度与并发执行 |
| `output_parser` | 输出解析 |
| `schema_loader` | JSON Schema 加载 |

### 2. Shell 执行环境 (`CommandShell`)

```rust
#[derive(Debug, Clone)]
pub(crate) struct CommandShell {
    pub program: String,
    pub args: Vec<String>,
}
```

**设计意图**：
- 封装 Shell 执行环境配置
- 支持自定义 Shell（如使用 zsh、fish 替代默认 sh）
- `program` 为空时使用系统默认 Shell

### 3. 运行时 Handler 配置 (`ConfiguredHandler`)

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ConfiguredHandler {
    pub event_name: HookEventName,
    pub matcher: Option<String>,
    pub command: String,
    pub timeout_sec: u64,
    pub status_message: Option<String>,
    pub source_path: PathBuf,
    pub display_order: i64,
}
```

**字段说明**：
| 字段 | 类型 | 说明 |
|-----|------|------|
| `event_name` | `HookEventName` | 关联的事件类型 |
| `matcher` | `Option<String>` | 正则匹配条件（仅 SessionStart） |
| `command` | `String` | 要执行的命令 |
| `timeout_sec` | `u64` | 超时秒数（默认 600） |
| `status_message` | `Option<String>` | UI 状态提示 |
| `source_path` | `PathBuf` | 配置来源文件路径 |
| `display_order` | `i64` | 执行顺序（全局递增） |

**ID 生成**：
```rust
pub fn run_id(&self) -> String {
    format!(
        "{}:{}:{}",
        self.event_name_label(),
        self.display_order,
        self.source_path.display()
    )
}
```

### 4. Hooks 引擎 (`ClaudeHooksEngine`)

```rust
#[derive(Clone)]
pub(crate) struct ClaudeHooksEngine {
    handlers: Vec<ConfiguredHandler>,
    warnings: Vec<String>,
    shell: CommandShell,
}
```

**设计模式**：
- **不可变性**：引擎创建后配置不可变（`Clone` 支持快照）
- **资源预加载**：构造函数中完成所有配置发现和 Schema 加载
- **警告收集**：非致命错误不影响引擎创建

**构造函数逻辑**：
```rust
pub(crate) fn new(
    enabled: bool,
    config_layer_stack: Option<&ConfigLayerStack>,
    shell: CommandShell,
) -> Self {
    if !enabled {
        return Self { handlers: Vec::new(), warnings: Vec::new(), shell };
    }

    let _ = schema_loader::generated_hook_schemas();  // 预加载 Schema
    let discovered = discovery::discover_handlers(config_layer_stack);
    Self {
        handlers: discovered.handlers,
        warnings: discovered.warnings,
        shell,
    }
}
```

### 5. 事件处理接口

**预览接口**（同步，用于 UI 展示）：
```rust
pub(crate) fn preview_session_start(&self, request: &SessionStartRequest) -> Vec<HookRunSummary>
pub(crate) fn preview_user_prompt_submit(&self, request: &UserPromptSubmitRequest) -> Vec<HookRunSummary>
pub(crate) fn preview_stop(&self, request: &StopRequest) -> Vec<HookRunSummary>
```

**执行接口**（异步，实际执行）：
```rust
pub(crate) async fn run_session_start(&self, request: SessionStartRequest, turn_id: Option<String>) -> SessionStartOutcome
pub(crate) async fn run_user_prompt_submit(&self, request: UserPromptSubmitRequest) -> UserPromptSubmitOutcome
pub(crate) async fn run_stop(&self, request: StopRequest) -> StopOutcome
```

**设计意图**：
- **预览/执行分离**：UI 可先展示将要执行的 Hook，再实际执行
- **异步执行**：避免阻塞主线程
- **类型安全**：每个事件类型有独立的 Request/Outcome 类型

## 具体技术实现

### 引擎创建流程

```
ClaudeHooksEngine::new(enabled, config_layer_stack, shell)
    ↓
enabled == false?
    ├── Yes → 返回空引擎
    └── No → 继续
        ↓
schema_loader::generated_hook_schemas()  // 预加载 Schema
    ↓
discovery::discover_handlers(config_layer_stack)  // 发现配置
    ↓
返回 ClaudeHooksEngine { handlers, warnings, shell }
```

### 事件名称标签映射

```rust
fn event_name_label(&self) -> &'static str {
    match self.event_name {
        HookEventName::SessionStart => "session-start",
        HookEventName::UserPromptSubmit => "user-prompt-submit",
        HookEventName::Stop => "stop",
    }
}
```

**用途**：
- 生成人类可读的 Handler ID
- 日志记录和调试

### 预览 vs 执行的区别

| 特性 | 预览 (preview) | 执行 (run) |
|-----|---------------|-----------|
| 同步性 | 同步 | 异步 |
| 副作用 | 无 | 执行命令 |
| 返回类型 | `Vec<HookRunSummary>` | `XxxOutcome` |
| 用途 | UI 展示 | 实际处理 |
| 实现 | 调用 `dispatcher::select_handlers` + `running_summary` | 调用 `events::xxx::run` |

## 关键代码路径与文件引用

### 当前文件结构

```
codex-rs/hooks/src/engine/mod.rs
├── CommandShell (struct) - Shell 环境
├── ConfiguredHandler (struct) - Handler 配置
│   ├── run_id() - ID 生成
│   └── event_name_label() - 标签映射
├── ClaudeHooksEngine (struct) - 引擎核心
│   ├── new() - 构造函数
│   ├── warnings() - 获取警告
│   ├── preview_*() - 预览接口
│   └── run_*() - 执行接口
└── 子模块声明
```

### 调用方（上游）

```
codex-rs/hooks/src/registry.rs (推测)
└── Hooks::new() / Hooks::execute()
    └── ClaudeHooksEngine::new() / run_*()

或

codex-rs/tui/src/... (推测)
└── 在会话生命周期中调用引擎
```

### 被调用方（下游）

```
codex-rs/hooks/src/engine/schema_loader.rs
└── generated_hook_schemas()  // 预加载

codex-rs/hooks/src/engine/discovery.rs
└── discover_handlers()  // 配置发现

codex-rs/hooks/src/events/session_start.rs
codex-rs/hooks/src/events/user_prompt_submit.rs
codex-rs/hooks/src/events/stop.rs
└── preview() / run()  // 事件处理实现
```

### 依赖类型

```
codex-rs/config/src/state.rs
├── ConfigLayerStack

codex-rs/protocol/src/protocol.rs
├── HookRunSummary
├── HookCompletedEvent
└── HookEventName

codex-rs/hooks/src/events/*.rs
├── SessionStartRequest / SessionStartOutcome
├── UserPromptSubmitRequest / UserPromptSubmitOutcome
└── StopRequest / StopOutcome
```

## 依赖与外部交互

### 外部依赖

| Crate | 用途 |
|-------|------|
| `std::path::PathBuf` | 路径处理 |
| `codex_config` | 配置层管理 |
| `codex_protocol` | 协议类型 |

### 输入依赖

| 来源 | 类型 | 用途 |
|-----|------|------|
| 调用方 | `bool` (enabled) | 是否启用 Hooks |
| 调用方 | `ConfigLayerStack` | 配置层栈 |
| 调用方 | `CommandShell` | Shell 环境 |
| 事件触发 | `SessionStartRequest` 等 | 事件上下文 |

### 输出消费

| 消费者 | 消费内容 |
|-------|---------|
| UI 层 | `Vec<HookRunSummary>` (预览结果) |
| 会话管理 | `SessionStartOutcome` 等 (执行结果) |
| 日志系统 | `warnings` (配置警告) |

## 风险、边界与改进建议

### 已知风险

1. **Schema 预加载副作用**
   ```rust
   let _ = schema_loader::generated_hook_schemas();
   ```
   - 使用 `OnceLock` 确保只加载一次
   - 如果加载失败会 panic（在 `schema_loader` 中处理）
   - **评估**：当前实现合理，失败时应阻止引擎创建

2. **引擎克隆成本**
   - `ClaudeHooksEngine` 实现了 `Clone`
   - 包含 `Vec<ConfiguredHandler>` 和 `CommandShell`
   - 频繁克隆可能产生内存开销
   - **建议**：考虑使用 `Arc<Vec<ConfiguredHandler>>` 共享配置

3. **警告信息暴露**
   - `warnings()` 返回 `&[String]`
   - 调用方需要主动检查并展示警告
   - 如果忽略，用户可能不知道配置问题

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| enabled = false | 返回空引擎，不执行任何 Hook | ✅ 合理 |
| config_layer_stack = None | discovery 返回空结果 | ✅ 合理 |
| 所有配置无效 | warnings 包含所有错误，handlers 为空 | ✅ 合理 |
| 重复调用 run_* | 每次都会重新执行所有 Handler | ✅ 符合预期 |
| 并发调用 run_* | 需要 &self，允许多线程并发 | ⚠️ 需确保底层安全 |

### 改进建议

1. **性能优化**
   ```rust
   #[derive(Clone)]
   pub(crate) struct ClaudeHooksEngine {
       handlers: Arc<Vec<ConfiguredHandler>>,  // 共享配置
       warnings: Arc<Vec<String>>,
       shell: CommandShell,
   }
   ```

2. **健康检查接口**
   ```rust
   pub struct EngineHealth {
       pub is_healthy: bool,
       pub warnings: Vec<String>,
       pub handler_count: usize,
   }
   
   impl ClaudeHooksEngine {
       pub fn health_check(&self) -> EngineHealth { ... }
   }
   ```

3. **执行统计**
   ```rust
   pub struct ExecutionStats {
       pub total_executions: AtomicU64,
       pub total_duration_ms: AtomicU64,
       pub failure_count: AtomicU64,
   }
   ```

4. **动态重载**
   ```rust
   impl ClaudeHooksEngine {
       pub async fn reload(&mut self, config_layer_stack: Option<&ConfigLayerStack>) {
           let discovered = discovery::discover_handlers(config_layer_stack);
           self.handlers = discovered.handlers;
           self.warnings = discovered.warnings;
       }
   }
   ```

### 测试覆盖

当前 `mod.rs` 中没有内联测试，测试分散在：
- `discovery.rs` - 配置发现测试
- `dispatcher.rs` - 调度逻辑测试
- `session_start.rs` / `user_prompt_submit.rs` / `stop.rs` - 事件处理测试

建议添加：
- 引擎生命周期测试（创建、执行、克隆）
- 边界条件测试（空配置、全部失败配置）
- 性能基准测试（大量 Handler 的创建和执行）

### 相关文件

- **配置发现**: `codex-rs/hooks/src/engine/discovery.rs`
- **命令执行**: `codex-rs/hooks/src/engine/command_runner.rs`
- **调度器**: `codex-rs/hooks/src/engine/dispatcher.rs`
- **事件处理**: `codex-rs/hooks/src/events/*.rs`
- **Schema 加载**: `codex-rs/hooks/src/engine/schema_loader.rs`
- **协议定义**: `codex-rs/protocol/src/protocol.rs`
