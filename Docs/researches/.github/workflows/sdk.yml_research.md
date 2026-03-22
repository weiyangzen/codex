# sdk.yml 深度研究文档

## 场景与职责

`sdk.yml` 是 OpenAI Codex 项目的 **TypeScript SDK 持续集成工作流**，负责在代码推送和 Pull Request 时自动构建、测试和验证 TypeScript SDK 包。它是保证 SDK 代码质量和兼容性的关键门禁。

### 触发条件
- **Push 事件**: 推送到 `main` 分支时触发
- **Pull Request**: 所有 PR 都会触发，用于代码审查前的质量检查

### 核心职责
1. **环境准备**: 配置 Rust 工具链和 Node.js 环境
2. **依赖安装**: 安装系统依赖 (libcap-dev) 和 Node 依赖
3. **Rust 构建**: 构建 `codex` 二进制 (SDK 测试需要)
4. **SDK 构建**: 编译 TypeScript SDK
5. **代码检查**: 运行 ESLint 检查代码风格
6. **单元测试**: 执行 Jest 测试套件

---

## 功能点目的

### 1. 自托管运行器
```yaml
runs-on:
  group: codex-runners
  labels: codex-linux-x64
```
**目的**: 使用团队维护的自托管运行器，确保构建环境的一致性和安全性。
- 避免 GitHub 托管运行器的资源限制
- 支持自定义硬件配置
- 预装必要的系统依赖

### 2. 系统依赖安装
```yaml
sudo apt-get install -y --no-install-recommends pkg-config libcap-dev
```
**目的**: 
- `pkg-config`: 用于 Rust 构建时查找库
- `libcap-dev`: Linux capabilities 开发库，sandbox 功能依赖

### 3. Rust 工具链
```yaml
- uses: dtolnay/rust-toolchain@1.93.0
- run: cargo build --bin codex
```
**目的**: SDK 测试需要实际的 `codex` 二进制文件进行集成测试。

### 4. SDK 构建与验证
| 步骤 | 命令 | 目的 |
|------|------|------|
| 构建 | `pnpm -r --filter ./sdk/typescript run build` | 编译 TS 到 JS |
| 检查 | `pnpm -r --filter ./sdk/typescript run lint` | ESLint 代码检查 |
| 测试 | `pnpm -r --filter ./sdk/typescript run test` | Jest 单元测试 |

---

## 具体技术实现

### 关键流程

```yaml
1. Checkout 代码
2. 安装系统依赖 (libcap-dev, pkg-config)
3. 配置 pnpm (run_install: false)
4. 配置 Node.js 22 (带 pnpm 缓存)
5. 配置 Rust 1.93.0
6. 构建 codex 二进制
7. 安装 Node 依赖 (frozen-lockfile)
8. 构建 SDK
9. 运行 Lint
10. 运行测试
```

### 技术细节

#### pnpm 配置
```yaml
- uses: pnpm/action-setup@v4
  with:
    run_install: false  # 手动控制安装时机
```
**原因**: 需要在 Rust 构建完成后再安装 Node 依赖，确保构建顺序正确。

#### Node.js 缓存
```yaml
- uses: actions/setup-node@v6
  with:
    node-version: 22
    cache: pnpm  # 自动缓存 pnpm store
```

#### 工作目录
```yaml
defaults:
  run:
    working-directory: codex-rs  # Rust 构建在此目录
```

### 命令详解

#### 构建 SDK
```bash
pnpm -r --filter ./sdk/typescript run build
```
- `-r`: 递归执行
- `--filter ./sdk/typescript`: 仅针对 sdk/typescript 包
- `run build`: 执行 package.json 中的 build 脚本

#### 代码检查
```bash
pnpm -r --filter ./sdk/typescript run lint
```
- 使用 ESLint 检查代码风格
- 配置来自 `sdk/typescript/eslint.config.js`

#### 测试执行
```bash
pnpm -r --filter ./sdk/typescript run test
```
- 使用 Jest 测试框架
- 配置来自 `sdk/typescript/jest.config.cjs`

---

## 关键代码路径与文件引用

### 工作流文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/sdk.yml` | SDK CI 工作流 (本文件) |

### SDK 源码
| 路径 | 内容 |
|------|------|
| `sdk/typescript/` | TypeScript SDK 根目录 |
| `sdk/typescript/src/` | 源码目录 |
| `sdk/typescript/tests/` | 测试文件 |
| `sdk/typescript/package.json` | 包配置和脚本 |

### 配置文件
| 文件 | 用途 |
|------|------|
| `sdk/typescript/tsconfig.json` | TypeScript 编译配置 |
| `sdk/typescript/tsup.config.ts` | 打包配置 |
| `sdk/typescript/jest.config.cjs` | 测试配置 |
| `sdk/typescript/eslint.config.js` | 代码检查配置 |

### Rust 相关
| 文件 | 用途 |
|------|------|
| `codex-rs/Cargo.toml` | Rust 工作区配置 |
| `codex-rs/cli/` | codex 二进制源码 |

---

## 依赖与外部交互

### 外部服务
| 服务 | 用途 | 说明 |
|------|------|------|
| GitHub Actions | CI 执行 | 自托管运行器 |
| npm Registry | 依赖下载 | 通过 pnpm |
| crates.io | Rust 依赖 | 通过 Cargo |

### 依赖工具
| 工具 | 版本 | 用途 |
|------|------|------|
| Node.js | 22 | 运行时 |
| pnpm | 10.29.3 | 包管理 |
| Rust | 1.93.0 | codex 构建 |
| Jest | ^29.7.0 | 测试框架 |
| ESLint | 配置中 | 代码检查 |
| tsup | ^8.5.0 | 打包工具 |

### 系统依赖
| 包 | 用途 |
|----|------|
| libcap-dev | Linux capabilities |
| pkg-config | 库查找 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. 自托管运行器可用性
- **风险**: `codex-runners` 组中的 `codex-linux-x64` 运行器可能不可用
- **影响**: CI 队列堆积，PR 合并阻塞
- **建议**: 监控运行器健康状态，设置备用运行器

#### 2. Rust 构建时间
- **风险**: `cargo build --bin codex` 可能需要较长时间
- **当前**: timeout-minutes: 10
- **建议**: 考虑添加 Rust 构建缓存

#### 3. 测试依赖外部服务
- **风险**: 部分测试可能依赖外部 API
- **建议**: 使用 mocking 隔离外部依赖

### 边界条件

#### 1. 路径过滤
- 当前: 无路径过滤，所有变更都触发
- 建议: 添加路径过滤，仅 SDK 变更时触发
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'sdk/typescript/**'
      - '.github/workflows/sdk.yml'
  pull_request:
    paths:
      - 'sdk/typescript/**'
```

#### 2. Node 版本
- 当前: 固定 Node 22
- 建议: 测试矩阵覆盖多个 Node 版本 (18, 20, 22)

### 改进建议

#### 1. 添加构建缓存
```yaml
- uses: Swatinem/rust-cache@v2
  with:
    workspaces: codex-rs
```

#### 2. 添加测试覆盖率
```yaml
- name: Upload coverage
  uses: codecov/codecov-action@v3
  with:
    files: ./sdk/typescript/coverage/lcov.info
```

#### 3. 添加类型检查
```yaml
- name: Type check
  run: pnpm -r --filter ./sdk/typescript run type-check
```

#### 4. 优化触发条件
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'sdk/typescript/**'
      - 'pnpm-lock.yaml'
  pull_request:
    paths:
      - 'sdk/typescript/**'
      - 'pnpm-lock.yaml'
```

#### 5. 添加并发控制
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## 附录: SDK 项目结构

```
sdk/typescript/
├── src/                    # 源码
│   ├── codex.ts           # 主入口
│   ├── events.ts          # 事件类型
│   ├── exec.ts            # 执行逻辑
│   └── ...
├── tests/                  # 测试
│   ├── exec.test.ts
│   ├── run.test.ts
│   └── ...
├── samples/                # 示例代码
├── package.json           # 包配置
├── tsconfig.json          # TS 配置
├── tsup.config.ts         # 打包配置
└── jest.config.cjs        # 测试配置
```
