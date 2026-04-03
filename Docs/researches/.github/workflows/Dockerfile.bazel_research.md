# Dockerfile.bazel 研究文档

## 场景与职责

本 Dockerfile 用于构建 Bazel CI 的自定义 Docker 镜像，为 GitHub Actions 的 Bazel 构建工作流提供标准化的构建环境。该镜像基于 Ubuntu 24.04，预装了 Bazel 构建所需的基础工具链，包括 Node.js、Git、Python3 和 DotSlash。

## 功能点目的

1. **标准化构建环境**：确保所有 Bazel 构建在一致的 Ubuntu 24.04 环境中执行
2. **Node.js 运行时支持**：安装指定版本的 Node.js（从 `codex-rs/node-version.txt` 读取），用于运行 js_repl 测试
3. **DotSlash 工具集成**：安装 Facebook 的 DotSlash 工具，用于管理外部依赖的二进制文件
4. **多架构支持**：通过 `dpkg --print-architecture` 自动检测 amd64/arm64 架构并下载对应 Node.js 二进制包

## 具体技术实现

### 基础镜像与依赖安装
```dockerfile
FROM ubuntu:24.04
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl git python3 ca-certificates xz-utils
```
- 使用最小化安装 (`--no-install-recommends`) 减小镜像体积
- 核心依赖：curl（下载）、git（版本控制）、python3（脚本）、ca-certificates（HTTPS）、xz-utils（解压）

### Node.js 多架构安装逻辑
```dockerfile
COPY codex-rs/node-version.txt /tmp/node-version.txt
RUN set -eux; \
    node_arch="$(dpkg --print-architecture)"; \
    case "${node_arch}" in \
      amd64) node_dist_arch="x64" ;; \
      arm64) node_dist_arch="arm64" ;; \
      *) echo "unsupported architecture: ${node_arch}"; exit 1 ;; \
    esac; \
    node_version="$(tr -d '[:space:]' </tmp/node-version.txt)"; \
    curl -fsSLO "https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-${node_dist_arch}.tar.xz"; \
    tar -xJf "node-v${node_version}-linux-${node_dist_arch}.tar.xz" -C /usr/local --strip-components=1
```
- 动态架构检测：将 Debian 架构名 (amd64/arm64) 映射到 Node.js 发布包架构名 (x64/arm64)
- 版本外置：从 `codex-rs/node-version.txt` 读取版本号（当前为 22.22.0），便于统一升级
- 官方源下载：直接从 nodejs.org 官方 CDN 下载预编译二进制包

### DotSlash 安装
```dockerfile
RUN curl -LSfs "https://github.com/facebook/dotslash/releases/download/v0.5.8/dotslash-ubuntu-22.04.$(uname -m).tar.gz" | tar fxz - -C /usr/local/bin
```
- 版本：v0.5.8
- 安装位置：`/usr/local/bin`（全局可访问）
- DotSlash 是 Meta 开发的工具，用于通过内容寻址方式管理外部二进制依赖

### 用户与工作目录配置
```dockerfile
USER ubuntu
WORKDIR /workspace
```
- 使用 Ubuntu 24.04 预创建的 `ubuntu` 用户（UID 1000）运行，遵循最小权限原则
- 设置工作目录为 `/workspace`

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `codex-rs/node-version.txt` | 定义 Node.js 版本号（22.22.0） |
| `.github/workflows/bazel.yml` | 使用该 Dockerfile 的 CI 工作流 |
| `https://github.com/facebook/dotslash` | DotSlash 工具上游仓库 |

## 依赖与外部交互

### 外部依赖
1. **Ubuntu 24.04 基础镜像**：提供基础操作系统环境
2. **Node.js 官方发布包**：https://nodejs.org/dist/
3. **DotSlash GitHub Releases**：https://github.com/facebook/dotslash/releases

### 被依赖方
- `.github/workflows/bazel.yml`：通过 `container` 指令或 `docker build` 使用该镜像

## 风险、边界与改进建议

### 风险
1. **架构支持限制**：仅支持 amd64 和 arm64，其他架构会直接退出
2. **Node.js 版本硬编码路径**：版本号依赖外部文件，如果文件不存在或格式错误会导致构建失败
3. **DotSlash 版本固定**：使用固定版本 v0.5.8，需要手动更新以获取安全补丁
4. **镜像发布位置**：注释提到当前发布到个人 Docker Hub 账号 (`docker.io/mbolin491/codex-bazel`)，需要迁移到官方位置

### 边界条件
- 构建时需要访问外部网络下载 Node.js 和 DotSlash
- 多平台构建需要 `docker buildx` 支持
- 镜像体积受 Node.js 二进制包大小影响

### 改进建议
1. **镜像发布迁移**：按 TODO 注释建议，将镜像发布从个人账号迁移到 OpenAI 官方 Docker Hub 组织
2. **版本参数化**：通过构建参数 (`ARG`) 允许在构建时覆盖 DotSlash 版本
3. **健康检查**：添加 `HEALTHCHECK` 指令验证 Node.js 和 DotSlash 可用性
4. **缓存优化**：利用 Docker 层缓存，将不常变更的依赖安装放在前面
5. **安全加固**：考虑使用 distroless 或更小的基础镜像减少攻击面
