# scripts/ 目录深度研究文档

## 概述

`scripts/` 目录包含 Codex 项目的辅助脚本集合，涵盖 CI/CD 检查、发布流程、安装脚本和开发调试工具。这些脚本主要由 Python 和 Shell 编写，用于支撑项目的自动化流程。

---

## 一、场景与职责

### 1.1 核心职责矩阵

| 脚本 | 主要职责 | 执行场景 |
|------|---------|---------|
| `asciicheck.py` | 非 ASCII 字符检测与修复 | CI 检查、文档规范 |
| `check-module-bazel-lock.sh` | Bazel 锁文件一致性校验 | CI (Bazel 工作流) |
| `check_blob_size.py` | Git Blob 大小策略检查 | CI (PR 检查) |
| `debug-codex.sh` | 本地开发调试入口 | 本地开发 |
| `mock_responses_websocket_server.py` | Mock Responses API WebSocket 服务器 | 本地测试、开发 |
| `readme_toc.py` | README 目录自动生成与校验 | CI 检查 |
| `stage_npm_packages.py` | NPM 包发布 staging | CI 发布流程 |
| `install/install.sh` | Unix 系统安装脚本 | 用户安装 |
| `install/install.ps1` | Windows PowerShell 安装脚本 | 用户安装 |

### 1.2 执行环境分类

```
scripts/
├── CI/CD 专用 (7个)
│   ├── asciicheck.py
│   ├── check-module-bazel-lock.sh
│   ├── check_blob_size.py
│   ├── readme_toc.py
│   └── stage_npm_packages.py
├── 本地开发 (2个)
│   ├── debug-codex.sh
│   └── mock_responses_websocket_server.py
└── 用户安装 (2个)
    ├── install/install.sh
    └── install/install.ps1
```

---

## 二、功能点目的

### 2.1 代码质量与规范检查

#### 2.1.1 asciicheck.py - ASCII 字符规范检查

**目的**: 防止非 ASCII 字符（如非断空格 U+00A0、智能引号等）进入代码库，这些字符可能导致正则匹配失败或 GitHub Markdown 渲染问题。

**核心功能**:
- 检测文件中的非 ASCII 字符（除允许的 Unicode 码点外）
- 支持 `--fix` 模式自动替换常见非 ASCII 字符为 ASCII 等价物
- 允许的 Unicode 码点: `0x2728` (✨ sparkles)

**自动替换映射**:
```python
substitutions = {
    0x00A0: " ",   # non-breaking space
    0x2011: "-",   # non-breaking hyphen
    0x2013: "-",   # en dash
    0x2014: "-",   # em dash
    0x2018: "'",   # left single quote
    0x2019: "'",   # right single quote
    0x201C: '"',   # left double quote
    0x201D: '"',   # right double quote
    0x2026: "...", # ellipsis
    0x202F: " ",   # narrow non-breaking space
}
```

#### 2.1.2 readme_toc.py - 目录自动生成

**目的**: 维护 README.md 文件的目录(ToC)与正文标题同步。

**工作机制**:
- 识别 `<!-- Begin ToC -->` 和 `<!-- End ToC -->` 标记之间的目录区域
- 解析 `##` 到 `######` 级别的标题生成目录
- 支持代码块内标题跳过（避免将代码示例中的 `#` 识别为标题）
- 生成 GitHub 兼容的锚点链接（小写、空格转连字符、去除标点）

**锚点生成规则**:
```python
slug = text.lower()
slug = slug.replace("\u00a0", " ")
slug = slug.replace("\u2011", "-").replace("\u2013", "-").replace("\u2014", "-")
slug = re.sub(r"[^0-9a-z\s-]", "", slug)
slug = slug.strip().replace(" ", "-")
```

### 2.2 构建系统支持

#### 2.2.1 check-module-bazel-lock.sh - Bazel 锁文件校验

**目的**: 确保 `MODULE.bazel.lock` 文件与 `MODULE.bazel` 同步，防止依赖漂移。

**实现**:
```bash
bazel mod deps --lockfile_mode=error
```

**失败处理**: 提示运行 `just bazel-lock-update` 更新锁文件。

### 2.3 发布与部署

#### 2.3.1 stage_npm_packages.py - NPM 包发布 staging

**目的**: 协调多平台 NPM 包的构建、native 组件下载和打包流程。

**核心流程**:
```
1. 解析包列表（支持包别名展开，如 codex -> codex + 6个平台包）
2. 收集 native 组件依赖
3. 通过 GitHub CLI 获取 rust-release 工作流产物
4. 调用 install_native_deps.py 下载 native 二进制
5. 调用 build_npm_package.py 构建各平台包
6. 生成 npm tarball 到输出目录
```

**包类型映射**:
| 包名 | 类型 | Native 组件 |
|------|------|------------|
| `codex` | 主包 | 依赖平台包作为 optionalDependencies |
| `codex-linux-x64` | 平台特定 | codex, rg |
| `codex-linux-arm64` | 平台特定 | codex, rg |
| `codex-darwin-x64` | 平台特定 | codex, rg |
| `codex-darwin-arm64` | 平台特定 | codex, rg |
| `codex-win32-x64` | 平台特定 | codex, rg, codex-windows-sandbox-setup, codex-command-runner |
| `codex-win32-arm64` | 平台特定 | codex, rg, codex-windows-sandbox-setup, codex-command-runner |
| `codex-responses-api-proxy` | 独立工具 | codex-responses-api-proxy |
| `codex-sdk` | SDK | 无 |

**依赖脚本**:
- `codex-cli/scripts/build_npm_package.py` - 实际构建逻辑
- `codex-cli/scripts/install_native_deps.py` - native 组件下载

### 2.4 存储策略检查

#### 2.4.1 check_blob_size.py - Git Blob 大小策略

**目的**: 防止大文件意外提交到 Git 仓库，控制仓库体积增长。

**检查逻辑**:
```python
# 默认限制: 500 KiB (512,000 bytes)
DEFAULT_MAX_BYTES = 500 * 1024

# 检查范围: PR 的 base..head 之间新增/修改的文件
# 使用 git diff --diff-filter=AM --no-renames 获取变更文件
# 通过 git cat-file -s 获取 blob 大小
```

**豁免机制**: 通过 `.github/blob-size-allowlist.txt` 配置允许的大文件路径列表。

**当前豁免列表**:
- `.github/codex-cli-splash.png`
- `MODULE.bazel.lock`
- `codex-rs/app-server-protocol/schema/json/*.json`
- `codex-rs/tui/tests/fixtures/oss-story.jsonl`
- `codex-rs/tui_app_server/tests/fixtures/oss-story.jsonl`

**输出**: 生成 GitHub Actions Step Summary，包含文件大小表格和违规项标记。

### 2.5 开发调试工具

#### 2.5.1 debug-codex.sh - 本地调试入口

**目的**: 为 VS Code 等 IDE 提供始终使用最新源码构建的调试入口。

**使用方式**:
```json
// VSCode settings.json
{
  "chatgpt.cliExecutable": "/Users/<USERNAME>/code/codex/scripts/debug-codex.sh"
}
```

**实现**: 进入 `codex-rs` 目录执行 `cargo run --quiet --bin codex`。

#### 2.5.2 mock_responses_websocket_server.py - Mock WebSocket 服务器

**目的**: 本地模拟 OpenAI Responses API WebSocket 端点，用于测试 codex-rs 的 WebSocket 客户端逻辑。

**协议实现**:
- 监听路径: `/v1/responses`
- 默认端口: `8765`（可通过 `--port` 指定）

**模拟对话流程**:
```
Request 1 (用户输入):
  -> 接收: 用户消息
  <- 发送: response.created 事件
  <- 发送: function_call 事件 (shell_command)
  <- 发送: response.done 事件

Request 2 (工具输出):
  -> 接收: 工具执行结果
  <- 发送: response.created 事件
  <- 发送: assistant message ("done")
  <- 发送: response.completed 事件
```

**事件类型**:
| 事件 | 类型 | 用途 |
|------|------|------|
| `response.created` | status | 响应创建 |
| `response.output_item.done` | output | 输出项完成（包含 function_call 或 message）|
| `response.done` | status | 响应完成 |
| `response.completed` | status | 整个请求完成 |

**配置模板输出**: 启动时打印 config.toml 配置片段，方便开发者直接复制使用。

### 2.6 用户安装脚本

#### 2.6.1 install/install.sh - Unix 安装脚本

**支持平台**:
- macOS (Apple Silicon / Intel)
- Linux (x64 / ARM64)

**版本解析逻辑**:
```bash
"" | latest -> "latest"
"rust-v*" -> "*" (去掉前缀)
"v*" -> "*" (去掉前缀)
* -> 原样保留
```

**安装流程**:
1. 检测平台架构（处理 Rosetta 转译情况）
2. 解析版本号（支持 latest 自动获取）
3. 下载对应平台的 npm tarball
4. 解压并复制二进制到 `~/.local/bin`（或 `CODEX_INSTALL_DIR`）
5. 自动添加 PATH 配置到 shell profile

**安装产物**:
- `codex` - 主二进制
- `rg` - ripgrep 搜索工具

#### 2.6.2 install/install.ps1 - Windows 安装脚本

**支持平台**:
- Windows (x64 / ARM64)

**安装路径**: `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`

**安装产物**:
- `codex.exe`
- `codex-command-runner.exe`
- `codex-windows-sandbox-setup.exe`
- `rg.exe`

---

## 三、具体技术实现

### 3.1 关键数据结构

#### 3.1.1 stage_npm_packages.py 包配置

```python
# 平台包配置（位于 codex-cli/scripts/build_npm_package.py）
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

# 包展开映射
PACKAGE_EXPANSIONS: dict[str, list[str]] = {
    "codex": ["codex", *CODEX_PLATFORM_PACKAGES],
}

# Native 组件依赖
PACKAGE_NATIVE_COMPONENTS: dict[str, list[str]] = {
    "codex": [],
    "codex-linux-x64": ["codex", "rg"],
    "codex-win32-x64": ["codex", "rg", "codex-windows-sandbox-setup", "codex-command-runner"],
    # ...
}
```

#### 3.1.2 install_native_deps.py 组件定义

```python
@dataclass(frozen=True)
class BinaryComponent:
    artifact_prefix: str      # 产物文件名前缀
    dest_dir: str            # vendor/<target>/ 下的目标目录
    binary_basename: str     # 可执行文件名（不含 .exe）
    targets: tuple[str, ...] | None = None  # 限制安装的目标平台

BINARY_COMPONENTS = {
    "codex": BinaryComponent(
        artifact_prefix="codex",
        dest_dir="codex",
        binary_basename="codex",
    ),
    "codex-windows-sandbox-setup": BinaryComponent(
        artifact_prefix="codex-windows-sandbox-setup",
        dest_dir="codex",
        binary_basename="codex-windows-sandbox-setup",
        targets=WINDOWS_TARGETS,  # 仅 Windows
    ),
    # ...
}
```

### 3.2 关键流程

#### 3.2.1 NPM 包构建流程

```
stage_npm_packages.py
    │
    ├── 1. 展开包列表（PACKAGE_EXPANSIONS）
    │
    ├── 2. 收集 native 组件
    │
    ├── 3. 解析工作流 URL
    │   └── gh run list --branch rust-v{version}
    │
    ├── 4. 下载 native 组件（install_native_deps.py）
    │   ├── gh run download {workflow_id}
    │   ├── 解压 zst 文件到 vendor/<target>/
    │   └── 下载 ripgrep（通过 DotSlash manifest）
    │
    └── 5. 构建各包（build_npm_package.py）
        ├── 复制源码/bin 文件到 staging 目录
        ├── 生成/修改 package.json
        ├── 复制 native 二进制到 vendor/
        └── npm pack 生成 tarball
```

#### 3.2.2 Mock WebSocket 服务器协议

```python
# 事件构造器
_event_response_created(response_id) -> {"type": "response.created", ...}
_event_function_call(call_id, name, args) -> {"type": "response.output_item.done", "item": {...}}
_event_response_done() -> {"type": "response.done", ...}
_event_assistant_message(msg_id, text) -> {"type": "response.output_item.done", "item": {...}}
_event_response_completed(response_id) -> {"type": "response.completed", ...}

# 对话状态机
State: CONNECTED
  -> recv_json("req1") [用户输入]
  -> send_event(response_created)
  -> send_event(function_call)
  -> send_event(response_done)
  -> State: WAITING_TOOL_OUTPUT

State: WAITING_TOOL_OUTPUT
  -> recv_json("req2") [工具输出]
  -> send_event(response_created)
  -> send_event(assistant_message)
  -> send_event(response_completed)
  -> websocket.close()
```

### 3.3 命令与协议

#### 3.3.1 GitHub CLI 使用

**获取工作流信息**:
```bash
gh run list \
  --branch rust-v{version} \
  --json workflowName,url,headSha \
  --workflow .github/workflows/rust-release.yml \
  --jq 'first(.[])'
```

**下载产物**:
```bash
gh run download --dir {dest_dir} --repo openai/codex {workflow_id}
```

#### 3.3.2 DotSlash 工具集成

**解析 manifest**:
```bash
dotslash -- parse {manifest_path}
```

**ripgrep 目标平台映射**:
```python
RG_TARGET_PLATFORM_PAIRS = [
    ("x86_64-unknown-linux-musl", "linux-x86_64"),
    ("aarch64-unknown-linux-musl", "linux-aarch64"),
    ("x86_64-apple-darwin", "macos-x86_64"),
    ("aarch64-apple-darwin", "macos-aarch64"),
    ("x86_64-pc-windows-msvc", "windows-x86_64"),
    ("aarch64-pc-windows-msvc", "windows-aarch64"),
]
```

---

## 四、关键代码路径与文件引用

### 4.1 脚本间依赖关系

```
scripts/stage_npm_packages.py
    ├── imports (动态): codex-cli/scripts/build_npm_package.py
    │   ├── PACKAGE_NATIVE_COMPONENTS
    │   ├── PACKAGE_EXPANSIONS
    │   └── CODEX_PLATFORM_PACKAGES
    │
    └── calls: codex-cli/scripts/install_native_deps.py
        └── calls: dotslash (CLI tool)
```

### 4.2 CI 工作流引用

| 工作流文件 | 引用脚本 | 用途 |
|-----------|---------|------|
| `.github/workflows/ci.yml:56` | `asciicheck.py README.md` | ASCII 检查 |
| `.github/workflows/ci.yml:58` | `readme_toc.py README.md` | ToC 检查 |
| `.github/workflows/ci.yml:42` | `stage_npm_packages.py` | NPM staging 测试 |
| `.github/workflows/blob-size-policy.yml:28` | `check_blob_size.py` | Blob 大小检查 |
| `.github/workflows/bazel.yml:79` | `check-module-bazel-lock.sh` | Bazel 锁文件检查 |
| `.github/workflows/rust-release.yml:495` | `stage_npm_packages.py` | 发布 staging |
| `.github/workflows/rust-release.yml:503-504` | `install.sh`, `install.ps1` | 发布安装脚本 |

### 4.3 配置文件引用

| 脚本 | 配置文件 | 用途 |
|------|---------|------|
| `check_blob_size.py` | `.github/blob-size-allowlist.txt` | 大文件豁免列表 |
| `install_native_deps.py` | `codex-cli/bin/rg` | DotSlash manifest for ripgrep |
| `stage_npm_packages.py` | `codex-cli/scripts/build_npm_package.py` | 包配置常量 |

### 4.4 关键文件路径

```
scripts/
├── asciicheck.py                    # 行 127
├── check-module-bazel-lock.sh       # 行 8
├── check_blob_size.py               # 行 193
├── debug-codex.sh                   # 行 10
├── mock_responses_websocket_server.py # 行 195
├── readme_toc.py                    # 行 120
├── stage_npm_packages.py            # 行 206
└── install/
    ├── install.sh                   # 行 244
    └── install.ps1                  # 行 196
```

---

## 五、依赖与外部交互

### 5.1 外部工具依赖

| 脚本 | 依赖工具 | 用途 |
|------|---------|------|
| `check-module-bazel-lock.sh` | `bazel` | 锁文件校验 |
| `check_blob_size.py` | `git` | 获取 blob 大小和变更列表 |
| `stage_npm_packages.py` | `gh` (GitHub CLI) | 获取工作流信息和下载产物 |
| `install_native_deps.py` | `gh`, `dotslash`, `zstd` | 下载和解压产物 |
| `install/install.sh` | `curl` 或 `wget`, `tar` | 下载和解压 |
| `mock_responses_websocket_server.py` | `websockets` (Python 包) | WebSocket 服务 |

### 5.2 Python 依赖

```python
# mock_responses_websocket_server.py
import websockets  # 第三方包

# install_native_deps.py
from concurrent.futures import ThreadPoolExecutor  # 标准库
import urllib.request  # 标准库

# check_blob_size.py
from dataclasses import dataclass  # 标准库
```

### 5.3 环境变量依赖

| 脚本 | 环境变量 | 用途 |
|------|---------|------|
| `check_blob_size.py` | `GITHUB_STEP_SUMMARY` | 写入 GitHub Actions Summary |
| `stage_npm_packages.py` | `RUNNER_TEMP`, `GH_TOKEN` | 临时目录和 GitHub 认证 |
| `install_native_deps.py` | `GITHUB_ACTIONS` | 检测是否在 GitHub Actions 环境 |
| `install/install.sh` | `CODEX_INSTALL_DIR` | 自定义安装目录 |
| `install/install.ps1` | `CODEX_INSTALL_DIR` | 自定义安装目录 |

### 5.4 网络交互

| 脚本 | 网络端点 | 用途 |
|------|---------|------|
| `stage_npm_packages.py` | `api.github.com` | 获取工作流信息 |
| `install_native_deps.py` | `api.github.com` | 下载工作流产物 |
| `install/install.sh` | `api.github.com`, `github.com` | 获取最新版本和下载 release |
| `install/install.ps1` | `api.github.com`, `github.com` | 获取最新版本和下载 release |
| `install_native_deps.py` | DotSlash manifest 中的 URL | 下载 ripgrep |
| `mock_responses_websocket_server.py` | `ws://127.0.0.1:8765` | 本地 WebSocket 服务 |

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 网络依赖风险

| 风险点 | 影响 | 缓解措施 |
|--------|------|---------|
| GitHub API 速率限制 | install 脚本可能失败 | 使用 CDN 或镜像 |
| 工作流产物过期 | stage_npm_packages 失败 | 明确错误提示，文档说明 |
| websockets 包未安装 | mock 服务器无法启动 | 添加 requirements.txt |

#### 6.1.2 平台兼容性风险

| 风险点 | 影响 | 缓解措施 |
|--------|------|---------|
| Windows ARM64 检测 | 可能误判架构 | 依赖 .NET RuntimeInformation |
| macOS Rosetta 转译 | 可能安装错误架构 | 检测 `sysctl.proc_translated` |
| 老旧系统缺少 zstd | 无法解压产物 | 提供 tar.gz 备选 |

#### 6.1.3 安全边界

| 风险点 | 说明 |
|--------|------|
| `check_blob_size.py` 的豁免列表 | 需定期审计，防止滥用 |
| `install.sh` 的 PATH 修改 | 自动修改 shell profile，需用户知情 |
| `stage_npm_packages.py` 的临时目录 | 使用 `RUNNER_TEMP` 或系统临时目录，默认清理 |

### 6.2 边界条件

#### 6.2.1 asciicheck.py

- **输入边界**: 必须有效的 UTF-8 编码文件
- **处理边界**: 非常大的文件（>100MB）可能导致内存问题（一次性读取）
- **修复边界**: 仅替换预定义的字符映射，其他非 ASCII 字符需手动处理

#### 6.2.2 check_blob_size.py

- **默认限制**: 500 KiB
- **豁免文件**: 精确路径匹配，不支持通配符
- **Git 依赖**: 需要完整的 Git 历史（`fetch-depth: 0`）

#### 6.2.3 mock_responses_websocket_server.py

- **单连接限制**: 仅支持顺序处理一个对话流程
- **固定响应**: 硬编码的 function_call 参数（`{"command": "echo websocket"}`）
- **端口占用**: 默认 8765，被占用时可通过 `--port 0` 使用随机端口

### 6.3 改进建议

#### 6.3.1 短期改进

1. **asciicheck.py**
   - 添加对大文件的流式处理支持
   - 支持 `.gitattributes` 或 `.asciicheckignore` 排除特定文件

2. **readme_toc.py**
   - 支持自定义目录深度限制（当前处理 `##` 到 `######`）
   - 添加对 HTML 注释内标题的跳过支持

3. **mock_responses_websocket_server.py**
   - 添加 requirements.txt 明确依赖 `websockets>=15.0`
   - 支持通过命令行参数自定义响应内容
   - 支持多并发连接

#### 6.3.2 中期改进

1. **stage_npm_packages.py**
   - 添加本地缓存机制，避免重复下载相同工作流产物
   - 支持增量构建（仅变更的平台包）
   - 添加产物校验（SHA256）

2. **install_native_deps.py**
   - 支持从本地目录而非仅 GitHub Actions 获取产物
   - 添加重试机制和指数退避
   - 支持代理配置

3. **check_blob_size.py**
   - 支持通配符和正则匹配豁免规则
   - 添加按文件类型的差异化限制

#### 6.3.3 长期改进

1. **统一配置**
   - 考虑将分散在各脚本的配置（如平台列表、组件映射）集中到一个 YAML 配置文件中

2. **测试覆盖**
   - 为脚本添加单元测试（使用 `pytest`）
   - 在 CI 中添加脚本本身的测试工作流

3. **文档化**
   - 为每个脚本添加 `--help` 详细说明
   - 添加 ARCHITECTURE.md 说明脚本间关系

---

## 七、附录

### 7.1 脚本调用关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                         CI/CD 工作流                             │
├─────────────────────────────────────────────────────────────────┤
│  ci.yml          blob-size-policy.yml    bazel.yml              │
│    │                  │                    │                    │
│    ├─ asciicheck.py   ├─ check_blob_size.py ├─ check-module-bazel-lock.sh
│    ├─ readme_toc.py   │                    │                    │
│    └─ stage_npm_packages.py (测试)          │                    │
│                       │                    │                    │
└───────────────────────┼────────────────────┼────────────────────┘
                        │                    │
┌───────────────────────┼────────────────────┼────────────────────┐
│                       │                    │                    │
│  rust-release.yml ◄───┘                    │                    │
│       │                                    │                    │
│       ├─ stage_npm_packages.py (发布)      │                    │
│       │       │                            │                    │
│       │       ├─ build_npm_package.py ◄────┼────────────────────┤
│       │       │           ▲                │                    │
│       │       └─ install_native_deps.py ───┘                    │
│       │                   │                                     │
│       └─ install.sh/ps1 (复制到 dist)                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         本地开发                                 │
├─────────────────────────────────────────────────────────────────┤
│  debug-codex.sh ──► cargo run --bin codex                       │
│                                                                 │
│  mock_responses_websocket_server.py ──► ws://localhost:8765     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         用户安装                                 │
├─────────────────────────────────────────────────────────────────┤
│  install/install.sh ──► GitHub Releases ──► npm tarball         │
│  install/install.ps1 ──► GitHub Releases ──► npm tarball        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 文件大小统计

| 文件 | 行数 | 复杂度 |
|------|------|--------|
| `stage_npm_packages.py` | 206 | 中（协调多个子流程） |
| `install_native_deps.py` | 475 | 高（并发下载、多格式解压） |
| `build_npm_package.py` | 453 | 高（多包类型处理） |
| `mock_responses_websocket_server.py` | 195 | 低（简单协议模拟） |
| `check_blob_size.py` | 193 | 低 |
| `install/install.sh` | 244 | 中 |
| `install/install.ps1` | 196 | 中 |
| `readme_toc.py` | 120 | 低 |
| `asciicheck.py` | 127 | 低 |
| `check-module-bazel-lock.sh` | 8 | 极低 |
| `debug-codex.sh` | 10 | 极低 |

---

*文档生成时间: 2026-03-22*
*基于仓库 commit: 需手动确认*
