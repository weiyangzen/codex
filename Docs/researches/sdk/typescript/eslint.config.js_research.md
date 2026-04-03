# eslint.config.js 研究文档

## 场景与职责

`eslint.config.js` 是 ESLint 静态代码分析工具的配置文件，位于 `sdk/typescript/` 目录下。它定义了 TypeScript SDK 项目的代码质量规则，用于在开发和 CI 阶段捕获潜在错误、强制执行代码风格一致性。

该文件采用 ESLint v9 引入的 Flat Config 格式，取代了传统的 `.eslintrc` 配置文件。

## 功能点目的

配置文件实现以下核心功能：

1. **基础规则集**: 集成 ESLint 推荐规则和 TypeScript 推荐规则
2. **Node.js 协议规范**: 强制使用 `node:` 前缀导入 Node.js 内置模块
3. **未使用变量管理**: 配置灵活的未使用变量检测，允许下划线前缀的变量名

## 具体技术实现

### 配置结构

```javascript
import eslint from "@eslint/js";
import { defineConfig } from "eslint/config";
import tseslint from "typescript-eslint";
import nodeImport from "eslint-plugin-node-import";

export default defineConfig(
  eslint.configs.recommended,
  tseslint.configs.recommended,
  {
    plugins: {
      "node-import": nodeImport,
    },
    rules: {
      "node-import/prefer-node-protocol": 2,
      "@typescript-eslint/no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
    },
  }
);
```

### 配置详解

#### 1. 基础规则集

| 配置来源 | 说明 |
|----------|------|
| `eslint.configs.recommended` | ESLint 核心推荐规则，包含常见错误检测 |
| `tseslint.configs.recommended` | TypeScript 推荐规则，包含 TS 特定最佳实践 |

#### 2. Node.js 协议规则

```javascript
"node-import/prefer-node-protocol": 2
```

- **规则**: 强制使用 `node:` 前缀导入 Node.js 内置模块
- **错误级别**: `2` (等同于 `"error"`)
- **示例**:
  ```typescript
  // ✅ 正确
  import fs from "node:fs/promises";
  
  // ❌ 错误
  import fs from "fs/promises";
  ```

**设计意图**:
- 明确区分内置模块和第三方包
- 避免与 npm 上的 polyfill 包冲突
- 符合 Node.js 官方推荐做法

#### 3. 未使用变量规则

```javascript
"@typescript-eslint/no-unused-vars": [
  "error",
  {
    argsIgnorePattern: "^_",
    varsIgnorePattern: "^_",
  },
]
```

- **规则**: 检测未使用的变量和参数
- **例外**: 以下划线 `_` 开头的名称被忽略
- **用途**: 允许故意忽略的参数（如回调中的未使用参数）

**示例**:
```typescript
// ✅ 允许 - 以下划线开头
const _unused = "value";
function callback(_err: Error, data: string) { }

// ❌ 错误 - 未使用且不以 _ 开头
const unused = "value";
```

### Flat Config 格式特点

相比传统 `.eslintrc`：
- 使用 JavaScript/ESM 而非 JSON/YAML
- 支持 `import` 语法和逻辑表达式
- 配置项按数组顺序合并，后项覆盖前项
- 使用 `defineConfig` 提供类型提示

## 关键代码路径与文件引用

- **配置文件位置**: `sdk/typescript/eslint.config.js`
- **调用方**: `package.json` 中的脚本
  ```json
  "lint": "pnpm eslint \"src/**/*.ts\" \"tests/**/*.ts\"",
  "lint:fix": "pnpm eslint --fix \"src/**/*.ts\" \"tests/**/*.ts\""
  ```
- **检查范围**:
  - `src/**/*.ts`: 源代码
  - `tests/**/*.ts`: 测试代码
  - `tsup.config.ts`: 构建配置

### 依赖的包

| 包名 | 版本 | 用途 |
|------|------|------|
| `eslint` | `^9.36.0` | 核心工具 |
| `typescript-eslint` | `^8.45.0` | TypeScript 支持 |
| `eslint-plugin-node-import` | `^1.0.5` | Node.js 协议规则 |
| `eslint-config-prettier` | `^9.1.2` | 禁用与 Prettier 冲突的规则 |

## 依赖与外部交互

### 与 Prettier 的集成

`eslint-config-prettier` 在 `package.json` 中被列为 devDependency，用于：
- 禁用 ESLint 中与代码格式相关的规则
- 避免与 Prettier 的格式化冲突
- 让 ESLint 专注于代码质量，Prettier 专注于代码格式

### 与 TypeScript 的集成

`typescript-eslint` 提供：
- 解析 TypeScript 语法
- 类型感知的 lint 规则
- 与 `tsconfig.json` 的集成

### IDE 集成

ESLint 配置会被主流 IDE 自动识别：
- VS Code: 通过 ESLint 扩展
- WebStorm: 内置支持
- Vim/Neovim: 通过 LSP 或 ALE

## 风险、边界与改进建议

### 潜在风险

1. **规则升级兼容性**:
   - `typescript-eslint` v8 与 ESLint v9 的兼容性需要持续关注
   - Flat Config 格式较新，某些旧插件可能不支持

2. **规则覆盖不足**:
   - 当前配置仅使用 `recommended` 规则集，可能遗漏一些有用的规则
   - 缺少针对测试文件的特定规则配置

3. **性能问题**:
   - 大型代码库中类型感知的规则可能较慢
   - 未配置缓存策略

### 边界情况

1. **文件扩展名**:
   - 配置中未显式指定 `files` 模式，依赖 ESLint 默认行为
   - `.js` 文件（如 `eslint.config.js` 自身）也会被检查

2. **全局变量**:
   - 未配置 `globals`，依赖 `@types/node` 和 `@types/jest`

### 改进建议

1. **增强规则集**:
   ```javascript
   export default defineConfig(
     eslint.configs.recommended,
     tseslint.configs.recommendedTypeChecked, // 使用类型感知规则
     {
       languageOptions: {
         parserOptions: {
           project: "./tsconfig.json",
         },
       },
     }
   );
   ```

2. **添加文件特定配置**:
   ```javascript
   {
     files: ["tests/**/*.ts"],
     rules: {
       // 测试文件允许更宽松的规则
       "@typescript-eslint/no-explicit-any": "off",
     },
   }
   ```

3. **配置忽略模式**:
   ```javascript
   {
     ignores: ["dist/**", "node_modules/**", "coverage/**"],
   }
   ```

4. **添加导入排序规则**:
   ```javascript
   import importPlugin from "eslint-plugin-import";
   
   // 在 rules 中添加
   "import/order": ["error", { "alphabetize": { "order": "asc" } }]
   ```

5. **启用更严格的 TypeScript 规则**:
   - `@typescript-eslint/no-floating-promises`: 检测未处理的 Promise
   - `@typescript-eslint/await-thenable`: 确保只 await Promise
   - `@typescript-eslint/no-misused-promises`: 防止 Promise 误用
