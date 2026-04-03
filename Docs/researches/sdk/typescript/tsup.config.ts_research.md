# tsup.config.ts 研究文档

## 场景与职责

`tsup.config.ts` 是 `tsup` 构建工具的配置文件，位于 `sdk/typescript/` 目录下。它定义了 TypeScript SDK 项目的打包策略，负责将 TypeScript 源代码编译并打包为可分发的 JavaScript 模块。`tsup` 是一个基于 `esbuild` 的快速 TypeScript 打包工具，特别适合构建库和 SDK。

## 功能点目的

配置文件实现以下核心功能：

1. **入口定义**: 指定打包的入口文件
2. **输出格式**: 配置输出为 ES 模块格式
3. **类型生成**: 启用 TypeScript 声明文件生成
4. **源映射**: 生成源映射文件便于调试
5. **构建优化**: 配置清理和压缩选项

## 具体技术实现

### 配置结构

```typescript
import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  dts: true,
  sourcemap: true,
  clean: true,
  minify: false,
  target: "node18",
  shims: false,
});
```

### 配置详解

#### 1. 入口配置

```typescript
entry: ["src/index.ts"]
```

- **入口文件**: `src/index.ts`
- **作用**: 定义打包的起点，`tsup` 会分析入口文件的依赖图
- **关联**: 与 `package.json` 中的 `"module": "./dist/index.js"` 对应

**入口文件职责** (`src/index.ts`):
```typescript
// 导出事件类型
export type { ThreadEvent, ThreadStartedEvent, ... } from "./events";
// 导出项目类型
export type { ThreadItem, AgentMessageItem, ... } from "./items";
// 导出核心类
export { Thread } from "./thread";
export { Codex } from "./codex";
// 导出选项类型
export type { CodexOptions } from "./codexOptions";
export type { ThreadOptions, ... } from "./threadOptions";
export type { TurnOptions } from "./turnOptions";
```

#### 2. 输出格式

```typescript
format: ["esm"]
```

- **格式**: 仅输出 ES 模块（ECMAScript Modules）
- **与 package.json 的协调**:
  ```json
  {
    "type": "module",
    "exports": {
      ".": {
        "import": "./dist/index.js",
        "types": "./dist/index.d.ts"
      }
    }
  }
  ```

**为什么不输出 CommonJS**:
- 项目目标环境是 Node.js 18+，原生支持 ESM
- 纯 ESM 简化构建配置和输出
- 现代 Node.js 项目趋势

#### 3. 类型声明生成

```typescript
dts: true
```

- **功能**: 生成 `.d.ts` 类型声明文件
- **实现方式**: `tsup` 内部调用 `tsc` 生成声明文件
- **输出**: `dist/index.d.ts` 和 `dist/index.d.ts.map`
- **与 tsconfig.json 的协调**: 读取 `tsconfig.json` 中的 `declaration` 和 `declarationMap` 配置

**类型生成流程**:
```
src/index.ts
    ↓ (tsup 分析依赖)
src/*.ts (所有依赖文件)
    ↓ (tsc 生成声明)
dist/index.d.ts
    ↓ (sourcemap)
dist/index.d.ts.map
```

#### 4. 源映射

```typescript
sourcemap: true
```

- **功能**: 生成 `.js.map` 源映射文件
- **输出**: `dist/index.js.map`
- **用途**: 
  - 调试时映射回 TypeScript 源码
  - 错误堆栈跟踪显示原始文件位置

**源映射链**:
```
dist/index.js
    ← dist/index.js.map
        ← src/index.ts
```

#### 5. 构建清理

```typescript
clean: true
```

- **功能**: 构建前自动清理 `dist` 目录
- **等价命令**: `rm -rf dist`
- **与 package.json 的协调**:
  ```json
  "scripts": {
    "clean": "rm -rf dist",
    "build": "tsup"
  }
  ```
  实际上 `clean: true` 使得 `"clean"` 脚本变得可选

#### 6. 代码压缩

```typescript
minify: false
```

- **功能**: 禁用代码压缩
- **原因**: 
  - SDK 库通常不压缩，由最终应用决定
  - 保持代码可读性，便于调试
  - 允许 Tree Shaking 优化

**如果启用压缩** (`minify: true`):
- 使用 `esbuild` 的压缩功能
- 移除空白、缩短变量名
- 可能略微影响 Tree Shaking 效果

#### 7. 目标平台

```typescript
target: "node18"
```

- **功能**: 指定代码编译目标为 Node.js 18
- **影响**: 
  - `esbuild` 会根据目标调整输出语法
  - 保留 Node.js 18 支持的现代语法（如可选链、空值合并）
  - 转换 Node.js 18 不支持的语法

**与 `tsconfig.json` 的协调**:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"]
  }
}
```
- `tsconfig.json` 控制类型检查和声明生成
- `tsup.config.ts` 控制实际编译输出

#### 8. Shims 配置

```typescript
shims: false
```

- **功能**: 禁用自动注入的 polyfills/shims
- **Shims 的作用**: 
  - 在 CJS 环境中模拟 ESM 特性（如 `__dirname`, `__filename`）
  - 在浏览器环境中模拟 Node.js 全局变量
- **禁用原因**: 
  - 目标环境是 Node.js 18+，原生支持 ESM
  - 不需要额外的兼容性层

## 关键代码路径与文件引用

### 配置文件网络

```
tsup.config.ts
├── src/index.ts (入口)
│   ├── src/codex.ts
│   ├── src/thread.ts
│   ├── src/events.ts
│   ├── src/items.ts
│   └── ... (其他模块)
├── tsconfig.json (类型配置)
└── package.json (包配置)
    └── "prepare": "pnpm run build"
```

### 构建输出

```
dist/
├── index.js          # ESM 模块 (由 esbuild 生成)
├── index.js.map      # JavaScript 源映射
├── index.d.ts        # 类型声明 (由 tsc 生成)
└── index.d.ts.map    # 声明源映射
```

### 脚本调用链

```
npm install
    └── prepare
        └── pnpm run build
            └── tsup
                ├── esbuild (编译 JS)
                └── tsc (生成 .d.ts)
```

## 依赖与外部交互

### 依赖包

| 包名 | 版本 | 用途 |
|------|------|------|
| `tsup` | `^8.5.0` | 构建工具核心 |
| `esbuild` | (tsup 依赖) | 快速编译和打包 |
| `typescript` | `^5.9.2` | 类型检查和声明生成 |

### 与 `tsconfig.json` 的协作

| tsup 功能 | tsconfig 配置 | 说明 |
|-----------|---------------|------|
| 类型检查 | `strict: true` | 遵循严格类型规则 |
| 声明生成 | `declaration: true` | 生成 `.d.ts` 文件 |
| 声明映射 | `declarationMap: true` | 生成 `.d.ts.map` |
| 源映射 | `sourceMap: true` | 生成 `.js.map` |
| 输出目录 | `outDir: "dist"` | 声明文件输出位置 |

### 与 `package.json` 的协作

```json
{
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  },
  "files": ["dist"]
}
```

- `tsup` 生成的文件路径必须与 `package.json` 中的配置匹配
- `files: ["dist"]` 确保只有构建输出被发布到 npm

### 开发工作流

```bash
# 开发模式（监听文件变化）
pnpm run build:watch
# 等价于: tsup --watch

# 生产构建
pnpm run build
# 等价于: tsup
```

## 风险、边界与改进建议

### 潜在风险

1. **单一入口限制**:
   - 当前只配置 `src/index.ts` 一个入口
   - 如果未来需要子路径导出（如 `@openai/codex-sdk/utils`），需要修改配置
   - **建议**: 提前规划可能的子路径导出

2. **类型生成依赖 `tsc`**:
   - `dts: true` 使用 `tsc` 生成声明文件，比 `esbuild` 慢
   - 大型项目可能导致构建时间增加
   - **缓解**: 考虑 `dts: { entry: { ... } }` 优化

3. **无 Bundle 分析**:
   - 配置中没有 Bundle 大小分析工具
   - 难以发现意外的依赖膨胀
   - **建议**: 添加 `--metafile` 选项生成构建元数据

### 边界情况

1. **外部依赖处理**:
   - `tsup` 默认会将所有依赖打包（bundle）
   - 对于 SDK，通常应该将依赖标记为 external
   - 当前配置依赖 `package.json` 的 `devDependencies` 策略（零运行时依赖）

2. **CSS/资源文件**:
   - 纯 TypeScript 项目无需处理
   - 如果未来添加 CSS 或静态资源，需要额外配置 loader

3. **Watch 模式性能**:
   - `tsup --watch` 在大型项目中可能消耗较多资源
   - 考虑配置 `ignoreWatch: ["**/*.test.ts"]` 排除测试文件

### 改进建议

1. **添加子路径导出支持**:
   ```typescript
   export default defineConfig({
     entry: {
       index: "src/index.ts",
       utils: "src/utils/index.ts",  // 如果未来需要
     },
     // ...
   });
   ```

2. **配置外部依赖**:
   ```typescript
   export default defineConfig({
     // ...
     external: ["@openai/codex"],  // 如果添加运行时依赖
   });
   ```

3. **启用元数据生成**:
   ```typescript
   export default defineConfig({
     // ...
     metafile: true,  // 生成构建元数据用于分析
   });
   ```

4. **优化 Watch 模式**:
   ```typescript
   export default defineConfig({
     // ...
     ignoreWatch: [
       "**/*.test.ts",
       "**/tests/**",
       "**/node_modules/**",
       "**/dist/**",
     ],
   });
   ```

5. **添加 Banner**:
   ```typescript
   export default defineConfig({
     // ...
     banner: {
       js: "/*! @openai/codex-sdk | Apache-2.0 */",
     },
   });
   ```

6. **分环境配置**:
   ```typescript
   import { defineConfig } from "tsup";
   
   const isDev = process.env.NODE_ENV === "development";
   
   export default defineConfig({
     entry: ["src/index.ts"],
     format: ["esm"],
     dts: true,
     sourcemap: isDev,
     clean: true,
     minify: !isDev,
     target: "node18",
     shims: false,
   });
   ```

7. **添加构建后验证**:
   在 `package.json` 中添加：
   ```json
   "scripts": {
     "build:verify": "tsup && node --input-type=module -e \"import './dist/index.js'\""
   }
   ```
