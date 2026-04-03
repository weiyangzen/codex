# responsesProxy.ts 研究文档

## 场景与职责

本模块是一个 **HTTP 测试代理服务器**，用于在测试中模拟 OpenAI Responses API 的行为。它允许测试在不依赖真实 OpenAI API 的情况下验证 SDK 的 HTTP 通信逻辑，是 TypeScript SDK 集成测试的核心基础设施。

主要使用场景：
1. 模拟 OpenAI Responses API 的 SSE (Server-Sent Events) 响应
2. 记录和验证 SDK 发送的 HTTP 请求内容
3. 测试各种响应场景（成功、错误、流式数据）
4. 验证请求头、请求体格式和认证信息

## 功能点目的

### 代理服务器功能目的
- **API 模拟**：提供与 OpenAI Responses API 兼容的端点
- **请求记录**：捕获所有传入请求供测试验证
- **响应控制**：允许测试精确控制响应内容和状态码
- **SSE 支持**：模拟服务器发送事件流

### 解决的问题
| 问题 | 解决方案 |
|-----|---------|
| 依赖外部 API 不稳定 | 本地 HTTP 服务器模拟 |
| 无法验证请求内容 | 记录所有请求体、头信息 |
| 难以测试错误场景 | 可配置的 `statusCode` 和错误响应 |
| 需要无限流测试 | 支持 Generator 模式的响应体 |

## 具体技术实现

### 关键流程

#### 1. 服务器创建和启动
```typescript
export async function startResponsesTestProxy(options: ResponsesProxyOptions): Promise<ResponsesProxy> {
  // 将数组转换为生成器
  const responseBodies: Generator<SseResponseBody> = Array.isArray(options.responseBodies)
    ? createGenerator(options.responseBodies)
    : options.responseBodies;

  const requests: RecordedRequest[] = [];

  const server = http.createServer((req, res) => {
    async function handle(): Promise<void> {
      if (req.method === "POST" && req.url === "/responses") {
        const body = await readRequestBody(req);
        const json = JSON.parse(body);
        requests.push({ body, json, headers: { ...req.headers } });

        const status = options.statusCode ?? 200;
        res.statusCode = status;
        res.setHeader("content-type", "text/event-stream");

        const responseBody = responseBodies.next().value;
        for (const event of responseBody.events) {
          res.write(formatSseEvent(event));
        }
        res.end();
        return;
      }
      res.statusCode = 404;
      res.end();
    }
    handle().catch(() => { res.statusCode = 500; res.end(); });
  });

  // 绑定到随机端口
  const url = await new Promise<string>((resolve, reject) => {
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("Unable to determine proxy address"));
        return;
      }
      resolve(`http://${info.address}:${info.port}`);
    });
  });

  return { url, close, requests };
}
```

#### 2. 请求体读取
```typescript
function readRequestBody(req: http.IncomingMessage): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk) => {
      chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
    });
    req.on("end", () => {
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    req.on("error", reject);
  });
}
```

#### 3. SSE 事件格式化
```typescript
function formatSseEvent(event: SseEvent): string {
  return `event: ${event.type}\n` + `data: ${JSON.stringify(event)}\n\n`;
}
// 输出示例：
// event: response.created
// data: {"type":"response.created","response":{"id":"resp_mock"}}
//
```

#### 4. 响应生成器
```typescript
function* createGenerator(array: SseResponseBody[]): Generator<SseResponseBody> {
  for (const elem of array) {
    yield elem;
  }
  throw new Error("not enough responses provided");
}
```
- 当测试提供的响应数组耗尽时抛出错误
- 防止测试意外继续而得不到响应

### 数据结构

#### 核心类型定义
```typescript
// SSE 事件
export type SseEvent = {
  type: string;
  [key: string]: unknown;
};

// SSE 响应体（一组事件）
export type SseResponseBody = {
  kind: "sse";
  events: SseEvent[];
};

// 代理服务器选项
export type ResponsesProxyOptions = {
  responseBodies: Generator<SseResponseBody> | SseResponseBody[];
  statusCode?: number;
};

// 代理服务器实例
export type ResponsesProxy = {
  url: string;                    // 服务器地址，如 "http://127.0.0.1:54321"
  close: () => Promise<void>;     // 关闭服务器
  requests: RecordedRequest[];    // 记录的所有请求
};

// 记录的请求
export type RecordedRequest = {
  body: string;                   // 原始请求体 JSON
  json: ResponsesApiRequest;      // 解析后的请求对象
  headers: http.IncomingHttpHeaders;
};

// OpenAI Responses API 请求结构
export type ResponsesApiRequest = {
  model?: string;
  input: Array<{
    role: string;
    content?: Array<{ type: string; text: string }>;
  }>;
  text?: {
    format?: Record<string, unknown>;
  };
};
```

### 辅助函数

#### SSE 事件构建器
```typescript
export function sse(...events: SseEvent[]): SseResponseBody {
  return { kind: "sse", events };
}

export function responseStarted(responseId: string = DEFAULT_RESPONSE_ID): SseEvent {
  return {
    type: "response.created",
    response: { id: responseId },
  };
}

export function assistantMessage(text: string, itemId: string = DEFAULT_MESSAGE_ID): SseEvent {
  return {
    type: "response.output_item.done",
    item: {
      type: "message",
      role: "assistant",
      id: itemId,
      content: [{ type: "output_text", text }],
    },
  };
}

export function shell_call(): SseEvent {
  return {
    type: "response.output_item.done",
    item: {
      type: "function_call",
      call_id: `call_id${Math.random().toString(36).slice(2)}`,
      name: "shell",
      arguments: JSON.stringify({ command: ["bash", "-lc", "echo 'Hello, world!'"], timeout_ms: 100 }),
    },
  };
}

export function responseCompleted(responseId: string, usage: ResponseCompletedUsage): SseEvent {
  return {
    type: "response.completed",
    response: { id: responseId, usage: { ... } },
  };
}

export function responseFailed(errorMessage: string): SseEvent {
  return {
    type: "error",
    error: { code: "rate_limit_exceeded", message: errorMessage },
  };
}
```

## 关键代码路径与文件引用

### 本模块
- `sdk/typescript/tests/responsesProxy.ts` - 本文件 (225 行)

### 使用本模块的测试
| 测试文件 | 使用场景 |
|---------|---------|
| `abort.test.ts` | 所有测试用例 |
| `run.test.ts` | 所有测试用例 |
| `runStreamed.test.ts` | 所有测试用例 |

### 被模拟的 API
- OpenAI Responses API (`/responses` 端点)
- SSE (Server-Sent Events) 协议

### 调用链
```
test file
  → startResponsesTestProxy({ responseBodies: [...], statusCode: 200 })
    → http.createServer()
    → server.listen(0, "127.0.0.1")  // 随机端口
  → createMockClient(url)
    → new Codex({ config: { model_providers: { mock: { base_url: url } } } })
  → thread.run("input")
    → CodexExec.run()
      → spawn(codex, [..., "--config", `openai_base_url=${url}`])
        → Rust CLI 发送 HTTP 请求到代理服务器
  → proxy server receives POST /responses
    → records request
    → responseBodies.next()
    → res.write(formatSseEvent(event))
  → Rust CLI receives SSE stream
    → outputs JSONL events
  → CodexExec.run() yields JSON lines
  → Thread processes events
  → test assertions on proxy.requests
  → close()
    → server.close()
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `node:http` | HTTP 服务器实现 |

### Node.js API 使用
| API | 用途 |
|-----|------|
| `http.createServer()` | 创建 HTTP 服务器 |
| `server.listen(port, host)` | 绑定到地址和端口 |
| `server.address()` | 获取实际绑定的地址 |
| `server.close()` | 关闭服务器 |
| `IncomingMessage` | HTTP 请求对象 |
| `ServerResponse` | HTTP 响应对象 |

### 与 Rust CLI 的集成
代理服务器模拟的是 OpenAI API，但实际交互流程是：
1. SDK 启动 Rust CLI 子进程
2. CLI 读取 `--config openai_base_url=<proxy_url>`
3. CLI 发送 HTTP 请求到代理服务器（而非真实的 OpenAI API）
4. 代理返回 SSE 事件
5. CLI 将事件转换为 JSONL 输出到 stdout

## 风险、边界与改进建议

### 当前风险

1. **端口竞争**
   ```typescript
   server.listen(0, "127.0.0.1")
   ```
   - 虽然使用端口 0 让系统分配随机端口，但在高并发测试下仍可能遇到端口耗尽
   - 未处理 `EADDRINUSE` 错误重试

2. **请求体大小限制**
   ```typescript
   req.on("data", (chunk) => { chunks.push(chunk); });
   ```
   - 未设置请求体大小限制
   - 恶意或错误的测试可能导致内存溢出

3. **生成器耗尽错误**
   ```typescript
   throw new Error("not enough responses provided");
   ```
   - 当测试请求数超过提供的响应数时抛出错误
   - 错误消息不够友好，难以定位问题

4. **未处理的路由**
   - 只处理 `POST /responses`，其他路由返回 404
   - 未模拟其他 OpenAI API 端点（如 `/chat/completions`）

5. **SSE 格式简化**
   - 只实现了最基本的 SSE 格式（`event:` 和 `data:`）
   - 未实现 `id:`、`retry:` 等字段

### 边界情况

1. **并发请求**
   - 当前实现按顺序从生成器获取响应
   - 如果多个请求同时到达，它们会竞争 `responseBodies.next()`
   - 这在实际测试中可能不是大问题，因为通常一次只有一个请求

2. **连接断开**
   - 未处理客户端提前断开连接的情况
   - 如果测试取消操作，服务器可能仍在尝试写入响应

3. **JSON 解析错误**
   ```typescript
   const json = JSON.parse(body);
   ```
   - 如果请求体不是有效的 JSON，会抛出错误
   - 虽然被 `handle().catch()` 捕获，但返回 500 可能不够精确

4. **头信息复制**
   ```typescript
   requests.push({ body, json, headers: { ...req.headers } });
   ```
   - 浅拷贝头信息，如果头信息值是数组，可能被修改

### 改进建议

1. **添加请求超时**
   ```typescript
   server.timeout = 30000;  // 30秒超时
   ```

2. **限制请求体大小**
   ```typescript
   const MAX_BODY_SIZE = 10 * 1024 * 1024;  // 10MB
   let totalSize = 0;
   req.on("data", (chunk) => {
     totalSize += chunk.length;
     if (totalSize > MAX_BODY_SIZE) {
       req.destroy();
       return;
     }
     chunks.push(chunk);
   });
   ```

3. **更好的错误消息**
   ```typescript
   function* createGenerator(array: SseResponseBody[], testName?: string): Generator<SseResponseBody> {
     for (const elem of array) {
       yield elem;
     }
     throw new Error(
       `Not enough responses provided in ${testName || "test"}. ` +
       `Expected ${array.length} responses but more were requested.`
     );
   }
   ```

4. **支持更多 SSE 功能**
   ```typescript
   export type SseEvent = {
     type: string;
     id?: string;
     retry?: number;
     [key: string]: unknown;
   };
   
   function formatSseEvent(event: SseEvent): string {
     let result = `event: ${event.type}\n`;
     if (event.id) result += `id: ${event.id}\n`;
     if (event.retry) result += `retry: ${event.retry}\n`;
     result += `data: ${JSON.stringify(event)}\n\n`;
     return result;
   }
   ```

5. **请求匹配和路由**
   ```typescript
   // 支持基于请求内容的路由
   export type ResponseRoute = {
     match: (req: http.IncomingMessage, body: unknown) => boolean;
     response: SseResponseBody | ((req: RecordedRequest) => SseResponseBody);
   };
   ```

6. **WebSocket 支持**
   - OpenAI API 支持 WebSocket 流
   - 当前代理只支持 SSE
   - 如果需要测试 WebSocket 场景，需要扩展

7. **请求验证辅助函数**
   ```typescript
   export function assertRequestContains(request: RecordedRequest, path: string, value: unknown): void {
     const actual = path.split('.').reduce((obj, key) => obj?.[key], request.json);
     expect(actual).toEqual(value);
   }
   ```

8. **并发控制**
   ```typescript
   // 支持按顺序或按请求 ID 匹配响应
   export type ResponsesProxyOptions = {
     responseBodies: SseResponseBody[];
     matchBy?: "sequence" | "requestId";  // 按顺序或按请求 ID
   };
   ```
