# sdk/typescript/src 深度研究文档

## 目录

1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 定位与目标

`sdk/typescript/src` 是 OpenAI Codex 的 **TypeScript SDK** 源代码目录，作为 Node.js 应用程序与 Codex Rust CLI 之间的桥梁。其核心定位是：

- **嵌入式 SDK**：允许开发者将 Codex Agent 能力集成到自己的 TypeScript/JavaScript 应用程序中
- **进程包装器**：通过 spawn 子进程方式调用底层 Rust 实现的 `codex` CLI
- **事件流转换器**：将 CLI 输出的 JSONL 事件流转换为 TypeScript 友好的异步迭代器和类型定义

### 1.2 核心使用场景

```typescript
// 场景1: 简单对话
const codex = new Codex();
const thread = codex.startThread();
const turn = await thread.run("分析测试失败原因并提出修复建议");
console.log(turn.finalResponse);

// 场景2: 流式响应处理
const { events } = await thread.runStreamed("诊断问题");
for await (const event of events) {
  if (event.type === "item.completed") {
    console.log("完成项目:", event.item);
  }
}

// 场景3: 结构化输出
const turn = await thread.run("总结状态", {
  outputSchema: { type: "object", properties: { summary: { type: "string" } }, required: ["summary"] }
});
```

### 1.3 架构层级

```
┌─────────────────────────────────────────────────────────────┐
│                    用户应用程序 (User App)                    │
├─────────────────────────────────────────────────────────────┤
│  sdk/typescript/src (本目录)                                  │
│  ├── Codex (入口类)                                          │
│  ├── Thread (会话管理)                                       │
│  ├── CodexExec (CLI 进程管理)                                │
│  └── 类型定义 (events.ts, items.ts)                          │
├─────────────────────────────────────────────────────────────┤
│  codex-rs/exec (Rust CLI)                                   │
│  ├── exec_events.rs (事件定义)                              │
│  └── event_processor_with_jsonl_output.rs (JSONL 输出)       │
├─────────────────────────────────────────────────────────────┤
│  OpenAI API (Responses API)                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 核心功能模块

| 模块 | 文件 | 功能目的 |
|------|------|----------|
| **入口类** | `codex.ts` | 提供 `Codex` 主类，管理 CLI 进程生命周期，创建/恢复线程 |
| **会话管理** | `thread.ts` | 提供 `Thread` 类，管理多轮对话状态，支持流式/非流式调用 |
| **进程执行** | `exec.ts` | `CodexExec` 类封装 CLI spawn 逻辑，处理参数序列化和环境变量 |
| **事件类型** | `events.ts` | 定义完整的 TypeScript 事件类型系统，与 Rust 端保持同步 |
| **项目类型** | `items.ts` | 定义线程项目（ThreadItem）的联合类型，包括消息、命令执行、文件变更等 |
| **配置选项** | `codexOptions.ts`, `threadOptions.ts`, `turnOptions.ts` | 分层配置模型：全局/线程级/轮次级 |
| **输出模式** | `outputSchemaFile.ts` | 处理结构化输出的 JSON Schema 临时文件管理 |
| **模块导出** | `index.ts` | 统一导出公共 API |

### 2.2 事件系统架构

SDK 采用 **JSONL (JSON Lines)** 协议与 CLI 通信，事件分为两类：

**生命周期事件 (Turn Lifecycle)**:
- `thread.started` - 线程启动，携带 thread_id
- `turn.started` - 单轮开始
- `turn.completed` - 单轮成功完成，携带 token 使用量
- `turn.failed` - 单轮失败
- `error` - 致命错误

**项目事件 (Item Events)**:
- `item.started` - 项目开始（如命令执行、文件变更）
- `item.updated` - 项目状态更新（如 todo list 进度）
- `item.completed` - 项目完成

**项目类型 (ThreadItem)**:
- `agent_message` - Agent 文本响应
- `reasoning` - Agent 推理过程
- `command_execution` - 命令执行（含 stdout/stderr 聚合）
- `file_change` - 文件变更（add/delete/update）
- `mcp_tool_call` - MCP 工具调用
- `web_search` - 网络搜索
- `todo_list` - 任务清单
- `error` - 非致命错误

### 2.3 配置分层模型

```typescript
// 第一层: CodexOptions (全局级) - codex.ts 构造函数
interface CodexOptions {
  codexPathOverride?: string;  // CLI 路径覆盖
  baseUrl?: string;            // API 基础 URL
  apiKey?: string;             // API 密钥
  config?: CodexConfigObject;  // --config 覆盖
  env?: Record<string, string>; // 环境变量
}

// 第二层: ThreadOptions (线程级) - startThread()/resumeThread()
interface ThreadOptions {
  model?: string;
  sandboxMode?: SandboxMode;           // "read-only" | "workspace-write" | "danger-full-access"
  workingDirectory?: string;
  skipGitRepoCheck?: boolean;
  modelReasoningEffort?: ModelReasoningEffort; // "minimal" | "low" | "medium" | "high" | "xhigh"
  networkAccessEnabled?: boolean;
  webSearchMode?: WebSearchMode;       // "disabled" | "cached" | "live"
  webSearchEnabled?: boolean;          // 向后兼容
  approvalPolicy?: ApprovalMode;       // "never" | "on-request" | "on-failure" | "untrusted"
  additionalDirectories?: string[];
}

// 第三层: TurnOptions (轮次级) - run()/runStreamed()
interface TurnOptions {
  outputSchema?: unknown;      // 结构化输出 JSON Schema
  signal?: AbortSignal;        // 取消信号
}
```

---

## 具体技术实现

### 3.1 CLI 进程管理 (exec.ts)

#### 3.1.1 平台特定二进制定位

```typescript
// PLATFORM_PACKAGE_BY_TARGET 映射表
const PLATFORM_PACKAGE_BY_TARGET: Record<string, string> = {
  "x86_64-unknown-linux-musl": "@openai/codex-linux-x64",
  "aarch64-unknown-linux-musl": "@openai/codex-linux-arm64",
  "x86_64-apple-darwin": "@openai/codex-darwin-x64",
  "aarch64-apple-darwin": "@openai/codex-darwin-arm64",
  "x86_64-pc-windows-msvc": "@openai/codex-win32-x64",
  "aarch64-pc-windows-msvc": "@openai/codex-win32-arm64",
};
```

**定位算法** (`findCodexPath`):
1. 根据 `process.platform` 和 `process.arch` 确定 target triple
2. 解析 `@openai/codex/package.json` 路径
3. 通过 `createRequire` 定位平台特定包的路径
4. 最终路径: `<platformPkg>/vendor/<targetTriple>/codex/codex[.exe]`

#### 3.1.2 参数构建流程

```typescript
// 命令结构: codex exec --experimental-json [config flags] [options] [resume <threadId>] [--image <path>...]

async *run(args: CodexExecArgs): AsyncGenerator<string> {
  const commandArgs: string[] = ["exec", "--experimental-json"];
  
  // 1. 全局 config 覆盖 (来自 CodexOptions)
  if (this.configOverrides) {
    for (const override of serializeConfigOverrides(this.configOverrides)) {
      commandArgs.push("--config", override);
    }
  }
  
  // 2. 特定配置项
  if (args.baseUrl) commandArgs.push("--config", `openai_base_url=${toTomlValue(...)}`);
  if (args.model) commandArgs.push("--model", args.model);
  if (args.sandboxMode) commandArgs.push("--sandbox", args.sandboxMode);
  // ... 其他选项
  
  // 3. resume 参数 (必须在 image 之前)
  if (args.threadId) commandArgs.push("resume", args.threadId);
  
  // 4. image 参数
  if (args.images?.length) {
    for (const image of args.images) commandArgs.push("--image", image);
  }
}
```

#### 3.1.3 TOML 值序列化

配置覆盖使用 TOML 格式传递给 CLI：

```typescript
function toTomlValue(value: CodexConfigValue, path: string): string {
  if (typeof value === "string") return JSON.stringify(value);  // "value"
  if (typeof value === "number") return `${value}`;             // 123
  if (typeof value === "boolean") return value ? "true" : "false";
  if (Array.isArray(value)) return `[${value.map(...).join(", ")}]`;
  if (isPlainObject(value)) return `{${key} = ${value}, ...}`;
}

// 示例: { sandbox_workspace_write: { network_access: true } }
// 输出: --config sandbox_workspace_write.network_access=true
```

### 3.2 线程生命周期管理 (thread.ts)

#### 3.2.1 状态机

```
┌─────────────┐    run() / runStreamed()    ┌─────────────┐
│   Initial   │ ──────────────────────────> │   Running   │
│  (_id=null) │                             │  (有threadId)│
└─────────────┘                             └─────────────┘
                                                   │
                      ┌────────────────────────────┘
                      │ thread.started 事件
                      ▼
               ┌─────────────┐
               │   Active    │
               │ (持久化存储) │
               └─────────────┘
```

#### 3.2.2 流式处理实现

```typescript
async *runStreamedInternal(input: Input, turnOptions: TurnOptions): AsyncGenerator<ThreadEvent> {
  // 1. 创建临时 schema 文件
  const { schemaPath, cleanup } = await createOutputSchemaFile(turnOptions.outputSchema);
  
  try {
    // 2. 标准化输入 (支持 string | UserInput[])
    const { prompt, images } = normalizeInput(input);
    
    // 3. 启动 CLI 进程
    const generator = this._exec.run({
      input: prompt,
      images,
      threadId: this._id,  // null 表示新线程
      outputSchemaFile: schemaPath,
      signal: turnOptions.signal,
      // ... 其他选项
    });
    
    // 4. 迭代 JSONL 输出
    for await (const item of generator) {
      const parsed = JSON.parse(item) as ThreadEvent;
      
      // 5. 捕获 thread_id (首次响应)
      if (parsed.type === "thread.started") {
        this._id = parsed.thread_id;
      }
      
      yield parsed;
    }
  } finally {
    // 6. 清理临时文件
    await cleanup();
  }
}
```

#### 3.2.3 非流式封装

```typescript
async run(input: Input, turnOptions: TurnOptions = {}): Promise<Turn> {
  const generator = this.runStreamedInternal(input, turnOptions);
  const items: ThreadItem[] = [];
  let finalResponse = "";
  let usage: Usage | null = null;
  let turnFailure: ThreadError | null = null;
  
  for await (const event of generator) {
    switch (event.type) {
      case "item.completed":
        if (event.item.type === "agent_message") {
          finalResponse = event.item.text;
        }
        items.push(event.item);
        break;
      case "turn.completed":
        usage = event.usage;
        break;
      case "turn.failed":
        turnFailure = event.error;
        break;
    }
  }
  
  if (turnFailure) throw new Error(turnFailure.message);
  return { items, finalResponse, usage };
}
```

### 3.3 输入处理 (Input Normalization)

```typescript
type UserInput = 
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };

type Input = string | UserInput[];

function normalizeInput(input: Input): { prompt: string; images: string[] } {
  if (typeof input === "string") {
    return { prompt: input, images: [] };
  }
  
  const promptParts: string[] = [];
  const images: string[] = [];
  
  for (const item of input) {
    if (item.type === "text") promptParts.push(item.text);
    else if (item.type === "local_image") images.push(item.path);
  }
  
  return { prompt: promptParts.join("\n\n"), images };
}
```

### 3.4 结构化输出支持

```typescript
// outputSchemaFile.ts
export async function createOutputSchemaFile(schema: unknown): Promise<OutputSchemaFile> {
  if (schema === undefined) {
    return { cleanup: async () => {} };
  }
  
  // 1. 创建临时目录
  const schemaDir = await fs.mkdtemp(path.join(os.tmpdir(), "codex-output-schema-"));
  const schemaPath = path.join(schemaDir, "schema.json");
  
  // 2. 写入 schema
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  
  // 3. 返回清理函数
  return {
    schemaPath,
    cleanup: async () => {
      await fs.rm(schemaDir, { recursive: true, force: true });
    }
  };
}
```

### 3.5 进程环境管理

```typescript
const INTERNAL_ORIGINATOR_ENV = "CODEX_INTERNAL_ORIGINATOR_OVERRIDE";
const TYPESCRIPT_SDK_ORIGINATOR = "codex_sdk_ts";

// 环境变量优先级:
// 1. 显式传入的 env (完全替换 process.env)
// 2. 继承的 process.env (默认)
// 3. 注入的 CODEX_API_KEY (来自 CodexOptions)
// 4. 注入的 CODEX_INTERNAL_ORIGINATOR_OVERRIDE (标识 SDK 类型)

const env: Record<string, string> = {};
if (this.envOverride) {
  Object.assign(env, this.envOverride);  // 完全替换
} else {
  Object.assign(env, process.env);       // 继承
}
if (!env[INTERNAL_ORIGINATOR_ENV]) {
  env[INTERNAL_ORIGINATOR_ENV] = TYPESCRIPT_SDK_ORIGINATOR;
}
if (args.apiKey) {
  env.CODEX_API_KEY = args.apiKey;
}
```

---

## 关键代码路径与文件引用

### 4.1 核心文件结构

```
sdk/typescript/src/
├── index.ts              # 公共 API 导出
├── codex.ts              # Codex 主类 (入口)
├── thread.ts             # Thread 类 (会话管理)
├── exec.ts               # CodexExec 类 (CLI 进程)
├── events.ts             # 事件类型定义
├── items.ts              # ThreadItem 类型定义
├── codexOptions.ts       # CodexOptions 类型
├── threadOptions.ts      # ThreadOptions 类型
└── turnOptions.ts        # TurnOptions 类型
└── outputSchemaFile.ts   # 结构化输出文件管理
```

### 4.2 关键调用链

#### 4.2.1 创建线程并运行

```
new Codex(options) 
  └─> CodexExec(executablePath, env, config)
      └─> findCodexPath() [平台检测]

codex.startThread(threadOptions)
  └─> new Thread(exec, options, threadOptions, id?)

thread.run(input, turnOptions)
  └─> thread.runStreamedInternal(input, turnOptions)
      ├─> createOutputSchemaFile(turnOptions.outputSchema)
      ├─> normalizeInput(input) [处理 string | UserInput[]]
      └─> exec.run({...args, signal})
          ├─> spawn(codexPath, ["exec", "--experimental-json", ...flags])
          ├─> child.stdin.write(input)
          └─> yield* readline.createInterface(child.stdout)
      ├─> JSON.parse(line) as ThreadEvent
      ├─> 捕获 thread.started 设置 this._id
      └─> finally: cleanup() [删除临时 schema 文件]
```

#### 4.2.2 恢复线程

```
codex.resumeThread(id, threadOptions)
  └─> new Thread(exec, options, threadOptions, id)
      └─> thread.run(input)
          └─> exec.run({ threadId: id, ... })
              └─> spawn(..., [..., "resume", id, ...])
```

### 4.3 类型映射 (TypeScript ↔ Rust)

| TypeScript (events.ts/items.ts) | Rust (exec_events.rs) | 说明 |
|--------------------------------|----------------------|------|
| `ThreadEvent` | `ThreadEvent` | 顶层事件联合类型，使用 `#[serde(tag = "type")]` |
| `ThreadStartedEvent` | `ThreadStartedEvent` | thread.started 事件 |
| `TurnCompletedEvent` | `TurnCompletedEvent` | turn.completed 事件 |
| `ItemCompletedEvent` | `ItemCompletedEvent` | item.completed 事件 |
| `ThreadItem` | `ThreadItem` | 项目包装器，含 id 和 details |
| `AgentMessageItem` | `AgentMessageItem` | Agent 消息 |
| `CommandExecutionItem` | `CommandExecutionItem` | 命令执行状态 |
| `FileChangeItem` | `FileChangeItem` | 文件变更 |
| `McpToolCallItem` | `McpToolCallItem` | MCP 工具调用 |
| `Usage` | `Usage` | Token 使用量统计 |

**注意**: TypeScript SDK 的 `CollabToolCallItem` 类型在 Rust 端存在，但当前未在 `items.ts` 中导出。

### 4.4 测试文件结构

```
sdk/typescript/tests/
├── run.test.ts           # Thread.run() 集成测试
├── runStreamed.test.ts   # Thread.runStreamed() 测试
├── exec.test.ts          # CodexExec 单元测试 (使用 mock spawn)
├── abort.test.ts         # AbortSignal 取消测试
├── responsesProxy.ts     # Mock OpenAI API 服务器
├── codexExecSpy.ts       # spawn 调用监控工具
├── testCodex.ts          # 测试客户端工厂
└── setupCodexHome.ts     # Jest 全局 setup (隔离 CODEX_HOME)
```

---

## 依赖与外部交互

### 5.1 运行时依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `node:child_process` | Node.js 内置 | spawn CLI 进程 |
| `node:readline` | Node.js 内置 | 逐行读取 stdout |
| `node:path` | Node.js 内置 | 路径处理 |
| `node:fs` | Node.js 内置 | 临时 schema 文件 |
| `node:os` | Node.js 内置 | 临时目录 |
| `node:module` (createRequire) | Node.js 内置 | 解析平台包路径 |

**零外部运行时依赖** - SDK 仅依赖 Node.js 内置模块，确保轻量级和安全性。

### 5.2 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `@modelcontextprotocol/sdk` | ^1.24.0 | MCP 类型定义 (McpContentBlock) |
| `typescript` | ^5.9.2 | 编译 |
| `tsup` | ^8.5.0 | 打包 (ESM + 类型声明) |
| `jest` | ^29.7.0 | 测试框架 |
| `ts-jest` | ^29.3.4 | TypeScript 测试支持 |
| `@types/node` | ^20.19.18 | Node.js 类型 |

### 5.3 外部交互

#### 5.3.1 与 Rust CLI 交互

**协议**: JSONL over stdout/stdin

```
TypeScript SDK          codex CLI (Rust)
     │                         │
     │── spawn ───────────────>│
     │   [exec --experimental-json]
     │                         │
     │── input (stdin) ───────>│
     │   "用户提示文本"          │
     │                         │
     │<── JSONL (stdout) ──────│
     │   {"type":"thread.started","thread_id":"..."}
     │   {"type":"turn.started"}
     │   {"type":"item.completed",...}
     │   {"type":"turn.completed",...}
     │                         │
     │── close stdin ─────────>│
     │<── exit code ───────────│
```

#### 5.3.2 与平台包交互

SDK 依赖 `@openai/codex` 的 optionalDependencies 中的平台特定包：

```json
// @openai/codex/package.json (假设结构)
{
  "optionalDependencies": {
    "@openai/codex-linux-x64": "0.0.0",
    "@openai/codex-darwin-arm64": "0.0.0",
    // ... 其他平台
  }
}
```

平台包结构:
```
@openai/codex-<platform>/
└── vendor/
    └── <target-triple>/
        └── codex/
            └── codex[.exe]   # 实际二进制
```

#### 5.3.3 与 OpenAI API 交互

Rust CLI 直接调用 OpenAI Responses API，SDK 仅通过 CLI 间接交互：

```
SDK ──CLI──> OpenAI Responses API (/responses)
              - Server-Sent Events (SSE)
              - 流式返回 assistant 消息、工具调用等
```

---

## 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 进程管理风险

**风险**: CLI 进程异常退出可能导致资源泄漏

```typescript
// exec.ts:217-225
} finally {
  rl.close();
  child.removeAllListeners();
  try {
    if (!child.killed) child.kill();
  } catch {
    // ignore
  }
}
```

**缓解**: 使用 `finally` 块确保清理，但 `child.kill()` 可能抛出异常被静默捕获。

#### 6.1.2 临时文件风险

**风险**: `outputSchemaFile.ts` 的临时目录在异常情况下可能未清理

```typescript
// 当前实现: cleanup 在 finally 中调用，但进程崩溃时不会执行
try {
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  return { schemaPath, cleanup };
} catch (error) {
  await cleanup();  // 错误时清理
  throw error;
}
```

**缓解**: 考虑使用 `process.on('exit')` 钩子或定期清理机制。

#### 6.1.3 JSON 解析风险

**风险**: CLI 可能输出非 JSON 行（如 panic 信息），导致 `JSON.parse` 失败

```typescript
// thread.ts:99-103
try {
  parsed = JSON.parse(item) as ThreadEvent;
} catch (error) {
  throw new Error(`Failed to parse item: ${item}`, { cause: error });
}
```

**现状**: 会抛出错误终止迭代，但错误信息包含原始内容便于调试。

### 6.2 边界情况

#### 6.2.1 平台支持边界

```typescript
// exec.ts:317-365
function findCodexPath() {
  // 仅支持: linux(x64/arm64), darwin(x64/arm64), win32(x64/arm64)
  // 不支持: freebsd, android(非 musl), 32位系统
}
```

#### 6.2.2 输入大小边界

- 输入通过 `child.stdin.write()` 发送，受 Node.js stream 缓冲区限制
- 图片路径通过命令行参数传递，受操作系统命令行长度限制

#### 6.2.3 并发边界

- 单个 `Thread` 实例不支持并发 `run()` 调用（无内部锁）
- 但多个 `Thread` 实例可并发运行（每个独立进程）

### 6.3 改进建议

#### 6.3.1 类型安全增强

**建议1**: 为 `outputSchema` 添加泛型支持

```typescript
// 当前
outputSchema?: unknown;

// 建议
outputSchema?: T;
run<T = string>(input: Input, turnOptions: TurnOptions & { outputSchema?: JSONSchemaType<T> }): Promise<Turn & { finalResponse: T }>;
```

**建议2**: 导出 `CollabToolCallItem` 类型

```typescript
// index.ts 添加
export type { CollabToolCallItem } from "./items";
```

#### 6.3.2 错误处理改进

**建议**: 定义专用错误类

```typescript
export class CodexError extends Error {
  constructor(
    message: string,
    public readonly code: 'PARSE_ERROR' | 'PROCESS_EXIT' | 'TURN_FAILED',
    public readonly cause?: unknown
  ) {
    super(message);
  }
}
```

#### 6.3.3 可观测性增强

**建议**: 添加日志/调试接口

```typescript
export interface CodexLogger {
  debug?(message: string, ...args: unknown[]): void;
  info?(message: string, ...args: unknown[]): void;
  error?(message: string, ...args: unknown[]): void;
}

export type CodexOptions = {
  // ... existing options
  logger?: CodexLogger;
};
```

#### 6.3.4 进程管理优化

**建议**: 添加健康检查/心跳机制

```typescript
// 在长时间运行的线程中，CLI 可能无响应
// 可考虑添加超时检测
const HEALTH_CHECK_INTERVAL = 30000; // 30s
```

#### 6.3.5 配置验证

**建议**: 在 SDK 层验证配置值

```typescript
// 当前: 直接传递给 CLI，错误延迟到运行时
// 建议: 使用 zod 等库在构造时验证
const SandboxModeSchema = z.enum(['read-only', 'workspace-write', 'danger-full-access']);
```

### 6.4 技术债务

| 位置 | 问题 | 优先级 |
|------|------|--------|
| `exec.ts:247-250` | `handle_output_chunk` TODO 未实现 | 低 |
| `exec.ts:252-258` | `handle_terminal_interaction` TODO 未实现 | 低 |
| `run.test.ts:772` | 硬编码超时 `10000` 需移除 | 低 |
| `items.ts` | `CollabToolCallItem` 未导出 | 中 |
| `events.ts` | 缺少与 Rust 的 `ts_rs` 生成类型同步机制 | 中 |

---

## 附录

### A. 版本信息

- **当前版本**: 0.0.0-dev (开发中)
- **Node.js 要求**: >= 18
- **模块格式**: ESM only
- **TypeScript**: 5.9.2

### B. 相关文档

- `sdk/typescript/README.md` - 用户文档和快速开始
- `codex-rs/exec/src/exec_events.rs` - Rust 端事件定义（权威来源）
- `codex-rs/exec/src/event_processor_with_jsonl_output.rs` - JSONL 输出生成器

### C. 构建命令

```bash
cd sdk/typescript
pnpm install
pnpm build      # tsup 打包
pnpm test       # Jest 测试
pnpm lint       # ESLint 检查
```

---

*文档生成时间: 2026-03-22*
*基于 commit: 当前工作目录*
