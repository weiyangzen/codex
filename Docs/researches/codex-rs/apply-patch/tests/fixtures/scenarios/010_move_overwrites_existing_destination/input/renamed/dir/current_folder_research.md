# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 对应场景：`010_move_overwrites_existing_destination`

## 场景与职责

该目录是 `010_move_overwrites_existing_destination` 场景输入态中的最末级目标目录，当前只包含一个文件：

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`，内容为 `existing`。

它不是补丁里的“更新源文件”，而是 `*** Move to: renamed/dir/name.txt` 的预置目标位置（`codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:3`）。因此其核心职责是固定“目标已存在”的前置条件，验证移动更新是否会覆盖既有目标内容。

在测试链路里，该目录被按 fixture 三件套消费：

1. `input/` 由 `copy_dir_recursive` 复制到临时目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37,107-124`）。
2. 同场景 `patch.txt` 被作为 `apply_patch` 参数执行（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
3. 执行后与 `expected/` 做目录+字节快照比对（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-60,65-105`）。

## 功能点目的

本目录服务的功能点是“`Update File + Move to` 在目标文件已存在时的覆盖语义”，具体目的：

1. 验证 destination 预存在时补丁仍可成功应用。
2. 验证 `existing` 会被补丁产物 `new` 覆盖（对应 `expected/renamed/dir/name.txt:1`）。
3. 验证源文件 `old/name.txt` 被删除（通过 expected 快照缺失该路径约束）。
4. 验证旁路文件 `old/other.txt` 不被误改（`expected/old/other.txt:1`）。

该目录对回归价值在于补足 `004_move_to_new_directory` 场景（目标不存在）未覆盖的分支，即“目标已存在的移动覆盖”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议输入与语法

本场景补丁如下（`patch.txt:1-7`）：

```patch
*** Begin Patch
*** Update File: old/name.txt
*** Move to: renamed/dir/name.txt
@@
-from
+new
*** End Patch
```

语法层允许 `update_hunk` 携带可选 `change_move`：

1. Lark 规范：`update_hunk: "*** Update File: " ... change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8-14`）。
2. apply-patch 文档：`UpdateFile := ... [ MoveTo ] { Hunk }`（`codex-rs/apply-patch/apply_patch_tool_instructions.md:47-50`）。
3. parser 常量：`MOVE_TO_MARKER`（`codex-rs/apply-patch/src/parser.rs:36`）。

### 2) 解析与变更建模

1. CLI 入口 `run_main()` 读取 patch 参数并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch()` 先 `parse_patch()`（`codex-rs/apply-patch/src/lib.rs:183-210`）。
3. `parse_one_hunk()` 在 `Update File` 分支读取 `*** Move to:`，产出：
   - `Hunk::UpdateFile { path, move_path: Some(...), chunks }`（`codex-rs/apply-patch/src/parser.rs:279-329`）。
4. 在 core handler 场景中，`maybe_parse_apply_patch_verified()` 会将相对 `move_path` 解析到 `effective_cwd` 绝对路径并放入 `ApplyPatchFileChange::Update`（`codex-rs/apply-patch/src/invocation.rs:152-203`）。

### 3) 执行层覆盖语义（本目录核心）

`apply_hunks_to_files()` 的 `UpdateFile + move_path` 分支（`codex-rs/apply-patch/src/lib.rs:306-331`）：

1. 先从源路径 `old/name.txt` 计算 `new_contents`（`derive_new_contents_from_chunks`，`lib.rs:348-380`）。
2. 确保目标父目录存在：`create_dir_all(dest.parent())`（`lib.rs:314-320`）。
3. 写目标：`std::fs::write(dest, new_contents)`（`lib.rs:321-322`）。
4. 删源：`std::fs::remove_file(path)`（`lib.rs:323-324`）。
5. 结果汇总将目标路径记为 `modified`，摘要输出 `M <dest>`（`lib.rs:325,537-551`）。

由于第 3 步采用 `std::fs::write`，目标文件已存在时会直接被覆写，这正是本目录 `name.txt` 初始值设置为 `existing` 的测试意图。

### 4) 调用方与校验路径

1. fixture 驱动：`test_apply_patch_scenarios()` 统一遍历所有场景目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 程序化断言：`test_apply_patch_cli_move_overwrites_existing_destination()` 直接构造已有 destination，断言覆盖与删源（`codex-rs/apply-patch/tests/suite/tool.rs:155-173`）。
3. core 端到端断言：`apply_patch_cli_move_overwrites_existing_destination` 覆盖不同模型输出形态下同语义（`codex-rs/core/tests/suite/apply_patch_cli.rs:247-275`）。

### 5) 相关命令

1. 场景总回放：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 定向覆盖语义：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_move_overwrites_existing_destination`
3. core 端验证：`cargo test -p codex-core --test suite apply_patch_cli_move_overwrites_existing_destination`

## 关键代码路径与文件引用

### 目标目录与场景文件

1. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/renamed/dir/name.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/patch.txt:1-7`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/name.txt:1`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/input/old/other.txt:1`
5. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/renamed/dir/name.txt:1`
6. `codex-rs/apply-patch/tests/fixtures/scenarios/010_move_overwrites_existing_destination/expected/old/other.txt:1`

### 调用方

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/tool.rs:155-173`
3. `codex-rs/core/tests/suite/apply_patch_cli.rs:247-275`

### 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-380`
5. `codex-rs/apply-patch/src/parser.rs:31-39`
6. `codex-rs/apply-patch/src/parser.rs:279-333`
7. `codex-rs/apply-patch/src/invocation.rs:132-217`

### 配置/文档/脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-50`
6. `.ops/generate_daily_research_todo.sh:1-42`
7. `Docs/researches/blueprint_checklist.md:113`

## 依赖与外部交互

### 1) 依赖

`codex-apply-patch` 关键依赖（`Cargo.toml:18-30`）：

1. `anyhow`、`thiserror`：错误聚合与上下文。
2. `similar`：生成 unified diff（verified 流程）。
3. `tree-sitter`、`tree-sitter-bash`：解析 shell/heredoc 形态 apply_patch 调用。
4. `assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`：集成测试支持。

### 2) 与上游模块交互

1. `ApplyPatchHandler` 在执行前做 verified parse，并抽取源/目标路径用于权限申请（`codex-rs/core/src/tools/handlers/apply_patch.rs:46-64,170-179`）。
2. `safety` 对 `Update` 同时校验 `path` 与 `move_path` 写权限（`codex-rs/core/src/safety.rs:159-175`）。
3. runtime 构造 `codex --codex-run-as-apply-patch <patch>` 命令并以最小环境执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-101,200-215`）。
4. `arg0` 识别 `--codex-run-as-apply-patch` 并分发到 `codex_apply_patch::apply_patch`（`codex-rs/arg0/src/lib.rs:89-107`）。

### 3) 文件系统与进程交互

1. fixture 回放会复制 `input` 到临时目录并运行子进程 `apply_patch`（`tests/suite/scenarios.rs:30-48`）。
2. 执行时存在读源、写目标、删源、建目录等文件系统操作（`src/lib.rs:313-324,348-360`）。
3. 成功摘要写 stdout，失败写 stderr（`src/lib.rs:247-255,537-551`）。

## 风险、边界与改进建议

### 风险

1. `Move to` 执行为“写目标 + 删源”，非原子；若删源失败会出现部分成功状态（`src/lib.rs:321-324`）。
2. 目标覆盖语义当前依赖 `std::fs::write` 的默认行为，若未来要改为冲突拒绝，需要同步调整 fixtures 与上层预期。
3. 场景框架以最终文件树为主，不直接断言 stderr/exit code（`tests/suite/scenarios.rs:42-45`），错误文案回归依赖其他测试文件。

### 边界

1. 本目录只覆盖“目标是已存在普通文件”这一分支，不覆盖“目标是目录”“目标只读”“权限不足”等异常。
2. 不覆盖元数据（权限位/mtime/owner）变更，仅覆盖路径与文件字节内容。
3. 不覆盖并发补丁竞争或跨文件系统语义差异。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 增补“`Move to` 目标已存在时当前实现按覆盖处理”的显式说明，减少语义歧义。
2. 增加负向 fixtures：`move_destination_is_directory_fails`、`move_destination_readonly_fails`、`move_remove_source_failure_partial_state`。
3. 给场景框架增加可选行为断言文件（如 `stderr_contains.txt`、`exit_code.txt`），补齐“只看最终文件树”的观测盲区。
