# package.json 文件研究文档

## 场景与职责

package.json 是 Node.js/npm 项目的配置文件，在 OpenAI Codex 项目中承担：
- **仓库维护任务**: 格式化、代码检查等跨语言任务
- **pnpm 工作区根**: 管理 monorepo 中的 Node.js 包
- **依赖安全**: 通过 resolutions/overrides 修复已知漏洞
- **工具版本锁定**: 确保团队成员使用一致的 Node.js 和 pnpm 版本

## 功能点目的

### 1. 项目定位
```
codex-monorepo
├── 主要: Rust (codex-rs/)
├── 次要: TypeScript/JavaScript (codex-cli/, sdk/, shell-tool-mcp/)
└── 维护: Node.js 工具链 (本文件)
```

### 2. 脚本功能
| 脚本 | 命令 | 用途 |
|------|------|------|
| `format` | prettier --check | 检查代码格式 |
| `format:fix` | prettier --write | 修复代码格式 |
| `write-hooks-schema` | cargo run ... | 生成 hooks 协议文件 |

### 3. 安全修复
```json
"resolutions": {
  "braces": "^3.0.3",        // 修复正则 DoS
  "micromatch": "^4.0.8",    // 修复路径遍历
  "semver": "^7.7.1"         // 修复正则 DoS
},
"overrides": {
  "punycode": "^2.3.1"       // 修复解析漏洞
}
```

## 具体技术实现

### 文件结构
```json
{
  "name": "codex-monorepo",
  "private": true,
  "description": "Tools for repo-wide maintenance.",
  "scripts": { ... },
  "devDependencies": { ... },
  "resolutions": { ... },
  "overrides": { ... },
  "engines": { ... },
  "packageManager": "..."
}
```

### 关键字段详解

#### 1. 私有包标记
```json
"private": true
```
- 防止意外发布到 npm
- 表明这是内部工具配置

#### 2. 脚本定义
```json
"scripts": {
  "format": "prettier --check *.json *.md docs/*.md .github/workflows/*.yml **/*.js",
  "format:fix": "prettier --write *.json *.md docs/*.md .github/workflows/*.yml **/*.js",
  "write-hooks-schema": "cargo run --manifest-path ./codex-rs/Cargo.toml -p codex-hooks --bin write_hooks_schema_fixtures"
}
```

**格式化范围**:
| 模式 | 说明 |
|------|------|
| `*.json` | 根目录 JSON 文件 |
| `*.md` | 根目录 Markdown 文件 |
| `docs/*.md` | 文档目录 |
| `.github/workflows/*.yml` | CI 工作流 |
| `**/*.js` | 所有 JavaScript 文件 |

#### 3. 依赖覆盖
```json
"resolutions": {
  "braces": "^3.0.3",
  "micromatch": "^4.0.8",
  "semver": "^7.7.1"
}
```

**resolutions vs overrides**:
| 字段 | 包管理器 | 用途 |
|------|---------|------|
| `resolutions` | Yarn/pnpm | 强制解析到特定版本 |
| `overrides` | npm | 覆盖依赖版本 |

**覆盖的漏洞**:
| 包 | CVE | 修复版本 |
|----|-----|---------|
| braces | CVE-2024-4068 | ^3.0.3 |
| micromatch | CVE-2024-4067 | ^4.0.8 |
| semver | CVE-2022-25883 | ^7.7.1 |
| punycode | CVE-2023-XXXX | ^2.3.1 |

#### 4. 引擎约束
```json
"engines": {
  "node": ">=22",
  "pnpm": ">=10.29.3"
}
```

**版本要求**:
- Node.js >= 22 (LTS)
- pnpm >= 10.29.3

#### 5. 包管理器锁定
```json
"packageManager": "pnpm@10.29.3+sha512.498e1fb4cca5aa06c1dcf2611e6fafc50972ffe7189998c409e90de74566444298ffe43e6cd2acdc775ba1aa7cc5e092a8b7054c811ba8c5770f84693d33d2dc"
```

**Corepack 支持**:
- 启用 Corepack 后自动使用指定版本的 pnpm
- SHA512 哈希确保包管理器完整性

### 工作区配置
```yaml
# pnpm-workspace.yaml
packages:
  - codex-cli
  - sdk
  - shell-tool-mcp
```

**工作区结构**:
```
root/
├── package.json          # 根配置（本文件）
├── pnpm-workspace.yaml   # 工作区定义
├── pnpm-lock.yaml        # 锁定文件
├── codex-cli/
│   └── package.json      # CLI 包
├── sdk/
│   └── package.json      # SDK 包
└── shell-tool-mcp/
    └── package.json      # MCP 工具包
```

## 关键代码路径与文件引用

### 相关文件
| 文件 | 说明 |
|------|------|
| `/home/sansha/Github/codex/package.json` | 本文件 |
| `/home/sansha/Github/codex/pnpm-workspace.yaml` | pnpm 工作区配置 |
| `/home/sansha/Github/codex/pnpm-lock.yaml` | 依赖锁定文件 |
| `/home/sansha/Github/codex/.prettierrc.toml` | Prettier 配置 |
| `/home/sansha/Github/codex/.prettierignore` | Prettier 忽略模式 |

### CI/CD 集成
```yaml
# .github/workflows/ci.yml
- name: Setup pnpm
  uses: pnpm/action-setup@v4
  with:
    run_install: false

- name: Install dependencies
  run: pnpm install --frozen-lockfile

- name: Check formatting
  run: pnpm run format
```

### 使用命令
```bash
# 安装依赖
pnpm install

# 检查格式
pnpm run format

# 修复格式
pnpm run format:fix

# 生成 hooks schema
pnpm run write-hooks-schema
```

## 依赖与外部交互

### Node.js 生态系统
```
package.json
├── pnpm ─────────────────────────┐
│   ├── 工作区管理                 │
│   ├── 依赖解析                   ├── 包管理
│   └── 脚本运行                   │
├── Prettier ─────────────────────┤
│   ├── JSON 格式化                │
│   ├── Markdown 格式化            ├── 代码格式化
│   ├── YAML 格式化                │
│   └── JavaScript 格式化          │
└── Corepack ─────────────────────┘
    └── 包管理器版本管理
```

### 与 Rust 项目的关系
| 方面 | Node.js | Rust |
|------|---------|------|
| 主要代码 | 配置/脚本 | codex-rs/ |
| 构建系统 | pnpm | Cargo/Bazel |
| 包管理 | package.json | Cargo.toml |
| 锁定文件 | pnpm-lock.yaml | Cargo.lock |

**交互点**:
```json
// package.json 调用 Cargo
"write-hooks-schema": "cargo run --manifest-path ./codex-rs/Cargo.toml ..."
```

### 与 justfile 的关系
| 文件 | 范围 | 主要用途 |
|------|------|---------|
| `justfile` | Rust 开发 | 构建、测试、运行 |
| `package.json` | 仓库维护 | 格式化、Node.js 工具 |

**分工**:
- justfile: Rust 代码的开发工作流
- package.json: 跨语言文件格式化和 Node.js 工具

## 风险、边界与改进建议

### 风险

#### 1. 依赖覆盖维护
```
风险: resolutions/overrides 可能过时
影响: 新漏洞可能通过传递依赖引入
缓解: 定期审计依赖（npm audit, pnpm audit）
```

#### 2. 版本约束
```
风险: Node.js >=22 可能排除某些环境
影响: 旧系统无法运行维护脚本
缓解: 考虑降低版本要求或使用 nvm
```

#### 3. 格式化范围
```
风险: **/*.js 可能匹配过多文件
影响: 性能问题或意外格式化
缓解: 细化模式或添加 .prettierignore
```

### 边界

#### 功能边界
- 不管理 Rust 依赖（由 Cargo 处理）
- 不替代 Bazel 作为主要构建系统
- 不用于生产代码部署

#### 范围边界
- 仅用于仓库维护任务
- 不管理应用运行时依赖

### 改进建议

#### 1. 添加更多格式化工具
```json
{
  "scripts": {
    "format": "pnpm run format:prettier && pnpm run format:toml",
    "format:prettier": "prettier --check ...",
    "format:toml": "taplo format --check **/*.toml",
    "format:fix": "pnpm run format:prettier --write && pnpm run format:toml --write"
  },
  "devDependencies": {
    "@taplo/cli": "^0.7.0"
  }
}
```

#### 2. 添加 lint 脚本
```json
{
  "scripts": {
    "lint": "pnpm run lint:json && pnpm run lint:yaml",
    "lint:json": "eslint **/*.json",
    "lint:yaml": "yamllint .github/workflows/"
  }
}
```

#### 3. 添加依赖审计
```json
{
  "scripts": {
    "audit": "pnpm audit --audit-level moderate",
    "audit:fix": "pnpm update --interactive"
  }
}
```

#### 4. 改进引擎约束
```json
{
  "engines": {
    "node": ">=20.0.0",
    "pnpm": ">=9.0.0"
  },
  "engineStrict": false
}
```

#### 5. 添加仓库健康检查
```json
{
  "scripts": {
    "healthcheck": "pnpm run format && pnpm run check:lockfile",
    "check:lockfile": "git diff --exit-code pnpm-lock.yaml || (echo 'Lockfile out of date' && exit 1)"
  }
}
```

#### 6. 文档生成
```json
{
  "scripts": {
    "docs:readme": "markdown-toc -i README.md",
    "docs:links": "markdown-link-check docs/*.md"
  }
}
```

#### 7. 添加类型检查（如有 TS 代码）
```json
{
  "scripts": {
    "typecheck": "tsc --noEmit",
    "typecheck:watch": "tsc --noEmit --watch"
  }
}
```

#### 8. 改进安全策略
```json
{
  "pnpm": {
    "overrides": {
      "braces": "$braces",
      "micromatch": "$micromatch"
    }
  },
  "dependenciesMeta": {
    "braces": {
      "injected": true
    }
  }
}
```

### 维护建议

#### 定期任务
| 频率 | 任务 | 命令 |
|------|------|------|
| 每周 | 检查依赖更新 | `pnpm outdated` |
| 每月 | 运行安全审计 | `pnpm audit` |
| 每季度 | 更新 resolutions | 手动审查 |
| 发布前 | 验证锁定文件 | `pnpm install --frozen-lockfile` |

#### 版本管理
```bash
# 更新 pnpm
pnpm add -g pnpm@latest

# 更新 packageManager 字段
pnpm pkg set packageManager=pnpm@$(pnpm --version)

# 更新锁定文件
pnpm install --no-frozen-lockfile
```

#### CI 一致性
确保 CI 使用与本地相同的工具版本：
```yaml
- uses: pnpm/action-setup@v4
  with:
    version: 10.29.3  # 与 packageManager 一致
```
