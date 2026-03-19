# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir`
- 对象类型：测试 fixture 的期望输出目录（DIR）
- 目录当前文件：`name.txt`（内容：`new content`）

## 场景与职责

该目录属于 `apply_patch` 集成场景 `004_move_to_new_directory` 的 `expected` 真值树，职责是定义“文件被更新并移动到新目录后”的**最终目标落点**。

在该场景里：
- 输入文件在 `input/old/name.txt`，原内容为 `old content`。
- patch 声明 `*** Move to: renamed/dir/name.txt`，并把内容改为 `new content`。
- 因此 `expected/renamed/dir/name.txt` 必须存在，且内容必须精确匹配。

该目录不是运行时代码，而是 E2E 断言基准；它和 `expected/old/other.txt` 一起定义完整最终文件系统状态（迁移目标存在、无关文件保留、源文件消失）。

## 功能点目的

该目录所覆盖的功能点是：

1. `Update File + Move to` 组合语义正确。
2. 目标目录原先不存在时，`apply_patch` 需要自动创建父目录并写入目标文件。
3. 迁移后断言最终树，而不是仅断言命令返回值。
4. 无关文件不受影响（通过同场景 `expected/old/other.txt` 间接保证）。

简言之，这个目录是“移动到新目录”能力在 fixture 层的最终证据位点（oracle leaf）。

## 具体技术实现（关键流程/数据结构/协议/命令）

关键流程（从调用到断言）：

1. `tests/suite/scenarios.rs::test_apply_patch_scenarios()` 遍历 `tests/fixtures/scenarios/*`，进入 `004_move_to_new_directory`。
2. `run_apply_patch_scenario()` 复制 `input/` 到临时目录，读取 `patch.txt`，调用二进制 `apply_patch` 执行。
3. `apply_patch` 解析 patch：
   - `parser::parse_one_hunk()` 识别 `*** Update File`。
   - 若下一行是 `*** Move to: ...`，写入 `Hunk::UpdateFile { move_path: Some(PathBuf), ... }`。
4. 执行阶段 `lib.rs::apply_hunks_to_files()`：
   - 先基于 chunk 计算新内容（`derive_new_contents_from_chunks`）。
   - 对 `move_path` 分支执行 `create_dir_all(parent)`、`write(dest, new_contents)`、`remove_file(src)`。
5. 场景测试使用 `snapshot_dir()` 将 `expected/` 与临时目录都转成 `BTreeMap<PathBuf, Entry>`（目录也会记录为 `Entry::Dir`），并用 `assert_eq!` 做全量比较。

关键数据结构：

- `parser::Hunk::UpdateFile { path, move_path: Option<PathBuf>, chunks }`
- `parser::UpdateFileChunk { change_context, old_lines, new_lines, is_end_of_file }`
- `tests/suite/scenarios.rs::Entry`：`File(Vec<u8>) | Dir`
- `snapshot_dir()` 输出 `BTreeMap<PathBuf, Entry>` 用于稳定比较

协议与命令（本场景实际使用）：

```text
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-old content
+new content
*** End Patch
```

测试命令路径：
- 场景测试通过 `codex_utils_cargo_bin::cargo_bin("apply_patch")` 启动可执行文件。

## 关键代码路径与文件引用

场景与 fixture：
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/patch.txt`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/input/old/name.txt`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/renamed/dir/name.txt`
- `codex-rs/apply-patch/tests/fixtures/scenarios/004_move_to_new_directory/expected/old/other.txt`

场景调用与断言：
- `codex-rs/apply-patch/tests/suite/scenarios.rs:11-25`（遍历场景）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:30-63`（复制输入、执行命令、比对 expected）
- `codex-rs/apply-patch/tests/suite/scenarios.rs:71-105`（目录快照）

解析与执行（被调用方）：
- `codex-rs/apply-patch/src/parser.rs:279-333`（解析 Update + Move to）
- `codex-rs/apply-patch/src/lib.rs:306-331`（执行 move_path 分支）
- `codex-rs/apply-patch/src/lib.rs:317-324`（创建目标父目录、写新文件、删原文件）

并行/补充测试：
- `codex-rs/apply-patch/tests/suite/tool.rs:65-82`（CLI 级“移动到新目录”测试）
- `codex-rs/apply-patch/tests/suite/tool.rs:155-175`（目标已存在时覆盖）
- `codex-rs/apply-patch/src/lib.rs:643-672`（库级 move 测试）
- `codex-rs/apply-patch/src/invocation.rs:768-812`（`cd` workdir 下 `move_path` 解析验证）

文档/规范：
- `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`（fixture 结构说明）
- `codex-rs/apply-patch/apply_patch_tool_instructions.md`（patch 语法与 `Move to` 语义）

配置与构建：
- `codex-rs/apply-patch/Cargo.toml`（crate/bin 与依赖）
- `codex-rs/apply-patch/BUILD.bazel`（`apply_patch_tool_instructions.md` 作为 `compile_data`）

## 依赖与外部交互

内部依赖：
- 解析：`parser` 模块（hunk 语义建模）
- 执行：`lib` 模块（文件系统更新）
- 调用解析：`invocation`（shell/heredoc 提取与 cwd 解析）

外部交互：
- 文件系统：`read_to_string`、`write`、`remove_file`、`create_dir_all`、`metadata`
- 进程调用：测试通过 `std::process::Command` 执行 `apply_patch` 二进制
- 临时目录：`tempfile::tempdir()` 用于隔离场景

配置侧信息：
- 无额外运行时配置文件；行为由 patch 文本和当前工作目录决定。
- 构建系统层面依赖 Cargo/Bazel，测试中通过 `codex_utils_cargo_bin::cargo_bin` 获取二进制路径以兼容不同执行环境。

## 风险、边界与改进建议

风险与边界：

1. 场景测试不校验命令退出码与 stdout/stderr（`scenarios.rs` 明确只比最终文件树），因此它聚焦状态正确性，不覆盖输出契约。
2. `move_path` 分支当前语义是“写目标后删除源”；若中间失败，可能出现部分成功状态（仓库已有 `015_failure_after_partial_success_leaves_changes` 覆盖了这类行为趋势）。
3. 本目录只验证单文件迁移落点，不覆盖更复杂冲突（目标为目录、权限错误、跨设备 rename 语义差异等）。

改进建议：

1. 为场景 runner 增加可选“退出码断言模式”（不改变当前默认），让状态断言与行为断言可组合。
2. 新增与本目录同层级的负向场景：例如目标父目录不可写、目标路径为目录，明确错误信息与最终状态。
3. 在 `scenarios/README.md` 增补“目录级 expected 如何表示移动语义”的说明，降低新增场景时的理解成本。
