# registry.rs 研究文档

## 场景与职责

`registry.rs` 是 codex-hooks crate 的钩子注册表模块，负责管理两类钩子系统的生命周期：

1. **遗留通知钩子（Legacy Notify Hooks）**：基于 `notify` 配置的传统钩子
2. **Claude Hooks 引擎**：基于 `hooks.json` 配置的现代钩子系统

该模块是钩子系统的**中央协调器**，负责：
- 钩子配置的初始化和验证
- 事件到钩子的路由分发
- 钩子执行的生命周期管理（预览、执行、结果收集）

## 功能点目的

### 1. 钩子配置 (`HooksConfig`)

```rust
pub struct HooksConfig {
    pub legacy_notify_argv: Option<Vec<String>>,  // 遗留通知命令行
    pub feature_enabled: bool,                     // Claude Hooks 功能开关
    pub config_layer_stack: Option<ConfigLayerStack>, // 配置层栈
    pub shell_program: Option<String>,            // 钩子执行 shell
    pub shell_args: Vec<String>,                  // shell 参数
}
```

**设计意图**：
- 统一两类钩子的配置入口
- 支持可选配置（`Option`）以实现渐进式启用
- 与 `codex-config` 集成，支持多层配置覆盖

### 2. 钩子注册表 (`Hooks`)

```rust
pub struct Hooks {
    after_agent: Vec<Hook>,        // AfterAgent 事件钩子
    after_tool_use: Vec<Hook>,     // AfterToolUse 事件钩子（预留）
    engine: ClaudeHooksEngine,     // Claude Hooks 引擎
}
```

**核心能力**：
- 事件路由：`hooks_for_event` 根据事件类型选择钩子列表
- 执行分发：`dispatch` 顺序执行钩子，支持中断（abort）语义
- Claude 事件支持：`SessionStart`、`UserPromptSubmit`、`Stop` 的预览和执行

### 3. 命令行解析 (`command_from_argv`)

将字符串向量解析为 `tokio::process::Command`：
- 首元素为程序路径
- 剩余元素为参数
- 空程序名返回 `None`

## 具体技术实现

### 初始化流程

```
Hooks::new(config)
  │
  ├─> 初始化 after_agent 钩子
  │     ├─> 检查 legacy_notify_argv
  │     ├─> 过滤空配置
  │     └─> 调用 notify_hook(argv) 创建 Hook
  │
  ├─> 初始化 ClaudeHooksEngine
  │     ├─> 检查 feature_enabled
  │     ├─> 加载生成的 schemas
  │     └─> discover_handlers(config_layer_stack)
  │
  └─> 返回 Hooks 实例
```

### 事件分发流程

```
dispatch(hook_payload)
  │
  ├─> hooks_for_event(&hook_payload.hook_event)
  │     ├─> AfterAgent { .. } => &self.after_agent
  │     └─> AfterToolUse { .. } => &self.after_tool_use
  │
  ├─> 遍历钩子顺序执行
  │     ├─> hook.execute(payload).await
  │     ├─> 检查 should_abort_operation()
  │     └─> 若需中断，提前返回
  │
  └─> 返回 Vec<HookResponse>
```

### Claude 事件处理

| 方法 | 阶段 | 说明 |
|------|------|------|
| `preview_session_start` | 预览 | 返回将要执行的钩子摘要 |
| `run_session_start` | 执行 | 异步执行 SessionStart 钩子 |
| `preview_user_prompt_submit` | 预览 | 返回将要执行的钩子摘要 |
| `run_user_prompt_submit` | 执行 | 异步执行 UserPromptSubmit 钩子 |
| `preview_stop` | 预览 | 返回将要执行的钩子摘要 |
| `run_stop` | 执行 | 异步执行 Stop 钩子 |

**预览 vs 执行**：
- 预览：同步返回 `HookRunSummary` 列表，用于 UI 展示
- 执行：异步返回 `Outcome`，包含详细结果和决策

## 关键代码路径与文件引用

### 当前文件关键代码

| 行号 | 代码 | 说明 |
|------|------|------|
| 17-24 | `HooksConfig` | 配置结构体定义 |
| 26-31 | `Hooks` | 注册表结构体 |
| 39-60 | `Hooks::new` | 初始化逻辑 |
| 66-71 | `hooks_for_event` | 事件路由 |
| 73-86 | `dispatch` | 钩子分发执行 |
| 88-126 | Claude 事件方法 | 预览和执行 API |
| 129-137 | `command_from_argv` | 命令行解析 |

### 跨文件引用

| 引用目标 | 路径 | 用途 |
|----------|------|------|
| `ClaudeHooksEngine` | `engine/mod.rs` | Claude Hooks 引擎 |
| `CommandShell` | `engine/mod.rs` | shell 配置 |
| `SessionStartOutcome/Request` | `events/session_start.rs` | SessionStart 事件 |
| `StopOutcome/Request` | `events/stop.rs` | Stop 事件 |
| `UserPromptSubmitOutcome/Request` | `events/user_prompt_submit.rs` | UserPromptSubmit 事件 |
| `Hook/HookEvent/HookPayload/HookResponse` | `types.rs` | 核心类型 |
| `notify_hook` | `legacy_notify.rs` | 创建遗留通知钩子 |

### 调用方

| 调用方 | 路径 | 调用内容 |
|--------|------|----------|
| `Codex::new` | `core/src/codex.rs:~1761` | `Hooks::new(HooksConfig { ... })` |
| 测试代码 | `core/src/codex_tests.rs` | `Hooks::new` 用于测试 |

### 配置来源链

```
config.toml / CLI args
  │
  ├─> core/src/config.rs: Config.notify -> Vec<String>
  │
  ├─> core/src/codex.rs: HooksConfig.legacy_notify_argv
  │
  └─> registry.rs: Hooks::new() -> notify_hook()
```

## 依赖与外部交互

### 内部依赖

```
registry.rs
  ├─> engine::ClaudeHooksEngine
  ├─> engine::CommandShell
  ├─> events::session_start::*
  ├─> events::stop::*
  ├─> events::user_prompt_submit::*
  ├─> types::Hook/HookEvent/HookPayload/HookResponse
  └─> legacy_notify::notify_hook (间接通过 crate::notify_hook)
```

### 外部依赖

| Crate | 类型 | 用途 |
|-------|------|------|
| `codex_config` | 外部 | `ConfigLayerStack` 配置层栈 |
| `tokio` | 外部 | `tokio::process::Command` 异步进程 |
| `codex_protocol` | 外部 | `protocol::HookRunSummary` 协议类型 |

### 与 core crate 的集成

```
core/src/codex.rs
  │
  ├─> 读取配置
  │     ├─> config.notify -> legacy_notify_argv
  │     ├─> config.features.enabled(Feature::CodexHooks) -> feature_enabled
  │     ├─> config.config_layer_stack.clone()
  │     └─> hook_shell_argv 解析 -> shell_program/shell_args
  │
  └─> Hooks::new(HooksConfig { ... })
```

## 风险、边界与改进建议

### 已知风险

1. **两类钩子系统的隔离性**
   - `after_agent` 钩子和 Claude Hooks 引擎完全独立
   - 可能产生重复执行或冲突
   - 建议：文档明确说明互斥性，或提供迁移工具

2. **`after_tool_use` 未实现**
   - 结构体中存在该字段，但始终为空 Vec
   - 可能误导开发者认为功能已就绪
   - 建议：添加 `#[doc(hidden)]` 或 TODO 注释

3. **钩子执行顺序**
   - 遗留钩子先于 Claude Hooks 执行（在 `after_agent` 中）
   - 但两者属于不同事件系统，实际不会交错
   - 建议：明确文档说明执行顺序保证

### 边界情况

| 场景 | 行为 |
|------|------|
| `legacy_notify_argv` 为空 | 不创建遗留钩子 |
| `legacy_notify_argv[0]` 为空字符串 | 过滤掉，不创建钩子 |
| `feature_enabled = false` | ClaudeHooksEngine 为空（无处理器） |
| `config_layer_stack = None` | 无法发现 `hooks.json` 配置 |
| 钩子执行返回 `FailedAbort` | 中断后续钩子执行 |

### 性能考虑

1. **克隆开销**
   - `Hooks` 实现 `Clone`，但包含 `Vec<Hook>` 和 `ClaudeHooksEngine`
   - 每次 clone 会复制所有钩子配置
   - 建议：考虑使用 `Arc` 共享配置

2. **分发效率**
   - `dispatch` 顺序执行，无并行化
   - 每个钩子等待前一个完成
   - 建议：评估是否需要并行执行（注意顺序依赖）

### 改进建议

1. **API 改进**
   ```rust
   // 当前：直接返回 Vec<HookResponse>
   pub async fn dispatch(&self, hook_payload: HookPayload) -> Vec<HookResponse>
   
   // 建议：添加元信息
   pub struct DispatchResult {
       pub responses: Vec<HookResponse>,
       pub aborted: bool,           // 是否被中断
       pub aborted_at: Option<usize>, // 中断位置
   }
   ```

2. **配置验证**
   - 在 `HooksConfig` 添加验证方法
   - 提前发现配置错误（如无效 shell 路径）
   - 在 `Hooks::new` 返回 `Result` 而非 panic

3. **可观测性**
   - 添加 `tracing` 日志记录钩子执行
   - 暴露钩子执行指标（延迟、成功率）
   - 支持钩子执行调试模式（打印命令和输出）

4. **测试改进**
   - 当前测试分散在 `codex_tests.rs`
   - 建议添加 `registry` 模块的单元测试
   - 模拟 `ClaudeHooksEngine` 进行隔离测试

### 代码质量

| 指标 | 现状 | 建议 |
|------|------|------|
| 行数 | ~137 行 | 适中 |
| 方法数 | 11 个 | 适中 |
| 圈复杂度 | 低 | 良好 |
| 文档覆盖率 | 低 | 添加 rustdoc |

### 长期演进

1. **统一钩子系统**
   - 将遗留通知迁移到 Claude Hooks 框架
   - 提供自动迁移工具
   - 最终移除 `legacy_notify_argv` 支持

2. **动态钩子注册**
   - 支持运行时添加/移除钩子
   - 热重载 `hooks.json` 配置
   - 支持插件化钩子（WebAssembly）
