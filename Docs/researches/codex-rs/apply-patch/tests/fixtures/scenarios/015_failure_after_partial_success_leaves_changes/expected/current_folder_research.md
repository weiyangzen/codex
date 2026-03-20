# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected`
- 目标类型：`DIR`
- 研究日期：`2026-03-20`
- 所属模块：`codex-rs/apply-patch`（crate：`codex-apply-patch`）
- 目录内文件：`created.txt`

## 场景与职责

该目录是场景 `015_failure_after_partial_success_leaves_changes` 的期望输出快照目录（`expected/`），用于表达一个关键语义：`apply_patch` 在多 hunk 顺序执行时，如果后续 hunk 失败，前序已落盘改动不会回滚。

目录本身非常小，但语义密度很高：

1. `expected/created.txt` 只有一行 `hello`（`codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt:1`）。
2. 对应 patch 先执行 `Add File: created.txt`，再执行 `Update File: missing.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt:1-8`）。
3. 由于 `missing.txt` 不存在，整体命令失败；但 `created.txt` 已经写入，因此最终快照中保留该文件。

在测试框架中的职责是“锁定失败场景下的副作用保留行为”，而不是验证完全成功路径。

## 功能点目的

围绕该 `expected/` 目录，核心目的是防止对 `apply_patch` 事务语义的误判：

1. 明确 `apply_patch` 默认是顺序应用（best-effort until failure），不是全量原子提交。
2. 通过文件系统最终态断言，保证“失败后保留前序成功改动”的行为长期可回归。
3. 与命令行错误断言形成互补：
   - 场景框架：只看最终目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-58`）。
   - tool 集成测试：看失败退出和 stderr，并再次确认 `created.txt` 仍存在（`codex-rs/apply-patch/tests/suite/tool.rs:243-255`）。

该目录因此承担“失败时副作用契约”的基准职责。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程（调用方）

`tests/suite/scenarios.rs` 的执行步骤：

1. 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 复制 `input/` 到临时目录；本场景无 `input/`，所以初始工作区为空（`codex-rs/apply-patch/tests/suite/scenarios.rs:34-37`）。
3. 读取 `patch.txt` 并调用 `apply_patch` 可执行文件（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 不检查退出码，只对比 `expected/` 与实际目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-58`）。

这意味着：只要最终文件树与 `expected/` 一致，即使命令失败，场景仍应通过。

### 2) 执行内核流程（被调用方）

`apply_patch` 主链路：

1. `standalone_executable::run_main` 读取参数并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch` 先解析 patch，再执行 `apply_hunks`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
3. `apply_hunks_to_files` 按 hunk 顺序遍历并直接进行文件系统读写（`codex-rs/apply-patch/src/lib.rs:279-333`）。

本场景关键点在顺序和无回滚：

1. `Hunk::AddFile` 先 `std::fs::write` 写入 `created.txt`（`codex-rs/apply-patch/src/lib.rs:289-299`）。
2. 后续 `Hunk::UpdateFile` 进入 `derive_new_contents_from_chunks`，尝试读取 `missing.txt`，读失败即返回错误（`codex-rs/apply-patch/src/lib.rs:311-313,348-359`）。
3. 错误被写入 stderr 并终止处理，但没有补偿/回滚逻辑（`codex-rs/apply-patch/src/lib.rs:253-264`）。

结果就是“命令失败 + created.txt 保留”，正是该 `expected/` 的目标状态。

### 3) 数据结构与协议

关键结构：

1. `parser::Hunk::{AddFile, DeleteFile, UpdateFile}`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
2. `UpdateFileChunk`（`change_context / old_lines / new_lines / is_end_of_file`，`codex-rs/apply-patch/src/parser.rs:90-104`）。
3. 场景快照结构 `BTreeMap<PathBuf, Entry>`，其中 `Entry::File(Vec<u8>)` 用字节级比较 expected 与 actual（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77,79-105`）。

协议层：

1. patch 语法 envelope 与 Add/Update 头部来自 `apply_patch` 规范（`codex-rs/apply-patch/apply_patch_tool_instructions.md:6-50`）。
2. 场景约定 `input/ + patch.txt + expected/` 来自 fixtures 说明（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）。

### 4) 相关命令

1. 运行场景回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 运行本行为专测：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_failure_after_partial_success_leaves_changes -- --exact`
3. 研究待办生成：`bash .ops/generate_daily_research_todo.sh`（`.ops/generate_daily_research_todo.sh:1-42`）。

## 关键代码路径与文件引用

### A. 研究对象与同场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/expected/created.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/015_failure_after_partial_success_leaves_changes/patch.txt:1-8`

### B. 直接调用方（测试）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-60`
2. `codex-rs/apply-patch/tests/suite/tool.rs:243-255`
3. `codex-rs/apply-patch/tests/all.rs:1-3`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 被调用方（apply-patch 实现）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-333`
4. `codex-rs/apply-patch/src/lib.rs:348-359`
5. `codex-rs/apply-patch/src/parser.rs:58-76`
6. `codex-rs/apply-patch/src/parser.rs:248-333`

### D. 上下文依赖（core/arg0/config）

1. `codex-rs/apply-patch/src/invocation.rs:132-217`（verified 预检与变更预计算）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-244`（handler 先做 verified，再决定是否执行）
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`（组装 `codex --codex-run-as-apply-patch <patch>` 命令）
4. `codex-rs/arg0/src/lib.rs:89-107`（ARG1 分发到 `codex_apply_patch::apply_patch`）
5. `codex-rs/core/src/tools/spec.rs:2784-2804`（注册 `apply_patch` tool）

### E. 配置、文档与脚本

1. `codex-rs/core/src/config/mod.rs:528-535`（`include_apply_patch_tool` 配置项定义）
2. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:6-50`
4. `codex-rs/apply-patch/Cargo.toml:1-30`
5. `codex-rs/apply-patch/BUILD.bazel:1-11`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:129`

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 关键依赖：

1. `anyhow` / `thiserror`：错误建模与上下文（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. `similar`：统一 diff 生成（`codex-rs/apply-patch/src/lib.rs:18,523-531`）。
3. `tree-sitter` / `tree-sitter-bash`：shell heredoc 识别（`codex-rs/apply-patch/src/invocation.rs:5-10,219-280`）。

测试依赖：

1. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统与进程交互

1. 场景 runner 会在临时目录中真实执行二进制并读写文件（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-48`）。
2. `expected/` 通过递归快照与临时目录做字节级比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-58,79-105`）。
3. 本场景将“失败后的残留状态”外显为 `created.txt`，属于可观测副作用。

### 3) 与 core 运行链交互

1. core handler 默认先 `maybe_parse_apply_patch_verified`，对不存在的更新目标会提前失败（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175` + `codex-rs/apply-patch/src/invocation.rs:184-194`）。
2. 这与裸 CLI 的“执行中失败并保留前序副作用”形成路径差异：core 常在执行前拦截，而不是执行后失败。
3. runtime 执行时通过 `CODEX_CORE_APPLY_PATCH_ARG1` 自调用当前 codex 可执行程序（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-93`, `codex-rs/arg0/src/lib.rs:89-107`）。

## 风险、边界与改进建议

### 风险

1. 语义误解风险：调用方可能把“exit code != 0”误读为“文件未改动”，但本场景证明并非如此。
2. 测试盲区风险：`scenarios.rs` 不断言退出码与 stderr，某些错误通道文案回归不会被该层发现。
3. 路径一致性风险：core verified 路径与裸 CLI 在失败时机上存在差异，可能导致跨入口行为预期不一致。

### 边界

1. 该目录只覆盖 `Add -> Update(missing)` 组合，不覆盖 `Delete`/`Move` 的部分成功行为。
2. 仅覆盖最终文件状态，不覆盖权限位、mtime、所有者、stderr 国际化差异。
3. 不覆盖并发执行或中途外部进程改写文件的情况。

### 改进建议

1. 在 `scenarios` 框架中增加可选元数据断言（如 `exit_code`、`stderr_contains`），让快照测试同时覆盖状态与失败通道。
2. 在 `apply_patch` 文档中显式声明“默认非事务性，不自动回滚已落盘改动”，降低上层误用概率。
3. 若未来需要原子语义，可新增 `--atomic` 模式：先全量预检与预演，再统一落盘；失败时零写入。
4. 为 `Delete`/`Move` 补充对应“部分成功后失败”的 fixtures，完善行为矩阵，避免只靠单一 `Add->Update` 代表全部情形。
