# codexExecSpy.ts 研究文档

## 场景与职责

本模块是一个 **Jest Mock 工具**，用于在测试中拦截和监控对 `node:child_process.spawn` 的调用。它是 TypeScript SDK 测试基础设施的关键组件，使测试能够验证 Codex CLI 二进制文件的调用参数和环境变量，而无需实际执行子进程。

主要使用场景：
1. 验证 CLI 命令行参数的正确性
2. 验证环境变量的传递和隔离
3. 验证配置覆盖的序列化格式
4. 在不需要实际执行 CLI 的情况下进行单元测试

## 功能点目的

### Mock 功能目的
- **调用拦截**：捕获所有 `child_process.spawn` 调用，记录参数
- **透明代理**：在记录参数后，仍调用真实的 spawn 实现，保持测试行为真实
- **可恢复状态**：提供 `restore()` 方法清理 mock 状态，避免测试间污染

### 解决的问题
| 问题 | 解决方案 |
|-----|---------|
| 无法验证 CLI 调用参数 | 记录 `spawn(command, args, options)` 的所有参数 |
| 无法验证环境变量隔离 | 记录 `options.env` 对象 |
| 测试间状态污染 | 提供 `restore()` 清理 mock |
| 需要真实执行但又要验证 | 代理到真实实现，先记录后执行 |

## 具体技术实现

### 关键流程

#### 1. Module Mock 设置
```typescript
jest.mock("node:child_process", () => {
  const actual = jest.requireActual<typeof import("node:child_process")>("node:child_process");
  return { ...actual, spawn: jest.fn(actual.spawn) };
});
```
- 使用 Jest 的 `jest.mock` 自动 mock 整个模块
- 保留所有原始导出，仅替换 `spawn` 为 `jest.fn(actual.spawn)`
- 这样 `spawn` 是一个包装了真实实现的 mock 函数

#### 2. Spy 工厂函数
```typescript
export function codexExecSpy(): {
  args: string[][];      // 记录所有调用的参数数组
  envs: (Record<string, string> | undefined)[];  // 记录所有调用的环境变量
  restore: () => void;   // 恢复原始实现的函数
} {
  const previousImplementation = spawnMock.getMockImplementation() ?? actualChildProcess.spawn;
  const args: string[][] = [];
  const envs: (Record<string, string> | undefined)[] = [];

  spawnMock.mockImplementation(((...spawnArgs: Parameters<typeof child_process.spawn>) => {
    const commandArgs = spawnArgs[1];
    args.push(Array.isArray(commandArgs) ? [...commandArgs] : []);
    const options = spawnArgs[2] as child_process.SpawnOptions | undefined;
    envs.push(options?.env as Record<string, string> | undefined);
    return previousImplementation(...spawnArgs);  // 代理到真实实现
  }) as typeof actualChildProcess.spawn);

  return { args, envs, restore: () => { ... } };
}
```

#### 3. 参数提取逻辑
```typescript
// spawnArgs[0] = command (string)
// spawnArgs[1] = args (string[])
// spawnArgs[2] = options (SpawnOptions)
const commandArgs = spawnArgs[1];
args.push(Array.isArray(commandArgs) ? [...commandArgs] : []);

const options = spawnArgs[2] as child_process.SpawnOptions | undefined;
envs.push(options?.env as Record<string, string> | undefined);
```

#### 4. 恢复机制
```typescript
restore: () => {
  spawnMock.mockClear();           // 清除调用记录
  spawnMock.mockImplementation(previousImplementation);  // 恢复实现
}
```

### 数据结构

#### 返回类型
```typescript
{
  args: string[][];      // 每次调用的参数数组，如 [["exec", "--json", "resume", "thread-1"]]
  envs: (Record<string, string> | undefined)[];  // 每次调用的环境变量
  restore: () => void;   // 清理函数
}
```

#### SpawnOptions 类型
```typescript
interface SpawnOptions {
  env?: NodeJS.ProcessEnv;  // 环境变量
  cwd?: string;             // 工作目录
  stdio?: StdioOptions;     // 标准 IO 配置
  // ... 其他选项
}
```

## 关键代码路径与文件引用

### 本模块
- `sdk/typescript/tests/codexExecSpy.ts` - 本文件 (37 行)

### 使用本模块的测试
- `sdk/typescript/tests/run.test.ts` (lines 197, 236, 267, 298, 329, 360, 391, 422, 463, 500, 542, 628, 675)
- `sdk/typescript/tests/exec.test.ts` (未直接使用，但有类似的 mock 设置)

### 被 Mock 的模块
- `node:child_process` - Node.js 内置模块

### 调用链
```
test file
  → codexExecSpy()
    → jest.mock("node:child_process")  // 模块级别
    → spawnMock.mockImplementation(...) // 运行时拦截
      → actualChildProcess.spawn(...)   // 代理到真实实现
  → exec.run(args)  // 被测试代码
    → spawn(codexPath, commandArgs, { env })
      → [INTERCEPTED BY MOCK]
  → test assertions on spy.args, spy.envs
  → spy.restore()  // 清理
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `node:child_process` | 被 mock 的目标模块 |
| `jest` | 提供 `jest.mock`, `jest.fn`, `jest.requireActual` |

### Jest API 使用
| API | 用途 |
|-----|------|
| `jest.mock()` | 模块级别自动 mock |
| `jest.requireActual()` | 获取原始模块实现 |
| `jest.fn()` | 创建 mock 函数 |
| `jest.MockedFunction<>` | TypeScript 类型推断 |
| `mockImplementation()` | 设置 mock 实现 |
| `mockClear()` | 清除调用记录 |
| `getMockImplementation()` | 获取当前 mock 实现 |

### 与测试框架的集成
- 在 `run.test.ts` 中，每个使用 `codexExecSpy` 的测试都遵循模式：
  ```typescript
  const { args: spawnArgs, restore } = codexExecSpy();
  try {
    // ... 测试代码 ...
  } finally {
    restore();
    // ... 其他清理 ...
  }
  ```

## 风险、边界与改进建议

### 当前风险

1. **模块级别 Mock 污染**
   - `jest.mock` 在模块级别执行，影响整个测试文件
   - 即使不使用 `codexExecSpy` 的测试也会受到影响
   - 可能导致意外的行为变化

2. **TypeScript 类型断言风险**
   ```typescript
   spawnMock.mockImplementation(((...spawnArgs: Parameters<typeof child_process.spawn>) => {
     // ...
   }) as typeof actualChildProcess.spawn);  // 类型断言可能掩盖问题
   ```

3. **并发测试风险**
   - 如果测试并发执行，共享的 `spawnMock` 状态可能导致干扰
   - Jest 默认串行执行测试文件，但 `--parallel` 模式下有风险

4. **恢复不完全**
   - `restore()` 只恢复 `mockImplementation`，不恢复 `mockName`、`mockReturnValue` 等
   - 如果其他测试修改了这些属性，可能产生意外行为

### 边界情况

1. **spawn 重载处理**
   - Node.js `spawn` 有多个重载签名
   - 当前实现假设 `(command, args, options)` 三参数形式
   - 两参数形式 `(command, options)` 可能处理不当

2. **环境变量继承**
   - 当 `options.env` 为 `undefined` 时，Node.js 会继承 `process.env`
   - 当前实现记录为 `undefined`，测试需要理解这一语义

3. **非 Codex 调用的干扰**
   - 所有 `spawn` 调用都被拦截，包括非 Codex 的调用
   - 测试需要过滤 `args` 数组找到 Codex 相关的调用

### 改进建议

1. **添加调用过滤功能**
   ```typescript
   // 建议：只记录 Codex 相关的调用
   export function codexExecSpy(options?: { filter?: (args: Parameters<typeof spawn>) => boolean }) {
     spawnMock.mockImplementation((...spawnArgs) => {
       if (!options?.filter || options.filter(spawnArgs)) {
         // 记录
       }
       return previousImplementation(...spawnArgs);
     });
   }
   ```

2. **增强类型安全**
   ```typescript
   // 建议：使用更精确的类型
   export interface CodexExecCall {
     command: string;
     args: string[];
     env: Record<string, string> | undefined;
     cwd: string | undefined;
   }
   ```

3. **自动恢复机制**
   ```typescript
   // 建议：集成 Jest 生命周期
   export function codexExecSpy(): SpyResult & { [Symbol.dispose]: () => void } {
     // ...
     return {
       // ...
       [Symbol.dispose]: restore,
     };
   }
   // 使用：using spy = codexExecSpy();
   ```

4. **验证特定调用**
   ```typescript
   // 建议：添加辅助函数
   export function getCodexCalls(spy: SpyResult): Array<{ args: string[]; env: Record<string, string> }> {
     return spy.args.map((args, i) => ({
       args: args.slice(1),  // 去掉 'exec'
       env: spy.envs[i],
     }));
   }
   ```

5. **文档和示例**
   - 添加 JSDoc 说明 `args` 数组包含 `['exec', ...]` 而不仅是 Codex 参数
   - 说明 `envs` 中 `undefined` 表示继承 `process.env`

6. **处理 spawn 重载**
   ```typescript
   // 建议：更健壮的参数解析
   function parseSpawnArgs(args: Parameters<typeof spawn>): { command: string; args: string[]; options: SpawnOptions } {
     if (typeof args[1] === 'object' && !Array.isArray(args[1])) {
       return { command: args[0], args: [], options: args[1] };
     }
     return { command: args[0], args: args[1] ?? [], options: args[2] };
   }
   ```
