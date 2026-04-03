# zsh (DotSlash 配置) 研究文档

## 场景与职责

`zsh` 文件是 Codex App Server 集成测试使用的 **DotSlash 配置文件**，用于在测试环境中提供预编译的 Zsh Shell 二进制文件。该文件位于 `codex-rs/app-server/tests/suite/zsh`，是一个可执行的 DotSlash 配置文件（使用 `#!/usr/bin/env dotslash` shebang）。

与 `bash` 配置类似，但 `zsh` 配置指向更新的版本（v0.104.0 vs v0.65.0），用于测试需要 Zsh 特定行为的场景（如 `turn_start_zsh_fork.rs` 测试）。

### 核心职责
1. **提供测试用 Zsh 二进制**: 为 Zsh shell 执行流程的集成测试提供一致的 Zsh 环境
2. **跨平台支持**: 支持 macOS (aarch64) 和 Linux (x86_64/aarch64) 三种平台
3. **版本锁定**: 通过 Blake3 哈希确保下载的二进制文件完整性
4. **自动获取**: 从 GitHub Releases 自动下载预构建的 shell-tool-mcp 包

---

## 功能点目的

### 1. DotSlash 配置结构

| 字段 | 说明 |
|------|------|
| `name` | 二进制名称标识 (`codex-zsh`) |
| `platforms` | 支持的平台配置映射 |
| `size` | 预期文件大小（字节） |
| `hash`/`digest` | Blake3 哈希校验 |
| `format` | 压缩格式 (`tar.gz`) |
| `path` | 在压缩包内的二进制路径 |
| `providers` | 下载源配置 |

### 2. 平台支持矩阵

| 平台 | 架构 | 路径（在 tar.gz 内） |
|------|------|---------------------|
| macOS | aarch64 | `package/vendor/aarch64-apple-darwin/zsh/macos-15/zsh` |
| Linux | x86_64 | `package/vendor/x86_64-unknown-linux-musl/zsh/ubuntu-24.04/zsh` |
| Linux | aarch64 | `package/vendor/aarch64-unknown-linux-musl/zsh/ubuntu-24.04/zsh` |

**注意**: Linux 路径中的 `musl` 是误导性的——Zsh 二进制实际上链接的是 `glibc`，但 `codex-execve-wrapper` 链接的是 `musl`。

---

## 具体技术实现

### DotSlash 配置详解

```json
{
  "name": "codex-zsh",
  "platforms": {
    "macos-aarch64": {
      "size": 53771483,           // 约 54MB
      "hash": "blake3",
      "digest": "ff664f63f5e1fa62762c9aff0aafa66cf196faf9b157f98ec98f59c152fc7bd3",
      "format": "tar.gz",
      "path": "package/vendor/aarch64-apple-darwin/zsh/macos-15/zsh",
      "providers": [
        {
          "url": "https://github.com/openai/codex/releases/download/rust-v0.104.0/codex-shell-tool-mcp-npm-0.104.0.tgz"
        },
        {
          "type": "github-release",
          "repo": "openai/codex",
          "tag": "rust-v0.104.0",
          "name": "codex-shell-tool-mcp-npm-0.104.0.tgz"
        }
      ]
    },
    // ... 其他平台类似
  }
}
```

### 版本对比

| 配置 | 版本 | 大小 | 哈希 |
|------|------|------|------|
| bash | v0.65.0 | 37MB | `d9cd5928c993b65c340507931c61c02bd6e9179933f8bf26a548482bb5fa53bb` |
| zsh | v0.104.0 | 54MB | `ff664f63f5e1fa62762c9aff0aafa66cf196faf9b157f98ec98f59c152fc7bd3` |

**观察**: 
- Zsh 版本（v0.104.0）比 Bash 版本（v0.65.0）更新
- Zsh 包比 Bash 包大约 45%（54MB vs 37MB）
- 两个配置使用相同的 Blake3 哈希值（可能来自相同的构建流程）

### Provider 配置

每个平台配置了两个下载源：

1. **直接 URL**: 通过 `https://github.com/openai/codex/releases/download/...` 直接下载
2. **GitHub Release API**: 使用 GitHub Release 元数据 API 获取下载链接

### 来源说明

该 Zsh 二进制是 **@openai/codex-shell-tool-mcp** npm 包的分支版本，由 `.github/workflows/shell-tool-mcp.yml` 构建。这是一个经过修改的 Zsh 版本，可能包含：
- 针对 Codex 使用场景的定制
- 改进的脚本执行安全性
- 额外的钩子或监控功能

---

## 关键代码路径与文件引用

### 本文件
| 文件 | 路径 | 说明 |
|------|------|------|
| zsh | `codex-rs/app-server/tests/suite/zsh` | DotSlash 配置文件（本文件） |

### 相关测试文件
| 文件 | 路径 | 说明 |
|------|------|------|
| turn_start_zsh_fork.rs | `codex-rs/app-server/tests/suite/v2/turn_start_zsh_fork.rs` | 使用此 Zsh 的测试 |
| bash | `codex-rs/app-server/tests/suite/bash` | Bash 的 DotSlash 配置 |

### 构建与发布
| 文件 | 路径 | 说明 |
|------|------|------|
| shell-tool-mcp.yml | `.github/workflows/shell-tool-mcp.yml` | 构建 shell-tool-mcp 的 CI 工作流 |
| shell-tool-mcp/ | `shell-tool-mcp/` | Shell tool MCP 包源码 |

### 使用场景
| 文件 | 路径 | 说明 |
|------|------|------|
| zsh_fork.rs | `codex-rs/core/tests/common/zsh_fork.rs` | core 测试中的 zsh fork 工具 |

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
集成测试 (如 turn_start_zsh_fork.rs)
    │
    ├─► 执行 ./zsh (通过 dotslash)
    │       │
    │       ├─► 检测当前平台 (macos-aarch64 / linux-x86_64 / linux-aarch64)
    │       │
    │       ├─► 检查本地缓存 (~/.dotslash/...)
    │       │       ├─ 命中: 直接返回路径
    │       │       └─ 未命中: 继续下载
    │       │
    │       ├─► 从 GitHub Releases 下载 codex-shell-tool-mcp-npm-0.104.0.tgz
    │       │       ├─ 验证 size (53771483 bytes)
    │       │       └─ 验证 blake3 hash
    │       │
    │       ├─► 解压 tar.gz
    │       │
    │       └─► 返回二进制绝对路径
    │
    └─► 使用返回的 Zsh 路径执行 shell 命令测试
```

### 环境要求

| 要求 | 说明 |
|------|------|
| DotSlash 安装 | `#!/usr/bin/env dotslash` 需要系统安装 DotSlash |
| 网络连接 | 首次使用需要下载 ~54MB 的 tar.gz 包 |
| 磁盘空间 | 缓存目录需要约 54MB 空间 |

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**: 首次运行测试需要下载 54MB 数据，在隔离环境会失败
2. **版本碎片化**: Bash 使用 v0.65.0，Zsh 使用 v0.104.0，版本不一致可能导致行为差异
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

1. **版本统一**: 考虑将 Bash 和 Zsh 更新到相同版本，减少维护成本

2. **架构特定包** (TODO 已标注):
   ```json
   // 当前: 所有平台共享同一个 54MB tar.gz
   // 改进: 为每个架构单独发布，减少下载体积
   "macos-aarch64": {
     "size": 18000000,  // 预估 18MB
     "name": "codex-shell-tool-mcp-npm-0.104.0-macos-aarch64.tgz"
   }
   ```

3. **本地回退**: 添加本地系统 zsh 作为回退选项
   ```json
   "providers": [
     { "type": "local", "path": "/bin/zsh" },
     { "url": "..." }
   ]
   ```

4. **版本自动同步**: 通过 CI 自动更新到最新版本，保持 Bash 和 Zsh 版本一致

5. **离线模式支持**: 在 CI 环境中预置缓存，避免运行时下载

### 与 Bash 配置的对比

| 特性 | Bash | Zsh |
|------|------|-----|
| 版本 | v0.65.0 | v0.104.0 |
| 大小 | 37MB | 54MB |
| 用途 | 通用 shell 测试 | Zsh 特定功能测试 |
| 更新频率 | 较低 | 较高 |

### 相关文档

- [DotSlash 官方文档](https://dotslash-cli.com/)
- [GitHub Releases - openai/codex](https://github.com/openai/codex/releases)
- [npm @openai/codex-shell-tool-mcp](https://www.npmjs.com/package/@openai/codex-shell-tool-mcp)
- [Zsh 官方网站](https://www.zsh.org/)

### 测试使用示例

```rust
// turn_start_zsh_fork.rs 中的典型用法

let zsh_path = std::process::Command::new("./zsh")
    .current_dir(test_dir)
    .output()
    .expect("zsh dotslash config should resolve");

// 使用获取到的 zsh 路径执行测试
let mut cmd = std::process::Command::new(&zsh_path);
cmd.arg("-c").arg("echo $ZSH_VERSION");
```
