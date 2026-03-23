# 研究文档：codex-rs/core/src/tools/js_repl/mod.rs

## 1. 场景与职责

### 1.1 功能定位

`js_repl` 模块是 Codex CLI 的 JavaScript REPL（Read-Eval-Print Loop）执行引擎，提供了一个持久化的 Node.js 运行时环境，允许 AI 模型在对话中直接执行 JavaScript 代码。这是一个实验性功能（`Feature::JsRepl`），需要用户显式启用。

### 1.2 核心职责

- **持久化 JS 执行环境**：维护一个长期运行的 Node.js 进程（称为 "kernel"），跨多次执行保持变量状态
- **代码执行与状态管理**：执行用户提供的 JavaScript 代码，管理执行上下文和变量绑定
- **工具调用桥接**：允许 JavaScript 代码通过 `codex.tool()` API 调用 Codex 的其他工具
- **图像输出支持**：通过 `codex.emitImage()` API 支持从 JS 环境输出图像到对话
- **沙箱安全**：在受控的沙箱环境中运行 Node 进程，限制敏感系统访问

### 1.3 使用场景

- 交互式网站调试
- 数据处理和转换脚本
- 需要状态保持的多步骤计算
- 调用其他 Codex 工具的自动化脚本
- 图像生成和处理流程

---

## 2. 功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 实现位置 |
|--------|------|----------|
| `JsReplManager` | 管理 kernel 生命周期、执行调度和资源清理 | `mod.rs` |
| `JsReplHandle` | 每个 Turn 的 handle，延迟初始化 manager | `mod.rs` |
| `kernel.js` | Node.js 端的代码执行引擎，处理模块加载和状态持久化 | `kernel.js` |
| `codex.tool()` | JS 端调用 Codex 工具的 API | `kernel.js` |
| `codex.emitImage()` | JS 端输出图像到对话的 API | `kernel.js` |
| `JsReplHandler` | 处理 `js_repl` 工具调用的处理器 | `handlers/js_repl.rs` |
| `JsReplResetHandler` | 处理 `js_repl_reset` 工具调用的处理器 | `handlers/js_repl.rs` |

### 2.2 状态持久化机制

JS REPL 的核心价值在于状态持久化：

1. **Cell 模型**：每次执行被视为一个 "cell"，类似 Jupyter Notebook
2. **变量绑定传递**：通过 `@prev` 伪模块将上一次的变量绑定传递到下一次执行
3. **失败恢复**：即使某个 cell 抛出异常，已初始化的变量仍然会被保留
4. **绑定类型处理**：
   - `const`/`let`/`class`：词法绑定，通过模块命名空间读取
   - `var`/`function`：提升绑定，需要显式标记才能持久化

### 2.3 安全限制

- **禁止的模块**：`process`, `child_process`, `worker_threads` 等敏感 Node 内置模块
- **沙箱执行**：通过 `SandboxManager` 应用文件系统和网络沙箱策略
- **静态导入限制**：禁止顶层静态 import，只允许动态 `await import()`

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 JsReplManager（Rust 端）

```rust
pub struct JsReplManager {
    node_path: Option<PathBuf>,           // Node 可执行文件路径
    node_module_dirs: Vec<PathBuf>,       // 额外的 node_modules 搜索路径
    tmp_dir: tempfile::TempDir,           // 临时目录（存放 kernel.js）
    kernel: Arc<Mutex<Option<KernelState>>>, // Kernel 进程状态
    exec_lock: Arc<tokio::sync::Semaphore>,  // 执行互斥锁（串行执行）
    exec_tool_calls: Arc<Mutex<HashMap<String, ExecToolCalls>>>, // 工具调用跟踪
}
```

#### 3.1.2 KernelState（Rust 端）

```rust
struct KernelState {
    child: Arc<Mutex<Child>>,             // Node 子进程
    recent_stderr: Arc<Mutex<VecDeque<String>>>, // 最近的 stderr 输出（用于调试）
    stdin: Arc<Mutex<ChildStdin>>,        // 向 kernel 发送命令的管道
    pending_execs: Arc<Mutex<HashMap<String, oneshot::Sender<ExecResultMessage>>>>, // 等待中的执行
    exec_contexts: Arc<Mutex<HashMap<String, ExecContext>>>, // 执行上下文
    top_level_exec_state: TopLevelExecState, // 顶层执行状态（用于中断处理）
    shutdown: CancellationToken,          // 关闭信号
}
```

#### 3.1.3 Host-Kernel 通信协议

**Host → Kernel 消息** (`HostToKernel`):
```rust
enum HostToKernel {
    Exec { id: String, code: String, timeout_ms: Option<u64> },
    RunToolResult(RunToolResult),
    EmitImageResult(EmitImageResult),
}
```

**Kernel → Host 消息** (`KernelToHost`):
```rust
enum KernelToHost {
    ExecResult { id: String, ok: bool, output: String, error: Option<String> },
    RunTool(RunToolRequest),      // 工具调用请求
    EmitImage(EmitImageRequest),  // 图像输出请求
}
```

通信使用 **JSON Lines** 格式通过 stdin/stdout 进行。

### 3.2 关键流程

#### 3.2.1 Kernel 启动流程

1. **版本检查**：通过 `resolve_compatible_node()` 查找并验证 Node 版本（要求 >= v22.22.0）
2. **脚本写入**：将 `kernel.js` 和 `meriyah.umd.min.js`（JS 解析器）写入临时目录
3. **进程启动**：使用 `tokio::process::Command` 启动 Node，带上 `--experimental-vm-modules` 标志
4. **沙箱配置**：通过 `SandboxManager` 应用执行环境沙箱
5. **IO 管道建立**：
   - `stdout`：读取 kernel 输出的 JSON 消息
   - `stdin`：向 kernel 发送执行命令
   - `stderr`：收集错误输出用于调试

#### 3.2.2 代码执行流程

```
JsReplHandler::handle()
  └── manager.execute()
      ├── 获取 exec_lock（确保串行执行）
      ├── 检查/启动 kernel
      ├── 生成 exec_id，注册执行上下文
      ├── 发送 HostToKernel::Exec 消息
      ├── 等待 KernelToHost::ExecResult 响应
      │   └── read_stdout() 后台任务处理 kernel 输出
      │       ├── 处理 ExecResult
      │       ├── 处理 RunTool（调用其他 Codex 工具）
      │       └── 处理 EmitImage（输出图像）
      └── 返回 JsExecResult
```

#### 3.2.3 工具调用流程（JS → Codex）

1. JS 代码调用 `codex.tool("tool_name", args)`
2. Kernel 发送 `KernelToHost::RunTool` 消息到 Host
3. Host 的 `read_stdout()` 接收消息，启动异步任务
4. 异步任务通过 `ToolRouter` 分发工具调用
5. 工具执行完成后，发送 `HostToKernel::RunToolResult` 回 Kernel
6. Kernel 将结果返回给 JS 的 Promise

#### 3.2.4 图像输出流程

1. JS 代码调用 `codex.emitImage(imageData)`
2. 支持多种输入格式：
   - Data URL 字符串
   - `{ bytes: Uint8Array, mimeType: string }`
   - 工具输出对象（如 `view_image` 的结果）
3. Kernel 发送 `KernelToHost::EmitImage` 消息
4. Host 验证并创建 `FunctionCallOutputContentItem::InputImage`
5. 图像被添加到执行结果中，最终显示在对话中

### 3.3 Kernel.js 实现细节

#### 3.3.1 模块系统

Kernel.js 使用 Node.js 的 `vm` 模块创建隔离的执行上下文：

```javascript
const context = vm.createContext({});
// 填充全局对象
globalThis = context;
context.console = console;
context.fetch = fetch;
// ... 其他全局 API
```

每个 cell 被编译为一个 ES Module：

```javascript
const module = new SourceTextModule(source, {
  context,
  identifier: cellIdentifier,
  importModuleDynamically: /* 动态导入处理 */,
});
```

#### 3.3.2 状态持久化实现

通过 `@prev` 伪模块实现变量传递：

```javascript
// 第一次执行
const answer = 42;
export { answer };

// 第二次执行（自动生成的 prelude）
import * as __prev from "@prev";
const answer = __prev.answer;
// 用户代码
console.log(answer);
```

#### 3.3.3 绑定收集与标记

使用 `meriyah` 解析器分析 AST：

1. **绑定收集**：`collectBindings()` 扫描 `const`/`let`/`var`/`function`/`class` 声明
2. **代码插桩**：在变量声明后插入标记调用，记录哪些绑定已初始化
3. **失败恢复**：异常时根据标记决定保留哪些绑定

```javascript
// 原始代码
const x = 1, y = 2;

// 插桩后
const x = 1, y = 2, __codex_internal_0 = (__markCommitted("x", "y"), undefined);
```

#### 3.3.4 模块解析策略

```javascript
// 支持的导入形式
await import("lodash");           // npm 包（从配置的 node_modules）
await import("./local.js");       // 相对路径（仅 .js/.mjs）
await import("node:fs");          // Node 内置模块（部分允许）

// 禁止的导入
import "./foo";                   // 顶层静态导入
await import("node:process");     // 敏感模块
await import("/absolute/path");   // 绝对路径
```

### 3.4 配置与常量

```rust
// 版本要求
const JS_REPL_MIN_NODE_VERSION: &str = include_str!("../../../../node-version.txt"); // v22.22.0

// 调试输出限制
const JS_REPL_STDERR_TAIL_LINE_LIMIT: usize = 20;
const JS_REPL_STDERR_TAIL_MAX_BYTES: usize = 4_096;
const JS_REPL_MODEL_DIAG_STDERR_MAX_BYTES: usize = 1_024;

// 执行超时默认 30 秒
const DEFAULT_TIMEOUT_MS: u64 = 30_000;

// Pragma 前缀（用于传递执行参数）
pub(crate) const JS_REPL_PRAGMA_PREFIX: &str = "// codex-js-repl:";
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/src/tools/js_repl/
├── mod.rs              # 主模块：JsReplManager、协议定义、Node 版本检查
├── mod_tests.rs        # 单元测试（~2000 行）
├── kernel.js           # Node.js 执行引擎（~1780 行）
└── meriyah.umd.min.js  # JS 解析器（第三方依赖）

codex-rs/core/src/tools/handlers/
├── js_repl.rs          # ToolHandler 实现（JsReplHandler、JsReplResetHandler）
└── js_repl_tests.rs    # 处理器单元测试

codex-rs/core/src/tools/
├── spec.rs             # 工具定义（create_js_repl_tool、create_js_repl_reset_tool）
├── router.rs           # 工具路由（含 js_repl_tools_only 模式检查）
└── mod.rs              # 模块导出

codex-rs/core/tests/suite/
└── js_repl.rs          # 集成测试（~712 行）
```

### 4.2 关键代码路径

#### 4.2.1 执行入口

```rust
// codex-rs/core/src/tools/handlers/js_repl.rs:110
#[async_trait]
impl ToolHandler for JsReplHandler {
    async fn handle(&self, invocation: ToolInvocation) -> Result<Self::Output, FunctionCallError> {
        // 1. 检查 Feature::JsRepl 是否启用
        // 2. 解析参数（支持 function 和 custom payload）
        // 3. 获取 manager 并执行
        // 4. 发射工具事件（begin/end）
    }
}
```

#### 4.2.2 Kernel 启动

```rust
// codex-rs/core/src/tools/js_repl/mod.rs:1000
async fn start_kernel(&self, ...) -> Result<KernelState, String> {
    // 1. 解析 Node 路径并检查版本
    // 2. 写入 kernel.js 和 meriyah 到临时目录
    // 3. 配置环境变量（CODEX_JS_TMP_DIR、CODEX_JS_REPL_NODE_MODULE_DIRS）
    // 4. 创建 CommandSpec 并应用沙箱转换
    // 5. 启动进程并建立 IO 管道
    // 6. 启动 stdout/stderr 读取任务
}
```

#### 4.2.3 执行核心

```rust
// codex-rs/core/src/tools/js_repl/mod.rs:834
pub async fn execute(&self, session, turn, tracker, args) -> Result<JsExecResult, FunctionCallError> {
    // 1. 获取执行锁
    // 2. 检查/启动 kernel
    // 3. 注册执行上下文和工具调用跟踪
    // 4. 发送 Exec 消息到 kernel
    // 5. 等待响应（带超时）
    // 6. 处理结果或超时重置
}
```

#### 4.2.4 工具调用处理

```rust
// codex-rs/core/src/tools/js_repl/mod.rs:1534
async fn run_tool_request(exec: ExecContext, req: RunToolRequest) -> RunToolResult {
    // 1. 检查递归调用（js_repl 不能调用自身）
    // 2. 创建 ToolRouter 并分发调用
    // 3. 序列化结果并返回
}
```

#### 4.2.5 Kernel 执行循环

```javascript
// codex-rs/core/src/tools/js_repl/kernel.js:1542
async function handleExec(message) {
    // 1. 构建模块源码（含 prelude 和插桩）
    // 2. 创建 SourceTextModule
    // 3. 链接模块（处理 @prev 导入）
    // 4. 执行模块
    // 5. 等待后台任务完成
    // 6. 收集输出并发送结果
}
```

### 4.3 配置集成

```rust
// codex-rs/core/src/tools/spec.rs:2037
fn create_js_repl_tool() -> ToolSpec {
    ToolSpec::Freeform(FreeformTool {
        name: "js_repl".to_string(),
        description: "Runs JavaScript in a persistent Node kernel with top-level await...",
        format: FreeformToolFormat { /* ... */ },
    })
}

// codex-rs/core/src/tools/spec.rs:2713
if config.js_repl_enabled {
    push_tool_spec(&mut builder, create_js_repl_tool(), ...);
    push_tool_spec(&mut builder, create_js_repl_reset_tool(), ...);
    builder.register_handler("js_repl", js_repl_handler);
    builder.register_handler("js_repl_reset", js_repl_reset_handler);
}
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::sandboxing` | 沙箱配置和进程隔离 |
| `crate::exec` | 执行策略和超时管理 |
| `crate::features` | Feature 标志检查（`Feature::JsRepl`） |
| `crate::tools::router` | 工具路由和分发 |
| `crate::tools::context` | 工具调用上下文和 payload |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |
| `codex_protocol` | 协议类型（ContentItem、ImageDetail 等） |

### 5.2 外部依赖

| 依赖 | 用途 |
|------|------|
| `tokio::process` | 异步进程管理 |
| `tokio::sync::{Mutex, Semaphore, oneshot, Notify}` | 并发同步原语 |
| `serde_json` | JSON 序列化/反序列化 |
| `uuid` | 生成执行 ID |
| `tempfile` | 临时目录管理 |
| `which` | 查找 Node 可执行文件 |

### 5.3 Node.js 依赖

| 模块 | 用途 |
|------|------|
| `node:vm` | VM 上下文和模块执行 |
| `node:module` | 模块解析 |
| `meriyah` | JavaScript AST 解析（ESM 格式） |

### 5.4 环境变量

| 变量 | 说明 |
|------|------|
| `CODEX_JS_REPL_NODE_PATH` | 指定 Node 可执行文件路径 |
| `CODEX_JS_REPL_NODE_MODULE_DIRS` | 额外的 node_modules 搜索路径 |
| `CODEX_JS_TMP_DIR` | Kernel 临时目录（由 Host 设置） |
| `CODEX_THREAD_ID` | 线程 ID（用于内部绑定名盐值） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

1. **VM 逃逸风险**：虽然使用 Node.js VM 模块，但 `vm` 模块并非完全隔离，存在潜在的逃逸风险
2. **动态导入绕过**：虽然禁止了敏感模块的静态导入，但动态 `import()` 仍可能被滥用
3. **原型污染**：多个 cell 共享同一个 `context` 对象，可能存在原型链污染风险

#### 6.1.2 稳定性风险

1. **Kernel 崩溃**：未捕获的异常或 Promise 拒绝会导致 kernel 进程退出，需要重新启动
2. **无限循环**：虽然设置了超时，但某些同步死循环可能无法被及时中断
3. **内存泄漏**：长期运行的 kernel 可能积累内存，目前没有自动重启机制

#### 6.1.3 兼容性风险

1. **Node 版本依赖**：要求 Node >= v22.22.0，旧版本会被拒绝
2. **平台差异**：macOS 和 Linux 的测试覆盖不同（`can_run_js_repl_runtime_tests()`）
3. **模块解析限制**：只支持特定的模块导入形式，某些 npm 包可能无法正常工作

### 6.2 边界情况

1. **执行超时**：默认 30 秒超时，超时后会强制重置 kernel
2. **并发限制**：通过 `exec_lock` 确保串行执行，不支持真正的并行 cell 执行
3. **变量作用域**：`var` 和 `function` 的提升行为有特殊处理，某些边缘情况可能不符合预期
4. **图像大小限制**：输出图像通过 data URL 传输，大图像可能导致内存问题

### 6.3 改进建议

#### 6.3.1 安全性增强

1. **更严格的沙箱**：考虑使用 `worker_threads` 或外部进程进行真正的隔离
2. **资源限制**：添加 CPU 时间限制、内存限制等 cgroup/ulimit 控制
3. **审计日志**：记录所有 `codex.tool()` 调用和文件系统访问

#### 6.3.2 性能优化

1. **并行执行**：考虑支持多个独立的 kernel 实例，实现真正的并行 cell 执行
2. **智能重启**：根据内存使用情况自动重启 kernel
3. **模块缓存优化**：改进 npm 包的加载和缓存策略

#### 6.3.3 功能扩展

1. **TypeScript 支持**：添加对 TypeScript 的转译支持
2. **调试功能**：添加 `console.log` 的实时流式输出
3. **断点支持**：允许在 cell 中设置断点进行调试
4. **包管理**：支持在 REPL 中动态安装 npm 包

#### 6.3.4 可观测性

1. **性能指标**：收集执行时间、内存使用等指标
2. **错误分析**：改进错误堆栈，提供更有用的调试信息
3. **状态检查**：添加 `js_repl_status` 工具检查 kernel 健康状态

#### 6.3.5 代码质量

1. **测试覆盖**：增加更多边界情况的单元测试
2. **文档完善**：补充更多使用示例和最佳实践
3. **错误消息**：改进用户-facing 的错误消息，提供更清晰的指导

---

## 7. 附录

### 7.1 测试覆盖

- **单元测试**：`mod_tests.rs`（~2000 行），覆盖版本解析、stderr 处理、工具调用等
- **处理器测试**：`js_repl_tests.rs`，覆盖参数解析和事件发射
- **集成测试**：`tests/suite/js_repl.rs`（~712 行），覆盖端到端场景

### 7.2 相关文档

- `AGENTS.md`：项目级代理开发指南
- `codex-rs/app-server/README.md`：API 开发最佳实践
- `codex-rs/core/config.schema.json`：配置模式定义

### 7.3 版本历史

- 当前 Node 最低版本：v22.22.0
- 功能状态：Experimental（实验性）
- 默认启用：否
