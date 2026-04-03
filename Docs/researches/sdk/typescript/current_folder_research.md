# TypeScript SDK 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

TypeScript SDK (`@openai/codex-sdk`) 是 Codex CLI 的 JavaScript/TypeScript 封装层，允许开发者将 Codex Agent 嵌入到 Node.js 应用、Electron 应用或其他 TypeScript/JavaScript 工作流中。

**核心职责：**
- 提供声明式 API 与 Codex Agent 交互（Thread/Turn 模型）
- 管理 Codex CLI 子进程的生命周期
- 处理 JSONL 事件流的解析与转换
- 支持同步（`run()`）和流式（`runStreamed()`）两种调用模式
- 提供结构化输出（JSON Schema）支持

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| 自动化工作流 | CI/CD 管道中集成 Codex 进行代码审查、生成 |
| 嵌入式应用 | Electron 应用中集成 AI 辅助功能 |
| 批处理脚本 | 批量处理文件、生成代码、执行分析 |
| 交互式工具 | 构建自定义的交互式 CLI 工具 |
| 服务端集成 | Node.js 服务端调用 Codex 处理请求 |

### 1.3 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    用户应用 (User App)                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              @openai/codex-sdk                       │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────────────┐  │   │
│  │  │  Codex  │  │ Thread  │  │    CodexExec        │  │   │
│  │  │  类     │  │  类     │  │    (子进程管理)      │  │   │
│  │  └────┬────┘  └────┬────┘  └──────────┬──────────┘  │   │
│  │       └─────────────┴──────────────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
└───────────────────────────┬─────────────────────────────────┘
                            │ spawn
┌───────────────────────────▼─────────────────────────────────┐
│              @openai/codex (CLI 包)                         │
│         ┌─────────────────────────┐                         │
│         │   bin/codex.js (入口)   │                         │
│         └───────────┬─────────────┘                         │
│                     │ resolve                                 │
│         ┌───────────▼─────────────┐                         │
│         │  平台特定二进制 (Rust)   │                         │
│         │  @openai/codex-<platform>                          │
│         └─────────────────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能模块

#### 2.1.1 Codex 类（入口类）

**文件：** `src/codex.ts`

**职责：**
- SDK 的主入口点
- 管理全局配置（API Key、Base URL、环境变量）
- 创建和恢复 Thread 实例

**关键方法：**
```typescript
// 创建新会话
startThread(options?: ThreadOptions): Thread

// 恢复已有会话
resumeThread(id: string, options?: ThreadOptions): Thread
```

#### 2.1.2 Thread 类（会话管理）

**文件：** `src/thread.ts`

**职责：**
- 代表与 Agent 的一个持续对话会话
- 管理多轮对话（Turn）的状态
- 提供同步和流式两种执行模式

**关键方法：**
```typescript
// 同步执行，等待完整响应
async run(input: Input, turnOptions?: TurnOptions): Promise<Turn>

// 流式执行，实时获取事件
async runStreamed(input: Input, turnOptions?: TurnOptions): Promise<StreamedTurn>

// 获取线程 ID（首次 turn 后可用）
get id(): string | null
```

#### 2.1.3 CodexExec 类（CLI 执行层）

**文件：** `src/exec.ts`

**职责：**
- 负责实际 spawn Codex CLI 子进程
- 构建命令行参数
- 处理 stdin/stdout/stderr 流
- 解析 JSONL 输出

**核心机制：**
```typescript
async *run(args: CodexExecArgs): AsyncGenerator<string>
```

使用生成器模式逐行 yield CLI 输出的 JSONL 事件。

### 2.2 配置系统

#### 2.2.1 CodexOptions（全局配置）

**文件：** `src/codexOptions.ts`

```typescript
type CodexOptions = {
  codexPathOverride?: string;  // 自定义 CLI 路径
  baseUrl?: string;            // API 基础 URL
  apiKey?: string;             // OpenAI API Key
  config?: CodexConfigObject;  // CLI 配置覆盖
  env?: Record<string, string>; // 自定义环境变量
}
```

#### 2.2.2 ThreadOptions（线程级配置）

**文件：** `src/threadOptions.ts`

```typescript
type ThreadOptions = {
  model?: string;                    // 模型选择
  sandboxMode?: SandboxMode;         // 沙箱模式
  workingDirectory?: string;         // 工作目录
  skipGitRepoCheck?: boolean;        // 跳过 Git 检查
  modelReasoningEffort?: ModelReasoningEffort; // 推理努力程度
  networkAccessEnabled?: boolean;    // 网络访问
  webSearchMode?: WebSearchMode;     // 搜索模式
  webSearchEnabled?: boolean;        // 搜索开关（legacy）
  approvalPolicy?: ApprovalMode;     // 审批策略
  additionalDirectories?: string[];  // 附加目录
}
```

#### 2.2.3 TurnOptions（单次调用配置）

**文件：** `src/turnOptions.ts`

```typescript
type TurnOptions = {
  outputSchema?: unknown;    // JSON Schema 结构化输出
  signal?: AbortSignal;      // 取消信号
}
```

### 2.3 事件系统

**文件：** `src/events.ts`

事件系统基于 Rust 端的 `exec_events.rs` 设计，采用 tagged union 模式：

```typescript
type ThreadEvent =
  | ThreadStartedEvent      // thread.started
  | TurnStartedEvent        // turn.started
  | TurnCompletedEvent      // turn.completed
  | TurnFailedEvent         // turn.failed
  | ItemStartedEvent        // item.started
  | ItemUpdatedEvent        // item.updated
  | ItemCompletedEvent      // item.completed
  | ThreadErrorEvent;       // error
```

### 2.4 Item 类型系统

**文件：** `src/items.ts`

表示 Agent 执行过程中的各种产出物：

```typescript
type ThreadItem =
  | AgentMessageItem      // Agent 文本响应
  | ReasoningItem         // 推理过程
  | CommandExecutionItem  // 命令执行
  | FileChangeItem        // 文件变更
  | McpToolCallItem       // MCP 工具调用
  | WebSearchItem         // 网络搜索
  | TodoListItem          // 待办列表
  | ErrorItem;            // 错误信息
```

---

## 3. 具体技术实现

### 3.1 CLI 子进程管理

#### 3.1.1 二进制定位逻辑

**文件：** `src/exec.ts` (lines 317-389)

```typescript
function findCodexPath() {
  // 1. 确定目标平台三元组
  const targetTriple = determineTargetTriple();
  
  // 2. 映射到 npm 包名
  const platformPackage = PLATFORM_PACKAGE_BY_TARGET[targetTriple];
  // 例如: "aarch64-apple-darwin" -> "@openai/codex-darwin-arm64"
  
  // 3. 通过 require.resolve 定位包路径
  const codexPackageJsonPath = moduleRequire.resolve("@openai/codex/package.json");
  const codexRequire = createRequire(codexPackageJsonPath);
  const platformPackageJsonPath = codexRequire.resolve(`${platformPackage}/package.json`);
  
  // 4. 构建二进制路径
  const vendorRoot = path.join(path.dirname(platformPackageJsonPath), "vendor");
  const binaryPath = path.join(vendorRoot, targetTriple, "codex", binaryName);
}
```

**支持的平台：**
| 平台 | 架构 | npm 包名 |
|------|------|----------|
| Linux | x64 | @openai/codex-linux-x64 |
| Linux | arm64 | @openai/codex-linux-arm64 |
| macOS | x64 | @openai/codex-darwin-x64 |
| macOS | arm64 | @openai/codex-darwin-arm64 |
| Windows | x64 | @openai/codex-win32-x64 |
| Windows | arm64 | @openai/codex-win32-arm64 |

#### 3.1.2 命令行参数构建

**文件：** `src/exec.ts` (lines 72-145)

```typescript
async *run(args: CodexExecArgs): AsyncGenerator<string> {
  const commandArgs: string[] = ["exec", "--experimental-json"];
  
  // 1. 全局配置覆盖（先添加）
  if (this.configOverrides) {
    for (const override of serializeConfigOverrides(this.configOverrides)) {
      commandArgs.push("--config", override);
    }
  }
  
  // 2. 特定参数（后添加，可覆盖全局配置）
  if (args.baseUrl) {
    commandArgs.push("--config", `openai_base_url=${toTomlValue(args.baseUrl)}`);
  }
  if (args.model) commandArgs.push("--model", args.model);
  if (args.sandboxMode) commandArgs.push("--sandbox", args.sandboxMode);
  if (args.workingDirectory) commandArgs.push("--cd", args.workingDirectory);
  if (args.outputSchemaFile) commandArgs.push("--output-schema", args.outputSchemaFile);
  // ... 更多参数
  
  // 3. 恢复会话
  if (args.threadId) {
    commandArgs.push("resume", args.threadId);
  }
  
  // 4. 图片参数（必须在 resume 之后）
  if (args.images?.length) {
    for (const image of args.images) {
      commandArgs.push("--image", image);
    }
  }
}
```

#### 3.1.3 子进程生命周期管理

```typescript
const child = spawn(this.executablePath, commandArgs, {
  env,           // 自定义环境变量
  signal: args.signal,  // 支持 AbortSignal
});

// 写入输入
child.stdin.write(args.input);
child.stdin.end();

// 读取输出
const rl = readline.createInterface({
  input: child.stdout,
  crlfDelay: Infinity,
});

for await (const line of rl) {
  yield line;  // 逐行 yield JSONL
}
```

### 3.2 TOML 配置序列化

**文件：** `src/exec.ts` (lines 229-315)

CLI 使用 TOML 格式接收 `--config key=value` 参数。SDK 需要将 JSON 配置对象转换为 TOML：

```typescript
// 输入
config = {
  approval_policy: "never",
  sandbox_workspace_write: { network_access: true },
  tool_rules: { allow: ["git status", "git diff"] }
}

// 输出
[
  'approval_policy="never"',
  'sandbox_workspace_write.network_access=true',
  'tool_rules.allow=["git status", "git diff"]'
]
```

**关键函数：**
- `serializeConfigOverrides()`: 入口函数
- `flattenConfigOverrides()`: 递归扁平化嵌套对象
- `toTomlValue()`: 值类型到 TOML 的转换
- `formatTomlKey()`: 键名格式化（bare key vs quoted key）

### 3.3 结构化输出支持

**文件：** `src/outputSchemaFile.ts`

当用户传入 `outputSchema` 时，SDK 需要：

1. 创建临时目录
2. 将 JSON Schema 写入文件
3. 传递 `--output-schema <path>` 给 CLI
4. 执行完成后清理临时文件

```typescript
export async function createOutputSchemaFile(schema: unknown): Promise<OutputSchemaFile> {
  const schemaDir = await fs.mkdtemp(path.join(os.tmpdir(), "codex-output-schema-"));
  const schemaPath = path.join(schemaDir, "schema.json");
  
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  
  return {
    schemaPath,
    cleanup: async () => {
      await fs.rm(schemaDir, { recursive: true, force: true });
    }
  };
}
```

### 3.4 输入处理

**文件：** `src/thread.ts` (lines 141-155)

支持两种输入格式：

```typescript
type Input = string | UserInput[];

type UserInput =
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };
```

处理逻辑：
```typescript
function normalizeInput(input: Input): { prompt: string; images: string[] } {
  if (typeof input === "string") {
    return { prompt: input, images: [] };
  }
  
  const promptParts: string[] = [];
  const images: string[] = [];
  
  for (const item of input) {
    if (item.type === "text") {
      promptParts.push(item.text);
    } else if (item.type === "local_image") {
      images.push(item.path);
    }
  }
  
  return { prompt: promptParts.join("\n\n"), images };
}
```

### 3.5 流式事件处理

**文件：** `src/thread.ts` (lines 70-112)

```typescript
private async *runStreamedInternal(
  input: Input,
  turnOptions: TurnOptions = {},
): AsyncGenerator<ThreadEvent> {
  // 1. 准备输出 schema 临时文件
  const { schemaPath, cleanup } = await createOutputSchemaFile(turnOptions.outputSchema);
  
  try {
    // 2. 调用 exec 生成器
    const generator = this._exec.run({ /* args */ });
    
    for await (const item of generator) {
      // 3. 解析 JSONL
      const parsed = JSON.parse(item) as ThreadEvent;
      
      // 4. 捕获 thread_id
      if (parsed.type === "thread.started") {
        this._id = parsed.thread_id;
      }
      
      yield parsed;
    }
  } finally {
    // 5. 清理临时文件
    await cleanup();
  }
}
```

### 3.6 同步执行封装

**文件：** `src/thread.ts` (lines 114-138)

`run()` 方法基于 `runStreamed()` 构建，聚合所有事件：

```typescript
async run(input: Input, turnOptions: TurnOptions = {}): Promise<Turn> {
  const generator = this.runStreamedInternal(input, turnOptions);
  const items: ThreadItem[] = [];
  let finalResponse: string = "";
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
  
  if (turnFailure) {
    throw new Error(turnFailure.message);
  }
  
  return { items, finalResponse, usage };
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源代码文件清单

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/index.ts` | 40 | 公共 API 导出 |
| `src/codex.ts` | 39 | 主入口类 |
| `src/codexOptions.ts` | 22 | 全局配置类型 |
| `src/thread.ts` | 155 | 线程/会话管理 |
| `src/threadOptions.ts` | 20 | 线程配置类型 |
| `src/turnOptions.ts` | 6 | 单次调用配置 |
| `src/exec.ts` | 389 | CLI 执行核心 |
| `src/events.ts` | 80 | 事件类型定义 |
| `src/items.ts` | 127 | Item 类型定义 |
| `src/outputSchemaFile.ts` | 40 | 结构化输出文件管理 |

### 4.2 测试文件清单

| 文件 | 行数 | 测试范围 |
|------|------|----------|
| `tests/run.test.ts` | 807 | run() 方法完整测试 |
| `tests/runStreamed.test.ts` | 207 | runStreamed() 测试 |
| `tests/exec.test.ts` | 146 | CodexExec 单元测试 |
| `tests/abort.test.ts` | 165 | AbortSignal 支持测试 |
| `tests/testCodex.ts` | 94 | 测试辅助函数 |
| `tests/responsesProxy.ts` | 225 | Mock OpenAI API 服务器 |
| `tests/codexExecSpy.ts` | 37 | spawn 调用监控 |
| `tests/setupCodexHome.ts` | 28 | 测试环境初始化 |

### 4.3 关键代码路径

#### 4.3.1 初始化流程

```
new Codex(options)
  └── new CodexExec(executablePath, env, configOverrides)
      └── findCodexPath()  // 平台检测 + 二进制定位
```

#### 4.3.2 创建 Thread 流程

```
codex.startThread(threadOptions)
  └── new Thread(exec, options, threadOptions, id?)
```

#### 4.3.3 执行 Turn 流程

```
thread.run(input, turnOptions)
  └── thread.runStreamedInternal(input, turnOptions)
      ├── createOutputSchemaFile(turnOptions.outputSchema)
      ├── normalizeInput(input)  // 处理 string | UserInput[]
      ├── exec.run(args)  // spawn CLI
      │   ├── build commandArgs
      │   ├── spawn(binaryPath, commandArgs)
      │   ├── write stdin
      │   └── yield* stdout lines (JSONL)
      ├── JSON.parse(line) -> ThreadEvent
      ├── capture thread_id from thread.started
      └── cleanup schema file
```

#### 4.3.4 恢复 Thread 流程

```
codex.resumeThread(id, options)
  └── new Thread(exec, options, threadOptions, id)
      // 后续 run() 会传递 threadId 给 exec
      // CLI 参数: codex exec --experimental-json resume <id>
```

### 4.4 CLI 协议详情

**命令格式：**
```bash
codex exec --experimental-json [options] [resume <thread_id>]
```

**输入：** 通过 stdin 传递用户 prompt

**输出：** JSON Lines (每行一个 JSON 对象)

**事件类型映射：**

| Rust 事件 | TypeScript 类型 | 说明 |
|-----------|-----------------|------|
| `thread.started` | `ThreadStartedEvent` | 会话开始，包含 thread_id |
| `turn.started` | `TurnStartedEvent` | 单轮开始 |
| `turn.completed` | `TurnCompletedEvent` | 单轮完成，包含 usage |
| `turn.failed` | `TurnFailedEvent` | 单轮失败 |
| `item.started` | `ItemStartedEvent` | Item 开始 |
| `item.updated` | `ItemUpdatedEvent` | Item 更新 |
| `item.completed` | `ItemCompletedEvent` | Item 完成 |
| `error` | `ThreadErrorEvent` | 致命错误 |

---

## 5. 依赖与外部交互

### 5.1 运行时依赖

**生产依赖：** 无（零依赖设计）

**说明：** SDK 仅使用 Node.js 内置模块：
- `node:child_process` - 子进程管理
- `node:path` - 路径处理
- `node:readline` - 行读取
- `node:module` - require 模拟
- `node:fs` - 文件系统（临时 schema 文件）
- `node:os` - 操作系统信息

### 5.2 开发依赖

| 包名 | 用途 |
|------|------|
| `@modelcontextprotocol/sdk` | MCP 类型定义 |
| `@types/jest` | Jest 类型 |
| `@types/node` | Node.js 类型 |
| `eslint` | 代码检查 |
| `jest` | 测试框架 |
| `prettier` | 代码格式化 |
| `ts-jest` | TypeScript 测试支持 |
| `tsup` | 构建工具 |
| `typescript` | 编译器 |
| `zod` | 测试中的 schema 验证 |
| `zod-to-json-schema` | Zod 到 JSON Schema 转换 |

### 5.3 外部 CLI 依赖

**必需：** `@openai/codex` 包及其平台特定依赖

```
@openai/codex
├── @openai/codex-darwin-arm64 (macOS ARM)
├── @openai/codex-darwin-x64   (macOS x64)
├── @openai/codex-linux-arm64  (Linux ARM)
├── @openai/codex-linux-x64    (Linux x64)
├── @openai/codex-win32-arm64  (Windows ARM)
└── @openai/codex-win32-x64    (Windows x64)
```

### 5.4 环境变量

**SDK 自动设置：**
| 变量 | 说明 |
|------|------|
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | 标识请求来源（`codex_sdk_ts`） |
| `CODEX_API_KEY` | API 密钥（如果提供） |

**可继承/覆盖：**
| 变量 | 说明 |
|------|------|
| `CODEX_HOME` | Codex 配置目录 |
| `OPENAI_BASE_URL` | API 基础 URL |
| 其他 `process.env` | 完整环境继承（除非指定 `env` 选项） |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 二进制定位失败

**风险：** 平台特定 npm 包未安装时，`findCodexPath()` 会抛出错误。

**错误信息：**
```
Unable to locate Codex CLI binaries. Ensure @openai/codex is installed with optional dependencies.
```

**缓解：** 清晰的错误提示，引导用户重新安装。

#### 6.1.2 临时文件泄漏

**风险：** `outputSchemaFile.ts` 创建的临时目录如果在 `cleanup()` 前进程崩溃，可能残留。

**当前处理：**
```typescript
try {
  await fs.writeFile(schemaPath, JSON.stringify(schema), "utf8");
  return { schemaPath, cleanup };
} catch (error) {
  await cleanup();  // 写入失败时立即清理
  throw error;
}
```

**建议：** 考虑使用 `process.on('exit')` 钩子做最终清理。

#### 6.1.3 JSON 解析错误

**风险：** CLI 输出非预期格式时，`JSON.parse()` 会抛出。

**当前处理：**
```typescript
try {
  parsed = JSON.parse(item) as ThreadEvent;
} catch (error) {
  throw new Error(`Failed to parse item: ${item}`, { cause: error });
}
```

#### 6.1.4 子进程僵尸

**风险：** 异常情况下子进程可能未被正确终止。

**当前处理：** `finally` 块中强制 `child.kill()`。

### 6.2 边界情况

#### 6.2.1 AbortSignal 支持

SDK 完整支持 `AbortSignal`：
- 传递给 `spawn()` 的 `signal` 选项
- 可在迭代事件流时随时取消

**测试覆盖：** `tests/abort.test.ts`

#### 6.2.2 空输入处理

```typescript
if (typeof input === "string") {
  return { prompt: input, images: [] };
}
// 空数组会返回 { prompt: "", images: [] }
```

#### 6.2.3 线程 ID 时机

`thread.id` 在首次 `run()` 调用前为 `null`，收到 `thread.started` 事件后才赋值。

### 6.3 改进建议

#### 6.3.1 类型安全增强

**现状：** `outputSchema` 使用 `unknown` 类型。

**建议：** 使用泛型支持类型推断：
```typescript
async run<T = string>(
  input: Input,
  turnOptions: TurnOptions & { outputSchema?: JSONSchema<T> }
): Promise<Turn<T>>
```

#### 6.3.2 重试机制

**现状：** 无内置重试，依赖 CLI 层。

**建议：** SDK 层添加可配置的重试策略（指数退避）。

#### 6.3.3 事件过滤

**现状：** 流式事件返回所有类型。

**建议：** 添加事件类型过滤选项：
```typescript
thread.runStreamed(input, {
  filter: ['item.completed', 'turn.completed']
})
```

#### 6.3.4 进度回调

**建议：** 为同步 `run()` 添加进度回调：
```typescript
thread.run(input, {
  onProgress: (event) => console.log(event.type)
})
```

#### 6.3.5 连接池/复用

**现状：** 每次 `run()` 都 spawn 新进程。

**建议：** 考虑长期运行的 CLI 守护进程模式（类似 LSP）。

#### 6.3.6 更好的错误类型

**现状：** 统一使用 `Error`。

**建议：** 定义专门的错误类：
```typescript
class CodexError extends Error {
  code: string;
  threadId?: string;
}
class CodexExecError extends CodexError {
  exitCode: number;
  stderr: string;
}
```

#### 6.3.7 日志/调试支持

**现状：** 无内置日志。

**建议：** 添加可选的日志回调：
```typescript
new Codex({
  logger: {
    debug: (msg) => console.debug(msg),
    error: (msg) => console.error(msg)
  }
})
```

### 6.4 测试策略分析

**测试架构：**

```
tests/
├── 单元测试
│   ├── exec.test.ts          # CodexExec 隔离测试（mock spawn）
│   └── abort.test.ts         # AbortSignal 行为测试
├── 集成测试
│   ├── run.test.ts           # run() 完整流程
│   └── runStreamed.test.ts   # runStreamed() 完整流程
└── 测试基础设施
    ├── testCodex.ts          # 测试客户端工厂
    ├── responsesProxy.ts     # Mock OpenAI API
    ├── codexExecSpy.ts       # spawn 调用监控
    └── setupCodexHome.ts     # 测试环境隔离
```

**Mock 策略：**
- `responsesProxy.ts` 启动本地 HTTP 服务器模拟 OpenAI Responses API
- `codexExecSpy.ts` 使用 Jest mock 监控 spawn 调用参数
- 测试使用真实的 `codex-rs/target/debug/codex` 二进制

**测试环境要求：**
- 需要预编译的 Codex CLI 二进制（`codex-rs/target/debug/codex`）
- 临时 `CODEX_HOME` 目录隔离

---

## 7. 附录

### 7.1 相关文档

- [SDK README](../../sdk/typescript/README.md) - 使用指南
- [Rust exec_events.rs](../../codex-rs/exec/src/exec_events.rs) - 事件定义源
- [Rust CLI](../../codex-rs/exec/src/cli.rs) - CLI 参数定义

### 7.2 版本信息

- **当前版本：** 0.0.0-dev
- **Node.js 要求：** >= 18
- **包管理器：** pnpm 10.29.3

### 7.3 构建配置

**TypeScript 配置：**
- Target: ES2022
- Module: ESNext
- ModuleResolution: bundler
- Strict: true
- noUncheckedIndexedAccess: true

**构建输出：**
- Format: ESM only
- 目标: Node.js 18+
- 工具: tsup
