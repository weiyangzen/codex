# runStreamed.test.ts 研究文档

## 场景与职责

本测试文件专注于验证 `Thread.runStreamed()` 方法的流式事件处理功能。与 `run.test.ts` 测试的同步返回不同，本文件测试的是异步事件流（AsyncGenerator）的生成、传递和消费。

测试场景覆盖：
1. 基本流式事件序列
2. 多轮流式对话和历史记录传递
3. 线程恢复与流式处理
4. 结构化输出的流式处理

## 功能点目的

### Thread.runStreamed() 测试目的
- **事件流验证**：确保所有事件按正确顺序生成
- **异步迭代器**：验证 `AsyncGenerator` 接口正确实现
- **实时反馈**：模拟用户需要实时看到 AI 处理过程的场景

### 与 run() 的区别
| 特性 | run() | runStreamed() |
|-----|-------|---------------|
| 返回类型 | `Promise<Turn>` | `Promise<StreamedTurn>` |
| 结果获取 | 一次性返回完整结果 | 通过 AsyncGenerator 流式获取 |
| 适用场景 | 简单对话 | 需要实时反馈的交互式应用 |
| 事件类型 | 聚合为 items | 原始 ThreadEvent 流 |

### 测试覆盖范围
| 测试用例 | 描述 |
|---------|------|
| `returns thread events` | 验证流式事件序列完整性 |
| `sends previous items when runStreamed is called twice` | 验证多轮流式对话 |
| `resumes thread by id when streaming` | 验证线程恢复后的流式处理 |
| `applies output schema turn options when streaming` | 验证结构化输出的流式处理 |

## 具体技术实现

### 关键流程

#### 1. 基本流式测试模式
```typescript
it("returns thread events", async () => {
  // 1. 启动代理服务器
  const { url, close } = await startResponsesTestProxy({
    statusCode: 200,
    responseBodies: [sse(responseStarted(), assistantMessage("Hi!"), responseCompleted())],
  });
  const { client, cleanup } = createMockClient(url);

  try {
    // 2. 启动流式对话
    const thread = client.startThread();
    const result = await thread.runStreamed("Hello, world!");

    // 3. 消费事件流
    const events: ThreadEvent[] = [];
    for await (const event of result.events) {
      events.push(event);
    }

    // 4. 验证完整事件序列
    expect(events).toEqual([
      { type: "thread.started", thread_id: expect.any(String) },
      { type: "turn.started" },
      { type: "item.completed", item: { id: "item_0", type: "agent_message", text: "Hi!" } },
      { type: "turn.completed", usage: { cached_input_tokens: 12, input_tokens: 42, output_tokens: 5 } },
    ]);
  } finally {
    cleanup();
    await close();
  }
});
```

#### 2. 事件流消费辅助函数
```typescript
async function drainEvents(events: AsyncGenerator<ThreadEvent>): Promise<void> {
  let done = false;
  do {
    done = (await events.next()).done ?? false;
  } while (!done);
}
```
- 完全消费事件流直到结束
- 用于测试中确保所有事件被处理

#### 3. 多轮流式对话测试
```typescript
it("sends previous items when runStreamed is called twice", async () => {
  const { url, close, requests } = await startResponsesTestProxy({
    responseBodies: [
      sse(responseStarted("response_1"), assistantMessage("First", "item_1"), responseCompleted("response_1")),
      sse(responseStarted("response_2"), assistantMessage("Second", "item_2"), responseCompleted("response_2")),
    ],
  });

  const thread = client.startThread();
  const first = await thread.runStreamed("first input");
  await drainEvents(first.events);  // 消费第一轮事件

  const second = await thread.runStreamed("second input");
  await drainEvents(second.events);  // 消费第二轮事件

  // 验证第二轮请求包含第一轮的历史记录
  const secondRequest = requests[1];
  const assistantEntry = secondRequest!.json.input.find(
    (entry: { role: string }) => entry.role === "assistant"
  );
  expect(assistantText).toBe("First response");
});
```

#### 4. 线程恢复 + 流式测试
```typescript
it("resumes thread by id when streaming", async () => {
  const originalThread = client.startThread();
  const first = await originalThread.runStreamed("first input");
  await drainEvents(first.events);

  // 通过 ID 恢复线程
  const resumedThread = client.resumeThread(originalThread.id!);
  const second = await resumedThread.runStreamed("second input");
  await drainEvents(second.events);

  // 验证 ID 一致性和历史记录传递
  expect(resumedThread.id).toBe(originalThread.id);
  // ... 验证历史记录
});
```

#### 5. 结构化输出流式测试
```typescript
it("applies output schema turn options when streaming", async () => {
  const schema = {
    type: "object",
    properties: { answer: { type: "string" } },
    required: ["answer"],
    additionalProperties: false,
  } as const;

  const thread = client.startThread();
  const streamed = await thread.runStreamed("structured", { outputSchema: schema });
  await drainEvents(streamed.events);

  // 验证请求体包含 schema
  expect(text?.format).toEqual({
    name: "codex_output_schema",
    type: "json_schema",
    strict: true,
    schema,
  });
});
```

### 数据结构

#### StreamedTurn 类型
```typescript
// 来自 thread.ts
export type StreamedTurn = {
  events: AsyncGenerator<ThreadEvent>;
};

export type RunStreamedResult = StreamedTurn;
```

#### ThreadEvent 联合类型
```typescript
// 来自 events.ts
export type ThreadEvent =
  | ThreadStartedEvent      // { type: "thread.started", thread_id: string }
  | TurnStartedEvent        // { type: "turn.started" }
  | TurnCompletedEvent      // { type: "turn.completed", usage: Usage }
  | TurnFailedEvent         // { type: "turn.failed", error: ThreadError }
  | ItemStartedEvent        // { type: "item.started", item: ThreadItem }
  | ItemUpdatedEvent        // { type: "item.updated", item: ThreadItem }
  | ItemCompletedEvent      // { type: "item.completed", item: ThreadItem }
  | ThreadErrorEvent;       // { type: "error", message: string }
```

#### 测试期望的事件序列
```typescript
// 标准成功对话的事件序列
[
  { type: "thread.started", thread_id: "..." },  // 线程创建
  { type: "turn.started" },                       // 开始处理
  { type: "item.completed", item: {...} },        // AI 响应完成
  { type: "turn.completed", usage: {...} },       // 本轮完成
]
```

### 流式处理机制

#### 事件生成流程
```typescript
// thread.ts lines 70-112
private async *runStreamedInternal(input: Input, turnOptions: TurnOptions = {}): AsyncGenerator<ThreadEvent> {
  const { schemaPath, cleanup } = await createOutputSchemaFile(turnOptions.outputSchema);
  const generator = this._exec.run({ ... });
  
  try {
    for await (const item of generator) {
      let parsed: ThreadEvent;
      try {
        parsed = JSON.parse(item) as ThreadEvent;
      } catch (error) {
        throw new Error(`Failed to parse item: ${item}`, { cause: error });
      }
      if (parsed.type === "thread.started") {
        this._id = parsed.thread_id;  // 更新线程 ID
      }
      yield parsed;  // 流式输出事件
    }
  } finally {
    await cleanup();  // 清理临时文件
  }
}
```

#### 与 run() 的关系
```typescript
// thread.ts lines 115-138
async run(input: Input, turnOptions: TurnOptions = {}): Promise<Turn> {
  const generator = this.runStreamedInternal(input, turnOptions);
  const items: ThreadItem[] = [];
  let finalResponse: string = "";
  let usage: Usage | null = null;
  let turnFailure: ThreadError | null = null;
  
  for await (const event of generator) {
    if (event.type === "item.completed") {
      if (event.item.type === "agent_message") {
        finalResponse = event.item.text;
      }
      items.push(event.item);
    } else if (event.type === "turn.completed") {
      usage = event.usage;
    } else if (event.type === "turn.failed") {
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
- `run()` 内部调用 `runStreamedInternal()`
- `run()` 聚合事件流为最终结果
- `runStreamed()` 直接暴露事件流

## 关键代码路径与文件引用

### 测试文件
- `sdk/typescript/tests/runStreamed.test.ts` - 本测试文件 (207 行)

### 被测试代码
- `sdk/typescript/src/thread.ts`
  - Lines 66-68: `runStreamed()` 公共方法
  - Lines 70-112: `runStreamedInternal()` 私有生成器

- `sdk/typescript/src/events.ts`
  - Lines 1-80: 所有事件类型定义

### 测试依赖
- `sdk/typescript/tests/responsesProxy.ts` - SSE 代理服务器
- `sdk/typescript/tests/testCodex.ts` - 测试客户端工厂

### 调用链
```
runStreamed.test.ts
  → startResponsesTestProxy()
  → createMockClient(url)
  → thread.runStreamed("input")
    → this.runStreamedInternal("input", turnOptions)
      → createOutputSchemaFile(turnOptions.outputSchema)
      → this._exec.run({ input, images, ... })
        → spawn(codex, ["exec", "--experimental-json", ...])
          → [Rust CLI]
            → HTTP POST /responses
            → Receive SSE stream
            → Transform to JSONL
            → Write to stdout
      → for await (const line of generator)
        → JSON.parse(line) as ThreadEvent
        → if (parsed.type === "thread.started") this._id = parsed.thread_id
        → yield parsed
    → return { events: generator }
  → for await (const event of result.events)
    → events.push(event)
  → expect(events).toEqual([...])
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `@jest/globals` | 测试框架 |
| `../src/index` | `ThreadEvent` 类型导入 |

### 测试基础设施
| 模块 | 功能 |
|-----|------|
| `responsesProxy.ts` | 模拟 OpenAI API |
| `testCodex.ts` | 创建测试客户端 |

### 与 run.test.ts 的关系
- 两个文件测试相似的功能，但接口不同
- `run.test.ts` 测试聚合结果
- `runStreamed.test.ts` 测试流式事件
- 两者共享相同的测试基础设施

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖不足**
   - 只有 4 个测试用例，相比 `run.test.ts` 的 21 个
   - 缺少配置选项、错误处理、取消信号等测试

2. **事件序列假设**
   ```typescript
   expect(events).toEqual([
     { type: "thread.started", ... },
     { type: "turn.started" },
     { type: "item.completed", ... },
     { type: "turn.completed", ... },
   ]);
   ```
   - 测试假设了固定的事件顺序
   - 实际事件顺序可能因 CLI 实现而变化

3. **drainEvents 辅助函数局限**
   ```typescript
   async function drainEvents(events: AsyncGenerator<ThreadEvent>): Promise<void> {
     let done = false;
     do {
       done = (await events.next()).done ?? false;
     } while (!done);
   }
   ```
   - 不收集事件，只确保流结束
   - 如果流抛出错误，错误会被吞没

4. **缺少错误流测试**
   - 没有测试 `turn.failed` 事件
   - 没有测试 `error` 事件
   - 没有测试流中断场景

### 边界情况

1. **空事件流**
   - 未测试 CLI 立即退出且不输出任何事件的情况

2. **大量事件**
   - 未测试事件数量很大的情况
   - 未测试背压（backpressure）处理

3. **部分消费**
   - 所有测试都完全消费事件流
   - 未测试提前终止迭代的情况（如 `break`）

4. **并发流**
   - 未测试多个线程同时流式处理

5. **事件类型覆盖**
   - 只测试了 `thread.started`, `turn.started`, `item.completed`, `turn.completed`
   - 未测试 `item.started`, `item.updated`, `turn.failed`, `error`

### 改进建议

1. **增加测试覆盖**
   ```typescript
   // 建议：从 run.test.ts 移植相关测试
   describe("configuration with streaming", () => {
     it("passes model to exec when streaming", ...);
     it("passes sandboxMode to exec when streaming", ...);
     // ... 其他配置选项
   });
   ```

2. **错误处理测试**
   ```typescript
   it("emits turn.failed on error", async () => {
     const { url, close } = await startResponsesTestProxy({
       responseBodies: [
         sse(responseStarted(), responseFailed("rate limit")),
       ],
     });
     // 验证 turn.failed 事件被正确发出
   });

   it("handles stream interruption", async () => {
     const result = await thread.runStreamed("input");
     const iterator = result.events[Symbol.asyncIterator]();
     await iterator.next();  // 获取第一个事件
     await iterator.return?.();  // 提前终止
     // 验证资源已清理
   });
   ```

3. **改进 drainEvents**
   ```typescript
   async function drainEvents(events: AsyncGenerator<ThreadEvent>): Promise<ThreadEvent[]> {
     const collected: ThreadEvent[] = [];
     try {
       for await (const event of events) {
         collected.push(event);
       }
     } catch (error) {
       // 记录错误但继续返回已收集的事件
       console.error("Error draining events:", error);
       throw error;
     }
     return collected;
   }
   ```

4. **测试所有事件类型**
   ```typescript
   it("emits all event types", async () => {
     const { url, close } = await startResponsesTestProxy({
       responseBodies: [
         sse(
           responseStarted(),
           { type: "item.started", item: { id: "1", type: "agent_message" } },
           { type: "item.updated", item: { id: "1", type: "agent_message", text: "partial" } },
           assistantMessage("complete"),
           responseCompleted()
         ),
       ],
     });
     // 验证所有事件类型都被正确解析和传递
   });
   ```

5. **背压测试**
   ```typescript
   it("handles backpressure", async () => {
     const { url, close } = await startResponsesTestProxy({
       responseBodies: [
         // 生成大量事件
         sse(...Array(1000).fill(assistantMessage("x"))),
       ],
     });
     const result = await thread.runStreamed("input");
     // 缓慢消费事件，验证不会内存溢出
     for await (const event of result.events) {
       await delay(1);
     }
   });
   ```

6. **与 abort.test.ts 整合**
   ```typescript
   // 建议：将流式取消测试从 abort.test.ts 移动到这里
   describe("cancellation", () => {
     it("aborts streaming when signal is triggered", ...);
   });
   ```

7. **部分消费测试**
   ```typescript
   it("cleans up resources when iteration is interrupted", async () => {
     const { schemaPath, cleanup } = await createOutputSchemaFile({...});
     const result = await thread.runStreamed("input", { outputSchema: {...} });
     
     // 只消费一个事件
     await result.events.next();
     
     // 验证临时文件仍然存在（因为 finally 还没执行）
     expect(fs.existsSync(schemaPath)).toBe(true);
     
     // 继续消费直到结束
     await drainEvents(result.events);
     
     // 验证临时文件已清理
     expect(fs.existsSync(schemaPath)).toBe(false);
   });
   ```

8. **事件顺序灵活性**
   ```typescript
   // 建议：使用更灵活的匹配
   expect(events).toContainEqual(expect.objectContaining({ type: "thread.started" }));
   expect(events).toContainEqual(expect.objectContaining({ type: "turn.completed" }));
   // 而不是严格的数组相等
   ```
