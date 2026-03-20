# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`012_delete_directory_fails`

## 场景与职责

该目录是场景 `012_delete_directory_fails` 的“最终文件系统真值（expected oracle）”。

此场景输入补丁为：

```patch
*** Begin Patch
*** Delete File: dir
*** End Patch
```

其中 `dir` 在输入态是一个目录（且包含 `foo.txt`）。因此该目录的职责不是表达“删除成功后状态”，而是表达“删除目录失败后，文件树保持不变”的基准。

该目录在场景中的角色分工：

1. `input/dir/foo.txt`：构造目标路径 `dir` 为目录这一前置条件。
2. `patch.txt`：触发 `Delete File` 操作，目标是目录路径。
3. `expected/dir/foo.txt`：声明失败后仍应保留目录与文件内容（`stable`）。

结论：`expected/` 目录承担“失败无副作用”的断言职责，是该负向场景的核心证据。

## 功能点目的

该目录对应功能点的目的可以归纳为 4 条：

1. 约束操作语义：`*** Delete File:` 仅允许删除文件，不允许删除目录。
2. 防止危险扩张：防止实现被误改成递归删目录（例如误用 `remove_dir_all`）。
3. 锁定失败副作用边界：失败发生后，目录树和文件内容不得改变。
4. 与相邻场景分工：
   - `007_rejects_missing_file_delete` 覆盖“目标不存在”；
   - `012_delete_directory_fails` 覆盖“目标存在但类型错误（目录）”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) fixture 协议与数据组织

`codex-rs/apply-patch/tests/fixtures/scenarios/README.md` 定义场景三件套：`input/`、`patch.txt`、`expected/`。

`expected/` 在该协议中的含义是“最终态目录快照来源”，会被测试框架递归读取并与实际执行结果做精确对比。

### 2) patch 解析到 Hunk

在 `parser.rs` 中：

1. `parse_patch()` 校验 `*** Begin Patch` / `*** End Patch` 边界并循环解析 hunk（`src/parser.rs:106-183`）。
2. `parse_one_hunk()` 命中 `DELETE_FILE_MARKER` 分支，得到 `Hunk::DeleteFile { path: "dir" }`（`src/parser.rs:34`, `src/parser.rs:271-278`）。

解析阶段仅构建语义结构，不做“路径是文件还是目录”的类型校验。

### 3) CLI 执行链路中的失败点

在 `lib.rs` 执行阶段：

1. `apply_patch()`：parse 后进入 `apply_hunks()`（`src/lib.rs:183-213`）。
2. `apply_hunks_to_files()`：`Hunk::DeleteFile` 分支调用 `std::fs::remove_file(path)`（`src/lib.rs:301-305`）。
3. 当目标是目录时，`remove_file` 触发 I/O 错误；错误被包装为上下文 `Failed to delete file dir`（`src/lib.rs:302-303`）。
4. `apply_hunks()` 将错误写入 stderr 并返回失败（`src/lib.rs:253-256`）。

因此在纯 `apply_patch` CLI 路径里，失败发生在“执行删除操作”时。

### 4) fixture runner 如何消费 `expected/`

`tests/suite/scenarios.rs` 关键流程：

1. 扫描 `tests/fixtures/scenarios/*` 并逐目录执行（`tests/suite/scenarios.rs:11-24`）。
2. 拷贝 `input/` 到临时目录（`tests/suite/scenarios.rs:33-37`, `107-125`）。
3. 调用二进制 `apply_patch` 执行 `patch.txt`（`tests/suite/scenarios.rs:39-48`）。
4. 将临时目录与 `expected/` 分别快照为 `BTreeMap<PathBuf, Entry>`（`Entry::Dir | Entry::File(Vec<u8>)`），然后 `assert_eq!`（`tests/suite/scenarios.rs:50-77`）。

注意：该 runner 明确不检查 exit status（`tests/suite/scenarios.rs:42-44`），只检查最终文件系统状态。这正是 `expected/` 目录存在的核心意义。

### 5) 同语义代码测试（补充 stderr/退出码）

`tests/suite/tool.rs` 有对应测试：

- `test_apply_patch_cli_delete_directory_fails()` 构造目录 `dir`，执行 `Delete File: dir`，断言 `.failure()` 且 stderr 为 `Failed to delete file dir`（`tests/suite/tool.rs:196-205`）。

即：fixture 场景负责“最终态不变”，tool 测试负责“失败信号与错误文案”。

### 6) core 集成链路中的差异（验证阶段提前失败）

在 core 集成里，`apply_patch` 先走 verified 解析：

1. handler 调用 `maybe_parse_apply_patch_verified`（`core/src/tools/handlers/apply_patch.rs:170-175`）。
2. `invocation.rs` 在 `Hunk::DeleteFile` 分支会先 `read_to_string(path)` 以构建变更对象；目录路径在这里即失败（`apply-patch/src/invocation.rs:170-183`）。
3. handler 返回 `apply_patch verification failed: ...`（`core/src/tools/handlers/apply_patch.rs:241-244`）。

所以 core 路径常在“预检阶段”失败，而不是到 `remove_file` 才失败。对应测试为 `core/tests/suite/apply_patch_cli.rs:536-554`。

### 7) 关键命令

场景验证常用命令：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_delete_directory_fails`
3. `cargo test -p codex-core --test suite apply_patch_cli_delete_directory_reports_verification_error`

## 关键代码路径与文件引用

### A. 研究对象（目标目录与场景资产）

1. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt`
4. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/current_folder_research.md`

### B. 直接调用方（消费 `expected/`）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs`
2. `codex-rs/apply-patch/tests/suite/mod.rs`
3. `codex-rs/apply-patch/tests/all.rs`

### C. 被调用方（解析/执行）

1. `codex-rs/apply-patch/src/parser.rs`（Delete hunk 解析）
2. `codex-rs/apply-patch/src/lib.rs`（`apply_patch`、`apply_hunks_to_files`、错误输出）
3. `codex-rs/apply-patch/src/standalone_executable.rs`（CLI 参数与退出码）
4. `codex-rs/apply-patch/src/main.rs`

### D. 上游集成与并行验证

1. `codex-rs/apply-patch/src/invocation.rs`（verified 解析与 Delete 预读）
2. `codex-rs/core/src/tools/handlers/apply_patch.rs`（verification failed 包装）
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs`（构造 `codex --codex-run-as-apply-patch`）
4. `codex-rs/arg0/src/lib.rs`（`--codex-run-as-apply-patch` 分发）
5. `codex-rs/core/tests/suite/apply_patch_cli.rs`（集成失败路径测试）
6. `codex-rs/apply-patch/tests/suite/tool.rs`（CLI 失败路径测试）

### E. 配置、构建、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml`
2. `codex-rs/apply-patch/BUILD.bazel`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md`
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md`
5. `Docs/researches/blueprint_checklist.md`
6. `.ops/generate_daily_research_todo.sh`

## 依赖与外部交互

### 1) 依赖

与该目录相关的执行链使用：

1. `anyhow` / `thiserror`：错误封装与上下文。
2. `tree-sitter` / `tree-sitter-bash`：shell/heredoc `apply_patch` 调用解析（verified 入口）。
3. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`：测试执行、临时目录、快照断言、二进制定位。

### 2) 外部交互

1. 文件系统：读写 patch、复制目录、`remove_file` 删除尝试、递归快照。
2. 子进程：fixture runner 与 tool tests 均通过 `cargo_bin("apply_patch")` 启动可执行程序。
3. 标准流：成功摘要走 stdout，失败信息走 stderr。
4. 进程分发：在 core runtime 下通过 `codex --codex-run-as-apply-patch <patch>` 自调用进入 apply_patch 逻辑。

### 3) 协议交互

1. 线协议操作为 `*** Delete File: <path>`。
2. 协议本身不带“路径类型字段”，目录/文件合法性由执行层或 verified 逻辑决定。

## 风险、边界与改进建议

### 风险

1. 不同入口错误文本不一致：
   - 纯 CLI：`Failed to delete file dir`；
   - core 入口：`apply_patch verification failed: Failed to read ...`。
2. fixture runner 不断言退出码与 stderr，负向语义主要靠额外测试补齐。
3. 当前删除流程是逐 hunk 执行，仍存在“前序 hunk 成功、后续失败”导致部分生效的非事务行为风险（由场景 `015_failure_after_partial_success_leaves_changes` 可见总体策略）。

### 边界

1. 本目录仅覆盖“目标是目录”边界，不覆盖权限拒绝、符号链接目录、路径带尾斜杠等平台差异。
2. 该目录本身不承载行为逻辑，仅是状态快照，必须依赖 runner 和实现代码共同保证语义。

### 改进建议

1. 在 `apply_patch_tool_instructions.md` 补充“`Delete File` 仅删除文件，不支持目录”说明，减少调用方误用。
2. 为 scenarios 机制引入可选的 `exit_code`/`stderr` 断言文件，增强负向场景可观测性。
3. 增加细分场景：
   - `delete_symlink_to_directory`；
   - `delete_directory_with_trailing_slash`；
   - `delete_file_permission_denied`。
4. 评估在 verified 阶段统一错误类型与文案，减少 CLI 与 core 行为差异对上层处理逻辑的影响。
