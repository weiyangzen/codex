# registry.rs 深度研究文档

## 场景与职责

`registry.rs` 是 Codex 工具系统的核心注册表，负责工具处理器的注册、查找和调用分发。主要职责包括：

1. **工具处理器注册**：支持静态和动态工具处理器的注册
2. **工具调用分发**：根据工具名称和命名空间路由到正确的处理器
3. **命名空间支持**：处理 MCP (Model Context Protocol) 工具的命名空间隔离
4. **执行生命周期管理**：管理工具调用的完整生命周期，包括钩子调用和遥测
5. **并行控制**：通过 tool gate 控制变异操作的串行化

该模块是工具系统的"中央交换机"，所有工具调用最终都通过 `ToolRegistry::dispatch_any()` 执行。

## 功能点目的

### 1. 工具处理器 Trait (ToolHandler)

```rust
#[async_trait]
pub trait ToolHandler: Send + Sync {
    type Output: ToolOutput + 'static;

    fn kind(&self) -> ToolKind;
    fn matches_kind(&self, payload: &ToolPayload) -> bool;
    async fn is_mutating(&self, _invocation: &ToolInvocation) -> bool;
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError>;
}
```

- **kind()**: 返回工具类型（Function 或 Mcp）
- **matches_kind()**: 验证 payload 类型与工具类型匹配
- **is_mutating()**: 判断工具是否可能修改环境（用于 gate 控制）
- **handle()**: 实际执行工具逻辑

### 2. 通用工具结果 (AnyToolResult)

```rust
pub(crate) struct AnyToolResult {
    pub(crate) call_id: String,
    pub(crate) payload: ToolPayload,
    pub(crate) result: Box<dyn ToolOutput>,
}
```

通过类型擦除统一不同工具处理器的返回类型。

### 3. 工具注册表 (ToolRegistry)

```rust
pub struct ToolRegistry {
    handlers: HashMap<String, Arc<dyn AnyToolHandler>>,
}
```

使用 `tool_handler_key(name, namespace)` 作为键，支持命名空间隔离。

### 4. 配置工具规格 (ConfiguredToolSpec)

```rust
pub struct ConfiguredToolSpec {
    pub spec: ToolSpec,
    pub supports_parallel_tool_calls: bool,
}
```

包装工具规格，附加并行执行能力标志。

### 5. 注册表构建器 (ToolRegistryBuilder)

```rust
pub struct ToolRegistryBuilder {
    handlers: HashMap<String, Arc<dyn AnyToolHandler>>,
    specs: Vec<ConfiguredToolSpec>,
}
```

支持构建时注册处理器和规格。

### 6. AfterToolUse 钩子

```rust
async fn dispatch_after_tool_use_hook(...) -> Option<FunctionCallError>
```

工具执行后调用钩子，支持：
- 成功继续 (`HookResult::Success`)
- 失败继续 (`HookResult::FailedContinue`)
- 失败中止 (`HookResult::FailedAbort`)

## 具体技术实现

### 核心分发流程

```
┌─────────────────────────────────────────────────────────────────┐
│                 ToolRegistry::dispatch_any()                     │
├─────────────────────────────────────────────────────────────────┤
│ 1. 提取工具信息                                                  │
│    ├─ tool_name, tool_namespace, call_id                        │
│    ├─ otel (遥测)                                               │
│    └─ mcp_server, mcp_server_origin (如果是 MCP 工具)          │
├─────────────────────────────────────────────────────────────────┤
│ 2. 更新会话状态                                                  │
│    └─ active_turn.tool_calls += 1                               │
├─────────────────────────────────────────────────────────────────┤
│ 3. 查找处理器                                                    │
│    ├─ handler(name, namespace)                                  │
│    └─ 未找到 → 返回 RespondToModel 错误                         │
├─────────────────────────────────────────────────────────────────┤
│ 4. 验证 payload 类型                                             │
│    └─ 不匹配 → 返回 Fatal 错误                                  │
├─────────────────────────────────────────────────────────────────┤
│ 5. 判断是否为变异操作                                            │
│    └─ is_mutating()                                             │
├─────────────────────────────────────────────────────────────────┤
│ 6. 执行工具（带遥测包装）                                        │
│    ├─ 如果是变异操作，等待 tool_call_gate                       │
│    └─ handler.handle_any()                                      │
├─────────────────────────────────────────────────────────────────┤
│ 7. 记录遥测指标                                                  │
│    └─ emit_metric_for_tool_read()                               │
├─────────────────────────────────────────────────────────────────┤
│ 8. 调用 AfterToolUse 钩子                                        │
│    └─ dispatch_after_tool_use_hook()                            │
├─────────────────────────────────────────────────────────────────┤
│ 9. 返回结果                                                      │
└─────────────────────────────────────────────────────────────────┘
```

### 关键代码路径

#### 处理器查找

```rust
// registry.rs:207-228
let handler = match self.handler(tool_name.as_ref(), tool_namespace.as_deref()) {
    Some(handler) => handler,
    None => {
        let message = unsupported_tool_call_message(...);
        otel.tool_result_with_tags(..., /*success*/ false, &message, ...);
        return Err(FunctionCallError::RespondToModel(message));
    }
};

fn handler(&self, name: &str, namespace: Option<&str>) -> Option<Arc<dyn AnyToolHandler>> {
    self.handlers
        .get(&tool_handler_key(name, namespace))
        .map(Arc::clone)
}
```

#### 命名空间键生成

```rust
// registry.rs:124-130
pub(crate) fn tool_handler_key(tool_name: &str, namespace: Option<&str>) -> String {
    if let Some(namespace) = namespace {
        format!("{namespace}:{tool_name}")
    } else {
        tool_name.to_string()
    }
}
```

示例：
- 普通工具：`"shell"`
- MCP 工具：`"mcp__codex_apps__gmail:gmail_get_recent_emails"`

#### 变异操作控制

```rust
// registry.rs:246-267
let is_mutating = handler.is_mutating(&invocation).await;
// ...
if is_mutating {
    tracing::trace!("waiting for tool gate");
    invocation_for_tool.turn.tool_call_gate.wait_ready().await;
    tracing::trace!("tool gate released");
}
```

#### 遥测记录

```rust
// registry.rs:251-281
let result = otel
    .log_tool_result_with_tags(
        tool_name.as_ref(),
        &call_id_owned,
        log_payload.as_ref(),
        &metric_tags,
        mcp_server_ref,
        mcp_server_origin_ref,
        || { /* 实际执行闭包 */ }
    )
    .await;
```

#### 钩子分发

```rust
// registry.rs:475-537
async fn dispatch_after_tool_use_hook(...) -> Option<FunctionCallError> {
    let hook_outcomes = session
        .hooks()
        .dispatch(HookPayload { ... })
        .await;

    for hook_outcome in hook_outcomes {
        match hook_outcome.result {
            HookResult::Success => {}
            HookResult::FailedContinue(error) => { /* 记录警告 */ }
            HookResult::FailedAbort(error) => { /* 返回致命错误 */ }
        }
    }
    None
}
```

### 数据结构详解

#### ToolInvocation

```rust
pub struct ToolInvocation {
    pub session: Arc<Session>,           // 会话状态
    pub turn: Arc<TurnContext>,          // 回合上下文
    pub tracker: SharedTurnDiffTracker,  // 差异跟踪
    pub call_id: String,                 // 调用 ID
    pub tool_name: String,               // 工具名称
    pub tool_namespace: Option<String>,  // 命名空间（MCP 工具）
    pub payload: ToolPayload,            // 调用参数
}
```

#### ToolPayload 枚举

```rust
pub enum ToolPayload {
    Function { arguments: String },
    ToolSearch { arguments: SearchToolCallParams },
    Custom { input: String },
    LocalShell { params: ShellToolCallParams },
    Mcp { server: String, tool: String, raw_arguments: String },
}
```

#### AfterToolUseHookDispatch

```rust
struct AfterToolUseHookDispatch<'a> {
    invocation: &'a ToolInvocation,
    output_preview: String,      // 输出预览（用于遥测）
    success: bool,               // 是否成功
    executed: bool,              // 是否已执行
    duration: Duration,          // 执行时长
    mutating: bool,              // 是否为变异操作
}
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::context::*` | ToolInvocation、ToolPayload、ToolOutput |
| `crate::tools::spec::ToolsConfig` | 工具配置 |
| `crate::client_common::tools::ToolSpec` | 工具规格 |
| `crate::function_tool::FunctionCallError` | 错误类型 |
| `crate::memories::usage::emit_metric_for_tool_read` | 遥测指标 |
| `crate::sandbox_tags::sandbox_tag` | 沙箱标签 |
| `codex_hooks::*` | 钩子系统 |

### 外部协议依赖

| 协议类型 | 用途 |
|----------|------|
| `ResponseInputItem` | 响应项类型 |
| `SandboxPolicy` | 沙箱策略 |

### 调用关系

```
ToolRegistry::dispatch_any()
    ├── handler()                                    [查找处理器]
    ├── handler.matches_kind()                       [验证类型]
    ├── handler.is_mutating()                        [检查变异]
    ├── tool_call_gate.wait_ready()                  [等待 gate]
    ├── handler.handle_any()                         [执行工具]
    │   └── ToolHandler::handle()                    [具体实现]
    ├── emit_metric_for_tool_read()                  [记录指标]
    └── dispatch_after_tool_use_hook()               [调用钩子]
        └── session.hooks().dispatch()               [钩子系统]
```

## 风险、边界与改进建议

### 已知风险

1. **处理器覆盖风险**
   - `register_handler` 允许覆盖已存在的处理器
   - 会记录警告日志，但行为可能不可预期
   ```rust
   if self.handlers.insert(name.clone(), handler.clone()).is_some() {
       warn!("overwriting handler for tool {name}");
   }
   ```

2. **命名空间冲突**
   - 命名空间键使用简单字符串拼接：`"{namespace}:{tool_name}"`
   - 如果工具名包含 `:`，可能导致解析歧义

3. **钩子失败影响**
   - `FailedAbort` 钩子会终止整个操作
   - 恶意或错误配置的钩子可能导致服务不可用

4. **Gate 死锁**
   - 如果 `tool_call_gate` 实现有缺陷，可能导致永久等待
   - 建议：添加超时机制

### 边界情况

1. **空命名空间 vs None**
   - `Some("")` 和 `None` 被视为不同
   - 可能导致查找失败

2. **MCP 服务器断开**
   - 如果 MCP 服务器在调用期间断开，`mcp_server_origin` 可能为 None
   - 遥测数据中会体现为无 origin

3. **并发工具计数**
   ```rust
   turn_state.tool_calls = turn_state.tool_calls.saturating_add(1);
   ```
   - 使用 `saturating_add` 防止溢出

### 改进建议

1. **命名空间安全**
   ```rust
   // 建议：对特殊字符进行转义
   fn tool_handler_key(tool_name: &str, namespace: Option<&str>) -> String {
       let escaped_name = tool_name.replace(':', "\\:");
       match namespace {
           Some(ns) => format!("{}:{}", ns.replace(':', "\\:"), escaped_name),
           None => escaped_name,
       }
   }
   ```

2. **处理器版本控制**
   - 添加版本号支持，允许安全地更新处理器
   - 支持蓝绿部署

3. **钩子超时**
   ```rust
   // 建议：为钩子调用添加超时
   tokio::time::timeout(Duration::from_secs(30), hooks.dispatch(...)).await
   ```

4. **批量注册**
   - 当前 `TODO(jif)` 注释提到动态工具注册
   - 建议实现批量原子注册，避免中间状态

5. **执行统计**
   - 记录每个处理器的执行次数、成功率
   - 支持基于统计的自动降级

6. **工具依赖图**
   - 支持声明工具间的依赖关系
   - 自动处理依赖顺序

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/core/src/tools/registry_tests.rs` | 单元测试 |
| `codex-rs/core/src/tools/context.rs` | ToolInvocation、ToolPayload 定义 |
| `codex-rs/core/src/tools/router.rs` | 调用 registry 的路由层 |
| `codex-rs/core/src/tools/handlers/*.rs` | 具体工具处理器实现 |
| `codex-rs/core/src/tools/spec.rs` | ToolsConfig 定义 |
| `codex-rs/codex-hooks/src/lib.rs` | 钩子系统接口 |
