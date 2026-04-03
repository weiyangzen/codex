# testCodex.ts 研究文档

## 场景与职责

本模块是 TypeScript SDK 测试套件的 **测试客户端工厂**，提供创建配置好的 `Codex` 实例的辅助函数。它封装了测试所需的复杂配置逻辑，使测试代码更简洁、可维护。

主要使用场景：
1. 创建连接到 Mock API 的测试客户端
2. 配置自定义模型提供者（指向本地代理服务器）
3. 管理测试环境变量和配置覆盖
4. 提供统一的客户端创建接口

## 功能点目的

### 测试客户端工厂目的
- **配置简化**：封装复杂的 `CodexOptions` 配置
- **Mock 集成**：自动配置指向本地代理服务器的模型提供者
- **环境隔离**：控制环境变量继承行为
- **路径管理**：自动定位 Rust CLI 二进制文件

### 提供的功能
| 函数 | 用途 |
|-----|------|
| `createMockClient(url)` | 快速创建连接到 Mock API 的客户端 |
| `createTestClient(options)` | 创建具有完整自定义能力的客户端 |

## 具体技术实现

### 关键流程

#### 1. CLI 二进制路径定义
```typescript
export const codexExecPath = path.join(
  process.cwd(),      // sdk/typescript
  "..",               // sdk/
  "..",               // 项目根目录
  "codex-rs",
  "target",
  "debug",
  "codex"
);
// 结果: <repo-root>/codex-rs/target/debug/codex
```

#### 2. 快速 Mock 客户端创建
```typescript
export function createMockClient(url: string): TestClient {
  return createTestClient({
    config: {
      model_provider: "mock",  // 使用 mock 提供者
      model_providers: {
        mock: {
          name: "Mock provider for test",
          base_url: url,           // 指向代理服务器
          wire_api: "responses",   // 使用 Responses API
          supports_websockets: false,
        },
      },
    },
  });
}
```

#### 3. 通用测试客户端创建
```typescript
export function createTestClient(options: CreateTestClientOptions = {}): TestClient {
  // 环境变量处理：继承或完全替换
  const env =
    options.inheritEnv === false
      ? { ...options.env }
      : { ...getCurrentEnv(), ...options.env };

  return {
    cleanup: () => {},  // 预留清理钩子
    client: new Codex({
      codexPathOverride: codexExecPath,
      baseUrl: options.baseUrl,
      apiKey: options.apiKey,
      config: mergeTestProviderConfig(options.baseUrl, options.config),
      env,
    }),
  };
}
```

#### 4. 提供者配置合并
```typescript
function mergeTestProviderConfig(
  baseUrl: string | undefined,
  config: CodexConfigObject | undefined,
): CodexConfigObject | undefined {
  // 如果已有显式提供者配置，不覆盖
  if (!baseUrl || hasExplicitProviderConfig(config)) {
    return config;
  }

  // 自动添加 mock 提供者配置
  return {
    ...config,
    model_provider: "mock",
    model_providers: {
      mock: {
        name: "Mock provider for test",
        base_url: baseUrl,
        wire_api: "responses",
        supports_websockets: false,
      },
    },
  };
}
```

#### 5. 环境变量过滤
```typescript
function getCurrentEnv(): Record<string, string> {
  const env: Record<string, string> = {};

  for (const [key, value] of Object.entries(process.env)) {
    // 排除内部来源标识，避免干扰测试
    if (key === "CODEX_INTERNAL_ORIGINATOR_OVERRIDE") {
      continue;
    }
    if (value !== undefined) {
      env[key] = value;
    }
  }

  return env;
}
```

### 数据结构

#### 配置类型
```typescript
// 来自 codexOptions.ts
export type CodexConfigObject = { [key: string]: CodexConfigValue };
export type CodexConfigValue = string | number | boolean | CodexConfigValue[] | CodexConfigObject;

// 来自本模块
export type CreateTestClientOptions = {
  apiKey?: string;
  baseUrl?: string;
  config?: CodexConfigObject;
  env?: Record<string, string>;
  inheritEnv?: boolean;  // 是否继承 process.env，默认 true
};

export type TestClient = {
  cleanup: () => void;  // 清理函数（当前为空实现）
  client: Codex;
};
```

#### 模型提供者配置
```typescript
// CodexConfigObject 中的 model_providers 结构
{
  model_provider: "mock",
  model_providers: {
    mock: {
      name: "Mock provider for test",
      base_url: "http://127.0.0.1:54321",  // 代理服务器地址
      wire_api: "responses",               // API 类型
      supports_websockets: false,
    },
  },
}
```

### 配置合并逻辑

#### 场景 1: 只有 baseUrl，无显式配置
```typescript
const client = createTestClient({ baseUrl: "http://localhost:1234" });
// 结果: 自动添加 mock 提供者配置
```

#### 场景 2: 已有显式提供者配置
```typescript
const client = createTestClient({
  baseUrl: "http://localhost:1234",
  config: { model_provider: "custom" }
});
// 结果: 不覆盖，保留用户配置
```

#### 场景 3: 完全自定义环境
```typescript
const client = createTestClient({
  inheritEnv: false,  // 不继承 process.env
  env: { CUSTOM: "value" },  // 只使用指定的环境变量
});
```

## 关键代码路径与文件引用

### 本模块
- `sdk/typescript/tests/testCodex.ts` - 本文件 (94 行)

### 依赖的源文件
- `sdk/typescript/src/codex.ts` - `Codex` 类
- `sdk/typescript/src/codexOptions.ts` - `CodexOptions`, `CodexConfigObject`

### 使用本模块的测试
| 测试文件 | 使用方式 |
|---------|---------|
| `abort.test.ts` | `createMockClient(url)` |
| `exec.test.ts` | 未直接使用（有自己的 mock） |
| `run.test.ts` | `createMockClient(url)`, `createTestClient(options)` |
| `runStreamed.test.ts` | `createMockClient(url)` |

### 调用链
```
test file
  → createMockClient(url)
    → createTestClient({ config: { model_provider: "mock", ... } })
      → mergeTestProviderConfig(url, config)
        → 检查 hasExplicitProviderConfig(config)
        → 返回合并后的配置
      → getCurrentEnv()
        → 过滤掉 CODEX_INTERNAL_ORIGINATOR_OVERRIDE
      → new Codex({
          codexPathOverride: codexExecPath,  // <repo>/codex-rs/target/debug/codex
          baseUrl: undefined,  // 通过 config 传递
          apiKey: undefined,
          config: { model_provider: "mock", model_providers: { mock: { base_url: url, ... } } },
          env: { ...process.env },
        })
        → new CodexExec(codexExecPath, env, config)
  ← { cleanup: () => {}, client }

test usage:
  → client.startThread(options)
    → new Thread(exec, codexOptions, threadOptions)
  → thread.run("input")
    → exec.run({ input, baseUrl, apiKey, ... })
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `node:path` | 路径拼接 |
| `../src/codex` | `Codex` 类 |
| `../src/codexOptions` | 配置类型 |

### Node.js API
| API | 用途 |
|-----|------|
| `process.cwd()` | 获取当前工作目录 |
| `process.env` | 读取环境变量 |

### 文件系统依赖
- `<repo-root>/codex-rs/target/debug/codex` - Rust CLI 二进制文件
  - 如果文件不存在，测试会在 `spawn` 时失败

## 风险、边界与改进建议

### 当前风险

1. **硬编码路径依赖**
   ```typescript
   export const codexExecPath = path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex");
   ```
   - 依赖特定的目录结构和构建配置
   - 如果工作目录不是 `sdk/typescript`，路径会错误
   - 如果 Rust 代码未构建，测试会失败

2. **路径平台兼容性**
   - 使用 `path.join` 处理跨平台
   - 但 `codexExecPath` 在 Windows 上应该是 `codex.exe`
   - 当前实现未处理 Windows 可执行文件扩展名

3. **环境变量过滤不完整**
   ```typescript
   if (key === "CODEX_INTERNAL_ORIGINATOR_OVERRIDE") continue;
   ```
   - 只过滤了一个内部变量
   - 可能还有其他需要过滤的变量

4. **cleanup 空实现**
   ```typescript
   cleanup: () => {}
   ```
   - 预留了清理钩子但未实现
   - 如果 `Codex` 类需要清理，这里没有处理

5. **配置合并逻辑复杂**
   - `mergeTestProviderConfig` 的行为可能令人困惑
   - 如果用户提供了 `config` 但没有 `model_provider`，自动添加 mock 配置
   - 如果用户提供了 `model_provider`，即使提供了 `baseUrl` 也不添加 mock

### 边界情况

1. **baseUrl 与 config 的交互**
   ```typescript
   // 这种情况不会添加 mock 提供者
   createTestClient({
     baseUrl: "http://localhost:1234",
     config: { other_setting: "value" }  // 没有 model_provider，但也不是 undefined
   });
   ```
   - 实际上会添加，因为 `hasExplicitProviderConfig` 检查 `model_provider` 和 `model_providers`

2. **空环境变量**
   ```typescript
   createTestClient({ inheritEnv: false, env: {} })
   ```
   - 创建一个完全隔离的环境
   - 但某些系统工具可能需要基本的环境变量（如 `PATH`）

3. **并发创建**
   - 多个测试同时调用 `createTestClient`
   - 共享 `codexExecPath`，但每个客户端独立
   - 理论上安全

4. **路径遍历攻击**
   - 如果 `process.cwd()` 被恶意控制，可能导致加载错误的二进制文件
   - 但在测试环境中风险较低

### 改进建议

1. **验证二进制文件存在**
   ```typescript
   import { existsSync } from "node:fs";
   import { resolve } from "node:path";

   function findCodexBinary(): string {
     const candidates = [
       // 开发构建
       path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex"),
       path.join(process.cwd(), "..", "..", "codex-rs", "target", "release", "codex"),
       // 发布构建（通过 npm 安装）
       path.join(process.cwd(), "..", "..", "node_modules", "@openai", "codex", "bin", "codex"),
     ];
     
     const platformExt = process.platform === "win32" ? ".exe" : "";
     
     for (const candidate of candidates) {
       const fullPath = candidate + platformExt;
       if (existsSync(fullPath)) {
         return fullPath;
       }
     }
     
     throw new Error(
       `Codex CLI binary not found. Searched paths. ` +
       `Please build the Rust project: cd codex-rs && cargo build`
     );
   }

   export const codexExecPath = findCodexBinary();
   ```

2. **改进 cleanup 实现**
   ```typescript
   export type TestClient = {
     cleanup: () => Promise<void>;  // 改为异步
     client: Codex;
   };

   export function createTestClient(options: CreateTestClientOptions = {}): TestClient {
     const client = new Codex({...});
     
     return {
       cleanup: async () => {
         // 如果 Codex 类添加了需要清理的资源，在这里处理
         // 例如：关闭连接、清理临时文件等
       },
       client,
     };
   }
   ```

3. **更灵活的环境变量控制**
   ```typescript
   export type CreateTestClientOptions = {
     // ...
     env?: Record<string, string>;
     inheritEnv?: boolean;
     envExclude?: string[];  // 继承时排除的变量
     envInclude?: string[];  // 即使 inheritEnv: false 也包含的变量
   };

   function getCurrentEnv(options: CreateTestClientOptions): Record<string, string> {
     if (options.inheritEnv === false) {
       const base = options.envInclude?.reduce((acc, key) => {
         if (process.env[key]) acc[key] = process.env[key];
         return acc;
       }, {} as Record<string, string>) ?? {};
       return { ...base, ...options.env };
     }
     
     const env: Record<string, string> = {};
     for (const [key, value] of Object.entries(process.env)) {
       if (value === undefined) continue;
       if (key === "CODEX_INTERNAL_ORIGINATOR_OVERRIDE") continue;
       if (options.envExclude?.includes(key)) continue;
       env[key] = value;
     }
     return { ...env, ...options.env };
   }
   ```

4. **文档和类型改进**
   ```typescript
   /**
    * Creates a test client configured to use a mock OpenAI API server.
    * 
    * @param url - The URL of the mock server (e.g., "http://127.0.0.1:12345")
    * @returns A TestClient instance with cleanup function
    * 
    * @example
    * const { url, close } = await startResponsesTestProxy({...});
    * const { client, cleanup } = createMockClient(url);
    * try {
    *   const thread = client.startThread();
    *   await thread.run("Hello");
    * } finally {
    *   cleanup();
    *   await close();
    * }
    */
   export function createMockClient(url: string): TestClient { ... }
   ```

5. **支持 Release 构建**
   ```typescript
   const codexExecPath = process.env.CODEX_TEST_BINARY || 
     (process.env.CI
       ? path.join(process.cwd(), "..", "..", "codex-rs", "target", "release", "codex")
       : path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex"));
   ```

6. **验证配置合并结果**
   ```typescript
   function mergeTestProviderConfig(baseUrl: string | undefined, config: CodexConfigObject | undefined): CodexConfigObject | undefined {
     const result = mergeInternal(baseUrl, config);
     
     // 验证结果配置有效
     if (result?.model_provider && !result.model_providers?.[result.model_provider]) {
       console.warn(`model_provider "${result.model_provider}" not found in model_providers`);
     }
     
     return result;
   }
   ```

7. **添加测试辅助函数**
   ```typescript
   export async function withTestClient(
     options: CreateTestClientOptions,
     fn: (client: Codex) => Promise<void>
   ): Promise<void> {
     const { client, cleanup } = createTestClient(options);
     try {
       await fn(client);
     } finally {
       await cleanup();
     }
   }

   // 使用
   await withTestClient({ baseUrl: url }, async (client) => {
     const thread = client.startThread();
     await thread.run("Hello");
   });
   ```
