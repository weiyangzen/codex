# js_repl 模块研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 核心定位
`js_repl` 是 Codex CLI 的 JavaScript REPL（交互式解释器）工具模块，提供了一个基于 Node.js 的持久化 JavaScript 执行环境。它允许模型在对话中执行 JavaScript 代码，并保持跨调用的变量状态，类似于 Jupyter Notebook 的 cell 执行模式。

### 主要职责
1. **代码执行**：在隔离的 Node.js VM 环境中执行 JavaScript 代码
2. **状态持久化**：跨多次执行保持顶层变量绑定（`const`/`let`/`var`/`function`/`class`）
3. **工具调用**：支持从 JavaScript 代码中调用其他 Codex 工具（`codex.tool()`）
4. **图像输出**：支持将图像数据作为执行结果返回（`codex.emitImage()`）
5. **安全管理**：通过沙箱机制限制代码执行权限，阻止危险操作

### 使用场景
- 复杂数据处理和转换
- 需要状态保持的多步骤计算
- 调用其他工具并处理其结果
- 生成和输出图像数据

---

## 功能点目的

### 1. 持久化 REPL 环境
- **目的**：允许用户在多次调用之间保持 JavaScript 状态
- **实现**：通过 Node.js VM 模块创建隔离上下文，使用 ESM 模块系统实现状态传递
- **状态传递机制**：每个 "cell"（执行单元）编译为独立 ESM 模块，通过 `@prev` 伪导入引用前一 cell 的命名空间

### 2. 工具调用桥接
- **目的**：允许 JavaScript 代码调用 Codex 的其他工具
- **API**：`codex.tool(toolName, args)` 返回 Promise
- **实现**：通过 JSON Lines 协议与宿主进程通信，异步等待工具执行结果

### 3. 图像输出支持
- **目的**：允许 JavaScript 代码生成并返回图像
- **API**：`codex.emitImage(dataUrl | {bytes, mimeType})`
- **限制**：仅接受 data URL 格式，禁止外部 URL

### 4. 超时与中断控制
- **目的**：防止长时间运行或无限循环的代码
- **配置**：支持通过 `// codex-js-repl: timeout_ms=15000` pragma 设置单次超时
- **中断**：支持 turn-level 中断，终止当前执行的 cell

### 5. 安全沙箱
- **目的**：限制 JavaScript 代码的执行权限
- **措施**：
  - 禁止访问 `process`、`child_process`、`worker_threads` 等敏感模块
  - 模块解析限制在指定的 `node_module_dirs` 内
  - 使用 Seatbelt/Landlock 等系统级沙箱（通过 `SandboxManager`）

---

## 具体技术实现

### 3.1 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                     Rust Host (codex-core)                   │
│  ┌─────────────────┐    ┌──────────────────────────────┐   │
│  │ JsReplHandler   │───▶│     JsReplManager            │   │
│  │ (工具处理器)     │    │  - 管理 kernel 生命周期       │   │
│  └─────────────────┘    │  - 执行队列控制               │   │
│                         │  - 工具调用协调               │   │
│                         └──────────────┬─────────────────┘   │
│                                        │                     │
│                         ┌──────────────▼─────────────────┐   │
│                         │      KernelState               │   │
│                         │  - Child 进程管理               │   │
│                         │  - stdin/stdout 管道           │   │
│                         │  - 待处理执行映射               │   │
│                         └──────────────┬─────────────────┘   │
│                                        │                     │
└────────────────────────────────────────┼─────────────────────┘
                                         │ JSON Lines over stdio
┌────────────────────────────────────────┼─────────────────────┐
│            Node.js Kernel (kernel.js)  │                     │
│                         ┌──────────────▼─────────────────┐   │
│                         │       handleExec()             │   │
│                         │  - 代码解析 (Meriyah)          │   │
│                         │  - 绑定收集与注入               │   │
│                         │  - VM 模块编译执行             │   │
│                         └────────────────────────────────┘   │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VM Context (vm.createContext)              │ │
│  │  - console, Buffer, URL, fetch, crypto...              │ │
│  │  - codex.tool() / codex.emitImage() / codex.cwd        │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心数据结构

#### 3.2.1 JsReplHandle（宿主端入口）
```rust
pub(crate) struct JsReplHandle {
    node_path: Option<PathBuf>,           // Node 可执行路径
    node_module_dirs: Vec<PathBuf>,       // 模块搜索目录
    cell: OnceCell<Arc<JsReplManager>>,   // 懒加载的管理器
}
```

#### 3.2.2 JsReplManager（核心管理器）
```rust
pub struct JsReplManager {
    node_path: Option<PathBuf>,
    node_module_dirs: Vec<PathBuf>,
    tmp_dir: tempfile::TempDir,           // 存放 kernel.js 和 meriyah
    kernel: Arc<Mutex<Option<KernelState>>>, // Kernel 进程状态
    exec_lock: Arc<tokio::sync::Semaphore>, // 执行互斥锁（容量=1）
    exec_tool_calls: Arc<Mutex<HashMap<String, ExecToolCalls>>>, // 工具调用跟踪
}
```

#### 3.2.3 KernelState（Kernel 进程状态）
```rust
struct KernelState {
    child: Arc<Mutex<Child>>,             // Node 子进程
    recent_stderr: Arc<Mutex<VecDeque<String>>>, // 最近 stderr 行（调试）
    stdin: Arc<Mutex<ChildStdin>>,        // 标准输入管道
    pending_execs: Arc<Mutex<HashMap<String, oneshot::Sender<ExecResultMessage>>>>,
    exec_contexts: Arc<Mutex<HashMap<String, ExecContext>>>, // 执行上下文
    top_level_exec_state: TopLevelExecState, // 顶层执行状态机
    shutdown: CancellationToken,          // 关闭信号
}
```

#### 3.2.4 执行状态机（TopLevelExecState）
```rust
enum TopLevelExecState {
    Idle,                           // 空闲
    FreshKernel { turn_id, exec_id: Option<String> },  // 新 kernel
    ReusedKernelPending { turn_id, exec_id },          // 复用 kernel，待提交
    Submitted { turn_id, exec_id }, // 已提交执行
}
```

### 3.3 关键流程

#### 3.3.1 Kernel 启动流程
1. **版本检查**：`resolve_compatible_node()` 检查 Node 版本（最低版本从 `node-version.txt` 读取）
2. **脚本写入**：`write_kernel_script()` 将 `kernel.js` 和 `meriyah.umd.min.js` 写入临时目录
3. **进程启动**：使用 `tokio::process::Command` 启动 Node，参数 `--experimental-vm-modules`
4. **沙箱配置**：通过 `SandboxManager` 应用 Seatbelt/Landlock 沙箱策略
5. **IO 循环启动**：
   - `read_stdout()`：处理 Kernel 输出（JSON Lines）
   - `read_stderr()`：收集 stderr 用于调试

#### 3.3.2 代码执行流程
1. **参数解析**：`JsReplHandler::handle()` 解析 `JsReplArgs { code, timeout_ms }`
2. **获取管理器**：`turn.js_repl.manager().await` 懒初始化 `JsReplManager`
3. **执行请求**：`manager.execute(session, turn, tracker, args)`
4. **Kernel 检查**：如无运行中的 Kernel，调用 `start_kernel()` 创建
5. **请求构造**：生成唯一 `req_id`，创建 `HostToKernel::Exec` 消息
6. **发送执行**：`write_message()` 将 JSON 写入 Kernel stdin
7. **等待结果**：使用 `tokio::time::timeout` 等待 oneshot 通道响应
8. **结果处理**：
   - `ExecResultMessage::Ok`：返回输出和 content items
   - `ExecResultMessage::Err`：返回错误信息
   - 超时：调用 `reset_kernel()` 终止并重启 Kernel

#### 3.3.3 Kernel 端代码处理（kernel.js）
1. **AST 解析**：使用 Meriyah 解析代码为 AST
2. **绑定收集**：`collectBindings()` 提取顶层声明（`const`/`let`/`var`/`function`/`class`）
3. **代码注入**：
   - 为变量声明添加提交标记调用
   - 为函数/类声明添加提交标记
   - 处理循环中的 `var` 绑定
4. **模块构建**：
   - 生成 prelude：从 `@prev` 导入前一 cell 的绑定
   - 合并当前 cell 的导出
5. **VM 执行**：
   - 创建 `SourceTextModule`
   - 链接阶段处理 `@prev` 为 `SyntheticModule`
   - 评估模块，捕获 console 输出
6. **结果发送**：通过 stdout 返回 `ExecResult` JSON

#### 3.3.4 工具调用流程（Kernel → Host）
1. **JS 调用**：`codex.tool("tool_name", args)`
2. **消息构造**：`RunTool { id, exec_id, tool_name, arguments }`
3. **发送到宿主**：通过 stdout 发送 JSON
4. **宿主处理**：`read_stdout()` 接收 `KernelToHost::RunTool`
5. **工具路由**：`run_tool_request()` 创建 `ToolRouter` 并分发调用
6. **递归防护**：禁止调用 `js_repl` 和 `js_repl_reset` 自身
7. **结果返回**：`HostToKernel::RunToolResult` 写回 Kernel stdin
8. **Promise 解析**：Kernel 中解析结果，完成 Promise

#### 3.3.5 图像输出流程
1. **JS 调用**：`codex.emitImage(dataUrl)` 或 `codex.emitImage({bytes, mimeType})`
2. **数据验证**：检查 data URL 格式，拒绝外部 URL
3. **消息发送**：`EmitImage { id, exec_id, image_url, detail }`
4. **宿主处理**：验证 URL，创建 `FunctionCallOutputContentItem::InputImage`
5. **结果收集**：content item 存入 `exec_tool_calls` 映射
6. **执行完成**：与主输出合并返回

### 3.4 通信协议

#### Host → Kernel 消息
```rust
enum HostToKernel {
    Exec { id, code, timeout_ms },
    RunToolResult(RunToolResult),
    EmitImageResult(EmitImageResult),
}
```

#### Kernel → Host 消息
```rust
enum KernelToHost {
    ExecResult { id, ok, output, error },
    RunTool(RunToolRequest),
    EmitImage(EmitImageRequest),
}
```

通信格式：JSON Lines（每行一个 JSON 对象，以 `\n` 分隔）

### 3.5 状态持久化机制

#### 绑定传递原理
```javascript
// Cell N 的代码
const x = 1;
let y = 2;

// 编译后生成导出
export { x, y };

// Cell N+1 的 prelude
import * as __prev from "@prev";
const x = __prev.x;
let y = __prev.y;
```

#### 失败 Cell 的绑定恢复
- **lexical 绑定**（`const`/`let`/`class`）：如果初始化完成，通过 namespace 读取恢复
- **var 绑定**：仅当声明点或写入点被执行时才恢复
- **function 绑定**：仅当函数声明被执行时才恢复

---

## 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | ~1966 | 宿主端核心实现：管理器、状态机、IO 处理 |
| `kernel.js` | ~1784 | Node.js Kernel：VM 执行、代码转换、工具桥接 |
| `mod_tests.rs` | ~1999 | 单元测试和集成测试 |
| `handlers/js_repl.rs` | ~296 | 工具处理器实现（Handler 接口） |
| `handlers/js_repl_tests.rs` | ~90 | 处理器单元测试 |

### 4.2 关键代码路径

#### 初始化路径
```
codex.rs:Session::new()
  └── js_repl: Arc::new(JsReplHandle::with_node_path(...))
      └── 懒加载: JsReplManager::new()
          └── start_kernel() [首次执行时]
```

#### 执行路径
```
handlers/js_repl.rs:JsReplHandler::handle()
  └── manager.execute()
      ├── start_kernel() [如需要]
      │   ├── resolve_compatible_node()
      │   ├── write_kernel_script()
      │   └── SandboxManager::transform()
      ├── write_message(HostToKernel::Exec)
      └── 等待 oneshot 响应
```

#### Kernel 消息处理路径
```
mod.rs:read_stdout()
  ├── KernelToHost::ExecResult
  │   └── 发送 ExecResultMessage 到 oneshot
  ├── KernelToHost::RunTool
  │   └── spawn run_tool_request()
  │       └── ToolRouter::dispatch_tool_call_with_code_mode_result()
  └── KernelToHost::EmitImage
      └── 验证并创建 content item
```

### 4.3 配置相关

| 配置项 | 位置 | 说明 |
|--------|------|------|
| `js_repl_node_path` | `config/mod.rs`, `config/profile.rs` | Node 可执行路径 |
| `js_repl_node_module_dirs` | `config/mod.rs`, `config/profile.rs` | 模块搜索目录 |
| `Feature::JsRepl` | `features.rs` | 功能开关 |
| `Feature::JsReplToolsOnly` | `features.rs` | 仅暴露 js_repl 工具 |

### 4.4 工具注册

```rust
// tools/spec.rs
if config.js_repl_enabled {
    push_tool_spec(create_js_repl_tool(), ...);
    push_tool_spec(create_js_repl_reset_tool(), ...);
    builder.register_handler("js_repl", js_repl_handler);
    builder.register_handler("js_repl_reset", js_repl_reset_handler);
}
```

---

## 依赖与外部交互

### 5.1 内部依赖

| 模块 | 用途 |
|------|------|
| `crate::tools::registry` | 工具注册和分发 |
| `crate::tools::router` | 工具路由（用于嵌套工具调用） |
| `crate::tools::context` | 工具调用上下文（`ToolInvocation`） |
| `crate::tools::events` | 工具执行事件发射 |
| `crate::sandboxing` | 沙箱策略应用 |
| `crate::features` | 功能开关检查 |
| `crate::codex::{Session, TurnContext}` | 会话和回合上下文 |

### 5.2 外部依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时、进程管理、同步原语 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `uuid` | 生成唯一执行 ID |
| `tempfile` | 临时目录管理 |
| `which` | 查找 Node 可执行文件 |
| `tracing` | 日志和遥测 |

### 5.3 嵌入资源

| 文件 | 用途 |
|------|------|
| `kernel.js` | Node.js Kernel 源码（`include_str!`） |
| `meriyah.umd.min.js` | JavaScript 解析器（`include_str!`） |
| `node-version.txt` | 最低 Node 版本要求 |

### 5.4 环境变量

| 变量 | 说明 |
|------|------|
| `CODEX_JS_REPL_NODE_PATH` | 覆盖 Node 路径 |
| `CODEX_JS_TMP_DIR` | Kernel 临时目录 |
| `CODEX_JS_REPL_NODE_MODULE_DIRS` | 模块搜索目录（冒号分隔） |
| `CODEX_THREAD_ID` | 用于内部绑定名盐值 |

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险
- **VM 逃逸**：虽然使用了 VM 模块，但 JavaScript 的复杂性意味着理论上可能存在逃逸漏洞
- **模块注入**：`node_module_dirs` 配置不当可能允许加载恶意模块
- **拒绝服务**：虽然有时超时控制，但复杂的正则或计算仍可能导致 CPU 耗尽

#### 6.1.2 稳定性风险
- **Kernel 崩溃**：未捕获的异常或 Promise 拒绝会导致 Kernel 进程退出
- **状态丢失**：Kernel 重启后所有绑定丢失，需要重新执行之前的 cell
- **内存泄漏**：长时间运行的 session 中，Kernel 进程可能累积内存

#### 6.1.3 兼容性风险
- **Node 版本**：依赖特定 Node 版本（检查 `node-version.txt`）
- **平台差异**：macOS 使用 Seatbelt，Linux 使用 Landlock，Windows 沙箱支持有限

### 6.2 边界情况

| 场景 | 行为 |
|------|------|
| 无限循环 | 超时后 Kernel 被强制终止并重启 |
| 递归调用 js_repl | 被显式阻止，返回错误 |
| 失败的 cell | 已完成的绑定保留，未完成的绑定丢弃 |
| 空循环 `for (var x of [])` | 变量不保留（设计权衡） |
| 非 data URL 图像 | 被拒绝，返回错误 |
| 混合文本和图像内容 | `emitImage` 拒绝，返回错误 |

### 6.3 改进建议

#### 6.3.1 性能优化
1. **Kernel 预热**：在 session 启动时预启动 Kernel，减少首次执行延迟
2. **绑定压缩**：对于大量绑定的场景，考虑使用更高效的状态序列化
3. **并行执行**：当前使用单 Semaphore，考虑支持多个独立 Kernel 实例

#### 6.3.2 功能增强
1. **TypeScript 支持**：添加 TypeScript 编译支持
2. **模块热重载**：支持开发时模块更新
3. **调试支持**：添加 `debugger` 语句支持和 source map
4. **性能分析**：提供执行时间和内存使用统计

#### 6.3.3 可观测性
1. **详细日志**：添加更多执行阶段的 tracing span
2. **指标收集**：收集执行成功率、平均执行时间等指标
3. **错误分类**：更细粒度的错误类型，便于问题诊断

#### 6.3.4 安全加固
1. **资源限制**：添加 CPU 时间、内存使用上限
2. **网络隔离**：更严格的网络访问控制
3. **审计日志**：记录所有工具调用和图像输出

### 6.4 测试覆盖

测试文件位置：
- `mod_tests.rs`：~2000 行，覆盖核心逻辑
- `handlers/js_repl_tests.rs`：处理器单元测试
- `tests/suite/js_repl.rs`：集成测试（~712 行）

关键测试场景：
- 基础执行和状态持久化
- 失败 cell 的绑定恢复
- 工具调用和图像输出
- 超时和中断处理
- 安全限制（模块导入、递归调用）

---

## 附录：代码统计

```
codex-rs/core/src/tools/js_repl/
├── kernel.js          ~1784 行（JavaScript Kernel）
├── meriyah.umd.min.js ~1 行（压缩后的解析器，实际 ~133KB）
├── mod.rs             ~1966 行（Rust 宿主实现）
└── mod_tests.rs       ~1999 行（测试）

总计：~4750 行（不含 meriyah 压缩代码）
```

---

*文档生成时间：2026-03-21*
*基于 commit: 研究时 HEAD*
