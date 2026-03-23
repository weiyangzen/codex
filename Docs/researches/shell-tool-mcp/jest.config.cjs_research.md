# shell-tool-mcp/jest.config.cjs 研究文档

## 场景与职责

`jest.config.cjs` 是 Jest 测试框架的配置文件，位于 `shell-tool-mcp` 项目根目录。其核心职责：

1. **配置测试环境**：指定 Node.js 作为测试运行环境
2. **配置 TypeScript 支持**：通过 ts-jest 预设实现 TypeScript 测试
3. **定义测试根目录**：限定测试文件搜索范围

## 功能点目的

### 配置项解析

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `preset` | `"ts-jest"` | 使用 ts-jest 预设，自动配置 TypeScript 支持 |
| `testEnvironment` | `"node"` | 在 Node.js 环境中运行测试（非浏览器环境） |
| `roots` | `["<rootDir>/tests"]` | 只在 `tests/` 目录下查找测试文件 |

### 为什么使用 CommonJS (.cjs)

- Jest 配置文件需要是 CommonJS 格式（`module.exports`）
- 使用 `.cjs` 扩展名明确标识为 CommonJS 模块
- 与项目中的 ES Module（tsup.config.ts 使用 `import`）区分开

### ts-jest 预设的作用

```javascript
// ts-jest 预设隐式配置：
{
  transform: {
    '^.+\\.tsx?$': 'ts-jest'  // 使用 ts-jest 转换 TypeScript
  },
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node']
}
```

## 具体技术实现

### 测试文件发现机制

```
Jest 测试发现流程：
1. 从 roots: ["<rootDir>/tests"] 开始扫描
2. 匹配模式：*.test.ts, *.spec.ts, *.test.js, *.spec.js（默认）
3. 在 shell-tool-mcp/tests/ 目录下找到：
   - bashSelection.test.ts
   - osRelease.test.ts
4. 使用 ts-jest 将 TypeScript 转换为 JavaScript
5. 在 Node.js 环境中执行测试
```

### 与 package.json 的集成

```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch"
  }
}
```

执行流程：
```bash
npm test
# 1. 调用 jest 命令
# 2. jest 查找 jest.config.cjs
# 3. 读取配置，初始化 ts-jest
# 4. 扫描 tests/ 目录
# 5. 执行测试，输出结果
```

### 与 tsconfig.json 的关系

```json
// tsconfig.json
{
  "include": ["src", "tests"]  // 包含测试文件
}
```

- ts-jest 使用项目的 tsconfig.json 进行类型检查
- 测试文件需要被 TypeScript 编译器识别
- 确保测试代码可以使用源码中的类型定义

## 关键代码路径与文件引用

| 文件 | 关联关系 |
|------|----------|
| `package.json` | `scripts.test` 调用 jest，依赖 `jest` 和 `ts-jest` |
| `tsconfig.json` | 定义 `include: ["src", "tests"]`，ts-jest 使用此配置 |
| `tests/bashSelection.test.ts` | 测试 Bash 选择逻辑 |
| `tests/osRelease.test.ts` | 测试 OS 信息解析 |
| `src/*.ts` | 被测试的源代码模块 |

## 依赖与外部交互

### 开发依赖

```json
{
  "devDependencies": {
    "@types/jest": "^29.5.14",    // Jest 类型定义
    "jest": "^29.7.0",             // 测试框架
    "ts-jest": "^29.3.4"           // TypeScript 支持
  }
}
```

### 外部工具交互

1. **Jest CLI**：
   - 读取 `jest.config.cjs` 作为默认配置
   - 支持命令行覆盖（如 `jest --config other.config.js`）

2. **ts-jest**：
   - 在内存中编译 TypeScript（不输出文件）
   - 使用项目的 `tsconfig.json` 进行类型检查

3. **Node.js**：
   - 提供测试运行环境
   - 支持 `node:` 前缀的内置模块（如 `node:path`）

## 风险、边界与改进建议

### 当前风险

1. **测试覆盖率不足**：
   - 仅测试了 `bashSelection.ts` 和 `osRelease.ts`
   - 缺少对 `index.ts`, `platform.ts`, `constants.ts` 的测试
   - 缺少集成测试

2. **配置简单但有限**：
   - 无覆盖率报告配置
   - 无测试超时配置
   - 无测试并行化配置

3. **模块格式潜在冲突**：
   - 项目使用 ES Module（tsup.config.ts 用 `import`）
   - Jest 配置使用 CommonJS（`module.exports`）
   - 目前无冲突，但未来可能需要注意

### 边界情况

1. **TypeScript 编译错误**：
   - 如果 tsconfig.json 配置严格，测试代码类型错误会导致测试失败
   - 这是预期行为，确保测试代码质量

2. **测试文件命名**：
   - 默认只识别 `.test.ts` 和 `.spec.ts`
   - 如果使用其他命名，需要配置 `testMatch`

3. **Node.js 版本**：
   - 要求 Node.js >= 18（package.json engines 字段）
   - 低版本可能不支持某些现代语法

### 改进建议

1. **增强测试配置**：

```javascript
/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/tests"],
  
  // 添加覆盖率配置
  collectCoverageFrom: [
    "src/**/*.ts",
    "!src/**/*.d.ts"
  ],
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "html"],
  
  // 添加测试超时
  testTimeout: 10000,
  
  // 清晰的测试报告
  verbose: true,
  
  // 模块路径别名（如果未来需要）
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/src/$1"
  }
};
```

2. **添加更多测试**：
   - `platform.test.ts`：测试 target triple 解析
   - `constants.test.ts`：验证变体列表完整性
   - `index.test.ts`：集成测试（可能需要 mock）

3. **考虑使用 ESM 配置**：
   - Jest 支持 ESM 配置（`jest.config.mjs`）
   - 与项目其他配置文件保持一致风格
   - 需要确保 ts-jest 兼容

4. **添加 CI 集成**：
   - 配置 GitHub Actions 运行测试
   - 上传覆盖率报告到 Codecov 或类似服务

5. **类型安全增强**：
   ```typescript
   // 使用 TypeScript 编写配置
   // jest.config.ts
   import type { Config } from 'jest';
   
   const config: Config = {
     preset: "ts-jest",
     testEnvironment: "node",
     roots: ["<rootDir>/tests"],
   };
   
   export default config;
   ```
