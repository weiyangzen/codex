# exec.test.ts 研究文档

## 场景与职责

本测试文件专注于验证 `CodexExec` 类的核心执行逻辑，这是 TypeScript SDK 与 Rust CLI 二进制文件交互的关键层。测试覆盖子进程管理、参数序列化、环境变量隔离等底层功能。

测试场景覆盖：
1. 子进程异常退出处理（stdout 关闭前退出）
2. 命令行参数顺序验证（resume 参数在 image 参数之前）
3. 环境变量隔离和覆盖机制

## 功能点目的

### CodexExec 测试目的
- **进程生命周期**：验证子进程异常退出时的错误处理
- **参数正确性**：验证 CLI 参数的顺序和格式
- **环境隔离**：验证环境变量的正确传递和隔离

### 测试覆盖范围
| 测试用例 | 描述 |
|---------|------|
| `rejects when exit happens before stdout closes` | 验证子进程提前退出时抛出错误 |
| `places resume args before image args` | 验证 `resume <threadId>` 在 `--image` 之前 |
| `allows overriding the env passed to the Codex CLI` | 验证环境变量覆盖和隔离 |

## 具体技术实现

### 关键流程

#### 1. FakeChildProcess 模拟器
```typescript
class FakeChildProcess extends EventEmitter {
  stdin = new PassThrough();
  stdout = new PassThrough();
  stderr = new PassThrough();
  killed = false;

  kill(): boolean {
    this.killed = true;
    return true;
  }
}
```
- 模拟真实的 `ChildProcess` 对象
- 使用 `PassThrough` 流模拟标准 IO
- 继承 `EventEmitter` 支持事件触发

#### 2. 提前退出模拟
```typescript
function createEarlyExitChild(exitCode = 2): FakeChildProcess {
  const child = new FakeChildProcess();
  setImmediate(() => {
    child.stderr.write("boom");
    child.emit("exit", exitCode, null);
    setImmediate(() => {
      child.stdout.end();
      child.stderr.end();
    });
  });
  return child;
}
```
- 模拟 stderr 输出后立即退出
- 使用 `setImmediate` 确保异步事件顺序
- 验证 `CodexExec` 能正确处理这种异常

#### 3. 参数顺序验证
```typescript
const commandArgs = spawnMock.mock.calls[0]?.[1] as string[];
const resumeIndex = commandArgs!.indexOf("resume");
const imageIndex = commandArgs!.indexOf("--image");
expect(resumeIndex).toBeLessThan(imageIndex);
```

#### 4. 环境变量验证
```typescript
expect(spawnEnv.CODEX_HOME).toBe("/tmp/codex-home");
expect(spawnEnv.CUSTOM_ENV).toBe("custom");
expect(spawnEnv.CODEX_ENV_SHOULD_NOT_LEAK).toBeUndefined();
expect(spawnEnv.OPENAI_BASE_URL).toBeUndefined();
expect(spawnEnv.CODEX_API_KEY).toBe("test");
```

### 数据结构

#### FakeChildProcess
```typescript
class FakeChildProcess extends EventEmitter {
  stdin: PassThrough;    // 可写流，接收输入
  stdout: PassThrough;   // 可读流，输出响应
  stderr: PassThrough;   // 可读流，错误输出
  killed: boolean;       // 是否已终止
  kill(): boolean;       // 终止方法
}
```

#### SpawnMock 调用记录
```typescript
spawnMock.mock.calls: Array<[
  command: string,           // 命令路径
  args: string[] | undefined, // 参数数组
  options: SpawnOptions | undefined  // 选项
]>
```

### 协议与命令

#### 命令行参数结构
```
codex exec --experimental-json \
  --config openai_base_url=... \
  --model <model> \
  --sandbox <mode> \
  --cd <workingDirectory> \
  --add-dir <dir1> \
  --add-dir <dir2> \
  --skip-git-repo-check \
  --output-schema <schemaPath> \
  --config model_reasoning_effort="..." \
  --config sandbox_workspace_write.network_access=true \
  --config web_search="..." \
  --config approval_policy="..." \
  resume <threadId> \
  --image <image1> \
  --image <image2>
```

#### 环境变量规则
| 变量 | 来源 | 说明 |
|-----|------|------|
| `CODEX_API_KEY` | `args.apiKey` | 从参数传递 |
| `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` | 自动设置 | 标识 SDK 类型 |
| `OPENAI_BASE_URL` | 通过 `--config` 传递 | 不直接设置环境变量 |
| 其他 `process.env` | 继承或覆盖 | 取决于 `envOverride` |

## 关键代码路径与文件引用

### 测试文件
- `sdk/typescript/tests/exec.test.ts` - 本测试文件 (146 行)

### 被测试代码
- `sdk/typescript/src/exec.ts` - `CodexExec` 类实现
  - Lines 57-227: `CodexExec` 类定义
  - Lines 72-226: `run()` 方法 - 核心执行逻辑
  - Lines 229-315: 配置序列化辅助函数

### 关键代码路径详解

#### 1. 异常退出检测 (exec.ts:191-216)
```typescript
const exitPromise = new Promise<{ code: number | null; signal: NodeJS.Signals | null }>(
  (resolve) => {
    child.once("exit", (code, signal) => {
      resolve({ code, signal });
    });
  },
);

// ...

const { code, signal } = await exitPromise;
if (code !== 0 || signal) {
  const stderrBuffer = Buffer.concat(stderrChunks);
  const detail = signal ? `signal ${signal}` : `code ${code ?? 1}`;
  throw new Error(`Codex Exec exited with ${detail}: ${stderrBuffer.toString("utf8")}`);
}
```

#### 2. 参数构建 (exec.ts:72-145)
```typescript
const commandArgs: string[] = ["exec", "--experimental-json"];
// ... 各种条件添加参数
if (args.threadId) {
  commandArgs.push("resume", args.threadId);  // Line 138-139
}
if (args.images?.length) {
  for (const image of args.images) {
    commandArgs.push("--image", image);  // Line 141-145
  }
}
```

#### 3. 环境变量构建 (exec.ts:147-162)
```typescript
const env: Record<string, string> = {};
if (this.envOverride) {
  Object.assign(env, this.envOverride);  // 完全覆盖
} else {
  for (const [key, value] of Object.entries(process.env)) {
    if (value !== undefined) {
      env[key] = value;  // 继承 process.env
    }
  }
}
if (!env[INTERNAL_ORIGINATOR_ENV]) {
  env[INTERNAL_ORIGINATOR_ENV] = TYPESCRIPT_SDK_ORIGINATOR;
}
if (args.apiKey) {
  env.CODEX_API_KEY = args.apiKey;
}
```

### 调用链
```
exec.test.ts
  → import("../src/exec").CodexExec  // 动态导入获取被 mock 的模块
  → new CodexExec("codex")
  → exec.run({ input: "hi", ... })
    → spawn(codexPath, commandArgs, { env, signal })
      → [MOCKED by FakeChildProcess]
  → FakeChildProcess.emit("exit", code, null)
  → exec.run() throws Error
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `node:child_process` | 被 mock 用于测试 |
| `node:events` | `EventEmitter` 基类 |
| `node:stream` | `PassThrough` 流 |
| `@jest/globals` | 测试框架 |

### Mock 设置
```typescript
jest.mock("node:child_process", () => {
  const actual = jest.requireActual<typeof import("node:child_process")>("node:child_process");
  return { ...actual, spawn: jest.fn() };  // 完全 mock spawn
});
```
- 与 `codexExecSpy.ts` 不同，这里完全 mock 而不代理到真实实现
- 测试不依赖真实的 Rust CLI 二进制文件

### 辅助函数
```typescript
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
```
- 用于超时测试，确保测试不会永远挂起

## 风险、边界与改进建议

### 当前风险

1. **动态导入依赖**
   ```typescript
   const { CodexExec } = await import("../src/exec");
   ```
   - 每个测试都动态导入，可能导致性能问题
   - 但这是必要的，因为 `jest.mock` 在模块级别执行，需要确保 mock 已应用

2. **不完全的 ChildProcess 模拟**
   - `FakeChildProcess` 只实现了测试需要的最小接口
   - 如果 `CodexExec` 使用其他 `ChildProcess` 属性，测试可能失败

3. **事件顺序假设**
   ```typescript
   setImmediate(() => {
     child.stderr.write("boom");
     child.emit("exit", exitCode, null);
     setImmediate(() => {
       child.stdout.end();
       child.stderr.end();
     });
   });
   ```
   - 嵌套的 `setImmediate` 依赖特定的事件循环行为
   - 在不同 Node.js 版本或 Jest 配置下可能表现不同

4. **竞态条件测试**
   ```typescript
   const result = await Promise.race([
     runPromise,
     delay(500).then(() => ({ status: "timeout" as const })),
   ]);
   ```
   - 500ms 超时是任意的，在慢速机器上可能导致误报

### 边界情况

1. **stdout 关闭顺序**
   - 测试验证 "exit happens before stdout closes"
   - 实际场景中，stdout 可能在 exit 之前或之后关闭
   - `CodexExec` 使用 `readline` 接口，在流结束时自动关闭

2. **环境变量继承**
   - 测试验证 `envOverride` 完全替换 `process.env`
   - 但未测试 `envOverride` 与 `process.env` 的合并场景

3. **信号处理**
   - 只测试了正常退出（`signal: null`）
   - 未测试 `SIGTERM`、`SIGKILL` 等信号场景

### 改进建议

1. **添加更多退出场景测试**
   ```typescript
   it("handles SIGTERM signal", async () => {
     const child = new FakeChildProcess();
     spawnMock.mockReturnValue(child as unknown as child_process.ChildProcess);
     
     setImmediate(() => {
       child.emit("exit", null, "SIGTERM");
     });
     
     const exec = new CodexExec("codex");
     await expect(
       (async () => {
         for await (const _ of exec.run({ input: "hi" })) {}
       })()
     ).rejects.toThrow(/signal SIGTERM/);
   });
   ```

2. **测试环境变量合并**
   ```typescript
   it("merges envOverride with process.env when requested", async () => {
     // 建议：添加新的配置选项控制继承行为
     const exec = new CodexExec("codex", { inheritEnv: true, env: { CUSTOM: "value" } });
   });
   ```

3. **更稳定的超时机制**
   ```typescript
   // 建议：使用 Jest 的 fake timers
   jest.useFakeTimers();
   // 或者增加超时时间
   const TIMEOUT = process.env.CI ? 2000 : 500;
   ```

4. **验证 stderr 内容**
   ```typescript
   // 当前测试只验证错误抛出
   // 建议：验证 stderr 内容包含在错误消息中
   expect(result.error.message).toContain("boom");
   ```

5. **测试更多参数组合**
   ```typescript
   // 建议：测试所有可选参数的组合
   it("handles all optional parameters", async () => {
     const exec = new CodexExec("codex");
     for await (const _ of exec.run({
       input: "test",
       baseUrl: "...",
       apiKey: "...",
       threadId: "...",
       images: ["..."],
       model: "...",
       // ... 所有参数
     })) {}
   });
   ```

6. **验证 stdin 写入**
   ```typescript
   // 建议：验证输入正确传递给子进程
   const stdinChunks: Buffer[] = [];
   child.stdin.on("data", (chunk) => stdinChunks.push(chunk));
   // 验证 Buffer.concat(stdinChunks).toString() === input
   ```

7. **资源清理验证**
   ```typescript
   // 建议：验证 readline 接口和子进程监听器已清理
   expect(child.listenerCount("exit")).toBe(0);
   expect(child.listenerCount("error")).toBe(0);
   ```
