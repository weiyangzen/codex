# pnpm-workspace.yaml 研究文档

## 场景与职责

`pnpm-workspace.yaml` 是 pnpm 工作区（Workspace）的核心配置文件，定义了 Codex 项目中所有 JavaScript/TypeScript 子包的组织结构。该文件位于仓库根目录，是 pnpm 识别和管理 monorepo 中多个相关包的入口点。

在 Codex 项目中，此文件服务于以下场景：
- **Monorepo 包管理**：统一管理多个 JavaScript/TypeScript 子项目
- **依赖共享与去重**：通过 pnpm 的虚拟存储机制优化 node_modules 空间占用
- **构建脚本协调**：支持跨包脚本执行和依赖安装
- **安全性控制**：限制特定依赖的构建行为和子依赖引入

## 功能点目的

### 1. 工作区包定义 (`packages`)

```yaml
packages:
  - codex-cli          # CLI 工具包 (@openai/codex)
  - codex-rs/responses-api-proxy/npm  # Rust 响应 API 代理的 npm 封装
  - sdk/typescript     # TypeScript SDK (@openai/codex-sdk)
  - shell-tool-mcp     # Shell 工具 MCP 实现 (@openai/codex-shell-tool-mcp)
```

**目的**：声明构成工作区的所有子包目录，使 pnpm 能够：
- 识别本地包之间的依赖关系（本地包优先于远程 registry）
- 支持 `pnpm -r` 递归执行命令
- 在工作区根目录统一安装所有依赖

### 2. 忽略的构建依赖 (`ignoredBuiltDependencies`)

```yaml
ignoredBuiltDependencies:
  - esbuild
```

**目的**：
- `esbuild` 是一个高性能的 JavaScript 打包工具，使用 Go 编写
- 跳过其原生构建步骤可加速依赖安装
- 适用于预编译的二进制分发场景

### 3. 最小发布年龄 (`minimumReleaseAge`)

```yaml
minimumReleaseAge: 10080  # 分钟数 = 7 天
```

**目的**：
- 安全机制：新发布的包需等待 7 天后才能被安装
- 防止恶意包或存在严重 bug 的新版本立即影响项目
- 给予社区时间发现和报告潜在问题

### 4. 阻止异构子依赖 (`blockExoticSubdeps`)

```yaml
blockExoticSubdeps: true
```

**目的**：
- 阻止依赖使用 Git URL、本地路径等非标准 registry 来源的子依赖
- 增强供应链安全性，确保所有依赖来自可控的 npm registry
- 减少因外部仓库不可用或变更导致的构建不稳定

## 具体技术实现

### 数据结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `packages` | `string[]` | 工作区包目录列表，支持 glob 模式 |
| `ignoredBuiltDependencies` | `string[]` | 跳过原生构建的依赖包名 |
| `minimumReleaseAge` | `number` | 最小发布年龄（分钟） |
| `blockExoticSubdeps` | `boolean` | 是否阻止异构子依赖 |

### 包结构详情

| 包路径 | 包名 | 用途 |
|--------|------|------|
| `codex-cli` | `@openai/codex` | 主 CLI 工具，提供 `codex` 命令 |
| `codex-rs/responses-api-proxy/npm` | `@openai/codex-responses-api-proxy` | OpenAI Responses API 代理的 npm 封装 |
| `sdk/typescript` | `@openai/codex-sdk` | TypeScript SDK，提供程序化 API |
| `shell-tool-mcp` | `@openai/codex-shell-tool-mcp` | Shell 执行工具的 MCP 实现 |

### 与 package.json 的关联

根目录 `package.json` 定义了工作区级别的脚本和工具：

```json
{
  "name": "codex-monorepo",
  "private": true,
  "scripts": {
    "format": "prettier --check *.json *.md docs/*.md .github/workflows/*.yml **/*.js",
    "format:fix": "prettier --write ...",
    "write-hooks-schema": "cargo run ..."
  },
  "packageManager": "pnpm@10.29.3+sha512..."
}
```

**关键点**：
- `private: true` 防止意外发布根目录
- `packageManager` 字段指定精确的 pnpm 版本，确保团队环境一致

## 关键代码路径与文件引用

### 直接依赖文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `/home/sansha/Github/codex/package.json` | 根 package.json | 定义工作区级脚本和工具依赖 |
| `/home/sansha/Github/codex/pnpm-lock.yaml` | 锁定文件 | 记录精确依赖版本，确保可复现构建 |

### 工作区包文件

| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/codex-cli/package.json` | CLI 工具包配置 |
| `/home/sansha/Github/codex/codex-rs/responses-api-proxy/npm/package.json` | API 代理 npm 封装 |
| `/home/sansha/Github/codex/sdk/typescript/package.json` | TypeScript SDK 配置 |
| `/home/sansha/Github/codex/shell-tool-mcp/package.json` | Shell MCP 工具配置 |

### 相关配置

| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/.npmrc` | npm/pnpm 行为配置 |
| `/home/sansha/Github/codex/.prettierrc.toml` | 代码格式化配置 |

## 依赖与外部交互

### 内部依赖关系

```
pnpm-workspace.yaml
├── codex-cli/
│   └── (依赖其他本地包或外部 registry)
├── codex-rs/responses-api-proxy/npm/
│   └── (封装 Rust 二进制为 npm 包)
├── sdk/typescript/
│   └── (可能被 codex-cli 依赖)
└── shell-tool-mcp/
    └── (MCP 工具实现)
```

### 外部交互

| 外部系统 | 交互方式 | 说明 |
|----------|----------|------|
| npm registry | HTTPS | 下载非本地依赖包 |
| GitHub Packages | HTTPS | 可能用于私有包分发 |
| pnpm 虚拟存储 | 文件系统 | 全局依赖去重存储 |

### 与 Bazel 的协作

虽然 `pnpm-workspace.yaml` 是 pnpm 专属配置，但项目同时使用 Bazel 构建系统：
- Bazel 通过 `rules_js` 或类似规则可能消费 pnpm 的依赖解析结果
- `MODULE.bazel` 和 `pnpm-workspace.yaml` 分别管理 Rust 和 JavaScript 生态

## 风险、边界与改进建议

### 风险点

1. **版本锁定风险**
   - `packageManager` 字段锁定 pnpm 10.29.3，升级需全员同步
   - 若 pnpm 存在安全漏洞，需整体迁移

2. **供应链安全**
   - `minimumReleaseAge: 10080` 虽提供缓冲，但仍依赖 npm registry 的可用性
   - `blockExoticSubdeps: true` 无法阻止 registry 被投毒

3. **跨包依赖冲突**
   - 工作区内多个包可能依赖同一库的不同版本
   - pnpm 的虚拟存储虽可共存，但可能增加磁盘占用

### 边界情况

1. **新包添加**
   - 新增工作区包需手动编辑 `packages` 列表
   - 忘记添加会导致该包被当作外部依赖处理

2. **esbuild 原生构建**
   - `ignoredBuiltDependencies` 中跳过 esbuild 构建
   - 若平台无预编译二进制，可能导致运行时错误

3. **CI/CD 环境**
   - 需确保 CI 使用与 `packageManager` 字段一致的 pnpm 版本
   - 缓存策略需考虑 `pnpm-lock.yaml` 的变化

### 改进建议

1. **自动化验证**
   ```yaml
   # 建议添加 CI 检查
   - name: Verify pnpm version
     run: pnpm --version | grep "10.29.3"
   ```

2. **安全增强**
   - 考虑添加 `onlyBuiltDependencies` 白名单替代 `ignoredBuiltDependencies`
   - 评估启用 `strict-peer-dependencies` 避免隐式依赖

3. **文档完善**
   - 在 `packages` 旁添加注释说明每个包的用途
   - 记录 `minimumReleaseAge` 的选取理由

4. **与 Bazel 集成优化**
   - 探索使用 `aspect_rules_js` 统一 Bazel 和 pnpm 的依赖管理
   - 避免两套系统维护独立的锁定文件

5. **监控与告警**
   - 对工作区包添加依赖更新自动化检测（如 Dependabot）
   - 设置 `minimumReleaseAge` 过期包的提醒机制
