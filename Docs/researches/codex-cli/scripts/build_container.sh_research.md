# codex-cli/scripts/build_container.sh 研究文档

## 场景与职责

`build_container.sh` 是一个 Docker 镜像构建脚本，负责将 Codex CLI 打包为容器化交付物。该脚本服务于以下场景：

1. **本地容器化测试**: 开发者在本地快速构建可运行的 Codex 容器
2. **CI/CD 集成**: 作为自动化构建流水线的组成部分
3. **隔离环境部署**: 为需要网络沙箱隔离的场景提供基础镜像

脚本的核心职责是：
- 构建 TypeScript/JavaScript 源码（通过 pnpm）
- 生成 npm tarball（`codex.tgz`）
- 构建 Docker 镜像并标记为 `codex`

## 功能点目的

### 构建流程

脚本执行以下原子操作序列：

```
1. pnpm install    → 安装 Node.js 依赖
2. pnpm run build  → 编译 TypeScript 源码
3. pnpm pack       → 生成 npm tarball
4. docker build    → 构建容器镜像
```

### 输出产物

| 产物 | 位置 | 说明 |
|------|------|------|
| `codex.tgz` | `./dist/codex.tgz` | 标准化的 npm 包文件名 |
| Docker 镜像 | 本地镜像仓库，标签 `codex` | 基于 `codex-cli/Dockerfile` 构建 |

## 具体技术实现

### 脚本头与安全选项

```bash
#!/bin/bash
set -euo pipefail
```

- `-e`: 任何命令失败立即退出
- `-u`: 使用未定义变量时报错
- `-o pipefail`: 管道中任一命令失败即整体失败

### 目录导航机制

```bash
SCRIPT_DIR=$(realpath "$(dirname "$0")")
trap "popd >> /dev/null" EXIT
pushd "$SCRIPT_DIR/.." >> /dev/null
```

**设计要点**：
- 使用 `realpath` 解析脚本绝对路径，确保从任意位置调用都能正确定位
- `pushd`/`popd` 配合 `trap` 保证无论脚本如何退出都能恢复原始目录
- 标准错误重定向到 `/dev/null` 抑制 shell 的目录切换输出

### 构建步骤详解

#### 1. 依赖安装与构建
```bash
pnpm install
pnpm run build
```

- 使用 `pnpm` 而非 `npm`，与仓库的 `packageManager` 配置一致
- 构建产物通常输出到 `dist/` 目录（由 `package.json` 中的 build 脚本定义）

#### 2. 包打包与重命名
```bash
rm -rf ./dist/openai-codex-*.tgz
pnpm pack --pack-destination ./dist
mv ./dist/openai-codex-*.tgz ./dist/codex.tgz
```

**关键细节**：
- 先清理旧的 tarball 避免冲突
- `pnpm pack` 默认生成包含版本号的文件名（如 `openai-codex-0.1.0.tgz`）
- 重命名为固定的 `codex.tgz`，简化 Dockerfile 中的引用

#### 3. Docker 构建
```bash
docker build -t codex -f "./Dockerfile" .
```

- 显式指定 Dockerfile 路径（相对于工作目录 `codex-cli/`）
- 镜像标签固定为 `codex`（无版本号），适用于本地开发

## 关键代码路径与文件引用

### 上游调用方
- 开发者手动执行：`./scripts/build_container.sh`
- CI/CD 工作流（潜在）
- `run_in_container.sh`（间接，依赖生成的 `codex` 镜像）

### 下游依赖
- `codex-cli/Dockerfile`: 容器构建定义
- `codex-cli/package.json`: 定义 `build` 脚本和包元数据
- `codex-cli/dist/`: 构建输出目录

### Dockerfile 关键交互点

```dockerfile
# Dockerfile 中引用构建产物
COPY dist/codex.tgz codex.tgz
RUN npm install -g codex.tgz
```

Dockerfile 期望在构建上下文（`codex-cli/` 目录）中找到 `dist/codex.tgz`。

## 依赖与外部交互

### 外部工具依赖

| 工具 | 最低版本 | 用途 |
|------|----------|------|
| `bash` | 任意 | 脚本解释器 |
| `realpath` | GNU coreutils | 解析绝对路径 |
| `pnpm` | 10.29.3+ | 包管理和构建 |
| `docker` | 任意 | 容器构建 |

### 环境假设

1. **工作目录**: 脚本必须在仓库克隆后的环境中运行
2. **Docker 守护进程**: 本地或远程 Docker 环境已配置
3. **网络连接**: pnpm 安装需要访问 npm registry

### 文件系统依赖

```
codex-cli/
├── scripts/
│   └── build_container.sh   # 本脚本
├── package.json             # pnpm 配置和 build 脚本
├── Dockerfile               # 容器定义
└── dist/                    # 构建输出（运行时创建）
    └── codex.tgz            # 打包产物
```

## 风险、边界与改进建议

### 已知风险

1. **并发构建冲突**
   - `rm -rf ./dist/openai-codex-*.tgz` 会删除所有匹配的 tarball
   - 如果多个构建并发运行，可能导致竞争条件
   - **缓解**: 使用临时目录隔离构建

2. **Docker 镜像标签冲突**
   - 固定标签 `codex` 会被后续构建覆盖
   - 无版本号管理，难以追溯历史镜像
   - **建议**: 添加版本号标签选项

3. **构建缓存失效**
   - 每次运行都执行完整的 `pnpm install` 和 `build`
   - 无层缓存优化，CI 场景中效率较低

### 边界条件

| 场景 | 行为 |
|------|------|
| `pnpm install` 失败 | 脚本立即退出（`set -e`） |
| `dist/` 目录不存在 | `pnpm pack` 会自动创建 |
| Docker 守护进程未运行 | `docker build` 报错退出 |
| 从其他目录调用脚本 | 通过 `SCRIPT_DIR` 计算正确定位 |

### 改进建议

1. **版本标签支持**
   ```bash
   # 建议添加可选参数
   VERSION=${1:-latest}
   docker build -t "codex:${VERSION}" -f "./Dockerfile" .
   ```

2. **构建缓存优化**
   - 使用 Docker BuildKit 的层缓存
   - 分离依赖安装和源码构建阶段

3. **健康检查**
   ```bash
   # 构建后验证
   docker run --rm codex codex --version
   ```

4. **多平台构建支持**
   ```bash
   # 支持 buildx 多平台构建
   docker buildx build --platform linux/amd64,linux/arm64 -t codex .
   ```

5. **错误信息增强**
   - 添加前置条件检查（如 `command -v pnpm`）
   - 提供清晰的错误消息而非原始 shell 错误

### 与相关脚本的协同

该脚本与 `run_in_container.sh` 形成构建-运行闭环：

```
build_container.sh  →  生成 codex 镜像
       ↓
run_in_container.sh →  使用 codex 镜像运行命令
```

两者共享以下约定：
- 镜像名称：`codex`
- 工作目录挂载点：`/app<work_dir>`
- 环境变量传递：`OPENAI_API_KEY`
