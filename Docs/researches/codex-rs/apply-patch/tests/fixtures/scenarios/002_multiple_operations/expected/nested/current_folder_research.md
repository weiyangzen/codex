# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `002_multiple_operations` 的叶子级 expected 快照目录，只承载一个文件 `new.txt`，其存在本身就是断言的一部分。

1. 目录职责是提供“最终文件树中应新增子目录 `nested/`”这一结构性证据，而不只是文本内容证据。
2. 该目录并不被业务代码直接读取；它由测试框架 `tests/suite/scenarios.rs` 在快照对比阶段递归扫描并参与 `assert_eq!`。
3. 在 `002_multiple_operations` 的 `patch.txt` 中，`*** Add File: nested/new.txt` 是唯一会生成该目录的操作；因此本目录是 Add hunk 父目录自动创建能力的外显结果。

直接对象：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:2-3`

## 功能点目的

围绕本目录，测试目标不是“文本文件存在”这么简单，而是验证复合 patch 的三个关键契约在最终态上可同时成立：

1. 目录自动创建契约  
   `Add File nested/new.txt` 应触发 `create_dir_all(parent)`，所以最终态必须包含目录 `nested/`。
2. 新文件内容契约  
   `new.txt` 内容必须是 `created\n`，证明 Add hunk 的 `+` 行拼接和落盘正确。
3. 复合操作协同契约  
   同一 patch 同时执行 Add/Delete/Update 时，Add 的目录与文件必须和其他操作一起进入最终快照，不被遗漏或覆盖。
4. 可移植 fixture 契约  
   `input/ + patch.txt + expected/` 三段式是场景规范，本目录是该规范在“新增嵌套路径”上的最小可移植样本。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 场景驱动  
   `test_apply_patch_scenarios()` 扫描 `tests/fixtures/scenarios/*` 并调用 `run_apply_patch_scenario()`。  
   见 `codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`。
2. 执行准备  
   `run_apply_patch_scenario()` 复制 `input/` 到临时目录，然后读取 `patch.txt`。  
   见 `.../scenarios.rs:30-40`。
3. 执行 patch  
   测试通过真实二进制 `apply_patch` 执行 patch 文本。  
   见 `.../scenarios.rs:45-48`，入口在 `codex-rs/apply-patch/src/standalone_executable.rs:11-58`。
4. 快照对比  
   测试对 expected 与实际目录分别调用 `snapshot_dir()`，递归记录 `Entry::Dir` 和 `Entry::File(Vec<u8>)` 后整体比对。  
   见 `.../scenarios.rs:50-58,65-105`。
5. 本目录被消费的方式  
   当扫描到 `expected/nested` 时，目录节点写入 `Entry::Dir`，`new.txt` 写入字节内容；最终与实际目录树逐项比较。

### 2) 关键数据结构

1. `Hunk`  
   patch 被解析为 `AddFile/DeleteFile/UpdateFile` 三种变更。  
   见 `codex-rs/apply-patch/src/parser.rs:58-76`。
2. `AffectedPaths`  
   执行器汇总 `added/modified/deleted`，用于生成 `A/M/D` 输出。  
   见 `codex-rs/apply-patch/src/lib.rs:270-275,537-551`。
3. `Entry`  
   场景快照结构，`Dir` 与 `File(Vec<u8>)` 并重，保证目录结构和内容同等受检。  
   见 `codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`。

### 3) 协议与命令细节

1. patch 协议要求以 `*** Begin Patch` / `*** End Patch` 包裹，文件操作头必须显式声明。  
   见 `codex-rs/apply-patch/src/parser.rs:31-39,154-183` 与  
   `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50,65-69`。
2. `Add File` 解析连续 `+` 行得到目标内容（每行补 `\n`）。  
   见 `codex-rs/apply-patch/src/parser.rs:251-270`。
3. 执行 `Add File` 时先 `create_dir_all(parent)` 再 `write`，因此 `nested/` 会被显式创建。  
   见 `codex-rs/apply-patch/src/lib.rs:289-299`。
4. 复合 patch 命令样例（场景 002）：  
   `*** Add File: nested/new.txt` + `*** Delete File: delete.txt` + `*** Update File: modify.txt`。  
   见 `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`。

## 关键代码路径与文件引用

目标目录与同场景文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/modify.txt:1-2`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`

调用方（消费该目录快照）：

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:79-105`

被调用方（生成本目录对应实际输出）：

1. `codex-rs/apply-patch/src/main.rs:1-3`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/parser.rs:154-183,248-333`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:537-551`

并行语义测试与上游运行时：

1. `codex-rs/apply-patch/tests/suite/tool.rs:20-42`（同 patch 语义并校验 stdout）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-210`（tool handler 先 verified parse）
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101`（构造 `codex --codex-run-as-apply-patch`）
4. `codex-rs/arg0/src/lib.rs:89-107`（arg0 分发至 `codex_apply_patch::apply_patch`）

配置/文档/脚本：

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `.ops/generate_daily_research_todo.sh:1-42`
6. `Docs/researches/blueprint_checklist.md:78`

## 依赖与外部交互

代码依赖：

1. `anyhow` / `thiserror`：错误包装与上下文。
2. `tree-sitter` / `tree-sitter-bash`：支持 shell/heredoc 形式 `apply_patch` 解析。见 `src/invocation.rs:103-217`。
3. `similar`：在 verified 路径中生成 unified diff。见 `src/lib.rs:511-533`。
4. `assert_cmd` / `tempfile` / `codex-utils-cargo-bin` / `pretty_assertions`：测试进程调度、临时目录、二进制定位、断言增强。

外部交互：

1. 文件系统：创建目录、写文件、删文件、递归快照（`lib.rs:289-305`，`scenarios.rs:79-125`）。
2. 子进程：测试通过 `cargo_bin("apply_patch")` 执行真实 CLI（`scenarios.rs:45-48`）。
3. 文档编排：研究流程通过 `.ops/generate_daily_research_todo.sh` 读取 checklist 并生成每日 todo。

## 风险、边界与改进建议

风险与边界：

1. 非原子性边界  
   `apply_hunks_to_files` 按 hunk 顺序即时落盘，后续失败不会回滚前序成功操作；复合场景可能出现“部分成功”。
2. 断言维度边界  
   `scenarios.rs` 不校验退出码和 stdout/stderr，只比较最终文件树；输出协议回归可能在该套件中漏检。
3. 目标目录极小  
   本目录仅 1 个文件，覆盖了“嵌套目录创建”但未覆盖权限位、二进制内容、冲突覆盖等边界。
4. 顺序稳定性  
   场景遍历依赖 `read_dir` 原始顺序，失败日志顺序在不同平台可能不同。

改进建议：

1. 为 `scenarios` 增加可选 `meta.toml`，支持 `expected_exit_code`/`expected_stdout`，与目录快照形成双重断言。
2. 在 `002_multiple_operations` 增补失败中断变体，显式固化“部分落盘非原子”行为契约。
3. 为 `expected/nested` 同类目录增加二进制 fixture，用 `Entry::File(Vec<u8>)` 验证非文本稳定性。
4. 在 `tests/suite/scenarios.rs` 对场景名排序后执行，提升跨平台复现一致性。
