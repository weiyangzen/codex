# run.test.ts 研究文档

## 场景与职责

本测试文件是 TypeScript SDK 最全面的集成测试套件，专注于验证 `Thread.run()` 方法的完整功能。它测试了从基本的对话流程到复杂的配置覆盖、输入处理、工作目录管理等所有核心功能。

测试场景覆盖：
1. 基本对话流程和事件返回
2. 多轮对话和线程恢复
3. 各种配置选项的传递（模型、沙盒、网络、搜索等）
4. 结构化输出（JSON Schema）
5. 多模态输入（文本 + 图片）
6. 工作目录和 Git 仓库检查
7. 错误处理

## 功能点目的

### Thread.run() 测试目的
- **功能验证**：确保所有 ThreadOptions 正确传递给 CLI
- **集成测试**：验证 SDK 到 CLI 到 Mock API 的完整链路
- **回归防护**：防止配置传递、参数序列化等逻辑被破坏

### 测试覆盖范围

| 测试用例 | 描述 |
|---------|------|
| `returns thread events` | 基本对话流程，验证返回结构和 token 使用 |
| `sends previous items when run is called twice` | 多轮对话，验证历史记录传递 |
| `continues the thread when run is called twice with options` | 带选项的多轮对话 |
| `resumes thread by id` | 通过 ID 恢复线程 |
| `passes turn options to exec` | 验证模型和沙盒选项传递 |
| `passes modelReasoningEffort to exec` | 验证推理努力程度配置 |
| `passes networkAccessEnabled to exec` | 验证网络访问配置 |
| `passes webSearchEnabled to exec` | 验证网络搜索启用 |
| `passes webSearchMode to exec` | 验证网络搜索模式 |
| `passes webSearchEnabled false to exec` | 验证网络搜索禁用 |
| `passes approvalPolicy to exec` | 验证审批策略 |
| `passes CodexOptions config overrides as TOML --config flags` | 验证复杂配置对象序列化 |
| `lets thread options override CodexOptions config overrides` | 验证选项优先级 |
| `passes additionalDirectories as repeated flags` | 验证额外目录参数 |
| `writes output schema to a temporary file and forwards it` | 验证结构化输出 |
| `combines structured text input segments` | 验证多段文本输入合并 |
| `forwards images to exec` | 验证图片输入处理 |
| `runs in provided working directory` | 验证工作目录切换 |
| `throws if working directory is not git and no skipGitRepoCheck is provided` | 验证 Git 仓库检查 |
| `sets the codex sdk originator header` | 验证来源标识头 |
| `throws ThreadRunError on turn failures` | 验证错误处理 |

## 具体技术实现

### 关键流程

#### 1. 基本测试模式
```typescript
it("returns thread events", async () => {
  // 1. 启动代理服务器
  const { url, close } = await startResponsesTestProxy({
    statusCode: 200,
    responseBodies: [sse(responseStarted(), assistantMessage("Hi!"), responseCompleted())],
  });
  
  // 2. 创建测试客户端
  const { client, cleanup } = createMockClient(url);

  try {
    // 3. 执行测试操作
    const thread = client.startThread();
    const result = await thread.run("Hello, world!");

    // 4. 验证结果
    expect(result.items).toEqual([...]);
    expect(result.usage).toEqual({...});
  } finally {
    // 5. 清理资源
    cleanup();
    await close();
  }
});
```

#### 2. 多轮对话测试
```typescript
it("sends previous items when run is called twice", async () => {
  const { url, close, requests } = await startResponsesTestProxy({
    responseBodies: [
      sse(responseStarted("response_1"), assistantMessage("First", "item_1"), responseCompleted("response_1")),
      sse(responseStarted("response_2"), assistantMessage("Second", "item_2"), responseCompleted("response_2")),
    ],
  });
  
  const thread = client.startThread();
  await thread.run("first input");
  await thread.run("second input");

  // 验证第二次请求包含第一次的响应
  const secondRequest = requests[1];
  const assistantEntry = secondRequest!.json.input.find(
    (entry: { role: string }) => entry.role === "assistant"
  );
  expect(assistantText).toBe("First response");
});
```

#### 3. 配置选项验证（使用 codexExecSpy）
```typescript
it("passes turn options to exec", async () => {
  const { args: spawnArgs, restore } = codexExecSpy();
  
  const thread = client.startThread({
    model: "gpt-test-1",
    sandboxMode: "workspace-write",
  });
  await thread.run("apply options");

  // 验证命令行参数
  expectPair(commandArgs, ["--sandbox", "workspace-write"]);
  expectPair(commandArgs, ["--model", "gpt-test-1"]);
  
  restore();
});
```

#### 4. 配置覆盖序列化验证
```typescript
it("passes CodexOptions config overrides as TOML --config flags", async () => {
  const { client, cleanup } = createTestClient({
    config: {
      approval_policy: "never",
      sandbox_workspace_write: { network_access: true },
      retry_budget: 3,
      tool_rules: { allow: ["git status", "git diff"] },
    },
  });

  // 验证 TOML 序列化
  expectPair(commandArgs, ["--config", 'approval_policy="never"']);
  expectPair(commandArgs, ["--config", "sandbox_workspace_write.network_access=true"]);
  expectPair(commandArgs, ["--config", "retry_budget=3"]);
  expectPair(commandArgs, ["--config", 'tool_rules.allow=["git status", "git diff"]']);
});
```

#### 5. 结构化输出测试
```typescript
it("writes output schema to a temporary file and forwards it", async () => {
  const schema = {
    type: "object",
    properties: { answer: { type: "string" } },
    required: ["answer"],
    additionalProperties: false,
  } as const;

  await thread.run("structured", { outputSchema: schema });

  // 验证请求体包含 schema
  expect(text?.format).toEqual({
    name: "codex_output_schema",
    type: "json_schema",
    strict: true,
    schema,
  });

  // 验证命令行参数
  const schemaFlagIndex = commandArgs!.indexOf("--output-schema");
  expect(fs.existsSync(schemaPath)).toBe(false);  // 临时文件已清理
});
```

#### 6. 多模态输入测试
```typescript
it("combines structured text input segments", async () => {
  await thread.run([
    { type: "text", text: "Describe file changes" },
    { type: "text", text: "Focus on impacted tests" },
  ]);

  // 验证文本合并
  expect(lastUser?.content?.[0]?.text).toBe("Describe file changes\n\nFocus on impacted tests");
});

it("forwards images to exec", async () => {
  await thread.run([
    { type: "text", text: "describe the images" },
    { type: "local_image", path: "/path/to/first.png" },
    { type: "local_image", path: "/path/to/second.jpg" },
  ]);

  // 验证 --image 参数
  expect(forwardedImages).toEqual(["/path/to/first.png", "/path/to/second.jpg"]);
});
```

#### 7. 工作目录和 Git 检查
```typescript
it("runs in provided working directory", async () => {
  const thread = client.startThread({
    workingDirectory,
    skipGitRepoCheck: true,  // 跳过 Git 检查
  });
  await thread.run("use custom working directory");

  expectPair(commandArgs, ["--cd", workingDirectory]);
});

it("throws if working directory is not git and no skipGitRepoCheck is provided", async () => {
  const thread = client.startThread({ workingDirectory });
  await expect(thread.run("...")).rejects.toThrow(/Not inside a trusted directory/);
});
```

### 数据结构

#### 测试辅助类型
```typescript
// 来自 testCodex.ts
type CreateTestClientOptions = {
  apiKey?: string;
  baseUrl?: string;
  config?: CodexConfigObject;
  env?: Record<string, string>;
  inheritEnv?: boolean;
};

type TestClient = {
  cleanup: () => void;
  client: Codex;
};
```

#### 输入类型
```typescript
// 来自 thread.ts
export type UserInput =
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };

export type Input = string | UserInput[];
```

#### 返回类型
```typescript
export type Turn = {
  items: ThreadItem[];
  finalResponse: string;
  usage: Usage | null;
};

export type Usage = {
  input_tokens: number;
  cached_input_tokens: number;
  output_tokens: number;
};
```

### 辅助函数

#### expectPair - 验证参数对
```typescript
function expectPair(args: string[] | undefined, pair: [string, string]) {
  if (!args) throw new Error("args is undefined");
  const index = args.findIndex((arg, i) => arg === pair[0] && args[i + 1] === pair[1]);
  if (index === -1) throw new Error(`Pair ${pair[0]} ${pair[1]} not found in args`);
  expect(args[index + 1]).toBe(pair[1]);
}
```

#### collectConfigValues - 收集配置值
```typescript
function collectConfigValues(args: string[] | undefined, key: string): string[] {
  const values: string[] = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] !== "--config") continue;
    const override = args[i + 1];
    if (override?.startsWith(`${key}=`)) values.push(override);
  }
  return values;
}
```

## 关键代码路径与文件引用

### 测试文件
- `sdk/typescript/tests/run.test.ts` - 本测试文件 (807 行)

### 被测试代码
- `sdk/typescript/src/thread.ts`
  - Lines 40-138: `Thread` 类实现
  - Lines 115-138: `run()` 方法
  - Lines 141-155: `normalizeInput()` 函数

- `sdk/typescript/src/exec.ts`
  - Lines 57-227: `CodexExec` 类
  - Lines 229-315: 配置序列化

- `sdk/typescript/src/codex.ts`
  - Lines 11-38: `Codex` 类

### 测试依赖
- `sdk/typescript/tests/responsesProxy.ts` - SSE 代理服务器
- `sdk/typescript/tests/testCodex.ts` - 测试客户端工厂
- `sdk/typescript/tests/codexExecSpy.ts` - spawn 调用监控

### 调用链（复杂场景示例）
```
run.test.ts
  → startResponsesTestProxy() + codexExecSpy()
  → createTestClient({ config: {...} }) / createMockClient(url)
    → new Codex({ codexPathOverride, config })
      → new CodexExec(codexPathOverride, env, config)
  → client.startThread({ model, sandboxMode, ... })
    → new Thread(exec, options, threadOptions)
  → thread.run("input", { outputSchema })
    → normalizeInput("input") → { prompt, images }
    → createOutputSchemaFile(schema) → { schemaPath, cleanup }
    → exec.run({ input: prompt, images, outputSchemaFile: schemaPath, ... })
      → spawn(codexPath, ["exec", "--experimental-json", "--config", ...])
        → [Rust CLI 执行]
          → HTTP POST /responses to mock server
          → Receive SSE stream
          → Output JSONL to stdout
      → yield JSON.parse(line) for each line
    → for await (event of generator)
      → if event.type === "item.completed" → items.push(event.item)
      → if event.type === "turn.completed" → usage = event.usage
    → cleanup()  // 删除临时 schema 文件
  → return { items, finalResponse, usage }
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `@jest/globals` | 测试框架 |
| `node:fs` | 文件系统操作（临时目录、图片文件） |
| `node:os` | 临时目录创建 |
| `node:path` | 路径处理 |

### 测试基础设施
| 模块 | 功能 |
|-----|------|
| `responsesProxy.ts` | 模拟 OpenAI API |
| `testCodex.ts` | 创建配置好的测试客户端 |
| `codexExecSpy.ts` | 监控 CLI 调用参数 |

### 二进制依赖
- `codex-rs/target/debug/codex` - Rust CLI 二进制

## 风险、边界与改进建议

### 当前风险

1. **测试执行时间长**
   - 21 个测试用例，每个都启动代理服务器和 CLI 进程
   - 测试套件执行时间可能较长
   - `throws ThreadRunError on turn failures` 显式设置了 10 秒超时

2. **临时文件管理**
   ```typescript
   const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "codex-images-"));
   // ...
   fs.rmSync(tempDir, { recursive: true, force: true });
   ```
   - 如果测试中断，临时文件可能残留
   - `force: true` 抑制了错误，可能隐藏问题

3. **硬编码路径**
   ```typescript
   export const codexExecPath = path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex");
   ```
   - 依赖特定目录结构和构建产物
   - 如果 Rust 代码未构建，测试会失败

4. **竞态条件**
   - 多个测试共享全局的 `spawn` mock
   - 如果测试并行执行，可能相互干扰

5. **Git 检查依赖**
   ```typescript
   await expect(thread.run("...")).rejects.toThrow(/Not inside a trusted directory/);
   ```
   - 依赖 Rust CLI 的特定错误消息
   - 如果 CLI 错误消息改变，测试会失败

### 边界情况

1. **配置覆盖优先级**
   - 测试验证了 `CodexOptions.config` 和 `ThreadOptions` 的覆盖关系
   - 但未测试 `baseUrl`/`apiKey` 与 `config` 的交互

2. **空输入处理**
   - 未测试空字符串输入 `thread.run("")`
   - 未测试空数组输入 `thread.run([])`

3. **并发线程**
   - 所有测试都是单线程顺序执行
   - 未测试多个线程同时运行的场景

4. **大型输入**
   - 未测试超长文本输入
   - 未测试大量图片输入

5. **Schema 验证**
   - 测试验证了 schema 文件传递，但未验证 schema 内容验证

### 改进建议

1. **测试并行化优化**
   ```typescript
   // 建议：使用测试数据库或隔离机制支持并行
   describe.parallel("Codex", () => { ... });
   ```

2. **临时文件自动清理**
   ```typescript
   // 建议：使用 try-finally 或 disposable 模式
   using tempDir = await createTempDir();
   ```

3. **缺失二进制文件的错误提示**
   ```typescript
   // 在 testCodex.ts 中
   if (!fs.existsSync(codexExecPath)) {
     throw new Error(
       `Codex CLI not found at ${codexExecPath}. ` +
       `Please build the Rust project first: cd codex-rs && cargo build`
     );
   }
   ```

4. **更多边界测试**
   ```typescript
   it("handles empty input", async () => {
     await expect(thread.run("")).rejects.toThrow();
   });

   it("handles very long input", async () => {
     const longInput = "x".repeat(1000000);
     // ...
   });

   it("handles concurrent threads", async () => {
     const thread1 = client.startThread();
     const thread2 = client.startThread();
     await Promise.all([thread1.run("input1"), thread2.run("input2")]);
   });
   ```

5. **验证 CLI 退出码**
   ```typescript
   // 建议：codexExecSpy 返回退出码信息
   const { args, exitCodes, restore } = codexExecSpy();
   expect(exitCodes).toEqual([0, 0]);  // 验证正常退出
   ```

6. **响应时间测试**
   ```typescript
   it("completes within reasonable time", async () => {
     const start = Date.now();
     await thread.run("input");
     expect(Date.now() - start).toBeLessThan(5000);
   });
   ```

7. **内存泄漏检测**
   ```typescript
   // 建议：验证大量线程创建不会导致内存泄漏
   it("does not leak memory when creating many threads", async () => {
     const initialMemory = process.memoryUsage().heapUsed;
     for (let i = 0; i < 100; i++) {
       const thread = client.startThread();
       await thread.run("input");
     }
     const finalMemory = process.memoryUsage().heapUsed;
     expect(finalMemory - initialMemory).toBeLessThan(10 * 1024 * 1024);  // 10MB
   });
   ```

8. **更清晰的测试组织**
   ```typescript
   describe("configuration", () => {
     describe("model options", () => { ... });
     describe("sandbox options", () => { ... });
     describe("search options", () => { ... });
   });
   describe("input handling", () => { ... });
   describe("thread lifecycle", () => { ... });
   ```
