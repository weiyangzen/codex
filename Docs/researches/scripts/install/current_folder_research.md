# scripts/install 目录研究文档

## 概述

`scripts/install` 目录包含 Codex CLI 的跨平台安装脚本，提供了一种不依赖 npm/brew 的原生二进制安装方式。这些脚本直接从 GitHub Releases 下载预编译的平台特定包并安装到用户系统。

---

## 场景与职责

### 核心职责

1. **跨平台安装入口**：为 macOS、Linux 和 Windows 用户提供统一的命令行安装体验
2. **GitHub Releases 集成**：直接从 `openai/codex` 仓库的 Releases 页面下载预编译二进制文件
3. **零依赖安装**：仅需系统自带的 `curl`/`wget` (Unix) 或 PowerShell (Windows)，无需 Node.js 或包管理器
4. **PATH 配置自动化**：自动检测并配置 shell 环境变量，确保安装后即可使用

### 使用场景

| 场景 | 适用脚本 | 说明 |
|------|----------|------|
| macOS/Linux 快速安装 | `install.sh` | 用户执行 `curl -fsSL .../install.sh \| sh` |
| Windows 快速安装 | `install.ps1` | 用户执行 `irm .../install.ps1 \| iex` |
| CI/CD 自动化部署 | 两者皆可 | 通过环境变量控制安装路径和版本 |
| 离线/私有化部署 | 修改脚本 | 修改 `release_url_for_asset` 函数指向私有仓库 |

### 与 npm/brew 安装的关系

```
┌─────────────────────────────────────────────────────────────┐
│                    Codex CLI 安装方式                         │
├─────────────────────────────────────────────────────────────┤
│  方式1: npm install -g @openai/codex   (Node.js 生态)        │
│  方式2: brew install --cask codex      (macOS 生态)          │
│  方式3: install.sh / install.ps1       (原生二进制, 本目录)   │
│  方式4: GitHub Releases 手动下载        (完全手动)            │
└─────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 版本解析与管理

**目的**：支持灵活的版本指定方式，兼容不同来源的版本标签格式。

**支持的版本格式**：
- `latest`（默认）：自动查询 GitHub API 获取最新版本
- `rust-v0.x.x`：Git 标签格式（带 `rust-v` 前缀）
- `v0.x.x`：简化标签格式（带 `v` 前缀）
- `0.x.x`：纯版本号

**关键代码**（`install.sh:14-29`）：
```bash
normalize_version() {
  case "$1" in
    "" | latest)
      printf 'latest\n'
      ;;
    rust-v*)
      printf '%s\n' "${1#rust-v}"  # 移除 rust-v 前缀
      ;;
    v*)
      printf '%s\n' "${1#v}"      # 移除 v 前缀
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}
```

### 2. 平台检测与架构适配

**目的**：自动识别操作系统和 CPU 架构，下载匹配的二进制包。

**支持的平台矩阵**：

| OS | 架构 | npm_tag | vendor_target | 平台标签 |
|----|------|---------|---------------|----------|
| macOS | Apple Silicon (arm64) | `darwin-arm64` | `aarch64-apple-darwin` | macOS (Apple Silicon) |
| macOS | Intel (x86_64) | `darwin-x64` | `x86_64-apple-darwin` | macOS (Intel) |
| Linux | ARM64 | `linux-arm64` | `aarch64-unknown-linux-musl` | Linux (ARM64) |
| Linux | x64 | `linux-x64` | `x86_64-unknown-linux-musl` | Linux (x64) |
| Windows | ARM64 | `win32-arm64` | `aarch64-pc-windows-msvc` | Windows (ARM64) |
| Windows | x64 | `win32-x64` | `x86_64-pc-windows-msvc` | Windows (x64) |

**特殊处理**：
- **Rosetta 检测**（`install.sh:162-166`）：在 Apple Silicon Mac 上检测是否通过 Rosetta 运行，自动切换到 `aarch64` 架构
- **Windows 辅助工具**（`install.ps1:147-152`）：额外安装 `codex-command-runner.exe` 和 `codex-windows-sandbox-setup.exe`

### 3. 下载与安装流程

**目的**：可靠地下载、解压并安装二进制文件到指定目录。

**流程步骤**：
1. 解析版本号（支持 `latest` 自动查询）
2. 构建下载 URL：`https://github.com/openai/codex/releases/download/rust-v{VERSION}/codex-npm-{PLATFORM_TAG}-{VERSION}.tgz`
3. 使用 `curl` 或 `wget` 下载 tarball
4. 解压到临时目录
5. 复制二进制文件到安装目录（默认：`$HOME/.local/bin` 或 `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`）
6. 设置可执行权限（Unix）
7. 清理临时文件

### 4. PATH 环境变量管理

**目的**：确保安装的二进制文件可以在 shell 中直接调用。

**Unix 实现**（`install.sh:66-98`）：
- 检测当前 shell（bash/zsh）
- 选择对应的配置文件（`.bashrc` / `.zshrc` / `.profile`）
- 检查 PATH 是否已包含安装目录
- 如未包含，追加 `export PATH="$INSTALL_DIR:\$PATH"` 到配置文件

**Windows 实现**（`install.ps1:163-187`）：
- 使用 `[Environment]::SetEnvironmentVariable` 修改用户级 PATH
- 同时更新当前进程的 `$env:Path` 变量
- 使用 `Path-Contains` 函数进行大小写不敏感的路径比较

### 5. 更新检测

**目的**：区分全新安装和版本更新，提供适当的用户提示。

**实现**（`install.sh:190-194`）：
```bash
if [ -x "$INSTALL_DIR/codex" ]; then
  install_mode="Updating"
else
  install_mode="Installing"
fi
```

---

## 具体技术实现

### 关键流程图

```
┌──────────────────────────────────────────────────────────────────────┐
│                           install.sh 流程                             │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. 参数解析 ────────────────────────► VERSION (默认: latest)          │
│                                                                      │
│  2. 环境检测 ────────────────────────► OS + ARCH ───────► platform    │
│     - uname -s (Darwin/Linux)              label                     │
│     - uname -m (x86_64/arm64)                                      │
│     - Rosetta 检测 (sysctl.proc_translated)                        │
│                                                                      │
│  3. 版本解析 ────────────────────────► 查询 GitHub API               │
│     normalize_version()                    (如果是 latest)          │
│                                            ────────► resolved_version│
│                                                                      │
│  4. 构建 URL ────────────────────────► codex-npm-{tag}-{ver}.tgz    │
│                                                                      │
│  5. 下载 ────────────────────────────► mktemp -d                    │
│     curl / wget                            ▼                        │
│                                      tar -xzf                       │
│                                                                      │
│  6. 安装 ────────────────────────────► cp codex rg                  │
│     mkdir -p $INSTALL_DIR                  chmod 0755               │
│                                                                      │
│  7. PATH 配置 ──────────────────────► 检测 shell                    │
│     add_to_path()                          编辑 .bashrc/.zshrc      │
│                                                                      │
│  8. 完成提示 ────────────────────────► 显示运行命令                  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 数据结构

#### 版本信息结构
```
VERSION (输入)
    ├── "" | "latest" ────────► "latest"
    ├── "rust-v0.x.x" ────────► "0.x.x"
    ├── "v0.x.x" ─────────────► "0.x.x"
    └── "0.x.x" ──────────────► "0.x.x"
```

#### 平台映射结构（`install.sh:168-188`）
```bash
# 伪代码表示
PlatformConfig {
  npm_tag: string,        # 用于构建 tarball 文件名
  vendor_target: string,  # 用于定位二进制文件在 tarball 中的路径
  platform_label: string  # 用于用户显示
}
```

### 关键命令与工具依赖

| 工具 | 用途 | 必需 | 备选 |
|------|------|------|------|
| `curl` | 下载文件/JSON | 否 | `wget` |
| `wget` | 下载文件/JSON | 否 | `curl` |
| `mktemp` | 创建临时目录 | 是 | 无 |
| `tar` | 解压 tarball | 是 | 无 |
| `uname` | 检测 OS/ARCH | 是 | 无 |
| `sysctl` | Rosetta 检测 (macOS) | 否 | 无 |

### 下载 URL 构建

**基础 URL 模板**（`install.sh:104`）：
```bash
printf 'https://github.com/openai/codex/releases/download/rust-v%s/%s\n' "$resolved_version" "$asset"
```

**Asset 名称格式**：
```
codex-npm-{npm_tag}-{version}.tgz

# 示例:
codex-npm-darwin-arm64-0.104.0.tgz
codex-npm-linux-x64-0.104.0.tgz
codex-npm-win32-x64-0.104.0.tgz
```

### tarball 内部结构

```
codex-npm-{platform}-{version}.tgz
└── package/
    └── vendor/
        └── {vendor_target}/           # 例如: aarch64-apple-darwin
            ├── codex/
            │   └── codex              # 主二进制文件 (Unix)
            │   └── codex.exe          # 主二进制文件 (Windows)
            │   └── codex-command-runner.exe      # (Windows 特有)
            │   └── codex-windows-sandbox-setup.exe # (Windows 特有)
            └── path/
                └── rg                 # ripgrep 二进制
                └── rg.exe             # (Windows)
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `scripts/install/install.sh` | 244 | Unix 安装脚本（macOS/Linux） |
| `scripts/install/install.ps1` | 196 | Windows 安装脚本（PowerShell） |

### 关键函数/代码块

#### install.sh

| 函数/代码块 | 行号 | 功能 |
|-------------|------|------|
| `step()` | 10-12 | 打印带格式的步骤信息 |
| `normalize_version()` | 14-29 | 版本号格式标准化 |
| `download_file()` | 31-47 | 使用 curl/wget 下载文件 |
| `download_text()` | 49-64 | 下载文本内容（用于 API 查询） |
| `add_to_path()` | 66-98 | 配置 PATH 环境变量 |
| `release_url_for_asset()` | 100-105 | 构建 GitHub Releases 下载 URL |
| `require_command()` | 107-112 | 检查必需命令是否存在 |
| `resolve_version()` | 117-134 | 解析版本号（包括 latest 查询） |
| OS 检测 case 语句 | 136-147 | 基于 `uname -s` 的 OS 检测 |
| ARCH 检测 case 语句 | 149-160 | 基于 `uname -m` 的架构检测 |
| Rosetta 检测 | 162-166 | 检测 macOS Rosetta 转译环境 |
| 平台配置映射 | 168-188 | 定义各平台的 npm_tag/vendor_target/label |
| 安装模式检测 | 190-194 | 检测是全新安装还是更新 |
| 主安装流程 | 196-244 | 下载、解压、安装、PATH 配置 |

#### install.ps1

| 函数/代码块 | 行号 | 功能 |
|-------------|------|------|
| `Write-Step()` | 10-16 | 打印带格式的步骤信息 |
| `Normalize-Version()` | 18-36 | 版本号格式标准化 |
| `Get-ReleaseUrl()` | 38-45 | 构建 GitHub Releases 下载 URL |
| `Path-Contains()` | 47-65 | 检查 PATH 是否包含指定目录 |
| `Resolve-Version()` | 67-80 | 解析版本号（包括 latest 查询） |
| OS 验证 | 82-85 | 验证运行环境为 Windows |
| 架构检测 | 92-111 | 使用 RuntimeInformation.OSArchitecture |
| 安装目录确定 | 113-117 | 基于 CODEX_INSTALL_DIR 或默认路径 |
| 主安装流程 | 119-196 | 下载、解压、安装、PATH 配置 |

### 相关外部文件

| 文件 | 关联说明 |
|------|----------|
| `codex-cli/scripts/build_npm_package.py` | 构建 npm tarball 的脚本，定义了 tarball 结构和平台映射 |
| `.github/workflows/rust-release.yml` | CI 工作流，触发构建并上传 tarball 到 Releases |
| `scripts/stage_npm_packages.py` | 发布流程中调用 build_npm_package.py 准备 npm 包 |
| `codex-cli/bin/codex.js` | npm 包的入口脚本，也使用类似的平台映射逻辑 |

---

## 依赖与外部交互

### 外部依赖

#### 1. GitHub Releases API

**用途**：查询最新版本信息

**请求**（`install.sh:125`）：
```bash
curl -fsSL "https://api.github.com/repos/openai/codex/releases/latest"
```

**响应解析**（`install.sh:126`）：
```bash
sed -n 's/.*"tag_name":[[:space:]]*"rust-v\([^"]*\)".*/\1/p'
```

**注意**：GitHub API 有速率限制（未认证 60 请求/小时/IP）

#### 2. GitHub Releases 下载

**用途**：下载预编译二进制 tarball

**URL 模式**：
```
https://github.com/openai/codex/releases/download/rust-v{VERSION}/codex-npm-{PLATFORM}-{VERSION}.tgz
```

**依赖关系**：
```
install.sh/install.ps1
    └── GitHub Releases (下载 tarball)
        └── rust-release.yml (CI 构建并上传)
            └── build_npm_package.py (构建 tarball)
```

#### 3. 系统命令

| 命令 | 来源 | 用途 |
|------|------|------|
| `curl` | 系统预装 | 首选下载工具 |
| `wget` | 系统预装 | 备选下载工具 |
| `tar` | 系统预装 | 解压 tarball |
| `mktemp` | 系统预装 | 创建临时目录 |
| `uname` | 系统预装 | 平台检测 |
| `sysctl` | macOS | Rosetta 检测 |

### 环境变量

| 变量 | 脚本 | 说明 | 默认值 |
|------|------|------|--------|
| `CODEX_INSTALL_DIR` | 两者 | 自定义安装目录 | Unix: `$HOME/.local/bin`<br>Win: `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` |
| `SHELL` | `install.sh` | 检测当前 shell | 自动检测 |
| `HOME` | `install.sh` | 用户主目录 | 系统设置 |
| `PATH` | 两者 | 可执行文件搜索路径 | 系统设置 |
| `LOCALAPPDATA` | `install.ps1` | Windows 本地应用数据目录 | 系统设置 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. GitHub API 速率限制

**风险**：未认证的 GitHub API 请求限制为 60 次/小时/IP。在 CI 环境或共享网络中可能触发限制。

**当前处理**：失败时退出并显示错误信息（`install.sh:128-131`）

**建议改进**：
```bash
# 添加重试机制和更友好的错误提示
resolve_version() {
  for i in 1 2 3; do
    release_json="$(download_text "https://api.github.com/repos/openai/codex/releases/latest" 2>/dev/null)"
    if [ -n "$release_json" ]; then
      break
    fi
    sleep 2
  done
  
  if [ -z "$release_json" ]; then
    echo "Failed to resolve version. GitHub API rate limit may have been exceeded." >&2
    echo "Please try again later or specify a specific version: ./install.sh 0.104.0" >&2
    exit 1
  fi
  # ...
}
```

#### 2. 网络中断处理

**风险**：大文件下载过程中网络中断可能导致不完整文件被安装。

**当前状态**：使用 `curl -f` 和 `wget -q`，失败时退出，但不会自动重试。

**建议改进**：添加下载校验（校验和验证）

#### 3. PATH 配置冲突

**风险**：
- 多个 shell 配置文件可能重复添加 PATH
- 手动修改的配置可能被覆盖

**当前处理**：使用 `grep -F` 检查是否已存在相同行（`install.sh:88`）

**边界情况**：
- 如果用户手动添加了不同格式的 PATH 行（如使用单引号、不同空格），可能重复添加
- 不会检测其他位置添加的相同目录

#### 4. 权限问题

**风险**：
- 安装目录可能没有写入权限
- 二进制文件可能没有执行权限

**当前处理**：
- `chmod 0755` 设置可执行权限（`install.sh:222-223`）
- 依赖 `mkdir -p` 创建目录

**建议改进**：提前检查目录写入权限

#### 5. Windows 特有组件依赖

**风险**：Windows 版本安装了额外的辅助二进制文件（`codex-command-runner.exe`, `codex-windows-sandbox-setup.exe`），但脚本不验证这些文件是否成功下载。

**当前处理**：`Move-Item` 失败时会抛出异常（PowerShell 的 `$ErrorActionPreference = "Stop"`）

### 边界情况

| 场景 | 行为 | 建议 |
|------|------|------|
| 已安装相同版本 | 覆盖安装，显示 "Updating" | 添加版本比较，相同版本时跳过 |
| 已安装更新版本 | 降级安装 | 添加版本比较，提示用户确认 |
| 磁盘空间不足 | 下载或解压失败 | 提前检查可用空间 |
| 临时目录不可写 | `mktemp` 失败 | 允许用户指定临时目录 |
| 代理环境 | 依赖系统代理配置 | 文档说明代理配置方法 |
| 非交互式 shell | PATH 配置可能无效 | 添加 `--no-path-config` 选项 |

### 改进建议

#### 1. 添加校验和验证

```bash
# 下载时同时获取 checksums.txt
download_checksums() {
  checksums_url="https://github.com/openai/codex/releases/download/rust-v${version}/SHA256SUMS"
  download_text "$checksums_url" > "$tmp_dir/checksums.txt"
}

# 验证下载文件
verify_checksum() {
  expected=$(grep "$asset" "$tmp_dir/checksums.txt" | awk '{print $1}')
  actual=$(sha256sum "$archive_path" | awk '{print $1}')
  if [ "$expected" != "$actual" ]; then
    echo "Checksum verification failed!" >&2
    exit 1
  fi
}
```

#### 2. 添加卸载功能

```bash
# 添加 --uninstall 选项
uninstall() {
  rm -f "$INSTALL_DIR/codex" "$INSTALL_DIR/rg"
  # 从 PATH 配置文件中移除
  sed -i '/# Added by Codex installer/d' "$HOME/.bashrc"
  sed -i '/export PATH=".*\.local\/bin:\$PATH"/d' "$HOME/.bashrc"
}
```

#### 3. 添加版本管理功能

```bash
# 添加 --list-versions 选项
list_versions() {
  download_text "https://api.github.com/repos/openai/codex/releases" | \
    grep -o '"tag_name": "rust-v[^"]*"' | \
    sed 's/"tag_name": "rust-v\([^"]*\)"/\1/' | \
    head -20
}
```

#### 4. 改进错误处理

```bash
# 添加更详细的错误分类
handle_error() {
  case "$1" in
    6)  echo "Could not resolve host. Check your internet connection." ;;
    7)  echo "Failed to connect to host. GitHub may be down." ;;
    22) echo "HTTP error 404. Version may not exist." ;;
    28) echo "Operation timeout. Check your network speed." ;;
    *)  echo "Unknown error (code: $1)" ;;
  esac
}
```

#### 5. 添加静默/自动化模式

```bash
# 添加 --yes / -y 选项用于 CI/CD
if [ "${CODEX_INSTALL_NONINTERACTIVE:-}" = "1" ]; then
  # 跳过所有提示，使用默认配置
  :  # no-op
fi
```

#### 6. Windows 脚本改进

```powershell
# 添加数字签名验证
# 添加进度条显示（Invoke-WebRequest 默认有进度条，但可通过 $ProgressPreference 控制）
# 添加管理员权限检测（某些安装路径需要）
```

### 测试建议

1. **多平台测试矩阵**：
   - macOS (Intel + Apple Silicon)
   - Ubuntu/Debian (x64 + ARM64)
   - Windows 10/11 (x64 + ARM64)

2. **边界条件测试**：
   - 磁盘空间不足
   - 网络中断/限速
   - 代理环境
   - 只读文件系统
   - 已存在旧版本

3. **集成测试**：
   - 与 GitHub Releases 的端到端测试
   - 与 npm 包的兼容性验证
   - PATH 配置验证

---

## 附录

### 相关文档链接

- [Codex 安装文档](../../docs/install.md)
- [GitHub Releases 页面](https://github.com/openai/codex/releases)
- [npm 包构建脚本](../../codex-cli/scripts/build_npm_package.py)

### 版本历史参考

发布流程通过 GitHub Actions 自动化（`.github/workflows/rust-release.yml`）：
1. 推送 `rust-v*` 标签触发构建
2. 多平台并行构建（macOS/Linux/Windows）
3. 代码签名（macOS 公证、Windows Azure 签名、Linux Cosign）
4. 创建 GitHub Release 并上传资产
5. 发布到 npm（可选）
6. 复制安装脚本到 Release 资产

### 文件变更历史

| 日期 | 变更 | 提交 |
|------|------|------|
| 2025-03 | 初始版本 | 基础安装脚本实现 |
| 2025-03 | 添加 Windows 支持 | 新增 install.ps1 |
| 2025-03 | 添加 Rosetta 检测 | install.sh 支持 Apple Silicon 转译检测 |

---

*文档生成时间：2026-03-22*
*研究范围：scripts/install/*
*相关系统：GitHub Releases, npm, CI/CD*
