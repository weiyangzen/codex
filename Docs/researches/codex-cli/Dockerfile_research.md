# codex-cli/Dockerfile 研究文档

## 场景与职责

`Dockerfile` 位于 `codex-cli/` 目录下，定义了 Codex CLI 的容器化运行环境。该镜像用于在 Linux 上提供安全的沙箱执行环境，是 Codex CLI 安全模型的重要组成部分。

根据 `codex-cli/README.md` 的安全模型说明：
> "Linux - there is no sandboxing by default. We recommend using Docker for sandboxing, where Codex launches itself inside a minimal container image..."

该 Dockerfile 构建的镜像通过以下方式提供安全保障：
1. 网络隔离（配合 `init_firewall.sh` 脚本）
2. 文件系统隔离（容器边界）
3. 非 root 用户运行

## 功能点目的

### 核心功能
1. **基础运行环境**：基于 Node.js 24 提供 JavaScript/TypeScript 运行环境
2. **开发工具链**：安装常用的开发工具（git、curl、jq、ripgrep 等）
3. **网络沙箱支持**：安装 iptables/ipset 等网络工具，支持防火墙规则
4. **安全运行**：使用非 root 用户执行 Codex CLI

### 目的详解

#### 1. 基础镜像选择
```dockerfile
FROM node:24-slim
```
- **Node 24**：较新的 LTS 版本，支持最新的 JavaScript 特性
- **slim 变体**：相比完整镜像更轻量，减少攻击面

#### 2. 时区配置
```dockerfile
ARG TZ
ENV TZ="$TZ"
```
- 允许构建时通过 `--build-arg` 指定时区
- 影响日志时间戳和定时任务行为

#### 3. 开发工具安装
安装的包可分为几类：

| 类别 | 包 | 用途 |
|------|-----|------|
| 网络工具 | curl, dnsutils, iproute2, ipset, iptables | 网络调试和防火墙 |
| 开发工具 | git, gh, jq, ripgrep, fzf | 代码检索和操作 |
| 安全/系统 | ca-certificates, gnupg2, procps, less, man-db | 基础系统功能 |
| 其他 | aggregate, unzip, zsh | 辅助工具 |

#### 4. 用户权限配置
```dockerfile
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node
USER node
```
- 创建全局 npm 安装目录并赋予 `node` 用户权限
- 后续操作以非 root 用户执行，遵循最小权限原则

#### 5. Codex CLI 安装
```dockerfile
COPY dist/codex.tgz codex.tgz
RUN npm install -g codex.tgz \
  && npm cache clean --force \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/node_modules/.cache \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/tests \
  && rm -rf /usr/local/share/npm-global/lib/node_modules/codex-cli/docs
```

关键步骤：
1. 从构建上下文复制打包好的 `.tgz` 文件
2. 全局安装 Codex CLI
3. 清理缓存和无用文件，减小镜像体积

#### 6. 沙箱环境标记
```dockerfile
ENV CODEX_UNSAFE_ALLOW_NO_SANDBOX=1
```
- 明确告知 Codex CLI 当前环境已足够隔离
- 允许在无额外沙箱的情况下运行

#### 7. 防火墙脚本配置
```dockerfile
USER root
COPY scripts/init_firewall.sh /usr/local/bin/
RUN chmod 500 /usr/local/bin/init_firewall.sh
USER node
```
- 以 root 身份复制防火墙初始化脚本
- 设置权限为 `500`（仅所有者可读可执行）
- 切回非 root 用户

## 具体技术实现

### 构建流程

完整的镜像构建由 `scripts/build_container.sh` 协调：

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(realpath "$(dirname "$0")")
trap "popd >> /dev/null" EXIT
pushd "$SCRIPT_DIR/.." >> /dev/null || {
  echo "Error: Failed to change directory to $SCRIPT_DIR/.."
  exit 1
}
pnpm install
pnpm run build
rm -rf ./dist/openai-codex-*.tgz
pnpm pack --pack-destination ./dist
mv ./dist/openai-codex-*.tgz ./dist/codex.tgz
docker build -t codex -f "./Dockerfile" .
```

### 运行时流程

镜像的运行时 orchestration 由 `scripts/run_in_container.sh` 处理：

```bash
# 1. 启动容器（后台运行）
docker run --name "$CONTAINER_NAME" -d \
  -e OPENAI_API_KEY \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$WORK_DIR:/app$WORK_DIR" \
  codex \
  sleep infinity

# 2. 配置允许访问的域名
docker exec --user root "$CONTAINER_NAME" bash -c "mkdir -p /etc/codex"
# ... 写入 allowed_domains.txt

# 3. 初始化防火墙
docker exec --user root "$CONTAINER_NAME" bash -c "/usr/local/bin/init_firewall.sh"

# 4. 删除防火墙脚本（安全清理）
docker exec --user root "$CONTAINER_NAME" bash -c "rm -f /usr/local/bin/init_firewall.sh"

# 5. 执行 Codex 命令
docker exec -it "$CONTAINER_NAME" bash -c "cd \"/app$WORK_DIR\" && codex --full-auto ${quoted_args}"
```

### 安全机制

#### 网络隔离
- 容器启动时添加 `NET_ADMIN` 和 `NET_RAW` 权限
- `init_firewall.sh` 配置 iptables/ipset 规则：
  - 默认拒绝所有出站连接
  - 仅允许访问 `api.openai.com`（或配置的允许域名）
  - 允许 DNS 查询（UDP 53）
  - 允许 localhost 通信

#### 文件系统隔离
- 工作目录以 volume 形式挂载到 `/app$WORK_DIR`
- 容器内仅能看到挂载的目录，无法访问主机其他文件

#### 用户权限
- 默认以 `node` 用户（非 root）运行 Codex CLI
- 仅防火墙配置阶段使用 root 权限

## 关键代码路径与文件引用

### 直接关联文件
| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-cli/.dockerignore` | 辅助 | 排除 `node_modules/` 等文件 |
| `codex-cli/scripts/build_container.sh` | 构建脚本 | 协调构建流程 |
| `codex-cli/scripts/run_in_container.sh` | 运行脚本 | 容器运行时 orchestration |
| `codex-cli/scripts/init_firewall.sh` | 运行时依赖 | 防火墙配置脚本 |
| `codex-cli/package.json` | 元数据 | 定义包信息和入口 |

### 依赖关系图
```
build_container.sh
    ├── pnpm install
    ├── pnpm run build
    ├── pnpm pack → dist/codex.tgz
    └── docker build (使用 Dockerfile)
            ├── FROM node:24-slim
            ├── COPY dist/codex.tgz
            ├── RUN npm install -g codex.tgz
            ├── COPY scripts/init_firewall.sh
            └── USER node

run_in_container.sh (运行时)
    ├── docker run (启动容器)
    ├── docker exec (配置防火墙)
    └── docker exec (运行 codex)
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 类型 | 说明 |
|------|------|------|
| `node:24-slim` | 基础镜像 | Node.js 运行时环境 |
| `dist/codex.tgz` | 构建产物 | 由 `pnpm pack` 生成的包 |
| `scripts/init_firewall.sh` | 运行时脚本 | 防火墙配置 |

### 运行时环境变量
| 变量 | 用途 |
|------|------|
| `OPENAI_API_KEY` | OpenAI API 认证 |
| `CODEX_UNSAFE_ALLOW_NO_SANDBOX=1` | 允许无额外沙箱运行 |
| `TZ` | 时区设置 |

### 端口和网络
- 无需暴露特定端口（CLI 工具）
- 网络访问通过 iptables 严格控制

## 风险、边界与改进建议

### 当前风险

1. **权限提升风险**
   - 容器启动时具有 `NET_ADMIN` 和 `NET_RAW` 能力
   - 如果容器逃逸，可能利用这些能力进行网络攻击

2. **防火墙脚本残留**
   - 虽然运行后会删除 `init_firewall.sh`，但在容器启动到删除之间存在窗口期
   - 如果容器在防火墙配置前被攻击，脚本可能被篡改

3. **单点故障**
   - 防火墙规则硬编码在 `init_firewall.sh` 中
   - DNS 解析失败会导致防火墙配置失败

4. **镜像体积**
   - 安装了较多开发工具（zsh、fzf、man-db 等）
   - 这些工具在生产环境可能不需要

### 边界情况

1. **DNS 解析依赖**
   - 防火墙配置需要解析域名到 IP
   - 如果 DNS 不可用，容器启动失败

2. **时区配置**
   - 如果构建时未提供 `TZ`，使用镜像默认值
   - 可能影响日志时间戳

3. **多平台支持**
   - 当前 Dockerfile 未使用多阶段构建或多平台指令
   - 跨平台构建需要 Buildx 支持

### 改进建议

#### 1. 安全加固
```dockerfile
# 添加健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f https://api.openai.com/v1/health || exit 1

# 只读根文件系统（需要调整部分路径）
# docker run 时添加 --read-only 和临时卷
```

#### 2. 多阶段构建优化
```dockerfile
# 构建阶段
FROM node:24-slim AS builder
COPY dist/codex.tgz .
RUN npm install -g codex.tgz

# 运行阶段（更轻量）
FROM node:24-alpine
COPY --from=builder /usr/local/share/npm-global /usr/local/share/npm-global
# ... 其他配置
```

#### 3. 防火墙脚本改进
- 将防火墙规则编译为二进制或嵌入镜像
- 使用 init 系统（如 tini）管理进程生命周期

#### 4. 镜像体积优化
```dockerfile
# 合并 RUN 指令减少层数
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 仅保留必要包
    ca-certificates curl iptables ipset \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
```

#### 5. 添加元数据标签
```dockerfile
LABEL org.opencontainers.image.title="Codex CLI"
LABEL org.opencontainers.image.description="OpenAI Codex CLI sandbox environment"
LABEL org.opencontainers.image.source="https://github.com/openai/codex"
```

### 监控和可观测性建议
- 添加结构化日志输出
- 集成 OpenTelemetry 追踪（如果 Codex CLI 支持）
- 暴露 metrics 端点供 Prometheus 抓取
