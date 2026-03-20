# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`

## 场景与职责

`012_delete_directory_fails` 是 `apply_patch` fixtures 中专门验证“`Delete File` 指向目录时必须失败”的负向场景。它不是语法测试，而是文件类型约束测试：删除操作只允许普通文件，不允许目录。

本目录由三部分组成：

1. `patch.txt`：仅包含 `*** Delete File: dir`（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`）。
2. `input/dir/foo.txt`：建立目录 `dir` 及内容文件，保证目标路径确实是目录而非不存在路径（`.../input/dir/foo.txt:1`）。
3. `expected/dir/foo.txt`：与 `input` 一致，表达“补丁失败后文件树不应变化”（`.../expected/dir/foo.txt:1`）。

该场景在测试矩阵中承担的职责：

1. 补齐删除类失败分支：`007_rejects_missing_file_delete` 覆盖“目标不存在”，`012` 覆盖“目标类型错误（目录）”。
2. 保证失败不产生副作用：fixture 比较最终目录快照，确保 `dir/foo.txt` 保持稳定。
3. 与代码驱动测试互补：fixture 关注最终态，`tests/suite/tool.rs` 关注 stderr 文案和退出状态。

## 功能点目的

该场景要锁定的行为契约是：

1. `*** Delete File:` 的语义是删除文件，不是删除目录。
2. 当路径存在但类型为目录时，应返回失败，而不是递归删除或静默成功。
3. 失败后不应修改工作目录其它内容。
4. 在 CLI 直接调用与 core 集成调用中，均应阻止该变更，只是失败阶段不同（执行期 vs 预检期）。

对应的回归价值：

1. 防止未来把 `remove_file` 误改为目录删除能力（如 `remove_dir_all`）导致危险行为扩张。
2. 防止“路径存在即删除成功”的宽松逻辑误伤目录结构。
3. 防止负向路径引入部分写入副作用。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 场景协议与输入

fixture 协议来源于 `scenarios/README.md`：每个场景固定为 `input/ + patch.txt + expected/` 三件套（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。

本场景 patch 为：

```patch
*** Begin Patch
*** Delete File: dir
*** End Patch
```

`parser` 解析路径：

1. `parse_patch()` 校验 Begin/End 包裹并迭代 hunk（`codex-rs/apply-patch/src/parser.rs:106-183`）。
2. `parse_one_hunk()` 命中 `DELETE_FILE_MARKER` 分支并构建 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:34`, `271-278`）。

### 2) fixture 回放执行流程（调用方）

`tests/suite/scenarios.rs` 的统一流程：

1. 扫描 `tests/fixtures/scenarios/*` 目录（`codex-rs/apply-patch/tests/suite/scenarios.rs:11-24`）。
2. 将场景 `input/` 复制到 `tempdir()`（`.../scenarios.rs:33-37`, `107-125`）。
3. 读取 `patch.txt` 并运行 `apply_patch <patch>` 子进程（`.../scenarios.rs:39-48`）。
4. 不断言 exit status/stderr，仅比较最终文件树快照（`.../scenarios.rs:42-45`, `50-60`）。

因此 `012` 在 fixture 层证明的是“目录未被删、状态不变”，不是错误文案文本。

### 3) CLI 直接执行链路（被调用方）

1. `apply_patch` 二进制入口读取参数或 stdin，调用 `crate::apply_patch`（`codex-rs/apply-patch/src/standalone_executable.rs:11-58`）。
2. `apply_patch()` 先 parse，再进入 `apply_hunks()`（`codex-rs/apply-patch/src/lib.rs:183-213`）。
3. `apply_hunks_to_files()` 在 `Hunk::DeleteFile` 分支执行 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:279-305`）。
4. 目标是目录时 `remove_file` 返回 I/O 错误，经 `with_context` 包装为 `Failed to delete file dir`，`apply_hunks()` 将错误写到 stderr 并返回失败（`codex-rs/apply-patch/src/lib.rs:253-256`, `301-304`）。

代码驱动验证见：

- `test_apply_patch_cli_delete_directory_fails()` 断言 `.failure()` 且 stderr 为 `Failed to delete file dir`（`codex-rs/apply-patch/tests/suite/tool.rs:196-205`）。

### 4) core 集成链路下的差异（预检先失败）

当补丁经 core 的 `apply_patch` handler 进入系统时，先做 verified 解析：

1. `apply_patch` handler 调用 `maybe_parse_apply_patch_verified`（`codex-rs/core/src/tools/handlers/apply_patch.rs:170-175`）。
2. verified 对 `Hunk::DeleteFile` 会先 `read_to_string(path)` 收集旧内容（用于审计/展示），目录路径在这里就会失败并返回 `Failed to read ...`（`codex-rs/apply-patch/src/invocation.rs:170-183`）。
3. handler 将其包装为 `apply_patch verification failed: ...` 返回模型侧（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`）。
4. 因为已在 verified 阶段失败，runtime 不会真正执行 `codex --codex-run-as-apply-patch` 命令（runtime命令构造见 `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`，arg0 分发见 `codex-rs/arg0/src/lib.rs:89-107`）。

core 对应测试：

- `apply_patch_cli_delete_directory_reports_verification_error()` 断言输出包含 `apply_patch verification failed` 和 `Failed to read`（`codex-rs/core/tests/suite/apply_patch_cli.rs:536-554`）。

结论：

1. 裸 CLI：执行期失败（`remove_file` 时报错）。
2. core tool 流：预检期失败（`read_to_string` 时报错）。

## 关键代码路径与文件引用

### A. 目标目录（研究对象）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`

### B. 直接调用方（消费该 fixture）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`（批量遍历并回放场景）
2. `codex-rs/apply-patch/tests/suite/mod.rs:1-4`
3. `codex-rs/apply-patch/tests/all.rs:1-3`

### C. 同语义测试（错误文案与退出路径）

1. `codex-rs/apply-patch/tests/suite/tool.rs:196-205`（CLI 直跑删除目录失败）
2. `codex-rs/core/tests/suite/apply_patch_cli.rs:536-554`（core verified 失败）

### D. 被调用方（解析与执行核心）

1. `codex-rs/apply-patch/src/parser.rs:31-39`, `248-278`（Delete hunk 解析）
2. `codex-rs/apply-patch/src/lib.rs:183-213`（apply_patch 主流程）
3. `codex-rs/apply-patch/src/lib.rs:279-305`（Delete 分支的 `remove_file`）
4. `codex-rs/apply-patch/src/lib.rs:253-264`（错误输出到 stderr）
5. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`（CLI 参数与退出码）
6. `codex-rs/apply-patch/src/invocation.rs:132-183`（verified 构建与 Delete 预读）

### E. 上下文配置、构建、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`（crate/bin 与测试依赖）
2. `codex-rs/apply-patch/BUILD.bazel:1-10`（Bazel 构建入口）
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-18`（fixture 协议）
4. `.ops/generate_daily_research_todo.sh:1-42`（基于 checklist 生成当日 todo）
5. `Docs/researches/blueprint_checklist.md:117`（本次勾选目标）

## 依赖与外部交互

### 1) 依赖层

`codex-apply-patch` 本场景相关依赖：

1. 运行依赖：`anyhow`、`thiserror`、`similar`、`tree-sitter`、`tree-sitter-bash`（`codex-rs/apply-patch/Cargo.toml:18-23`）。
2. 测试依赖：`assert_cmd`、`tempfile`、`pretty_assertions`、`codex-utils-cargo-bin`（`codex-rs/apply-patch/Cargo.toml:25-30`）。

### 2) 文件系统/进程交互

1. fixture 回放阶段：复制目录、读取 patch、启动子进程、快照目录树（`tests/suite/scenarios.rs`）。
2. CLI 执行阶段：针对 Delete 调用 `std::fs::remove_file`；目录输入触发 OS I/O 错误。
3. core 流程：先读取要删路径内容用于 verified 变更建模；目录输入在预检时失败，阻止后续执行。

### 3) 协议与命令交互

1. 协议层使用 `*** Delete File: <path>`，不区分文件/目录类型；类型约束由执行与预检逻辑承担。
2. runtime 若进入执行，会构造 `codex --codex-run-as-apply-patch <patch>`，由 arg0 分发到 apply_patch（`core/src/tools/runtimes/apply_patch.rs:69-102`，`arg0/src/lib.rs:89-107`）。

## 风险、边界与改进建议

### 风险与边界

1. 两条调用链的错误文案不一致：
   - 裸 CLI：`Failed to delete file dir`。
   - core 集成：`apply_patch verification failed: Failed to read ...`。
   这会增加上层统一错误处理成本。

2. fixture runner 只比目录最终态，不校验退出码与 stderr；若未来错误文案退化，fixture 层无法发现（`tests/suite/scenarios.rs:42-48`）。

3. `Delete File` 对“目录、符号链接目录、权限受限路径”的边界差异未在本场景细分。

4. 当前语义是“失败即停止当前 hunk”，但多 hunk 时仍可能出现前序成功后续失败的非事务状态（由 `015_failure_after_partial_success_leaves_changes` 证明）。

### 改进建议

1. 在 verified 层对 Delete 增加显式类型检查并统一错误文本，例如返回 `target is a directory, expected file`，减少入口差异。

2. 给 scenarios 框架增加可选断言文件（如 `stderr_contains.txt` / `exit_code.txt`），让负向场景同时校验状态与错误通道。

3. 增加相邻场景：
   - `delete_symlink_to_directory_behavior`
   - `delete_readonly_file_permission_denied`
   - `delete_directory_with_trailing_slash`
   以覆盖不同平台 I/O 细节。

4. 在 `apply_patch_tool_instructions.md` 或测试文档中明确：`Delete File` 仅面向文件，目录删除不受支持。
