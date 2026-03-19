# DIR `.github` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github`（DIR）
- 研究日期：2026-03-19
- 研究范围：GitHub 平台自动化层（CI/CD、发布、签名、安全策略、Issue/PR 治理）及其上下游脚本、配置、测试与文档依赖。

## 场景与职责

`.github` 在本仓库中承担“托管平台控制面”职责，不承载产品运行时逻辑，但决定了代码从提交到交付的主要路径：

1. 质量门禁入口
- PR/Push 触发 JS、Rust、Bazel、拼写、依赖合规检查（`.github/workflows/ci.yml:1-66`，`.github/workflows/rust-ci.yml:1-741`，`.github/workflows/bazel.yml:1-221`，`.github/workflows/codespell.yml:1-27`，`.github/workflows/cargo-deny.yml:1-26`）。

2. 发布流水线编排层
- Rust 发布主流程在 `.github/workflows/rust-release.yml`，并复用 Windows 发布子工作流与 shell-tool-mcp 子工作流（`.github/workflows/rust-release.yml:367-381`，`.github/workflows/rust-release-windows.yml:1-264`，`.github/workflows/shell-tool-mcp.yml:1-553`）。

3. 供应链与工件治理
- DotSlash 发布映射、blob 大文件策略、Dependabot 更新策略均在 `.github` 定义（`.github/dotslash-config.json:1-84`，`.github/blob-size-allowlist.txt:1-9`，`.github/dependabot.yaml:3-30`）。

4. 社区与治理自动化
- Issue 模板、PR 模板、CLA 校验、Issue label/deduplicate、陈旧 PR 清理形成维护闭环（`.github/ISSUE_TEMPLATE/*.yml`，`.github/pull_request_template.md:1-8`，`.github/workflows/cla.yml:1-49`，`.github/workflows/issue-labeler.yml:1-133`，`.github/workflows/issue-deduplicator.yml:1-402`，`.github/workflows/close-stale-contributor-prs.yml:1-107`）。

5. 签名与发行安全边界
- Linux（cosign）、macOS（codesign+notary）、Windows（Azure Trusted Signing）在本地 composite actions 封装（`.github/actions/linux-code-sign/action.yml:1-45`，`.github/actions/macos-code-sign/action.yml:1-251`，`.github/actions/windows-code-sign/action.yml:1-57`）。

## 功能点目的

### 1) CI 目标：降低回归与发布前缺陷

1. `ci.yml`
- 做 Node/PNPM 基础检查、README ASCII/ToC、Prettier，并预先尝试 stage npm 包，提前暴露发布链断裂（`.github/workflows/ci.yml:27-66`）。
- 其 `stage_npm_packages.py` 会回查 `rust-release.yml` 产物，属于“把发布可用性前置到 CI”设计（`scripts/stage_npm_packages.py:81-110`）。

2. `rust-ci.yml`
- 先做 changed-path 分类，再按需运行 fmt/cargo-shear/argument-comment-lint/matrix lint+build+tests，减少无效 runner 开销（`.github/workflows/rust-ci.yml:12-58`，`:59-130`，`:133-741`）。
- `results` 汇总 job 作为唯一 required 状态，避免矩阵状态配置复杂化（`.github/workflows/rust-ci.yml:703-741`）。

3. `bazel.yml`（experimental）
- 与 Cargo 并行验证 Bazel 构建与测试可用性，并在 fork 场景降级禁用远程缓存/执行（`.github/workflows/bazel.yml:174-214`）。

4. 专项检查
- `cargo-deny`：Rust 许可证/安全合规（`.github/workflows/cargo-deny.yml:9-26`）。
- `codespell`：拼写质量（`.github/workflows/codespell.yml:14-27`）。
- `blob-size-policy`：阻断大文件入仓（`.github/workflows/blob-size-policy.yml:23-32`，`scripts/check_blob_size.py:136-189`）。
- `sdk.yml` 与 `shell-tool-mcp-ci.yml`：子模块独立构建质量（`.github/workflows/sdk.yml:8-52`，`.github/workflows/shell-tool-mcp-ci.yml:20-48`）。

### 2) Release 目标：多平台工件一致、可验证、可分发

1. `rust-release.yml`
- Tag 规范与 Cargo 版本一致性校验（`.github/workflows/rust-release.yml:19-47`）。
- Linux/macOS build、签名、压缩、上传工件（`.github/workflows/rust-release.yml:48-366`）。
- 复用 `rust-release-windows.yml` 与 `shell-tool-mcp.yml` 合并最终 release 资产（`.github/workflows/rust-release.yml:367-440`）。
- 生成 GitHub Release，发布 npm，发布 winget，更新 `latest-alpha-cli` 分支（`.github/workflows/rust-release.yml:506-689`）。

2. `rust-release-windows.yml`
- 拆成 “build-windows-binaries” 与 “build-windows(sign+package)” 两阶段，先并行编译再签名归档（`.github/workflows/rust-release-windows.yml:24-120`，`:121-264`）。

3. `shell-tool-mcp.yml`
- 构建多发行版/多平台 patched Bash 与 zsh，打包成 `@openai/codex-shell-tool-mcp` npm tarball，并可选发布（`.github/workflows/shell-tool-mcp.yml:73-553`）。

### 3) 社区治理目标：降低维护噪音并自动化分流

1. Issue 模板将问题归类到 app/extension/cli/bug/docs/feature（`.github/ISSUE_TEMPLATE/*.yml`）。
2. `issue-labeler.yml` 用 Codex 自动建议 labels 并应用到 issue（`.github/workflows/issue-labeler.yml:22-127`）。
3. `issue-deduplicator.yml` 双阶段（all/open）去重并自动评论候选重复 issue（`.github/workflows/issue-deduplicator.yml:10-402`）。
4. `cla.yml` 与 `docs/CLA.md` 联动自动验签（`.github/workflows/cla.yml:21-49`，`docs/CLA.md:1-49`）。
5. 定时清理 stale contributor PR（`.github/workflows/close-stale-contributor-prs.yml:24-107`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 工作流编排与可复用链路

1. 可复用 workflow_call
- `rust-release.yml` 通过 `uses: ./.github/workflows/rust-release-windows.yml` 与 `uses: ./.github/workflows/shell-tool-mcp.yml` 串联子发布（`.github/workflows/rust-release.yml:368-381`）。
- 子工作流输入通过 `inputs.release-lto`、`inputs.release-version/release-tag/publish` 传递，形成稳定接口（`.github/workflows/rust-release-windows.yml:4-8`，`.github/workflows/shell-tool-mcp.yml:4-18`）。

2. 本地 composite actions
- Linux：安装 cosign 后对 `codex`/`codex-responses-api-proxy` 做 `cosign sign-blob --bundle *.sigstore`（`.github/actions/linux-code-sign/action.yml:14-45`）。
- macOS：创建临时 keychain -> 导入 p12 -> codesign -> notarytool -> stapler -> 清理 keychain（`.github/actions/macos-code-sign/action.yml:33-251`，`.github/actions/macos-code-sign/notary_helpers.sh:3-46`）。
- Windows：OIDC 登录 Azure -> Trusted Signing Action 批量签名 4 个 exe（`.github/actions/windows-code-sign/action.yml:29-57`）。

### 2) 关键数据结构与产物命名协议

1. DotSlash 发布配置
- `.github/dotslash-config.json` 以 `outputs -> platforms -> regex/path` 映射 release 资产到目标执行文件名，供 `facebook/dotslash-publish-release` 消费（`.github/dotslash-config.json:2-84`，`.github/workflows/rust-release.yml:517-523`）。

2. shell-tool-mcp 产物协议
- workflow 统一输出 `codex-shell-tool-mcp-npm-${VERSION}.tgz`（`.github/workflows/shell-tool-mcp.yml:506-512`）。
- `codex-rs/app-server/tests/suite/bash` 与 `zsh` 的 DotSlash 测试清单直接引用这一发布工件（`codex-rs/app-server/tests/suite/bash:3-75`，`codex-rs/app-server/tests/suite/zsh:3-72`）。

3. Issue 自动化输出 schema
- labeler 期望 `{ labels: string[] }`（`.github/workflows/issue-labeler.yml:74-87`）。
- deduplicator 期望 `{ issues: string[], reason: string }`，并在 pass1/pass2 后规范化去重、截断到 5 个（`.github/workflows/issue-deduplicator.yml:85-99`，`:122-143`，`:256-277`）。

### 3) 关键命令与脚本调用链

1. npm 分发 staging
- `ci.yml` 与 `rust-release.yml` 都调用 `scripts/stage_npm_packages.py`（`.github/workflows/ci.yml:33-47`，`.github/workflows/rust-release.yml:490-499`）。
- 该脚本会调用 `codex-cli/scripts/build_npm_package.py`、`codex-cli/scripts/install_native_deps.py` 并通过 `gh run list` 锚定 release workflow 产物（`scripts/stage_npm_packages.py:16-126`，`codex-cli/scripts/build_npm_package.py:21-87`，`codex-cli/scripts/install_native_deps.py:262-273`）。

2. musl 交叉编译环境装配
- `rust-ci.yml` 与 `rust-release.yml` 都调用 `.github/scripts/install-musl-build-tools.sh`（`.github/workflows/rust-ci.yml:358-367`，`.github/workflows/rust-release.yml:149-154`）。
- 脚本执行 apt 安装、libcap 静态构建、zig wrapper 生成、C/CXX/PKG_CONFIG/CARGO_TARGET_* 环境注入（`.github/scripts/install-musl-build-tools.sh:19-279`）。

3. Bazel 锁文件验证
- `bazel.yml` 调用 `scripts/check-module-bazel-lock.sh`，失败时要求 `just bazel-lock-update`（`.github/workflows/bazel.yml:76-80`，`scripts/check-module-bazel-lock.sh:1-8`）。

4. 文档质量检查
- `ci.yml` 通过 `scripts/asciicheck.py` + `scripts/readme_toc.py` 校验 README 文本规范（`.github/workflows/ci.yml:55-63`，`scripts/asciicheck.py:49-127`，`scripts/readme_toc.py:22-116`）。

### 4) 触发策略与边界控制

1. 调度策略
- 定时任务：`rust-release-prepare`（每 4 小时）与 `close-stale-contributor-prs`（每天 06:00 UTC）（`.github/workflows/rust-release-prepare.yml:3-6`，`.github/workflows/close-stale-contributor-prs.yml:4-7`）。
- path 过滤：`shell-tool-mcp-ci.yml` 仅在 shell-tool-mcp 相关路径变化时触发（`.github/workflows/shell-tool-mcp-ci.yml:4-15`）。

2. 仓库范围保护
- 多个工作流显式限制 `github.repository == 'openai/codex'`，避免 fork 无秘密运行浪费资源（`.github/workflows/rust-release-prepare.yml:17-19`，`.github/workflows/issue-labeler.yml:13-14`，`.github/workflows/issue-deduplicator.yml:13-14`，`.github/workflows/close-stale-contributor-prs.yml:15-17`）。

## 关键代码路径与文件引用

### A. 目录内核心对象（调用关系主干）

1. 工作流入口
- `.github/workflows/ci.yml`
- `.github/workflows/rust-ci.yml`
- `.github/workflows/rust-release.yml`
- `.github/workflows/rust-release-windows.yml`
- `.github/workflows/shell-tool-mcp.yml`
- `.github/workflows/bazel.yml`
- `.github/workflows/issue-labeler.yml`
- `.github/workflows/issue-deduplicator.yml`

2. 本地 action 与脚本
- `.github/actions/linux-code-sign/action.yml`
- `.github/actions/macos-code-sign/action.yml`
- `.github/actions/macos-code-sign/notary_helpers.sh`
- `.github/actions/windows-code-sign/action.yml`
- `.github/scripts/install-musl-build-tools.sh`

3. 策略与模板
- `.github/dotslash-config.json`
- `.github/blob-size-allowlist.txt`
- `.github/dependabot.yaml`
- `.github/pull_request_template.md`
- `.github/ISSUE_TEMPLATE/1-codex-app.yml`
- `.github/ISSUE_TEMPLATE/2-extension.yml`
- `.github/ISSUE_TEMPLATE/3-cli.yml`
- `.github/ISSUE_TEMPLATE/4-bug-report.yml`
- `.github/ISSUE_TEMPLATE/5-feature-request.yml`
- `.github/ISSUE_TEMPLATE/6-docs-issue.yml`
- `.github/codex/home/config.toml`
- `.github/codex/labels/codex-review.md`
- `.github/codex/labels/codex-rust-review.md`
- `.github/codex/labels/codex-triage.md`
- `.github/codex/labels/codex-attempt.md`

### B. 关键调用方（目录外调用 `.github`）

1. `scripts/stage_npm_packages.py:19` 依赖 `.github/workflows/rust-release.yml` 名称定位发布 run。
2. `README.md:4` 直接引用 `.github/codex-cli-splash.png`。
3. `package.json:6-7` 将 `.github/workflows/*.yml` 纳入 Prettier 检查。
4. `codex-rs/app-server/tests/suite/zsh:4` 注释性绑定 `.github/workflows/shell-tool-mcp.yml` 产物来源。

### C. 被调用方（`.github` 调用目录外对象）

1. 脚本
- `scripts/stage_npm_packages.py`
- `scripts/check_blob_size.py`
- `scripts/check-module-bazel-lock.sh`
- `scripts/asciicheck.py`
- `scripts/readme_toc.py`
- `scripts/install/install.sh`
- `scripts/install/install.ps1`

2. 子项目/补丁
- `shell-tool-mcp/patches/bash-exec-wrapper.patch`
- `shell-tool-mcp/patches/zsh-exec-wrapper.patch`
- `shell-tool-mcp/package.json`
- `shell-tool-mcp/README.md`
- `codex-cli/scripts/build_npm_package.py`
- `codex-cli/scripts/install_native_deps.py`

3. 文档治理
- `docs/contributing.md`
- `docs/CLA.md`

## 依赖与外部交互

### 1) GitHub 平台与生态 Action 依赖

1. 官方/主流 action
- `actions/*`, `actions/cache*`, `actions/github-script`, `actions/upload/download-artifact`, `actions/setup-node`。

2. 关键第三方 action
- `openai/codex-action@main`（issue label/deduplicate）。
- `contributor-assistant/github-action@v2.6.1`（CLA）。
- `sigstore/cosign-installer@v3.7.0`（Linux 签名）。
- `azure/login@v2` + `azure/trusted-signing-action@v0`（Windows 签名）。
- `softprops/action-gh-release@v2`（GitHub release）。
- `facebook/dotslash-publish-release@v2`（DotSlash 资产索引发布）。
- `vedantmgoyal9/winget-releaser@...`（WinGet 发布）。

### 2) 外部服务与协议交互

1. OpenAI API
- `rust-release-prepare.yml` 使用 `CODEX_OPENAI_API_KEY` 拉取 `models` 并更新 `codex-rs/core/models.json`（`.github/workflows/rust-release-prepare.yml:26-44`）。
- issue 自动化通过 `openai/codex-action` 调用模型并返回结构化 JSON（`.github/workflows/issue-labeler.yml:22-88`，`.github/workflows/issue-deduplicator.yml:62-99`）。

2. 软件供应链/发行
- npm trusted publishing（OIDC）发布多个 tarball（`.github/workflows/rust-release.yml:537-647`，`.github/workflows/shell-tool-mcp.yml:514-553`）。
- Apple notarytool / codesign（`.github/actions/macos-code-sign/action.yml:140-229`）。
- Azure Trusted Signing（`.github/actions/windows-code-sign/action.yml:29-57`）。
- Sigstore cosign（`.github/actions/linux-code-sign/action.yml:41-44`）。

3. GitHub CLI / API
- `gh issue list/view/edit`、`gh release download`、`gh run list/download`、`gh api repos/.../git/refs` 在多个流程中作为数据平面（`.github/workflows/issue-deduplicator.yml:35-55`，`.github/workflows/issue-labeler.yml:122-127`，`.github/workflows/rust-release.yml:581-585`，`:685-688`，`scripts/stage_npm_packages.py:82-95`）。

### 3) 秘密与权限模型

1. 关键 secrets
- `CODEX_OPENAI_API_KEY`、Apple notarization/certificate secrets、Azure Trusted Signing secrets、`WINGET_PUBLISH_PAT`、`BUILDBUDDY_API_KEY`、`DEV_WEBSITE_VERCEL_DEPLOY_HOOK_URL`（见 `.github/workflows/*.yml` 中 `secrets.*`）。

2. 权限声明现状
- 部分 workflow/job 显式最小权限（例如 `issue-labeler`、`issue-deduplicator`、`rust-release` 发布作业）。
- 也存在未显式声明权限的 workflow（如 `ci.yml`、`sdk.yml`、`shell-tool-mcp-ci.yml`），依赖平台默认权限策略。

## 风险、边界与改进建议

### 风险

1. 供应链固定性不足
- 多个 action 仍按 tag 或 `@main` 引用（如 `openai/codex-action@main`），存在上游漂移风险；建议统一 pin 到 commit SHA。

2. 发布链耦合导致脆弱点
- `ci.yml` 中 `CODEX_VERSION=0.115.0` 为硬编码，版本更新后可能出现“CI staging 与当前主线发布状态不一致”（`.github/workflows/ci.yml:39-47`）。

3. 临时逻辑暴露架构边界问题
- `rust-release.yml` 明确写有“temporary fix”并在 release 阶段删除 `dist/shell-tool-mcp*`（`.github/workflows/rust-release.yml:430-440`），说明 artifact 汇聚边界尚未收敛。

4. 配置漂移迹象
- `dependabot.yaml` 指向 `.github/actions/codex`（`.github/dependabot.yaml:6`），当前仓库并无该目录，可能导致对应生态更新失效。

5. 模板质量小缺陷
- `ISSUE_TEMPLATE/3-cli.yml` 中同一字段重复 `description` 键（`.github/ISSUE_TEMPLATE/3-cli.yml:44-46`），存在 YAML 键覆盖语义风险。

6. Shell fork 构建链外部依赖较重
- `shell-tool-mcp.yml` 在运行时克隆 Bash/Zsh 源仓并打 patch（`.github/workflows/shell-tool-mcp.yml:152-155`，`:290-294`），受上游可用性与网络抖动影响，虽然 commit 已固定。

### 边界

1. `.github` 负责“自动化编排与治理策略”，不包含 CLI/TUI/App-Server 业务实现。
2. 目录内多数对象是声明式 YAML 与脚本，不提供单元测试；质量主要依赖 workflow 实跑反馈。
3. 目录与仓库其他模块呈“高控制、低耦合源码”关系：通过脚本/工件接口交互，而非直接链接代码。

### 改进建议

1. 将第三方 action 全量 SHA 固定化
- 对 `@main`、`@v*` 的关键路径动作（发布、签名、issue 自动化）优先收敛，降低供应链漂移。

2. 消除发布临时清理步骤
- 调整 `shell-tool-mcp.yml` 的 artifact 命名与 upload 范围，避免在 `rust-release.yml` 做 `rm -rf` 型兜底。

3. 将 `ci.yml` 的 staging 版本改为可解析最新 release
- 通过 `gh release`/tag 解析动态版本，或用固定测试基准并在注释中说明更新策略。

4. 修复 dependabot 目录与 issue template 键冲突
- 移除无效目录配置、修复重复 YAML 键，减少隐性失效。

5. 权限声明统一化
- 为未声明 `permissions` 的 workflow 明确最小权限，提升审计可见性。

6. 为关键脚本补最小回归测试
- 建议优先给 `scripts/stage_npm_packages.py`、`scripts/check_blob_size.py` 增加 dry-run/fixture 测试，降低发布辅助脚本回归风险。
