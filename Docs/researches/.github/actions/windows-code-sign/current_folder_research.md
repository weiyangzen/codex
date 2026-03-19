# DIR `.github/actions/windows-code-sign` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/actions/windows-code-sign`（DIR）
- 研究日期：2026-03-19
- 目录内容：`action.yml`（单文件 composite action）
- 研究范围：目录本体、调用方 workflow、发布与分发消费链（GitHub Release/WinGet/npm/安装脚本）、相关二进制被调用关系、配置与测试现状。

## 场景与职责

`windows-code-sign` 是 Windows 发布链路中的“签名执行单元”，位于 `rust-release-windows` 的二阶段流水线中：先构建并汇总四个 Windows 可执行文件，再统一签名，然后才进入归档与发布。

1. 触发场景
- 由主发布 workflow `rust-release` 复用调用：`build-windows` job 使用 `./.github/workflows/rust-release-windows.yml`，并 `secrets: inherit`（`.github/workflows/rust-release.yml:367-372`）。
- 在 `rust-release-windows` 内，真正执行签名的是 `build-windows` job 的 `Sign Windows binaries with Azure Trusted Signing` 步骤（`.github/workflows/rust-release-windows.yml:121-183`）。

2. 核心职责
- 使用 GitHub OIDC + Azure 登录建立签名会话（`.github/actions/windows-code-sign/action.yml:29-35`）。
- 调用 Azure Trusted Signing 对四个固定文件批量签名：
  - `codex.exe`
  - `codex-responses-api-proxy.exe`
  - `codex-windows-sandbox-setup.exe`
  - `codex-command-runner.exe`
  （`.github/actions/windows-code-sign/action.yml:53-57`）

3. 上下游边界
- 上游（调用方前置）负责构建、拆分上传 primary/helpers 两组产物并回收到签名前目录（`.github/workflows/rust-release-windows.yml:24-120,152-171`）。
- 下游（调用方后置）负责重命名、压缩（`.tar.gz/.zip/.zst`）和上传 artifacts（`.github/workflows/rust-release-windows.yml:184-264`）。
- 本目录不负责构建、不负责压缩、不负责发布页面上传，仅负责签名动作定义。

## 功能点目的

1. 保证 Windows 发布资产在分发前完成 Authenticode 签名
- 签名步骤处于 Stage/Compress 之前，确保后续所有归档物基于已签名 exe 生成（`.github/workflows/rust-release-windows.yml:173-258`）。

2. 覆盖主程序与沙箱辅助程序
- 四个签名目标不只包含 `codex.exe`，还包含 `codex-windows-sandbox-setup.exe` 和 `codex-command-runner.exe`，与 Windows 沙箱链路依赖保持一致（`.github/actions/windows-code-sign/action.yml:56-57`；`codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs:434-443`；`codex-rs/windows-sandbox-rs/src/helper_materialization.rs:17-25`）。

3. 为多消费端提供统一“已签名源资产”
- WinGet：仅消费主安装 zip（`codex-<target>.exe.zip`），但 zip 内被显式打包 helper exe（`.github/workflows/rust-release-windows.yml:231-245`；`.github/workflows/rust-release.yml:662-670`）。
- npm 平台包：Windows 平台包显式包含 `codex-windows-sandbox-setup` 与 `codex-command-runner`（`codex-cli/scripts/build_npm_package.py:76-77`）。
- 安装脚本：Windows 安装会部署 `codex.exe`、`codex-command-runner.exe`、`codex-windows-sandbox-setup.exe`（`scripts/install/install.ps1:147-151`）。

4. 最小化凭据来源歧义
- Trusted Signing 配置明确关闭绝大部分 credential provider，仅保留 Azure CLI credential（`exclude-azure-cli-credential: false`，其他大多为 `true`），降低 runner 上多身份来源干扰（`.github/actions/windows-code-sign/action.yml:42-51`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 主 workflow 进入 Windows 子流程
- `rust-release` 在 tag 发布中触发 `build-windows` 复用工作流（`.github/workflows/rust-release.yml:367-372`）。

2. 子流程阶段一：并行构建与产物分组
- `build-windows-binaries` 按 target（x64/arm64）和 bundle（primary/helpers）矩阵构建（`.github/workflows/rust-release-windows.yml:36-67`）。
- primary 生成 `codex.exe` 与 `codex-responses-api-proxy.exe`；helpers 生成 `codex-windows-sandbox-setup.exe` 与 `codex-command-runner.exe`（`.github/workflows/rust-release-windows.yml:106-112`）。

3. 子流程阶段二：汇总、验收、签名
- 下载两类 artifacts 到同一 release 目录（`.github/workflows/rust-release-windows.yml:152-163`）。
- 通过 `ls -lh` 显式验证四个目标文件存在（`.github/workflows/rust-release-windows.yml:164-171`）。
- 调用 `./.github/actions/windows-code-sign` 执行签名（`.github/workflows/rust-release-windows.yml:173-182`）。

4. 签名后归档分发
- 将签名后的 exe 重命名为 `*-<target>.exe` 进入 `dist/<target>`（`.github/workflows/rust-release-windows.yml:184-193`）。
- 生成 `.tar.gz`/`.zip`/`.zst` 并上传（`.github/workflows/rust-release-windows.yml:198-264`）。
- release job 汇总 `dist/**` 发布到 GitHub Release（`.github/workflows/rust-release.yml:423-425,506-515`）。

### 2) Action 输入“数据结构”

`windows-code-sign` 的接口是 7 个必填输入（`.github/actions/windows-code-sign/action.yml:3-24`）：
- `target`: Rust target triple（用于拼接签名文件路径）
- `client-id`
- `tenant-id`
- `subscription-id`
- `endpoint`
- `account-name`
- `certificate-profile-name`

无 `outputs`，通过“文件被签名”这一副作用对调用方生效。

### 3) 身份与协议

1. GitHub OIDC -> Azure 登录
- 调用方 job 需 `id-token: write`（`.github/workflows/rust-release-windows.yml:127-129`）。
- action 内通过 `azure/login@v2` 用服务主体三元组登录（`.github/actions/windows-code-sign/action.yml:29-35`）。

2. Azure Trusted Signing 批量签名
- 采用 `azure/trusted-signing-action@v0`（`.github/actions/windows-code-sign/action.yml:37`）。
- 使用 account/profile/endpoint 组合定位签名服务（`.github/actions/windows-code-sign/action.yml:39-41`）。
- `files: |` 多行输入一次性传递 4 个绝对路径（`.github/actions/windows-code-sign/action.yml:53-57`）。

### 4) 关键命令与路径契约

- 构建命令：`cargo build --target <triple> --release --timings <bins>`（`.github/workflows/rust-release-windows.yml:89-93`）。
- 签名前存在性校验：`ls -lh target/<triple>/release/*.exe`（`.github/workflows/rust-release-windows.yml:164-171`）。
- 签名目标路径基于：`${{ github.workspace }}/codex-rs/target/${{ inputs.target }}/release/*.exe`（`.github/actions/windows-code-sign/action.yml:54-57`）。

### 5) 被调用方（签名结果的消费者）

1. Windows 沙箱运行时
- setup 启动器按固定文件名查找 `codex-windows-sandbox-setup.exe`（`codex-rs/windows-sandbox-rs/src/setup_orchestrator.rs:434-443`）。
- helper 解析按固定文件名查找 `codex-command-runner.exe`（`codex-rs/windows-sandbox-rs/src/helper_materialization.rs:17-25,47-57`）。

2. npm 平台包与原生依赖安装
- Windows npm 包要求包含两个 helper 组件（`codex-cli/scripts/build_npm_package.py:76-77`）。
- 原生组件安装器默认也会拉取这两个组件（`codex-cli/scripts/install_native_deps.py:57-68,161-166`）。

3. DotSlash 发布映射
- `codex-command-runner` / `codex-windows-sandbox-setup` 在 DotSlash 输出配置中有独立 Windows 资产映射（`.github/dotslash-config.json:59-80`）。

## 关键代码路径与文件引用

### 目录内核心实现
- `.github/actions/windows-code-sign/action.yml:1-57`

### 调用方（Who calls）
1. 直接调用点
- `.github/workflows/rust-release-windows.yml:173-182`

2. 上层入口
- `.github/workflows/rust-release.yml:367-372`

3. 调用前后关键步骤
- 构建与产物拆分：`.github/workflows/rust-release-windows.yml:24-120`
- 签名前文件校验：`.github/workflows/rust-release-windows.yml:164-171`
- 签后重命名与压缩：`.github/workflows/rust-release-windows.yml:184-258`

### 关键配置与消费链
- `workflow_call` secrets 契约：`.github/workflows/rust-release-windows.yml:4-21`
- `id-token` 权限前提：`.github/workflows/rust-release-windows.yml:127-129`
- release 汇总发布：`.github/workflows/rust-release.yml:423-425,506-515`
- WinGet 安装器选择规则：`.github/workflows/rust-release.yml:662-670`
- npm/安装脚本消费 helper：
  - `codex-cli/scripts/build_npm_package.py:70-80`
  - `codex-cli/scripts/install_native_deps.py:46-69,161-166`
  - `scripts/install/install.ps1:147-151`

### 测试与校验现状
- 未发现针对 `.github/actions/windows-code-sign` 的独立测试（单元测试、action 级测试或 mock 测试）。
- 当前主要依赖发布 workflow 实跑时的失败中断机制。

## 依赖与外部交互

1. 外部 GitHub Actions 依赖
- `azure/login@v2`（OIDC 登录）
- `azure/trusted-signing-action@v0`（签名执行）
（`.github/actions/windows-code-sign/action.yml:30,37`）

2. 外部服务与身份
- Azure AD/OIDC（tenant + client）
- Azure Subscription
- Azure Trusted Signing endpoint/account/certificate-profile
（`.github/actions/windows-code-sign/action.yml:7-24`；`.github/workflows/rust-release-windows.yml:10-21`）

3. Secrets 与权限
- 必需 secrets：`AZURE_TRUSTED_SIGNING_*` 六项（`.github/workflows/rust-release-windows.yml:10-21`）。
- 必需 job 权限：`id-token: write`（`.github/workflows/rust-release-windows.yml:127-129`）。

4. 与发布系统交互
- 签名完成后资产被上传并由 release job 汇总发布（`.github/workflows/rust-release-windows.yml:260-264`；`.github/workflows/rust-release.yml:423-425,506-515`）。
- WinGet 与 npm 平台包均消费同一发布资产体系（`.github/workflows/rust-release.yml:540-670`）。

## 风险、边界与改进建议

### 风险

1. 第三方 action 版本漂移
- `azure/trusted-signing-action@v0` 为浮动主版本，存在上游行为变化风险（`.github/actions/windows-code-sign/action.yml:37`）。

2. 签名文件列表硬编码
- 新增 Windows 可执行发布物时若未同步更新 `files`，会出现“可发布但未签名”的遗漏风险（`.github/actions/windows-code-sign/action.yml:53-57`）。

3. 缺乏“签后验证”步骤
- 目前有“签名前存在性校验”，但没有显式 `Get-AuthenticodeSignature` 或 `signtool verify` 回归检查，签名质量完全依赖 trusted-signing-action 成功返回。

4. 路径契约耦合
- action 假定 `github.workspace/codex-rs/target/<target>/release` 目录结构稳定；若构建目录布局变化会直接失效（`.github/actions/windows-code-sign/action.yml:54-57`）。

5. 自动化测试空缺
- 该目录没有独立测试，回归只能在发布链路中暴露，反馈周期长。

### 边界

1. 本目录只定义 Windows 签名动作，不负责 release 触发策略。
2. 不负责构建、压缩与上传动作，这些在 `rust-release-windows.yml`/`rust-release.yml`。
3. 不负责 Windows 安装端逻辑（安装端在 `scripts/install/install.ps1` 与 npm 包工具链）。

### 改进建议

1. 固定第三方 action 到 commit SHA
- 将 `azure/login@v2` 与 `azure/trusted-signing-action@v0` 固定到具体 SHA，降低供应链漂移。

2. 增加签后验签步骤
- 在 `build-windows` 中追加 PowerShell 验签（例如 `Get-AuthenticodeSignature`）并对四个 exe 逐一断言 `Status`。

3. 抽象签名清单为单一来源
- 将签名目标清单与打包/安装消费清单统一（manifest 驱动），减少硬编码分散在 workflow、action、npm 脚本的漂移风险。

4. 增加 action 静态校验
- 在 PR CI 中加入 `actionlint` 与最小 smoke 检查（至少检查输入必填项、路径模板与调用一致性）。

5. 增加故障可观测性
- 在签名前输出待签名文件摘要（文件大小/哈希）并在失败时保留日志线索，降低发布故障排障时间。
