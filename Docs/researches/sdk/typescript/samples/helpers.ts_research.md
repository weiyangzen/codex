# helpers.ts 深度研究文档

## 场景与职责

`helpers.ts` 是 OpenAI Codex TypeScript SDK 示例程序的**共享工具模块**，提供跨示例的通用辅助功能。当前版本仅包含一个核心函数 `codexPathOverride()`，用于解决 SDK 示例在**开发环境**与**生产环境**中定位 Codex 可执行文件的差异问题。

该模块的设计哲学是「约定优于配置」——通过智能路径推断，让示例程序在无需额外配置的情况下即可运行。

## 功能点目的

### 1. 可执行文件路径解析

核心目标是确定 `codex` Rust 二进制文件的位置，优先级如下：

| 优先级 | 来源 | 适用场景 |
|-------|------|---------|
| 1 | `process.env.CODEX_EXECUTABLE` | 用户显式指定（生产/自定义部署） |
| 2 | `../../codex-rs/target/debug/codex` | 开发模式（从源码构建） |

### 2. 开发体验优化

在 monorepo 结构中，SDK 示例位于 `sdk/typescript/samples/`，而 Rust 可执行文件默认输出到 `codex-rs/target/debug/codex`。`helpers.ts` 通过相对路径 `../../codex-rs/target/debug/codex` 自动桥接这一差距，使开发者可以：
- 克隆仓库后直接运行示例
- 无需安装 npm 发布的 `@openai/codex` 包
- 使用本地最新构建的 Rust 二进制进行测试

## 具体技术实现

### 代码实现

```typescript
import path from "node:path";

export function codexPathOverride() {
  return (
    process.env.CODEX_EXECUTABLE ??
    path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex")
  );
}
```

### 路径解析逻辑

```
sdk/typescript/samples/
├── basic_streaming.ts
├── helpers.ts          ◄── 当前文件
├── structured_output.ts
└── ...
    │
    │ path.join(process.cwd(), "..", "..")
    ▼
codex/                  ◄── 项目根目录
├── sdk/
├── codex-rs/           ◄── Rust 源码
│   └── target/
│       └── debug/
│           └── codex   ◄── 目标可执行文件
```

### 调用方使用模式

所有示例统一采用以下模式：
```typescript
import { codexPathOverride } from "./helpers.ts";

const codex = new Codex({ codexPathOverride: codexPathOverride() });
```

`Codex` 类构造函数签名（来自 `src/codexOptions.ts`）：
```typescript
export type CodexOptions = {
  codexPathOverride?: string;  // 显式指定可执行文件路径
  baseUrl?: string;
  apiKey?: string;
  config?: CodexConfigObject;
  env?: Record<string, string>;
};
```

## 关键代码路径与文件引用

### 被调用方

| 文件路径 | 导入方式 | 用途 |
|---------|---------|------|
| `basic_streaming.ts` | `import { codexPathOverride } from "./helpers.ts"` | REPL 示例 |
| `structured_output.ts` | `import { codexPathOverride } from "./helpers.ts"` | 结构化输出示例 |
| `structured_output_zod.ts` | `import { codexPathOverride } from "./helpers.ts"` | Zod schema 示例 |

### SDK 内部消费链

```
helpers.ts
    │
    ├──▶ codexPathOverride() returns string
    │
    └──▶ new Codex({ codexPathOverride })
            └── src/codex.ts
                └── new CodexExec(executablePath, ...)
                    └── src/exec.ts
                        └── this.executablePath = executablePath || findCodexPath()
```

注意：`CodexExec` 构造函数会优先使用传入的 `executablePath`，若未提供则调用 `findCodexPath()` 自动检测 npm 安装的包。

## 依赖与外部交互

### 模块依赖

| 模块 | 来源 | 用途 |
|-----|------|------|
| `node:path` | Node.js 内置 | 跨平台路径拼接 |

### 零外部依赖设计

该模块 intentionally 仅依赖 Node.js 内置模块，确保：
- 无需额外 `npm install` 即可使用
- 启动时间最小化
- 无第三方包的安全风险

### 环境变量

| 变量名 | 类型 | 说明 |
|-------|------|------|
| `CODEX_EXECUTABLE` | string (optional) | 覆盖默认路径检测 |

## 风险、边界与改进建议

### 已知风险

1. **路径硬编码假设**
   ```typescript
   path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex")
   ```
   - 假设工作目录是 `sdk/typescript/samples/`
   - 若从其他目录运行（如 `node sdk/typescript/samples/basic_streaming.ts`），路径解析失败
   - **影响**: 抛出 `ENOENT` 错误或启动错误的可执行文件

2. **构建状态依赖**
   - 默认路径指向 `debug` 构建产物
   - 若开发者仅构建 `release` 版本（`cargo build --release`），路径不存在
   - 无自动 fallback 到 `release` 目录的逻辑

3. **平台兼容性**
   - 返回的路径在 Windows 上会是 `codex-rs\target\debug\codex`
   - 但 Rust 在 Windows 上实际输出 `codex.exe`
   - SDK 的 `findCodexPath()` 会正确处理 `.exe` 扩展名，但 `codexPathOverride()` 返回的裸路径可能导致问题

### 边界条件

| 场景 | 当前行为 | 建议 |
|-----|---------|------|
| `CODEX_EXECUTABLE` 指向不存在的文件 | SDK 启动时抛出错误 | 在 helpers.ts 添加存在性检查 |
| 从非 samples 目录运行 | 路径解析错误 | 使用 `import.meta.url` 替代 `process.cwd()` |
| `codex-rs/target/debug/codex` 不存在 | 返回路径字符串，错误延迟到 SDK 启动 | 添加文件存在性验证 |

### 改进建议

1. **使用 `import.meta.url` 替代 `process.cwd()`**
   ```typescript
   import { fileURLToPath } from "node:url";
   import path from "node:path";

   const __dirname = path.dirname(fileURLToPath(import.meta.url));

   export function codexPathOverride() {
     return (
       process.env.CODEX_EXECUTABLE ??
       path.join(__dirname, "..", "..", "..", "..", "codex-rs", "target", "debug", "codex")
     );
   }
   ```
   优势：无论从哪里运行，路径都相对于本文件位置解析。

2. **添加文件存在性验证**
   ```typescript
   import { existsSync } from "node:fs";

   export function codexPathOverride(): string {
     const envPath = process.env.CODEX_EXECUTABLE;
     if (envPath) {
       if (!existsSync(envPath)) {
         throw new Error(`CODEX_EXECUTABLE points to non-existent file: ${envPath}`);
       }
       return envPath;
     }

     const devPath = path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex");
     if (existsSync(devPath)) {
       return devPath;
     }

     // Fallback to release build
     const releasePath = path.join(process.cwd(), "..", "..", "codex-rs", "target", "release", "codex");
     if (existsSync(releasePath)) {
       return releasePath;
     }

     throw new Error(
       `Could not find codex executable. ` +
       `Please build the Rust project (cargo build) or set CODEX_EXECUTABLE.`
     );
   }
   ```

3. **支持 release 构建自动检测**
   ```typescript
   function findCodexBinary(): string {
     const baseDir = path.join(process.cwd(), "..", "..", "codex-rs", "target");
     const debugPath = path.join(baseDir, "debug", "codex");
     const releasePath = path.join(baseDir, "release", "codex");

     // Prefer release if both exist (typically newer for demos)
     if (existsSync(releasePath)) return releasePath;
     if (existsSync(debugPath)) return debugPath;

     throw new Error("No codex binary found. Run: cargo build");
   }
   ```

4. **扩展为更通用的配置工具**
   当前模块仅有一个函数，可扩展为：
   ```typescript
   // helpers.ts 扩展建议
   export function codexPathOverride(): string | undefined;
   export function getDefaultConfig(): CodexConfigObject;
   export function validateEnvironment(): { ok: boolean; errors: string[] };
   ```

### 相关代码

- `sdk/typescript/src/exec.ts` 中的 `findCodexPath()`: 生产环境的 npm 包路径检测
- `sdk/typescript/tests/testCodex.ts`: 测试使用的类似路径逻辑
  ```typescript
  export const codexExecPath = path.join(process.cwd(), "..", "..", "codex-rs", "target", "debug", "codex");
  ```
