# shell-tool-mcp-ci.yml 深度研究文档

## 场景与职责

`shell-tool-mcp-ci.yml` 是 OpenAI Codex 项目的 **Shell Tool MCP 持续集成工作流**，负责在 Shell Tool MCP 代码变更时运行快速验证（格式检查、测试、构建）。它是保证 Shell Tool MCP 包质量的快速反馈循环。

### 触发条件
- **Push 事件**: 仅当以下路径变更时触发
  - `shell-tool-mcp/**`
  - `.github/workflows/shell-tool-mcp-ci.yml`
  - `pnpm-lock.yaml`
  - `pnpm-workspace.yaml`
- **Pull Request**: 同样路径过滤，确保 PR 只相关变更时运行

### 核心职责
1. **快速验证**: 在代码推送时快速检查 Shell Tool MCP 包
2. **格式检查**: 使用 Prettier 确保代码风格一致
3. **单元测试**: 运行 Jest 测试套件
4. **构建验证**: 确保 TypeScript 能正确编译

---

## 功能点目的

### 1. 路径过滤触发
```yaml
on:
  push:
    paths:
      - "shell-tool-mcp/**"
      - ".github/workflows/shell-tool-mcp-ci.yml"
      - "pnpm-lock.yaml"
      - "pnpm-workspace.yaml"
```
**目的**: 
- 避免无关变更触发 CI，节省资源
- 仅当 Shell Tool MCP 相关文件变更时才运行
- 锁定文件变更时重新验证依赖兼容性

### 2. 快速反馈循环
```yaml
timeout-minutes: 10
```
**目的**: 确保快速完成，提供即时反馈。

### 3. 标准化检查流程
| 步骤 | 命令 | 目的 |
|------|------|------|
| 格式检查 | `pnpm --filter @openai/codex-shell-tool-mcp run format` | Prettier 风格检查 |
| 测试 | `pnpm --filter @openai/codex-shell-tool-mcp test` | Jest 单元测试 |
| 构建 | `pnpm --filter @openai/codex-shell-tool-mcp run build` | TypeScript 编译 |

---

## 具体技术实现

### 关键流程

```yaml
1. Checkout 代码
2. 配置 pnpm (run_install: false)
3. 配置 Node.js 22 (带 pnpm 缓存)
4. 安装依赖 (frozen-lockfile)
5. 运行格式检查
6. 运行测试
7. 运行构建
```

### 技术细节

#### Node 版本
```yaml
env:
  NODE_VERSION: 22
```
与主项目保持一致，使用 Node.js 22 LTS。

#### 包过滤
```bash
pnpm --filter @openai/codex-shell-tool-mcp <command>
```
使用 pnpm 的 filter 功能，仅操作指定包，避免整个工作区的开销。

#### 格式检查命令
```bash
pnpm --filter @openai/codex-shell-tool-mcp run format
```
**注意**: 这里 `run format` 实际上是 `prettier --check .`，用于检查而非修复。
修复命令是 `format:fix` (`prettier --write .`)。

### 命令详解

#### 格式检查
```bash
pnpm --filter @openai/codex-shell-tool-mcp run format
```
- 执行 `package.json` 中的 `"format": "prettier --check ."`
- 检查所有文件是否符合 Prettier 格式
- 失败时退出码非零

#### 测试
```bash
pnpm --filter @openai/codex-shell-tool-mcp test
```
- 执行 `package.json` 中的 `"test": "jest"`
- 运行 Jest 测试套件
- 配置来自 `jest.config.js` (如果有) 或 package.json

#### 构建
```bash
pnpm --filter @openai/codex-shell-tool-mcp run build
```
- 执行 `package.json` 中的 `"build": "tsup"`
- 使用 tsup 将 TypeScript 编译为 JavaScript
- 输出到 `bin/` 目录

---

## 关键代码路径与文件引用

### 工作流文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/shell-tool-mcp-ci.yml` | CI 工作流 (本文件) |
| `.github/workflows/shell-tool-mcp.yml` | 发布工作流 |

### Shell Tool MCP 源码
| 路径 | 内容 |
|------|------|
| `shell-tool-mcp/` | 包根目录 |
| `shell-tool-mcp/src/` | TypeScript 源码 |
| `shell-tool-mcp/patches/` | Bash/zsh 补丁 |
| `shell-tool-mcp/package.json` | 包配置 |

### 配置文件
| 文件 | 用途 |
|------|------|
| `pnpm-workspace.yaml` | pnpm 工作区配置 |
| `pnpm-lock.yaml` | 锁定文件 |

---

## 依赖与外部交互

### 外部服务
| 服务 | 用途 |
|------|------|
| GitHub Actions | CI 执行 |
| npm Registry | 依赖下载 |

### 依赖工具
| 工具 | 版本 | 用途 |
|------|------|------|
| Node.js | 22 | 运行时 |
| pnpm | 10.29.3 | 包管理 |
| Prettier | ^3.6.2 | 代码格式化 |
| Jest | ^29.7.0 | 测试框架 |
| tsup | ^8.5.0 | 打包工具 |
| TypeScript | ^5.9.2 | 类型检查 |

### 包信息
```json
{
  "name": "@openai/codex-shell-tool-mcp",
  "version": "0.0.0-dev",
  "packageManager": "pnpm@10.29.3"
}
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. 格式检查阻塞
- **风险**: `prettier --check` 失败会阻塞整个 CI
- **缓解**: 开发者应在提交前运行 `format:fix`
- **建议**: 考虑添加自动修复的 pre-commit hook

#### 2. 测试覆盖率未知
- **风险**: 没有覆盖率报告，无法评估测试质量
- **建议**: 添加 `--coverage` 标志和覆盖率上传

#### 3. 缺少类型检查
- **风险**: 仅构建不保证类型正确 (tsup 可能跳过类型检查)
- **建议**: 添加显式的 `tsc --noEmit` 步骤

### 边界条件

#### 1. 仅检查当前包
- 当前: 仅验证 `@openai/codex-shell-tool-mcp`
- 注意: 不验证依赖包的变化影响

#### 2. Ubuntu 单平台
- 当前: 仅在 ubuntu-latest 运行
- 限制: 不测试平台特定行为

### 改进建议

#### 1. 添加类型检查步骤
```yaml
- name: Type check
  run: pnpm --filter @openai/codex-shell-tool-mcp exec tsc --noEmit
```

#### 2. 添加测试覆盖率
```yaml
- name: Run tests with coverage
  run: pnpm --filter @openai/codex-shell-tool-mcp test --coverage
- name: Upload coverage
  uses: codecov/codecov-action@v3
```

#### 3. 添加并发控制
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

#### 4. 优化格式检查
```yaml
# 可选: 自动修复并提交
- name: Format fix
  if: github.event_name == 'pull_request'
  run: pnpm --filter @openai/codex-shell-tool-mcp run format:fix
- name: Commit changes
  if: github.event_name == 'pull_request'
  uses: stefanzweifel/git-auto-commit-action@v4
  with:
    commit_message: "Apply formatting changes"
```

#### 5. 添加缓存优化
```yaml
- name: Setup pnpm cache
  uses: actions/cache@v3
  with:
    path: |
      ~/.pnpm-store
      shell-tool-mcp/node_modules
    key: ${{ runner.os }}-pnpm-${{ hashFiles('pnpm-lock.yaml') }}
```

---

## 附录: 与发布工作流的关系

```
shell-tool-mcp-ci.yml (本文件)
├── 触发: shell-tool-mcp/** 变更
├── 目的: 快速验证
└── 输出: 质量门禁

shell-tool-mcp.yml (发布工作流)
├── 触发: rust-release.yml 调用
├── 目的: 构建和发布
└── 输出: npm 包
```

CI 工作流确保代码质量，发布工作流负责制品构建，两者形成完整的质量保证体系。
