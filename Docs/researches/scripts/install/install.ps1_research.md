# install.ps1 深度研究文档

## 文件信息
- **路径**: `scripts/install/install.ps1`
- **大小**: 196 行 / 约 5650 字节
- **类型**: PowerShell 安装脚本
- **用途**: Windows 平台 Codex CLI 自动化安装程序

---

## 一、场景与职责

### 1.1 核心场景
`install.ps1` 是 OpenAI Codex CLI 在 **Windows 平台** 的官方安装脚本，面向以下用户场景：

1. **新用户快速安装**: 用户通过 `curl` 下载并执行脚本，一键完成 Codex CLI 的安装
2. **版本升级**: 检测已安装版本，支持从旧版本升级到新版本
3. **CI/CD 自动化**: 在 Windows 构建环境中自动化部署 Codex CLI
4. **离线/企业环境**: 支持通过 `CODEX_INSTALL_DIR` 环境变量自定义安装路径

### 1.2 核心职责
| 职责 | 说明 |
|------|------|
| 平台检测 | 验证 Windows OS 和 64 位架构支持 |
| 架构识别 | 自动识别 ARM64 或 X64 架构 |
| 版本解析 | 支持 `latest`、语义化版本、`v` 前缀、`rust-v` 前缀等多种版本格式 |
| 二进制下载 | 从 GitHub Releases 下载对应平台的 npm tarball |
| 文件安装 | 解压并安装 codex.exe、rg.exe 等二进制文件 |
| PATH 配置 | 自动更新用户级 PATH 环境变量 |
| 清理工作 | 安装完成后清理临时文件 |

---

## 二、功能点目的

### 2.1 版本参数处理
```powershell
param(
    [Parameter(Position=0)]
    [string]$Version = "latest"
)
```
- **目的**: 允许用户指定特定版本安装，默认为最新版
- **使用示例**: `install.ps1 0.1.0` 或 `install.ps1 v0.1.0`

### 2.2 严格模式设置
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
```
- **目的**: 
  - `Set-StrictMode`: 启用严格的语法检查，捕获潜在错误
  - `ErrorActionPreference = "Stop"`: 任何错误立即终止脚本
  - `ProgressPreference`: 禁用进度条，避免在 CI 环境中产生干扰输出

### 2.3 版本规范化 (`Normalize-Version`)
```powershell
function Normalize-Version {
    param([string]$RawVersion)
    # 处理 "latest"、"rust-v0.1.0"、"v0.1.0"、"0.1.0" 等格式
}
```
- **目的**: 统一处理多种版本标识格式，兼容不同用户输入习惯
- **支持的格式**:
  - `latest` → `latest`
  - `rust-v0.1.0` → `0.1.0`
  - `v0.1.0` → `0.1.0`
  - `0.1.0` → `0.1.0`

### 2.4 版本解析 (`Resolve-Version`)
```powershell
function Resolve-Version {
    # 调用 GitHub API 获取最新 release 版本
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/openai/codex/releases/latest"
}
```
- **目的**: 当用户指定 `latest` 时，动态查询 GitHub API 获取实际最新版本号

### 2.5 平台架构检测
```powershell
$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
switch ($architecture) {
    "Arm64" { $target = "aarch64-pc-windows-msvc"; $npmTag = "win32-arm64" }
    "X64"   { $target = "x86_64-pc-windows-msvc"; $npmTag = "win32-x64" }
}
```
- **目的**: 自动识别系统架构，下载对应的目标二进制文件
- **支持架构**:
  - ARM64: `aarch64-pc-windows-msvc`
  - X64: `x86_64-pc-windows-msvc`

### 2.6 安装目录确定
```powershell
if ([string]::IsNullOrWhiteSpace($env:CODEX_INSTALL_DIR)) {
    $installDir = Join-Path $env:LOCALAPPDATA "Programs\OpenAI\Codex\bin"
} else {
    $installDir = $env:CODEX_INSTALL_DIR
}
```
- **默认路径**: `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`
- **自定义路径**: 通过 `CODEX_INSTALL_DIR` 环境变量覆盖

### 2.7 二进制文件映射
```powershell
$copyMap = @{
    "codex/codex.exe" = "codex.exe"
    "codex/codex-command-runner.exe" = "codex-command-runner.exe"
    "codex/codex-windows-sandbox-setup.exe" = "codex-windows-sandbox-setup.exe"
    "path/rg.exe" = "rg.exe"
}
```
- **目的**: 定义从 tarball 内部路径到安装目录的映射关系
- **说明**: Windows 平台额外包含 `codex-command-runner.exe` 和 `codex-windows-sandbox-setup.exe`

### 2.8 PATH 环境变量管理
```powershell
function Path-Contains {
    param([string]$PathValue, [string]$Entry)
    # 检查 PATH 中是否已包含指定目录
}
```
- **目的**: 智能检测 PATH 配置状态，避免重复添加
- **行为**:
  - 如果目录已在用户 PATH 中且当前会话 PATH 中 → 显示已配置
  - 如果目录在用户 PATH 中但不在当前会话 → 提示需要新开 shell
  - 如果目录不在 PATH 中 → 添加到用户 PATH 并更新当前会话

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
│ 平台检测        │────▶│ 非 Windows?     │────▶ 错误退出
│ (Windows + 64位)│     └─────────────────┘
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 架构检测        │────▶ ARM64 / X64
│ (ARM64/X64)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 确定安装目录    │────▶ %LOCALAPPDATA%\Programs\OpenAI\Codex\bin
│ (环境变量覆盖)  │      或 CODEX_INSTALL_DIR
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
│ 创建临时目录    │────▶ %TEMP%\codex-install-<GUID>
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 下载 tarball    │────▶ https://github.com/openai/codex/releases/
│                 │      download/rust-v{version}/codex-npm-{platform}-{version}.tgz
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 解压 tarball    │────▶ tar -xzf
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 复制二进制文件  │────▶ 按 copyMap 映射安装
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 更新 PATH       │────▶ 用户级 + 当前会话
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 清理临时文件    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 完成提示        │
└─────────────────┘
```

### 3.2 数据结构

#### 3.2.1 架构信息映射
```powershell
switch ($architecture) {
    "Arm64" {
        $target = "aarch64-pc-windows-msvc"      # Rust target triple
        $platformLabel = "Windows (ARM64)"       # 显示标签
        $npmTag = "win32-arm64"                  # npm 包标签
    }
    "X64" {
        $target = "x86_64-pc-windows-msvc"
        $platformLabel = "Windows (x64)"
        $npmTag = "win32-x64"
    }
}
```

#### 3.2.2 文件复制映射
```powershell
$copyMap = @{
    "codex/codex.exe" = "codex.exe"                           # 主程序
    "codex/codex-command-runner.exe" = "codex-command-runner.exe"  # 命令运行器
    "codex/codex-windows-sandbox-setup.exe" = "codex-windows-sandbox-setup.exe"  # 沙盒设置
    "path/rg.exe" = "rg.exe"                                  # ripgrep 工具
}
```

### 3.3 协议与命令

#### 3.3.1 GitHub API 调用
```powershell
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/openai/codex/releases/latest"
```
- **协议**: HTTPS REST API
- **端点**: `GET /repos/openai/codex/releases/latest`
- **响应**: JSON 格式，包含 `tag_name` 字段

#### 3.3.2 资源下载
```powershell
Invoke-WebRequest -Uri $url -OutFile $archivePath
```
- **URL 格式**: `https://github.com/openai/codex/releases/download/rust-v{version}/{asset}`
- **Asset 格式**: `codex-npm-{platform}-{version}.tgz`

#### 3.3.3 解压命令
```powershell
tar -xzf $archivePath -C $extractDir
```
- **工具**: Windows 内置 tar (Windows 10 1803+ 内置)
- **格式**: gzip 压缩的 tar 归档

---

## 四、关键代码路径与文件引用

### 4.1 脚本内部函数
| 函数名 | 行号 | 职责 |
|--------|------|------|
| `Write-Step` | 10-16 | 输出带格式的步骤信息 |
| `Normalize-Version` | 18-36 | 版本字符串规范化 |
| `Get-ReleaseUrl` | 38-45 | 构建 GitHub Release URL |
| `Path-Contains` | 47-65 | 检查 PATH 是否包含指定目录 |
| `Resolve-Version` | 67-80 | 解析版本号（支持 latest） |

### 4.2 外部依赖文件
| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-npm-win32-x64-{version}.tgz` | 下载 | Windows x64 平台 npm 包 |
| `codex-npm-win32-arm64-{version}.tgz` | 下载 | Windows ARM64 平台 npm 包 |
| `codex.exe` | 安装 | 主程序二进制 |
| `codex-command-runner.exe` | 安装 | 命令运行器 |
| `codex-windows-sandbox-setup.exe` | 安装 | Windows 沙盒设置工具 |
| `rg.exe` | 安装 | ripgrep 搜索工具 |

### 4.3 相关脚本与配置
| 文件 | 关系 | 说明 |
|------|------|------|
| `.github/workflows/rust-release.yml` | 调用方 | CI 流程中复制安装脚本到发布产物 |
| `scripts/stage_npm_packages.py` | 构建依赖 | 生成 npm tarball 的 staging 脚本 |
| `codex-cli/scripts/build_npm_package.py` | 构建依赖 | npm 包构建脚本，定义平台包配置 |
| `scripts/install/install.sh` | 姐妹脚本 | Unix/Linux 平台对应脚本 |

---

## 五、依赖与外部交互

### 5.1 系统依赖
| 依赖项 | 用途 | 检查方式 |
|--------|------|----------|
| Windows OS | 运行环境 | `$env:OS -eq "Windows_NT"` |
| 64-bit 架构 | 运行要求 | `[Environment]::Is64BitOperatingSystem` |
| tar | 解压 tarball | 内置命令 |
| PowerShell | 脚本执行 | 隐式要求 |

### 5.2 网络依赖
| 依赖项 | 用途 | 端点 |
|--------|------|------|
| GitHub API | 获取最新版本 | `api.github.com/repos/openai/codex/releases/latest` |
| GitHub Releases | 下载二进制包 | `github.com/openai/codex/releases/download/...` |

### 5.3 环境变量
| 变量名 | 用途 | 默认值 |
|--------|------|--------|
| `CODEX_INSTALL_DIR` | 自定义安装目录 | `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` |
| `LOCALAPPDATA` | 确定默认安装路径 | 系统定义 |
| `Path` (User) | 持久化 PATH 配置 | 用户环境变量 |
| `Path` (Process) | 当前会话 PATH | 进程环境变量 |

### 5.4 外部服务交互
```
┌─────────────────┐         HTTPS          ┌─────────────────┐
│   install.ps1   │ ─────────────────────▶ │  GitHub API     │
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

#### 6.1.2 权限风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 无法写入安装目录 | 安装失败 | 提前检测目录写权限 |
| 无法修改 PATH | 需要手动配置 | 清晰提示用户手动添加 |
| 需要管理员权限 | UAC 提示 | 默认安装到用户目录避免管理员权限 |

#### 6.1.3 架构兼容性风险
| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 不支持 32-bit Windows | 脚本退出 | 明确错误提示 |
| 不支持非 Windows 系统 | 脚本退出 | 提示使用 install.sh |

### 6.2 边界情况

#### 6.2.1 版本处理边界
```powershell
# 边界: 空字符串处理
[string]::IsNullOrWhiteSpace($RawVersion) → 返回 "latest"

# 边界: 多种前缀处理
"rust-v0.1.0" → "0.1.0"
"v0.1.0" → "0.1.0"
"0.1.0" → "0.1.0"
```

#### 6.2.2 PATH 处理边界
```powershell
# 边界: 空 PATH
if ([string]::IsNullOrWhiteSpace($userPath)) { $newUserPath = $installDir }

# 边界: 大小写不敏感比较
$segment.TrimEnd("\") -ieq $needle  # -ieq = case-insensitive equal

# 边界: 尾部反斜杠处理
$needle = $Entry.TrimEnd("\")
```

#### 6.2.3 临时目录边界
```powershell
# 边界: GUID 生成确保唯一性
"codex-install-" + [System.Guid]::NewGuid().ToString("N")

# 边界: try-finally 确保清理
try { ... } finally { Remove-Item -Recurse -Force $tempDir }
```

### 6.3 改进建议

#### 6.3.1 安全性改进
1. **添加 Checksum 验证**
   ```powershell
   # 建议: 下载后验证 SHA256 checksum
   $expectedHash = (Invoke-RestMethod "$url.sha256").Split()[0]
   $actualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
   if ($actualHash -ne $expectedHash) { throw "Checksum mismatch" }
   ```

2. **签名验证**
   ```powershell
   # 建议: 验证二进制签名
   Get-AuthenticodeSignature $codexPath
   ```

#### 6.3.2 功能改进
1. **支持卸载**
   ```powershell
   # 建议: 添加 -Uninstall 参数
   param([switch]$Uninstall)
   ```

2. **支持强制重装**
   ```powershell
   # 建议: 添加 -Force 参数覆盖现有安装
   param([switch]$Force)
   ```

3. **详细日志模式**
   ```powershell
   # 建议: 添加 -Verbose 参数
   param([switch]$Verbose)
   if ($Verbose) { $VerbosePreference = "Continue" }
   ```

#### 6.3.3 可靠性改进
1. **重试机制**
   ```powershell
   # 建议: 网络请求添加重试
   for ($i = 0; $i -lt 3; $i++) {
       try { Invoke-WebRequest ...; break } catch { Start-Sleep 2 }
   }
   ```

2. **代理支持**
   ```powershell
   # 建议: 自动检测系统代理设置
   $proxy = [System.Net.WebRequest]::GetSystemWebProxy()
   ```

#### 6.3.4 用户体验改进
1. **进度显示**
   ```powershell
   # 建议: 大文件下载显示进度
   Invoke-WebRequest ... -OutFile ... -PassThru | ForEach-Object { ... }
   ```

2. **版本信息持久化**
   ```powershell
   # 建议: 安装后记录版本信息
   "$resolvedVersion" | Out-File "$installDir\version.txt"
   ```

---

## 七、总结

`install.ps1` 是一个设计简洁、功能完整的 Windows 平台安装脚本。它通过以下设计保证了可靠性：

1. **严格的错误处理**: `Set-StrictMode` 和 `$ErrorActionPreference = "Stop"`
2. **智能的版本解析**: 支持多种版本格式输入
3. **自动的架构检测**: 无需用户手动选择平台
4. **安全的安装路径**: 默认使用用户目录，避免管理员权限
5. **完善的 PATH 管理**: 智能检测和更新环境变量

主要改进方向应聚焦于安全性（checksum 验证）和用户体验（进度显示、卸载支持）。
