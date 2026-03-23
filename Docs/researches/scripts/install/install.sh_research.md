# install.sh 深度研究文档

## 文件信息
- **路径**: `scripts/install/install.sh`
- **大小**: 244 行 / 约 5043 字节
- **类型**: POSIX Shell 脚本 (sh-compatible)
- **用途**: macOS/Linux 平台 Codex CLI 自动化安装程序

---

## 一、场景与职责

### 1.1 核心场景
`install.sh` 是 OpenAI Codex CLI 在 **macOS 和 Linux 平台** 的官方安装脚本，面向以下用户场景：

1. **新用户快速安装**: 用户通过 `curl | sh` 方式一键安装
   ```bash
   curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | sh
   ```
2. **指定版本安装**: 支持安装特定版本
   ```bash
   curl -fsSL ... | sh -s -- 0.1.0
   ```
3. **CI/CD 自动化**: 在 macOS/Linux 构建环境中自动化部署
4. **开发环境配置**: 支持通过 `CODEX_INSTALL_DIR` 自定义安装路径

### 1.2 核心职责
| 职责 | 说明 |
|------|------|
| 平台检测 | 验证 macOS 或 Linux 操作系统 |
| 架构识别 | 自动识别 x86_64 或 aarch64/arm64 架构 |
| Rosetta 检测 | 在 macOS 上检测 Rosetta 转译环境 |
| 版本解析 | 支持 `latest`、语义化版本、`v` 前缀、`rust-v` 前缀等 |
| 下载工具适配 | 自动检测并使用 curl 或 wget |
| 二进制下载 | 从 GitHub Releases 下载对应平台的 npm tarball |
| 文件安装 | 解压并安装 codex、rg 二进制文件 |
| PATH 配置 | 自动检测并更新 shell profile 中的 PATH |
| 清理工作 | 安装完成后清理临时文件 (trap EXIT) |

---

## 二、功能点目的

### 2.1 Shell 兼容性设置
```bash
#!/bin/sh
set -eu
```
- **目的**: 使用 POSIX sh 确保最大兼容性（不仅限于 bash）
- `-e`: 命令失败立即退出
- `-u`: 使用未定义变量时报错

### 2.2 版本参数处理
```bash
VERSION="${1:-latest}"
```
- **目的**: 第一个参数指定版本，默认为 `latest`
- **使用示例**: `./install.sh 0.1.0`

### 2.3 安装目录配置
```bash
INSTALL_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
```
- **默认路径**: `$HOME/.local/bin` (遵循 XDG 规范)
- **自定义路径**: 通过 `CODEX_INSTALL_DIR` 环境变量覆盖

### 2.4 版本规范化 (`normalize_version`)
```bash
normalize_version() {
  case "$1" in
    "" | latest)  printf 'latest\n' ;;
    rust-v*)      printf '%s\n' "${1#rust-v}" ;;
    v*)           printf '%s\n' "${1#v}" ;;
    *)            printf '%s\n' "$1" ;;
  esac
}
```
- **目的**: 统一处理多种版本标识格式
- **支持的格式**: `latest`、`rust-v0.1.0`、`v0.1.0`、`0.1.0`

### 2.5 下载工具适配
```bash
download_file() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$output" "$url"
    return
  fi
  echo "curl or wget is required to install Codex." >&2
  exit 1
}
```
- **目的**: 兼容不同系统环境，优先使用 curl，回退到 wget
- **选项说明**:
  - `curl -fsSL`: fail silently, show error, location follow
  - `wget -q`: quiet mode

### 2.6 平台架构检测
```bash
case "$(uname -s)" in
  Darwin)  os="darwin" ;;
  Linux)   os="linux" ;;
esac

case "$(uname -m)" in
  x86_64 | amd64)  arch="x86_64" ;;
  arm64 | aarch64) arch="aarch64" ;;
esac
```
- **目的**: 自动识别操作系统和 CPU 架构
- **支持平台**:
  - macOS (Darwin): x86_64, aarch64 (Apple Silicon)
  - Linux: x86_64, aarch64

### 2.7 Rosetta 转译检测 (macOS 特有)
```bash
if [ "$os" = "darwin" ] && [ "$arch" = "x86_64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
    arch="aarch64"
  fi
fi
```
- **目的**: 检测是否在 Apple Silicon Mac 上通过 Rosetta 运行 x86_64 shell
- **原理**: `sysctl.proc_translated` 返回 1 表示在转译环境中
- **行为**: 自动切换到 aarch64 原生二进制以获得更好性能

### 2.8 PATH 配置 (`add_to_path`)
```bash
add_to_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*)  return ;;  # 已在 PATH 中
  esac

  # 根据当前 shell 选择 profile 文件
  profile="$HOME/.profile"
  case "${SHELL:-}" in
    */zsh) profile="$HOME/.zshrc" ;;
    */bash) profile="$HOME/.bashrc" ;;
  esac

  # 添加到 profile
  printf '\n# Added by Codex installer\n' >> "$profile"
  printf 'export PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$profile"
}
```
- **目的**: 智能配置 PATH，支持 bash/zsh/sh
- **行为**:
  - 如果目录已在 PATH 中 → 跳过
  - 如果配置已存在于 profile → 标记为已配置
  - 否则添加到 profile

### 2.9 临时目录清理 (trap)
```bash
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM
```
- **目的**: 确保脚本退出时清理临时文件
- **信号捕获**: EXIT (正常退出)、INT (Ctrl+C)、TERM (kill)

---

## 三、具体技术实现

### 3.1 关键流程图

```
┌─────────────────┐
│   脚本启动      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 平台检测        │────▶│ 非 macOS/Linux? │────▶ 错误退出
│ (uname -s)      │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 架构检测        │────▶│ 不支持?         │────▶ 错误退出
│ (uname -m)      │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ Rosetta 检测    │────▶│ 转译中?         │────▶ 切换 aarch64
│ (macOS only)    │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 确定目标三元组  │────▶ aarch64-apple-darwin
│                 │      x86_64-apple-darwin
│                 │      aarch64-unknown-linux-musl
│                 │      x86_64-unknown-linux-musl
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 确定安装目录    │────▶ $HOME/.local/bin
│ (环境变量覆盖)  │      或 $CODEX_INSTALL_DIR
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 版本解析        │────▶│ latest?         │────▶ 调用 GitHub API
│                 │     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 创建临时目录    │────▶ mktemp -d
│ 设置清理 trap   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 下载 tarball    │────▶ curl/wget
│                 │      github.com/.../codex-npm-{platform}-{version}.tgz
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 解压 tarball    │────▶ tar -xzf
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 复制二进制文件  │────▶ cp codex, rg
│ 设置权限        │      chmod 0755
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 更新 PATH       │────▶ 写入 ~/.bashrc / ~/.zshrc / ~/.profile
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ trap 清理       │────▶ rm -rf $tmp_dir
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 完成提示        │
└─────────────────┘
```

### 3.2 数据结构

#### 3.2.1 平台到 npm_tag 映射
```bash
if [ "$os" = "darwin" ]; then
  if [ "$arch" = "aarch64" ]; then
    npm_tag="darwin-arm64"
    vendor_target="aarch64-apple-darwin"
    platform_label="macOS (Apple Silicon)"
  else
    npm_tag="darwin-x64"
    vendor_target="x86_64-apple-darwin"
    platform_label="macOS (Intel)"
  fi
else
  if [ "$arch" = "aarch64" ]; then
    npm_tag="linux-arm64"
    vendor_target="aarch64-unknown-linux-musl"
    platform_label="Linux (ARM64)"
  else
    npm_tag="linux-x64"
    vendor_target="x86_64-unknown-linux-musl"
    platform_label="Linux (x64)"
  fi
fi
```

#### 3.2.2 文件安装映射
```bash
# tarball 内部路径 → 安装目录
cp "$tmp_dir/package/vendor/$vendor_target/codex/codex" "$INSTALL_DIR/codex"
cp "$tmp_dir/package/vendor/$vendor_target/path/rg" "$INSTALL_DIR/rg"
chmod 0755 "$INSTALL_DIR/codex"
chmod 0755 "$INSTALL_DIR/rg"
```

### 3.3 协议与命令

#### 3.3.1 GitHub API 调用
```bash
release_json="$(download_text "https://api.github.com/repos/openai/codex/releases/latest")"
resolved="$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name":[[:space:]]*"rust-v\([^"]*\)".*/\1/p' | head -n 1)"
```
- **协议**: HTTPS
- **端点**: `GET /repos/openai/codex/releases/latest`
- **响应解析**: 使用 sed 提取 `tag_name` 字段中的版本号

#### 3.3.2 资源下载
```bash
# curl 方式
curl -fsSL "$url" -o "$output"

# wget 方式
wget -q -O "$output" "$url"
```
- **URL 格式**: `https://github.com/openai/codex/releases/download/rust-v{version}/{asset}`
- **Asset 格式**: `codex-npm-{platform}-{version}.tgz`

#### 3.3.3 解压命令
```bash
tar -xzf "$archive_path" -C "$tmp_dir"
```
- **工具**: tar (POSIX 标准)
- **格式**: gzip 压缩的 tar 归档

---

## 四、关键代码路径与文件引用

### 4.1 脚本内部函数
| 函数名 | 行号 | 职责 |
|--------|------|------|
| `step` | 10-12 | 输出带格式的步骤信息 |
| `normalize_version` | 14-29 | 版本字符串规范化 |
| `download_file` | 31-47 | 下载文件 (curl/wget 适配) |
| `download_text` | 49-64 | 下载文本内容 (curl/wget 适配) |
| `add_to_path` | 66-98 | 配置 PATH 到 shell profile |
| `release_url_for_asset` | 100-105 | 构建 GitHub Release URL |
| `require_command` | 107-112 | 检查必需命令是否存在 |
| `resolve_version` | 117-134 | 解析版本号（支持 latest） |

### 4.2 外部依赖文件
| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-npm-darwin-arm64-{version}.tgz` | 下载 | macOS ARM64 npm 包 |
| `codex-npm-darwin-x64-{version}.tgz` | 下载 | macOS x64 npm 包 |
| `codex-npm-linux-arm64-{version}.tgz` | 下载 | Linux ARM64 npm 包 |
| `codex-npm-linux-x64-{version}.tgz` | 下载 | Linux x64 npm 包 |
| `codex` | 安装 | 主程序二进制 |
| `rg` | 安装 | ripgrep 搜索工具 |

### 4.3 相关脚本与配置
| 文件 | 关系 | 说明 |
|------|------|------|
| `.github/workflows/rust-release.yml` | 调用方 | CI 流程中复制安装脚本到发布产物 (第 501-504 行) |
| `scripts/stage_npm_packages.py` | 构建依赖 | 生成 npm tarball 的 staging 脚本 |
| `codex-cli/scripts/build_npm_package.py` | 构建依赖 | npm 包构建脚本，定义平台包配置 |
| `scripts/install/install.ps1` | 姐妹脚本 | Windows 平台对应脚本 |

---

## 五、依赖与外部交互

### 5.1 系统依赖
| 依赖项 | 用途 | 检查方式 |
|--------|------|----------|
| sh/POSIX shell | 脚本执行 | shebang `#!/bin/sh` |
| mktemp | 创建临时目录 | `require_command mktemp` |
| tar | 解压 tarball | `require_command tar` |
| curl 或 wget | 下载文件 | `command -v curl/wget` |
| sysctl (macOS) | Rosetta 检测 | `sysctl -n sysctl.proc_translated` |

### 5.2 网络依赖
| 依赖项 | 用途 | 端点 |
|--------|------|------|
| GitHub API | 获取最新版本 | `api.github.com/repos/openai/codex/releases/latest` |
| GitHub Releases | 下载二进制包 | `github.com/openai/codex/releases/download/...` |

### 5.3 环境变量
| 变量名 | 用途 | 默认值 |
|--------|------|--------|
| `CODEX_INSTALL_DIR` | 自定义安装目录 | `$HOME/.local/bin` |
| `HOME` | 确定默认安装路径和 profile 位置 | 系统定义 |
| `PATH` | 检查/更新可执行文件搜索路径 | 系统定义 |
| `SHELL` | 检测当前 shell 类型 | 系统定义 |

### 5.4 外部服务交互
```
┌─────────────────┐         HTTPS          ┌─────────────────┐
│   install.sh    │ ─────────────────────▶ │  GitHub API     │
│                 │  GET /repos/.../latest │                 │
│                 │ ◀───────────────────── │  api.github.com │
└─────────────────┘      JSON 响应         └─────────────────┘
         │
         │ HTTPS
         ▼
┌─────────────────┐
│ GitHub Releases │
│                 │
│ github.com/...  │
└─────────────────┘
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 网络依赖风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| GitHub API 限流 | 无法解析 latest 版本 | 支持直接指定版本号绕过 API 调用 |
| 网络不通/防火墙 | 无法下载二进制包 | 提供离线安装文档 |
| DNS 劫持 | 下载恶意包 | 建议验证 checksum（当前未实现） |
| curl/wget 缺失 | 无法下载 | 明确错误提示用户安装 |

#### 6.1.2 权限风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 无法写入安装目录 | 安装失败 | 提前检测目录写权限 |
| 无法修改 profile | PATH 配置失败 | 清晰提示用户手动添加 |
| `$HOME` 未设置 | 路径解析错误 | 使用默认值或报错 |

#### 6.1.3 平台兼容性风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 不支持 Windows | 脚本退出 | 提示使用 install.ps1 |
| 不支持 32-bit | 脚本退出 | 明确错误提示 |
| 不支持非 x86/arm 架构 | 脚本退出 | 明确错误提示 |

#### 6.1.4 Shell 兼容性风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 非 POSIX 扩展 | 在某些 sh 上失败 | 使用 POSIX sh 子集 |
| `local` 关键字 | 某些 sh 不支持 | 避免使用 local |

### 6.2 边界情况

#### 6.2.1 版本处理边界
```bash
# 边界: 空字符串
"" → "latest"

# 边界: 多种前缀
"rust-v0.1.0" → "0.1.0"
"v0.1.0" → "0.1.0"
"0.1.0" → "0.1.0"
```

#### 6.2.2 PATH 处理边界
```bash
# 边界: 防止重复添加
case ":$PATH:" in
  *":$INSTALL_DIR:"*) return ;;  # 匹配 :/path: 避免子串匹配问题
esac
```

#### 6.2.3 Profile 选择边界
```bash
# 边界: 根据 SHELL 环境变量选择
# 注意: 这假设用户主要使用登录 shell
# 如果用户切换 shell 可能不准确
case "${SHELL:-}" in
  */zsh) profile="$HOME/.zshrc" ;;
  */bash) profile="$HOME/.bashrc" ;;
esac
```

#### 6.2.4 Rosetta 检测边界
```bash
# 边界: sysctl 可能不存在或返回空
"$(sysctl -n sysctl.proc_translated 2>/dev/null || true)"
# 使用 2>/dev/null 抑制错误，|| true 确保不中断
```

#### 6.2.5 临时目录边界
```bash
# 边界: trap 确保清理
trap cleanup EXIT INT TERM
# EXIT: 正常退出
# INT:  Ctrl+C (SIGINT)
# TERM: kill (SIGTERM)
```

### 6.3 改进建议

#### 6.3.1 安全性改进
1. **添加 Checksum 验证**
   ```bash
   # 建议: 下载后验证 SHA256 checksum
   download_file "$url.sha256" "$tmp_dir/checksum"
   expected=$(cat "$tmp_dir/checksum" | awk '{print $1}')
   actual=$(sha256sum "$archive_path" | awk '{print $1}')
   [ "$actual" = "$expected" ] || { echo "Checksum mismatch"; exit 1; }
   ```

2. **GPG 签名验证**
   ```bash
   # 建议: 验证发布签名
   gpg --verify "$tmp_dir/$asset.sig" "$archive_path"
   ```

#### 6.3.2 功能改进
1. **支持卸载**
   ```bash
   # 建议: 添加 uninstall 参数
   if [ "$1" = "--uninstall" ]; then
     rm -f "$INSTALL_DIR/codex" "$INSTALL_DIR/rg"
     # 从 profile 中移除 PATH 配置
     sed -i '/# Added by Codex installer/d' "$profile"
     sed -i "/export PATH=\"$INSTALL_DIR/d" "$profile"
   fi
   ```

2. **支持检查更新**
   ```bash
   # 建议: 添加 --check-update 参数
   # 比较本地版本和远程最新版本
   ```

3. **支持安静模式**
   ```bash
   # 建议: 添加 -q/--quiet 参数
   # 减少输出，适合 CI 环境
   ```

#### 6.3.3 可靠性改进
1. **重试机制**
   ```bash
   # 建议: 网络请求添加重试
   download_with_retry() {
     for i in 1 2 3; do
       download_file "$@" && return
       sleep 2
     done
     exit 1
   }
   ```

2. **代理支持**
   ```bash
   # 建议: 自动检测代理环境变量
   # curl 和 wget 自动使用 http_proxy/https_proxy
   ```

3. **更好的错误信息**
   ```bash
   # 建议: 添加更多上下文信息
   echo "Failed to download from: $url" >&2
   echo "Please check your internet connection." >&2
   ```

#### 6.3.4 用户体验改进
1. **进度显示**
   ```bash
   # curl 自带进度条，但可以通过 -# 启用简单进度
   # 或添加 --progress-bar 选项
   ```

2. **fish shell 支持**
   ```bash
   # 建议: 添加 fish shell profile 支持
   */fish)
     profile="$HOME/.config/fish/config.fish"
     path_line="set -gx PATH $INSTALL_DIR \$PATH"
     ;;
   ```

3. **版本信息持久化**
   ```bash
   # 建议: 安装后记录版本信息
   echo "$resolved_version" > "$INSTALL_DIR/.codex-version"
   ```

#### 6.3.5 POSIX 兼容性改进
1. **避免 bash 扩展**
   ```bash
   # 当前: 使用 ${var//pattern/replacement} (bash 扩展)
   # 建议: 使用 sed 替代以保持 POSIX 兼容
   ```

2. **测试多 shell 兼容性**
   ```bash
   # dash, busybox ash, zsh --emulate sh 等
   ```

---

## 七、总结

`install.sh` 是一个设计精良的 POSIX Shell 安装脚本，具有以下特点：

1. **最大兼容性**: 使用 POSIX sh 而非 bash，确保在各类 Unix-like 系统上运行
2. **智能平台检测**: 自动识别 macOS/Linux 和 x86_64/aarch64 架构
3. **Rosetta 感知**: 在 Apple Silicon Mac 上自动使用原生 aarch64 二进制
4. **工具自适应**: 自动检测并使用 curl 或 wget
5. **安全清理**: 使用 trap 确保临时文件清理
6. **非侵入式 PATH 配置**: 智能检测现有配置，避免重复添加

主要改进方向应聚焦于安全性（checksum 验证）、功能完整性（卸载支持）和 shell 生态支持（fish 等）。

---

## 附录: 与 install.ps1 的对比

| 特性 | install.sh (Unix) | install.ps1 (Windows) |
|------|-------------------|----------------------|
| 语言 | POSIX sh | PowerShell |
| 默认安装路径 | `$HOME/.local/bin` | `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` |
| PATH 配置 | 写入 shell profile | 修改注册表 + 当前会话 |
| 架构检测 | `uname -m` | `[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture` |
| 特殊处理 | Rosetta 检测 | 无 |
| 额外二进制 | codex, rg | codex.exe, rg.exe, codex-command-runner.exe, codex-windows-sandbox-setup.exe |
| 下载工具 | curl/wget | Invoke-WebRequest |
| 解压工具 | tar | tar (内置) |
