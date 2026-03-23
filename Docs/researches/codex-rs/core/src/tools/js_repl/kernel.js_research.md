# kernel.js 深度研究文档

## 1. 场景与职责

### 1.1 核心定位

`kernel.js` 是 Codex 项目中 JavaScript REPL (Read-Eval-Print Loop) 功能的核心执行引擎。它是一个 Node.js 脚本，作为子进程被 Rust 主程序启动，负责在隔离的 VM 环境中执行用户提供的 JavaScript 代码。

### 1.2 主要职责

| 职责领域 | 具体描述 |
|---------|---------|
| **代码执行** | 在 Node.js VM 模块创建的隔离上下文中执行 JavaScript 代码 |
| **状态持久化** | 维护 REPL 会话状态，支持跨执行单元(cell)的变量绑定传递 |
| **模块解析** | 实现自定义的模块导入系统，支持 npm 包、本地文件和 Node 内置模块 |
| **工具调用** | 提供 `codex.tool()` API，允许 JavaScript 代码调用 Codex 工具 |
| **图像输出** | 提供 `codex.emitImage()` API，支持将图像数据返回给主程序 |
| **安全沙箱** | 限制危险模块访问，防止代码逃逸 |

### 1.3 使用场景

- **交互式调试**: 用户在对话中执行 JavaScript 代码片段
- **自动化脚本**: 通过 `js_repl` 工具执行复杂的 JavaScript 逻辑
- **网页调试**: 结合浏览器自动化工具进行网页调试
- **数据处理**: 使用 JavaScript 进行数据转换和分析

---

## 2. 功能点目的

### 2.1 VM 隔离执行

**目的**: 在用户代码和宿主 Node 进程之间建立安全隔离层。

**实现方式**:
- 使用 Node.js 的 `vm` 模块创建独立上下文
- 通过 `SourceTextModule` 和 `SyntheticModule` 实现 ES 模块支持
- 每个执行单元(cell)作为一个独立模块运行

```javascript
const context = vm.createContext({});
// 填充常用全局对象
context.globalThis = context;
context.Buffer = Buffer;
context.console = console;
// ... 其他全局对象
```

### 2.2 状态持久化机制

**目的**: 实现类似传统 REPL 的体验，让变量在多次执行间保持。

**核心概念**:
- **Cell**: 单次代码执行单元
- **Bindings**: 变量绑定，包含名称和类型(const/let/var/function/class)
- **@prev 模块**: 通过合成模块机制将上一 cell 的导出导入到新 cell

**状态流转**:
```
Cell N 执行 → 收集 bindings → 创建 @prev 合成模块 → Cell N+1 导入 @prev
```

### 2.3 失败恢复机制

**目的**: 当某个 cell 执行失败时，合理保留已初始化的状态。

**策略**:
- `const`/`let`/`class`: 通过模块命名空间可读性判断初始化是否完成
- `var`/`function`: 通过声明点标记器跟踪
- 支持预声明变量写入的恢复（如 `x = 1; var x;`）

### 2.4 模块系统

**目的**: 在受限环境中提供灵活的模块导入能力。

**支持的导入类型**:
| 类型 | 示例 | 说明 |
|-----|------|------|
| Node 内置模块 | `node:fs`, `node:path` | 部分敏感模块被禁用 |
| npm 包 | `lodash`, `@scope/pkg` | 通过 CODEX_JS_REPL_NODE_MODULE_DIRS 配置搜索路径 |
| 本地文件 | `./utils.js`, `/abs/path.js` | 仅支持 `.js` 和 `.mjs` 文件 |
| 动态导入 | `await import("specifier")` | 运行时动态解析 |

**安全限制**:
- 禁止访问: `process`, `child_process`, `worker_threads`
- 静态导入限制: 仅支持 `@prev`，其他需使用动态导入

### 2.5 工具调用桥接

**目的**: 让 JavaScript 代码能够调用 Codex 的工具系统。

**API 设计**:
```javascript
// 调用任意 Codex 工具
const result = await codex.tool("shell_command", { command: "ls -la" });

// 发送图像到对话
await codex.emitImage("data:image/png;base64,...");
await codex.emitImage({ bytes: imageBuffer, mimeType: "image/png" });
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### Binding (变量绑定)
```javascript
/**
 * @typedef {{ name: string, kind: "const"|"let"|"var"|"function"|"class" }} Binding
 */
```

#### REPL 状态模型
```javascript
// 核心状态变量
let previousModule = null;        // 上一个成功执行的模块
let previousBindings = [];        // 需要传递到下一个 cell 的绑定
let cellCounter = 0;              // cell 计数器，用于生成唯一标识
let internalBindingCounter = 0;   // 内部绑定计数器
const internalBindingSalt = ...;  // 基于线程 ID 的盐值，防止命名冲突
```

#### 执行上下文
```javascript
const execContextStorage = new AsyncLocalStorage();
// 存储: { id: string, pendingBackgroundTasks: Set<Promise> }
```

### 3.2 关键流程

#### 代码执行流程 (handleExec)

```
1. 清除本地文件模块缓存
2. 构建模块源代码 (buildModuleSource)
   ├── 使用 meriyah 解析 AST
   ├── 收集变量绑定 (collectBindings)
   ├── 仪器化变量声明 (instrumentCurrentBindings)
   ├── 处理未来 var 写入 (collectFutureVarWriteReplacements)
   └── 生成含 prelude 的完整模块代码
3. 创建 SourceTextModule
4. 链接模块 (module.link)
   └── 处理 @prev 导入，创建 SyntheticModule
5. 评估模块 (module.evaluate)
6. 等待后台任务完成
7. 更新 previousModule 和 previousBindings
8. 发送执行结果
```

#### 模块源代码构建 (buildModuleSource)

```javascript
async function buildModuleSource(code) {
  // 1. 解析 AST
  const ast = meriyah.parseModule(code, { ranges: true, ... });
  
  // 2. 收集当前 bindings
  const currentBindings = collectBindings(ast);
  
  // 3. 处理未来 var 写入（hoisted 变量在声明前被赋值的情况）
  const writeInstrumentedCode = applyReplacements(
    code,
    collectFutureVarWriteReplacements(code, ast, { ... })
  );
  
  // 4. 重新解析仪器化后的代码
  const instrumentedAst = meriyah.parseModule(writeInstrumentedCode, ...);
  
  // 5. 仪器化当前 bindings
  const instrumentedCode = instrumentCurrentBindings(...);
  
  // 6. 构建 prelude
  let prelude = '';
  if (previousModule && priorBindings.length) {
    prelude += 'import * as __prev from "@prev";\n';
    prelude += priorBindings.map(b => 
      `${b.kind === 'var' ? 'var' : b.kind === 'const' ? 'const' : 'let'} ${b.name} = __prev.${b.name};`
    ).join('\n');
  }
  
  // 7. 添加辅助声明和标记函数
  prelude += helperDeclarations.join('\n');
  prelude += `${markPreludeCompletedFnName}();\n`;
  
  // 8. 构建导出语句
  const exportStmt = exportNames.length ? `\nexport { ${exportNames.join(', ')} };` : '';
  
  return { source: prelude + instrumentedCode + exportStmt, ... };
}
```

#### 模块解析流程 (resolveSpecifier)

```
resolveSpecifier(specifier, referrerIdentifier)
├── 检查 node: 前缀或内置模块名
│   └── 如果是 denied 模块 → 抛出错误
├── 检查是否是路径指定符
│   ├── file:// URL → 转换为路径
│   ├── 绝对/相对路径 → 解析
│   └── 验证文件存在、是文件、扩展名合法
├── 检查是否是 bare package 指定符
│   └── 通过 require.resolve 解析（带条件: node, import）
└── 返回解析结果: { kind: "builtin"|"file"|"package", ... }
```

### 3.3 协议设计

#### 主机 → Kernel 消息

```typescript
type HostToKernel =
  | { type: "exec"; id: string; code: string; timeout_ms?: number }
  | { type: "run_tool_result"; id: string; ok: boolean; response?: any; error?: string }
  | { type: "emit_image_result"; id: string; ok: boolean; error?: string };
```

#### Kernel → 主机消息

```typescript
type KernelToHost =
  | { type: "exec_result"; id: string; ok: boolean; output: string; error?: string }
  | { type: "run_tool"; id: string; exec_id: string; tool_name: string; arguments: string }
  | { type: "emit_image"; id: string; exec_id: string; image_url: string; detail?: string };
```

#### 通信机制
- 传输: JSON Lines (JSONL) over stdin/stdout
- 队列: 串行执行，通过 `queue = queue.then(() => handleExec(message))` 实现
- 错误处理: uncaughtException 和 unhandledRejection 触发致命退出

### 3.4 仪器化技术细节

#### 变量声明仪器化

对于每个顶层变量声明，插入提交标记:

```javascript
// 原始代码
const x = 1, y = 2;

// 仪器化后
const __codex_internal_commit_salt_0 = import.meta.__codexInternalMarkCommittedBindings;
const x = 1, __codex_internal_commit_salt_1 = __codex_internal_commit_salt_0("x"), 
      y = 2, __codex_internal_commit_salt_2 = __codex_internal_commit_salt_0("y");
```

#### 函数/类声明仪器化

```javascript
// 原始代码
function foo() { return 1; }

// 仪器化后
function foo() { return 1; }
__codex_internal_commit_salt_N("foo");
```

#### 循环变量仪器化

```javascript
// 原始代码
for (var x of [1, 2, 3]) { console.log(x); }

// 仪器化后
let __guard_N = true;
for (var x of [1, 2, 3]) { 
  if (__guard_N) { __guard_N = false; __codex_internal_commit_salt_N("x"); }
  console.log(x); 
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/core/src/tools/js_repl/
├── kernel.js              # 核心执行引擎 (本研究对象)
├── meriyah.umd.min.js     # JavaScript 解析器 (bundled)
├── mod.rs                 # Rust 主机端管理器
├── mod_tests.rs           # 单元测试
└── [通过 include_str! 嵌入 kernel.js]
```

### 4.2 调用链

#### 启动流程
```
JsReplManager::new()
└── JsReplManager::start_kernel()
    ├── 写入 kernel.js 和 meriyah.umd.min.js 到临时目录
    ├── 启动 Node 进程: node --experimental-vm-modules /tmp/.../kernel.js
    └── 建立 stdin/stdout 通信管道
```

#### 代码执行调用链
```
JsReplHandler::handle()                 [handlers/js_repl.rs]
└── JsReplManager::execute()            [mod.rs]
    ├── 获取或创建 KernelState
    ├── 发送 HostToKernel::Exec 消息
    ├── 等待 oneshot channel 响应
    └── 处理 ExecResultMessage

Kernel 端 (kernel.js):
handleInputLine() → handleExec()
    ├── buildModuleSource()
    │   ├── meriyah.parseModule()
    │   ├── collectBindings()
    │   └── instrumentCurrentBindings()
    ├── module.link() 处理 @prev
    ├── module.evaluate()
    └── 发送 exec_result 消息
```

#### 工具调用调用链
```
JavaScript: codex.tool("name", args)
└── 发送 KernelToHost::RunTool 消息

Rust 端:
read_stdout() 接收消息
└── JsReplManager::run_tool_request()
    ├── ToolRouter::dispatch_tool_call_with_code_mode_result()
    ├── 执行工具
    └── 发送 HostToKernel::RunToolResult 回 kernel

Kernel 端:
handleToolResult() → 解析 Promise
```

### 4.3 关键代码位置

| 功能 | 文件 | 行号范围 |
|-----|------|---------|
| VM 上下文创建 | kernel.js | 25-71 |
| 模块解析 | kernel.js | 371-397 |
| 构建模块源代码 | kernel.js | 959-1047 |
| 收集 Bindings | kernel.js | 524-562 |
| 仪器化当前 Bindings | kernel.js | 850-957 |
| 处理未来 var 写入 | kernel.js | 701-848 |
| 执行 Cell | kernel.js | 1542-1687 |
| 工具调用 API | kernel.js | 1444-1479 |
| 图像输出 API | kernel.js | 1480-1539 |
| 消息处理循环 | kernel.js | 1716-1784 |
| Rust 管理器 | mod.rs | 360-999 |
| 协议定义 | mod.rs | 1769-1839 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

#### Node.js 内置模块
```javascript
const { Buffer } = require("node:buffer");
const { AsyncLocalStorage } = require("node:async_hooks");
const crypto = require("node:crypto");
const fs = require("node:fs");
const { builtinModules, createRequire } = require("node:module");
const { performance } = require("node:perf_hooks");
const path = require("node:path");
const { URL, URLSearchParams, fileURLToPath, pathToFileURL } = require("node:url");
const { inspect, TextDecoder, TextEncoder } = require("node:util");
const vm = require("node:vm");
```

#### 第三方依赖
- **meriyah**: JavaScript 解析器 (v7.0.0)，用于 AST 分析和代码仪器化
  - 来源: `npm package meriyah@7.0.0`
  - 许可证: ISC
  - 使用方式: UMD bundle 内嵌，通过动态导入加载

### 5.2 环境变量

| 变量名 | 用途 |
|-------|------|
| `CODEX_THREAD_ID` | 生成内部绑定盐值，防止多线程命名冲突 |
| `CODEX_JS_TMP_DIR` | 临时目录路径，用于文件操作 |
| `HOME` | 用户主目录路径 |
| `CODEX_JS_REPL_NODE_MODULE_DIRS` | 额外的 node_modules 搜索路径 |

### 5.3 Rust 端交互

#### 启动参数
```rust
// mod.rs:1031-1043
let spec = CommandSpec {
    program: node_path,
    args: vec![
        "--experimental-vm-modules".to_string(),  // 启用 VM 模块实验特性
        kernel_path.to_string_lossy().to_string(),
    ],
    cwd: turn.cwd.clone(),
    env,  // 包含上述环境变量
    // ...
};
```

#### 沙箱集成
- 通过 `SandboxManager` 配置执行环境
- 支持 Seatbelt (macOS)、Landlock/bubblewrap (Linux) 等沙箱技术
- 文件系统和网络访问受 `turn.file_system_sandbox_policy` 和 `turn.network_sandbox_policy` 控制

---

## 6. 风险、边界与改进建议

### 6.1 安全风险

#### 当前防护措施
| 风险 | 防护措施 |
|-----|---------|
| 访问 process 对象 | 从上下文中移除，deniedBuiltinModules 拦截 |
| 子进程执行 | child_process 模块被禁止导入 |
| Worker 线程 | worker_threads 模块被禁止导入 |
| 文件系统逃逸 | 通过沙箱策略限制，模块解析限制在指定搜索路径 |

#### 潜在风险点
1. **VM 逃逸**: Node.js vm 模块并非完全隔离，存在已知逃逸技术
2. **原型链污染**: 共享的上下文对象可能受到原型链污染攻击
3. **资源耗尽**: 无限循环或内存耗尽攻击（依赖超时机制）
4. **信息泄露**: 错误消息可能泄露敏感路径信息

### 6.2 边界情况

#### 已处理的边界
- **失败 Cell 状态恢复**: 精细的 binding 级别状态跟踪
- **循环变量**: 仅当循环体实际执行时才标记为已提交
- **逻辑赋值运算符**: `&&=`, `||=`, `??=` 的短路行为正确处理
- **函数 toString**: 保持原始源代码，不包含仪器化代码

#### 已知限制
1. **嵌套作用域**: 不支持嵌套块级作用域中的 var 写入恢复
   ```javascript
   { x = 1; }  // 不支持
   var x;
   ```

2. **空循环**: `for (var x of [])` 不会创建 binding，因为循环体从未执行

3. **静态导入限制**: 除 `@prev` 外，顶层静态导入被禁止，需使用动态导入

4. **目录导入**: 不支持 `import "./folder"`，必须是具体文件

5. **模块缓存**: 本地文件模块在 cell 间缓存，npm 模块全局缓存

### 6.3 改进建议

#### 高优先级
1. **增强 VM 隔离**
   - 考虑使用 `vm.Script` 的 `createContext` 配合更严格的选项
   - 评估使用 `isolated-vm` 包实现真正的 V8 隔离

2. **改进错误报告**
   - 添加源映射支持，将仪器化代码的错误映射回原始代码
   - 提供更清晰的堆栈跟踪信息

3. **性能优化**
   - 缓存已解析的 AST，避免重复解析
   - 对频繁使用的模块实现预编译

#### 中优先级
4. **TypeScript 支持**
   - 集成 TypeScript 编译器或 SWC 进行实时转译
   - 添加类型定义文件支持

5. **调试支持**
   - 实现 `debugger;` 语句支持
   - 添加与 Chrome DevTools 的集成

6. **模块热重载**
   - 开发模式下支持文件变更自动重载
   - 提供更细粒度的模块缓存控制

#### 低优先级
7. **REPL 增强**
   - 添加命令历史记录
   - 支持多行输入编辑
   - 添加自动补全功能

8. **可观测性**
   - 添加执行指标收集（CPU/内存使用）
   - 实现更详细的日志记录

### 6.4 测试覆盖

当前测试位于:
- `mod_tests.rs`: 单元测试，测试解析、仪器化逻辑
- `handlers/js_repl_tests.rs`: 处理器测试
- `tests/suite/js_repl.rs`: 集成测试，端到端场景

建议增加:
- 安全渗透测试套件
- 性能基准测试
- 模糊测试 (fuzzing) 发现边界情况

---

## 7. 总结

`kernel.js` 是 Codex JavaScript REPL 功能的核心，通过精巧的 AST 仪器化和 VM 隔离技术，在保持 REPL 交互体验的同时提供了合理的安全边界。其状态持久化机制允许跨 cell 的变量传递，而失败恢复机制确保了部分失败时的状态一致性。

代码结构清晰，职责分离明确：
- **解析层**: meriyah 负责 AST 分析
- **仪器化层**: 代码转换和标记插入
- **执行层**: VM 模块负责实际运行
- **协议层**: JSONL 通信桥接 Rust 主机

理解该文件对于维护和扩展 JavaScript REPL 功能至关重要。
