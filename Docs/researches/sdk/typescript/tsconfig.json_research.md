# tsconfig.json 研究文档

## 场景与职责

`tsconfig.json` 是 TypeScript 编译器的配置文件，位于 `sdk/typescript/` 目录下。它定义了 TypeScript SDK 项目的编译选项、模块解析策略和文件包含规则。该配置确保源代码能够被正确编译为 JavaScript，并为开发提供类型检查支持。

## 功能点目的

配置文件实现以下核心功能：

1. **语言目标**: 指定编译目标为 ES2022
2. **模块系统**: 启用 ES 模块和 bundler 解析策略
3. **类型安全**: 启用严格模式和各种类型检查选项
4. **开发体验**: 生成源映射和声明文件
5. **项目组织**: 定义包含和排除的文件范围

## 具体技术实现

### 配置结构

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "resolveJsonModule": true,
    "lib": ["ES2022"],
    "types": ["node", "jest"],
    "sourceMap": true,
    "declaration": true,
    "declarationMap": true,
    "noImplicitAny": true,
    "outDir": "dist",
    "stripInternal": true
  },
  "include": ["src", "tests", "tsup.config.ts", "samples"],
  "exclude": ["dist", "node_modules"]
}
```

### 编译器选项详解

#### 1. 语言和模块配置

```json
{
  "target": "ES2022",
  "module": "ESNext",
  "moduleResolution": "bundler",
  "lib": ["ES2022"]
}
```

| 选项 | 值 | 说明 |
|------|-----|------|
| `target` | `ES2022` | 编译目标为 ES2022，支持现代 JavaScript 特性（如 `at()`, `Object.hasOwn()`） |
| `module` | `ESNext` | 输出 ES 模块，与 `package.json` 的 `"type": "module"` 一致 |
| `moduleResolution` | `bundler` | 使用 bundler 风格的模块解析，支持 `node:` 前缀和裸导入 |
| `lib` | `["ES2022"]` | 包含 ES2022 的类型定义 |

**模块解析策略选择**:
- `bundler` 模式是 TypeScript 4.7+ 引入的
- 支持 `package.json` 中的 `exports` 字段
- 允许导入没有扩展名的文件（如 `./file` 而非 `./file.js`）
- 与 `tsup` 和 Node.js ESM 配合良好

#### 2. 互操作性配置

```json
{
  "allowSyntheticDefaultImports": true,
  "esModuleInterop": true,
  "resolveJsonModule": true
}
```

| 选项 | 说明 |
|------|------|
| `allowSyntheticDefaultImports` | 允许从没有默认导出的模块进行默认导入 |
| `esModuleInterop` | 启用全面的 ES 模块互操作性，自动处理 `__importDefault` |
| `resolveJsonModule` | 允许导入 JSON 文件，并生成类型 |

#### 3. 严格类型检查

```json
{
  "strict": true,
  "noUncheckedIndexedAccess": true,
  "noImplicitAny": true
}
```

| 选项 | 说明 |
|------|------|
| `strict` | 启用所有严格类型检查选项的开关 |
| `noUncheckedIndexedAccess` | 索引访问（如 `obj[key]`）返回 `T \| undefined`，防止越界错误 |
| `noImplicitAny` | 禁止隐式 `any` 类型，要求显式声明 |

**`noUncheckedIndexedAccess` 的影响**:

```typescript
const arr = [1, 2, 3];
const val = arr[10];  // 类型为 number | undefined，而非 number

const obj: Record<string, string> = {};
const str = obj["key"];  // 类型为 string | undefined
```

这要求开发者显式处理可能的 `undefined` 值：
```typescript
if (str !== undefined) {
  // 使用 str
}
```

#### 4. 输出配置

```json
{
  "outDir": "dist",
  "sourceMap": true,
  "declaration": true,
  "declarationMap": true,
  "stripInternal": true
}
```

| 选项 | 说明 |
|------|------|
| `outDir` | 编译输出目录，与 `tsup.config.ts` 的 `clean: true` 配合 |
| `sourceMap` | 生成 `.js.map` 源映射文件 |
| `declaration` | 生成 `.d.ts` 类型声明文件 |
| `declarationMap` | 生成 `.d.ts.map` 声明映射，支持跳转到源码 |
| `stripInternal` | 移除标记为 `@internal` 的声明 |

**源映射链**:
```
源码 (src/index.ts)
    ↓ (tsc/tsup 编译)
编译输出 (dist/index.js)
    ↓ (sourceMap)
源码映射 (dist/index.js.map)
    ↓ (declarationMap)
类型声明映射 (dist/index.d.ts.map)
```

#### 5. 类型定义

```json
{
  "types": ["node", "jest"],
  "skipLibCheck": true
}
```

| 选项 | 说明 |
|------|------|
| `types` | 显式包含 `node` 和 `jest` 的类型定义 |
| `skipLibCheck` | 跳过所有声明文件（`.d.ts`）的类型检查，加速编译 |

**为什么显式指定 `types`**:
- 避免自动包含 `node_modules/@types` 下的所有类型
- 减少命名冲突风险
- 明确项目的类型依赖

#### 6. 文件组织

```json
{
  "include": ["src", "tests", "tsup.config.ts", "samples"],
  "exclude": ["dist", "node_modules"]
}
```

**包含的文件**:
- `src/`: 源代码目录
- `tests/`: 测试文件目录
- `tsup.config.ts`: 构建工具配置
- `samples/`: 示例代码

**排除的文件**:
- `dist/`: 编译输出，避免循环包含
- `node_modules/`: 依赖包

### 与 `tsup.config.ts` 的协调

```typescript
// tsup.config.ts
export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  dts: true,  // 使用 tsc 生成声明文件
  sourcemap: true,
  // ...
});
```

**分工**:
- `tsconfig.json`: 提供类型检查和 IDE 支持
- `tsup`: 实际构建打包，使用 `esbuild` 进行快速编译
- `tsup` 的 `dts: true` 选项会使用 `tsc` 生成声明文件，读取 `tsconfig.json`

## 关键代码路径与文件引用

### 配置文件依赖图

```
tsconfig.json
├── src/ (源代码)
│   └── index.ts (入口)
├── tests/ (测试)
│   └── *.test.ts
├── samples/ (示例)
│   └── *.ts
├── tsup.config.ts (构建配置)
└── jest.config.cjs (测试配置，通过 ts-jest 读取)
```

### 类型定义来源

| 类型包 | 来源 | 用途 |
|--------|------|------|
| `node` | `@types/node` | Node.js 内置模块类型 |
| `jest` | `@types/jest` | Jest 测试框架类型 |

### 编译输出结构

```
dist/
├── index.js          # 编译后的 JavaScript
├── index.js.map      # 源映射
├── index.d.ts        # 类型声明
└── index.d.ts.map    # 声明映射
```

## 依赖与外部交互

### 与构建工具的交互

| 工具 | 交互方式 | 说明 |
|------|----------|------|
| `tsup` | 读取 `tsconfig.json` | 用于生成声明文件 (`dts: true`) |
| `jest` / `ts-jest` | 显式指定配置 | `jest.config.cjs` 中 `tsconfig: "tsconfig.json"` |
| VS Code | 自动检测 | 提供 IntelliSense 和类型检查 |

### 与 Node.js 的兼容性

**ES2022 特性支持** (Node.js 18+):
- `Array.prototype.at()`
- `Object.hasOwn()`
- `Error.cause`
- 类字段和私有方法
- 顶层 await

### 与 ESM 的集成

配置完全支持 ESM:
- `"module": "ESNext"` 输出 ES 模块
- `"moduleResolution": "bundler"` 支持 ESM 解析规则
- `package.json` 中 `"type": "module"` 启用原生 ESM

## 风险、边界与改进建议

### 潜在风险

1. **`skipLibCheck: true` 的风险**:
   - 跳过 `.d.ts` 文件的类型检查
   - 可能遗漏依赖包中的类型错误
   - **缓解**: 定期运行 `tsc --noEmit` 不跳过 lib 检查

2. **`noUncheckedIndexedAccess` 的严格性**:
   - 可能导致大量 `undefined` 检查代码
   - 团队需要适应这种编程风格
   - **建议**: 配合 `!` 非空断言（谨慎使用）或类型守卫

3. **与 `tsup` 的潜在不一致**:
   - `tsup` 使用 `esbuild`，与 `tsc` 的编译行为可能略有差异
   - 类型检查通过但运行时可能出错
   - **建议**: CI 中同时运行类型检查和构建

### 边界情况

1. **JSON 导入类型**:
   ```typescript
   import pkg from "./package.json";
   // pkg 类型为 { default: { name: string, ... } }
   ```
   需要配合 `esModuleInterop` 使用

2. **声明文件生成**:
   - `stripInternal: true` 会移除 `@internal` 标记的导出
   - 确保内部 API 正确标记

3. **路径别名缺失**:
   - 当前配置未设置 `paths` 和 `baseUrl`
   - 只能使用相对导入（如 `../utils`）

### 改进建议

1. **添加路径别名**:
   ```json
   {
     "compilerOptions": {
       "baseUrl": ".",
       "paths": {
         "@/*": ["src/*"],
         "@test/*": ["tests/*"]
       }
     }
   }
   ```
   需要同步更新 `jest.config.cjs` 的 `moduleNameMapper`

2. **启用更多严格选项**:
   ```json
   {
     "compilerOptions": {
       "exactOptionalPropertyTypes": true,
       "noImplicitReturns": true,
       "noFallthroughCasesInSwitch": true,
       "noUncheckedSideEffectImports": true
     }
   }
   ```

3. **添加项目引用（Project References）**:
   如果未来拆分子包：
   ```json
   {
     "references": [
       { "path": "./tsconfig.src.json" },
       { "path": "./tsconfig.test.json" }
     ]
   }
   ```

4. **优化 `lib` 配置**:
   如果使用 DOM API（如 `fetch`）：
   ```json
   {
     "lib": ["ES2022", "DOM", "DOM.Iterable"]
   }
   ```

5. **添加编译性能优化**:
   ```json
   {
     "compilerOptions": {
       "incremental": true,
       "tsBuildInfoFile": ".tsbuildinfo"
     }
   }
   ```

6. **明确 JSX 配置**（如果使用）:
   ```json
   {
     "compilerOptions": {
       "jsx": "react-jsx",
       "jsxImportSource": "react"
     }
   }
   ```
