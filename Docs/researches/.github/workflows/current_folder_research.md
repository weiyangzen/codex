# DIR `.github/workflows` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/workflows`（DIR）
- 研究日期：2026-03-19
- 关联范围：工作流定义、可复用工作流、同目录辅助配置/脚本、被调用脚本、本地 action、相关文档与测试引用

## 场景与职责

`.github/workflows` 是仓库自动化控制平面，职责可分为 4 层：

1. 质量门禁（PR / main 持续集成）
- JS/文档检查：`ci.yml`
- Rust 主 CI：`rust-ci.yml`
- Bazel 实验流水线：`bazel.yml`
- 依赖与文本质量：`cargo-deny.yml`、`codespell.yml`、`blob-size-policy.yml`
- 子项目流水线：`sdk.yml`、`shell-tool-mcp-ci.yml`

2. 发布编排（tag 驱动）
- 总发布编排：`rust-release.yml`
- Windows 子发布（可复用）：`rust-release-windows.yml`
- shell-tool-mcp 子发布（可复用）：`shell-tool-mcp.yml`
- 模型元数据自动更新：`rust-release-prepare.yml`

3. 仓库治理（Issue/PR 运维）
- CLA 校验：`cla.yml`
- 过期贡献者 PR 自动关闭：`close-stale-contributor-prs.yml`
- Issue 自动标签：`issue-labeler.yml`
- Issue 去重建议：`issue-deduplicator.yml`

4. 工作流运行时配套文件
- Bazel CI 参数：`ci.bazelrc`
- Bazel 容器构建镜像样例：`Dockerfile.bazel`
- Windows 下 zstd DotSlash 包装器：`zstd`

## 功能点目的

### 1) 各工作流目标与触发

| 工作流 | 触发 | 目的 |
| --- | --- | --- |
| `ci.yml` | `pull_request` / `push(main)` | Node/PNPM 依赖安装、npm staging 验证、README ASCII+ToC 校验、Prettier 校验 |
| `rust-ci.yml` | `pull_request` / `push(main)` / `workflow_dispatch` | 变更检测后按需执行 format/shear/argument-comment-lint/跨平台 clippy/nextest |
| `bazel.yml` | `pull_request` / `push(main)` / `workflow_dispatch` | Bazel 全仓测试（含 BuildBuddy 有/无密钥两路径） |
| `cargo-deny.yml` | `pull_request` / `push(main)` | 许可证/漏洞/依赖策略检查（`codex-rs/deny.toml`） |
| `codespell.yml` | `pull_request(main)` / `push(main)` | 拼写检查（`.codespellrc` + `.codespellignore`） |
| `blob-size-policy.yml` | `pull_request` | 拦截超大 blob（allowlist 例外） |
| `sdk.yml` | `pull_request` / `push(main)` | 构建 Rust `codex` 并构建/测试 TS SDK |
| `shell-tool-mcp-ci.yml` | `shell-tool-mcp/**` 等路径变更 | `@openai/codex-shell-tool-mcp` format/test/build |
| `rust-release.yml` | `push tags: rust-v*.*.*` | 主发布：构建签名打包、GitHub Release、npm 发布、winget、分支更新 |
| `rust-release-windows.yml` | `workflow_call` | Windows 目标的构建、签名、归档（被 `rust-release.yml` 调用） |
| `shell-tool-mcp.yml` | `workflow_call` | 构建多发行版 bash/zsh 补丁二进制并打 npm 包（可选发布） |
| `rust-release-prepare.yml` | `schedule(4h)` / `workflow_dispatch` | 拉取 `/models` 更新 `codex-rs/core/models.json` 并自动提 PR |
| `issue-labeler.yml` | `issues.opened/labeled` | 让 Codex Action 输出 labels，自动打标签 |
| `issue-deduplicator.yml` | `issues.opened/labeled` | 两阶段重复 issue 检测并评论建议 |
| `cla.yml` | `issue_comment.created` + `pull_request_target` | 贡献者 CLA 合同状态自动检查与记录 |
| `close-stale-contributor-prs.yml` | `schedule` / `workflow_dispatch` | 自动关闭长期无更新的协作者 PR |

### 2) 调用方 / 被调用方关系

1. 可复用工作流调用链
- `rust-release.yml` 调用 `./.github/workflows/rust-release-windows.yml`
- `rust-release.yml` 调用 `./.github/workflows/shell-tool-mcp.yml`

2. 工作流对本地 action 的调用
- Linux 签名：`./.github/actions/linux-code-sign`
- macOS 签名与 notarize：`./.github/actions/macos-code-sign`
- Windows Trusted Signing：`./.github/actions/windows-code-sign`

3. 工作流对仓库脚本的调用
- `scripts/stage_npm_packages.py`
- `scripts/asciicheck.py`
- `scripts/readme_toc.py`
- `scripts/check_blob_size.py`
- `scripts/check-module-bazel-lock.sh`
- `.github/scripts/install-musl-build-tools.sh`

4. 反向依赖（谁依赖本目录产物）
- `scripts/stage_npm_packages.py` 默认依赖 `rust-release.yml` 的 run artifacts
- `codex-rs/app-server/tests/suite/zsh` 注释明确依赖 `shell-tool-mcp.yml` 产出的发布包结构

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. Rust CI 主流程（`rust-ci.yml`）

1. 变更检测分流
- `changed` job 基于 `git diff base..head` 计算布尔输出：`codex` / `workflows` / `argument_comment_lint*`
- 下游 job 依据输出做条件执行，减少无关矩阵成本

2. 两类矩阵任务
- `lint_build`：多 OS/target + dev/release profile，执行 `cargo clippy --all-features --tests`
- `tests`：多 OS/target，执行 `cargo nextest run --all-features --no-fail-fast`

3. 性能/稳定性策略
- `sccache` + `actions/cache` 双路径缓存
- musl 目标启用 hermetic `CARGO_HOME`、APT 缓存、`setup-zig`
- 使用 `.github/scripts/install-musl-build-tools.sh` 写入交叉编译所需环境变量（`CC_*` / `CARGO_TARGET_*_LINKER` / `PKG_CONFIG_*` 等）

4. 汇总 required check
- `results` job 聚合所有上游结果，作为单一 required status

### B. 发布流程（`rust-release.yml` + 子工作流）

1. 入口与版本约束
- 仅 `rust-v*` tag 触发
- `tag-check` 校验 tag semver 与 `codex-rs/Cargo.toml` 版本一致

2. 跨平台构建与签名
- 非 Windows：`build` job 覆盖 macOS / Linux gnu+musl
- Linux：通过 `linux-code-sign` 用 cosign 生成 `.sigstore`
- macOS：通过 `macos-code-sign` 执行 codesign + notarize（binary + dmg 分阶段）
- Windows：`build-windows` 调 `rust-release-windows.yml`，使用 Azure Trusted Signing

3. 产物组装与发布
- 构建产物汇总到 `dist/`
- 生成 `.zst` + `.tar.gz`（Windows 另有 `.zip`）
- `softprops/action-gh-release` 发布 GitHub Release
- `facebook/dotslash-publish-release` 基于 `.github/dotslash-config.json` 发布 DotSlash 映射
- 稳定版触发 developers.openai.com deploy hook

4. npm 与 winget 发布
- `publish-npm` 用 npm Trusted Publishing(OIDC) 发布 tarball
- `winget` 仅稳定版执行

5. 附加分支维护
- `update-branch` 强制更新 `latest-alpha-cli`

### C. shell-tool-mcp 可复用发布流（`shell-tool-mcp.yml`）

1. 元数据决策
- `metadata` job 解析 `release-version/release-tag`，输出 `should_publish` 与 `npm_tag`

2. 供应链构建
- 在 Linux 容器矩阵（Ubuntu/Debian/CentOS，x64+arm64）构建 patched Bash
- 在 Linux/macOS 矩阵构建 patched zsh，并做 smoke test（验证 `EXEC_WRAPPER`）
- patch 来源：`shell-tool-mcp/patches/bash-exec-wrapper.patch`、`zsh-exec-wrapper.patch`

3. 打包
- 汇总各矩阵 artifact 到 `vendor/<target>/<shell>/<variant>`
- 回填 `package.json.version`
- `npm pack` 产出 `codex-shell-tool-mcp-npm-<version>.tgz`

4. 发布
- `publish` job 依据 `inputs.publish && should_publish` 用 npm OIDC 发布

### D. Issue 自动治理流

1. `issue-labeler.yml`
- `openai/codex-action@main` 接收 issue 标题/正文，按输出 schema 返回 `labels[]`
- shell 步骤使用 `gh issue edit --add-label` 应用标签
- 当人工添加触发标签 `codex-label` 时，任务结束后自动移除触发标签

2. `issue-deduplicator.yml`
- 两阶段：先全量 issue，再 open issue fallback
- 每阶段输出 schema：`issues[]` + `reason`
- 归一化步骤用 `jq` 过滤当前 issue、自去重、截断到最多 5 条
- 最终 `actions/github-script` 发表评论

### E. Bazel CI (`bazel.yml` + `ci.bazelrc`)

1. BuildBuddy 有密钥路径
- 使用 `.github/workflows/ci.bazelrc` + `--remote_header=x-buildbuddy-api-key=...`

2. 无密钥路径（fork/社区 PR）
- 显式清空 `--remote_cache` / `--remote_executor`
- 保持 Bazel 测试仍可本地执行

3. 失败日志增强
- 从控制台解析失败 target，再回溯 `bazel-testlogs/.../test.log` 的 tail 输出

### F. 关键协议/数据结构/命令约定

1. GitHub Actions 跨 job 数据
- 统一使用 `$GITHUB_OUTPUT` 输出键值（如 `version`, `should_publish`, `has_matches`）

2. Artifact 命名约定（发布链路强耦合）
- Rust 产物：`codex-<target>[.exe].zst`、`codex-responses-api-proxy-...`
- shell-tool-mcp：`codex-shell-tool-mcp-npm-<version>.tgz`
- CI 依赖这些名字进行下载/过滤/发布

3. OIDC 发布协议
- npm Trusted Publishing：`id-token: write` + 无 `NODE_AUTH_TOKEN`
- Azure Trusted Signing：`azure/login@v2` OIDC + trusted-signing-action
- Sigstore cosign：OIDC issuer/client id 写在环境变量

## 关键代码路径与文件引用

### 1) 工作流入口文件
- `.github/workflows/ci.yml`
- `.github/workflows/rust-ci.yml`
- `.github/workflows/rust-release.yml`
- `.github/workflows/rust-release-windows.yml`
- `.github/workflows/shell-tool-mcp.yml`
- `.github/workflows/bazel.yml`
- `.github/workflows/issue-labeler.yml`
- `.github/workflows/issue-deduplicator.yml`
- `.github/workflows/cla.yml`
- `.github/workflows/blob-size-policy.yml`
- `.github/workflows/cargo-deny.yml`
- `.github/workflows/codespell.yml`
- `.github/workflows/sdk.yml`
- `.github/workflows/shell-tool-mcp-ci.yml`
- `.github/workflows/rust-release-prepare.yml`
- `.github/workflows/close-stale-contributor-prs.yml`

### 2) 同目录配套文件
- `.github/workflows/ci.bazelrc`
- `.github/workflows/Dockerfile.bazel`
- `.github/workflows/zstd`

### 3) 本地 action（被工作流调用）
- `.github/actions/linux-code-sign/action.yml`
- `.github/actions/macos-code-sign/action.yml`
- `.github/actions/macos-code-sign/notary_helpers.sh`
- `.github/actions/windows-code-sign/action.yml`

### 4) 仓库脚本（被工作流调用）
- `.github/scripts/install-musl-build-tools.sh`
- `scripts/stage_npm_packages.py`
- `scripts/asciicheck.py`
- `scripts/readme_toc.py`
- `scripts/check_blob_size.py`
- `scripts/check-module-bazel-lock.sh`
- `scripts/install/install.sh`
- `scripts/install/install.ps1`

### 5) 上下游补充文件
- `codex-cli/scripts/build_npm_package.py`
- `codex-cli/scripts/install_native_deps.py`
- `codex-cli/scripts/README.md`
- `shell-tool-mcp/package.json`
- `shell-tool-mcp/README.md`
- `shell-tool-mcp/patches/bash-exec-wrapper.patch`
- `shell-tool-mcp/patches/zsh-exec-wrapper.patch`
- `.github/dotslash-config.json`
- `.github/blob-size-allowlist.txt`
- `codex-rs/deny.toml`
- `codex-rs/app-server/tests/suite/zsh`
- `docs/contributing.md`
- `docs/install.md`
- `docs/CLA.md`
- `package.json`
- `pnpm-workspace.yaml`
- `justfile`

## 依赖与外部交互

### 1) GitHub 生态

1. GitHub Actions 官方 action
- `actions/checkout`, `actions/setup-node`, `actions/cache`, `actions/upload/download-artifact`, `actions/github-script`

2. GitHub CLI / API
- `gh run list/download`, `gh issue edit`, `gh api` 在多个工作流中用于查 run、写 issue、更新分支

3. Release 与资产分发
- `softprops/action-gh-release`
- `facebook/dotslash-publish-release`

### 2) 供应链与签名服务

1. npm registry（OIDC trusted publishing）
2. Sigstore/cosign（Linux 签名）
3. Apple notarization（`xcrun notarytool` + `stapler`）
4. Azure Trusted Signing（Windows 签名）
5. WinGet 自动提交流程（`winget-releaser`）

### 3) OpenAI 相关外部交互

1. `rust-release-prepare.yml`
- 使用 `CODEX_OPENAI_API_KEY` 调 `/models` 接口并更新 `codex-rs/core/models.json`

2. issue 自动化
- `issue-labeler.yml` / `issue-deduplicator.yml` 调用 `openai/codex-action@main`

### 4) 构建与测试外部来源

1. shell-tool-mcp 构建阶段直接 clone 上游 shell 源码仓库并 checkout 固定 commit
2. Bazel 可连接 BuildBuddy 远程执行/缓存
3. DotSlash（`zstd` 和 `rg` manifest）按平台下载预编译工具

## 风险、边界与改进建议

### 风险

1. 供应链版本漂移风险
- `openai/codex-action@main` 使用可变引用，不可重现性较高。

2. 外部网络与第三方服务强依赖
- 发布链路依赖 npm、Apple、Azure、GitHub、BuildBuddy；任一服务抖动可能导致发布失败。

3. 工作流逻辑测试覆盖不足
- 目前主要依赖线上 run 验证，缺少 `actionlint` / 本地模拟测试来提前发现表达式或条件错误。

4. 发布资产命名耦合较深
- 下载/过滤步骤依赖固定文件名模式，命名变更会产生级联故障。

5. Shell 源码构建成本高
- `shell-tool-mcp.yml` 在多发行版矩阵中 clone+编译 Bash/Zsh，耗时与失败面较大。

6. 容错策略可能掩盖问题
- 部分步骤使用 `|| true`（标签应用、标签移除等），会隐藏执行失败细节。

### 边界

1. 本目录主要负责 CI/CD 编排，不负责业务逻辑正确性本身。
2. Secret 权限在 fork 场景受限，多个工作流通过 `if: github.repository == 'openai/codex'` 显式避开。
3. 可复用工作流（`workflow_call`）需要上游传入输入/密钥，不能独立完成完整发布。
4. 同一 automation 同时覆盖 Rust/Node/Bazel，多技术栈并存是既定架构前提。

### 改进建议

1. 固定第三方 action 到 commit SHA
- 尤其是 `openai/codex-action@main` 等可变标签，建议 pin 到不可变 SHA 并建立周期升级策略。

2. 引入 workflow 静态检查
- 增加 `actionlint` + YAML schema 校验，减少表达式/引用路径错误上线。

3. 抽象重复步骤
- 将 `rust-ci.yml` 中重复的 sccache/cargo cache 逻辑提取为 composite action，降低维护成本。

4. 细化失败告警
- 对当前 `|| true` 的治理脚本步骤增加 `::warning` 注释或 step summary，避免静默失败。

5. 发布资产契约文档化
- 建立 `dist` 资产命名与消费者（npm/winget/dotslash）的映射文档，避免“隐式契约”引发回归。

6. shell-tool-mcp 供应链强化
- 在 clone 上游源码后补充 commit 校验/来源校验与构建缓存策略，降低网络与构建波动。

