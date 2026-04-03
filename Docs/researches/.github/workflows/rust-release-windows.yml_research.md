# rust-release-windows.yml 研究文档

## 场景与职责

本 GitHub Actions 工作流负责构建 Windows 平台的 Codex CLI 二进制文件，并进行代码签名。它是 Rust 发布流程的重要组成部分，确保 Windows 用户可以获得经过签名的可信二进制文件。

## 功能点目的

1. **Windows 二进制构建**：支持 x64 和 ARM64 架构
2. **代码签名**：使用 Azure Trusted Signing 签名二进制文件
3. **产物打包**：生成多种格式的分发包（zst、tar.gz、zip）
4. **辅助工具**：构建 sandbox setup 和 command runner 辅助工具

## 具体技术实现

### 触发条件
```yaml
on:
  workflow_call:
    inputs:
      release-lto:
        required: true
        type: string
    secrets:
      AZURE_TRUSTED_SIGNING_CLIENT_ID:
        required: true
      # ... 其他 Azure 签名密钥
```

- 使用 `workflow_call`：被主发布工作流调用
- 输入：`release-lto`（LTO 配置）
- 密钥：Azure Trusted Signing 所需的所有密钥

### Job 1: build-windows-binaries

#### 构建矩阵
```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - runner: windows-x64
        target: x86_64-pc-windows-msvc
        bundle: primary
        build_args: --bin codex --bin codex-responses-api-proxy
      - runner: windows-arm64
        target: aarch64-pc-windows-msvc
        bundle: primary
        build_args: --bin codex --bin codex-responses-api-proxy
      - runner: windows-x64
        target: x86_64-pc-windows-msvc
        bundle: helpers
        build_args: --bin codex-windows-sandbox-setup --bin codex-command-runner
```

| 目标 | bundle 类型 | 构建内容 |
|------|-------------|----------|
| x86_64 | primary | codex.exe, codex-responses-api-proxy.exe |
| aarch64 | primary | codex.exe, codex-responses-api-proxy.exe |
| x86_64 | helpers | codex-windows-sandbox-setup.exe, codex-command-runner.exe |
| aarch64 | helpers | codex-windows-sandbox-setup.exe, codex-command-runner.exe |

#### 构建执行
```yaml
- name: Cargo build (Windows binaries)
  shell: bash
  run: cargo build --target ${{ matrix.target }} --release --timings ${{ matrix.build_args }}
```

- 使用 bash shell（即使在 Windows 上）
- `--timings`：生成构建时间报告

#### 产物暂存
```yaml
- name: Stage Windows binaries
  run: |
    output_dir="target/${{ matrix.target }}/release/staged-${{ matrix.bundle }}"
    mkdir -p "$output_dir"
    if [[ "${{ matrix.bundle }}" == "primary" ]]; then
      cp target/${{ matrix.target }}/release/codex.exe "$output_dir/codex.exe"
      cp target/${{ matrix.target }}/release/codex-responses-api-proxy.exe "$output_dir/codex-responses-api-proxy.exe"
    else
      cp .../codex-windows-sandbox-setup.exe "$output_dir/"
      cp .../codex-command-runner.exe "$output_dir/"
    fi
```

### Job 2: build-windows

#### 产物下载
```yaml
- name: Download prebuilt Windows primary binaries
  uses: actions/download-artifact@v8
  with:
    name: windows-binaries-${{ matrix.target }}-primary
    path: codex-rs/target/${{ matrix.target }}/release

- name: Download prebuilt Windows helper binaries
  uses: actions/download-artifact@v8
  with:
    name: windows-binaries-${{ matrix.target }}-helpers
    path: codex-rs/target/${{ matrix.target }}/release
```

- 从 Job 1 下载构建好的二进制文件
- 分别下载 primary 和 helpers bundle

#### 代码签名
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

使用 Azure Trusted Signing 服务：
- OIDC 登录（通过 `id-token: write` 权限）
- 签名所有 Windows 二进制文件

#### 产物打包
```yaml
- name: Compress artifacts
  run: |
    for f in "$dest"/*; do
      base="$(basename "$f")"
      
      # 跳过已归档文件
      if [[ "$base" == *.tar.gz || "$base" == *.zip || "$base" == *.dmg ]]; then
        continue
      fi
      
      # 创建 tar.gz
      tar -C "$dest" -czf "$dest/${base}.tar.gz" "$base"
      
      # 创建 zip（主程序包含辅助工具）
      if [[ "$base" == "codex-${{ matrix.target }}.exe" ]]; then
        bundle_dir="$(mktemp -d)"
        cp "$dest/$base" "$bundle_dir/$base"
        cp "$runner_src" "$bundle_dir/codex-command-runner.exe"
        cp "$setup_src" "$bundle_dir/codex-windows-sandbox-setup.exe"
        (cd "$bundle_dir" && 7z a "$repo_root/$dest/${base}.zip" .)
      else
        (cd "$dest" && 7z a "${base}.zip" "$base")
      fi
      
      # 创建 zst
      "${GITHUB_WORKSPACE}/.github/workflows/zstd" -T0 -19 "$dest/$base"
    done
```

##### 打包策略

| 格式 | 说明 |
|------|------|
| `.tar.gz` | 通用压缩格式，兼容性好 |
| `.zip` | Windows 原生支持，主程序包含辅助工具 |
| `.zst` | 高压缩率，需要 zstd 工具解压 |

##### 特殊处理：主程序 zip
- `codex-<target>.exe` 的 zip 包含辅助工具
- 便于 WinGet 等包管理器安装
- 如果辅助工具缺失，回退到单二进制 zip

## 关键代码路径与文件引用

| 文件 | 作用 |
|------|------|
| `.github/workflows/rust-release-windows.yml` | 本工作流定义 |
| `.github/actions/windows-code-sign/action.yml` | 代码签名 Action |
| `.github/workflows/zstd` | DotSlash zstd 包装器 |

### 代码签名 Action
```yaml
# .github/actions/windows-code-sign/action.yml
- name: Azure login for Trusted Signing (OIDC)
  uses: azure/login@v2

- name: Sign Windows binaries
  uses: azure/trusted-signing-action@v0
  with:
    endpoint: ${{ inputs.endpoint }}
    trusted-signing-account-name: ${{ inputs.account-name }}
    certificate-profile-name: ${{ inputs.certificate-profile-name }}
    files: |
      ${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/codex.exe
      ...
```

## 依赖与外部交互

### 外部服务
1. **Azure Trusted Signing**：代码签名服务
2. **GitHub Actions 缓存**：artifact 传递

### 自托管运行器
```yaml
runs_on:
  group: codex-runners
  labels: codex-windows-x64
```
- 使用自托管 Windows 运行器
- 标签：`codex-windows-x64`、`codex-windows-arm64`

### 密钥依赖
| 密钥 | 用途 |
|------|------|
| `AZURE_TRUSTED_SIGNING_CLIENT_ID` | Azure AD 应用客户端 ID |
| `AZURE_TRUSTED_SIGNING_TENANT_ID` | Azure AD 租户 ID |
| `AZURE_TRUSTED_SIGNING_SUBSCRIPTION_ID` | Azure 订阅 ID |
| `AZURE_TRUSTED_SIGNING_ENDPOINT` | Trusted Signing 端点 |
| `AZURE_TRUSTED_SIGNING_ACCOUNT_NAME` | 签名账户名 |
| `AZURE_TRUSTED_SIGNING_CERTIFICATE_PROFILE_NAME` | 证书配置文件名 |

### 工具依赖
- `7z`：创建 zip 归档
- `zstd`：创建 zst 压缩（通过 DotSlash）

## 风险、边界与改进建议

### 风险
1. **签名服务依赖**：Azure Trusted Signing 服务不可用会阻塞发布
2. **密钥管理**：大量密钥需要安全管理和轮换
3. **运行器依赖**：依赖自托管 Windows 运行器
4. **架构支持**：ARM64 Windows 支持相对较新，可能不稳定
5. **辅助工具缺失**：如果辅助工具构建失败，回退逻辑可能产生不完整包

### 边界条件
- 需要所有 Azure 签名密钥
- 需要自托管 Windows 运行器
- 主程序 zip 依赖辅助工具存在

### 改进建议
1. **签名验证**：添加步骤验证签名是否成功
2. **健康检查**：添加 Azure 服务健康检查
3. **密钥轮换**：建立密钥轮换流程
4. **回退策略**：签名失败时的处理策略（是否允许未签名发布）
5. **产物验证**：添加 checksum 生成和验证
6. **并行优化**：primary 和 helpers 构建可以进一步并行
7. **缓存优化**：评估 sccache 在 Windows 上的使用

### 建议的签名验证
```yaml
- name: Verify signatures
  run: |
    for exe in target/${{ matrix.target }}/release/*.exe; do
      echo "Checking signature for $exe"
      signtool verify /pa "$exe" || exit 1
    done
```

### 建议的 checksum 生成
```yaml
- name: Generate checksums
  run: |
    cd "codex-rs/dist/${{ matrix.target }}"
    sha256sum * > SHA256SUMS
```
