# DIR `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir` 研究文档

- 研究对象：`/home/sansha/Github/codex/codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-apply-patch`
- 关联场景：`012_delete_directory_fails`

## 场景与职责

该目录是场景 `012_delete_directory_fails` 的最小 expected 子树，内容只有 `foo.txt`，文本为 `stable`（`codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`）。

在场景协议里（`input/ + patch.txt + expected/`），该目录承担的职责是“失败后状态真值（oracle）”的叶子节点：

1. `patch.txt` 发起 `*** Delete File: dir`（`.../patch.txt:1-3`）。
2. `input/dir/foo.txt` 让 `dir` 明确是目录而非文件（`.../input/dir/foo.txt:1`）。
3. `expected/dir/foo.txt` 要求失败后目录和文件均保持不变。

因此，这个目录本身不是业务逻辑实现，而是回归测试断言中的“目录仍存在且内容未变”的证据载体。

## 功能点目的

围绕该目录承载的功能点目的有 4 个：

1. 固化 `Delete File` 的语义边界：只删文件，不删目录。
2. 防止实现被误放宽为目录删除（例如误用 `remove_dir`/`remove_dir_all`）。
3. 保证失败路径无副作用：当目标类型错误时，文件树必须保持输入态。
4. 与相邻场景形成互补：`007_rejects_missing_file_delete` 覆盖“目标不存在”，本场景覆盖“目标存在但类型是目录”。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 协议与场景数据

- 场景协议由 `scenarios/README.md` 定义，每个场景包含 `input/`、`patch.txt`、`expected/`（`codex-rs/apply-patch/tests/fixtures/scenarios/README.md:5-17`）。
- 本场景 patch：

```patch
*** Begin Patch
*** Delete File: dir
*** End Patch
```

### 2) 调用方：fixture runner 如何消费该目录

`tests/suite/scenarios.rs` 会遍历 `scenarios/*` 并回放：

1. 把 `input/` 复制到 `tempdir`（`codex-rs/apply-patch/tests/suite/scenarios.rs:33-37`）。
2. 调用 `apply_patch <patch>`（`.../scenarios.rs:45-48`）。
3. 将临时目录和 `expected/` 都快照成 `BTreeMap<PathBuf, Entry>` 再 `assert_eq!`（`.../scenarios.rs:50-77`）。

关键数据结构：

- `Entry::Dir` / `Entry::File(Vec<u8>)`（`.../scenarios.rs:65-69`）。
- 由于 `expected/dir/foo.txt` 存在，比较时会要求实际结果同时包含目录 `dir` 与同字节文件 `foo.txt`。

注意：runner 明确“不检查退出码”，只检查最终文件树状态（`.../scenarios.rs:42-44`）。这也是该目录存在价值的核心。

### 3) 被调用方：apply-patch 失败链路

- 解析阶段：`parse_one_hunk` 将 `*** Delete File: dir` 解析为 `Hunk::DeleteFile { path }`（`codex-rs/apply-patch/src/parser.rs:248-278`）。
- 执行阶段：`apply_hunks_to_files` 在 `DeleteFile` 分支调用 `std::fs::remove_file(path)`（`codex-rs/apply-patch/src/lib.rs:301-304`）。
- 当目标是目录时，`remove_file` 返回 I/O 错误，错误被包装为 `Failed to delete file dir` 并写入 stderr（`.../lib.rs:253-256`）。

该失败会让实际目录保持不变，进而与 `expected/dir/foo.txt` 对齐。

### 4) 并行验证测试与命令

- CLI 侧显式测试：`test_apply_patch_cli_delete_directory_fails` 断言 `.failure()` 且 stderr 为 `Failed to delete file dir`（`codex-rs/apply-patch/tests/suite/tool.rs:196-205`）。
- Core 集成侧：`maybe_parse_apply_patch_verified` 会先读取删除目标内容，目录路径在此阶段报 `Failed to read ...`（`codex-rs/apply-patch/src/invocation.rs:170-179`），上层包装为 `apply_patch verification failed`（`codex-rs/core/src/tools/handlers/apply_patch.rs:241-244`；测试见 `codex-rs/core/tests/suite/apply_patch_cli.rs:536-554`）。

常用验证命令：

1. `cargo test -p codex-apply-patch --test all test_apply_patch_scenarios`
2. `cargo test -p codex-apply-patch --test all test_apply_patch_cli_delete_directory_fails`
3. `cargo test -p codex-core --test suite apply_patch_cli_delete_directory_reports_verification_error`

## 关键代码路径与文件引用

### 目标对象与同场景资产

1. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/expected/dir/foo.txt:1`
2. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/input/dir/foo.txt:1`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/012_delete_directory_fails/patch.txt:1-3`

### 直接调用方（消费 expected 目录）

1. `codex-rs/apply-patch/tests/suite/scenarios.rs:11-63`
2. `codex-rs/apply-patch/tests/suite/scenarios.rs:65-126`

### 被调用方（解析与执行）

1. `codex-rs/apply-patch/src/parser.rs:31-39`
2. `codex-rs/apply-patch/src/parser.rs:248-278`
3. `codex-rs/apply-patch/src/lib.rs:183-213`
4. `codex-rs/apply-patch/src/lib.rs:279-339`
5. `codex-rs/apply-patch/src/standalone_executable.rs:11-58`

### 上下游与集成路径

1. `codex-rs/apply-patch/src/invocation.rs:132-217`
2. `codex-rs/core/src/tools/handlers/apply_patch.rs:170-244`
3. `codex-rs/core/src/tools/runtimes/apply_patch.rs:69-102`
4. `codex-rs/arg0/src/lib.rs:85-107`
5. `codex-rs/apply-patch/tests/suite/tool.rs:196-205`
6. `codex-rs/core/tests/suite/apply_patch_cli.rs:536-554`

### 配置、构建、文档、脚本

1. `codex-rs/apply-patch/Cargo.toml:1-30`
2. `codex-rs/apply-patch/BUILD.bazel:1-10`
3. `codex-rs/apply-patch/tests/fixtures/scenarios/README.md:1-17`
4. `codex-rs/apply-patch/apply_patch_tool_instructions.md:14-17`
5. `.ops/generate_daily_research_todo.sh:1-42`
6. `Docs/researches/blueprint_checklist.md:119`

## 依赖与外部交互

### 依赖

与该目录断言链路直接相关的依赖包括：

1. `assert_cmd` / `tempfile` / `pretty_assertions` / `codex-utils-cargo-bin`（测试执行、临时目录、断言和二进制定位；`codex-rs/apply-patch/Cargo.toml:25-30`）。
2. `anyhow` / `thiserror`（I/O 错误上下文与传播；`.../Cargo.toml:18-23`，`.../src/lib.rs`）。
3. `tree-sitter` / `tree-sitter-bash`（core 验证阶段识别 shell 形式 `apply_patch` 调用；`.../Cargo.toml:22-23`，`.../src/invocation.rs`）。

### 外部交互

1. 文件系统：复制 `input/`、读取 `patch.txt`、删除尝试 `remove_file`、递归快照比较。
2. 子进程：scenarios runner 与 tool tests 都通过 `cargo_bin("apply_patch")` 启动命令。
3. 标准流：失败信息输出到 stderr，成功摘要输出到 stdout。
4. 进程分发：core runtime 使用 `codex --codex-run-as-apply-patch <patch>` 自调用进入执行器（`codex-rs/core/src/tools/runtimes/apply_patch.rs:90-93`，`codex-rs/arg0/src/lib.rs:90-107`）。

## 风险、边界与改进建议

### 风险

1. 入口差异：纯 CLI 与 core 验证路径的错误文本不同（`Failed to delete file ...` vs `apply_patch verification failed: Failed to read ...`），可能增加上层处理复杂度。
2. scenarios 框架不校验退出码/stderr，仅靠目录快照，无法单独捕获错误文案回归。
3. 当前目录只覆盖“目标是目录”的边界，不覆盖符号链接目录、权限异常、尾斜杠路径等平台差异。

### 边界

1. 该目录仅是 expected 快照，不携带执行逻辑；必须结合 `scenarios.rs` 与 `lib.rs` 才能形成完整语义。
2. 场景断言的是“最终态不变”，不是“错误原因文本”。错误文本由 `tool.rs` / core 测试补充。

### 改进建议

1. 在 scenarios 机制中增加可选 `exit_code`/`stderr_contains` 断言文件，让负向场景一处同时校验状态与结果。
2. 在 `apply_patch_tool_instructions.md` 补充一句“`Delete File` 不支持目录路径”，降低调用端误用概率。
3. 增加细分场景：
   - `delete_symlink_to_directory_fails`
   - `delete_directory_with_trailing_slash_fails`
   - `delete_file_permission_denied`
4. 评估统一 CLI 与 core 验证层的错误分类与文案，减少上游兼容分支。
