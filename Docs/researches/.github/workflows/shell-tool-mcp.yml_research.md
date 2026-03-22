# shell-tool-mcp.yml 深度研究文档

## 场景与职责

`shell-tool-mcp.yml` 是 OpenAI Codex 项目的 **Shell Tool MCP 发布工作流**，负责构建和发布 `@openai/codex-shell-tool-mcp` npm 包。该包包含经过补丁修改的 Bash 和 zsh 二进制文件，用于在沙箱环境中执行 shell 命令。

### 触发条件
- **workflow_call**: 由 `rust-release.yml` 调用触发
- **输入参数**:
  - `release-version`: 发布版本号
  - `release-tag`: Git 标签名
  - `publish`: 是否发布到 npm (默认 true)

### 核心职责
1. **多平台 Bash 构建**: 在 Linux (多发行版) 和 macOS 上编译补丁版 Bash
2. **多平台 zsh 构建**: 在 Linux (多发行版) 和 macOS 上编译补丁版 zsh
3. **制品打包**: 将二进制文件打包为 npm 包
4. **npm 发布**: 发布到 npm registry

---

## 功能点目的

### 1. 多发行版 Linux 支持
**目的**: 确保 Bash/zsh 在不同 glibc 版本上兼容运行

| 变体 | 目标架构 | 容器镜像 |
|------|----------|----------|
| ubuntu-24.04 | x86_64/aarch64 | ubuntu:24.04 / arm64v8/ubuntu:24.04 |
| ubuntu-22.04 | x86_64/aarch64 | ubuntu:22.04 / arm64v8/ubuntu:22.04 |
| ubuntu-20.04 | aarch64 | arm64v8/ubuntu:20.04 |
| debian-12 | x86_64/aarch64 | debian:12 / arm64v8/debian:12 |
| debian-11 | x86_64/aarch64 | debian:11 / arm64v8/debian:11 |
| centos-9 | x86_64/aarch64 | quay.io/centos/centos:stream9 |

### 2. macOS 版本支持
| 变体 | 目标架构 | 运行器 |
|------|----------|--------|
| macos-15 | aarch64 | macos-15-xlarge |
| macos-14 | aarch64 | macos-14 |

### 3. EXEC_WRAPPER 补丁机制
**目的**: 拦截 `execve` 系统调用，实现命令执行控制

**Bash 补丁** (`shell-tool-mcp/patches/bash-exec-wrapper.patch`):
```c
char* exec_wrapper = getenv("EXEC_WRAPPER");
if (exec_wrapper && *exec_wrapper && !whitespace (*exec_wrapper))
{
    // 将原始命令和参数包装到 EXEC_WRAPPER 中
    args[0] = exec_wrapper;
    args[1] = orig_command;
    command = exec_wrapper;
}
```

**zsh 补丁** (`shell-tool-mcp/patches/zsh-exec-wrapper.patch`):
```c
if ((exec_wrapper = getenv("EXEC_WRAPPER")) &&
    *exec_wrapper && !inblank(*exec_wrapper)) {
    exec_argv = argv - 2;
    exec_argv[0] = exec_wrapper;
    exec_argv[1] = orig_pth;
    pth = exec_wrapper;
}
```

### 4. 版本计算逻辑
```bash
# 从输入或 GITHUB_REF_NAME 提取版本
if [[ -z "$version" ]]; then
    if [[ "$release_tag" =~ ^rust-v.+ ]]; then
        version="${release_tag#rust-v}"
    elif [[ "${GITHUB_REF_NAME:-}" =~ ^rust-v.+ ]]; then
        version="${GITHUB_REF_NAME#rust-v}"
    fi
fi

# 发布决策
if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    should_publish="true"      # 稳定版
elif [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]; then
    should_publish="true"      # Alpha 预发布
    npm_tag="alpha"
fi
```

---

## 具体技术实现

### 关键流程

#### Bash 构建流程 (Linux)
```yaml
1. 安装构建依赖 (git, build-essential, bison, autoconf, gettext, libncursesw5-dev)
2. 克隆 Bash 源码 (git.savannah.gnu.org)
3. 检出特定 commit: a8a1c2fac029404d3f42cd39f5a20f24b6e4fe4b
4. 应用补丁: bash-exec-wrapper.patch
5. 配置: ./configure --without-bash-malloc
6. 编译: make -j$(nproc)
7. 复制二进制到 artifacts/vendor/<target>/bash/<variant>/
```

#### zsh 构建流程 (Linux)
```yaml
1. 安装构建依赖 (同上)
2. 克隆 zsh 源码 (git.code.sf.net)
3. 检出特定 commit: 77045ef899e53b9598bebc5a41db93a548a40ca6
4. 应用补丁: zsh-exec-wrapper.patch
5. 预配置: ./Util/preconfig
6. 配置: ./configure
7. 编译: make -j$(nproc)
8. 复制二进制到 artifacts/vendor/<target>/zsh/<variant>/
9. 烟雾测试: 验证 EXEC_WRAPPER 功能
```

#### 烟雾测试实现
```bash
# 创建测试 wrapper 脚本
cat > "$tmpdir/exec-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${CODEX_WRAPPER_LOG:?missing CODEX_WRAPPER_LOG}"
printf '%s\n' "$@" > "$CODEX_WRAPPER_LOG"
file="$1"
shift
if [[ "$#" -eq 0 ]]; then
    exec "$file"
fi
arg0="$1"
shift
exec -a "$arg0" "$file" "$@"
EOF
chmod +x "$tmpdir/exec-wrapper"

# 运行测试
CODEX_WRAPPER_LOG="$tmpdir/wrapper.log" \
EXEC_WRAPPER="$tmpdir/exec-wrapper" \
/tmp/zsh/Src/zsh -fc '/bin/echo smoke-zsh' > "$tmpdir/stdout.txt"

# 验证输出
grep -Fx "smoke-zsh" "$tmpdir/stdout.txt"
grep -Fx "/bin/echo" "$tmpdir/wrapper.log"
```

#### 打包流程
```yaml
1. 下载所有构建产物
2. 组装 staging 目录
   - 复制 README.md, package.json
   - 合并所有 vendor 目录
3. 更新 package.json 版本
4. 设置二进制可执行权限
5. 创建 npm tarball: npm pack
6. 重命名为 codex-shell-tool-mcp-npm-<version>.tgz
```

### 数据结构

#### 矩阵配置 (bash-linux)
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - runner: ubuntu-24.04
        target: x86_64-unknown-linux-musl
        variant: ubuntu-24.04
        image: ubuntu:24.04
      # ... 其他变体
```

#### 容器配置
```yaml
container:
  image: ${{ matrix.image }}
```
使用容器确保不同发行版的构建环境隔离。

### 协议与命令

#### 包管理器检测
```bash
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ...
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ...
elif command -v yum >/dev/null 2>&1; then
    yum install -y ...
fi
```

#### npm 发布
```bash
# 使用 OIDC 认证 (无需 NODE_AUTH_TOKEN)
npm publish "dist/npm/codex-shell-tool-mcp-npm-${VERSION}.tgz" --tag "${NPM_TAG}"
```

---

## 关键代码路径与文件引用

### 工作流文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/shell-tool-mcp.yml` | 发布工作流 (本文件) |
| `.github/workflows/shell-tool-mcp-ci.yml` | CI 验证工作流 |
| `.github/workflows/rust-release.yml` | 调用方工作流 |

### 补丁文件
| 文件 | 作用 |
|------|------|
| `shell-tool-mcp/patches/bash-exec-wrapper.patch` | Bash EXEC_WRAPPER 补丁 |
| `shell-tool-mcp/patches/zsh-exec-wrapper.patch` | zsh EXEC_WRAPPER 补丁 |

### 源码和配置
| 文件 | 作用 |
|------|------|
| `shell-tool-mcp/package.json` | npm 包配置 |
| `shell-tool-mcp/README.md` | 包文档 |
| `shell-tool-mcp/src/` | TypeScript 源码 (运行时选择逻辑) |

### 上游源码
| 仓库 | 用途 |
|------|------|
| `https://git.savannah.gnu.org/git/bash` | Bash 源码 |
| `https://git.code.sf.net/p/zsh/code` | zsh 源码 |

---

## 依赖与外部交互

### 外部服务
| 服务 | 用途 | 认证 |
|------|------|------|
| GitHub Releases | 制品托管 | GITHUB_TOKEN |
| npm Registry | 包发布 | OIDC |
| Savannah Git | Bash 源码 | 无 |
| SourceForge | zsh 源码 | 无 |

### 依赖工具
| 工具 | 版本 | 用途 |
|------|------|------|
| Node.js | 22 | npm 包构建 |
| pnpm | 10.29.3 | 依赖管理 |
| npm | latest | 发布 (需 >=11.5.1) |
| git | - | 源码克隆 |
| gcc/g++ | - | 编译 |
| bison | - | 语法解析器生成 |
| autoconf | - | 配置脚本生成 |
| gettext | - | 国际化 |
| ncurses | - | 终端库 |

### 系统依赖 (按发行版)
| 发行版 | 包名 |
|--------|------|
| Debian/Ubuntu | git, build-essential, bison, autoconf, gettext, libncursesw5-dev |
| CentOS/RHEL | git, gcc, gcc-c++, make, bison, autoconf, gettext, ncurses-devel |
| macOS | autoconf (brew) |

---

## 风险、边界与改进建议

### 已知风险

#### 1. 上游源码可用性
- **风险**: Savannah 和 SourceForge 可能不可用
- **影响**: 构建失败，无法发布
- **缓解**: 考虑镜像源码到可靠位置

#### 2. 容器镜像拉取限制
- **风险**: Docker Hub 速率限制
- **影响**: 构建失败
- **缓解**: 使用 GitHub Container Registry 或缓存

#### 3. 编译时间
- **风险**: 30 分钟超时可能不够
- **当前**: timeout-minutes: 30
- **建议**: 监控实际编译时间，必要时调整

#### 4. 版本匹配
- **风险**: Shell Tool MCP 版本需与 Codex CLI 版本匹配
- **文档**: README 中明确说明此约束

### 边界条件

#### 1. 版本格式限制
- 支持: `x.y.z`, `x.y.z-alpha.N`
- 不支持: `x.y.z-beta.N`, `x.y.z-rc.N`

#### 2. 平台覆盖
- Linux: x86_64 和 aarch64
- macOS: 仅 aarch64 (Apple Silicon)
- 不支持: Windows (无原生 Bash/zsh)

#### 3. 二进制选择逻辑
运行时根据 `/etc/os-release` (Linux) 或 Darwin 版本 (macOS) 选择最佳匹配的二进制。

### 改进建议

#### 1. 添加上游缓存
```yaml
- name: Cache upstream source
  uses: actions/cache@v3
  with:
    path: /tmp/bash
    key: bash-${{ hashFiles('shell-tool-mcp/patches/bash-exec-wrapper.patch') }}
```

#### 2. 并行构建优化
```yaml
# 当前已使用 fail-fast: false
# 可考虑添加 needs 优化依赖
```

#### 3. 添加签名验证
```yaml
- name: Verify upstream signatures
  run: |
    gpg --verify bash.tar.gz.sig
```

#### 4. 制品验证
```yaml
- name: Verify binaries
  run: |
    file "$dest/bash"
    ldd "$dest/bash" || true  # 检查动态链接
```

#### 5. 安全扫描
```yaml
- name: Scan binaries
  uses: securecodewarrior/github-action-add-sarif@v1
```

#### 6. 文档自动化
- 自动生成支持的平台矩阵
- 自动更新兼容性文档

---

## 附录: 工作流程图

```
rust-release.yml
    │
    ▼
shell-tool-mcp.yml
    │
    ├── metadata (版本计算)
    │
    ├── bash-linux (矩阵: 6 变体 x 2 架构)
    │   └── 编译 Bash + 上传产物
    │
    ├── bash-darwin (矩阵: 2 变体)
    │   └── 编译 Bash + 上传产物
    │
    ├── zsh-linux (矩阵: 6 变体 x 2 架构)
    │   └── 编译 zsh + 烟雾测试 + 上传产物
    │
    ├── zsh-darwin (矩阵: 2 变体)
    │   └── 编译 zsh + 烟雾测试 + 上传产物
    │
    ├── package (依赖: 所有构建 job)
    │   ├── 下载所有产物
    │   ├── 组装 staging
    │   ├── 更新版本
    │   └── 创建 npm tarball
    │
    └── publish (依赖: package, 条件: publish=true)
        └── 发布到 npm
```

---

## 附录: EXEC_WRAPPER 机制详解

### 工作原理

1. **环境变量**: `EXEC_WRAPPER` 指向一个可执行文件
2. **拦截**: Bash/zsh 在执行命令前检查该变量
3. **包装**: 将原始命令和参数传递给 wrapper
4. **控制**: wrapper 可以审查、修改或拒绝执行

### 使用场景

Codex CLI 使用此机制实现:
- **命令审查**: 在沙箱中拦截所有外部命令执行
- **权限提升**: 根据 `.rules` 配置决定是否允许执行
- **审计日志**: 记录所有执行的命令

### 安全考虑

- wrapper 必须安全处理参数
- 防止命令注入
- 正确处理退出码
