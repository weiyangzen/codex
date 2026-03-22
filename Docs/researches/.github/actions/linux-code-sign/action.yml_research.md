# linux-code-sign GitHub Action 研究文档

## 概述

**文件路径**: `.github/actions/linux-code-sign/action.yml`  
**类型**: GitHub Composite Action  
**用途**: 使用 Sigstore Cosign 对 Linux 构建产物进行数字签名

---

## 1. 场景与职责

### 1.1 使用场景

该 Action 是 OpenAI Codex 项目 Rust 组件发布流程中的关键安全环节，专门用于：

- **Linux 平台发布签名**: 对 `codex` 和 `codex-responses-api-proxy` 两个核心二进制文件进行签名
- **供应链安全**: 通过 Sigstore 的透明日志和 OIDC 身份验证，确保构建产物的来源可追溯、不可篡改
- **跨平台发布一致性**: 与 macOS 代码签名 (`macos-code-sign`) 和 Windows 代码签名 (`windows-code-sign`) 形成完整的跨平台签名体系

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| 安装 Cosign | 使用 `sigstore/cosign-installer@v3.7.0` 安装特定版本的 Cosign CLI 工具 |
| 验证构建产物 | 检查目标目录和待签名二进制文件是否存在 |
| 执行签名 | 使用 `cosign sign-blob` 命令对二进制文件进行签名，生成 `.sigstore` 格式的签名包 |
| 生成签名包 | 为每个二进制文件生成包含签名、证书和透明日志条目的 `.sigstore` 文件 |

### 1.3 调用时机

在 `.github/workflows/rust-release.yml` 中被调用：

```yaml
- if: ${{ contains(matrix.target, 'linux') }}
  name: Cosign Linux artifacts
  uses: ./.github/actions/linux-code-sign
  with:
    target: ${{ matrix.target }}
    artifacts-dir: ${{ github.workspace }}/codex-rs/target/${{ matrix.target }}/release
```

**触发条件**: 仅当构建目标包含 "linux" 字符串时执行（支持 `x86_64-unknown-linux-musl`、`x86_64-unknown-linux-gnu`、`aarch64-unknown-linux-musl`、`aarch64-unknown-linux-gnu`）

---

## 2. 功能点目的

### 2.1 无密钥签名 (Keyless Signing)

该 Action 采用 Sigstore 的**无密钥签名**模式，核心优势：

- **无需管理私钥**: 传统代码签名需要安全存储私钥，而无密钥签名使用短期有效的 OIDC 身份令牌
- **自动证书管理**: Fulcio CA 自动颁发短期证书（默认 10 分钟有效期）
- **透明日志记录**: 所有签名自动记录到 Rekor 透明日志，可供公众审计

### 2.2 签名产物格式

生成的 `.sigstore` 文件是 JSON 格式的签名包，包含：

```json
{
  "mediaType": "application/vnd.dev.sigstore.bundle+json;version=0.1",
  "verificationMaterial": {
    "certificate": {
      "rawBytes": "..."
    },
    "tlogEntries": [...]
  },
  "messageSignature": {
    "messageDigest": {
      "algorithm": "SHA2_256",
      "digest": "..."
    },
    "signature": "..."
  }
}
```

### 2.3 签名目标文件

| 二进制文件 | 说明 |
|-----------|------|
| `codex` | 主 CLI 工具，Codex 的核心可执行文件 |
| `codex-responses-api-proxy` | OpenAI Responses API 的本地代理服务 |

---

## 3. 具体技术实现

### 3.1 输入参数定义

```yaml
inputs:
  target:
    description: Target triple for the artifacts to sign.
    required: true
  artifacts-dir:
    description: Absolute path to the directory containing built binaries to sign.
    required: true
```

| 参数 | 类型 | 必填 | 示例值 |
|------|------|------|--------|
| `target` | string | 是 | `x86_64-unknown-linux-musl` |
| `artifacts-dir` | string | 是 | `/home/runner/work/codex/codex-rs/target/x86_64-unknown-linux-musl/release` |

### 3.2 环境变量配置

```yaml
env:
  ARTIFACTS_DIR: ${{ inputs.artifacts-dir }}
  COSIGN_EXPERIMENTAL: "1"
  COSIGN_YES: "true"
  COSIGN_OIDC_CLIENT_ID: "sigstore"
  COSIGN_OIDC_ISSUER: "https://oauth2.sigstore.dev/auth"
```

| 环境变量 | 值 | 作用 |
|---------|-----|------|
| `COSIGN_EXPERIMENTAL` | `1` | 启用实验性功能（无密钥签名需要） |
| `COSIGN_YES` | `true` | 自动确认所有提示，实现非交互式运行 |
| `COSIGN_OIDC_CLIENT_ID` | `sigstore` | OIDC 客户端 ID，用于 GitHub Actions 身份验证 |
| `COSIGN_OIDC_ISSUER` | `https://oauth2.sigstore.dev/auth` | Sigstore 的 OIDC 颁发者 URL |

### 3.3 签名流程详解

```bash
# 1. 设置严格错误处理
set -euo pipefail

# 2. 验证目标目录存在
dest="$ARTIFACTS_DIR"
if [[ ! -d "$dest" ]]; then
  echo "Destination $dest does not exist"
  exit 1
fi

# 3. 遍历签名目标二进制文件
for binary in codex codex-responses-api-proxy; do
  artifact="${dest}/${binary}"
  if [[ ! -f "$artifact" ]]; then
    echo "Binary $artifact not found"
    exit 1
  fi

  # 4. 执行签名
  cosign sign-blob \
    --yes \
    --bundle "${artifact}.sigstore" \
    "$artifact"
done
```

### 3.4 Cosign 命令解析

```bash
cosign sign-blob \
  --yes \                          # 自动确认，无需交互
  --bundle "${artifact}.sigstore" \ # 输出签名包文件路径
  "$artifact"                      # 待签名的二进制文件
```

**命令行为**:
1. 通过 OIDC 从 GitHub Actions 获取身份令牌
2. 向 Fulcio CA 请求短期签名证书
3. 使用证书对文件进行数字签名
4. 将签名记录上传到 Rekor 透明日志
5. 将证书、签名和日志条目打包为 `.sigstore` 文件

---

## 4. 关键代码路径与文件引用

### 4.1 当前文件结构

```
.github/actions/linux-code-sign/
└── action.yml          # 本文件，定义 Composite Action
```

### 4.2 调用方文件

| 文件路径 | 作用 |
|---------|------|
| `.github/workflows/rust-release.yml` | Rust 发布工作流，在 Linux 构建后调用本 Action |

**调用代码位置** (line 226-231):
```yaml
- if: ${{ contains(matrix.target, 'linux') }}
  name: Cosign Linux artifacts
  uses: ./.github/actions/linux-code-sign
  with:
    target: ${{ matrix.target }}
    artifacts-dir: ${{ github.workspace }}/codex-rs/target/${{ matrix.target }}/release
```

### 4.3 相关 Action 文件

| 文件路径 | 作用 |
|---------|------|
| `.github/actions/macos-code-sign/action.yml` | macOS 代码签名（使用 Apple 证书 + Notary） |
| `.github/actions/windows-code-sign/action.yml` | Windows 代码签名（使用 Azure Trusted Signing） |

### 4.4 签名产物处理

在 `.github/workflows/rust-release.yml` 的 **Stage artifacts** 阶段 (line 305-321):

```yaml
- name: Stage artifacts
  shell: bash
  run: |
    dest="dist/${{ matrix.target }}"
    mkdir -p "$dest"

    cp target/${{ matrix.target }}/release/codex "$dest/codex-${{ matrix.target }}"
    cp target/${{ matrix.target }}/release/codex-responses-api-proxy "$dest/codex-responses-api-proxy-${{ matrix.target }}"

    if [[ "${{ matrix.target }}" == *linux* ]]; then
      cp target/${{ matrix.target }}/release/codex.sigstore "$dest/codex-${{ matrix.target }}.sigstore"
      cp target/${{ matrix.target }}/release/codex-responses-api-proxy.sigstore "$dest/codex-responses-api-proxy-${{ matrix.target }}.sigstore"
    fi
    # ...
```

签名产物 (`.sigstore` 文件) 会被复制到发布目录，最终随 GitHub Release 发布。

### 4.5 DotSlash 配置

`.github/dotslash-config.json` 定义了各平台的发布产物匹配规则：

```json
{
  "outputs": {
    "codex": {
      "platforms": {
        "linux-x86_64": {
          "regex": "^codex-x86_64-unknown-linux-musl\\.zst$",
          "path": "codex"
        },
        "linux-aarch64": {
          "regex": "^codex-aarch64-unknown-linux-musl\\.zst$",
          "path": "codex"
        }
      }
    }
  }
}
```

注意：签名文件 (`.sigstore`) 与压缩包 (`.zst`) 是分开发布的。

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `sigstore/cosign-installer` | v3.7.0 | 安装 Cosign CLI 工具 |
| `cosign` | 最新（由 installer 决定） | 执行实际的签名操作 |

### 5.2 外部服务交互

```
┌─────────────────┐     OIDC Token      ┌──────────────────┐
│ GitHub Actions  │ ───────────────────>│ Sigstore Fulcio  │
│   (Workload)    │                     │    (OIDC CA)     │
└─────────────────┘                     └──────────────────┘
         │                                        │
         │         Request Certificate            │
         │<───────────────────────────────────────│
         │                                        │
         │         Sign Blob + Upload Entry       │
         │───────────────────────────────────────>│
         │                                        │
         │         Signature Bundle               │
         │<───────────────────────────────────────│
         │                                        │
         ▼                                        ▼
┌─────────────────┐                     ┌──────────────────┐
│  .sigstore file │                     │ Rekor Transparency│
│   (output)      │                     │      Log         │
└─────────────────┘                     └──────────────────┘
```

**交互流程**:
1. **OIDC 身份验证**: Cosign 从 GitHub Actions 环境获取 OIDC 令牌（通过 `ACTIONS_ID_TOKEN_REQUEST_URL` 和 `ACTIONS_ID_TOKEN_REQUEST_TOKEN`）
2. **证书申请**: 使用 OIDC 令牌向 Fulcio 申请短期代码签名证书
3. **签名操作**: 使用证书对二进制文件进行 SHA256 哈希签名
4. **透明日志**: 将签名条目上传到 Rekor 透明日志，获得日志索引和集成时间
5. **生成签名包**: 将证书、签名和日志证明打包为 `.sigstore` 文件

### 5.3 权限要求

调用本 Action 的工作流需要以下权限：

```yaml
permissions:
  contents: read      # 读取仓库内容
  id-token: write     # 获取 OIDC 令牌（关键权限）
```

**注意**: `id-token: write` 是必需的，否则 Cosign 无法获取 OIDC 令牌进行无密钥签名。

---

## 6. 风险、边界与改进建议

### 6.1 当前风险

| 风险类别 | 描述 | 严重程度 |
|---------|------|---------|
| **单点故障** | 依赖 Sigstore 基础设施（Fulcio/Rekor）的可用性 | 中 |
| **网络依赖** | 签名过程需要访问外部服务，无法离线执行 | 中 |
| **版本锁定** | Cosign 版本由 installer 决定，可能存在行为变更风险 | 低 |
| **实验性功能** | `COSIGN_EXPERIMENTAL=1` 依赖的功能可能不稳定 | 低 |

### 6.2 边界条件

| 边界条件 | 当前行为 | 潜在问题 |
|---------|---------|---------|
| 目录不存在 | 立即退出并报错 | 清晰的错误处理 |
| 二进制文件缺失 | 立即退出并报错 | 清晰的错误处理 |
| 签名失败 | 脚本因 `set -e` 而终止 | 需要查看 Cosign 输出诊断 |
| 重复签名 | 会覆盖现有 `.sigstore` 文件 | 无版本控制，可能丢失旧签名 |

### 6.3 改进建议

#### 6.3.1 增强可观测性

```yaml
# 建议：添加签名验证步骤
- name: Verify signatures
  shell: bash
  run: |
    for binary in codex codex-responses-api-proxy; do
      artifact="${ARTIFACTS_DIR}/${binary}"
      cosign verify-blob \
        --bundle "${artifact}.sigstore" \
        --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
        --certificate-identity-regexp "^https://github.com/openai/codex/.github/workflows/rust-release.yml@refs/tags/rust-v[0-9]+\.[0-9]+\.[0-9]+$" \
        "$artifact"
    done
```

#### 6.3.2 固定 Cosign 版本

```yaml
# 建议：明确指定 Cosign 版本，避免意外行为变更
- name: Install cosign
  uses: sigstore/cosign-installer@v3.7.0
  with:
    cosign-release: 'v2.4.0'  # 明确版本
```

#### 6.3.3 添加签名元数据

```yaml
# 建议：在签名包中包含更多构建元数据
env:
  COSIGN_EXPERIMENTAL: "1"
  COSIGN_YES: "true"
  COSIGN_OIDC_CLIENT_ID: "sigstore"
  COSIGN_OIDC_ISSUER: "https://oauth2.sigstore.dev/auth"
  # 添加注解
  COSIGN_ANNOTATIONS: "github.workflow=rust-release,github.run_id=${{ github.run_id }},github.sha=${{ github.sha }}"
```

#### 6.3.4 支持更多二进制文件

当前硬编码了两个二进制文件：

```bash
for binary in codex codex-responses-api-proxy; do
```

建议改为通过输入参数传递：

```yaml
inputs:
  binaries:
    description: Space-separated list of binary names to sign
    required: false
    default: "codex codex-responses-api-proxy"
```

#### 6.3.5 添加重试机制

网络问题可能导致签名失败，建议添加重试：

```bash
for binary in codex codex-responses-api-proxy; do
  artifact="${dest}/${binary}"
  for attempt in 1 2 3; do
    if cosign sign-blob --yes --bundle "${artifact}.sigstore" "$artifact"; then
      break
    fi
    if [[ $attempt -eq 3 ]]; then
      echo "Failed to sign $binary after 3 attempts"
      exit 1
    fi
    sleep 5
  done
done
```

### 6.4 安全最佳实践

1. **验证签名**: 发布后应提供签名验证指南，帮助用户验证下载的二进制文件
2. **监控透明日志**: 定期检查 Rekor 日志，确保没有异常的签名条目
3. **轮换策略**: 虽然使用无密钥签名，但仍应监控 Fulcio 证书策略的变更

---

## 7. 相关文档链接

- [Sigstore 官方文档](https://docs.sigstore.dev/)
- [Cosign GitHub 仓库](https://github.com/sigstore/cosign)
- [GitHub Actions OIDC 文档](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Sigstore Cosign Installer Action](https://github.com/sigstore/cosign-installer)

---

## 8. 版本历史

| 日期 | 变更 | 作者 |
|------|------|------|
| 2026-03-22 | 初始研究文档 | Kimi Code CLI |

---

*文档生成时间: 2026-03-22*  
*研究范围: `.github/actions/linux-code-sign/action.yml` 及其上下游依赖*
