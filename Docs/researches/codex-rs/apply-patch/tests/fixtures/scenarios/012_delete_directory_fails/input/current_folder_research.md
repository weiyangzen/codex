# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

该目录是场景 `012_delete_directory_fails` 的输入态基线（pre-state）。其核心职责是确保补丁 `*** Delete File: dir` 命中的对象是“已存在目录”，而不是普通文件或缺失路径。

本目录当前结构：

1. `input/dir/foo.txt`：内容为 `stable`，用于物化目录 `dir` 并验证失败后目录内容保持不变（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`）。

在场景执行中，`tests/suite/scenarios.rs` 会将 `input/` 递归复制到临时目录后再执行 patch（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-48`）。因此该输入目录不是样例数据，而是“删除目录应失败”语义的前置约束。

## 功能点目的

该输入目录支撑的功能点是：验证 `Delete File` 仅允许删除文件，不允许删除目录。具体目的：

1. 明确类型边界：路径存在但类型为目录时，应失败。
2. 保证无副作用：失败后 `dir/foo.txt` 仍存在且内容不变。
3. 与邻近负向用例分工：`007_rejects_missing_file_delete` 覆盖“不存在”，本目录覆盖“存在但类型错误”。
4. 形成跨层回归锚点：fixture 最终态、CLI 错误输出、core verified 错误共同约束同一语义。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与回放

`scenarios/README.md` 定义场景三件套：`input/ + patch.txt + expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。

`test_apply_patch_scenarios()` 的关键流程：

1. 遍历 `fixtures/scenarios/*`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 复制本目录 `input/` 到 `tempdir()`（`codex-rs/apply-patch/tests/suite/scenarios.rs:34-37,107-123`）。
3. 读取 `patch.txt` 并执行 `apply_patch <patch>` 子进程（`codex-rs/apply-patch/tests/suite/scenarios.rs:39-48`）。
4. 使用 `BTreeMap<PathBuf, Entry>` 快照比对临时目录与 `expected/`（`codex-rs/apply-patch/tests/suite/scenarios.rs:50-77`）。

数据结构要点：`Entry::{File(Vec<u8>), Dir}` 既校验目录存在，也校验文件字节内容；本输入目录提供了 `dir` 与 `dir/foo.txt` 两类条目，确保“目录未被误删”可被准确捕获。

### 2) patch 解析与执行

本场景 patch：

```patch
*** Begin Patch
*** Delete File: dir
*** End Patch
```

执行链路：

1. `parse_patch()` 解析到 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:106-183,271-278`）。
2. `apply_hunks_to_files()` 在 Delete 分支调用 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:301-304`）。
3. 当 `path` 为目录时，`remove_file` 返回 I/O 错误；错误被包装为 `Failed to delete file <path>` 并写入 stderr（`codex-rs/apply-patch/src/lib.rs:253-256,301-304`）。
4. CLI 返回非零退出码（`codex-rs/apply-patch/src/standalone_executable.rs:51-58`）。

### 3) core 工具链中的预检差异

core 通过 `maybe_parse_apply_patch_verified()` 先构建“可验证变更”，对 `DeleteFile` 会先 `read_to_string(path)` 读取将被删除文件内容（`codex-rs/apply-patch/src/invocation.rs:132-183`）。

当路径为目录时，错误在 verified 阶段提前抛出，handler 返回 `apply_patch verification failed: ...`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175,241-244`），不会进入 runtime 的 `codex --codex-run-as-apply-patch <patch>` 执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`，`codex-rs/arg0/src/lib.rs:89-107`）。

### 4) 同语义测试与命令

1. fixture 总场景：`cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. CLI 错误断言：`cargo test -p codex-apply-patch --test all test_apply_patch_cli_delete_directory_fails`（`codex-rs/apply-patch/tests/suite/tool.rs:196-205`）
3. core 集成断言：`apply_patch_cli_delete_directory_reports_verification_error`（`codex-rs/core/tests/suite/apply_patch_cli.rs:536-554`）

## 关键代码路径与文件引用

### A. 研究对象与同场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`

### B. 直接调用方（消费 input 目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:107-125`
3. `codex-rs/apply-patch/tests/all.rs:1-3`
4. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`

### C. 被调用方（解析/执行核心）

1. `codex-rs/apply-patch/src/parser.rs:31-39,248-278`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-305`
4. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
5. `codex-rs/apply-patch/src/invocation.rs:132-183`

### D. 上游配置、脚本、文档、运行时

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-11`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/.gitattributes:1`
5. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-258`
6. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-215`
7. `codex-rs/arg0/src/lib.rs:89-107`
8. `.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

1. 依赖层：`anyhow`/`thiserror` 提供错误上下文；`assert_cmd`/`tempfile`/`codex-utils-cargo-bin` 支撑场景与 CLI 测试（`codex-rs/apply-patch/Cargo.toml:18-30`）。
2. 文件系统交互：场景回放会复制 `input/`、读取 `patch.txt`、执行删除并快照目录树（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`）。
3. 进程交互：测试通过 `cargo_bin("apply_patch")` 启动二进制执行真实 patch（`codex-rs/apply-patch/tests/suite/scenarios.rs:45-48`）。
4. 协议交互：`Delete File` 语法不带类型信息，类型约束由 verified/执行层通过真实文件系统行为落实。
5. core 运行时交互：通过审批与 sandbox 机制执行 `--codex-run-as-apply-patch`，并使用最小环境变量集（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-101,200-215`）。

## 风险、边界与改进建议

1. 错误文本分叉风险：裸 CLI 报 `Failed to delete file ...`，core 预检报 `Failed to read ...`；同语义在不同入口输出不一致，增加上层处理成本。
2. 场景框架观测边界：`scenarios.rs` 不断言 exit code/stderr，只看最终态，错误消息回归可能漏检。
3. 覆盖边界有限：本输入目录只覆盖“目录存在且含文件”的情况，未覆盖空目录、符号链接目录、权限拒绝目录等系统差异路径。
4. 改进建议一：在 verified 阶段对 Delete 增加显式“必须是普通文件”的类型检查，并统一错误语义。
5. 改进建议二：为场景框架增加可选 `stderr`/`exit_code` 断言文件，补齐负向行为的可观测性。
6. 改进建议三：新增相邻 fixture（空目录、symlink 目录、带尾斜杠路径）扩展跨平台稳定性验证。
