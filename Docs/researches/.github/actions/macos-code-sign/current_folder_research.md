# DIR `.github/actions/macos-code-sign` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/actions/macos-code-sign`（DIR）
- 研究日期：2026-03-19
- 目录内容：`action.yml`、`notary_helpers.sh`
- 上下文覆盖：调用方 workflow、同目录脚本、发布阶段产物流、Secrets/权限配置、文档入口、测试现状。

## 场景与职责

`macos-code-sign` 是 `rust-release` 发布链路里的 macOS 签名与公证执行单元，处于“构建完成后、产物归档前”的关键路径。

1. 触发与调用方式
- 在 `.github/workflows/rust-release.yml` 中被调用两次：
- 第一次用于二进制：`sign-binaries: true`、`sign-dmg: false`（`.github/workflows/rust-release.yml:233-245`）。
- 第二次用于 dmg：`sign-binaries: false`、`sign-dmg: true`（`.github/workflows/rust-release.yml:292-304`）。
- 仅在 `runner.os == 'macOS'` 时触发（`.github/workflows/rust-release.yml:233,246,292`）。

2. 核心职责
- 建立临时 keychain、导入 Apple P12 证书、提取唯一 codesign identity（`.github/actions/macos-code-sign/action.yml:33-115`）。
- 对 `codex` 与 `codex-responses-api-proxy` 进行 `codesign` 并提交 Apple notarization（`.github/actions/macos-code-sign/action.yml:117-185`）。
- 对 `codex-<target>.dmg` 再次签名、公证并 `stapler`（`.github/actions/macos-code-sign/action.yml:186-228`）。
- 使用 `always()` 步骤删除临时 keychain，降低 runner 污染风险（`.github/actions/macos-code-sign/action.yml:230-250`）。

3. 边界（非职责）
- 不负责构建二进制（构建由 `cargo build` 完成，`.github/workflows/rust-release.yml:213-218`）。
- 不负责构建 dmg（dmg 由 `Build macOS dmg` 步骤生成，`.github/workflows/rust-release.yml:247-291`）。
- 不负责最终 release 上传（`softprops/action-gh-release` 在 `release` job 中执行，`.github/workflows/rust-release.yml:506-515`）。

## 功能点目的

1. 满足 macOS 分发可信链要求
- 通过 `codesign + notarytool + stapler`，使二进制与 dmg 满足 Gatekeeper 场景要求。

2. 将发布流程拆为“先签二进制，再封装，再签 dmg”
- 第一次调用 action 确保进入 dmg 的是已签且已公证的可执行文件（`.github/workflows/rust-release.yml:258-263`）。
- 第二次调用 action 为最终可分发介质（dmg）补齐签名与公证。

3. 强失败策略防止“部分可信”产物流出
- 对必需输入、签名身份唯一性、目标文件存在性、公证状态均做硬性检查，任一不满足即失败（`.github/actions/macos-code-sign/action.yml:42-50,94-107,172-174,197-201,216-219`；`.github/actions/macos-code-sign/notary_helpers.sh:8-21,42-44`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 初始化签名环境（每次调用都会执行）
- 从输入读取 Base64 的 P12 与密码（`.github/actions/macos-code-sign/action.yml:15-20,35-39`）。
- 写入临时证书文件：`$RUNNER_TEMP/apple_signing_certificate.p12`（`.github/actions/macos-code-sign/action.yml:52-53`）。
- 创建并解锁临时 keychain：`$RUNNER_TEMP/codex-signing.keychain-db`（`.github/actions/macos-code-sign/action.yml:55-59`）。
- 导入证书并设置 key partition list（`.github/actions/macos-code-sign/action.yml:84-85`）。
- 通过 `security find-identity` + `sed` 提取 40 位 identity hash，要求“恰好 1 个”身份（`.github/actions/macos-code-sign/action.yml:87-109`）。
- 将 `APPLE_CODESIGN_IDENTITY`、`APPLE_CODESIGN_KEYCHAIN` 写入 `GITHUB_ENV` 给后续步骤（`.github/actions/macos-code-sign/action.yml:113-114`）。

2. 二进制签名与公证（`sign-binaries == true`）
- 对 `codex` 与 `codex-responses-api-proxy` 执行：
- `codesign --force --options runtime --timestamp --sign <identity> [--keychain <path>] <binary>`（`.github/actions/macos-code-sign/action.yml:135-138`）。
- 对每个二进制使用 `ditto -c -k --keepParent` 生成 zip，再调用 `notarize_submission`（`.github/actions/macos-code-sign/action.yml:167-184`）。

3. dmg 签名与公证（`sign-dmg == true`）
- 对 `codex-<target>.dmg` 执行 `codesign --force --timestamp`（`.github/actions/macos-code-sign/action.yml:213-227`）。
- 调用 `notarize_submission` 后执行 `xcrun stapler staple`（`.github/actions/macos-code-sign/action.yml:227-228`）。

4. 收尾清理
- `Remove signing keychain` 在 `always()` 条件下执行，移除临时 keychain 并尝试恢复 keychain 列表/默认项（`.github/actions/macos-code-sign/action.yml:230-250`）。
- P8 公证密钥文件在 notarization 步骤里用 `trap` 清理（`.github/actions/macos-code-sign/action.yml:158-163,204-209`）。

### 2) 数据结构与接口约定

1. Action 输入（`with`）
- 控制位：`sign-binaries`、`sign-dmg`（字符串布尔，默认均为 `"true"`）（`.github/actions/macos-code-sign/action.yml:7-14`）。
- 签名凭据：`apple-certificate`、`apple-certificate-password`（`.github/actions/macos-code-sign/action.yml:15-20`）。
- 公证凭据：`apple-notarization-key-p8`、`apple-notarization-key-id`、`apple-notarization-issuer-id`（`.github/actions/macos-code-sign/action.yml:21-29`）。

2. Action 输出
- 无显式 `outputs`。
- 通过副作用输出：目标二进制签名状态变化、dmg 被签名并 stapled、临时 keychain/密钥文件被清理。

3. 脚本函数接口（被调用方）
- `notary_helpers.sh` 暴露 `notarize_submission(label, path, notary_key_path)`（`.github/actions/macos-code-sign/notary_helpers.sh:3-6`）。
- 函数读取环境变量 `APPLE_NOTARIZATION_KEY_ID`、`APPLE_NOTARIZATION_ISSUER_ID`，提交 `xcrun notarytool submit --wait --output-format json`，用 `jq` 解析 `status/id` 并强制 `Accepted`（`.github/actions/macos-code-sign/notary_helpers.sh:8-45`）。

### 3) 协议与命令

1. Apple 代码签名链
- `security create-keychain / import / find-identity / delete-keychain`
- `codesign --timestamp [--options runtime]`

2. Apple 公证链
- `xcrun notarytool submit ... --wait --output-format json`
- `xcrun stapler staple <dmg>`

3. 归档与封装命令
- `ditto -c -k --keepParent`（二进制公证提交包）

4. 运行目录与路径约定
- `rust-release` job 的 `run` 默认工作目录是 `codex-rs`（`.github/workflows/rust-release.yml:56-59`），但 composite action 内部命令使用 `codex-rs/target/...` 路径（`.github/actions/macos-code-sign/action.yml:136,169,214`），这隐含 action 以内仓库根目录为路径基准。

## 关键代码路径与文件引用

### 目录内核心实现
- `.github/actions/macos-code-sign/action.yml:1-250`
- `.github/actions/macos-code-sign/notary_helpers.sh:1-46`

### 调用方（Who calls）
- `.github/workflows/rust-release.yml:233-245`（MacOS code signing binaries）
- `.github/workflows/rust-release.yml:292-304`（MacOS code signing dmg）

### 上下游强耦合步骤
- 调用前构建：`.github/workflows/rust-release.yml:213-218`
- 两次调用中间构建 dmg：`.github/workflows/rust-release.yml:247-291`
- 调用后归档 dmg 到发布目录：`.github/workflows/rust-release.yml:319-321`
- 最终发布：`.github/workflows/rust-release.yml:506-515`

### 配置、脚本、文档、测试关联
1. 配置/Secrets
- Apple 相关 secrets 透传：`.github/workflows/rust-release.yml:240-244,299-303`。

2. 脚本
- 目录内脚本：`.github/actions/macos-code-sign/notary_helpers.sh`。
- workflow 内 dmg 构建脚本：`.github/workflows/rust-release.yml:247-291`。

3. 文档
- Release 下载入口（用户最终消费签名产物）：`README.md:31-45`。
- 安装/构建文档总入口：`docs/install.md:1-50`。

4. 测试
- 未发现针对 `.github/actions/macos-code-sign` 的独立单元测试或 action 级 CI 验证。
- 现状主要依赖 `rust-release` 真机流水线作为集成验证。

## 依赖与外部交互

1. Runner 与工具依赖（macOS）
- `bash`、`security`、`codesign`、`xcrun`（`notarytool`、`stapler`）、`ditto`、`jq`、`base64`。

2. 外部服务交互
- Apple Notary 服务（通过 `xcrun notarytool submit`）。
- GitHub Actions Secrets（证书与公证凭据输入）。

3. 与仓库流程交互
- 与构建产物目录耦合：`codex-rs/target/<target>/release/*`。
- 与发布归档链路耦合：签名后的二进制/dmg 在 `dist/**` 上传为 release 资产（`.github/workflows/rust-release.yml:305-365,506-515`）。

## 风险、边界与改进建议

### 风险

1. 路径基准隐式耦合
- action 内路径硬编码 `codex-rs/target/...`，若调用方改变 checkout 结构或工作目录语义，易导致找不到文件。

2. 签名对象硬编码
- 二进制列表固定为 `codex`、`codex-responses-api-proxy`（`.github/actions/macos-code-sign/action.yml:135,183-184`）。新增 macOS 发布二进制时存在漏签风险。

3. 工具可用性隐式依赖
- `jq` 是公证结果解析关键依赖（`.github/actions/macos-code-sign/notary_helpers.sh:32-33`），当前没有显式可用性检测与安装兜底。

4. 多次调用导致重复初始化
- 同一 job 内该 action 调用两次，每次都创建/删除 keychain，逻辑更稳妥但增加执行时间与排障复杂度。

### 边界

1. 该目录只负责签名与公证执行，不定义 release 触发策略。
2. 该目录不维护证书生命周期与 secrets 轮换策略。
3. 该目录不提供用户侧验证说明（例如如何本地验证 notarization/staple）。

### 改进建议

1. 增加工具预检
- 在 action 开头增加 `command -v jq`、`xcrun notarytool --version` 预检，失败时给出明确修复提示。

2. 提取签名清单为单一配置源
- 将签名目标列表从脚本硬编码改为 workflow 传参或 manifest，减少新增二进制时的维护遗漏。

3. 增加 action 静态校验与最小集成测试
- 在 PR CI 加入 `actionlint`/shell 脚本检查；可补一个最小模拟测试验证参数缺失与路径缺失分支。

4. 明确路径契约
- 在 `action.yml` 描述中注明“路径基于仓库根目录”，或引入 `artifacts-dir` 输入以降低调用方耦合。
