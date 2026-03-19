# DIR `.github/actions` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/actions`（DIR）
- 研究日期：2026-03-19
- 研究范围：`linux-code-sign`、`macos-code-sign`、`windows-code-sign` 三个 composite action，以及其在 release workflow、脚本、文档、测试链路中的上下游依赖。

## 场景与职责

`.github/actions` 是 Codex 发布流水线中的“签名与公证执行层”，位于 `rust-release*` workflow 的构建产物之后、归档与发布之前。

1. Linux 签名职责
- 对 Linux 产物 `codex` 与 `codex-responses-api-proxy` 执行 cosign `sign-blob`，产出 `*.sigstore` 证明文件（`.github/actions/linux-code-sign/action.yml:34-44`）。
- 在主发布工作流中仅对 Linux target 执行（`.github/workflows/rust-release.yml:226-231`）。

2. macOS 签名与 notarization 职责
- 建立临时 keychain，导入 Apple 证书，提取唯一 codesign identity（`.github/actions/macos-code-sign/action.yml:55-115`）。
- 分两类目标处理：二进制（`sign-binaries=true`）与 dmg（`sign-dmg=true`），并统一走 notarytool 公证（`.github/actions/macos-code-sign/action.yml:117-228`）。
- 工作流中被调用两次：先签名+公证二进制，再打包 dmg 后二次签名+公证 dmg（`.github/workflows/rust-release.yml:233-304`）。

3. Windows 签名职责
- 通过 Azure OIDC 登录并调用 Trusted Signing Action 批量签名 4 个 exe（`.github/actions/windows-code-sign/action.yml:29-57`）。
- 由 `rust-release-windows` 的第二阶段在下载预构建产物后执行（`.github/workflows/rust-release-windows.yml:152-182`）。

## 功能点目的

1. 供应链完整性与可验证性
- Linux 使用 Sigstore 生成 bundle，随发布资产分发，便于后续验签（`.github/actions/linux-code-sign/action.yml:41-44`，`.github/workflows/rust-release.yml:314-317`）。
- macOS 通过 Apple 官方链路（codesign + notarytool + stapler）满足 Gatekeeper 分发要求（`.github/actions/macos-code-sign/action.yml:226-228`，`.github/actions/macos-code-sign/notary_helpers.sh:24-44`）。
- Windows 使用 Azure Trusted Signing 满足 Authenticode 分发要求，并覆盖主程序与沙箱辅助程序（`.github/actions/windows-code-sign/action.yml:53-57`）。

2. 将平台差异封装成统一接口
- 三个 action 都以 `target` 作为核心输入，调用方 workflow 不需要重复写平台签名细节（`linux-code-sign/action.yml:3-9`，`macos-code-sign/action.yml:3-29`，`windows-code-sign/action.yml:3-24`）。

3. 在 release 关键路径中控制失败边界
- 各 action 在输入缺失、目标文件不存在、签名身份异常时 `exit 1`，确保不发布未签名或签名状态不明的产物（例如 `.github/actions/macos-code-sign/action.yml:42-50,94-107,216-219`；`.github/actions/linux-code-sign/action.yml:29-39`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. Linux 签名流程
- 安装 `sigstore/cosign-installer@v3.7.0`（`.github/actions/linux-code-sign/action.yml:14-15`）。
- 设置 OIDC 相关环境变量并遍历固定二进制列表签名（`.github/actions/linux-code-sign/action.yml:20-24,34-44`）。
- 产物命名规则：`<binary>.sigstore`，后续由 release workflow 拷贝到 `dist/<target>/`（`.github/workflows/rust-release.yml:315-317`）。

2. macOS 签名与公证流程
- `Configure Apple code signing`：
  - Base64 解码 `.p12` -> 创建临时 keychain -> `security import` -> 提取 40 位签名 hash（`.github/actions/macos-code-sign/action.yml:52-92`）。
  - 强约束“恰好一个签名身份”，否则失败（`.github/actions/macos-code-sign/action.yml:94-107`）。
  - 将 `APPLE_CODESIGN_IDENTITY` 与 `APPLE_CODESIGN_KEYCHAIN` 写入 `GITHUB_ENV`（`.github/actions/macos-code-sign/action.yml:113-115`）。
- `Sign macOS binaries`：对 `codex` 与 `codex-responses-api-proxy` 执行 `codesign --options runtime --timestamp`（`.github/actions/macos-code-sign/action.yml:135-138`）。
- `Notarize macOS binaries`：对每个二进制先 `ditto -c -k --keepParent` 再调用 `notarize_submission`（`.github/actions/macos-code-sign/action.yml:167-184`）。
- `Sign and notarize macOS dmg`：对 `codex-<target>.dmg` 再签名、公证、`stapler staple`（`.github/actions/macos-code-sign/action.yml:213-228`）。
- `Remove signing keychain`：`always()` 清理 keychain，避免 runner 污染（`.github/actions/macos-code-sign/action.yml:230-250`）。

3. Windows 签名流程
- `azure/login@v2` 使用 `client-id/tenant-id/subscription-id` 做 OIDC 登录（`.github/actions/windows-code-sign/action.yml:29-35`）。
- `azure/trusted-signing-action@v0` 配置 credential 选择策略，仅允许 Azure CLI 凭据路径（`.github/actions/windows-code-sign/action.yml:42-51`）。
- 固定签名文件清单包含 4 个 exe（`.github/actions/windows-code-sign/action.yml:53-57`）。

### 2) 数据结构与协议

1. Composite action 输入协议
- Linux：`target` + `artifacts-dir`（`.github/actions/linux-code-sign/action.yml:3-9`）。
- macOS：布尔开关（字符串）`sign-binaries/sign-dmg` + Apple 证书/公证凭据（`.github/actions/macos-code-sign/action.yml:7-29`）。
- Windows：Azure Trusted Signing 六元组参数（`.github/actions/windows-code-sign/action.yml:7-24`）。

2. 产物协议
- Linux：二进制同目录生成 `.sigstore` bundle，最终进入 release 资产（`.github/workflows/rust-release.yml:305-321`）。
- macOS：最终包含 `.dmg` 资产；二进制签名状态通过先签名后打包流程继承（`.github/workflows/rust-release.yml:247-291`）。
- Windows：签名后再做 `.tar.gz/.zip/.zst`，其中主 `codex.exe.zip` 额外捆绑 sandbox helper 两个 exe（`.github/workflows/rust-release-windows.yml:231-257`）。

3. 失败协议
- 主要通过 shell `set -euo pipefail` + 显式文件/变量检查保证失败即中断（如 `.github/actions/macos-code-sign/action.yml:40,123,149,195`）。
- notarization helper 以 `xcrun notarytool ... --output-format json --wait` 返回状态，必须 `Accepted` 才放行（`.github/actions/macos-code-sign/notary_helpers.sh:24-44`）。

### 3) 关键命令

- Linux：`cosign sign-blob --bundle`。
- macOS：`security create-keychain/import/find-identity`、`codesign`、`xcrun notarytool submit --wait`、`xcrun stapler staple`。
- Windows：`azure/login` + `azure/trusted-signing-action`。
- 上游构建脚本：musl 目标在签名前通过 `.github/scripts/install-musl-build-tools.sh` 注入交叉编译工具链和 `PKG_CONFIG_*`/`CARGO_TARGET_*_LINKER` 环境（`.github/scripts/install-musl-build-tools.sh:19-279`）。

## 关键代码路径与文件引用

### A. 目录内核心文件

- `.github/actions/linux-code-sign/action.yml`
- `.github/actions/macos-code-sign/action.yml`
- `.github/actions/macos-code-sign/notary_helpers.sh`
- `.github/actions/windows-code-sign/action.yml`

### B. 调用方（Who calls）

1. 主发布 workflow
- Linux/macos action 调用点：`.github/workflows/rust-release.yml:226-245,292-304`。
- 产物归档与发布：`.github/workflows/rust-release.yml:305-365,423-523`。

2. Windows 子工作流
- windows action 调用点：`.github/workflows/rust-release-windows.yml:173-182`。
- 其上游由 `rust-release` 通过 `workflow_call` 复用：`.github/workflows/rust-release.yml:367-372`。

3. 发布触发入口
- Tag `rust-v*.*.*` 触发发布总流程（`.github/workflows/rust-release.yml:8-13`）。

### C. 被调用方（What actions call）

1. GitHub Action 依赖
- `sigstore/cosign-installer@v3.7.0`（Linux）。
- `azure/login@v2`、`azure/trusted-signing-action@v0`（Windows）。

2. 平台工具依赖
- macOS runner 上的 `security`、`codesign`、`xcrun notarytool`、`xcrun stapler`、`jq`（见 `macos-code-sign` 脚本步骤）。

### D. 配置、脚本、文档、测试上下文

1. 配置与 secrets
- Apple secrets 来源：`.github/workflows/rust-release.yml:240-244,299-303`。
- Azure secrets 来源：`.github/workflows/rust-release-windows.yml:177-182`。
- 签名流程需 job 级 `id-token: write`（Linux 主 build、Windows build-windows）：`.github/workflows/rust-release.yml:53-55`，`.github/workflows/rust-release-windows.yml:127-129`。

2. 脚本依赖
- musl 编译前置：`.github/scripts/install-musl-build-tools.sh:19-279`。
- Windows 压缩依赖 DotSlash zstd 包装器：`.github/workflows/zstd:1-46` 与 `.github/workflows/rust-release-windows.yml:257`。

3. 文档依赖
- 用户下载发布产物的入口在 README 的 GitHub Release 指引（`README.md:32-43`），签名 action 直接影响这些产物可信度。

4. 测试现状
- 当前未发现针对 `.github/actions/*` 的独立单元测试/集成测试脚本；质量主要依赖 `rust-release`/`rust-release-windows` 实际运行结果与失败即终止机制。

## 依赖与外部交互

1. 外部服务
- Sigstore OIDC（Linux）：`COSIGN_OIDC_ISSUER=https://oauth2.sigstore.dev/auth`（`.github/actions/linux-code-sign/action.yml:23-24`）。
- Apple Notary 服务（macOS）：`xcrun notarytool submit --wait`（`.github/actions/macos-code-sign/notary_helpers.sh:24-29`）。
- Azure Trusted Signing（Windows）：`azure/login` + `azure/trusted-signing-action`（`.github/actions/windows-code-sign/action.yml:29-41`）。

2. 与仓库其他流程的交互
- 与构建链：签名前要求目标二进制已存在；不存在即失败（Linux: `.github/actions/linux-code-sign/action.yml:34-39`，macOS: `.github/actions/macos-code-sign/action.yml:172-174`）。
- 与发布链：签名产物进入 `dist/**` 后被 `softprops/action-gh-release` 上传（`.github/workflows/rust-release.yml:506-515`）。
- 与 npm/winget 分发链：release job 发布后，npm 与 winget job 消费同一 tag 的发布资产（`.github/workflows/rust-release.yml:540-670`）。

3. 与调用工具协议
- 所有 action 使用 `composite` + `with` 输入，未定义 outputs；调用方通过约定路径读取副产物（如 `.sigstore`、`.dmg`、`.exe`）。

## 风险、边界与改进建议

### 风险

1. 供应链版本漂移
- `azure/trusted-signing-action@v0` 使用浮动主版本标签，存在上游不兼容变更风险（`.github/actions/windows-code-sign/action.yml:37`）。

2. 证书身份唯一性约束较硬
- macOS action 要求 keychain 中仅 1 个 codesign identity；若证书包策略变化（多个 identity），会直接阻断发布（`.github/actions/macos-code-sign/action.yml:101-107`）。

3. 文件列表硬编码
- Linux 固定仅签 `codex` 与 `codex-responses-api-proxy`；Windows 固定 4 个 exe。新增可执行文件时若漏改，可能出现“发布资产中部分未签名”（`.github/actions/linux-code-sign/action.yml:34`，`.github/actions/windows-code-sign/action.yml:53-57`）。

4. 隐式工具前提
- `macos-code-sign` 依赖 runner 自带 `jq`；脚本无安装步骤，若 runner 基线变化会在公证解析阶段失败（`.github/actions/macos-code-sign/notary_helpers.sh:32-33`）。

### 边界

1. 本目录只负责签名/公证执行，不负责编译、版本生成、最终发布页面元数据。
2. 触发与编排边界在 `.github/workflows/rust-release.yml` 与 `.github/workflows/rust-release-windows.yml`。
3. 业务代码仓（`codex-rs`/`codex-cli`）只提供待签名二进制，不直接感知签名实现细节。

### 改进建议

1. 将关键第三方 action 固定到 commit SHA
- 优先处理 `azure/trusted-signing-action@v0`，降低供应链漂移风险。

2. 收敛签名文件清单为单一来源
- 建议在 workflow 侧维护“待签名 artifact manifest”，3 个 action 按 manifest 签名，减少新增二进制时的漏签概率。

3. 增加 actionlint / dry-run 校验
- 在 PR CI 中加入对 `.github/actions/**/action.yml` 的静态校验，至少覆盖语法与引用一致性；当前缺少专门测试。

4. 显式声明 macOS 工具依赖
- 在 action 内添加 `jq` 可用性检查（或安装步骤），降低 runner 镜像变化造成的偶发发布失败。
