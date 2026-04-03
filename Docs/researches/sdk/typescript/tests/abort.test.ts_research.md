# abort.test.ts 研究文档

## 场景与职责

本测试文件专注于验证 TypeScript SDK 的 **AbortSignal 支持**功能，确保用户可以通过标准的 Web `AbortController` 机制取消正在进行的 AI 对话操作。这是 SDK 提供良好用户体验的关键功能，允许用户在长时间运行的 AI 操作需要中断时进行优雅取消。

测试场景覆盖：
1. 在操作开始前已取消的信号
2. 在操作执行过程中取消信号
3. 流式操作 (`runStreamed`) 的取消支持
4. 正常未取消情况下的操作完成

## 功能点目的

### AbortSignal 集成目的
- **用户控制**：允许用户随时取消正在进行的 AI 请求
- **资源清理**：确保取消后相关资源（子进程、网络连接）被正确释放
- **标准兼容**：遵循 Web 标准的 `AbortSignal` API，与前端/Node.js 生态保持一致

### 测试覆盖范围
| 测试用例 | 描述 |
|---------|------|
| `aborts run() when signal is aborted` | 验证 `run()` 在已取消信号下立即抛出错误 |
| `aborts runStreamed() when signal is aborted` | 验证 `runStreamed()` 在已取消信号下迭代器立即抛出错误 |
| `aborts run() when signal is aborted during execution` | 验证执行过程中取消信号能终止操作 |
| `aborts runStreamed() when signal is aborted during iteration` | 验证流式迭代过程中取消信号能终止迭代 |
| `completes normally when signal is not aborted` | 验证未取消信号下操作正常完成 |

## 具体技术实现

### 关键流程

#### 1. 无限响应生成器
```typescript
function* infiniteShellCall(): Generator<SseResponseBody> {
  while (true) {
    yield sse(responseStarted(), shellCall(), responseCompleted());
  }
}
```
- 用于模拟长时间运行的 AI 对话
- 无限循环产生 shell 调用事件，确保测试可以控制取消时机

#### 2. 预取消信号测试流程
```typescript
const controller = new AbortController();
controller.abort("Test abort");  // 预先取消
await expect(thread.run("Hello, world!", { signal: controller.signal })).rejects.toThrow();
```

#### 3. 执行中取消测试流程
```typescript
const controller = new AbortController();
const runPromise = thread.run("Hello, world!", { signal: controller.signal });
setTimeout(() => controller.abort("Aborted during execution"), 10);
await expect(runPromise).rejects.toThrow();
```

#### 4. 流式迭代中取消测试流程
```typescript
const { events } = await thread.runStreamed("Hello, world!", { signal: controller.signal });
for await (const event of events) {
  eventCount++;
  if (eventCount === 5) {
    controller.abort("Aborted during iteration");
  }
}
```

### 数据结构

#### AbortController / AbortSignal
- 标准 Web API，Node.js 18+ 原生支持
- `controller.abort(reason)` - 触发取消
- `signal.aborted` - 检查是否已取消
- `signal.reason` - 获取取消原因

#### 测试辅助类型
```typescript
// 来自 responsesProxy.ts
SseResponseBody = { kind: "sse"; events: SseEvent[] }
SseEvent = { type: string; [key: string]: unknown }
```

### 协议与命令

#### SSE 事件序列（模拟）
```
event: response.created
data: {"type":"response.created","response":{"id":"resp_mock"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{...shell call...}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_mock","usage":...}}
```

#### CLI 命令参数
```
codex exec --experimental-json [options] [resume <threadId>]
```
- `--experimental-json`: 启用 JSON 行输出模式
- `signal` 通过 `spawn` 的 `options.signal` 传递

## 关键代码路径与文件引用

### 测试文件
- `sdk/typescript/tests/abort.test.ts` - 本测试文件

### 被测试代码
- `sdk/typescript/src/thread.ts` (lines 66-112)
  - `runStreamed()` 方法接收 `TurnOptions.signal`
  - `runStreamedInternal()` 将 signal 传递给 `CodexExec.run()`
  
- `sdk/typescript/src/exec.ts` (lines 72-226)
  - `CodexExec.run()` 接收 `CodexExecArgs.signal`
  - Line 166: `spawn(this.executablePath, commandArgs, { env, signal: args.signal })`
  - Node.js 的 `child_process.spawn` 原生支持 `AbortSignal`

- `sdk/typescript/src/turnOptions.ts` (lines 1-6)
  ```typescript
  export type TurnOptions = {
    outputSchema?: unknown;
    signal?: AbortSignal;  // 取消信号
  };
  ```

### 测试依赖
- `sdk/typescript/tests/responsesProxy.ts` - SSE 测试代理服务器
- `sdk/typescript/tests/testCodex.ts` - 测试客户端工厂

### 调用链
```
abort.test.ts
  → thread.run(input, { signal })
    → Thread.runStreamedInternal() (thread.ts:70-112)
      → CodexExec.run({ signal, ... }) (exec.ts:72)
        → spawn(codexPath, args, { signal }) (exec.ts:164-167)
          → Node.js child_process (系统调用)
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `@jest/globals` | 测试框架 API (describe, expect, it) |
| `node:child_process` | 被 mock 用于验证 spawn 调用 |
| `AbortController` | Web 标准 API，Node.js 18+ 内置 |

### 测试辅助模块
| 模块 | 功能 |
|-----|------|
| `responsesProxy.ts` | 启动本地 HTTP 代理模拟 OpenAI Responses API |
| `testCodex.ts` | 创建配置好的 Codex 测试客户端 |

### 二进制依赖
- `codex-rs/target/debug/codex` - Rust CLI 二进制文件路径（由 `testCodex.ts` 定义）

## 风险、边界与改进建议

### 当前风险

1. **无限生成器资源泄漏**
   - `infiniteShellCall()` 生成器在测试结束后可能仍在内存中
   - 虽然测试通过 `close()` 关闭代理服务器，但生成器引用可能未完全释放

2. **竞态条件**
   - `setTimeout(() => controller.abort(), 10)` 依赖时间假设
   - 在慢速机器上可能操作已完成才触发取消

3. **错误消息验证不足**
   - 仅验证 `rejects.toThrow()`，未验证具体错误消息
   - 无法区分是预期取消错误还是其他意外错误

### 边界情况

1. **已取消信号检测**
   - 测试验证当 `signal.aborted === true` 时操作立即失败
   - 这是 Node.js spawn 的原生行为

2. **流式迭代边界**
   - `runStreamed()` 返回的 `events` 是 `AsyncGenerator`
   - 取消后 `for await...of` 循环应抛出 `AbortError`

3. **多次取消调用**
   - 未测试重复调用 `controller.abort()` 的行为
   - 未测试不同取消原因的影响

### 改进建议

1. **增强错误验证**
   ```typescript
   // 建议：验证具体错误类型
   await expect(thread.run(...)).rejects.toThrow(AbortError);
   await expect(thread.run(...)).rejects.toHaveProperty('name', 'AbortError');
   ```

2. **添加资源清理验证**
   ```typescript
   // 建议：验证子进程已终止
   expect(child.killed).toBe(true);
   ```

3. **测试超时保护**
   - 无限生成器测试应有全局超时保护
   - 当前依赖 Jest 默认超时（5秒），可能不够明确

4. **并发取消测试**
   ```typescript
   // 建议：测试多个并发操作的取消隔离
   it("isolates abort between concurrent threads", ...)
   ```

5. **流式数据完整性**
   - 当前测试仅验证取消时抛出错误
   - 应验证取消前已接收的数据是完整的

6. **CLI 信号传播测试**
   - 验证 `SIGTERM`/`SIGKILL` 是否正确传播到 Rust CLI 进程
   - 验证临时文件（如 output schema）在取消后是否清理
