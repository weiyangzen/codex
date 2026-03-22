# codex-cli/bin/rg 深度研究文档

## 场景与职责

`rg` 是一个 **DotSlash 格式的清单文件（Manifest File）**，用于描述和管理 **ripgrep（rg）** 二进制文件的分发和安装。ripgrep 是一个高性能的代码搜索工具，由 BurntSushi 开发，是 Codex CLI 的依赖组件之一。

该文件的核心职责：

1. **跨平台二进制分发**：定义 6 个平台的 ripgrep 下载源和校验信息
2. **版本锁定**：固定使用 ripgrep 15.1.0 版本
3. **完整性验证**：通过 SHA256 哈希和文件大小验证下载内容
4. **与 install_native_deps.py 协作**：作为 Python 脚本解析的数据源

**注意**：此文件本身不是可执行文件，而是被 `dotslash` 工具或 Python 脚本解析的 JSON 格式清单。

## 功能点目的

### 1. DotSlash 格式概述

DotSlash 是 Meta（Facebook）开发的一种工具，用于：
- 将大型二进制文件从版本控制中分离
- 通过 URL 按需下载二进制文件
- 验证下载内容的完整性（哈希校验）
- 缓存下载的文件避免重复获取

文件以 `#!/usr/bin/env dotslash` 开头，使其可以直接执行（如果 dotslash 已安装）。

### 2. 平台定义结构

```json
{
  "name": "rg",
  "platforms": {
    "macos-aarch64": { ... },
    "linux-aarch64": { ... },
    "macos-x86_64": { ... },
    "linux-x86_64": { ... },
    "windows-x86_64": { ... },
    "windows-aarch64": { ... }
  }
}
```

**平台键命名规则**：
- 格式：`<os>-<arch>`
- OS: macos, linux, windows
- Arch: aarch64, x86_64

**注意**：这与 Rust target triple 格式不同，是 DotSlash 的简化平台标识。

### 3. 每个平台的配置字段

```json
{
  "size": 1777930,                    // 文件大小（字节）
  "hash": "sha256",                   // 哈希算法
  "digest": "sha256:...",             // 预期哈希值
  "format": "tar.gz",                 // 压缩格式
  "path": "ripgrep-.../rg",           // 压缩包内路径
  "providers": [{ "url": "..." }]     // 下载源
}
```

**目的**：
- `size` + `digest`：双重验证下载完整性
- `format`：支持 tar.gz（Unix）和 zip（Windows）
- `path`：指定从压缩包中提取的具体文件路径
- `providers`：支持多个镜像源（当前仅配置 GitHub Releases）

### 4. 格式差异处理

| 平台 | 格式 | 原因 |
|------|------|------|
| macOS/Linux | tar.gz | Unix 系统标准压缩格式 |
| Windows | zip | Windows 原生支持，无需额外工具 |

**路径差异**：
- Unix: `ripgrep-15.1.0-aarch64-apple-darwin/rg`（无扩展名）
- Windows: `ripgrep-15.1.0-aarch64-pc-windows-msvc/rg.exe`（带 .exe）

## 具体技术实现

### 清单解析流程（由 install_native_deps.py 执行）

```python
# 1. 使用 dotslash 命令解析清单
def _load_manifest(manifest_path: Path) -> dict:
    cmd = ["dotslash", "--", "parse", str(manifest_path)]
    stdout = subprocess.check_output(cmd, text=True)
    return json.loads(stdout)

# 2. 目标平台到 DotSlash 平台键的映射
RG_TARGET_PLATFORM_PAIRS = [
    ("x86_64-unknown-linux-musl", "linux-x86_64"),
    ("aarch64-unknown-linux-musl", "linux-aarch64"),
    ("x86_64-apple-darwin", "macos-x86_64"),
    ("aarch64-apple-darwin", "macos-aarch64"),
    ("x86_64-pc-windows-msvc", "windows-x86_64"),
    ("aarch64-pc-windows-msvc", "windows-aarch64"),
]

# 3. 下载和提取
# - 根据 platform_key 获取配置
# - 下载 URL 指向的压缩包
# - 验证大小和哈希
# - 提取 path 指定的文件到 vendor/<target>/path/
```

### 数据结构详解

```typescript
interface DotSlashManifest {
  name: string;           // 工具名称（rg）
  platforms: {
    [platformKey: string]: {
      size: number;       // 字节数
      hash: "sha256";     // 哈希算法（固定）
      digest: string;     // SHA256 十六进制值
      format: "tar.gz" | "zip";
      path: string;       // 压缩包内文件路径
      providers: Array<{
        url: string;      // 下载 URL
      }>;
    };
  };
}
```

### 文件大小与哈希值

| 平台 | 大小 | SHA256 哈希 |
|------|------|-------------|
| macOS arm64 | 1,777,930 B | `378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715` |
| Linux arm64 | 1,869,959 B | `2b661c6ef508e902f388e9098d9c4c5aca72c87b55922d94abdba830b4dc885e` |
| macOS x64 | 1,894,127 B | `64811cb24e77cac3057d6c40b63ac9becf9082eedd54ca411b475b755d334882` |
| Linux x64 | 2,263,077 B | `1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599` |
| Windows x64 | 1,810,687 B | `124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a` |
| Windows arm64 | 1,675,460 B | `00d931fb5237c9696ca49308818edb76d8eb6fc132761cb2a1bd616b2df02f8e` |

**观察**：
- Linux x64 版本最大（约 2.2MB），可能因为包含更多功能或调试符号
- Windows arm64 版本最小（约 1.6MB）

### 下载源

所有平台均从 GitHub Releases 下载：
```
https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-<target>.tar.gz
https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-<target>.zip
```

**依赖外部服务**：
- GitHub Releases 的可用性
- 网络连接（安装时）
- 下载后本地缓存（由 dotslash 或 Python 脚本管理）

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-cli/bin/rg` - DotSlash 清单文件（79 行 JSON）

### 相关文件

| 文件路径 | 关系 | 说明 |
|----------|------|------|
| `codex-cli/scripts/install_native_deps.py` | 消费者 | 解析此清单并下载 ripgrep |
| `codex-cli/scripts/build_npm_package.py` | 构建 | 将 rg 清单复制到 npm 包 |
| `codex-cli/bin/codex.js` | 运行时 | 将 rg 所在目录加入 PATH |

### 安装流程中的角色

```
install_native_deps.py 执行
    ↓
读取 codex-cli/bin/rg（本文件）
    ↓
解析 platforms 配置
    ↓
对每个目标平台：
    - 下载 providers[0].url
    - 验证 size 和 digest
    - 提取 path 指定的文件
    - 安装到 vendor/<target>/path/rg[.exe]
    ↓
rg 二进制就绪，可被 codex Rust 二进制调用
```

### 运行时路径

```
codex.js 启动时
    ↓
计算 vendorRoot/<target>/path/
    ↓
添加到 PATH 环境变量
    ↓
spawn codex 二进制
    ↓
codex (Rust) 可通过 PATH 调用 rg
```

## 依赖与外部交互

### 构建时依赖

| 依赖 | 用途 |
|------|------|
| `dotslash` CLI | 可选，用于直接执行清单文件 |
| `install_native_deps.py` | 主要消费者，解析清单并安装二进制 |
| GitHub Releases | 下载源（BurntSushi/ripgrep） |

### 运行时依赖

| 依赖 | 用途 |
|------|------|
| `codex.js` | 将 rg 目录加入 PATH |
| `codex` (Rust) | 调用 rg 进行代码搜索 |

### ripgrep 版本信息

- **版本**：15.1.0
- **发布日期**：2024 年左右（根据 GitHub Releases）
- **源码**：https://github.com/BurntSushi/ripgrep
- **许可证**：MIT/UNLICENSE（双许可）

### 网络依赖

```
下载 URL 模式：
https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-<target>.<format>

需要：
- DNS 解析 github.com
- HTTPS 连接
- 能够访问 GitHub Releases（某些地区可能需要代理）
```

## 风险、边界与改进建议

### 已知风险

1. **单点故障：GitHub Releases**
   - 所有下载源都指向 GitHub Releases
   - 如果 GitHub 不可用或被封锁，安装将失败
   - 建议：添加镜像源（如 npm CDN、S3 等）

2. **版本锁定风险**
   - 固定使用 ripgrep 15.1.0
   - 如果该版本有安全漏洞，需要手动更新清单
   - 建议：建立自动化更新流程

3. **哈希验证依赖**
   - 如果 BurntSushi 重新上传了相同版本的文件（罕见但可能），哈希会不匹配
   - 文件大小验证提供额外保护，但非加密安全

4. **平台覆盖不完整**
   - 不支持 32 位系统
   - 不支持某些 Linux 发行版（如 Alpine 以外的 musl 系统）
   - Android 被归入 Linux，但 ripgrep 的 Linux 构建可能不完全兼容

5. **下载超时**
   - `install_native_deps.py` 设置了 60 秒超时
   - 慢速网络环境下可能失败

### 边界条件

| 场景 | 行为 |
|------|------|
| 清单文件损坏/格式错误 | `dotslash parse` 或 Python JSON 解析报错 |
| 下载失败（网络问题） | 抛出 RuntimeError，提示下载失败 |
| 哈希不匹配 | 由 dotslash 或 Python 脚本检测并报错 |
| 文件大小不匹配 | 作为额外验证，可能警告或报错 |
| 压缩包内路径不存在 | 提取时抛出 KeyError/RuntimeError |

### 改进建议

1. **添加多镜像源支持**
   ```json
   {
     "providers": [
       { "url": "https://github.com/..." },
       { "url": "https://registry.npmjs.org/..." },
       { "url": "https://cdn.openai.com/..." }
     ]
   }
   ```

2. **自动化版本更新**
   - 创建 GitHub Action 监控 ripgrep 新版本
   - 自动更新清单中的版本号、URL、哈希值
   - 运行测试验证新版本兼容性

3. **支持更多平台**
   - 添加 FreeBSD 支持（如果需求存在）
   - 考虑为 Alpine Linux 提供特定构建

4. **改进错误处理**
   - 在 `install_native_deps.py` 中添加重试机制
   - 提供更详细的下载失败诊断信息
   - 支持离线模式（使用预下载的缓存）

5. **安全增强**
   - 考虑添加 GPG 签名验证（ripgrep 发布提供 .asc 文件）
   - 使用更严格的文件权限（当前设置为 0o755）

6. **文档改进**
   - 在清单文件顶部添加注释说明用途
   - 记录如何手动更新清单
   - 添加 ripgrep 功能说明（为什么 Codex 需要它）

7. **替代方案考虑**
   - 评估是否可以将 ripgrep 作为可选依赖
   - 考虑在 Codex Rust 二进制中内置搜索功能，减少外部依赖

### 维护检查清单

- [ ] 定期检查 ripgrep 新版本（https://github.com/BurntSushi/ripgrep/releases）
- [ ] 验证 GitHub Releases URL 仍然有效
- [ ] 测试所有 6 个平台的安装流程
- [ ] 确认哈希值与官方发布一致
