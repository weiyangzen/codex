# codex-rs/core/src/tools/js_repl/mod_tests.rs 研究文档

## 1. 场景与职责

### 1.1 文件定位

`mod_tests.rs` 是 `codex-rs/core/src/tools/js_repl/mod.rs` 的配套测试模块，通过 `#[path = "mod_tests.rs"]` 声明在 `mod.rs` 末尾条件编译引入。该文件包含 **60+ 个测试用例**，是 Codex 项目中 JavaScript REPL (Read-Eval-Print Loop) 功能的核心测试集合。

### 1.2 核心职责

该测试文件负责验证以下关键场景：

| 场景类别 | 具体职责 |
|---------|---------|
| **单元测试** | 验证独立函数（如版本解析、UTF-8截断、stderr处理、工具调用响应摘要等）|
| **运行时集成测试** | 验证与 Node.js 内核的完整交互流程（仅在 macOS 上运行）|
| **并发与生命周期** | 验证 `exec_tool_calls` 映射的并发访问、reset 操作的锁行为、任务取消机制 |
| **图像处理** | 验证 `emitImage` API 的各种输入格式、验证、错误处理 |
| **模块系统** | 验证本地文件导入、npm 包解析、`node_modules` 搜索路径 |
| **工具调用** | 验证从 JS REPL 内部调用 Codex 工具（如 shell_command）、动态工具响应 |
| **中断与恢复** | 验证 turn 中断、内核崩溃恢复、超时处理 |

### 1.3 测试执行条件

```rust
async fn can_run_js_repl_runtime_tests() -> bool {
    // 这些白盒运行时测试在 macOS 上是必需的。
    // Linux 依赖于 codex-linux-sandbox arg0 分发路径，在集成测试中验证。
    cfg!(target_os = "macos")
}
```

运行时测试仅在 **macOS** 上执行，Linux 平台通过 `codex-linux-sandbox` 的集成测试覆盖。

---

## 2. 功能点目的

### 2.1 NodeVersion 解析 (`node_version_parses_v_prefix_and_suffix`)

验证 `NodeVersion::parse` 能够正确处理带 `v` 前缀和预发布后缀的版本字符串（如 `"v25.1.0-nightly.2024"`）。

**关键代码路径：**
- `mod.rs:1854-1878` - `NodeVersion::parse` 实现
- `mod.rs:1935-1941` - `resolve_compatible_node` 调用版本检查

### 2.2 UTF-8 安全截断 (`truncate_utf8_prefix_by_bytes`)

验证 `truncate_utf8_prefix_by_bytes` 函数在多字节字符边界处正确截断字符串，避免产生无效的 UTF-8 序列。

**测试用例覆盖：**
- 空字符串、单字节字符（ASCII）
- 多字节字符（如 `é` - 2字节，`🙂` - 4字节）
- 截断位置恰好在字符边界和非边界处

### 2.3 stderr 尾部追踪 (`stderr_tail_applies_line_and_byte_limits`)

验证内核 stderr 的环形缓冲区实现：
- 行数限制（`JS_REPL_STDERR_TAIL_LINE_LIMIT = 20`）
- 每行字节限制（`JS_REPL_STDERR_TAIL_LINE_MAX_BYTES = 512`）
- 总字节限制（`JS_REPL_STDERR_TAIL_MAX_BYTES = 4,096`）

**关键常量：**
```rust
const JS_REPL_STDERR_TAIL_LINE_LIMIT: usize = 20;
const JS_REPL_STDERR_TAIL_LINE_MAX_BYTES: usize = 512;
const JS_REPL_STDERR_TAIL_MAX_BYTES: usize = 4_096;
```

### 2.4 内核故障诊断 (`model_kernel_failure_details_are_structured_and_truncated`)

验证当内核崩溃时，向模型返回的诊断信息：
- 包含结构化 JSON（reason、kernel_pid、kernel_status、kernel_stderr_tail、stream_error）
- 正确截断过长的 stderr 和错误信息
- 符合大小限制（`JS_REPL_MODEL_DIAG_STDERR_MAX_BYTES = 1,024`，`JS_REPL_MODEL_DIAG_ERROR_MAX_BYTES = 256`）

### 2.5 执行工具调用映射管理

#### `wait_for_exec_tool_calls_map_drains_inflight_calls_without_hanging`
验证 `ExecToolCalls` 映射的并发操作不会死锁，包括：
- `begin_exec_tool_call` - 开始工具调用
- `wait_for_exec_tool_calls_map` - 等待完成
- `finish_exec_tool_call` - 标记完成
- `clear_exec_tool_calls_map` - 清理

#### `reset_waits_for_exec_lock_before_clearing_exec_tool_calls`
验证 `reset()` 操作会等待执行锁释放后才清理工具调用上下文，避免竞态条件。

### 2.6 工具调用响应摘要 (`summarize_tool_call_response_for_*`)

验证 `JsReplManager::summarize_tool_call_response` 对不同响应类型的正确摘要：
- `FunctionCallOutput` - 函数调用输出
- `CustomToolCallOutput` - 自定义工具输出
- 多模态内容（文本 + 图像）
- 错误响应

### 2.7 图像内容项处理

#### `emitted_image_content_item_*` 系列测试
验证图像内容项的生成逻辑：
- 丢弃不支持的 `detail` 值（如 `ImageDetail::Low`）
- 当启用 `ImageDetailOriginal` 特性时允许 `original` detail
- 未启用特性时丢弃 `original` detail

#### `validate_emitted_image_url_*` 系列测试
验证图像 URL 验证：
- 接受大小写不敏感的 `data:` scheme
- 拒绝非 data URL（如 `https://`）

### 2.8 运行时执行测试（macOS  only）

#### 超时处理 (`js_repl_timeout_does_not_deadlock`, `js_repl_timeout_kills_kernel_process`)
验证：
- 超时不会导致死锁
- 超时后内核进程被正确终止
- 返回正确的错误消息（"js_repl execution timed out; kernel reset, rerun your request"）

#### 中断处理 (`interrupt_turn_exec_*` 系列)
验证 `interrupt_turn_exec` 方法：
- 正确识别并中断匹配的 turn
- 区分不同状态（`FreshKernel`、`Submitted`、`ReusedKernelPending`）
- 清理内核状态和工具调用映射

#### 内核崩溃恢复 (`js_repl_forced_kernel_exit_recovers_on_next_exec`)
验证强制终止内核后，下一次执行能正确恢复。

#### 未捕获异常处理 (`js_repl_uncaught_exception_returns_exec_error_and_recovers`)
验证：
- 未捕获的异常返回正确的错误消息
- 内核被重置
- 后续执行能正常恢复

### 2.9 工具调用等待 (`js_repl_waits_for_unawaited_tool_calls_before_completion`)

验证即使 JavaScript 代码没有 `await` 工具调用，REPL 仍会等待其完成：
```javascript
void codex.tool("shell_command", { command: "sleep 0.35; ..." });
console.log("cell-complete");
```
输出包含 `"cell-complete"` 且文件写入完成。

### 2.10 持久化工具辅助函数 (`js_repl_persisted_tool_helpers_work_across_cells`)

验证跨 cell 保存的工具函数能正常工作：
- 全局保存（`globalThis.globalToolHelper`）
- 词法闭包保存（`lexicalToolHelper`）

### 2.11 图像发射 (`js_repl_can_emit_*` 系列)

验证 `codex.emitImage()` 的各种用法：
- 通过 `view_image` 工具结果发射图像
- 从字节和 MIME 类型发射图像
- 一次 cell 中发射多个图像
- 等待未 awaited 的 `emitImage` 调用
- 跨 cell 持久化的 `emitImage` 辅助函数

### 2.12 错误处理 (`js_repl_unawaited_emit_image_errors_fail_cell` 等)

验证：
- 未捕获的 `emitImage` 错误导致 cell 失败
- 捕获的错误不会导致 cell 失败
- 缺少 MIME 类型时拒绝
- 拒绝非 data URL
- 拒绝无效的 detail 值
- 拒绝混合内容（文本 + 图像）

### 2.13 动态工具响应 (`js_repl_dynamic_tool_response_*`)

验证：
- 保留 Unicode 行分隔符（U+2028）和段落分隔符（U+2029）
- 能调用隐藏的动态工具（`defer_loading: true`）

### 2.14 模块解析 (`js_repl_prefers_env_node_module_dirs_over_config` 等)

验证 Node.js 模块解析逻辑：
- 环境变量 `CODEX_JS_REPL_NODE_MODULE_DIRS` 优先于配置
- 从第一个配置目录解析
- 回退到 CWD 的 `node_modules`
- 接受 `node_modules` 目录条目
- 支持相对路径文件导入（`./foo.js`）
- 支持绝对路径文件导入
- 导入的本地文件能访问 REPL 全局变量（`codex.tmpDir`、`codex.cwd` 等）

### 2.15 本地文件重新导入 (`js_repl_reimports_local_files_after_edit` 等)

验证：
- 文件修改后能重新导入（缓存失效）
- 修复失败的模块后能重新导入

### 2.16 import.meta 支持 (`js_repl_local_files_expose_node_like_import_meta`)

验证本地文件具有 Node.js 风格的 `import.meta`：
- `url`、`filename`、`dirname`、`main`
- `resolve()` 方法

### 2.17 导入限制 (`js_repl_rejects_top_level_static_imports_with_clear_error` 等)

验证：
- 拒绝顶层静态导入（要求使用 `await import()`）
- 拒绝本地文件中的静态裸导入
- 拒绝不支持的文件扩展名（`.ts`、无扩展名）
- 拒绝目录导入
- 拒绝不支持的 URL scheme（`https://`）
- 阻止敏感的内置模块导入（`node:process`、`node:child_process` 等）
- 防止从本地文件逃逸到父目录的 `node_modules`

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### `JsReplManager` (mod.rs:360-367)
```rust
pub struct JsReplManager {
    node_path: Option<PathBuf>,
    node_module_dirs: Vec<PathBuf>,
    tmp_dir: tempfile::TempDir,
    kernel: Arc<Mutex<Option<KernelState>>>,
    exec_lock: Arc<tokio::sync::Semaphore>,
    exec_tool_calls: Arc<Mutex<HashMap<String, ExecToolCalls>>>,
}
```

#### `KernelState` (mod.rs:116-124)
```rust
struct KernelState {
    child: Arc<Mutex<Child>>,
    recent_stderr: Arc<Mutex<VecDeque<String>>>,
    stdin: Arc<Mutex<ChildStdin>>,
    pending_execs: Arc<Mutex<HashMap<String, tokio::sync::oneshot::Sender<ExecResultMessage>>>>,
    exec_contexts: Arc<Mutex<HashMap<String, ExecContext>>>,
    top_level_exec_state: TopLevelExecState,
    shutdown: CancellationToken,
}
```

#### `TopLevelExecState` (mod.rs:133-149)
```rust
enum TopLevelExecState {
    Idle,
    FreshKernel { turn_id: String, exec_id: Option<String> },
    ReusedKernelPending { turn_id: String, exec_id: String },
    Submitted { turn_id: String, exec_id: String },
}
```

#### `ExecToolCalls` (mod.rs:181-187)
```rust
struct ExecToolCalls {
    in_flight: usize,
    content_items: Vec<FunctionCallOutputContentItem>,
    notify: Arc<Notify>,
    cancel: CancellationToken,
}
```

### 3.2 主机-内核协议

#### 主机到内核消息 (`HostToKernel`, mod.rs:1785-1794)
```rust
enum HostToKernel {
    Exec { id: String, code: String, timeout_ms: Option<u64> },
    RunToolResult(RunToolResult),
    EmitImageResult(EmitImageResult),
}
```

#### 内核到主机消息 (`KernelToHost`, mod.rs:1769-1781)
```rust
enum KernelToHost {
    ExecResult { id: String, ok: bool, output: String, error: Option<String> },
    RunTool(RunToolRequest),
    EmitImage(EmitImageRequest),
}
```

### 3.3 关键流程

#### 3.3.1 执行流程 (`JsReplManager::execute`, mod.rs:834-998)

1. **获取执行锁** - 通过 `exec_lock` 信号量确保单线程执行
2. **检查/启动内核** - 如果内核不存在，调用 `start_kernel`
3. **注册执行** - 生成 UUID，注册到 `pending_execs` 和 `exec_contexts`
4. **写入消息** - 通过 stdin 发送 `HostToKernel::Exec`
5. **等待响应** - 使用 oneshot channel 等待内核响应
6. **处理超时** - 如果超时，重置内核并返回错误
7. **处理结果** - 解析 `ExecResultMessage`，构建 `JsExecResult`

#### 3.3.2 内核启动流程 (`JsReplManager::start_kernel`, mod.rs:1000-1156)

1. **解析 Node 路径** - 调用 `resolve_compatible_node`
2. **写入内核脚本** - 将 `kernel.js` 和 `meriyah.umd.min.js` 写入临时目录
3. **构建环境变量** - 设置 `CODEX_JS_TMP_DIR`、`CODEX_JS_REPL_NODE_MODULE_DIRS`
4. **配置沙箱** - 使用 `SandboxManager` 选择和应用沙箱策略
5. **启动进程** - 使用 `tokio::process::Command` 启动 Node.js
6. **启动 I/O 任务** - 启动 `read_stdout` 和 `read_stderr` 异步任务

#### 3.3.3 标准输出读取流程 (`JsReplManager::read_stdout`, mod.rs:1269-1532)

1. **循环读取** - 从 stdout 读取 JSON Lines
2. **消息分发** - 根据消息类型处理：
   - `ExecResult` - 完成执行，发送结果
   - `RunTool` - 调用 Codex 工具，返回结果
   - `EmitImage` - 验证并处理图像发射
3. **清理** - 内核退出时清理 pending execs 和工具调用

### 3.4 内核实现 (kernel.js)

#### 3.4.1 REPL 状态模型
```javascript
let previousModule = null;
let previousBindings = [];
let cellCounter = 0;
```

每个 cell 编译为独立的 ESM 模块，通过 `@prev` 导入前一个 cell 的命名空间。

#### 3.4.2 代码插桩 (instrumentation)

使用 `meriyah` 解析器进行 AST 转换：
- `collectBindings` - 收集顶层绑定
- `instrumentCurrentBindings` - 插入标记调用以追踪已提交的绑定
- `collectFutureVarWriteReplacements` - 处理 `var` 的提前写入

#### 3.4.3 模块链接器

```javascript
await module.link(async (specifier) => {
  if (specifier === "@prev" && previousModule) {
    // 构建合成模块桥接前一个 cell
  }
  throw new Error("Top-level static import is not supported...");
});
```

#### 3.4.4 `codex` 全局 API

```javascript
const codex = {
  cwd,           // 当前工作目录
  homeDir,       // HOME 环境变量
  tmpDir,        // 临时目录
  tool(toolName, args),     // 调用 Codex 工具
  emitImage(imageLike),     // 发射图像到对话
};
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 职责 |
|-----|------|
| `mod.rs` | Rust 端 JsReplManager 实现，主机-内核协议，工具调用路由 |
| `mod_tests.rs` | 测试集合（本研究文档目标） |
| `kernel.js` | Node.js 内核实现，VM 模块管理，代码插桩，模块系统 |
| `meriyah.umd.min.js` | JavaScript 解析器（UMD 格式） |

### 4.2 调用方文件

| 文件 | 职责 |
|-----|------|
| `tools/handlers/js_repl.rs` | `JsReplHandler` 和 `JsReplResetHandler` 工具处理器 |
| `tools/handlers/js_repl_tests.rs` | 处理器级别的单元测试 |
| `codex.rs` | `TurnContext` 包含 `JsReplHandle`，提供 `make_session_and_context` 测试辅助函数 |

### 4.3 关键代码路径

```
工具调用入口
├── tools/handlers/js_repl.rs:110-182 (JsReplHandler::handle)
│   └── 调用 turn.js_repl.manager().await?
│       └── mod.rs:88-95 (JsReplHandle::manager)
│           └── 初始化 JsReplManager
│               └── mod.rs:370-388 (JsReplManager::new)
│
执行流程
├── mod.rs:834-998 (JsReplManager::execute)
│   ├── 获取执行锁 (exec_lock)
│   ├── 检查/启动内核
│   │   └── mod.rs:1000-1156 (start_kernel)
│   │       ├── 写入内核脚本 (kernel.js, meriyah.umd.min.js)
│   │       ├── 配置沙箱
│   │       └── 启动 Node.js 进程
│   ├── 注册执行上下文
│   ├── 写入 Exec 消息
│   └── 等待响应
│
内核通信
├── mod.rs:1269-1532 (read_stdout)
│   ├── 解析 KernelToHost 消息
│   ├── ExecResult - 完成执行
│   ├── RunTool - 调用 Codex 工具
│   │   └── mod.rs:1534-1675 (run_tool_request)
│   │       └── 使用 ToolRouter 分发工具调用
│   └── EmitImage - 处理图像发射
│
工具调用追踪
├── mod.rs:420-505 (exec_tool_calls 管理)
│   ├── begin_exec_tool_call - 开始追踪
│   ├── record_exec_content_item - 记录内容项
│   ├── finish_exec_tool_call - 标记完成
│   └── wait_for_exec_tool_calls_map - 等待完成
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```rust
// 核心协议类型
use codex_protocol::models::FunctionCallOutputContentItem;
use codex_protocol::models::FunctionCallOutputPayload;
use codex_protocol::models::ImageDetail;
use codex_protocol::models::ResponseInputItem;
use codex_protocol::openai_models::InputModality;
use codex_protocol::dynamic_tools::{DynamicToolCallOutputContentItem, DynamicToolResponse, DynamicToolSpec};

// 内部模块
use crate::codex::{make_session_and_context, make_session_and_context_with_dynamic_tools_and_rx};
use crate::features::Feature;
use crate::protocol::{AskForApproval, EventMsg, SandboxPolicy};
use crate::turn_diff_tracker::TurnDiffTracker;
```

### 5.2 外部依赖

| 依赖 | 用途 |
|-----|------|
| `tokio` | 异步运行时、进程管理、同步原语 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `uuid` | 生成执行 ID |
| `tempfile` | 临时目录管理 |
| `pretty_assertions` | 测试断言 |
| `Node.js` | JavaScript 执行环境（外部进程）|

### 5.3 环境变量

| 变量 | 用途 |
|-----|------|
| `CODEX_JS_REPL_NODE_PATH` | 指定 Node.js 可执行文件路径 |
| `CODEX_JS_REPL_NODE_MODULE_DIRS` | 指定模块搜索路径 |
| `CODEX_JS_TMP_DIR` | 内核临时目录 |
| `HOME` | 用户主目录 |
| `CODEX_THREAD_ID` | 线程 ID（用于内部绑定盐值）|

### 5.4 测试辅助函数

```rust
// 来自 codex.rs 的测试辅助函数
pub(crate) use tests::make_session_and_context;
pub(crate) use tests::make_session_and_context_with_dynamic_tools_and_rx;
pub(crate) use tests::make_session_and_context_with_rx;
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 平台限制
- **风险**：运行时测试仅在 macOS 执行，Linux 依赖集成测试
- **影响**：Linux 特定的沙箱行为（`codex-linux-sandbox`）覆盖可能不足
- **建议**：考虑在 CI 中增加 macOS 运行器执行这些测试

#### 6.1.2 竞态条件
- **风险**：`exec_tool_calls` 映射的并发访问复杂
- **缓解**：使用 `Mutex` + `Notify` 模式，测试覆盖多种并发场景
- **边界**：`reset_clears_inflight_exec_tool_calls_without_waiting` 测试验证无等待清理

#### 6.1.3 内核崩溃处理
- **风险**：Node.js 内核可能因未捕获异常、内存不足等原因崩溃
- **缓解**：
  - `uncaughtException` 和 `unhandledRejection` 处理器
  - 主机检测 stdout EOF 并清理状态
  - 下次执行时自动重启内核

#### 6.1.4 模块缓存失效
- **风险**：本地文件修改后缓存可能未正确失效
- **测试覆盖**：`js_repl_reimports_local_files_after_edit` 验证此场景
- **边界**：仅验证文件内容修改，不验证文件删除/重命名

### 6.2 边界条件

| 边界 | 说明 |
|-----|------|
| 超时最小值 | 测试使用 50ms 超时验证行为 |
| stderr 限制 | 20 行、每行 512 字节、总共 4096 字节 |
| 诊断信息限制 | stderr 1024 字节、错误 256 字节 |
| 并发工具调用 | 测试验证 128 次循环的并发操作 |
| 图像大小 | 测试使用 1x1 像素的 base64 PNG |

### 6.3 改进建议

#### 6.3.1 测试覆盖
- **建议 1**：增加对 Windows 平台的测试（当前仅 macOS 运行时测试）
- **建议 2**：增加对大型图像（接近大小限制）的测试
- **建议 3**：增加对循环依赖本地模块的测试
- **建议 4**：增加对并发 `reset()` 调用的测试

#### 6.3.2 可观测性
- **建议 5**：在测试失败时捕获并输出内核 stderr 内容，便于诊断
- **建议 6**：增加对 `exec_tool_calls` 映射大小的监控/限制

#### 6.3.3 性能
- **建议 7**：考虑对 `linkedFileModules` 缓存设置大小限制，防止内存泄漏
- **建议 8**：考虑对 `pendingTool` 和 `pendingEmitImage` 映射设置清理超时

#### 6.3.4 安全性
- **建议 9**：考虑对 `CODEX_JS_REPL_NODE_MODULE_DIRS` 进行路径遍历验证
- **建议 10**：考虑对 `kernel.js` 进行完整性校验（如哈希检查）

### 6.4 技术债务

1. **测试条件分散**：`can_run_js_repl_runtime_tests()` 在多处重复定义，应统一
2. **辅助函数重复**：`write_js_repl_test_package` 等辅助函数与 `mod.rs` 中的生产代码有重复逻辑
3. **硬编码超时**：测试中使用多处硬编码超时（如 10s、15s），应统一配置

---

## 7. 总结

`mod_tests.rs` 是一个全面的测试集合，覆盖了 JavaScript REPL 功能的各个方面：

- **单元测试**：验证独立函数的正确性
- **集成测试**：验证与 Node.js 内核的完整交互
- **并发测试**：验证多线程环境下的正确性
- **生命周期测试**：验证内核启动、重置、崩溃恢复
- **模块系统测试**：验证本地文件和 npm 包导入
- **图像处理测试**：验证 `emitImage` 的各种场景

测试设计良好，使用了 `pretty_assertions` 提供清晰的差异输出，使用 `tokio::time::timeout` 防止测试挂起。主要限制是运行时测试仅在 macOS 执行，这可能影响跨平台兼容性验证。
