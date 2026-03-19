# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`007_rejects_missing_file_delete` 是 `apply_patch` 场景集中用于校验“删除不存在文件必须失败且不产生副作用”的负向用例。

该目录包含三类 fixture：

1. `patch.txt`：补丁只包含 `*** Delete File: missing.txt`（`codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt:1-3`）。
2. `input/foo.txt`：初始状态只有一个稳定文件 `stable`，故意不提供 `missing.txt`（`.../input/foo.txt:1`）。
3. `expected/foo.txt`：与 `input` 完全一致，用于表达“失败后工作目录不变”（`.../expected/foo.txt:1`）。

它在测试体系中的职责是“状态不变回归保护”：

1. fixture 回放层：比较最终文件树，确保失败不会误删或误写（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-60`）。
2. CLI 行为层：精确断言 stderr 文案 `Failed to delete file missing.txt`（`codex-rs/apply-patch/tests/suite/tool.rs:114-123`）。
3. core 工具链层：在更上游的 verified 路径断言“预检读文件失败”（`codex-rs/core/tests/suite/apply_patch_cli.rs:474-503`）。

## 功能点目的

该场景的功能目标是锁定 `Delete File` 操作的失败语义边界：

1. 不允许“删除不存在目标”被当作成功，避免虚假成功状态。
2. 失败必须可诊断，调用方能基于错误信息决定是否重试或改补丁。
3. 失败不能破坏现有文件，确保非目标文件保持原样。
4. 与同类负向场景形成覆盖矩阵：
   - `006_rejects_missing_context` 覆盖 update 定位失败；
   - `007_rejects_missing_file_delete` 覆盖 delete 目标缺失；
   - `012_delete_directory_fails` 覆盖 delete 类型错误（目录不是普通文件）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景执行流程

1. `test_apply_patch_scenarios()` 扫描 `tests/fixtures/scenarios` 下所有目录并逐个执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录（`.../scenarios.rs:33-37,107-125`）。
3. 读取 `patch.txt` 并执行 `apply_patch <patch>`（`.../scenarios.rs:39-48`）。
4. 该回放测试不校验退出码，只比较最终快照（`.../scenarios.rs:42-45,50-60`）。
5. 快照结构是 `BTreeMap<PathBuf, Entry>`，其中 `Entry = File(Vec<u8>) | Dir`（`.../scenarios.rs:65-77`）。

### 2) 从协议到执行的关键链路

1. CLI 入口：`src/main.rs` 仅转发到 `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-2`）。
2. `run_main()` 读取参数或 stdin，调用 `crate::apply_patch()`，失败返回退出码 `1`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
3. `apply_patch()` 先 `parse_patch()`，再调用 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
4. parser 在 `parse_one_hunk()` 中将 `*** Delete File: missing.txt` 解析为 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:248-278`）。
5. `apply_hunks_to_files()` 遇到 `Hunk::DeleteFile` 时执行 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:301-304`）。
6. 因 `missing.txt` 不存在，`remove_file` 报错，经 `with_context` 包装为 `Failed to delete file missing.txt`（`codex-rs/apply-patch/src/lib.rs:302-303`）。
7. `apply_hunks()` 捕获错误并写入 stderr，返回失败（`codex-rs/apply-patch/src/lib.rs:253-264`）。
8. 由于失败发生在 delete hunk 执行点且本补丁仅一条 hunk，临时目录内容保持 `foo.txt=stable`，与 `expected` 一致。

### 3) 数据结构与协议

1. 协议标记：`*** Begin Patch` / `*** Delete File: <path>` / `*** End Patch`（`patch.txt:1-3`，协议定义见 `codex-rs/apply-patch/apply_patch_tool_instructions.md:41-47`）。
2. 关键数据结构：
   - `Hunk::DeleteFile { path: PathBuf }`（`codex-rs/apply-patch/src/parser.rs:64-67,271-278`）。
   - `AffectedPaths { added, modified, deleted }`（`codex-rs/apply-patch/src/lib.rs:271-275`）。
3. 本场景的 `AffectedPaths` 不会生成成功结果，因为在 push `deleted` 前已错误返回。

### 4) 命令与跨模块调用契约

1. 直接命令：`apply_patch "*** Begin Patch\n*** Delete File: missing.txt\n*** End Patch"`（`codex-rs/apply-patch/tests/suite/tool.rs:117-121`）。
2. 在 core runtime 中，成功通过预检后会组装 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-94`）。
3. core handler 对 `apply_patch` 输入先走 `maybe_parse_apply_patch_verified()` 预检（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
4. 预检对 `DeleteFile` 的策略是先 `read_to_string(path)` 读取待删文件内容，不存在时提前返回 `Failed to read ...`（`codex-rs/apply-patch/src/invocation.rs:170-183`）。

这意味着：

1. 裸 `apply_patch` CLI（本场景）对 missing delete 的报错是 `Failed to delete file ...`（执行期）。
2. core 工具链对 missing delete 的报错更早，是 `Failed to read ...`（预检期，`codex-rs/core/tests/suite/apply_patch_cli.rs:489-500`）。

## 关键代码路径与文件引用

### 目标目录与夹具

1. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/patch.txt:1-3`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/input/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/007_rejects_missing_file_delete/expected/foo.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-18`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`

### 调用方

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:114-123`
5. `codex-rs/core/tests/suite/apply_patch_cli.rs:474-503`

### 被调用方

1. `codex-rs/apply-patch/src/main.rs:1-2`
2. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:216-266`
5. `codex-rs/apply-patch/src/lib.rs:279-339`
6. `codex-rs/apply-patch/src/parser.rs:248-278`
7. `codex-rs/apply-patch/src/invocation.rs:132-183`

### 配置、构建、文档、脚本上下文

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-16,41-47,71-75`
4. `codex-rs/core/src/tools/handlers/apply_patch.rs:157-210`
5. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
6. `codex-rs/exec/tests/suite/apply_patch.rs:16-40`
7. `.ops/generate_daily_research_todo.sh:5-7,15-18,33-39`
8. `Docs/researches/blueprint_checklist.md:96-98`

## 依赖与外部交互

### 1) 依赖

1. `codex-apply-patch` 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 外部交互

1. 文件系统：场景框架复制 `input`、读取 `patch`、执行后抓取目录快照（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`）。
2. 子进程：通过 `Command::new(cargo_bin("apply_patch"))` 调用目标可执行文件（`.../scenarios.rs:45-48`，`.../tool.rs:7-14`）。
3. 标准输出/错误：失败路径向 stderr 输出错误字符串（`codex-rs/apply-patch/src/lib.rs:253-256`）。
4. 在 core 模式下还会走审批与沙箱编排，并通过 `--codex-run-as-apply-patch` 自调用执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-100`）。

### 3) 与研究流水线的脚本交互

1. 勾选 checklist 后，`generate_daily_research_todo.sh` 通过正则抽取 pending 条目，重写当日 `todos_YYYYMMDD.md`（`.ops/generate_daily_research_todo.sh:15-39`）。
2. 本次目标对应的 checklist 行是第 96 行（`Docs/researches/blueprint_checklist.md:96`）。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不断言 exit status/stderr，只看最终文件树；若错误文案或错误码回归但文件未变，fixture 层无法发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
2. 同一语义在不同入口报错文案不同：
   - 直接 CLI：`Failed to delete file ...`；
   - core verified 路径：`Failed to read ...`。
   这会增加调用方做统一错误处理的复杂度（`codex-rs/apply-patch/src/lib.rs:302-303`，`codex-rs/apply-patch/src/invocation.rs:170-177`）。
3. 当前场景只覆盖“目标不存在”，未覆盖“权限不足删除失败”“只读文件系统”等系统级失败原因。
4. 该场景是单 hunk，无法反映多 hunk 情况下部分成功后的可观测行为。

### 改进建议

1. 为 fixture 框架增加可选断言元数据（例如 `result.json`），至少支持 `expected_exit_code` 与 `stderr_contains`，让负向场景不只校验最终态。
2. 统一 missing delete 错误语义（预检与执行期），或在文档中明确“core 与裸 CLI 的错误来源差异”。
3. 新增 delete 失败细分场景：权限拒绝、符号链接、并发删除（TOCTOU）等，避免仅依赖 `ENOENT`。
4. 在 `scenarios.rs` 中对目录名排序后执行，提升失败日志定位和 CI 复现实用性。
