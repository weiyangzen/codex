# DIR `.codex/skills/babysit-pr/agents` 研究报告

- 研究对象：`/home/sansha/Github/codex/.codex/skills/babysit-pr/agents`
- 研究日期：2026-03-19
- 目录内容：`openai.yaml`（单文件目录）

## 场景与职责

`.codex/skills/babysit-pr/agents` 是 `babysit-pr` 技能的“机器可读元数据入口”，核心职责不是承载完整技能逻辑，而是为宿主系统提供 UI/交互侧接口信息（显示名、简述、默认提示词），并把该技能与“持续值守 PR”的行为意图绑定。

该目录在整体链路中的定位：

1. 上游（作者侧）
- 技能作者手工维护 `agents/openai.yaml`，或通过 skill-creator 脚本生成（`codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py:3`）。

2. 中游（加载侧）
- Core skills loader 在解析 `SKILL.md` 后，会额外尝试读取 `<skill_dir>/agents/openai.yaml`，并解析 `interface` 字段（`codex-rs/core/src/skills/loader.rs:602-655`、`693-722`）。

3. 下游（消费侧）
- 解析后的 `SkillInterface` 被传到协议层与 UI 层，用于技能列表展示和客户端返回（`codex-rs/core/src/codex.rs:5332-5373`、`codex-rs/app-server/src/codex_message_processor.rs:7542-7607`、`codex-rs/tui/src/skills_helpers.rs:8-23`）。

4. 与技能指令正文的边界
- 真正注入模型上下文的仍是 `SKILL.md` 内容，不是 `openai.yaml`（`codex-rs/core/src/skills/injection.rs:40-54`）。

## 功能点目的

本目录当前仅包含 `openai.yaml`，但承担 4 个关键功能点：

1. 技能品牌化与可发现性
- `interface.display_name`、`short_description` 提升技能在 UI 的辨识度（`openai.yaml:2-3`；消费逻辑见 `skills_helpers.rs:8-23`）。

2. 行为意图预设
- `interface.default_prompt` 预置该技能应如何被触发，且明确 babysit 场景中的关键约束（单 watcher、push 后立刻恢复 watch、非终态不得结束）（`openai.yaml:4`）。

3. 与 `SKILL.md` 行为约束保持一致
- `SKILL.md` 要求“默认 `--watch`、持续监控到严格 stop condition”（`.codex/skills/babysit-pr/SKILL.md:26-40,149-164`），`default_prompt` 用更短入口语句把这些约束前置给调用方。

4. 作为技能元数据扩展载体
- `agents/` 目录被定义为产品侧扩展配置位置，`openai.yaml` 是其中默认约定文件（`codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md:3`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 元数据文件结构

当前文件内容（`openai.yaml:1-4`）：

- `interface.display_name`
- `interface.short_description`
- `interface.default_prompt`

`babysit-pr` 没有声明 icon/brand_color/dependencies/policy（这些字段在 schema 能力上是可选的，见 `loader.rs:57-67,98-120`）。

### 2) Loader 解析流程

1. 先扫描并解析 `SKILL.md` frontmatter，构建基础 `SkillMetadata`（`loader.rs:527-585`）。
2. 再调用 `load_skill_metadata()` 尝试读取 `agents/openai.yaml`（`loader.rs:602-612`）。
3. 成功解析后通过 `resolve_interface()` 归一化 `SkillInterface`（`loader.rs:693-722`）：
- 字符串字段走 `resolve_str()`，会 trim+压缩空白+长度上限校验（`loader.rs:852-864`）。
- `default_prompt` 长度上限是 `MAX_DEFAULT_PROMPT_LEN=1024`（`loader.rs:141,709-713`）。
- 若 `interface` 全字段都无效/为空，则整体丢弃为 `None`（`loader.rs:715-722`）。

### 3) 失败策略与容错

- `openai.yaml` 读取失败或 YAML 解析失败时，采用 fail-open：忽略 metadata，不阻断技能装载（`loader.rs:603,614-637`）。
- 该策略保证 `SKILL.md` 主体仍可运行，但会导致 UI/默认提示词退化。

### 4) 协议与下游传递

- Core 协议结构携带 `SkillInterface.default_prompt: Option<String>`（`codex-rs/protocol/src/protocol.rs:2955-2969`）。
- App-server v2 同步暴露相同字段（`codex-rs/app-server-protocol/src/protocol/v2.rs:3166-3182`，转换见 `3391-3424`）。
- TUI/APP_SERVER TUI 通过 `display_name/short_description` 做展示回退逻辑（`codex-rs/tui/src/skills_helpers.rs:8-23`，`codex-rs/tui_app_server/src/skills_helpers.rs:8-23`）。

### 5) 与 babysit 运行时实现的对接

`openai.yaml` 本身不执行命令；真正执行链由 `SKILL.md` 引导到 watcher 脚本：

- 一次快照：`python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --once`
- 持续监控：`python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch`
- 失败重试：`python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --retry-failed-now`

核心动作协议来自 watcher 输出的 `actions` 数组（`gh_pr_watch.py:572-599`），并在 `--watch` 中通过 `snapshot/stop` JSONL 事件持续输出（`gh_pr_watch.py:747-767`）。

## 关键代码路径与文件引用

### 目标目录

- `.codex/skills/babysit-pr/agents/openai.yaml:1-4`

### 直接上下文（同技能目录）

- `.codex/skills/babysit-pr/SKILL.md:24-40,119-180`
- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py:55-94,601-649,747-805`
- `.codex/skills/babysit-pr/references/heuristics.md:1-41`
- `.codex/skills/babysit-pr/references/github-api-notes.md:1-63`

### 调用方（加载与分发）

- `codex-rs/core/src/skills/loader.rs:133-137,602-655,693-722,852-864`
- `codex-rs/core/src/skills/model.rs:24-63`
- `codex-rs/core/src/skills/manager.rs:82-93,319-328`
- `codex-rs/core/src/codex.rs:5332-5373`
- `codex-rs/app-server/src/codex_message_processor.rs:7542-7607`
- `codex-rs/app-server-protocol/src/protocol/v2.rs:3145-3182,3391-3424`

### 被调用方/验证与约束

- `codex-rs/core/src/skills/loader_tests.rs:403-457,949-988,991-1043,1046-1085`
- `codex-rs/skills/src/assets/samples/skill-creator/references/openai_yaml.md:1-49`
- `codex-rs/skills/src/assets/samples/skill-creator/scripts/generate_openai_yaml.py:1-226`

## 依赖与外部交互

1. 文件系统依赖
- 固定路径约定：`<skill_dir>/agents/openai.yaml`（`loader.rs:607-609`）。
- 解析器使用 `serde_yaml` 读取 YAML。

2. 协议依赖
- Core protocol + app-server v2 都定义了 `SkillInterface`，字段需保持一致映射（`protocol.rs:2955-2969`，`v2.rs:3166-3182`）。

3. UI 依赖
- Skills 列表展示优先使用 `interface.display_name` 与 `interface.short_description`，否则回退到技能原名和 description（`skills_helpers.rs:8-23`）。

4. 运行时外部交互（由同技能脚本承担）
- 通过 `gh` 命令访问 GitHub PR、checks、actions runs、comments/reviews API（`gh_pr_watch.py:108-133,157-193,265-316,349-475`）。
- 状态落盘到 `/tmp/codex-babysit-pr-*.json`（`gh_pr_watch.py:260-263`）。

## 风险、边界与改进建议

1. 风险：`openai.yaml` 与 `SKILL.md` 语义漂移
- 当前 `default_prompt` 很长，且承载了关键行为约束；若未来 `SKILL.md` 更新而 YAML 未同步，会出现“入口提示词与实际技能规则不一致”。
- 建议：增加一致性检查（CI lint），至少校验 `default_prompt` 与 `SKILL.md` 中关键约束关键词（如 `--watch`、single watcher、strict stop condition）。

2. 风险：fail-open 可能掩盖元数据错误
- 解析失败不会阻断技能加载（`loader.rs:603-637`），易出现“技能可用但 UI 退化且不易被发现”。
- 建议：在技能开发流程里加入 `openai.yaml` 校验脚本，并在 PR 模板中要求截图或字段检查。

3. 边界：`default_prompt` 目前主要是透传元数据
- 代码中已完整透传该字段到协议层，但仓内未看到明确“自动把 `default_prompt` 写入输入框”的消费实现；这意味着它在不同客户端的实际效果可能不一致。
- 建议：明确产品契约（哪些端自动注入 default_prompt，哪些仅展示）。

4. 边界：目录级最小实现可运行，但信息密度有限
- 当前只有 3 个 interface 字段，未提供图标与品牌色，技能在列表视觉识别度一般。
- 建议：补充 `icon_small/icon_large/brand_color`，并遵守 assets 相对路径规则（`loader.rs:783-829`）。

5. 与 babysit 主流程相关的外部风险（上下文）
- watcher 对 review 作者有信任过滤（`gh_pr_watch.py:458-503`），可能遗漏外部贡献者的重要评论。
- 建议：在 `openai.yaml.default_prompt` 或 `SKILL.md` 增加提示：必要时手工复核 GitHub 全量评论线程。
