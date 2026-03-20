# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 对应场景：`010_move_overwrites_existing_destination`

## 场景与职责

`input/old` 是场景 `010_move_overwrites_existing_destination` 的输入子目录，包含两类文件角色：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`，内容 `from`，是补丁 `*** Update File: old/name.txt` 的源文件。
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt:1`，内容 `unrelated file`，是“同目录旁路文件”，用于验证 move/update 不会误改无关文件。

该目录本身不包含执行逻辑，职责是作为 fixture 的“初始文件系统快照”供 `tests/suite/scenarios.rs` 消费：

1. `run_apply_patch_scenario()` 先把场景 `input/` 递归复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:30-37,107-124`）。
2. 在临时目录运行 `apply_patch` 执行 `patch.txt`（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
3. 把执行后目录与 `expected/` 做完整结构+字节快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60,65-105`）。

因此，`input/old` 的职责是对“源文件应被移动且改写、旁路文件应保持不变”提供可重复输入基线。

## 功能点目的

本目录服务的核心功能点是：`Move to` 在目标已存在时进行覆盖更新，同时保证影响范围最小。

对应补丁（`codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

配合 `input/old`，该场景要锁定以下行为：

1. `old/name.txt` 必须作为 Update+Move 的真实输入源存在。
2. 更新后的内容应落到 `renamed/dir/name.txt`（目标原本存在 `existing`，会被覆盖）。
3. 源路径 `old/name.txt` 执行后应删除。
4. `old/other.txt` 不在补丁命中路径内，应在最终态保持不变（`expected/old/other.txt:1` 仍是 `unrelated file`）。

这也是为什么同语义在程序化测试中还有显式断言：`test_apply_patch_cli_move_overwrites_existing_destination`（`codex-rs/apply-patch/tests/suite/tool.rs:155-174`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 到执行的关键流程

1. `test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:10-25`）。
2. 命中 `010_move_overwrites_existing_destination` 后，`copy_dir_recursive()` 将 `input/` 复制到临时目录，复制时跟随 metadata，兼容 Buck2 下可能存在的 symlink tree（`codex-rs/apply-patch/tests/suite/scenarios.rs:92-95,113-124`）。
3. 子进程执行 `apply_patch <patch>`；该场景框架不检查退出码，只以最终文件系统状态为真值（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-48`）。
4. `snapshot_dir()` 生成 `BTreeMap<PathBuf, Entry>`（`Entry::Dir | Entry::File(Vec<u8>)`）并与 `expected/` 比较（`codex-rs/apply-patch/tests/suite/scenarios.rs:65-77`）。

### 2) 协议与数据结构

1. 语法层面 `Update` 可选 `Move to`：
   - Lark：`update_hunk: ... change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8,13`）。
   - 工具文档：`MoveTo := "*** Move to: " newPath`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:47-49`）。
2. 解析后落到 `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:68-75`）。
3. `parse_one_hunk()` 通过 `MOVE_TO_MARKER` 读取可选目标路径（`codex-rs/apply-patch/src/parser.rs:285-330`）。

### 3) 执行实现（覆盖行为发生点）

执行入口是 `standalone_executable::run_main()`：

1. 支持从 argv 或 stdin 读取 PATCH，限制“仅一个参数”避免歧义（`codex-rs/apply-patch/src/standalone_executable.rs:11-47`）。
2. 调用 `apply_patch()`，其流程是 `parse_patch()` -> `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。

真正与本目录相关的覆盖语义在 `apply_hunks_to_files()`：

1. `derive_new_contents_from_chunks(path, chunks)` 基于原文件和 hunk 算出新内容（`codex-rs/apply-patch/src/lib.rs:311-313,348-380`）。
2. 对 `move_path` 分支：先 `create_dir_all(dest.parent)`，再 `write(dest, new_contents)`，最后 `remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:313-325`）。
3. 因为使用 `std::fs::write`，已存在目标文件会被覆盖；这正是 `input/old/name.txt` + `input/renamed/dir/name.txt` 共同构造要验证的行为。
4. 成功输出摘要为 `M <dest>`（`codex-rs/apply-patch/src/lib.rs:537-551`，对应 `tool.rs` 断言 `M renamed/dir/name.txt`）。

### 4) 上下文调用方与被调用方

1. 上游工具链先用 `maybe_parse_apply_patch_verified()` 做语义验证并构造变更集（`codex-rs/apply-patch/src/invocation.rs:132-217`）。
2. `ApplyPatchHandler` 把 patch 解析出的源/目标路径都纳入权限求解（`codex-rs/core/src/tools/handlers/apply_patch.rs:46-64,170-203`）。
3. 安全判定对 `Update` 会同时校验 `path` 与 `move_path` 的可写性（`codex-rs/core/src/safety.rs:159-175`）。
4. runtime 最终执行 `codex --codex-run-as-apply-patch <patch>`（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`），由 arg0 分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:90-107`）。

### 5) 可复现命令

1. 场景全集回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 定向语义测试：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. 研究 TODO 更新：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### 目标目录与场景数据

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt:1`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt:1`

### 测试入口与场景执行

1. `codex-rs/apply-patch/tests/all.rs:1-2`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:10-63`
4. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`
5. `codex-rs/apply-patch/tests/suite/tool.rs:155-174`

### 解析/执行核心

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-474`
5. `codex-rs/apply-patch/src/lib.rs:537-551`
6. `codex-rs/apply-patch/src/parser.rs:31-39`
7. `codex-rs/apply-patch/src/parser.rs:68-84`
8. `codex-rs/apply-patch/src/parser.rs:248-333`
9. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 配置、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md:40-50,65-75`
6. `codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
7. `.ops/generate_daily_research_todo.sh:4-41`
8. `Docs/researches/blueprint_checklist.md:111`

## 依赖与外部交互

### 1) 编译与运行依赖

`codex-apply-patch` 依赖（`codex-rs/apply-patch/Cargo.toml:18-30`）：

1. `anyhow` / `thiserror`：错误建模与上下文。
2. `similar`：在 verified 场景生成 unified diff。
3. `tree-sitter` / `tree-sitter-bash`：解析 shell 形式的 apply_patch 调用。
4. 测试依赖 `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`。

### 2) 外部交互面

1. 文件系统：读取 `input/old` 文件、写目的文件、删除源文件、快照比对。
2. 子进程：测试通过 `cargo_bin("apply_patch")` 启动独立二进制（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
3. 标准流：成功摘要输出到 stdout，错误输出到 stderr（`codex-rs/apply-patch/src/lib.rs:247-255,537-551`）。

### 3) 与上层系统交互

1. Handler 在执行前二次验证 patch（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. 安全策略对 move 源与目标双路径校验（`codex-rs/core/src/safety.rs:166-175`）。
3. runtime 以最小环境执行，避免环境泄漏（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-99`）。

## 风险、边界与改进建议

### 风险

1. move 当前实现是“写目标 -> 删源”两步，不是原子事务；若删源失败可能出现源/目标同时存在的部分成功状态。
2. 目标覆盖行为是实现事实（`std::fs::write(dest, ...)`），但工具文档未明确“冲突时覆盖”策略，存在使用方误判风险。
3. 场景框架默认只看最终文件树，不检查 exit code/stderr，可能掩盖错误信息层面的回归。

### 边界

1. `input/old` 仅承担 fixture 输入，不直接承载业务逻辑。
2. 本场景聚焦“已有目标文件的 move 覆盖”，未覆盖权限不足、目标为目录、跨设备 rename 语义等异常边界。
3. 旁路文件仅验证单层同目录样本（`old/other.txt`），对更复杂目录树误伤保护依赖其他场景补充。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增加“Move to 目标存在时默认覆盖”的显式说明。
2. 为 `tests/suite/scenarios.rs` 增加可选元数据断言（如 `exit_code.txt`、`stderr_contains.txt`），补齐行为观测维度。
3. 增加负向场景：`move_destination_is_directory_fails`、`move_source_remove_fails_partial_state`，把异常路径固定为回归测试。
4. 若后续要求更强一致性，可评估“临时文件 + 原子替换”策略并通过独立场景锁定新契约。
