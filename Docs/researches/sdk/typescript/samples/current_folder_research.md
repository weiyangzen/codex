# sdk/typescript/samples 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`sdk/typescript/samples` 目录包含 **OpenAI Codex TypeScript SDK** 的示例代码，用于演示如何将 Codex 智能代理集成到 TypeScript/JavaScript 应用程序中。这些示例展示了 SDK 的核心功能和使用模式。

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **程序化 AI 交互** | 在脚本或应用中调用 Codex 代理，而非使用交互式 CLI |
| **自动化工作流** | 将 Codex 集成到 CI/CD、数据处理管道等自动化流程 |
| **结构化输出** | 获取 JSON 格式的结构化响应，便于后续程序处理 |
| **流式响应处理** | 实时接收和处理代理的中间事件（命令执行、文件变更等） |
| **多模态输入** | 结合文本和图像输入进行复杂的 AI 任务 |

### 1.3 与相关组件的关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户应用程序                              │
│                   (使用 samples 作为参考)                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              sdk/typescript (TypeScript SDK)                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────────┐ │
│  │ codex.ts│  │ thread.ts│  │ exec.ts │  │ events.ts/items.ts  │ │
│  │(主入口) │  │(对话管理)│  │(CLI调用)│  │(类型定义)           │ │
│  └────┬────┘  └────┬────┘  └────┬────┘  └─────────────────────┘ │
│       └─────────────┴────────────┘                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │ spawn child process
                            │ JSONL over stdin/stdout
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              codex-rs/exec (Rust CLI 二进制)                     │
│  ┌─────────┐  ┌─────────────────────┐  ┌─────────────────────┐  │
│  │ main.rs │  │ event_processor_... │  │ exec_events.rs      │  │
│  │(CLI入口)│  │(JSONL事件处理器)    │  │(事件类型定义)       │  │
│  └────┬────┘  └─────────────────────┘  └─────────────────────┘  │
│       └──────────────────────────────────────────────────────┐  │
└──────────────────────────────────────────────────────────────┼──┘
                                                               │
                                                               ▼
┌─────────────────────────────────────────────────────────────────┐
│              codex-rs/core + app-server (核心逻辑)               │
│         (会话管理、工具调用、沙箱执行、OpenAI API 调用)           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 示例文件功能概览

| 文件 | 功能目的 | 核心演示点 |
|------|----------|-----------|
| `basic_streaming.ts` | 流式交互示例 | `runStreamed()` API、实时事件处理、对话循环 |
| `structured_output.ts` | 结构化输出（原生 JSON Schema） | `outputSchema` 参数、类型安全响应 |
| `structured_output_zod.ts` | 结构化输出（Zod 集成） | Zod schema 转 JSON Schema、运行时类型验证 |
| `helpers.ts` | 共享辅助函数 | CLI 路径解析、环境变量处理 |

### 2.2 各示例详细分析

#### 2.2.1 basic_streaming.ts

**目的**：展示如何建立持续对话并实时处理代理事件。

**关键功能点**：
- 使用 `createInterface` 创建交互式命令行界面
- 通过 `runStreamed()` 获取异步事件生成器
- 处理多种事件类型：
  - `item.completed`: 代理消息、推理过程、命令执行结果、文件变更
  - `item.updated`/`item.started`: 待办事项列表更新
  - `turn.completed`: Token 使用统计
  - `turn.failed`: 错误处理

**适用场景**：
- 构建交互式 AI 助手
- 实时监控代理执行状态
- 需要展示进度的长时间运行任务

#### 2.2.2 structured_output.ts

**目的**：演示如何使用原生 JSON Schema 获取结构化响应。

**关键功能点**：
- 内联定义 JSON Schema（使用 `as const` 确保类型推断）
- 通过 `outputSchema` 选项传递给 `thread.run()`
- 直接获取符合 schema 的 JSON 响应

**Schema 示例**：
```typescript
const schema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    status: { type: "string", enum: ["ok", "action_required"] },
  },
  required: ["summary", "status"],
  additionalProperties: false,
} as const;
```

**适用场景**：
- 需要机器解析的响应（如状态报告、配置生成）
- 与现有类型系统的集成

#### 2.2.3 structured_output_zod.ts

**目的**：展示 Zod 运行时类型验证与 Codex SDK 的集成。

**关键功能点**：
- 使用 Zod 定义 schema，获得 TypeScript 类型推断
- 通过 `zod-to-json-schema` 转换为 OpenAI 兼容的 JSON Schema
- 目标设置为 `"openAi"` 确保兼容性

**依赖**：
- `zod`: 运行时类型验证库
- `zod-to-json-schema`: Schema 转换工具

**适用场景**：
- 已有 Zod schema 的项目
- 需要运行时类型验证的场景
- 类型安全优先的开发流程

#### 2.2.4 helpers.ts

**目的**：提供示例间共享的辅助功能。

**核心函数**：
```typescript
export function codexPathOverride() {
  return (
    process.env.CODEX_EXECUTABLE ??
    path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex")
  );
}
```

**功能**：
- 优先从环境变量 `CODEX_EXECUTABLE` 获取 CLI 路径
- 回退到相对路径（假设在开发环境中运行）
- 支持本地开发和生产部署的灵活配置

---

## 3. 具体技术实现

### 3.1 SDK 架构与数据流

#### 3.1.1 核心类关系

```typescript
// 入口类：管理 CLI 进程生命周期
class Codex {
  private exec: CodexExec;        // 封装 CLI 进程调用
  private options: CodexOptions;  // 全局配置
  
  startThread(options?: ThreadOptions): Thread
  resumeThread(id: string, options?: ThreadOptions): Thread
}

// 对话管理：维护线程状态和对话历史
class Thread {
  private _exec: CodexExec;
  private _id: string | null;     // 线程 ID（首次 turn 后设置）
  
  run(input: Input, options?: TurnOptions): Promise<Turn>
  runStreamed(input: Input, options?: TurnOptions): Promise<StreamedTurn>
}
```

#### 3.1.2 执行流程

```
User Input
    │
    ▼
┌─────────────────┐
│  Thread.run()   │ ──► 阻塞等待完整响应
│  or             │
│  Thread.runStreamed() │ ──► 返回 AsyncGenerator 实时事件
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ normalizeInput()│ ──► 将 string | UserInput[] 转换为 { prompt, images }
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ createOutputSchemaFile() │ ──► 如有 schema，写入临时文件
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  CodexExec.run()│ ──► 构建 CLI 参数，spawn 子进程
└────────┬────────
         │
         ▼
┌─────────────────┐
│   codex exec    │ ──► Rust CLI 接收 JSONL 参数，执行 AI 任务
│   --experimental-json   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  JSONL Events   │ ──► thread.started, item.*, turn.*, error
│  (stdout)       │
└─────────────────┘
```

### 3.2 关键数据结构

#### 3.2.1 事件类型（ThreadEvent）

```typescript
type ThreadEvent =
  | ThreadStartedEvent      // { type: "thread.started", thread_id: string }
  | TurnStartedEvent        // { type: "turn.started" }
  | TurnCompletedEvent      // { type: "turn.completed", usage: Usage }
  | TurnFailedEvent         // { type: "turn.failed", error: ThreadError }
  | ItemStartedEvent        // { type: "item.started", item: ThreadItem }
  | ItemUpdatedEvent        // { type: "item.updated", item: ThreadItem }
  | ItemCompletedEvent      // { type: "item.completed", item: ThreadItem }
  | ThreadErrorEvent;       // { type: "error", message: string }
```

#### 3.2.2 线程项目类型（ThreadItem）

```typescript
type ThreadItem =
  | AgentMessageItem        // 代理文本响应
  | ReasoningItem           // 推理过程摘要
  | CommandExecutionItem    // 命令执行（含状态、输出、退出码）
  | FileChangeItem          // 文件变更（add/delete/update）
  | McpToolCallItem         // MCP 工具调用
  | WebSearchItem           // 网络搜索请求
  | TodoListItem            // 待办事项列表
  | ErrorItem;              // 非致命错误
```

#### 3.2.3 配置选项

**CodexOptions**（全局）：
```typescript
type CodexOptions = {
  codexPathOverride?: string;    // CLI 二进制路径覆盖
  baseUrl?: string;              // OpenAI API 基础 URL
  apiKey?: string;               // API 密钥
  config?: CodexConfigObject;    // --config 覆盖项（TOML 格式）
  env?: Record<string, string>;  // 子进程环境变量（完全覆盖）
};
```

**ThreadOptions**（线程级）：
```typescript
type ThreadOptions = {
  model?: string;                    // 模型选择
  sandboxMode?: SandboxMode;         // 沙箱模式
  workingDirectory?: string;         // 工作目录
  skipGitRepoCheck?: boolean;        // 跳过 Git 仓库检查
  modelReasoningEffort?: ModelReasoningEffort;  // 推理努力程度
  networkAccessEnabled?: boolean;    // 网络访问
  webSearchMode?: WebSearchMode;     // 搜索模式
  approvalPolicy?: ApprovalMode;     // 审批策略
  additionalDirectories?: string[];  // 额外可写目录
};
```

**TurnOptions**（单次调用）：
```typescript
type TurnOptions = {
  outputSchema?: unknown;    // JSON Schema 用于结构化输出
  signal?: AbortSignal;      // 用于取消操作
};
```

### 3.3 CLI 参数构建协议

SDK 将高层 API 调用转换为 `codex exec` 命令行参数：

```typescript
// 基础命令
codex exec --experimental-json

// 配置覆盖（扁平化为 TOML key=value）
--config openai_base_url="https://..."
--config model_reasoning_effort="high"
--config sandbox_workspace_write.network_access=true
--config approval_policy="on-request"
--config web_search="live"

// 线程选项
--model <model>
--sandbox <sandboxMode>
--cd <workingDirectory>
--skip-git-repo-check
--add-dir <dir1> --add-dir <dir2>

// 单次调用选项
--output-schema <temp_file_path>

// 图像输入
--image <path1> --image <path2>

// 恢复线程
resume <threadId>

// 输入通过 stdin 传递
```

### 3.4 JSONL 通信协议

SDK 与 Rust CLI 之间通过 stdin/stdout 进行 JSONL（JSON Lines）通信：

**输入**（stdin）：
- 纯文本提示直接写入 stdin

**输出**（stdout）：
- 每行一个 JSON 对象
- 对象格式遵循 `ThreadEvent` 类型定义
- 关键事件示例：

```json
{"type":"thread.started","thread_id":"550e8400-e29b-41d4-a716-446655440000"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Hello!"}}
{"type":"turn.completed","usage":{"input_tokens":42,"cached_input_tokens":12,"output_tokens":5}}
```

### 3.5 输出 Schema 处理流程

```typescript
// 1. 用户传入 schema
const schema = { type: "object", properties: { ... } };

// 2. SDK 创建临时文件
const schemaDir = await fs.mkdtemp("codex-output-schema-");
const schemaPath = path.join(schemaDir, "schema.json");
await fs.writeFile(schemaPath, JSON.stringify(schema));

// 3. 传递路径给 CLI
--output-schema /tmp/codex-output-schema-xxx/schema.json

// 4. turn 结束后自动清理
await fs.rm(schemaDir, { recursive: true, force: true });
```

---

## 4. 关键代码路径与文件引用

### 4.1 SDK 源码结构

```
sdk/typescript/
├── src/
│   ├── index.ts              # 公共 API 导出
│   ├── codex.ts              # Codex 主类（入口）
│   ├── codexOptions.ts       # 全局配置类型
│   ├── thread.ts             # Thread 类（对话管理）
│   ├── threadOptions.ts      # 线程配置类型
│   ├── turnOptions.ts        # 单次调用配置类型
│   ├── exec.ts               # CodexExec 类（CLI 进程管理）
│   ├── events.ts             # 事件类型定义
│   ├── items.ts              # ThreadItem 类型定义
│   └── outputSchemaFile.ts   # Schema 临时文件管理
├── samples/
│   ├── basic_streaming.ts
│   ├── structured_output.ts
│   ├── structured_output_zod.ts
│   └── helpers.ts
├── tests/
│   ├── run.test.ts           # Thread.run() 测试
│   ├── runStreamed.test.ts   # Thread.runStreamed() 测试
│   ├── exec.test.ts          # CodexExec 测试
│   └── ...
├── package.json
└── tsconfig.json
```

### 4.2 Rust CLI 相关代码

```
codex-rs/
├── exec/src/
│   ├── main.rs               # CLI 入口
│   ├── lib.rs                # 核心执行逻辑
│   ├── cli.rs                # 命令行参数解析
│   ├── exec_events.rs        # 事件类型定义（与 TS 对应）
│   ├── event_processor_with_jsonl_output.rs  # JSONL 事件生成
│   └── event_processor.rs    # 事件处理器 trait
```

### 4.3 关键代码引用

| 功能 | TypeScript 文件 | Rust 文件 |
|------|-----------------|-----------|
| 事件类型定义 | `src/events.ts` | `exec/src/exec_events.rs` |
| Item 类型定义 | `src/items.ts` | `exec/src/exec_events.rs` |
| CLI 参数构建 | `src/exec.ts` `buildArgs()` | `exec/src/cli.rs` `Cli` |
| JSONL 输出 | `src/exec.ts` `readline` 解析 | `exec/src/event_processor_with_jsonl_output.rs` |
| Schema 文件处理 | `src/outputSchemaFile.ts` | `exec/src/main.rs` `load_output_schema()` |

---

## 5. 依赖与外部交互

### 5.1 TypeScript SDK 依赖

**运行时依赖**：
- 无直接运行时依赖（纯 Node.js 标准库）
- 可选：Zod 用于类型验证

**开发依赖**：
```json
{
  "@modelcontextprotocol/sdk": "^1.24.0",  // MCP 类型定义
  "@types/node": "^20.19.18",
  "typescript": "^5.9.2",
  "tsup": "^8.5.0",                        // 构建工具
  "jest": "^29.7.0",                       // 测试框架
  "zod": "^3.24.2",                        // 可选运行时验证
  "zod-to-json-schema": "^3.24.6"          // Schema 转换
}
```

### 5.2 外部 CLI 依赖

SDK 通过 `codex exec` 命令调用 Rust CLI，CLI 的查找顺序：

1. `codexPathOverride` 选项（显式指定）
2. 环境变量 `CODEX_EXECUTABLE`
3. 自动查找（基于平台）：
   - 通过 `@openai/codex` 包解析平台特定二进制包
   - 支持平台：Linux (x64/arm64)、macOS (x64/arm64)、Windows (x64/arm64)

### 5.3 环境变量

| 变量 | 用途 | 设置方 |
|------|------|--------|
| `CODEX_EXECUTABLE` | 覆盖 CLI 二进制路径 | 用户/CI |
| `CODEX_API_KEY` | OpenAI API 密钥 | SDK（从 options.apiKey） |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | 标识请求来源 | SDK（自动设置为 `codex_sdk_ts`） |
| `OPENAI_BASE_URL` | API 基础 URL | SDK（从 options.baseUrl） |

### 5.4 与 Rust CLI 的进程间通信

```typescript
// SDK 侧（exec.ts）
const child = spawn(this.executablePath, commandArgs, {
  env,
  signal: args.signal,
});

// 写入输入
child.stdin.write(args.input);
child.stdin.end();

// 读取 JSONL 输出
const rl = readline.createInterface({
  input: child.stdout,
  crlfDelay: Infinity,
});

for await (const line of rl) {
  yield line;  // 每行是一个 JSON 事件
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 进程管理风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 僵尸进程 | CLI 进程异常退出时可能残留 | `finally` 块中强制 `child.kill()` |
| 信号处理 | `AbortSignal` 传递可能不及时 | 已传递至 `spawn` 选项 |
| 资源泄漏 | 临时 schema 文件未清理 | `try/finally` 确保 `cleanup()` 调用 |

#### 6.1.2 类型安全边界

```typescript
// 风险：outputSchema 是 unknown 类型，无编译时检查
const turn = await thread.run("prompt", { 
  outputSchema: { invalid: "schema" }  // 运行时才会报错
});

// 风险：JSON 解析失败
const parsed = JSON.parse(item) as ThreadEvent;  // 类型断言可能不安全
```

#### 6.1.3 平台兼容性

- **Windows 路径处理**：需要验证路径分隔符和空格处理
- **信号处理**：Windows 对 POSIX 信号支持有限
- **二进制查找**：依赖 npm 包结构，自定义安装可能失败

### 6.2 边界条件

#### 6.2.1 输入限制

| 边界 | 限制 | 说明 |
|------|------|------|
| 输入大小 | 受限于 CLI stdin 缓冲区 | 超大输入需考虑分片 |
| 图像数量 | 无显式限制 | 受 CLI 参数长度限制 |
| Schema 复杂度 | 受 OpenAI API 限制 | 嵌套层级和属性数量 |

#### 6.2.2 并发限制

- 每个 `Thread` 实例对应一个独立的 CLI 进程
- 并发调用 `run()` 可能导致未定义行为（无内置队列）
- 建议：每个线程串行执行，多线程间可并行

### 6.3 改进建议

#### 6.3.1 类型安全增强

```typescript
// 建议：使用泛型约束 outputSchema
async function run<T = string>(
  input: Input,
  options?: TurnOptions & { outputSchema?: JSONSchemaType<T> }
): Promise<Turn<T>>;

// 这样可以在编译时推断 finalResponse 类型
type Turn<T> = {
  items: ThreadItem[];
  finalResponse: T;  // 而非 string
  usage: Usage | null;
};
```

#### 6.3.2 错误处理改进

```typescript
// 当前：简单抛出 Error
throw new Error(turnFailure.message);

// 建议：结构化错误类型
class TurnFailedError extends Error {
  constructor(
    message: string,
    public readonly turnId: string,
    public readonly threadId: string,
    public readonly items: ThreadItem[]  // 部分完成的 items
  ) {
    super(message);
  }
}
```

#### 6.3.3 重试与弹性

```typescript
// 建议：内置重试机制
const thread = client.startThread({
  retryPolicy: {
    maxRetries: 3,
    backoff: "exponential",
    retryableErrors: ["rate_limit", "timeout"]
  }
});
```

#### 6.3.4 事件过滤与转换

```typescript
// 建议：支持事件过滤
const { events } = await thread.runStreamed("prompt", {
  eventFilter: ["item.completed", "turn.completed"]  // 只接收这些事件
});

// 建议：支持自定义事件转换
const { events } = await thread.runStreamed("prompt", {
  transform: (event) => customTransform(event)
});
```

#### 6.3.5 可观测性增强

```typescript
// 建议：内置日志和指标钩子
const client = new Codex({
  hooks: {
    onEvent: (event) => metrics.record(event),
    onSpawn: (cmd, args) => logger.debug(`Spawn: ${cmd} ${args.join(" ")}`),
    onExit: (code, signal) => logger.info(`Exit: ${code}, ${signal}`)
  }
});
```

#### 6.3.6 文档与示例

| 改进项 | 优先级 | 说明 |
|--------|--------|------|
| MCP 工具调用示例 | 高 | 当前 samples 未展示 MCP 集成 |
| 错误处理最佳实践 | 高 | 展示如何处理各种失败场景 |
| 多线程协作示例 | 中 | 展示 `resumeThread` 的高级用法 |
| 流式输出到 WebSocket | 中 | 服务器端实时推送场景 |
| 与 Express/Fastify 集成 | 低 | Web 服务器集成模式 |

### 6.4 测试覆盖建议

当前测试主要覆盖：
- ✅ 基本 `run()` 和 `runStreamed()` 功能
- ✅ 线程恢复
- ✅ 配置传递
- ✅ Schema 文件处理

建议补充：
- ⬜ 大输入处理（>1MB）
- ⬜ 并发调用行为
- ⬜ 网络中断恢复
- ⬜ 内存泄漏检测（长时间运行）
- ⬜ 平台特定测试（Windows 路径等）

---

## 7. 附录

### 7.1 快速参考：事件处理模式

```typescript
const handleEvent = (event: ThreadEvent): void => {
  switch (event.type) {
    case "thread.started":
      console.log(`Thread: ${event.thread_id}`);
      break;
    case "item.completed":
      handleCompletedItem(event.item);
      break;
    case "turn.completed":
      console.log(`Tokens: ${event.usage.input_tokens}`);
      break;
    case "turn.failed":
      console.error(`Failed: ${event.error.message}`);
      break;
  }
};

const handleCompletedItem = (item: ThreadItem): void => {
  switch (item.type) {
    case "agent_message":
      console.log(`AI: ${item.text}`);
      break;
    case "command_execution":
      console.log(`Cmd: ${item.command} (${item.status})`);
      break;
    case "file_change":
      item.changes.forEach(c => console.log(`File: ${c.kind} ${c.path}`));
      break;
    // ... 其他类型
  }
};
```

### 7.2 相关文档链接

- SDK README: `sdk/typescript/README.md`
- Rust CLI 文档: `codex-rs/exec/README.md`（如存在）
- 配置文档: `docs/` 目录
- AGENTS.md: 项目根目录开发指南
