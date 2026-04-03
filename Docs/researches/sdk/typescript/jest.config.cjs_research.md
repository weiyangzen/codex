# jest.config.cjs 研究文档

## 场景与职责

`jest.config.cjs` 是 Jest 测试框架的配置文件，位于 `sdk/typescript/` 目录下。它定义了 TypeScript SDK 项目的测试运行环境、模块解析策略和转换规则。该配置确保 Jest 能够正确执行 TypeScript 编写的 ESM 模块测试。

## 功能点目的

配置文件实现以下核心功能：

1. **ESM 支持**: 配置 Jest 以原生支持 ES 模块
2. **TypeScript 转换**: 使用 `ts-jest` 将 TypeScript 代码转换为可执行格式
3. **测试环境设置**: 配置测试前后的全局设置（如临时目录创建）
4. **模块解析**: 处理 ESM 的导入路径映射
5. **Import Meta 处理**: 解决 `import.meta.url` 在 Jest 中的兼容性问题

## 具体技术实现

### 配置结构

```javascript
/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest/presets/default-esm",
  testEnvironment: "node",
  extensionsToTreatAsEsm: [".ts"],
  setupFilesAfterEnv: ["<rootDir>/tests/setupCodexHome.ts"],
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  testMatch: ["**/tests/**/*.test.ts"],
  transform: {
    "^.+\\.tsx?$": [
      "ts-jest",
      {
        useESM: true,
        tsconfig: "tsconfig.json",
        diagnostics: {
          ignoreCodes: [1343],
        },
        astTransformers: {
          before: [
            {
              path: "ts-jest-mock-import-meta",
              options: { metaObjectReplacement: { url: "file://" + __dirname + "/dist/index.js" } },
            },
          ],
        },
      },
    ],
  },
};
```

### 配置详解

#### 1. ESM 预设

```javascript
preset: "ts-jest/presets/default-esm"
```

- 使用 `ts-jest` 的 ESM 预设配置
- 自动配置大部分 ESM 支持所需的选项
- 与 `extensionsToTreatAsEsm` 配合使用

#### 2. ESM 扩展名处理

```javascript
extensionsToTreatAsEsm: [".ts"]
```

- 告知 Jest 将 `.ts` 文件视为 ES 模块
- 这是 ESM 支持的关键配置

#### 3. 测试环境设置

```javascript
setupFilesAfterEnv: ["<rootDir>/tests/setupCodexHome.ts"]
```

- 在每个测试文件执行后、测试开始前运行设置脚本
- `<rootDir>` 是 Jest 的项目根目录占位符
- **引用的设置文件**: `tests/setupCodexHome.ts`

**setupCodexHome.ts 功能**:
```typescript
// 为每个测试创建临时 CODEX_HOME 目录
beforeEach(async () => {
  currentCodexHome = await fs.mkdtemp(path.join(os.tmpdir(), "codex-sdk-test-"));
  process.env.CODEX_HOME = currentCodexHome;
});

// 测试后清理
afterEach(async () => {
  // 恢复原始 CODEX_HOME 并删除临时目录
});
```

这确保：
- 每个测试在隔离的环境中运行
- 不会污染用户真实的 `~/.codex` 目录
- 测试完成后自动清理临时文件

#### 4. 模块名称映射

```javascript
moduleNameMapper: {
  "^(\\.{1,2}/.*)\\.js$": "$1",
}
```

- **用途**: 处理 TypeScript ESM 导入中的 `.js` 扩展名
- **问题**: TypeScript ESM 要求导入时写 `.js` 扩展名，但实际文件是 `.ts`
- **解决**: 将 `import "./file.js"` 映射到 `./file`

**示例转换**:
```typescript
// 源代码中的导入
import { something } from "./utils.js";

// Jest 运行时映射为
import { something } from "./utils";  // 实际查找 utils.ts
```

#### 5. 测试匹配模式

```javascript
testMatch: ["**/tests/**/*.test.ts"]
```

- 只匹配 `tests` 目录下以 `.test.ts` 结尾的文件
- 排除其他文件（如源码、配置文件）

#### 6. TypeScript 转换配置

```javascript
transform: {
  "^.+\\.tsx?$": [
    "ts-jest",
    {
      useESM: true,
      tsconfig: "tsconfig.json",
      diagnostics: {
        ignoreCodes: [1343],
      },
      astTransformers: {
        before: [
          {
            path: "ts-jest-mock-import-meta",
            options: { metaObjectReplacement: { url: "file://" + __dirname + "/dist/index.js" } },
          },
        ],
      },
    },
  ],
}
```

**配置项详解**:

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `useESM` | `true` | 启用 ESM 支持 |
| `tsconfig` | `"tsconfig.json"` | 使用项目的 TypeScript 配置 |
| `diagnostics.ignoreCodes` | `[1343]` | 忽略 TS1343 错误（`import.meta` 相关） |
| `astTransformers` | 自定义转换器 | 处理 `import.meta.url` |

**Import Meta 转换器**:

`ts-jest-mock-import-meta` 插件解决以下问题：
- Jest 在 CommonJS 模式下运行，不支持 `import.meta`
- 插件将 `import.meta.url` 替换为指定的字符串
- 配置中设置为 `file://{__dirname}/dist/index.js`

## 关键代码路径与文件引用

### 配置文件关系

```
jest.config.cjs
├── tsconfig.json (TypeScript 配置)
├── tests/setupCodexHome.ts (测试前置设置)
└── tests/*.test.ts (测试文件)
```

### 测试文件结构

| 测试文件 | 测试内容 |
|----------|----------|
| `tests/abort.test.ts` | 中止/取消操作测试 |
| `tests/exec.test.ts` | 进程执行测试 |
| `tests/run.test.ts` | 基础运行测试 |
| `tests/runStreamed.test.ts` | 流式响应测试 |

### 测试工具文件

| 文件 | 用途 |
|------|------|
| `tests/setupCodexHome.ts` | 全局测试设置 |
| `tests/testCodex.ts` | 测试辅助函数 |
| `tests/codexExecSpy.ts` | CLI 执行监控 |
| `tests/responsesProxy.ts` | 响应代理模拟 |

## 依赖与外部交互

### 依赖包

| 包名 | 版本 | 用途 |
|------|------|------|
| `jest` | `^29.7.0` | 测试框架核心 |
| `ts-jest` | `^29.3.4` | TypeScript 支持 |
| `ts-jest-mock-import-meta` | `^1.3.1` | Import meta 模拟 |
| `@types/jest` | `^29.5.14` | Jest 类型定义 |

### 与 package.json 的集成

```json
"scripts": {
  "test": "jest",
  "test:watch": "jest --watch",
  "coverage": "jest --coverage"
}
```

### 与 TypeScript 配置的协调

`tsconfig.json` 中的相关配置：
```json
{
  "compilerOptions": {
    "module": "ESNext",
    "moduleResolution": "bundler",
    "types": ["node", "jest"]
  },
  "include": ["src", "tests", "tsup.config.ts", "samples"]
}
```

## 风险、边界与改进建议

### 潜在风险

1. **ESM/CJS 混合复杂性**:
   - 配置文件使用 `.cjs` 扩展名（CommonJS）
   - 源码使用 ESM（`"type": "module"`）
   - 这种混合可能导致混淆和工具链问题

2. **Import Meta 硬编码**:
   ```javascript
   metaObjectReplacement: { url: "file://" + __dirname + "/dist/index.js" }
   ```
   - 硬编码路径可能在不同环境中失效
   - 如果构建输出路径改变，测试会失败

3. **诊断代码忽略**:
   - `ignoreCodes: [1343]` 可能掩盖真实的类型问题
   - 应该逐步解决根本问题而非永久忽略

### 边界情况

1. **Node.js 版本兼容性**:
   - ESM 支持在不同 Node.js 版本中有差异
   - 项目要求 Node.js >= 18

2. **Windows 路径处理**:
   - `file://` URL 在 Windows 上可能需要特殊处理
   - `__dirname` 在 ESM 中不可用（但配置文件是 CJS）

3. **测试隔离性**:
   - 虽然每个测试有独立的 `CODEX_HOME`，但全局状态仍可能影响测试

### 改进建议

1. **动态 Import Meta 处理**:
   ```javascript
   options: { 
     metaObjectReplacement: { 
       url: () => `file://${process.cwd()}/dist/index.js` 
     } 
   }
   ```

2. **添加覆盖率配置**:
   ```javascript
   collectCoverageFrom: [
     "src/**/*.ts",
     "!src/**/*.d.ts",
   ],
   coverageThreshold: {
     global: {
       branches: 80,
       functions: 80,
       lines: 80,
       statements: 80,
     },
   },
   ```

3. **优化模块映射**:
   ```javascript
   moduleNameMapper: {
     "^(\\.{1,2}/.*)\\.js$": "$1",
     "^@/(.*)$": "<rootDir>/src/$1",  // 支持路径别名
   },
   ```

4. **添加测试超时配置**:
   ```javascript
   testTimeout: 10000,  // 10秒超时
   ```

5. **并行测试配置**:
   ```javascript
   maxWorkers: "50%",  // 使用 50% CPU 核心
   ```

6. **考虑迁移到原生 Node.js 测试**:
   - Node.js 18+ 内置 `node:test` 模块
   - 可以减少外部依赖
   - 但生态系统成熟度不如 Jest
