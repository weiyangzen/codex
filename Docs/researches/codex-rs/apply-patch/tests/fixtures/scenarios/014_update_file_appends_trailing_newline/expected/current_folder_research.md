# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/expected`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属模块：`codex-rs/apply-patch`（crate：`codex-apply-patch`）
- 目录内文件：`no_newline.txt`

## 场景与职责

该目录是场景 `014_update_file_appends_trailing_newline` 的 **期望输出快照目录（expected snapshot）**。在 `apply_patch` 的场景回放测试中，它不参与执行逻辑，只作为“最终文件系统状态”的基准。

这个目录在测试中的职责是：

1. 定义 `Update File` 操作成功后的目标文件内容与换行形态。
2. 配合同级 `input/` 和 `patch.txt` 形成三段式场景契约（输入、操作、期望）。
3. 通过字节级快照比较约束回归行为，避免只看 stdout/stderr 导致漏检。

目录内容与语义：

1. `expected/no_newline.txt` 内容是两行文本，且最后有 `\n`（hex 末尾 `0A`）。
2. 配套 patch 将 `no newline at end` 替换为 `first line` + `second line`。
3. 场景名强调“append trailing newline”，对应执行层在更新后统一补齐末尾换行的实现策略。

## 功能点目的

围绕该 `expected/` 目录，核心目的不是演示 patch 语法本身，而是固化一个可回归的输出语义：

1. `Update File` 的结果文件应当是 **newline-terminated text**（文本文件以换行结束）。
2. 多行替换后的落盘结果必须稳定为：
   - `first line\n`
   - `second line\n`
3. 在场景测试框架中，此目录作为“真值”，保证后续改动（匹配算法、replace 逻辑、I/O 逻辑）不会破坏该语义。

与其它测试的分工：

1. `tests/suite/scenarios.rs` 使用该目录验证“最终文件树一致”。
2. `tests/suite/tool.rs::test_apply_patch_cli_updates_file_appends_trailing_newline` 额外验证 stdout 与 `ends_with('\n')`。
3. 两者组合覆盖“状态面 + 行为面”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（场景回放）

1. `test_apply_patch_scenarios` 遍历 `fixtures/scenarios/*`。
2. 对每个场景，`run_apply_patch_scenario`：
   - 复制 `input/` 到临时目录。
   - 读取 `patch.txt`。
   - 启动 `apply_patch` 二进制执行 patch。
   - 对比 `expected/` 与临时目录快照。
3. 本目录（`expected/`）仅在最后一步被读取并参与断言。

### 2) 关键数据结构

1. `parser::Hunk`
   - `AddFile`
   - `DeleteFile`
   - `UpdateFile { path, move_path, chunks }`
2. `parser::UpdateFileChunk`
   - `change_context`
   - `old_lines`
   - `new_lines`
   - `is_end_of_file`
3. 场景快照结构：`BTreeMap<PathBuf, Entry>`，其中 `Entry = File(Vec<u8>) | Dir`。

`expected/no_newline.txt` 的断言是通过 `Entry::File(Vec<u8>)` 的字节相等完成，不是“模糊文本比较”。

### 3) 关键实现点（为何会补尾换行）

`derive_new_contents_from_chunks` 的实现路径：

1. 读取原文件并按 `\n` 拆分为行数组。
2. 若拆分尾部为空行（表示源文件末尾已有换行），先弹出空元素。
3. 根据 `compute_replacements` 结果执行替换。
4. 在输出前执行统一收敛：
   - 如果最后一行不是空字符串，就 `push(String::new())`。
5. `join("\n")` 得到最终文本，保证结果末尾为 `\n`。

因此，本目录里的 `expected/no_newline.txt` 正是在锁定该收敛行为。

### 4) 协议/命令语义

patch 协议来自 `apply_patch_tool_instructions.md` 与 parser grammar：

1. Envelope：`*** Begin Patch ... *** End Patch`
2. 文件头：`*** Update File: <path>`
3. hunk：`@@` + `+/-/ ` 行

场景命令层面由测试代码调用：

- `Command::new(codex_utils_cargo_bin::cargo_bin("apply_patch")?)`
- `arg(patch)`
- `current_dir(tmp.path())`

CLI 入口 `standalone_executable::run_main` 支持：

1. argv 传入完整 patch。
2. 无 argv 时从 stdin 读取 patch。

## 关键代码路径与文件引用

### A. 目标目录与同场景实体

1. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/expected/no_newline.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/input/no_newline.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/014_update_file_appends_trailing_newline/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`

### B. 直接调用方（消费 expected 的测试）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`
4. `codex-rs/apply-patch/tests/suite/tool.rs`

### C. 被调用方（apply_patch 执行链）

1. `codex-rs/apply-patch/src/main.rs`
2. `codex-rs/apply-patch/src/standalone_executable.rs`
3. `codex-rs/apply-patch/src/parser.rs`
4. `codex-rs/apply-patch/src/lib.rs`
5. `codex-rs/apply-patch/src/seek_sequence.rs`

### D. 上游运行时/分发链（上下文依赖）

1. `codex-rs/core/src/tools/handlers/apply_patch.rs`（handler 侧验证 + 运行编排）
2. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（运行时构造 `codex --codex-run-as-apply-patch` 命令）
3. `codex-rs/arg0/src/lib.rs`（`CODEX_CORE_APPLY_PATCH_ARG1` 分发到 `codex_apply_patch::apply_patch`）

### E. 配置/脚本/文档

1. `codex-rs/apply-patch/Cargo.toml`（crate、bin、依赖）
2. `codex-rs/apply-patch/BUILD.bazel`（`compile_data`）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（场景规范）
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（协议文档）
5. `.ops/generate_daily_research_todo.sh`（每日 todo 生成）
6. `Docs/researches/blueprint_checklist.md`（研究任务基线）

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 关键依赖：

1. `anyhow` / `thiserror`：错误建模与上下文。
2. `similar`：统一 diff 生成。
3. `tree-sitter` / `tree-sitter-bash`：shell heredoc 命令解析（invocation 路径）。

测试依赖：

1. `assert_cmd`
2. `codex-utils-cargo-bin`
3. `tempfile`
4. `pretty_assertions`

### 2) 文件系统与进程交互

1. 测试侧会读写临时目录、复制 `input/`、读取 `expected/`。
2. 通过子进程执行 `apply_patch` 二进制。
3. 执行器会对目标文件做真实读写与可能的删除/移动。

### 3) 与规范/工具链交互

1. `.gitattributes`：`** text eol=lf` 统一换行，减少跨平台波动。
2. `scenarios/README.md`：定义 fixtures 目录契约。
3. `.ops/generate_daily_research_todo.sh`：从 checklist 生成当日待办快照。

## 风险、边界与改进建议

### 风险

1. 场景名 `no_newline` 与 fixture 实际字节（末尾有 `0A`）存在语义歧义，容易误读。
2. `scenarios.rs` 明确不校验退出码，仅比较最终文件树；错误文案回归可能不会被该场景发现。
3. 末尾换行是当前实现策略（统一补齐），若未来要支持“保留无末尾换行”将与本场景冲突。

### 边界

1. 本目录只覆盖文本文件内容与目录结构，不覆盖权限位、mtime、owner 等元数据。
2. 不覆盖 `*** End of File` 专用语义（对应 `022_update_file_end_of_file_marker`）。
3. 不覆盖失败回滚/部分成功语义（对应 `015_failure_after_partial_success_leaves_changes`）。

### 改进建议

1. 在该场景目录补充短 README（或注释）解释“名称与字节现状”，减少维护误解。
2. 为场景框架增加可选元数据断言（如 `expected_exit_code`、`expected_stderr_contains`）。
3. 若需要严格覆盖“输入无末尾换行”字节语义，可新增 `-text` 或二进制 fixture 路径，避免 `.gitattributes` 文本归一化干扰。
4. 在 `apply_patch_tool_instructions.md` 增加“输出文本默认补尾换行”的说明，统一调用方预期。
