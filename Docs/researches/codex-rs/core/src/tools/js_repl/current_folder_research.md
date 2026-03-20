# js_repl 目录研究文档

## 目录信息

- **位置**: `codex-rs/core/src/tools/js_repl/`
- **用途**: JavaScript REPL (Read-Eval-Print Loop) 工具实现，提供在 Codex 中执行 JavaScript 代码的能力
- **包含文件**:
  - `mod.rs` - Rust 主机端实现（约 1966 行）
  - `mod_tests.rs` - 单元测试（约 2000 行）
  - `kernel.js` - Node.js 内核实现（约 1782 行）
  - `meriyah.umd.min.js` - JavaScript 解析器库（Meriyah v7.0.0）

---

## 1. 场景与职责

### 1.1 核心场景

`js_repl` 是一个**实验性功能**（由 `Feature::JsRepl` 控制），为 Codex 提供以下能力：

1. **JavaScript 代码执行**: 允许 AI 在对话中执行 JavaScript 代码片段
2. **状态持久化**: 跨多次执行保持变量和函数定义（REPL 特性）
3. **工具调用**: JavaScript 代码可以调用 Codex 的其他工具（如 shell_command、view_image 等）
4. **图像输出**: 支持通过 `codex.emitImage()` 将图像作为执行结果返回

### 1.2 典型使用场景

- **数据处理**: 使用 JavaScript 进行复杂的数据转换和分析
- **原型验证**: 快速验证代码逻辑或算法
- **工具编排**: 在 JavaScript 中编排多个工具调用
- **图像生成**: 生成或处理图像并通过 emitImage 返回

### 1.3 职责边界

| 职责 | 说明 |
|------|------|
| 代码执行 | 在隔离的 Node.js VM 环境中执行 JS 代码 |
| 状态管理 | 维护跨 cell 的变量绑定（通过 `@prev` 模块导入） |
| 工具代理 | 允许 JS 代码调用 Codex 工具（通过 `codex.tool()`） |
| 沙箱安全 | 限制对敏感 Node.js 模块的访问（如 process、child_process） |
| 超时控制 | 支持可配置的执行超时（默认 30 秒） |

---

## 2. 功能点目的

### 2.1 主要功能模块

#### 2.1.1 JsReplManager（Rust 端）

```rust
pub struct JsReplManager {
    node_path: Option<PathBuf>,           // Node.js 可执行路径
    node_module_dirs: Vec<PathBuf>,       // 模块搜索路径
    tmp_dir: tempfile::TempDir,           // 临时目录（存放 kernel.js）
    kernel: Arc<Mutex<Option<KernelState>>>, // 内核进程状态
    exec_lock: Arc<tokio::sync::Semaphore>, // 执行锁（串行执行）
    exec_tool_calls: Arc<Mutex<HashMap<String, ExecToolCalls>>>, // 嵌套工具调用跟踪
}
```

**目的**: 管理 Node.js 内核进程的生命周期，处理代码执行请求，协调嵌套工具调用。

#### 2.1.2 KernelState（内核状态）

```rust
struct KernelState {
    child: Arc<Mutex<Child>>,             // Node.js 子进程
    recent_stderr: Arc<Mutex<VecDeque<String>>>, // 最近的 stderr 输出（用于调试）
    stdin: Arc<Mutex<ChildStdin>>,        // 向内核发送命令
    pending_execs: Arc<Mutex<HashMap<String, oneshot::Sender<ExecResultMessage>>>>, // 待处理的执行请求
    exec_contexts: Arc<Mutex<HashMap<String, ExecContext>>>, // 执行上下文
    top_level_exec_state: TopLevelExecState, // 顶层执行状态（用于中断处理）
    shutdown: CancellationToken,          // 关闭信号
}
```

#### 2.1.3 kernel.js（Node.js 端）

**目的**: 在 Node.js 进程中运行，提供：
- VM 隔离的代码执行环境
- ESM 模块支持（通过 `vm.SourceTextModule`）
- 状态持久化（`@prev` 模块机制）
- 工具调用代理（`codex.tool()`）
- 图像输出（`codex.emitImage()`）

### 2.2 关键功能详解

#### 2.2.1 状态持久化机制

```javascript
// kernel.js 中的核心逻辑
let previousModule = null;  // 上一个成功执行的模块
let previousBindings = [];  // 需要持久化的绑定列表

// 每个 cell 执行时：
// 1. 从 @prev 导入之前的绑定
// 2. 执行当前代码
// 3. 导出新的绑定供下一个 cell 使用
```

**绑定类型处理**:
- `const`/`let`/`class`: 词法绑定，仅当成功初始化后才持久化
- `var`/`function`: 函数作用域绑定，通过标记机制跟踪是否已初始化

#### 2.2.2 工具调用机制

```javascript
// JS 代码中调用 Codex 工具
codex.tool("shell_command", { command: "ls -la" });
```

**流程**:
1. JS 端发送 `run_tool` 消息到 Rust 端
2. Rust 端通过 `ToolRouter` 分发工具调用
3. 执行结果被序列化为 JSON 返回给 JS 端
4. **递归保护**: 禁止 JS 代码调用 `js_repl` 或 `js_repl_reset` 自身

#### 2.2.3 图像输出机制

```javascript
// 多种方式输出图像
codex.emitImage("data:image/png;base64,...");           // data URL
codex.emitImage({ bytes: buffer, mimeType: "image/png" }); // 字节数组
codex.emitImage(toolOutput);  // 从工具输出中提取图像
```

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 内核启动流程

```rust
// JsReplManager::start_kernel()
async fn start_kernel(&self, turn: Arc<TurnContext>, ...) -> Result<KernelState, String> {
    // 1. 解析 Node.js 路径并验证版本（>= 22.22.0）
    let node_path = resolve_compatible_node(self.node_path.as_deref()).await?;
    
    // 2. 将 kernel.js 和 meriyah.umd.min.js 写入临时目录
    let kernel_path = self.write_kernel_script().await?;
    
    // 3. 配置环境变量
    let mut env = create_env(&turn.shell_environment_policy, thread_id);
    env.insert("CODEX_JS_TMP_DIR".to_string(), ...);
    env.insert("CODEX_JS_REPL_NODE_MODULE_DIRS".to_string(), ...);
    
    // 4. 创建沙箱化的命令规范
    let spec = CommandSpec {
        program: node_path.to_string_lossy().to_string(),
        args: vec!["--experimental-vm-modules".to_string(), kernel_path.to_string_lossy().to_string()],
        ...
    };
    
    // 5. 通过 SandboxManager 应用沙箱策略
    let exec_env = sandbox.transform(...)?;
    
    // 6. 启动 Node.js 进程
    let mut child = cmd.spawn()?;
    
    // 7. 启动 stdout/stderr 读取任务
    tokio::spawn(Self::read_stdout(...));
    tokio::spawn(Self::read_stderr(...));
}
```

#### 3.1.2 代码执行流程

```rust
// JsReplManager::execute()
pub async fn execute(&self, session, turn, tracker, args: JsReplArgs) -> Result<JsExecResult, FunctionCallError> {
    // 1. 获取执行锁（确保串行执行）
    let _permit = self.exec_lock.clone().acquire_owned().await?;
    
    // 2. 检查/启动内核
    if kernel.is_none() { self.start_kernel(...).await?; }
    
    // 3. 创建执行请求和响应通道
    let (req_id, rx) = { ... };
    
    // 4. 发送 Exec 消息到内核
    Self::write_message(&stdin, &HostToKernel::Exec { id, code, timeout_ms }).await?;
    
    // 5. 等待执行结果（带超时）
    let response = tokio::time::timeout(Duration::from_millis(timeout_ms), rx).await?;
    
    // 6. 处理结果
    match response { ... }
}
```

#### 3.1.3 消息协议（Host ↔ Kernel）

**Host → Kernel**:
```rust
enum HostToKernel {
    Exec { id: String, code: String, timeout_ms: Option<u64> },
    RunToolResult(RunToolResult),
    EmitImageResult(EmitImageResult),
}
```

**Kernel → Host**:
```rust
enum KernelToHost {
    ExecResult { id: String, ok: bool, output: String, error: Option<String> },
    RunTool(RunToolRequest),
    EmitImage(EmitImageRequest),
}
```

### 3.2 关键数据结构

#### 3.2.1 JsReplArgs

```rust
#[derive(Clone, Debug, Deserialize)]
pub struct JsReplArgs {
    pub code: String,           // JavaScript 代码
    #[serde(default)]
    pub timeout_ms: Option<u64>, // 可选超时（毫秒）
}
```

#### 3.2.2 JsExecResult

```rust
#[derive(Clone, Debug)]
pub struct JsExecResult {
    pub output: String,  // 控制台输出（console.log 等）
    pub content_items: Vec<FunctionCallOutputContentItem>, // 图像等多媒体内容
}
```

#### 3.2.3 TopLevelExecState

```rust
#[derive(Clone, Debug, Default, PartialEq, Eq)]
enum TopLevelExecState {
    #[default]
    Idle,
    FreshKernel { turn_id: String, exec_id: Option<String> },
    ReusedKernelPending { turn_id: String, exec_id: String },
    Submitted { turn_id: String, exec_id: String },
}
```

用于跟踪执行状态，支持 turn 中断时的正确清理。

### 3.3 协议与命令

#### 3.3.1 Pragma 指令

支持在代码第一行使用特殊注释配置执行参数：

```javascript
// codex-js-repl: timeout_ms=15000
console.log("这段代码有 15 秒超时");
```

#### 3.3.2 沙箱限制

**禁止的 Node.js 内置模块**:
- `process` / `node:process`
- `child_process` / `node:child_process`
- `worker_threads` / `node:worker_threads`

**模块解析规则**:
- 支持 `node:` 前缀的内置模块（除禁止列表外）
- 支持相对路径 `./foo.js` 和绝对路径 `/path/to/foo.js`
- 支持 `file://` URL
- 支持 bare import（如 `lodash`），但限制在配置的 `node_module_dirs` 内

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/src/tools/js_repl/
├── mod.rs              # Rust 主机端实现
│   ├── JsReplHandle    # 每个 TurnContext 持有的句柄
│   ├── JsReplManager   # 内核管理器
│   ├── KernelState     # 内核进程状态
│   └── 消息协议定义
├── mod_tests.rs        # 单元测试
├── kernel.js           # Node.js 内核实现
│   ├── VM 上下文初始化
│   ├── 模块解析系统
│   ├── 代码插桩（instrumentation）
│   ├── 状态持久化逻辑
│   └── codex API（tool、emitImage）
└── meriyah.umd.min.js  # JavaScript 解析器（用于 AST 分析）
```

### 4.2 关键代码路径

#### 4.2.1 初始化路径

```
TurnContext::new()
  └── JsReplHandle::with_node_path(node_path, node_module_dirs)
      └── manager() [懒加载]
          └── JsReplManager::new()
              └── 创建临时目录
```

#### 4.2.2 执行路径

```
JsReplHandler::handle()
  └── JsReplManager::execute()
      ├── start_kernel() [如果需要]
      │   ├── resolve_compatible_node() [版本检查]
      │   ├── write_kernel_script()
      │   └── SandboxManager::transform() [沙箱化]
      ├── write_message(HostToKernel::Exec)
      └── 等待 ExecResultMessage
```

#### 4.2.3 工具调用路径（嵌套）

```
kernel.js: codex.tool()
  └── 发送 KernelToHost::RunTool
      └── read_stdout() 处理
          └── JsReplManager::run_tool_request()
              └── ToolRouter::dispatch_tool_call_with_code_mode_result()
                  └── 执行工具
              └── 发送 HostToKernel::RunToolResult
```

### 4.3 相关文件引用

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/tools/handlers/js_repl.rs` | ToolHandler 实现（JsReplHandler、JsReplResetHandler） |
| `codex-rs/core/src/tools/spec.rs` | ToolsConfig 中 js_repl_enabled 配置 |
| `codex-rs/core/src/features.rs` | Feature::JsRepl 定义 |
| `codex-rs/core/src/config/mod.rs` | js_repl_node_path、js_repl_node_module_dirs 配置 |
| `codex-rs/core/src/codex.rs` | TurnContext 中 js_repl 字段 |
| `codex-rs/core/tests/suite/js_repl.rs` | 集成测试 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

#### 5.1.1 Node.js 运行时

- **最低版本**: 22.22.0（由 `node-version.txt` 定义）
- **启动参数**: `--experimental-vm-modules`（启用 ES 模块支持）
- **环境变量**:
  - `CODEX_JS_REPL_NODE_PATH`: 指定 Node.js 路径
  - `CODEX_JS_TMP_DIR`: 临时目录路径
  - `CODEX_JS_REPL_NODE_MODULE_DIRS`: 模块搜索路径（冒号分隔）

#### 5.1.2 Meriyah 解析器

- **版本**: 7.0.0
- **用途**: 在 kernel.js 中解析 JavaScript AST，用于：
  - 提取变量绑定（`collectBindings`）
  - 代码插桩（`instrumentCurrentBindings`）
  - 跟踪 `var` 赋值（`collectFutureVarWriteReplacements`）

### 5.2 内部依赖

#### 5.2.1 工具系统

```rust
// 与工具系统的交互
crate::tools::ToolRouter              // 分发嵌套工具调用
crate::tools::context::ToolInvocation // 工具调用上下文
crate::tools::registry::ToolHandler   // Handler trait
```

#### 5.2.2 沙箱系统

```rust
crate::sandboxing::SandboxManager     // 沙箱管理
crate::sandboxing::SandboxPermissions // 权限配置
```

#### 5.2.3 会话系统

```rust
crate::codex::Session                 // 会话状态（MCP 工具、权限等）
crate::codex::TurnContext             // Turn 上下文（配置、沙箱策略等）
```

### 5.3 配置项

```rust
// Config 中的相关字段
pub struct Config {
    pub js_repl_node_path: Option<PathBuf>,           // Node.js 路径
    pub js_repl_node_module_dirs: Vec<PathBuf>,       // 模块目录
    // ...
}

// ConfigProfile 中的 TOML 配置
pub struct ConfigProfile {
    pub js_repl_node_path: Option<AbsolutePathBuf>,
    pub js_repl_node_module_dirs: Option<Vec<AbsolutePathBuf>>,
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| VM 逃逸 | Node.js VM 模块可能存在逃逸漏洞 | 使用沙箱（Seatbelt/bubblewrap）限制进程权限 |
| 无限循环 | JS 代码可能死循环 | 可配置的超时机制（默认 30s） |
| 内存耗尽 | JS 代码可能分配大量内存 | 依赖 OS 的 OOM killer 和沙箱限制 |
| 敏感模块访问 | 访问 process、child_process 等 | 显式模块黑名单 |

#### 6.1.2 稳定性风险

| 风险 | 说明 | 缓解措施 |
|------|------|----------|
| 内核崩溃 | 未捕获的异常导致 Node.js 进程退出 | 自动重启内核，恢复执行 |
| 状态丢失 | 内核重启后所有变量丢失 | 向模型报告状态重置 |
| 死锁 | 嵌套工具调用可能死锁 | 超时和取消令牌机制 |

### 6.2 边界条件

#### 6.2.1 执行限制

- **超时**: 默认 30 秒，可通过 `timeout_ms` 参数或 pragma 调整
- **串行执行**: 同一时刻只能执行一个 JS cell（通过 `exec_lock` 保证）
- **模块限制**: 仅支持 `.js` 和 `.mjs` 文件，不支持目录导入
- **静态导入限制**: 不支持顶层 `import ... from ...`，必须使用动态 `await import()`

#### 6.2.2 状态持久化边界

```javascript
// 以下情况绑定不会持久化：
// 1. 未执行的 var 声明（如空循环中的 var）
for (var x of []) {}
throw new Error("boom");
// x 不会持久化，因为循环体从未执行

// 2. 嵌套块中的 var 赋值
{ let x = 1; x = 2; }
throw new Error("boom");
// 外层 var 的赋值不会被跟踪

// 3. 复杂赋值表达式
x = (y = 1);
// y 的赋值不会被跟踪
```

### 6.3 改进建议

#### 6.3.1 功能增强

1. **并行执行**: 当前串行执行限制可能影响性能，考虑支持多个独立的 JS 上下文
2. **TypeScript 支持**: 添加对 TypeScript 的透明支持（通过 tsc 或 swc）
3. **调试支持**: 添加 `console.debug()` 和更详细的错误堆栈
4. **模块热重载**: 支持开发时自动重新加载修改的本地模块

#### 6.3.2 安全增强

1. **资源限制**: 添加 CPU 时间、内存使用量的硬限制
2. **网络隔离**: 更细粒度的网络访问控制（当前依赖沙箱）
3. **审计日志**: 记录所有 JS 执行和工具调用的详细日志

#### 6.3.3 可观测性

1. **性能指标**: 收集执行时间、内存使用、缓存命中率等指标
2. **错误分类**: 更详细的错误分类（语法错误、运行时错误、超时等）
3. **状态诊断**: 提供查询当前 REPL 状态的能力（已定义变量等）

#### 6.3.4 代码质量

1. **测试覆盖**: 增加更多边界条件的测试（当前测试已较全面）
2. **文档**: 添加用户-facing 的文档和示例
3. **错误消息**: 改进错误消息的清晰度和可操作性

### 6.4 监控要点

生产环境部署时应监控：

1. **内核重启频率**: 频繁重启可能表示稳定性问题
2. **超时率**: 高超时率可能表示需要调整默认超时或优化代码
3. **工具调用延迟**: 嵌套工具调用的响应时间
4. **内存使用**: Node.js 进程的内存增长趋势
5. **沙箱违规**: 尝试访问禁止模块的尝试

---

## 附录：关键常量

```rust
// mod.rs 中的关键常量
const JS_REPL_PRAGMA_PREFIX: &str = "// codex-js-repl:";
const JS_REPL_MIN_NODE_VERSION: &str = include_str!("../../../../node-version.txt"); // 22.22.0
const JS_REPL_STDERR_TAIL_LINE_LIMIT: usize = 20;      // stderr 尾部保留行数
const JS_REPL_STDERR_TAIL_MAX_BYTES: usize = 4_096;    // stderr 尾部最大字节
const JS_REPL_EXEC_ID_LOG_LIMIT: usize = 8;            // 日志中执行 ID 数量限制
const JS_REPL_MODEL_DIAG_STDERR_MAX_BYTES: usize = 1_024; // 模型诊断 stderr 限制
const JS_REPL_MODEL_DIAG_ERROR_MAX_BYTES: usize = 256;    // 模型诊断错误限制
const JS_REPL_TOOL_RESPONSE_TEXT_PREVIEW_MAX_BYTES: usize = 512; // 工具响应预览限制
```

---

*文档生成时间: 2026-03-21*
*基于 commit: 最新工作目录状态*
