# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`009_requires_existing_file_for_update` 是 `apply_patch` 场景集中的负向用例，验证语义是：
当 patch 语法合法、`Update File` hunk 也合法时，如果目标文件不存在，工具必须失败并且不产生额外副作用。

该目录夹具由三部分构成：

1. `patch.txt` 指向不存在的 `missing.txt` 并尝试执行 `-old/+new` 替换（`codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/patch.txt:1-6`）。
2. `input/foo.txt` 提供一个不相关稳定文件，模拟“工作目录有其他文件”的常见状态（`.../input/foo.txt:1`）。
3. `expected/foo.txt` 与 input 完全一致，用于断言失败后文件系统不变（`.../expected/foo.txt:1`）。

在测试职责上，该场景承担的是“执行前置条件错误（目标文件缺失）”这一边界，与邻近场景分工不同：

1. `008_rejects_empty_update_hunk` 覆盖“语法层拒绝”（chunk 为空）。
2. `009_requires_existing_file_for_update` 覆盖“执行层拒绝”（读取更新目标失败）。
3. `015_failure_after_partial_success_leaves_changes` 覆盖“多 hunk 部分成功后失败”。

## 功能点目的

本场景不是为了证明“update 能成功”，而是锁定下面三个工程目标：

1. 明确的前置条件：`Update File` 必须作用于已存在且可读的文件。
2. 明确的失败可诊断性：错误文本应包含目标路径和 OS I/O 细节。
3. 失败副作用可预期：本场景下由于第一步读取即失败，输入文件树应保持原样。

这个语义能防止两类高风险行为：

1. 把 `Update File` 误当成“若不存在则新建”的隐式 add。
2. 在路径拼写错误时静默成功，导致模型或调用方认为补丁已生效。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景回放流程（fixture runner）

`test_apply_patch_scenarios()` 会遍历 `fixtures/scenarios` 下每个目录并调用 `run_apply_patch_scenario`（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。

`run_apply_patch_scenario()` 的执行步骤：

1. 将场景 `input/` 复制到临时目录（`.../scenarios.rs:33-37,107-124`）。
2. 读取场景 `patch.txt`（`.../scenarios.rs:39-40`）。
3. 调用 `apply_patch` 可执行文件执行补丁（`.../scenarios.rs:45-48`）。
4. 不检查进程退出码，只比较最终文件树快照（`.../scenarios.rs:42-45,50-60`）。

所以该场景的核心断言是“最终目录状态不变”，而不是 stderr 文案。

### 2) CLI 到执行层的失败链路

入口链路：

1. `src/main.rs` 转发到 `codex_apply_patch::main()`（`codex-rs/apply-patch/src/main.rs:1-2`）。
2. `run_main()` 获取 patch 参数并调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。

核心失败点在 `derive_new_contents_from_chunks()`：

1. `apply_patch()` 先 `parse_patch()`，语法通过后进入 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
2. `apply_hunks_to_files()` 处理 `Hunk::UpdateFile` 时调用 `derive_new_contents_from_chunks(path, chunks)`（`.../lib.rs:306-313`）。
3. `derive_new_contents_from_chunks()` 用 `std::fs::read_to_string(path)` 读取原文件；若不存在，返回
   `IoError { context: "Failed to read file to update <path>", source: os error }`（`.../lib.rs:348-359`）。
4. `apply_hunks()` 将该错误写入 stderr 并返回失败（`.../lib.rs:253-265`）。

### 3) 数据结构与协议约束

关键类型：

1. `Hunk::UpdateFile { path, move_path, chunks }`（`codex-rs/apply-patch/src/parser.rs:67-76`）。
2. `ApplyPatchError::IoError(IoError { context, source })`（`codex-rs/apply-patch/src/lib.rs:35-74`）。

语法层（Lark）只规定 `update_hunk` 形状，不保证文件存在：

- `update_hunk: "*** Update File: " filename LF change_move? change?`（`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:8`）。

因此“文件是否存在”由执行层 I/O 校验承担，而非 parser 承担。

### 4) 上层（core）对该错误的传播

在 `core` 中，`ApplyPatchHandler` 会先调用 `maybe_parse_apply_patch_verified` 进行二次验证与变更提取（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。

对于不存在文件的 update：

1. `maybe_parse_apply_patch_verified()` 在构建 update 变更时会调用 `unified_diff_from_chunks`，内部也会走读取源文件逻辑（`codex-rs/apply-patch/src/invocation.rs:184-194`）。
2. 一旦失败，返回 `MaybeApplyPatchVerified::CorrectnessError`（`.../invocation.rs:192-194,214`）。
3. handler 将其包装为 `apply_patch verification failed: ...` 反馈给模型（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-245`）。

已通过验证且需执行时，runtime 用 `codex --codex-run-as-apply-patch` 自调用执行（`codex-rs/core/src/tools/runtimes/apply_patch.rs:69-94`，`codex-rs/arg0/src/lib.rs:90-107`）。

### 5) 复现与验证命令

1. 只跑场景回放：
   `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. 精确验证 stderr 用例：
   `cargo test -p codex-apply-patch --test all test_apply_patch_cli_requires_existing_file_for_update`

`tool.rs` 已断言错误文本：
`Failed to read file to update missing.txt: No such file or directory (os error 2)`（`codex-rs/apply-patch/tests/suite/tool.rs:140-149`）。

## 关键代码路径与文件引用

### 1) 目标夹具目录

1. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/patch.txt:1-6`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/input/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/009_requires_existing_file_for_update/expected/foo.txt:1`

### 2) 直接调用方（测试）

1. `codex-rs/apply-patch/tests/all.rs:1-3`
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
4. `codex-rs/apply-patch/tests/suite/tool.rs:140-149`

### 3) 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`
2. `codex-rs/apply-patch/src/lib.rs:183-213`
3. `codex-rs/apply-patch/src/lib.rs:279-339`
4. `codex-rs/apply-patch/src/lib.rs:348-359`
5. `codex-rs/apply-patch/src/parser.rs:248-333`

### 4) 上下文依赖（调用链、协议、构建、文档、脚本）

1. 上层 handler：`codex-rs/core/src/tools/handlers/apply_patch.rs:170-245`
2. 上层 runtime：`codex-rs/core/src/tools/runtimes/apply_patch.rs:35-102`
3. arg0 分发：`codex-rs/arg0/src/lib.rs:85-107`
4. 场景规范文档：`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`
5. apply_patch 协议文档：`codex-rs/apply-patch/apply_patch_tool_instructions.md:1-76`
6. Lark 协议文件：`codex-rs/core/src/tools/handlers/tool_apply_patch.lark:1-19`
7. crate/build 配置：`codex-rs/apply-patch/Cargo.toml:1-30`、`codex-rs/apply-patch/BUILD.bazel:1-8`
8. 研究任务脚本：`.ops/research_guard.sh:190-233`、`.ops/generate_daily_research_todo.sh:1-42`

## 依赖与外部交互

### 1) 代码依赖

`codex-apply-patch` 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`；
测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:18-30`）。

### 2) 外部交互

1. 文件系统：场景回放复制 `input`、读取 `patch`、快照对比 `expected`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-53`）。
2. 子进程：测试通过 `cargo_bin("apply_patch")` 拉起二进制（`.../scenarios.rs:45-48`）。
3. 标准流：失败信息写 stderr；成功汇总写 stdout（`codex-rs/apply-patch/src/lib.rs:249-256`）。
4. 平台差异：本错误文本携带 OS errno，Linux/macOS 文案不同，`tool.rs` 当前按 Unix 文案断言并在 Windows 平台禁测（`codex-rs/apply-patch/tests/suite/mod.rs:3-4`）。

### 3) 与上层系统的交互

1. `core` 中该错误可能在“验证阶段”就被阻断，不一定进入 runtime 执行（`codex-rs/core/src/tools/handlers/apply_patch.rs:174-245`）。
2. 如果进入 runtime，则以空环境执行 `codex --codex-run-as-apply-patch`，降低环境泄漏与不确定性（`codex-rs/core/src/tools/runtimes/apply_patch.rs:96-100`）。

## 风险、边界与改进建议

### 风险与边界

1. `scenarios.rs` 不校验退出码/stderr，仅校验最终文件树；错误文案回归无法被该层发现（`codex-rs/apply-patch/tests/suite/scenarios.rs:42-45`）。
2. `tool.rs` 错误文本包含完整 OS 文案，跨平台可移植性差；目前通过 `#[cfg(not(target_os = "windows"))]` 规避（`codex-rs/apply-patch/tests/suite/mod.rs:3-4`）。
3. 本场景只覆盖“单 update 文件不存在”，未覆盖“move_path 目标存在/源不存在”等复合路径边界。
4. 该场景验证的是“无副作用”，但无法区分“完全未执行”与“执行后回滚”，仅靠最终状态推断。

### 改进建议

1. 给场景框架增加可选元数据（如 `exit_code.txt`、`stderr_contains.txt`），让负向场景同时验证状态与诊断。
2. 在 `tool.rs` 中用“稳定前缀 + 错误类型”断言替代全句 OS 文案，降低平台差异噪音。
3. 新增 fixture：`Update File + Move to` 且源文件缺失，明确 rename-update 的缺失文件行为。
4. 在 `core/tests/suite/apply_patch_cli.rs` 增补“verification failed: Failed to read file to update ...”端到端断言，确保错误跨 crate 传播稳定。
