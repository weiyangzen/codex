# macos-code-sign GitHub Action 研究文档

## 场景与职责

`macos-code-sign` 是一个 GitHub Composite Action，专门用于在 CI/CD 流水线中对 macOS 平台的 Rust 二进制产物进行完整的代码签名和公证流程。该 Action 是 OpenAI Codex 项目发布流程的关键组成部分，确保 macOS 用户能够安全地运行下载的二进制文件，避免 Gatekeeper 拦截。

### 核心职责
1. **代码签名（Code Signing）**：使用 Apple Developer ID 证书对二进制文件进行签名
2. **公证（Notarization）**：将签名后的二进制提交给 Apple 进行公证验证
3. **DMG 签名与公证**：对 macOS 安装包（DMG）进行签名、公证和钉合（Staple）
4. **密钥链管理**：安全地创建、配置和清理临时密钥链

### 使用场景
该 Action 在 `rust-release.yml` 工作流中被调用两次：
1. **第一次调用**（行 233-244）：仅签名和公证二进制文件（`codex` 和 `codex-responses-api-proxy`）
2. **第二次调用**（行 292-303）：仅签名和公证 DMG 安装包

这种分离设计确保二进制文件先被签名公证，然后打包成 DMG，最后 DMG 本身也经过签名公证流程。

---

## 功能点目的

### 1. Apple 代码签名配置（Configure Apple code signing）

**目的**：建立安全的签名环境，导入 Apple 开发者证书并配置密钥链。

**关键输入**：
- `apple-certificate`：Base64 编码的 P12 格式签名证书
- `apple-certificate-password`：证书解锁密码

**输出环境变量**：
- `APPLE_CODESIGN_IDENTITY`：签名身份（证书哈希）
- `APPLE_CODESIGN_KEYCHAIN`：临时密钥链路径

### 2. 二进制文件签名（Sign macOS binaries）

**目的**：对 Rust 编译产物进行代码签名，启用运行时 hardened runtime。

**签名参数**：
- `--force`：强制重新签名
- `--options runtime`：启用 hardened runtime（必要选项以通过公证）
- `--timestamp`：添加可信时间戳

**目标二进制**：
- `codex-rs/target/${TARGET}/release/codex`
- `codex-rs/target/${TARGET}/release/codex-responses-api-proxy`

### 3. 二进制文件公证（Notarize macOS binaries）

**目的**：将签名后的二进制提交给 Apple 公证服务进行恶意软件扫描。

**流程**：
1. 使用 `ditto` 将二进制打包为 ZIP 格式
2. 调用 `notarytool submit` 提交公证
3. 等待公证完成（`--wait` 模式）
4. 验证公证状态

### 4. DMG 签名与公证（Sign and notarize macOS dmg）

**目的**：对 DMG 安装包进行完整的签名-公证-钉合流程。

**特殊处理**：
- DMG 签名后需要执行 `stapler staple` 将公证凭证"钉合"到 DMG 文件中
- 这使得离线安装时 Gatekeeper 也能验证公证状态

### 5. 密钥链清理（Remove signing keychain）

**目的**：无论流程成功与否，都安全地清理临时密钥链。

**特点**：
- 使用 `if: ${{ always() }}` 确保总是执行
- 恢复原始密钥链列表
- 删除临时密钥链文件

---

## 具体技术实现

### 密钥链管理流程

```bash
# 1. 创建临时密钥链
security create-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"  # 6小时超时
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$keychain_path"

# 2. 保存原始密钥链列表
while IFS= read -r keychain; do
  [[ -n "$keychain" ]] && keychain_args+=("$keychain")
done < <(security list-keychains | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/"//g')

# 3. 将临时密钥链添加到搜索列表
security list-keychains -s "$keychain_path" "${keychain_args[@]}"
security default-keychain -s "$keychain_path"

# 4. 导入证书
security import "$cert_path" -k "$keychain_path" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security

# 5. 设置密钥分区列表（允许 codesign 访问私钥）
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$keychain_path"
```

### 签名身份验证

```bash
# 提取所有代码签名身份（40位十六进制哈希）
codesign_hashes=()
while IFS= read -r hash; do
  [[ -n "$hash" ]] && codesign_hashes+=("$hash")
done < <(security find-identity -v -p codesigning "$keychain_path" \
  | sed -n 's/.*\([0-9A-F]\{40\}\).*/\1/p' \
  | sort -u)

# 严格验证：必须且只能有一个签名身份
if ((${#codesign_hashes[@]} == 0)); then
  echo "No signing identities found"
  exit 1
fi

if ((${#codesign_hashes[@]} > 1)); then
  echo "Multiple signing identities found"
  exit 1
fi
```

### 代码签名命令

```bash
codesign --force --options runtime --timestamp --sign "$APPLE_CODESIGN_IDENTITY" \
  --keychain "$keychain_path" "$binary_path"
```

**参数说明**：
- `--options runtime`：启用 hardened runtime，这是公证的必要条件
- `--timestamp`：添加 RFC 3161 时间戳，确保签名在证书过期后仍然有效

### 公证提交流程（调用 notary_helpers.sh）

```bash
# 1. 准备公证密钥
notary_key_path="${RUNNER_TEMP}/notarytool.key.p8"
echo "$APPLE_NOTARIZATION_KEY_P8" | base64 -d > "$notary_key_path"

# 2. 打包二进制为 ZIP
ditto -c -k --keepParent "$source_path" "$archive_path"

# 3. 调用公证函数
notarize_submission "$binary_name" "$archive_path" "$notary_key_path"
```

### DMG 钉合（Staple）

```bash
# 签名 DMG
codesign --force --timestamp --sign "$APPLE_CODESIGN_IDENTITY" "$dmg_path"

# 提交公证
notarize_submission "$dmg_name" "$dmg_path" "$notary_key_path"

# 钉合公证凭证（仅 DMG 需要，二进制文件不需要）
xcrun stapler staple "$dmg_path"
```

---

## 关键代码路径与文件引用

### 当前文件
- **路径**：`.github/actions/macos-code-sign/action.yml`
- **类型**：GitHub Composite Action
- **行数**：251 行

### 依赖文件
- **`.github/actions/macos-code-sign/notary_helpers.sh`**：公证辅助函数，提供 `notarize_submission` 函数
  - 路径通过 `$GITHUB_ACTION_PATH` 环境变量引用
  - 使用 `source "$GITHUB_ACTION_PATH/notary_helpers.sh"` 加载

### 调用方
- **`.github/workflows/rust-release.yml`**：Rust 发布工作流
  - 第 233-244 行：第一次调用（签名二进制）
  - 第 292-303 行：第二次调用（签名 DMG）

### 输入参数映射

| Action 输入 | 工作流传入值 | 来源 |
|------------|-------------|------|
| `apple-certificate` | `${{ secrets.APPLE_CERTIFICATE_P12 }}` | GitHub Secrets |
| `apple-certificate-password` | `${{ secrets.APPLE_CERTIFICATE_PASSWORD }}` | GitHub Secrets |
| `apple-notarization-key-p8` | `${{ secrets.APPLE_NOTARIZATION_KEY_P8 }}` | GitHub Secrets |
| `apple-notarization-key-id` | `${{ secrets.APPLE_NOTARIZATION_KEY_ID }}` | GitHub Secrets |
| `apple-notarization-issuer-id` | `${{ secrets.APPLE_NOTARIZATION_ISSUER_ID }}` | GitHub Secrets |

### 目标产物路径

```
codex-rs/target/${TARGET}/release/
├── codex                              # 主二进制
├── codex-responses-api-proxy          # API 代理二进制
└── codex-${TARGET}.dmg                # DMG 安装包
```

---

## 依赖与外部交互

### 系统依赖

| 工具 | 用途 | 来源 |
|------|------|------|
| `security` | 密钥链管理 | macOS 系统自带 |
| `codesign` | 代码签名 | macOS 系统自带（Xcode Command Line Tools） |
| `xcrun notarytool` | 公证提交 | Xcode |
| `xcrun stapler` | 公证凭证钉合 | Xcode |
| `ditto` | 文件打包 | macOS 系统自带 |
| `hdiutil` | DMG 创建 | macOS 系统自带（在工作流中调用） |
| `jq` | JSON 解析 | 假设已安装（notary_helpers.sh 中使用） |

### Apple 服务交互

1. **Apple Developer Portal**：证书和公证密钥的来源
2. **Apple Notary Service**：公证提交和状态查询
   - 使用 JWT 认证（P8 密钥 + Key ID + Issuer ID）
   - 同步等待模式（`--wait`）

### GitHub 环境集成

| 环境变量 | 用途 |
|---------|------|
| `RUNNER_TEMP` | 临时文件存储路径 |
| `GITHUB_ENV` | 跨步骤传递环境变量 |
| `GITHUB_ACTION_PATH` | 当前 Action 所在目录 |
| `GITHUB_WORKSPACE` | 仓库检出目录 |

---

## 风险、边界与改进建议

### 已知风险

#### 1. 证书和密钥安全
- **风险**：P12 证书和 P8 密钥通过 GitHub Secrets 传入，但在运行时会临时写入磁盘
- **缓解措施**：
  - 使用 `set -euo pipefail` 确保错误时立即退出
  - 使用 `trap` 和 cleanup 函数确保临时文件被删除
  - 密钥链密码硬编码为 `"actions"`（仅用于临时密钥链）

#### 2. 公证超时
- **风险**：`notarytool submit --wait` 可能长时间阻塞
- **现状**：没有设置显式超时，依赖 GitHub Actions 作业超时（60 分钟）
- **建议**：考虑添加 `--timeout` 参数或 wrapping timeout

#### 3. 多身份证书处理
- **风险**：如果 P12 文件包含多个证书，Action 会明确失败
- **现状**：代码检查并拒绝多身份情况（行 101-107）
- **建议**：这是有意为之的安全特性，确保签名身份明确

#### 4. 密钥链并发冲突
- **风险**：多个作业同时修改系统密钥链列表可能导致冲突
- **缓解**：使用临时密钥链，并在完成后恢复原始列表

### 边界条件

| 场景 | 行为 |
|------|------|
| `sign-binaries: false` | 跳过二进制签名和公证步骤 |
| `sign-dmg: false` | 跳过 DMG 签名和公证步骤 |
| 证书导入失败 | 立即退出，清理密钥链 |
| 找不到签名身份 | 退出并显示错误 |
| 多个签名身份 | 退出并显示所有身份 |
| 公证失败 | 通过 `notarize_submission` 函数退出 |
| DMG 不存在 | 退出并显示错误 |

### 改进建议

#### 1. 添加重试机制
公证服务偶尔可能暂时不可用，建议添加指数退避重试：
```bash
for i in {1..3}; do
  if notarize_submission ...; then
    break
  fi
  sleep $((2 ** i))
done
```

#### 2. 优化错误信息
当前错误信息较为简单，建议添加更多上下文：
- 显示证书主题名称
- 显示公证提交 ID 的查询链接
- 提供故障排除文档链接

#### 3. 支持并发公证
当前使用 `--wait` 同步等待，可以考虑：
- 使用 `--no-wait` 提交
- 保存 submission ID
- 在后续步骤中轮询状态
- 这样可以并行处理多个二进制

#### 4. 添加验证步骤
建议在签名和公证后添加验证：
```bash
# 验证签名
codesign --verify --deep --strict "$path"

# 验证公证（仅 DMG）
spctl --assess --type open --context context:primary-signature "$dmg_path"
```

#### 5. 密钥链密码随机化
当前使用硬编码密码 `"actions"`，虽然风险较低（临时密钥链），但建议使用随机生成的密码：
```bash
KEYCHAIN_PASSWORD=$(openssl rand -base64 32)
```

#### 6. 缓存公证凭证
对于重复构建相同版本的情况，可以考虑缓存公证结果，避免重复提交。

### 相关对比

与项目中的其他代码签名 Action 对比：

| 特性 | macOS | Linux | Windows |
|------|-------|-------|---------|
| 签名工具 | `codesign` | `cosign` | Azure Trusted Signing |
| 信任模型 | Apple PKI | Sigstore/OIDC | Azure PKI |
| 公证/验证 | Apple Notary Service | Rekor 透明日志 | 无额外验证 |
| 密钥管理 | P12 + P8 文件 | OIDC 临时凭证 | Azure Managed Identity |
| 产物格式 | 二进制 + DMG | 二进制 + Sigstore bundle | EXE + ZIP |
