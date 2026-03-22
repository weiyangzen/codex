# codex-cli/scripts/run_in_container.sh 研究文档

## 场景与职责

`run_in_container.sh` 是 Codex CLI 的**容器化执行入口**，为本地开发提供安全的沙箱环境来运行 AI 代码生成任务。该脚本服务于以下核心场景：

1. **安全隔离执行**: 在用户工作目录的副本上运行 Codex，防止 AI 生成代码直接影响主机
2. **网络沙箱**: 通过防火墙限制容器只能访问 OpenAI API
3. **多项目支持**: 基于工作目录路径生成唯一容器名，支持同时运行多个隔离实例
4. **一键体验**: 隐藏 Docker 复杂性，提供简单的命令行接口

脚本的核心职责：
- 管理容器生命周期（创建、配置、执行、清理）
- 配置网络防火墙（通过调用 `init_firewall.sh`）
- 安全传递环境变量和命令参数
- 确保容器退出后资源完全释放

## 功能点目的

### 执行流程

```
1. 解析参数（--work_dir 和命令）
2. 生成唯一容器名
3. 清理已存在的同名容器
4. 启动容器（后台运行 sleep infinity）
5. 写入允许域名配置
6. 执行防火墙初始化
7. 删除防火墙脚本
8. 执行用户命令
9. 退出时清理容器（trap EXIT）
```

### 安全边界

| 边界 | 实现方式 |
|------|----------|
| 文件系统隔离 | 工作目录挂载到容器内 `/app<work_dir>` |
| 网络隔离 | iptables + ipset 白名单，仅允许指定域名 |
| 权限隔离 | 容器内以非 root 用户运行（Dockerfile 中 USER node） |
| 资源清理 | `trap cleanup EXIT` 确保容器删除 |

## 具体技术实现

### 脚本头与选项

```bash
#!/bin/bash
set -e
```

- `-e`: 命令失败立即退出
- 注意：未使用 `-u`（未定义变量报错），因为某些环境变量可能可选

### 参数解析

```bash
# 默认值
WORK_DIR="${WORKSPACE_ROOT_DIR:-$(pwd)}"
OPENAI_ALLOWED_DOMAINS="${OPENAI_ALLOWED_DOMAINS:-api.openai.com}"

# 可选的 --work_dir 标志
if [ "$1" = "--work_dir" ]; then
    WORK_DIR="$2"
    shift 2
fi
```

**设计要点**：
- 支持环境变量和命令行参数两种方式指定工作目录
- 域名白名单可通过环境变量自定义，默认仅 OpenAI API

### 容器命名策略

```bash
CONTAINER_NAME="codex_$(echo "$WORK_DIR" | sed 's/\//_/g' | sed 's/[^a-zA-Z0-9_-]//g')"
```

**转换规则**：
1. 将路径分隔符 `/` 替换为 `_`
2. 移除所有非字母数字、下划线、连字符字符

**示例**：
- `/home/user/project` → `codex_home_user_project`
- `/path/with spaces` → `codex_pathwith_spaces`

**优势**：
- 基于路径的唯一性，同一目录总是使用同一容器名
- 清理时自动终止已存在的容器，避免冲突

### 生命周期管理

#### 清理函数
```bash
cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
```

**双重保障**：
1. 脚本开始时调用 `cleanup` 终止已存在的同名容器
2. `trap EXIT` 确保无论脚本如何退出（正常、错误、信号）都会清理

#### 容器启动
```bash
docker run --name "$CONTAINER_NAME" -d \
  -e OPENAI_API_KEY \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$WORK_DIR:/app$WORK_DIR" \
  codex \
  sleep infinity
```

**关键配置**：

| 选项 | 说明 |
|------|------|
| `-d` | 后台运行 |
| `-e OPENAI_API_KEY` | 传递 API 密钥（值从主机环境获取）|
| `--cap-add=NET_ADMIN` | 允许修改网络配置（防火墙需要）|
| `--cap-add=NET_RAW` | 允许原始套接字 |
| `-v "$WORK_DIR:/app$WORK_DIR"` | 挂载工作目录到容器内相同路径（前缀 `/app`）|
| `sleep infinity` | 保持容器运行，后续通过 `docker exec` 执行命令 |

### 防火墙配置

#### 1. 写入域名白名单 (行 69-77)
```bash
docker exec --user root "$CONTAINER_NAME" bash -c "mkdir -p /etc/codex"
for domain in $OPENAI_ALLOWED_DOMAINS; do
  # 域名格式验证
  if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Error: Invalid domain format: $domain"
    exit 1
  fi
  echo "$domain" | docker exec --user root -i "$CONTAINER_NAME" bash -c "cat >> /etc/codex/allowed_domains.txt"
done
```

**安全细节**：
- 使用正则表达式验证域名格式，防止命令注入
- 通过管道和 `-i` 选项安全传递数据到容器

#### 2. 设置文件权限 (行 80)
```bash
docker exec --user root "$CONTAINER_NAME" bash -c \
  "chmod 444 /etc/codex/allowed_domains.txt && chown root:root /etc/codex/allowed_domains.txt"
```

**权限设计**：
- `444`: 只读，防止运行时修改
- `root:root`: 确保只有 root 可修改（虽然已只读）

#### 3. 执行防火墙初始化 (行 83-86)
```bash
docker exec --user root "$CONTAINER_NAME" bash -c "/usr/local/bin/init_firewall.sh"
docker exec --user root "$CONTAINER_NAME" bash -c "rm -f /usr/local/bin/init_firewall.sh"
```

**安全清理**：防火墙脚本执行后立即删除，减少攻击面。

### 命令执行

```bash
quoted_args=""
for arg in "$@"; do
  quoted_args+=" $(printf '%q' "$arg")"
done
docker exec -it "$CONTAINER_NAME" bash -c "cd \"/app$WORK_DIR\" && codex --full-auto ${quoted_args}"
```

**参数处理**：
- 使用 `printf '%q'` 对参数进行 shell 转义，防止注入攻击
- 在容器内切换到工作目录的挂载点 `/app$WORK_DIR`
- 自动添加 `--full-auto` 标志（非交互模式）

**交互性**：`-it` 选项分配伪终端并保持 STDIN 打开，支持交互式命令。

## 关键代码路径与文件引用

### 上游调用方

- **开发者手动执行**:
  ```bash
  ./run_in_container.sh --work_dir /path/to/project "ls -la"
  ./run_in_container.sh "echo Hello"
  ```

- **IDE 集成**（潜在）

### 下游依赖

| 文件 | 关系 | 用途 |
|------|------|------|
| `codex-cli/Dockerfile` | 构建依赖 | 定义 `codex` 镜像 |
| `codex-cli/scripts/init_firewall.sh` | 运行时依赖 | 容器内防火墙初始化 |
| `codex-cli/scripts/build_container.sh` | 前置依赖 | 构建 `codex` 镜像 |

### 镜像依赖

脚本依赖名为 `codex` 的本地 Docker 镜像，该镜像必须：
- 包含 `codex` 命令（Codex CLI）
- 包含 `/usr/local/bin/init_firewall.sh`
- 支持 `sleep infinity` 作为保持运行的命令
- 具有 `NET_ADMIN` 和 `NET_RAW` 能力

## 依赖与外部交互

### 外部工具依赖

| 工具 | 用途 |
|------|------|
| `docker` | 容器管理（run, exec, rm）|
| `realpath` | 解析工作目录绝对路径 |
| `sed` | 容器名生成时的字符串处理 |

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WORKSPACE_ROOT_DIR` | `$(pwd)` | 工作目录（环境变量方式）|
| `OPENAI_ALLOWED_DOMAINS` | `api.openai.com` | 允许的出站域名列表 |
| `OPENAI_API_KEY` | 无 | OpenAI API 密钥（传递给容器）|

### 网络假设

- Docker 守护进程可访问
- 容器能够解析 DNS（用于防火墙初始化时的域名解析）
- 宿主机能够访问 Docker 网络（用于验证防火墙）

## 风险、边界与改进建议

### 已知风险

1. **容器名冲突**
   - 不同路径可能生成相同容器名（如 `/a-b` 和 `/a_b` 都变为 `codex_a_b`）
   - **影响**：后启动的实例会终止先启动的实例
   - **缓解**：使用更复杂的编码（如 base64）或添加随机后缀

2. **域名注入风险**
   - 虽然已验证域名格式，但 `OPENAI_ALLOWED_DOMAINS` 是空格分隔的字符串
   - 如果域名本身包含空格（虽然不符合 RFC），可能导致解析错误

3. **API 密钥泄露**
   - `OPENAI_API_KEY` 通过环境变量传递给容器
   - 容器内任何进程都可读取该变量
   - **缓解**：这是 Docker 的标准做法，依赖镜像的可信性

4. **防火墙绕过风险**
   - 容器具有 `NET_ADMIN` 能力，容器内 root 用户可以修改防火墙规则
   - **缓解**：防火墙初始化后，Codex 以非 root 用户运行

5. **资源泄漏**
   - 如果脚本被 SIGKILL 终止，`trap EXIT` 不会执行
   - **缓解**：下次运行同一工作目录时会清理旧容器

### 边界条件

| 场景 | 行为 |
|------|------|
| 未提供命令 | 显示用法并退出 |
| `WORK_DIR` 为空 | 错误退出 |
| `OPENAI_ALLOWED_DOMAINS` 为空 | 错误退出 |
| 域名格式无效 | 错误退出 |
| Docker 未运行 | `docker run` 失败，脚本退出 |
| `codex` 镜像不存在 | `docker run` 失败，脚本退出 |
| 容器启动失败 | 后续命令失败，脚本退出 |
| 防火墙初始化失败 | 错误信息，脚本退出（因为 `set -e`）|
| 用户命令失败 | 脚本退出，容器被清理 |

### 改进建议

1. **容器名唯一性增强**
   ```bash
   # 使用路径哈希确保唯一性
   PATH_HASH=$(echo -n "$WORK_DIR" | sha256sum | cut -c1-8)
   CONTAINER_NAME="codex_${PATH_HASH}"
   ```

2. **配置文件支持**
   ```bash
   # 支持 .codexrc 或类似配置文件
   if [ -f "$WORK_DIR/.codexrc" ]; then
       source "$WORK_DIR/.codexrc"
   fi
   ```

3. **状态检查**
   ```bash
   # 检查容器健康状态后再执行命令
   if ! docker exec "$CONTAINER_NAME" pgrep sleep >/dev/null; then
       echo "Error: Container not healthy"
       exit 1
   fi
   ```

4. **日志收集**
   ```bash
   # 捕获并显示防火墙初始化日志
   docker exec --user root "$CONTAINER_NAME" bash -c "/usr/local/bin/init_firewall.sh" 2>&1 | tee /tmp/codex-firewall.log
   ```

5. **交互模式支持**
   ```bash
   # 检测是否运行在交互式终端
   if [ -t 0 ]; then
       DOCKER_EXEC_FLAGS="-it"
   else
       DOCKER_EXEC_FLAGS=""
   fi
   ```

6. **挂载选项优化**
   ```bash
   # 只读挂载，防止容器修改主机文件
   -v "$WORK_DIR:/app$WORK_DIR:ro"
   
   # 或使用 overlay 实现写时复制
   ```

7. **超时控制**
   ```bash
   # 为命令执行添加超时
   timeout 3600 docker exec ...
   ```

8. **信号转发**
   ```bash
   # 更好地处理 Ctrl-C
   trap 'cleanup; exit 130' INT
   ```

### 与相关脚本的协同

```
build_container.sh      # 构建 codex 镜像
        ↓
run_in_container.sh     # 使用 codex 镜像运行命令
        ↓
init_firewall.sh        # 在容器内初始化防火墙
```

**关键约定**：
- 镜像名称：`codex`
- 挂载点前缀：`/app`
- 防火墙脚本路径：`/usr/local/bin/init_firewall.sh`
- 域名配置路径：`/etc/codex/allowed_domains.txt`

### 架构设计考量

1. **为什么使用 `sleep infinity` + `docker exec` 而非直接运行？**
   - 需要在执行用户命令前完成防火墙初始化
   - 允许分离容器启动、配置、执行三个阶段
   - 便于调试（可以 `docker exec` 进入运行中的容器）

2. **为什么挂载到 `/app$WORK_DIR` 而非固定路径？**
   - 保持容器内路径与主机路径一致，便于错误报告和调试
   - 某些工具依赖绝对路径（如 source map）

3. **为什么传递 `--full-auto`？**
   - 容器环境通常是非交互式的
   - 确保 Codex 不会等待用户输入
