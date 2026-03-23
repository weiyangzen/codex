# shell-tool-mcp/tsconfig.json 研究文档

## 场景与职责

`tsconfig.json` 是 TypeScript 编译器的配置文件，定义：

1. **编译目标**：生成哪个版本的 JavaScript
2. **模块系统**：使用哪种模块规范
3. **类型检查**：启用哪些严格检查规则
4. **包含文件**：哪些文件参与编译

## 功能点目的

### 编译器选项解析

| 选项 | 值 | 说明 |
|------|-----|------|
| `target` | `"ES2022"` | 编译为 ES2022 标准 JavaScript |
| `module` | `"CommonJS"` | 使用 CommonJS 模块系统 |
| `moduleResolution` | `"Node"` | Node.js 风格的模块解析 |
| `noEmit` | `true` | 不输出文件（仅类型检查） |
| `strict` | `true` | 启用所有严格类型检查 |
| `esModuleInterop` | `true` | 支持 ES 模块与 CommonJS 互操作 |
| `forceConsistentCasingInFileNames` | `true` | 强制文件名大小写一致 |
| `skipLibCheck` | `true` | 跳过声明文件（.d.ts）类型检查 |

### 包含文件

```json
{
  "include": ["src", "tests"]
}
```

- `src/`：源代码目录
- `tests/`：测试代码目录

## 具体技术实现

### 为什么设置 `noEmit: true`

```
编译流程设计：
1. TypeScript 编译器（tsc）仅用于类型检查
2. 实际编译由 tsup（基于 esbuild）完成
3. tsup 更快，且支持打包优化
4. 分离关注点：tsc 负责类型安全，tsup 负责构建输出
```

对比：
- `tsc`：类型检查 + 编译（慢，但类型检查严格）
- `tsup`：快速编译 + 打包（基于 esbuild）
- 本项目：tsc 类型检查，tsup 实际构建

### 模块系统选择

```json
{
  "module": "CommonJS",
  "moduleResolution": "Node"
}
```

**原因**：
- 目标运行环境是 Node.js
- CommonJS 是 Node.js 的传统模块系统
- 与 `tsup.config.ts` 的 `format: ["cjs"]` 一致

**注意**：
- 源码中使用 ES Module 语法（`import/export`）
- TypeScript 编译为 CommonJS（`require/module.exports`）
- `esModuleInterop: true` 确保两种模块系统兼容

### 严格模式配置

```json
{
  "strict": true
}
```

启用以下所有严格检查：
- `noImplicitAny`：禁止隐式 any 类型
- `strictNullChecks`：严格空值检查
- `strictFunctionTypes`：严格函数类型检查
- `strictBindCallApply`：严格 bind/call/apply 检查
- `strictPropertyInitialization`：严格属性初始化检查
- `noImplicitThis`：禁止隐式 this 类型
- `alwaysStrict`：在 "use strict" 模式下解析

### 路径解析策略

```json
{
  "moduleResolution": "Node"
}
```

Node.js 风格解析：
```
import { foo } from "./bar"
1. 尝试 ./bar.ts
2. 尝试 ./bar.tsx
3. 尝试 ./bar.d.ts
4. 尝试 ./bar/package.json (types/main 字段)
5. 尝试 ./bar/index.ts

import { foo } from "baz"
1. 查找 node_modules/baz
2. 解析 package.json 的 types/main 字段
```

## 关键代码路径与文件引用

| 文件 | 关联关系 |
|------|----------|
| `tsup.config.ts` | 使用独立的构建配置，不直接使用 tsconfig.json |
| `jest.config.cjs` | ts-jest 会自动读取 tsconfig.json 进行类型检查 |
| `src/*.ts` | 源代码，受 tsconfig.json 约束 |
| `tests/*.ts` | 测试代码，受 tsconfig.json 约束 |

## 依赖与外部交互

### TypeScript 版本

```json
{
  "devDependencies": {
    "typescript": "^5.9.2"
  }
}
```

- TypeScript 5.9 是最新版本
- 支持最新的语言特性和类型系统改进

### 与 tsup 的关系

```typescript
// tsup.config.ts
export default defineConfig({
  entry: { "mcp-server": "src/index.ts" },
  format: ["cjs"],
  target: "node18",
  // 不使用 tsconfig.json，独立配置
});
```

**分离设计**：
- `tsconfig.json`：开发时类型检查
- `tsup.config.ts`：构建时编译配置
- 两者独立，但保持一致（如 target）

### 与 Jest 的关系

```javascript
// jest.config.cjs
module.exports = {
  preset: "ts-jest",
  // ts-jest 会自动读取 tsconfig.json
};
```

- ts-jest 使用 tsconfig.json 配置 TypeScript 编译器
- 确保测试代码与源代码使用相同的类型检查规则

## 风险、边界与改进建议

### 当前风险

1. **配置分离可能导致不一致**：
   - tsconfig.json 的 `target: "ES2022"` 与 tsup 的 `target: "node18"` 略有不同
   - 虽然 Node.js 18 支持 ES2022，但理论上可能有不一致

2. **noEmit 的副作用**：
   - 不能直接运行 `tsc` 生成输出
   - 新开发者可能困惑为什么 `tsc` 不产生文件

3. **缺少 exclude 配置**：
   - 没有显式排除文件
   - 如果 tests/ 包含大型 fixture 文件，可能影响性能

### 边界情况

1. **Node.js 内置模块**：
   - 使用 `node:` 前缀导入（如 `node:path`）
   - TypeScript 5.9 完全支持此语法

2. **第三方类型定义**：
   - `@types/node` 提供 Node.js API 类型
   - `@types/jest` 提供 Jest API 类型

3. **严格模式的边界**：
   - 严格模式可能拒绝一些合法的 JavaScript 代码
   - 需要确保所有代码都通过类型检查

### 改进建议

1. **统一 target 配置**：

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022"]
  }
}
```

确保与 tsup 的 `target: "node18"` 语义一致。

2. **添加 exclude 配置**：

```json
{
  "include": ["src", "tests"],
  "exclude": ["node_modules", "bin", "vendor"]
}
```

明确排除不需要编译的目录。

3. **添加路径别名**：

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  }
}
```

简化导入路径：
```typescript
// 之前
import { resolveBashPath } from "./bashSelection";

// 之后
import { resolveBashPath } from "@/bashSelection";
```

4. **添加输出目录配置（即使 noEmit）**：

```json
{
  "compilerOptions": {
    "outDir": "./bin",
    "declaration": true,
    "declarationDir": "./types"
  }
}
```

为未来可能的类型发布做准备。

5. **添加更多严格检查**：

```json
{
  "compilerOptions": {
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true
  }
}
```

进一步增强类型安全性。

6. **添加编译器诊断**：

```json
{
  "compilerOptions": {
    "diagnostics": true,
    "extendedDiagnostics": true
  }
}
```

在需要时输出详细的编译性能信息。

7. **考虑使用项目引用（Project References）**：

如果未来项目变大：

```json
{
  "references": [
    { "path": "./src" },
    { "path": "./tests" }
  ]
}
```

实现增量编译。

8. **添加 VS Code 配置**：

```json
// .vscode/settings.json
{
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true
}
```

确保 IDE 使用项目指定的 TypeScript 版本。
