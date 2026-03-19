# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 当前目录文件：`other.txt`

## 场景与职责

该目录是场景 `004_move_to_new_directory` 的期望结果子目录之一，承担“迁移场景中的未命中文件保持不变”断言职责。

在该场景中，补丁只操作 `old/name.txt -> renamed/dir/name.txt`，并不触及 `old/other.txt`。因此 `expected/old/` 目录保留 `other.txt`，用于证明：

1. 文件迁移不会误删源目录中的其他文件。
2. 文件迁移不会污染同级无关文件内容。
3. 场景最终文件树快照必须同时满足“目标文件迁移成功”和“旁路文件稳定”。

换句话说，`expected/old/other.txt` 不是冗余样本，而是 `Move to` 功能的副作用边界哨兵。

## 功能点目的

围绕本目录，`004_move_to_new_directory` 主要验证以下能力：

1. `*** Move to:` 与 `*** Update File:` 组合执行时，仅影响目标源文件，不影响同目录其他文件。
2. 在目标目录 `renamed/dir` 自动创建并写入新文件后，源目录 `old/` 仍可部分保留（因为仍有 `other.txt`）。
3. 测试框架按目录+文件字节进行全量比对，`expected/old/other.txt` 用于捕获“误删 old 目录”或“误改 unrelated file 内容”的回归。

这让场景 004 不仅是“能 move 成功”，也是“move 的作用域正确”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. `tests/suite/scenarios.rs` 的 `test_apply_patch_scenarios()` 遍历场景目录并执行 `run_apply_patch_scenario()`。
2. `run_apply_patch_scenario()` 把 `input/` 复制到临时目录；此时临时目录含 `old/name.txt` 与 `old/other.txt`。
3. 读取 `patch.txt`，调用 `apply_patch` 子进程执行：
   - `Update File: old/name.txt`
   - `Move to: renamed/dir/name.txt`
   - hunk `old content -> new content`
4. 执行后，测试将 `expected/` 与临时目录分别快照为 `BTreeMap<PathBuf, Entry>` 并 `assert_eq!`。
5. 由于 `expected/old/other.txt` 存在且内容固定，任何“误删/误改 other.txt”都会导致场景失败。

### 2) 数据结构与断言机制

1. 解析层：`parser.rs` 把补丁解析为 `Hunk::UpdateFile { path, move_path, chunks }`，其中 `move_path = Some("renamed/dir/name.txt")`。
2. 执行层：`lib.rs::apply_hunks_to_files()` 在 `UpdateFile + move_path` 分支中：
   - 先计算 `new_contents`，写入目标路径；
   - 再删除源文件 `old/name.txt`；
   - 不会遍历或删除 `old/` 目录内其他文件。
3. 测试快照层：`scenarios.rs::snapshot_dir_recursive()` 使用 `Entry::Dir | Entry::File(Vec<u8>)` 收集目录树，按字节精确比较。

因此本目录中的 `other.txt` 通过“字节级静态断言”锁定副作用边界。

### 3) 协议与命令

场景协议输入（`patch.txt`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch
```

关键命令（研发/回归常用）：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_moves_file_to_new_directory`
3. `bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### 1) 目标目录与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/other.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt`

### 2) 调用方（测试装载与断言）

1. `codex-rs/apply-patch/tests/all.rs`（集成测试入口）
2. `codex-rs/apply-patch/tests/suite/mod.rs`（suite 组织）
3. `codex-rs/apply-patch/tests/suite/scenarios.rs`（fixture 遍历、临时目录执行、快照比对）
4. `codex-rs/apply-patch/tests/suite/tool.rs`（对应 CLI 行为测试 `test_apply_patch_cli_moves_file_to_new_directory`）

### 3) 被调用方（补丁解析与执行）

1. `codex-rs/apply-patch/src/main.rs`
2. `codex-rs/apply-patch/src/standalone_executable.rs`
3. `codex-rs/apply-patch/src/parser.rs`
4. `codex-rs/apply-patch/src/lib.rs`
5. `codex-rs/apply-patch/src/seek_sequence.rs`

### 4) 配置、脚本、文档与跨 crate 上下文

1. `codex-rs/apply-patch/Cargo.toml`（crate/bin 与依赖）
2. `codex-rs/apply-patch/BUILD.bazel`（Bazel 构建入口）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes`（fixtures 强制 LF）
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（fixture 规范）
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md`（协议说明）
6. `codex-rs/core/src/tools/handlers/apply_patch.rs`（工具调用侧校验与审批）
7. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（runtime 执行 `codex --codex-run-as-apply-patch`）
8. `codex-rs/arg0/src/lib.rs`（`apply_patch`/`applypatch` arg0 分发）
9. `.ops/generate_daily_research_todo.sh`（基于 checklist 生成当日 todo）
10. `Docs/researches/blueprint_checklist.md`（研究进度登记）

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 的关键依赖：

1. `anyhow`、`thiserror`：错误传播与上下文封装。
2. `similar`：统一 diff 文本生成（用于 verified 变更信息）。
3. `tree-sitter`、`tree-sitter-bash`：shell/heredoc 形式 `apply_patch` 调用解析。
4. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：测试执行与断言。

### 2) 外部交互

1. 文件系统交互：
   - 读取 `old/name.txt` 与 `old/other.txt`；
   - 创建 `renamed/dir`；
   - 写入 `renamed/dir/name.txt`；
   - 删除 `old/name.txt`；
   - 保留 `old/other.txt`。
2. 子进程交互：fixture 测试通过 `Command::new(cargo_bin("apply_patch"))` 启动可执行程序。
3. 标准流交互：成功输出 `Success. Updated the following files:`，失败输出错误文本。
4. 跨 crate 交互：`core` 层可在执行前调用 `maybe_parse_apply_patch_verified()` 计算变更与权限审批范围。

## 风险、边界与改进建议

### 风险与边界

1. 该目录只验证“无关文件保留”这一边界，不覆盖权限异常、并发写入、磁盘错误等 I/O 异常路径。
2. 场景回放机制只比较最终文件树，不直接断言退出码/stderr；输出协议回归需依赖 `tool.rs`/`cli.rs`。
3. move 语义是“写目标+删源”，非原子事务；在中途失败场景可能留下部分变更（由场景 015 体现）。
4. 当前场景中 `old/` 目录因 `other.txt` 保留而继续存在；未覆盖“源目录因空目录被清理/不清理”的策略决策。

### 改进建议

1. 增补场景：`move_keeps_unrelated_sibling_files_with_multiple_chunks`，验证多 chunk 更新时旁路文件仍稳定。
2. 增补负向场景：目标目录无权限时，断言 `old/other.txt`、`old/name.txt` 的最终状态，明确失败后副作用边界。
3. 为 `scenarios.rs` 增加可选元数据断言（`expected_exit_code`/`stderr_contains`），补齐仅看最终态的盲区。
4. 在协议文档显式标注“`Move to` 不会清理源目录，仅删除源文件本身”，减少调用方误解。
