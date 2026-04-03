# package.json 研究文档

## 场景与职责

`package.json` 是 TypeScript SDK 项目的核心配置文件，定义了包的元数据、依赖关系、脚本命令和发布配置。它是 npm/pnpm 生态系统的入口点，决定了包如何被安装、构建、测试和分发。

## 功能点目的

该文件实现以下核心功能：

1. **包标识**: 定义包名、版本、描述和仓库信息
2. **模块导出**: 配置 ESM 模块的入口点和类型定义
3. **脚本自动化**: 提供开发、构建、测试、格式化的命令
4. **依赖管理**: 声明开发和运行时依赖
5. **引擎约束**: 指定 Node.js 版本要求
6. **发布配置**: 控制哪些文件被包含在 npm 包中

## 具体技术实现

### 包元数据

```json
{
  "name": "@openai/codex-sdk",
  "version": "0.0.0-dev",
  "description": "TypeScript SDK for Codex APIs.",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/openai/codex.git",
    "directory": "sdk/typescript"
  },
  "keywords": ["openai", "codex", "sdk", "typescript", "api"],
  "license": "Apache-2.0"
}
```

**关键设计决策**:
- **包名**: 使用 `@openai` 作用域，表明是官方包
- **版本**: `0.0.0-dev` 表示开发版本，正式发布时会更新
- **仓库**: 指向 monorepo 中的子目录

### 模块系统配置

```json
{
  "type": "module",
  "engines": {
    "node": ">=18"
  },
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  }
}
```

**配置解析**:

| 字段 | 值 | 说明 |
|------|-----|------|
| `type` | `"module"` | 启用原生 ESM 支持 |
| `engines.node` | `">=18"` | 最低 Node.js 版本要求 |
| `module` | `"./dist/index.js"` | ESM 入口点 |
| `types` | `"./dist/index.d.ts"` | TypeScript 类型定义 |
| `exports` | 条件导出 | 支持 `"import"` 和 `"types"` 条件 |

**ESM 优先策略**:
- 项目采用纯 ESM 方案，不提供 CommonJS 导出
- 这是现代 Node.js 包的趋势
- 要求使用者也使用 ESM 或动态导入

### 发布配置

```json
{
  "files": ["dist"],
  "sideEffects": false
}
```

- **`files`**: 仅发布 `dist` 目录，排除源码和测试
- **`sideEffects`**: 声明无副作用，允许打包工具进行 Tree Shaking

### 脚本命令

```json
{
  "scripts": {
    "clean": "rm -rf dist",
    "build": "tsup",
    "build:watch": "tsup --watch",
    "lint": "pnpm eslint \"src/**/*.ts\" \"tests/**/*.ts\"",
    "lint:fix": "pnpm eslint --fix \"src/**/*.ts\" \"tests/**/*.ts\"",
    "test": "jest",
    "test:watch": "jest --watch",
    "coverage": "jest --coverage",
    "format": "prettier --check .",
    "format:fix": "prettier --write .",
    "prepare": "pnpm run build"
  }
}
```

**脚本分类**:

| 类别 | 脚本 | 说明 |
|------|------|------|
| 构建 | `clean`, `build`, `build:watch` | 使用 `tsup` 构建 |
| 代码质量 | `lint`, `lint:fix` | ESLint 检查 |
| 测试 | `test`, `test:watch`, `coverage` | Jest 测试 |
| 格式化 | `format`, `format:fix` | Prettier 格式化 |
| 生命周期 | `prepare` | 安装时自动构建 |

**关键脚本详解**:

1. **`prepare`**: npm 生命周期脚本，在 `npm install` 后自动执行
   - 确保包安装后立即可用
   - 对于 Git 依赖特别重要

2. **`build:watch`**: 开发模式，监听文件变化自动重新构建

3. **`coverage`**: 生成测试覆盖率报告

### 开发依赖

```json
{
  "devDependencies": {
    "@modelcontextprotocol/sdk": "^1.24.0",
    "@types/jest": "^29.5.14",
    "@types/node": "^20.19.18",
    "eslint": "^9.36.0",
    "eslint-config-prettier": "^9.1.2",
    "eslint-plugin-jest": "^29.0.1",
    "eslint-plugin-node-import": "^1.0.5",
    "jest": "^29.7.0",
    "prettier": "^3.6.2",
    "ts-jest": "^29.3.4",
    "ts-jest-mock-import-meta": "^1.3.1",
    "ts-node": "^10.9.2",
    "tsup": "^8.5.0",
    "typescript": "^5.9.2",
    "typescript-eslint": "^8.45.0",
    "zod": "^3.24.2",
    "zod-to-json-schema": "^3.24.6"
  }
}
```

**依赖分类分析**:

| 类别 | 包 | 用途 |
|------|-----|------|
| 类型定义 | `@types/jest`, `@types/node` | TypeScript 类型 |
| 构建工具 | `typescript`, `tsup`, `ts-node` | 编译和打包 |
| 测试框架 | `jest`, `ts-jest`, `ts-jest-mock-import-meta` | 单元测试 |
| 代码质量 | `eslint`, `typescript-eslint`, `eslint-*` | 静态分析 |
| 格式化 | `prettier`, `eslint-config-prettier` | 代码风格 |
| Schema 验证 | `zod`, `zod-to-json-schema` | 运行时类型检查 |
| MCP | `@modelcontextprotocol/sdk` | Model Context Protocol 支持 |

**值得注意的依赖**:

- **`@modelcontextprotocol/sdk`**: 表明 SDK 支持 MCP 协议
- **`zod` + `zod-to-json-schema`**: 提供类型安全的 Schema 定义
- **无运行时依赖**: 所有依赖都是 `devDependencies`，包本身零依赖

### 包管理器配置

```json
{
  "packageManager": "pnpm@10.29.3+sha512.498e1fb4cca5aa06c1dcf2611e6fafc50972ffe7189998c409e90de74566444298ffe43e6cd2acdc775ba1aa7cc5e092a8b7054c811ba8c5770f84693d33d2dc"
}
```

- **指定包管理器**: pnpm 10.29.3
- **完整性校验**: SHA512 哈希确保版本一致性
- **Corepack 支持**: Node.js 16+ 会自动使用指定的包管理器

## 关键代码路径与文件引用

### 配置文件网络

```
package.json
├── tsconfig.json (TypeScript 配置)
├── tsup.config.ts (构建配置)
├── jest.config.cjs (测试配置)
├── eslint.config.js (代码质量配置)
├── .prettierrc (格式化配置)
└── .prettierignore (格式化忽略)
```

### 源码入口

- **主入口**: `src/index.ts` (由 `tsup.config.ts` 指定)
- **构建输出**: `dist/index.js` 和 `dist/index.d.ts`

### 脚本依赖链

```
prepare (npm install)
  └── build
      └── tsup
          └── tsconfig.json

test
  └── jest
      └── jest.config.cjs
          └── tsconfig.json
          └── tests/setupCodexHome.ts

lint
  └── eslint
      └── eslint.config.js
          └── tsconfig.json
```

## 依赖与外部交互

### 运行时依赖

**零运行时依赖设计**:
- 所有依赖都是 `devDependencies`
- 运行时仅依赖 Node.js 内置模块
- 使用者需要自行安装 `@openai/codex` CLI

### 隐式依赖

虽然未在 `dependencies` 中声明，但 SDK 运行时依赖：
- `@openai/codex` CLI 工具
- Node.js >= 18

### 上游依赖关系

```
使用者项目
  └── @openai/codex-sdk
      └── (spawn) codex CLI
          └── OpenAI API
```

## 风险、边界与改进建议

### 潜在风险

1. **零运行时依赖的双刃剑**:
   - 优点：包体积小，无依赖冲突
   - 风险：使用者可能忘记安装 `@openai/codex` CLI
   - **建议**: 在文档中明确说明，或在代码中检查 CLI 存在性

2. **`prepare` 脚本问题**:
   - 在 CI 环境中可能不需要构建
   - 某些环境（如 Heroku）会自动运行 `prepare`
   - **建议**: 考虑使用 `prepublishOnly` 替代

3. **版本 `0.0.0-dev`**:
   - 开发版本号可能导致缓存问题
   - npm 可能认为所有 `0.0.0-dev` 版本相同
   - **建议**: 使用语义化版本或带时间戳的版本

4. **ESM 兼容性**:
   - 纯 ESM 包在 CommonJS 项目中使用困难
   - 需要 `import()` 动态导入
   - **建议**: 考虑提供双模式（Dual Package）支持

### 边界情况

1. **Node.js 版本边界**:
   - `>=18` 包含 18.0.0，但某些特性可能需要更高版本
   - 建议测试最低版本兼容性

2. **Windows 兼容性**:
   - `rm -rf` 在 Windows PowerShell 中可用，但在 CMD 中不可用
   - 建议使用 `rimraf` 包实现跨平台

3. **pnpm 版本锁定**:
   - 严格的包管理器版本可能阻碍贡献者
   - 建议放宽到 `pnpm@^10.29.0`

### 改进建议

1. **添加 `engines` 到 `.npmrc`**:
   ```
   engine-strict=true
   ```
   确保使用正确的 Node.js 版本

2. **添加 `peerDependencies`**:
   ```json
   "peerDependencies": {
     "@openai/codex": "^1.0.0"
   },
   "peerDependenciesMeta": {
     "@openai/codex": {
       "optional": true
     }
   }
   ```

3. **脚本跨平台化**:
   ```json
   "clean": "rimraf dist",
   ```
   需要添加 `rimraf` 到 devDependencies

4. **添加类型导出验证**:
   ```json
   "scripts": {
     "test:types": "tsc --noEmit"
   }
   ```

5. **优化 `files` 配置**:
   ```json
   "files": [
     "dist",
     "README.md",
     "LICENSE"
   ]
   ```

6. **添加 `keywords` 优化搜索**:
   ```json
   "keywords": [
     "openai",
     "codex",
     "ai",
     "agent",
     "cli",
     "typescript",
     "sdk"
   ]
   ```

7. ** funding 和 sponsors 信息**:
   ```json
   "funding": {
     "type": "github",
     "url": "https://github.com/sponsors/openai"
   }
   ```
