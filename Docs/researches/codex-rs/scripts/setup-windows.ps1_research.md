# setup-windows.ps1 深度研究文档

## 文件基本信息

- **文件路径**: `/home/sansha/Github/codex/codex-rs/scripts/setup-windows.ps1`
- **文件类型**: PowerShell 脚本
- **所属项目**: codex-rs (OpenAI Codex CLI Rust 实现)
- **目标平台**: Windows 10/11
- **执行权限**: 需要管理员权限 (Administrator)

---

## 1. 场景与职责

### 1.1 核心定位

`setup-windows.ps1` 是 **codex-rs 项目在 Windows 平台上的官方环境初始化脚本**。它的核心职责是为一台全新的 Windows 开发机器配置完整的 Rust 开发环境，使开发者能够立即开始构建和运行 Codex CLI。

### 1.2 使用场景

| 场景 | 描述 |
|------|------|
| **新开发者 onboarding** | 刚克隆仓库的 Windows 开发者首次设置环境 |
| **CI/CD 环境准备** | 在 Windows 构建代理上自动配置构建环境 |
| **环境修复/重装** | 开发环境损坏后快速恢复 |
| **工具链升级** | 随项目升级同步更新 Rust 工具链版本 |

### 1.3 与项目整体的关系

```
codex-rs/
├── scripts/
│   └── setup-windows.ps1    <-- 本文件：Windows 环境初始化
├── codex-windows-sandbox/   <-- Windows 沙箱实现（依赖本脚本安装的工具链）
├── Cargo.toml               <-- 工作区配置
├── rust-toolchain.toml      <-- Rust 工具链版本规范
└── justfile                 <-- 构建任务（依赖本脚本安装的 just）
```

### 1.4 执行前提

- **操作系统**: Windows 10 (1903+) 或 Windows 11
- **权限**: 必须以管理员身份运行 PowerShell
- **网络**: 需要互联网连接下载工具
- **预装依赖**: `winget` (Windows Package Manager)

---

## 2. 功能点目的

### 2.1 功能总览

脚本按顺序执行以下 7 大类安装/配置任务：

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: 前置检查                                               │
│  ├── 验证 winget 可用性                                          │
│  └── 设置错误处理策略 ($ErrorActionPreference = 'Stop')          │
├─────────────────────────────────────────────────────────────────┤
│  Phase 2: Visual Studio Build Tools 安装                         │
│  ├── 通过 winget 安装 VS 2022 Build Tools                        │
│  ├── 添加 VC Tools workload                                      │
│  ├── 添加 ARM64/ARM64EC 工具链支持                               │
│  └── 添加 Windows 11 SDK 22000                                   │
├─────────────────────────────────────────────────────────────────┤
│  Phase 3: Rust 工具链安装                                        │
│  ├── 通过 winget 安装 rustup                                     │
│  ├── 安装指定版本工具链 (1.93.0)                                 │
│  └── 添加组件: clippy, rustfmt, rust-src                         │
├─────────────────────────────────────────────────────────────────┤
│  Phase 4: 辅助 CLI 工具安装                                      │
│  ├── Git (Git.Git)                                               │
│  ├── ripgrep (BurntSushi.ripgrep.MSVC)                           │
│  ├── just (Casey.Just)                                           │
│  └── CMake (Kitware.CMake)                                       │
├─────────────────────────────────────────────────────────────────┤
│  Phase 5: LLVM/Clang 安装                                        │
│  ├── 安装 LLVM (LLVM.LLVM)                                       │
│  ├── 配置 LIBCLANG_PATH 环境变量                                 │
│  └── 配置 CC/CXX 环境变量                                        │
├─────────────────────────────────────────────────────────────────┤
│  Phase 6: cargo-insta 安装                                       │
│  └── 通过 cargo install 安装 snapshot 测试工具                   │
├─────────────────────────────────────────────────────────────────┤
│  Phase 7: 项目构建                                               │
│  ├── 进入 VS Dev Shell                                           │
│  └── 执行 cargo build                                            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 各功能点详细说明

#### 2.2.1 Visual Studio Build Tools 安装

**目的**: 提供 Rust 在 Windows 上编译所需的 C/C++ 编译器 (MSVC) 和 Windows SDK。

**关键组件**:
- `Microsoft.VisualStudio.Workload.VCTools`: 核心 VC++ 工具链
- `Microsoft.VisualStudio.Component.VC.Tools.ARM64`: ARM64 架构支持
- `Microsoft.VisualStudio.Component.VC.Tools.ARM64EC`: ARM64EC 仿真支持
- `Microsoft.VisualStudio.Component.Windows11SDK.22000`: Windows 11 SDK

**为什么需要**:
- Rust 在 Windows 上默认使用 MSVC 工具链
- 某些 crate (如 `windows-sys`) 需要编译 C/C++ 代码
- `codex-windows-sandbox` 需要与 Windows API 深度集成

#### 2.2.2 Rust 工具链管理

**目的**: 安装与项目兼容的 Rust 版本。

**关键决策**:
```powershell
$toolchain = '1.93.0'  # 硬编码版本号
```

- 版本号与 `rust-toolchain.toml` 中的 `channel = "1.93.0"` 保持一致
- 使用 `--profile minimal` 减少下载体积
- 显式安装 `clippy` (linting), `rustfmt` (格式化), `rust-src` (标准库源码)

#### 2.2.3 LLVM/Clang 安装

**目的**: 为需要 `bindgen` 或原生 C/C++ 依赖的 crate 提供编译器。

**环境变量配置**:
```powershell
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
$env:CC = 'C:\Program Files\LLVM\bin\clang.exe'
$env:CXX = 'C:\Program Files\LLVM\bin\clang++.exe'
```

**为什么需要**:
- 某些依赖可能使用 Clang 进行编译
- `bindgen` 需要 libclang 来解析 C 头文件

#### 2.2.4 cargo-insta 安装

**目的**: 支持 snapshot 测试 (insta crate)。

**特殊处理**:
```powershell
# 只有在 MSVC linker 可用时才安装
if ($hasLink) {
    & cargo install cargo-insta --locked
}
```

- `--locked` 确保使用 Cargo.lock 中的精确版本
- 需要等待 VS Dev Shell 环境准备就绪

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 脚本参数

```powershell
param(
  [switch] $SkipBuild  # 可选：跳过最终的 cargo build
)
```

#### 3.1.2 核心变量

```powershell
$WingetArgs = @('--accept-package-agreements', '--accept-source-agreements', '-e')
# --accept-package-agreements: 自动接受包许可协议
# --accept-source-agreements: 自动接受源协议
# -e: 使用精确匹配
```

### 3.2 关键函数实现

#### 3.2.1 Ensure-Command

```powershell
function Ensure-Command($Name) {
  $exists = Get-Command $Name -ErrorAction SilentlyContinue
  return $null -ne $exists
}
```

**作用**: 检查命令是否存在于 PATH 中。

#### 3.2.2 Add-CargoBinToPath

```powershell
function Add-CargoBinToPath() {
  $cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
  if (Test-Path $cargoBin) {
    if (-not ($env:Path.Split(';') -contains $cargoBin)) {
      $env:Path = "$env:Path;$cargoBin"
    }
  }
}
```

**作用**: 将 Cargo bin 目录添加到当前会话的 PATH。

**为什么需要**:
- rustup 安装后，cargo 位于 `%USERPROFILE%\.cargo\bin`
- 新安装的 cargo 在当前 PowerShell 会话中不可见，需要手动添加

#### 3.2.3 Ensure-VSComponents

```powershell
function Ensure-VSComponents([string[]]$Components) {
  $vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vs_installer.exe"
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  
  # 多阶段回退策略查找 VS 安装路径
  $instPath = & $vswhere -latest -products * -version "[17.0,18.0)" ...
  if (-not $instPath) { ... }
  
  # 使用 vs_installer 确保组件已安装
  & $vsInstaller @args | Out-Host
}
```

**作用**: 确保 Visual Studio 安装了指定的工作负载组件。

**查找策略** (按优先级):
1. 查找带 VCTools 的 VS 2022 实例
2. 查找 BuildTools 2022
3. 查找任意带 VCTools 的实例
4. 回退到默认路径 `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`

#### 3.2.4 Enter-VsDevShell

```powershell
function Enter-VsDevShell() {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  
  # 查找带 VC 工具链的 VS 安装
  $instPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ...
  
  # 执行 VsDevCmd.bat 并导入环境变量
  $devCmdStr = ('"{0}" -no_logo -arch={1} -host_arch={1} & set' -f $vsDevCmd, $arch)
  $envLines = & cmd.exe /c $devCmdStr
  
  # 解析并设置环境变量
  foreach ($line in $envLines) {
    if ($line -match '^(.*?)=(.*)$') {
      [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
  }
}
```

**作用**: 进入 Visual Studio 开发者命令提示环境，使 `link.exe` 等工具可用。

**架构检测**:
```powershell
$arch = if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 
  'arm64' 
} else { 
  'x64' 
}
```

### 3.3 关键流程

#### 3.3.1 主执行流程

```powershell
# 1. 前置检查
Ensure-Command 'winget'  # 必须存在

# 2. 安装 VS Build Tools (含 ARM64 支持)
winget install ... Microsoft.VisualStudio.2022.BuildTools
Ensure-VSComponents ...

# 3. 安装 rustup
winget install ... Rustlang.Rustup
Add-CargoBinToPath

# 4. 安装辅助工具
winget install ... Git.Git
winget install ... BurntSushi.ripgrep.MSVC
winget install ... Casey.Just
winget install ... Kitware.CMake

# 5. 配置 Rust 工具链
rustup toolchain install 1.93.0 --profile minimal
rustup default 1.93.0
rustup component add clippy rustfmt rust-src --toolchain 1.93.0

# 6. 安装 LLVM
winget install ... LLVM.LLVM
Add-LLVMToPath  # 配置 LIBCLANG_PATH, CC, CXX

# 7. 安装 cargo-insta
Enter-VsDevShell
if ($hasLink) { cargo install cargo-insta --locked }

# 8. 构建项目
if (-not $SkipBuild) {
  Enter-VsDevShell
  cargo build
}
```

### 3.4 协议与命令

#### 3.4.1 winget 命令模式

```powershell
winget install @WingetArgs --id <PackageId> [--override <InstallerArgs>]
```

**常用包 ID**:
| 包 ID | 用途 |
|-------|------|
| Microsoft.VisualStudio.2022.BuildTools | VS 构建工具 |
| Rustlang.Rustup | Rust 工具链管理器 |
| Git.Git | 版本控制 |
| BurntSushi.ripgrep.MSVC | 快速文本搜索 |
| Casey.Just | 命令运行器 |
| Kitware.CMake | 构建系统 |
| LLVM.LLVM | Clang 编译器 |

#### 3.4.2 vswhere 查询语法

```powershell
# 查找 VS 2022 安装路径
vswhere -latest -products * -version "[17.0,18.0)" -requires <ComponentId> -property installationPath

# 常用组件 ID
Microsoft.VisualStudio.Workload.VCTools           # VC++ 工具集
Microsoft.VisualStudio.Component.VC.Tools.x86.x64 # x86/x64 工具链
Microsoft.VisualStudio.Component.VC.Tools.ARM64   # ARM64 工具链
```

---

## 4. 关键代码路径与文件引用

### 4.1 直接依赖的文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-rs/rust-toolchain.toml` | 配置源 | 定义 Rust 版本 `1.93.0` |
| `codex-rs/Cargo.toml` | 构建目标 | 工作区配置，构建入口 |
| `codex-rs/justfile` | 可选工具 | just 任务定义 |

### 4.2 被调用方 (下游依赖)

```
setup-windows.ps1
    └── 安装的工具被以下组件使用:
        ├── codex-windows-sandbox/          # Windows 沙箱实现
        │   ├── build.rs                    # 使用 winres 编译资源
        │   ├── src/setup_orchestrator.rs   # 沙箱设置编排
        │   └── src/elevated_impl.rs        # 提权沙箱实现
        ├── codex-cli/                      # CLI 入口
        │   └── src/debug_sandbox.rs        # 调试沙箱子命令
        └── codex-core/                     # 核心逻辑
            ├── src/windows_sandbox.rs      # Windows 沙箱配置
            └── src/sandboxing/mod.rs       # 沙箱抽象层
```

### 4.3 调用方 (上游调用)

脚本目前**没有自动化调用方**，是开发者手动执行的入口脚本。

**预期调用方式**:
```powershell
# 以管理员身份运行 PowerShell
powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1
```

### 4.4 与 Windows 沙箱的深度关联

`codex-windows-sandbox` crate 是本脚本安装的工具链的主要消费者：

```rust
// codex-windows-sandbox/src/setup_orchestrator.rs
pub const SETUP_VERSION: u32 = 5;
pub const OFFLINE_USERNAME: &str = "CodexSandboxOffline";
pub const ONLINE_USERNAME: &str = "CodexSandboxOnline";

// 需要 VS Build Tools 编译的 Windows API 绑定
#[cfg(target_os = "windows")]
use windows_sys::Win32::Security::...;
use windows_sys::Win32::System::Threading::...;
```

**为什么需要完整的 VS 工具链**:
- `windows-sys` crate 需要链接 Windows API
- `winres` build 依赖需要编译资源文件
- 沙箱实现涉及底层 Windows 安全 API

---

## 5. 依赖与外部交互

### 5.1 外部系统依赖

| 依赖 | 类型 | 用途 | 获取方式 |
|------|------|------|----------|
| winget | 系统工具 | Windows 包管理 | Windows 10/11 内置 |
| vswhere.exe | VS 组件 | 定位 VS 安装 | 随 VS Installer 安装 |
| vs_installer.exe | VS 组件 | 修改 VS 安装 | 随 VS Installer 安装 |
| PowerShell 5.1+ | 系统工具 | 脚本执行环境 | Windows 内置 |

### 5.2 网络依赖

| 目标 | 用途 |
|------|------|
| Microsoft Store (winget 源) | 下载所有 winget 包 |
| crates.io | cargo install cargo-insta |
| static.rust-lang.org | rustup 工具链下载 |

### 5.3 环境变量影响

脚本修改以下环境变量：

```powershell
# 进程级 (当前会话)
$env:Path              # 添加 Cargo bin, LLVM bin
$env:LIBCLANG_PATH     # 指向 LLVM bin
$env:CC                # 指向 clang.exe
$env:CXX               # 指向 clang++.exe
$env:RUSTFLAGS         # 清空为 ''

# 用户级 (持久化)
[Environment]::SetEnvironmentVariable('Path', ..., 'User')
[Environment]::SetEnvironmentVariable('LIBCLANG_PATH', ..., 'User')
[Environment]::SetEnvironmentVariable('CC', ..., 'User')
[Environment]::SetEnvironmentVariable('CXX', ..., 'User')
```

### 5.4 文件系统影响

| 路径 | 操作 | 内容 |
|------|------|------|
| `%USERPROFILE%\.cargo\bin` | 添加到 PATH | cargo, rustc, rustup 等 |
| `C:\Program Files\LLVM\bin` | 添加到 PATH | clang, llvm 工具 |
| `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | 安装 | VS Build Tools |
| `codex-rs/target/` | 创建 | 构建产物 |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 硬编码版本号风险

**问题**: Rust 工具链版本 `1.93.0` 硬编码在脚本中。

```powershell
$toolchain = '1.93.0'  # 与 rust-toolchain.toml 可能不同步
```

**风险**: 当 `rust-toolchain.toml` 更新时，脚本可能安装错误版本。

**建议**: 从 `rust-toolchain.toml` 动态读取版本：
```powershell
$toolchain = (Get-Content rust-toolchain.toml | Select-String 'channel = "(.+)"').Matches.Groups[1].Value
```

#### 6.1.2 winget 可用性风险

**问题**: 脚本严格要求 winget，但某些环境可能缺失。

```powershell
if (-not (Ensure-Command 'winget')) {
  throw "winget is required. Please update to the latest Windows 10/11 or install winget."
}
```

**风险场景**:
- Windows Server 版本可能无 winget
- 企业策略可能禁用 Microsoft Store
- 精简版 Windows 可能移除 winget

**建议**: 提供备用安装路径或更详细的故障排除指南。

#### 6.1.3 架构检测边界情况

**问题**: ARM64 检测逻辑可能不够全面。

```powershell
$isArm64 = ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
```

**风险**: 某些 ARM64 设备可能使用不同的环境变量标识。

#### 6.1.4 静默失败风险

**问题**: 某些函数使用 `try/catch {}` 静默吞掉异常。

```powershell
function Ensure-UserPathContains([string] $Segment) {
  try { ... } catch {}
}
```

**风险**: 环境变量设置失败不会被报告，可能导致后续构建问题。

### 6.2 边界条件

| 边界条件 | 行为 |
|----------|------|
| 已安装 VS 2022 但缺少 ARM64 组件 | `Ensure-VSComponents` 会尝试添加 |
| 已安装 rustup 但版本不同 | rustup 会管理多版本，脚本继续执行 |
| 网络中断 | winget/cargo 会失败，脚本终止 |
| 非管理员执行 | VS Build Tools 安装会失败 |
| 路径含空格 | 已使用引号正确处理 |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **版本同步机制**
   ```powershell
   # 读取 rust-toolchain.toml
   $toolchainToml = Join-Path $PSScriptRoot "..\rust-toolchain.toml"
   if (Test-Path $toolchainToml) {
       $content = Get-Content $toolchainToml -Raw
       if ($content -match 'channel\s*=\s*"([^"]+)"') {
           $toolchain = $Matches[1]
       }
   }
   ```

2. **增强错误处理**
   - 在 `Ensure-UserPathContains` 等函数中添加日志记录
   - 提供详细的故障排除步骤

3. **进度指示**
   - 添加 `-Verbose` 开关
   - 显示下载进度估计

#### 6.3.2 中优先级

4. **离线模式支持**
   ```powershell
   param(
     [switch] $SkipBuild,
     [switch] $Offline  # 跳过网络依赖检查
   )
   ```

5. **并行安装**
   - 某些 winget 安装可以并行执行以加速

6. **健康检查命令**
   ```powershell
   # 添加验证模式
   .\setup-windows.ps1 -CheckOnly
   ```

#### 6.3.3 低优先级

7. **配置导出**
   - 支持导出已安装版本的清单

8. **回滚机制**
   - 记录安装前状态，支持回滚

### 6.4 测试建议

| 测试场景 | 验证点 |
|----------|--------|
| 全新 Windows 11 安装 | 完整流程通过 |
| 已安装 VS 2022 | 跳过或增量安装 |
| ARM64 设备 | 正确安装 ARM64 工具链 |
| 网络受限环境 | 优雅失败，清晰错误 |
| 非管理员执行 | 早期检测，友好提示 |

---

## 7. 附录

### 7.1 相关文档

- [codex-rs/README.md](/home/sansha/Github/codex/codex-rs/README.md) - 项目主文档
- [docs/install.md](/home/sansha/Github/codex/docs/install.md) - 安装指南
- [codex-rs/rust-toolchain.toml](/home/sansha/Github/codex/codex-rs/rust-toolchain.toml) - Rust 版本规范

### 7.2 相关代码

- [codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs](/home/sansha/Github/codex/codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs) - 沙箱设置编排
- [codex-rs/core/src/windows_sandbox.rs](/home/sansha/Github/codex/codex-rs/core/src/windows_sandbox.rs) - Windows 沙箱配置
- [codex-rs/cli/src/debug_sandbox.rs](/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs) - 调试沙箱子命令

### 7.3 外部参考

- [winget 文档](https://docs.microsoft.com/en-us/windows/package-manager/)
- [vswhere 文档](https://github.com/microsoft/vswhere)
- [Rust on Windows](https://rust-lang.github.io/rustup/installation/windows.html)
