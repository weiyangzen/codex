# ci.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流是项目的主要 CI 工作流，负责 JavaScript/TypeScript 部分的构建、测试和发布准备。它与 Rust CI (`rust-ci.yml`) 分工协作，共同保证代码质量。

## 功能点目的

1. **Node.js 项目构建**：构建 codex-cli 等 npm 包
2. **代码质量检查**：Prettier 格式化检查、README 校验
3. **NPM 包预发布**：构建并打包 npm 包供后续发布使用
4. **字符编码检查**：确保 README 文件只包含允许的字符

## 具体技术实现

### 触发条件
```yaml
on:
  pull_request: {}
  push: { branches: [main] }
```
- PR 触发：所有 Pull Request
- Push 触发：main 分支推送

### 作业配置
```yaml
jobs:
  build-test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    env:
      NODE_OPTIONS: --max-old-space-size=4096
```
- 超时设置：10 分钟（相对较短，因为主要是 JS 构建）
- Node.js 内存：4GB 堆内存限制

### 环境设置
```yaml
- name: Setup pnpm
  uses: pnpm/action-setup@v4
  with:
    run_install: false

- name: Setup Node.js
  uses: actions/setup-node@v6
  with:
    node-version: 22

- name: Install dependencies
  run: pnpm install --frozen-lockfile
```
- 包管理器：pnpm（通过 `pnpm-workspace.yaml` 配置为 monorepo）
- Node.js 版本：22（固定版本）
- 安装参数：`--frozen-lockfile` 确保 lock 文件不意外变更

### NPM 包预发布
```yaml
- name: Stage npm package
  id: stage_npm_package
  env:
    GH_TOKEN: ${{ github.token }}
  run: |
    set -euo pipefail
    CODEX_VERSION=0.115.0
    OUTPUT_DIR="${RUNNER_TEMP}"
    python3 ./scripts/stage_npm_packages.py \
      --release-version "$CODEX_VERSION" \
      --package codex \
      --output-dir "$OUTPUT_DIR"
    PACK_OUTPUT="${OUTPUT_DIR}/codex-npm-${CODEX_VERSION}.tgz"
    echo "pack_output=$PACK_OUTPUT" >> "$GITHUB_OUTPUT"
```
- 硬编码版本：0.115.0（需要定期更新）
- 脚本：`scripts/stage_npm_packages.py`
- 输出：打包后的 `.tgz` 文件路径

#### stage_npm_packages.py 关键逻辑
```python
def main() -> int:
    # 解析参数
    parser.add_argument("--release-version", required=True)
    parser.add_argument("--package", dest="packages", action="append", required=True)
    parser.add_argument("--output-dir", type=Path, default=None)
    
    # 收集原生组件
    components = collect_native_components(packages)
    
    # 解析发布工作流
    workflow_url, resolved_head_sha = resolve_workflow_url(version, args.workflow_url)
    
    # 安装原生依赖
    install_native_components(workflow_url, components, vendor_root)
    
    # 构建并打包
    for package in packages:
        run_command([BUILD_SCRIPT, "--package", package, ...])
```
- 从 Rust 发布工作流获取原生二进制文件
- 将原生二进制文件打包到 npm 包中

### 产物上传
```yaml
- name: Upload staged npm package artifact
  uses: actions/upload-artifact@v7
  with:
    name: codex-npm-staging
    path: ${{ steps.stage_npm_package.outputs.pack_output }}
```
- 使用 artifacts v7 上传打包结果
- 供后续发布工作流下载使用

### README 字符编码检查
```yaml
- name: Ensure root README.md contains only ASCII and certain Unicode code points
  run: ./scripts/asciicheck.py README.md
```
- 脚本：`scripts/asciicheck.py`
- 目的：确保 README 只包含 ASCII 和特定 Unicode 字符
- 原因：避免某些特殊字符导致显示问题

### README 目录检查
```yaml
- name: Check root README ToC
  run: python3 scripts/readme_toc.py README.md
```
- 脚本：`scripts/readme_toc.py`
- 目的：验证 README 目录结构正确

### 格式化检查
```yaml
- name: Prettier (run `pnpm run format:fix` to fix)
  run: pnpm run format
```
- 使用 Prettier 检查代码格式
- 失败提示：运行 `pnpm run format:fix` 修复

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/ci.yml` | 本工作流定义 |
| `package.json` | 根目录 npm 配置 |
| `pnpm-workspace.yaml` | pnpm monorepo 配置 |
| `scripts/stage_npm_packages.py` | npm 包预发布脚本 |
| `scripts/asciicheck.py` | ASCII 字符检查脚本 |
| `scripts/readme_toc.py` | README 目录检查脚本 |
| `codex-cli/scripts/build_npm_package.py` | npm 包构建脚本 |
| `codex-cli/scripts/install_native_deps.py` | 原生依赖安装脚本 |

### 依赖关系
```
ci.yml
├── pnpm install
│   └── package.json, pnpm-lock.yaml
├── stage_npm_packages.py
│   ├── build_npm_package.py
│   ├── install_native_deps.py
│   └── rust-release workflow (获取原生二进制)
├── asciicheck.py
├── readme_toc.py
└── pnpm run format
    └── .prettierrc.toml
```

## 依赖与外部交互

### 外部服务
1. **GitHub Packages/Actions**：artifact 上传、GitHub CLI
2. **NPM Registry**：潜在的包发布目标

### 依赖的工具
- pnpm (v4)
- Node.js 22
- Python 3
- DotSlash（用于 stage_npm_packages）

### 密钥依赖
- `github.token`：用于 GitHub CLI 调用

## 风险、边界与改进建议

### 风险
1. **硬编码版本号**：`CODEX_VERSION=0.115.0` 需要手动更新
2. **版本不一致**：JS 版本与 Rust 版本可能不同步
3. **超时设置**：10 分钟可能不足以应对依赖安装缓慢的情况
4. **单平台构建**：仅在 Ubuntu 上构建，不验证其他平台

### 边界条件
- 依赖 `pnpm-lock.yaml` 存在且最新
- 需要 `scripts/stage_npm_packages.py` 及其依赖脚本
- Rust 发布工作流需要已运行以提供原生二进制

### 改进建议
1. **动态版本获取**：从 `package.json` 或 Git 标签自动获取版本号
2. **版本同步检查**：添加步骤验证 JS 版本与 Rust 版本一致
3. **多平台构建**：添加 macOS 和 Windows 构建验证
4. **缓存优化**：利用 `actions/setup-node` 的缓存功能
5. **并行化**：README 检查和格式化可以并行执行
6. **发布集成**：与发布工作流更紧密集成，自动触发

### 代码改进示例
```yaml
# 动态获取版本
- name: Get version
  id: version
  run: |
    version=$(jq -r '.version' codex-cli/package.json)
    echo "version=$version" >> "$GITHUB_OUTPUT"

- name: Stage npm package
  run: |
    python3 ./scripts/stage_npm_packages.py \
      --release-version "${{ steps.version.outputs.version }}" \
      ...
```
