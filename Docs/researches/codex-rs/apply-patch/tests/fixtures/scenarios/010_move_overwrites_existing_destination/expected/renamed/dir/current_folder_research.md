# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属模块：`codex-rs/apply-patch`（crate：`codex-apply-patch`）
- 对应场景：`010_move_overwrites_existing_destination`

## 场景与职责

该目录是场景 `010_move_overwrites_existing_destination` 在 `expected/` 快照下的最末级目标目录，当前只包含一个业务文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`（内容：`new`）。

它在场景中的职责非常明确：

1. 作为 move 目标路径的最终状态锚点，定义 `old/name.txt` 在 `*** Move to: renamed/dir/name.txt` 后应落到这里。
2. 作为“目标已存在仍覆盖成功”语义的直接证据：`input/renamed/dir/name.txt` 初始值为 `existing`，此目录下 expected 值改为 `new`。
3. 与同场景 `expected/old/other.txt` 协同，定义“命中路径被修改、旁路文件不受影响”的边界。
4. 被 `tests/suite/scenarios.rs` 的目录快照机制直接消费，不承载执行逻辑，仅承载断言语义。

## 功能点目的

围绕该目录，功能目的不是“测试目录存在”本身，而是稳定锁定以下行为契约：

1. `Update File + Move to` 的结果文件应写入目标路径 `renamed/dir/name.txt`。
2. 目标文件已存在时，当前实现采用覆盖语义而非冲突失败语义。
3. 源路径 `old/name.txt` 在执行后应被删除（通过 expected 全量快照间接约束）。
4. 目标目录路径层级 `renamed/dir` 要在最终态中存在，从而验证执行器目录创建/保留逻辑与路径解析一致。

该目录对回归的价值：

1. 补齐 `004_move_to_new_directory` 的覆盖盲区（`004` 主要验证 move 到新目录，`010` 验证 move 覆盖已有目标）。
2. 与程序化测试 `test_apply_patch_cli_move_overwrites_existing_destination` 形成 fixture 断言 + 显式断言的双重保护。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，命中 `010_move_overwrites_existing_destination`（`codex-rs/apply-patch/tests/suite/scenarios.rs`）。
2. `run_apply_patch_scenario()` 将 `input/` 复制到临时目录，读取 `patch.txt`，执行 `apply_patch` 二进制（同文件）。
3. 执行后分别对 `expected/` 与临时目录做递归快照，比较 `BTreeMap<PathBuf, Entry>` 是否完全一致（同文件）。
4. 本目录中的 `expected/renamed/dir/name.txt` 作为结果快照的一部分参与 byte-level 比对，内容不一致即失败。

### 2) 关键数据结构

1. Patch 解析结构：`Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs`）。
2. Update chunk 结构：`UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`（`codex-rs/apply-patch/src/parser.rs`）。
3. 场景快照结构：`Entry::Dir | Entry::File(Vec<u8>)`（`codex-rs/apply-patch/tests/suite/scenarios.rs`）。
4. 执行结果统计：`AffectedPaths { added, modified, deleted }`，成功后输出 `A/M/D` 摘要（`codex-rs/apply-patch/src/lib.rs`）。

### 3) 协议与命令

场景 patch（`codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

协议要点：

1. `*** Update File:` 定义源文件。
2. `*** Move to:` 定义目标路径（可与 update 同时出现）。
3. `@@` 后的 `-from +new` 定义内容替换。

对应执行命令路径：

1. 直接 CLI：`apply_patch "<PATCH>"` 或 stdin 管道（`codex-rs/apply-patch/src/standalone_executable.rs`）。
2. 场景测试：`Command::new(cargo_bin("apply_patch"))` 在临时目录执行（`codex-rs/apply-patch/tests/suite/scenarios.rs`）。
3. Core 运行时：`codex --codex-run-as-apply-patch <patch>`（`codex-rs/core/src/tools/runtimes/apply_patch.rs` + `codex-rs/arg0/src/lib.rs`）。

### 4) 覆盖语义落地细节（本目录为何是 `new`）

`apply_hunks_to_files()` 在 `move_path` 分支中的关键动作：

1. 先对源文件计算更新后的 `new_contents`（`derive_new_contents_from_chunks`）。
2. `create_dir_all(dest.parent())` 确保目标目录可写。
3. `std::fs::write(dest, new_contents)` 写入目标路径；目标文件已存在时会被覆盖。
4. `std::fs::remove_file(path)` 删除源文件。

这直接决定了 `expected/renamed/dir/name.txt` 必须为 `new\n`，且 `old/name.txt` 必须缺失。

## 关键代码路径与文件引用

### A. 目标目录与同场景数据

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt`

### B. 调用方（消费该目录的测试）

1. `codex-rs/apply-patch/tests/all.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`
4. `codex-rs/apply-patch/tests/suite/tool.rs`（`test_apply_patch_cli_move_overwrites_existing_destination`）
5. `codex-rs/core/tests/suite/apply_patch_cli.rs`（同语义的核心链路集成测试）

### C. 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/main.rs`
2. `codex-rs/apply-patch/src/standalone_executable.rs`
3. `codex-rs/apply-patch/src/parser.rs`
4. `codex-rs/apply-patch/src/lib.rs`
5. `codex-rs/apply-patch/src/invocation.rs`

### D. 上游工具链与权限链路

1. `codex-rs/core/src/tools/handlers/apply_patch.rs`（verified parse、权限 key 收集、runtime 调用）
2. `codex-rs/core/src/tools/handlers/apply_patch_tests.rs`（move 目标路径纳入审批 key）
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（审批与执行命令构建）
4. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark`（handler 层语法约束）
5. `codex-rs/arg0/src/lib.rs`（`apply_patch`/`--codex-run-as-apply-patch` 分发）

### E. 配置、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
6. `Docs/researches/blueprint_checklist.md`
7. `.ops/generate_daily_research_todo.sh`
8. `Docs/researches/todos_20260320.md`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 核心依赖：

1. `anyhow`、`thiserror`：错误封装与上下文。
2. `similar`：生成 unified diff（在 verified 变更建模中使用）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形式的 apply_patch 调用。
4. 测试依赖 `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`。

### 2) 外部交互

1. 文件系统交互：读取源文件、写目标文件（覆盖）、删除源文件、递归快照读取 expected/actual。
2. 进程交互：场景测试通过子进程运行 `apply_patch` 真正二进制。
3. 标准流交互：成功路径输出 `Success. Updated the following files:` 与 `M <path>`。
4. 构建系统交互：Bazel 通过 `compile_data` 打包 `apply_patch_tool_instructions.md`，避免运行时缺失说明文本。

### 3) 与配置/策略的关系

1. handler 会把 `move_path` 也纳入审批路径集合，避免只批准源路径而遗漏目标路径权限。
2. runtime 会沿用上游审批结果执行 `apply_patch`，防止重复询问。
3. 当前场景不依赖网络，不依赖外部服务，只依赖本地文件系统与进程执行能力。

## 风险、边界与改进建议

### 风险

1. `Move to` 当前实现不是原子 rename，而是“写目标 + 删源”；若删源失败，可能产生部分完成状态。
2. 覆盖语义依赖 `std::fs::write` 行为，若未来策略改为冲突报错，本目录期望值会整体变化。
3. 场景框架主要比较最终文件树，不直接断言退出码/stderr；错误文案回归可能在该层漏检。

### 边界

1. 本目录仅验证“目标文件最终内容”，不覆盖权限错误、目标为目录、只读文件、并发写入冲突。
2. 本目录仅覆盖文本内容，不覆盖权限位、owner、mtime 等元数据。
3. 本目录依赖 `\n` 换行约定；跨平台 CRLF 改写会导致快照不一致（仓库通过 `.gitattributes` 约束 LF）。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 明确写出 `Move to` 目标存在时的覆盖语义，减少调用方歧义。
2. 为 fixtures 框架扩展可选行为断言（如 `exit_code.txt`、`stderr.txt`），补足仅比对文件树的盲区。
3. 新增边界场景：
   - `move_destination_is_directory_fails`
   - `move_destination_readonly_fails`
   - `move_partial_failure_after_dest_write`
4. 如果要提高一致性，可评估临时文件 + 原子替换方案，并把“覆盖/拒绝”设为显式策略。
