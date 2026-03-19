# codex-cli/bin 目录研究（DIR）

## 场景与职责

`codex-cli/bin` 是 npm 包 `@openai/codex` 的运行时入口层，职责不是实现 CLI 业务，而是把“用户命令”稳定路由到平台对应的原生二进制。

该目录仅包含两个入口对象：

- `codex-cli/bin/codex.js`：npm `bin` 字段指向的统一 launcher（`codex-cli/package.json:5-7`）。
- `codex-cli/bin/rg`：DotSlash manifest，描述 ripgrep 在多平台下的下载来源与元信息（`codex-cli/bin/rg:1-79`）。

目录在系统中的角色是“薄包装层 + 供应链描述层”：

- 薄包装层负责平台识别、依赖定位、环境变量注入、信号/退出码透传（`codex-cli/bin/codex.js:24-229`）。
- 供应链描述层（`bin/rg`）被发布脚本消费，下载并落地 `vendor/<triple>/path/rg[.exe]`（`codex-cli/scripts/install_native_deps.py:25`, `194-259`, `340-399`）。

## 功能点目的

1. 统一用户入口，屏蔽平台差异
- 用户执行 `codex` 时进入 JS launcher（`codex-cli/package.json:5-7`），launcher 再按 `platform+arch` 映射到目标 triple（`codex-cli/bin/codex.js:26-67`）。

2. 将 npm 元包与平台包解耦
- `@openai/codex` 自身是 meta 包；真正二进制来自可选依赖平台包（`@openai/codex-linux-x64` 等）。映射常量在 launcher 中固定（`codex-cli/bin/codex.js:15-22`）。
- 发布脚本会自动写 `optionalDependencies` 指向这些平台别名（`codex-cli/scripts/build_npm_package.py:304-313`）。

3. 保障本地开发/打包时的 fallback 可运行
- 优先 `require.resolve(<platform-package>/package.json)` 找 vendor；失败时尝试本地 `../vendor`（`codex-cli/bin/codex.js:87-104`）。
- fallback 允许 staging 或源码环境在未完整安装 optional dependency 时仍可启动。

4. 启动前注入补充 PATH（主要是 bundled `rg`）
- launcher 会探测 `vendor/<triple>/path` 并 prepend 到 PATH（`codex-cli/bin/codex.js:161-167`），让原生 `codex` 在运行时优先命中同包内工具链。

5. 向下游 UI 更新逻辑暴露“安装来源”信号
- launcher 设置 `CODEX_MANAGED_BY_NPM` 或 `CODEX_MANAGED_BY_BUN`（`codex-cli/bin/codex.js:169-173`）。
- Rust TUI/TUI App Server 用它决定“升级命令建议”（`codex-rs/tui/src/update_action.rs:31-61`，`codex-rs/tui_app_server/src/update_action.rs:31-61`）。

6. 为 ripgrep 多平台分发提供声明式清单
- `bin/rg` 包含每个平台的 URL / digest / format / path（`codex-cli/bin/rg:6-77`）。
- 安装脚本基于该清单拉取并解压（`codex-cli/scripts/install_native_deps.py:208-227`, `340-453`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) `codex.js` 启动关键流程

A. 平台解析
- 输入：`process.platform`, `process.arch`。
- 输出：Rust 目标 triple（linux/android、darwin、win32 三大分支）。
- 未命中即抛错 `Unsupported platform`（`codex-cli/bin/codex.js:24-71`）。

B. 包映射与 vendor 定位
- `PLATFORM_PACKAGE_BY_TARGET: triple -> npm 平台包名`（`codex-cli/bin/codex.js:15-22`）。
- 优先 `require.resolve(${platformPackage}/package.json)` 推导 vendor 根（`codex-cli/bin/codex.js:87-91`）。
- 失败后检查本地 `../vendor/<triple>/codex/<binary>` 是否存在（`codex-cli/bin/codex.js:79-85`, `92-94`）。
- 两者都失败时给出重装命令提示（`codex-cli/bin/codex.js:95-115`）。

C. PATH 与环境变量构造
- `getUpdatedPath()` 采用平台分隔符拼接新 PATH（`codex-cli/bin/codex.js:126-134`）。
- 如存在 `vendor/<triple>/path`，加入 PATH 前缀（`codex-cli/bin/codex.js:161-167`）。
- 设置 `CODEX_MANAGED_BY_BUN` 或 `CODEX_MANAGED_BY_NPM`（`codex-cli/bin/codex.js:169-173`）。

D. 子进程执行与生命周期透传
- `spawn(binaryPath, process.argv.slice(2), { stdio: "inherit", env })`（`codex-cli/bin/codex.js:175-178`）。
- 前向转发 `SIGINT/SIGTERM/SIGHUP`（`codex-cli/bin/codex.js:189-206`）。
- 根据子进程 `exit` 结果：
  - 若 signal 退出，父进程 re-emit 同信号（`codex-cli/bin/codex.js:223-227`）。
  - 若 code 退出，父进程使用同退出码（`codex-cli/bin/codex.js:227-228`）。

### 2) `bin/rg` 清单机制

`bin/rg` 不是 shell 脚本，而是 DotSlash 清单（shebang: `#!/usr/bin/env dotslash`，`codex-cli/bin/rg:1`）。

核心字段：
- `platforms.<platform>.providers[0].url`：下载地址（GitHub Releases）（`codex-cli/bin/rg:12-15`, `24-27`, `36-39`, `48-51`, `60-63`, `72-75`）。
- `digest/hash/size`：校验元数据（`codex-cli/bin/rg:7-10` 等）。
- `format`：`tar.gz` 或 `zip`（`codex-cli/bin/rg:10`, `22`, `34`, `46`, `58`, `70`）。
- `path`：压缩包内目标成员路径（`codex-cli/bin/rg:11`, `23`, `35`, `47`, `59`, `71`）。

安装脚本读取流程：
- 用 `dotslash -- parse <manifest>` 解析（`codex-cli/scripts/install_native_deps.py:456-469`）。
- 将 `target triple` 映射为 `manifest platform key`（`71-80`, `217-227`）。
- 并发下载与解压（`234-259`, `364-399`）。
- 解压支持 `zst`、`tar.gz`、`zip`（`409-453`）。

### 3) 发布链路中的装配逻辑

A. stage 脚本总入口
- `scripts/stage_npm_packages.py` 统一编排：先装 native，再为每个 package 调 `build_npm_package.py`（`scripts/stage_npm_packages.py:113-125`, `157-194`）。

B. `build_npm_package.py` 与 `bin` 的直接关系
- staging `codex` 包时会拷贝 `bin/codex.js` 与 `bin/rg`（`codex-cli/scripts/build_npm_package.py:240-247`）。
- 生成 `optionalDependencies`（meta 包 -> 各平台包别名）供 `codex.js` 运行时解析（`304-313`）。
- 平台包自身只打 `vendor` 内容（`265-273`）。

C. CI/Release 工作流依赖
- CI 与 rust-release 在 stage npm 包前均安装 DotSlash（`.github/workflows/ci.yml:30-45`, `.github/workflows/rust-release.yml:488-499`）。
- 说明 `bin/rg` 的清单解析是发布流程硬依赖。

### 4) 与 SDK 的“并行实现”关系

TypeScript SDK 不调用 `bin/codex.js`，但在 `findCodexPath()` 中复制了同样的平台映射与 vendor 解析逻辑（`sdk/typescript/src/exec.ts:46-53`, `317-389`），语义上与 launcher 平行。

## 关键代码路径与文件引用

核心对象：
- `codex-cli/bin/codex.js:1-229`
- `codex-cli/bin/rg:1-79`

直接调用方与装配方：
- `codex-cli/package.json:5-7`（`bin.codex -> bin/codex.js`）
- `codex-cli/scripts/build_npm_package.py:240-247`（拷贝 bin）
- `codex-cli/scripts/build_npm_package.py:304-313`（写 optionalDependencies）
- `scripts/stage_npm_packages.py:17-19`, `113-125`, `157-194`（发布编排）
- `.github/workflows/ci.yml:30-45`（CI staging）
- `.github/workflows/rust-release.yml:488-499`（release staging）

被调用方/下游联动：
- 平台包 vendor 二进制（`codex-cli/bin/codex.js:117-118`, `175-178`）
- `codex-rs/tui/src/update_action.rs:31-61`（读取 `CODEX_MANAGED_BY_*`）
- `codex-rs/tui_app_server/src/update_action.rs:31-61`（同上）
- `codex-cli/scripts/install_native_deps.py:194-259`, `340-399`, `456-469`（消费 `bin/rg`）
- `sdk/typescript/src/exec.ts:317-389`（平行查找机制）

配置、文档、说明：
- `codex-cli/package.json:9-15`（Node 版本、files）
- `codex-cli/scripts/README.md:14-23`（vendor hydration 与 staging 说明）
- `sdk/typescript/README.md:5-6`（SDK 包装 CLI）
- `codex-cli/README.md:7`, `206-213`, `284-297`（安装/系统要求/历史文档定位）

测试现状：
- `codex-cli` 目录内未检索到针对 `bin/codex.js` 或 `bin/rg` 的直接测试用例（按 `*test*`, `*.spec.*`, `*.snap` 检索为空）。
- 与 launcher 环境变量相关的行为，存在 Rust 侧更新动作检测单测（`codex-rs/tui/src/update_action.rs:64-101`，`codex-rs/tui_app_server/src/update_action.rs:64-101`）。

## 依赖与外部交互

运行时依赖（`codex.js`）：
- Node 内建模块：`child_process`, `fs`, `module`, `path`, `url`（`codex-cli/bin/codex.js:4-8`）。
- 本地文件系统：`vendor/<triple>/codex` 与 `vendor/<triple>/path`。
- 环境变量：
  - 读取：`npm_config_user_agent`, `npm_execpath`, `PATH`（`codex-cli/bin/codex.js:141-158`, `128`）。
  - 写入：`CODEX_MANAGED_BY_NPM/BUN`（`169-173`）。

构建/发布依赖（围绕 `bin/rg`）：
- CLI 工具：`gh`, `dotslash`, `zstd`, `npm`, `pnpm`（来自脚本行为与 workflow）。
- 远端接口：
  - GitHub Actions artifacts（`gh run download`，`install_native_deps.py:262-273`）。
  - GitHub Releases（ripgrep 下载 URL，`codex-cli/bin/rg:14-75`，下载逻辑 `401-406`）。

协议/命令层面：
- 用户升级提示协议：通过 `CODEX_MANAGED_BY_*` 让 Rust UI 给出 npm/bun 升级命令。
- 发布协议：`stage_npm_packages.py -> install_native_deps.py -> build_npm_package.py -> npm pack`。

## 风险、边界与改进建议

1. 平台映射重复维护风险
- `PLATFORM_PACKAGE_BY_TARGET` 在 `codex-cli/bin/codex.js` 与 `sdk/typescript/src/exec.ts` 各维护一份（`codex-cli/bin/codex.js:15-22` vs `sdk/typescript/src/exec.ts:46-53`）。
- 改进：抽出单一生成源（例如构建期生成常量）减少平台新增时的漏改概率。

2. `rg` 下载完整性校验未显式执行
- manifest 含 `digest/size`，但 `install_native_deps.py` 当前读取后仅用于错误上下文，未主动比对（`codex-cli/scripts/install_native_deps.py:354-355`, `380-383`）。
- 改进：下载后执行 sha256 与 size 校验，不匹配即失败。

3. `detectPackageManager()` 回退策略可能误判
- 未识别 bun 时默认设置 `CODEX_MANAGED_BY_NPM`（`codex-cli/bin/codex.js:169-173`）。
- 在“未知安装来源”场景会影响升级提示策略。
- 改进：支持 `unknown` 分支，避免错误注入来源标记。

4. 入口缺少直接自动化测试
- 当前缺乏对 `codex.js`（平台分支、fallback、信号转发）和 `bin/rg`（清单完整性）的独立测试。
- 改进：
  - 为 `codex.js` 增加 Node 级最小测试（mock `process.platform/arch` 与 `require.resolve` 行为）。
  - 为 `bin/rg` 增加 schema/字段完整性校验脚本并纳入 CI。

5. Node 版本边界存在文档/工程分层差异
- `@openai/codex` 包声明 Node >=16（`codex-cli/package.json:9-11`），而仓库 CI stage npm 使用 Node 22（`.github/workflows/ci.yml:22-26`）。
- 这不是直接 bug，但会影响本地复现差异。
- 改进：在发布/开发文档中明确“最低运行版本”和“仓库开发版本”差异边界。

6. fallback 边界
- `localVendorRoot` fallback 仅在本地 vendor 已存在时可用（`codex-cli/bin/codex.js:79-94`），并不替代 optionalDependencies。
- 改进：在错误提示中补充 `npm config set include=optional` / 包管理器 optional 相关提示，降低用户误判。

