# rust-release.yml 深度研究文档

## 场景与职责

`rust-release.yml` 是 OpenAI Codex 项目的 **Rust 组件正式发布工作流**，负责在推送版本标签时触发完整的跨平台构建、签名、打包和发布流程。它是 Codex CLI 核心 Rust 代码的发布中枢。

### 触发条件
- **事件类型**: `push` 事件，且标签匹配 `rust-v*.*.*` 模式
- **标签格式**: 
  - 稳定版: `rust-v1.2.3`
  - 预发布: `rust-v1.2.3-alpha.1`, `rust-v1.2.3-beta.1`

### 核心职责
1. **版本验证**: 确保 Git 标签版本与 `codex-rs/Cargo.toml` 中的版本一致
2. **跨平台构建**: 支持 6 个目标平台的 Release 构建
3. **代码签名**: Linux (Cosign) 和 macOS (Apple 证书) 双平台签名
4. **制品打包**: 生成 `.zst`、`.tar.gz`、`.dmg` (macOS) 等多种格式
5. **GitHub Release**: 自动创建 Release 并上传制品
6. **npm 发布**: 将 Rust 二进制打包为 npm 包发布
7. **WinGet 提交**: 自动向 Windows Package Manager 提交新版本

---

## 功能点目的

### 1. 标签检查 (tag-check)
**目的**: 防止版本不一致导致的发布错误
- 验证 `GITHUB_REF_TYPE` 为 tag
- 验证标签格式符合语义化版本规范
- 对比标签版本与 `codex-rs/Cargo.toml` 中的版本

### 2. 跨平台构建矩阵
| 平台 | 目标三元组 | 运行器 | 特殊处理 |
|------|-----------|--------|----------|
| macOS ARM64 | `aarch64-apple-darwin` | macos-15-xlarge | 签名 + DMG 打包 |
| macOS x64 | `x86_64-apple-darwin` | macos-15-xlarge | 签名 + DMG 打包 |
| Linux x64 (musl) | `x86_64-unknown-linux-musl` | ubuntu-24.04 | Zig + musl 工具链 |
| Linux x64 (gnu) | `x86_64-unknown-linux-gnu` | ubuntu-24.04 | 标准构建 |
| Linux ARM64 (musl) | `aarch64-unknown-linux-musl` | ubuntu-24.04-arm | Zig + musl 工具链 |
| Linux ARM64 (gnu) | `aarch64-unknown-linux-gnu` | ubuntu-24.04-arm | 标准构建 |

### 3. 构建产物
- **主二进制**: `codex` (CLI 主程序)
- **代理服务**: `codex-responses-api-proxy` (Responses API 代理)
- **Windows 专用**: `codex-windows-sandbox-setup`, `codex-command-runner`

### 4. 代码签名策略
- **Linux**: 使用 Sigstore Cosign 进行无密钥签名，生成 `.sigstore` 签名包
- **macOS**: 使用 Apple 开发者证书签名，支持公证 (Notarization)
- **Windows**: 委托给 `rust-release-windows.yml`，使用 Azure Trusted Signing

### 5. 压缩与打包
- **zstd**: 高压缩比，用于发布制品
- **tar.gz**: 兼容性格式，支持无 zstd 环境
- **zip**: Windows 平台专用
- **dmg**: macOS 磁盘镜像，包含签名和公证

### 6. npm 包发布
- 使用 `stage_npm_packages.py` 脚本构建平台特定的 npm 包
- 支持 OIDC 可信发布 (Trusted Publishing)
- 区分稳定版和 alpha 标签

### 7. WinGet 自动提交
- 仅针对稳定版 (无 `-` 后缀的版本)
- 使用 `vedantmgoyal9/winget-releaser` Action
- 匹配 Windows x64/ARM64 安装包

---

## 具体技术实现

### 关键流程

#### 1. musl 构建流程 (Linux)
```yaml
# 关键步骤
1. 安装 Zig (作为交叉编译工具链)
2. 运行 install-musl-build-tools.sh
   - 安装 musl-tools, libcap-dev
   - 下载并编译 libcap 2.75 (静态库)
   - 生成 Zig 包装器脚本 (zigcc/zigcxx)
   - 配置环境变量 (CC, CXX, CFLAGS, etc.)
3. 配置 UBSan 包装器 (仅 musl 目标)
4. 清除 sanitizer 标志 (避免 aws-lc 构建问题)
5. cargo build --target <target> --release
```

#### 2. macOS 签名流程
```yaml
# 两阶段签名
1. 二进制签名 (sign-binaries: true)
   - 导入 Apple 证书到临时钥匙串
   - codesign --force --options runtime --timestamp
   - 公证: ditto 打包 + notarytool submit

2. DMG 签名 (sign-dmg: true)
   - hdiutil create 生成 DMG
   - codesign 签名 DMG
   - 公证 + stapler staple
```

#### 3. 发布流程
```yaml
1. 生成 Release Notes (从 tag 指向的 commit 消息)
2. 下载所有构建产物
3. 清理临时文件 (cargo-timing.html, shell-tool-mcp 等)
4. 添加 config.schema.json
5. 创建 GitHub Release (softprops/action-gh-release)
6. DotSlash 发布 (facebook/dotslash-publish-release)
7. 触发 developers.openai.com 部署
```

### 数据结构

#### 矩阵构建配置
```yaml
strategy:
  fail-fast: false  # 允许部分失败，最大化构建成功率
  matrix:
    include:
      - runner: macos-15-xlarge
        target: aarch64-apple-darwin
      # ... 其他目标
```

#### 环境变量配置 (musl 专用)
```bash
# LTO 设置 (临时使用 thin LTO 避免 ARM 构建超时)
CARGO_PROFILE_RELEASE_LTO: thin

# AWS-LC 禁用 jitter (musl 兼容)
AWS_LC_SYS_NO_JITTER_ENTROPY=1

# 清除 sanitizer 标志
RUSTFLAGS=
CARGO_ENCODED_RUSTFLAGS=
```

### 协议与命令

#### 版本解析逻辑
```bash
# 从标签提取版本
tag_ver="${GITHUB_REF_NAME#rust-v}"

# 从 Cargo.toml 提取版本
cargo_ver="$(grep -m1 '^version' codex-rs/Cargo.toml | sed -E 's/version *= *"([^"]+)".*/\1/')"

# 对比验证
[[ "${tag_ver}" == "${cargo_ver}" ]]
```

#### npm 发布判断
```bash
if [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # 稳定版: 发布到 latest
    should_publish="true"
    npm_tag=""
elif [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$ ]]; then
    # Alpha 预发布: 发布到 alpha tag
    should_publish="true"
    npm_tag="alpha"
fi
```

---

## 关键代码路径与文件引用

### 工作流文件
| 文件 | 作用 |
|------|------|
| `.github/workflows/rust-release.yml` | 主发布工作流 (本文件) |
| `.github/workflows/rust-release-windows.yml` | Windows 构建子工作流 |
| `.github/workflows/shell-tool-mcp.yml` | Shell Tool MCP 构建 |

### 脚本与工具
| 文件 | 作用 |
|------|------|
| `.github/scripts/install-musl-build-tools.sh` | musl 交叉编译环境配置 |
| `scripts/stage_npm_packages.py` | npm 包构建编排 |
| `scripts/install/install.sh` | 用户安装脚本 (随 Release 分发) |
| `scripts/install/install.ps1` | Windows 安装脚本 |

### GitHub Actions
| 路径 | 作用 |
|------|------|
| `.github/actions/linux-code-sign` | Linux Cosign 签名 |
| `.github/actions/macos-code-sign` | macOS 签名与公证 |
| `.github/actions/windows-code-sign` | Windows Azure 签名 |

### 配置文件
| 文件 | 作用 |
|------|------|
| `.github/dotslash-config.json` | DotSlash 发布配置 |
| `codex-rs/Cargo.toml` | 版本源 (workspace.version) |
| `codex-rs/core/config.schema.json` | 配置 JSON Schema |

### 关键代码片段

#### musl 构建工具安装脚本
```bash
# .github/scripts/install-musl-build-tools.sh
# 功能: 设置 Zig + musl 交叉编译环境
# 关键输出:
# - CC/CXX: Zig 包装器路径
# - CFLAGS/CXXFLAGS: -pthread
# - PKG_CONFIG_PATH: libcap.pc 路径
# - BORING_BSSL_SYSROOT: Zig sysroot
```

#### Linux 签名 Action
```yaml
# .github/actions/linux-code-sign/action.yml
cosign sign-blob \
  --yes \
  --bundle "${artifact}.sigstore" \
  "$artifact"
```

---

## 依赖与外部交互

### 外部服务
| 服务 | 用途 | 认证方式 |
|------|------|----------|
| GitHub Releases | 制品托管 | `secrets.GITHUB_TOKEN` |
| npm Registry | 包发布 | OIDC 可信发布 |
| Azure Trusted Signing | Windows 签名 | `AZURE_*` secrets |
| Apple Developer | macOS 签名 | `APPLE_*` secrets |
| Sigstore | Linux 签名 | OIDC (Cosign) |
| WinGet | Windows 包管理 | `WINGET_PUBLISH_PAT` |
| Vercel | 文档部署 | `DEV_WEBSITE_VERCEL_DEPLOY_HOOK_URL` |

### 依赖工具
| 工具 | 版本 | 用途 |
|------|------|------|
| Rust | 1.93.0 | 编译 |
| Zig | 0.14.0 | musl 交叉编译 |
| pnpm | 10.29.3 | Node 依赖管理 |
| Node.js | 22 | npm 包构建 |
| cosign | v3.7.0 | Linux 签名 |
| DotSlash | v2 | 可执行文件分发 |

### 上游依赖
- **Bash 源码**: `git.savannah.gnu.org` (shell-tool-mcp)
- **zsh 源码**: `git.code.sf.net` (shell-tool-mcp)
- **libcap**: `mirrors.edge.kernel.org` (musl 构建)
- **zstd**: `github.com/facebook/zstd` (压缩工具)

---

## 风险、边界与改进建议

### 已知风险

#### 1. 构建超时风险 (ARM64 musl)
- **问题**: Ubuntu ARM 构建在 fat LTO 下超过 60 分钟
- **当前缓解**: 强制使用 `thin` LTO
- **代码**: `CARGO_PROFILE_RELEASE_LTO: thin`
- **建议**: 监控构建时间，考虑升级运行器或优化代码

#### 2. 版本一致性风险
- **问题**: 标签版本与 Cargo.toml 不匹配会导致发布失败
- **缓解**: `tag-check` job 在构建前验证
- **建议**: 考虑添加自动化脚本同步版本

#### 3. 密钥泄露风险
- **问题**: Apple 证书、Azure 凭据等敏感信息
- **缓解**: 使用 GitHub Secrets，临时钥匙串
- **建议**: 定期轮换证书，监控异常使用

#### 4. 构建矩阵失败
- **问题**: `fail-fast: false` 允许部分失败，但可能导致不完整发布
- **建议**: 添加发布前完整性检查，确保所有目标构建成功

### 边界条件

#### 1. 版本号格式
- 支持: `x.y.z`, `x.y.z-alpha.N`, `x.y.z-beta.N`
- 不支持: `x.y.z-rc.N`, `x.y.z+build` (可能需调整正则)

#### 2. 平台支持
- macOS: 仅签名 Apple Silicon (aarch64)，x86_64 通过 Rosetta 支持
- Linux: 优先 musl 构建，gnu 为备选
- Windows: 委托给独立工作流

#### 3. npm 发布限制
- 仅稳定版和 alpha 预发布会自动发布
- beta 版本不会触发 npm 发布

### 改进建议

#### 1. 构建优化
```yaml
# 建议: 添加构建缓存
- uses: Swatinem/rust-cache@v2
  with:
    workspaces: codex-rs
    key: ${{ matrix.target }}
```

#### 2. 健康检查
```yaml
# 建议: 添加发布后验证
- name: Verify release assets
  run: |
    # 检查所有预期文件存在
    # 验证签名有效性
    # 测试安装脚本
```

#### 3. 通知机制
```yaml
# 建议: 添加失败通知
- name: Notify on failure
  if: failure()
  uses: slack/notify@v1
  with:
    message: "Release ${{ github.ref_name }} failed"
```

#### 4. 文档自动化
- 自动生成 CHANGELOG
- 自动更新版本兼容性矩阵
- 自动发布 API 文档

#### 5. 安全加固
- 启用 SLSA  provenance 生成
- 添加 SBOM (Software Bill of Materials)
- 集成漏洞扫描 (cargo-audit)

---

## 附录: 工作流调用关系

```
rust-release.yml (主工作流)
├── tag-check (版本验证)
├── build (矩阵构建: Linux/macOS)
│   ├── linux-code-sign (Cosign)
│   └── macos-code-sign (Apple)
├── build-windows (委托给 rust-release-windows.yml)
│   └── windows-code-sign (Azure)
├── shell-tool-mcp (委托给 shell-tool-mcp.yml)
├── release (制品收集与发布)
│   ├── softprops/action-gh-release
│   └── facebook/dotslash-publish-release
├── publish-npm (npm 发布)
├── winget (WinGet 提交)
└── update-branch (latest-alpha-cli 分支更新)
```
