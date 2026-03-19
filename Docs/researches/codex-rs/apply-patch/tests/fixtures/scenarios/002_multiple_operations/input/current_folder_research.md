# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input`
- 类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`input/` 是 `002_multiple_operations` 场景的“执行前基线状态”，用于承载 patch 执行前真实文件树。该目录不直接包含逻辑代码，但它是场景正确性的起点样本，直接决定后续 `Delete` 与 `Update` hunk 能否命中。

本目录内文件职责：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`
   - 提供 `Update File: modify.txt` 的旧内容上下文（`line2` 将被替换为 `changed`）。
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`
   - 提供 `Delete File: delete.txt` 的删除目标。

在场景框架中，它与同级 `patch.txt`、`expected/` 形成三段式契约（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-7`）：

1. `input/`：初始状态。
2. `patch.txt`：单次 patch 操作。
3. `expected/`：最终状态。

## 功能点目的

围绕本目录的功能目的可拆成三个层次：

1. 覆盖“复合补丁”场景的输入前提。
- `patch.txt` 同时包含 Add/Delete/Update 三种操作（`codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`）。
- `input/` 提供其中 Delete 与 Update 的必要前置文件。

2. 验证 `Update` 的内容替换语义。
- `modify.txt` 从 `line1\nline2\n` 变为 `line1\nchanged\n`，对应 patch 中 `-line2/+changed`（`.../patch.txt:7-8`）。

3. 验证 `Delete` 的文件存在前提。
- `delete.txt` 需在执行前存在，确保 `remove_file` 走成功路径（执行代码在 `codex-rs/apply-patch/src/lib.rs:301-305`）。

额外说明：同语义在 `tests/suite/tool.rs` 里有命令行断言版测试（`codex-rs/apply-patch/tests/suite/tool.rs:20-41`），而本场景 fixture 版本更偏向“目录最终态一致性”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

`input/` 被消费的主流程（integration test）：

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将当前场景 `input/` 递归复制到临时目录（`.../scenarios.rs:34-37,107-125`）。
3. 读取同级 `patch.txt`（`.../scenarios.rs:39-40`），调用 `apply_patch` 二进制执行（`.../scenarios.rs:45-48`）。
4. 把执行后临时目录与 `expected/` 快照对比（`.../scenarios.rs:50-58,71-105`）。

### 2) 关键数据结构

1. 场景快照结构：`Entry::File(Vec<u8>) | Entry::Dir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-69`）。
2. patch 解析结构：`Hunk::{AddFile, DeleteFile, UpdateFile}`（`codex-rs/apply-patch/src/parser.rs:58-76`）。
3. 更新块结构：`UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`codex-rs/apply-patch/src/parser.rs:90-104`）。
4. 执行统计结构：`AffectedPaths { added, modified, deleted }`，用于输出摘要（`codex-rs/apply-patch/src/lib.rs:271-275,537-551`）。

### 3) 协议与命令

patch 协议边界：

1. 必须以 `*** Begin Patch` 开始、`*** End Patch` 结束（`codex-rs/apply-patch/src/parser.rs:31-32,185-243`）。
2. 文件操作头包括 `*** Add File`、`*** Delete File`、`*** Update File`（`.../parser.rs:33-35,248-340`；文档见 `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-17,40-50`）。
3. 路径要求为相对路径（`.../apply_patch_tool_instructions.md:69`），`input/` 中 `delete.txt`、`modify.txt` 正是该约束下的相对文件。

执行命令路径：

1. 可执行入口 `apply_patch` -> `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-3`）。
2. `run_main()` 接受单参数 patch 或 stdin（`codex-rs/apply-patch/src/standalone_executable.rs:11-41`），再调用 `apply_patch()`（`.../standalone_executable.rs:49-57`）。
3. `apply_patch()` 先 parse，再 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
4. `apply_hunks_to_files()` 顺序执行 Add/Delete/Update，直接操作文件系统（`.../lib.rs:279-339`）。

### 4) 与上层工具链的连接

虽然本目录是测试 fixture，但协议/执行语义与生产链路一致：

1. `core` handler 对 patch 先做 verified parse（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. runtime 通过 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-94`）。
3. `arg0` 检测 `--codex-run-as-apply-patch` 并调用 `codex_apply_patch::apply_patch` 落盘（`codex-rs/arg0/src/lib.rs:89-107`）。

## 关键代码路径与文件引用

### A. 目标目录与同级场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/modify.txt:1-2`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/input/delete.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/patch.txt:1-9`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/modify.txt:1-2`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/002_multiple_operations/expected/nested/new.txt:1`

### B. 直接调用方（消费 `input/`）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:107-125`
3. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 语义并行测试（行为对照）

1. `codex-rs/apply-patch/tests/suite/tool.rs:20-41`
2. `codex-rs/apply-patch/tests/suite/cli.rs:11-90`

### D. 被调用实现（解析/执行）

1. `codex-rs/apply-patch/src/parser.rs:106-183`
2. `codex-rs/apply-patch/src/parser.rs:248-340`
3. `codex-rs/apply-patch/src/lib.rs:183-266`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/lib.rs:386-474`

### E. 配置、文档与脚本

1. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-7`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:1-75`
4. `codex-rs/apply-patch/Cargo.toml:1-30`
5. `codex-rs/apply-patch/BUILD.bazel:1-11`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:79`

## 依赖与外部交互

### 1) 依赖关系

1. crate 依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`codex-utils-cargo-bin`、`tempfile`、`pretty_assertions`（`.../Cargo.toml:25-30`）。
3. Bazel 打包约束：`apply_patch_tool_instructions.md` 被 `compile_data` 引入（`codex-rs/apply-patch/BUILD.bazel:8-10`）。

### 2) 外部交互面

1. 文件系统交互：
- `input/` 复制到临时目录（`scenarios.rs:34-37,107-125`）。
- 执行器对文件 `write/remove/read`（`lib.rs:289-329,348-359`）。

2. 子进程交互：
- 测试使用 `cargo_bin("apply_patch")` 启动真实可执行文件（`scenarios.rs:45-48`，`tool.rs:7-10`）。

3. 平台兼容处理：
- 快照和复制逻辑都使用 `fs::metadata()` 跟随 symlink，兼容 Buck2 场景（`scenarios.rs:92-95,113-114`）。

### 3) 配置/约束语义

1. 本场景没有独立配置文件；“配置”主要体现为 patch 协议文本与相对路径规则。
2. 路径解析以当前目录为基准，`Hunk::resolve_path` 将相对路径 join 到 `cwd`（`codex-rs/apply-patch/src/parser.rs:78-85`）。
3. 更上层 `maybe_parse_apply_patch_verified` 还支持 shell 脚本/ heredoc 与可选 workdir 解析（`codex-rs/apply-patch/src/invocation.rs:75-217`）。

## 风险、边界与改进建议

### 风险与边界

1. 非原子执行：`apply_hunks_to_files` 顺序落盘，后续 hunk 失败不会回滚前序成功变更（`codex-rs/apply-patch/src/lib.rs:287-333`）。
2. 场景测试不校验退出码与 stdout/stderr，仅比较最终文件树（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
3. 当前场景只覆盖“成功复合操作”；对“复合补丁中途失败”风险没有在本目录就地体现（该行为在 `tool.rs` 另有覆盖）。
4. 场景遍历未显式排序（`scenarios.rs:18`），跨文件系统的失败顺序可读性可能不稳定。

### 改进建议

1. 在场景系统增加可选元数据（如 `meta.toml`），允许声明 `expectExitCode` 与 `expectStdoutContains`，补齐行为协议断言。
2. 在 `002_multiple_operations` 旁增加一个“部分成功后失败”的兄弟场景，显式刻画非原子语义。
3. 对 `test_apply_patch_scenarios()` 的目录遍历做排序，提升失败复现一致性。
4. 在 `scenarios/README.md` 增补“复合操作样例（002）”说明，降低维护者理解成本。
