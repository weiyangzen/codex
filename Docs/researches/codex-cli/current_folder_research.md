# DIR `codex-cli` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-cli`（DIR）
- 研究日期：2026-03-19
- 研究范围：`codex-cli` 目录本身，以及其调用方（CI/release/staging/SDK）、被调用方（Rust 二进制、Docker/iptables、gh/npm/dotslash 等）、相关配置与文档。

## 场景与职责

`codex-cli` 在当前仓库中的定位是“npm 分发与启动桥接层”，而不是核心业务执行层：

1. npm 入口门面
- 对外发布包名是 `@openai/codex`，`bin` 入口为 `bin/codex.js`，用户执行 `codex` 实际会进入这个 JS wrapper（`codex-cli/package.json:2-7`）。
- `codex-cli/README.md` 已明确这是 legacy TypeScript 实现文档，主实现已迁移到 Rust（`codex-cli/README.md:6-7`）。

2. 原生二进制分发编排
- `bin/codex.js` 负责平台识别、定位平台包中的 `vendor/<triple>/codex/{codex|codex.exe}` 并转发执行（`codex-cli/bin/codex.js:15-118`）。
- 平台原生产物由 release/staging 脚本写入 `vendor/`，并由 npm 平台包携带（`codex-cli/scripts/build_npm_package.py:21-95`）。

3. 发布链路中的“打包节点”
- 仓库根脚本 `scripts/stage_npm_packages.py` 通过 `codex-cli/scripts/build_npm_package.py` + `install_native_deps.py` 生产 `codex` 与平台 tarball（`scripts/stage_npm_packages.py:17-29`）。
- CI 与 release workflow 都调用该 staging 方案（`.github/workflows/ci.yml:30-47`，`.github/workflows/rust-release.yml:488-500`）。

4. Linux 容器隔离辅助层
- 提供 Dockerfile 与 `run_in_container.sh`/`init_firewall.sh`，用于在 Linux 下将 Codex 放入容器并限制网络出口（`codex-cli/Dockerfile:1-59`，`codex-cli/scripts/run_in_container.sh:60-95`，`codex-cli/scripts/init_firewall.sh:25-115`）。

## 功能点目的

1. 统一跨平台启动体验
- 用户只安装 `@openai/codex`，通过可选依赖自动拉取对应平台包；`codex` 命令保持一致。
- 目标：把“平台差异 + 二进制路径差异”隐藏在 wrapper 内。

2. 降低 npm 包重复发布冲突
- 平台包版本通过 `"<release>-<platform-tag>"` 生成（如 `1.2.3-linux-x64`），规避 npm 不能重复发布同名同版本限制（`codex-cli/scripts/build_npm_package.py:331-334`）。

3. 实现“轻量主包 + 平台包”分层
- 主包 `codex` 通过 `optionalDependencies` 指向别名包（`@openai/codex-linux-x64` 等），底层真实发布名统一映射为 `@openai/codex@<platform-version>`（`codex-cli/scripts/build_npm_package.py:304-313`）。

4. 支持附属产物一体化 staging
- 同一套脚本同时处理 `codex`、`codex-responses-api-proxy`、`codex-sdk`，避免发布流程割裂（`codex-cli/scripts/build_npm_package.py:282-325`）。

5. 提供 Linux 下额外隔离运行方式
- `run_in_container.sh` 自动起容器、注入允许域名、配置 iptables/ipset，并以 `codex --full-auto` 执行命令（`codex-cli/scripts/run_in_container.sh:68-95`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) CLI 启动关键流程（`bin/codex.js`）

1. 平台三元组解析
- 根据 `process.platform` + `process.arch` 映射到目标 triple：
  - `linux/android + x64 -> x86_64-unknown-linux-musl`
  - `darwin + arm64 -> aarch64-apple-darwin`
  - `win32 + arm64 -> aarch64-pc-windows-msvc`
- 映射常量位于 `PLATFORM_PACKAGE_BY_TARGET`（`codex-cli/bin/codex.js:15-67`）。

2. 平台包与 vendor 根目录定位
- 优先 `require.resolve(<platformPackage>/package.json)` 定位平台包。
- 如果失败，回退本地 `codex-cli/vendor`（用于本地已注入 vendor 的场景）。
- 都失败时，按 npm/bun 生成重装提示（`codex-cli/bin/codex.js:87-115`）。

3. PATH 注入 + 进程转发
- 若存在 `vendor/<triple>/path`，追加进 PATH（通常承载 bundled `rg`）（`codex-cli/bin/codex.js:161-167`）。
- 设置 `CODEX_MANAGED_BY_NPM` 或 `CODEX_MANAGED_BY_BUN` 后 `spawn` 原生 `codex`。
- 转发 `SIGINT/SIGTERM/SIGHUP`，并按子进程退出码/信号退出父进程（`codex-cli/bin/codex.js:168-229`）。

### 2) npm staging/packaging 流程（Python）

1. 包类型建模
- `CODEX_PLATFORM_PACKAGES`：平台包映射（npm 别名、tag、triple、os/cpu）
- `PACKAGE_NATIVE_COMPONENTS`：每种包需要复制的 native 组件集合
- `COMPONENT_DEST_DIR`：组件到 vendor 子目录映射（`codex-cli/scripts/build_npm_package.py:21-95`）

2. 核心命令形态
- `build_npm_package.py --package <name> --release-version <v> --staging-dir <dir> [--vendor-src <vendor>] [--pack-output <tgz>]`
- 对需要 native 的包，若缺少 `--vendor-src` 会直接失败（`codex-cli/scripts/build_npm_package.py:166-173`）。

3. 主包与平台包构造差异
- `codex`：拷贝 `bin/codex.js` + `bin/rg` manifest，写 `optionalDependencies`。
- 平台包：写 `os/cpu/files=vendor`，按 target 过滤复制 native 文件（`codex-cli/scripts/build_npm_package.py:240-313`，`361-420`）。

4. vendor 复制逻辑
- 遍历 `vendor_src/<target>`，按 `COMPONENT_DEST_DIR` 将对应目录复制到 staged 包。
- 如果 target 缺失会报错（`codex-cli/scripts/build_npm_package.py:361-420`）。

### 3) native 依赖安装流程（`install_native_deps.py`）

1. Rust 产物来源
- 通过 `gh run download --repo openai/codex <workflow_id>` 下载 release workflow 产物（`codex-cli/scripts/install_native_deps.py:262-273`）。

2. 组件抽象
- `BinaryComponent` 描述 artifact 前缀、目标目录、二进制名称及可选 target 过滤。
- Windows 专属组件：`codex-windows-sandbox-setup`、`codex-command-runner`（`codex-cli/scripts/install_native_deps.py:36-69`）。

3. ripgrep 安装机制
- 读取 DotSlash manifest `codex-cli/bin/rg`（`dotslash -- parse ...`）并按平台下载对应压缩包（`codex-cli/scripts/install_native_deps.py:194-259`，`474-490`）。
- 支持 `tar.gz`、`zip`、`zst` 三种解包（`codex-cli/scripts/install_native_deps.py:409-459`）。

4. 并发策略
- 安装组件和拉取 rg 都使用 `ThreadPoolExecutor` 并发执行，worker 数按 target 数与 CPU 核数取最小（`codex-cli/scripts/install_native_deps.py:230-235`，`291-303`）。

### 4) 容器执行与网络约束流程（Shell）

1. 镜像构建
- `build_container.sh` 在 `codex-cli` 下执行 `pnpm install && pnpm run build && pnpm pack`，重命名产物为 `dist/codex.tgz` 后 `docker build -t codex`（`codex-cli/scripts/build_container.sh:11-16`）。

2. 容器启动与命令执行
- `run_in_container.sh`：
  - 以当前目录生成唯一容器名
  - `docker run` 挂载工作目录到 `/app<workdir>`
  - 写入允许域名到 `/etc/codex/allowed_domains.txt`
  - 运行并删除 `init_firewall.sh`
  - 最终执行 `codex --full-auto <user-args>`（`codex-cli/scripts/run_in_container.sh:28-95`）

3. 防火墙策略
- `init_firewall.sh`：
  - 清空既有规则，建立 `ipset allowed-domains`
  - 放行 DNS + localhost + host 网段
  - 默认策略 `DROP`，仅允许目标域解析出的 IP
  - 通过 `curl example.com`（应失败）和 `curl api.openai.com`（应成功）验收（`codex-cli/scripts/init_firewall.sh:25-115`）。

### 5) 关联协议与命令（目录外调用语境）

1. staging 入口命令
- `./scripts/stage_npm_packages.py --release-version <v> --package codex ...`（`codex-cli/scripts/README.md:3-23`）。

2. release workflow 发布策略
- stable 版本发布默认 tag；`-alpha.n` 发布 `alpha` tag。
- 平台 tarball 会附带平台 dist-tag（如 `linux-x64`）后缀（`.github/workflows/rust-release.yml:456-647`）。

3. SDK 调用协议
- TypeScript SDK 通过 `spawn(codex, ["exec", "--experimental-json", ...])` 与 CLI 交换 JSONL 事件（`sdk/typescript/src/exec.ts:72-216`，`sdk/typescript/README.md:5`）。

## 关键代码路径与文件引用

### A. `codex-cli` 内部核心
- 启动入口：`codex-cli/bin/codex.js:15-229`
- ripgrep DotSlash 清单：`codex-cli/bin/rg:1-79`
- npm 主包元数据：`codex-cli/package.json:1-22`
- 容器基础镜像：`codex-cli/Dockerfile:1-59`
- staging 核心：`codex-cli/scripts/build_npm_package.py:21-459`
- native 安装器：`codex-cli/scripts/install_native_deps.py:21-490`
- 容器运行器：`codex-cli/scripts/run_in_container.sh:11-95`
- 防火墙脚本：`codex-cli/scripts/init_firewall.sh:5-115`
- 目录内发布说明：`codex-cli/scripts/README.md:1-23`

### B. 调用方（上游）
- 统一 staging orchestrator：`scripts/stage_npm_packages.py:16-206`
- 常规 CI staging 检查：`.github/workflows/ci.yml:30-53`
- 正式 release staging + npm publish：`.github/workflows/rust-release.yml:456-647`

### C. 被调用方（下游/并行消费者）
- TypeScript SDK 对 codex 二进制定位与调用：`sdk/typescript/src/exec.ts:46-53`，`sdk/typescript/src/exec.ts:317-389`
- SDK 文档说明其包装 `@openai/codex`：`sdk/typescript/README.md:5`
- responses-api-proxy npm 包（同类分发模型）：`codex-rs/responses-api-proxy/npm/package.json:1-22`，`codex-rs/responses-api-proxy/npm/bin/codex-responses-api-proxy.js:11-97`

## 依赖与外部交互

### 1) 构建与打包依赖

1. Node / PNPM
- 工作区包含 `codex-cli`（`pnpm-workspace.yaml:1-5`）。
- 仓库根要求 Node >= 22，但 `@openai/codex` 包声明 Node >= 16（`package.json:21-24`，`codex-cli/package.json:9-11`）。

2. Python 脚本运行时
- `build_npm_package.py` 与 `install_native_deps.py` 依赖 Python3 + 标准库。

3. DotSlash
- `install_native_deps.py` 用 `dotslash -- parse` 解析 `bin/rg` manifest（`codex-cli/scripts/install_native_deps.py:474-476`）。
- CI/release 专门安装 DotSlash（`.github/workflows/ci.yml:30-31`，`.github/workflows/rust-release.yml:488-489`）。

### 2) 外部服务与命令交互

1. GitHub APIs / GH CLI
- `gh run list` 查找 release workflow（`scripts/stage_npm_packages.py:81-103`）。
- `gh run download` 下载 native artifacts（`codex-cli/scripts/install_native_deps.py:262-273`）。

2. npm registry
- release job 下载 tgz 后 `npm publish`（`.github/workflows/rust-release.yml:562-647`）。

3. 第三方下载源
- ripgrep 二进制从 GitHub Releases 拉取（`codex-cli/bin/rg:14-75`）。

4. 系统/容器网络能力
- Docker 需要 `NET_ADMIN` / `NET_RAW` 以应用 iptables/ipset（`codex-cli/scripts/run_in_container.sh:62-63`）。
- 防火墙依赖 `iptables`, `ipset`, `dig`, `curl`（`codex-cli/scripts/init_firewall.sh:25-115`）。

### 3) 配置与环境变量

- `OPENAI_API_KEY` 透传到容器（`codex-cli/scripts/run_in_container.sh:61`）。
- `OPENAI_ALLOWED_DOMAINS` 控制允许域名，默认 `api.openai.com`（`codex-cli/scripts/run_in_container.sh:14`）。
- `CODEX_MANAGED_BY_NPM/BUN` 由 launcher 注入，标记安装来源（`codex-cli/bin/codex.js:169-173`）。
- `CODEX_UNSAFE_ALLOW_NO_SANDBOX=1` 在容器内默认打开（`codex-cli/Dockerfile:49-51`）。

## 风险、边界与改进建议

### 风险

1. 文档与实现存在局部漂移
- README 中 `./scripts/install_native_deps.sh` 与当前实际脚本名 `install_native_deps.py` 不一致（`codex-cli/README.md:316-317` vs `codex-cli/scripts/install_native_deps.py`）。

2. 启动映射重复维护
- `PLATFORM_PACKAGE_BY_TARGET` 在 `codex-cli/bin/codex.js` 与 `sdk/typescript/src/exec.ts` 各维护一份，新增平台时有分叉风险（`codex-cli/bin/codex.js:15-22`，`sdk/typescript/src/exec.ts:46-53`）。

3. 供应链完整性校验不完整
- `bin/rg` manifest 含 `digest/size`，`install_native_deps.py` 会读取但未显式校验 digest，当前主要依赖 TLS 与下载源可信性（`codex-cli/scripts/install_native_deps.py:354-355`）。

4. 防火墙策略局限于 IPv4 A 记录
- `init_firewall.sh` 只解析 `dig +short A`，未覆盖 AAAA/IPv6。

5. 目录内缺少自动化测试覆盖
- `codex-cli` 未见独立单元测试；当前主要靠 CI staging/release 过程暴露问题（`.github/workflows/ci.yml:33-53`）。

### 边界

1. `codex-cli` 不承载模型交互/agent 核心逻辑，核心行为在 Rust `codex` 二进制。
2. 该目录核心价值在于“分发、封装、启动、发布链路”，不是产品功能本身。
3. 容器隔离脚本属于 Linux 辅助能力，默认主线路径仍是直接运行已安装的 `codex` 命令。

### 改进建议

1. 统一平台映射源
- 将平台 triple -> npm 包映射抽到单一生成源（如 JSON 模板），`codex.js` 与 SDK 构建时共享，减少双端漂移。

2. 补充下载完整性校验
- 在 `install_native_deps.py` 对 ripgrep 下载结果执行 `sha256` 校验（可直接复用 manifest 中 `digest` 字段）。

3. 修复并收敛 README 发布说明
- 把 `install_native_deps.sh` 更正为 `.py`，并将 `legacy` 与当前 release 流程关联（`scripts/stage_npm_packages.py`）写成同一条主路径。

4. 增加轻量回归测试
- 为 `bin/codex.js` 的平台解析、错误提示、fallback 路径增加最小 Node 级测试；为 Python staging 脚本增加参数校验测试。

5. 强化容器防火墙策略说明
- 在脚本或 README 中明确 IPv6 行为、域名解析更新策略（DNS 变更后的重建时机）。
