# DIR `.github/codex/home` 研究报告

- 研究对象：`/home/sansha/Github/codex/.github/codex/home`
- 研究日期：2026-03-19
- 对象类型：目录（DIR）

## 场景与职责

`.github/codex/home` 是一个极小但语义明确的“Codex 运行主目录模板”，当前目录下只有一个配置文件：`.github/codex/home/config.toml`。

它的核心职责不是实现逻辑，而是作为 **`CODEX_HOME` 目录内容** 提供默认配置载荷，主要用于 GitHub Action 场景下的 Codex CLI 运行参数注入。

从仓库历史可见，该目录曾被旧版 `Codex` workflow 显式传入 action 输入 `codex_home`：

- `git show aa5fc5855^:.github/workflows/codex.yml` 第 59-64 行：`codex_home: ./.github/codex/home`
- `git show aa5fc5855^:.github/actions/codex/action.yml` 第 19-21 行：`codex_home` 输入定义为“写入 `CODEX_HOME` 环境变量”
- `git show aa5fc5855^:.github/actions/codex/src/run-codex.ts` 第 33-36 行：若有 `INPUT_CODEX_HOME`，则设置 `env.CODEX_HOME`

当前主分支已删除该旧 workflow（commit `aa5fc5855`），因此该目录在“现行仓库内调用链”里处于潜在闲置状态。

## 功能点目的

### 1) 设定自动化运行默认模型

`config.toml` 当前只设置了一项：

- `model = "gpt-5.1"`（`.github/codex/home/config.toml:1`）

目的：当该目录被挂载为 `CODEX_HOME` 时，让 Codex CLI 无需额外 `--model` 参数即可采用统一默认模型。

### 2) 预留 MCP 扩展入口

- 注释 `# Consider setting [mcp_servers] here!`（`.github/codex/home/config.toml:3`）

目的：提示可在同文件中继续声明 MCP server（与 `ConfigToml.mcp_servers` 语义对齐）。

### 3) 充当“仓库内可版本化运行配置”

把 action 运行配置放在仓库路径（而非 workflow 内硬编码大段 `--config`）有两个收益：

- 可被 PR 审查与历史追踪
- 可与 `.github/codex/labels/*.md` 一起形成同源的自动化资产包

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 当前目录的实现形态

当前目录没有脚本和测试，只有静态 TOML：

- `.github/codex/home/config.toml`

其配置内容：

```toml
model = "gpt-5.1"

# Consider setting [mcp_servers] here!
```

### B. 配置被消费时的底层解析路径（Codex Core）

若运行时设置了 `CODEX_HOME=<某目录>`，Codex Core 会按以下路径加载：

1. `find_codex_home()` 解析 `CODEX_HOME`（`codex-rs/core/src/config/mod.rs:2965-2966`）
2. `ConfigBuilder::build()` 调用 `load_config_layers_state(...)` 合并配置层（`codex-rs/core/src/config/mod.rs:632-690`）
3. 合并结果反序列化为 `ConfigToml`（`codex-rs/core/src/config/mod.rs:1196` 起）
4. 模型最终值按优先级计算：
   - `harness override` -> `profile.model` -> `cfg.model`
   - 见 `let model = model.or(config_profile.model).or(cfg.model);`（`codex-rs/core/src/config/mod.rs:2490`）

对应数据结构关键字段：

- `ConfigToml.model: Option<String>`（`codex-rs/core/src/config/mod.rs:1198`）
- `ConfigToml.mcp_servers: HashMap<String, McpServerConfig>`（`codex-rs/core/src/config/mod.rs:1286-1290`）

### C. 历史上的 action 消费链（已从主线移除，但定义了目录语义）

旧链路（commit `aa5fc5855^`）如下：

1. workflow 传入 `codex_home: ./.github/codex/home`（`.github/workflows/codex.yml` 第 64 行，历史版本）
2. 复用 action 将输入映射到 `INPUT_CODEX_HOME`（`.github/actions/codex/action.yml` 第 115-117 行，历史版本）
3. `run-codex.ts` 将其转为 `env.CODEX_HOME`（`.github/actions/codex/src/run-codex.ts` 第 33-36 行，历史版本）
4. 执行命令：`/usr/local/bin/codex exec ... --output-last-message <file> <prompt>`（`.github/actions/codex/src/run-codex.ts` 第 23-31 行，历史版本）

这条链路定义了 `.github/codex/home` 的原始职责，即：**给 GitHub Action 中的 Codex CLI 提供可版本化的 HOME 配置目录。**

### D. 配置演进历史

`config.toml` 的模型值经历过三次演进：

1. 初始导入：`o3`（commit `baa92f37e`）
2. `o3 -> gpt-5`（commit `52bd7f666`）
3. `gpt-5 -> gpt-5.1`（commit `ddcc60a08`）

说明该文件在历史上被当作“自动化默认模型开关位”，而不是文档占位文件。

## 关键代码路径与文件引用

### 目录本体

- `.github/codex/home/config.toml:1-3`

### 当前主线中的相关调用方（间接）

- `.github/workflows/issue-labeler.yml:22-27`（使用 `openai/codex-action@main`，但未传 `codex_home`）
- `.github/workflows/issue-deduplicator.yml:62-68`
- `.github/workflows/issue-deduplicator.yml:196-202`

现状结论：当前 workflow 使用“内联 prompt + schema”，没有仓内显式引用 `.github/codex/home`。

### 历史调用方与被调用方（定义该目录语义）

- `git show aa5fc5855^:.github/workflows/codex.yml`（第 59-64 行）
- `git show aa5fc5855^:.github/actions/codex/action.yml`（第 19-21、115-117 行）
- `git show aa5fc5855^:.github/actions/codex/src/run-codex.ts`（第 23-36 行）
- `git show aa5fc5855^:.github/actions/codex/src/load-config.ts`（第 18-20 行，扫描 `.github/codex/labels`）
- `git show aa5fc5855^:.github/actions/codex/src/prompt-template.ts`（第 54-67、217-247 行，占位符协议）

### 底层配置语义（Rust Core）

- `codex-rs/core/src/config/mod.rs:1196-1200`（`ConfigToml` 与 `model` 字段）
- `codex-rs/core/src/config/mod.rs:1286-1290`（`mcp_servers`）
- `codex-rs/core/src/config/mod.rs:632-690`（构建并加载配置层）
- `codex-rs/core/src/config/mod.rs:2490`（模型优先级合并）
- `codex-rs/core/src/config/mod.rs:2965-2966`（`find_codex_home`）

## 依赖与外部交互

### 外部依赖

1. GitHub Actions Runtime
- 环境变量、事件 JSON、权限模型。

2. `openai/codex-action`
- 当前 workflow 直接依赖该外部 action；是否读取 `.github/codex/home` 取决于 action 输入与实现。

3. Codex CLI 二进制
- 历史链路中通过 `codex exec` 执行并读写 `CODEX_HOME/config.toml`。

4. GitHub API / gh / jq（工作流层）
- issue 去重流程依赖 `gh issue list/view` + `jq` 预处理输入（`.github/workflows/issue-deduplicator.yml:35-55,171-191`）。

### 输入/输出边界

- 输入：`config.toml` 顶层键值（当前为 `model`）
- 输出：运行时生效模型（通过 core 配置加载链参与最终 `Config.model`）

### 测试与脚本现状

- 当前仓库无针对 `.github/codex/home` 的专门测试。
- 当前目录无执行脚本；与之关联的历史脚本（`.github/actions/codex/*`）已从主分支删除。

## 风险、边界与改进建议

### 风险

1. 配置漂移风险
- 目录仍在，但当前主线 workflow 不显式消费它；后续维护者容易误判“已生效”。

2. 模型版本陈旧风险
- 若未来某条自动化链重新挂载该目录，`model = "gpt-5.1"` 会立即影响行为；缺少在位校验可能导致隐性变更。

3. 契约不可见风险
- `.github/codex/home` 与 action 的耦合主要体现在历史实现和约定，当前仓内缺少明确“谁读取它”的活文档。

### 边界

1. 本目录不实现任何执行逻辑，仅提供配置。
2. 是否生效完全取决于调用链是否把该目录作为 `CODEX_HOME`。
3. 当前主线 issue 自动化的主要逻辑已转向 workflow 内联 prompt，不依赖本目录。

### 改进建议

1. 明确生效状态（二选一）
- 若继续保留：在 README 或 `.github` 文档中显式写明“何时被读取、由谁读取”。
- 若不再使用：考虑删除目录，避免误导。

2. 增加最小契约检查
- 对引用该目录的 workflow/action 增加 CI 检查：若传了 `codex_home`，则必须存在 `config.toml` 且可解析。

3. 模型版本治理
- 将 `.github/codex/home/config.toml` 的模型升级纳入统一发布 checklist（与 CLI 默认模型升级同步）。

4. 文档化历史切换
- 在 `.github/workflows/issue-labeler.yml` 或仓库维护文档中补一段说明：当前是“内联 prompt 模式”，避免团队成员误以为仍走 `.github/codex/home`。
