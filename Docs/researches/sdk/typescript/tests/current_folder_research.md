# SDK TypeScript Tests 深度研究文档

## 目录
1. [场景与职责](#场景与职责)
2. [功能点目的](#功能点目的)
3. [具体技术实现](#具体技术实现)
4. [关键代码路径与文件引用](#关键代码路径与文件引用)
5. [依赖与外部交互](#依赖与外部交互)
6. [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 1.1 测试目录定位

`sdk/typescript/tests` 是 OpenAI Codex TypeScript SDK 的测试套件目录，位于 `/home/sansha/Github/codex/sdk/typescript/tests/`。该测试套件采用 **Jest** 测试框架，使用 **ESM 模块系统**，通过 `ts-jest` 进行 TypeScript 代码的转换和执行。

### 1.2 核心职责

该测试套件承担以下核心职责：

| 职责领域 | 说明 |
|---------|------|
| **功能验证** | 验证 SDK 核心 API（`run()`, `runStreamed()`）的正确性 |
| **集成测试** | 测试 SDK 与 Codex CLI 的进程间通信 |
| **配置验证** | 验证各种配置选项（ThreadOptions、CodexOptions）的正确传递 |
| **流式处理** | 验证 SSE (Server-Sent Events) 事件流的解析和处理 |
| **异常处理** | 验证错误处理、AbortSignal 取消机制 |
| **Mock 测试** | 通过 Mock HTTP 服务器和子进程进行隔离测试 |

### 1.3 测试架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                     SDK TypeScript Tests                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  Unit Tests │  │ Integration │  │  Mock Infrastructure    │  │
│  │             │  │    Tests    │  │                         │  │
│  │ • exec.test │  │ • run.test  │  │ • responsesProxy.ts     │  │
│  │             │  │ • runStream │  │ • codexExecSpy.ts       │  │
│  │             │  │ • abort.test│  │ • testCodex.ts          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SDK Source Code (src/)                      │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐  │
│  │ codex.ts│ │ exec.ts │ │thread.ts│ │ events.ts│ │ items.ts │  │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Codex CLI (Rust Binary)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 2.1 测试文件功能矩阵

| 测试文件 | 功能目的 | 测试数量 | 关键验证点 |
|---------|---------|---------|-----------|
| `abort.test.ts` | AbortSignal 取消机制 | 5 | 验证 run() 和 runStreamed() 的取消行为 |
| `exec.test.ts` | CodexExec 核心执行器 | 3 | 验证子进程管理、参数顺序、环境变量隔离 |
| `run.test.ts` | Thread.run() 方法 | 21 | 验证线程生命周期、配置传递、输入处理 |
| `runStreamed.test.ts` | Thread.runStreamed() | 5 | 验证流式事件、线程恢复、结构化输出 |
| `setupCodexHome.ts` | 测试环境初始化 | - | 每个测试用例的 CODEX_HOME 隔离 |
| `testCodex.ts` | 测试辅助工具 | - | Mock 客户端创建、配置合并 |
| `responsesProxy.ts` | Mock HTTP 服务器 | - | OpenAI Responses API 模拟 |
| `codexExecSpy.ts` | 子进程监控 | - | 捕获 spawn 调用的参数和环境变量 |

### 2.2 核心功能验证详解

#### 2.2.1 线程生命周期管理

```typescript
// run.test.ts: 验证线程创建、运行、恢复
- "returns thread events"                    // 基本线程事件
- "sends previous items when run is called twice"  // 对话连续性
- "resumes thread by id"                     // 线程持久化恢复
```

#### 2.2.2 配置选项传递验证

测试套件验证了从 SDK 到 CLI 的完整配置传递链：

| 配置层级 | 配置项 | 验证测试 |
|---------|-------|---------|
| `ThreadOptions` | `model` | "passes turn options to exec" |
| `ThreadOptions` | `sandboxMode` | "passes turn options to exec" |
| `ThreadOptions` | `modelReasoningEffort` | "passes modelReasoningEffort to exec" |
| `ThreadOptions` | `networkAccessEnabled` | "passes networkAccessEnabled to exec" |
| `ThreadOptions` | `webSearchEnabled` | "passes webSearchEnabled to exec" |
| `ThreadOptions` | `webSearchMode` | "passes webSearchMode to exec" |
| `ThreadOptions` | `approvalPolicy` | "passes approvalPolicy to exec" |
| `ThreadOptions` | `additionalDirectories` | "passes additionalDirectories as repeated flags" |
| `ThreadOptions` | `workingDirectory` | "runs in provided working directory" |
| `TurnOptions` | `outputSchema` | "writes output schema to a temporary file" |
| `CodexOptions` | `config` | "passes CodexOptions config overrides as TOML" |

#### 2.2.3 输入处理验证

| 输入类型 | 测试用例 | 处理方式 |
|---------|---------|---------|
| 纯文本 | 基础测试 | 直接传递 |
| 多段文本 | "combines structured text input segments" | `\n\n` 连接 |
| 本地图片 | "forwards images to exec" | `--image` 参数 |
| 混合输入 | 同上 | 文本合并 + 图片分离 |

---

## 具体技术实现

### 3.1 Mock HTTP 服务器 (responsesProxy.ts)

#### 3.1.1 架构设计

`responsesProxy.ts` 实现了一个轻量级的 HTTP Mock 服务器，用于模拟 OpenAI Responses API：

```typescript
// 核心类型定义
export type SseEvent = {
  type: string;
  [key: string]: unknown;
};

export type SseResponseBody = {
  kind: "sse";
  events: SseEvent[];
};

export type ResponsesProxy = {
  url: string;           // 服务器地址
  close: () => Promise<void>;
  requests: RecordedRequest[];  // 记录所有请求
};
```

#### 3.1.2 SSE 事件生成器

```typescript
// 无限生成 shell_call 事件（用于 abort 测试）
function* infiniteShellCall(): Generator<SseResponseBody> {
  while (true) {
    yield sse(responseStarted(), shellCall(), responseCompleted());
  }
}
```

#### 3.1.3 预设 SSE 事件工厂函数

| 工厂函数 | 事件类型 | 用途 |
|---------|---------|------|
| `responseStarted(id?)` | `response.created` | 标记响应开始 |
| `assistantMessage(text, id?)` | `response.output_item.done` | 模拟助手回复 |
| `shell_call()` | `response.output_item.done` | 模拟函数调用 |
| `responseCompleted(id?, usage?)` | `response.completed` | 标记响应完成 |
| `responseFailed(message)` | `error` | 模拟错误响应 |

### 3.2 子进程监控 (codexExecSpy.ts)

#### 3.2.1 Jest Mock 机制

```typescript
// 部分 mock node:child_process，保留实际实现
jest.mock("node:child_process", () => {
  const actual = jest.requireActual<typeof import("node:child_process")>("node:child_process");
  return { ...actual, spawn: jest.fn(actual.spawn) };
});
```

#### 3.2.2 Spy 实现原理

```typescript
export function codexExecSpy(): {
  args: string[][];                    // 捕获所有 spawn 调用的参数
  envs: (Record<string, string> | undefined)[];  // 捕获环境变量
  restore: () => void;                 // 恢复原始实现
} {
  spawnMock.mockImplementation(((...spawnArgs) => {
    const commandArgs = spawnArgs[1];
    args.push(Array.isArray(commandArgs) ? [...commandArgs] : []);
    const options = spawnArgs[2] as child_process.SpawnOptions | undefined;
    envs.push(options?.env as Record<string, string> | undefined);
    return previousImplementation(...spawnArgs);  // 调用真实实现
  }) as typeof actualChildProcess.spawn);
}
```

### 3.3 测试环境隔离 (setupCodexHome.ts)

#### 3.3.1 环境隔离机制

```typescript
const originalCodexHome = process.env.CODEX_HOME;
let currentCodexHome: string | undefined;

beforeEach(async () => {
  // 每个测试用例创建独立的临时目录
  currentCodexHome = await fs.mkdtemp(path.join(os.tmpdir(), "codex-sdk-test-"));
  process.env.CODEX_HOME = currentCodexHome;
});

afterEach(async () => {
  // 恢复原始环境变量
  if (originalCodexHome === undefined) {
    delete process.env.CODEX_HOME;
  } else {
    process.env.CODEX_HOME = originalCodexHome;
  }
  // 清理临时目录
  if (codexHomeToDelete) {
    await fs.rm(codexHomeToDelete, { recursive: true, force: true });
  }
});
```

### 3.4 测试客户端工厂 (testCodex.ts)

#### 3.4.1 Mock 客户端配置

```typescript
export function createMockClient(url: string): TestClient {
  return createTestClient({
    config: {
      model_provider: "mock",
      model_providers: {
        mock: {
          name: "Mock provider for test",
          base_url: url,                    // 指向 Mock HTTP 服务器
          wire_api: "responses",
          supports_websockets: false,
        },
      },
    },
  });
}
```

#### 3.4.2 配置合并策略

```typescript
function mergeTestProviderConfig(
  baseUrl: string | undefined,
  config: CodexConfigObject | undefined,
): CodexConfigObject | undefined {
  if (!baseUrl || hasExplicitProviderConfig(config)) {
    return config;
  }
  // 自动注入 mock provider 配置
  return {
    ...config,
    model_provider: "mock",
    model_providers: { /* ... */ },
  };
}
```

### 3.5 AbortSignal 实现机制

#### 3.5.1 取消信号传递链

```
User Code
    │
    ▼
Thread.runStreamed(input, { signal })
    │
    ▼
CodexExec.run({ signal })  // 传递给 child_process.spawn
    │
    ▼
spawn(command, args, { signal })  // Node.js 原生支持
```

#### 3.5.2 测试覆盖场景

| 测试用例 | 取消时机 | 预期行为 |
|---------|---------|---------|
| "aborts run() when signal is aborted" | 调用前已取消 | 立即抛出异常 |
| "aborts runStreamed() when signal is aborted" | 调用前已取消 | 迭代器立即抛出 |
| "aborts run() when signal is aborted during execution" | 执行中取消 | 操作被拒绝 |
| "aborts runStreamed() when signal is aborted during iteration" | 迭代中取消 | 迭代器抛出异常 |
| "completes normally when signal is not aborted" | 不取消 | 正常完成 |

### 3.6 配置序列化机制

#### 3.6.1 TOML 值转换

```typescript
// exec.ts: toTomlValue 函数
function toTomlValue(value: CodexConfigValue, path: string): string {
  if (typeof value === "string") {
    return JSON.stringify(value);  // "value"
  } else if (typeof value === "number") {
    return `${value}`;             // 123
  } else if (typeof value === "boolean") {
    return value ? "true" : "false";  // true/false
  } else if (Array.isArray(value)) {
    return `[${rendered.join(", ")}]`;  // ["a", "b"]
  } else if (isPlainObject(value)) {
    return `{${parts.join(", ")}}`;    // {key = value}
  }
}
```

#### 3.6.2 配置扁平化

```typescript
// 输入: { sandbox_workspace_write: { network_access: true } }
// 输出: ["sandbox_workspace_write.network_access=true"]

function flattenConfigOverrides(
  value: CodexConfigValue,
  prefix: string,
  overrides: string[],
): void {
  for (const [key, child] of Object.entries(value)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (isPlainObject(child)) {
      flattenConfigOverrides(child, path, overrides);
    } else {
      overrides.push(`${path}=${toTomlValue(child, path)}`);
    }
  }
}
```

---

## 关键代码路径与文件引用

### 4.1 测试文件结构

```
sdk/typescript/tests/
├── abort.test.ts           # AbortSignal 测试
├── codexExecSpy.ts         # 子进程监控工具
├── exec.test.ts            # CodexExec 单元测试
├── responsesProxy.ts       # Mock HTTP 服务器
├── run.test.ts             # Thread.run() 集成测试
├── runStreamed.test.ts     # Thread.runStreamed() 集成测试
├── setupCodexHome.ts       # 测试环境初始化
└── testCodex.ts            # 测试辅助工具
```

### 4.2 源码依赖关系

```
sdk/typescript/src/
├── codex.ts        # Codex 主类
│   └── 依赖: exec.ts, thread.ts, codexOptions.ts, threadOptions.ts
├── exec.ts         # CLI 执行器
│   └── 依赖: codexOptions.ts, threadOptions.ts
├── thread.ts       # 线程管理
│   └── 依赖: exec.ts, events.ts, items.ts, turnOptions.ts, outputSchemaFile.ts
├── events.ts       # 事件类型定义
├── items.ts        # 线程项类型定义
├── codexOptions.ts # Codex 配置选项
├── threadOptions.ts # 线程配置选项
├── turnOptions.ts  # 回合配置选项
├── outputSchemaFile.ts # 输出 schema 文件管理
└── index.ts        # 公共 API 导出
```

### 4.3 关键代码路径

#### 4.3.1 正常执行流程

```
1. 测试创建 Mock 服务器
   responsesProxy.ts:startResponsesTestProxy()
   
2. 测试创建 Mock 客户端
   testCodex.ts:createMockClient(url) → createTestClient()
   
3. 测试调用 SDK API
   thread.ts:run(input) / runStreamed(input)
   
4. SDK 准备执行参数
   thread.ts:normalizeInput(input) → { prompt, images }
   
5. SDK 调用执行器
   exec.ts:CodexExec.run(args)
   
6. 执行器构建命令参数
   exec.ts: 构建 commandArgs 数组
   - config 覆盖项
   - --model, --sandbox, --cd 等标志
   - resume 子命令（如有 threadId）
   - --image 参数（如有图片）
   
7. 执行器生成子进程
   exec.ts:spawn(executablePath, commandArgs, { env, signal })
   
8. 执行器解析 JSONL 输出
   exec.ts:readline.createInterface() → for await...of
   
9. 线程解析事件
   thread.ts:JSON.parse() → ThreadEvent
   
10. 返回结果给测试
    run(): Turn { items, finalResponse, usage }
    runStreamed(): StreamedTurn { events: AsyncGenerator }
```

#### 4.3.2 配置传递路径

```
Test Code
    │
    ├──► createTestClient({ config: {...} })  // CodexOptions
    │         │
    │         ▼
    │    new Codex(options) ──► new CodexExec(codexPathOverride, env, config)
    │         │
    │         ▼
    │    Codex.startThread(threadOptions)  // ThreadOptions
    │         │
    │         ▼
    │    new Thread(exec, codexOptions, threadOptions)
    │         │
    │         ▼
    └────► thread.run(input, turnOptions)  // TurnOptions
                  │
                  ▼
           this._exec.run({
             ...codexOptions,
             ...threadOptions,
             ...turnOptions
           })
                  │
                  ▼
           构建 commandArgs:
           1. config 覆盖项（CodexOptions.config）
           2. baseUrl（CodexOptions.baseUrl）
           3. model（ThreadOptions.model）
           4. sandboxMode（ThreadOptions.sandboxMode）
           5. ...
           6. threadId（Thread._id）
           7. images（从 input 提取）
```

### 4.4 Jest 配置关键项

```javascript
// jest.config.cjs
module.exports = {
  preset: "ts-jest/presets/default-esm",  // ESM 支持
  testEnvironment: "node",
  extensionsToTreatAsEsm: [".ts"],
  setupFilesAfterEnv: ["<rootDir>/tests/setupCodexHome.ts"],  // 环境初始化
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",  // .js 扩展名映射
  },
  transform: {
    "^.+\\.tsx?$": ["ts-jest", {
      useESM: true,
      astTransformers: {
        before: [{
          path: "ts-jest-mock-import-meta",
          options: { metaObjectReplacement: { url: "file://..." } }
        }]
      }
    }]
  }
};
```

---

## 依赖与外部交互

### 5.1 运行时依赖

| 依赖包 | 用途 | 版本 |
|-------|------|------|
| `@modelcontextprotocol/sdk` | MCP (Model Context Protocol) 类型定义 | ^1.24.0 |

### 5.2 开发依赖

| 依赖包 | 用途 | 版本 |
|-------|------|------|
| `jest` | 测试框架 | ^29.7.0 |
| `ts-jest` | TypeScript Jest 转换器 | ^29.3.4 |
| `ts-jest-mock-import-meta` | import.meta.url Mock | ^1.3.1 |
| `@types/jest` | Jest 类型定义 | ^29.5.14 |
| `@types/node` | Node.js 类型定义 | ^20.19.18 |
| `typescript` | TypeScript 编译器 | ^5.9.2 |

### 5.3 外部系统交互

#### 5.3.1 Codex CLI 二进制文件

```typescript
// exec.ts: findCodexPath()
const PLATFORM_PACKAGE_BY_TARGET: Record<string, string> = {
  "x86_64-unknown-linux-musl": "@openai/codex-linux-x64",
  "aarch64-unknown-linux-musl": "@openai/codex-linux-arm64",
  "x86_64-apple-darwin": "@openai/codex-darwin-x64",
  "aarch64-apple-darwin": "@openai/codex-darwin-arm64",
  "x86_64-pc-windows-msvc": "@openai/codex-win32-x64",
  "aarch64-pc-windows-msvc": "@openai/codex-win32-arm64",
};
```

测试中使用本地构建的调试版本：
```typescript
// testCodex.ts
export const codexExecPath = path.join(
  process.cwd(), 
  "..", "..", 
  "codex-rs", "target", "debug", "codex"
);
```

#### 5.3.2 OpenAI Responses API

测试通过 Mock 服务器模拟 Responses API：

```
POST /responses
Content-Type: application/json

{
  "model": "gpt-4o",
  "input": [
    { "role": "user", "content": [{ "type": "text", "text": "..." }] }
  ]
}
```

响应格式 (SSE)：
```
event: response.created
data: {"type": "response.created", "response": {"id": "..."}}

event: response.output_item.done
data: {"type": "response.output_item.done", "item": {...}}

event: response.completed
data: {"type": "response.completed", "response": {"usage": {...}}}
```

### 5.4 环境变量

| 变量名 | 用途 | 设置位置 |
|-------|------|---------|
| `CODEX_HOME` | 会话存储目录 | setupCodexHome.ts |
| `CODEX_API_KEY` | API 密钥 | exec.ts (运行时注入) |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | 来源标识 | exec.ts (自动设置) |
| `OPENAI_BASE_URL` | API 基础 URL | 通过 --config 传递 |

---

## 风险、边界与改进建议

### 6.1 当前风险点

#### 6.1.1 测试稳定性风险

| 风险 | 描述 | 影响 |
|-----|------|------|
| **超时测试** | `run.test.ts:753` 设置了 10 秒超时 | 在慢速环境可能失败 |
| **无限生成器** | `infiniteShellCall()` 用于 abort 测试 | 如果 abort 机制失效，测试会挂起 |
| **临时文件泄漏** | `outputSchemaFile.ts` 创建临时文件 | 在异常情况下可能泄漏 |
| **进程泄漏** | Mock 服务器和子进程需要手动关闭 | 忘记 cleanup 可能导致端口占用 |

#### 6.1.2 代码覆盖盲区

| 盲区 | 描述 | 建议 |
|-----|------|------|
| **平台特定代码** | `findCodexPath()` 的平台检测 | 需要多平台 CI 覆盖 |
| **错误恢复路径** | `exec.ts:209-216` 错误处理 | 增加更多错误场景测试 |
| **WebSocket 支持** | `supports_websockets: false` | 未测试 WebSocket 路径 |
| **MCP 工具调用** | `items.ts:McpToolCallItem` | 未测试 MCP 集成 |

### 6.2 边界条件

#### 6.2.1 已处理的边界

| 边界条件 | 处理方式 | 测试覆盖 |
|---------|---------|---------|
| 空输入 | `normalizeInput()` 处理 | 基础测试 |
| 大量图片 | 多个 `--image` 参数 | "forwards images to exec" |
| 特殊字符配置值 | `JSON.stringify()` 转义 | "passes CodexOptions config overrides" |
| Git 仓库检查 | `skipGitRepoCheck` 选项 | "throws if working directory is not git" |
| 环境变量隔离 | `env` 参数控制 | "allows overriding the env passed to the Codex CLI" |

#### 6.2.2 未处理的边界

| 边界条件 | 潜在问题 | 建议 |
|---------|---------|------|
| 超长命令参数 | 可能超过系统限制 | 添加参数长度检查 |
| 超大 schema 文件 | 磁盘空间问题 | 添加大小限制 |
| 并发线程 | 未测试并发场景 | 添加并发测试 |
| 特殊文件名 | 图片路径含特殊字符 | 添加路径转义测试 |

### 6.3 改进建议

#### 6.3.1 测试改进

```typescript
// 建议 1: 添加自动资源清理
// 使用 try-finally 或自定义 jest 环境

// 建议 2: 添加并发测试
it("handles concurrent thread execution", async () => {
  const threads = Array(5).fill(null).map(() => client.startThread());
  const results = await Promise.all(
    threads.map(t => t.run("concurrent test"))
  );
  expect(results).toHaveLength(5);
});

// 建议 3: 添加性能基准测试
it("completes within acceptable time", async () => {
  const start = Date.now();
  await thread.run("performance test");
  expect(Date.now() - start).toBeLessThan(5000);
});
```

#### 6.3.2 代码改进

| 改进点 | 当前实现 | 建议 |
|-------|---------|------|
| **错误类型** | 通用 `Error` | 定义 `CodexSDKError` 层次结构 |
| **日志记录** | 无日志 | 添加可选的日志回调 |
| **重试机制** | 无 | 添加指数退避重试 |
| **连接池** | 每次新建连接 | 考虑连接复用 |

#### 6.3.3 架构改进

```
当前架构:
SDK → spawn CLI → HTTP → OpenAI API

建议架构 (支持 WebSocket):
SDK → spawn CLI → (HTTP | WebSocket) → OpenAI API
                              │
                              └── 支持长连接和实时推送
```

### 6.4 技术债务

| 债务项 | 位置 | 优先级 |
|-------|------|-------|
| TODO 移除超时 | `run.test.ts:773` | 中 |
| 硬编码路径 | `testCodex.ts:6` | 低 |
| 类型断言过多 | 多处使用 `as` | 中 |
| 重复代码 | `run.test.ts` 和 `runStreamed.test.ts` | 低 |

### 6.5 监控与可观测性建议

```typescript
// 建议添加事件追踪
interface SDKMetrics {
  threadCount: number;
  averageTurnDuration: number;
  errorRate: number;
  tokenUsage: Usage;
}

// 建议添加调试模式
const codex = new Codex({
  debug: true,  // 输出详细日志
  onEvent: (event) => console.log(event),  // 事件钩子
});
```

---

## 附录

### A. 测试执行命令

```bash
# 运行所有测试
cd sdk/typescript && pnpm test

# 运行特定测试文件
pnpm jest tests/run.test.ts

# 运行带覆盖率
pnpm jest --coverage

# 调试模式
pnpm jest --verbose
```

### B. 关键类型定义速查

```typescript
// ThreadEvent 联合类型
ThreadEvent = 
  | ThreadStartedEvent    // { type: "thread.started", thread_id: string }
  | TurnStartedEvent      // { type: "turn.started" }
  | TurnCompletedEvent    // { type: "turn.completed", usage: Usage }
  | TurnFailedEvent       // { type: "turn.failed", error: ThreadError }
  | ItemStartedEvent      // { type: "item.started", item: ThreadItem }
  | ItemUpdatedEvent      // { type: "item.updated", item: ThreadItem }
  | ItemCompletedEvent    // { type: "item.completed", item: ThreadItem }
  | ThreadErrorEvent;     // { type: "error", message: string }

// ThreadItem 联合类型
ThreadItem =
  | AgentMessageItem      // { type: "agent_message", text: string }
  | ReasoningItem         // { type: "reasoning", text: string }
  | CommandExecutionItem  // { type: "command_execution", command: string, ... }
  | FileChangeItem        // { type: "file_change", changes: [...] }
  | McpToolCallItem       // { type: "mcp_tool_call", server: string, ... }
  | WebSearchItem         // { type: "web_search", query: string }
  | TodoListItem          // { type: "todo_list", items: [...] }
  | ErrorItem;            // { type: "error", message: string }
```

---

*文档生成时间: 2026-03-22*
*研究范围: sdk/typescript/tests/*
*SDK 版本: 0.0.0-dev*
