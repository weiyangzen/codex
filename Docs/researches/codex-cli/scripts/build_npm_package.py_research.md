# codex-cli/scripts/build_npm_package.py 研究文档

## 场景与职责

`build_npm_package.py` 是 Codex CLI npm 包构建的核心引擎，负责将源码、原生二进制和元数据组装为可发布的 npm 包。该脚本服务于以下场景：

1. **多平台包构建**: 构建 6 个平台特定的原生包 + 1 个元包
2. **发布准备**: 生成版本化的 package.json 和目录结构
3. **CI/CD 集成**: 作为自动化发布流水线的构建步骤
4. **本地开发**: 开发者构建测试包

脚本的核心职责：
- 管理多平台包矩阵（Linux/macOS/Windows × x64/arm64）
- 协调原生二进制（Rust 构建产物）与 JavaScript 启动器的集成
- 生成符合 npm 规范的包结构
- 执行 `npm pack` 生成发布 tarball

## 功能点目的

### 包类型体系

脚本管理 4 类 npm 包：

| 类型 | 示例 | 说明 |
|------|------|------|
| 元包 (Meta) | `@openai/codex` | 轻量级入口，通过 optionalDependencies 引用平台包 |
| 平台包 (Platform) | `@openai/codex-linux-x64` | 包含特定平台的原生二进制 |
| 代理包 (Proxy) | `codex-responses-api-proxy` | Responses API 代理服务 |
| SDK 包 | `codex-sdk` | TypeScript SDK |

### 关键功能模块

1. **平台包配置管理** (`CODEX_PLATFORM_PACKAGES`)
2. **原生组件映射** (`PACKAGE_NATIVE_COMPONENTS`)
3. **源码 staging** (`stage_sources`)
4. **原生二进制复制** (`copy_native_binaries`)
5. **npm 打包** (`run_npm_pack`)

## 具体技术实现

### 数据结构详解

#### 1. 平台包配置 (行 21-64)

```python
CODEX_PLATFORM_PACKAGES: dict[str, dict[str, str]] = {
    "codex-linux-x64": {
        "npm_name": "@openai/codex-linux-x64",    # npm 包名
        "npm_tag": "linux-x64",                   # dist-tag 标识
        "target_triple": "x86_64-unknown-linux-musl",  # Rust 目标
        "os": "linux",                            # package.json os 字段
        "cpu": "x64",                             # package.json cpu 字段
    },
    # ... 共 6 个平台
}
```

**设计要点**：
- `target_triple` 对应 Rust 编译目标，与 GitHub Actions artifact 命名一致
- `npm_tag` 用于生成复合版本号（如 `0.6.0-linux-x64`）
- `os`/`cpu` 字段限制 npm 只在匹配平台安装该包

#### 2. 原生组件映射 (行 70-80)

```python
PACKAGE_NATIVE_COMPONENTS: dict[str, list[str]] = {
    "codex": [],  # 元包无原生组件
    "codex-linux-x64": ["codex", "rg"],  # Linux/macOS 平台
    "codex-win32-x64": ["codex", "rg", "codex-windows-sandbox-setup", "codex-command-runner"],
    "codex-responses-api-proxy": ["codex-responses-api-proxy"],
    "codex-sdk": [],  # SDK 为纯 TypeScript
}
```

**Windows 特殊处理**：
- Windows 平台额外包含沙箱设置和命令运行器组件
- 这些组件仅存在于 Windows 目标

#### 3. 组件目标目录映射 (行 89-95)

```python
COMPONENT_DEST_DIR: dict[str, str] = {
    "codex": "codex",
    "codex-responses-api-proxy": "codex-responses-api-proxy",
    "codex-windows-sandbox-setup": "codex",
    "codex-command-runner": "codex",
    "rg": "path",  # ripgrep 放入 path/ 子目录，用于 PATH 扩展
}
```

### 核心流程

#### 主函数流程 (行 143-221)

```
parse_args() → prepare_staging_dir() → stage_sources() → [copy_native_binaries()] → [run_npm_pack()]
```

**条件逻辑**：
- 仅当包包含原生组件时才执行 `copy_native_binaries`
- 仅当提供 `--pack-output` 时才执行 `run_npm_pack`

#### 源码 Staging (行 236-328)

根据包类型执行不同的 staging 逻辑：

**元包 (`codex`)**：
- 复制 `bin/codex.js` 启动器
- 复制 `bin/rg` DotSlash manifest（如存在）
- 复制根目录 README.md
- 修改 package.json：
  - 设置 `files: ["bin"]`
  - 生成 `optionalDependencies` 映射所有平台包

**平台包** (`codex-<platform>`)：
- 动态生成 package.json（非从文件读取）
- 设置 `name: @openai/codex`
- 设置 `files: ["vendor"]`
- 版本号格式：`{version}-{platform_tag}`

**代理包** (`codex-responses-api-proxy`)：
- 从 `codex-rs/responses-api-proxy/npm/` 复制启动器

**SDK 包** (`codex-sdk`)：
- 执行 `pnpm install` 和 `pnpm run build`
- 复制 `dist/` 目录
- 添加 `@openai/codex` 作为依赖

#### 原生二进制复制 (行 363-415)

```python
def copy_native_binaries(
    vendor_src: Path,      # 源 vendor 目录（来自 install_native_deps.py）
    staging_dir: Path,     # 目标 staging 目录
    components: list[str], # 要复制的组件列表
    target_filter: set[str] | None,  # 目标平台过滤
) -> None:
```

**目录结构转换**：
```
vendor_src/                    staging_dir/vendor/
├── x86_64-unknown-linux-musl/  →  ├── x86_64-unknown-linux-musl/
│   ├── codex/                 │   ├── codex/          (来自 COMPONENT_DEST_DIR)
│   └── path/                  │   └── path/           (rg 组件)
└── ...                        └── ...
```

**验证机制**：
- 检查源目录存在性
- 验证所有目标平台都有对应目录
- 验证每个组件的源目录存在

#### npm 打包 (行 418-447)

使用 `npm pack --json` 获取结构化输出：

```python
stdout = subprocess.check_output(
    ["npm", "pack", "--json", "--pack-destination", str(pack_dir)],
    cwd=staging_dir,
    text=True,
)
pack_output = json.loads(stdout)
tarball_name = pack_output[0].get("filename")
```

**优势**：
- `--json` 输出提供准确的文件名（包含版本号）
- 避免手动构造文件名导致的错误

### 版本号计算 (行 331-334)

```python
def compute_platform_package_version(version: str, platform_tag: str) -> str:
    return f"{version}-{platform_tag}"
```

**示例**：
- 输入：`version="0.6.0"`, `platform_tag="linux-x64"`
- 输出：`"0.6.0-linux-x64"`

## 关键代码路径与文件引用

### 上游调用方

1. **根目录 staging 脚本** (`scripts/stage_npm_packages.py` 行 173-189)
   ```python
   cmd = [
       str(BUILD_SCRIPT),
       "--package", package,
       "--release-version", args.release_version,
       "--staging-dir", str(staging_dir),
       "--pack-output", str(pack_output),
       "--vendor-src", str(vendor_src),
   ]
   ```

2. **手动调用**（开发/调试场景）

### 下游依赖

1. **install_native_deps.py**: 预填充 `vendor/` 目录
2. **bin/codex.js**: 被复制到元包的 `bin/` 目录
3. **package.json**: 读取元数据（license, engines, repository）

### 跨文件数据共享

`stage_npm_packages.py` 通过 Python 模块导入共享数据：

```python
_SPEC = importlib.util.spec_from_file_location("codex_build_npm_package", BUILD_SCRIPT)
_BUILD_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_BUILD_MODULE)
PACKAGE_NATIVE_COMPONENTS = getattr(_BUILD_MODULE, "PACKAGE_NATIVE_COMPONENTS", {})
```

## 依赖与外部交互

### 外部工具依赖

| 工具 | 用途 |
|------|------|
| `npm` | 打包 (`npm pack`) |
| `pnpm` | SDK 构建 |
| `zstd` | 解压 `.zst` 文件（在 install_native_deps.py 中） |
| `gh` | 下载 artifacts（在 install_native_deps.py 中） |

### 文件系统约定

**输入目录**：
- `codex-cli/bin/`: Node.js 启动器和 DotSlash manifest
- `codex-rs/responses-api-proxy/npm/`: 代理包源码
- `sdk/typescript/`: SDK 源码
- `vendor/`: 原生二进制（由 `--vendor-src` 指定）

**输出结构**：
```
<staging_dir>/
├── package.json          # 生成的或修改的
├── bin/                  # 元包/代理包
│   └── codex.js
├── vendor/               # 平台包
│   └── <target>/
│       ├── codex/
│       └── path/
└── README.md
```

### 网络依赖

- npm registry（打包时验证）
- GitHub releases（ripgrep 下载，间接通过 install_native_deps.py）

## 风险、边界与改进建议

### 已知风险

1. **版本号格式依赖**
   - 平台包版本号使用 `-` 分隔符，如果基础版本包含 prerelease 标识（如 `0.6.0-alpha.1`），可能导致解析歧义
   - **示例**: `0.6.0-alpha.1-linux-x64` 语义不明确

2. **并发 staging 冲突**
   - 如果多个进程同时 staging 到同一目录，`any(staging_dir.iterdir())` 检查可能存在竞态条件

3. **SDK 构建失败传播**
   - SDK staging 执行 `pnpm run build`，如果构建失败，错误信息可能不够清晰

4. **平台包名硬编码**
   - `CODEX_NPM_NAME = "@openai/codex"` 是硬编码常量
   - 如果组织或包名变更，需要修改源码

### 边界条件

| 场景 | 行为 |
|------|------|
| `--version` 和 `--release-version` 同时提供但不同 | 抛出 `RuntimeError` |
| 未提供版本参数 | 抛出 `RuntimeError` |
| staging 目录非空 | 抛出 `RuntimeError` |
| 需要原生组件但缺少 `--vendor-src` | 抛出 `RuntimeError` |
| vendor 源缺少目标平台目录 | 抛出 `RuntimeError` |
| vendor 源缺少组件目录 | 抛出 `RuntimeError` |
| `npm pack` 输出解析失败 | 抛出 `RuntimeError` |

### 改进建议

1. **版本号语义增强**
   ```python
   # 使用 + 构建元数据而非 - 预发布标识
   def compute_platform_package_version(version: str, platform_tag: str) -> str:
       return f"{version}+{platform_tag}"  # 0.6.0+linux-x64
   ```

2. **并行构建支持**
   - 当前 `stage_npm_packages.py` 串行调用本脚本
   - 可考虑添加 `--skip-pack` 选项，仅 staging 不打包，由上游统一并行处理

3. **校验和验证**
   - 复制原生二进制时验证 SHA256 校验和
   - 防止 artifacts 损坏或篡改

4. **干运行模式**
   ```python
   parser.add_argument("--dry-run", action="store_true", help="Staging only, no pack")
   ```

5. **元数据丰富**
   - 在生成的 package.json 中添加构建信息（如构建时间、源码 commit SHA）

6. **错误上下文增强**
   ```python
   raise RuntimeError(
       f"Missing native component '{component}' in vendor source: {src_component_dir}\n"
       f"Available components: {list_available_components(vendor_src)}"
   )
   ```

7. **类型安全增强**
   - 使用 `TypedDict` 定义平台包配置结构
   - 添加运行时验证（如 `npm_tag` 格式检查）

### 与架构决策的关系

本脚本的设计反映了以下架构决策：

1. **平台包分离**: 避免单个包体积过大，利用 npm 的 optionalDependencies 机制
2. **版本号隔离**: 每个平台独立版本，支持独立发布和回滚
3. **Rust + Node.js 混合**: JavaScript 启动器 + 原生二进制，兼顾跨平台和性能
4. **DotSlash 工具管理**: ripgrep 通过 DotSlash manifest 管理，简化多平台分发
