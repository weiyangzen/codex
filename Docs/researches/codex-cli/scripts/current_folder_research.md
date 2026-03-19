# codex-cli/scripts 目录研究

## 场景与职责

`codex-cli/scripts` 是 `codex-cli` 的发布与容器化运行辅助层，承担两类核心职责：

1. npm 发布编排的“子执行器”
- 目录内的 `build_npm_package.py` 和 `install_native_deps.py` 被仓库根脚本 `scripts/stage_npm_packages.py` 调用，用于把 release 工件转为可发布 npm tarball。参考：
  - `scripts/stage_npm_packages.py:16-29`
  - `scripts/stage_npm_packages.py:113-126`
  - `scripts/stage_npm_packages.py:169-190`

2. Linux 容器沙箱运行辅助
- `build_container.sh` 构建容器镜像，`run_in_container.sh` 启动并配置容器，`init_firewall.sh` 在容器内收敛网络出口，仅放行允许域名（默认 OpenAI API）。参考：
  - `codex-cli/scripts/build_container.sh:11-16`
  - `codex-cli/scripts/run_in_container.sh:60-95`
  - `codex-cli/scripts/init_firewall.sh:25-115`
  - `codex-cli/Dockerfile:53-56`

它不是终端用户命令入口（入口是 `codex-cli/bin/codex.js`），但直接影响以下关键交付路径：
- CI 对 npm 包 staging 的验证：`.github/workflows/ci.yml:30-47`
- 正式 release 打包：`.github/workflows/rust-release.yml:488-500`
- 平台包发布与 dist-tag 规则：`.github/workflows/rust-release.yml:572-647`

## 功能点目的

### 1. `build_npm_package.py`
目的：把不同 package（`codex`、平台包、`codex-responses-api-proxy`、`codex-sdk`）统一 stage 成可 `npm pack` 的目录，并可直接产出 tgz。

关键意图：
- 用 `CODEX_PLATFORM_PACKAGES` 把目标三元组、npm alias、os/cpu 元数据统一建模，保证发布矩阵一致。`codex-cli/scripts/build_npm_package.py:21-64`
- 主包 `@openai/codex` 通过 `optionalDependencies` 映射到平台 alias（`@openai/codex-linux-x64` 等），而底层实际发布名统一是 `@openai/codex@<version-platform>`。`codex-cli/scripts/build_npm_package.py:304-313`
- 平台包版本加后缀（如 `1.2.3-linux-x64`）规避 npm 不允许同名同版本重复发布。`codex-cli/scripts/build_npm_package.py:331-334`

### 2. `install_native_deps.py`
目的：把 release workflow 产出的原生二进制与 ripgrep 安装到 `vendor/<target>/...`，为 npm 平台包提供内容源。

关键意图：
- 通过 `gh run download` 拉取 GitHub Actions artifacts。`codex-cli/scripts/install_native_deps.py:262-273`
- 通过 DotSlash manifest (`codex-cli/bin/rg`) 下载各平台 `rg` 并解压。`codex-cli/scripts/install_native_deps.py:194-259`, `456-469`
- 统一 `vendor` 目录规范（`codex/`、`codex-responses-api-proxy/`、`path/`）。`codex-cli/scripts/install_native_deps.py:46-69`, `320-331`, `357-363`

### 3. `build_container.sh`
目的：快速生成本地 `codex` Docker 镜像，供 Linux 无 root sandbox 运行场景使用。`codex-cli/scripts/build_container.sh:11-16`

### 4. `run_in_container.sh`
目的：将宿主工作目录同路径挂载到容器，注入允许域名列表，初始化防火墙后执行 `codex --full-auto`。`codex-cli/scripts/run_in_container.sh:11-95`

### 5. `init_firewall.sh`
目的：在容器内通过 `iptables + ipset` 默认拒绝流量，仅允许 DNS、localhost、主机网段和 allowlist 域名解析结果。`codex-cli/scripts/init_firewall.sh:25-99`

### 6. `README.md`（目录内）
目的：定义推荐使用路径：优先调用仓库根 `scripts/stage_npm_packages.py`，不建议直接手工拼装。`codex-cli/scripts/README.md:3-23`

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. npm staging 主流程（上游 orchestrator -> 本目录脚本）

1. 上游入口
- CI/release 调用 `scripts/stage_npm_packages.py`。`.github/workflows/ci.yml:33-45`, `.github/workflows/rust-release.yml:490-499`
- 该脚本动态加载 `build_npm_package.py`，直接复用 `PACKAGE_NATIVE_COMPONENTS/PACKAGE_EXPANSIONS/CODEX_PLATFORM_PACKAGES`，避免重复定义矩阵。`scripts/stage_npm_packages.py:22-30`

2. native 工件准备
- 对需要 native 的 package，先 resolve workflow URL（可自动按 `rust-v<version>` 查找）。`scripts/stage_npm_packages.py:81-110`, `157-164`
- 调 `install_native_deps.py --workflow-url ... --component ... <vendor_root>`，把 native 解压到临时 vendor 根。`scripts/stage_npm_packages.py:113-126`

3. package stage + pack
- 对每个 package 调 `build_npm_package.py --staging-dir ... --pack-output ...`。`scripts/stage_npm_packages.py:169-190`
- 产物文件名协议：
  - 主包：`codex-npm-<version>.tgz`
  - 平台包：`codex-npm-<platform>-<version>.tgz`
  - 其他包：`<package>-npm-<version>.tgz`
  参考 `scripts/stage_npm_packages.py:133-138`。

### B. `build_npm_package.py` 内部实现

1. 关键数据结构
- `CODEX_PLATFORM_PACKAGES`：平台 alias -> `{npm_name,npm_tag,target_triple,os,cpu}`。`codex-cli/scripts/build_npm_package.py:21-64`
- `PACKAGE_NATIVE_COMPONENTS`：每个 package 需要的 native 组件列表。`codex-cli/scripts/build_npm_package.py:70-80`
- `COMPONENT_DEST_DIR`：组件名到 vendor 子目录映射。`codex-cli/scripts/build_npm_package.py:89-95`

2. stage 规则
- `codex`：复制 `bin/codex.js`，并可附带 `bin/rg` manifest。`codex-cli/scripts/build_npm_package.py:240-247`
- 平台包：生成极简 `package.json`（`os/cpu/files=vendor`），并将 name 固定为 `@openai/codex`。`codex-cli/scripts/build_npm_package.py:265-273`
- `codex-responses-api-proxy`：复制 npm launcher 与 README。`codex-cli/scripts/build_npm_package.py:282-293`
- `codex-sdk`：触发 `pnpm install/build` 后复制 `dist`。`codex-cli/scripts/build_npm_package.py:342-353`

3. vendor 复制协议
- 仅复制声明在 `components` 且存在于 `COMPONENT_DEST_DIR` 的目录。
- 平台包可启用 `target_filter`，若目标三元组缺失会 hard fail。`codex-cli/scripts/build_npm_package.py:388-415`

4. 命令执行
- `npm pack --json --pack-destination ...` 解析 JSON 输出文件名后搬运到 `--pack-output`。`codex-cli/scripts/build_npm_package.py:418-447`

### C. `install_native_deps.py` 内部实现

1. 组件模型
- `BinaryComponent`（artifact 前缀、目标目录、二进制名、可选 target 限制）。`codex-cli/scripts/install_native_deps.py:36-42`
- Windows 专属组件通过 `targets=WINDOWS_TARGETS` 约束。`codex-cli/scripts/install_native_deps.py:44-69`

2. Rust 工件安装
- artifact 命名规则：`<prefix>-<target>.zst`，Windows 为 `<prefix>-<target>.exe.zst`。`codex-cli/scripts/install_native_deps.py:334-337`
- 解压统一走 `extract_archive(..., "zst", ...)`，落地到 `vendor/<target>/<dest_dir>/...`。`codex-cli/scripts/install_native_deps.py:320-331`, `409-423`

3. ripgrep 安装
- 通过 `dotslash -- parse codex-cli/bin/rg` 获取平台 URL/格式/路径。`codex-cli/scripts/install_native_deps.py:456-469`
- 支持 `zst`、`tar.gz`、`zip` 三种格式。`codex-cli/scripts/install_native_deps.py:417-453`
- 并发下载各 target（`ThreadPoolExecutor`）。`codex-cli/scripts/install_native_deps.py:230-257`

4. GHA 友好日志协议
- 仅在 `GITHUB_ACTIONS=true` 时输出 `::group::` 和 `::error::` 注解，增强可观测性。`codex-cli/scripts/install_native_deps.py:86-120`

### D. 容器沙箱流程

1. 镜像构建
- `build_container.sh` 在 `codex-cli` 目录执行 `pnpm install/build/pack`，重命名 tgz 为 `dist/codex.tgz` 后 `docker build -t codex`。`codex-cli/scripts/build_container.sh:11-16`
- Dockerfile 将 `scripts/init_firewall.sh` 放入镜像并赋执行权限。`codex-cli/Dockerfile:55-56`

2. 容器执行与网络收敛
- `run_in_container.sh` 使用 `--cap-add=NET_ADMIN/NET_RAW` 启动容器。`codex-cli/scripts/run_in_container.sh:62-63`
- 允许域名来自 `OPENAI_ALLOWED_DOMAINS`（默认 `api.openai.com`），逐个校验正则后写入 `/etc/codex/allowed_domains.txt`。`codex-cli/scripts/run_in_container.sh:14`, `50-77`
- 执行 `init_firewall.sh` 后删除脚本，减少后续容器中被二次调用风险。`codex-cli/scripts/run_in_container.sh:83-87`
- 最终在挂载目录执行：`codex --full-auto <args>`。`codex-cli/scripts/run_in_container.sh:95`

3. 防火墙规则
- 清空既有规则 -> 放行 DNS/localhost -> 解析 allowlist 域名并写入 ipset -> 默认策略 DROP -> 仅放行目标 ipset -> 用 REJECT 提供快速失败。`codex-cli/scripts/init_firewall.sh:25-99`
- 自检策略：`example.com` 必须失败，`api.openai.com` 必须成功。`codex-cli/scripts/init_firewall.sh:102-115`

## 关键代码路径与文件引用

- 目录入口说明：`codex-cli/scripts/README.md:1-23`
- npm 构包核心：`codex-cli/scripts/build_npm_package.py:21-447`
- native 安装核心：`codex-cli/scripts/install_native_deps.py:21-475`
- 容器构建：`codex-cli/scripts/build_container.sh:1-16`
- 容器运行：`codex-cli/scripts/run_in_container.sh:1-95`
- 防火墙策略：`codex-cli/scripts/init_firewall.sh:1-115`

关键上下游：
- 上游 orchestrator：`scripts/stage_npm_packages.py:16-206`
- CI 调用：`.github/workflows/ci.yml:30-47`
- release 调用：`.github/workflows/rust-release.yml:488-500`
- npm 发布消费 staging 命名协议：`.github/workflows/rust-release.yml:572-647`
- 运行时消费 vendor 布局：`codex-cli/bin/codex.js:73-119`, `161-178`
- rg 清单协议：`codex-cli/bin/rg:1-79`
- 容器镜像中注入 firewall 脚本：`codex-cli/Dockerfile:53-56`

## 依赖与外部交互

### 本地命令依赖
- 发布链路：`python3`, `npm`, `pnpm`, `gh`, `dotslash`, `zstd`
  - `stage_npm_packages.py` 明确依赖 `gh`；`.github/workflows` 会显式安装 dotslash。参考：
    - `scripts/stage_npm_packages.py:82-95`
    - `.github/workflows/ci.yml:30-31`
    - `.github/workflows/rust-release.yml:488-489`
- 容器链路：`docker`（host），`iptables/ipset/dig/curl/iproute2`（container）
  - `codex-cli/Dockerfile:7-19`
  - `codex-cli/scripts/init_firewall.sh:26-66`, `102-115`

### 外部网络与服务交互
- GitHub Actions artifacts：`gh run list` / `gh run download`
  - `scripts/stage_npm_packages.py:82-95`
  - `codex-cli/scripts/install_native_deps.py:262-273`
- ripgrep 发行源（GitHub Release URL）：来自 DotSlash manifest provider URL
  - `codex-cli/bin/rg:14-15`, `26-27`, `50-51`, `62-63`, `74-75`
  - `codex-cli/scripts/install_native_deps.py:351-406`
- 容器内 API 可达性探测：`curl https://api.openai.com`
  - `codex-cli/scripts/init_firewall.sh:109-114`

### 配置/环境变量交互
- `OPENAI_ALLOWED_DOMAINS`、`OPENAI_API_KEY`、`WORKSPACE_ROOT_DIR`：容器运行脚本使用。`codex-cli/scripts/run_in_container.sh:12-14`, `60-64`
- `GITHUB_ACTIONS`：native 安装脚本决定是否输出 workflow commands。`codex-cli/scripts/install_native_deps.py:86-120`
- `RUNNER_TEMP`：staging 临时目录根。`scripts/stage_npm_packages.py:146`

## 风险、边界与改进建议

1. 文档与实现偏差
- `codex-cli/README.md` 仍写 `./scripts/install_native_deps.sh`，但当前脚本是 `.py`。`codex-cli/README.md:316-317` vs `codex-cli/scripts/install_native_deps.py:1`
- 建议：修正文档命令并补充 `gh/dotslash/zstd` 前置依赖。

2. ripgrep 下载完整性校验缺口
- manifest 提供 `hash/digest/size`，脚本目前仅读取并用于报错上下文，未做强校验。`codex-cli/bin/rg:7-10`, `42-45`; `codex-cli/scripts/install_native_deps.py:354-355`, `380-383`
- 建议：下载后强制 SHA-256 与 size 校验，失败立即中止。

3. 防火墙策略的地址族边界
- 解析逻辑仅处理 `dig +short A`（IPv4），未纳入 AAAA/IPv6。`codex-cli/scripts/init_firewall.sh:49`, `56-57`
- 建议：明确禁用 IPv6 或补充 `AAAA + ip6tables/ipset` 同步规则，避免策略绕过或误判。

4. 容器运行参数与可移植性
- `run_in_container.sh` 假设 docker 可用且授予 `NET_ADMIN/NET_RAW`，在受限环境会失败。`codex-cli/scripts/run_in_container.sh:60-63`
- 建议：增加 preflight 检查（docker daemon、capability）与清晰失败提示。

5. 变更可回归性不足
- 当前目录脚本没有独立单元测试，主要依赖 CI 真实流程执行。
- 建议：
  - 给 `build_npm_package.py` 的 `copy_native_binaries`、版本命名与 optionalDependencies 生成增加 fixture 测试。
  - 给 `install_native_deps.py` 的 archive 解压和 manifest 解析增加离线测试样本。

6. workflow pinning 风险
- `install_native_deps.py` 的 `DEFAULT_WORKFLOW_URL` 固定到历史 run id。`codex-cli/scripts/install_native_deps.py:23`
- 边界：如果 run 被清理或权限变化，本地默认路径会失效。
- 建议：默认优先通过版本分支解析 workflow（类似 `stage_npm_packages.py`），固定 URL 仅作为 fallback。
