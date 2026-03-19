# DIR `.github/actions/linux-code-sign` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/actions/linux-code-sign`（DIR）
- 研究日期：2026-03-19
- 目录内容：`action.yml`（单文件 composite action）
- 上下文范围：调用方 workflow、同层签名 action、发布产物归档链路、安装/文档入口、研究自动化清单与 todo 生成脚本。

## 场景与职责

`linux-code-sign` 是 Rust 发布流水线中的 Linux 签名执行单元，位置在“构建成功之后、发布归档之前”。它本身不构建、不上传、不发布，只做 keyless 签名并输出 Sigstore bundle。

1. 触发场景
- 仅在 `rust-release` 的 `build` job 中，且 target 包含 `linux` 时调用（`.github/workflows/rust-release.yml:226-231`）。
- 发布入口是 tag push：`rust-v*.*.*`（`.github/workflows/rust-release.yml:8-13`）。

2. 核心职责
- 安装 `cosign` 工具（`.github/actions/linux-code-sign/action.yml:14-15`）。
- 对两个 Linux 二进制执行 `cosign sign-blob`：`codex`、`codex-responses-api-proxy`（`.github/actions/linux-code-sign/action.yml:34-44`）。
- 生成同目录 `*.sigstore` bundle，供后续打包到 release 资产（`.github/workflows/rust-release.yml:314-317`）。

3. 非职责边界
- 不负责构建二进制（构建在 `cargo build` 阶段完成，`.github/workflows/rust-release.yml:213-218`）。
- 不负责压缩归档（归档在 `Compress artifacts`，`.github/workflows/rust-release.yml:323-357`）。
- 不负责最终 GitHub Release 上传（上传在 `release` job，`.github/workflows/rust-release.yml:506-515`）。

## 功能点目的

1. 建立 Linux 发布物可验证的供应链证明
- 通过 `cosign sign-blob --bundle` 生成 Sigstore bundle，使每个 Linux 可执行文件具备独立签名证据（`.github/actions/linux-code-sign/action.yml:41-44`）。

2. 在不管理私钥的前提下完成签名
- 使用 OIDC 配置（`COSIGN_OIDC_CLIENT_ID`、`COSIGN_OIDC_ISSUER`）进行 keyless 签名（`.github/actions/linux-code-sign/action.yml:23-24`）。
- 对应 workflow 开启 `id-token: write`，为 OIDC 发令牌（`.github/workflows/rust-release.yml:53-55`）。

3. 与发布命名规范对齐
- Stage 阶段把 `codex.sigstore` 重命名为 `codex-<target>.sigstore`，把 `codex-responses-api-proxy.sigstore` 重命名为 `codex-responses-api-proxy-<target>.sigstore`（`.github/workflows/rust-release.yml:315-317`）。
- 压缩阶段明确跳过 `.sigstore`，避免被再次打包（`.github/workflows/rust-release.yml:346-349`）。

4. 用显式失败阻断不完整发布
- `artifacts-dir` 不存在直接失败（`.github/actions/linux-code-sign/action.yml:29-31`）。
- 任一目标二进制缺失直接失败（`.github/actions/linux-code-sign/action.yml:36-39`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 构建产物就位
- `cargo build --target ... --release --bin codex --bin codex-responses-api-proxy` 产出二进制（`.github/workflows/rust-release.yml:217`）。

2. Linux 签名 action 执行
- 输入：`target`（必填）、`artifacts-dir`（必填）（`.github/actions/linux-code-sign/action.yml:3-9`）。
- 安装 cosign：`sigstore/cosign-installer@v3.7.0`（`.github/actions/linux-code-sign/action.yml:14-15`）。
- 运行脚本：
  - 校验目录存在；
  - 遍历固定列表 `codex`、`codex-responses-api-proxy`；
  - 对每个文件执行：
    `cosign sign-blob --yes --bundle <artifact>.sigstore <artifact>`（`.github/actions/linux-code-sign/action.yml:34-44`）。

3. 签名文件进入发布链
- Stage：复制两个 `.sigstore` 到 `dist/<target>/`（`.github/workflows/rust-release.yml:314-317`）。
- Compress：对普通二进制生成 `.tar.gz` 和 `.zst`，但跳过 `.sigstore`（`.github/workflows/rust-release.yml:336-357`）。
- Upload：`actions/upload-artifact@v7` 上传 `dist/<target>/*`（`.github/workflows/rust-release.yml:359-365`）。
- Release job 下载后统一上传到 GitHub Release（`.github/workflows/rust-release.yml:423-425,506-515`）。

### 2) 输入/输出“数据结构”

1. Action 输入结构（`with`）
- `target: string`（目标 triple；在当前实现中仅用于接口一致性，脚本内部未直接读取）
- `artifacts-dir: string`（签名目录，脚本中映射到 `ARTIFACTS_DIR`）（`.github/actions/linux-code-sign/action.yml:20`）

2. Action 输出结构
- 无显式 `outputs`。
- 通过文件副作用输出：`<artifacts-dir>/codex.sigstore` 与 `<artifacts-dir>/codex-responses-api-proxy.sigstore`。

### 3) 协议与身份链路

1. GitHub Actions OIDC -> Sigstore
- job 权限需 `id-token: write`（`.github/workflows/rust-release.yml:53-55`）。
- cosign 使用 `COSIGN_OIDC_CLIENT_ID=sigstore` 与 `COSIGN_OIDC_ISSUER=https://oauth2.sigstore.dev/auth`（`.github/actions/linux-code-sign/action.yml:23-24`）。

2. 构建-签名-分发协议约束
- 签名动作依赖固定二进制文件名，和构建/Stage 命名保持一致：
  - 构建产物：`codex`、`codex-responses-api-proxy`（`.github/workflows/rust-release.yml:217`）
  - 签名对象：同名（`.github/actions/linux-code-sign/action.yml:34-35`）
  - Stage 重命名后发布（`.github/workflows/rust-release.yml:311-317`）

### 4) 关键命令

- `cosign sign-blob --yes --bundle <artifact>.sigstore <artifact>`（签名主命令）
- `cp target/.../*.sigstore dist/...`（发布前归档）
- `zstd -T0 -19 --rm`（仅对二进制压缩，签名 bundle 不压缩）

## 关键代码路径与文件引用

### 目录内核心文件

- `.github/actions/linux-code-sign/action.yml:1-45`

### 调用方（Who calls）

1. 主调用点
- `.github/workflows/rust-release.yml:226-231`

2. 触发与权限前提
- tag 触发：`.github/workflows/rust-release.yml:8-13`
- OIDC 权限：`.github/workflows/rust-release.yml:53-55`

3. 与调用点前后强耦合的步骤
- 调用前构建：`.github/workflows/rust-release.yml:213-218`
- 调用后归档：`.github/workflows/rust-release.yml:305-317`
- 压缩跳过 `.sigstore`：`.github/workflows/rust-release.yml:346-349`

### 同层对照与并行实现

- macOS 签名 action：`.github/actions/macos-code-sign/action.yml:1-251`
- Windows 签名 action：`.github/actions/windows-code-sign/action.yml:1-57`
- Windows 调用点：`.github/workflows/rust-release-windows.yml:173-182`

### 文档/脚本关联路径

- 用户下载 release 资产入口：`README.md:31-45`
- 安装脚本被 release job 一并发布：`.github/workflows/rust-release.yml:501-504`
- 安装文档（构建与安装总入口）：`docs/install.md:1-50`

### 测试与校验现状

- 未发现针对 `.github/actions/linux-code-sign` 的专门单元测试或静态 action 测试配置。
- 当前质量保障主要依赖 release workflow 真实执行中的失败即中断机制。

## 依赖与外部交互

1. 外部 Action 依赖
- `sigstore/cosign-installer@v3.7.0`（`.github/actions/linux-code-sign/action.yml:15`）

2. 外部服务依赖
- Sigstore OIDC Issuer：`https://oauth2.sigstore.dev/auth`（`.github/actions/linux-code-sign/action.yml:24`）
- GitHub OIDC Token（由 Actions `id-token: write` 权限提供，`.github/workflows/rust-release.yml:55`）

3. Runner 与环境依赖
- `bash`、`cosign` 可执行环境。
- `ARTIFACTS_DIR` 指向绝对路径（调用时传入 `${{ github.workspace }}/codex-rs/target/${{ matrix.target }}/release`，`.github/workflows/rust-release.yml:231`）。

4. 与发布分发链的交互
- 上传到 GitHub Release 的 `dist/**` 包含 Linux `.sigstore` 文件（`.github/workflows/rust-release.yml:512`）。
- npm/winget 后续流程依赖同一 release 资产集合，但不直接消费 `.sigstore`（`.github/workflows/rust-release.yml:540-670`）。

## 风险、边界与改进建议

### 风险

1. `target` 输入未被 action 内部使用
- `target` 目前只在调用侧传入，action 脚本未读取，存在接口漂移风险（`.github/actions/linux-code-sign/action.yml:4-6,20-44`）。

2. 签名对象硬编码
- 仅签 `codex` 与 `codex-responses-api-proxy`；若未来新增 Linux 可执行发布物且未更新循环列表，可能漏签（`.github/actions/linux-code-sign/action.yml:34`）。

3. 缺乏验签回归步骤
- 当前流程只签不验，仓库中未见 `cosign verify-blob` 的 CI 校验步骤，问题会在下游使用者验证时才暴露。

4. 外部依赖可用性风险
- 对 Sigstore OIDC 和外部 action 可用性敏感；网络/服务抖动会直接阻断发布。

### 边界

1. 该目录仅负责 Linux 签名动作定义，不负责发布编排。
2. 该目录不维护消费端验签文档，用户侧如何验证签名未在当前仓库 docs 中形成完整指引。
3. 该目录不管理 artifact 命名策略，命名在 `rust-release.yml` 的 Stage 步骤中定义。

### 改进建议

1. 增加签后验签步骤
- 在 `rust-release.yml` 的 Linux 分支里追加 `cosign verify-blob --bundle ...`，形成“签名+验证”闭环。

2. 消除未使用输入
- 两种可选路径：
  - 在 action 内用 `target` 做路径/日志一致性校验；
  - 或移除 `target` 输入，避免误导调用者。

3. 抽象签名清单来源
- 用 manifest（例如 workflow env 或文件清单）驱动签名对象，避免硬编码列表与构建产物脱节。

4. 补充用户验签文档
- 在 `README` 或 `docs/install.md` 增加 Linux 产物 + `.sigstore` 的验签示例，降低供应链可验证性“有产物、无指南”的使用门槛。
