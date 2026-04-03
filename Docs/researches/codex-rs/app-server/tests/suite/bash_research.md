# bash (DotSlash 配置) 研究文档

## 场景与职责

`bash` 文件是 Codex App Server 集成测试使用的 **DotSlash 配置文件**，用于在测试环境中提供预编译的 Bash Shell 二进制文件。该文件位于 `codex-rs/app-server/tests/suite/bash`，是一个可执行的 DotSlash 配置文件（使用 `#!/usr/bin/env dotslash` shebang）。

### 核心职责
1. **提供测试用 Bash 二进制**: 为 shell 执行流程的集成测试提供一致的 Bash 环境
2. **跨平台支持**: 支持 macOS (aarch64) 和 Linux (x86_64/aarch64) 三种平台
3. **版本锁定**: 通过 Blake3 哈希确保下载的二进制文件完整性
4. **自动获取**: 从 GitHub Releases 自动下载预构建的 shell-tool-mcp 包

---

## 功能点目的

### 1. DotSlash 配置结构

DotSlash 是 Meta 开发的工具，用于管理外部二进制依赖。该配置定义了：

| 字段 | 说明 |
|------|------|
| `name` | 二进制名称标识 (`codex-bash`) |
| `platforms` | 支持的平台配置映射 |
| `size` | 预期文件大小（字节） |
| `hash`/`digest` | Blake3 哈希校验 |
| `format` | 压缩格式 (`tar.gz`) |
| `path` | 在压缩包内的二进制路径 |
| `providers` | 下载源配置 |

### 2. 平台支持矩阵

| 平台 | 架构 | 路径（在 tar.gz 内） |
|------|------|---------------------|
| macOS | aarch64 | `package/vendor/aarch64-apple-darwin/bash/macos-15/bash` |
| Linux | x86_64 | `package/vendor/x86_64-unknown-linux-musl/bash/ubuntu-24.04/bash` |
| Linux | aarch64 | `package/vendor/aarch64-unknown-linux-musl/bash/ubuntu-24.04/bash` |

**注意**: Linux 路径中的 `musl` 是误导性的——Bash 二进制实际上链接的是 `glibc`，但 `codex-execve-wrapper` 链接的是 `musl`。

---

## 具体技术实现

### DotSlash 配置详解

```json
{
  "name": "codex-bash",
  "platforms": {
    "macos-aarch64": {
      "size": 37003612,           // 约 37MB
      "hash": "blake3",
      "digest": "d9cd5928c993b65c340507931c61c02bd6e9179933f8bf26a548482bb5fa53bb",
      "format": "tar.gz",
      "path": "package/vendor/aarch64-apple-darwin/bash/macos-15/bash",
      "providers": [
        {
          "url": "https://github.com/openai/codex/releases/download/rust-v0.65.0/codex-shell-tool-mcp-npm-0.65.0.tgz"
        },
        {
          "type": "github-release",
          "repo": "openai/codex",
          "tag": "rust-v0.65.0",
          "name": "codex-shell-tool-mcp-npm-0.65.0.tgz"
        }
      ]
    },
    // ... 其他平台类似
  }
}
```

### Provider 配置

每个平台配置了两个下载源：

1. **直接 URL**: 通过 `https://github.com/openai/codex/releases/download/...` 直接下载
2. **GitHub Release API**: 使用 GitHub Release 元数据 API 获取下载链接

这种双 provider 设计提供了冗余：
- 直接 URL 更快
- GitHub Release API 在 URL 变化时更稳定

### 来源说明

该 Bash 二进制是 **@openai/codex-shell-tool-mcp** npm 包的分支版本，包含：
- 经过修改的 Bash 源码
- 针对 Codex 使用场景的定制
- 预编译的多平台二进制

构建流程定义在 `.github/workflows/shell-tool-mcp.yml`。

---

## 关键代码路径与文件引用

### 本文件
| 文件 | 路径 | 说明 |
|------|------|------|
| bash | `codex-rs/app-server/tests/suite/bash` | DotSlash 配置文件（本文件） |

### 相关测试文件
| 文件 | 路径 | 说明 |
|------|------|------|
| turn_start_zsh_fork.rs | `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs` | 使用 zsh 的类似测试 |
| zsh | `codex-rs/app-server/tests/suite/zsh` | zsh 的 DotSlash 配置 |

### 构建与发布
| 文件 | 路径 | 说明 |
|------|------|------|
| shell-tool-mcp.yml | `.github/workflows/shell-tool-mcp.yml` | 构建 shell-tool-mcp 的 CI 工作流 |
| shell-tool-mcp/ | `shell-tool-mcp/` | Shell tool MCP 包源码 |

### 使用场景
| 文件 | 路径 | 说明 |
|------|------|------|
| core/tests/common/zsh_fork.rs | `codex-rs/core/tests/common/zsh_fork.rs` | core 测试中的 zsh fork 工具 |
| turn_start.rs | `codex-rs/app-server/tests/suite/v2/turn_start.rs` | 可能使用 bash 的测试 |

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 说明 |
|------|------|
| DotSlash | Meta 开发的二进制管理工具，需要预先安装 |
| GitHub Releases | 二进制分发源 |
| Blake3 | 哈希校验算法 |

### 使用流程

```
集成测试
    │
    ├─► 执行 ./bash (通过 dotslash)
    │       │
    │       ├─► 检测当前平台 (macos-aarch64 / linux-x86_64 / linux-aarch64)
    │       │
    │       ├─► 检查本地缓存 (~/.dotslash/...)
    │       │       ├─ 命中: 直接返回路径
    │       │       └─ 未命中: 继续下载
    │       │
    │       ├─► 从 GitHub Releases 下载 codex-shell-tool-mcp-npm-{version}.tgz
    │       │       ├─ 验证 size (37003612 bytes)
    │       │       └─ 验证 blake3 hash
    │       │
    │       ├─► 解压 tar.gz
    │       │
    │       └─► 返回二进制绝对路径
    │
    └─► 使用返回的 Bash 路径执行 shell 命令测试
```

### 环境要求

| 要求 | 说明 |
|------|------|
| DotSlash 安装 | `#!/usr/bin/env dotslash` 需要系统安装 DotSlash |
| 网络连接 | 首次使用需要下载 ~37MB 的 tar.gz 包 |
| 磁盘空间 | 缓存目录需要约 37MB 空间 |

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**: 首次运行测试需要下载 37MB 数据，在隔离环境会失败
2. **版本锁定**: 固定使用 rust-v0.65.0 版本，更新需要手动修改配置
3. **平台限制**: macOS x86_64 在 PR #7295 后被移除，仅支持 Apple Silicon
4. **哈希失效**: 如果 GitHub Release 被重新上传，Blake3 校验会失败

### 边界条件

| 边界场景 | 处理 |
|----------|------|
| 缓存命中 | DotSlash 自动使用本地缓存，无需下载 |
| 哈希不匹配 | DotSlash 报错，拒绝执行 |
| 平台不支持 | DotSlash 报错，提示不支持当前平台 |
| 网络超时 | 依赖 DotSlash 的重试逻辑 |

### 改进建议

1. **架构特定包** (TODO 已标注):
   ```json
   // 当前: 所有平台共享同一个 37MB tar.gz
   // 改进: 为每个架构单独发布，减少下载体积
   "macos-aarch64": {
     "size": 12000000,  // 预估 12MB
     "name": "codex-shell-tool-mcp-npm-0.65.0-macos-aarch64.tgz"
   }
   ```

2. **本地回退**: 添加本地系统 bash 作为回退选项
   ```json
   "providers": [
     { "type": "local", "path": "/bin/bash" },
     { "url": "..." }
   ]
   ```

3. **版本自动更新**: 通过 CI 自动更新到最新版本

4. **离线模式支持**: 在 CI 环境中预置缓存，避免运行时下载

### 相关配置对比

| 配置 | 版本 | 大小 | 用途 |
|------|------|------|------|
| bash | v0.65.0 | 37MB | Bash shell 测试 |
| zsh | v0.104.0 | 54MB | Zsh shell 测试 |

### 相关文档

- [DotSlash 官方文档](https://dotslash-cli.com/)
- [GitHub Releases - openai/codex](https://github.com/openai/codex/releases)
- [npm @openai/codex-shell-tool-mcp](https://www.npmjs.com/package/@openai/codex-shell-tool-mcp)
