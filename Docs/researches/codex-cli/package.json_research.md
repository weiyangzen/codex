# codex-cli/package.json 研究文档

## 场景与职责

`codex-cli/package.json` 是 OpenAI Codex CLI npm 包的清单文件。它定义了包的元数据、入口点、发布内容和依赖关系。该文件是 npm 发布流程的核心，也是 `bin/codex.js` 入口脚本的配置来源。

根据仓库根目录 `AGENTS.md` 的说明，该项目已迁移到 Rust 实现，但 `codex-cli` 仍作为 **npm 元包（meta-package）** 存在，用于分发原生 Rust 二进制文件。

## 功能点目的

### 1. 包标识与元数据
```json
{
  "name": "@openai/codex",
  "version": "0.0.0-dev",
  "license": "Apache-2.0"
}
```

- **作用域包名**：`@openai/codex` 使用 npm 作用域，属于 OpenAI 组织
- **版本占位符**：`0.0.0-dev` 表示开发版本，实际发布时由 `build_npm_package.py` 替换
- **许可证**：Apache-2.0，与仓库根目录一致

### 2. 入口点定义
```json
{
  "bin": {
    "codex": "bin/codex.js"
  }
}
```

- **全局命令**：安装后用户可使用 `codex` 命令
- **入口脚本**：`bin/codex.js` 是一个 Node.js wrapper，负责：
  1. 检测当前平台架构
  2. 解析对应的原生二进制包
  3. 启动 Rust CLI 二进制文件

### 3. 模块类型
```json
{
  "type": "module"
}
```

- **ESM 模块**：使用 ES Modules 而非 CommonJS
- 影响 `bin/codex.js` 的语法（使用 `import` 而非 `require`）

### 4. 引擎要求
```json
{
  "engines": {
    "node": ">=16"
  }
}
```

- **最低 Node.js 版本**：16，与 README.md 中系统要求一致
- **兼容性**：支持 Node 16、18、20+，但推荐 20 LTS

### 5. 发布内容控制
```json
{
  "files": [
    "bin",
    "vendor"
  ]
}
```

- **白名单模式**：仅包含 `bin/` 和 `vendor/` 目录
- **排除内容**：源代码、测试、文档等不进入 npm 包
- **vendor 目录**：包含各平台的原生 Rust 二进制文件

### 6. 仓库信息
```json
{
  "repository": {
    "type": "git",
    "url": "git+https://github.com/openai/codex.git",
    "directory": "codex-cli"
  }
}
```

- **monorepo 支持**：`directory` 字段指明子目录位置
- **npm 链接**：在 npm 页面显示仓库链接

### 7. 包管理器锁定
```json
{
  "packageManager": "pnpm@10.29.3+sha512.498e1fb4cca5aa06c1dcf2611e6fafc50972ffe7189998c409e90de74566444298ffe43e6cd2acdc775ba1aa7cc5e092a8b7054c811ba8c5770f84693d33d2dc"
}
```

- **Corepack 支持**：指定使用 pnpm 10.29.3
- **完整性校验**：包含 SHA512 哈希，防止包管理器被篡改

## 具体技术实现

### 构建时版本注入

在 `scripts/build_npm_package.py` 中：

```python
def stage_sources(staging_dir: Path, version: str, package: str) -> None:
    # ...
    if package_json_path is not None:
        with open(package_json_path, "r", encoding="utf-8") as fh:
            package_json = json.load(fh)
        package_json["version"] = version  # 替换版本号
    
    if package == "codex":
        package_json["files"] = ["bin"]  # 主包只包含 bin
        package_json["optionalDependencies"] = {
            # 添加平台特定包作为可选依赖
            CODEX_PLATFORM_PACKAGES[platform_package]["npm_name"]: (
                f"npm:{CODEX_NPM_NAME}@"
                f"{compute_platform_package_version(version, CODEX_PLATFORM_PACKAGES[platform_package]['npm_tag'])}"
            )
            for platform_package in PACKAGE_EXPANSIONS["codex"]
            if platform_package != "codex"
        }
```

### 平台包架构

根据 `build_npm_package.py` 中的 `CODEX_PLATFORM_PACKAGES`：

| 包名 | 目标三元组 | 平台 | 架构 |
|------|------------|------|------|
| `@openai/codex-linux-x64` | `x86_64-unknown-linux-musl` | Linux | x64 |
| `@openai/codex-linux-arm64` | `aarch64-unknown-linux-musl` | Linux | arm64 |
| `@openai/codex-darwin-x64` | `x86_64-apple-darwin` | macOS | x64 |
| `@openai/codex-darwin-arm64` | `aarch64-apple-darwin` | macOS | arm64 |
| `@openai/codex-win32-x64` | `x86_64-pc-windows-msvc` | Windows | x64 |
| `@openai/codex-win32-arm64` | `aarch64-pc-windows-msvc` | Windows | arm64 |

### 入口脚本逻辑

`bin/codex.js` 的关键逻辑：

```javascript
const PLATFORM_PACKAGE_BY_TARGET = {
  "x86_64-unknown-linux-musl": "@openai/codex-linux-x64",
  "aarch64-unknown-linux-musl": "@openai/codex-linux-arm64",
  // ... 其他平台
};

// 1. 检测平台架构
const { platform, arch } = process;
let targetTriple = null;
// ... 平台检测逻辑

// 2. 查找原生二进制
const platformPackage = PLATFORM_PACKAGE_BY_TARGET[targetTriple];
const binaryPath = path.join(vendorRoot, targetTriple, "codex", codexBinaryName);

// 3. 启动子进程
const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: "inherit",
  env,
});
```

## 关键代码路径与文件引用

### 直接关联文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `bin/codex.js` | 入口点 | 读取 package.json 解析平台包 |
| `scripts/build_npm_package.py` | 构建脚本 | 修改 version、添加 optionalDependencies |
| `scripts/install_native_deps.py` | 安装脚本 | 下载二进制到 vendor/ |
| `bin/rg` | 辅助文件 | DotSlash 清单，用于下载 ripgrep |

### 依赖关系图

```
package.json
    ├── bin/codex.js (入口)
    │       └── 检测平台 → 查找 vendor/ → 启动 Rust 二进制
    ├── files: ["bin", "vendor"]
    │       ├── bin/
    │       │   ├── codex.js
    │       │   └── rg
    │       └── vendor/ (由 install_native_deps.py 填充)
    │           └── <target-triple>/
    │               ├── codex/
    │               └── path/rg
    └── optionalDependencies (由 build_npm_package.py 添加)
            ├── @openai/codex-linux-x64
            ├── @openai/codex-darwin-arm64
            └── ...
```

### 构建流程中的角色

```
1. 开发阶段
   package.json (version: 0.0.0-dev)
   └── 本地开发和测试

2. 发布准备 (build_npm_package.py)
   package.json
   ├── version: 替换为实际版本 (如 0.6.0)
   ├── files: ["bin"] (主包)
   └── optionalDependencies: 添加平台包引用

3. 平台包构建
   每个平台生成独立的 package.json
   ├── name: @openai/codex-<platform>
   ├── version: 0.6.0-<platform-tag>
   ├── os: [特定平台]
   ├── cpu: [特定架构]
   └── files: ["vendor"]

4. npm 发布
   ├── @openai/codex@0.6.0 (主包)
   ├── @openai/codex-linux-x64@0.6.0-linux-x64
   ├── @openai/codex-darwin-arm64@0.6.0-darwin-arm64
   └── ...
```

## 依赖与外部交互

### 运行时依赖

| 依赖 | 来源 | 说明 |
|------|------|------|
| Node.js >=16 | 系统 | JavaScript 运行时 |
| 平台特定包 | npm | `@openai/codex-<platform>` 作为 optionalDependencies |
| Rust 二进制 | vendor/ | 实际的 CLI 实现 |
| ripgrep | vendor/path/ | 代码搜索工具 |

### 可选依赖解析

当用户运行 `npm install -g @openai/codex`：

1. npm 安装主包 `@openai/codex`
2. npm 尝试安装所有 `optionalDependencies`
3. 只有匹配当前平台 `os` 和 `cpu` 的包会成功安装
4. `bin/codex.js` 在运行时查找已安装的平台包

### 与 Rust 代码的关系

```
Rust CLI (codex-rs/)
    ├── 编译为各平台二进制
    │       └── GitHub Actions Artifacts
    ├── install_native_deps.py 下载
    │       └── vendor/
    ├── build_npm_package.py 打包
    │       └── npm 包
    └── 最终通过 package.json 分发给用户
```

## 风险、边界与改进建议

### 当前风险

1. **版本占位符风险**
   - `version: "0.0.0-dev"` 是占位符，直接发布会出错
   - 依赖 `build_npm_package.py` 正确替换版本
   - 如果脚本失败，可能发布错误版本

2. **可选依赖解析失败**
   - 如果所有平台包都安装失败，用户仍可使用 `codex` 命令
   - 但 `bin/codex.js` 会抛出错误提示重新安装
   - 用户体验不佳

3. **平台检测局限**
   - `bin/codex.js` 中的平台检测可能遗漏某些架构
   - 例如：FreeBSD、ARMv7 等不支持

4. **vendor 目录缺失**
   - `files` 包含 `vendor`，但开发时 `vendor/` 为空（被 .gitignore 排除）
   - 新开发者可能困惑为什么安装后无法运行

### 边界情况

1. **Node.js 版本边界**
   - `>=16` 包含 Node 16、17、18、19、20...
   - 但某些功能可能需要更高版本
   - 未测试的 Node 版本可能存在兼容性问题

2. **包管理器差异**
   - `packageManager` 锁定 pnpm，但用户可能使用 npm/yarn
   - 不同包管理器对 `optionalDependencies` 处理可能不同

3. **平台包版本格式**
   - 平台包版本格式：`{version}-{platform-tag}`（如 `0.6.0-linux-x64`）
   - 这种格式不是标准 semver，某些工具可能无法正确解析

### 改进建议

#### 1. 添加预发布检查
```json
{
  "scripts": {
    "prepublishOnly": "node scripts/check-version.js"
  }
}
```

`check-version.js`：
```javascript
if (require('./package.json').version === '0.0.0-dev') {
  console.error('Error: Cannot publish with placeholder version');
  process.exit(1);
}
```

#### 2. 改进引擎要求
```json
{
  "engines": {
    "node": ">=16 <=22"
  }
}
```

限制最高版本，避免未测试的 Node 版本导致问题。

#### 3. 添加更多元数据
```json
{
  "description": "OpenAI Codex CLI - AI coding agent for your terminal",
  "keywords": ["openai", "codex", "cli", "ai", "coding"],
  "author": "OpenAI",
  "bugs": {
    "url": "https://github.com/openai/codex/issues"
  },
  "homepage": "https://github.com/openai/codex#readme"
}
```

#### 4. 平台支持扩展
```json
{
  "bin": {
    "codex": "bin/codex.js"
  },
  "exports": {
    ".": {
      "types": "./types/index.d.ts",
      "default": "./bin/codex.js"
    }
  }
}
```

#### 5. 开发体验改进
添加 `scripts` 部分：
```json
{
  "scripts": {
    "postinstall": "node scripts/welcome.js",
    "test": "echo 'Tests run in codex-rs/'"
  }
}
```

`welcome.js` 可以提示开发者运行 `install_native_deps.py`。

#### 6. 版本管理优化
考虑使用 `semantic-release` 或 `changesets` 自动化版本管理：

```json
{
  "scripts": {
    "version": "changeset version",
    "release": "changeset publish"
  }
}
```

### 与新版 CLI 的协调

建议添加 `deprecated` 字段（当 Rust CLI 完全替代后）：

```json
{
  "deprecated": "This package has been replaced by @openai/codex-rs. Please run: npm uninstall -g @openai/codex && npm install -g @openai/codex-rs"
}
```

### 安全性建议

1. **添加 integrity 字段**：对 `vendor/` 中的二进制文件进行校验
2. **签名发布**：使用 npm 的签名功能验证包完整性
3. **SLSA 合规**：生成和发布 SLSA  provenance 数据
