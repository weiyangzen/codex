# Windows Code Sign Action 研究文档

## 概述

本文档深入研究 `.github/actions/windows-code-sign/action.yml`，该 GitHub Action 用于对 Codex 项目的 Windows 二进制文件进行代码签名。该 Action 采用 Azure Trusted Signing 服务，通过 OIDC (OpenID Connect) 身份验证实现安全的无密钥签名流程。

---

## 1. 场景与职责

### 1.1 使用场景

该 Action 在以下场景中被调用：

| 场景 | 描述 |
|------|------|
| **Rust Release Windows 工作流** | 在 `rust-release-windows.yml` 工作流中，构建完 Windows 二进制文件后调用 |
| **主 Release 流程** | 通过 `rust-release.yml` 触发，为 Windows 平台 (x86_64 和 aarch64) 构建的发布包签名 |
| **WinGet 发布准备** | 签名后的二进制文件将被打包为 WinGet 可安装格式 |

### 1.2 核心职责

1. **Azure 身份验证**：使用 OIDC 流程登录 Azure，获取临时凭证
2. **代码签名**：使用 Azure Trusted Signing 服务对 Windows 可执行文件进行数字签名
3. **安全保障**：确保发布的 Windows 二进制文件具有可信的数字签名，避免 Windows SmartScreen 警告

### 1.3 签名目标文件

该 Action 对以下 4 个 Windows 可执行文件进行签名：

```yaml
${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex.exe
${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex-responses-api-proxy.exe
${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex-windows-sandbox-setup.exe
${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex-command-runner.exe
```

这些二进制文件对应 Codex 项目的核心组件：
- `codex.exe`: 主 CLI 可执行文件
- `codex-responses-api-proxy.exe`: OpenAI Responses API 代理服务
- `codex-windows-sandbox-setup.exe`: Windows 沙箱设置工具
- `codex-command-runner.exe`: Windows 命令运行器（用于沙箱内执行）

---

## 2. 功能点目的

### 2.1 功能架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    windows-code-sign Composite Action                    │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────────────────────────┐ │
│  │ Azure Login (OIDC)  │───▶│  azure/login@v2                         │ │
│  │                     │    │  - client-id, tenant-id, subscription-id│ │
│  └─────────────────────┘    └─────────────────────────────────────────┘ │
│                           │                                             │
│                           ▼                                             │
│  ┌─────────────────────┐    ┌─────────────────────────────────────────┐ │
│  │ Trusted Signing     │───▶│  azure/trusted-signing-action@v0        │ │
│  │                     │    │  - endpoint, account-name, cert-profile │ │
│  │                     │    │  - 文件列表 (4个 .exe 文件)              │ │
│  └─────────────────────┘    └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 各输入参数用途

| 参数 | 用途 | 来源 |
|------|------|------|
| `target` | Rust 目标三元组，确定二进制文件路径 | 矩阵配置 (x86_64-pc-windows-msvc / aarch64-pc-windows-msvc) |
| `client-id` | Azure AD 应用程序客户端 ID | GitHub Secrets (AZURE_TRUSTED_SIGNING_CLIENT_ID) |
| `tenant-id` | Azure AD 租户 ID | GitHub Secrets (AZURE_TRUSTED_SIGNING_TENANT_ID) |
| `subscription-id` | Azure 订阅 ID | GitHub Secrets (AZURE_TRUSTED_SIGNING_SUBSCRIPTION_ID) |
| `endpoint` | Azure Trusted Signing 服务端点 | GitHub Secrets (AZURE_TRUSTED_SIGNING_ENDPOINT) |
| `account-name` | Trusted Signing 账户名称 | GitHub Secrets (AZURE_TRUSTED_SIGNING_ACCOUNT_NAME) |
| `certificate-profile-name` | 证书配置文件名称 | GitHub Secrets (AZURE_TRUSTED_SIGNING_CERTIFICATE_PROFILE_NAME) |

### 2.3 与其他平台签名对比

| 平台 | Action 文件 | 签名技术 |
|------|------------|----------|
| Windows | `windows-code-sign/action.yml` | Azure Trusted Signing (云签名) |
| macOS | `macos-code-sign/action.yml` | Apple Developer ID + Notary API |
| Linux | `linux-code-sign/action.yml` | Sigstore Cosign (OIDC 签名) |

---

## 3. 具体技术实现

### 3.1 技术栈

- **Azure Trusted Signing**: 微软提供的云代码签名服务
- **OIDC (OpenID Connect)**: 用于 GitHub Actions 与 Azure 之间的无密钥身份验证
- **azure/login@v2**: Azure 官方登录 Action
- **azure/trusted-signing-action@v0**: Azure Trusted Signing 官方 Action

### 3.2 关键流程详解

#### 3.2.1 Step 1: Azure OIDC 登录

```yaml
- name: Azure login for Trusted Signing (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ inputs.client-id }}
    tenant-id: ${{ inputs.tenant-id }}
    subscription-id: ${{ inputs.subscription-id }}
```

**技术细节**：
- 使用 OIDC 联邦身份验证，无需在 GitHub Secrets 中存储长期有效的 Azure 凭证
- GitHub Actions 运行时生成临时 JWT token
- Azure AD 验证该 token 后颁发短期访问令牌
- 需要 GitHub Actions 工作流具有 `id-token: write` 权限

#### 3.2.2 Step 2: 执行代码签名

```yaml
- name: Sign Windows binaries with Azure Trusted Signing
  uses: azure/trusted-signing-action@v0
  with:
    endpoint: ${{ inputs.endpoint }}
    trusted-signing-account-name: ${{ inputs.account-name }}
    certificate-profile-name: ${{ inputs.certificate-profile-name }}
    exclude-environment-credential: true
    exclude-workload-identity-credential: true
    exclude-managed-identity-credential: true
    exclude-shared-token-cache-credential: true
    exclude-visual-studio-credential: true
    exclude-visual-studio-code-credential: true
    exclude-azure-cli-credential: false
    exclude-azure-powershell-credential: true
    exclude-azure-developer-cli-credential: true
    exclude-interactive-browser-credential: true
    cache-dependencies: false
    files: |
      ${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex.exe
      ...
```

**凭证排除策略分析**：

| 凭证类型 | 设置 | 说明 |
|----------|------|------|
| `exclude-azure-cli-credential` | `false` | **唯一启用的方式**，依赖前一步的 `azure/login` |
| `exclude-environment-credential` | `true` | 禁用环境变量凭证 |
| `exclude-workload-identity-credential` | `true` | 禁用工作负载身份 |
| `exclude-managed-identity-credential` | `true` | 禁用托管身份 |
| `exclude-visual-studio-credential` | `true` | 禁用 Visual Studio 凭证 |
| `exclude-interactive-browser-credential` | `true` | 禁用交互式浏览器登录 |

这种配置强制使用 Azure CLI 凭证（由 `azure/login` 设置），确保身份验证链路清晰可控。

### 3.3 数据结构

#### 3.3.1 Action 输入接口 (Inputs)

```yaml
inputs:
  target:
    description: Target triple for the artifacts to sign.
    required: true
  client-id:
    description: Azure Trusted Signing client ID.
    required: true
  tenant-id:
    description: Azure tenant ID for Trusted Signing.
    required: true
  subscription-id:
    description: Azure subscription ID for Trusted Signing.
    required: true
  endpoint:
    description: Azure Trusted Signing endpoint.
    required: true
  account-name:
    description: Azure Trusted Signing account name.
    required: true
  certificate-profile-name:
    description: Certificate profile name for signing.
    required: true
```

#### 3.3.2 运行时文件路径结构

```
codex-rs/target/${{ inputs.target }}/release/
├── codex.exe                           # 主程序
├── codex-responses-api-proxy.exe       # API 代理
├── codex-windows-sandbox-setup.exe     # 沙箱设置
└── codex-command-runner.exe            # 命令运行器
```

---

## 4. 关键代码路径与文件引用

### 4.1 Action 定义文件

| 文件路径 | 说明 |
|----------|------|
| `.github/actions/windows-code-sign/action.yml` | **本 Action 定义文件** |

### 4.2 调用方文件

| 文件路径 | 说明 |
|----------|------|
| `.github/workflows/rust-release-windows.yml` | Windows 发布工作流，第 173-182 行调用本 Action |
| `.github/workflows/rust-release.yml` | 主发布工作流，通过 `workflow_call` 触发 Windows 构建 |

### 4.3 被签名二进制文件的源码位置

| 二进制文件 | Cargo.toml 路径 | 源码入口 |
|------------|-----------------|----------|
| `codex.exe` | `codex-rs/cli/Cargo.toml` | `codex-rs/cli/src/main.rs` |
| `codex-responses-api-proxy.exe` | `codex-rs/responses-api-proxy/Cargo.toml` | `codex-rs/responses-api-proxy/src/main.rs` |
| `codex-windows-sandbox-setup.exe` | `codex-rs/windows-sandbox-rs/Cargo.toml` | `codex-rs/windows-sandbox-rs/src/bin/setup_main.rs` |
| `codex-command-runner.exe` | `codex-rs/windows-sandbox-rs/Cargo.toml` | `codex-rs/windows-sandbox-rs/src/bin/command_runner.rs` |

### 4.4 相关配置

| 文件路径 | 说明 |
|----------|------|
| `.github/dotslash-config.json` | DotSlash 发布配置，定义各平台二进制文件的命名和路径匹配规则 |
| `codex-rs/Cargo.toml` | Workspace 配置，定义所有 crate 的构建设置 |
| `codex-rs/windows-sandbox-rs/Cargo.toml` | Windows 沙箱 crate 配置，定义两个二进制文件的构建规则 |

### 4.5 代码片段引用

**rust-release-windows.yml 中的调用代码** (第 173-182 行)：
```yaml
- name: Sign Windows binaries with Azure Trusted Signing
  uses: ./.github/actions/windows-code-sign
  with:
    target: ${{ matrix.target }}
    client-id: ${{ secrets.AZURE_TRUSTED_SIGNING_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TRUSTED_SIGNING_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_TRUSTED_SIGNING_SUBSCRIPTION_ID }}
    endpoint: ${{ secrets.AZURE_TRUSTED_SIGNING_ENDPOINT }}
    account-name: ${{ secrets.AZURE_TRUSTED_SIGNING_ACCOUNT_NAME }}
    certificate-profile-name: ${{ secrets.AZURE_TRUSTED_SIGNING_CERTIFICATE_PROFILE_NAME }}
```

**rust-release-windows.yml 中的权限配置** (第 127-130 行)：
```yaml
permissions:
  contents: read
  id-token: write  # 必需：用于 OIDC 身份验证
```

---

## 5. 依赖与外部交互

### 5.1 GitHub Actions 依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `azure/login` | `v2` | Azure OIDC 身份验证 |
| `azure/trusted-signing-action` | `v0` | 执行代码签名操作 |

### 5.2 Azure 服务依赖

| 服务 | 用途 |
|------|------|
| **Azure Active Directory** | OIDC 身份提供商，验证 GitHub Actions 身份 |
| **Azure Trusted Signing** | 云代码签名服务，提供证书和签名操作 |

### 5.3 Azure Trusted Signing 工作原理

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  GitHub Actions │────▶│  Azure AD (OIDC) │────▶│  Trusted Signing    │
│  (workflow)     │     │  (身份验证)       │     │  (签名服务)         │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
                              │                           │
                              │                           │
                              ▼                           ▼
                       ┌──────────────┐          ┌──────────────┐
                       │ 临时访问令牌  │          │ 代码签名证书  │
                       │ (JWT)        │          │ (EV/OV)      │
                       └──────────────┘          └──────────────┘
```

### 5.4 上游工作流依赖

```
rust-release.yml (主发布工作流)
    │
    ├──► build-windows job
    │       │
    │       └──► rust-release-windows.yml (workflow_call)
    │               │
    │               ├──► build-windows-binaries job
    │               │       └──► 构建并上传未签名二进制文件
    │               │
    │               └──► build-windows job
    │                       │
    │                       ├──► 下载二进制文件
    │                       ├──► windows-code-sign/action.yml ⭐
    │                       └──► 打包并上传签名后的文件
    │
    └──► release job
            └──► 创建 GitHub Release 并发布签名二进制文件
```

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **Secret 泄露** | Azure 凭证泄露可能导致恶意签名 | 使用 OIDC 避免长期凭证；Secrets 已加密存储 |
| **供应链攻击** | `azure/trusted-signing-action` 被篡改 | 使用官方 Action，考虑锁定到具体 SHA |
| **中间人攻击** | 网络拦截导致签名请求被篡改 | Azure 服务使用 HTTPS/TLS |

#### 6.1.2 运营风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **Azure 服务中断** | Trusted Signing 服务不可用导致发布失败 | 监控 Azure 服务状态；考虑备用签名方案 |
| **证书过期** | 代码签名证书过期 | Azure Trusted Signing 自动管理证书续期 |
| **权限配置错误** | `id-token: write` 权限缺失导致 OIDC 失败 | 工作流已明确配置权限 |

### 6.2 边界条件

#### 6.2.1 输入验证边界

- `target` 必须是有效的 Rust Windows 目标三元组
- 所有 Azure 相关 secrets 必须非空且有效
- 二进制文件必须在指定路径存在，否则签名步骤会失败

#### 6.2.2 执行环境边界

- 必须在 Windows 运行器上执行（二进制文件是 Windows PE 格式）
- 运行器必须能够访问 Azure 服务（网络连通性）
- 工作流必须具有 `id-token: write` 权限

### 6.3 改进建议

#### 6.3.1 安全性改进

1. **Action 版本锁定**
   ```yaml
   # 当前
   uses: azure/trusted-signing-action@v0
   
   # 建议：锁定到具体 SHA
   uses: azure/trusted-signing-action@<commit-sha>
   ```

2. **添加签名验证步骤**
   ```yaml
   - name: Verify signatures
     shell: pwsh
     run: |
       Get-AuthenticodeSignature -FilePath "${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex.exe"
   ```

3. **输入验证**
   ```yaml
   - name: Validate inputs
     shell: bash
     run: |
       if [[ ! "${{ inputs.target }}" =~ ^(x86_64|aarch64)-pc-windows-msvc$ ]]; then
         echo "Invalid target: ${{ inputs.target }}"
         exit 1
       fi
   ```

#### 6.3.2 可维护性改进

1. **文件列表参数化**
   当前文件列表硬编码在 Action 中，建议通过输入参数传递：
   ```yaml
   inputs:
     files:
       description: 'Files to sign (multiline)'
       required: false
       default: |
         codex.exe
         codex-responses-api-proxy.exe
         codex-windows-sandbox-setup.exe
         codex-command-runner.exe
   ```

2. **添加输出参数**
   ```yaml
   outputs:
     signed-files:
       description: 'List of successfully signed files'
       value: ${{ steps.sign.outputs.signed-files }}
   ```

3. **错误处理和重试机制**
   Azure Trusted Signing 偶尔可能因网络问题失败，建议添加重试逻辑。

#### 6.3.3 监控和可观测性

1. **签名审计日志**
   ```yaml
   - name: Log signing event
     shell: bash
     run: |
       echo "::notice::Signed Windows binaries for target: ${{ inputs.target }}"
       echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

2. **指标收集**
   记录签名耗时、成功率等指标，用于监控签名服务健康状况。

### 6.4 已知限制

1. **仅支持 Windows 目标**：该 Action 专门用于 Windows PE 文件签名，不适用于其他平台
2. **Azure 依赖**：必须使用 Azure Trusted Signing 服务，无法切换到其他 CA
3. **无本地回退**：如果 Azure 服务不可用，没有本地签名备选方案
4. **单区域依赖**：如果 Azure 区域故障，可能影响签名能力

---

## 附录

### A. 相关文档链接

- [Azure Trusted Signing 文档](https://learn.microsoft.com/en-us/azure/security/trusted-signing/)
- [GitHub Actions OIDC with Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [azure/trusted-signing-action GitHub](https://github.com/Azure/trusted-signing-action)

### B. 版本历史

| 日期 | 变更 |
|------|------|
| 2026-03-22 | 创建研究文档 |

### C. 相关文件索引

```
.github/
├── actions/
│   ├── windows-code-sign/
│   │   └── action.yml              # 本文件
│   ├── macos-code-sign/
│   │   ├── action.yml
│   │   └── notary_helpers.sh
│   └── linux-code-sign/
│       └── action.yml
├── workflows/
│   ├── rust-release-windows.yml    # 调用方
│   ├── rust-release.yml            # 主发布工作流
│   └── rust-release-prepare.yml
├── dotslash-config.json            # 发布配置
└── ...

codex-rs/
├── Cargo.toml                      # Workspace 配置
├── windows-sandbox-rs/
│   ├── Cargo.toml                  # 定义 codex-windows-sandbox-setup 和 codex-command-runner
│   └── src/
│       ├── bin/
│       │   ├── setup_main.rs
│       │   └── command_runner.rs
│       └── ...
├── cli/
│   ├── Cargo.toml                  # 定义 codex 主程序
│   └── src/
│       └── main.rs
└── responses-api-proxy/
    ├── Cargo.toml                  # 定义 codex-responses-api-proxy
    └── src/
        └── main.rs
```
