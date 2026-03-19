# DIR `.codex/skills/test-tui` 研究报告

- 研究对象：`/home/sansha/Github/codex/.codex/skills/test-tui`
- 研究日期：2026-03-19
- 研究类型：目录级（DIR）深度研究

## 场景与职责

`.codex/skills/test-tui` 是一个“轻量但高约束”的仓库内技能目录，核心作用不是提供脚本，而是为代理执行 TUI 验证时提供**操作规程**。该目录当前仅包含 `SKILL.md`，通过前置 YAML frontmatter 暴露给技能系统（`.codex/skills/test-tui/SKILL.md:1-14`）。

它在整体系统中的职责是：

1. 约束 TUI 交互验证流程
- 明确要求“交互方式启动”（而非仅跑单条命令后退出）。
- 要求显式开启高粒度日志和独立日志目录，便于复盘。

2. 规避 TUI 输入时序误判
- 要求程序化输入时把“文本输入”与“Enter”分开发送，避免被粘贴突发（paste burst）逻辑误判。

3. 通过统一入口降低环境偏差
- 要求通过 `just codex` 启动，统一在 `codex-rs` 工作目录下运行目标二进制（`justfile:1-11`）。

从调用链看，`test-tui` 并不直接执行代码；它被 Codex 的 skills 子系统扫描、列出、匹配并在命中时注入到本轮上下文（`codex-rs/core/src/skills/loader.rs:218-242`, `codex-rs/core/src/skills/render.rs:5-25`, `codex-rs/core/src/codex.rs:3491-3492`, `codex-rs/core/src/skills/injection.rs:24-52`）。

## 功能点目的

结合 `SKILL.md` 文本与下游实现，可拆为 4 个明确功能点：

1. `RUST_LOG="trace"`（`.codex/skills/test-tui/SKILL.md:11`）
- 目的：把 TUI 行为调试提升到可观测级别，覆盖 key-event、渲染、状态机分支的排查场景。
- 依据：TUI 默认日志级别是 `info`，trace 属于显式放大（`docs/install.md:56`, `codex-rs/tui_app_server/src/lib.rs:806-810`）。

2. `-c log_dir=<temp>`（`.codex/skills/test-tui/SKILL.md:12`）
- 目的：将日志输出隔离到一次性目录，避免历史会话噪音干扰；便于对单次实验做截面分析。
- 依据：TUI 默认写 `~/.codex/log/codex-tui.log`，文档建议可用 `-c log_dir=...` 做单次隔离（`docs/install.md:56`, `docs/tui-stream-chunking-validation.md:35-37`）。

3. “文本与 Enter 分开发送”（`.codex/skills/test-tui/SKILL.md:13`）
- 目的：避免程序化输入被 paste burst 逻辑当成粘贴，导致 Enter 被解释为换行而非提交。
- 依据：TUI 在 burst 场景会把 Enter 吸收到缓冲或转换为 newline（`codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs:2473-2484`, `3015`, `docs/tui-chat-composer.md:219-305`），并有测试固定该行为（`.../chat_composer.rs:5960`）。

4. 使用 `just codex -c ...`（`.codex/skills/test-tui/SKILL.md:14`）
- 目的：统一运行入口，避免直接 `cargo run` 时参数与工作目录不一致。
- 依据：根 `justfile` 把工作目录固定为 `codex-rs`，`codex` 目标映射到 `cargo run --bin codex -- "$@"`（`justfile:1`, `10-11`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 技能发现与加载

1. 根路径来源
- `skill_roots(...)` 会组合 repo/user/system/admin roots，并包含仓库 `.codex/skills` 目录（`codex-rs/core/src/skills/loader.rs:218-242`, `309`）。

2. 扫描与解析
- `discover_skills_under_root(...)` BFS 扫描 `SKILL.md`（深度/目录数受限：`MAX_SCAN_DEPTH=6`、`MAX_SKILLS_DIRS_PER_ROOT=2000`，`loader.rs:149-150`, `388-407`）。
- `parse_skill_file(...)` 读取 frontmatter 的 `name/description`，并构建 `SkillMetadata`（`loader.rs:527-583`）。
- `test-tui/SKILL.md` frontmatter 合法，能稳定被加载。

3. 可选元数据
- 系统会尝试读取同目录 `agents/openai.yaml` 增强界面/依赖/权限信息（`loader.rs:602-699`）。
- `test-tui` 当前无 `agents/openai.yaml`，因此仅使用 `SKILL.md` 基础元数据。

### 2) 技能注入与触发

1. 会话层展示
- `render_skills_section(...)` 把“可用技能 + 触发规则”拼到 `<skills_instructions>` 区块（`codex-rs/core/src/skills/render.rs:5-25`）。

2. 触发与选择
- 用户输入中的 `UserInput::Skill` 或文本 `$skill` mention 经 `collect_explicit_skill_mentions(...)` 解析（`codex-rs/core/src/skills/injection.rs:100-154`）。
- 路径链接 mention（如 `[/tmp/.../SKILL.md]`）优先，普通名称需“无歧义”才选中（`injection.rs:319-374`）。

3. 内容注入
- `build_skill_injections(...)` 直接读取命中的 `SKILL.md` 内容并封装为 `<skill><name>...<path>...` 消息（`injection.rs:24-52`, `codex-rs/core/src/instructions/user_instructions.rs:38-52`）。

### 3) 与 TUI 输入行为的耦合点（本技能的核心）

`test-tui` 第 13 行要求“分开发送 Enter”，其技术根因是 TUI composer 的 burst 机制：

1. 输入主路径
- `handle_key_event_without_popup(...)` 中 Enter 会走 `handle_submission(...)`（`chat_composer.rs:2741-2812`）。

2. 但在 burst 状态下
- `handle_submission_with_time(...)` 会先判定 `paste_burst.is_active()`，若命中则 `append_newline_if_active(now)`，不提交（`chat_composer.rs:2442-2484`）。
- `handle_input_basic_with_time(...)` 也会在 Enter 时追加换行到 burst（`chat_composer.rs:2998-3016`）。

3. 行为被测试锁定
- `ascii_burst_treats_enter_as_newline` 明确断言 Enter 在 burst 内应插入换行而不是提交（`chat_composer.rs:5960-6010`）。

因此，skill 的“文本与 Enter 分开发送”是对实现细节的直接规避策略，不是经验性建议。

### 4) 建议命令路径

按 skill + 文档语义可归纳为：

```bash
RUST_LOG=trace just codex -c log_dir=/tmp/codex-tui-<ts>
```

程序化输入建议：
1. 先写入纯文本（不带 `\n`）。
2. 再单独发送 Enter。

## 关键代码路径与文件引用

目标目录与直接内容：
- `.codex/skills/test-tui/SKILL.md:1-14`

调用方（加载/列举/注入）：
- `codex-rs/core/src/skills/loader.rs:218-242`（skills roots 组装）
- `codex-rs/core/src/skills/loader.rs:388-527`（扫描与 `SKILL.md` 发现）
- `codex-rs/core/src/skills/loader.rs:527-583`（frontmatter 解析 -> `SkillMetadata`）
- `codex-rs/core/src/skills/manager.rs:65-75`（按配置缓存加载）
- `codex-rs/core/src/skills/render.rs:5-25`（技能列表与触发规则注入）
- `codex-rs/core/src/codex.rs:3491-3492`（开发者消息拼装 skills section）
- `codex-rs/core/src/codex.rs:5474-5508`（显式 mention 收集与技能注入）
- `codex-rs/core/src/skills/injection.rs:24-52`（读取 `SKILL.md` 注入）
- `codex-rs/core/src/instructions/user_instructions.rs:38-52`（`<skill>` 消息格式）

被调用方（TUI运行与输入语义）：
- `justfile:1-11`（`just codex` -> `cargo run --bin codex`）
- `codex-rs/cli/src/main.rs:599-612`（无子命令默认进交互 TUI）
- `codex-rs/cli/src/main.rs:1043-1093`（interactive TUI 入口）
- `codex-rs/tui_app_server/src/lib.rs:785-810`（log_dir 与 `RUST_LOG` 默认）
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs:2442-2484`（burst 时 Enter 逻辑）
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs:2998-3016`（输入基础路径的 Enter 处理）
- `codex-rs/tui_app_server/src/bottom_pane/chat_composer.rs:5960-6010`（测试：Enter 在 burst 中换行）

协议与客户端链路（skills/list）：
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3092`（`SkillsListParams/Response`）
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3224-3228`（`SkillsListEntry`）
- `codex-rs/app-server-protocol/src/protocol/v2.rs:4654-4656`（`skills/changed` 语义）
- `codex-rs/app-server/src/codex_message_processor.rs:5385-5454`（`skills/list` 实现）
- `codex-rs/tui_app_server/src/app.rs:1988-1994`（TUI 发起 `skills_list`）
- `codex-rs/tui_app_server/src/chatwidget/skills.rs:147-155`（按 cwd 取技能并供 mention）

配置、测试、文档、脚本：
- `codex-rs/core/src/config/types.rs:799-825`（`SkillsConfig` / enable 开关）
- `codex-rs/core/src/skills/loader_tests.rs:1517-1530`（frontmatter 缺失报错）
- `codex-rs/core/src/skills/manager_tests.rs:39-70`（按配置缓存）
- `codex-rs/core/src/skills/injection_tests.rs:115-173`（技能 mention 解析）
- `codex-rs/app-server/tests/suite/v2/skills_list.rs:30-223`（extra roots / cache / skills changed 测试）
- `docs/install.md:54-64`（TUI 日志与 `-c log_dir`）
- `docs/tui-chat-composer.md:219-305`（Enter suppression 与 burst）
- `docs/tui-stream-chunking-validation.md:29-37`（`RUST_LOG` 与日志隔离实践）

## 依赖与外部交互

1. 构建与运行依赖
- `just` 命令（运行 `just codex`）。
- Rust/Cargo 工具链（`just` 最终执行 `cargo run --bin codex`）。

2. 配置与文件系统依赖
- `-c log_dir=...` 依赖 CLI override 解析与目录可写权限。
- 默认日志路径回退到 `CODEX_HOME/log`（`codex-rs/core/src/config/mod.rs:2572-2578`）。

3. 终端/输入系统依赖
- 依赖 crossterm key event 行为，尤其在 Windows/部分终端下的“非 bracketed paste”表现。
- 技能第 13 行本质是对终端输入事件抖动的操作层兜底。

4. 协议与进程边界
- skills 可通过 app-server `skills/list` 查询；TUI 会按 cwd 消费结果并更新 mention 源。
- 该技能本身无网络 I/O，无独立脚本执行面。

## 风险、边界与改进建议

1. 风险：`RUST_LOG=trace` 日志体积和噪音较大
- 影响：长会话日志迅速膨胀，分析成本上升。
- 建议：把 skill 文本升级为“优先模块级 trace”，如 `codex_tui=trace,codex_core=info`，并提供最小可复现模板。

2. 风险：仅靠“分开发送 Enter”属于操作约束，不是机制防护
- 影响：自动化执行方若忽略该细节，可能出现“看似输入成功但未提交”。
- 建议：在 skill 中给出一段标准化伪代码/命令序列（text write -> short delay -> enter write），降低实现歧义。

3. 边界：目录内无 `scripts/` 与 `references/`
- 影响：缺少可复用自动化脚本，执行一致性依赖操作者经验。
- 建议：新增最小 `scripts/`（例如 PTY 驱动样例），并在 `SKILL.md` 引用它。

4. 边界：缺失 `agents/openai.yaml` 的 interface 元数据
- 影响：技能展示信息较基础，无法定义更细的 UI/依赖提示。
- 建议：为 `test-tui` 补充 `agents/openai.yaml`（`display_name`、`short_description`、`default_prompt`）。

5. 风险：`just codex -c ...` 没有明确临时目录生命周期
- 影响：频繁调试会遗留大量日志目录。
- 建议：在技能里补充建议命名规范与清理命令（例如会后 `rm -rf /tmp/codex-tui-*`）。

6. 测试覆盖边界
- 当前仓库对“技能文案语义”没有专门测试；现有测试主要覆盖 skills 解析/缓存与 TUI 输入状态机。
- 建议：新增一个轻量文档一致性测试（lint 级）检查 `test-tui/SKILL.md` 是否仍包含 4 条关键约束（interactive、RUST_LOG、log_dir、separate Enter write）。
