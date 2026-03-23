# runner.cjs 研究文档

## 场景与职责

`runner.cjs` 是 Code Mode 的 **Node.js 运行时核心**，负责在隔离的 VM 环境中执行用户 JavaScript 代码。它是一个完整的 JavaScript 运行时实现，包含主进程协议处理、Worker 线程管理、VM 模块执行等多个子系统。

**核心定位**：
- 主进程：处理与 Rust 端的 JSON 行协议通信
- Worker 管理：创建和管理执行用户代码的 Worker 线程
- VM 执行：在隔离上下文中安全执行 JavaScript
- 工具桥接：将 JavaScript 工具调用转发到 Rust 端

## 功能点目的

### 1. 协议层（createProtocol）
```javascript
function createProtocol() {
  const rl = readline.createInterface({ input: process.stdin, ... });
  // 处理 start, poll, terminate, response 消息
  // 管理 pending 请求和 sessions
}
```
- 通过 stdin/stdout 与 Rust 端进行 JSON 行协议通信
- 管理会话生命周期（start → running → complete）
- 处理工具调用响应路由

### 2. Worker 执行层（codeModeWorkerMain）
Worker 线程中执行的核心逻辑：
- 创建 VM 上下文（`vm.createContext`）
- 加载用户代码为 ES 模块（`SourceTextModule`）
- 提供工具调用能力（`createToolCaller`）
- 管理内容项收集（`createContentItems`）

### 3. 模块系统
支持多种模块导入：
- `tools.js`：全局工具命名空间
- `@openai/code_mode` / `openai/code_mode`：Code Mode 辅助函数
- `tools/{namespace}.js`：命名空间工具（如 MCP 工具）

### 4. 辅助函数（createCodeModeHelpers）
提供给用户代码的全局 API：
- `text(value)`：添加文本输出
- `image(value)`：添加图像输出
- `store(key, value)` / `load(key)`：键值存储
- `notify(value)`：发送即时通知
- `yield_control()`：主动让出控制权
- `exit()`：终止执行

### 5. 让出控制机制
- `initial_yield_timer`：初始执行后的定时让出
- `poll_yield_timer`：轮询时的定时让出
- 支持脚本主动调用 `yield_control()`

## 具体技术实现

### 文件结构
```
runner.cjs
├── 工具函数
│   ├── normalizeMaxOutputTokensPerExecCall
│   ├── normalizeYieldTime
│   ├── formatErrorText
│   ├── cloneJsonValue
│   └── clearTimer
├── codeModeWorkerMain (Worker 入口)
│   ├── createToolCaller
│   ├── createContentItems
│   ├── createGlobalToolsNamespace
│   ├── createModuleToolsNamespace
│   ├── createAllToolsMetadata
│   ├── createToolsModule
│   ├── ensureContentItems
│   ├── serializeOutputText
│   ├── normalizeOutputImage
│   ├── createCodeModeHelpers
│   ├── createCodeModeModule
│   ├── createBridgeRuntime
│   ├── namespacesMatch
│   ├── createNamespacedToolsNamespace
│   ├── createNamespacedToolsModule
│   ├── createModuleResolver
│   ├── resolveDynamicModule
│   ├── runModule
│   └── main (Worker 主函数)
├── createProtocol (主进程协议)
├── sessionWorkerSource
├── startSession
├── handleWorkerMessage
├── forwardToolCall
├── sendYielded
├── scheduleInitialYield
├── schedulePollYield
├── completeSession
├── terminateSession
└── main (进程入口)
```

### 关键流程详解

#### 会话启动流程
```javascript
function startSession(protocol, sessions, start) {
  // 1. 验证 tool_call_id
  // 2. 规范化 max_output_tokens（默认 10000）
  // 3. 规范化 yield_time（默认来自参数或 10000ms）
  // 4. 创建 session 对象
  const session = {
    completed: false,
    content_items: [],
    default_yield_time_ms: ...,
    id: start.cell_id,
    initial_yield_time_ms: ...,
    initial_yield_timer: null,
    initial_yield_triggered: false,
    max_output_tokens_per_exec_call: ...,
    pending_result: null,
    poll_yield_timer: null,
    request_id: String(start.request_id),
    worker: new Worker(sessionWorkerSource(), { eval: true, workerData: start }),
  };
  // 5. 注册事件处理器
  // 6. 保存到 sessions Map
}
```

#### Worker 执行流程
```javascript
async function main() {
  const start = workerData ?? {};
  const toolCallId = start.tool_call_id;
  const state = { storedValues: cloneJsonValue(start.stored_values ?? {}) };
  const callTool = createToolCaller();
  const enabledTools = start.enabled_tools ?? [];
  const contentItems = createContentItems();
  
  // 创建 VM 上下文
  const context = vm.createContext({ __codexContentItems: contentItems });
  const helpers = createCodeModeHelpers(context, state, toolCallId);
  
  // 注入运行时
  Object.defineProperty(context, '__codexRuntime', {
    value: createBridgeRuntime(callTool, enabledTools, helpers),
    ...
  });
  
  parentPort.postMessage({ type: 'started' });
  
  try {
    await runModule(context, start, callTool, helpers);
    parentPort.postMessage({ type: 'result', stored_values: state.storedValues });
  } catch (error) {
    if (isCodeModeExitSignal(error)) {
      parentPort.postMessage({ type: 'result', stored_values: state.storedValues });
    } else {
      parentPort.postMessage({ type: 'result', stored_values: state.storedValues, error_text: formatErrorText(error) });
    }
  }
}
```

#### 工具调用流程
```javascript
function createToolCaller() {
  let nextId = 0;
  const pending = new Map();
  
  parentPort.on('message', (message) => {
    if (message.type === 'tool_response') {
      const entry = pending.get(message.id);
      pending.delete(message.id);
      entry.resolve(message.result ?? '');
    } else if (message.type === 'tool_response_error') {
      const entry = pending.get(message.id);
      pending.delete(message.id);
      entry.reject(new Error(message.error_text ?? 'tool call failed'));
    }
  });
  
  return (name, input) => {
    const id = 'msg-' + ++nextId;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      parentPort.postMessage({ type: 'tool_call', id, name: String(name), input });
    });
  };
}
```

### 模块解析器
```javascript
function createModuleResolver(context, callTool, enabledTools, helpers) {
  let toolsModule, codeModeModule;
  const namespacedModules = new Map();
  
  return function resolveModule(specifier) {
    if (specifier === 'tools.js') {
      toolsModule ??= createToolsModule(context, callTool, enabledTools);
      return toolsModule;
    }
    if (specifier === '@openai/code_mode' || specifier === 'openai/code_mode') {
      codeModeModule ??= createCodeModeModule(context, helpers);
      return codeModeModule;
    }
    const namespacedMatch = /^tools\/(.+)\.js$/.exec(specifier);
    if (namespacedMatch) {
      const namespace = namespacedMatch[1].split('/').filter(s => s.length > 0);
      const cacheKey = namespace.join('/');
      if (!namespacedModules.has(cacheKey)) {
        namespacedModules.set(cacheKey, createNamespacedToolsModule(context, callTool, enabledTools, namespace));
      }
      return namespacedModules.get(cacheKey);
    }
    throw new Error('Unsupported import in exec: ' + specifier);
  };
}
```

### 安全机制

1. **VM 隔离**
   ```javascript
   const context = vm.createContext({ __codexContentItems: contentItems });
   ```
   创建全新的 V8 上下文，与 Node.js 全局环境隔离

2. **模块限制**
   - 仅允许导入 `tools.js`、`@openai/code_mode`、`tools/{namespace}.js`
   - 其他导入抛出错误

3. **Console 禁用**
   在 bridge.js 中替换为空实现

4. **超时控制**
   - `initial_yield_timer`：防止脚本无限运行
   - `poll_yield_timer`：轮询时再次触发让出

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/runner.cjs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/process.rs`
  - `spawn_code_mode_process()` 通过 `--eval` 执行此文件内容
  - 常量 `CODE_MODE_RUNNER_SOURCE` 嵌入此文件

### 与 bridge.js 的关系
- `runner.cjs` 创建 VM 上下文并注入 `__codexRuntime`
- `bridge.js` 消费 `__codexRuntime` 并暴露为用户友好的全局 API
- `runner.cjs` 中的 `createBridgeRuntime` 创建运行时对象

### 协议对应
| runner.cjs | protocol.rs |
|-----------|-------------|
| `type: 'start'` | `HostToNodeMessage::Start` |
| `type: 'poll'` | `HostToNodeMessage::Poll` |
| `type: 'terminate'` | `HostToNodeMessage::Terminate` |
| `type: 'response'` | `HostToNodeMessage::Response` |
| `type: 'tool_call'` | `NodeToHostMessage::ToolCall` |
| `type: 'notify'` | `NodeToHostMessage::Notify` |
| `type: 'yielded'` | `NodeToHostMessage::Yielded` |
| `type: 'terminated'` | `NodeToHostMessage::Terminated` |
| `type: 'result'` | `NodeToHostMessage::Result` |

## 依赖与外部交互

### Node.js 内置模块
| 模块 | 用途 |
|------|------|
| `readline` | 逐行读取 stdin |
| `worker_threads` | 创建 Worker 线程 |
| `vm` | 创建 VM 上下文和模块 |

### 从 Rust 端接收的数据
| 字段 | 类型 | 用途 |
|------|------|------|
| `request_id` | string | 请求标识 |
| `cell_id` | string | cell 标识 |
| `tool_call_id` | string | 原始工具调用 ID |
| `default_yield_time_ms` | number | 默认让出时间 |
| `enabled_tools` | Array | 可用工具列表 |
| `stored_values` | object | 存储的键值对 |
| `source` | string | 用户 JavaScript 代码 |
| `yield_time_ms` | number? | 自定义让出时间 |
| `max_output_tokens` | number? | 最大输出 token 数 |

### 向 Rust 端发送的数据
| 类型 | 字段 | 用途 |
|------|------|------|
| `started` | - | Worker 启动完成 |
| `content_item` | item | 新内容项 |
| `yield` | - | 主动让出控制 |
| `notify` | call_id, text | 即时通知 |
| `tool_call` | id, name, input | 工具调用请求 |
| `result` | stored_values, error_text? | 执行结果 |

## 风险、边界与改进建议

### 风险点

1. **VM 逃逸风险**
   - 虽然使用 `vm` 模块，但历史上存在逃逸漏洞
   - 需要持续跟进 Node.js 安全更新

2. **无限循环**
   - `yield_time_ms` 是协作式让出，恶意代码可以忽略
   - 需要配合 Rust 端的整体超时或进程终止

3. **内存泄漏**
   - `namespacedModules` 使用 Map 缓存，可能无限增长
   - Worker 线程的 `pending` Map 在异常情况下可能残留

4. **错误信息泄露**
   - `formatErrorText` 包含完整堆栈跟踪
   - 可能泄露内部实现细节

### 边界情况

1. **空 enabled_tools**
   ```javascript
   const enabledTools = start.enabled_tools ?? [];
   ```
   正确处理空数组

2. **无效模块导入**
   ```javascript
   throw new Error('Unsupported import in exec: ' + specifier);
   ```
   抛出清晰错误

3. **Worker 异常退出**
   ```javascript
   session.worker.on('exit', (code) => {
     if (code !== 0 && !session.completed) {
       // 发送错误结果
     }
   });
   ```
   检测并处理异常退出

4. **stdin 关闭**
   ```javascript
   rl.on('close', () => {
     // 清理所有资源
   });
   ```
   优雅处理连接断开

### 改进建议

1. **添加严格模式验证**
   ```javascript
   'use strict';
   // 已在文件开头添加，确保严格模式
   ```

2. **限制内容项数量**
   ```javascript
   function createContentItems() {
     const contentItems = [];
     const MAX_ITEMS = 1000;
     contentItems.push = (...items) => {
       if (contentItems.length + items.length > MAX_ITEMS) {
         throw new Error('Maximum content items exceeded');
       }
       // ...
     };
   }
   ```

3. **工具调用超时**
   ```javascript
   function createToolCaller(timeoutMs = 60000) {
     return (name, input) => {
       return new Promise((resolve, reject) => {
         const timer = setTimeout(() => {
           pending.delete(id);
           reject(new Error('Tool call timeout'));
         }, timeoutMs);
         // ...
       });
     };
   }
   ```

4. **更好的错误分类**
   ```javascript
   class CodeModeError extends Error {
     constructor(type, message) {
       super(message);
       this.type = type; // 'user', 'system', 'timeout'
     }
   }
   ```

5. **Source Map 支持**
   - 为错误堆栈提供原始代码位置
   - 便于调试经过模板替换的代码

6. **性能优化**
   - 缓存已编译的模块
   - 重用 Worker 线程（当前每次执行创建新 Worker）

7. **测试覆盖**
   - 当前无直接测试
   - 建议添加单元测试，使用 Node.js 的 `vm` 模块模拟
