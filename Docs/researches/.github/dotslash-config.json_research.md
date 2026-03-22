# dotslash-config.json 研究文档

## 场景与职责

`dotslash-config.json` 是 Facebook DotSlash 工具的配置文件，位于 `.github/dotslash-config.json`。该文件定义了 Codex 项目多平台二进制文件的发布配置，用于自动化生成 DotSlash 可执行文件，使用户能够通过简单的命令安装和运行 Codex CLI。

### DotSlash 简介

DotSlash 是 Meta (Facebook) 开发的一种工具，它允许将可执行文件作为版本控制的文本文件分发。其核心优势：
- **简化分发**: 用户无需手动下载和解压二进制文件
- **版本控制友好**: DotSlash 文件是纯文本，可存储在 Git 中
- **跨平台**: 自动根据平台下载正确的二进制文件
- **缓存管理**: 自动管理本地二进制文件缓存

### 项目发布场景

Codex 项目需要发布以下二进制文件到多个平台：
- **codex**: 主 CLI 工具（macOS/Linux/Windows，x86_64/aarch64）
- **codex-responses-api-proxy**: API 代理服务
- **codex-command-runner**: Windows 命令执行器
- **codex-windows-sandbox-setup**: Windows 沙箱设置工具

## 功能点目的

### 1. 多平台二进制文件映射

定义每个输出文件在不同平台上的命名规则和路径映射，确保用户在任何支持的平台上都能获取正确的二进制文件。

### 2. 自动化发布流程

与 GitHub Actions 工作流集成，在发布时自动生成 DotSlash 文件并上传到 GitHub Releases。

### 3. 简化用户安装

用户可以通过以下方式安装 Codex：
```bash
# 使用 DotSlash 直接运行
dotslash //github.com/openai/codex/releases/latest/download/codex

# 或下载 DotSlash 文件后执行
./codex  # 其中 codex 是 DotSlash 包装脚本
```

### 4. 版本管理

通过 GitHub Releases 的版本标签，确保用户获取到正确的版本。

## 具体技术实现

### 配置文件结构

```json
{
  "outputs": {
    "<output-name>": {
      "platforms": {
        "<platform-key>": {
          "regex": "<filename-pattern>",
          "path": "<executable-name>"
        }
      }
    }
  }
}
```

### 平台标识符

DotSlash 使用特定的平台标识符格式：`{os}-{arch}`

| 平台标识符 | 操作系统 | 架构 | 对应 Rust Target |
|-----------|---------|------|-----------------|
| `macos-aarch64` | macOS | ARM64 | `aarch64-apple-darwin` |
| `macos-x86_64` | macOS | x86_64 | `x86_64-apple-darwin` |
| `linux-x86_64` | Linux | x86_64 | `x86_64-unknown-linux-musl` |
| `linux-aarch64` | Linux | ARM64 | `aarch64-unknown-linux-musl` |
| `windows-x86_64` | Windows | x86_64 | `x86_64-pc-windows-msvc` |
| `windows-aarch64` | Windows | ARM64 | `aarch64-pc-windows-msvc` |

### 输出定义详解

#### 1. codex（主 CLI）
```json
"codex": {
  "platforms": {
    "macos-aarch64": {
      "regex": "^codex-aarch64-apple-darwin\\.zst$",
      "path": "codex"
    },
    ...
  }
}
```
- **覆盖范围**: 6 个平台（macOS/Linux/Windows × x86_64/aarch64）
- **文件格式**: `.zst`（Zstandard 压缩）
- **可执行文件名**: `codex`（Unix）或 `codex.exe`（Windows）

#### 2. codex-responses-api-proxy
```json
"codex-responses-api-proxy": {
  "platforms": { ... }
}
```
- **覆盖范围**: 6 个平台
- **用途**: OpenAI Responses API 的本地代理服务
- **文件命名**: `codex-responses-api-proxy-{target}.zst`

#### 3. codex-command-runner（Windows 专用）
```json
"codex-command-runner": {
  "platforms": {
    "windows-x86_64": { ... },
    "windows-aarch64": { ... }
  }
}
```
- **覆盖范围**: 仅 Windows 平台
- **用途**: Windows 环境下的命令执行代理
- **背景**: Windows 沙箱环境需要特殊的命令执行机制

#### 4. codex-windows-sandbox-setup（Windows 专用）
```json
"codex-windows-sandbox-setup": {
  "platforms": {
    "windows-x86_64": { ... },
    "windows-aarch64": { ... }
  }
}
```
- **覆盖范围**: 仅 Windows 平台
- **用途**: Windows 沙箱环境初始化工具

### 正则表达式模式

配置文件使用正则表达式匹配发布产物文件名：

```regex
^codex-aarch64-apple-darwin\.zst$
```

- `^` 和 `$`: 确保完全匹配
- `\\.zst`: 匹配 `.zst` 后缀（JSON 中需要转义）
- Windows 可执行文件包含 `.exe`: `codex-x86_64-pc-windows-msvc\.exe\.zst`

## 关键代码路径与文件引用

### 配置文件位置
```
.github/dotslash-config.json
```

### 相关文件

| 文件路径 | 说明 |
|---------|------|
| `.github/workflows/rust-release.yml` | 主发布工作流，调用 DotSlash 发布 |
| `scripts/stage_npm_packages.py` | NPM 包 staging 脚本 |
| `codex-cli/scripts/install_native_deps.py` | 本地依赖安装脚本 |
| `codex-cli/scripts/build_npm_package.py` | NPM 包构建脚本 |

### 发布流程集成

在 `.github/workflows/rust-release.yml` 中：

```yaml
- uses: facebook/dotslash-publish-release@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    tag: ${{ github.ref_name }}
    config: .github/dotslash-config.json
```

### 构建产物命名

Rust 发布工作流生成的文件名模式：
```
codex-{target}.zst
codex-responses-api-proxy-{target}.zst
codex-command-runner-{target}.exe.zst
codex-windows-sandbox-setup-{target}.exe.zst
```

其中 `{target}` 包括：
- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `x86_64-unknown-linux-musl`
- `aarch64-unknown-linux-musl`
- `x86_64-pc-windows-msvc`
- `aarch64-pc-windows-msvc`

### 依赖关系图

```
.github/dotslash-config.json
    ├── codex
    │   ├── macos-aarch64 → codex-aarch64-apple-darwin.zst
    │   ├── macos-x86_64 → codex-x86_64-apple-darwin.zst
    │   ├── linux-x86_64 → codex-x86_64-unknown-linux-musl.zst
    │   ├── linux-aarch64 → codex-aarch64-unknown-linux-musl.zst
    │   ├── windows-x86_64 → codex-x86_64-pc-windows-msvc.exe.zst
    │   └── windows-aarch64 → codex-aarch64-pc-windows-msvc.exe.zst
    ├── codex-responses-api-proxy (同上 6 平台)
    ├── codex-command-runner (仅 Windows 2 平台)
    └── codex-windows-sandbox-setup (仅 Windows 2 平台)
```

## 依赖与外部交互

### 外部服务

1. **GitHub Releases**
   - DotSlash 从 GitHub Releases 下载二进制文件
   - 需要 `GITHUB_TOKEN` 权限访问发布产物

2. **Facebook DotSlash Action**
   - 使用 `facebook/dotslash-publish-release@v2` GitHub Action
   - 在发布时自动生成 DotSlash 文件

3. **Zstandard 压缩**
   - 所有二进制文件使用 Zstandard (zst) 压缩
   - 相比 gzip 提供更好的压缩比和解压速度

### 与发布流程的集成

```
Tag Push (rust-v*.*.*)
    ↓
rust-release.yml
    ├── Build (多平台矩阵构建)
    │   └── 生成 *.zst 文件
    ├── Code Sign (代码签名)
    ├── Compress (压缩)
    ├── Upload Artifacts (上传产物)
    └── Release Job
        ├── Create GitHub Release
        ├── dotslash-publish-release
        │   └── 读取 .github/dotslash-config.json
        │   └── 生成 DotSlash 文件
        └── Publish to npm
```

### 与 NPM 包的关系

NPM 包（`codex-npm-*`）与 DotSlash 是并行分发机制：
- NPM 包面向 Node.js 生态用户
- DotSlash 面向通用命令行用户
- 两者共享相同的底层二进制文件

### 与安装脚本的交互

安装脚本（`scripts/install/install.sh` 和 `install.ps1`）可能使用 DotSlash 或直接从 GitHub Releases 下载：
- 简化安装脚本可以依赖 DotSlash 处理平台检测
- 或者手动实现平台检测和下载逻辑

## 风险、边界与改进建议

### 潜在风险

1. **文件名不匹配**
   - 如果 Rust 构建工作流更改了输出文件名格式，正则表达式将失效
   - 风险：DotSlash 无法找到匹配的二进制文件

2. **平台支持变更**
   - 添加或移除支持的平台需要同步更新此配置
   - 容易遗漏，导致某些平台无法使用 DotSlash 安装

3. **GitHub Releases 结构变更**
   - 如果发布流程更改了产物上传方式，DotSlash 可能无法正确解析

4. **正则表达式错误**
   - JSON 中的正则表达式需要双重转义（`\\`），容易出错
   - 例如：`\\.zst$` 实际匹配 `.zst`

### 边界情况

1. **Windows 可执行文件扩展名**
   - Windows 平台需要 `.exe` 扩展名
   - 配置中 `path` 字段正确区分了 `codex` 和 `codex.exe`

2. **压缩格式变更**
   - 当前使用 `.zst` 格式
   - 如果更改为 `.tar.gz` 或其他格式，需要更新正则表达式

3. **新增输出目标**
   - 添加新的二进制输出（如 `codex-lsp`）需要：
     - 更新 `dotslash-config.json`
     - 更新发布工作流生成对应产物

4. **平台检测失败**
   - DotSlash 依赖平台标识符匹配
   - 某些特殊环境（如 WSL、容器）可能报告错误的平台信息

### 改进建议

1. **配置验证**
   ```json
   {
     "$schema": "https://dotslash.dev/schema.json"
   }
   ```
   添加 JSON Schema 验证，在 CI 中检查配置有效性

2. **文档化平台映射**
   在配置文件中添加注释说明 Rust target 到 DotSlash 平台的映射关系：
   ```json
   {
     "_comment": "Rust target aarch64-apple-darwin maps to macos-aarch64"
   }
   ```

3. **自动化测试**
   - 在发布前验证所有正则表达式都能匹配到实际的构建产物
   - 添加 CI 检查确保配置与构建矩阵一致

4. **版本兼容性**
   ```json
   {
     "outputs": {
       "codex": {
         "minimum_version": "0.1.0"
       }
     }
   }
   ```
   考虑添加最低版本要求，避免使用过旧的二进制文件

5. **备用下载源**
   ```json
   {
     "platforms": {
       "linux-x86_64": {
         "regex": "...",
         "path": "codex",
         "fallback_url": "https://backup.cdn/..."
       }
     }
   }
   ```
   考虑添加备用下载 URL，应对 GitHub 访问问题

6. **校验和验证**
   - 发布流程生成 SHA256 校验和
   - DotSlash 配置引用校验和文件进行完整性验证

7. **与 install 脚本统一**
   - 确保 `scripts/install/install.sh` 和 `install.ps1` 使用相同的平台映射逻辑
   - 考虑让安装脚本直接使用 DotSlash 文件

### 相关文档

- [DotSlash 官方文档](https://dotslash.dev/)
- [facebook/dotslash-publish-release Action](https://github.com/facebook/dotslash-publish-release)
- [Zstandard 压缩格式](https://facebook.github.io/zstd/)
- [GitHub Releases 上传产物](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
