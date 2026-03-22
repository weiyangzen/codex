# codex-cli/scripts/README.md 研究文档

## 场景与职责

该 README.md 文件是 `codex-cli/scripts/` 目录的文档入口，专门面向需要构建和发布 Codex CLI npm 包的开发者和发布工程师。文档的核心职责是说明如何使用仓库根目录的 staging helper 脚本 (`scripts/stage_npm_packages.py`) 来生成 npm 发布包，以及如何在需要时直接调用 `build_npm_package.py`。

该文档属于发布流程的**用户指南**，连接了以下关键组件：
- 根目录的发布编排脚本：`scripts/stage_npm_packages.py`
- CLI 目录的包构建脚本：`codex-cli/scripts/build_npm_package.py`
- 原生依赖安装脚本：`codex-cli/scripts/install_native_deps.py`

## 功能点目的

文档涵盖两个主要使用场景：

### 1. 标准发布流程（推荐）
使用根目录的 `stage_npm_packages.py` 脚本一次性为多个包生成 npm tarball：

```bash
./scripts/stage_npm_packages.py \
  --release-version 0.6.0 \
  --package codex \
  --package codex-responses-api-proxy \
  --package codex-sdk
```

**关键特性**：
- 单次下载原生构建产物（native artifacts），避免重复下载
- 为每个包 hydrate `vendor/` 目录（填充原生二进制文件）
- 输出位置：`dist/npm/`
- 当指定 `--package codex` 时，会自动构建：
  - 轻量级的 `@openai/codex` 元包（meta package）
  - 所有平台特定的原生变体包（platform-native variants），后续通过平台特定的 dist-tags 发布

### 2. 直接调用 build_npm_package.py（高级/调试场景）
当需要绕过标准发布流程时，可以直接调用底层构建脚本。前置条件：
- 必须先运行 `codex-cli/scripts/install_native_deps.py` 安装原生依赖
- 必须提供 `--vendor-src` 参数指向已填充的 `vendor/` 目录

## 具体技术实现

### 包类型与架构

| 包名 | 类型 | 说明 |
|------|------|------|
| `@openai/codex` | 元包 | 轻量级入口，通过 `optionalDependencies` 引用平台特定包 |
| `@openai/codex-linux-x64` | 平台包 | Linux x86_64 原生二进制 |
| `@openai/codex-linux-arm64` | 平台包 | Linux ARM64 原生二进制 |
| `@openai/codex-darwin-x64` | 平台包 | macOS x86_64 原生二进制 |
| `@openai/codex-darwin-arm64` | 平台包 | macOS ARM64 原生二进制 |
| `@openai/codex-win32-x64` | 平台包 | Windows x86_64 原生二进制 |
| `@openai/codex-win32-arm64` | 平台包 | Windows ARM64 原生二进制 |
| `codex-responses-api-proxy` | 独立包 | Responses API 代理服务 |
| `codex-sdk` | 独立包 | TypeScript SDK |

### 平台检测与分发机制

元包 (`@openai/codex`) 本身不包含原生二进制，而是通过 npm 的 `optionalDependencies` 机制声明所有平台包。安装时：
1. npm 尝试安装所有 optional dependencies
2. 只有匹配当前平台的包会成功安装
3. 运行时 Node.js 启动器脚本 (`bin/codex.js`) 检测平台并加载对应二进制

### 版本命名约定

平台特定包使用复合版本号：`<version>-<platform_tag>`
- 例如：`0.6.0-linux-x64`
- 原因：npm 禁止重复发布同名同版本的包

## 关键代码路径与文件引用

### 上游调用方
- `scripts/stage_npm_packages.py` (行17): 导入并调用 `BUILD_SCRIPT`
- CI/CD 工作流（如 `.github/workflows/rust-release.yml`）

### 下游依赖脚本
- `codex-cli/scripts/build_npm_package.py`: 实际执行包构建和打包
- `codex-cli/scripts/install_native_deps.py`: 预填充 `vendor/` 目录

### 关键数据结构（来自 build_npm_package.py）

```python
# 平台包配置映射
CODEX_PLATFORM_PACKAGES: dict[str, dict[str, str]] = {
    "codex-linux-x64": {
        "npm_name": "@openai/codex-linux-x64",
        "npm_tag": "linux-x64",
        "target_triple": "x86_64-unknown-linux-musl",
        "os": "linux",
        "cpu": "x64",
    },
    # ... 其他平台
}

# 包扩展定义（元包展开为多个平台包）
PACKAGE_EXPANSIONS: dict[str, list[str]] = {
    "codex": ["codex", *CODEX_PLATFORM_PACKAGES],
}
```

### 入口点脚本
- `codex-cli/bin/codex.js`: Node.js 启动器，负责平台检测和二进制加载

## 依赖与外部交互

### 外部工具依赖
| 工具 | 用途 |
|------|------|
| `gh` (GitHub CLI) | 下载 workflow artifacts |
| `npm` | 打包 (`npm pack`) |
| `pnpm` | SDK 构建时的包管理 |
| `zstd` | 解压 `.zst` 压缩的原生二进制 |
| `dotslash` | 解析 DotSlash 格式的 ripgrep manifest |

### 网络依赖
- GitHub Actions artifacts 下载
- npm registry 发布（间接）
- GitHub releases（ripgrep 二进制下载）

### 文件系统约定
```
vendor/
├── <target_triple>/
│   ├── codex/           # Codex 原生二进制
│   ├── path/            # ripgrep 二进制
│   └── ...
```

## 风险、边界与改进建议

### 已知风险

1. **版本号冲突风险**
   - 平台包使用 `<version>-<tag>` 格式，如果同一版本需要重新发布，必须递增版本号
   - 建议：建立严格的版本发布流程，避免重复构建

2. **原生二进制缺失**
   - 如果 `install_native_deps.py` 未运行或失败，`build_npm_package.py` 会因缺少 `--vendor-src` 而失败
   - 缓解：文档已明确说明依赖关系

3. **平台支持碎片化**
   - 新增平台需要同时修改：
     - `build_npm_package.py` 中的 `CODEX_PLATFORM_PACKAGES`
     - `bin/codex.js` 中的 `PLATFORM_PACKAGE_BY_TARGET`
   - 风险：配置不同步导致运行时错误

### 边界条件

- **最小 Node.js 版本**: 16+（来自 `package.json` 的 `engines` 字段）
- **支持的平台**: 6 个目标三元组（见上表）
- **架构限制**: Windows 平台额外包含 `codex-windows-sandbox-setup` 和 `codex-command-runner` 组件

### 改进建议

1. **文档增强**
   - 添加故障排除章节（如 "vendor directory not found" 错误处理）
   - 提供完整的端到端示例（从源码到发布）

2. **验证机制**
   - 在 staging 后自动运行 `node bin/codex.js --version` 验证包完整性
   - 添加平台包完整性检查（校验和验证）

3. **配置统一**
   - 考虑将平台定义提取到独立的 JSON/YAML 文件，供 Python 和 Node.js 共享
   - 减少 `build_npm_package.py` 和 `bin/codex.js` 之间重复的平台映射

4. **CI 集成优化**
   - 文档可提及 `RUNNER_TEMP` 环境变量的使用（用于 GitHub Actions 中的临时目录）
   - 说明 `--keep-staging-dirs` 调试选项的使用场景
