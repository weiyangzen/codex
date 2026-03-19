# DIR `codex-rs/apply-patch/tests/fixtures` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`codex-rs/apply-patch/tests/fixtures` 是 `apply_patch` 的“规范样例库（spec fixture set）”，职责是把补丁语义从 Rust 测试代码中抽离成目录化样例，供集成测试批量回放。

它在测试链路里的定位是：

1. 由 `tests/suite/scenarios.rs` 动态遍历每个场景目录并执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 场景以 `input/ + patch.txt + expected/` 三段式描述，强调“最终文件树状态”而非进程输出（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`, `codex-rs/apply-patch/tests/suite/scenarios.rs:42-53`）。
3. 通过文本文件落盘，形成跨语言可迁移的 apply-patch 行为样本（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-7`）。

目录边界：

- `fixtures/` 当前承载 `scenarios/` 子目录；用例数据本身不含 Rust 逻辑。
- 行结束由 `.gitattributes` 统一成 LF，避免跨平台 EOL 差异污染断言（`codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`）。

## 功能点目的

`fixtures/scenarios` 当前覆盖 22 个编号场景（含两个 `020_*` 目录），可按语义分组：

1. 基础成功路径
- `001_add_file`：新增文件。
- `002_multiple_operations`：同一 patch 内 add/delete/update 混合。
- `003_multiple_chunks`：同文件多 chunk 更新。
- `004_move_to_new_directory`：更新并移动到新目录。
- `020_delete_file_success`：成功删除文件。

2. 失败与错误保持
- `005_rejects_empty_patch`：空 patch 不应修改文件。
- `006_rejects_missing_context`：上下文不匹配失败。
- `007_rejects_missing_file_delete`：删除不存在文件失败。
- `008_rejects_empty_update_hunk`：Update 无 chunk。
- `009_requires_existing_file_for_update`：更新不存在文件失败。
- `012_delete_directory_fails`：Delete File 指向目录失败。
- `013_rejects_invalid_hunk_header`：非法 hunk 头失败。

3. 语义边界
- `010_move_overwrites_existing_destination`：`Move to` 覆盖已有目标。
- `011_add_overwrites_existing_file`：`Add File` 覆盖同名文件。
- `014_update_file_appends_trailing_newline`：更新后补尾换行。
- `015_failure_after_partial_success_leaves_changes`：中途失败保留前序已生效改动（非事务）。
- `016_pure_addition_update_chunk`：仅 `+` 行的更新块（插入语义）。
- `021_update_file_deletion_only`：仅删除行。
- `022_update_file_end_of_file_marker`：`*** End of File` EOF 锚点。

4. 容错与字符处理
- `017_whitespace_padded_hunk_header`：hunk 头前置空白。
- `018_whitespace_padded_patch_markers` / `020_whitespace_padded_patch_marker_lines`：Begin/End marker 两端空白。
- `019_unicode_simple`：Unicode 内容更新（含 emoji）。

这些 fixture 的目标不是重复 unit test，而是“以最小文本约束表达可复现行为”，使测试维护者先看样例即可理解工具契约。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放关键流程

1. 入口 `test_apply_patch_scenarios()` 计算 `fixtures/scenarios` 绝对目录并遍历子目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-18`）。
2. 每个场景调用 `run_apply_patch_scenario()`：
- 拷贝 `input/` 到临时目录（`.../scenarios.rs:33-37`）；
- 读取 `patch.txt`（`.../scenarios.rs:39-40`）；
- 以 `apply_patch <patch>` 执行 CLI（`.../scenarios.rs:45-48`）；
- 比较临时目录与 `expected/` 的完整快照（`.../scenarios.rs:50-60`）。
3. 快照结构 `BTreeMap<PathBuf, Entry>`：
- `Entry::File(Vec<u8>)` / `Entry::Dir`（`.../scenarios.rs:65-69`）；
- 用 `fs::metadata()` 跟随 symlink，兼容 Buck2 `__srcs`（`.../scenarios.rs:92-99`, `113-114`）。

### 2) 与被测实现的协议对齐

fixture 的 `patch.txt` 语法直接对应 apply-patch 协议：

- 包裹符：`*** Begin Patch` / `*** End Patch`。
- 文件操作：`*** Add File:` / `*** Delete File:` / `*** Update File:` / 可选 `*** Move to:`。
- 更新块：`@@` + ` ` / `-` / `+` 前缀行 + 可选 `*** End of File`。

该协议在说明文档中定义（`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`），并由 parser 实现（`codex-rs/apply-patch/src/parser.rs:31-39`, `106-183`, `248-434`）。

### 3) 关键数据结构与算法映射

fixtures 虽然是纯数据，但其覆盖点一一映射到核心实现：

1. `parser::Hunk` / `UpdateFileChunk`（`codex-rs/apply-patch/src/parser.rs:58-104`）
- `017/018/020_*` 覆盖 marker trim 容错（`parser.rs:230-235`, `248-251`）。
- `022` 覆盖 `is_end_of_file`（`parser.rs:387-395`）。

2. `lib::apply_hunks_to_files`（`codex-rs/apply-patch/src/lib.rs:279-339`）
- `010/011` 覆盖覆盖写入语义（`write` 直接覆盖）。
- `015` 覆盖顺序执行、失败不回滚。

3. `lib::compute_replacements` + `seek_sequence`（`codex-rs/apply-patch/src/lib.rs:386-474`, `codex-rs/apply-patch/src/seek_sequence.rs:12-110`）
- `006` 覆盖找不到上下文错误。
- `019` 与 whitespace 场景覆盖宽松匹配链路（trim / Unicode normalise）。

### 4) 场景执行命令

目录相关实际命令链路：

1. 运行本目录场景：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`。
2. 场景执行期调用：`apply_patch '<PATCH_TEXT>'`（由 `assert_cmd` 启动，`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. CLI 本身支持 `argv` 或 `stdin` 两种输入（`codex-rs/apply-patch/src/standalone_executable.rs:11-47`，基础覆盖见 `tests/suite/cli.rs:12-91`）。

## 关键代码路径与文件引用

### A. 目标目录与直接说明

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`：fixture 结构规范（`input/patch/expected`）。
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`：强制 `eol=lf`。
3. `codex-rs/apply-patch/tests/fixtures/scenarios/*/patch.txt`：协议输入。
4. `codex-rs/apply-patch/tests/fixtures/scenarios/*/{input,expected}/...`：初始态与期望态。

### B. 调用方（谁消费 fixtures）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-126`：遍历目录并回放。
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`：聚合 `scenarios` 模块。
3. `codex-rs/apply-patch/tests/all.rs:1-3`：integration test 入口。

### C. 被调用方（fixtures 间接驱动的实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`：CLI 参数解析与退出码。
2. `codex-rs/apply-patch/src/lib.rs:183-266`：`apply_patch` 主入口。
3. `codex-rs/apply-patch/src/lib.rs:279-339`：文件系统落盘。
4. `codex-rs/apply-patch/src/lib.rs:386-474`：更新块替换计算。
5. `codex-rs/apply-patch/src/parser.rs:154-434`：patch/hunk/chunk 解析。
6. `codex-rs/apply-patch/src/seek_sequence.rs:12-110`：模糊匹配策略。

### D. 配置、构建、上游集成、脚本、文档

1. 构建与依赖
- `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与 test 依赖）。
- `codex-rs/apply-patch/BUILD.bazel:1-11`（Bazel crate + compile_data）。

2. 上游集成调用
- `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`（调用 `maybe_parse_apply_patch_verified`）。
- `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`（构造 `--codex-run-as-apply-patch` 执行命令）。
- `codex-rs/arg0/src/lib.rs:85-107`（arg0 分发到 `codex_apply_patch`）。

3. 流程脚本（研究任务上下文）
- `Docs/researches/blueprint_checklist.md:72`（当前目录 checklist 条目）。
- `.ops/generate_daily_research_todo.sh:1-42`（每日 todo 由 checklist 派生）。

## 依赖与外部交互

### 1) 依赖

对 fixtures 回放直接有影响的依赖：

1. `assert_cmd`：启动 `apply_patch` 进程（`codex-rs/apply-patch/Cargo.toml:26`）。
2. `tempfile`：隔离场景执行目录（`Cargo.toml:30`, `scenarios.rs:8,31`）。
3. `codex-utils-cargo-bin`：在 Cargo/Bazel 环境稳定定位二进制（`Cargo.toml:28`, `scenarios.rs:1,45`）。
4. `pretty_assertions`：快照差异输出更可读（`Cargo.toml:29`, `scenarios.rs:2,55-60`）。

### 2) 外部交互面

1. 文件系统交互
- 递归复制 `input/` 到 tempdir。
- 扫描 `expected/` 与实际目录并比较原始字节。

2. 进程交互
- 每个场景都会启动一次 `apply_patch` 子进程。

3. 平台行为
- fixture 文本统一 LF，降低跨平台换行噪声。
- 快照逻辑跟随 symlink，兼容 Buck2 源树映射。

### 3) 与其它测试层关系

1. `tests/suite/tool.rs` 覆盖相同语义但更关注退出码与 stdout/stderr（`codex-rs/apply-patch/tests/suite/tool.rs:20-257`）。
2. `core/tests/suite/apply_patch_cli.rs` 在更高层验证审批、路径越界拒绝、事件输出等（例如 `.../apply_patch_cli.rs:95-260`, `563-743`, `1071-1135`）。
3. 因此 fixtures 层定位为“文件结果规范”，不是安全策略完整覆盖层。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言 exit code/stdout/stderr
- 当前只看最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-53`），若未来错误文案或退出码回归但文件状态巧合一致，可能漏检。

2. 场景遍历未排序
- 使用 `fs::read_dir` 原序遍历（`.../scenarios.rs:18`），失败定位顺序在不同文件系统上可能不稳定。

3. 编号可读性风险
- 存在 `020_delete_file_success` 与 `020_whitespace_padded_patch_marker_lines` 双 020，长期维护时容易误判覆盖缺口。

4. 非事务语义需显式认知
- `015_failure_after_partial_success_leaves_changes` 明确“前序成功改动会保留”，该语义合理但高风险，调用方必须理解。

5. 安全边界不在本目录
- 路径越界拒绝、审批策略等主要在 `core` 层测试，fixtures 本身不直接体现。

### 改进建议

1. 为场景增加可选元数据（如 `expect_exit`, `expect_stderr_contains`），保留最终态断言的同时补足错误通道回归检测。
2. 在 `test_apply_patch_scenarios()` 中对目录名排序后再执行，提高可重复性与 CI 可读性。
3. 统一场景编号策略（例如修正重复 `020`），并在 README 增加“编号/命名约定”。
4. 扩展 fixture 维度：补充路径归一化、混合换行（CRLF 输入）、更复杂 Unicode 正规化冲突案例。
5. 在 README 增加“本层仅验证最终态，不覆盖审批/越界策略”说明，减少误用预期。
