# shell-tool-mcp/package.json 研究文档

## 场景与职责

`package.json` 是 `@openai/codex-shell-tool-mcp` npm 包的核心配置文件，定义：

1. **包元数据**：名称、版本、许可证、仓库信息
2. **发布内容**：哪些文件随 npm 包发布
3. **构建脚本**：编译、测试、格式化等命令
4. **开发依赖**：开发和测试所需的依赖包
5. **引擎要求**：Node.js 版本限制

## 功能点目的

### 1. 包标识与元数据

```json
{
  "name": "@openai/codex-shell-tool-mcp",
  "version": "0.0.0-dev",
  "description": "Patched Bash and Zsh binaries for Codex shell execution.",
  "license": "Apache-2.0"
}
```

- **作用域包**：`@openai/` 命名空间下的官方包
- **版本策略**：`0.0.0-dev` 表示开发版本，正式发布时更新
- **许可证**：Apache-2.0，与主项目一致

### 2. 引擎要求

```json
{
  "engines": {
    "node": ">=18"
  }
}
```

- **Node.js 18+**：支持现代 JavaScript 特性（如 `fetch` API）
- 与 `tsconfig.json` 的 `target: "ES2022"` 一致
- 与 `tsup.config.ts` 的 `target: "node18"` 一致

### 3. 发布文件控制

```json
{
  "files": [
    "vendor",
    "README.md"
  ]
}
```

**关键决策**：
- 只发布 `vendor/`（原生二进制文件）和 `README.md`
- **不发布** `src/`（TypeScript 源码）
- **不发布** `bin/`（编译后的 JS）
- **不发布** 测试文件和配置

**原因**：
- 该包的核心价值是**原生 Bash/Zsh 二进制文件**
- TypeScript 代码仅用于开发时选择正确的二进制文件
- 运行时由 MCP 客户端（如 Codex CLI）处理

### 4. 脚本命令

| 脚本 | 命令 | 用途 |
|------|------|------|
| `clean` | `rm -rf bin` | 删除编译输出 |
| `build` | `tsup` | 编译 TypeScript 到 bin/ |
| `build:watch` | `tsup --watch` | 开发模式，监听文件变化 |
| `test` | `jest` | 运行单元测试 |
| `test:watch` | `jest --watch` | 测试开发模式 |
| `format` | `prettier --check .` | 检查代码格式 |
| `format:fix` | `prettier --write .` | 修复代码格式 |

### 5. 开发依赖

```json
{
  "devDependencies": {
    "@types/jest": "^29.5.14",     // Jest 类型
    "@types/node": "^20.19.18",    // Node.js 类型
    "jest": "^29.7.0",              // 测试框架
    "prettier": "^3.6.2",           // 代码格式化
    "ts-jest": "^29.3.4",           // TypeScript 测试支持
    "tsup": "^8.5.0",               // TypeScript 打包工具
    "typescript": "^5.9.2"          // TypeScript 编译器
  }
}
```

**技术栈选择**：
- **tsup**：基于 esbuild，快速打包，支持 TypeScript
- **Jest + ts-jest**：成熟的测试方案
- **Prettier**：统一的代码风格

### 6. 包管理器锁定

```json
{
  "packageManager": "pnpm@10.29.3+sha512.498e1fb4cca5aa06c1dcf2611e6fafc50972ffe7189998c409e90de74566444298ffe43e6cd2acdc775ba1aa7cc5e092a8b7054c811ba8c5770f84693d33d2dc"
}
```

- **pnpm**：使用 pnpm 作为包管理器
- **版本锁定**：精确到 `10.29.3`
- **SHA512 校验**：确保包管理器完整性

## 具体技术实现

### 构建流程

```
完整构建流程：
1. pnpm install          # 安装依赖
2. pnpm run build        # 调用 tsup
   ├── tsup 读取 tsup.config.ts
   ├── 编译 src/index.ts -> bin/mcp-server.js
   └── 添加 shebang (#!/usr/bin/env node)
3. pnpm run test         # 调用 jest
   └── 运行 tests/*.test.ts
```

### 发布流程

```
npm publish 流程：
1. npm 读取 package.json
2. 根据 files 字段筛选要发布的文件：
   - vendor/          # 包含
   - README.md        # 包含
   - src/             # 排除（不在 files 中）
   - bin/             # 排除（被 .gitignore 忽略）
   - tests/           # 排除
   - 配置文件         # 排除
3. 打包并上传到 npm registry
```

### 版本号策略

当前 `0.0.0-dev` 表示：
- 开发版本，不用于生产
- 正式发布时应遵循语义化版本（SemVer）
- 建议与 codex-cli 版本保持同步（README 强调版本匹配）

## 关键代码路径与文件引用

| 文件 | 关联关系 |
|------|----------|
| `tsup.config.ts` | 定义 build/build:watch 的具体行为 |
| `jest.config.cjs` | 定义 test/test:watch 的具体行为 |
| `.gitignore` | 排除 bin/ 和 node_modules/ |
| `src/index.ts` | 入口文件，编译为 bin/mcp-server.js |
| `vendor/` | 核心发布内容，包含 Bash/Zsh 二进制文件 |
| `README.md` | 发布内容之一，包含使用文档 |

## 依赖与外部交互

### 运行时依赖

**注意**：该包**没有** `dependencies`，只有 `devDependencies`。

这意味着：
- 运行时依赖由宿主环境（MCP 客户端）提供
- 该包仅提供静态资源（vendor/ 中的二进制文件）
- TypeScript 代码在开发时编译，不随包发布

### 外部系统集成

1. **npm registry**：
   - 包发布到 `@openai/codex-shell-tool-mcp`
   - 用户通过 `npx -y @openai/codex-shell-tool-mcp` 使用

2. **Codex CLI**：
   - 作为 MCP 服务器被调用
   - 配置示例见 README.md

3. **操作系统**：
   - 需要支持的平台：Linux (x64/arm64), macOS (x64/arm64)
   - 通过 vendor/ 中的原生二进制文件与 OS 交互

## 风险、边界与改进建议

### 当前风险

1. **版本管理**：
   - `0.0.0-dev` 不适合发布
   - 需要建立版本发布流程
   - 版本应与 codex-cli 保持兼容

2. **发布内容限制**：
   - 只发布 vendor/ 意味着 TypeScript 功能不可用
   - 如果用户需要程序化选择 Bash，无法直接使用

3. **引擎要求**：
   - Node.js >= 18 是合理的，但需要文档说明
   - 低版本 Node.js 会报错，但错误信息可能不清晰

4. **包管理器锁定**：
   - 强制使用 pnpm 可能给贡献者带来不便
   - 但确保了依赖一致性

### 边界情况

1. **vendor/ 目录缺失**：
   - 如果发布时 vendor/ 不存在，包将无实际功能
   - 需要确保 CI/CD 流程包含 vendor/

2. **二进制文件权限**：
   - vendor/ 中的二进制文件需要可执行权限
   - npm 发布时可能丢失权限，需要 postinstall 脚本修复

3. **跨平台兼容性**：
   - 不同平台需要不同的二进制文件
   - 选择逻辑在 TypeScript 代码中，但代码不随包发布
   - 依赖 MCP 客户端实现选择逻辑

### 改进建议

1. **添加发布脚本**：

```json
{
  "scripts": {
    "prepublishOnly": "pnpm run build && pnpm run test",
    "version": "echo '请手动更新版本号' && exit 1"
  }
}
```

2. **添加引擎检查**：

```json
{
  "engines": {
    "node": ">=18"
  },
  "engineStrict": true
}
```

3. **添加 bin 字段（如果需要 CLI）**：

```json
{
  "bin": {
    "codex-shell-tool-mcp": "./bin/mcp-server.js"
  }
}
```

4. **添加关键字**：

```json
{
  "keywords": [
    "codex",
    "openai",
    "mcp",
    "shell",
    "sandbox",
    "bash",
    "zsh"
  ]
}
```

5. **添加主页和 bugs 字段**：

```json
{
  "homepage": "https://github.com/openai/codex/tree/main/shell-tool-mcp#readme",
  "bugs": {
    "url": "https://github.com/openai/codex/issues"
  }
}
```

6. **考虑添加 exports 字段**：

```json
{
  "exports": {
    ".": {
      "types": "./src/types.ts",
      "default": "./src/index.ts"
    },
    "./vendor/*": "./vendor/*"
  }
}
```

7. **添加 scripts 文档**：

```json
{
  "scripts": {
    "build": "tsup",
    "build:watch": "tsup --watch",
    "test": "jest",
    "test:watch": "jest --watch",
    "format": "prettier --check .",
    "format:fix": "prettier --write .",
    "lint": "tsc --noEmit"
  }
}
```

8. **考虑发布 TypeScript 类型**：

如果其他项目需要类型支持：

```json
{
  "types": "./src/types.ts",
  "typesVersions": {
    "*": {
      "*": ["./src/types.ts"]
    }
  }
}
```

或编译生成 .d.ts 文件：

```json
{
  "scripts": {
    "build:types": "tsc --declaration --emitDeclarationOnly --outDir types"
  }
}
```
