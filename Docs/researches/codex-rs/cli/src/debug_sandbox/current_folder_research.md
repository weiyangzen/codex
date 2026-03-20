# DIR `codex-rs/cli/src/debug_sandbox` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 关联主模块：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs`
- 关联 crate：`codex-cli`

## 场景与职责

`debug_sandbox` 目录（含其父模块 `debug_sandbox.rs`）是 `codex` CLI 的“沙箱调试执行器”。它与日常 agent 工具执行路径（`codex-core` 的 sandboxing pipeline）不同，定位是：

1. 把用户手工输入的命令直接放到指定平台沙箱里运行（macOS/ Linux/ Windows）。
2. 保留接近原生命令行的 I/O 行为（继承 stdin/stdout/stderr，退出码透传）。
3. 允许用 `--full-auto` 快速切换 legacy `sandbox_mode`（只读/工作区可写）。
4. 在 macOS 额外提供 denial 观测能力（`--log-denials`），帮助定位 Seatbelt 拒绝原因。

它在 CLI 路由上的位置是：

- `codex sandbox macos|linux|windows` 参数解析：`/home/sansha/Github/codex/codex-rs/cli/src/main.rs:239`、`/home/sansha/Github/codex/codex-rs/cli/src/main.rs:246`
- 调度到本模块：`/home/sansha/Github/codex/codex-rs/cli/src/main.rs:788`
- 三类命令结构体定义（`full_auto/log_denials/config_overrides/command`）：`/home/sansha/Github/codex/codex-rs/cli/src/lib.rs:9`、`/home/sansha/Github/codex/codex-rs/cli/src/lib.rs:27`、`/home/sansha/Github/codex/codex-rs/cli/src/lib.rs:41`

## 功能点目的

1. 跨平台沙箱实验入口统一化
- 目的：避免用户分别记忆多个平台 helper 命令，统一使用 `codex sandbox <platform> -- <cmd...>`。
- 实现：`run_command_under_seatbelt / run_command_under_landlock / run_command_under_windows` 统一汇聚到 `run_command_under_sandbox`。

2. `--full-auto` 快捷模式
- 目的：快速把命令切到 legacy `sandbox_mode` 的 `workspace-write`，便于复现“可写+无网络”常见调试场景。
- 实现：`create_sandbox_mode(true) => WorkspaceWrite`，`false => ReadOnly`。

3. profile 配置与 legacy 模式兼容控制
- 目的：当用户配置已采用 `[permissions]` + `default_permissions`（新模型）时，避免 `--full-auto` 混用导致语义不清。
- 实现：检测到 `default_permissions` 后，`--full-auto` 直接报错并要求选择可写 profile。

4. macOS denial 收集
- 目的：把 `sandbox-exec` 拒绝事件从系统日志聚合成可读摘要，降低排障成本。
- 实现：`DenialLogger` + `PidTracker` 只收集当前被测子进程树相关事件，减少噪音。

5. managed network proxy 联动
- 目的：在配置了受管网络代理时，让 sandbox 内命令可按策略走代理，而不是直接放开网络。
- 实现：运行前启动 proxy，向子进程注入代理环境；网络受限时再设置 `CODEX_SANDBOX_NETWORK_DISABLED=1`。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 总流程（从 CLI 到子进程）

1. `main.rs` 匹配 `Subcommand::Sandbox`，把根 `-c` 覆盖合并进子命令，再调用本模块入口：
- `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:788`

2. 入口函数拆包参数后进入统一执行函数：
- macOS: `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:36`
- Linux: `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:65`
- Windows: `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:85`
- 统一执行：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:112`

3. 配置加载：先解析 `CliConfigOverrides` 的 `-c key=value`，再用 `ConfigBuilder` 构建最终 `Config`。
- `parse_overrides`：`/home/sansha/Github/codex/codex-rs/utils/cli/src/config_override.rs:42`
- config 构建：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:426`

4. 生成子进程环境：
- 使用 `create_env(shell_environment_policy, None)` 做环境变量白/黑名单与覆盖处理。
- 函数定义：`/home/sansha/Github/codex/codex-rs/core/src/exec_env.rs:20`

5. 按平台分叉：
- macOS：拼 Seatbelt profile 参数并调用 `/usr/bin/sandbox-exec`。
- Linux：拼 `codex-linux-sandbox` 参数并执行 helper。
- Windows：调用 `codex-windows-sandbox` 捕获器，复制 stdout/stderr 后直接 `process::exit`。

6. 等待子进程结束并透传退出状态：
- `child.wait().await` 后调用 `handle_exit_status(status)`：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:317`、`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:332`

### 2) 配置分支与 `--full-auto` 规则

关键逻辑在 `load_debug_sandbox_config_with_codex_home`：

- 先在“无 `sandbox_mode` 强制覆盖”的前提下构建一次 config。
- 若检测到 `default_permissions`（表示走 permission profile），则：
  - `full_auto=false`：直接使用 profile 解析结果。
  - `full_auto=true`：报错拒绝。
- 若未检测到 profile，才注入 legacy `sandbox_mode`（read-only/workspace-write）重建 config。

对应代码：
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:388`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:404`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:413`
- `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs:57`

### 3) Linux 协议参数拼装（CLI -> helper）

`debug_sandbox` 不直接执行隔离系统调用，而是构造 helper 协议参数给 `codex-linux-sandbox`：

- 入口参数生成函数：`create_linux_sandbox_command_args_for_policies`。
- 参数包含：
  - `--sandbox-policy-cwd`
  - `--command-cwd`
  - `--sandbox-policy`（legacy policy JSON）
  - `--file-system-sandbox-policy`（split policy JSON）
  - `--network-sandbox-policy`（split policy JSON）
  - 可选 `--use-legacy-landlock`
  - `--` 后附原命令

代码与 helper 侧契约：
- 参数生成：`/home/sansha/Github/codex/codex-rs/core/src/landlock.rs:78`
- debug_sandbox 调用点：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:281`
- helper CLI 字段：`/home/sansha/Github/codex/codex-rs/linux-sandbox/src/linux_run_main.rs:27`
- helper 主流程（bubblewrap 默认、legacy landlock fallback）：`/home/sansha/Github/codex/codex-rs/linux-sandbox/src/linux_run_main.rs:99`

### 4) macOS denial 采集机制（目录内核心实现）

`DenialLogger` 的三步：

1. `new()` 启动 `log stream --style ndjson --predicate ...`，异步读取 stdout 原始日志行。
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs:20`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs:87`

2. `on_child_spawn()` 记录根 pid，并启动 `PidTracker` 递归追踪后代 pid 集。
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs:46`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:13`

3. `finish()` 停止 tracker、杀掉 log stream，逐行解析 `eventMessage`，正则抽取 `(pid,name,capability)`，仅保留目标 pid 树且去重。
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs:52`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs:102`

### 5) `PidTracker` 数据结构与算法

`PidTracker` 使用 `kqueue + EVFILT_PROC` 监听 fork/exit，配合 `proc_listchildpids` 补齐递归子进程发现：

- 关键集合：
  - `seen: HashSet<i32>` 所有观测过的 pid
  - `active: HashSet<i32>` 当前活跃监视 pid
- 结束机制：`EVFILT_USER` 的 STOP 事件触发 `stop_requested`
- 稳定性细节：
  - `kqueue()` 或注册 stop 失败时降级返回只含 root pid
  - `watch_pid` 遇 `ESRCH` 视为进程已结束，不报致命错误

代码：
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:7`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:83`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:185`

### 6) Windows 分支执行模型

Windows 不走 `spawn_debug_sandbox_child`，而是：

1. 将 `sandbox_policy` 序列化为 JSON 字符串。
2. 根据 `WindowsSandboxLevel::from_config(&config)` 选择 elevated 或 unelevated capture。
3. 在 `spawn_blocking` 中调用 `run_windows_sandbox_capture[_elevated]`。
4. 把捕获到的 `stdout/stderr` 回写到当前进程，再 `process::exit(capture.exit_code)`。

代码：
- debug_sandbox 分支：`/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:142`
- level 解析：`/home/sansha/Github/codex/codex-rs/core/src/windows_sandbox.rs:30`
- capture API 导出：`/home/sansha/Github/codex/codex-rs/windows-sandbox-rs/src/lib.rs:73`、`/home/sansha/Github/codex/codex-rs/windows-sandbox-rs/src/lib.rs:145`

### 7) 环境变量与网络语义

- 统一网络受限标记：`CODEX_SANDBOX_NETWORK_DISABLED=1`
  - 在 `spawn_debug_sandbox_child` 中按 `NetworkSandboxPolicy::is_enabled()` 控制。
  - 常量来源：`/home/sansha/Github/codex/codex-rs/core/src/spawn.rs:19`
- macOS 额外注入：`CODEX_SANDBOX=seatbelt`。
- managed proxy：若 `config.permissions.network` 存在，先 `start_proxy()`，再把代理环境注入子进程。

代码：
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:363`
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:267`
- `/home/sansha/Github/codex/codex-rs/core/src/config/network_proxy_spec.rs:118`
- `/home/sansha/Github/codex/codex-rs/core/src/config/mod.rs:2909`

## 关键代码路径与文件引用

### A. 目标目录与直属模块

1. `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs`
- 统一调度与平台分支的主实现。
- 包含配置加载、进程启动、退出码处理、profile/full-auto 约束和单元测试。

2. `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/seatbelt.rs`
- macOS denial 日志采集与解析。

3. `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs`
- 递归 pid 追踪（仅 macOS 编译）。

### B. 调用方（callers）

1. `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:788`
- `Subcommand::Sandbox` 路由总入口。

2. `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:795`
- 调用 `run_command_under_seatbelt`。

3. `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:807`
- 调用 `run_command_under_landlock`。

4. `/home/sansha/Github/codex/codex-rs/cli/src/main.rs:819`
- 调用 `run_command_under_windows`。

5. `/home/sansha/Github/codex/codex-rs/cli/src/lib.rs:1`
- 对外暴露 `pub mod debug_sandbox`。

### C. 被调用方（callees）

1. 配置与环境
- `/home/sansha/Github/codex/codex-rs/utils/cli/src/config_override.rs:42`
- `/home/sansha/Github/codex/codex-rs/core/src/exec_env.rs:20`

2. 沙箱参数构造
- `/home/sansha/Github/codex/codex-rs/core/src/seatbelt.rs:428`
- `/home/sansha/Github/codex/codex-rs/core/src/landlock.rs:78`

3. 网络代理
- `/home/sansha/Github/codex/codex-rs/core/src/config/network_proxy_spec.rs:118`

4. Windows sandbox backend
- `/home/sansha/Github/codex/codex-rs/core/src/windows_sandbox.rs:30`
- `/home/sansha/Github/codex/codex-rs/windows-sandbox-rs/src/lib.rs:261`

5. Linux helper 二次执行协议
- `/home/sansha/Github/codex/codex-rs/linux-sandbox/src/linux_run_main.rs:27`
- `/home/sansha/Github/codex/codex-rs/linux-sandbox/src/linux_run_main.rs:99`

### D. 配置、测试、脚本、文档上下文

1. 配置相关
- `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs:57`（`SandboxMode`）
- `/home/sansha/Github/codex/codex-rs/protocol/src/permissions.rs:25`（`NetworkSandboxPolicy`）

2. 目标对象内测试
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:482`（profile 优先）
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox.rs:533`（full-auto 拒绝）
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:319`（子进程收集）
- `/home/sansha/Github/codex/codex-rs/cli/src/debug_sandbox/pid_tracker.rs:347`（bash 子孙进程）

3. 脚本/外部验证
- `/home/sansha/Github/codex/codex-rs/windows-sandbox-rs/sandbox_smoketests.py:12`（自动调用 `codex sandbox windows`）

4. 文档
- `/home/sansha/Github/codex/codex-rs/README.md:56`（sandbox 命令说明）
- `/home/sansha/Github/codex/codex-rs/core/README.md:49`（Linux helper/legacy alias 背景）
- `/home/sansha/Github/codex/codex-rs/linux-sandbox/README.md:16`（helper 行为约束）

## 依赖与外部交互

### 1) 内部 crate 依赖

- `codex-core`：配置聚合、shell env 计算、seatbelt/landlock 参数生成、windows sandbox level 判断、network proxy。
- `codex-protocol`：`SandboxMode`、`NetworkSandboxPolicy` 等协议类型。
- `codex-utils-cli`：`-c key=value` 解析。
- `codex-arg0`：提供 `codex_linux_sandbox_exe` 路径，让 Linux 分支可定位 helper 可执行文件。

参考：
- `/home/sansha/Github/codex/codex-rs/arg0/src/lib.rs:21`
- `/home/sansha/Github/codex/codex-rs/arg0/src/lib.rs:145`

### 2) 系统命令与 OS 能力

- macOS
  - `/usr/bin/sandbox-exec`
  - `log stream --style ndjson --predicate ...`
  - `kqueue` / `kevent` / `proc_listchildpids`

- Linux
  - `codex-linux-sandbox` helper（其内部再走 bubblewrap/landlock/seccomp）

- Windows
  - `codex-windows-sandbox` restricted token/elevated backend（通过 Rust crate API 调用）

### 3) 环境与进程模型交互

- 子进程统一 `env_clear()`，只注入策略允许环境变量。
- 网络禁用时注入 `CODEX_SANDBOX_NETWORK_DISABLED=1`。
- 子进程 `kill_on_drop(true)`，防止父进程提前退出后僵留。
- Windows 分支通过 capture 实现“仿继承 I/O”，但最终由当前进程显式 `process::exit`。

## 风险、边界与改进建议

### 1) 风险：profile 检测策略过于“键存在”

现状：`config_uses_permission_profiles` 只检查 `effective_config().get("default_permissions")` 是否存在。若未来配置演进（字段别名/迁移）可能误判。

建议：
- 优先通过 `Config` 的结构化字段或专用 helper 判断，而不是裸 key 检测。
- 增加覆盖“字段存在但无效值/空值/被 profile 覆盖”的测试。

### 2) 风险：macOS denial 解析对日志格式强依赖

现状：`parse_message` 使用固定 regex 匹配 `Sandbox: name(pid) deny(...) capability`。

边界：
- macOS 日志格式变动或 locale 变化可能导致解析失败。
- 当前无针对 `seatbelt.rs` 的独立单测。

建议：
- 为 `parse_message` 增加表驱动单元测试（合法、噪音、格式漂移样例）。
- `finish()` 输出中附带“解析失败行计数”，提高可观测性。

### 3) 风险：Windows 分支直接 `process::exit` 导致可组合性弱

现状：Windows 路径在模块内部结束整个进程，这让上层难做统一收尾（例如 metrics flush、defer 清理）。

建议：
- 返回一个结构化 `CaptureResult` 到调用方，由上层统一决定退出时机。
- 或明确文档声明该路径的“终止语义”是预期契约。

### 4) 风险：目录内测试覆盖偏配置逻辑，缺少端到端契约

现状：`debug_sandbox.rs` 只测配置分支；`pid_tracker` 仅 macOS 条件测试；缺少跨平台“命令执行+退出码+环境注入”契约测试。

建议：
- 增加最小 e2e smoke tests（平台条件编译）：
  - `read-only` 下写入失败
  - `full-auto` 下 cwd 写入成功
  - `CODEX_SANDBOX_NETWORK_DISABLED` 标记符合策略

### 5) 文档边界与一致性问题

观察到文档与实现存在轻微漂移风险：
- README 仍写有 `codex debug seatbelt/landlock` legacy alias（`/home/sansha/Github/codex/codex-rs/README.md:70`），但当前 `cli/src/main.rs` 的 `debug` 子命令并不包含 seatbelt/landlock 路径，实际入口为 `codex sandbox ...` + `sandbox` 子命令的 visible alias（`seatbelt`/`landlock`）。

建议：
- 对齐 README 与当前 clap 路由定义，避免用户按旧文档误用命令。

### 6) 明确的功能边界

- `debug_sandbox` 不是常规 agent shell tool 执行主路径，不负责 approval 流程与复杂 tool orchestration。
- Linux helper 行为（bubblewrap/landlock 细节）主要由 `codex-rs/linux-sandbox` 负责，本模块只负责参数协议与进程拉起。
- Windows private desktop、elevated/unelevated 等策略解释，核心在 `codex-core` + `codex-windows-sandbox`，本模块只做选择与桥接。
